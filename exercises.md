# Phiếu Phản Ánh — K3 Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder của mỗi câu bằng câu trả lời của bạn.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Nguyễn Đình Bình  Mã học viên: 2A202601091

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> Khi tôi deploy lên Render, tôi quên chưa đặt biến `AGENT_API_KEY` trong
> dashboard của service. Nếu `agent_api_key` có mặc định `"changeme"`, app vẫn
> khởi động "thành công", Render báo Live, và tôi tưởng mọi thứ ổn. Nhưng mọi
> request `/ask` đều trả 401 vì so sánh key với `"changeme"` không khớp — người
> dùng thấy API hỏng mà tôi không hề biết. Với cách fail-fast, app từ chối
> khởi động và Render báo lỗi ngay lập tức, ép tôi đặt đúng key trước khi ai đó
> gọi. "Chết sớm" biến một lỗi cấu hình bị giấu kín thành một lỗi to rõ ràng
> ngay từ đầu.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Khi gọi `/ask`, tôi thu được log (đã cắt bớt phần answer):
> `{"event":"ask_completed","level":"info","timestamp":"2026-08-10T09:40:12Z","user_id":"sv-test","tokens_in":12,"tokens_out":18,"cost_usd":2.3e-05}`
>
> Hai việc làm được mà `print("đã trả lời xong")` không làm được:
> (1) **Máy có thể truy vấn/parse tự động**: mỗi trường nằm trong key riêng của
> JSON nên Elasticsearch, Loki hoặc một script có thể lọc theo `user_id` hay
> `cost_usd`. Với chuỗi text thường, không có cách nào tách trường ra một cách
> đáng tin cậy.
> (2) **Có timestamp chuẩn và đo lường kinh doanh**: tôi biết chính xác lúc nào
> request xong, tốn bao nhiêu token và tiền. `print` thường thì không ghi thời
> gian và không có con số chi phí để giám sát.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ~900 MB |
| Multi-stage | ~180 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Bản 1 stage giữ nguyên toàn bộ tầng build: trình biên dịch, header của các
> package C, file cache của pip, và cả source code thừa. Bản multi-stage dùng
> stage `builder` chỉ để cài dependency vào một thư mục riêng (`--prefix=/install`),
> rồi stage runtime chỉ `COPY --from=builder` đúng thư mục đó cùng code `app/`
> và `utils/`. Mọi thứ không cần khi chạy — công cụ build, cache — đều bị loại
> bỏ, nên image nhỏ đi rất nhiều. Đó chính là phần chênh lệch giữa hai bản.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Với Dockerfile của tôi, thứ tự là `COPY requirements.txt` → `RUN pip install`
> → mới `COPY app/` `COPY utils/`. Khi sửa một ký tự trong `app/main.py`, Docker
> so hash từng layer: các layer trước `COPY app/` (như `requirements.txt` và
> `pip install`) **không đổi** nên dùng lại từ cache, chỉ layer `COPY app/` và
> những layer sau phải chạy lại. Nếu đặt `COPY . .` lên trước `RUN pip install`
> thì bất kỳ file nào thay đổi (kể cả một comment trong code) đều làm hash của
> `COPY . .` đổi, khiến Docker **hủy cache toàn bộ** cả `RUN pip install` — mỗi
> lần sửa code lại cài lại từ đầu hàng trăm package, rất chậm. Đó là vì Docker
> cache theo thứ tự layer: một layer đổi sẽ làm mọi layer sau nó chạy lại.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> Chuỗi sự kiện: (1) code Python của tôi có một lỗ hổng, ví dụ đọc file theo
> đường dẫn do người dùng gửi lên (path traversal) hoặc chạy lệnh không an toàn.
> (2) Kẻ tấn công khai thác lỗ này và thực thi lệnh **bên trong container**.
> (3) Vì process chạy bằng UID 0 (root), lệnh đó chạy với quyền root — nó xóa
> file, đọc secret, hoặc đặt thêm payload. (4) Nếu container được mount volume
> hay có capability broad, root trong container có thể đào thoát (escape) hoặc
> chạm vào tài nguyên của host. Lệnh `USER appuser` cắt chuỗi ở bước (3): dù kẻ
> tấn công vẫn chạy được lệnh, process chỉ có quyền của `appuser` (không có
> quyền ghi vào file hệ thống, không phải root), nên thiệt hại bị giới hạn trong
> phạm vi app — không leo thang lên root để tiếp cận host.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> Với phút cố định reset lúc giây 00, người dùng có thể gửi tối đa **20 request**
> trong 2 giây liên tiếp. Cách đạt được: chọn 2 giây rơi vào cuối một phút (ví dụ
> 59:59–60:01). Ở giây cuối của phút A, quota của phút A gần như đã hết dùng
> nhưng vẫn còn vài slot; đồng thời người bắn nhanh hết quota phút A rồi đúng
> mốc 00:00 phút B reset, quota phút B lại đầy 10. Nếu bỏ đi giới hạn nhỏ vụn
> của A, gần như tối đa là 10 (phút A) + 10 (phút B) = 20 request trong 2 giây.
> Cửa sổ trượt khắc phục điều này: nó xét 60 giây liên tục trước thời điểm hiện
> tại, nên không có "khe nứt" giữa hai phút để lách qua.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> Rate limit giới hạn **số lượng request** trong một khoảng thời gian ngắn (bảo
> vệ hệ thống khỏi bị quá tải/abuse), còn cost guard giới hạn **tổng chi phí tích
> lũy** trong một tháng (bảo vệ ngân sách tiền). Một tình huống rate limit cho
> qua nhưng cost guard chặn: người dùng gửi các request thưa (dưới hạn 10/phút)
> nhưng mỗi request có câu hỏi rất dài, tốn nhiều token LLM — số request ít nên
> rate limit không bắt, nhưng tiền cộng dồn vượt ngân sách tháng nên cost guard
> trả 402. Tình huống ngược lại: người dùng bắn 50 request trong vài giây, mỗi
> request rẻ (câu hỏi ngắn) nên tổng tiền chưa vượt ngân sách — cost guard cho
> qua, nhưng rate limit chặn ở request thứ 11 bằng 429 vì quá nhanh.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> Thứ tự sự kiện: (1) Redis mất kết nối. (2) Endpoint gộp gọi `store.ping()`
> trả False nên trả 503. (3) Load balancer / orchestrator coi tất cả 3 container
> là "không khỏe" và **rút hết** chúng khỏi vòng xoay. (4) Không còn container
> nào nhận request → toàn bộ cụm sập, downtime kéo dài suốt 30 giây dù Redis chỉ
> ngắt có 30 giây. Với /health tách riêng (không gọi Redis), nó vẫn trả 200 vì
> process sống, chỉ /ready trả 503 — container bị rút khỏi traffic **nhưng** vẫn
> được coi là "đang chạy", không bị restart liên tục; khi Redis về, /ready thành
> 200 và container được nhận traffic lại ngay. Tách hai endpoint tránh việc một
> lỗi phụ thuộc (Redis) làm rate-limit restart cụm.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Khi chạy thật với `--scale agent=3`, tôi gọi `/ask` 5 lần cùng `X-User-Id` và
> thấy `history_length` tăng đều 0, 2, 4, 6, 8 — mỗi lần gọi ghi thêm 2 tin
> (user + assistant) và các container chia nhau nhận request (nginx round-robin)
> nhưng vì state nằm ở Redis dùng chung nên lịch sử vẫn cộng dồn đúng. Nếu lưu
> trong dict Python (mỗi container một bản memory riêng), thì mỗi container chỉ
> thấy lịch sử của chính nó: request 1 vào container A ghi dict A, request 2 vào
> container B không thấy gì nên `history_length` lại về 0, rồi A, rồi 0... Con số
> sẽ nhảy lung tung và không phản ánh đúng hội thoại — chứng tỏ trạng thái phải
> nằm ngoài process (Redis) để scale ngang được.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> Lỗi tôi gặp: sau khi deploy lên Render, ban đầu mọi endpoint đều trả 404
> (không tìm thấy route). Thông báo tôi thấy là `404 Not Found` khi gọi
> `/health`, kèm header `x-render-routing: no-server`. Tôi tìm nguyên nhân bằng
> cách kiểm tra code local (chạy Docker image tương tự) thấy `/health` trả 200
> bình thường, đối chiếu `render.yaml` thấy đúng, rồi nhận ra dấu hiệu
> `x-render-routing: no-server` nghĩa là instance của Render free tier đã ngủ
> (spin down) sau một thời gian không có traffic — nó đang khởi động lại nên
> chưa nhận request. Cách sửa: chỉ cần gọi lại và chờ vài chục giây cho instance
> cold start xong, sau đó `/health` trả 200 và `/ready` trả `redis: true`. Cũng
> đảm bảo app đọc cổng `$PORT` do platform gán để lệnh khởi động đúng.

---