#!/bin/bash
# Temporary probe v3: HTTP over 1-level vs 2-level hostnames, plus tcp and ssh
# origins one level deep.  Only reports; never fails the job.
set -uo pipefail

wait_dns() {
  local host="$1"
  for _ in $(seq 1 25); do
    getent hosts "$host" >/dev/null 2>&1 && return 0
    sleep 3
  done
  return 1
}

http_test() {
  local host="$1"
  echo "--- HTTP origin: $host ---"
  wait_dns "$host" || echo "  (DNS still missing)"
  local code
  code=$(curl -sS -m 25 -o /tmp/h.body -w "%{http_code}" "https://$host/" 2>/tmp/h.err || true)
  echo "  HTTPS status: [${code:-none}]"
  head -c 120 /tmp/h.body 2>/dev/null | head -2 | sed 's/^/  body: /'
  sed 's/^/  err : /' /tmp/h.err 2>/dev/null
  echo
}

tcp_test() {
  local host="$1" port="$2"
  echo "--- non-HTTP origin: $host ---"
  wait_dns "$host" || echo "  (DNS still missing)"
  rm -f /tmp/t.log
  /tmp/cloudflared access tcp --hostname "$host" --url "localhost:$port" \
    --logfile /tmp/t.log --log-level debug >/dev/null 2>&1 &
  local pid=$!
  sleep 15
  local got
  got=$(timeout 8 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port; head -c 40 <&3" 2>/dev/null || true)
  if [ -n "$got" ]; then
    echo "  BANNER: [$(printf '%s' "$got" | cat -v)]  -> DATA FLOWS"
  else
    echo "  BANNER: (none)  -> NO DATA"
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  grep -hoE '"message":"[^"]{0,80}"|"error":"[^"]{0,80}"' /tmp/t.log 2>/dev/null | tail -4 | sed 's/^/  log: /'
  echo
}

echo "=========================================="
http_test "$PROBE_FP1"
http_test "$PROBE_FP4"
tcp_test  "$PROBE_FP2" 2224
tcp_test  "$PROBE_FP3" 2225
echo "=========================================="
echo "probe finished"
