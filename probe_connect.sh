#!/bin/bash
# Temporary probe: can a client reach the published hostname at all, with and
# without an Access app in front of it?  Never fails the job - it only reports.
set -uo pipefail

HOST="${PROBE_HOST:-}"
echo "=========================================="
echo "target host : $HOST"
echo "--- DNS ---"
getent hosts "$HOST" || echo "  (no A/AAAA record yet)"
echo

try_once() {
  local label="$1"; shift
  local port="$1"; shift
  local logfile="$1"; shift
  rm -f "$logfile"
  echo "--- $label ---"
  /tmp/cloudflared access tcp --hostname "$HOST" --url "localhost:$port" \
    --logfile "$logfile" --log-level debug "$@" >/dev/null 2>&1 &
  local pid=$!
  sleep 15
  if ss -ltn 2>/dev/null | grep -q ":$port "; then
    echo "  local listener is UP on $port"
    local banner
    banner=$(timeout 6 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port; head -c 40 <&3" 2>/dev/null || true)
    echo "  bytes read from the origin: [$(printf '%s' "$banner" | cat -v)]"
    echo "  VERDICT: TUNNEL_CARRIES_DATA"
  else
    echo "  no local listener on $port"
    echo "  VERDICT: NO_CONNECTION"
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "  --- cloudflared log (last 15 lines) ---"
  tail -15 "$logfile" 2>/dev/null | sed 's/^/    /'
  echo
}

try_once "A: no credentials at all" 2222 /tmp/a.log

if [ -f /tmp/svc_token.json ]; then
  SVC_ID=$(python3 -c "import json;print(json.load(open('/tmp/svc_token.json'))['id'])")
  SVC_SECRET=$(python3 -c "import json;print(json.load(open('/tmp/svc_token.json'))['secret'])")
  echo "service token available (client_id=$SVC_ID)"
  try_once "B: with an Access service token" 2223 /tmp/b.log \
    --service-token-id "$SVC_ID" --service-token-secret "$SVC_SECRET"
else
  echo "no service token was created - skipping B"
fi
echo "=========================================="
echo "probe finished"
