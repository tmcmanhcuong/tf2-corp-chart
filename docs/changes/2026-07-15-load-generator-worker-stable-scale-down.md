# Change: Restore stable load-generator-worker HPA scale-down

## Summary

Restored the slower Horizontal Pod Autoscaler scale-in policy for **`load-generator-worker` only** (300s stabilization, 50% per 60s) so Locust workers no longer thrash 1↔2 after brief CPU spikes. Reverses the aggressive 30s / 100% per 15s behavior introduced for faster Spot reclaim.

## Context

Live prod showed repeated HPA rescales within about one minute:

```text
New size: 2; reason: cpu resource utilization (percentage of request) above target
New size: 1; reason: All metrics below target
```

Locust distributes a fixed `LOCUST_USERS` count across workers. Scale-out lowers per-worker CPU; with a 30s / 100% scale-down window the HPA immediately scaled back in, disconnecting workers from the master and degrading load tests. The prior fast scale-down change (`docs/changes/2026-07-14-load-generator-worker-fast-scale-down.md`) optimized residual Spot cost after idle peaks but caused unacceptable worker churn under normal autostart traffic.

* Related prior work: `docs/changes/2026-07-14-load-generator-worker-fast-scale-down.md`, `docs/changes/2026-07-14-fix-locust-master-worker-discovery.md`

## Before

`components.load-generator-worker.autoscaling.behavior.scaleDown` in `values.yaml`:

* `stabilizationWindowSeconds: 30`
* policy: `Percent` value `100`, `periodSeconds: 15`
* `selectPolicy: Max`

Rough path after a brief CPU blip: 1→2 within 15s, then 2→1 after ~30s of below-target metrics.

## After

Worker-only scaleDown:

* `stabilizationWindowSeconds: 300`
* policy: `Percent` value `50`, `periodSeconds: 60`
* `selectPolicy: Max`

Scale-up behavior unchanged (0s stabilize, +2 pods or +100% per 15s). Shared `*hpa-behavior-default` for commerce/proxy HPAs unchanged. Karpenter `consolidateAfter` / Underutilized eviction is out of scope for this chart change.

## Technical Design Decisions

* **Restore prior churn mitigation** rather than disable HPA — still allows scale-out under sustained Locust CPU pressure.
* **50% / 60s** stepwise scale-in over 100% dump — avoids mass worker disconnect when load eases.
* **300s stabilize** — matches the earlier Locust master/worker hardening intent; accepts slower Spot reclaim after tests.
* Alternatives rejected for this slice: disable worker HPA entirely (loses auto scale-out); raise CPU target only (does not stop fast reverse scale-in after rebalance).

## Implementation Details

1. Edited `components.load-generator-worker.autoscaling.behavior.scaleDown` in `values.yaml`.
2. Updated operator docs that advertised the fast scale-down policy.
3. No template change — `templates/hpa.yaml` / `techx-corp.hpa` already pass through `autoscaling.behavior`.

## Files Changed

**Configuration:**

* `values.yaml` — Worker HPA scaleDown: 300s stabilize, 50% per 60s, `selectPolicy: Max`.

**Documentation:**

* `docs/DEPLOYMENT.md` — Locust worker HPA note uses stable scale-down values.
* `docs/operations/workload-placement.md` — Worker HPA row notes 300s / 50% scale-in.
* `docs/changes/2026-07-15-load-generator-worker-stable-scale-down.md` — This change record.

## Dependencies and Cross-Repository Impact

None. Chart-only HPA behavior; platform Locust image and infra Karpenter NodePools unchanged. Residual worker loss from Karpenter `WhenEmptyOrUnderutilized` / `consolidateAfter: 1m` may still occur and is a separate infra follow-up.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Locust workers stay registered longer after scale-out; fewer 1↔2 flaps |
| **Infrastructure** | Idle workers may hold Spot capacity up to ~5+ minutes after CPU drops |
| **Deployment** | Helm/Argo sync updates `HorizontalPodAutoscaler/load-generator-worker` behavior only |
| **Performance** | No change to scale-up or max replicas (8) |
| **Cost** | Slightly higher residual worker cost after load drops vs 30s/100% policy |
| **Reliability** | Lower worker disconnect thrash during autostart / modest user counts |
| **Backward compatibility** | Fully compatible; only HPA behavior field changes |
| **Observability** | No change |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values edit | Inspect `components.load-generator-worker.autoscaling.behavior.scaleDown` | ✅ 300s / 50% / 60s |
| Scope | Confirm other components still use `*hpa-behavior-default` or their own blocks | ✅ Unchanged |

### Manual Verification

After sync:

```cmd
kubectl -n techx-corp-prod get hpa load-generator-worker -o yaml
```

Expect `spec.behavior.scaleDown.stabilizationWindowSeconds: 300` and percent policy `50` / `60`.

```cmd
kubectl -n techx-corp-prod describe hpa load-generator-worker
```

Under brief CPU spikes, desired replicas should not reverse 2→1 within the same minute solely due to rebalance.

### Remaining Verification (Post-Merge)

* Operator: Argo CD sync for the chart app.
* Confirm during next load test that scale-out still works and 1↔2 thrash is reduced.
* Optional follow-up: Karpenter consolidation / fixed worker pool for intentional tests.

## Migration or Deployment Notes

1. Merge/sync **techx-corp-chart** only.
2. No image rebuild.
3. Existing HPA object updates behavior in place after GitOps sync.

```cmd
REM After GitOps sync
kubectl -n techx-corp-prod get hpa load-generator-worker -o jsonpath="{.spec.behavior.scaleDown}"
kubectl -n techx-corp-prod describe hpa load-generator-worker
```

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Idle workers hold Spot longer after tests | Medium | Low | Scale workers to 0 when tests stop; or re-enable faster scale-down later |
| Sustained over-capacity after long spike | Low | Low | Scale-up still works; max 8 unchanged |

**Rollback procedure:**

Restore the aggressive scaleDown block in `values.yaml`:

```yaml
scaleDown:
  stabilizationWindowSeconds: 30
  policies:
    - type: Percent
      value: 100
      periodSeconds: 15
  selectPolicy: Max
```

Re-sync the chart Application.

<!-- Change trail: @hungxqt - 2026-07-15 - Restore load-generator-worker HPA stable scale-down. -->
