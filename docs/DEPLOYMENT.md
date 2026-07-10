# Tài liệu Hướng dẫn Triển khai End-to-End (Production Runbook)

> [!NOTE]
> **Vai trò của Repository này (`techx-corp-chart`):**
> Repository này chịu trách nhiệm quản lý **Helm chart**, cấu hình **public ALB Ingress** (`values-public-alb.yaml`), **smoke test**, và quy trình **upgrade/rollback** an toàn.  
> Chart consume image theo quy ước **`[REGISTRY]/[PROJECT]/[SERVICE]:[VERSION]`**.

---

## 1. Mục tiêu (Objectives)

- Deploy ứng dụng TechX Corp lên EKS bằng Helm (`--wait --atomic`).
- Gắn đúng image từ ECR nested (`techx-corp/<service>` hoặc `techx-dev-corp/<service>`).
- Bật public ALB cho storefront, chặn route nhạy cảm.
- Xác minh bằng smoke test; rollback khi cần.

## 2. Bản đồ Repository

| Repository | Vai trò |
|---|---|
| **`techx-corp-platform`** | Build/push images (CI/CD hoặc bake) |
| **`techx-corp-infra`** | VPC, EKS, nested ECR, IAM (GHA OIDC, ALB Controller, ESO IRSA, ASM shells) |
| **`techx-corp-chart`** | Helm chart, secrets-chart (ESO), ALB values, smoke test, rollout safety |

## 3. Điều kiện tiên quyết

- Cluster EKS đã sẵn sàng (`techx-tf2` production), `kubectl` context đúng.
- AWS Load Balancer Controller đã cài trong `kube-system`.
- **SEC-05:** ESO installed, `ClusterSecretStore` Ready, ASM values bootstrapped, **`techx-corp-secrets`** ExternalSecrets Ready (or use `-f values-demo.yaml` for local demo only).
- Images đã có trên ECR theo format nested (xem Phase 3 / platform repo).
- **Helm** v3+, **kubectl**, **bash** (smoke test).
- **Metrics Server:** chart cài kèm subchart `metrics-server` (default `enabled: true`) để HPA (`frontend`, `checkout`) đọc CPU/memory. **Không** cần cài sẵn trong `kube-system`. Nếu cluster **đã** có Metrics Server (một APIService `v1beta1.metrics.k8s.io` duy nhất), tắt trong overlay: `metrics-server.enabled: false`.

## 4. Hằng số & quy ước image

### Production

| Hằng số | Giá trị |
|---|---|
| Account / Region | `493499579600` / `us-east-1` |
| EKS | `techx-tf2` |
| Namespace | `techx-corp` |
| Helm release | `techx-corp` |
| `default.image.repository` | `493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-corp` |
| `default.image.tag` | VERSION only, ví dụ `sha-a1b2c3d` hoặc `v1.2.3` |

### Development (nếu deploy dev cluster)

| Hằng số | Giá trị |
|---|---|
| `default.image.repository` | `493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-dev-corp` |
| `default.image.tag` | VERSION đã push từ branch `techx-dev-corp` |

### Quy ước image (chart template)

```text
[REGISTRY]/[PROJECT]/[SERVICE]:[VERSION]
```

Template (`templates/_objects.tpl`) render:

```text
{{ default.image.repository }}/{{ component.name }}:{{ default.image.tag }}
```

Ví dụ:

```text
493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-corp/ad:sha-a1b2c3d
493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-corp/frontend:sha-a1b2c3d
493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-corp/checkout:sha-a1b2c3d
```

| Helm value | Ý nghĩa |
|---|---|
| `default.image.repository` | **REGISTRY/PROJECT** — không kèm service |
| `default.image.tag` | **VERSION** — không còn suffix `-service` |

> **Deprecated:** `repository:tag` dạng `.../techx-corp:1.0-ad` (service trong tag).

Component có `imageOverride.repository` (postgres, flagd, …) dùng full `repository:tag` public image, không append service path.

---

