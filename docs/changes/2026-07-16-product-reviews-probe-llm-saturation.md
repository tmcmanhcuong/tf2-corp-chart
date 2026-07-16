# Change: product-reviews probes under LLM worker saturation

## Summary

Updated `product-reviews` Kubernetes probes so a saturated gRPC worker pool (long `AskProductAIAssistant` / LLM calls) marks the pod NotReady when appropriate but no longer fails **liveness** and restarts the process. Added a **startupProbe** for cold bind after model init, and chart env `GRPC_MAX_WORKERS=32` to match the platform worker-pool increase.

## Context

* Prod Events on `product-reviews` (IP example `10.0.46.3:3551`) showed:
  * `Readiness probe failed: timeout: health rpc did not complete within 5s`
  * `Liveness probe failed: timeout: health rpc did not complete within 5s`
  * `failed to connect service "…:3551" within 5s: context deadline exceeded`
  * `Container product-reviews failed liveness probe, will be restarted` (exit **137**)
* Live HPA was at max (6 replicas) with high CPU and RPS; several pods NotReady with restarts.
* Health `Check` shares the same Python `ThreadPoolExecutor` as AI RPCs. Under load, health RPCs queue past 5s. When **liveness** also used gRPC, kubelet killed healthy-but-busy processes.
* Related prior change: `2026-07-14-product-reviews-memory-readiness-timeout.md` (timeout 5s only; liveness still gRPC).

## Before

* `startupProbe`: unset
* `readinessProbe`: grpc :3551, period 10, timeout 5, fail 3
* `livenessProbe`: **grpc** :3551, period 15, timeout 5, fail 5 (~75s restart window)
* No `GRPC_MAX_WORKERS` env (app hardcoded `max_workers=10`)

## After

* `startupProbe`: grpc :3551, period 5, timeout 5, fail **24** (~2 minutes; blocks liveness/readiness until port serves health)
* `readinessProbe`: grpc :3551, period 10, timeout 5, fail 3 (unchanged math; still load-sheds when pool is full)
* `livenessProbe`: **tcpSocket** :3551, period **20**, timeout **3**, fail 5 (~100s)
* `env.GRPC_MAX_WORKERS`: `"32"` (consumed by platform image when rolled)

## Technical Design Decisions

* **Split readiness vs liveness handlers** — same pattern as `cart` (gRPC readiness, TCP liveness). Readiness may go false under overload; liveness only checks that the process still accepts TCP on 3551.
* **Keep readiness on gRPC** — intentional: when workers are fully busy, NotReady removes the endpoint from Service load balancing instead of accepting more AI RPCs that will only queue.
* **startupProbe over large initialDelaySeconds** — model fetch is already in init containers; startup covers Python bind under CPU contention after restart without delaying probes forever on a healthy pod.
* **Do not raise readiness timeout further** — 5s is enough for a free worker; larger timeouts hide overload and slow endpoint removal.
* **Platform worker pool is required for full effect** — chart env alone does nothing until the image that reads `GRPC_MAX_WORKERS` is deployed. Chart probe change alone stops liveness thrash.

## Implementation Details

1. Updated `components.product-reviews` probes and `GRPC_MAX_WORKERS` in `values.yaml`.
2. Documented Tier B‡ matrix and rationale in `docs/operations/probe-thresholds.md`.
3. Added this change record.

## Files Changed

**Configuration:**

* `values.yaml` — product-reviews startupProbe, tcp liveness, `GRPC_MAX_WORKERS=32`.

**Documentation:**

* `docs/operations/probe-thresholds.md` — matrix, tier footnote, product-reviews section.
* `docs/changes/2026-07-16-product-reviews-probe-llm-saturation.md` — This change record.

## Dependencies and Cross-Repository Impact

* Related: `techx-corp-platform/docs/changes/2026-07-16-product-reviews-grpc-max-workers.md`
* Deploy order for full fix: merge/publish platform image → chart image tag promote (dev auto / prod PR) **or** sync chart probes first (stops liveness kills immediately) then roll image for larger pool.
* No infra Terraform change.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Busy pods less likely to restart; may stay Running but NotReady under extreme load until workers free |
| **Infrastructure** | No change |
| **Deployment** | Argo chart sync; image roll for worker pool |
| **Performance** | Fewer restart storms; better HPA signal stability |
| **Reliability** | Primary goal — stop exit-137 liveness thrash |
| **Backward compatibility** | Probe-only chart change is backward compatible with old image; new env ignored by old image |
| **Observability** | Fewer Unhealthy liveness events; readiness timeouts may still appear under overload (expected) |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values parse | Visual/edit review of `values.yaml` probe blocks | ✅ Edited |
| Live incident correlation | `kubectl describe` / Events on product-reviews | ✅ Matched (gRPC liveness + worker starvation) |

### Manual Verification

* Pre-change: pods with restarts, liveness kill messages, HPA maxed.
* Post-sync (operator):

```cmd
kubectl -n techx-corp-prod get pod -l opentelemetry.io/name=product-reviews
kubectl -n techx-corp-prod describe pod -l opentelemetry.io/name=product-reviews
kubectl -n techx-corp-prod get events --field-selector reason=Unhealthy --sort-by=.lastTimestamp
```

Expect: no `failed liveness probe, will be restarted` driven by `health rpc did not complete`; readiness may still flap under extreme RPS until image roll + load eases.

### Remaining Verification (Post-Merge)

* Argo sync chart revision.
* Confirm container probe YAML on a new pod matches After section.
* After platform image promote: logs contain `grpc_max_workers=32`.

## Migration or Deployment Notes

1. Merge chart change; Argo auto-sync applies probes (recreate pods via Deployment rollout if template hash changes).
2. Deploy platform image with `GRPC_MAX_WORKERS` support and promote tag into chart values as usual.
3. Optional: lower load-generator RPS if HPA remains pegged at maxReplicas.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| TCP liveness misses a wedged gRPC server that still accepts TCP | Low | Medium | Readiness still fails gRPC; investigate hung process; restore gRPC liveness if needed |
| startupProbe fail 24 too short under extreme CPU starve | Low | Medium | Raise failureThreshold or CPU request in follow-up |
| Larger worker pool increases concurrent LLM/memory use | Medium | Low | Memory limit 2Gi; monitor; lower GRPC_MAX_WORKERS if needed |

**Rollback procedure:**

Revert `components.product-reviews` probe and env blocks in `values.yaml` to the previous revision and sync Argo.

<!-- Change trail: @hungxqt - 2026-07-16 - product-reviews startupProbe, tcp liveness, GRPC_MAX_WORKERS chart env. -->
