# Minecraft (archived 2026-11-19)

Both servers were removed from the cluster when it was repurposed for the website and network-analysis work. Manifests here are cleaned exports of the last live state, with the JMX/Prometheus exporter wiring removed.

| Server | Manifest | World archive (Google Drive) | Last RAM request |
|---|---|---|---|
| Crucial 2 (Forge 1.16.5) | `crucial-server.yaml` | `gdrive:MinecraftArchive/crucial_final_*.tar.gz` | 5 Gi |
| Paper (latest) | `vanilla-paper-server.yaml` | `gdrive:MinecraftArchive/vanilla-paper_final_*.tar.gz` | 4 Gi |

`MinecraftArchive/` is separate from the old `MinecraftBackups/` folder, which the former backup CronJob pruned after 2 days.

## Restore

```bash
kubectl apply -f namespace.yaml
kubectl apply -f crucial-server.yaml               # creates PVC, Service, StatefulSet (replicas: 0)

# Load world data into the empty PVC with a temporary pod, then:
rclone copy gdrive:MinecraftArchive/crucial_final_<ts>.tar.gz /tmp/
kubectl -n minecraft cp /tmp/crucial_final_<ts>.tar.gz <restore-pod>:/data/
kubectl -n minecraft exec <restore-pod> -- tar -xzf /data/crucial_final_<ts>.tar.gz -C /data

kubectl -n minecraft scale sts crucial-server --replicas=1
```

Size the k3s VM for the RAM request first, and re-add the MikroTik DNAT/forward rules for NodePorts 30001/30002.
