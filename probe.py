#!/usr/bin/env python3
"""Temporary probe v2: publish three hostnames with different origin types and
no Access app, so we can tell whether the refusal is specific to TCP/SSH or
affects the tunnel as a whole."""
import os
import importlib.util

spec = importlib.util.spec_from_file_location("cf", "cf_tunnel.py")
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)

domain = cf.env("CF_DOMAIN", True)
# (label, hostname, cloudflared origin service)
routes = [
    ("http", f"probehttp.{domain}", "http://localhost:8080"),
    ("tcp", f"probetcp.{domain}", "tcp://localhost:22"),
    ("ssh", f"probessh.{domain}", "ssh://localhost:22"),
]

zones = {host: cf.find_zone(host) for _, host, _ in routes}
account = cf.account_id(zones[routes[0][1]])
run_name = "freevps-" + os.environ.get("GITHUB_RUN_ID", "local")

tunnel_id, token = cf.create_tunnel(account, run_name)
cf.configure_ingress(account, tunnel_id, routes)

exports = {"CF_TUNNEL_TOKEN": token}
for kind, host, service in routes:
    cf.ensure_dns(zones[host]["id"], host, tunnel_id)
    exports[f"PROBE_{kind.upper()}"] = host
    print(f"[probe2] {host} -> {service}  (zone {zones[host]['name']})")

cf.export_env(exports)
print(f"[probe2] tunnel {tunnel_id} ready, no Access app was created")
