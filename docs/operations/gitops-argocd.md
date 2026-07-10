# Vận hành GitOps (Argo CD) — techx-corp-chart

## Mục tiêu

Git (`techx-corp-chart`) là nguồn sự thật; Argo CD đồng bộ namespace `techx-corp`.  
Sau cutover: **không** dùng `helm upgrade` thường xuyên.

## Truy cập UI (v1 — không public Ingress)

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# Admin password (xoay vòng sau login đầu):
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

## Bootstrap lần đầu

1. Terraform: `argocd_enabled = true` (dev trước) → apply.
2. Cấu hình credential repo Git trong namespace `argocd` (GitHub App / deploy key).
3. Cập nhật `values-dev.yaml` / `values-prod.yaml` **tag đang chạy thật** (giảm drift).
4. Apply manifests:

```bash
kubectl apply -f gitops/clusters/dev/   # hoặc prod/
```

5. Application bật **auto-sync + self-heal** (`prune: false`). Sau apply, Argo sẽ
   tự sync khi OutOfSync. Vẫn có thể force/review:

```bash
# Dev: techx-corp-dev / namespace techx-corp-dev
# Prod: techx-corp / namespace techx-corp
argocd app diff techx-corp-dev
argocd app sync techx-corp-dev --dry-run   # optional review
argocd app wait techx-corp-dev --sync --health --timeout 600
./scripts/smoke-test.sh --namespace techx-corp-dev
```

## Ownership sau cutover

Argo CD **quản lý** các resource hiện có. Trạng thái Helm release cũ **không** được chuyển sang Argo.  
Không còn dùng `helm upgrade` cho deploy thường. Break-glass: **tắt auto-sync** trước, rồi Helm nếu bắt buộc, sau đó **đồng bộ lại Git**.

## Rollback

### Chuẩn (primary)

```text
git revert <deployment-commit> → merge → Argo CD sync desired state cũ
```

### Break-glass: Argo History Rollback

Chỉ khi cần khẩn cấp:

1. Tắt automated sync trên Application.  
2. Argo CD History → Rollback.  
3. **Ghi cùng thay đổi vào Git** (revert/commit) để desired state khớp.  
4. Bật lại auto-sync (nếu đang dùng).

Nếu không cập nhật Git, Argo sẽ coi trạng thái rollback là **OutOfSync** và có thể ghi đè.

## Promote image tag

Contract chart: **một** `default.image.tag` cho **mọi** service nested, **và** `opensearch.image.tag` cùng VERSION (subchart OpenSearch không inherit `default.image`).

```text
Build ALL services with same tag (21-image release set, includes opensearch)
  → Push ECR
  → Verify every required repo has the tag (including PROJECT/opensearch)
  → Smoke/security checks
  → Open PR (values-dev.yaml or values-prod.yaml):
      default.image.tag + opensearch.image.repository/tag
  → Review / merge
  → Argo sync (+ wait 600s)
```

**Không** mở PR values song song khi push image chưa xong.  
Partial bake + global tag mới → `ImagePullBackOff`.

### Gợi ý verify ECR (prod project)

```bash
TAG=sha-a1b2c3d
PROJECT=techx-corp   # or techx-dev-corp
for svc in ad cart checkout frontend frontend-proxy product-catalog opensearch; do
  aws ecr describe-images --repository-name "${PROJECT}/${svc}" \
    --image-ids imageTag="${TAG}" --region us-east-1 >/dev/null \
    && echo "OK ${PROJECT}/${svc}:${TAG}" \
    || echo "MISSING ${PROJECT}/${svc}:${TAG}"
done
```

(Mở rộng list đủ catalog bake 21 services trước khi merge prod.)

## Prod path protection

Required reviewers / CODEOWNERS không chỉ `values-prod.yaml`, mà cả:

- `templates/**`, `charts/**`
- `Chart.yaml`, `Chart.lock`
- `values.yaml`, `values-prod.yaml`, `values-public-alb.yaml`
- `gitops/clusters/prod/**`
- `postgresql/**` (và asset chart khác được render)

## Secrets

- Dev: có thể tạm giữ posture hiện tại với **risk acceptance** rõ.  
- Prod cutover: không commit credential thật mới; **ưu tiên hoàn thành SEC-05 (ESO)** trước.  
- Secret nên được tạo trên cluster (ESO), không nhét password production vào GitOps render.

## Auto-sync (mặc định)

**Dev và prod:** `automated.selfHeal: true`, `prune: false` trên Application
(`gitops/clusters/*/application.yaml`).

- Git commit → Argo reconcile → auto-apply khi OutOfSync.
- Live cluster drift bị self-heal (Git thắng).
- Resource xóa khỏi Git **không** bị prune tự động (an toàn; bật prune sau Phase 7 nếu cần).
- Tắt tạm: `argocd app set <APP> --sync-policy none` (hoặc sửa manifest / bỏ `automated`).

Không bật `ServerSideApply` trong baseline v1.

## Partial sync failure

Argo **không** có Helm `--atomic`. Failed sync có thể để lại trạng thái một phần.  
Hành động: `argocd app wait` / health; sửa Git; sync lại; hoặc Git revert.

## Liên quan

- Workspace plan: `docs/gitops-argocd.md`
- Backlog: `docs/backlogs/2026-07-09-rel-09-gitops-argocd.md`
- Smoke: `scripts/smoke-test.sh`
