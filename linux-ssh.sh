#!/bin/bash
# linux-ssh.sh LINUX_USER_PASSWORD CF_SSH_* LINUX_USERNAME LINUX_MACHINE_NAME

sudo useradd -m $LINUX_USERNAME
sudo adduser $LINUX_USERNAME sudo
echo "$LINUX_USERNAME:$LINUX_USER_PASSWORD" | sudo chpasswd
sed -i 's/\/bin\/sh/\/bin\/bash/g' /etc/passwd
sudo hostname $LINUX_MACHINE_NAME

if [[ -z "$LINUX_USER_PASSWORD" ]]; then
  echo "Please set 'LINUX_USER_PASSWORD' for user: $USER"
  exit 3
fi

echo "### Install cloudflared ###"

curl -fsSL -o /tmp/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
chmod +x /tmp/cloudflared

echo "### Update user: $USER password ###"
echo -e "$LINUX_USER_PASSWORD\n$LINUX_USER_PASSWORD" | sudo passwd "$USER"

echo "### Create Cloudflare tunnel for SSH (port 22) ###"

python3 cf_tunnel.py setup ssh

rm -f /tmp/cloudflared.log
/tmp/cloudflared tunnel run --token "$CF_TUNNEL_TOKEN" > /tmp/cloudflared.log 2>&1 &

# Wait until the tunnel is registered with the Cloudflare edge
READY=""
for i in $(seq 1 60); do
  if grep -q "Registered tunnel connection" /tmp/cloudflared.log 2>/dev/null; then
    READY=1
    break
  fi
  sleep 1
done

if [[ -z "$READY" ]]; then
  echo "### cloudflared failed to register the tunnel ###"
  tail -n 40 /tmp/cloudflared.log 2>/dev/null
  exit 4
fi

echo ""
echo "=========================================="
echo "Tunnel is up: $CF_SSH_HOSTNAME"
echo "Connect from your PC with cloudflared installed:"
echo "  cloudflared access ssh --hostname $CF_SSH_HOSTNAME"
echo "or: ssh -o ProxyCommand=\"cloudflared access ssh --hostname $CF_SSH_HOSTNAME\" $LINUX_USERNAME@$CF_SSH_HOSTNAME"
echo "(use your LINUX_USER_PASSWORD secret as the password)"
echo "=========================================="
echo "::notice::TUNNEL_HOSTNAMES=$CF_SSH_HOSTNAME"
