<div align="center">

# Persistent Windows on GitHub Actions

**A browser-accessible Windows Server desktop with encrypted checkpoints, automatic restore, and automatic continuation before the six-hour runner limit.**

[English](README.md) · [فارسی](supports/README-fa.md)

![Windows workflow](https://github.com/Mimoli001/turbo-disco/actions/workflows/windows.yml/badge.svg)

</div>

## What you get

- Windows Server 2025 on the pinned `windows-2025-vs2026` runner.
- Browser desktop through noVNC, plus native Remote Desktop through `cloudflared`.
- A consistent copy of the complete `runneradmin` user profile, made through the Volume Shadow Copy Service (VSS) so open files can be captured.
- User registry settings, installed-application inventories, and Winget, Chocolatey, user-pip, and global-npm package manifests.
- AES-256 encrypted checkpoints in the private `windows-state` GitHub Release. Files are split into **1,900 MiB** assets, below GitHub's 2 GiB per-asset limit.
- SHA-256 corruption checks plus HMAC-SHA256 authentication, three complete checkpoints, and fallback to an older checkpoint when the newest one is incomplete or damaged.
- Automatic checkpoint every 15 minutes when the profile changes, a final checkpoint after 320 minutes, and an optional fresh restored run.
- OpenBot is restored with the profile, registered for user logon, and started inside the long-lived session step. A separate portable AES-256-GCM copy of its account session is kept inside the encrypted checkpoint and rebound to the new Windows user's DPAPI key after restore, without modifying OpenBot or its ASAR integrity protection.

> **Scope:** this preserves user data and restorable application state, not a bare-metal image of Windows or the contents of RAM. GitHub's base runner image is always supplied by GitHub. Some logins protected by Windows DPAPI or by the service itself can require reauthentication on a new machine. Regenerable caches and machine-specific App Execution Aliases are excluded.

## Quick start

1. Add the required secrets listed below.
2. Open **Actions → Windows Virtual Machine → Run workflow**.
3. Keep `chain=true`, or set it to false for one session only.
4. Wait for the tunnel checks and open `https://web.<your-zone>/vnc.html`.
5. Enter the VNC password shown in the job log. Native RDP instructions are printed there too.

The first run initializes an empty state. Later runs restore the newest valid checkpoint before enabling the desktop.

## Required secrets

| Secret | Purpose |
| --- | --- |
| `CF_API_TOKEN` | Cloudflare token with **Cloudflare Tunnel:Edit**, **DNS:Edit**, and **Zone:Read** |
| `CF_DOMAIN` | Domain or subdomain used to find your Cloudflare zone |
| `PASSWORD` | Windows account password; the first 8 characters are also the VNC password |
| `STATE_PASSPHRASE` | Independent, long random passphrase used to encrypt every checkpoint |
| `GH_PAT` | GitHub token with repository **Contents: Read and write** and **Actions: Read and write**, used for release uploads and the next workflow dispatch |

Optional secrets: `CF_ACCOUNT_ID`, `CF_RDP_HOST`, and `CF_WEB_HOST`. The default hostnames are `rdp.<zone>` and `web.<zone>`.

Keep the repository **private**. Checkpoints deliberately contain browser profiles, application data, and potentially reusable sign-in tokens. Losing or changing `STATE_PASSPHRASE` makes existing checkpoints undecryptable; keep a separate recovery copy in a password manager.

## Checkpoints and automatic continuation

| Setting | Default | Allowed values |
| --- | --- | --- |
| `session_minutes` | `320` (5h20m) | 30–330 |
| `save_interval_minutes` | `15` | 5–120 |
| `chain` | `true` | true / false |

The time budget leaves room for the final multi-gigabyte upload before GitHub's hard six-hour limit. Independently of the requested session length, the hold stops by job minute 330, reserving 20 minutes for final upload and 10 minutes for cleanup. A new dispatch waits on the `windows-persistent` concurrency group until the previous run has completely finished. If the hold is interrupted, a successful fallback final checkpoint can also dispatch the successor; cancellation does not restart it.

To request a checkpoint from inside Windows:

```powershell
New-Item -ItemType File -Path "$HOME\.save-now" -Force
```

The session loop notices the file, removes it, and saves. Unchanged profiles are fingerprinted and skipped. A failed save never replaces the previous complete checkpoint; the next interval retries it. Only the three newest complete checkpoints are retained.

To inspect or validate the stored state locally on the runner:

```powershell
.github/windows/state.ps1 status
.github/windows/state.ps1 verify
```

`verify` downloads, hashes, decrypts, and extracts the newest checkpoint into scratch space **without applying it to the live profile**.

### What is restored

- Desktop, Documents, Downloads, projects, browser profiles, application data, and the rest of the user profile except regenerable caches.
- `HKCU` user registry settings.
- Missing Winget packages without upgrading already installed packages, plus Chocolatey, user-pip, and global-npm packages when their package manager is available.
- OpenBot's per-user installation and logon registration.

The restore never uses `/MIR` and never deletes files that came with the new runner. Built-in Windows databases that remain memory-mapped, such as WebCache or notification databases, are skipped with a warning instead of aborting the entire restore. Windows itself, preinstalled system files, kernel state, running processes, and RAM are not replaced. Package restoration can take longer for applications whose old versions are no longer available.

Chunking removes the **per-file** 2 GiB release-asset limit; it does not eliminate upload time, bandwidth, or GitHub service limits. The 15-minute default is intended for a multi-gigabyte Windows profile.

## Connection options

### Browser (recommended)

Open:

```text
https://web.<your-zone>/vnc.html
```

TightVNC listens only through the configured Cloudflare route. Loopback is explicitly enabled because both noVNC and the tunnel connect locally.

### Native Remote Desktop

Install `cloudflared` on your computer, then run the command printed in the job log:

```bash
cloudflared access tcp --hostname rdp.<your-zone> --url localhost:3389
```

Connect `mstsc` to `localhost:3389`. A raw RDP client cannot connect directly to the Cloudflare hostname.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Restore reports a checksum or decrypt error | The script automatically tries the next older complete checkpoint. Check that `STATE_PASSPHRASE` has not changed. |
| Save is refused | The restore step did not complete. This guard prevents a fresh runner from overwriting a good saved state. |
| An autosave fails | The previous complete checkpoint remains intact; the next interval retries. Check the job log and `GH_PAT` permissions. |
| No new run starts | Final save must succeed and `chain` must be true. Confirm that `GH_PAT` can dispatch workflows. |
| Browser desktop is unavailable | Check the VNC handshake and public noVNC HTTP checks in the long-lived session step. |
| A login needs to be repeated | Some credentials are tied to the old machine or have expired. This is expected for DPAPI-protected or server-invalidated sessions. |
| Disk space is low | Scratch archives use `D:\windows-state-work`. Only three uploaded checkpoints are retained; incomplete local scratch directories can be removed after the save process has stopped. |

## Project layout

```text
.github/workflows/windows.yml   Windows services, restore, autosave, final save, and chaining
.github/windows/state.ps1       VSS, encryption, chunking, verification, restore, and retention
.github/windows/openbot-secret-storage.ps1  Portable OpenBot account-session migration
cf_tunnel.py                    Cloudflare RDP and noVNC routes
supports/README-fa.md           Persian documentation
```

## Security notes

- Never commit `STATE_PASSPHRASE`, `GH_PAT`, Cloudflare credentials, or the local passphrase file.
- Checkpoints are encrypted before upload, but GitHub Release asset names and sizes are visible to people with repository access.
- Treat connection details and job logs as sensitive while a session is running.
- Do not run untrusted workflow code: it can read the same secrets and decrypted user profile.
- Cloudflare Access is intentionally not required. The Windows password and VNC password protect the desktop endpoints.

## License

Apache License 2.0. See [LICENSE](LICENSE).
