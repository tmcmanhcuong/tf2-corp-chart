# Restore Directive #3 production HA floor

## Context

The production replica floor introduced for Directive #3 was temporarily
commented out for a capacity test. That made the production overlay inherit the
single-replica defaults and prevented PodDisruptionBudgets from rendering.

## Change

- Restore a floor of two replicas for the stateless services used by browse,
  cart and checkout.
- Set `autoscaling.minReplicas: 2` for HPA-managed services, including `quote`
  and `shipping`; a fixed `replicas` value is ignored when an HPA is enabled.
- Keep two fixed replicas for non-HPA services and for flagd without changing
  flag definitions or the BTC synchronization source.
- Enforce two-zone/two-host placement with hard topology spread instead of
  allowing both replicas to share a failure domain.
- Add a native 10-second preStop sleep and 30-second termination grace period
  so endpoint and ALB target removal precede process termination.
- Preserve the existing internal ALB, TLS and production image settings.

The chart consequently renders `PodDisruptionBudget` objects with
`minAvailable: 1` for all of these stateless Deployments.

## Verification

Run against the production merge order:

```powershell
helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml
helm template techx-corp . -n techx-corp-prod `
  -f values.yaml -f values-public-alb.yaml -f values-prod.yaml
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts/verify-directive-03.ps1
```

Static verification does not replace the mentor-observed production drain and
k6/Grafana acceptance procedure in
`docs/operations/directive-03-maintenance.md`.

## Residual boundary

Kafka and `valkey-cart` remain singleton stateful services. The first acceptance
drain must stay within the stateless-node safety boundary documented in the
runbook. Full stateful-node fault tolerance requires a separate replicated
data-plane design and failover test; independent extra StatefulSet replicas are
not a safe substitute.
