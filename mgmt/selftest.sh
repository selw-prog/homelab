#!/bin/sh
# Self-test for the mgmt MCP endpoint. Reads MCP_TOKEN from .env; never prints it.
set -u
cd /opt/mgmt
TOKEN=$(sed -n 's/^MCP_TOKEN=//p' .env)
U=https://127.0.0.1/proxmox/mcp
CA=/tmp/caddy-root.crt
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt "$CA" >/dev/null 2>&1
C="curl -sS --cacert $CA --resolve 10.10.200.10:443:127.0.0.1 -o /dev/null -w %{http_code}"
U=https://10.10.200.10/proxmox/mcp
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"selftest","version":"1"}}}'
H='-H Content-Type:application/json -H Accept:application/json,text/event-stream'

echo "healthz (no auth):  $($C https://10.10.200.10/healthz)"
echo "no token:           $($C $H -d "$INIT" $U)"
echo "wrong token:        $($C $H -H 'Authorization: Bearer nope' -d "$INIT" $U)"
echo "other path w/token: $($C -H "Authorization: Bearer $TOKEN" https://10.10.200.10/admin)"
echo "--- initialize with token:"
curl -sS --cacert $CA --resolve 10.10.200.10:443:127.0.0.1 -D /tmp/h $H \
  -H "Authorization: Bearer $TOKEN" -d "$INIT" $U | head -c 300; echo
grep -i -E '^HTTP|mcp-session-id' /tmp/h
SID=$(sed -n 's/^[Mm]cp-[Ss]ession-[Ii]d: *//p' /tmp/h | tr -d '\r')
curl -sS --cacert $CA --resolve 10.10.200.10:443:127.0.0.1 -o /dev/null $H \
  -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' $U
echo "--- tools/call get_version:"
curl -sS --cacert $CA --resolve 10.10.200.10:443:127.0.0.1 $H \
  -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_version","arguments":{}}}' $U | head -c 400; echo
echo "--- cert:"
openssl x509 -in "$CA" -noout -subject -enddate 2>/dev/null || echo "openssl missing"
docker compose ps --format '{{.Name}} {{.Status}}'
