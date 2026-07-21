# MANDATE-16.1 - Tail Latency Baseline and Budget

## Dashboard

- Name: Webstore SLOs & Resources
- UID: `webstore-perf-slo-res`
- URL: https://internal.hungtran.id.vn/grafana/d/webstore-perf-slo-res

## Mục tiêu đo

Đo p95 và p99 của ba thao tác người dùng thuộc critical flow:

| Flow | API được đo | Measurement boundary |
|---|---|---|
| Browse | `GET /api/products/{productId}` | HTTP end-to-end tại frontend |
| Cart | `POST /api/cart` | HTTP end-to-end tại frontend |
| Checkout | `POST /api/checkout` | HTTP end-to-end tại frontend |

Các service nội bộ như product-catalog, payment, email, Kafka/MSK và PostgreSQL không phải là các dòng kết quả riêng của MANDATE-16.1. Chúng sẽ được điều tra bằng Jaeger trong MANDATE-16.2 sau khi xác định được mức tải gây nghẽn.

## Điều kiện test cố định

- Cluster: `techx-tf2-prod`
- Namespace: `techx-corp-prod`
- Browser traffic: disabled
- Locust workload: default mixed HTTP workload
- Spawn rate: 10 users/second
- Warm-up: 5 phút
- Measurement: 20 phút cho mỗi mức tải
- Load levels: 200, 300, 400, sau đó tăng 500, 600, 700... cho tới breakpoint
- Load-generator workers: cố định 3 replicas trong toàn bộ chuỗi test
- Application HPA: vẫn bật
- Cluster capacity: cố định 6 nodes
- Karpenter controller: tạm scale về 0 trong toàn bộ chuỗi test
- Giữa hai mức tải: Stop, Reset, đợi workload ổn định rồi mới chạy mức tiếp theo

Không được thay đổi số node, số load-generator worker, workload mix, spawn rate hoặc thời gian đo giữa các mức tải. Nếu một điều kiện thay đổi, run đó phải đánh dấu `Invalid` và chạy lại.

## Trạng thái trước chuỗi test

- Snapshot time: `2026-07-20T21:30:27+07:00`
- Nodes: 6 Ready
  - 2 node nền On-Demand `t4g.large`
  - 4 node Karpenter Spot: `c7g.large`, `c7g.large`, `c8g.large`, `c9g.large`
- Karpenter Deployment: `0/0`
- Load generator: 1 master, 3 workers
- Application pods: Running; không có pod Pending hoặc CrashLoopBackOff
- Cảnh báo pre-test: ba Spot node đang dùng khoảng 92%, 96% và 92% memory. Nếu xảy ra OOM/Pending dưới tải, phải ghi nhận như một capacity constraint.
- Raw snapshot: `docs/evidence/mandate-16/tail-latency/pre-test-fixed-6-nodes/cluster-state.txt`

## Ngân sách độ trễ đề xuất

| Flow | p95 budget | p99 budget | Trạng thái |
|---|---:|---:|---|
| Browse | < 300 ms | < 700 ms | Proposed |
| Cart | < 300 ms | < 700 ms | Proposed |
| Checkout | < 500 ms | < 1000 ms | Proposed |

`Max` lớn hơn budget không tự động làm vi phạm SLO. Kết luận pass/fail dựa trên p95, p99 và failure rate trong đúng measurement window.

## Kết quả chính thức

