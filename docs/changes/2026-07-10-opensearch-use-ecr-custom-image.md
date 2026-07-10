# Change: Deploy customized OpenSearch from ECR

## Context

The OpenSearch Helm subchart defaulted to the public `opensearchproject/opensearch` image. That image includes plugins (notably Performance Analyzer) that emit startup errors when config metadata files are missing. Platform already builds a customized image (`src/opensearch/Dockerfile`) that removes unused plugins; that image is now published to ECR as part of the platform release catalog.

## Before

* `opensearch` values did not override `image.repository` / `image.tag` → chart used Docker Hub default.
* Dev/prod overlays only set `default.image.*` for app components.

## After

* Base and env overlays set OpenSearch to the ECR custom image:
  * Prod: `…/techx-corp/opensearch:<tag>`
  * Dev: `…/techx-dev-corp/opensearch:<tag>`
* `majorVersion: "3"` is set so the chart helper does not require a semver image tag (`sha-*` / `v*` tags).
* Promotion docs require keeping `opensearch.image.tag` in sync with `default.image.tag`.

## Implementation

1. Added `opensearch.image` and `majorVersion` in `values.yaml`.
2. Overrode repository + tag in `values-dev.yaml` and `values-prod.yaml`.
3. Documented the dual-tag contract in `docs/DEPLOYMENT.md` and `docs/operations/gitops-argocd.md`.
4. Updated SEC-04 notes for the ECR image source.

## Files Changed

* `values.yaml` — ECR image + majorVersion for OpenSearch subchart.
* `values-dev.yaml` / `values-prod.yaml` — env-specific OpenSearch image repository and tag.
* `docs/DEPLOYMENT.md` — image convention for OpenSearch.
* `docs/operations/gitops-argocd.md` — promote checklist includes opensearch.
* `SEC-04-notes.md` — image reference updated.

## Impact

* **Application behavior:** OpenSearch pods pull customized ECR image; Performance Analyzer and other stripped plugins are absent.
* **Deployment:** Operators must update **both** `default.image.tag` and `opensearch.image.tag` on every promotion.
* **Backward compatibility:** Requires platform CI to have pushed `opensearch` for the chosen tag before Argo sync.

## Validation

* Helm values review: `opensearch.image.repository` is full ECR path; tag matches env `default.image.tag`.
* After first successful platform publish + Argo sync: pod image shows ECR path; Performance Analyzer `plugin-stats-metadata` errors should stop.

## Migration or Deployment Notes

1. Ensure platform release for the target tag includes `opensearch` in ECR (new platform CI catalog).
2. Verify: `aws ecr describe-images --repository-name techx-dev-corp/opensearch --image-ids imageTag=<tag>`.
3. Sync Argo Application after merging this chart change with matching tags.

If the currently committed dev tag (`sha-0d4b544`) does not yet have an OpenSearch image in ECR, either:

* re-publish that SHA (workflow_dispatch) after the platform bake change, or
* promote to a newer tag that includes OpenSearch after the platform change lands.

## Risks and Rollback

* Risk: ImagePullBackOff if tag missing on `…/opensearch`.
* Rollback: remove `opensearch.image` overrides so the subchart falls back to `opensearchproject/opensearch` (public image); reintroduce Performance Analyzer log noise.
