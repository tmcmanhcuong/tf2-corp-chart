# Change: Pin Locust Master to Critical MNG (System Nodes)

## Summary

Moved the Locust master (`load-generator`) from Karpenter Spot (`workload-class=spot-tolerant`) to the Critical managed node group (`workload-class=critical` / system nodes). Locust workers remain on Karpenter Spot and continue to generate load.

## Context

The Locust master is a lightweight control plane (web UI, worker coordination on port 5557, stats aggregation). Spot interruption or Karpenter consolidation of the master pod loses worker registrations and requires a coordinated restart. Pinning the master to stable On-Demand system MNG capacity keeps the control plane available while workers scale on interruptible capacity.

* Why now: distributed Locust is active in prod; master stability matters more than saving a small Spot footprint for a single low-resource pod.
* Placement contracts: `docs/operations/workload-placement.md` and infra `docs/workload-placement.md`.

## Before

* `components.load-generator.schedulingRules` used `*scheduling-spot-tolerant` (hard `nodeSelector: workload-class=spot-tolerant`, Karpenter toleration, preferred Spot affinity, soft topology spreads).
* Workers (`load-generator-worker`) also on spot-tolerant with storefront pod anti-affinity.
* Placement docs listed master under the stateless/Spot contract.

## After

* `components.load-generator.schedulingRules` uses `*scheduling-critical`:
  * `nodeSelector.workload-class=critical`
  * empty affinity and tolerations (no Karpenter taint tolerance)
  * `topologySpreadConstraints: []` (opt out of default soft spreads on the small MNG floor)
* Workers unchanged: still Karpenter Spot + anti-affinity.
* Workload placement docs and the distributed Locust migration note updated to match.

## Technical Design Decisions

* **Critical MNG for master only** — Master is fixed 0–1 replica and light on CPU/memory; safe on system nodes. Workers HPA up to 8 and generate HTTP load, so they must stay off Critical MNG.
* **Reuse `*scheduling-critical` anchor** — Same contract as `frontend-proxy`, `flagd`, stateful data; no new scheduling fragment.
* **No prod overlay override** — Base `values.yaml` change applies to all envs; `values-prod.yaml` only sets replicas/image.

## Implementation Details

1. Point `components.load-generator.schedulingRules` at `*scheduling-critical` in `values.yaml`.
2. Update comments to describe master on Critical MNG and workers on Spot.
3. Align `docs/operations/workload-placement.md` critical list, HPA table, and rendered inventory matrix.
4. Correct placement wording in `docs/changes/2026-07-14-distributed-load-generator.md`.

## Files Changed

**Configuration:**
* `values.yaml` — Locust master `schedulingRules: *scheduling-critical`.

**Documentation:**
* `docs/operations/workload-placement.md` — Critical vs worker contracts for Locust.
* `docs/DEPLOYMENT.md` — Locust distributed placement note.
* `docs/changes/2026-07-14-distributed-load-generator.md` — Master placement note.
* `docs/changes/2026-07-14-locust-master-critical-mng.md` — This change record.

## Dependencies and Cross-Repository Impact

* Depends on infra Critical MNG nodes labeled `workload-class=critical` (`system-*`).
* No platform image or infra Terraform change required.
* Workers still reach master via ClusterIP Service `load-generator:5557` (cross-node); NetworkPolicy already allows worker → master on 5557.

None for other repositories beyond existing placement prerequisites.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Locust master schedules only on Critical MNG; worker load generation unchanged |
| **Infrastructure** | One low-resource pod may land on system MNG when master replicas=1 |
| **Deployment** | Helm/Argo sync rolls master Deployment; reschedule onto system node |
| **Performance** | Negligible master CPU/memory on system nodes |
| **Reliability** | Master no longer interrupted by Spot reclaim; workers remain Spot-tolerant |
| **Cost** | Tiny On-Demand share on existing system MNG vs prior Spot master pod |
| **Backward compatibility** | Fully compatible; Service DNS and ports unchanged |
| **Observability** | No change |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Template placement | `helm template techx-corp . -f values.yaml -f values-prod.yaml` | Master Deployment `nodeSelector.workload-class: critical`; worker remains `spot-tolerant` |

### Manual Verification

* Inspect rendered `load-generator` Deployment for `workload-class: critical` and absence of Karpenter toleration.
* Inspect rendered `load-generator-worker` still has `spot-tolerant` selector + toleration.

### Remaining Verification (Post-Merge)

```cmd
kubectl get pod -n techx-corp-prod -l opentelemetry.io/name=load-generator -o wide
kubectl get node -L workload-class
```

Expect master pod NODE to be a `system-*` / `workload-class=critical` node when replicas=1. Confirm Locust UI workers still join after roll.

## Migration or Deployment Notes

1. Sync chart (Argo CD or break-glass Helm upgrade).
2. Ensure master `replicas: 1` if load testing is active (`values-prod.yaml` already sets this while testing).
3. After roll, verify master pod node label and worker connectivity to `load-generator:5557`.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Critical MNG capacity pressure | Low | Medium | Master requests are small (10m/64Mi); scale master to 0 when idle |
| Master Pending if critical labels missing | Low | High | Confirm system MNG labels before sync; temporary revert to spot-tolerant |

**Rollback procedure:**

Set `components.load-generator.schedulingRules` back to `*scheduling-spot-tolerant` in `values.yaml`, re-sync chart, confirm pod lands on Karpenter.

<!-- Change trail: @hungxqt - 2026-07-14 - Pin Locust master to Critical MNG (system nodes). -->