## Phase 1–2: Hạ tầng & ALB Controller (tham chiếu)

*Chi tiết đầy đủ: repo `techx-corp-infra` / `techx-corp-platform` docs/DEPLOYMENT.md.*

Tóm tắt:

1. Terraform bootstrap + `environments/production` (EKS, nested ECR `techx-corp/*`, GHA role).
2. `aws eks update-kubeconfig --region us-east-1 --name techx-tf2`
3. Cài AWS Load Balancer Controller từ Terraform output `aws_load_balancer_controller_helm_command`.

   Output includes **`region`**, **`vpcId`**, and IRSA `role-arn`. Required so the controller does not rely on EC2 IMDS (pods often cannot reach metadata → CrashLoop with `failed to get VPC ID` / `ec2imds … deadline exceeded`).

   ```bash
   helm repo add eks https://aws.github.io/eks-charts && helm repo update
   terraform -chdir=../techx-corp-infra/environments/production \
     output -raw aws_load_balancer_controller_helm_command
   # Run the printed helm upgrade --install
   kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=120s
   ```

Nested ECR (Terraform module `ecr`) phải tồn tại **trước** khi pod pull image, ví dụ: `techx-corp/ad`, `techx-corp/checkout`, …

4. **SEC-05 secrets path** (before app chart with default `values.yaml`):

   Bootstrap ASM values from `techx-corp-infra` (current live credentials only). Use full extension:

   ```powershell
   # Windows PowerShell (recommended)
   .\scripts\bootstrap-asm-secrets.ps1 techx-corp/production us-east-1
   ```

   ```cmd
   REM Windows CMD
   scripts\bootstrap-asm-secrets.cmd techx-corp/production us-east-1
   ```

   ```bash
   # Bash / Git Bash / WSL
   ./scripts/bootstrap-asm-secrets.sh techx-corp/production us-east-1
   ```

   Install ESO (infra) and wait until Helm `STATUS: deployed` — do not interrupt `--wait`.  
   If you see `another operation is in progress`, uninstall then reinstall (infra DEPLOYMENT troubleshooting §5).

   ```bash
   # From techx-corp-infra
   terraform -chdir=environments/production output -raw external_secrets_helm_command
   # run printed command; then:
   helm status external-secrets -n external-secrets   # expect deployed

   terraform -chdir=environments/production output -raw external_secrets_cluster_secret_store_manifest | kubectl apply -f -
   kubectl get clustersecretstore aws-secretsmanager
   ```

   Then ExternalSecrets release (after ESO + ClusterSecretStore Ready):

   ```bash
   helm upgrade --install techx-corp-secrets ./secrets-chart \
     -n techx-corp --create-namespace \
     -f secrets-chart/values.yaml \
     -f secrets-chart/values-prod.yaml   # or values-dev.yaml
   kubectl -n techx-corp wait --for=condition=Ready externalsecret --all --timeout=120s
   ```

   Runbook: [operations/external-secrets.md](./operations/external-secrets.md).

   Local demo **without** ESO: add `-f values-demo.yaml` to the app chart (plaintext demo only).

---

## Phase 3: Images (tham chiếu platform)

Images được build từ **`techx-corp-platform`**:

- **CI/CD (khuyến nghị):** push `main` → `techx-corp/*:sha-…`; branch `techx-dev-corp` → `techx-dev-corp/*:sha-…`
- **Thủ công:**

```bash
IMAGE_NAME=493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-corp \
IMAGE_VERSION=sha-manual DEMO_VERSION=sha-manual \
docker buildx bake -f docker-compose.yml --push \
  --set "*.platform=linux/amd64,linux/arm64"
```

Xác minh trước khi Helm:

```bash
aws ecr describe-images --repository-name techx-corp/ad --region us-east-1 --max-items 3
```

Ghi lại **VERSION** (tag) để ghi vào `values-prod.yaml` / `values-dev.yaml` (GitOps) — **không** chỉ giữ trên máy operator.

---

## Phase 4: Deploy (GitOps ưu tiên — REL-09)

