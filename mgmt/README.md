# mgmt VM (VMID 110)

Management host for MCP servers, kept outside the k3s VM so a k3s reboot or failure doesn't cut off management access.

| Item | Value |
|---|---|
| VM | VMID 110 `mgmt`, Debian 13 cloud image, 2 vCPU / 2 GB / 32 GB on `data-vms`, guest agent, `onboot=1` |
| Network | VLAN 200 (`vmbr0`), 10.10.200.10/24, gw 10.10.200.1 |
| Runtime | Docker + Compose, stack in `/opt/mgmt` |
| Endpoints | `https://10.10.200.10/proxmox/mcp` (proxmox-mcp), `https://10.10.200.10/k8s/mcp` (kubernetes-mcp) |
| Auth | Bearer token (`MCP_TOKEN`) enforced by Caddy; TLS from Caddy's internal CA |

## Layout on the VM

```
/opt/mgmt/
  compose.yaml   # this directory
  Caddyfile      # this directory
  kubernetes-mcp.toml  # this directory
  .env           # secrets, root:root 0600 - see .env.example
  kubeconfig     # SA kube-system/claude-mcp token, 65532:65532 0400, never committed
  selftest.sh    # proxmox: auth / handshake / get_version (never prints the token)
  selftest-k8s.sh  # k8s: auth / handshake / tools/list / namespaces_list
```

## Kubernetes MCP

- Server: `ghcr.io/containers/kubernetes-mcp-server:v0.1.0` (digest-pinned). Config is TOML only from v0.1.0 (`kubernetes-mcp.toml`); toolsets `core,config,helm`, read/write.
- Identity: ServiceAccount `kube-system/claude-mcp` bound to `cluster-admin` (`k3s/infra/claude-mcp-rbac.yaml`), long-lived token in `/opt/mgmt/kubeconfig`, server `https://10.10.110.10:6443`.
- Caddy strips `Authorization` before proxying to it (`header_up -Authorization`). Without that, the server passes our MCP bearer token to the API server as a k8s credential and every call gets 401.
- Firewall: hEX rule `mgmt -> k3s API (110)` allows 10.10.200.10 to 10.10.110.10:6443.
- Rotate: delete Secret `kube-system/claude-mcp-token`, re-apply the RBAC file, rebuild `/opt/mgmt/kubeconfig`, `docker compose restart kubernetes-mcp`.
- Client: same entry as proxmox-mcp with the URL ending `/k8s/mcp` (same token and CA).

## Deploy / update

```bash
cd /opt/mgmt
docker compose pull && docker compose up -d
sh selftest.sh     # expect: healthz 200, no/wrong token 401, initialize 200, get_version OK
```

## Client config (each admin workstation)

Claude Desktop `claude_desktop_config.json`:

```json
"proxmox-mcp": {
  "command": "/usr/bin/npx",
  "args": ["-y", "mcp-remote", "https://10.10.200.10/proxmox/mcp",
           "--header", "Authorization:${MCP_AUTH}"],
  "env": {
    "MCP_AUTH": "Bearer <MCP_TOKEN>",
    "NODE_EXTRA_CA_CERTS": "/home/sean/.config/mgmt/mgmt-ca.crt"
  }
}
```

The CA cert is Caddy's local root: `docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt mgmt-ca.crt` (valid to 2036). Merge into the existing config rather than overwriting it, keep the file `chmod 600`, and fully quit/restart Claude Desktop.

## Firewall (MikroTik)

- `ws-admin` -> 10.10.200.10:443 is covered by `ADMIN: ws-admin -> all lab VLANs` (10.10.200.0/24 is in `lab-vlans`).
- VLAN 200 is in `VLAN-INTERNAL`, so the VM has outbound access for apt and image pulls.

## PVE token

`claude@pve!mcp` (privsep). ACLs: `PVEAdmin` on `/` and `PVEAdmin,ClaudeNodeOps` on `/nodes/pve`, for both the user and the token. `ClaudeNodeOps` = `Sys.Modify,Sys.AccessNetwork` (needed for `download-url`). A more specific ACL path replaces inherited roles, so `/nodes/pve` must list `PVEAdmin` too.

## Notes

- `qemu-guest-agent` desyncs on non-ASCII bytes in `guest-exec` commands; keep agent commands ASCII-only. Recovery: `systemctl restart qemu-guest-agent` in the guest.
- `proxmox-mcp-server==1.4.2` installs from PyPI at container start into a tmpfs (`exec` enabled).
