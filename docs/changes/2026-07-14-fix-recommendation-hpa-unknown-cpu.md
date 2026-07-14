# Change: Fix recommendation HPA CPU unknown (probes + PostgreSQL capacity)

## Summary

Stabilized **`recommendation`** so HPA can read CPU metrics again: readiness timeout and resource headroom, plus PostgreSQL `max_connections` and resource raises so product-catalog scale-out no longer exhausts DB slots and cascades into NotReady recommendation pods. Chart **0.48.0**. Complements platform pool/worker fixes.

## Context

Live HPA:

```text
recommendation   cpu: <unknown>/70%, memory: 35%/90% + 1 more...   MIN=1 MAX=6 REPLICAS=1
```

Cluster facts:

* Recommendation pod **0/1 Ready**, restarts, exit **137**, readiness/liveness: `health rpc did not complete within 3s/5s`.
* HPA events: `did not receive metrics for targeted pods (pods might be unready)` / `no metrics returned from resource metrics API`.
* Logs: product-catalog → Postgres `remaining connection slots are reserved for roles with the SUPERUSER attribute` and connection resets.
* `SHOW max_connections` = **100**; ~**76** sessions in use (~62 idle `otelu`) with product-catalog at **10** replicas.
* PostgreSQL top ~**402m** CPU / **133Mi** mem against limits **400m** / **256Mi**.

CPU `<unknown>` is a **symptom of NotReady pods**, not a broken Metrics Server for this service alone.

## Before

| Item | Value |
|---|---|
| recommendation readiness timeout | 3s |
| recommendation CPU/mem limits | 200m / 256Mi |
| postgresql max_connections | 100 (image default) |
| postgresql requests/limits | 75m/128Mi · 400m/256Mi |
| Chart | 0.47.0 |

## After

| Item | Value |
|---|---|
| recommendation readiness timeout | **5s** |
| recommendation CPU/mem limits | **400m / 384Mi** |
| recommendation env | `GRPC_MAX_WORKERS=20` (honored after platform image with worker env) |
| postgresql command | `docker-entrypoint.sh postgres -c max_connections=200` |
| postgresql requests/limits | **100m/256Mi · 1000m/512Mi** |
| Chart | **0.48.0** |

## Technical Design Decisions

* **Fix readiness first for HPA** — Metrics Server still needs Ready pods for utilization; raising maxReplicas would not clear `<unknown>`.
* **Postgres capacity + app pool** — chart raises slots/resources; platform caps product-catalog `sql.DB` pool (separate change) so 12 catalog pods cannot reopen unlimited idle connections.
* **Keep entrypoint** — `docker-entrypoint.sh postgres …` preserves init scripts; do not override to bare `postgres` only.
* **Timeout 5s only on readiness** — same pattern as product-reviews; liveness already 5s.
* Rejected: disable CPU metric on recommendation HPA (hides saturation).

## Implementation Details

1. Updated `components.recommendation` probes, resources, and `GRPC_MAX_WORKERS` env in `values.yaml`.
2. Set postgresql `command` for `max_connections=200` and raised resources.
3. Bumped chart to `0.48.0`.
4. Updated probe policy docs.

## Files Changed

**Configuration:**

* `values.yaml` — recommendation + postgresql.
* `Chart.yaml` — `0.47.0` → `0.48.0`.

**Documentation:**

* `docs/operations/probe-thresholds.md` — recommendation readiness timeout 5s; Tier B‡ note.
* `docs/changes/2026-07-14-fix-recommendation-hpa-unknown-cpu.md` — this record.

## Dependencies and Cross-Repository Impact

* **techx-corp-platform** (required for full fix):
  * `product-catalog`: `SetMaxOpenConns(5)` / idle/lifetime caps.
  * `recommendation`: default gRPC worker pool 20 via `GRPC_MAX_WORKERS`.
  * Related: `techx-corp-platform/docs/changes/2026-07-14-fix-recommendation-catalog-db-pressure.md`
* Chart-only deploy improves probes/resources/Postgres immediately; worker-pool env needs the new recommendation image to take effect.
* PostgreSQL StatefulSet restart applies `max_connections` (brief DB interruption).

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Fewer false NotReady/liveness kills on recommendation; fewer catalog DB “no slots” errors after platform pool fix |
| **Infrastructure** | Postgres uses more CPU/mem budget on Critical MNG; connection ceiling 200 |
| **Deployment** | Chart sync restarts recommendation Deployment and postgresql StatefulSet |
| **Performance** | Higher postgres headroom under multi-replica catalog |
| **Reliability** | HPA CPU target should populate when pods stay Ready |
| **Cost** | Modest Critical capacity for larger postgres limits |
| **Backward compatibility** | Compatible |
| **Observability** | HPA TARGETS for recommendation CPU become usable again when Ready |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values | Inspect recommendation timeout/limits; postgresql command/resources | ✅ |
| Chart version | `Chart.yaml` | ✅ 0.48.0 |

### Manual Verification

```cmd
kubectl -n techx-corp-prod get pods -l app.kubernetes.io/component=recommendation
kubectl -n techx-corp-prod get hpa recommendation
kubectl -n techx-corp-prod exec postgresql-0 -- psql -U root -d otel -c "SHOW max_connections;"
```

Expect: recommendation Ready 1/1; HPA `cpu` numeric (not `<unknown>`); `max_connections` **200**.

### Remaining Verification (Post-Merge)

* Deploy platform images for catalog pool + recommendation workers.
* Under Locust, confirm no SUPERUSER slot errors and stable recommendation readiness.

## Migration or Deployment Notes

1. Sync **techx-corp-chart** `0.48.0` (Argo).
2. Expect short PostgreSQL restart when StatefulSet picks up `command` / resources.
3. Build/push/promote platform images for catalog + recommendation (full fix).
4. Order: chart postgres/recommendation first is OK; platform images as soon as available.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Brief DB outage on postgres restart | High (once) | Medium | Sync in low traffic; apps reconnect |
| Critical MNG memory pressure from larger postgres | Low–Medium | Medium | Watch node allocatable; lower limits if Pending |
| GRPC_MAX_WORKERS ignored on old image | Medium until promote | Low | Platform image required; timeout/resource help anyway |

**Rollback procedure:**

Revert `values.yaml` recommendation and postgresql blocks to pre-change values, chart version if needed, re-sync.

<!-- Change trail: @hungxqt - 2026-07-14 - Recommendation HPA unknown CPU + postgres capacity. -->
