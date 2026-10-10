#macos-run.sh MAC_USER_PASSWORD VNC_PASSWORD NGROK_AUTH_TOKEN MAC_REALNAME

#disable spotlight indexing
sudo mdutil -i off -a

#Create new account
sudo dscl . -create /Users/vpsuser
sudo dscl . -create /Users/vpsuser UserShell /bin/bash
sudo dscl . -create /Users/vpsuser RealName $4
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

#install bore tunnel client (no account/card required)
curl -fsSL -o /tmp/bore.tar.gz "https://github.com/ekzhang/bore/releases/download/v0.6.0/bore-v0.6.0-aarch64-apple-darwin.tar.gz"
tar -xzf /tmp/bore.tar.gz -C /tmp
chmod +x /tmp/bore

#start bore tunnel for the VNC/Screen Sharing port (5900)
rm -f /tmp/bore.log
/tmp/bore local 5900 --to bore.pub > /tmp/bore.log 2>&1 &
