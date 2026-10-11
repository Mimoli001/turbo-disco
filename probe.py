#!/usr/bin/env python3
"""Temporary probe v3 - the decisive experiment.

Publish hostnames directly under the zone (one label) and one two labels deep,
across http/tcp/ssh origin types, with no Access app.  This tells us whether
the TLS failure is caused by nesting depth (Cloudflare's free universal cert
only covers `zone` and `*.zone`) and whether TCP/SSH work without Access."""
import os
import importlib.util

spec = importlib.util.spec_from_file_location("cf", "cf_tunnel.py")
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)

domain = cf.env("CF_DOMAIN", True)
zone = cf.find_zone("fp1." + domain)
zone_name = zone["name"]
print(f"[probe3] CF_DOMAIN={domain!r} zone={zone_name!r}")

routes = [
    ("fp1", f"fp1.{zone_name}", "http://localhost:8080"),   # 1 level, http
    ("fp2", f"fp2.{zone_name}", "tcp://localhost:22"),      # 1 level, tcp
    ("fp3", f"fp3.{zone_name}", "ssh://localhost:22"),      # 1 level, ssh
    ("fp4", f"deep.fp1.{zone_name}", "http://localhost:8080"),  # 2 levels, http
]

account = cf.account_id(zone)
run_name = "freevps-" + os.environ.get("GITHUB_RUN_ID", "local")
tunnel_id, token = cf.create_tunnel(account, run_name)
cf.configure_ingress(account, tunnel_id, routes)

exports = {"CF_TUNNEL_TOKEN": token}
for kind, host, service in routes:
    cf.ensure_dns(zone["id"], host, tunnel_id)
    exports[f"PROBE_{kind.upper()}"] = host
    print(f"[probe3] {host} -> {service}")

cf.export_env(exports)
print(f"[probe3] tunnel {tunnel_id} ready")
