# Change: Production Namespace techx-corp-prod Across Chart Repo

## Summary

Aligned the entire `techx-corp-chart` production destination namespace to **`techx-corp-prod`** (GitOps, values, secrets-chart, smoke default, operational docs, and Grafana filters that hard-coded the old prod OTEL `service_namespace`). Helm/Argo release and Application names remain **`techx-corp`**.

## Context

- Production previously used Kubernetes namespace `techx-corp`, which collided with the chart/release identity name and did not mirror the explicit dev pattern (`techx-corp-dev`).
- Operators and Argo CD destination must agree on one production namespace; docs and manifests had diverged after the DEPLOYMENT.md-only update.
- Why now: complete the rename so GitOps, Helm values, and runbooks all target `techx-corp-prod`.

## Before

| Area | Production namespace |
|---|---|
| Argo Application / AppProject destination | `techx-corp` |
| `values.yaml` `externalSecrets.namespace` | `techx-corp` |
| `values-prod.yaml` | (inherited base only) |
| secrets-chart default `namespace` | already `techx-corp-prod` (comment still `-n techx-corp`) |
| `scripts/smoke-test.sh` default | `techx-corp` |
| Ops docs / README prod examples | `-n techx-corp` |
| Grafana cart alert + k8s-pod dashboard filters | `service_namespace=techx-corp` |

## After

| Area | Production namespace |
|---|---|
| Argo Application / AppProject destination | `techx-corp-prod` |
| `values.yaml` / `values-prod.yaml` `externalSecrets.namespace` | `techx-corp-prod` |
| `values-dev.yaml` `externalSecrets.namespace` | `techx-corp-dev` (explicit override) |
| secrets-chart default + comments | `techx-corp-prod` |
| Smoke script default | `techx-corp-prod` |
| Ops docs / README prod examples | `-n techx-corp-prod` / `--namespace techx-corp-prod` |
| Grafana hard-coded prod filters | `techx-corp-prod` |

**Unchanged:** Helm release name `techx-corp`, Argo Application/AppProject name `techx-corp`, ECR project `techx-corp/*`, ASM prefix `techx-corp/production`, secret object names (`techx-corp-postgresql-app`, …), chart template helpers (`techx-corp.*`), and all `techx-corp-dev` destinations.

## Technical Design Decisions

* **Rename destination NS only** — keep Application/release identity `techx-corp` to minimize Argo/Helm history churn beyond destination.
* **Base values default to prod NS** — matches production-oriented base image repo; dev overlay sets `techx-corp-dev`.
* **Do not rewrite historical `docs/changes/*` / backlog acceptance logs** — those remain historical records of prior state.
* **Grafana filters** that hard-coded OTEL `service_namespace=techx-corp` updated to `techx-corp-prod` because pod annotations inject `.Release.Namespace`.

## Implementation Details

1. GitOps prod Application + AppProject destination → `techx-corp-prod`.
2. Values: base + prod `externalSecrets.namespace: techx-corp-prod`; dev overlay `techx-corp-dev`.
3. Secrets-chart comment alignment; smoke default NS.
4. Operational docs (`DEPLOYMENT.md` already done; `external-secrets.md`, `rollout-safety.md`, `gitops-argocd.md`, `README.md`).
5. Grafana cart alert + k8s-pod-troubleshooting dashboard prod filter strings.

## Files Changed

**GitOps:**
* `gitops/clusters/prod/application.yaml` — destination namespace `techx-corp-prod`.
* `gitops/clusters/prod/appproject.yaml` — allowed destination namespace `techx-corp-prod`.

**Values / secrets:**
* `values.yaml` — `externalSecrets.namespace: techx-corp-prod`.
* `values-prod.yaml` — explicit `externalSecrets.namespace: techx-corp-prod`.
* `values-dev.yaml` — explicit `externalSecrets.namespace: techx-corp-dev`.
* `secrets-chart/values.yaml` — comment uses `-n techx-corp-prod` (value already correct).

**Scripts:**
* `scripts/smoke-test.sh` — default namespace `techx-corp-prod`.

