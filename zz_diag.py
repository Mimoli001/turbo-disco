#!/usr/bin/env python3
"""Temporary diagnostic: dump every DNS record and tunnel so we can see what
rdp.<zone> actually points at compared with ssh.<zone> and desktop.<zone>."""
import importlib.util
import json

spec = importlib.util.spec_from_file_location("cf", "cf_tunnel.py")
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)

domain = cf.env("CF_DOMAIN", True)
zone = cf.find_zone("ssh." + domain)
account = cf.account_id(zone)
print(f"[diag] zone={zone['name']} account={account}")

st, payload = cf.api("GET", f"/zones/{zone['id']}/dns_records?per_page=100")
print(f"[diag] list DNS http={st}")
for r in cf.items(payload):
    print(
        f"[diag]   {r.get('type'):5} {r.get('name'):24} -> "
        f"{r.get('content')} proxied={r.get('proxied')} ttl={r.get('ttl')} "
        f"created={r.get('created_on')} id={r.get('id')}"
    )

st, payload = cf.api(
    "GET", f"/accounts/{account}/cfd_tunnel?is_deleted=false&per_page=100"
)
print(f"[diag] list tunnels http={st}")
tunnels = cf.items(payload)
for t in tunnels:
    print(
        f"[diag]   {t.get('name')} id={t.get('id')} status={t.get('status')} "
        f"created={t.get('created_at')} deleted={t.get('deleted_at')}"
    )

zone_hosts = ("ssh." + zone["name"], "rdp." + zone["name"],
              "desktop." + zone["name"], "vnc." + zone["name"])
for t in tunnels:
    st, cfg = cf.api(
        "GET", f"/accounts/{account}/cfd_tunnel/{t['id']}/configurations"
    )
    ingress = ((cfg.get("result") or {}).get("config") or {}).get("ingress")
    names = [e.get("hostname", "") for e in (ingress or [])]
    if any(n in zone_hosts for n in names):
        print(
            f"[diag] ingress of {t['name']} status={t.get('status')} "
            f"http={st} {json.dumps(ingress)}"
        )

st, payload = cf.api("GET", f"/accounts/{account}/access/apps")
print(f"[diag] Access apps http={st} {json.dumps(payload.get('result'))[:400]}")
print("[diag] done")
