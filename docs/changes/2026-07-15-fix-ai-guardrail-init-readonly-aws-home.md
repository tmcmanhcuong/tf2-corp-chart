# Change: Fix AI guardrail model fetch init on read-only root

## Summary

The `fetch-ai-guardrail-model` init container failed with
`[Errno 30] Read-only file system: '/.aws'` because the AWS CLI tried to write
under the default home directory on a read-only root filesystem. The init now
points `HOME` and AWS config paths at the writable `/tmp` emptyDir mount.

## Context

* Production pod `product-reviews` in `techx-corp-prod` was CrashLooping on the
  init container `fetch-ai-guardrail-model` (Back-off restarting failed container).
* Chart 0.48.4 introduced private S3 model delivery with a default
  `initContainerSecurityContext.readOnlyRootFilesystem: true` and no `HOME`.
* AWS CLI v2 caches web-identity (IRSA) credentials under `$HOME/.aws`; with
  unset/empty home that resolves to `/.aws` on the container root.

## Before

* Init env only set `AWS_REGION` and `AWS_EC2_METADATA_DISABLED=true`.
* Writable mounts: `/models` (cache) and `/tmp` (`tmp-dir` emptyDir).
* AWS CLI attempted to create `/.aws` → `Errno 30` → init failure → main
  container never started.

## After

* Init env also sets:
  * `HOME=/tmp`
  * `AWS_CONFIG_FILE=/tmp/.aws/config`
  * `AWS_SHARED_CREDENTIALS_FILE=/tmp/.aws/credentials`
* Credential cache and any CLI config writes land on the existing writable
  `tmp-dir` volume under `/tmp`.
* Chart version bumped to `0.48.5`.

## Technical Design Decisions

* **Prefer env redirect over relaxing security context.** Keeping
  `readOnlyRootFilesystem: true` preserves SEC-04 posture; only redirect home.
* **Reuse existing `tmp-dir` mount** rather than adding another emptyDir solely
  for AWS cache.
* Explicit `AWS_CONFIG_FILE` / `AWS_SHARED_CREDENTIALS_FILE` make paths
  independent of AWS CLI defaults if `HOME` handling changes across CLI images.

Alternatives rejected:

* Disable `readOnlyRootFilesystem` for this init only — weaker security for a
  network-capable container.
* Bake credentials into the image — incompatible with IRSA and rotation.

## Implementation Details

1. Extended `fetch-ai-guardrail-model` env in `templates/_objects.tpl`.
2. Bumped `Chart.yaml` to `0.48.5`.
3. Documented the RO-root requirement in `docs/operations/ai-model-delivery.md`.

## Files Changed

**Templates:**
* `templates/_objects.tpl` — Set HOME and AWS config env vars on the model-fetch init.

**Chart metadata:**
* `Chart.yaml` — Version `0.48.4` → `0.48.5`.

**Documentation:**
* `docs/operations/ai-model-delivery.md` — Init RO-root / HOME note and prod verification example.
* `docs/changes/2026-07-15-fix-ai-guardrail-init-readonly-aws-home.md` — This change record.

## Dependencies and Cross-Repository Impact

* Depends on the existing model-delivery design from chart/infra
  `2026-07-15-ai-guardrail-model-delivery` (IRSA role, S3 artifact, prod URI).
* No platform image or Terraform change required for this fix.
* Related: `techx-corp-infra/docs/changes/2026-07-15-ai-guardrail-model-delivery.md`

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | product-reviews can complete init and start when S3/IRSA are healthy |
| **Infrastructure** | No change |
| **Deployment** | Chart sync to `0.48.5` (Argo CD auto-sync) |
| **Performance** | Negligible; same download path |
| **Security** | Unchanged least-privilege; RO root retained |
| **Reliability** | Removes false-fail init CrashLoop from AWS CLI home path |
| **Cost** | None |
| **Backward compatibility** | Fully compatible |
| **Observability** | Init logs should show successful `aws s3 cp` instead of Errno 30 |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Helm lint (prod overlay) | `helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml` | Run at change time |
| Helm template (init env) | `helm template` grep for `HOME` / `AWS_CONFIG_FILE` under fetch init | Run at change time |

### Manual Verification

After Argo sync in prod:

```cmd
kubectl -n techx-corp-prod logs deployment/product-reviews -c fetch-ai-guardrail-model
kubectl -n techx-corp-prod get pod -l opentelemetry.io/name=product-reviews
kubectl -n techx-corp-prod rollout status deployment/product-reviews --timeout=10m
```

Expect: init completes without `/.aws` Errno 30; pod reaches Ready (assuming
S3 object and IRSA remain valid).

### Remaining Verification (Post-Merge)

* Operator: confirm prod artifact still exists at the configured `s3Uri`.
* Operator: if init still fails after this fix, inspect IRSA/S3 access
  (AccessDenied, NoSuchKey) separately from the filesystem issue.

## Migration or Deployment Notes

1. Commit and push this chart change; Argo CD auto-syncs `techx-corp-chart`.
2. No manual `helm upgrade` or `kubectl` mutate (GitOps).
3. Post-sync: verify init logs and pod Ready as above.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Residual S3/IRSA misconfig still fails init | Medium | Medium | Fail-closed by design; fix IAM/object, not this chart path |
| Older AWS CLI image ignores env vars | Low | Low | HOME=/tmp is standard; pin remains `aws-cli:2.27.49` |

**Rollback procedure:**

Revert this chart commit (or pin Application to previous chart revision /
`0.48.4`). That restores the previous init env and will reintroduce the `/.aws`
failure until a different fix is applied.

<!-- Change trail: @hungxqt - 2026-07-15 - Fix fetch-ai-guardrail-model RO-root HOME for AWS CLI. -->
