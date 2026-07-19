# Change: Remove Production Per-Service Image Overrides

## Summary

Removed all `imageOverride` pins from `values-prod.yaml` so every release service uses the global `default.image.repository` and `default.image.tag` contract only. Checkout, accounting, and load-generator-worker no longer pin separate tags or full repository paths.

## Context

* Production overlay had temporary per-service image pins (different SHA tags or an explicit full repository for the load-generator worker).
* The platform/chart promote path assumes one global runtime tag for all nested services.
* Per-service overrides break that contract and leave prod partially on older digests after a full-catalog promote.

## Before

`values-prod.yaml` contained:

* `components.checkout.imageOverride.tag: "sha-033949b"`
* `components.accounting.imageOverride.tag: "sha-59fb903"`
* `components.load-generator-worker.imageOverride.repository: …/techx-prod-corp/load-generator`

Global `default.image.tag` remained separate (`sha-53f7fb1` at time of edit).

## After

* No `imageOverride` keys under any component in `values-prod.yaml`.
* Checkout, accounting, and load-generator-worker inherit `default.image.repository` + `default.image.tag` (templates append `/<service>` as usual).
* Other prod settings (HA floors, MSK/Valkey env, mem0, ALB, etc.) are unchanged.
* Utility init image `busybox:1.37.0` for cart’s managed-Valkey wait remains (not a release-service pin).

## Technical Design Decisions

* **Remove overrides rather than retarget them to the current global tag** — empty inheritance is the intended GitOps promote model; re-pinning recreates drift risk.
* **Keep `default.image.tag`** — that is the global promote field, not a per-service override.
* **Keep load-generator-worker envOverrides** — LOCUST tag exclusion is config, not an image pin.

## Implementation Details

1. Deleted `imageOverride` under `components.checkout`.
2. Deleted `imageOverride` under `components.accounting`.
3. Deleted `imageOverride` under `components.load-generator-worker`.
4. Updated the file change trail.

## Files Changed

**Configuration:**
* `values-prod.yaml` — Removed three `imageOverride` blocks.

**Documentation:**
* `docs/changes/2026-07-19-remove-prod-image-overrides.md` — This change record.

## Dependencies and Cross-Repository Impact

* After Argo sync, checkout, accounting, and load-generator-worker will run the current `default.image.tag` digests from `techx-prod-corp`.
* Ensure that global tag exists in ECR for **all** services (including checkout, accounting, load-generator) before merge, or pods will fail ImagePull.
* None required in platform or infra for this values-only cleanup.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Checkout, accounting, and load-generator-worker switch from pinned digests to the global prod tag |
| **Infrastructure** | No change |
| **Deployment** | Argo CD auto-sync rolls those Deployments when the values PR merges |
| **Performance** | None expected |
| **Security** | Aligns runtime with the promoted global image set |
| **Reliability** | Removes mixed-tag prod fleet for those three services |
| **Cost** | None |
| **Backward compatibility** | Intentional: drops per-service image pins |
| **Observability** | None |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Grep for imageOverride in prod overlay | search `imageOverride` in `values-prod.yaml` | ✅ No matches after edit |

### Manual Verification

* Confirmed only the three listed override blocks existed; global `default.image` retained.
* Helm template / cluster smoke not run in this session (GitOps apply after merge).

### Remaining Verification (Post-Merge)

1. Argo CD app `techx-corp` (or prod Application) syncs healthy.
2. Pods for checkout, accounting, load-generator-worker show image `…/techx-prod-corp/<service>:<default.image.tag>`.
3. Smoke storefront browse → cart → checkout path.

## Migration or Deployment Notes

1. Confirm ECR has images for the current `default.image.tag` for checkout, accounting, and load-generator.
2. Merge this chart change; allow Argo CD auto-sync (do not `helm upgrade` directly).
3. Watch rollouts for the three components.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Global tag missing for a formerly pinned service | Low | High | Verify ECR tags before merge; fix by promoting a complete catalog |
| Regression vs temporary pin behavior | Low | Medium | Revert this values change or reintroduce a short-lived override |

**Rollback procedure:**

1. Restore the three `imageOverride` blocks from git history on `values-prod.yaml`.
2. Commit/push; Argo CD syncs the previous pins.

<!-- Change trail: @hungxqt - 2026-07-19 - Document removal of prod per-service imageOverride pins. -->
