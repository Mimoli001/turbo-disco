#!/usr/bin/env python3
"""
cf_tunnel.py - ephemeral Cloudflare Tunnel helper for the FreeVPS workflows.

Every run creates its own Cloudflare Tunnel on your domain and publishes two
hostnames: native RDP plus a browser desktop. It also deletes tunnels left
over from runs that ended more than 7 hours ago. Nothing but the tunnel and
DNS records is involved - no third-party tunnel service, and no Cloudflare
Access app in front of the machine: the VM's own login password protects it.

Usage:
  python3 cf_tunnel.py setup rdp web

Environment:
  CF_API_TOKEN    (required) API token with these permissions:
                    Account -> Cloudflare Tunnel: Edit
                    Zone     -> DNS: Edit
                    Zone     -> Zone: Read
  CF_DOMAIN       your domain, e.g. "example.com" (a subdomain of it also
                  works - it only decides WHICH of your zones is used)
  CF_RDP_HOST / CF_WEB_HOST
                  optional per-service override: either a bare label
                  ("mywin" -> mywin.<zone>) or a full hostname one level
                  under the zone ("mywin.example.com")
  CF_ACCOUNT_ID   optional; auto-discovered from CF_DOMAIN's zone when empty

Hostnames sit exactly ONE label above the zone, because that is all
Cloudflare's universal certificate covers on the free plan - a deeper name
has no certificate and the TLS handshake fails.
"""
import datetime
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.cloudflare.com/client/v4"
TUNNEL_PREFIX = "freevps-"

# name -> (cloudflared origin service, hostname env var, local client port the
#          connect hint tells you to forward to)
#
# RDP and VNC are published as plain tcp:// rather than rdp:// / vnc://: the
# rdp:// origin type is refused by the edge on port 443 ("websocket: bad
# handshake"), while tcp:// carries the identical bytes.  Measured on a live
# account - tcp:// and vnc:// both pass traffic, rdp:// does not.
SERVICES = {
    "rdp": ("tcp://localhost:3389", "CF_RDP_HOST", 3389),
    # browser desktop (noVNC served over plain http on the runner; the edge
    # terminates TLS, so users always see https).  A raw RDP client cannot
    # talk to a Cloudflare hostname without cloudflared on the client, which
    # is why this second, install-free path exists alongside native RDP.
    "web": ("http://localhost:6080", "CF_WEB_HOST", 6080),
}

# A GitHub-hosted job is killed after 6 hours, so any tunnel older than that
# definitely belongs to a finished run.  Younger ones may belong to a workflow
# that is still running - deleting it would break an active Windows session.
PRUNE_AFTER = datetime.timedelta(hours=7)


def items(payload):
    """The array of a Cloudflare list endpoint.

    Cloudflare API v4 puts it under "result" (with "result_info" holding the
    pagination); reading "data" instead silently yields nothing, which is why
    every lookup used to come back empty.
    """
    if isinstance(payload, dict):
        for key in ("result", "data"):
            value = payload.get(key)
            if isinstance(value, list):
                return value
    return []


def env(name, required=False):
    value = os.environ.get(name, "").strip()
    if required and not value:
        sys.exit(f"cf_tunnel: environment variable {name} is required")
    return value


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + env("CF_API_TOKEN", True),
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as exc:
        try:
            payload = json.loads(exc.read() or b"{}")
        except Exception:
            payload = {}
        return exc.code, payload
    except urllib.error.URLError as exc:
        sys.exit(f"cf_tunnel: cannot reach the Cloudflare API: {exc}")


def account_id(zone=None):
    """The Cloudflare account to work in.

    CF_ACCOUNT_ID is optional: when it is empty we use the account that owns
    the zone of CF_DOMAIN, so a token spanning several accounts still picks
    the right one.
    """
    explicit = env("CF_ACCOUNT_ID")
    if explicit:
        return explicit
    if zone and zone.get("account", {}).get("id"):
        return zone["account"]["id"]
    _, payload = api("GET", "/accounts?per_page=50")
    accounts = items(payload)
    if not accounts:
        sys.exit(
            "cf_tunnel: no Cloudflare account visible to this token "
            "(grant Account permissions, or set CF_ACCOUNT_ID explicitly)"
        )
    return accounts[0]["id"]


