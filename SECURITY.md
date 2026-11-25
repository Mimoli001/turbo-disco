# Security Policy

## Supported version

Only the `main` branch of `Mimoli001/turbo-disco` receives fixes. This project is intended for a private repository and a user-owned GitHub Actions runner.

## Reporting a vulnerability

Open a private security advisory on GitHub instead of publishing credentials, checkpoint contents, tunnel addresses, or a working exploit. Do not test against accounts, runners, domains, or systems you do not own or have explicit permission to assess.

## Checkpoint data

Checkpoints contain sensitive user profiles and may contain reusable sign-in tokens. Keep `STATE_PASSPHRASE` and `GH_PAT` separate, rotate them if repository access is compromised, and remember that changing the passphrase prevents decryption of older checkpoints.
