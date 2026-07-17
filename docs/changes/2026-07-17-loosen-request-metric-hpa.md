# Change: Loosen Request-Metric HPA

## Summary

Raised per-pod RPS targets for all request-metric HPAs and dampened the shared HPA scale-up/scale-down behavior so short traffic or metric noise no longer drives aggressive replica churn. Chart version **0.48.9**. Production frontend RPS override aligned to the new base target (80).

## Context

Request-rate HPA was scaling out too eagerly: External RPS targets were still on the conservative side of early tuning, and shared behavior used **0s** scale-up stabilization with **+100% every 15s** and only **60s** scale-down stabilization. That combination over-provisions under bursty Locust/browse traffic and spanmetrics-inflated frontend RPS, even when CPU remains well under target.

Ops guidance already says to raise RPS targets when flapping; this change applies that across the hot path and softens the shared policy.

## Before

**RPS/pod targets (base `values.yaml`):**

| Service | RPS/pod |
|---|---:|
| `frontend-proxy` | 200 |
| `frontend` | 50 (prod override **40**) |
| `product-catalog` | 100 |
| `cart` | 100 |
| `currency` | 150 |
| `checkout` | 30 |
| `recommendation` | 15 |
| `product-reviews` | 10 |

**Shared `hpa-behavior-default`:**

* scaleUp: stabilize **0s**, +2 pods or **+100%** per **15s**
* scaleDown: stabilize **60s**, 50% per 60s

CPU targets and maxReplicas unchanged.

## After

**RPS/pod targets:**

| Service | RPS/pod |
|---|---:|
| `frontend-proxy` | **300** |
| `frontend` | **80** (prod override **80**) |
| `product-catalog` | **150** |
| `cart` | **150** |
| `currency` | **250** |
| `checkout` | **50** |
| `recommendation` | **25** |
| `product-reviews` | **20** |

**Shared `hpa-behavior-default`:**

* scaleUp: stabilize **30s**, +2 pods or **+50%** per **30s**
* scaleDown: stabilize **120s**, 50% per 60s

CPU remains the safety valve (70% / 80% frontend & proxy; prod frontend still 65%). `load-generator-worker` keeps its own CPU-only behavior (unchanged).

## Technical Design Decisions

* **Raise RPS first** — primary lever for “too aggressive” request-based scale-out; desired replicas ≈ total RPS ÷ target RPS/pod.
* **Damp scale-up, not remove RPS** — keep External metrics so I/O-bound services (e.g. `currency`) still scale before CPU hits 70%; only slow the reaction.
* **Longer scale-down stabilize (120s)** — reduces thrash when rate windows and adapter lag bounce around the target; not as long as the old 300s commerce window.
* **Align prod frontend to 80** — prod’s previous 40 RPS/pod was already a loosen vs earlier over-scale; base raise to 80 needs the same floor or prod would stay more aggressive than base.
* **Rejected:** disable `prometheus-adapter` / drop RPS metrics entirely — would reintroduce CPU-only blind spot on low-CPU high-RPS paths.
* **Rejected:** lower maxReplicas — does not fix early scale-out; only caps the worst case.

## Implementation Details

1. Updated all `components.*.autoscaling.targetRequestsPerSecond` values listed above in `values.yaml`.
2. Rewrote `&hpa-behavior-default` (cart anchor, aliased by other request-path HPAs).
3. Raised `values-prod.yaml` `components.frontend.autoscaling.targetRequestsPerSecond` from 40 → 80.
4. Bumped chart version to `0.48.9`.
5. Aligned ops inventory tables in `request-metric-hpa.md` and `DEPLOYMENT.md`.

## Files Changed

**Configuration:**

* `values.yaml` — Higher RPS targets; dampened shared HPA behavior.
* `values-prod.yaml` — Frontend RPS target 80.
* `Chart.yaml` — version `0.48.8` → `0.48.9`.

**Documentation:**

* `docs/operations/request-metric-hpa.md` — Service RPS table and behavior notes.
* `docs/DEPLOYMENT.md` — Production HPA inventory RPS values and behavior line.
* `docs/changes/2026-07-17-loosen-request-metric-hpa.md` — This change record.

## Dependencies and Cross-Repository Impact

None. No platform or infra change. After Argo sync, HPA objects pick up new targets and behavior; no Prometheus Adapter rule change.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Same services remain dual-metric (RPS + CPU); scale-out starts later and ramps slower |
| **Infrastructure** | Fewer Karpenter Spot nodes under moderate load; Critical MNG less pressured by early `frontend-proxy` scale-out |
| **Deployment** | Chart sync only (GitOps) |
| **Performance** | Slightly higher per-pod RPS before scale-out; CPU safety valve still protects compute-bound paths |
| **Reliability** | Less replica thrash; possible slower response to true RPS spikes (mitigated by 30s stabilize + CPU metric) |
| **Cost** | Lower peak pod count under the same moderate traffic |
| **Backward compatibility** | Fully compatible; operators can retune RPS targets per service |
| **Observability** | No change to metric pipeline |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Helm lint (dev) | `helm lint . -f values.yaml -f values-dev.yaml` | (run after edit) |
| Helm lint (prod) | `helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml` | (run after edit) |
| Template HPA | `helm template` inspect External averageValue + behavior | (run after edit) |

### Manual Verification

* Confirm rendered HPA External `averageValue` matches new RPS targets.
* Confirm `spec.behavior.scaleUp.stabilizationWindowSeconds: 30` and scaleDown `120`.

### Remaining Verification (Post-Merge)

1. Argo sync chart release.
2. `kubectl describe hpa` on hot-path services — External targets and behavior updated.
3. Under moderate Locust load, confirm replica counts stay nearer min when CPU is healthy; under heavy load, confirm CPU and/or RPS still scale out before latency collapse.

## Migration or Deployment Notes

1. Merge and push `techx-corp-chart` (GitOps source of truth).
2. Allow Argo CD auto-sync; do **not** `helm upgrade` directly against managed releases.
3. No adapter restart required unless targets appear stale (HPA controller reads new Spec immediately).

```cmd
cd /d techx-corp-chart
helm lint . -f values.yaml -f values-dev.yaml
helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml
helm template techx-corp . -n techx-corp-prod ^
  -f values.yaml -f values-public-alb.yaml -f values-prod.yaml > %TEMP%\render-hpa.yaml
```

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Scale-out too slow under sudden spike | Medium | Medium | CPU metric still scales; lower individual RPS targets if latency rises first |
| Latency climbs before RPS threshold | Low | Medium | Lower `targetRequestsPerSecond` for the affected service only |
| Under-capacity on frontend spanmetrics path | Low | Medium | Prod already uses 80 with minReplicas 3; watch P95 |

**Rollback procedure:**

1. Revert this chart commit (or restore previous RPS targets and behavior in `values.yaml` / `values-prod.yaml`).
2. Bump chart version and let Argo sync.

<!-- Change trail: @hungxqt - 2026-07-17 - Loosen request-metric HPA RPS targets and scale behavior. -->