> Chi tiết: [operations/gitops-argocd.md](./operations/gitops-argocd.md) · plan workspace `docs/gitops-argocd.md`

### 4A. Argo CD (sau khi control plane đã cài)

1. Cập nhật tag trong Git:
   - Prod: `values-prod.yaml` → `default.image.tag`
   - Dev: `values-dev.yaml` → `default.image.tag`
2. **Contract:** tag global — rebuild/push **toàn bộ** service bake với cùng tag; verify ECR trước merge PR.
3. Sync:

```bash
argocd app diff techx-corp
argocd app sync techx-corp --dry-run
argocd app sync techx-corp
argocd app wait techx-corp --sync --health --timeout 600
```

4. **Rollback chuẩn:** `git revert` commit deploy → merge → Argo sync.  
   History rollback Argo chỉ break-glass (tắt auto-sync → rollback → **cập nhật Git**).
5. Sau cutover: **không** `helm upgrade` thường xuyên (ownership = Argo CD).

Value layer: `values.yaml` + `values-public-alb.yaml` + `values-dev|prod.yaml` (xem `gitops/clusters/`).

#### Truy cập Argo CD UI / first admin (initial)

Không public Ingress (v1). Port-forward:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# → https://localhost:8080
```

| Field | Value |
|---|---|
| **Username** | `admin` (fixed initial account) |
| **Password** | From Secret `argocd-initial-admin-secret` (namespace `argocd`) |

**Query first/initial admin password:**

```bash
# Bash / Git Bash / WSL
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

```powershell
# Windows PowerShell
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
  (kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}")
))
```

Infra Terraform helper (when `argocd_enabled=true` — prints the same kubectl query):

```bash
terraform -chdir=../techx-corp-infra/environments/development \
  output -raw argocd_admin_password_command
# run the printed command
```

Xoay password sau login đầu; secret `argocd-initial-admin-secret` có thể bị xóa sau khi đổi (query trên sẽ fail).
### 4B. Helm break-glass (chỉ khẩn cấp)

Tắt Argo auto-sync trước. Argo **không** chuyển Helm release state; dual-drive gây lệch.

### Production (break-glass)

```bash
# Secrets release first (SEC-05)
helm upgrade --install techx-corp-secrets ./techx-corp-chart/secrets-chart \
  -n techx-corp --create-namespace \
  -f ./techx-corp-chart/secrets-chart/values.yaml \
  -f ./techx-corp-chart/secrets-chart/values-prod.yaml
kubectl -n techx-corp wait --for=condition=Ready externalsecret --all --timeout=120s

helm upgrade --install techx-corp ./techx-corp-chart \
  -n techx-corp --create-namespace \
  -f ./techx-corp-chart/values.yaml \
  -f ./techx-corp-chart/values-public-alb.yaml \
  -f ./techx-corp-chart/values-prod.yaml \
  --wait --atomic --timeout 10m --history-max 10
```

### Development (break-glass)

```bash
helm upgrade --install techx-corp-secrets ./techx-corp-chart/secrets-chart \
  -n techx-corp-dev --create-namespace \
  -f ./techx-corp-chart/secrets-chart/values.yaml \
  -f ./techx-corp-chart/secrets-chart/values-dev.yaml
kubectl -n techx-corp-dev wait --for=condition=Ready externalsecret --all --timeout=120s

# From techx-corp-chart/ working directory:
helm upgrade --install techx-corp-dev . \
  -n techx-corp-dev --create-namespace \
  -f values.yaml \
  -f values-public-alb.yaml \
  -f values-dev.yaml \
  --wait --atomic --timeout 10m --history-max 10
```

### Helm NOTES — Argo CD credential in ra sau install/upgrade

Khi `helm upgrade --install` **thành công**, chart in **NOTES** (cuối output), gồm block **ARGO CD DEFAULT ADMIN CREDENTIAL (initial admin)**:

