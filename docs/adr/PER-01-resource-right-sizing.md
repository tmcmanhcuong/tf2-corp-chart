# PER-01 — Resource Right-sizing for Workloads

**Date:** 2026-07-14
**Status:** Accepted
**Deciders:** Team CDO-03
**Priority:** P1
**Pillar:** Performance Efficiency & Cost Optimization

---

## Context

The TechX Corp microservices platform runs ~20 workloads under continuous load testing (via Locust load generator). The initial configuration in `values.yaml` contained arbitrary resource requests and limits that did not reflect actual application behavior or requirements. 

This led to major inefficiencies:
- **Over-provisioning (Waste):** Many lightweight services (e.g. `shipping` in Rust, `quote` in PHP, `product-catalog` in Go) had request floors of 50m-100m CPU and 100Mi-256Mi memory, wasting valuable compute slots and preventing efficient node bin-packing.
- **Under-provisioning (OOM Risk):** Heavy services like `payment` (Node.js), `product-reviews` (Python), `opensearch` (JVM), and sub-charts like `prometheus-server` and `grafana` were running dangerously close to or exceeding their memory requests/limits under load, leading to potential OOMKills or container restart loops.
- **HPA Throttling:** Services using HPA (e.g. `frontend`) had request targets configured in a way that did not align with actual per-pod load characteristics, rendering the auto-scaling logic ineffective.

To resolve these issues, we collected metrics under active load testing:
1. **P95/P99 CPU & Memory metrics** from a 30-hours load test.
2. **`kubectl top pods` per-pod output** during active traffic to cross-verify.

---

## Decision

We decided to right-size the CPU and Memory resource configurations (`requests` and `limits`) across all microservices and sub-charts using the following methodology:

### Sizing Methodology
1. **Memory Requests:** Configured at **P99 Memory Usage + 15-25% headroom** buffer. This guarantees the pod will not be scheduled on a node that lacks sufficient physical memory, avoiding runtime page thrashing or OOMKills.
2. **Memory Limits:** Configured at **Memory Requests × 1.5 - 2.0x** for stateless services. For stateful/Guaranteed QoS services (`postgresql`, `valkey-cart`, `opensearch`, `kafka`), limits were set **exactly equal to requests** to maintain QoS guarantees.
3. **CPU Requests:** Set to reflect actual steady-state P99 CPU cores, with a minimum floor of 5m-10m for lightweight applications to allow scheduler efficiency. For JVM and Node.js applications, higher CPU requests were retained to handle startup spikes and garbage collection (GC) cycles.
4. **HPA Services (`frontend`, `cart`, etc.):** CPU requests were tuned so that the target CPU utilization threshold (70%) represents a realistic scaling trigger based on per-pod performance.

---

## Technical Details

The following changes were applied to `values.yaml`:

### 1. Application Microservices (Stateless / Spot-tolerant)
- **`accounting` (C#):** Reduced requests to `20m` CPU / `200Mi` memory (actual ~155Mi memory).
- **`ad` (JVM):** Set to `15m` CPU / `288Mi` memory (actual JVM footprint ~229Mi).
- **`cart` (.NET):** Configured to `20m` CPU / `80Mi` memory (actual ~65Mi).
- **`checkout` (Go):** Reduced to `10m` CPU / `24Mi` memory (Go footprint is minimal).
- **`currency` (C++):** Reduced to `10m` CPU / `8Mi` memory (actual ~3.5Mi).
- **`email` (Node.js):** Set to `10m` CPU / `64Mi` memory (actual ~51Mi).
- **`fraud-detection` (Python):** Raised memory request to `300Mi` (actual ~235Mi) to support Python dependencies.
- **`frontend` (Next.js SSR):** Tuned per-pod request to `50m` CPU / `128Mi` memory (actual per-pod ~30-55m, ~107Mi).
- **`frontend-proxy` (Envoy):** Set per-pod request to `35m` CPU / `32Mi` memory (actual per-pod ~29m, ~21Mi).
- **`payment` (Node.js):** Raised memory request to `128Mi` (actual ~104Mi) to prevent OOM.
- **`product-catalog` (Go):** Reduced request to `20m` CPU / `24Mi` memory (actual ~16Mi).
- **`product-reviews` (Python):** Configured to `30m` CPU / `96Mi` memory (actual ~74Mi).
- **`quote` (PHP):** Reduced to `5m` CPU / `24Mi` memory (actual ~18Mi).
- **`recommendation` (Python):** Reduced to `20m` CPU / `56Mi` memory (limit kept at `500Mi` for cache feature flag).
- **`shipping` (Rust):** Reduced to `5m` CPU / `8Mi` memory (Rust footprint ~3.5Mi).

### 2. Databases & Platform Components (Stateful / Guaranteed QoS)
- **`postgresql`:** Set request/limit to `80m` CPU / `64Mi` memory (actual ~44Mi memory).
- **`valkey-cart`:** Set request/limit to `10m` CPU / `8Mi` memory. Maxmemory in config is set to 32MB.
- **`opensearch` (JVM):** Configured to `500m` CPU / `900Mi` memory (actual ~700Mi). Retains high CPU request to avoid JVM cold-start timeout loops.
- **`kafka`:** Configured to `200m` CPU / `650Mi` memory (actual ~553Mi).
- **`otel-collector` (DaemonSet):** Set per-pod request to `50m` CPU / `150Mi` memory (actual max ~120Mi) to ensure reliable agent telemetry.

### 3. Monitoring & Sub-charts
- **`jaeger`:** Configured to `25m` CPU / `384Mi` memory (actual ~305Mi).
- **`prometheus`:** Raised memory request to `700Mi` (actual ~650Mi) and limit to `900Mi` to prevent crash loop.
- **`grafana`:** Main container raised to `700Mi` request / `900Mi` limit (actual ~654Mi with Opensearch plugin). Sidecars adjusted to `80Mi` request each.
- **`metrics-server`:** Tightened to `10m` CPU / `40Mi` memory.
- **`prometheus-adapter`:** Set request to `10m` CPU / `56Mi` memory.

---

## Consequences

### Positive
- **Increased Resource Efficiency:** Significantly lowered CPU and memory requests for over-provisioned apps, allowing more pods to fit on Karpenter Spot nodes, reducing AWS infra costs.
- **Improved Reliability:** Raised memory limits and requests for heavy workloads (`prometheus`, `grafana`, `payment`, `fraud-detection`, `ad`) eliminating unexpected OOMKills.
- **Accurate HPA Scaling:** The HPA triggers are now based on realistic per-pod capacities.

### Negative / Trade-offs
- **Throttling Risk:** Lower limits on CPU for lightweight services means burst latency could slightly increase if multiple services spike simultaneously. However, this is mitigated by limits set to 4-10x requests.