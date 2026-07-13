# SEC-02 - Siết truy cập Grafana và UI observability

## 1. Mục tiêu

Mục tiêu của SEC-02 là giảm rủi ro lộ dữ liệu vận hành từ Grafana và các UI observability, nhưng vẫn giữ đầy đủ khả năng theo dõi SLO, điều tra incident và vận hành hệ thống.

Hiện tại Grafana không chỉ là dashboard đẹp. Nó chứa thông tin rất nhạy cảm về service topology, latency, error rate, datasource, logs, traces và health của toàn hệ thống. Nếu endpoint này bị mở rộng ra ngoài hoặc bị người không đúng quyền truy cập, họ có thể đọc được cách hệ thống vận hành, nhìn thấy service nào yếu, datasource nào đang dùng, thậm chí chỉnh dashboard hoặc datasource nếu có quyền admin.

SEC-02 vì vậy tập trung vào việc chuyển Grafana từ trạng thái demo-friendly sang trạng thái vận hành an toàn hơn:

- Người chưa đăng nhập không được xem hoặc sửa Grafana.
- Anonymous user không còn quyền Admin.
- Password mặc định `admin` không còn nằm trong Helm values.
- Dashboard và datasource vẫn được provision tự động để team tiếp tục vận hành SLO.
- Không thay đổi luồng checkout, storefront, telemetry pipeline hoặc cơ chế `flagd` của BTC.

## 2. Tình trạng hiện tại

### 2.1. Trước khi implement

Trước SEC-02, `tf2-corp-chart/values.yaml` cấu hình Grafana ở dạng tiện cho demo hơn là an toàn cho vận hành:

```yaml
grafana:
  grafana.ini:
    auth:
      disable_login_form: true
    auth.anonymous:
      enabled: true
      org_name: Main Org.
      org_role: Admin
  adminPassword: admin
```

Ý nghĩa thực tế:

- `disable_login_form: true`: tắt màn hình đăng nhập, khiến team không có cơ chế login rõ ràng.
- `auth.anonymous.enabled: true`: người không đăng nhập vẫn vào được Grafana.
- `org_role: Admin`: anonymous user có quyền quá cao, có thể thay đổi cấu hình quan trọng.
- `adminPassword: admin`: credential mặc định nằm thẳng trong values, dễ bị lộ qua Git, Helm render hoặc manifest.

### 2.2. UI observability đang được expose qua frontend-proxy

Trong all-in-one baseline, `frontend-proxy` route các UI observability qua cùng cổng `8080`:

- `/grafana/` -> Grafana
- `/jaeger/` -> Jaeger UI
- `/loadgen/` -> Locust load generator
- `/feature` -> flagd UI khi sidecar còn bật

Điều này giúp onboarding dễ hơn, nhưng cũng làm rủi ro tăng lên: nếu endpoint `frontend-proxy` bị expose rộng, các UI nội bộ có thể bị truy cập cùng với storefront.

Trong mô hình observability-only ở `deploy/values-observability.yaml`, các app component và `frontend-proxy` bị tắt. Khi đó trọng tâm hardening là chính Grafana chart và cách service Grafana được expose ra ngoài.

## 3. Phương án kỹ thuật

### 3.1. Hardening Grafana authentication

Đã thay đổi cấu hình Grafana theo hướng bắt buộc đăng nhập:

```yaml
grafana:
  grafana.ini:
    auth:
      disable_login_form: false
    auth.anonymous:
      enabled: false
    server:
      root_url: "%(protocol)s://%(domain)s:%(http_port)s/grafana"
      serve_from_sub_path: true
```

Giữ `root_url` và `serve_from_sub_path: true` để không phá đường dẫn `/grafana/` hiện tại.

Không giữ `org_role: Admin` cho anonymous user. Khi anonymous đã tắt, role này không còn cần thiết trong cấu hình.

### 3.2. Chuyển admin password sang Kubernetes Secret

Đã bỏ `grafana.adminPassword: admin` khỏi `values.yaml`. Admin credential được lấy từ Kubernetes Secret tên `grafana-admin`:

Tạo Kubernetes Secret do TF quản lý, ví dụ:

```powershell
kubectl -n <namespace> create secret generic grafana-admin `
  --from-literal=admin-user=admin `
  --from-literal=admin-password=<strong-password>
```

Chart hiện dùng secret reference sau:

