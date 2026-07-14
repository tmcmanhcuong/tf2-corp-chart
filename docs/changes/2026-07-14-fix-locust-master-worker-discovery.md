# Change: Harden Distributed Locust Master/Worker Chart Config

## Summary

Chart hardening so Locust distributed mode keeps workers visible and network-ready under HPA/Spot churn: explicit master bind flags, `LOCUST_EXPECT_WORKERS`, master HTTP probes, slower worker HPA scale-down, and NetworkPolicy rules for worker ↔ master `:5557` (plus worker egress to load path). Complements the platform `locustfile.py` guard that prevents master `client_listener` death on stale worker messages.

## Context

Live prod showed Locust UI `worker_count: 0` while `load-generator-worker` pods were Ready and could TCP-connect to `svc/load-generator:5557`. Root cause was master process state after a Locust `KeyError` on a disconnected worker id (see platform change). Chart gaps also needed fixing for durable ops:

* Autostart without expecting workers races empty swarms.
* Master bind host/port not explicit.
* Worker HPA scale-down could churn quickly (default 60s stabilization).
* NetworkPolicy (when enabled) only allowed UI traffic to master, not worker ZMQ `:5557`, and had no worker policy.

## Before

* Master command: `locust --master --skip-log-setup` only.
* No `LOCUST_EXPECT_WORKERS`.
* Worker HPA used shared `*hpa-behavior-default` (scaleDown stabilize 60s).
* NP `load-generator`: ingress only from `frontend-proxy:8089`.
* No `load-generator-worker` NetworkPolicy.
* Docs still described single-pod Locust / no worker HPA in places.
* Deployment template used `replicas | default`, so chart `replicas: 0` was ignored (Helm treats `0` as empty → fell back to default `1`).

## After

* Master binds `0.0.0.0:5557` explicitly; `LOCUST_EXPECT_WORKERS=1` (matches worker HPA min).
* Master readiness/liveness HTTP probes on web UI `:8089`.
* Worker command sets `--master-port=5557`.
* Worker HPA is **CPU-only** (`targetCPUUtilizationPercentage: 70`; no memory metric) with scaleDown `stabilizationWindowSeconds: 300` (reduce churn).
* NP: master accepts workers on `5557`; worker NP egress to master/frontend-proxy/flagd/otel; flagd + frontend allow workers.
* Deployment template honors explicit `replicas: 0` via `hasKey` (idle cost control for Locust master).
* Ops docs (`DEPLOYMENT`, workload-placement, network-policy) updated for distributed mode.

## Technical Design Decisions

* **Chart alone cannot fix greenlet death** — process fix is in platform image; chart reduces races and future NP lockout.
* **`EXPECT_WORKERS=1` not `=maxReplicas`** — HPA varies worker count; waiting for max would stall autostart.
* **Longer scale-down only on workers** — leave shared HPA behavior for hot-path services unchanged.
* **Probes on master UI only** — detect dead process, not “0 workers”; worker-count semantics remain Locust’s.

## Implementation Details

1. Updated `components.load-generator` command/env/probes in `values.yaml`.
2. Updated `components.load-generator-worker` command and dedicated HPA behavior.
3. Extended `templates/networkpolicy.yaml` for master/worker ZMQ and worker egress.
4. Documented matrix in operations + DEPLOYMENT.

## Files Changed

**Configuration:**

* `values.yaml` — Master bind/expect-workers/probes; worker master-port; worker HPA CPU-only + longer scale-down.
* `values-prod.yaml` — `load-generator.replicas: 1` while active load testing (base idle remains 0).

**Templates:**

* `templates/_objects.tpl` — Honor `replicas: 0` (do not `default` over zero).
* `templates/networkpolicy.yaml` — Master ingress `:5557` from workers; worker NP; flagd/frontend allow workers.

**Documentation:**

* `docs/operations/network-policy.md` — Master/worker traffic matrix.
* `docs/operations/workload-placement.md` — Master vs worker placement/HPA.
* `docs/DEPLOYMENT.md` — Distributed Locust + worker HPA notes.
* `docs/changes/2026-07-14-fix-locust-master-worker-discovery.md` — This change record.

## Dependencies and Cross-Repository Impact

* Related: `techx-corp-platform/docs/changes/2026-07-14-fix-locust-master-worker-discovery.md` (required image fix for KeyError).
* Chart deploy without new image improves bind/expect-workers/NP/HPA but **does not** alone stop master greenlet death.
* Prior: `docs/changes/2026-07-14-distributed-load-generator.md`.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Autostart waits for ≥1 worker; clearer master bind |
| **Infrastructure** | No new cloud resources |
| **Deployment** | Helm/Argo sync of chart values + NP templates |
| **Performance** | Worker scale-down slower (up to ~5m stabilize) — intentional |
| **Security** | NP ready for distributed ZMQ when `networkPolicy.enabled=true` |
| **Reliability** | Less worker churn; NP will not block master-worker when enforced |
| **Cost** | Workers may linger slightly longer after load drops |
| **Backward compatibility** | Compatible; master still default replicas 0 when idle |
| **Observability** | Master HTTP probes |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Helm template | `helm template techx-corp . -f values.yaml -f values-prod.yaml` | Run in validation step |
| Helm lint | `helm lint . -f values.yaml -f values-prod.yaml` | Run in validation step |

### Manual Verification

* Pre-fix: TCP to `:5557` OK; API `worker_count: 0` until master restart.
* After chart sync (with platform image): workers stay listed through HPA scale events; master probes Ready.

### Remaining Verification (Post-Merge)

1. Argo sync chart to target env.
2. Confirm master Deployment args include bind host/port and env `LOCUST_EXPECT_WORKERS=1`.
3. Confirm HPA worker behavior scaleDown stabilize 300.
4. When NP is enabled later, verify worker→master `:5557` still works.

## Migration or Deployment Notes

1. Prefer platform image (stale-worker guard) + this chart change together.
2. Scale master to 1 if currently 0 and tests are needed:

```cmd
kubectl scale deployment load-generator --replicas=1 -n techx-corp-prod
```

3. No special migrate for Service ports (`5557`/`8089` already present).

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| `EXPECT_WORKERS=1` delays autostart if workers Pending | Medium | Low | Fix worker schedule/HPA; or set expect to 0 temporarily |
| Longer scale-down holds Spot capacity | Low | Low | Lower stabilize window if cost-sensitive |
| NP typo blocks workers when NP enabled | Low | High | NP currently `enabled: false`; test in dev before enforce |

**Rollback procedure:**

Revert this chart change (values + networkpolicy + docs) and sync. Platform image guard can remain independently.

<!-- Change trail: @hungxqt - 2026-07-14 - Locust worker HPA CPU-only; chart master-worker harden. -->
