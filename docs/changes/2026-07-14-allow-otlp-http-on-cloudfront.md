# Change: Align chart docs with CloudFront `/otlp-http` allow

## Summary

Updated chart comments and emergency ALB block-prefix list so `/otlp-http` is not treated as a blocked admin path. Public browser OTLP is allowed at CloudFront (infra change); chart notes match that policy.

## Context

Infra removed `/otlp-http` from the CloudFront Function block list so `POST /otlp-http/v1/traces` from the storefront works. Chart overlay comments and optional emergency `blockedPrefixes` still listed `/otlp-http`, which was misleading.

## Before

* Comments listed `/otlp-http` among CF-blocked prefixes.
* Emergency ALB `blockedPrefixes` included `/otlp-http`.

## After

* Comments state `/otlp-http` is allowed for browser OTLP.
* Emergency ALB list no longer includes `/otlp-http` (so break-glass ALB blocks do not break telemetry if enabled).

## Technical Design Decisions

* Chart does not own CloudFront Function code; this is documentation + emergency ALB list alignment only.

## Implementation Details

1. Updated `values-public-alb.yaml` CF block list comment.
2. Removed `/otlp-http` from `values.yaml` `publicAlb.blockedPrefixes` with a note.
3. Updated `docs/DEPLOYMENT.md` CloudFront row.

## Files Changed

* `values.yaml` — Emergency blockedPrefixes without `/otlp-http`.
* `values-public-alb.yaml` — Comment.
* `docs/DEPLOYMENT.md` — CloudFront block list note.
* `docs/changes/2026-07-14-allow-otlp-http-on-cloudfront.md` — This change record.

## Dependencies and Cross-Repository Impact

* Related: `techx-corp-infra/docs/changes/2026-07-14-allow-otlp-http-on-cloudfront.md` (actual CloudFront Function change).

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | No runtime change unless emergency ALB path blocks are enabled |
| **Deployment** | Docs/values only; CF fix requires infra apply |
| **Backward compatibility** | Fully compatible |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| N/A | Comment/list-only | N/A |

### Manual Verification

None required for chart-only alignment; verify after infra apply.

### Remaining Verification (Post-Merge)

None for chart.

## Migration or Deployment Notes

None for chart. Apply **infra** production Terraform to change live CloudFront 403 behavior.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| None material | — | — | Re-add prefix to emergency list if desired |

**Rollback:** restore `/otlp-http` in chart comments/`blockedPrefixes` if needed.
