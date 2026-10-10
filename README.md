<div align="center">

# Free Virtual Machine with GitHub Actions

**Run a full macOS, Windows or Ubuntu machine inside GitHub Actions and connect to it remotely — completely free on public repositories.**

[English](README.md) · [فارسی](supports/README-fa.md)

![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![Actions](https://github.com/Mimoli001/turbo-disco/actions/workflows/linux-ssh.yml/badge.svg)

</div>

> :warning: **Keeping your fork up to date:** if the workflows fail to start, fork this repository again — or sync your existing fork with the newest code. Steps are in [Updating your fork](#updating-your-fork).

---

## Table of contents

- [What you get](#what-you-get)
- [Machine specifications](#machine-specifications)
- [Quick start](#quick-start)
- [Required secrets](#required-secrets)
- [Deploy and run](#deploy-and-run) — macOS · Windows · Linux
- [Updating your fork](#updating-your-fork)
- [Limits](#limits)
- [Troubleshooting](#troubleshooting)
- [Security notes](#security-notes)
- [Tips and tricks](#tips-and-tricks)
- [License](#license)

---

## What you get

| Workflow (in the `Actions` tab) | Operating system | How you connect to it |
| --- | --- | --- |
| `MacOS Virtual Machine` | macOS on Apple silicon | VNC Viewer through an ngrok tunnel |
| `Windows Virtual Machine` | Windows Server desktop (looks like Windows 10/11) | Remote Desktop (`mstsc`) through an ngrok tunnel |
| `Ubuntu ssh Virtual Machine` | Ubuntu Server | `ssh` through an ngrok tunnel |
| `Ubuntu Desktop Virtual Machine` | Ubuntu with the XFCE desktop | Google Remote Desktop (+ SSH backup) |

Everything is provisioned by the workflows in [`.github/workflows/`](.github/workflows/) and the setup scripts next to this file. You only add a few secrets and press **Run workflow**.

---

## Machine specifications

Specs below are the standard GitHub-hosted runners used by this project in **public** repositories (free and unlimited there):

| Machine | vCPU | RAM | Free disk |
| --- | --- | --- | --- |
| Windows and Linux | 4 cores | 16 GB | 14 GB SSD **(system excluded)** |
| macOS (`macos-latest`, Apple silicon) | 3 cores (Apple M1) | 7 GB | 14 GB SSD **(system excluded)** |

> :warning: These specs apply to **public** forks. If you fork this repository as **private**, Linux/Windows runners are smaller (2-core vCPU / 8 GB RAM), consume the 2,000 free Actions minutes per month (Windows counts 2x, macOS 10x per minute), and macOS concurrency is limited to 5 jobs.

> :information_source: The Windows workflow runs on GitHub's Windows Server runner with Remote Desktop enabled, so the desktop looks similar to Windows 10/11.

---

## Quick start

1. **Fork** this repository.
2. Add the [secrets](#required-secrets) you need under `Settings` → `Secrets and variables` → `Actions` → `New repository secret`.
3. Open the **`Actions`** tab, pick a workflow on the left and press **Run workflow**.
4. Wait a few minutes, then copy the connection info printed in the job log (or read it from the ngrok dashboard).
5. Connect with VNC Viewer, Remote Desktop or `ssh` — and enjoy your machine until the job ends.

---

## Required secrets

Go to your project page → `Settings` → `Secrets and variables` → `Actions` → `New repository secret` and add:

| Secret | Used for | Notes |
| --- | --- | --- |
| `NGROK_AUTH_TOKEN` | All ngrok tunnels (SSH / RDP / VNC) | Copy your API key from <https://dashboard.ngrok.com/get-started/your-authtoken>. :warning: On the ngrok **free** plan, TCP tunnels require a **verified credit card**. |
| `MAC_REALNAME` | macOS user display name | Any name you like |
| `MAC_USER_PASSWORD` | macOS admin password | Any password you like |
| `VNC_PASSWORD` | macOS VNC login password | Any password you like |
| `WINDOWS_USER_PASSWORD` | Windows RDP password | Set as the password of the built-in administrator account |
| `LINUX_USERNAME` | Linux username | Any name you like |
| `LINUX_USER_PASSWORD` | Linux shell and `sudo` password | Any password you like |
| `LINUX_MACHINE_NAME` | Linux computer name | Any name you like |
| `CHROME_HEADLESS_CODE` | Google Remote Desktop for the Linux desktop | Copy a code from <https://remotedesktop.google.com/headless>, log in with your Google account and copy the code under `Debian Linux`. :warning: Every code works only **once** — generate a new one each time. |
| `GOOGLE_REMOTE_PIN` | Google Remote Desktop PIN | Any PIN of at least 6 digits; you need it when connecting to the Linux desktop |

---

## Deploy and run

<details>
<summary><b>macOS</b></summary>
<br>

1. Open the **`Actions`** tab and select **`MacOS Virtual Machine`**.
2. Press **`Run Workflow`**.
3. Wait a few minutes for the build and tunnel to come up.
4. Open <https://dashboard.ngrok.com/status/tunnels> and confirm one tunnel is online.
5. Copy the address **without the `tcp://` prefix**, install [VNC Viewer](https://www.realvnc.com/en/connect/download/viewer/) and paste it into the connect field.
6. Log in with username `vpsuser` and the password you stored in `VNC_PASSWORD`.
7. Enjoy!

</details>

<details>
<summary><b>Windows</b></summary>
<br>

1. Start **`Windows Virtual Machine`** from the `Actions` tab.
2. Wait for the **`Print connection info`** step in the job log — it prints your `mstsc /v:HOST:PORT` address, the username and where the password comes from. You can also check <https://dashboard.ngrok.com/status/tunnels>.
3. Open Remote Desktop Connection (`mstsc`) or Microsoft Remote Desktop and connect using that address.
4. Enjoy!

</details>

<details>
<summary><b>Linux (SSH and desktop)</b></summary>
<br>

1. Start either **`Ubuntu ssh Virtual Machine`** (server only) or **`Ubuntu Desktop Virtual Machine`** (XFCE desktop) from the `Actions` tab.
2. Copy the connection line printed at the end of the log, for example:
   ```bash
   ssh LINUX_USERNAME@HOST -p PORT
   ```
3. Run it from macOS Terminal, Windows CMD/PowerShell or any SSH client, type **`yes`** when asked to confirm the fingerprint, then enter `LINUX_USER_PASSWORD`.
4. Run **`sudo -i`** and enter the same password to get root access.
5. For the desktop version, open <https://remotedesktop.google.com/access> in a browser on another machine and join the host with `GOOGLE_REMOTE_PIN`.

</details>

> :warning: **Do not stop the workflow while you are connected.** The machine — and your remote session with it — lives only until the job finishes (the GitHub-hosted runner limit is **6 hours**), then everything is deleted.

> :warning: **Do not install system updates** (macOS, Windows or large system updates) while connected. They may reboot the machine and break your remote session.

---

## Updating your fork

<details>
<summary>Bring the newest workflows and scripts into your fork</summary>
<br>

**Option A — on GitHub:** open your fork, press **Sync fork** next to the branch name, then **Update branch**.

**Option B — from a terminal:**

```bash
git remote add upstream https://github.com/Mimoli001/turbo-disco.git   # only the first time
git fetch upstream
git merge upstream/main      # or: git rebase upstream/main
git push
```

Your fork now runs the newest workflows and scripts.

</details>

---

## Limits

| # | Limit |
| --- | --- |
| 1 | **6 hours** of execution time per job — the hard limit of GitHub-hosted runners. When it is reached the job is terminated and the machine is wiped. |
| 2 | **Don't store important or sensitive files** on a machine: everything is deleted afterwards and cannot be recovered. |
| 3 | The ngrok **free** plan allows **3** online tunnels at once, so run at most three of these systems concurrently. :warning: TCP tunnels (SSH / RDP / VNC) need **credit card verification** and are limited to 100 TCP connections/minute, 5,000 connections/month and 1 GB transfer/month (<https://ngrok.com/pricing>). |
| 4 | **Don't log into personal accounts** (Google, Microsoft, banking, …): the VNC connection is not encrypted and can be intercepted. |
| 5 | Actions on **public** repositories are free and unlimited. On a **private** fork the 2,000 free minutes per month are shared by all workflows (Linux 1x, Windows 2x, macOS 10x per minute). |
| 6 | On the GitHub Free plan at most **20** jobs run at the same time — **5** of them may be macOS jobs. |

---

## Troubleshooting

| Symptom | Likely cause — and fix |
| --- | --- |
| `ngrok tunnel did not start` | Invalid `NGROK_AUTH_TOKEN`, or TCP tunnels are not enabled on your ngrok account (free plan needs credit card verification). |
| Only one or two machines run at once | Your free ngrok plan allows 3 tunnels in total. |
| The workflow fails immediately after you fork it | Your fork is behind: [update it](#updating-your-fork). |
| The remote session drops after a while | The job ended — its keep-alive period is over, or the 6-hour limit was reached. Start the workflow again. |
| macOS jobs are queued | Only 5 macOS jobs may run in parallel on the free plan. |

---

## Security notes

- These machines are **temporary playgrounds**, not servers: assume everything on them is wiped when the job ends.
- VNC traffic through the free ngrok tunnel is **not end-to-end encrypted** — never sign in to personal or work accounts.
- Use throw-away passwords, and treat the connection details printed in the job logs as secrets while a job is running.

---

## Tips and tricks

- Remote control of **macOS** or **Windows** feels slow or laggy? Google Remote Desktop or Microsoft Remote Desktop are usually faster than raw VNC/RDP tunnels.
- **Fork the project** before running it so you can set your own usernames, computer names and display names.
- Keep your fork synced (see [Updating your fork](#updating-your-fork)) whenever the workflows stop starting.

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
