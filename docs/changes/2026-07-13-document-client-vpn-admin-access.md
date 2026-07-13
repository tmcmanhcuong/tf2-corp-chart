# Change: Document Client VPN admin access to internal storefront ALB

## Summary

Documented that operators open admin/observability paths via **AWS Client VPN** against the **existing internal** storefront ALB. No new Ingress or path-block changes; smoke-test help text clarifies that `-a` is CloudFront only.

## Context

Infra introduced optional Client VPN (`techx-corp-infra` module + `docs/client-vpn.md`). Chart already uses `scheme: internal` with no ALB path blocks; public 403s are at CloudFront. Operators need chart-side guidance aligned with that model.

## Before

* Chart docs described internal ALB + CloudFront path blocking only.
* No pointer to Client VPN for private `/grafana` / `/jaeger` access.
* Smoke script help did not warn against using internal ALB for edge 403 checks.

## After

* `values-public-alb.yaml` header notes VPN → this ALB (no second admin Ingress).
* `docs/DEPLOYMENT.md` storefront section includes Client VPN row and verify curl.
* `scripts/smoke-test.sh` comments/help point at Client VPN for admin 200s.

## Technical Design Decisions

* **Docs only in chart:** Routing already correct; a second Ingress would violate the edge ADR.
* **Smoke stays edge-focused:** Admin 200s require VPN; not asserted in default CI/smoke.

## Implementation Details

1. Updated overlay comments and deployment runbook.
2. Clarified smoke-test usage for CloudFront vs internal ALB.

## Files Changed

* `values-public-alb.yaml` — Client VPN admin-access comment.
* `docs/DEPLOYMENT.md` — Client VPN row + verify step.
* `scripts/smoke-test.sh` — Header and `-a` help text.
* `docs/changes/2026-07-13-document-client-vpn-admin-access.md` — This change record.

## Dependencies and Cross-Repository Impact

* Related: `techx-corp-infra/docs/changes/2026-07-13-introduce-client-vpn-for-internal-paths.md`
* Related: `techx-corp-platform` frontend-proxy guide dual-path update.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | None |
| **Infrastructure** | None (docs only) |
| **Deployment** | None |
| **Backward compatibility** | Fully compatible |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| N/A (docs/comments) | — | N/A |

### Manual Verification

* Comments match infra Client VPN runbook.

### Remaining Verification (Post-Merge)

* None for chart; live VPN enable is an infra operator step.

## Migration or Deployment Notes

None.

## Risks and Rollback

None for documentation-only change.

**Rollback procedure:** Revert this change document and the three doc/comment edits.