- Username: `admin`
- Password: Helm `lookup` Secret `argocd/argocd-initial-admin-secret` (nếu còn trên cluster)
- **Luôn in** lệnh query first admin init:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Xem lại NOTES sau này:

```bash
helm get notes techx-corp-dev -n techx-corp-dev
# hoặc prod:
helm get notes techx-corp -n techx-corp
```

> **Lưu ý:** `--dry-run=client` không đọc được secret (lookup rỗng). Cần kết nối cluster thật.  
> Secret biến mất sau khi đổi password admin — lúc đó chỉ còn cách reset password Argo CD (xem runbook GitOps).
### Ý nghĩa tham số an toàn

| Flag / value | Mục đích |
|---|---|
| `-f values-public-alb.yaml` | Public ALB Ingress cho `frontend-proxy` + route blocking |
| `-f values-dev\|prod.yaml` | REGISTRY/PROJECT + tag trong Git |
| `--wait` / Argo `app wait` | Chờ ready / health (timeout 10m) |
| `--atomic` | **Chỉ Helm**; Argo không có parity — partial sync có thể xảy ra |
| `--history-max 10` | Giới hạn revision history (Helm) |
| `metrics-server.enabled` | Default `true` trong `values.yaml`. Set `false` nếu cluster đã có Metrics Server (tránh conflict APIService / RBAC) |

### Subchart Metrics Server (HPA)

Chart dependency: **metrics-server 3.13.1** (`https://kubernetes-sigs.github.io/metrics-server/`), condition `metrics-server.enabled`.

| Value | Default | Ghi chú |
|---|---|---|
| `metrics-server.enabled` | `true` | Tắt nếu đã cài cluster-wide |
| `metrics-server.fullnameOverride` | `metrics-server` | Tên Deployment/Service trong release namespace |
| `metrics-server.args` | `--kubelet-insecure-tls` | Thường cần trên EKS (kubelet serving cert) |
| `metrics-server.resources` | requests 100m/200Mi, limit memory 200Mi | |

HPA templates (`templates/hpa.yaml`) dùng `autoscaling/v2` + CPU/memory utilization — **cần** Metrics Server (API `metrics.k8s.io`). Components bật HPA mặc định: `frontend`, `checkout` (`components.*.autoscaling.enabled`).

### Kiểm tra image trong Pod

```bash
kubectl -n techx-corp get deploy ad -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# Kỳ vọng: .../techx-corp/ad:sha-a1b2c3d
```

### Storefront ALB path blocking (toggle only)

Security posture on public ALB (`frontend-proxy-public`):

| | Paths |
|---|---|
| **ALLOWED** | `/`, `/api/*`, `/images/*` (catch-all `/` → frontend-proxy) |
| **BLOCKED** (HTTP 403) when ON | `/grafana`, `/jaeger`, `/loadgen`, `/feature`, `/flagservice`, `/otlp-http` |

Flag: `components.frontend-proxy.publicAlb.blockSensitivePaths`  
- Default in `values-public-alb.yaml`: **`true`**  
- Terraform source of truth (optional): `storefront_alb_block_sensitive_paths` in `techx-corp-infra`

If the Helm release is **already installed**, you do **not** need a full reinstall. Toggle **only** the block flag with `helm upgrade` + `--reuse-values` (keeps image repo/tag and other values):

**Turn blocking ON** (storefront-only; 403 on sensitive paths):

```bash
helm upgrade techx-corp ./techx-corp-chart \
  -n techx-corp \
  --reuse-values \
  --set components.frontend-proxy.publicAlb.blockSensitivePaths=true \
  --wait --timeout 5m
```

**Turn blocking OFF** (all paths forward to frontend-proxy):

```bash
helm upgrade techx-corp ./techx-corp-chart \
  -n techx-corp \
  --reuse-values \
  --set components.frontend-proxy.publicAlb.blockSensitivePaths=false \
  --wait --timeout 5m
```

> Use the same chart path you used on install (`./techx-corp-chart` or `techx-corp-chart`).  
> ALB listener rules may take **1–2 minutes** to update after Ingress changes.

**Verify:**

