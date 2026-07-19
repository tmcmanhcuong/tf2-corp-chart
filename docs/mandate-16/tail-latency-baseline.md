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
- Test date: 2026-07-19
- Image tag: sha-bd3c049

## Endpoint definitions

| Flow | Service | Span |
|---|---|---|
| Browse | frontend | GET /api/products/{productId} |
| Cart | frontend | POST /api/cart |
| Checkout | frontend | POST /api/checkout |

## Pre-test state


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
| 300 | 20m | TODO | Browse | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 300 | 20m | TODO | Cart | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 300 | 20m | TODO | Checkout | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 400 | 20m | TODO | Browse | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 400 | 20m | TODO | Cart | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |
| 400 | 20m | TODO | Checkout | TODO | TODO | TODO | TODO | TODO | TODO | Not executed |

> `*` Browse p95/p99 are the worst values observed among the individual `/api/products/{productId}` endpoints, not a combined percentile.

## Breakpoint

- First sustained latency violation: Checkout p95 and p99 exceeded the proposed budgets.
- Load level: 200 users
- Average RPS: 39.27
- Affected flow: Checkout / Email
- Observed p95: 1,600 ms
- Observed p99: 4,700 ms
- HTTP success rate: 100%
- Infrastructure stability: Failed
- Notes: Both Email replicas were repeatedly OOMKilled at a 128Mi memory limit. The test was aborted after 11m12s for system safety.

## Approval

- Proposed by: Le Nguyen Nhat Thanh
- Reviewed by: TODO
- Status: Proposed
- Approval date: TODO
