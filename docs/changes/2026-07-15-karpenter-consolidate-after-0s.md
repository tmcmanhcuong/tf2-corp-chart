# Change: Validation runbook — Karpenter consolidateAfter 0s

## Summary

Updated the autoscaling validation runbook so scale-in evidence expects immediate empty consolidation (`consolidateAfter: 0s`), including DaemonSet-only nodes such as otel-collector agent only.

## Context

Infra set `karpenter_consolidate_after = "0s"` so empty nodes reclaim without a multi-minute settle delay. The chart-owned validation runbook previously expected a five-minute wait and would mislead operators.

* Related: `techx-corp-infra/docs/changes/2026-07-15-karpenter-consolidate-after-0s.md`.

## Before

* Step 7 expected a `5m` consolidation wait in development and production.

## After

* Step 7 expects `consolidateAfter: 0s` with DaemonSet-only / empty nodes (including otel agent only) reclaiming immediately, subject to PDBs.

## Technical Design Decisions

* Docs-only chart change; consolidation timing remains owned by infra NodePools.
* No Helm values or otel collector template changes (already `mode: daemonset`).

## Implementation Details

1. Edited scale-in step 7 in `docs/operations/autoscaling-validation.md`.

## Files Changed

**Documentation:**
* `docs/operations/autoscaling-validation.md` — Consolidation wait guidance updated to `0s` / empty immediate.
* `docs/changes/2026-07-15-karpenter-consolidate-after-0s.md` — This change record.

## Dependencies and Cross-Repository Impact

* Depends on infra applying `consolidateAfter: 0s` for live behavior to match.
* Related: `techx-corp-infra/docs/changes/2026-07-15-karpenter-consolidate-after-0s.md`.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | No runtime change from this chart edit |
| **Deployment** | Documentation only |
| **Observability** | Validation expects immediate empty reclaim after scale-in |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Doc review | Diff of autoscaling-validation step 7 | ✅ `0s` / DaemonSet-only immediate |

### Manual Verification

* None required for docs-only update.

### Remaining Verification (Post-Merge)

* After infra apply, confirm empty (otel agent + system DaemonSets only) nodes consolidate without a multi-minute delay during scale-in tests.

## Migration or Deployment Notes

None. Documentation only.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Runbook diverges if infra raises consolidateAfter | Low | Low | Revert this doc with the matching infra rollback |

**Rollback procedure:**

Restore step 7 to the previous settle-delay wording if infra returns to a positive `consolidateAfter`.

<!-- Change trail: @hungxqt - 2026-07-15 - Record chart runbook for Karpenter consolidateAfter 0s. -->
