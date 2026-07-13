# ADR SEC-05: Loại bỏ credential hardcode khỏi Helm chart

- **Status:** Accepted
- **Date:** 2026-07-09
- **Author:** CDO-03 (TF2)
- **Trụ:** Security + Auditability

---

## Bối cảnh

Khi audit `tf2-corp-chart/values.yaml`, phát hiện các credential được hardcode trực tiếp:

| Vị trí | Credential | Rủi ro |
|---|---|---|
| `postgresql.env` | `POSTGRES_PASSWORD=otel` | Root DB password |
| `postgresql.podAnnotations` | `password: otel` | Scraper password |
| `accounting.env` | `DB_CONNECTION_STRING` chứa `Password=otelp` | App DB password |
| `product-catalog.env` | `DB_CONNECTION_STRING` chứa `otelp` | App DB password |
| `product-reviews.env` | `DB_CONNECTION_STRING` chứa `otelp` | App DB password |
| `grafana` | `adminPassword: admin` | Grafana admin |
| `flagd sidecar` | `SECRET_KEY_BASE=yYrE...` | Phoenix session key |

Hệ quả:
- Bất kỳ ai có quyền đọc git repo hoặc `helm get values` đều thấy credential rõ ràng
- `kubectl get deploy -o yaml` expose credential trong manifest
- K8s audit log, CloudTrail log đều record credential dưới dạng plaintext
- Không thể rotate credential nhanh khi bị lộ (phải sửa code + redeploy)
- Vi phạm compliance: PCI-DSS, SOC2 yêu cầu credential không được tồn tại trong SCM

---

## Quyết định

Dùng **External Secrets Operator (ESO) + AWS Secrets Manager** để tách credential khỏi chart.

### Lý do chọn ESO thay vì Sealed Secrets

| Tiêu chí | ESO + Secrets Manager | Sealed Secrets |
|---|---|---|
| Multi-team isolation | ✅ IAM policy per-cluster prefix | ❌ Shared cluster key |
| Secret rotation | ✅ Tự động sync, không cần redeploy | ❌ Phải re-encrypt + commit |
| Audit trail | ✅ CloudTrail đầy đủ | ❌ Chỉ K8s audit log |
| Cross-env management | ✅ Centralized, IAM-gated | ❌ Mỗi cluster key riêng |
| Phù hợp trụ Auditability | ✅ Cao | ⚠️ Trung bình |

Dự án có nhiều team (4 TF) và cần audit trail rõ ràng → ESO phù hợp hơn.

---

## Giải pháp

### Kiến trúc

```
AWS Secrets Manager
  techx-tf2/postgres-credentials      → postgres pod
  techx-tf2/app-db-credentials        → accounting, product-catalog, product-reviews
  techx-tf2/grafana-admin             → grafana subchart
  techx-tf2/flagd-ui-secret           → flagd sidecar
        ↓ ESO sync (refreshInterval: 1h)
K8s Secret (plaintext, chỉ trong etcd)
        ↓ secretKeyRef
Application env var
```

### IAM Least-Privilege

ESO IAM Role (`techx-tf2-eso-role`) chỉ có quyền đọc secret có prefix `techx-tf2/*`:
```json
{
  "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
  "Resource": "arn:aws:secretsmanager:*:*:secret:techx-tf2/*"
}
```
TF khác không thể đọc secret của TF2 (và ngược lại).

### Known Limitation: PostgreSQL scraper annotation

`io.opentelemetry.discovery.metrics/config` trong `podAnnotations` không hỗ trợ `secretKeyRef`. Password trong annotation hiện dùng `${env:POSTGRES_SCRAPER_PASSWORD}` (OTel Collector env var substitution). Đây là known limitation, tracked để xử lý trong future work.

---

## Thay đổi

### tf2-corp-infra
- Thêm `modules/eks/eso.tf`: IAM Role + Policy cho ESO (IRSA pattern)
- Thêm output `eso_role_arn` vào module và production environment

### tf2-corp-chart
- `Chart.yaml`: thêm `external-secrets` dependency
- `values.yaml`: xóa credential plaintext, thay bằng `secretKeyRef`
- `values.yaml`: thêm `externalSecrets` config block và `grafana.admin.existingSecret`
- `templates/external-secrets.yaml`: ClusterSecretStore + 4 ExternalSecret resources
- `scripts/create-secrets.sh`: script tạo secrets trong AWS Secrets Manager

---

## Thứ tự deploy (quan trọng)

```
1. terraform apply (tf2-corp-infra)
   → Tạo IAM Role cho ESO
   → Lấy output: terraform output -raw eso_role_arn

2. Tạo secrets trong AWS Secrets Manager
   → bash scripts/create-secrets.sh (với env vars thật)

3. Điền ESO Role ARN vào values.yaml
   → external-secrets.serviceAccount.annotations.eks.amazonaws.com/role-arn

4. helm repo add external-secrets https://charts.external-secrets.io
   helm dependency update ./tf2-corp-chart

5. helm upgrade --install techx-corp ./tf2-corp-chart ...

6. Verify
   kubectl get externalsecret -n <ns>    # tất cả phải "Ready"
   kubectl get secret -n <ns>            # 4 secret phải tồn tại
```

---

## Rollback

Nếu ESO có vấn đề:

```bash
# 1. Restore values.yaml về trạng thái cũ (git revert)
git revert <commit-hash>

# 2. Disable ESO trong values.yaml
# externalSecrets.enabled: false
# external-secrets.enabled: false

# 3. Tạo K8s Secret thủ công
kubectl create secret generic postgres-credentials \
  --from-literal=postgres-user=root \
  --from-literal=postgres-password=<password>
# ... tương tự cho các secret khác

# 4. helm upgrade lại
```

---

## Rủi ro

| Rủi ro | Xác suất | Mức độ | Giảm thiểu |
|---|---|---|---|
| ESO không sync được (AWS API lỗi) | Thấp | Cao | `refreshInterval` giữ K8s Secret alive; chỉ fail khi Secret bị xóa |
| Deploy trước khi tạo Secret | Cao | Cao | Documented thứ tự deploy; CI/CD check |
| IAM Role ARN chưa điền vào values | Cao | Cao | Helm lint sẽ warn; documented |

---

## Tham chiếu

- [External Secrets Operator docs](https://external-secrets.io/latest/)
- [AWS IRSA documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- `tf2-corp-infra/modules/eks/eso.tf`
- `tf2-corp-chart/templates/external-secrets.yaml`
- `tf2-corp-chart/scripts/create-secrets.sh`
