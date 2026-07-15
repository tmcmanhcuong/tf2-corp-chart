# Change: flagd singleton on Critical MNG

## Summary

Production `flagd` is scaled back from two replicas to **one**, and placement is pinned exclusively to Critical MNG (`workload-class=critical` / `system-*`) with no topology spreads. Directive #3 verification and ops docs treat flagd as a reviewed singleton exception outside the money-path two-replica floor.

## Context

* Two flagd replicas were added only for Directive #3 drain HA, not load.
* BTC chaos keys already come from a shared HTTP source; each replica polled independently.
* Multi-replica flagd with per-pod emptyDir + flagd-ui splits `local-*` UI state across pods.
* Operators confirmed singleton + Critical MNG pin is preferred over multi-replica HA for this control plane.

## Before

* `values-prod.yaml`: `components.flagd.replicas: 2` with `schedulingRules: *directive03-hard-spread` (zone/hostname hard spreads layered on critical placement).
* `scripts/verify-directive-03.ps1` required flagd fixed `replicas: 2`, PDB, and hard spreads.
* Ops docs described flagd as a multi-replica critical service with preferred multi-host spread.

## After

* `values-prod.yaml`: `replicas: 1` and explicit Critical MNG scheduling:

  ```yaml
  schedulingRules:
    nodeSelector:
      workload-class: critical
    affinity: {}
    tolerations: []
    topologySpreadConstraints: []
  ```

* No flagd PDB (chart only renders PDBs for multi-replica Deployments).
* Verify script asserts flagd singleton + critical pin and rejects PDB / topology spreads for flagd.
* Directive #3 runbook and evidence checklist document the singleton exception.

## Technical Design Decisions

* **Singleton over HA floor for flagd** — load is tiny; BTC authority is HTTP; dual emptyDir was worse for local toggles than single-pod brief unavailability during drain.
* **Keep Critical MNG pin** — control plane stays off Karpenter Spot (`system-*` / `workload-class=critical`).
* **Clear topology spreads** — spreads are meaningless for one replica and could confuse capacity planning on the small MNG floor.
* **Policy script exception** — money-path services remain at two; flagd is checked separately so the gate does not force HA that we intentionally removed.

## Implementation Details

1. Set prod flagd `replicas: 1` and full critical `schedulingRules` (no hard-spread anchor).
2. Removed flagd from the multi-replica loop in `verify-directive-03.ps1`; added singleton assertions.
3. Updated Directive #3 maintenance runbook, evidence template, and workload-placement docs.
4. Dual-source flagd command (file + BTC HTTP) is unchanged.

## Files Changed

**Configuration:**

* `values-prod.yaml` — flagd `replicas: 1`; Critical MNG pin; no topology spreads.

**Scripts:**

* `scripts/verify-directive-03.ps1` — flagd singleton + critical nodeSelector policy.

**Documentation:**

* `docs/operations/directive-03-maintenance.md` — singleton exception in controls and pre-flight.
* `docs/operations/directive-03-evidence-template.md` — checklist wording for flagd singleton.
* `docs/operations/workload-placement.md` — flagd no longer multi-replica spread.
* `docs/changes/2026-07-15-flagd-singleton-critical-mng.md` — this change record.

## Dependencies and Cross-Repository Impact

None. Platform apps still resolve flags via in-cluster flagd Service; no image change.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Unchanged when flagd is Ready. During flagd pod restart/drain there is a brief window with no Ready endpoints; evaluations use OpenFeature defaults (typically OFF). |
| **Infrastructure** | One fewer flagd pod on Critical MNG; still requires `workload-class=critical` capacity. |
| **Deployment** | Argo sync rolls flagd Deployment to 1 replica on critical nodes. |
| **Reliability** | Removes flagd multi-pod HA during node drain; money-path services remain multi-replica. |
| **Security** | No change. |
| **Observability** | No change. |
| **Backward compatibility** | Dual-source flags and dual-read apps unchanged. Local UI state is consistent on a single emptyDir. |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Helm lint (prod) | `helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml` | Pass (icon INFO only) |
| Template pin | `helm template` flagd Deployment | Pass — `replicas: 1`, `nodeSelector.workload-class: critical`, no topologySpreadConstraints, no flagd PDB, safe rollout + preStop present |
| Directive #3 policy | `powershell -File scripts/verify-directive-03.ps1` | Pre-existing fail on `frontend` HPA exact `minReplicas: 2` (prod uses 3); flagd is no longer in the multi-replica loop and has a dedicated singleton assert block |

### Manual Verification

* After Argo sync: one Ready `flagd` pod on a Critical MNG / `system-*` node.
* Confirm BTC flag evaluation still works (HTTP source).
* Optional: toggle `local-*` in `/feature` and confirm consistent inject (single emptyDir).

### Remaining Verification (Post-Merge)

* Operator: Argo sync prod Application; wait for flagd Ready.
* If mentor drain hits the flagd node, expect brief flag-evaluation blip (documented residual risk).

## Migration or Deployment Notes

1. Merge chart PR; Argo auto-syncs.
2. No infra or secrets change.
3. Old second flagd pod is terminated by Deployment scale-down.

```cmd
cd /d techx-corp-chart
helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\verify-directive-03.ps1
```

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| flagd pod or Critical MNG node down during traffic | Low | Medium | Flags fail-open to defaults; money path continues without chaos inject; restore `replicas: 2` + hard spread if HA required |
| Drain of sole flagd node causes short OFREP/RPC errors | Medium | Low | Documented residual; apps default false/0 for most chaos keys |

**Rollback procedure:**

1. Revert `values-prod.yaml` flagd block to `replicas: 2` and `schedulingRules: *directive03-hard-spread`.
2. Restore previous verify-script multi-replica assertions for flagd.
3. Argo sync.

<!-- Change trail: @hungxqt - 2026-07-15 - flagd singleton on Critical MNG production placement. -->
