# GitOps manifests (Argo CD)

Cluster-specific Argo CD `AppProject` + `Application` for the `techx-corp` Helm chart.

| Path | Cluster |
|------|---------|
| `clusters/dev/` | development EKS (`techx-dev`) |
| `clusters/prod/` | production EKS (`techx-tf2`) |

## Prerequisites

1. Argo CD installed (`argocd_enabled=true` in `techx-corp-infra`, or equivalent Helm).
2. Git repository credentials Secret in namespace `argocd` (GitHub App / deploy key / PAT).
3. `values-dev.yaml` / `values-prod.yaml` image tags match **currently running** tags before first sync.

## Bootstrap (once per cluster)

```bash
# Dev example
kubectl apply -f gitops/clusters/dev/

argocd app get techx-corp-dev
argocd app diff techx-corp-dev
# Applications use automated sync + selfHeal; optional first manual sync:
argocd app sync techx-corp-dev --dry-run
argocd app sync techx-corp-dev
argocd app wait techx-corp-dev --sync --health --timeout 600
```

## Rules (REL-09)

- **No ServerSideApply** in v1 Application specs.
- **Default sync policy:** `automated` with `selfHeal: true`, `prune: false`.
- **Primary rollback:** `git revert` → merge → Argo auto-syncs.
- **History rollback:** break-glass only; disable auto-sync; fix Git afterward.
- After cutover: do **not** routine `helm upgrade` (ownership is Argo CD).
- Global image tag: rebuild **all** services with the same tag before promotion PR.

See `docs/operations/gitops-argocd.md` and workspace `docs/gitops-argocd.md`.

## Gatekeeper runtime-hardening policy

Terraform owns the Gatekeeper namespace, Helm release, CRDs, and admission
webhook. Argo CD owns only the ConstraintTemplates and Constraints in
`gitops/gatekeeper`.

Bootstrap production in this order:

```bash
# 1. Apply tf2-corp-infra and wait for Gatekeeper to become ready.
kubectl -n gatekeeper-system rollout status deployment/gatekeeper-controller-manager
kubectl -n gatekeeper-system rollout status deployment/gatekeeper-audit

# 2. Create the dedicated project, then the policy application.
kubectl apply -f gitops/clusters/prod/gatekeeper-appproject.yaml
kubectl apply -f gitops/clusters/prod/gatekeeper-application.yaml

# 3. Confirm templates and dry-run constraints are healthy.
kubectl get constrainttemplates
kubectl get k8scontainerhardening,k8sallowedimagetags,k8srequiredresources
```

Keep all three constraints at `dryrun` for at least two 60-second audit cycles.
Only change them to `deny` after every `status.totalViolations` is zero and the
production smoke/SLO checks pass. Roll back a false positive by reverting the
constraint commit to `dryrun`; do not delete the templates or disable flagd.
