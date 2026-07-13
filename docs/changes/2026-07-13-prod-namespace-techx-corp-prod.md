# Change: Production Namespace Renamed to techx-corp-prod in DEPLOYMENT.md

## Summary

Updated `docs/DEPLOYMENT.md` so the documented production Kubernetes namespace is `techx-corp-prod` instead of `techx-corp`, aligning the runbook with the intended prod destination namespace while leaving Helm/Argo release and Application names as `techx-corp`.

## Context

- Production previously shared the short name `techx-corp` for both release identity and namespace.
- Dev already uses the explicit namespace `techx-corp-dev`; production should follow the same pattern with `techx-corp-prod`.
- This change is documentation-only for the chart runbook; operators and GitOps manifests must match the same destination namespace in live cluster config.

## Before

- Production table constant: Namespace = `techx-corp`.
- GitOps contract Destination NS (prod) = `techx-corp`.
- All prod helm/kubectl/smoke examples used `-n techx-corp` / `--namespace techx-corp`.

## After

- Production table constant: Namespace = `techx-corp-prod`.
- GitOps contract Destination NS (prod) = `techx-corp-prod`.
- All prod helm/kubectl/smoke examples use `-n techx-corp-prod` / `--namespace techx-corp-prod`.
- Unchanged on purpose: Helm/Argo release name `techx-corp`, Argo Application/AppProject `techx-corp`, ECR project `techx-corp/*`, ASM path `techx-corp/production`, and all `techx-corp-dev` references.

## Technical Design Decisions

- **Namespace-only rename in the doc** — release and Argo Application names stay `techx-corp` to avoid implying a full identity rename until GitOps/live resources are updated separately.
- **No silent rewrite of ECR or secrets paths** — those use the project prefix `techx-corp`, not the Kubernetes namespace.
- **GitOps YAML not changed in this edit** — only the deployment runbook; follow-up may be needed for `gitops/clusters/prod/*` if live destination still points at `techx-corp`.

## Implementation Details

1. Updated Production constants table (`Namespace` row).
2. Updated GitOps contract table Destination NS column for prod only.
3. Replaced prod kubectl/helm `-n` and smoke `--namespace` flags to `techx-corp-prod`.
4. Updated related prose (release vs namespace note, apply comments).

## Files Changed

**Documentation:**
* `docs/DEPLOYMENT.md` — Production namespace `techx-corp` → `techx-corp-prod` in constants, GitOps table, and all prod operational commands.
* `docs/changes/2026-07-13-prod-namespace-techx-corp-prod.md` — This change record.

## Dependencies and Cross-Repository Impact

* Related follow-up (not in this change): `gitops/clusters/prod/application.yaml` and `appproject.yaml` currently still list destination namespace `techx-corp` and should be aligned if the cluster uses `techx-corp-prod`.
* Infra/platform image and ECR paths unchanged.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | No runtime change from this doc edit alone |
| **Infrastructure** | No Terraform change |
| **Deployment** | Operators following the runbook will target namespace `techx-corp-prod` |
| **Backward compatibility** | Doc now diverges from GitOps manifests if they still use `techx-corp` as destination NS |
| **Observability** | No change |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Namespace constant | Manual review of Production table | ✅ `techx-corp-prod` |
| No accidental `-dev` rewrite | Grep for `techx-corp-prod-dev` | ✅ None |
| Dev NS preserved | Count of `techx-corp-dev` | ✅ Still present |
| ECR paths preserved | `techx-corp/ad` examples | ✅ Unchanged |

### Manual Verification

* Confirmed 43 occurrences of `techx-corp-prod` are namespace/flags/prose only.
* Confirmed Application/AppProject/release columns remain `techx-corp` for prod.

### Remaining Verification (Post-Merge)

* Confirm live prod cluster and Argo Application destination match `techx-corp-prod` (or update GitOps manifests accordingly).
* Re-run smoke against prod with `--namespace techx-corp-prod` after cutover.

## Migration or Deployment Notes

1. Create namespace if missing: `kubectl create namespace techx-corp-prod` (or rely on Helm `--create-namespace` / Argo create-namespace).
2. Align Argo CD Application and AppProject destinations to `techx-corp-prod` before syncing prod.
3. Reinstall or migrate secrets/app releases into `techx-corp-prod` if currently living in `techx-corp`.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Doc/GitOps namespace mismatch | Medium | Medium | Update `gitops/clusters/prod/*` or revert doc until manifests catch up |
| Operator deploys to empty new NS | Low | Medium | Migrate or recreate secrets + app chart in new NS |

**Rollback procedure:**

Revert `docs/DEPLOYMENT.md` (and this change record if desired) to restore production namespace documentation to `techx-corp`.
