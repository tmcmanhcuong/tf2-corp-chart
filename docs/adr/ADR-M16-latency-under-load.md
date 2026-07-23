# ADR-M16 — Giải quyết Tail Latency Dưới Tải: gRPC Connection Pinning

| Trường            | Nội dung                                                                                        |
| ----------------- | ----------------------------------------------------------------------------------------------- |
| **Mandate**       | MANDATE-16 — Latency Under Load                                                                 |
| **Trạng thái**    | 🔄 **Đang thực hiện** — Giải pháp đã triển khai, đang xác nhận kết quả trên production         |
| **Tác giả**       | Nguyễn Đức Chinh ([@chinhgithub04](https://github.com/chinhgithub04)) — CDO-03 / TF 2 |
| **Ngày**          | 2026-07-24                                                                                      |

---

## 1. Bối cảnh & Triệu chứng ban đầu

### 1.1 Điều kiện tải

Hệ thống được chạy load test với **200 Locust users đồng thời** trong môi trường production (`techx-corp-prod`). Toàn bộ SLO về tỷ lệ thành công (Browse, Cart, Checkout) đều đạt 100% — hệ thống không có request thất bại. Tuy nhiên, **tail latency của Checkout vi phạm nghiêm trọng latency budget**:

| Chỉ số          | Giá trị đo được    | Budget SLO | Kết quả   |
| --------------- | ------------------ | ---------- | --------- |
| Checkout p95    | 3.22s – 4.90s      | 500ms      | ❌ Vi phạm |
| Checkout p99    | 5.88s – 9.65s      | 1s         | ❌ Vi phạm |
| Browse p95      | 16.7ms             | 300ms      | ✅ Đạt    |
| Browse p99      | 80.8ms             | 700ms      | ✅ Đạt    |
| Cart p95        | 42.7ms             | 300ms      | ✅ Đạt    |
| Cart p99        | 108ms              | 700ms      | ✅ Đạt    |

![Grafana trước khi tối ưu tại 200 users](../adr/image/mandate16/before/grafana.png)

*Dashboard Grafana ghi nhận Checkout p95 và p99 vượt budget trong khi các SLO thành công vẫn giữ được 100%.*

---

## 2. Điều tra & Xác định nguyên nhân gốc

### 2.1 Phân tích trace Jaeger — Bottleneck nằm ở CurrencyService

Lấy 4 trace checkout chậm từ Jaeger, tất cả đều có cùng pattern:

**Trace `00ee70b` (6.16s tổng):**

![Checkout single trace 00ee70b](../adr/image/mandate16/before/jaeger-checkout-single1.png)

- Hai lần gọi `CurrencyService/Convert` tuần tự chiếm `4.93s + 771ms` ≈ **95% critical path**.
- Cart, product-catalog, payment, email mỗi bước chỉ vài millisecond.

**Trace `6968014` (5.50s tổng):**

![Checkout single trace 6968014](../adr/image/mandate16/before/jaeger-checkout-single2.png)

- Hai span currency: `1.38s + 2.65s`. Pattern lặp lại.

**Trace `7b56ab2` (6.15s tổng):**

![Checkout multi trace 7b56ab2](../adr/image/mandate16/before/jaeger-checkout-multi1.png)

- Ba lần gọi currency tuần tự: `1.52s + 2.89s + 893ms`.

**Trace `79e2178` (5.69s tổng):**

![Checkout multi trace 79e2178](../adr/image/mandate16/before/jaeger-checkout-multi2.png)

- Năm lần gọi currency tuần tự (giỏ hàng nhiều sản phẩm): `2.84s + 2.05s + 153ms + 395ms + 98ms`.

**Nhận xét:** 4/4 trace chậm đều bị giữ tại `CurrencyService/Convert`. Checkout gọi currency **tuần tự cho từng item**, nên độ trễ mỗi lần cộng dồn. Vấn đề không nằm ở logic checkout hay currency nội bộ — mà nằm ở **tại sao một số lời gọi currency mất 1–5 giây**.

---

### 2.2 Phân tích phân phối tải giữa các Currency pod

Cluster đang chạy **2 replica** cho service `currency`. Đo request rate, CPU và tail latency theo từng pod qua Grafana:

**Request rate theo pod:**

![Currency request rate theo pod](../adr/image/mandate16/before/currency-rps-per-pod.png)

| Pod      | RPS đo được     |
| -------- | --------------- |
| `hth74`  | 4.8 – 9.4 RPS   |
| `5gwwk`  | 0.2 – 3.4 RPS   |

→ `hth74` liên tục nhận **3–10x** nhiều request hơn `5gwwk`.

**Tỷ lệ traffic theo pod:**

![Tỷ lệ traffic của từng Currency pod](../adr/image/mandate16/before/currency-traffic-share-per-pod.png)

- `hth74`: **62–96%** tổng traffic (đỉnh điểm: 95.9%).
- `5gwwk`: chỉ **4–38%**.
- Tỷ lệ kỳ vọng nếu cân bằng: ~50%/50%.

**Tail latency theo pod:**

![Currency p95 theo pod](../adr/image/mandate16/before/currency-p95-per-pod.png)
![Currency p99 theo pod](../adr/image/mandate16/before/currency-p99-per-pod.png)

| Pod     | p95         | p99          |
| ------- | ----------- | ------------ |
| `hth74` | ~1,142.7ms  | ~11,100ms    |
| `5gwwk` | ~97.0ms     | ~210ms       |

→ Pod nhận nhiều traffic hơn có p99 **cao hơn 52.9x**. Đây chính là nguyên nhân checkout chờ hàng giây.

**CPU theo pod:**

![Currency CPU theo pod](../adr/image/mandate16/before/currency-cpu-per-pod.png)

| Pod     | CPU          |
| ------- | ------------ |
| `hth74` | ~29.2m       |
| `5gwwk` | ~1.0m        |

→ Chuỗi tương quan rõ ràng: **RPS dồn → CPU cao → latency cao → checkout chờ**.

---

### 2.3 Vấn đề có hệ thống — Không chỉ currency

Đo CPU theo pod cho các service khác qua 5 snapshot trong cùng cửa sổ tải:

| Service          | Độ lệch CPU (max/min) | Nhận xét                             |
| ---------------- | --------------------- | ------------------------------------ |
| `frontend`       | 4.3x – 24.7x          | Lệch lớn, liên tục trong 5 mẫu      |
| `currency`       | 3.0x – 9.0x           | Một replica luôn nóng hơn            |
| `product-reviews`| 6.4x – 10.7x          | Lệch kéo dài giữa 3 replica         |
| `recommendation` | 6.0x – 11.7x          | Lệch kéo dài giữa 4 replica         |
| `cart`           | 1.4x – 3.0x           | Lệch vừa phải                        |

→ Đây **không phải vấn đề riêng của currency**. Toàn bộ hệ thống có hiện tượng tải không phân đều giữa các replica.

---

### 2.4 Root Cause — gRPC Connection Pinning

Phân tích source code `checkout/main.go`:

```go
// Trước khi sửa
func mustCreateClient(svcAddr string) *grpc.ClientConn {
    c, err := grpc.NewClient(svcAddr, // "currency:8080" → ClusterIP VIP
        grpc.WithTransportCredentials(insecure.NewCredentials()),
        grpc.WithStatsHandler(otelgrpc.NewClientHandler()),
    )
    // Không có round_robin, không có dns:/// scheme
    return c
}
```

**Cơ chế gây ra vấn đề:**

```
grpc.NewClient("currency:8080")
  → OS DNS resolve → trả về ClusterIP VIP duy nhất (172.20.41.173)
  → Mở 1 HTTP/2 connection duy nhất tới VIP
  → kube-proxy forward connection này tới pod A khi connection được thiết lập
  → Mọi gRPC request sau đó (multiplexed trên HTTP/2) đều đi qua pod A
  → Pod B không nhận được traffic
```

gRPC dùng **HTTP/2 multiplexing** — nhiều request chia sẻ 1 TCP connection. Kubernetes ClusterIP hoạt động ở L4 (TCP): load balancing chỉ xảy ra khi connection **mới được mở**, không phải từng request. Khi checkout process restart và mở lại connection, kube-proxy iptables random chọn 1 trong 2 pod và ghim vào đó mãi. HPA thêm replica cũng không giải quyết được vì các connection cũ không tái phân phối.

**Kết luận root cause:** Toàn bộ gRPC traffic từ checkout → currency đi qua 1 pod cố định do connection-level load balancing của ClusterIP. Đây là hạn chế kiến trúc ảnh hưởng toàn bộ 18 service gRPC trong hệ thống.

---

## 3. Giải pháp: Linkerd Service Mesh

### 3.1 Lý do chọn Linkerd

| Tiêu chí                   | Headless Service             | Linkerd Service Mesh              |
| -------------------------- | ---------------------------- | --------------------------------- |
| **Phạm vi**                | Phải cấu hình từng service   | Inject 1 lần → áp dụng 18 service |
| **Thay đổi code**          | Sửa env var + client config  | **Không cần đụng code**            |
| **gRPC Load Balancing**    | L4 DNS-level                 | **L7 per-request** (đúng cấp)     |
| **Các tính năng thêm**     | Không có                     | mTLS, observability, retries       |
| **Rủi ro khi thay đổi**    | Cao (sửa từng service)       | Thấp (non-invasive sidecar)        |

Linkerd inject sidecar proxy `linkerd-proxy` vào mỗi pod. Proxy này hiểu gRPC (HTTP/2) và thực hiện **L7 per-request load balancing** — mỗi gRPC call được gửi tới pod ít tải nhất, không phụ thuộc vào connection hiện tại.

### 3.2 Kiến trúc triển khai

Linkerd được triển khai hoàn toàn qua **ArgoCD GitOps**, theo đúng mô hình GitOps hiện tại của hệ thống:

```
gitops/
└── linkerd/
    ├── README.md                        ← Hướng dẫn + ADR reference
    ├── appproject.yaml                  ← AppProject "linkerd" (sync-wave: -1)
    └── applications/
        ├── linkerd-crds.yaml            ← Cài CRDs (sync-wave: 0)
        └── linkerd-control-plane.yaml   ← Cài control plane (sync-wave: 1)

gitops/clusters/prod/
└── linkerd-application.yaml            ← Đăng ký vào root app-of-apps
```

**Sync order được đảm bảo bởi sync-wave annotations:**

```
wave -1 → AppProject "linkerd" (phải tạo trước để Applications tham chiếu)
wave  0 → linkerd-crds (CRDs phải tồn tại trước control plane)
wave  1 → linkerd-control-plane (proxy-injector, destination, identity)
```

### 3.3 Cấu hình Linkerd Control Plane

```yaml
# gitops/linkerd/applications/linkerd-control-plane.yaml (trích)
identity:
  issuer:
    scheme: kubernetes.io/tls   # Đọc issuer cert từ K8s Secret
proxy:
  resources:
    cpu:    { request: 10m,  limit: 100m  }
    memory: { request: 20Mi, limit: 250Mi }
proxyInjector:
  failurePolicy: Ignore   # Không block pod creation nếu injector tạm thời down
```

Resource overhead mỗi pod: **10m CPU / 20Mi RAM** — phù hợp với budget hiện tại (BUDGET.md).

### 3.4 Kích hoạt proxy injection

Namespace `techx-corp-prod` được annotate qua Helm template (`templates/linkerd-namespace-inject.yaml`), đảm bảo GitOps owns metadata:

```yaml
# templates/linkerd-namespace-inject.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: techx-corp-prod
  annotations:
    linkerd.io/inject: enabled
    config.linkerd.io/proxy-cpu-request:    "10m"
    config.linkerd.io/proxy-cpu-limit:      "100m"
    config.linkerd.io/proxy-memory-request: "20Mi"
    config.linkerd.io/proxy-memory-limit:   "250Mi"
```

### 3.5 Thay đổi code checkout

Code `checkout/main.go` được revert về trạng thái sạch — không cần `dns:///` scheme hay `round_robin` serviceConfig nữa vì Linkerd proxy sẽ intercept và handle L7 LB:

```go
// Sau khi sửa — Linkerd proxy handle load balancing
func mustCreateClient(svcAddr string) *grpc.ClientConn {
    // Linkerd sidecar proxy intercepts this connection and performs
    // L7 (per-request) load balancing across all destination pod replicas automatically.
    c, err := grpc.NewClient(svcAddr,
        grpc.WithTransportCredentials(insecure.NewCredentials()),
        grpc.WithStatsHandler(otelgrpc.NewClientHandler()),
    )
    return c
}
```

Ngoài ra, các lời gọi downstream trong checkout đã được **song song hóa bằng `errgroup`** (commit `be9c187`) — giảm thêm latency cộng dồn khi gọi nhiều service đồng thời.

---

## 4. Kết quả

> **Trạng thái: 🔄 Đang xác nhận trên production.**
>
> Linkerd đang trong quá trình deploy. Phần này sẽ được cập nhật sau khi chạy lại load test 200 users và có số liệu so sánh đầy đủ.

### 4.1 Điều kiện xác nhận thành công

Bản sửa được coi là thành công khi đồng thời đạt **tất cả** các điều kiện sau, tại cùng mức tải 200 Locust users:

| Điều kiện                                         | Ngưỡng mục tiêu          |
| ------------------------------------------------- | ------------------------ |
| Tỷ lệ traffic Currency pod 1 / pod 2              | Gần 50% / 50%            |
| Chênh lệch CPU giữa 2 Currency replica            | Giảm rõ rệt so với trước |
| Checkout p95                                      | ≤ 500ms (đạt SLO)        |
| Checkout p99                                      | ≤ 1s (đạt SLO)           |
| Tổng tài nguyên cluster (node count, instance type) | Không tăng               |

### 4.2 Kết quả dự kiến

- **Tải cân bằng hơn:** Linkerd proxy intercept mỗi gRPC request và gửi tới pod ít tải nhất (EWMA algorithm).
- **Checkout p95/p99 giảm:** Khi currency không còn bị dồn vào 1 pod, latency mỗi lời gọi `CurrencyService/Convert` giảm xuống, kéo theo checkout end-to-end giảm.
- **Áp dụng cho toàn hệ thống:** frontend → product-catalog, frontend → recommendation, frontend → cart cũng được hưởng lợi mà không cần thêm config.

---

## 5. Các lựa chọn thay thế đã xem xét và lý do từ chối

### Phương án A: Headless Service per gRPC backend

Tạo `ClusterIP: None` service cho từng backend (currency-headless, cart-headless, ...), cấu hình DNS resolver `dns:///` và `round_robin` trong gRPC client.

**Lý do từ chối:**
- Phải cấu hình riêng cho 18 service → tốn công, dễ sót.
- Phải sửa env var của tất cả client service (checkout, frontend, ...).
- Chỉ giải quyết ở L4 DNS level, không phải L7.
- Không giải quyết được HTTP/1.1 keep-alive pinning ở frontend.

### Phương án B: Tăng minReplicas

Tăng replica để "pha loãng" tải vào pod bị ghim.

**Lý do từ chối:**
- Không giải quyết root cause — vẫn bị connection pinning, chỉ giảm xác suất.
- Tốn ngân sách cluster mà không giải quyết được vấn đề kỹ thuật.
- HPA đã tự scale dựa trên RPS/CPU, thêm minReplicas không thay đổi cơ chế phân phối.

### Phương án C: Envoy Sidecar (Istio)

**Lý do từ chối:**
- Istio phức tạp hơn Linkerd nhiều lần (CRD surface, control plane footprint).
- Resource overhead cao hơn — không phù hợp với budget tight hiện tại.
- Linkerd đơn giản hơn, đủ để giải quyết vấn đề, và là CNCF graduated project ổn định.

---

## 6. Ảnh hưởng và rủi ro

| Rủi ro                                    | Mức độ   | Biện pháp giảm thiểu                                                   |
| ----------------------------------------- | -------- | ---------------------------------------------------------------------- |
| Rolling restart toàn bộ pod khi inject    | Trung bình | Thực hiện khi không có load test; PodDisruptionBudget hiện có đảm bảo rolling |
| Linkerd proxy tạm thời không available    | Thấp     | `failurePolicy: Ignore` — pod vẫn tạo được nếu injector down           |
| Resource overhead ~10m CPU / 20Mi / pod  | Thấp     | Đã tính toán phù hợp với BUDGET.md; cluster hiện không bị CPU pressure |
| Xung đột với runtime-hardening policy    | Thấp     | Linkerd proxy chạy với UID 2102 (non-root); tuân thủ runAsNonRoot policy |

---

## 7. Files thay đổi

### `tf2-corp-chart`

| File | Loại | Mô tả |
| ---- | ---- | ----- |
| `gitops/linkerd/README.md` | NEW | Hướng dẫn Linkerd GitOps, cert generation, rollback |
| `gitops/linkerd/appproject.yaml` | NEW | AppProject "linkerd" với whitelist CRDs và webhooks |
| `gitops/linkerd/applications/linkerd-crds.yaml` | NEW | ArgoCD Application cài Linkerd CRDs (sync-wave 0) |
| `gitops/linkerd/applications/linkerd-control-plane.yaml` | NEW | ArgoCD Application cài control plane (sync-wave 1) |
| `gitops/clusters/prod/linkerd-application.yaml` | NEW | Đăng ký vào root app-of-apps prod |
| `templates/linkerd-namespace-inject.yaml` | NEW | Namespace resource với `linkerd.io/inject: enabled` |

### `tf2-corp-platform`

| File | Loại | Mô tả |
| ---- | ---- | ----- |
| `src/checkout/main.go` | MODIFY | Revert `dns:///` và `round_robin`; thêm errgroup parallelization |

---

## 8. Tham chiếu

- [gitops/linkerd/README.md](../../gitops/linkerd/README.md) — Hướng dẫn đầy đủ về Linkerd GitOps
- [Linkerd gRPC Load Balancing](https://linkerd.io/2.17/features/load-balancing/)
- [Linkerd GitOps with ArgoCD](https://linkerd.io/2.17/tasks/gitops/)
- [BUDGET.md](../../../onboarding/BUDGET.md)
- [SLO.md](../../../onboarding/SLO.md)

---

*Ký: **Nguyễn Đức Chinh** — CDO-03 / Task Force 2 — 2026-07-24*

<!-- Change trail: @chinhgithub04 - 2026-07-24 - M16: Rewrite as proper ADR with root cause analysis and Linkerd solution. -->