def find_zone(hostname):
    """Find the Cloudflare zone (domain) that owns this hostname."""
    _, payload = api("GET", "/zones?per_page=50&status=active")
    zones = sorted(
        items(payload), key=lambda z: len(z["name"]), reverse=True
    )
    for zone in zones:
        if hostname == zone["name"] or hostname.endswith("." + zone["name"]):
            return zone
    seen = ", ".join(z["name"] for z in zones) or "(none)"
    sys.exit(
        f"cf_tunnel: no Cloudflare zone on this account contains {hostname}. "
        f"Zones visible to this token: {seen}. "
        "Set CF_DOMAIN to a domain whose DNS is hosted on this account."
    )


def resolve_route(name):
    """The (hostname, zone) pair to publish for one machine.

    The hostname always ends up exactly one label above the zone: that is all
    Cloudflare's universal certificate covers on the free plan, and a deeper
    name therefore has no certificate and cannot complete a TLS handshake.
    """
    _, host_env, _ = SERVICES[name]
    custom = env(host_env)
    base = env("CF_DOMAIN")

    if custom and "." in custom:
        anchor = custom  # a full hostname - the zone is derived from it
    elif base:
        anchor = base
    else:
        sys.exit(
            "cf_tunnel: set CF_DOMAIN (your domain), or set "
            f"{host_env} to a full hostname"
        )

    zone = find_zone(anchor)
    zone_name = zone["name"]

    if custom and "." in custom:
        host = custom
    elif custom:
        host = f"{custom}.{zone_name}"
    else:
        host = f"{name}.{zone_name}"
        if base.lower() != zone_name.lower():
            # stderr, not stdout: callers capture the resolved hostname from
            # stdout and this note must not become part of it
            print(
                f"cf_tunnel: note: CF_DOMAIN={base} is a subdomain of "
                f"{zone_name}; using {host} because a published name must sit "
                f"directly under the zone (its certificate only covers "
                f"{zone_name} and *.{zone_name})",
                file=sys.stderr,
            )

    depth = len(host.split(".")) - len(zone_name.split("."))
    if depth != 1:
        sys.exit(
            f"cf_tunnel: {host} sits {depth} labels above {zone_name}, but "
            "Cloudflare's universal certificate only covers the zone itself "
            f"and one level below it (*.{zone_name}). Use a name like "
            f"<something>.{zone_name}, or add your own lower-level "
            "certificate to the zone."
        )
    return host, zone


def parse_time(value):
    if not value:
        return None
    try:
        return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def prune_old_tunnels(account, current):
    now = datetime.datetime.now(datetime.timezone.utc)
    _, payload = api(
        "GET", f"/accounts/{account}/cfd_tunnel?is_deleted=false&per_page=100"
    )
    for tunnel in items(payload):
        name = tunnel.get("name", "")
        if not name.startswith(TUNNEL_PREFIX) or name == current:
            continue
        created = parse_time(tunnel.get("created_at"))
        if created is None or now - created <= PRUNE_AFTER:
            continue
        api("DELETE", f"/accounts/{account}/cfd_tunnel/{tunnel['id']}")
        print(f"cf_tunnel: removed stale tunnel {name}")


def create_tunnel(account, name):
    status, payload = api(
        "POST",
        f"/accounts/{account}/cfd_tunnel",
        {"name": name, "config_src": "cloudflare"},
    )
    if status in (200, 201):
        result = payload.get("result") or {}
        return result["id"], result["token"]
    if status == 409:
        # leftover with the same name: replace it
        _, listing = api(
            "GET", f"/accounts/{account}/cfd_tunnel?is_deleted=false&per_page=100"
        )
        for tunnel in items(listing):
            if tunnel.get("name") == name:
                api("DELETE", f"/accounts/{account}/cfd_tunnel/{tunnel['id']}")
        return create_tunnel(account, name)
    sys.exit(f"cf_tunnel: tunnel creation failed: {payload}")


