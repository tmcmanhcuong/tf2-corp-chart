# Workload Migration: Standalone Locust to Distributed Master-Worker Architecture

**Date:** 2026-07-14  
**Author:** Team CDO-03  
**Status:** Implemented  

---

## Context

To run high-load simulations for TechX Corp microservices, the load generator architecture was migrated from a standalone single-pod configuration to a distributed **Master-Worker** architecture:
- **`load-generator` (Locust Master):** Hosts the Locust web UI and coordinates work distribution. Scheduled on the **Critical MNG / system nodes** (`*scheduling-critical`, `workload-class=critical`).
- **`load-generator-worker` (Locust Workers):** Generate heavy browser/virtual user traffic. Scheduled on the **Karpenter Spot pool** with pod anti-affinity to keep storefront pods separate.

To minimize ongoing AWS infrastructure costs when load testing is not active:
1. Both `load-generator` and `load-generator-worker` default replicas are set to `0` in the production configuration.
2. During active test cycles, developers scale up the workloads on demand.

> [!NOTE]
> Currently, as we are actively running test scenarios, we temporarily maintain a baseline of `1` minimum replica for both master and worker.

---

## How to Enable Load Testing (Scaling Up)

To start load testing, scale both master and worker replicas to `1` (or more for workers) using Helm upgrade flags:

```bash
helm upgrade --install techx-corp . \
  --namespace techx-corp-prod \
  --set components.load-generator.replicas=1 \
  --set components.load-generator-worker.replicas=1
```

Or scale via `kubectl`:

```bash
kubectl scale deployment load-generator --replicas=1 -n techx-corp-prod
kubectl scale deployment load-generator-worker --replicas=1 -n techx-corp-prod
```

---

## Cost Risk and Remediation Plan

### The Risk
If a tester scales up the Locust master and workers (e.g. up to 6 replicas under heavy test) and **forgets to scale them down**, it will lead to significant unnecessary AWS charges on the Karpenter Spot instances.

### Proposed Solutions (Remediation)
1. **Auto-Idle CronJob:** A Kubernetes CronJob scheduled daily at midnight to set deployment replicas back to `0`.
2. **TTL/Idle Telemetry:** A simple script or pipeline integrating with Prometheus that scales the worker deployments down if zero active Locust test tasks are run for over 30 minutes.

### Current Status
Because cost efficiency optimization on static workloads is currently a lower priority compared to completing other core tracks, this automated scale-down logic **is not yet implemented**. Users must manually scale replicas to `0` once tests are completed:

```bash
kubectl scale deployment load-generator --replicas=0 -n techx-corp-prod
kubectl scale deployment load-generator-worker --replicas=0 -n techx-corp-prod
```

<!-- Change trail: @hungxqt - 2026-07-14 - Locust master placement Critical MNG (system nodes). -->