**Observability:**
* `grafana/provisioning/alerting/cart-service-alerting.yml` — `service_namespace` → `techx-corp-prod`.
* `grafana/provisioning/dashboards/k8s-pod-troubleshooting.json` — hard-coded filter → `techx-corp-prod`.

**Documentation:**
* `README.md` — break-glass prod install `-n techx-corp-prod`.
* `docs/DEPLOYMENT.md` — already updated in prior pass.
* `docs/operations/external-secrets.md` — prod NS + corrected separate dev/prod command blocks.
* `docs/operations/rollout-safety.md` — prod `-n techx-corp-prod`.
* `docs/operations/gitops-argocd.md` — prod destination `techx-corp-prod`; intro lists both env namespaces.
* `docs/changes/2026-07-13-prod-namespace-techx-corp-prod.md` — this record (expanded from docs-only scope).

## Dependencies and Cross-Repository Impact

* Live prod cluster: if workloads still live in `techx-corp`, migrate or reinstall into `techx-corp-prod` before/while applying GitOps (Argo will create the new namespace via `CreateNamespace=true` but will not move existing PVCs/data).
* Infra/platform image ECR and ASM path prefixes are **not** renamed.
* Related platform/infra docs outside this repo may still mention `-n techx-corp` for prod and should be updated separately if present.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | No code change; workloads run in namespace `techx-corp-prod` when installed/synced with new destination |
| **Infrastructure** | New or different K8s namespace; cluster RBAC/network policies scoped to old NS may need review |
| **Deployment** | Argo destination + Helm `-n` must be `techx-corp-prod`; secrets-chart before app chart in that NS |
| **Observability** | OTEL `service.namespace` follows release NS → `techx-corp-prod`; Grafana hard-coded filters updated |
| **Backward compatibility** | Existing objects in namespace `techx-corp` are not automatically moved |
| **Security** | Secrets re-synced into new NS via secrets-chart / ESO |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Prod GitOps destination | Inspect `gitops/clusters/prod/*.yaml` | ✅ `techx-corp-prod` |
| No bare `-n techx-corp` in ops/live config | Repo scan (excluding historical changes/backlogs) | ✅ Clean |
| Dev NS preserved | `values-dev` / `gitops/clusters/dev` | ✅ `techx-corp-dev` |
| No `techx-corp-prod-dev` corruption | Grep | ✅ None |

### Manual Verification

* Confirmed Application `releaseName` / metadata `name` still `techx-corp`.
* Confirmed ECR and ASM strings still use project prefix `techx-corp/...`.

### Remaining Verification (Post-Merge)

1. Apply updated AppProject + Application on prod Argo (`kubectl apply -f gitops/clusters/prod/`).
2. Deploy/re-sync secrets-chart into `techx-corp-prod`, then app Application.
3. Smoke: `bash scripts/smoke-test.sh --namespace techx-corp-prod` (or default).
4. Confirm Grafana alerts fire against new `service_namespace`.

## Migration or Deployment Notes

1. Create/allow destination `techx-corp-prod` (Argo `CreateNamespace=true` or manual).
2. Re-apply AppProject then Application so destination is allowed.
3. Install secrets-chart into `techx-corp-prod` with `values-prod.yaml` before app sync.
4. If migrating from live `techx-corp`: plan PVC/data move or dual-run cutover; do not expect prune of old NS by Argo (prune OFF; different destination).
5. Update any external bookmarks / CI that hard-code `-n techx-corp`.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Empty new NS while traffic still on old NS | Medium | High | Cutover plan; ALB/Ingress recreated in new NS |
| AppProject destination mismatch during apply | Low | Medium | Apply appproject.yaml before Application |
| Grafana still filtered on old service_namespace elsewhere | Low | Low | Search remaining dashboards; APM uses variables |

**Rollback procedure:**

1. Revert Git: destination namespace and docs back to `techx-corp`.
2. Re-apply GitOps manifests; re-point operators to `-n techx-corp`.
3. Secrets/app still in `techx-corp-prod` need manual uninstall or leave orphaned until cleaned.
