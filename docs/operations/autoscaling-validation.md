# Autoscaling Validation Runbook

This runbook validates pod scheduling, HPA scale-out, Karpenter provisioning, and consolidation without treating static configuration as runtime evidence. Use read-only inspection first. All desired-state changes to this chart must go through Git and Argo CD.

## Acceptance gates

| Gate | Required result |
|---|---|
| Pending pods | No unexpected unschedulable production pod for 5 minutes; investigate before relaxing hard topology |
| Karpenter synchronization | `karpenter_cluster_state_synced` remains `1` |
| NodePool capacity | CPU and memory usage remain below 80% of each NodePool limit |
| Critical MNG | Requested CPU and memory remain below 75% of allocatable; pod density remains below 80%, evaluated per node and AZ |
| Scale-out | Representative traffic raises the HPA and Karpenter provisions eligible capacity without bypassing taints or topology |
| Scale-in | Load returns to baseline, HPA stabilization completes, and Karpenter consolidates only after the environment delay |
| Evidence window | At least 30 continuous minutes under representative traffic; AMI or lifecycle changes additionally require the infra bake window |

## Read-only inspection

CMD (`cmd.exe`):

```cmd
set NAMESPACE=techx-corp-prod
kubectl get nodes -L workload-class,karpenter.sh/nodepool,karpenter.sh/capacity-type,topology.kubernetes.io/zone
kubectl get nodepool,ec2nodeclass,nodeclaim
kubectl -n %NAMESPACE% get pods,hpa,pdb -o wide
kubectl -n %NAMESPACE% get events --sort-by=.lastTimestamp
kubectl -n kube-system get deploy karpenter
```

Do not retrieve Kubernetes Secret data or print environment variables containing credentials during diagnosis.

## Prometheus evidence

Use Grafana Explore with the Prometheus datasource and retain screenshots or exported, non-sensitive query results with the change review:

```promql
karpenter_cluster_state_synced
```

```promql
karpenter_scheduler_unschedulable_pods_count{controller="provisioner"}
```

```promql
karpenter_nodepools_usage{resource_type=~"cpu|memory"}
  / on(nodepool, resource_type)
karpenter_nodepools_limit{resource_type=~"cpu|memory"}
```

```promql
sum(kube_pod_status_unschedulable{namespace="techx-corp-prod"})
```

## Resource-request evidence gate

Do not tune a workload request from a single instantaneous sample. Run representative traffic for at least 30 minutes and record P95 CPU usage, P95 memory working set, throttling, restarts, OOM events, HPA behavior, and replica count.

For a proposed request, use these review formulas and round upward to a Kubernetes-friendly unit:

* CPU request: `max(current request, P95 CPU / target utilization fraction)`; use the workload's configured HPA CPU target as the fraction.
* Memory request: `max(current request, P95 working set × 1.20)`; memory is a capacity/safety request, not an HPA target in the current base policy.
* Maximum replica footprint: proposed request × `maxReplicas`; the result must fit within the intended NodePool cap with operational headroom.

A request change is rejected when the evidence window is missing, the proposed maximum footprint would exceed 70% of a NodePool limit, or it would push the Critical MNG beyond its 75% resource or 80% pod-density gate. This implementation intentionally leaves existing workload requests unchanged because no qualifying load sample was collected.

## Scale-out and scale-in sequence

1. Record baseline HPA replicas, Pending pods, NodeClaims, NodePool usage/limits, and critical-node headroom.
2. Start the approved representative workload from its normal operator path; do not add ad hoc production traffic from this runbook.
3. Observe HPA desired/current replicas and Karpenter scheduler metrics until scale-out stabilizes.
4. Confirm new pods retain the expected workload-class selector, taint toleration, and production hard zone/hostname spread.
5. Confirm Spot is preferred and On-Demand remains available as fallback; do not force interruption in production.
6. Stop the workload using its approved operator procedure and observe HPA stabilization.
7. Confirm Karpenter consolidates with `consolidateAfter: 0s` (DaemonSet-only / empty nodes, including otel-collector agent only, reclaim immediately) and respects PDBs for voluntary disruption.
8. Retain at least 30 minutes of results and stop promotion on any alert, unexpected replacement, or unsatisfied capacity gate.

## Rollback

Revert the alert and scrape configuration in Git and allow Argo CD to reconcile it. Do not use direct mutating Helm or kubectl commands. Alert rollback does not authorize relaxing workload topology or Karpenter disruption policy.

<!-- Change trail: @hungxqt - 2026-07-15 - Expect consolidateAfter 0s empty reclaim in autoscaling validation. -->
