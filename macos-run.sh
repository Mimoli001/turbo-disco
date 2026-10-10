#macos-run.sh MAC_USER_PASSWORD VNC_PASSWORD MAC_REALNAME

#disable spotlight indexing
sudo mdutil -i off -a

#Create new account
sudo dscl . -create /Users/vpsuser
sudo dscl . -create /Users/vpsuser UserShell /bin/bash
sudo dscl . -create /Users/vpsuser RealName $3
sudo dscl . -create /Users/vpsuser UniqueID 1001
sudo dscl . -create /Users/vpsuser PrimaryGroupID 80
sudo dscl . -create /Users/vpsuser NFSHomeDirectory /Users/vpsuser
sudo dscl . -passwd /Users/vpsuser $1
sudo dscl . -passwd /Users/vpsuser $1
sudo createhomedir -c -u vpsuser > /dev/null
sudo dscl . -append /Groups/admin GroupMembership vpsuser

#Enable VNC
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -allowAccessFor -allUsers -privs -all
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -clientopts -setvnclegacy -vnclegacy yes 

echo $2 | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt

#Start VNC/reset changes
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -restart -agent -console
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate

#install cloudflared
curl -fsSL -o /tmp/cloudflared.tgz "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz"
tar -xzf /tmp/cloudflared.tgz -C /tmp
chmod +x /tmp/cloudflared

#create the Cloudflare tunnel for VNC (port 5900)
python3 cf_tunnel.py setup vnc

rm -f /tmp/cloudflared.log
/tmp/cloudflared tunnel run --token "$CF_TUNNEL_TOKEN" > /tmp/cloudflared.log 2>&1 &

#wait until the tunnel is registered with the Cloudflare edge
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

echo "VNC tunnel is up: $CF_VNC_HOSTNAME"
echo "Connect from your PC with cloudflared installed:"
echo "  cloudflared access tcp --hostname $CF_VNC_HOSTNAME --url localhost:5900"
echo "::notice::TUNNEL_HOSTNAMES=$CF_VNC_HOSTNAME"
