# Change: Raise HPA maxReplicas Round 2 (currency, frontend, frontend-proxy)

## Summary

Second raise of HPA `maxReplicas` for three services that remained pinned at their round-1 ceilings under continued load testing while CPU stayed above target. Chart version bumped to `0.45.0`. Ops inventory docs updated.

## Context

After chart `0.44.0` (first max raise), a second HPA snapshot still showed ceiling pins:

| Service | min / max / replicas | CPU vs target |
|---|---|---|
| `currency` | 1 / 12 / 12 | 412% / 70% |
| `frontend` | 2 / 14 / 14 | 100% / 80% |
| `frontend-proxy` | 2 / 6 / 6 | 110% / 80% |

Desired-replica estimate: `currentReplicas × (currentCPU% / targetCPU%)`, then modest headroom.

`currency` at 412% is extreme; the service still uses a **10m** CPU request, which amplifies utilization percentage. Raising max unblocks HPA; request right-sizing remains a follow-up.

## Before

| Service | maxReplicas (after round 1) |
|---|---:|
| `currency` | 12 |
| `frontend` | 14 |
| `frontend-proxy` | 6 |

## After

| Service | maxReplicas | Math |
|---|---:|---|
| `currency` | **72** | `12 × 412/70 ≈ 71` |
| `frontend` | **20** | `14 × 100/80 = 17.5` + headroom |
| `frontend-proxy` | **10** | `6 × 110/80 = 8.25` + headroom |

Other HPA max values from round 1 unchanged (`cart` 12, `checkout` 16).

## Technical Design Decisions

* **Same formula as round 1** — stay consistent with CPU-implied desired + small headroom.
* **currency 72 (not a small bump)** — partial raises would re-pin immediately at 412%/70%.
* **frontend-proxy 10** — still Critical MNG only; Pending risk grows; operators must verify MNG capacity.
* **Do not change minReplicas or metric targets** in this change.

## Implementation Details

1. Set `components.currency.autoscaling.maxReplicas: 72` in `values.yaml`.
2. Set `components.frontend.autoscaling.maxReplicas: 20`.
3. Set `components.frontend-proxy.autoscaling.maxReplicas: 10`.
4. Bumped chart version to `0.45.0`.
5. Updated HPA inventory tables in DEPLOYMENT, request-metric-hpa, and workload-placement ops docs.

## Files Changed

**Configuration:**

* `values.yaml` — currency/frontend/frontend-proxy maxReplicas; inline math comments.
* `Chart.yaml` — version `0.44.0` → `0.45.0`.

**Documentation:**

* `docs/DEPLOYMENT.md` — HPA inventory max columns.
* `docs/operations/request-metric-hpa.md` — service table and Critical Pending note.
* `docs/operations/workload-placement.md` — max ranges for spot services and proxy.
* `docs/changes/2026-07-14-raise-hpa-max-replicas-round-2.md` — this change record.

## Dependencies and Cross-Repository Impact

* **Karpenter** (`techx-corp-infra`): `currency` and `frontend` may provision many more Spot nodes at peak (currency up to 72 pods).
* **Critical MNG** (`techx-corp-infra`): `frontend-proxy` max 10 needs multi-AZ Critical capacity; grow MNG or free capacity if Pending.
* No `techx-corp-platform` change.

Related: `docs/changes/2026-07-14-raise-hpa-max-replicas-load-test.md` (round 1).

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Unblocks further scale-out for three still-pinned services |
| **Infrastructure** | Higher peak pod/node count, especially currency on Spot and proxy on Critical |
| **Deployment** | Argo/Helm sync updates HPA objects only |
| **Performance** | Removes artificial ceilings observed under load |
| **Reliability** | frontend-proxy Pending risk if Critical undersized; currency pod fan-out pressure on nodes |
| **Cost** | Higher peak Spot/Critical cost under sustained load only |
| **Backward compatibility** | Fully compatible; lower max via overlay if needed |
| **Observability** | No change |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values | maxReplicas 72 / 20 / 10 set | ✅ |

### Manual Verification

* Post-sync: `kubectl get hpa` shows new MAXPODS.
* Under load: currency/frontend/proxy REPLICAS can exceed prior max when CPU still over target.

### Remaining Verification (Post-Merge)

1. Sync chart; re-run load test.
2. Confirm HPAs not pinned (or only briefly) at new max.
3. If currency still at extreme %, consider raising `resources.requests.cpu` (right-size) so HPA % is meaningful.
4. Watch frontend-proxy for Pending on Critical MNG.

## Migration or Deployment Notes

1. Merge and Argo sync (or break-glass Helm upgrade).
2. If frontend-proxy Pending: free Critical capacity or raise MNG size in infra before further max increases.

```cmd
kubectl get hpa -n techx-corp-prod currency frontend frontend-proxy
kubectl describe hpa currency frontend frontend-proxy -n techx-corp-prod
```

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| currency 72 pods / Spot cost spike | Medium | Medium | Scale-down policy still applies; lower max or right-size CPU request |
| frontend-proxy Pending | Medium–High | High | Critical MNG capacity; temporary max 6 |
| HPA still pinned if RPS metric is higher than CPU implies | Low–Medium | Medium | Check External metric on `describe hpa`; raise again only with evidence |

**Rollback procedure:**

1. Restore maxReplicas to currency 12, frontend 14, frontend-proxy 6 (or revert this change).
2. Sync chart; HPA scale-down reduces excess pods.

<!-- Change trail: @hungxqt - 2026-07-14 - Document round-2 HPA maxReplicas raise. -->
