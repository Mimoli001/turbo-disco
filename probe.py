#!/usr/bin/env python3
"""Temporary probe: can Access be enabled via the API, and can a service token
be created?  Writes /tmp/svc_token.json when it succeeds."""
import json
import importlib.util

spec = importlib.util.spec_from_file_location("cf", "cf_tunnel.py")
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)

domain = cf.env("CF_DOMAIN", True)
zone = cf.find_zone("ssh.probe." + domain)
account = cf.account_id(zone)
print(f"[probe] account={account} zone={zone['name']}")


def step(label, status, payload):
    msgs = "; ".join(e.get("message", "") for e in (payload.get("errors") or []))
    print(f"[probe] {label}: http={status} {msgs[:300]}")
    return payload.get("result")


print("[probe] --- Access organisation ---")
step("GET  /access/organizations",
     *cf.api("GET", f"/accounts/{account}/access/organizations"))
step("PUT  /access/organizations  (try to enable Access)",
     *cf.api("PUT", f"/accounts/{account}/access/organizations",
             {"name": f"freevps-{account[:8].lower()}",
              "session_duration": "24h", "ui_session_duration": "24h",
              "seat_mode": "manual", "is_ui_allowed": True,
              "allow_authenticate_via_warp": False, "auth_mode": "openid",
              "custom_pages": {}}))

print("[probe] --- Access application ---")
app = step("POST /access/apps  (ssh.probe.<domain>)",
           *cf.api("POST", f"/accounts/{account}/access/apps",
                   {"domain": f"ssh.probe.{domain}", "type": "ssh",
                    "name": "freevps probe", "session_duration": "24h"}))
if app:
    step("POST /access/apps/<id>/policies  (everyone)",
         *cf.api("POST", f"/accounts/{account}/access/apps/{app['id']}/policies",
                 {"decision": "allow", "name": "probe-everyone",
                  "include": [{"everyone": {}}], "precedence": 1}))

print("[probe] --- service token (for headless testing) ---")
tok = step("POST /access/service_tokens",
           *cf.api("POST", f"/accounts/{account}/access/service_tokens",
                   {"name": "freevps-test", "duration": "8760h"}))
if tok:
    with open("/tmp/svc_token.json", "w") as fh:
        json.dump({"id": tok.get("client_id"),
                   "secret": tok.get("client_secret")}, fh)
    print(f"[probe] service token saved, client_id={tok.get('client_id')}")

print("[probe] --- identity providers ---")
step("GET  /access/identity_providers",
     *cf.api("GET", f"/accounts/{account}/access/identity_providers"))
print("[probe] done")
