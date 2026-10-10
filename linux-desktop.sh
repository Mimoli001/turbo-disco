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

if [[ -z "$LINUX_USER_PASSWORD" ]]; then
  echo "Please set 'LINUX_USER_PASSWORD' for user: $USER"
  exit 3
fi

echo "### Install bore tunnel client ###"

curl -fsSL -o /tmp/bore.tar.gz "https://github.com/ekzhang/bore/releases/download/v0.6.0/bore-v0.6.0-x86_64-unknown-linux-musl.tar.gz"
tar -xzf /tmp/bore.tar.gz -C /tmp
chmod +x /tmp/bore

echo "### Update user: $USER password ###"
echo -e "$LINUX_USER_PASSWORD\n$LINUX_USER_PASSWORD" | sudo passwd "$USER"

echo "### Start bore proxy for 22 port ###"

rm -f /tmp/bore.log
/tmp/bore local 22 --to bore.pub > /tmp/bore.log 2>&1 &

# Wait until the tunnel shows up in the bore log ("listening at bore.pub:PORT")
PUBLIC_HOSTPORT=""
for i in $(seq 1 30); do
  PUBLIC_HOSTPORT=$(grep -oE 'bore\.pub:[0-9]+' /tmp/bore.log 2>/dev/null | head -n1)
  if [[ -n "$PUBLIC_HOSTPORT" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$PUBLIC_HOSTPORT" ]]; then
  echo "### bore failed to start the SSH tunnel ###"
  tail -n 30 /tmp/bore.log 2>/dev/null
  exit 4
fi

HOST="${PUBLIC_HOSTPORT%:*}"
PORT="${HOSTPORT##*:}"

echo ""
echo "=========================================="
echo "To connect: ssh $LINUX_USERNAME@$HOST -p $PORT"
echo "or connect with: ssh $USER@$HOST -p $PORT"
echo "(use your LINUX_USER_PASSWORD secret as the password)"
echo "Connect with remote desktop: https://remotedesktop.google.com/access"
echo "=========================================="
