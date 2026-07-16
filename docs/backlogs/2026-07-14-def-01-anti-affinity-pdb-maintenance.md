# Backlog: DEF-01 - Bảo vệ luồng ra tiền qua Pod Anti-Affinity và Pod Disruption Budget (PDB)

## Bối cảnh

Trong quá trình chuẩn bị cho **Directive #3 (Bảo trì trong giờ vận hành - luồng ra tiền không được rớt)**, hạ tầng EKS của TechX Corp cần phải thực hiện các đợt tắt máy chủ / bảo trì node vật lý (`kubectl drain node`) hoặc khởi động lại rolling-restart các dịch vụ mà không được phép làm rơi request của khách hàng, đảm bảo SLO checkout >= 99%.

Mặc dù các microservice quan trọng trên luồng ra tiền đã được nâng cấu hình lên tối thiểu 2 replicas, hệ thống vẫn ghi nhận các khoảng thời gian bị sập kết nối tạm thời (**connection timeout / no data**) trong quá trình bảo trì node.

## Vấn đề

Khi phân tích trạng thái hoạt động thực tế của các Pod trong cụm EKS, chúng tôi phát hiện 2 điểm yếu chí tử sau:

1. **Hiện tượng chạy chung Node (Pod Co-location):**
   * Do thiếu luật chống đồng địa điểm dạng cứng (**Hard Pod Anti-Affinity**), scheduler của Kubernetes tự động xếp tất cả các bản sao (replicas) của cùng một dịch vụ chạy chung trên **cùng một node vật lý** để tối ưu hóa vị trí mạng.
   * *Ví dụ thực tế:* Cả 2 pod `frontend` đều chạy chung trên node `ip-10-0-11-145`, và cả 2 pod `frontend-proxy` đều chạy chung trên node `ip-10-0-11-104`.
   * *Hậu quả:* Khi node `145` hoặc `104` bị drain (tắt máy chủ vật lý), tất cả các replica của dịch vụ đó bị tắt cùng một lúc. Hệ thống hoàn toàn không còn pod nào chạy để gánh tải (0 ready replica), dẫn đến sập kết nối đối với người dùng cuối.

2. **Thiếu ràng buộc bảo vệ số lượng Pod tối thiểu (Pod Disruption Budget - PDB):**
   * Khi thực hiện lệnh bảo trì node tự nguyện (`kubectl drain`), Kubernetes sẽ trục xuất (evict) các pod ngay lập tức mà không kiểm tra xem dịch vụ đó có còn pod nào khác đang sống để phục vụ khách hàng hay không.
   * *Hậu quả:* Cả hai pod của dịch vụ đều bị tắt đồng thời trước khi pod mới trên node khác kịp khởi động xong và vượt qua bài test kiểm tra sức khỏe (Readiness Probe).

---

## Giải pháp đề xuất

Để đảm bảo luồng ra tiền không bị rớt bất kỳ gói tin nào khi bảo trì node, chúng tôi đề xuất áp dụng đồng thời hai cơ chế sau cho tất cả các dịch vụ thuộc hot-path (`frontend`, `frontend-proxy`, `checkout`, `cart`, `product-catalog`):

### 1. Bắt buộc chạy trên các Node khác nhau (Hard Pod Anti-Affinity)
* **Cấu hình:** Sử dụng luật `requiredDuringSchedulingIgnoredDuringExecution` (Hard Anti-Affinity).
* **Quy tắc:** Scheduler sẽ từ chối xếp một pod mới vào một node nếu node đó đã có một pod cùng loại đang chạy.
* **Kết quả:** Pod replica 1 chạy trên Node A, Pod replica 2 bắt buộc phải chạy trên Node B. Khi Node A sập/bảo trì, Pod replica 2 vẫn hoạt động bình thường trên Node B để xử lý request của khách hàng.

### 2. Thiết lập ngân sách bảo vệ Pod (Pod Disruption Budget - PDB)
* **Cấu hình:** Tạo tài nguyên `PodDisruptionBudget` cho từng microservice với tham số `minAvailable: 1` hoặc `maxUnavailable: 1`.
* **Kết quả:** Khi chạy lệnh `kubectl drain`, Kubernetes sẽ từ chối tắt pod trên node đang bảo trì nếu pod mới ở node khác chưa đạt trạng thái `Ready 1/1`. Pod cũ chỉ bị tắt đi sau khi pod mới đã online và sẵn sàng gánh tải.

---

## Các thay đổi dự kiến (Proposed Changes)

### 1. Cấu hình Helm Chart (`tf2-corp-chart`)

* **[MODIFY] [values.yaml](file:///d:/Workspace/Study/AWS/capstone-phase-3/tf2-corp-chart/values.yaml)**
  * Bật cấu hình `podAntiAffinity` dạng `hard` làm mặc định cho các dịch vụ quan trọng.
  * Bật cấu hình `podDisruptionBudget.enabled: true` và set `minAvailable: 1`.

* **[MODIFY] [templates/component.yaml](file:///d:/Workspace/Study/AWS/capstone-phase-3/tf2-corp-chart/templates/component.yaml)**
  * Cập nhật template Deployment của ứng dụng để tự động inject cấu hình `affinity.podAntiAffinity` nếu được khai báo trong values.

* **[NEW] [templates/pdb.yaml](file:///d:/Workspace/Study/AWS/capstone-phase-3/tf2-corp-chart/templates/pdb.yaml)**
  * Định nghĩa template Kubernetes `PodDisruptionBudget` cho các component có bật PDB.

---

## Ảnh hưởng và Đánh giá tác động (Impact Analysis)

| Chiều tác động | Ảnh hưởng | Biện pháp giảm thiểu |
| :--- | :--- | :--- |
| **Độ tin cậy (Reliability)** | **Tăng cực kỳ cao**. Đạt 0% downtime khi bảo trì node vật lý. | Không có. |
| **Yêu cầu Tài nguyên (Resource Demand)** | **Tăng nhẹ**. Do bắt buộc chạy trên các node khác nhau, cụm EKS bắt buộc phải duy trì tối thiểu 2 nodes hoạt động đồng thời khi scale ứng dụng. | Karpenter đã được kích hoạt trên cụm để tự động cấp thêm node khi phát hiện thiếu RAM/CPU. |
| **Chi phí (Cost)** | **Tác động rất nhỏ**. Việc chạy tối thiểu 2 nodes chỉ tốn thêm chi phí thuê node EC2. | Karpenter có tính năng Consolidation giúp tự động thu hồi/tắt bớt node trống khi tải giảm, đảm bảo trong ngân sách $300/tuần. |
| **Tính tương thích (Compatibility)** | Hoàn toàn tương thích và không ảnh hưởng đến logic code của microservice. | N/A |

---

## Kịch bản xác minh (Verification Plan)

1. **Chạy tải mô phỏng:** Sử dụng Locust chạy 200 users để tạo tải liên tục vào storefront.
2. **Thực hiện bảo trì:** Chạy lệnh drain node vật lý đang chứa pod ứng dụng chính:
   ```bash
   kubectl drain <tên_node_đang_chứa_frontend> --ignore-daemonsets --delete-emptydir-data
   ```
3. **Theo dõi SLO:**
   * Kiểm tra xem Pod mới có được lập lịch thành công trên node khác trước khi pod cũ bị hủy không.
   * Xem biểu đồ Grafana: Đảm bảo chỉ số SLO checkout duy trì ở mức **100%** (không bị lỗi 5xx hay timeout).