| Users | Duration | Avg RPS | Flow | Requests | Failures | p95 | p99 | Nodes start/end | Pods start/end | Result |
|---:|---:|---:|---|---:|---:|---:|---:|---|---|---|
| 200 | 22m20s | 41.60* | Browse | 36,913* | 0 | 6.32 ms | 34.2 ms | 6/6 | 52/52 | Valid; passed budget |
| 200 | 22m20s | 41.60* | Cart | 13,905* | 0 | 9.72 ms | 46.3 ms | 6/6 | 52/52 | Valid; passed budget |
| 200 | 22m20s | 41.60* | Checkout | 4,634* | 0 | 96.1 ms | 176 ms | 6/6 | 52/52 | Valid; passed budget |
| 300 | 21m54s | 63.17 | Browse | 38,179 | 0 | 7.08 ms | 39.7 ms | 6/6 | 52R+2P / 53R+2P | Passed latency budget; capacity warning |
| 300 | 21m54s | 63.17 | Cart | 14,281 | 0 | 18.4 ms | 55.8 ms | 6/6 | 52R+2P / 53R+2P | Passed latency budget; capacity warning |
| 300 | 21m54s | 63.17 | Checkout | 4,790 | 0 | 96.9 ms | 174 ms | 6/6 | 52R+2P / 53R+2P | Passed latency budget; capacity warning |
| 400 | 27m00s | 84.35 | Browse | 60,570 | 0 | 7.92 ms | 45.4 ms | 6/6 | 53R+5P / 53R+5P | Passed latency budget; scheduling constrained |
| 400 | 27m00s | 84.35 | Cart | 23,018 | 0 | 17.4 ms | 49.5 ms | 6/6 | 53R+5P / 53R+5P | Passed latency budget; scheduling constrained |
| 400 | 27m00s | 84.35 | Checkout | 7,719 | 0 | 99.3 ms | 186 ms | 6/6 | 53R+5P / 53R+5P | Passed latency budget; scheduling constrained |
| 500 | 28m23s | 104.66 | Browse | 79,634 | 0 | 18.0 ms | 48.1 ms | 6/6 | 54R+8P / 54R+8P | Passed latency budget; severe scheduling constraint |
| 500 | 28m23s | 104.66 | Cart | 29,554 | 0 | 24.6 ms | 53.9 ms | 6/6 | 54R+8P / 54R+8P | Passed latency budget; severe scheduling constraint |
| 500 | 28m23s | 104.66 | Checkout | 9,828 | 0 | 150 ms | 227 ms | 6/6 | 54R+8P / 54R+8P | Passed latency budget; severe scheduling constraint |
| 600 | 28m04s | 125.56 | Browse | 93,685 | 1 | 23.9 ms | 55.4 ms | 6/6 | 54R+10P / 54R+11P | Passed latency budget; one transient 503; severe scheduling constraint |
| 600 | 28m04s | 125.56 | Cart | 35,057 | 0 | 43.4 ms | 85.7 ms | 6/6 | 54R+10P / 54R+11P | Passed latency budget; severe scheduling constraint |
| 600 | 28m04s | 125.56 | Checkout | 11,636 | 0 | 156 ms | 237 ms | 6/6 | 54R+10P / 54R+11P | Passed latency budget; severe scheduling constraint |
| 700 | 31m20s | 142.49 | Browse | 123,292 | 2 | 30.0 ms | 66.2 ms | 6/6 | 54R+12P / 55R+12P | Passed latency budget; two transient 503s; measurement-window caveat |
| 700 | 31m20s | 142.49 | Cart | 46,070 | 0 | 33.9 ms | 74.5 ms | 6/6 | 54R+12P / 55R+12P | Passed latency budget; severe scheduling constraint; measurement-window caveat |
| 700 | 31m20s | 142.49 | Checkout | 15,480 | 0 | 158 ms | 230 ms | 6/6 | 54R+12P / 55R+12P | Passed latency budget; severe scheduling constraint; measurement-window caveat |
| 800 | 28m19s | 167.49 | Browse | 126,748 | 0 | 37.7 ms | 77.6 ms | 6/6 | 56R+14P / 56R+15P | Passed latency budget; severe scheduling constraint |
| 800 | 28m19s | 167.49 | Cart | 47,235 | 0 | 38.7 ms | 85.8 ms | 6/6 | 56R+14P / 56R+15P | Passed latency budget; severe scheduling constraint |
| 800 | 28m19s | 167.49 | Checkout | 15,791 | 0 | 179 ms | 322 ms | 6/6 | 56R+14P / 56R+15P | Passed latency budget; severe scheduling constraint |
| 1000 | ~28m41s* | 209.74 | Browse | 178,770 | 1 | 45.4 ms | 89.5 ms | 6/6 | 57R+22P / 58R+22P | Passed latency budget; one isolated HTTP 503 |
| 1000 | ~28m41s* | 209.74 | Cart | 66,883 | 0 | 49.2 ms | 111 ms | 6/6 | 57R+22P / 58R+22P | Passed latency budget; severe scheduling constraint |
| 1000 | ~28m41s* | 209.74 | Checkout | 22,383 | 1 | 226 ms | 382 ms | 6/6 | 57R+22P / 58R+22P | Passed latency budget; one isolated HTTP 503 |
| 1200 | 22m44s | 240.50 | Browse | 150,730 | 7 | 97.2 ms | 186 ms | 6/6 | 59R+28P / 59R+30P+1I | **Invalid**; concurrent image publication caused ImagePullBackOff |
| 1200 | 22m44s | 240.50 | Cart | 56,437 | 0 | 195 ms | 365 ms | 6/6 | 59R+28P / 59R+30P+1I | **Invalid**; concurrent image publication caused ImagePullBackOff |
| 1200 | 22m44s | 240.50 | Checkout | 18,984 | 0 | 392 ms | 707 ms | 6/6 | 59R+28P / 59R+30P+1I | **Invalid**; concurrent image publication caused ImagePullBackOff |

