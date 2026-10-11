#!/bin/bash
# linux-desktop.sh - build a full XFCE desktop VM and expose it through a
# Cloudflare Tunnel on your own domain.
#
# The desktop is served by TightVNC (display :1 -> port 5901) through the same
# cloudflared tunnel used for the other machines - no Google account, no
# one-time Chrome Remote Desktop code to regenerate on every run.
#
# Environment:
#   PASSWORD            login + VNC password (optional - random when empty;
#                       VNC viewers use its first 8 characters)
#   LINUX_USERNAME      login user  (default: admin)
#   LINUX_MACHINE_NAME  hostname    (default: ubuntu-vps)
#   CF_DOMAIN           your domain or a subdomain of it (zone auto-detected)
#   CF_DESKTOP_HOST     optional full hostname override for this machine

set -euo pipefail

LINUX_USERNAME="${LINUX_USERNAME:-admin}"
LINUX_MACHINE_NAME="${LINUX_MACHINE_NAME:-ubuntu-vps}"
PASSWORD="${PASSWORD:-${LINUX_USER_PASSWORD:-}}"

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(12)))')"
  echo "### No PASSWORD secret set - generated a random one (shown below) ###"
fi
# Legacy VNC authentication is limited to 8 characters.
VNC_PASSWORD="${PASSWORD:0:8}"

if ! id -u "$LINUX_USERNAME" >/dev/null 2>&1; then
  # -N: do NOT create a same-named group - the GitHub runner already has an
  # "admin" group, which makes a plain `useradd -m admin` fail.
  sudo useradd -m -N "$LINUX_USERNAME"
fi
sudo usermod -aG sudo "$LINUX_USERNAME"
echo "$LINUX_USERNAME:$PASSWORD" | sudo chpasswd
sudo sed -i 's/\/bin\/sh/\/bin\/bash/g' /etc/passwd
sudo hostname "$LINUX_MACHINE_NAME"

echo "### Install the desktop (XFCE) + VNC server ###"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install --assume-yes \
  xfce4 desktop-base xscreensaver tightvncserver nautilus nano

echo "### Install a browser (Google Chrome) ###"
curl -fsSL -o /tmp/chrome.deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
sudo DEBIAN_FRONTEND=noninteractive apt-get install --assume-yes /tmp/chrome.deb

echo "### Install cloudflared ###"
curl -fsSL -o /tmp/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
chmod +x /tmp/cloudflared

echo "### Update runner user password ###"
echo -e "$PASSWORD\n$PASSWORD" | sudo passwd "$USER" >/dev/null

echo "### Configure VNC to launch XFCE ###"
VNC_DIR="/home/$LINUX_USERNAME/.vnc"
sudo -H -u "$LINUX_USERNAME" mkdir -p "$VNC_DIR"
cat > /tmp/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
sudo install -o "$LINUX_USERNAME" -g "$LINUX_USERNAME" -m 755 /tmp/xstartup "$VNC_DIR/xstartup"

echo "### Start VNC on display :1 (port 5901) ###"
# vncpasswd asks for: password, verify, then whether a view-only password is
# wanted - so the answers must go in that order.
echo -e "$VNC_PASSWORD\n$VNC_PASSWORD\nno" | sudo -H -u "$LINUX_USERNAME" tightvncserver :1

echo "### Create the Cloudflare tunnel for the desktop (port 5901) ###"
python3 cf_tunnel.py setup desktop
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
echo " Desktop machine is ready (XFCE over VNC)"
echo "  Hostname   : $LINUX_MACHINE_NAME"
echo "  User       : $LINUX_USERNAME"
echo "  Password   : $PASSWORD"
echo "  VNC password (first 8 chars): $VNC_PASSWORD"
echo "  Public host: $CF_DESKTOP_HOSTNAME"
echo ""
echo " On your PC (cloudflared installed):"
echo "  cloudflared access tcp --hostname $CF_DESKTOP_HOSTNAME --url localhost:5900"
echo "  then open a VNC viewer at localhost:5900"
echo "=========================================="
echo "::notice::TUNNEL_HOSTNAMES=$CF_DESKTOP_HOSTNAME"
