# Change: Validation runbook — production Karpenter consolidateAfter 5m

## Summary

Updated the autoscaling validation runbook so production Karpenter consolidation wait matches the infra contract of `5m` (was documented as `10m`).

## Context

Production Terraform `karpenter_consolidate_after` was changed from `10m` to `5m` in `techx-corp-infra`. The chart-owned validation runbook still instructed operators to expect a 10-minute production delay and would have produced false failures or confusion during scale-in checks.

* Why now: keep operator acceptance steps aligned with the infra NodePool contract.
* Related: `techx-corp-infra/docs/changes/2026-07-15-prod-karpenter-consolidate-after-5m.md`.

## Before

* `docs/operations/autoscaling-validation.md` step 7: wait `5m` in development or `10m` in production before consolidation.

## After

* Same step expects `5m` in development and production.

## Technical Design Decisions

* **Docs-only chart change** — consolidation timing is owned by infra NodePools; the chart only documents the expected evidence window.
* No Helm values or templates changed.

## Implementation Details

1. Edited scale-in step 7 in `docs/operations/autoscaling-validation.md` to state `5m` for both environments.

## Files Changed

**Documentation:**
* `docs/operations/autoscaling-validation.md` — Production consolidation wait `10m` → `5m`.
* `docs/changes/2026-07-15-prod-karpenter-consolidate-after-5m.md` — This change record.

## Dependencies and Cross-Repository Impact

* Depends on infra applying `karpenter_consolidate_after = "5m"` in production for live behavior to match this runbook.
* Related: `techx-corp-infra/docs/changes/2026-07-15-prod-karpenter-consolidate-after-5m.md`.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | No runtime change from this chart edit |
| **Deployment** | No Helm/Argo change; documentation only |
| **Observability** | Validation evidence window for consolidation is 5 minutes in both envs |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Doc review | Diff of autoscaling-validation consolidation step | ✅ `5m` for development and production |

### Manual Verification

* None required for docs-only update.

### Remaining Verification (Post-Merge)

* After infra production apply, run scale-in steps in this runbook and confirm consolidation eligibility ~5m after underutilization.

## Migration or Deployment Notes

None. Documentation only; no chart deploy.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Runbook diverges if infra reverts to `10m` | Low | Low | Revert this doc change with the matching infra rollback |

**Rollback procedure:**

Restore step 7 text to expect `10m` in production if infra returns to `10m`.

<!-- Change trail: @hungxqt - 2026-07-15 - Record chart runbook align for prod Karpenter consolidateAfter 5m. -->