Mức 900 users không được thực hiện. Chuỗi test chuyển trực tiếp từ 800 lên 1000 users. Run 1200-01 chỉ được giữ làm contaminated evidence và không được dùng để xác định breakpoint; phải chạy lại 1200 users sau khi rollout ổn định.

### Run 200-01 - Valid on fixed six-node capacity

- Evidence: `docs/evidence/mandate-16/tail-latency/200-users-run-01-fixed-6-nodes`
- Measurement started: `2026-07-20T21:57:28+07:00`
- Measurement ended: `2026-07-20T22:19:48+07:00`
- Duration: 22 phút 20 giây
- Load: 200 users, 3 fixed workers
- HTTP failures: 0
- Nodes: 6/6 Ready; không thay đổi node trong measurement window
- Karpenter: 0/0 trong toàn bộ measurement window
- Ready application/system pods: 52/52; ngoài ra có 2 inventory Job ở trạng thái Completed
- Pod restarts during measurement: 0
- Application scaling: Checkout đã ở 3 replicas khi bắt đầu measurement và giữ 3 replicas tới cuối; các workload chính khác trong bảng HPA giữ nguyên replica.
- Breakpoint: chưa đạt tại 200 users

Giá trị p95/p99 trong bảng là giá trị `Max` của rolling percentile trên Grafana trong đúng absolute measurement window. Đây là cách đo bảo thủ và khớp trực tiếp với các threshold line của dashboard.

`*` Locust không reset statistics ngay sau warm-up và CSV được tải sau khi kết thúc measurement, trong khi tải vẫn giữ cố định 200 users. Vì vậy request count và Average RPS trong CSV bao phủ toàn bộ thời gian chạy cố định và chỉ mang tính diagnostic; chúng không được dùng để tính p95/p99 chính thức. Locust Statistics tại cuối run vẫn xác nhận 200 users, 3 workers, khoảng 41.7 RPS và 0% failures.

#### Capacity observations

- Ba Spot node đã ở mức memory cao tại đầu/cuối run: khoảng 92-98% theo Metrics Server.
- Grafana ghi nhận các workload sử dụng memory lớn gồm Product Reviews khoảng 3.38 GiB, Prometheus tối đa khoảng 1.97 GiB và Shopping Copilot khoảng 1.72 GiB.
- Run không có OOMKilled, Pending hoặc CrashLoopBackOff, nhưng memory headroom thấp có thể trở thành giới hạn tại các load level tiếp theo.
- `05-grafana-resources.png` ghi bảng CPU/RAM trong measurement window. Số node và pod thực tế đã được lưu dạng raw evidence trong `cluster-start.txt` và `cluster-end.txt`; dashboard source vẫn có panel `Scaling Elasticity Trend (Nodes vs Pods)`.

### Run 300-01 - Passed latency budget with a scheduling capacity warning

- Evidence: `docs/evidence/mandate-16/tail-latency/300-users-run-01-fixed-6-nodes`
- Measurement started: `2026-07-20T22:34:33+07:00`
- Measurement ended: `2026-07-20T22:56:27+07:00`
- Duration: 21 phút 54 giây
- Load: 300 users, 3 fixed workers
- Average RPS: 63.17
- Total requests: 85,627
- HTTP failures: 0
- Nodes: 6/6 Ready; không thay đổi node trong measurement window
- Karpenter: 0/0 trong toàn bộ measurement window
- Running pods: 52 lúc bắt đầu, 53 lúc kết thúc; ngoài ra có 2 inventory Job Completed
- Pod restarts during measurement: 0; restart duy nhất trong snapshot là Metrics Server từ 17 giờ trước, không thuộc run này
- Application scaling: Cart tăng từ 2 lên 3 replicas. Checkout và Frontend cùng yêu cầu 4 replicas nhưng chỉ có 3 Ready, mỗi workload có 1 pod Pending trong suốt measurement window.
- Pending reason: hai node On-Demand không khớp `nodeSelector workload-class=spot-tolerant`; các Spot node còn lại bị giới hạn bởi topology spread/anti-affinity, trong khi Karpenter được cố định 0/0 nên không thể bổ sung node.
- Latency conclusion: Browse, Cart và Checkout đều đạt p95/p99 budget; chưa có latency breakpoint.
- Capacity conclusion: đã xuất hiện scheduling capacity warning tại 300 users. Kết quả 400 users phải được theo dõi kỹ; nếu Pending làm tăng latency/failure hoặc HPA không thể đáp ứng tải thì dừng chuỗi test và chuyển sang MANDATE-16.2.

Giá trị p95/p99 chính thức ở trên là `Max` của rolling percentile trên Grafana trong đúng absolute measurement window. Request count, failure count và Average RPS lấy từ `locust_stats.csv`; Browse là tổng của 10 endpoint `GET /api/products/{productId}`.