```yaml
grafana:
  admin:
    existingSecret: grafana-admin
    userKey: admin-user
    passwordKey: admin-password
```

Secret value không được commit vào Git. Trước khi deploy, TF cần tạo secret này trong namespace chạy Grafana.

### 3.3. Giữ dashboard và datasource provisioning

Giữ nguyên cơ chế provisioning hiện tại:

- `tf2-corp-chart/templates/grafana-config.yaml` tạo ConfigMap cho alerting, dashboards và datasources.
- `grafana.sidecar.alerts.enabled: true`
- `grafana.sidecar.dashboards.enabled: true`
- `grafana.sidecar.datasources.enabled: true`

Điều này đảm bảo sau khi bật authentication, team vẫn có dashboard để theo dõi SLO, latency, error rate, logs và traces.

Đã đổi datasource provisioned sang non-editable để giảm rủi ro user sửa nhầm datasource:

```yaml
editable: false
```

Thay đổi này áp dụng trong `tf2-corp-chart/grafana/provisioning/datasources/default.yaml`.

### 3.4. Kiểm soát các UI observability khác

SEC-02 ưu tiên Grafana vì Grafana hiện có anonymous admin và password mặc định. Tuy nhiên khi pitch cần nói rõ observability UI không chỉ có Grafana.

Các endpoint cần được xem là UI nội bộ:

- `/grafana/`: dashboard, datasource, alerting, logs/traces qua datasource.
- `/jaeger/`: distributed tracing, có thể lộ topology và request path.
- `/loadgen/`: công cụ sinh tải, nếu mở rộng có thể bị dùng sai mục đích.
- `/feature`: flagd UI, cần đặc biệt cẩn trọng vì `flagd` là cơ chế BTC dùng để bơm incident.

Nguyên tắc:

- Không public rộng các UI này.
- Nếu cần expose ngoài cluster, đặt auth tại Ingress hoặc lớp proxy.
- Nếu có Ingress controller, ưu tiên allowlist IP của team/mentor hoặc OIDC/basic auth ở ingress.
- Không tắt hoặc đổi hướng `flagd`; chỉ hạn chế UI truy cập, không can thiệp cơ chế đọc flag của service.

## 4. Thay đổi đã implement

### 4.1. File đã sửa

- `values.yaml`: tắt anonymous access, bật login form, bỏ password mặc định và dùng secret `grafana-admin`.
- `grafana/provisioning/datasources/default.yaml`: đổi Prometheus datasource sang `editable: false`.
- `docs/backlogs/sec-02-grafana-observability-access.md`: ghi lại rationale, cách verify, rollback và nội dung pitching.

### 4.2. Secret cần tạo trước khi deploy

Tạo secret trong namespace deploy:

```powershell
kubectl -n <namespace> create secret generic grafana-admin `
  --from-literal=admin-user=admin `
  --from-literal=admin-password=<strong-password>
```

Không commit password thật vào repo.

### 4.3. Cấu hình target

`values.yaml` hiện có cấu hình target sau:

```yaml
grafana:
  grafana.ini:
    auth:
      disable_login_form: false
    auth.anonymous:
      enabled: false
    server:
      root_url: "%(protocol)s://%(domain)s:%(http_port)s/grafana"
      serve_from_sub_path: true
  admin:
    existingSecret: grafana-admin
    userKey: admin-user
    passwordKey: admin-password
```

## 5. Kiểm tra trước deploy

Chạy render trước khi deploy:

```powershell
helm template techx-corp . -n <namespace>
```

Cần xác nhận:

- Không còn `auth.anonymous.enabled: true`.
- Không còn `org_role: Admin` cho anonymous user.
- Không còn `adminPassword: admin`.
- Manifest Grafana có tham chiếu secret.
- Dashboard/datasource ConfigMap vẫn được render.

## 6. Deploy và verify

Deploy bằng Helm:

```powershell
helm upgrade --install techx-corp . -n <namespace>
```

Verify:

```powershell
kubectl -n <namespace> get pods
kubectl -n <namespace> get secret grafana-admin
kubectl -n <namespace> logs deploy/grafana
```

Kiểm tra bằng trình duyệt:

- Truy cập `/grafana/` khi chưa login: phải thấy login form hoặc bị từ chối.
- Login bằng credential trong secret: vào được dashboard.
- Dashboard Prometheus/Jaeger/OpenSearch vẫn load được dữ liệu.

