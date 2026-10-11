# AGENTS.md — notes for future AI work on this repo

## What this repo is
- A `FreeVPS` fork (`Mimoli001/turbo-disco`): disposable VMs via GitHub Actions,
  exposed through **ephemeral per-run Cloudflare Tunnels** on the user's own
  domain. ngrok/bore are gone; Google Remote Desktop was replaced by
  **TightVNC over the same cloudflared tunnel**.
- **Never open a PR to upstream `cybershadowvps/FreeVPS`.** Push only to
  `Mimoli001/turbo-disco`.
- Docs are English (`README.md`) + Persian (`supports/README-fa.md`).
  Chinese text was removed; do not reintroduce it. No personal credits.
- Workflows are `workflow_dispatch`-only (no `push:` triggers). Keep-alive is
  6h (`sleep 6h` / `Start-Sleep -Seconds 21600`).

## Secrets / env conventions
- One `PASSWORD` secret feeds every machine (fallback chain: `PASSWORD` →
  legacy per-OS secret → random printed in the log). VNC uses the first
  8 chars (printed separately).
- `MAC_REALNAME`, `LINUX_USERNAME`, `LINUX_MACHINE_NAME` auto-default when
  unset. `CF_ACCOUNT_ID` is optional — it is derived from `CF_DOMAIN`'s zone.
- Token needs only: **Cloudflare Tunnel:Edit, DNS:Edit, Zone:Read**.
  No Access permissions, no identity provider, no service token.

## Cloudflare facts (all verified live, do not regress)
- API lists live under `result`, not `data`. `/user/tokens/verify` 401s for
  account-scoped tokens — red herring, ignore it.
- **Cloudflare Access is intentionally absent.** `tcp://` and `ssh://`
  origins pass real data with no Access app; every Access endpoint returns
  403 `access.api.error.not_enabled` and it cannot be enabled via API.
- **Published names must sit exactly ONE label above the zone.** The free
  universal cert covers only `zone` and `*.zone`; deeper names fail the TLS
  handshake. `cf_tunnel.py::resolve_route()` enforces this: a subdomain
  `CF_DOMAIN` only selects the zone and is flattened to `<kind>.<zone>`
  (note goes to **stderr**, never stdout — callers capture stdout).
  Hostnames: `ssh|desktop|rdp|vnc.<zone>`.
- **RDP must be published as `tcp://localhost:3389`, not `rdp://`.**
  The edge refuses `rdp://` on 443 (`websocket: bad handshake`);
  `tcp://` carries identical bytes. `vnc://` and `ssh://` work as-is.
- Tunnel pruning (`prune_old_tunnels`) deletes only `freevps-*` tunnels older
  than 7h (`PRUNE_AFTER`) so concurrent runs never delete each other.

## Windows gotcha (critical)
- A `cloudflared.exe` started with `Start-Process` **in its own step is dead
  by the next step** (it registers, prints "Tunnel is up", then vanishes).
  Tunnel start + registration wait + connection info + keep-alive **must live
  in ONE step** in `windows.yml`. Linux/macOS are unaffected (cloudflared
  runs inside the long-lived setup script step).

## Script fixes baked in (do not revert)
- `linux-desktop.sh`: `vncpasswd` answers must be `password, verify, no`
  (old order fed `no` as the password). VNC is display `:1` → port 5901.
- `linux-ssh.sh` / `linux-desktop.sh`: `useradd -m -N` (the runner already
  has an `admin` group) and `sudo` on the `/etc/passwd` sed.
- RDP probe payload must be exactly **19 bytes**
  (`030000130ee000000000000100080003000000`, TPKT len `0x13`, LI `0x0e`),
  and a Connection Confirm carries code **`0xd0`** at index 5 (not `0xe0`).
  A malformed 18-byte request makes the RDP server wait silently → timeout.

## Testing lessons
- `GITHUB_TOKEN` (ghu_) can push and read runs/logs but **cannot dispatch,
  cancel, or manage secrets (403)**. For live tests, temporarily add `push:`
  triggers, verify, then **revert them** before the final push.
- Readiness via `curl https://<host>/` is unreliable for non-HTTP origins
  (the edge answers 1033/502/200 interchangeably); assert at the protocol
  level instead (SSH login, RFB banner, X.224 Confirm with 5s socket
  timeouts — PowerShell `.Read()` has no timeout by default and hangs).
- Repo is private: **macOS runs cost 10x minutes**; it is excluded from
  routine testing by owner decision.
- `/tmp/opencode` is wiped on restart; `~/.local/bin/actionlint` (v1.7.7)
  persists. Validate with: `actionlint .github/workflows/*.yml`,
  `bash -n`, `python3 -m py_compile`.

## Runner labels (pinned 2026-10, see actions/runner-images)
- Linux: `ubuntu-24.04` (== current `ubuntu-latest`; pinned so the gradual
  `-latest` migration to 26.04 cannot silently change the OS).
- Windows: `windows-2025-vs2026` (Server 2025 + VS2026). Same OS base as the
  tested `windows-latest`, but that exact image variant was not live-tested.
  Note: actionlint v1.7.7 flags this label as unknown — its built-in label
  list is stale (it still lists retired `windows-2019`/`ubuntu-20.04`);
  the actions/runner-images table confirms the label is valid.
- macOS intentionally left on `macos-latest`.
