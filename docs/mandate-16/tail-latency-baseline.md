# Mandate 16.1 — Tail Latency Baseline and Budget

## Dashboard

- Name: Webstore SLOs & Resources
- UID: webstore-perf-slo-res
- URL: https://internal.hungtran.id.vn/grafana/d/webstore-perf-slo-res

## Test configuration

- Cluster: techx-tf2-prod
- Namespace: techx-corp-prod
- Browser traffic: disabled
- Locust workload: default mixed HTTP workload
- Spawn rate: 10 users/second
- Warm-up: 5 minutes
- Measurement duration: 20 minutes per load level
- Test operator: Le Nguyen Nhat Thanh
- Test dates: 2026-07-19 and 2026-07-20
- Run 200-01 image tag: sha-bd3c049
- Run 200-02 Email image tag observed in events: sha-fa6cb8f

## Endpoint definitions

| Flow | Service | Span |
|---|---|---|
| Browse | frontend | GET /api/products/{productId} |
| Cart | frontend | POST /api/cart |
| Checkout | frontend | POST /api/checkout |

## Pre-test state — Run 200-01


- Locust users: 0
- Locust RPS: 0
- Running nodes: 7
- On-Demand nodes: 3
- Spot nodes: 4
- Unhealthy pods: 0
- Pod restarts: 0
- Memory observation:
  - ip-10-0-25-86: 105%
  - ip-10-0-32-149: 96%
- Notes: Cluster was allowed to stabilize before testing. Two Spot nodes already had high memory usage before load was applied.

## Proposed latency budget

| Flow | p95 budget | p99 budget | Approval |
|---|---:|---:|---|
| Browse | 300 ms | 700 ms | Proposed |
| Cart | 300 ms | 700 ms | Proposed |
| Checkout | 500 ms | 1000 ms | Proposed |

## Test results

### Run 200-01 - Aborted due to Email OOM

- Evidence: `docs/evidence/mandate-16/tail-latency/200-users-run-01-aborted-email-oom`
- Started: 2026-07-19T12:55:11+07:00
- Ended: 2026-07-19T13:06:23+07:00
- Status: Aborted
- Reason: Both Email replicas were repeatedly OOMKilled.
- Email memory request/limit: 64Mi / 128Mi

| Users | Duration | Total Avg RPS | Flow | Requests | Failures | p95 | p99 | Nodes start/end | Pods start/end | Result |
|---:|---:|---:|---|---:|---:|---:|---:|---|---|---|
| 200 | 11m12s | 39.27 | Browse | 12,638 | 0 | 25 ms* | 190 ms* | 7/7 | 49/52 | Passed latency budget; test later aborted due to Email OOM |
| 200 | 11m12s | 39.27 | Cart | 4,874 | 0 | 14 ms | 47 ms | 7/7 | 49/52 | Passed latency budget before abort |
| 200 | 11m12s | 39.27 | Checkout | 1,615 | 0 | 1,600 ms | 4,700 ms | 7/7 | 49/52 | Failed latency budget; test aborted |

### Run 200-02 - Completed after Email recovery

- Evidence: `docs/evidence/mandate-16/tail-latency/200-users-run-02-after-email-recovery`
- Warm-up started: 2026-07-20T11:43:21+07:00
- Measurement started: 2026-07-20T11:48:53+07:00
- Measurement ended: 2026-07-20T12:12:09+07:00
- Actual measurement duration: 23m16s
- Status: Completed with a transient Spot interruption
- Total requests: 60,443
- Total failures: 7
- Overall failure rate: 0.0116%
- Total average RPS: 42.31

| Users | Duration | Total Avg RPS | Flow | Requests | Failures | p95 | p99 | Nodes start/end | Pods start/end | Result |
|---:|---:|---:|---|---:|---:|---:|---:|---|---|---|
| 200 | 23m16s | 42.31 | Browse | 26,749 | 1 | 24 ms* | 110 ms* | 6/7 | 49/54 | Passed latency budget; one transient 503 during Spot replacement |
| 200 | 23m16s | 42.31 | Cart | 10,185 | 0 | 19 ms | 83 ms | 6/7 | 49/54 | Passed latency budget with no failures |
| 200 | 23m16s | 42.31 | Checkout | 3,313 | 5 | 110 ms | 200 ms | 6/7 | 49/54 | Passed latency budget; five transient 500 responses during Spot replacement |

#### Email recovery validation

- Email pods at start: 2 Running, 0 restarts, using 45Mi and 54Mi.
- Email pods at end: 2 Running, 0 restarts, both using 56Mi.
- No Email container was OOMKilled during the run.
- One Email pod was evicted with `Forceful Termination` when its Spot node was replaced and was recreated successfully.
- The replacement pod briefly failed readiness/liveness while starting, then became Ready without restarting.

#### Scaling and infrastructure observations

- HPA scaled Cart from 2 to 3 replicas.
- HPA scaled Checkout from 2 to 4 replicas.
- HPA scaled Load Generator Worker from 1 to 2 replicas.
- Ready pod count increased from 49 to 54.
- Node count increased from 6 to 7.
- Spot node `ip-10-0-29-169` present at the start was absent at the end; replacement nodes joined during the run.
- All seven request failures occurred at approximately 12:03:32–12:03:35 and correlate with the Spot replacement window. The evidence indicates a short availability event rather than a sustained latency bottleneck.

#### Evidence follow-up

- `04-grafana-tail-latency.png` currently uses `Last 30 minutes` and includes warm-up. Recapture it with the absolute measurement window `11:48:53–12:12:09`.
- Add `05-grafana-resources.png` for node count, pod count, CPU, and memory over the same window.
- Rename `locust_stats-aborted.csv` to `locust_stats.csv`; Run 200-02 was completed, not aborted.

### Planned load levels

| Users | Duration | Total Avg RPS | Flow | Requests | Failures | p95 | p99 | Nodes start/end | Pods start/end | Result |
|---:|---:|---:|---|---:|---:|---:|---:|---|---|---|
| 300 | 20m | TODO | Browse | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 300 | 20m | TODO | Cart | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 300 | 20m | TODO | Checkout | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 400 | 20m | TODO | Browse | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 400 | 20m | TODO | Cart | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 400 | 20m | TODO | Checkout | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |

> `*` Browse p95/p99 are the worst values observed among the individual `/api/products/{productId}` endpoints, not a combined percentile.

## Breakpoint status

- Run 200-01 cannot be used as a confirmed capacity breakpoint because its Checkout latency violation occurred while both Email replicas were repeatedly OOMKilled.
- After Email recovery, Run 200-02 passed all proposed p95 and p99 budgets at 200 users and 42.31 average RPS.
- Run 200-02 had a 0.0116% failure rate correlated with a short Spot replacement event; it did not show sustained latency degradation.
- Confirmed latency breakpoint: Not reached yet.
- Next load level: 300 users under the same workload, warm-up, measurement, and evidence procedure.

## Approval

- Proposed by: Le Nguyen Nhat Thanh
- Reviewed by: TODO
- Status: Proposed
- Approval date: TODO
