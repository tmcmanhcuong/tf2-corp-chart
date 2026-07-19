# Change: Fix load-generator-worker Image to Follow Global Project

## Summary

`load-generator-worker` no longer hardcodes a full ECR repository path under `techx-corp`. It remaps only the service segment to `load-generator` via `imageOverride.name`, so production pulls `…/techx-prod-corp/load-generator:<default.image.tag>` (and development uses its global project the same way).

## Context

* Component key is `load-generator-worker`, but the platform bake/ECR catalog publishes a single image named **`load-generator`** (master and worker share that image).
* Templates default to `default.image.repository/<component-name>:<tag>`, which would resolve to a non-existent `…/load-generator-worker` repo.
* Base `values.yaml` therefore set a full `imageOverride.repository` to  
  `493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-corp/load-generator`.
* After removing the prod overlay full-path pin, workers fell back to that base pin and pulled **`techx-corp`** instead of **`techx-prod-corp`**, with the current global tag (`sha-53f7fb1`).

Observed image:

```text
493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-corp/load-generator:sha-53f7fb1
```

## Before

| Source | Behavior |
|---|---|
| Template | Full `imageOverride.repository` replaces the whole image path |
| `values.yaml` | Hardcoded `…/techx-corp/load-generator` |
| Tag | Still from `default.image.tag` when override omits `tag` |

## After

| Source | Behavior |
|---|---|
| Template | Optional `imageOverride.name` replaces only the service segment |
| `values.yaml` | `imageOverride.name: load-generator` |
| Resolved prod image | `…/techx-prod-corp/load-generator:<default.image.tag>` |

## Technical Design Decisions

* **`name` remap vs full repository** — keeps env project (`techx-prod-corp` / `techx-dev-corp`) and global tag on the promote path; only renames the service segment for dual-role Locust image.
* **Keep full `repository` override for third-party images** (flagd, postgres, valkey) unchanged.
* **Do not invent an ECR repo `load-generator-worker`** — platform catalog is still one image.

## Implementation Details

1. `_objects.tpl` Deployment and sidecar image blocks:  
   `default.image.repository / (imageOverride.name | default component name) : tag`
2. `components.load-generator-worker.imageOverride` → `{ name: load-generator }`
3. Documented `imageOverride.name` in the components comment block.

## Files Changed

**Templates:**
* `templates/_objects.tpl` — Support `imageOverride.name` service-segment remap.

**Configuration:**
* `values.yaml` — Worker uses `name: load-generator`; comment for override shapes.
* `values.schema.json` — Allow `Image.name` on imageOverride schema.

**Documentation:**
* `docs/changes/2026-07-19-load-generator-worker-image-name-override.md` — This change record.

Change trail exception for `values.schema.json`: JSON does not support comments.

## Dependencies and Cross-Repository Impact

* Requires ECR image `techx-prod-corp/load-generator:<current default.image.tag>` (same as master).
* No platform bake catalog change.
* Related prior: `docs/changes/2026-07-19-remove-prod-image-overrides.md` (removed prod full-path pin that had masked the base hardcode).

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Worker pulls correct env project + `load-generator` image |
| **Infrastructure** | No change |
| **Deployment** | Argo sync updates Deployment image |
| **Performance** | None |
| **Security** | Stops accidental pull from non-prod `techx-corp` project when running prod |
| **Reliability** | Aligns with global image contract |
| **Cost** | None |
| **Backward compatibility** | Full `imageOverride.repository` still works for third-party components |
| **Observability** | None |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Values inspect | `imageOverride.name: load-generator` | ✅ Present |
| Template logic | `imageOverride.name \| default .name` | ✅ Both image sites updated |
| Helm schema | `helm template … -f values-prod.yaml` | ✅ Pass |
| Rendered worker image | `…/techx-prod-corp/load-generator:sha-53f7fb1` | ✅ Master + worker |

### Manual Verification

* Explained observed image as base full-path pin + global tag inheritance.
* Cluster render/sync not run in this session.

### Remaining Verification (Post-Merge)

```cmd
helm template techx-corp . -n techx-corp-prod -f values.yaml -f values-public-alb.yaml -f values-prod.yaml | findstr /i "load-generator"
```

Expect worker container image:

```text
…/techx-prod-corp/load-generator:<default.image.tag>
```

Then Argo sync and confirm pod image.

## Migration or Deployment Notes

1. Merge chart change; Argo auto-syncs.
2. Confirm `techx-prod-corp/load-generator` has the current global tag in ECR.
3. No need to reintroduce a prod full-path `imageOverride.repository`.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Global tag missing for load-generator | Low | High | Verify ECR before sync |
| Template name field unused elsewhere | Low | Low | Optional field; no-op when unset |

**Rollback procedure:**

1. Restore `imageOverride.repository` full path (prefer `techx-prod-corp` for prod) and/or revert template.
2. Git push; Argo sync.

<!-- Change trail: @hungxqt - 2026-07-19 - Document load-generator-worker imageOverride.name fix; schema exception for values.schema.json. -->
