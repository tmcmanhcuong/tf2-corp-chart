# Change: Extract AI guardrail model with busybox (aws-cli has no tar)

## Summary

The `product-reviews` model bootstrap init failed after a successful checksum
with `tar: command not found` because the official AWS CLI image does not ship
`tar`. Extraction now runs in a second init container based on busybox. The
fetch init also strips CR from the `.sha256` file so Windows CRLF uploads do
not break `sha256sum -c`.

## Context

* Live prod init progression after S3 artifact publication:
  1. `HOME`/RO-root fix (chart 0.48.5)
  2. Checksum object had CRLF → `model.tar.gz: FAILED open or read`
  3. After LF checksum (or in-pod strip), verify succeeded → `tar: command not found`
* `public.ecr.aws/aws-cli/aws-cli:2.27.49` is intentionally minimal; it has
  `aws` and `sha256sum` but not `tar`.
* Chart version was `0.48.5`.

## Before

* Single init `fetch-ai-guardrail-model` downloaded, verified, extracted, and
  checked `.model-ready` in one shell script on the AWS CLI image.
* No `extractorImage` field.
* No CRLF normalization before `sha256sum -c`.

## After

* `fetch-ai-guardrail-model` (AWS CLI): download archive + checksum to `/tmp`,
  strip trailing CR from the checksum file, run `sha256sum -c`.
* `extract-ai-guardrail-model` (busybox): `tar -xzf` into `/models`, require
  `.model-ready`, delete the archive from `/tmp`.
* `modelDelivery.extractorImage` defaults to `busybox:1.37.0`.
* Chart version `0.48.6`.

## Technical Design Decisions

* **Two inits over a custom image.** Reuses the pinned AWS CLI image and the
  same busybox family already used for wait-for-* inits; avoids maintaining a
  private aws+tar image.
* **Keep archive on `tmp-dir`, extract to `ai-model-cache`.** Matches the prior
  volume layout; extract init mounts both.
* **Strip CR in-pod.** Operational defense if publishers re-upload from Windows;
  LF-only objects remain the preferred artifact format.
* **Do not relax `readOnlyRootFilesystem`.** HOME=/tmp pattern for the AWS CLI
  init is unchanged.

## Implementation Details

1. Split model delivery script in `templates/_objects.tpl` into fetch and extract
   init containers.
2. Added `extractorImage` to `values.yaml` and `values.schema.json`.
3. Bumped chart to `0.48.6`.
4. Documented the split and LF checksum rule in
   `docs/operations/ai-model-delivery.md`.

## Files Changed

**Templates:**
* `templates/_objects.tpl` — Fetch-only AWS CLI init; new busybox extract init;
  CRLF strip before checksum.

**Configuration:**
* `values.yaml` — `modelDelivery.extractorImage: busybox:1.37.0` and comments.
* `values.schema.json` — Allow `extractorImage` string.
* `Chart.yaml` — Version `0.48.6`.

**Documentation:**
* `docs/operations/ai-model-delivery.md` — Two-init table, LF checksum note,
  extract log command.
* `docs/changes/2026-07-15-ai-guardrail-extract-init-busybox.md` — This record.

Change trail exception for `values.schema.json`: JSON does not support comments.

## Dependencies and Cross-Repository Impact

* None for platform or infra code.
* Operators must sync this chart revision (GitOps) after merge; no S3 re-upload
  is required if the archive and LF checksum are already present.
* Related prior: `docs/changes/2026-07-15-fix-ai-guardrail-init-readonly-aws-home.md`,
  `docs/changes/2026-07-15-ai-guardrail-model-delivery.md`.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Unblocks product-reviews startup when model bootstrap reaches extract |
| **Infrastructure** | No change |
| **Deployment** | Chart sync; pod gains a second init (`Init:0/3` when wait-for-postgresql is present) |
| **Performance** | One extra short-lived busybox container per pod start |
| **Security** | Same SEC-04 init securityContext; no new IAM/S3 surface |
| **Reliability** | Removes hard dependency on `tar` inside the AWS CLI image |
| **Cost** | Negligible (busybox pull once per node) |
| **Backward compatibility** | Requires chart values that include `extractorImage` (set in base values) |
| **Observability** | New log stream: `-c extract-ai-guardrail-model` |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Helm lint (prod overlay) | `helm lint . -f values.yaml -f values-prod.yaml` | Pass |
| Helm template contains extract init | `helm template` grep extract-ai-guardrail-model | Pass |

### Manual Verification

* Live failure reproduced: `model.tar.gz: OK` then `tar: command not found`.
* Post-sync: confirm fetch and extract inits complete and main container Ready.

### Remaining Verification (Post-Merge)

* Argo CD sync chart to prod (and dev if applicable).
* `kubectl logs ... -c fetch-ai-guardrail-model` and `-c extract-ai-guardrail-model`.
* `kubectl rollout status deployment/product-reviews`.

## Migration or Deployment Notes

1. Merge and push `techx-corp-chart` so Argo CD reconciles chart `0.48.6`.
2. Do not run direct `helm upgrade` against the Argo-managed release.
3. After sync, wait for product-reviews rollout; init order is fetch → extract →
   wait-for-postgresql (existing) → main.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| busybox image pull blocked | Low | Medium | Pin matches other wait-for inits; node already caches busybox |
| Extract OOM on large archive | Low | Medium | tar streams; same resource block as fetch; raise limits if needed |
| emptyDir sizeLimit too small for extracted tree | Medium | High | `cacheSizeLimit: 2Gi` already set; monitor extract failures |

**Rollback procedure:**

Revert this chart commit (or pin Argo to previous chart revision) so the pod
spec returns to the single-init script. Note: that prior script still cannot
extract on aws-cli-only; rollback only helps if rolling back to a chart that
does not require external model delivery.

<!-- Change trail: @hungxqt - 2026-07-15 - Split AI model bootstrap into aws-cli fetch and busybox extract inits. -->