### Run 400-01 - Passed latency budget while pod scheduling was constrained

- Evidence: `docs/evidence/mandate-16/tail-latency/400-users-run-01-fixed-6-nodes`
- Measurement started: `2026-07-20T23:23:38+07:00`
- Measurement ended: `2026-07-20T23:50:38+07:00`
- Duration: 27 phút; nằm trong khoảng 15-30 phút của MANDATE-16.1
- Load: 400 users, 3 fixed workers
- Average RPS: 84.35
- Total requests: 136,844
- HTTP failures: 0
- Nodes: 6/6 Ready; không thay đổi node trong measurement window
- Karpenter: 0/0 trong toàn bộ measurement window
- Running pods: 53/53; 5 pod Pending và 2 inventory Job Completed tại cả đầu và cuối run
- Pod restarts during measurement: 0; Metrics Server có một restart từ 18 giờ trước, không thuộc run này
- Pending pods: 1 Cart, 2 Checkout và 2 Frontend. HPA yêu cầu lần lượt 4, 5 và 5 replicas nhưng chỉ schedule được 3 replicas cho mỗi workload.
- Pending reason: 2 node không khớp node selector, 3 node không thỏa topology spread constraints và 1 node vi phạm pod anti-affinity. Karpenter bị cố định 0/0 nên không bổ sung capacity.
- HPA pressure at end: Checkout 106%/70%, Frontend 77%/65% và Cart 67%/70%. Checkout và Frontend vẫn cần scale-out nhưng replica mới không thể schedule.
- Latency conclusion: Browse, Cart và Checkout đều đạt p95/p99 budget; chưa có latency breakpoint tại 400 users.
- Capacity conclusion: fixed six-node cluster đã bị scheduling constrained rõ ràng. Mức 500 users có thể được chạy để tìm latency breakpoint, nhưng phải dừng ngay khi p95/p99/failure vi phạm hoặc workload đang Running bị OOM/CrashLoopBackOff.

Grafana resource evidence ghi nhận các workload memory lớn gồm Product Reviews 3.38 GiB, Prometheus p99 1.79 GiB, Shopping Copilot 1.72 GiB, OpenSearch 872 MiB và OTel Collector p99 631 MiB. Không có container restart mới trong measurement window.

### Run 500-01 - Passed latency budget under severe scheduling constraint

- Evidence: `docs/evidence/mandate-16/tail-latency/500-users-run-01-fixed-6-nodes`
- Measurement started: `2026-07-21T00:18:49+07:00`
- Measurement ended: `2026-07-21T00:47:12+07:00`
- Duration: 28 phút 23 giây; nằm trong khoảng 15-30 phút của MANDATE-16.1
- Load: 500 users, 3 fixed workers
- Average RPS: 104.66; tăng 24.1% so với 84.35 RPS tại 400 users, gần tuyến tính với mức tăng users 25%
- Total requests: 178,527
- HTTP failures: 0
- Nodes: 6/6 Ready; không thay đổi node trong measurement window
- Karpenter: 0/0 trong toàn bộ measurement window
- Running pods: 54/54; 8 pod Pending và 2 inventory Job Completed tại cả đầu và cuối run
- Pod restarts during measurement: 0; Metrics Server có một restart từ 19 giờ trước, không thuộc run này
- Pending pods: 2 Cart, 3 Checkout và 3 Frontend. HPA yêu cầu lần lượt 5, 6 và 6 replicas nhưng chỉ schedule được 3 replicas cho mỗi workload.
- Pending reason: node selector, topology spread constraints và pod anti-affinity loại toàn bộ 6 node khỏi tập ứng viên; Karpenter bị cố định 0/0 nên không bổ sung capacity.
- HPA pressure at end: Checkout 133%/70%, Frontend 97%/65% và Cart 80%/70%. Cả ba workload đều cần scale-out nhưng replica mới không thể schedule.
- Latency conclusion: Browse, Cart và Checkout đều đạt p95/p99 budget; chưa có latency breakpoint tại 500 users.
- Throughput conclusion: throughput vẫn tăng gần tuyến tính, nên chưa có bằng chứng bão hòa tại 500 users.
- Capacity conclusion: fixed six-node cluster đã scheduling constrained nghiêm trọng. Có thể tiếp tục mức 600 users để tìm breakpoint, nhưng phải dừng ngay khi SLO/failure vi phạm hoặc workload đang Running bị OOM/CrashLoopBackOff.
- Evidence caveat: các ảnh Locust được chụp khi `STOPPING` nên không hiển thị trực tiếp 500 users. CSV, 3 workers và throughput xác nhận run, nhưng run 600 phải chụp thêm ảnh khi `RUNNING` hiển thị rõ users/workers.

