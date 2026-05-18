# Hetzner Cloud — Kairos + k3s + Hetzner Cloud Controller Manager

Ready-to-deploy [Kairos](https://kairos.io) cloud-configs for bootstrapping a single-node k3s cluster on [Hetzner Cloud](https://www.hetzner.com/cloud/) with the [Hetzner Cloud Controller Manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager) (HCCM / "hcloud CCM") pre-installed via [k3s auto-deploying manifests](https://docs.k3s.io/installation/packaged-components).

Each variant produces a working cluster within ~1 min of first boot — no `kubectl apply` after install, no manual Helm runs.

## Variants

| File | What you get |
|---|---|
| **`hcm-only.yaml`** | k3s + Flannel (default CNI) + Hetzner CCM. No ingress controller. The minimum that exposes Hetzner Cloud Load Balancers and Volumes to your workloads. |
| **`hcm-traefik.yaml`** | `hcm-only` + the k3s-bundled Traefik v3, reconfigured to enable its native [Gateway API](https://gateway-api.sigs.k8s.io/) provider. Lets you write `Gateway` + `HTTPRoute` resources out of the box. A Hetzner Cloud Load Balancer is auto-provisioned for Traefik. |
| **`hcm-cilium.yaml`** | k3s with [Cilium](https://cilium.io/) as the CNI (eBPF dataplane, `kubeProxyReplacement: true`), in native-routing mode over the Hetzner private network. Hetzner CCM still runs (for node addressing + Hetzner LBs); Cilium handles all pod routing. Gateway API enabled via Cilium. |

All three share the same plumbing:
- HCCM via a `HelmChart` manifest dropped in `/var/lib/rancher/k3s/server/manifests/` at first boot
- `networking.clusterCIDR: 10.42.0.0/16` so the CCM route-controller agrees with k3s's default pod CIDR (mismatch crashloops the CCM — see notes below)
- A `stages.boot` step that detects the private-network IP and writes `node-ip:` to `/etc/rancher/k3s/config.yaml` *before* k3s starts (otherwise kubelet's TLS cert SAN omits the private IP, and `kubectl logs/exec/top` later fail with `x509` errors)

## Repository layout

```
hetzner-cloud/
├── README.md
├── hcm-only.yaml          # cloud-config: HCCM + Flannel + hcloud-csi
├── hcm-traefik.yaml       # cloud-config: + Traefik v3 Gateway API
├── hcm-cilium.yaml        # cloud-config: + Cilium (replaces Flannel + kube-proxy)
└── manifests/             # cleartext sources for every base64-encoded write_files entry
    ├── hcloud-secret.yaml         # used by all three
    ├── hcloud-ccm-only.yaml       # used by hcm-only
    ├── hcloud-ccm-traefik.yaml    # used by hcm-traefik
    ├── hcloud-ccm-cilium.yaml     # used by hcm-cilium
    ├── hcloud-csi.yaml            # used by all three
    ├── traefik-config.yaml        # used by hcm-traefik
    ├── cilium.yaml                # used by hcm-cilium
    └── regenerate-b64.sh          # re-encodes every manifest to single-line b64
```

The `manifests/` directory holds the cleartext source for every base64-encoded `write_files.content` field in the cloud-configs. The cloud-configs themselves still use the encoded form (cloud-init expects single-string `content`). If you change a manifest, run `bash manifests/regenerate-b64.sh` and paste the matching block into the `content:` field of the cloud-config(s) listed in the script's per-block `# consumed by:` header. The leading `#` explanation block at the top of each manifest file is stripped before encoding (it's there for human readers, not for k3s).

## Prerequisites

1. **A Hetzner Cloud account and project.** Free to create.
2. **A custom Kairos ISO** uploaded to your Hetzner account. Hetzner does not allow direct ISO uploads — open a support ticket pointing at the Kairos ISO URL of your choice. See the [Kairos Hetzner installation guide](https://kairos.io/docs/installation/hetzner/) for the full flow.
3. **A Hetzner Cloud API token** with **Read & Write** scope. Generate one in `Project → Security → API Tokens`.
4. **A Hetzner Cloud Private Network** that your servers will be attached to. Without one the HCCM still runs but loses access to the per-node `InternalIP = private address` benefit (pod traffic stays on the public NIC).
5. **A server name in Hetzner Cloud** that you use *exactly* in the cloud-config's `hostname:` field. The HCCM looks up each node by name in the Hetzner API; a mismatch breaks the node ↔ server binding (no `providerID`, no zone labels, possibly broken LB attachment). Pick a name in the Hetzner console first, then put the same name in the cloud-config.

## Use

1. **Pick the variant** that matches your needs (see table above).

2. **Substitute the placeholders** in the file:

   | Placeholder | Where | Replace with |
   |---|---|---|
   | `<YOUR_HETZNER_SERVER_NAME>` | `hostname:` line | The name you assigned to the Hetzner Cloud server in the console — **must match exactly** |
   | `<K3S_TOKEN>` | `--token=...` in `k3s.args` | Any random string. The first node defines the cluster's shared secret; subsequent join nodes must use the same value. Example: `openssl rand -hex 32` |
   | `<HETZNER_API_TOKEN>` and `<HETZNER_NETWORK_NAME_OR_ID>` | The `hcloud-secret.yaml` base64 content | Regenerate with: `printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: hcloud\n  namespace: kube-system\nstringData:\n  token: "<YOUR_TOKEN>"\n  network: "<YOUR_NETWORK>"\n' \| base64 -w0` — paste the output into the `content:` field |
   | `"ssh-ed25519 AAAA... user@host"` | `users[0].ssh_authorized_keys` | Your public SSH key(s) |
   | `<HETZNER_REGION>` (all three variants) | `HCLOUD_LOAD_BALANCERS_LOCATION` value inside the CCM `valuesContent` | One of `fsn1`, `nbg1`, `hel1`, `ash`, `hil`, `sin`. **Must align with your servers' Hetzner location** — the LB and servers have to share a Hetzner network zone (`eu-central` = fsn1/nbg1/hel1, `us-east` = ash, `us-west` = hil, `ap-southeast` = sin) for the bundled `HCLOUD_LOAD_BALANCERS_USE_PRIVATE_IP=true` setting to work. Best practice: set this to the **exact same** Hetzner location code as your servers. |

3. **Paste the resulting cloud-config** into the [Kairos WebUI installer](https://kairos.io/docs/installation/webui/) when the VM boots from the Kairos ISO. The installer writes it to disk, then on first boot of the installed system everything provisions automatically.

4. **Verify after first boot** (~1 min from kubelet-ready):
   ```bash
   kubectl get nodes -o wide
   # Expect: STATUS Ready, INTERNAL-IP from your Hetzner private network (10.0.0.x by default)
   kubectl -n kube-system get pods | grep hcloud-cloud-controller-manager
   # Expect: 1/1 Running, RESTARTS=0
   kubectl get node <hostname> -o jsonpath='{.spec.providerID}{"\n"}'
   # Expect: hcloud://<numeric-server-id>  (proves CCM matched the Hetzner server)
   ```

## Security: restricting access to the LBs

Hetzner Cloud Firewalls only apply to **servers**, not to Load Balancers — so you can't use one to filter who can reach an LB's public IP. Restrict at the LB itself instead.

### 1. Allowlist source IPs on a public LB

Set `loadBalancerSourceRanges` on the Service. HCCM translates it into the Hetzner LB's per-listener Source IP filter (visible in the Hetzner console under the service's "Source IPs"). Anything outside the listed CIDRs is dropped by the LB before it ever reaches your nodes.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  type: LoadBalancer
  loadBalancerSourceRanges:
    - 203.0.113.42/32       # office IPv4
    - 2a01:4f8::/29         # office IPv6
  ports:
    - { port: 443, targetPort: 8443 }
```

Caveats:
- Applies to **all** listener ports of that Service. For per-port ACLs, configure the LB directly in the Hetzner console.
- IPv4 and IPv6 CIDRs can mix in the same list. Empty list = wide open (the default).
- For Cilium Gateway API (`hcm-cilium`) the Service is auto-created as `cilium-gateway-<gateway-name>` — `kubectl edit svc cilium-gateway-<name>` to add the field; Cilium preserves it on reconcile.
- For Traefik (`hcm-traefik`) the Service is `traefik` in `kube-system` — edit it there.

### 2. Make the LB private-only (no public IP)

If a workload only needs to be reachable from other resources inside your Hetzner private network, give the LB no public IP at all. Skips public-side billing and removes the public attack surface entirely.

```yaml
metadata:
  annotations:
    load-balancer.hetzner.cloud/disable-public-network: "true"
    load-balancer.hetzner.cloud/location: <HETZNER_REGION>
    load-balancer.hetzner.cloud/network: <HETZNER_NETWORK_NAME_OR_ID>
```

The LB then has only a private IPv4 in your Hetzner network.

### 3. Firewall the cluster nodes (defense in depth)

Apply a Hetzner Cloud Firewall to the **server's public NIC** restricting inbound to only what you actually need from the Internet (e.g. SSH from trusted IPs, ICMP). All three variants bundle `HCLOUD_LOAD_BALANCERS_USE_PRIVATE_IP: "true"` in the CCM env, so the LB → node path rides the Hetzner private network — a tight public-NIC firewall will **not** mark LB targets Unhealthy. Without that flag you'd have to allowlist the Hetzner LB source ranges on the public NIC for health checks to pass — fragile and easy to get wrong.

If you also want to restrict LB → node traffic itself, put the rules on the server's **private NIC** firewall (Hetzner Cloud Firewalls can be scoped per-NIC).

## What can fail (and the fixes that are already baked in)

The cloud-configs are the way they are because each of these failure modes was hit during validation. Knowing them helps debug if you change values:

- **CCM crashloops with `ClusterCIDRMisconfigured`** → the chart default `networking.clusterCIDR` is `10.244.0.0/16` (vanilla k8s); k3s uses `10.42.0.0/16`. Already overridden in the CCM HelmChart values. **Do not change** unless you also change k3s's `--cluster-cidr`.
- **`kubectl logs/exec/top` fails with `x509: certificate is valid for ..., not <private-ip>`** → kubelet generates its cert before the CCM moves InternalIP to the private network. The `stages.boot` step writes `node-ip` to k3s config *before* k3s starts, so kubelet includes the private IP in its cert SAN from the first registration.
- **`Service type=LoadBalancer` stuck `<pending>`** → CCM doesn't know where to provision the Hetzner Cloud LB. All three variants set `HCLOUD_LOAD_BALANCERS_LOCATION` in CCM env (via the `<HETZNER_REGION>` placeholder). If you left the placeholder unsubstituted, the chart treats the literal string as an invalid location and the LB never provisions. Substitute it, or override per-Service with `load-balancer.hetzner.cloud/location: <region>`.
- **LB Service has `EXTERNAL-IP` but the Hetzner console shows targets `Unhealthy`** → LB health checks dial the targets via their **public** IP by default, which a tight Hetzner Cloud Firewall on the server's public NIC (or public-NIC quirks like RPF / asymmetric routing) often silently drops. All three variants set `HCLOUD_LOAD_BALANCERS_USE_PRIVATE_IP: "true"` in CCM env so probes ride the private network instead, same path as inter-node traffic. Don't unset it unless you know what you're doing.
- **Node has `<none>` InternalIP** → CCM didn't pick up `HCLOUD_NETWORK`. Confirm the `network:` field is present in the encoded secret AND `networking.enabled: true` is set in the CCM Helm values (`hcm-only.yaml` and `hcm-traefik.yaml`), or that `HCLOUD_NETWORK` is wired via the `env:` block in CCM values (`hcm-cilium.yaml`).
- **`Node ... not found in Hetzner` events on the CCM** → `hostname:` doesn't match the Hetzner server name. Fix by aligning them.

## Validation status

| File | Validated end-to-end on Hetzner Cloud |
|---|---|
| `hcm-only.yaml` | ✅ single-node cpx32 in `fsn1`, attached to private network — Node Ready, CCM stable, kubelet TLS path healthy, `Service type=LoadBalancer` provisions a Hetzner LB, `hcloud-csi` provisions a Hetzner Cloud Volume |
| `hcm-traefik.yaml` | ✅ same baseline as `hcm-only`, plus: Traefik Running, auto-generated `traefik-gateway` PROGRAMMED=True with Hetzner LB IP, `curl http://<lb-ip>/` flows Internet → LB → Traefik → HTTPRoute → backend pod (cross-namespace via `ReferenceGrant`), `hcloud-csi` PVC bound and read/write OK |
| `hcm-cilium.yaml` | ✅ same baseline as `hcm-only`, plus: Cilium agent + operator Running (`cilium status` OK), `cilium` GatewayClass ACCEPTED=True, user-created Gateway PROGRAMMED with Hetzner LB IP, `curl http://<lb-ip>/` flows Internet → LB → Cilium Envoy → HTTPRoute → backend pod, `hcloud-csi` PVC bound and read/write OK |

## Related

- [Kairos Hetzner installation docs](https://kairos.io/docs/installation/hetzner/) — full install flow including custom-ISO request, server creation, WebUI install, and the underlying `write_files`/`stages.boot` patterns these examples build on
- [Hetzner Cloud Controller Manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager) — upstream chart and CCM source
- [HCCM official deployment docs](https://github.com/hetznercloud/hcloud-cloud-controller-manager/tree/main/docs) — authoritative reference for env vars, deploy modes (with / without networks), and Service annotations
- [HCCM Helm chart values](https://github.com/hetznercloud/hcloud-cloud-controller-manager/tree/main/chart) — full list of supported `valuesContent` keys for the `HelmChart` manifest used here
- [hcloud-csi-driver](https://github.com/hetznercloud/csi-driver) — Hetzner Cloud Volume CSI driver bundled by all three variants (`hcloud-volumes` StorageClass)
- [Cilium k3s install guide](https://docs.cilium.io/en/stable/installation/k3s/) — generic Cilium-on-k3s reference (the `hcm-cilium.yaml` values are tuned for Hetzner private-network native routing on top of this)
