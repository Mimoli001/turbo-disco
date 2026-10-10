#!/bin/bash
# linux-desktop.sh LINUX_USER_PASSWORD CF_SSH_* CHROME_HEADLESS_CODE LINUX_MACHINE_NAME LINUX_USERNAME GOOGLE_REMOTE_PIN

sudo useradd -m $LINUX_USERNAME
sudo adduser $LINUX_USERNAME sudo
echo "$LINUX_USERNAME:$LINUX_USER_PASSWORD" | sudo chpasswd
sed -i 's/\/bin\/sh/\/bin\/bash/g' /etc/passwd
sudo apt-get update
wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
sudo dpkg --install chrome-remote-desktop_current_amd64.deb
sudo apt install --assume-yes --fix-broken
sudo DEBIAN_FRONTEND=noninteractive \
apt install --assume-yes xfce4 desktop-base
sudo bash -c 'echo "exec /etc/X11/Xsession /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session'
sudo apt install --assume-yes xscreensaver
sudo systemctl disable lightdm.service
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg --install google-chrome-stable_current_amd64.deb
sudo apt install --assume-yes --fix-broken
sudo apt install --assume-yes nautilus nano
sudo apt install --assume-yes gdebi
sudo apt install --assume-yes firefox || echo "firefox package unavailable on this image, skipping (Google Chrome is installed)"
sudo hostname $LINUX_MACHINE_NAME
sudo adduser $LINUX_USERNAME chrome-remote-desktop
sudo apt install --assume-yes tightvncserver
echo -e "no\n$LINUX_USER_PASSWORD\n$LINUX_USER_PASSWORD" | tightvncserver :1
echo -e "$GOOGLE_REMOTE_PIN\n$GOOGLE_REMOTE_PIN" | su - $LINUX_USERNAME -c """$CHROME_HEADLESS_CODE"""

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
echo "Connect with remote desktop: https://remotedesktop.google.com/access"
echo "=========================================="
echo "::notice::TUNNEL_HOSTNAMES=$CF_SSH_HOSTNAME"