Grafana resource evidence ghi nhận Product Reviews 3.38 GiB, Shopping Copilot 1.72 GiB, Prometheus p99 1.73 GiB, OpenSearch 890 MiB, OTel Collector p99 622 MiB và Frontend p99 345 MiB. Không có container restart mới trong measurement window.

### Run 600-01 - Passed latency budget with one transient Browse failure

- Evidence: `docs/evidence/mandate-16/tail-latency/600-users-run-01-fixed-6-nodes`
- Measurement started: `2026-07-21T01:06:50+07:00`
- Measurement ended: `2026-07-21T01:34:54+07:00`
- Duration: 28 phút 04 giây; nằm trong khoảng 15-30 phút của MANDATE-16.1
- Load: 600 users, 3 fixed workers; `00-locust-running-600-users.png` xác nhận trực tiếp trên UI
- Average RPS: 125.56; tăng 20.0% so với 104.66 RPS tại 500 users, khớp với mức tăng users 20%
- Total requests: 210,690
- HTTP failures: 1 Browse request `GET /api/products/1YMWWN1N4O` trả về HTTP 503 tại `2026-07-21 01:15:25`; failure rate khoảng 0.00047%
- Nodes: 6/6 Ready; không thay đổi node trong measurement window
- Karpenter: 0/0 trong toàn bộ measurement window
- Running pods: 54/54; Pending tăng từ 10 lên 11 pod; ngoài ra có 2 inventory Job Completed
- Pod restarts during measurement: 0; Metrics Server có một restart từ 19-20 giờ trước, không thuộc run này
- Pending at start: 2 Cart, 3 Checkout và 5 Frontend. Cuối run Cart tăng thêm 1 replica Pending, thành 3 Cart, 3 Checkout và 5 Frontend Pending.
- Scheduling reason: node selector, topology spread constraints và pod anti-affinity loại toàn bộ 6 node khỏi tập ứng viên; Karpenter bị cố định 0/0 nên không bổ sung capacity.
- HPA pressure near measurement start: Cart 108%/70%, Checkout 140%/70% và Frontend 93%/65%. HPA yêu cầu 5 Cart, 6 Checkout và 8 Frontend replicas nhưng chỉ schedule được 3 cho mỗi workload.
- Latency conclusion: Browse, Cart và Checkout đều đạt p95/p99 budget; chưa có latency breakpoint tại 600 users.
- Failure conclusion: một HTTP 503 đơn lẻ không lặp lại và không làm suy giảm percentile/throughput, nên được ghi nhận là transient failure chứ chưa xác nhận breakpoint.
- Throughput conclusion: throughput vẫn tăng tuyến tính, nên chưa có bằng chứng bão hòa tại 600 users.
- Capacity conclusion: fixed six-node cluster không còn khả năng schedule replica scale-out. Có thể tiếp tục mức 700 users để tìm breakpoint, nhưng phải dừng khi SLO/failure vi phạm lặp lại hoặc workload đang Running bị OOM/CrashLoopBackOff.

Grafana resource evidence ghi nhận Product Reviews p99 3.49 GiB, Prometheus p99 1.80 GiB, Shopping Copilot 1.72 GiB, OpenSearch 904 MiB, OTel Collector p99 624 MiB và Frontend p99 343 MiB. Không có container restart mới trong measurement window.

### Run 700-01 - Passed latency budget while fixed capacity was exhausted