```bash
# Ingress paths: with ON → /grafana (etc.) present; with OFF → only /
kubectl -n techx-corp get ingress frontend-proxy-public -o yaml

ALB_DNS=$(kubectl get ingress frontend-proxy-public -n techx-corp \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# ON  → HTTP 403 ;  OFF → not 403 (often 200/302/404 from app)
curl -i "http://${ALB_DNS}/grafana"
```

From Terraform (optional helper):

```bash
terraform -chdir=enviroments/production output storefront_alb_helm_set_flags
# → --set components.frontend-proxy.publicAlb.blockSensitivePaths=true|false
```

---

## Phase 5: Verification & Access

### ALB hostname

```bash
kubectl get ingress frontend-proxy-public -n techx-corp \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

(DNS ALB có thể mất 2–5 phút.)

### Metrics Server & HPA

```bash
# Metrics Server pod (release namespace)
kubectl -n techx-corp get deploy,pods -l app.kubernetes.io/name=metrics-server
kubectl -n techx-corp rollout status deploy/metrics-server --timeout=120s

# API available (cluster-scoped)
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | head -c 200; echo

# Resource metrics (after ~15–30s scrape)
kubectl top nodes
kubectl top pods -n techx-corp

# HPA objects for services with autoscaling
kubectl -n techx-corp get hpa
kubectl -n techx-corp describe hpa frontend checkout
```

Kỳ vọng: `TARGETS` không còn `<unknown>` sau khi Metrics Server Ready; `kubectl top` trả về CPU/memory.

### Smoke test

```bash
# Port-forward / in-cluster path
bash scripts/smoke-test.sh --namespace techx-corp

