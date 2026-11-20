#!/bin/bash
# Self-test for https://10.10.200.10/k8s/mcp. Reads MCP_TOKEN from .env; never prints it.
set -u
cd /opt/mgmt
TOKEN=$(sed -n 's/^MCP_TOKEN=//p' .env)
CA=/tmp/caddy-root.crt
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt "$CA" >/dev/null 2>&1
U=https://10.10.200.10/k8s/mcp
R="--resolve 10.10.200.10:443:127.0.0.1 --cacert $CA"
H1='Content-Type: application/json'
H2='Accept: application/json, text/event-stream'
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"selftest","version":"1"}}}'

echo "api tcp:     $(timeout 5 bash -c '</dev/tcp/10.10.110.10/6443' 2>/dev/null && echo open || echo blocked)"
echo "no token:    $(curl -sS $R -o /dev/null -w '%{http_code}' -H "$H1" -H "$H2" -d "$INIT" $U)"
echo "--- initialize:"
curl -sS $R -D /tmp/kh -H "$H1" -H "$H2" -H "Authorization: Bearer $TOKEN" -d "$INIT" $U | head -c 250; echo
SID=$(sed -n 's/^[Mm]cp-[Ss]ession-[Ii]d: *//p' /tmp/kh | tr -d '\r')
echo "session: ${SID:+present}"
S="-H Mcp-Session-Id:$SID"
curl -sS $R -o /dev/null -H "$H1" -H "$H2" -H "Authorization: Bearer $TOKEN" $S -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' $U
echo "--- tools/list (names):"
curl -sS $R -H "$H1" -H "$H2" -H "Authorization: Bearer $TOKEN" $S -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' $U \
  | grep -o '"name":"[a-z_]*"' | sort -u | tr '\n' ' '; echo
echo "--- tools/call namespaces_list:"
curl -sS $R -H "$H1" -H "$H2" -H "Authorization: Bearer $TOKEN" $S -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"namespaces_list","arguments":{}}}' $U | head -c 700; echo
rm -f /tmp/kh "$CA"
