#!/bin/bash
# linux-ssh.sh - create an SSH-reachable Linux VM exposed through a Cloudflare
# Tunnel on your own domain (no ngrok / bore / other third-party service).
#
# Environment:
#   PASSWORD            login password (optional - a random one is generated
#                       when empty)
#   LINUX_USERNAME      login user  (default: admin)
#   LINUX_MACHINE_NAME  hostname    (default: ubuntu-vps)
#   CF_DOMAIN           your domain or a subdomain of it (zone auto-detected)
#   CF_SSH_HOST         optional full hostname override for this machine

set -euo pipefail

LINUX_USERNAME="${LINUX_USERNAME:-admin}"
LINUX_MACHINE_NAME="${LINUX_MACHINE_NAME:-ubuntu-vps}"
PASSWORD="${PASSWORD:-${LINUX_USER_PASSWORD:-}}"

# A single PASSWORD secret is enough; fall back to a random one so the box is
# always reachable.
if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(12)))')"
  echo "### No PASSWORD secret set - generated a random one (shown below) ###"
fi

sudo useradd -m "$LINUX_USERNAME"
sudo adduser "$LINUX_USERNAME" sudo
echo "$LINUX_USERNAME:$PASSWORD" | sudo chpasswd
sed -i 's/\/bin\/sh/\/bin\/bash/g' /etc/passwd
sudo hostname "$LINUX_MACHINE_NAME"

echo "### Install cloudflared ###"
curl -fsSL -o /tmp/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
chmod +x /tmp/cloudflared

echo "### Update runner user password ###"
echo -e "$PASSWORD\n$PASSWORD" | sudo passwd "$USER" >/dev/null

echo "### Create the Cloudflare tunnel for SSH (port 22) ###"
python3 cf_tunnel.py setup ssh
source /tmp/cf_tunnel.env

echo "### Launch the tunnel ###"
rm -f /tmp/cloudflared.log
/tmp/cloudflared tunnel run --token "$CF_TUNNEL_TOKEN" > /tmp/cloudflared.log 2>&1 &

READY=""
for _ in $(seq 1 60); do
  if grep -q "Registered tunnel connection" /tmp/cloudflared.log 2>/dev/null; then
    READY=1
    break
  fi
  sleep 1
done
if [[ -z "$READY" ]]; then
  echo "### cloudflared failed to register the tunnel ###"
  tail -n 40 /tmp/cloudflared.log 2>/dev/null || true
  exit 4
fi

echo ""
echo "=========================================="
echo " SSH machine is ready"
echo "  Hostname   : $LINUX_MACHINE_NAME"
echo "  User       : $LINUX_USERNAME"
echo "  Password   : $PASSWORD"
echo "  Public host: $CF_SSH_HOSTNAME"
echo ""
echo " On your PC (cloudflared installed):"
echo "  ssh -o ProxyCommand=\"cloudflared access ssh --hostname $CF_SSH_HOSTNAME\" $LINUX_USERNAME@$CF_SSH_HOSTNAME"
echo "=========================================="
echo "::notice::TUNNEL_HOSTNAMES=$CF_SSH_HOSTNAME"
