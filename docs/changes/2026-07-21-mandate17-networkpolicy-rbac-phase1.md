# Mandate 17 — Phase 1: NetworkPolicy enable + RBAC least-privilege

**Date:** 2026-07-21
**Author:** @cdo06
**Mandate:** DIRECTIVE #17 — Chịu được sự cố, khoanh được kẻ xâm nhập
**Trụ:** Security (blast-radius containment)
**Risk:** Low — ingress-only enforcement; no egress isolation yet.

---

## Thay đổi

### 1. NetworkPolicy — bật ingress-only enforcement (`values-prod.yaml`)

```diff
- networkPolicy:
-   enabled: false
-   enforceEgress: false
+ networkPolicy:
+   enabled: true      # Phase 1: ingress-only
+   enforceEgress: false  # egress isolation deferred to Phase 2
```

**Tại sao ingress-only trước?**
- `enforceEgress: true` yêu cầu `egressProxy.enabled: true` (fail-safe guard trong template).
- Ingress-only đã đạt mục tiêu chính của Mandate 17: pod bị chiếm không thể bị lateral-reach từ pod không có business reason.
- Egress isolation sẽ theo sau khi egress-proxy soak 24h clean.

**Những gì được enforce:**
- `default-deny-all-ingress` — namespace-wide: tất cả inbound traffic bị block trừ khi có rule allow.
- 29 NetworkPolicy objects cover toàn bộ service, chỉ allow đúng peer và port theo kiến trúc.

**Những gì chưa enforce:**
- Egress (outbound từ pod). Một pod bị chiếm vẫn có thể initiate connection ra ngoài.
  → Follow-up: Phase 2 (enforceEgress + egressProxy).

---

### 2. ServiceAccount least-privilege — tách SA cho 3 service (`values-prod.yaml`)

Trước thay đổi này, `accounting`, `fraud-detection`, `payment` dùng chung global SA.

| Service | SA trước | SA sau | IRSA role |
|---|---|---|---|
| `accounting` | global (techx-corp) | `accounting` | none (không cần AWS API hiện tại) |
| `fraud-detection` | global (techx-corp) | `fraud-detection` | none |
| `payment` | global (techx-corp) | `payment` | none |
| `checkout` | ✅ đã có riêng | `checkout` | `techx-prod-tf2-checkout-outbox` |
| `product-reviews` | ✅ đã có riêng | `product-reviews` | `techx-prod-tf2-product-reviews-model-read` |
| `shopping-copilot` | ✅ đã có riêng | `shopping-copilot` | `techx-prod-tf2-shopping-copilot-model-read` |

**Tại sao ưu tiên 3 service này?**
- `payment`: service có blast-radius cao nhất trên revenue path. Cô lập danh tính phòng khi AWS API được thêm sau này.
- `accounting` + `fraud-detection`: xử lý dữ liệu tài chính/event — audit rõ hơn, giảm nguy cơ token chung bị lạm dụng.
- `automountServiceAccountToken: false` đã được set ở template level (không pod nào nhận token trừ khi explicitly mount).

**Workload chưa tách SA (lý do deferral):**
- `frontend`, `frontend-proxy`: customer-facing, không có nhu cầu AWS API, rủi ro thấp hơn; defer sau Phase 2.
- `cart`, `checkout` (đã có), `recommendation`, `ad`, `email`, `shipping`, `quote`: tương tự.

---

## Verify (sau deploy)

```powershell
# 1. Kiểm tra NetworkPolicy đã tồn tại
kubectl -n techx-corp-prod get networkpolicy

# 2. Kiểm tra default-deny đã active
kubectl -n techx-corp-prod get networkpolicy default-deny-all-ingress

# 3. Kiểm tra SA đã tách đúng
kubectl -n techx-corp-prod get pods -o custom-columns=NAME:.metadata.name,SA:.spec.serviceAccountName | grep -E "accounting|fraud|payment"

# 4. Storefront và checkout vẫn hoạt động
kubectl -n techx-corp-prod get pods  # tất cả Running/Ready

# 5. Không có OTel trace error mới sau ~5 phút
# → Grafana: Service Health dashboard
```

---

## Rollback

```powershell
helm rollback techx-corp <prev-revision> -n techx-corp-prod
```

Hoặc set lại `networkPolicy.enabled: false` trong values-prod.yaml và helm upgrade.
SA tách riêng không gây breaking change — pod vẫn chạy bình thường với SA mới (không cần IRSA role vì các SA mới chưa có annotation).
