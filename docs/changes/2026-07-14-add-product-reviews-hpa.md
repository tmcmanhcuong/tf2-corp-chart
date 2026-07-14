# Change: Add product-reviews Horizontal Pod Autoscaler

## Summary

Enabled triple-metric HPA for **`product-reviews`** (CPU 70% + memory 90% + RPS **10**/pod, min 1 / max 6, shared scale behavior) so the AI review path can scale under Locust/product-page load instead of remaining fixed at the default single replica. Chart version **0.47.0**.

## Context

Other hot-path / product-page services (`product-catalog`, `recommendation`, money-flow stack) already had request-metric HPA. `product-reviews` stayed on fixed `default.replicas` (1) while still serving frontend product-page traffic, Postgres, and optional LLM generation — a single pod can saturate CPU/memory and cause readiness probe pressure (see `docs/changes/2026-07-14-product-reviews-memory-readiness-timeout.md`). Operators asked to add HPA for this deployment.

## Before

* `components.product-reviews` had **no** `autoscaling` block.
* Deployment used static replicas from `default.replicas` (1).
* No `HorizontalPodAutoscaler/product-reviews` rendered.
* Ops inventories listed seven request-path HPAs (excluding product-reviews).

## After

* `components.product-reviews.autoscaling`:

| Field | Value |
|---|---|
| `enabled` | `true` |
| `minReplicas` | 1 |
| `maxReplicas` | 6 |
| `targetCPUUtilizationPercentage` | 70 |
| `targetMemoryUtilizationPercentage` | 90 |
| `targetRequestsPerSecond` | 10 |
| `behavior` | `*hpa-behavior-default` |

* Deployment omits static `replicas` while HPA is enabled (existing template behavior).
* Chart **0.47.0**; docs list eight request-path HPAs including product-reviews.

## Technical Design Decisions

* **Match recommendation shape** — both are Python product-page backends on spot-tolerant nodes; same min/max band (1–6) until load-test pin data justifies a raise.
* **RPS target 10 (not 15)** — reviews path includes Postgres + LLM; lower average RPS/pod so HPA scales earlier than pure recommendation.
* **Triple metrics (max of RPS/CPU/mem)** — same Option B+ as other request-path services; External metric uses default `service_name=product-reviews` via existing Prometheus Adapter rules (`rpc_server_*` / spanmetrics).
* **minReplicas 1** — not money-flow Directive #3 floor; keeps idle cost low (same as currency/recommendation).
* **No template/schema change** — `techx-corp.hpa` already supports these fields; enabling values is sufficient.
* Rejected: CPU-only HPA (would under-scale on I/O wait); min 2 (unnecessary idle cost without maintenance floor requirement).

## Implementation Details

1. Added `autoscaling` block under `components.product-reviews` in `values.yaml`.
2. Bumped chart version to `0.47.0`.
3. Updated HPA inventory and describe/verify examples in DEPLOYMENT, request-metric-hpa, and workload-placement docs.

## Files Changed

**Configuration:**

* `values.yaml` — product-reviews autoscaling block.
* `Chart.yaml` — version `0.46.0` → `0.47.0`.

**Documentation:**

* `docs/DEPLOYMENT.md` — inventory row, min note, describe/verify text.
* `docs/operations/request-metric-hpa.md` — service table + describe example.
* `docs/operations/workload-placement.md` — HPA service list includes product-reviews.
* `docs/changes/2026-07-14-add-product-reviews-hpa.md` — this change record.

## Dependencies and Cross-Repository Impact

* Depends on existing Metrics Server (CPU/mem) and Prometheus Adapter (RPS) already in the chart.
* **Karpenter** may add Spot nodes when reviews scale out (default spot-tolerant scheduling).
* **PostgreSQL** and **llm** backends see more concurrent clients at max replicas — watch connections and LLM latency.
* No `techx-corp-platform` or `techx-corp-infra` code change required.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | product-reviews can scale 1–6 under load; idle stays at 1 |
| **Infrastructure** | Possible extra Karpenter Spot pods under product-page load |
| **Deployment** | Argo/Helm creates `HorizontalPodAutoscaler/product-reviews`; Deployment replicas managed by HPA |
| **Performance** | Better headroom for AI/review RPCs when single pod was CPU/mem bound |
| **Cost** | Low idle (min 1); peak up to 6 pods under load |
| **Reliability** | Reduces single-pod saturation; PDB still only if min later ≥ 2 |
| **Backward compatibility** | Compatible; set `autoscaling.enabled: false` to restore fixed replicas |
| **Observability** | HPA exposes CPU/mem/RPS targets for product-reviews |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values | Inspect `components.product-reviews.autoscaling` | ✅ enabled, min 1, max 6, CPU 70, mem 90, RPS 10 |
| Chart version | `Chart.yaml` | ✅ 0.47.0 |

### Manual Verification

After sync:

```cmd
kubectl -n techx-corp-prod get hpa product-reviews
kubectl -n techx-corp-prod describe hpa product-reviews
```

Expect MINPODS 1, MAXPODS 6, TARGETS for CPU / memory / External RPS (RPS may stay low until review traffic).

```cmd
kubectl -n techx-corp-prod get deploy product-reviews -o jsonpath="{.spec.replicas}{'\n'}"
```

Replicas should be HPA-managed (not a hard-coded chart-only value when HPA is active).

### Remaining Verification (Post-Merge)

* Confirm External metric `service_name=product-reviews` exists in Prometheus after traffic.
* Under Locust product-page browse with reviews, confirm scale-out when RPS/CPU exceeds targets.
* Watch Postgres connection count and `llm` latency at higher replica counts.

## Migration or Deployment Notes

1. Merge/sync **techx-corp-chart** (chart `0.47.0`) only.
2. No image rebuild.
3. If External TARGET stays `<unknown>` after traffic, inventory Prometheus series for `product-reviews` (adapter rules already cover gRPC/spanmetrics).

```cmd
kubectl -n techx-corp-prod get hpa product-reviews
kubectl -n techx-corp-prod get deploy product-reviews
```

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| RPS metric missing → only CPU/mem scale | Medium | Low | CPU/mem still work; fix instrumentation/adapter inventory |
| Over-scale on low RPS target (10) | Low | Low | Raise `targetRequestsPerSecond` |
| Postgres/LLM pressure at max 6 | Low–Medium | Medium | Lower maxReplicas; watch dependency metrics |
| Flapping near target | Low | Low | Shared scaleDown stabilize 60s |

**Rollback procedure:**

```yaml
# values.yaml — disable or remove autoscaling on product-reviews
components:
  product-reviews:
    autoscaling:
      enabled: false
    # optional fixed floor:
    # replicas: 1
```

Re-sync chart. HPA object is removed/disabled; Deployment regains static replicas.

<!-- Change trail: @hungxqt - 2026-07-14 - Add product-reviews HPA (CPU/mem/RPS). -->
