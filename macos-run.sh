#!/bin/bash
# macos-run.sh - prepare the macOS VM and expose Screen Sharing (port 5900)
# through a Cloudflare Tunnel on your own domain. Sourced by the workflow
# under `bash -e -o pipefail`.
#
# Environment:
#   PASSWORD       account + VNC password (optional - random when empty;
#                  VNC viewers use its first 8 characters)
#   MAC_REALNAME   account full name (default: mac)

MAC_REALNAME="${MAC_REALNAME:-mac}"
PASSWORD="${PASSWORD:-${MAC_USER_PASSWORD:-${VNC_PASSWORD:-}}}"

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(12)))')"
  echo "### No PASSWORD secret set - generated a random one (shown below) ###"
fi
# Apple's legacy VNC authentication is limited to 8 characters.
VNC_PASSWORD="${PASSWORD:0:8}"

echo "### Turn off Spotlight indexing to save CPU ###"
sudo mdutil -i off -a

echo "### Create the user account ###"
sudo dscl . -create /Users/vpsuser
sudo dscl . -create /Users/vpsuser UserShell /bin/bash
sudo dscl . -create /Users/vpsuser RealName "$MAC_REALNAME"
sudo dscl . -create /Users/vpsuser UniqueID 1001
sudo dscl . -create /Users/vpsuser PrimaryGroupID 80
sudo dscl . -create /Users/vpsuser NFSHomeDirectory /Users/vpsuser
sudo dscl . -passwd /Users/vpsuser "$PASSWORD"
sudo createhomedir -c -u vpsuser > /dev/null
sudo dscl . -append /Groups/admin GroupMembership vpsuser

echo "### Enable Screen Sharing and set its password ###"
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -configure -allowAccessFor -allUsers -privs -all
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -configure -clientopts -setvnclegacy -vnclegacy yes
echo "$VNC_PASSWORD" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -restart -agent -console
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate

echo "### Install cloudflared ###"
curl -fsSL -o /tmp/cloudflared.tgz "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz"
tar -xzf /tmp/cloudflared.tgz -C /tmp
chmod +x /tmp/cloudflared

echo "### Create the Cloudflare tunnel for Screen Sharing (port 5900) ###"
python3 cf_tunnel.py setup vnc
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
echo " macOS machine is ready"
echo "  Account    : vpsuser  (full name: $MAC_REALNAME)"
echo "  Password   : $PASSWORD"
echo "  VNC password (first 8 chars): $VNC_PASSWORD"
echo "  Public host: $CF_VNC_HOSTNAME"
echo ""
echo " On your PC (cloudflared installed):"
echo "  cloudflared access tcp --hostname $CF_VNC_HOSTNAME --url localhost:5900"
echo "  then open Screen Sharing / a VNC viewer at localhost:5900"
echo "=========================================="
echo "::notice::TUNNEL_HOSTNAMES=$CF_VNC_HOSTNAME"
