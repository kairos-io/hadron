#!/bin/sh
# Best-effort Kubernetes diagnostics collector.
#
# Run on a Kairos node by tests/tests_suite_test.go gatherLogs() ONLY when a
# test fails, to dump cluster state for debugging. This is busybox/POSIX sh
# (NOT bash) and must never hard-fail: every command is guarded so missing
# k3s/kubectl/crictl/systemctl is tolerated. All output goes to stdout.

# Print a clear banner before each section.
banner() {
    echo
    echo "===== $* ====="
}

# Detect a usable kubectl. k3s bundles it as "k3s kubectl"; fall back to a
# standalone kubectl. KUBECTL is left empty if neither is available.
KUBECTL=""
if command -v k3s >/dev/null 2>&1; then
    KUBECTL="k3s kubectl"
elif command -v kubectl >/dev/null 2>&1; then
    KUBECTL="kubectl"
fi

if [ -z "$KUBECTL" ]; then
    banner "kubectl not found (no k3s/kubectl), skipping cluster diagnostics"
else
    banner "NODES"
    $KUBECTL get nodes -o wide 2>&1 || true

    banner "PODS (all namespaces)"
    $KUBECTL get pods -A -o wide 2>&1 || true

    banner "EVENTS (all namespaces)"
    $KUBECTL get events -A 2>&1 || true

    # For any pod not in a healthy terminal/running state, dump describe and
    # logs (both previous and current containers) to help diagnose the failure.
    banner "UNHEALTHY POD DETAILS"
    $KUBECTL get pods -A --no-headers 2>/dev/null | while read -r ns name ready status rest; do
        case "$status" in
            Running|Completed|Succeeded)
                ;;
            *)
                echo
                echo "--- describe $ns/$name (status=$status) ---"
                $KUBECTL describe pod "$name" -n "$ns" 2>&1 || true
                echo "--- previous logs $ns/$name ---"
                $KUBECTL logs "$name" -n "$ns" --all-containers --previous 2>&1 || true
                echo "--- current logs $ns/$name ---"
                $KUBECTL logs "$name" -n "$ns" --all-containers 2>&1 || true
                ;;
        esac
    done
fi

# Containerd / CRI level info, independent of the kube API being reachable.
if command -v crictl >/dev/null 2>&1; then
    banner "CRICTL PS -A"
    crictl ps -a 2>&1 || true

    banner "CRICTL IMAGES"
    crictl images 2>&1 || true
else
    banner "crictl not found, skipping CRI diagnostics"
fi

# Kubelet / k3s service health and recent journal lines.
if command -v systemctl >/dev/null 2>&1; then
    banner "SYSTEMCTL STATUS k3s"
    systemctl status k3s 2>&1 || true
else
    banner "systemctl not found, skipping service status"
fi

if command -v journalctl >/dev/null 2>&1; then
    banner "JOURNAL k3s (last 500 lines)"
    journalctl -u k3s --no-pager -n 500 2>&1 || true
else
    banner "journalctl not found, skipping journal dump"
fi
