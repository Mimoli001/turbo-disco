#!/usr/bin/env python3
"""
cf_tunnel.py - ephemeral Cloudflare Tunnel helper for the FreeVPS workflows.

Usage:
  python3 cf_tunnel.py setup <ssh|desktop|rdp|vnc> [...]

Environment:
  CF_API_TOKEN    (required) API token with these permissions:
                    Account -> Cloudflare Tunnel: Edit
                    Account -> Access: Apps and Policies: Edit
                    Zone     -> DNS: Edit
                    Zone     -> Zone: Read
  CF_DOMAIN       your domain OR a subdomain of it, e.g. "example.com" or
                  "vps.example.com". The Cloudflare zone is auto-detected.
  CF_SSH_HOST / CF_DESKTOP_HOST / CF_RDP_HOST / CF_VNC_HOST
                  optional per-machine override. Either a full hostname
                  ("ssh.vps.example.com") used as-is, or a bare subdomain
                  label ("myvps" -> ssh.myvps.<CF_DOMAIN>).
  CF_ACCOUNT_ID   optional; auto-discovered from the token when empty
"""
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.cloudflare.com/client/v4"
TUNNEL_PREFIX = "freevps-"

# name -> (Access app type, cloudflared origin service, hostname env var,
#          local client port printed in the connect hint)
SERVICES = {
    "ssh": ("ssh", "ssh://localhost:22", "CF_SSH_HOST", 2222),
    "desktop": ("tcp", "vnc://localhost:5901", "CF_DESKTOP_HOST", 5900),
    "rdp": ("tcp", "rdp://localhost:3389", "CF_RDP_HOST", 3389),
    "vnc": ("tcp", "vnc://localhost:5900", "CF_VNC_HOST", 5900),
}


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


def account_id():
    explicit = env("CF_ACCOUNT_ID")
    if explicit:
        return explicit
    _, payload = api("GET", "/accounts?per_page=50")
    accounts = payload.get("data") or []
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
        (z["name"] for z in payload.get("data") or []), key=len, reverse=True
    )
    for zone in zones:
        if hostname == zone or hostname.endswith("." + zone):
            return zone
    sys.exit(
        f"cf_tunnel: no Cloudflare zone on this account contains {hostname}. "
        "Set CF_DOMAIN (or the CF_*_HOST override) to a name whose DNS is "
        "hosted on this account."
    )


def resolve_hostname(name):
    _, _, host_env, _ = SERVICES[name]
    custom = env(host_env)
    base = env("CF_DOMAIN")
    if custom and "." in custom:
        return custom  # already a full hostname
    if custom:
        if not base:
            sys.exit(
                f"cf_tunnel: {host_env}={custom} is only a label - "
                "set CF_DOMAIN too, or give a full hostname"
            )
        return f"{name}.{custom}.{base}"
    if not base:
        sys.exit(
            f"cf_tunnel: set CF_DOMAIN (your domain or a subdomain of it), "
            f"or set {host_env} to a full hostname"
        )
    return f"{name}.{base}"


def prune_old_tunnels(account, current):
    _, payload = api(
        "GET", f"/accounts/{account}/cfd_tunnel?is_deleted=false&per_page=100"
    )
    for tunnel in payload.get("data") or []:
        name = tunnel.get("name", "")
        if name.startswith(TUNNEL_PREFIX) and name != current:
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
        _, listing = api(
            "GET", f"/accounts/{account}/cfd_tunnel?is_deleted=false&per_page=100"
        )
        for tunnel in listing.get("data") or []:
            if tunnel.get("name") == name:
                api("DELETE", f"/accounts/{account}/cfd_tunnel/{tunnel['id']}")
        return create_tunnel(account, name)
    sys.exit(f"cf_tunnel: tunnel creation failed: {payload}")


def configure_ingress(account, tunnel_id, routes):
    ingress = [
        {"hostname": host, "service": service} for _, host, service in routes
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
    _, payload = api("GET", f"/zones/{zone}/dns_records?type=CNAME&name={hostname}")
    existing = (payload.get("data") or [None])[0]
    if existing:
        status, answer = api(
            "PUT", f"/zones/{zone}/dns_records/{existing['id']}", record
        )
    else:
        status, answer = api("POST", f"/zones/{zone}/dns_records", record)
    if status not in (200, 201):
        sys.exit(f"cf_tunnel: could not create DNS record {hostname}: {answer}")


def ensure_access_app(account, hostname, app_type):
    _, payload = api("GET", f"/accounts/{account}/access/apps?domain={hostname}")
    apps = payload.get("data") or []
    if apps:
        app_id = apps[0]["id"]
    else:
        status, payload = api(
            "POST",
            f"/accounts/{account}/access/apps",
            {
                "domain": hostname,
                "type": app_type,
                "name": f"freevps {hostname}",
                "session_duration": "24h",
            },
        )
        if status not in (200, 201):
            sys.exit(
                f"cf_tunnel: could not create Access app {hostname}: {payload}"
            )
        app_id = payload["result"]["id"]
    # anyone who reaches the hostname may use it; the VM itself is
    # protected by its user password
    api(
        "POST",
        f"/accounts/{account}/access/apps/{app_id}/policies",
        {
            "decision": "allow",
            "name": "freevps-everyone",
            "include": [{"everyone": {}}],
            "precedence": 1,
        },
    )


def warn_if_no_identity_provider(account):
    status, payload = api(
        "GET", f"/accounts/{account}/access/identity_providers"
    )
    if status == 200 and not payload.get("data"):
        print(
            "::warning::No Cloudflare Access identity provider is configured. "
            "One-time setup: Zero Trust dashboard -> Settings -> Authentication "
            "-> Add provider (\"One-time PIN\" needs no third-party account). "
            "Until then, cloudflared access cannot authenticate you."
        )


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
    if name == "ssh":
        return [
            f'  ssh -o ProxyCommand="cloudflared access ssh --hostname {hostname}" USER@{hostname}',
            f"  (or run: cloudflared access ssh --hostname {hostname})",
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
    account = account_id()
    warn_if_no_identity_provider(account)
    routes = [
        (name, resolve_hostname(name), SERVICES[name][1]) for name in selected
    ]
    run_name = TUNNEL_PREFIX + os.environ.get("GITHUB_RUN_ID", "local")

    prune_old_tunnels(account, run_name)
    tunnel_id, token = create_tunnel(account, run_name)
    configure_ingress(account, tunnel_id, routes)

    exports = {"CF_TUNNEL_TOKEN": token}
    print(f"cf_tunnel: tunnel {run_name} created ({tunnel_id})")
    for name, host, service in routes:
        ensure_dns(find_zone(host), host, tunnel_id)
        ensure_access_app(account, host, SERVICES[name][0])
        exports[f"CF_{name.upper()}_HOSTNAME"] = host
        print(f"cf_tunnel: {host} -> {service} (Access app ready)")

    export_env(exports)
    print("==========================================")
    print("Cloudflare tunnel ready. On your PC install cloudflared, then:")
    for name, host, _ in routes:
        for line in connect_instructions(name, host, SERVICES[name][3]):
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
                "cf_tunnel: setup needs at least one of: ssh, desktop, rdp, vnc"
            )
        main_setup(sys.argv[2:])
    elif sys.argv[1] == "cleanup":
        main_cleanup()
    else:
        sys.exit(f"cf_tunnel: unknown command {sys.argv[1]!r}")


if __name__ == "__main__":
    main()
