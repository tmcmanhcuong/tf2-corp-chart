# Change: Faster load-generator-worker HPA scale-down

## Summary

Speed up Horizontal Pod Autoscaler scale-in for **`load-generator-worker` only** so idle Locust workers (observed at ~5% CPU vs 70% target while still at max replicas) return to `minReplicas` within about one minute instead of many minutes.

## Context

Live HPA status showed:

```text
Deployment/load-generator-worker   cpu: 5%/70%   MIN=1  MAX=8  REPLICAS=8
```

Workers had scaled out under load, then stayed at 8 replicas long after CPU dropped because the worker HPA used a **300s** scale-down stabilization window and a **50% per 60s** policy. That was intentional earlier to reduce Locust master churn on Spot terminate, but it holds Karpenter capacity and delays cost recovery after load tests. Hot-path service HPA behavior is unchanged.

## Before

`components.load-generator-worker.autoscaling.behavior.scaleDown` in `values.yaml`:

* `stabilizationWindowSeconds: 300`
* policy: `Percent` value `50`, `periodSeconds: 60`
* No explicit `selectPolicy` on scaleDown

Rough path from 8 → 1 after metrics stay low: wait up to ~5 minutes, then 8→4→2→1 over successive 60s periods (~8+ minutes total).

## After

Worker-only scaleDown:

* `stabilizationWindowSeconds: 30`
* policy: `Percent` value `100`, `periodSeconds: 15`
* `selectPolicy: Max`

After ~30s of sustained under-target CPU, HPA may remove all excess replicas in a single policy window (down to `minReplicas: 1`). Scale-up behavior for this component is unchanged. Shared `*hpa-behavior-default` for commerce/proxy HPAs is unchanged.

## Technical Design Decisions

* **Scope:** only `load-generator-worker` — synthetic load pool, not customer traffic path.
* **Aggressive percent (100%)** over multi-step 50% — when Locust users drop, worker CPU collapses quickly; stepwise scale-in was the main cost/latency problem.
* **30s stabilize** (not 0) — still dampens single-metric blips without the previous 5-minute hold.
* **Kept 300s churn mitigation out of scope for reverse** — master now has HTTP probes / `LOCUST_EXPECT_WORKERS` / network policy; re-evaluate if worker disconnect storms return.
* Alternatives rejected: lowering `maxReplicas` only (does not fix slow scale-in from current peak); disabling HPA (loses auto scale-out under Locust).

## Implementation Details

1. Edited `components.load-generator-worker.autoscaling.behavior.scaleDown` in `values.yaml`.
2. Documented the policy in `docs/DEPLOYMENT.md` and `docs/operations/workload-placement.md`.
3. No template change — `templates/hpa.yaml` / `techx-corp.hpa` already pass through `autoscaling.behavior`.

## Files Changed

**Configuration:**

* `values.yaml` — Worker HPA scaleDown: 30s stabilize, 100% per 15s, `selectPolicy: Max`.

**Documentation:**

* `docs/DEPLOYMENT.md` — Locust worker HPA note includes fast scale-down.
* `docs/operations/workload-placement.md` — Worker HPA row notes scaleDown policy.
* `docs/changes/2026-07-14-load-generator-worker-fast-scale-down.md` — This change record.

## Dependencies and Cross-Repository Impact

None. Chart-only HPA behavior; platform Locust image and infra node pools unchanged.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Locust workers scale in faster when idle; master and other services unchanged |
| **Infrastructure** | Earlier release of Karpenter Spot capacity after load tests |
| **Deployment** | Helm/Argo sync updates `HorizontalPodAutoscaler/load-generator-worker` behavior only |
| **Performance** | No change to scale-up; load test peak capacity unchanged (max 8) |
| **Cost** | Lower residual worker cost when CPU is well below target |
| **Reliability** | Slightly higher chance of worker pod churn if CPU oscillates near target — mitigated by 30s window |
| **Backward compatibility** | Fully compatible; only HPA behavior field changes |
| **Observability** | No change |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values edit | Inspect `components.load-generator-worker.autoscaling.behavior.scaleDown` | ✅ 30s / 100% / 15s |
| Scope | Confirm other components still use `*hpa-behavior-default` or their own blocks | ✅ Unchanged |

### Manual Verification

After sync:

```cmd
kubectl -n techx-corp-prod get hpa load-generator-worker -o yaml
```

Expect `spec.behavior.scaleDown.stabilizationWindowSeconds: 30` and percent policy `100` / `15`.

```cmd
kubectl -n techx-corp-prod get hpa load-generator-worker
```

With idle workers (`cpu` well below `70%`), REPLICAS should move toward MIN within roughly one minute (Metrics Server lag may add a short delay).

### Remaining Verification (Post-Merge)

* Operator: Argo CD sync (or break-glass Helm upgrade) for the chart app.
* Confirm during/after next load test that scale-out still works and scale-in does not break Locust master worker list unacceptably.

## Migration or Deployment Notes

1. Merge/sync **techx-corp-chart** only.
2. No image rebuild.
3. Existing pods above desired count terminate per HPA scale-down after the new window — expect quicker drop from max toward min when load is low.

```cmd
REM After GitOps sync
kubectl -n techx-corp-prod get hpa load-generator-worker
kubectl -n techx-corp-prod get deploy load-generator-worker
```

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Worker flapping near CPU target | Low–Medium | Low | Raise stabilize to 60s or restore 50%/60s policy |
| Locust master sees mass disconnect on fast scale-in | Low | Medium | Master probes / expect-workers already hardened; raise stabilize if observed |
| Premature scale-in mid-ramp | Low | Low | Scale-up policies unchanged; Locust user ramp still drives CPU up |

**Rollback procedure:**

Restore previous scaleDown block in `values.yaml`:

```yaml
scaleDown:
  stabilizationWindowSeconds: 300
  policies:
    - type: Percent
      value: 50
      periodSeconds: 60
```

Re-sync the chart Application.

<!-- Change trail: @hungxqt - 2026-07-14 - Faster load-generator-worker HPA scale-down only. -->
