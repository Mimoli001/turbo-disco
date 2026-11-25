# AGENTS.md — notes for future AI work on this repo

## What this repo is
- A Windows-only `FreeVPS` fork (`Mimoli001/turbo-disco`): a persistent Windows
  Server desktop on GitHub Actions, exposed through per-run Cloudflare Tunnels.
  Linux and macOS workflows/scripts were removed by owner decision.
- **Never open a PR to upstream `cybershadowvps/FreeVPS`.** Push only to
  `Mimoli001/turbo-disco`.
- Docs are English (`README.md`) + Persian (`supports/README-fa.md`).
  Chinese text was removed; do not reintroduce it. No personal credits.
- The only workflow is `workflow_dispatch`-only `.github/workflows/windows.yml`.
  It defaults to a 320-minute session, 15-minute checkpoint interval, and a
  restored chained run. `concurrency: windows-persistent` prevents overlap.

## Persistence architecture
- `.github/windows/state.ps1` implements `restore`, `verify`, `save`, `hold`,
  `final`, and `status`. Keep the save guard: saving is refused unless restore
  completed (or a first run was initialized) in the same runner.
- Checkpoints live in the private `windows-state` release. Assets are AES-256
  encrypted, split at 1900 MiB, and have per-chunk SHA-256 values in a
  `state-<timestamp>.done.json` manifest. Chunks upload first, manifest last.
- Retain three complete snapshots. A partial/corrupt newest snapshot must not
  hide older valid ones. Never apply an older snapshot after a newer snapshot
  has already been partially applied to the live profile.
- The source is the complete `runneradmin` user profile, plus HKCU and package
  manifests. VSS gives a consistent view of open files. Only regenerable caches
  and `AppData/Local/Microsoft/WindowsApps` are excluded; WindowsApps contains
  machine-specific app execution aliases that fail inside a shadow copy.
- **Robocopy cannot read a direct `\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopyN`
  source.** Create a temporary directory symlink to the shadow device with
  `mklink /d`, copy through that path, remove the link, then remove the shadow.
- Restore uses Robocopy without `/MIR`: never delete files supplied by the new
  runner. Built-in Windows databases (WebCache, Notifications, packaged-app
  hives, etc.) can be memory-mapped for the whole session; restore skips files
  that remain locked with a visible warning instead of failing the entire run.
  Save still requires Robocopy success. HKLM is never wholesale imported.
  Winget uses `--no-upgrade` and `--ignore-unavailable`; other package managers
  install only missing packages.
- This is user-state persistence, not a full disk/RAM image. DPAPI-protected or
  server-invalidated logins can require reauthentication. Do not promise that
  every login survives.
- Chunking solves only the 2 GiB per-asset limit, not bandwidth or upload time.
  Leave enough time before the hard 6h job cap for the final save.
- `verify` must remain non-destructive: download, verify, decrypt, and extract
  into scratch space without applying to the live profile.

## Secrets / env conventions
- `PASSWORD` feeds Windows and VNC (first 8 chars), with legacy
  `WINDOWS_USER_PASSWORD` as fallback.
- `STATE_PASSPHRASE` is independent and required. Changing or losing it makes
  old snapshots undecryptable. Never print it or commit the local passphrase.
- `GH_PAT` is required for release uploads and workflow dispatch. Previous
  testing showed the job's `GITHUB_TOKEN` could not dispatch this workflow.
- `CF_ACCOUNT_ID` is optional and derived from `CF_DOMAIN`'s zone when empty.
- Token needs only: **Cloudflare Tunnel:Edit, DNS:Edit, Zone:Read**.
  No Access permissions, identity provider, or service token.

## Cloudflare facts (verified live; do not regress)
- API lists live under `result`, not `data`. `/user/tokens/verify` 401s for
  account-scoped tokens — red herring, ignore it.
- **Cloudflare Access is intentionally absent.** The machine password is the
  login barrier; no Access app or identity provider is required.
- Published names must sit exactly ONE label above the zone. The free universal
  cert covers only `zone` and `*.zone`. `cf_tunnel.py::resolve_route()` flattens
  a subdomain `CF_DOMAIN` to `<kind>.<zone>` and writes notes to stderr.
- Windows hostnames: `rdp.<zone>` and `web.<zone>`.
- **RDP must be published as `tcp://localhost:3389`, not `rdp://`.** The edge
  refuses `rdp://` on 443; `tcp://` carries identical bytes.
- Tunnel pruning deletes only `freevps-*` tunnels older than 7h so an active run
  is not removed.

## Windows gotchas (critical)
- A `cloudflared.exe` started with `Start-Process` **in its own step is dead by
  the next step**. Tunnel start + registration wait + connection info + the
  session/save loop **must live in ONE step**. OpenBot and noVNC also start in
  this long-lived step; OpenBot additionally gets an HKCU Run registration.
- The run publishes two routes from one tunnel: RDP and noVNC. Browser path is
  TightVNC 2.8.90 + `python -m websockify --web noVNC-1.7.0 6080 localhost:5900`.
- TightVNC loopback must be enabled with `SERVER_ALLOW_LOOPBACK=1` and the
  `HKLM:\SOFTWARE\TightVNC\Server\AllowLoopback` DWORD, then restart `tvnserver`.
- `utils/novnc_proxy` is a bash script; on Windows run the websockify module.
- A raw RDP client cannot talk to a Cloudflare hostname without a local
  `cloudflared access tcp` bridge. Do not promise direct `mstsc`-to-hostname.
- RDP probe payload is exactly 19 bytes
  (`030000130ee000000000000100080003000000`), and a Connection Confirm carries
  code `0xd0` at index 5. Set 5-second socket timeouts.

## Validation
- Run PowerShell parser validation on `.github/windows/state.ps1`,
  `actionlint .github/workflows/windows.yml`, `python -m py_compile cf_tunnel.py`,
  and `git diff --check`. Remove generated `__pycache__` before committing.
- For persistence changes, test both `save` and non-destructive `verify`; check
  release asset existence and size. Do not test restore by overwriting the live
  OpenBot profile unless the owner explicitly requests that exact operation.
- Runner label is pinned to `windows-2025-vs2026` (Server 2025 + VS2026). Older
  actionlint builds can flag this valid label as unknown; check the current
  actions/runner-images table before changing it.
