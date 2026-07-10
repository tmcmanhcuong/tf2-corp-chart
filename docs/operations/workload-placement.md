# Workload Placement (Chart)

This chart implements **soft** scheduling for critical vs Spot-tolerant workloads. Infrastructure labels and capacity policy live in `techx-corp-infra` — see that repo’s `docs/workload-placement.md`.

## Rules applied in this chart

| Class | Mechanism | Components |
|-------|-----------|------------|
| **Critical** | `nodeSelector.workload-class=critical` | `postgresql`, `kafka`, `valkey-cart`, `opensearch` |
| **Critical (prod edge)** | Same selector via `values-prod.yaml` | `frontend-proxy`, `flagd` |
| **Spot-tolerant (default)** | Preferred affinity for `karpenter.sh/capacity-type=spot` and `workload-class=spot-tolerant` | All other demo Deployments |
| **System (subchart)** | `metrics-server.nodeSelector` | metrics-server |

DaemonSets (`opentelemetry-collector` agent mode) schedule on **all** nodes and are not pinned.

## Template behavior

`templates/_objects.tpl` merges `default.schedulingRules` with per-component `schedulingRules`. When a component sets a key (`nodeSelector`, `affinity`, or `tolerations`), that key **fully replaces** the default — including empty maps so critical STS can clear Spot affinity.

## Overlays

* **values-dev.yaml** — frontend-proxy stays on default Spot prefer (debug-friendly).
* **values-prod.yaml** — pins frontend-proxy and flagd to critical MNG.

## Prerequisites

1. Cluster MNG nodes labeled `workload-class=critical` (Terraform).
2. Karpenter nodes labeled `workload-class=spot-tolerant` (NodePool template).
3. Apply/sync **infra first**, then this chart, so critical pods do not stay Pending.

## Verification

```bash
kubectl get nodes -L workload-class,karpenter.sh/capacity-type
kubectl get sts,deploy -o wide
# Critical STS should land on MNG (no karpenter.sh/nodepool on the node)
kubectl get pod postgresql-0 -o wide
```

## Phase 2 (not enabled)

Hard MNG taints require matching **tolerations** on critical pods and DaemonSets before enabling taints in Terraform. Do not enable taints from the chart alone.
