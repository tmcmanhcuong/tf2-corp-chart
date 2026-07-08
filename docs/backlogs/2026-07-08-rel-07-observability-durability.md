# Backlog: REL-07 - Tăng độ bền observability stack

## Bối cảnh

`techx-corp-chart` triển khai kèm observability stack để thu thập và hiển thị metrics, logs, traces và dashboards cho toàn bộ nền tảng TechX Corp. Stack này gồm `opentelemetry-collector`, `prometheus`, `grafana`, `jaeger` và `opensearch`.

Nếu observability stack không đủ bền, sự cố ứng dụng có thể xảy ra nhưng team lại thiếu dữ liệu để điều tra: metrics bị mất sau restart, logs không được ghi lại, dashboard Grafana mất cấu hình runtime, hoặc collector bị nghẽn khi backend tạm thời chậm.

## Vấn đề

Cấu hình trước đó còn một số điểm yếu ở mức Helm chart:

- `prometheus.server.persistentVolume.enabled` đang tắt, metrics có thể mất khi pod bị recreate.
- `grafana.persistence.enabled` chưa bật, dữ liệu runtime của Grafana không bền qua restart.
- `opensearch.persistence.enabled` đang tắt, log storage không bền.
- `opentelemetry-collector` có resource limit nhưng thiếu resource request, dễ bị schedule vào node không đủ tài nguyên.
- Exporter của collector chưa có retry/queue rõ ràng cho các backend `jaeger`, `prometheus` và `opensearch`.
- Batch processor chưa được định nghĩa rõ threshold, làm pipeline kém ổn định khi telemetry tăng đột biến.

## Giải pháp đề xuất

1. Bật persistent volume cho các thành phần lưu trữ chính:
   - `prometheus.server.persistentVolume.enabled: true`
   - `grafana.persistence.enabled: true`
   - `opensearch.persistence.enabled: true`
2. Thêm kích thước PVC mặc định để môi trường triển khai có baseline rõ ràng:
   - Prometheus: `8Gi`
   - Grafana: `1Gi`
   - OpenSearch: `10Gi`
3. Thêm `resources.requests` cho các component observability trọng yếu để scheduler có tín hiệu tài nguyên tối thiểu.
4. Thêm `retry_on_failure` và `sending_queue` cho các exporter của `opentelemetry-collector`:
   - `otlp/jaeger`
   - `otlphttp/prometheus`
   - `opensearch`
5. Cấu hình batch processor với `timeout`, `send_batch_size` và `send_batch_max_size` để giảm áp lực lên backend khi telemetry burst.
6. Giữ Jaeger ở memory storage trong phạm vi task này, nhưng tăng resource baseline và batch config. Persistent trace storage nên được thiết kế riêng nếu cần SLA lưu trace dài hạn.

## Acceptance Criteria

- Helm lint chạy thành công không có lỗi.
- Helm template render thành công sau khi chạy `helm dependency build`.
- Manifest render có PVC/persistence cho Prometheus, Grafana và OpenSearch.
- OTel Collector render ra cấu hình `retry_on_failure`, `sending_queue` và `batch` processor.
- Các thay đổi không expose thêm route public mới và không thay đổi logic business của application services.

## Kiểm thử / xác minh

1. Tải dependency Helm:
   ```sh
   helm dependency build .
   ```
2. Kiểm tra cú pháp chart:
   ```sh
   helm lint .
   ```
3. Render manifest:
   ```sh
   helm template techx . > rendered.yaml
   ```
4. Xác minh persistence và collector durability config:
   ```sh
   grep -n "PersistentVolumeClaim\\|retry_on_failure\\|sending_queue\\|send_batch_size" rendered.yaml
   ```

## Rủi ro & rollback

- **Rủi ro**: Bật PVC cho observability stack yêu cầu cluster có default StorageClass hoặc cấu hình storage class phù hợp. Nếu không có, pod có thể bị kẹt ở trạng thái `Pending`.
- **Rủi ro**: Queue/retry giúp giảm mất telemetry khi backend chậm, nhưng nếu backend lỗi kéo dài, collector vẫn có thể drop dữ liệu khi queue đầy.
- **Rollback**: Tắt lại các khóa persistence (`prometheus.server.persistentVolume.enabled`, `grafana.persistence.enabled`, `opensearch.persistence.enabled`) và giảm cấu hình queue/retry của collector về mặc định trước đó.

---

## English Summary

This backlog tracks Helm-level hardening for the observability stack. It enables persistence for Prometheus, Grafana, and OpenSearch; adds resource requests/limits for critical observability components; and configures OpenTelemetry Collector exporter retry queues and batching to reduce telemetry loss during backend slowness or restarts.
