# GPU Operator on Hadron Thor (T264)

Deploy NVIDIA GPU Operator on a Hadron Thor node so pods can request
`nvidia.com/gpu` resources and run CUDA workloads. The image built from
`Dockerfile.Thor` ships everything needed on the host side (kernel + OOT
modules + glibc runtime + nvidia-container-toolkit 1.18.1 + CSV files
from `nvidia-l4t-init` + `nvidia-cdi-refresh.service`). What follows is
the cluster-side setup.

## Prerequisites

- Node booted from `Dockerfile.Thor` image
- `nvidia-smi` works on host (`sudo nvidia-smi` shows `NVIDIA Thor`)
- k3s installed with NVIDIA runtime configured (containerd CDI enabled)
- `helm` available

## Why version pinning matters

The host ships `nvidia-ctk` 1.18.1 (latest in NVIDIA's r38.4 jetson apt
repo). The device-plugin in its container generates a CDI spec referencing
`nvidia-ctk hook ...` invocations that must match the host binary's flag
set.

| Component                | Version | Source                        |
|--------------------------|---------|-------------------------------|
| Host nvidia-ctk          | 1.18.1  | r38.4 jetson repo (`.deb`)    |
| device-plugin container  | v0.18.1 | gpu-operator helm chart       |
| nvidia-ctk inside plugin | 1.18.1  | bundled in plugin image       |

`gpu-operator v25.10.x` ships `device-plugin v0.18.x` → matches.
`gpu-operator v26.x` ships `device-plugin v0.19.x` → mismatches host
(`-host-cuda-version` flag introduced in 1.19) → CDI hook execution fails
with `flag provided but not defined: -host-cuda-version`.

**Use `v25.10.1`.** Do not use `v26.x` until NVIDIA bumps the jetson repo
to nvidia-container-toolkit 1.19+.

## Install

```bash
helm repo add nvidia https://nvidia.github.io/gpu-operator
helm repo update nvidia

cat > /tmp/gpu-operator-values.yaml <<'EOF'
# Host already ships nvidia-container-toolkit (deb from r38.4 jetson repo).
toolkit:
  enabled: false

# Tegra OOT driver is built into the kernel, not deployed by the operator.
driver:
  enabled: false

# Tegra single-GPU pure-CSV path: when only one GPU is present, the device-plugin
# falls back to "pure CSV" device-spec generation with an empty UUID. The
# default UUID-based namer then returns "" → "no names defined" → pod start
# error. Override to index naming.
devicePlugin:
  env:
    - name: DEVICE_ID_STRATEGY
      value: index
EOF

helm upgrade --install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --version v25.10.1 \
  -f /tmp/gpu-operator-values.yaml
```

## Post-install daemonset patch

The device-plugin container needs to read the host CSV files at
`/etc/nvidia-container-runtime/host-files-for-container.d/` (drivers.csv,
devices.csv, l4t.csv). The chart doesn't expose `extraVolumes` /
`extraVolumeMounts` on `devicePlugin`, and the controller resets
`NVIDIA_DRIVER_ROOT=/`, so the alternative of pointing driver-root at the
existing `/host` mount doesn't survive reconciliation.

Bind-mount the CSV directory into the plugin container directly:

```bash
kubectl patch daemonset nvidia-device-plugin-daemonset -n gpu-operator --type=json -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"nv-csv","hostPath":{"path":"/etc/nvidia-container-runtime/host-files-for-container.d"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"nv-csv","mountPath":"/etc/nvidia-container-runtime/host-files-for-container.d","readOnly":true}}
]'
```

The patch persists across plugin pod restarts but **is reverted if you
`helm upgrade` the chart**. Re-apply after upgrades.

## Verify

```bash
# Wait for the device-plugin pod to become Ready
kubectl get pod -n gpu-operator -l app=nvidia-device-plugin-daemonset -w

# GPU resource registered with kubelet
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'
# Expected: <node-name>    1

# Quick describe view
kubectl describe node | grep "nvidia.com/gpu"
```

## Smoke-test pod

```yaml
# /tmp/gpu-smi.yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-smi
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  containers:
  - name: smi
    image: ubuntu:24.04
    command: ["bash", "-c", "nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
```

```bash
kubectl apply -f /tmp/gpu-smi.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/gpu-smi --timeout=2m
kubectl logs gpu-smi
```

Expected:

```
NVIDIA-SMI 580.00     Driver Version: 580.00     CUDA Version: 13.0
0  NVIDIA Thor    Off  |   00000000:01:00.0 Off
```

## Optional: gpu-operator-free path

The image enables `nvidia-cdi-refresh.service`, which auto-runs
`nvidia-ctk cdi generate` at boot and writes `/var/run/cdi/nvidia.yaml`.
For workloads that don't need k8s scheduling on `nvidia.com/gpu`, you can
skip the device-plugin entirely and use a pod with `runtimeClassName:
nvidia` + `NVIDIA_VISIBLE_DEVICES=all`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-direct
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  containers:
  - name: smi
    image: ubuntu:24.04
    command: ["bash", "-c", "nvidia-smi"]
    env:
    - name: NVIDIA_VISIBLE_DEVICES
      value: all
    - name: NVIDIA_DRIVER_CAPABILITIES
      value: all
```

This bypasses the device-plugin entirely. Useful for one-off jobs or
when you don't want gpu-operator overhead. Caveat: kube-scheduler has no
visibility into GPU consumption, so co-tenancy isn't enforced.

## Known issues

- `nvidia-dcgm-exporter` crashloops: DCGM doesn't support Tegra. Disable
  via helm `dcgmExporter.enabled=false` if the noise bothers you.
- `gpu-feature-discovery` reports `nvidia.com/gpu.family=undefined` and
  `nvidia.com/gpu.mode=unknown`. Cosmetic. NVML on Tegra returns
  `Not Supported` for several queries.
- gpu-operator's official platform-support page states Jetson is not
  supported. The recipe above works because Thor's PCIe-attached GPU is
  close enough to a discrete GPU shape that the device-plugin's pure-CSV
  fallback functions once the namer + CSV mount are corrected.
