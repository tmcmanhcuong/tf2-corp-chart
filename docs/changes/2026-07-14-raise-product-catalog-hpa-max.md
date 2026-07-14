# Change: Raise product-catalog HPA maxReplicas (6 → 12)

## Summary

Raised `components.product-catalog.autoscaling.maxReplicas` from **6** to **12** so HPA can scale out under load when CPU stays above target at the previous ceiling. Chart version **0.46.0**. Ops HPA inventory tables updated (including min/RPS drift fixes for this service).

## Context

Live HPA snapshot:

```text
product-catalog   Deployment/product-catalog
  cpu: 126%/70%, memory: 60%/90% + 1 more...
  MIN=2  MAX=6  REPLICAS=6
```

The Deployment was pinned at max while CPU utilization vs the 70% target still called for more pods. Same pattern as prior load-test max raises (`docs/changes/2026-07-14-raise-hpa-max-replicas-load-test.md`, round-2).

Desired-replica estimate: `currentReplicas × (currentCPU% / targetCPU%)` = `6 × 126/70 ≈ 10.8`, then modest headroom → **12**.

## Before

| Field | Value |
|---|---:|
| `maxReplicas` | 6 |
| Chart version | 0.45.0 |
| Docs inventory | Some tables still showed min 1 / max 6 / RPS 30 |

## After

| Field | Value |
|---|---:|
| `maxReplicas` | **12** |
| Chart version | **0.46.0** |
| Docs inventory | min **2** / max **12** / RPS **100** (matches `values.yaml`) |

`minReplicas`, CPU/memory/RPS targets, and shared HPA behavior are unchanged.

## Technical Design Decisions

* **Same formula as prior max raises** — CPU-implied desired + small headroom (not a multi-step partial bump).
* **12 not 20+** — utilization pin was moderate (126%/70%), not currency-class (412%/70%).
* **Do not raise CPU request here** — unblocking HPA is the immediate fix; request right-sizing is a separate PER-01-style change if needed.
* **Docs sync** — inventory rows for product-catalog still listed stale min 1 and RPS 30; corrected while updating max.

## Implementation Details

1. Set `components.product-catalog.autoscaling.maxReplicas: 12` with inline math comment in `values.yaml`.
2. Bumped `Chart.yaml` to `0.46.0`.
3. Updated HPA tables in `docs/DEPLOYMENT.md` and `docs/operations/request-metric-hpa.md`.

## Files Changed

**Configuration:**

* `values.yaml` — product-catalog `maxReplicas` 6 → 12.
* `Chart.yaml` — version `0.45.0` → `0.46.0`.

**Documentation:**

* `docs/DEPLOYMENT.md` — HPA inventory row + min-replicas note for product-catalog.
* `docs/operations/request-metric-hpa.md` — service table min/max/RPS for product-catalog.
* `docs/changes/2026-07-14-raise-product-catalog-hpa-max.md` — this change record.

## Dependencies and Cross-Repository Impact

* **Karpenter** (`techx-corp-infra`): up to 6 additional spot-tolerant pods at peak vs previous max.
* No `techx-corp-platform` change.
* PostgreSQL: more catalog pods share the same DB; watch connection count under sustained max load.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Unblocks product-catalog scale-out beyond 6 when CPU/RPS demand more |
| **Infrastructure** | Possible extra Karpenter Spot capacity under load |
| **Deployment** | Helm/Argo sync updates `HorizontalPodAutoscaler/product-catalog` max only |
| **Performance** | Better headroom when browse/catalog path is CPU-bound |
| **Cost** | Higher peak only under load; scale-down policy unchanged (default 60s stabilize) |
| **Reliability** | Reduces prolonged high CPU per pod when previously pinned at max |
| **Backward compatibility** | Fully compatible |
| **Observability** | No change |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values | Inspect `components.product-catalog.autoscaling.maxReplicas` | ✅ 12 |
| Chart version | `Chart.yaml` | ✅ 0.46.0 |

### Manual Verification

After sync:

```cmd
kubectl -n techx-corp-prod get hpa product-catalog
```

Expect MAXPODS **12**. Under the same load, REPLICAS should rise above 6 if CPU stays over target.

### Remaining Verification (Post-Merge)

* Operator: Argo CD sync for chart Application.
* Confirm no Pending catalog pods (Karpenter provisioning).
* Re-check HPA TARGETS after scale-out (CPU should move closer to 70%).

## Migration or Deployment Notes

1. Merge/sync **techx-corp-chart** only (chart `0.46.0`).
2. No image rebuild.

```cmd
kubectl -n techx-corp-prod get hpa product-catalog
kubectl -n techx-corp-prod get deploy product-catalog
```

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Extra Spot cost under prolonged load | Medium | Low | Unchanged scale-down; lower max if needed |
| PostgreSQL connection pressure at 12 pods | Low–Medium | Medium | Watch DB connections/pool; reduce max if saturated |
| Still pinned at 12 under heavier load | Low | Low | Re-apply formula and raise again |

**Rollback procedure:**

Set `maxReplicas: 6` in `values.yaml`, restore chart version if required, re-sync. Existing pods above the restored max scale down per HPA scale-down policy.

<!-- Change trail: @hungxqt - 2026-07-14 - product-catalog HPA maxReplicas 6→12. -->
