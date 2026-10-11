#!/bin/bash
# Temporary probe v2: compare an http:// origin with tcp:// and ssh:// origins,
# none of them protected by an Access app.  Only reports; never fails the job.
set -uo pipefail

wait_dns() {
  local host="$1"
  for _ in $(seq 1 30); do
    if getent hosts "$host" >/dev/null 2>&1; then echo "  DNS ok: $(getent hosts "$host" | head -1)"; return 0; fi
    sleep 3
  done
  echo "  DNS: still no record for $host"
  return 1
}

echo "=========================================="
echo "--- control: HTTP origin ---"
echo "target: $PROBE_HTTP"
wait_dns "$PROBE_HTTP" || true
code=$(curl -sS -m 25 -o /tmp/http.body -w "%{http_code}" "https://$PROBE_HTTP/" 2>/tmp/http.err || true)
echo "  curl returned HTTP status: [${code:-none}]"
head -c 200 /tmp/http.body 2>/dev/null | head -3 | sed 's/^/  body: /'
cat /tmp/http.err 2>/dev/null | sed 's/^/  err : /'

tcp_test() {
  local host="$1" port="$2" extra="${3:-}"
  echo "--- origin type: $host ---"
  wait_dns "$host" || true
  rm -f /tmp/t.log
  # shellcheck disable=SC2086
  /tmp/cloudflared access tcp --hostname "$host" --url "localhost:$port" \
    --logfile /tmp/t.log --log-level debug $extra >/dev/null 2>&1 &
  local pid=$!
  sleep 15
  if ss -ltn 2>/dev/null | grep -q ":$port "; then
    echo "  local listener on $port: yes (this always happens - not a verdict)"
  fi
  local got
  got=$(timeout 8 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port; head -c 40 <&3" 2>/dev/null || true)
  if [ -n "$got" ]; then
    echo "  BANNER from the origin: [$(printf '%s' "$got" | cat -v)]"
    echo "  VERDICT: DATA FLOWS"
  else
    echo "  BANNER from the origin: (nothing)"
    echo "  VERDICT: NO DATA"
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  grep -hoE '"message":"[^"]*"|"error":"[^"]*"' /tmp/t.log 2>/dev/null | tail -6 | sed 's/^/  log: /'
}

tcp_test "$PROBE_TCP" 2222
tcp_test "$PROBE_SSH" 2223
echo "=========================================="
echo "probe finished"
