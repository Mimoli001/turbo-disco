#!/bin/bash
# Temporary end-to-end client: connects to a machine that a concurrent workflow
# run has published, through the public Cloudflare edge, and checks the real
# protocol handshake / login.  Only reports; never fails the job.
#
#   usage: e2e_test.sh <ssh|desktop|rdp> [poll-seconds] [hostname]
set -uo pipefail

WHICH="$1"
LIMIT="${2:-150}"
OVERRIDE="${3:-}"

host_for() {
  if [ -n "$OVERRIDE" ]; then
    echo "$OVERRIDE"
    return
  fi
  python3 - "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cf", "cf_tunnel.py")
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)
print(cf.resolve_route(sys.argv[1])[0])
PY
}

HOST=$(host_for "$WHICH" | tail -1)
echo "=========================================="
echo "target hostname : $HOST"
echo "protocol        : $WHICH"

# Cloudflare answers "error code: 1033" for a published hostname whose tunnel
# has no live connection yet.  Anything else means the tunnel is connected, so
# this gives the client a precise readiness signal instead of a blind race.
wait_for_tunnel() {
  local limit="${1:-60}" body i
  for i in $(seq 1 "$limit"); do
    body=$(curl -sS -m 8 "https://$HOST/" 2>&1 | tr -d '\n')
    if [ -n "$body" ] && [ "${body#*error code: 1033}" = "$body" ]; then
      echo "tunnel is live    : $i probe(s), reply [$(printf '%s' "$body" | head -c 90)]"
      return 0
    fi
    sleep 4
  done
  echo "tunnel never became live (still 1033) - giving up"
  return 1
}
wait_for_tunnel "${WAIT_FOR_TUNNEL:-60}" || true

start_proxy() {
  local port="$1"
  cloudflared access tcp --hostname "$HOST" --url "localhost:$port" \
    --logfile /tmp/proxy.log --log-level error >/dev/null 2>&1 &
  PROXY_PID=$!
  sleep 3
  echo "local forward    : localhost:$port"
}

case "$WHICH" in
  ssh)
    start_proxy 2222
    echo "--- waiting for an SSH login through the tunnel ---"
    for i in $(seq 1 "$LIMIT"); do
      out=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no \
              -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
              -o PreferredAuthentications=password -p 2222 admin@127.0.0.1 \
              'echo SSH_LOGIN_OK; whoami; hostname' 2>/dev/null)
      if [[ "$out" == *SSH_LOGIN_OK* ]]; then
        echo "RESULT: SSH LOGIN SUCCEEDED through the tunnel"
        echo "$out" | sed 's/^/  /'
        break
      fi
      sleep 3
    done
    echo "--- also trying 'cloudflared access ssh' (ProxyCommand form) ---"
    timeout 60 sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=20 \
      -o ProxyCommand="cloudflared access ssh --hostname $HOST" \
      admin@"$HOST" 'echo PROXYCOMMAND_OK' 2>&1 | tail -4 | sed 's/^/  /'
    ;;

  rdp)
    start_proxy 3390
    echo "--- waiting for an RDP X.224 Connection Confirm ---"
    python3 - "$LIMIT" <<'PY'
import socket, sys, time
limit = int(sys.argv[1])
# X.224 Connection Request carrying an RDP Negotiation Request
# (19 bytes: TPKT len 0x13, LI 0x0e, CR 0xe0, RDP-neg len 8, protocols 3 LE)
payload = bytes.fromhex("030000130ee000000000000100080003000000")
for i in range(limit):
    try:
        s = socket.create_connection(("127.0.0.1", 3390), timeout=8)
        s.sendall(payload)
        data = s.recv(64)
        s.close()
        # a Connection Confirm carries TPDU code 0xd0 at index 5
        if len(data) >= 6 and data[5] == 0xd0:
            print("RESULT: RDP HANDSHAKE SUCCEEDED (X.224 Connection Confirm)")
            print("  reply: %s" % data.hex())
            sys.exit(0)
        print("  attempt %d: %d bytes back: %s" % (i, len(data), data.hex()))
    except Exception as exc:
        print("  attempt %d: %s" % (i, exc))
    time.sleep(3)
print("RESULT: RDP HANDSHAKE NOT RECEIVED")
PY
    ;;

  desktop)
    start_proxy 5905
    echo "--- waiting for a VNC RFB banner ---"
    python3 - "$LIMIT" <<'PY'
import socket, sys, time
limit = int(sys.argv[1])
for i in range(limit):
    try:
        s = socket.create_connection(("127.0.0.1", 5905), timeout=8)
        banner = s.recv(12)
        s.close()
        if banner.startswith(b"RFB "):
            print("RESULT: VNC REACHED (RFB banner) %s"
                  % banner.decode(errors="replace").strip())
            sys.exit(0)
        print("  attempt %d: unexpected reply %r" % (i, banner))
    except Exception as exc:
        print("  attempt %d: %s" % (i, exc))
    time.sleep(3)
print("RESULT: NO RFB BANNER")
PY
    ;;

  *)
    echo "unknown protocol $WHICH"
    ;;
esac

kill "$PROXY_PID" 2>/dev/null || true
echo "=========================================="
echo "proxy log (last 8 lines):"
tail -8 /tmp/proxy.log 2>/dev/null | sed 's/^/  /'
echo "client finished"