### 6.1. Ghi evidence để pitch

Ghi lại bằng chứng:

- Diff cấu hình trước/sau.
- Output `helm template` chứng minh không còn anonymous admin.
- Screenshot hoặc mô tả login behavior.
- Output `kubectl get pods` cho thấy Grafana vẫn Ready.
- Một dashboard vẫn đọc được metric sau khi hardening.

## 7. Acceptance Criteria

SEC-02 được xem là hoàn thành khi đạt các điều kiện sau:

- Người chưa đăng nhập không thể xem hoặc sửa Grafana.
- Anonymous user không còn quyền Admin.
- `adminPassword: admin` không còn là cấu hình được commit hoặc render ra manifest.
- Admin credential được lấy từ Kubernetes Secret.
- `/grafana/` vẫn hoạt động với `serve_from_sub_path: true`.
- Dashboard, datasource và alerting provisioning vẫn hoạt động.
- Prometheus metrics, Jaeger traces và OpenSearch logs vẫn được Grafana đọc được.
- Storefront, checkout và telemetry pipeline không bị ảnh hưởng.
- Có evidence đủ để mentor kiểm tra.

## 8. Rollback plan

Nếu Grafana không lên hoặc team không thể truy cập sau khi deploy:

1. Kiểm tra secret `grafana-admin` có đúng namespace và đúng key chưa.
2. Kiểm tra log Grafana để xác định lỗi secret, config hoặc subpath.
3. Sửa overlay SEC-02 rồi `helm upgrade` lại.
4. Nếu cần phục hồi nhanh, dùng `helm rollback techx-corp <revision> -n <namespace>`.

Không chọn rollback lâu dài về anonymous admin. Nếu phải rollback tạm thời để khôi phục dashboard trong incident, cần ghi rõ trong decision log và tạo follow-up để bật lại authenticated access ngay sau khi ổn định.

## 9. Pitching

### Vấn đề

SEC-02 là một thay đổi nhỏ về chi phí nhưng lớn về giảm rủi ro. Hệ thống đang dùng observability để vận hành SLO, điều tra incident và bảo vệ checkout. Nếu Grafana mở anonymous admin, người không đúng quyền có thể xem topology, logs, datasource và thay đổi dashboard. Đây là rủi ro security và auditability rõ ràng.

Thay đổi này không đụng code app, không đụng checkout path, không tắt telemetry, không tắt `flagd`. Nó chỉ chuyển UI vận hành từ trạng thái demo sang trạng thái có kiểm soát truy cập.

### Role PM

**Mentor hỏi:** Khách hàng được gì nếu chỉ sửa Grafana?

**Trả lời:** Khách hàng không thấy trực tiếp một feature mới, nhưng họ được bảo vệ gián tiếp. Grafana chứa thông tin giúp attacker hiểu service nào yếu, endpoint nào lỗi, hệ thống phụ thuộc vào gì. Giảm lộ dữ liệu vận hành giúp giảm khả năng incident bảo mật lan tới trải nghiệm khách hàng và checkout.

### Role CFO

**Mentor hỏi:** Việc này tốn bao nhiêu?

**Trả lời:** Chi phí hạ tầng gần như bằng 0. Không cần thêm node, không cần managed service mới. Đây là hardening bằng cấu hình Helm và Kubernetes Secret. ROI tốt vì giảm rủi ro lộ thông tin vận hành mà không làm tăng đáng kể chi phí trong trần khoảng 300 USD/tuần.

### Role SRE lead

**Mentor hỏi:** Có làm mất khả năng quan sát hệ thống không?

**Trả lời:** Không. Dashboard, datasource và sidecar provisioning vẫn giữ nguyên. Prometheus, Jaeger và OpenSearch vẫn chạy. Điểm thay đổi chỉ là người dùng phải login trước khi xem/sửa Grafana. Acceptance criteria có kiểm tra cả Grafana login và dashboard data sau deploy.

### Rollback

**Mentor hỏi:** Nếu deploy xong Grafana không vào được thì sao?

**Trả lời:** Rollback bằng Helm revision hoặc sửa secret/config rồi upgrade lại. Vì thay đổi này không đụng app path, checkout vẫn tiếp tục chạy. Nếu rollback tạm thời, team không giữ anonymous admin như trạng thái lâu dài mà phải ghi decision log và xử lý lại ngay.