def configure_ingress(account, tunnel_id, routes):
    ingress = [
        {"hostname": host, "service": service} for host, service in routes
    ]
    ingress.append({"service": "http_status:404"})
    status, payload = api(
        "PUT",
        f"/accounts/{account}/cfd_tunnel/{tunnel_id}/configurations",
        {"config": {"ingress": ingress}},
    )
    if status != 200:
        sys.exit(f"cf_tunnel: could not configure tunnel routing: {payload}")


def ensure_dns(zone, hostname, tunnel_id):
    record = {
        "type": "CNAME",
        "name": hostname,
        "content": f"{tunnel_id}.cfargotunnel.com",
        "proxied": True,
        "ttl": 1,
    }
    _, payload = api(
        "GET", f"/zones/{zone}/dns_records?type=CNAME&name={hostname}"
    )
    existing = (items(payload) or [None])[0]
    if existing:
        status, answer = api(
            "PUT", f"/zones/{zone}/dns_records/{existing['id']}", record
        )
    else:
        status, answer = api("POST", f"/zones/{zone}/dns_records", record)
    if status not in (200, 201):
        sys.exit(f"cf_tunnel: could not create DNS record {hostname}: {answer}")


def export_env(values):
    target = os.environ.get("GITHUB_ENV")
    if target:
        with open(target, "a") as handle:
            for key, value in values.items():
                handle.write(f"{key}={value}\n")
    # GITHUB_ENV only becomes visible in *later* workflow steps, but the calling
    # shell script needs these values in the same step - so also write a file it
    # can source.
    try:
        with open("/tmp/cf_tunnel.env", "w") as handle:
            for key, value in values.items():
                handle.write(f"{key}={value}\n")
    except OSError:
        pass
    for key, value in values.items():
        print(f"{key}={value}")


def connect_instructions(name, hostname, port):
    if name == "web":
        return [
            f"  open https://{hostname}/vnc.html in any browser (nothing to install)",
            "  enter the VNC password shown below when asked",
        ]
    return [
        f"  cloudflared access tcp --hostname {hostname} --url localhost:{port}",
        f"  then point your client at localhost:{port}",
    ]


def main_setup(selected):
    for name in selected:
        if name not in SERVICES:
            sys.exit(
                f"cf_tunnel: unknown service {name!r} (use: {', '.join(SERVICES)})"
            )
    routes = [(name,) + resolve_route(name) for name in selected]
    account = account_id(routes[0][2])
    run_name = TUNNEL_PREFIX + os.environ.get("GITHUB_RUN_ID", "local")

    prune_old_tunnels(account, run_name)
    tunnel_id, token = create_tunnel(account, run_name)
    configure_ingress(
        account, tunnel_id, [(host, SERVICES[name][0]) for name, host, _ in routes]
    )

    exports = {"CF_TUNNEL_TOKEN": token}
    print(f"cf_tunnel: tunnel {run_name} created ({tunnel_id})")
    for name, host, zone in routes:
        ensure_dns(zone["id"], host, tunnel_id)
        exports[f"CF_{name.upper()}_HOSTNAME"] = host
        print(f"cf_tunnel: {host} -> {SERVICES[name][0]} (DNS record ready)")

    export_env(exports)
    print("==========================================")
    print("Cloudflare tunnel ready. On your PC install cloudflared, then:")
    for name, host, _ in routes:
        for line in connect_instructions(name, host, SERVICES[name][2]):
            print(line)
    print("==========================================")


def main_cleanup():
    account = account_id()
    prune_old_tunnels(account, current="__none__")
    print("cf_tunnel: cleanup done")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "setup":
        if len(sys.argv) < 3:
            sys.exit(
                "cf_tunnel: setup needs at least one of: ssh, desktop, rdp, web, vnc"
            )
        main_setup(sys.argv[2:])
    elif sys.argv[1] == "cleanup":
        main_cleanup()
    else:
        sys.exit(f"cf_tunnel: unknown command {sys.argv[1]!r}")


if __name__ == "__main__":
    main()