# Qua public ALB (gồm route-blocking)
ALB_DNS=$(kubectl get ingress frontend-proxy-public -n techx-corp \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
bash scripts/smoke-test.sh --namespace techx-corp --alb-host "$ALB_DNS"
```

Route nhạy cảm (`/grafana`, `/jaeger`, `/loadgen`, `/feature`, `/flagservice`, `/otlp-http`) qua ALB công cộng → **HTTP 403** khi `blockSensitivePaths=true` (xem mục *Storefront ALB path blocking* ở Phase 4).

---

## Phase 6: Rollback & Safety

```bash
helm history techx-corp -n techx-corp
helm rollback techx-corp <REVISION> -n techx-corp --wait --timeout 10m

kubectl -n techx-corp rollout status deploy/frontend-proxy --timeout=300s
kubectl -n techx-corp rollout status deploy/frontend --timeout=300s
kubectl -n techx-corp rollout status deploy/checkout --timeout=300s
kubectl -n techx-corp rollout status deploy/payment --timeout=300s

bash scripts/smoke-test.sh --namespace techx-corp
```

Chi tiết rollout: `docs/operations/rollout-safety.md` (nếu có trong repo).

---

## Troubleshooting

### ErrImagePull / ImagePullBackOff

1. Image format đúng?

   ```text
   OK:  .../techx-corp/ad:sha-a1b2c3d
   BAD: .../techx-corp:sha-a1b2c3d-ad
   BAD: .../techx-corp:1.0-ad
   ```

2. Tag Helm khớp tag ECR?

   ```bash
   aws ecr list-images --repository-name techx-corp/ad --region us-east-1
   ```

3. `repository` chỉ là base project, không có `/ad` trong value `default.image.repository`.

4. Node IAM có quyền pull ECR.

### ALB / Ingress

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100
kubectl describe ingress frontend-proxy-public -n techx-corp
```

| Symptom | Fix |
|---|---|
| `failed to get VPC ID` / `ec2imds GetMetadata` / `context deadline exceeded` | Helm install missing `region`/`vpcId`. Re-run Terraform output `aws_load_balancer_controller_helm_command` (see Phase 1–2). |
| Controller Ready, Ingress no ADDRESS | Check subnet tags `kubernetes.io/role/elb=1` / `internal-elb=1`; Ingress class/annotations for ALB. |
| IRSA / AccessDenied in logs | SA must have `eks.amazonaws.com/role-arn` from Terraform ALB controller role. |

### ExternalSecrets / CreateContainerConfigError (SEC-05)

```bash
kubectl -n techx-corp get externalsecret
kubectl -n techx-corp describe externalsecret techx-corp-postgresql-app
kubectl get clustersecretstore aws-secretsmanager
kubectl -n external-secrets logs deploy/external-secrets --tail=50
```

| Symptom | Fix |
|---|---|
| ExternalSecret not Ready | ASM value missing / wrong key; IRSA on ESO SA; ClusterSecretStore region |
| `CreateContainerConfigError` / secret not found | Deploy `techx-corp-secrets` and `kubectl wait --for=condition=Ready` before app chart |
| Auth to ASM fails | Check ESO SA annotation `eks.amazonaws.com/role-arn` matches Terraform output |
| `another operation (install/upgrade/rollback) is in progress` | Helm release stuck `pending-install` / `pending-upgrade`. See infra DEPLOYMENT troubleshooting §5: `helm status` → `helm uninstall` → reinstall from `external_secrets_helm_command`. Do not start a second upgrade while pending. |

### Helm upgrade stuck

- Kiểm tra events: `kubectl -n techx-corp get events --sort-by='.lastTimestamp' | tail -30`
- `--atomic` sẽ rollback khi timeout; xem `helm history`.

### Metrics Server / HPA

```bash
kubectl -n techx-corp logs deploy/metrics-server --tail=50
kubectl get apiservice v1beta1.metrics.k8s.io -o yaml
kubectl -n techx-corp get hpa
```

| Symptom | Fix |
|---|---|
| HPA `TARGETS` = `<unknown>` / `failed to get cpu utilization` | Metrics Server chưa Ready hoặc APIService not Available. Check deploy + logs; đợi 1–2 phút sau Ready. |
| `x509: cannot validate certificate` / kubelet TLS errors in logs | Giữ `args: [--kubelet-insecure-tls]` (default chart). Không bỏ trên EKS managed nodes trừ khi đã cấu hình trusted kubelet certs. |
| APIService create conflict / `already exists` | Cluster đã có Metrics Server (thường `kube-system`). Set `metrics-server.enabled: false` và upgrade/sync. |
| `kubectl top` → `Metrics API not available` | Pod CrashLoop / APIService False. `kubectl describe apiservice v1beta1.metrics.k8s.io`; fix readiness, network to kubelets. |
| Duplicate Metrics Server | Chỉ **một** Metrics Server per cluster. App chart default ON — tắt subchart nếu infra đã cài. |

Tắt subchart (cluster đã có Metrics Server):

```bash
# Break-glass Helm
helm upgrade techx-corp ./techx-corp-chart -n techx-corp \
  --reuse-values --set metrics-server.enabled=false \
  --wait --timeout 5m

# GitOps: ghi metrics-server.enabled: false vào values-dev.yaml / values-prod.yaml rồi Argo sync
```

---

## Tài liệu liên quan

- `techx-corp-platform/docs/CICD.md` — build/push OIDC  
- `techx-corp-platform/docs/DEPLOYMENT.md` — E2E đầy đủ  
- `techx-corp-infra` — nested ECR + IAM + SEC-05 ASM/ESO  
- [operations/external-secrets.md](./operations/external-secrets.md) — ESO bootstrap / cutover / rotation  
- `values.yaml` — `secretKeyRef` production path; `values-demo.yaml` for local plaintext; `metrics-server` subchart values  
- `secrets-chart/` — ExternalSecrets Helm release (`techx-corp-secrets`)  
- `Chart.yaml` — subchart deps (OTel, Prometheus, Grafana, Jaeger, OpenSearch, **metrics-server**)  
- `templates/NOTES.txt` — post-install notes (port-forward, ALB, **Argo CD admin credential**)  
- [operations/gitops-argocd.md](./operations/gitops-argocd.md) — GitOps runbook + UI access  
