# Change: Raise Jaeger memory after OOMKilled CrashLoop

## Summary

Raised Jaeger all-in-one memory (and CPU headroom) and lowered `MEMORY_MAX_TRACES` so the in-memory backend stays within the cgroup limit under continuous OTLP ingest instead of `OOMKilled` / CrashLoopBackOff.

## Context

Live prod pod `jaeger-c9d86c5c9-tfgrf` (`techx-corp-prod`) was `CrashLoopBackOff` with:

* Last state: **`OOMKilled`**, exit **137**
* Limits: cpu 300m / memory **1536Mi** (1.5Gi); requests: 25m / **768Mi**
* Storage: **in-memory** (`storage.type: memory`) with `MEMORY_MAX_TRACES=25000`
* Runtime pattern: container becomes Ready, ingests traces for ~6 minutes, then cgroup kill
* Logs: starts cleanly; metrics export retries show collector pressure (`data refused due to high memory usage`) while RSS climbs toward the limit
* Critical node `t4g.large` had free request budget after Prometheus was moved/raised on the peer critical node

The prior sizing (768Mi / 1.5Gi, 25k traces) matched a light P99 baseline (~417Mi) but not sustained multi-service OTLP under load testing.

* Related: `docs/changes/2026-07-15-prometheus-oom-raise-memory.md`
* Related: `docs/adr/PER-01-resource-right-sizing.md` (historical 384Mi request baseline)

## Before

```yaml
extraEnv:
  - name: MEMORY_MAX_TRACES
    value: "25000"
resources:
  requests:
    cpu: 25m
    memory: 768Mi
  limits:
    cpu: 300m
    memory: 1.5Gi
```

## After

```yaml
extraEnv:
  - name: MEMORY_MAX_TRACES
    value: "10000"
resources:
  requests:
    cpu: 50m
    memory: 1Gi
  limits:
    cpu: 500m
    memory: 3Gi
```

In-memory storage type and OTLP/Prometheus wiring are unchanged.

## Technical Design Decisions

* **Raise limit to 3Gi** — confirmed root cause is cgroup OOM after continuous ingest, not probes or image start failure.
* **Request 1Gi (not 3Gi)** — keeps Critical MNG packing feasible on dual `t4g.large`; avoid starving OpenSearch / Grafana / frontend-proxy on the same node.
* **Lower `MEMORY_MAX_TRACES` 25k → 10k** — primary bound for the in-memory backend; fewer retained traces so RSS cannot grow without limit relative to 3Gi.
* **CPU limit 500m / request 50m** — modest raise so batch processing and GC are less throttled during ingest spikes.
* **Deferred:** switch to badger/ES backend, sampling at the collector, or shorter UI retention — use if 3Gi + 10k still OOMs under extreme load.

## Implementation Details

1. Updated `jaeger.jaeger.resources` and `MEMORY_MAX_TRACES` in base `values.yaml`.
2. Recorded this change document.

## Files Changed

**Configuration:**

* `values.yaml` — Jaeger request/limit and `MEMORY_MAX_TRACES`.

**Documentation:**

* `docs/changes/2026-07-16-jaeger-oom-raise-memory.md` — This change record.

## Dependencies and Cross-Repository Impact

* Critical MNG remains dual `t4g.large` (infra). If the new request fails to schedule (`Insufficient memory`), enlarge system MNG or rebalance co-located critical pods — separate infra change.
* No platform image change.
* Tracing UI retains fewer in-memory traces (10k vs 25k); historical query depth is shorter until backend storage is durable.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Storefront unchanged; Jaeger UI keeps fewer in-memory traces |
| **Infrastructure** | +256Mi memory request on Critical MNG; higher peak limit when used |
| **Deployment** | Argo/Helm rolls Jaeger Deployment with new resources/env |
| **Performance** | Less CPU throttle under ingest; more headroom for in-memory backend |
| **Reliability** | Breaks OOM CrashLoop when 3Gi + 10k cap is sufficient for current OTLP load |
| **Cost** | Marginal on existing nodes unless MNG must grow later |
| **Observability** | Restores Jaeger UI / OTLP receive path when Ready; max retained traces reduced |
| **Backward compatibility** | Fully compatible resource raise; trace retention cap is lower |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values | Inspect `jaeger.jaeger.resources` | ✅ 1Gi / 3Gi, cpu 50m / 500m |
| Env | `MEMORY_MAX_TRACES: "10000"` | ✅ |

### Manual Verification

* Live describe: `OOMKilled` exit 137, limits 1536Mi, `MEMORY_MAX_TRACES=25000`, ~6 min runtime before kill.
* Previous logs: clean start → continuous metric export pressure → cgroup kill (no config parse error).

### Remaining Verification (Post-Merge)

1. Commit/push chart change; wait for Argo CD auto-sync of `techx-corp` (prod).
2. Confirm new pod Ready:

```cmd
kubectl -n techx-corp-prod get pod -l app.kubernetes.io/name=jaeger -o wide
kubectl -n techx-corp-prod describe pod -l app.kubernetes.io/name=jaeger
```

3. Confirm resources and env on the running container:

```cmd
kubectl -n techx-corp-prod get deploy jaeger -o jsonpath="{.spec.template.spec.containers[0].resources}"
kubectl -n techx-corp-prod get deploy jaeger -o jsonpath="{.spec.template.spec.containers[0].env}"
```

4. Watch for recurrence under load (no OOM for ≥30 minutes; restartCount stable).

## Migration or Deployment Notes

1. Merge/push to the chart GitOps remote; do **not** `helm upgrade` or mutate the live Deployment directly (Argo auto-sync).
2. After sync, Jaeger restarts once with empty in-memory store (expected for memory backend).
3. If the new pod is `Pending` for `Insufficient memory`, free Critical MNG request budget or raise MNG size in infra.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Still OOM at 3Gi under extreme load | Low | Medium | Lower `MEMORY_MAX_TRACES` further or move traces off in-memory storage |
| `Pending` due to higher request | Low | Medium | Reduce request to 896Mi or rebalance critical pods |
| Shorter UI lookback (10k traces) | Medium | Low | Accept for demo; durable storage is a follow-up |

**Rollback procedure:**

1. Revert `values.yaml` Jaeger `resources` and `MEMORY_MAX_TRACES` to the Before block.
2. Push the revert; let Argo CD reconcile.

<!-- Change trail: @hungxqt - 2026-07-16 - Raise Jaeger memory limit and lower MEMORY_MAX_TRACES after prod OOMKilled CrashLoop. -->
