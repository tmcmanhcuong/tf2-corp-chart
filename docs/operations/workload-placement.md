# Workload Placement (Chart)

This chart implements **hard placement** between Critical MNG and Karpenter. Infrastructure labels, taints, NodePool weights, and capacity policy live in `techx-corp-infra` — see that repo’s `docs/workload-placement.md`.

## Placement contracts

| Contract | Mechanism | Workloads |
|----------|-----------|-----------|
| **Critical** | `nodeSelector.workload-class=critical`; **no** Karpenter toleration | `frontend-proxy`, `flagd`, `load-generator`, `postgresql`, `kafka`, `valkey-cart`, `opensearch`, `prometheus.server`, `grafana`, `jaeger.jaeger`, `metrics-server` |
| **Stateless (default)** | `nodeSelector.workload-class=spot-tolerant` + toleration `workload-class=spot-tolerant:NoSchedule` + preferred Spot affinity | All first-party Deployments that inherit `default.schedulingRules` (explicit: `frontend`, `product-catalog`, `recommendation`, and other classified demo apps) |
| **Universal DaemonSet** | No workload-class selector; Karpenter taint toleration | `opentelemetry-collector` (agent DaemonSet) |

### Important distinctions

* **`frontend`** is stateless → Karpenter.
* **`frontend-proxy`** is critical ingress/gateway → Critical MNG.
* Spot capacity-type affinity is a **preference only**. Primary vs On-Demand fallback is decided by **NodePool weight** in infra, not by chart affinity alone.
* Isolation is **one-way**: classified critical pods cannot land on Karpenter; classified stateless pods cannot land on MNG; **unclassified** pods without the Karpenter toleration can still schedule on MNG.

## Template behavior

`templates/_objects.tpl` merges `default.schedulingRules` with per-component `schedulingRules`. When a component sets a key (`nodeSelector`, `affinity`, or `tolerations`), that key **fully replaces** the default — including empty maps so critical workloads clear Spot affinity and Karpenter tolerations.

## Overlays

* **values-dev.yaml** / **values-prod.yaml** — image tags, ALB path blocking, secrets; critical/stateless contracts live in base `values.yaml`.

## Prerequisites

1. Critical MNG nodes labeled `workload-class=critical` (`system-*`, and legacy `general-*` during dual-run).
2. Karpenter NodePools label + taint `workload-class=spot-tolerant:NoSchedule`.
3. Universal DaemonSets (VPC CNI, kube-proxy, ebs-csi-node, OTel agent) tolerate the Karpenter taint **before** taint is applied.
4. Apply/sync **infra first**, then this chart.

## Rendered inventory validation

Validate **all** PodTemplates, not only Deployments:

```text
Deployment, StatefulSet, DaemonSet, Job, CronJob, Helm hooks, test Pods
```

```bash
helm lint . -f values.yaml -f values-dev.yaml
helm template test . -f values.yaml -f values-dev.yaml > /tmp/render-dev.yaml
helm template test . -f values.yaml -f values-prod.yaml > /tmp/render-prod.yaml
```

Expected matrix (selected):

| Kind | Workload | Contract | Selector | Karpenter toleration |
|------|----------|----------|----------|----------------------|
| Deployment | frontend | stateless | `spot-tolerant` | Yes |
| Deployment | load-generator | critical | `critical` | No |
| Deployment | frontend-proxy | critical | `critical` | No |
| StatefulSet | postgresql / kafka / … | critical | `critical` | No |
| DaemonSet | otel-collector-agent | universal | none | Yes |
| Deployment | prometheus / grafana / jaeger | critical | `critical` | No |

List any intentionally unclassified workload explicitly during acceptance review.

## Live verification

```bash
kubectl get nodes -L workload-class,karpenter.sh/capacity-type,role,karpenter.sh/nodepool
kubectl get pod -A -o wide

# Critical only on system-* (or labeled critical MNG during dual-run)
# Stateless only on Karpenter nodes (workload-class=spot-tolerant)
# OTel agent on both layers
```

## Canaries (runtime acceptance)

| Canary | Spec | Expected |
|--------|------|----------|
| A | No selector, no Karpenter toleration | Schedules on MNG |
| B | `nodeSelector.workload-class=spot-tolerant` without toleration | Pending |
| C | Selector spot-tolerant + capacity-type on-demand + toleration | Karpenter On-Demand node |

## Rollback (chart only)

1. Revert hard `nodeSelector` / tolerations to soft preferred affinity (prior soft-placement revision).
2. Keep critical STS pins if MNG remains healthy.
3. Do **not** downgrade Karpenter chart version from the application chart.

## Out of scope (follow-up)

* MNG taints / PriorityClass / PDB / topology spread / admission policy.
* Cluster Autoscaler for Critical MNG (scale-out is a reviewed Terraform `desired_size` change only).
