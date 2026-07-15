# Change: Remove Memory Metric from All HPA Targets

## Summary

Removed `targetMemoryUtilizationPercentage` from every HorizontalPodAutoscaler-enabled component in base `values.yaml`. HPAs now scale on CPU and (where configured) RPS only. Chart version bumped to `0.48.2`.

## Context

Memory utilization as an HPA signal often thrashs or dominates max-of-metrics for runtimes with steady RSS (Go, .NET, Node, Locust). Prior work already dropped memory from `load-generator-worker` for that reason. Operators requested removal of memory scale metrics from all remaining HPAs so replica count tracks load (RPS/CPU) rather than heap occupancy near request.

* Related prior work: `docs/changes/2026-07-11-hpa-memory-safety-valve.md`, `docs/changes/2026-07-12-request-metric-hpa.md`, `docs/changes/2026-07-14-load-generator-worker-fast-scale-down.md`.
* Hard OOM protection stays on container `limits` and runtime caps (e.g. `GOMEMLIMIT`); HPA is not the OOM path.

## Before

Ten services emitted a Resource memory metric at **90%** averageUtilization (in addition to CPU and optional RPS):

| Service | Prior metrics |
|---|---|
| `cart`, `checkout`, `currency`, `product-catalog`, `product-reviews`, `recommendation` | CPU + Mem 90% + RPS |
| `frontend`, `frontend-proxy` | CPU 80% + Mem 90% + RPS |
| `quote`, `shipping` | CPU + Mem 90% |
| `load-generator-worker` | CPU only (already no memory) |

## After

| Service | Metrics |
|---|---|
| Request-path HPAs (8) | CPU + RPS (unchanged targets) |
| `quote`, `shipping` | CPU 70% only |
| `load-generator-worker` | CPU only (unchanged) |

No service sets `targetMemoryUtilizationPercentage` in base values. Template/schema still accept the field if re-enabled later.

## Technical Design Decisions

* **Values-only removal** — `techx-corp.hpa` already gates memory on presence of `targetMemoryUtilizationPercentage`; no template API change.
* **Keep schema/template support** — optional re-enable without chart code churn.
* **Do not lower memory requests/limits** — those remain capacity and OOM bounds; only the scale signal is removed.
* **Patch chart version `0.48.2`** — configuration policy change, not a new feature.

Alternatives rejected: leave memory at 90% (continues max-of-metrics noise); raise memory target further (still can dominate under steady RSS).

## Implementation Details

1. Removed all `targetMemoryUtilizationPercentage: 90` entries from `values.yaml` (10 components).
2. Updated inline HPA comments from triple/CPU+mem wording to RPS+CPU (or CPU-only).
3. Updated ops inventory: `docs/operations/request-metric-hpa.md`, `docs/DEPLOYMENT.md` HPA policy and tables.
4. Bumped `Chart.yaml` version to `0.48.2`.

## Files Changed

**Configuration:**
* `values.yaml` — Removed memory HPA targets; adjusted comments.
* `Chart.yaml` — Version `0.48.1` → `0.48.2`.

**Documentation:**
* `docs/operations/request-metric-hpa.md` — Dual-metric (RPS+CPU) inventory; memory optional only.
* `docs/DEPLOYMENT.md` — Metric policy, HPA table, verification expectations without memory targets.
* `docs/changes/2026-07-15-remove-hpa-memory-metrics.md` — This change record.

## Dependencies and Cross-Repository Impact

None. No platform image or infra Terraform change. Argo CD reconciling `techx-corp-chart` will update HPA specs after this chart version is synced.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Pods no longer scale out solely because average memory working set ≥ 90% of request |
| **Infrastructure** | Possible lower average replica count under memory-pressure-without-CPU/RPS load |
| **Deployment** | Argo CD / Helm sync applies new HPA metric lists; no recreate of Deployments required |
| **Performance** | Scale tracks RPS/CPU; memory-bound saturation relies on limits/OOM and operator request right-sizing |
| **Security** | No change |
| **Reliability** | Removes memory-driven scale thrash; OOM still hard-fails at limit |
| **Cost** | May reduce unnecessary replicas driven by steady RSS near request |
| **Backward compatibility** | Fully compatible for clients; HPA STATUS targets drop `memory` |
| **Observability** | `kubectl describe hpa` TARGETS show cpu and external only (where configured) |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| No memory HPA targets in values | search `targetMemoryUtilizationPercentage` in `values.yaml` | ✅ Zero matches |
| Template still optional | `techx-corp.hpa` emits memory only when key set | ✅ Unchanged gate |

### Manual Verification

* Confirm rendered HPAs omit Resource memory metrics:

```cmd
cd /d techx-corp-chart
helm template techx-corp . -n techx-corp ^
  -f values.yaml -f values-public-alb.yaml -f values-prod.yaml ^
  | findstr /i "name: memory averageUtilization"
```

Expect CPU `averageUtilization` lines only (no `name: memory` under HPA metrics).

### Remaining Verification (Post-Merge)

1. After Argo sync: `kubectl -n <ns> get hpa` and `describe hpa` — TARGETS without memory.
2. Under load, confirm scale still responds to CPU and RPS.
3. Watch for OOMKilled on right-sized services; raise requests/limits if needed (do not re-add memory HPA without reviewing thrash history).

## Migration or Deployment Notes

1. Merge chart change; allow Argo CD auto-sync (or sync Application).
2. No secret or image tag change required.
3. Optional break-glass check: `kubectl get hpa -A` TARGETS column.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Memory-bound service saturates without scale-out | Low–Medium | Medium | Raise requests/limits; re-enable `targetMemoryUtilizationPercentage` if operators accept thrash trade-off |
| Operators expect memory in TARGETS | Low | Low | Docs updated; describe is source of truth |

**Rollback procedure:**

1. Restore `targetMemoryUtilizationPercentage: 90` on desired components (see `docs/changes/2026-07-11-hpa-memory-safety-valve.md` for prior Option B).
2. Revert this commit or chart version and re-sync Argo CD.

<!-- Change trail: @hungxqt - 2026-07-15 - Remove all HPA memory metric scale targets. -->