- Evidence: `docs/evidence/mandate-16/tail-latency/700-users-run-01-fixed-6-nodes`
- Measurement started: `2026-07-21T01:50:08+07:00`
- Measurement ended: `2026-07-21T02:21:28+07:00`
- Captured duration: 31 phút 20 giây. Run vượt giới hạn 30 phút của MANDATE-16.1 khoảng 1 phút 20 giây do thời gian thao tác dừng/chụp cuối run; kết quả được giữ làm evidence nhưng mang measurement-window caveat.
- Load: 700 users, 3 fixed workers. `02-locust-charts.png` xác nhận đường Number of Users giữ ở 700 gần như toàn bộ measurement window; ảnh Statistics/Failures được chụp ngay sau khi bấm Stop nên hiển thị `STOPPING`.
- Average RPS: 142.49; tăng 13.5% so với 125.56 RPS tại 600 users, thấp hơn mức tăng users 16.7%. Scaling efficiency theo throughput khoảng 81%, là dấu hiệu sớm cần theo dõi nhưng chưa đủ xác nhận saturation.
- Total requests: 276,896
- HTTP failures: 2 Browse requests trả HTTP 503: `GET /api/products/L9ECAV7KIM` lúc `02:06:32` và `GET /api/products/LS4PSXUNUM` lúc `02:12:54`; failure rate khoảng 0.00072%. Cart và Checkout không có failure.
- Nodes: 6/6 Ready; không thay đổi node trong measurement window
- Karpenter: 0/0 trong toàn bộ measurement window
- Pod inventory: 54 Running + 12 Pending lúc bắt đầu; 55 Running + 12 Pending lúc kết thúc; ngoài ra có 2 inventory Job Completed.
- Pod restarts during measurement: 0; Metrics Server có một restart từ 20-21 giờ trước, không thuộc run này.
- Pending pods tại cả đầu và cuối run: 2 Cart, 4 Checkout và 6 Frontend. Các replica HPA yêu cầu thêm không thể schedule trên fixed six-node capacity.
- HPA pressure: Cart khoảng 104-107%/70%, Checkout 130-153%/70% và Frontend 96-98%/65%. HPA giữ desired replicas lần lượt 5, 7 và 9 nhưng chỉ có 3 replica Running cho mỗi workload.
- Node pressure: cuối measurement có ba node ở khoảng 94%, 95% và 100% memory. Đây là capacity exhaustion rõ ràng dù CPU toàn node vẫn chủ yếu dưới 30%, ngoại trừ spike cục bộ.
- Latency conclusion: Browse, Cart và Checkout đều đạt p95/p99 budget; chưa có latency breakpoint tại 700 users.
- Failure conclusion: hai HTTP 503 xảy ra ở hai Browse product endpoint khác nhau, không lặp lại trên cùng endpoint và failure rate vẫn gần 0%; ghi nhận là transient failures, chưa đủ xác nhận breakpoint.
- Throughput conclusion: RPS vẫn tăng nhưng không còn hoàn toàn tuyến tính. Mức 800 users cần kiểm tra xem RPS có tiếp tục tăng tương ứng hay latency/failure bắt đầu xấu đi.
- Capacity conclusion: cluster đã hết khả năng schedule replica scale-out. Chỉ tiếp tục 800 users nếu mục tiêu là tìm breakpoint trên fixed capacity và phải dừng ngay khi failure lặp lại, p95/p99 vượt budget, hoặc workload Running bị OOM/CrashLoopBackOff.

Grafana resource evidence ghi nhận Product Reviews p99 3.47 GiB, Prometheus p99 1.79 GiB, Shopping Copilot 1.72 GiB, OpenSearch 916 MiB, OTel Collector p99 652 MiB và Frontend p99 349 MiB. Không có container restart mới trong measurement window.

### Run 800-01 - Passed latency budget while HPA scale-out remained unschedulable

- Evidence: `docs/evidence/mandate-16/tail-latency/800-users-run-01-fixed-6-nodes`
- Measurement started: `2026-07-21T02:40:42+07:00`
- Measurement ended: `2026-07-21T03:09:01+07:00`
- Duration: 28 phút 19 giây; nằm trong khoảng 15-30 phút của MANDATE-16.1
- Load: 800 users, 3 fixed workers. `02-locust-charts.png` xác nhận Number of Users giữ ở 800 trong measurement window.
- Average RPS: 167.49; tăng 17.5% so với 142.49 RPS tại 700 users, cao hơn mức tăng users 14.3%. Chưa có bằng chứng throughput saturation tại 800 users.
- Total requests: 285,279
- HTTP failures: 1 request `GET /api/recommendations?productIds=LS4PSXUNUM` trả HTTP 503 lúc `02:45:24`; failure rate khoảng 0.00035%. Browse, Cart và Checkout không có failure.
- Nodes: 6/6 Ready; không thay đổi node trong measurement window
- Karpenter: 0/0 trong toàn bộ measurement window
- Pod inventory: 56 Running + 14 Pending lúc bắt đầu; 56 Running + 15 Pending lúc kết thúc; ngoài ra có 2 inventory Job Completed.
- Pod restarts during measurement: 0. Một Load Generator Worker restart khoảng 18 phút trước thời điểm bắt đầu measurement và Metrics Server restart khoảng 21 giờ trước, không thuộc run này.
- Pending at start: 3 Cart, 5 Checkout và 6 Frontend. Cuối run Frontend tăng thêm 1 replica Pending, thành 3 Cart, 5 Checkout và 7 Frontend Pending.
- HPA pressure: Cart khoảng 100-105%/70%, Checkout 173-176%/70% và Frontend 120-127%/65%. HPA yêu cầu lần lượt 6 Cart, 8 Checkout và 9-10 Frontend replicas nhưng chỉ có 3 replica Running cho mỗi workload.
- Node pressure: ba node duy trì khoảng 94%, 95% và 99-100% memory trong khi CPU còn thấp hơn nhiều. Fixed capacity đã cạn memory/scheduling headroom.
- Latency conclusion: Browse, Cart và Checkout đều đạt p95/p99 budget; chưa có latency breakpoint tại 800 users.
- Failure conclusion: lỗi 503 duy nhất nằm ở Recommendation, không thuộc ba critical-flow endpoint được chấm budget và không lặp lại; ghi nhận là transient supporting-service failure.
- Throughput conclusion: RPS vẫn tăng tương ứng với tải, nên chưa có bằng chứng bão hòa tại 800 users.
- Capacity conclusion: HPA đã phản ứng nhưng cluster không thể schedule thêm replica. Có thể chạy 900 users để tìm breakpoint trên fixed capacity, nhưng phải dừng ngay nếu core-flow failure xuất hiện lặp lại, p95/p99 vượt budget hoặc workload Running bị OOM/CrashLoopBackOff.

