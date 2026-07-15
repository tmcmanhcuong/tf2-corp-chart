# Change: Harden Pod Scheduling and PDB Ownership

## Summary

Corrects PodDisruptionBudget eligibility so it follows the active replica controller, raises the production `product-reviews` HPA floor to two, classifies kube-state-metrics on the Critical managed-node tier, and aligns scheduler verification and operations documentation with the rendered production contract.

## Context

The prior PDB template used an OR between fixed replicas and HPA minimum replicas. A stale fixed `replicas: 2` value could therefore create a PDB even when an active HPA was allowed to scale to one. The production verification script also required an exact floor of two and rejected the valid frontend floor of three. Documentation still described memory HPA metrics and soft-only topology spreading.

## Before

* PDB eligibility combined fixed and HPA replica values.
* `product-reviews` carried an ineffective fixed `replicas: 2` while its HPA floor remained one.
* The verifier required `minReplicas: 2` exactly.
* kube-state-metrics had no production workload-class selector.
* Operations docs described CPU, memory, and RPS HPA inputs and soft topology only.

## After

* An enabled HPA exclusively controls PDB eligibility through `minReplicas`; otherwise fixed replicas control it.
* Explicit fixed `replicas: 0` is preserved instead of falling through Helm's `default` behavior.
* `product-reviews` has production HPA `minReplicas: 2` and one valid PDB.
* Replica-floor checks accept any numeric value of two or greater and include a stale-fixed-replica regression render.
* kube-state-metrics is pinned to `workload-class=critical` in production.
* Documentation distinguishes base/development soft spreading from production hard zone/hostname spreading and CPU/RPS-only HPA metrics.

## Technical Design Decisions

The PDB template derives one `activeReplicaFloor` rather than combining two possible owners. This mirrors Kubernetes behavior because a Deployment omits its fixed replica count when HPA is enabled. Production hard spreading remains unchanged: it favors two-AZ maintenance safety and intentionally blocks placement when the domain contract cannot be met.

Resource requests and HPA maximum replicas are not changed without representative load evidence. Karpenter capacity policy is owned by the related infrastructure change.

## Implementation Details

1. Refactored the PDB template to preserve explicit fixed replicas and override the floor only when HPA is enabled.
2. Moved `product-reviews` production availability to the active HPA configuration.
3. Added the production kube-state-metrics Critical selector.
4. Added numeric floor validation and an isolated `replicas=2`, `minReplicas=1` render that must produce no PDB.
5. Updated deployment and workload-placement guidance to the rendered policy.

## Files Changed

**Templates and values:**
* `templates/pdb.yaml` — Uses the active replica controller for PDB eligibility.
* `values-prod.yaml` — Sets the product-reviews HPA floor and kube-state-metrics placement.

**Validation:**
* `scripts/verify-directive-03.ps1` — Accepts floors of at least two and tests stale fixed-replica behavior.

**Documentation:**
* `docs/operations/workload-placement.md` — Documents production hard spread and PDB ownership.
* `docs/DEPLOYMENT.md` — Corrects production HPA inventory and verification expectations.
* `docs/changes/2026-07-15-harden-pod-scheduling.md` — This change record.

## Dependencies and Cross-Repository Impact

The scheduler contract depends on the Karpenter NodePools and fixed Critical managed-node groups in `techx-corp-infra`.

Related: `techx-corp-infra/docs/changes/2026-07-15-harden-karpenter-scaling.md`

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Product-reviews cannot scale below two replicas in production. |
| **Infrastructure** | No infrastructure resource is changed by this repository. |
| **Deployment** | Argo CD rolls product-reviews and kube-state-metrics after the Git change. |
| **Performance** | No HPA maximum or resource request change. |
| **Security** | No new credential or permission surface. |
| **Reliability** | PDBs represent real availability floors; kube-state-metrics stays on fixed capacity. |
| **Cost** | One additional minimum product-reviews replica in production. |
| **Backward compatibility** | Base/development behavior remains compatible; production availability is stricter. |
| **Observability** | Existing kube-state-metrics series remain available from the Critical tier. |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Production chart lint | `helm lint . -f values-public-alb.yaml -f values-prod.yaml` | Pass |
| Directive policy | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-directive-03.ps1` | Pass |
| PDB regression | Isolated Helm render in the directive script | Pass: HPA floor one renders no PDB despite fixed replicas two |
| Product-reviews render | Directive script and manifest inspection | Pass: HPA floor two, one PDB, no Deployment replicas |

### Manual Verification

The rendered production manifests show zone and hostname `DoNotSchedule` constraints with `minDomains: 2`, and `techx-corp-kube-state-metrics` has `workload-class: critical`.

### Remaining Verification (Post-Merge)

* Confirm Argo CD sync health without direct Helm or kubectl mutation.
* Read-only check that product-reviews has two Ready replicas and one allowed PDB disruption.
* Confirm kube-state-metrics schedules on a Critical node.

## Migration or Deployment Notes

1. Merge through the normal chart repository workflow; Argo CD is the only deployment path.
2. Confirm the Critical managed-node tier passes CPU, memory, and pod-density headroom gates before sync.
3. Observe Pending pods and PDB allowed disruptions during rollout.
4. Do not run direct mutating Helm or kubectl commands against the managed release.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Product-reviews floor increases resource demand | Low | Medium | Verify headroom before sync; revert the production HPA floor through Git if capacity is insufficient. |
| Hard two-domain placement blocks during AZ loss | Medium | Medium | Observe Pending pods during rollout and preserve this deliberate reliability contract unless an approved incident change relaxes it. |
| PDB restricts voluntary maintenance | Low | Medium | Confirm two Ready replicas and PDB health before voluntary node disruption. |

**Rollback procedure:**

Revert this chart change in Git and let Argo CD reconcile the prior manifests. Review the rendered diff first; do not use direct `helm rollback` or mutating kubectl commands.

<!-- Change trail: @hungxqt - 2026-07-15 - Record active-controller PDB and production scheduling hardening. -->
