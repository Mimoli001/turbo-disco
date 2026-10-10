#!/bin/bash
# linux-desktop.sh LINUX_USER_PASSWORD NGROK_AUTH_TOKEN CHROME_HEADLESS_CODE LINUX_MACHINE_NAME LINUX_USERNAME GOOGLE_REMOTE_PIN

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

if [[ -z "$NGROK_AUTH_TOKEN" ]]; then
  echo "Please set 'NGROK_AUTH_TOKEN'"
  exit 2
fi

if [[ -z "$LINUX_USER_PASSWORD" ]]; then
  echo "Please set 'LINUX_USER_PASSWORD' for user: $USER"
  exit 3
fi

echo "### Install ngrok ###"

curl -fsSL -o /tmp/ngrok.zip "https://bin.ngrok.com/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip"
unzip -o /tmp/ngrok.zip -d /tmp/ngrok-bin
chmod +x /tmp/ngrok-bin/ngrok

echo "### Update user: $USER password ###"
echo -e "$LINUX_USER_PASSWORD\n$LINUX_USER_PASSWORD" | sudo passwd "$USER"

echo "### Start ngrok proxy for 22 port ###"

rm -f /tmp/ngrok.log
/tmp/ngrok-bin/ngrok config add-authtoken "$NGROK_AUTH_TOKEN"
/tmp/ngrok-bin/ngrok tcp 22 --log /tmp/ngrok.log &

# Wait until the tunnel shows up in the local ngrok API (http://127.0.0.1:4040)
PUBLIC_URL=""
for i in $(seq 1 30); do
  if grep -q "command failed" /tmp/ngrok.log 2>/dev/null; then
    break
  fi
  PUBLIC_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | grep -oE 'tcp://[A-Za-z0-9.]+:[0-9]+' | head -n1)
  if [[ -n "$PUBLIC_URL" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$PUBLIC_URL" ]]; then
  echo "### ngrok failed to start the SSH tunnel ###"
  grep -h "command failed" /tmp/ngrok.log 2>/dev/null
  tail -n 30 /tmp/ngrok.log 2>/dev/null
  echo "Common causes:"
  echo " - NGROK_AUTH_TOKEN is invalid (create one at https://dashboard.ngrok.com/get-started/your-authtoken)"
  echo " - free ngrok accounts must verify a credit card before TCP tunnels (SSH/RDP/VNC) are allowed"
  exit 4
fi

HOSTPORT="${PUBLIC_URL#tcp://}"
HOST="${HOSTPORT%:*}"
PORT="${HOSTPORT##*:}"

echo ""
echo "=========================================="
echo "To connect: ssh $LINUX_USERNAME@$HOST -p $PORT"
echo "or connect with: ssh $USER@$HOST -p $PORT"
echo "(use your LINUX_USER_PASSWORD secret as the password)"
echo "Connect with remote desktop: https://remotedesktop.google.com/access"
echo "=========================================="
