# Change: Request-Metric HPA for Hot-Path Services

## Summary

Added Prometheus Adapter and request-rate (RPS) External metrics to HorizontalPodAutoscalers for hot-path services (`frontend-proxy`, `frontend`, `product-catalog`, `cart`, `currency`, `checkout`, `recommendation`), while keeping CPU 70% and memory 90% as safety valves. `currency` and `recommendation` gain HPA for the first time.

## Context

Resource-only HPA underestimates capacity needs for I/O-bound and high-RPS/low-CPU services (especially native C++ `currency`). OTel already exports request counters into Prometheus; the chart had no custom/external metrics path. This change wires Prometheus Adapter and extends first-party HPA templates to scale on average RPS per pod.

## Before

* HPA only for `frontend`, `checkout`, `cart`, `product-catalog`, `frontend-proxy`.
* Metrics: CPU 70% + memory 90% via Metrics Server only.
* No Prometheus Adapter dependency.
* `currency` and `recommendation` fixed at default replica count (1).

## After

* Subchart **prometheus-adapter 5.3.0** (Critical MNG), maps OTel/spanmetrics series to External metric `http_requests_per_second` by `service_name`.
* HPA template supports `targetRequestsPerSecond` (External AverageValue), optional `customMetricName` / `serviceName`.
* Seven HPAs with RPS targets (starting values):

| Service | RPS/pod | maxReplicas |
|---------|--------:|------------:|
| frontend-proxy | 40 | 3 |
| frontend | 15 | 6 |
| product-catalog | 30 | 6 |
| cart | 20 | 6 |
| currency | 50 | 6 |
| checkout | 5 | 6 |
| recommendation | 15 | 6 |

* Chart version `0.42.0`.
* Ops runbook: `docs/operations/request-metric-hpa.md`.

## Technical Design Decisions

* **Prometheus Adapter + native HPA** over KEDA for this change — reuses existing HPA/PDB wiring; KEDA remains a follow-up for Kafka lag.
* **External + AverageValue** keyed by `service_name` rather than Pods metrics — matches OTel dimensions already used in Grafana (`service_name`) without requiring per-series pod labels.
* **Triple metrics (max of RPS/CPU/mem)** — RPS primary under traffic; CPU/mem retain Option B safety valves if External metrics are missing.
* **Starting RPS targets are placeholders** — tune after Locust + APM baseline; documented as non-SLO.
* Adapter `rules.default: false` — Metrics Server continues to own Resource metrics (avoid dual providers).

## Implementation Details

1. Added `prometheus-adapter` dependency and values (Critical pin, Prometheus URL, external rules for gRPC/HTTP/spanmetrics).
2. Extended `techx-corp.hpa` validation and External metric block.
3. Extended `values.schema.json` Autoscaling properties.
4. Set `targetRequestsPerSecond` on P0/P1 services; enabled full HPA on `currency` and `recommendation`.
5. Documented inventory, verification, and failure modes.

## Files Changed

**Chart / templates / values:**

* `Chart.yaml` — version 0.42.0; prometheus-adapter 5.3.0 dependency.
* `values.yaml` — adapter config; RPS targets; currency + recommendation HPA.
* `templates/_objects.tpl` — External RPS metric in `techx-corp.hpa`.
* `values.schema.json` — `targetRequestsPerSecond`, `customMetricName`, `serviceName`.

**Documentation:**

* `docs/operations/request-metric-hpa.md` — ops runbook (new).
* `docs/operations/workload-placement.md` — HPA inventory includes RPS + new services.
* `docs/DEPLOYMENT.md` — triple metrics, inventory, verification.
* `docs/changes/2026-07-12-request-metric-hpa.md` — this change record.

## Dependencies and Cross-Repository Impact

* Depends on in-cluster Prometheus receiving OTel metrics (existing collector → `otlphttp/prometheus`).
* No `techx-corp-platform` code change.
* No infra change required unless `frontend-proxy` Pending under scale-out (Critical MNG capacity — separate reviewed change).
* GitOps AppProject already allows `APIService`, `ClusterRole`, `ClusterRoleBinding` (same as metrics-server).

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Hot-path services scale earlier under traffic; `currency`/`recommendation` become multi-replica capable under load |
| **Infrastructure** | One additional Critical-floor Deployment (adapter); small CPU/mem footprint |
| **Deployment** | Helm/Argo sync; dependency update pulls adapter chart |
| **Performance** | Better RPS-driven capacity; possible earlier scale-out cost on Spot/Karpenter |
| **Security** | Adapter RBAC for external metrics API (subchart defaults) |
| **Reliability** | Dual path: if External metrics fail, CPU/mem HPA still works |
| **Cost** | Adapter pod + more frequent scale-out under load |
| **Backward compatibility** | Fully additive; disable via `prometheus-adapter.enabled: false` |
| **Observability** | Uses existing OTel metrics; no new app instrumentation |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Helm dependency | `helm dependency update` | ✅ Pass (prometheus-adapter-5.3.0) |
| Lint | `helm lint . -f values.yaml -f values-dev.yaml` | ✅ Pass |
| Template | `helm template` — 7 HPAs with External RPS; adapter Critical pin; no load-generator HPA | ✅ Pass |

### Manual Verification

* Local template asserts seven HPAs with External `http_requests_per_second` and Resource metrics.
* Cluster (post-merge): Adapter Ready, external.metrics APIService, HPA TARGETS under Locust.

### Remaining Verification (Post-Merge)

1. Dev sync: Adapter on Critical; APIService Available.
2. Metric inventory in Prometheus — confirm `service_name` labels.
3. Load test: scale-out on RPS for `currency` / `product-catalog` without requiring 70% CPU.
4. Prod promote after dev acceptance; watch Critical capacity for `frontend-proxy`.

## Migration or Deployment Notes

1. `helm dependency update` (or Argo with dependency resolution).
2. Sync chart; wait for `prometheus-adapter` Ready and external metrics APIService.
3. Confirm HPA describe shows External targets after traffic.
4. Tune `targetRequestsPerSecond` if flapping or laggy scale-out.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Wrong Prom series/labels → External `<unknown>` | Medium | Low | CPU/mem still scale; fix rules after inventory |
| Aggressive RPS targets → flapping | Medium | Medium | Raise targets; scaleDown 60s window |
| Adapter/proxy pressure on Critical MNG | Low | Medium | Small adapter resources; proxy max=3; disable adapter if needed |

**Rollback procedure:**

1. Set `prometheus-adapter.enabled: false` and re-sync (or remove `targetRequestsPerSecond` from components).
2. Resource HPA remains via Metrics Server.
3. Full revert: restore chart revision before this change.
