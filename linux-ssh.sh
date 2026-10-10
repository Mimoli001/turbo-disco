#!/bin/bash
# linux-ssh.sh LINUX_USER_PASSWORD NGROK_AUTH_TOKEN LINUX_USERNAME LINUX_MACHINE_NAME

sudo useradd -m $LINUX_USERNAME
sudo adduser $LINUX_USERNAME sudo
echo "$LINUX_USERNAME:$LINUX_USER_PASSWORD" | sudo chpasswd
sed -i 's/\/bin\/sh/\/bin\/bash/g' /etc/passwd
sudo hostname $LINUX_MACHINE_NAME

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
/tmp/bore local 22 --to bore.pub --port 40261 > /tmp/bore.log 2>&1 &

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
PORT="${PUBLIC_HOSTPORT##*:}"

echo ""
echo "=========================================="
echo "::notice::TUNNEL_PORT=$PORT"
echo "To connect: ssh $LINUX_USERNAME@$HOST -p $PORT"
echo "or connect with: ssh $USER@$HOST -p $PORT"
echo "(use your LINUX_USER_PASSWORD secret as the password)"
echo "=========================================="