Grafana resource evidence ghi nhận Product Reviews p99 3.47 GiB, Prometheus p99 1.90 GiB, Shopping Copilot 1.72 GiB, OpenSearch 932 MiB, OTel Collector p99 658 MiB và Frontend p99 349 MiB. Không có container restart mới trong measurement window.

### Run 1000-01 - Passed critical-flow tail-latency budget

- Evidence: `docs/evidence/mandate-16/tail-latency/1000-users-run-01-fixed-6-nodes`
- Measurement started: `2026-07-21T08:00:47+07:00`
- Active measurement completed at approximately `08:29:28` according to the final monitor sample, giving approximately 28 phút 41 giây of active measurement.
- `end-time.txt` and `cluster-end.txt` were captured manually at `08:31:39`, about two minutes after Locust was stopped because the original script did not save them automatically. The resulting absolute evidence window is 30 phút 52 giây; this post-stop capture delay is an evidence caveat.
- Load: 1000 users, 3 fixed workers. `02-locust-charts.png` confirms Number of Users remained at 1000 throughout the active measurement.
- Average RPS: 209.74; tăng 25.2% so với 167.49 RPS tại 800 users, gần như khớp với mức tăng users 25%. Application throughput chưa bão hòa rõ rệt.
- Total requests: 401,994
- Total HTTP failures: 163; failure rate khoảng 0.0405%.
- Reliability observation ngoài phạm vi tail-latency budget: 159 HTTP 500 responses trên bảy biến thể `GET /api/data` trong khoảng `08:26:24-08:27:50`. `/api/data` không thuộc ba API critical-flow được chấm trong MANDATE-16.1, nên lỗi này không được dùng để tuyên bố latency breakpoint; cần tạo reliability backlog riêng.
- Additional failures: 1 `GET /api/cart` HTTP 503, 1 `POST /api/checkout` HTTP 503, 1 Browse product HTTP 503 và 1 Recommendation HTTP 503.
- Nodes: 6/6 Ready; không thay đổi node trong measurement window
- Karpenter: 0/0 trong toàn bộ measurement window
- Pod inventory: 57 Running + 22 Pending lúc bắt đầu; 58 Running + 22 Pending lúc capture cuối; ngoài ra có 2 inventory Job Completed.
- Pod restarts during measurement: 0. Hai Load Generator Worker và Metrics Server có restart từ nhiều giờ trước, không thuộc run này.
- Pending pods tại cả đầu và cuối: 5 Cart, 7 Checkout và 10 Frontend. HPA scale-out tiếp tục không thể schedule trên fixed six-node capacity.
- HPA pressure: Cart khoảng 143-148%/70%, Checkout 223-233%/70% và Frontend 154-156%/65%. Load Generator Worker ở khoảng 88-92%/70% và đã chạm giới hạn cố định 3 replicas, nhưng RPS vẫn tăng tương ứng nên chưa xác nhận load-generator saturation.
- Node pressure: ba node ở khoảng 94%, 96% và 101-103% allocatable memory; CPU node cao nhất khoảng 53% lúc đầu và 47% lúc cuối.
- Latency conclusion: cả ba critical flow vẫn đạt budget. Grafana rolling-percentile Max lần lượt là Browse 45.4/89.5 ms, Cart 49.2/111 ms và Checkout 226/382 ms cho p95/p99.
- Breakpoint conclusion: chưa có latency breakpoint tại 1000 users vì p95/p99 của Browse, Cart và Checkout đều còn thấp hơn budget. Một Checkout HTTP 503 đơn lẻ được ghi nhận nhưng chưa đủ chứng minh điểm nghẽn latency lặp lại.
- Next step: tiếp tục mức tải cao hơn trên cùng fixed capacity. Khi p95/p99 critical flow vượt budget hoặc tăng/jitter bền vững, dùng chính mức tải đó làm đầu vào cho MANDATE-16.2.

