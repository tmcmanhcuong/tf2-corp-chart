# Change: Raise HPA maxReplicas for Load-Test CPU Pins

## Summary

Raised HorizontalPodAutoscaler `maxReplicas` for five hot-path services that were pinned at their previous ceilings under load testing while CPU utilization remained well above target. Chart version bumped to `0.44.0`. Ops inventory docs were updated to match.

## Context

Cluster HPA status during load testing showed all of the following at max with CPU still over target (memory well under 90%):

| Service | min / max / replicas | CPU vs target |
|---|---|---|
| `cart` | 2 / 6 / 6 | 110% / 70% |
| `checkout` | 2 / 6 / 6 | 148% / 70% |
| `currency` | 1 / 6 / 6 | 140% / 70% |
| `frontend` | 2 / 6 / 6 | 157% / 80% |
| `frontend-proxy` | 2 / 3 / 3 | 128% / 80% |

HPA could not add capacity because it had already hit `maxReplicas`. Desired-replica estimate: `currentReplicas × (currentCPU% / targetCPU%)`, plus modest headroom so the new ceiling is not immediately re-pinned.

## Before

| Service | maxReplicas |
|---|---:|
| `cart` | 6 |
| `checkout` | 6 |
| `currency` | 6 |
| `frontend` | 6 |
| `frontend-proxy` | 3 |

## After

| Service | maxReplicas | Rationale |
|---|---:|---|
| `cart` | **12** | ~9.4 desired at 110%/70%; +headroom |
| `checkout` | **16** | ~12.7 desired at 148%/70%; +headroom (orchestration fan-out) |
| `currency` | **12** | ~12 desired at 140%/70% |
| `frontend` | **14** | ~11.8 desired at 157%/80%; +SSR headroom |
| `frontend-proxy` | **6** | ~4.8 desired at 128%/80%; requires Critical MNG capacity |

Min replicas, CPU/memory targets, RPS targets, and HPA behavior policies are unchanged. `product-catalog` and `recommendation` remain max 6 (not pinned in the observed snapshot).

## Technical Design Decisions

* **Raise max only (not requests/limits)** — Immediate fix for HPA ceiling; request right-sizing remains a separate follow-up (tiny CPU requests on currency/checkout inflate utilization %).
* **CPU-implied desired + ~15–25% headroom** — Avoids re-pinning on the next small load bump without unbounded scale-out cost.
* **frontend-proxy to 6 (not higher)** — Still Critical MNG only; operators must confirm multi-AZ Critical capacity. Documented Pending failure mode remains.
* **No prod overlay override** — Base `values.yaml` is the source of truth for max; prod inherits.

Alternatives rejected:

* Lowering CPU targets further — would scale earlier but not help once already at max.
* Disabling HPA and fixing replicas — loses automatic scale-down after load tests.

## Implementation Details

1. Updated `components.*.autoscaling.maxReplicas` for cart (12), checkout (16), currency (12), frontend (14), frontend-proxy (6) in `values.yaml`.
2. Added brief inline comments documenting the load-test math behind each new max.
3. Bumped chart `version` to `0.44.0`.
4. Aligned HPA inventory tables in `docs/DEPLOYMENT.md`, `docs/operations/request-metric-hpa.md`, and `docs/operations/workload-placement.md` (max values and Critical capacity note).

## Files Changed

**Configuration:**

* `values.yaml` — Raised maxReplicas for five hot-path HPAs; comments for load-test rationale.
* `Chart.yaml` — version `0.43.0` → `0.44.0`.

**Documentation:**

* `docs/DEPLOYMENT.md` — Default HPA inventory max/min/metric targets aligned with values.
* `docs/operations/request-metric-hpa.md` — Service table max values; Pending guidance for proxy max 6.
* `docs/operations/workload-placement.md` — Spot HPA max range; frontend-proxy max 6.
* `docs/changes/2026-07-14-raise-hpa-max-replicas-load-test.md` — This change record.

## Dependencies and Cross-Repository Impact

* **Karpenter** (`techx-corp-infra`): cart, checkout, currency, frontend scale-out may provision more Spot nodes under load.
* **Critical MNG** (`techx-corp-infra`): frontend-proxy max 6 requires sufficient Critical node capacity (multi-AZ). If pods `Pending`, free Critical workload or grow MNG — do not keep raising chart max alone.
* No `techx-corp-platform` application change.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Hot-path services can scale beyond previous ceilings under load; lower latency risk when previously CPU-starved at max |
| **Infrastructure** | Higher peak pod count on Spot (Karpenter) and Critical MNG (proxy); possible extra nodes under Locust |
| **Deployment** | Argo CD / Helm sync updates HPA objects only; no image rebuild |
| **Performance** | Removes artificial replica ceiling observed under load test |
| **Security** | No change |
| **Reliability** | Better scale-out headroom; frontend-proxy Pending risk if Critical MNG undersized |
| **Cost** | Higher peak cost only under sustained load; scale-down behavior unchanged (60s stabilization) |
| **Backward compatibility** | Fully compatible; operators can lower maxReplicas in an overlay if needed |
| **Observability** | No change |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values grep | Confirm maxReplicas 12/16/12/14/6 for five services | ✅ Set in `values.yaml` |
| Chart version | `Chart.yaml` version 0.44.0 | ✅ |

### Manual Verification

* Post-sync: `kubectl get hpa` should show new MAXPODS.
* Under same load profile: REPLICAS should move above prior max if CPU still over target, and eventually sit below the new max if capacity is sufficient.
* `frontend-proxy`: confirm no `Pending` pods after scale-out.

### Remaining Verification (Post-Merge)

1. GitOps sync (dev then prod as appropriate).
2. Re-run load test; confirm HPAs are not pinned at the new max (or only briefly).
3. If still pinned, check External RPS targets via `kubectl describe hpa` and absolute CPU via `kubectl top pods`.
4. Critical MNG capacity review if frontend-proxy Pending.

## Migration or Deployment Notes

1. Merge chart change; Argo CD sync (or break-glass Helm upgrade).
2. No infra apply required unless frontend-proxy cannot schedule — then review Critical MNG size in `techx-corp-infra`.
3. Optional verification:

```cmd
kubectl get hpa -n techx-corp-prod
kubectl describe hpa cart checkout currency frontend frontend-proxy -n techx-corp-prod
```

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| frontend-proxy Pending on Critical MNG | Medium | High | Free Critical capacity or grow MNG; temporarily set maxReplicas back to 3 |
| Higher Spot cost under prolonged load | Medium | Low–Medium | Unchanged scale-down; lower max in overlay if needed |
| Downstream pressure (valkey-cart, payment, etc.) | Medium | Medium | Watch dependent services; they may need separate scaling |

**Rollback procedure:**

1. Revert this chart change (or set the five `maxReplicas` back to 6/6/6/6/3).
2. Sync Argo CD / Helm upgrade.
3. Existing pods above the restored max will scale down per HPA scale-down policy.

<!-- Change trail: @hungxqt - 2026-07-14 - Document HPA maxReplicas raise for load-test CPU pins. -->