Grafana resource evidence ghi nhận Product Reviews p99 1.79 GiB, Prometheus p99 1.38 GiB, Shopping Copilot 1.72 GiB, OpenSearch 939 MiB, OTel Collector p99 133 MiB và Frontend p99 128 MiB. Không có container restart mới trong measurement window.

### Run 1200-01 - Invalid due to concurrent image publication

- Evidence: `docs/evidence/mandate-16/tail-latency/1200-users-run-01-fixed-6-nodes`
- Measurement started: `2026-07-21T09:14:29+07:00`
- Measurement ended: `2026-07-21T09:37:13+07:00`
- Duration: 22 phút 44 giây
- Load: 1200 users, 3 fixed workers; average throughput 240.50 RPS
- Total requests: 339,100; HTTP failures: 10 (khoảng 0.00295%)
- Nodes: 6/6 Ready; Karpenter giữ ở 0/0
- Pod inventory: 59 Running + 28 Pending lúc bắt đầu; 59 Running + 30 Pending + 1 ImagePullBackOff lúc kết thúc
- Trong khoảng 2 phút cuối measurement, HPA tạo thêm pod `product-reviews-7cd8dcb9cd-n5mpd` từ cùng ReplicaSet hiện hữu. Pod mới không pull được image `product-reviews:sha-aabb8be` và rơi vào `ImagePullBackOff` đúng lúc có hoạt động push image bên ngoài bài test.
- Việc publish image đồng thời làm replica scale-out không thể khởi động, khiến điều kiện hệ thống thay đổi ngoài kế hoạch trong measurement window. Vì vậy toàn bộ run được đánh dấu **Invalid/Contaminated**, dù Grafana ghi nhận Browse 97.2/186 ms, Cart 195/365 ms và Checkout 392/707 ms cho p95/p99, đều còn dưới budget.
- Không dùng số liệu run này để tuyên bố pass, fail hoặc latency breakpoint. Giữ evidence để giải trình và chạy lại ở thư mục `1200-users-run-02-fixed-6-nodes` sau khi image/rollout ổn định.

## Quy tắc xác định latency breakpoint

Một mức tải được xem là breakpoint khi xảy ra ít nhất một trong các điều kiện sau trong measurement window:

- p95 hoặc p99 vượt budget liên tục, không chỉ là một điểm spike đơn lẻ.
- HTTP failure lặp lại trên chính Browse, Cart hoặc Checkout được ghi nhận như dấu hiệu critical flow không còn phục vụ ổn định; lỗi của API ngoài phạm vi không tự xác nhận latency breakpoint cho MANDATE-16.
- Pod OOMKilled/CrashLoopBackOff lặp lại, hoặc pod Pending do hết capacity kèm theo latency/failure xấu đi hay HPA không còn đáp ứng được tải. Pending đơn lẻ mà SLO vẫn đạt được ghi là capacity warning, chưa tự nó xác nhận latency breakpoint.
- Latency tiếp tục tăng trong khi RPS không tăng tương ứng.
- HPA chạm maxReplicas hoặc cluster hết CPU/RAM có thể cấp phát.

Khi p95/p99 critical flow gặp breakpoint: dừng tăng tải, giữ lại evidence, ghi timestamp và chuyển sang MANDATE-16.2 để phân tích các trace chậm bằng Jaeger. Lỗi ngoài critical flow được tách thành reliability backlog riêng.

## Evidence bắt buộc cho mỗi run

Mỗi thư mục `<users>-users-run-01-fixed-6-nodes` phải có:

1. `start-time.txt`
2. `end-time.txt`
3. `01-locust-statistics.png`
4. `02-locust-charts.png`
5. `03-locust-failures.png`
6. `04-grafana-tail-latency.png`: một ảnh tổng hợp đủ Browse, Cart và Checkout p95/p99 cùng threshold line.
7. `05-grafana-resources.png`: bảng CPU và RAM trong measurement window.
8. `locust_stats.csv`
9. `cluster-start.txt`: gom trạng thái Karpenter, số node/pod, HPA, CPU/RAM và events lúc bắt đầu.
10. `cluster-end.txt`: gom cùng các dữ liệu trên lúc kết thúc.

Các ảnh Grafana phải dùng đúng absolute measurement window trong `start-time.txt` và `end-time.txt`. Tên, UID, URL và source JSON của dashboard đã được ghi trong phần Dashboard của tài liệu này.

## Approval

- Proposed by: Le Nguyen Nhat Thanh
- Reviewed by: TODO
- Status: Proposed
- Approval date: TODO
