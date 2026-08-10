# ✅ Checklist — K3 Day 12: Hạ Tầng Cloud & Deployment

> Thứ tự làm: **tuần tự CP0 → CP1 → CP2 → CP3 → CP4 → CP5 → Bonus**.
> Mỗi checkpoint xong thì `git add` + `git commit` ngay (điều kiện nộp bài: nhiều commit, không phải 1 commit duy nhất).
> Mục tiêu cuối: `python grade.py` ≥ 75/100.

---

## CP0 — Setup môi trường (chưa có điểm, nhưng bắt buộc)

- [X]  Kiểm tra Python ≥ 3.11: `python --version`
- [X]  Cài venv + thư viện:
  - PowerShell: `python -m venv .venv` → `.venv\Scripts\Activate.ps1` → `pip install -r requirements.txt`
- [X]  Tạo `.env` từ `.env.example` (`copy .env.example .env`)
- [X]  Sinh khóa API riêng: `python -c "import secrets; print(secrets.token_urlsafe(32))"` → dán vào `AGENT_API_KEY` trong `.env`
- [X]  Khởi động Redis: `docker compose up -d redis` (chưa có Docker → đặt `REDIS_URL=fake://`)
- [X]  Chạy thử bộ test (chỉ CP1–CP4, bỏ docker):
  `pytest tests/test_cp1.py tests/test_cp2.py tests/test_cp3.py tests/test_cp4.py -v -m "not docker"`
  - Kết quả đúng: các test **FAILED** do TODO chưa làm, nhưng **KHÔNG** được có `ModuleNotFoundError` / `ImportError`.
- [X]  Xác nhận `.env` không bị track: `git ls-files | grep .env` chỉ thấy `.env.example`
- [X]  **Commit:** `"CP0: setup môi trường"`

---

## CP1 — 12-Factor Config, Health & Logging (15 điểm)

### `app/config.py`

- [X]  Khai báo 6 trường trong class `Settings`:
  - `port: int = 8000`
  - `agent_api_key: str` (KHÔNG có mặc định → fail-fast)
  - `redis_url: str = "redis://localhost:6379/0"`
  - `rate_limit_per_minute: int = 10`
  - `monthly_budget_usd: float = 10.0`
  - `log_level: str = "INFO"`

### `app/logging_utils.py`

- [X]  `log_event(event, level="info", **fields)`:
  - Tạo dict: `{"event": event, "level": level.lower(), "timestamp": utc_now_iso()}` + gộp `**fields`
  - `print(json.dumps(..., ensure_ascii=False))` — **một dòng duy nhất**, không dùng `indent`
  - `return` chính chuỗi JSON đó

### `app/main.py` — endpoint `/health`

- [X]  Blog `health()`:
  - Nếu `lifecycle.shutting_down` → `return JSONResponse(status_code=503, content={"status": "shutting_down"})`
  - Ngược lại → `return {"status": "ok", "service": SERVICE_NAME, "version": SERVICE_VERSION}`
  - ⚠️ **KHÔNG nhận dependency nào** (test CP1 kiểm tra signature) — không gọi Redis

### Kiểm tra

- [X]  `pytest tests/test_cp1.py -v` → xanh hết
- [ ]  Test thủ công: `uvicorn app.main:app --reload --port 8000` → `curl -H "X-API-Key: $AGENT_API_KEY" localhost:8000/health` → 200
- [X]  **Commit:** `"CP1: 12-Factor config, logging JSON, /health"`

---

## CP2 — Docker: multi-stage, bảo mật image (15 điểm)

### `Dockerfile` (viết lại thành multi-stage)

- [X]  Stage 1 `builder`: `FROM python:3.11-slim AS builder`, `WORKDIR /build`, `COPY requirements.txt .`, `RUN pip install --no-cache-dir --prefix=/install -r requirements.txt`
- [X]  Stage 2 runtime: `FROM python:3.11-slim`, `WORKDIR /app`, `COPY --from=builder /install /usr/local`, `COPY app/ app/`, `COPY utils/ utils/`
- [ ]  `RUN adduser --disabled-password --no-create-home appuser` + `USER appuser`
- [ ]  `EXPOSE 8000`
- [ ]  `HEALTHCHECK` gọi `/health` bằng Python (image slim không có curl, đọc `$PORT`):
  `CMD python -c "import os, urllib.request; port = os.getenv('PORT', '8000'); urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=3)"`
- [ ]  `CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]` (đọc `$PORT` cho cloud)
- [ ]  ⚠️ Thứ tự: `COPY requirements.txt` → `pip install` → mới `COPY app/` (dùng cache)
- [ ]  Build thử: `docker build -t day12-agent:prod .` → `docker images day12-agent:prod` → **≤ 500MB** (stretch: < 200MB)

### `.dockerignore`

- [X]  Bổ sung đủ: `.env`, `.venv/`, `__pycache__/`, `*.pyc`, `.git/`, `screenshots/`
  - ⚠️ **KHÔNG** được ignore `app`, `requirements.txt`, `utils`

### `docker-compose.yml`

- [X]  Thêm service `agent`:
  - `build: .`
  - `ports: "8000:8000"`
  - `environment: AGENT_API_KEY: ${AGENT_API_KEY:?...}`, `REDIS_URL: redis://redis:6379/0`
  - `depends_on: redis` (condition service_healthy)
  - `healthcheck` gọi `/health` (giống Dockerfile)
- [X]  (Điểm cộng) Thêm service `nginx`: `image: nginx:1.27-alpine`, `ports: "8000:80"`, mount `./nginx/nginx.conf`, `depends_on: agent`. Khi đó agent **bỏ** `ports` public, chỉ `expose: "8000"`.

### Kiểm tra

- [X]  `pytest tests/test_cp2.py -v` → các test static xanh; test build (mark `docker`) bỏ qua nếu chưa bật Docker
- [X]  **Commit:** `"CP2: Dockerfile multi-stage + compose + dockerignore"`

---

## CP3 — API Security: auth, rate limit, cost guard (20 điểm)

### `app/auth.py` — `verify_api_key`

- [X]  Lấy `settings.agent_api_key`
- [X]  `x_api_key` None hoặc sai → `HTTPException(401, detail="invalid or missing API key")`
- [X]  So sánh bằng `secrets.compare_digest(x_api_key, settings.agent_api_key)` — KHÔNG dùng `==`
- [X]  Hợp lệ → trả về `x_user_id` nếu có, ngược lại `ANONYMOUS_USER`

### `app/rate_limiter.py`

- [X]  `hit_count(user_id, now)`: `zremrangebyscore(key, 0, now - WINDOW_SECONDS)` → `zcard(key)`
- [X]  `check(user_id, now)` — **đúng thứ tự**:
  1. `count = hit_count(...)`
  2. `count >= self.limit` → `HTTPException(429, detail="rate limit exceeded", headers={"Retry-After": str(WINDOW_SECONDS)})` (KHÔNG ghi nhận)
  3. Còn quota → `zadd(key, {f"{now}:{uuid.uuid4().hex}": now})`
  4. `expire(key, WINDOW_SECONDS)`

### `app/cost_guard.py`

- [X]  `spent(user_id, month)`: `get(key)` → Redis None → `0.0`; else `float(...)`
- [X]  `check(user_id, estimated_cost, month)`: `spent + estimated_cost > budget` → `HTTPException(402, detail="monthly budget exceeded")`
- [X]  `record(user_id, cost, month)`: `incrbyfloat(key, cost)` → `expire(key, KEY_TTL_SECONDS)` → `return float(total)`

### `app/main.py` — `/ask` (đúng thứ tự)

- [X]  `limiter.check(user_id)` → 429 nếu gọi quá nhanh
- [X]  `guard.check(user_id)` → 402 nếu hết ngân sách
- [X]  `history = store.get_history(user_id)`
- [X]  `result = ask_llm(payload.question, history)`
- [X]  `store.append(user_id, "user", payload.question)` + `store.append(user_id, "assistant", result["answer"])`
- [X]  `guard.record(user_id, result["cost_usd"])`
- [X]  `log_event("ask_completed", user_id=..., tokens_in=..., tokens_out=..., cost_usd=...)`
- [X]  Trả về `{answer, user_id, history_length, cost_usd, tokens}`

- ⚠️ `user_id` đến từ `Depends(verify_api_key)` — request thiếu key dừng ở 401 trước khi chạm vào gì.

### Kiểm tra

- [X]  `pytest tests/test_cp3.py -v` → **22/22 PASSED**
- [X]  **Commit:** `"CP3: auth + sliding window rate limit + cost guard"`

---

## CP4 — Scaling & Reliability: stateless, probe, shutdown (20 điểm)

### `app/store.py`

- [X]  `ping()`: `try: return self.client.ping() except Exception: return False`
- [X]  `append(user_id, role, content)`:
  - `rpush(key, json.dumps({"role": role, "content": content}, ensure_ascii=False))`
  - `ltrim(key, -HISTORY_MAX_MESSAGES, -1)` (giữ N message gần nhất)
  - `expire(key, HISTORY_TTL_SECONDS)`
- [X]  `get_history(user_id)`: `lrange(key, 0, -1)` → `[json.loads(m) for m in ...]`

### `app/lifecycle.py`

- [X]  `request_shutdown(signum, frame)`:
  - `self.shutting_down = True`
  - Gọi lại handler cũ: `previous = self._previous.get(signum); if callable(previous): previous(signum, frame)`
- [X]  `install()`: với mỗi sig trong `(SIGTERM, SIGINT)`: `self._previous[sig] = signal.getsignal(sig)` rồi `signal.signal(sig, self.request_shutdown)`

### `app/main.py`

- [X]  `/health`: thêm nhánh `if lifecycle.shutting_down` → 503 (đã làm ở CP1)
- [X]  `/ready`:
  - `lifecycle.shutting_down` → `JSONResponse(503, {"status": "shutting_down"})`
  - `store.ping()` False → `JSONResponse(503, {"status": "not ready", "redis": False})`
  - Ngược lại → `{"status": "ready", "redis": True}`

### Kiểm tra + thử stateless

- [X]  `pytest tests/test_cp4.py -v` → **19/19 PASSED**
- [X]  (Điểm cộng) `docker compose up -d --scale agent=3` → gọi `/ask` 5 lần cùng `X-User-Id` qua cổng 8000 → `history_length` tăng 0,2,4,6,8 (mỗi `/ask` ghi 2 tin user+assistant) dù request rơi vào container bất kỳ — đã xác nhận bằng Docker thật, state nằm ở Redis dùng chung
- [X]  **Commit:** `"CP4: state qua Redis + graceful shutdown + /ready"`

---

## CP5 — Deploy lên Cloud (15 điểm)

### Chọn platform (Railway hoặc Render)

- [X]  Chọn **Render** (Blueprint `render.yaml` đã sẵn sàng)
- [X]  Push repo lên GitHub: `git push origin main`
- [X]  Deploy: Render → Dashboard → **New → Blueprint** → chọn repo → Render tự tạo web service + Redis
- [X]  Nhập `AGENT_API_KEY` (sync:false → Render hỏi lúc deploy), các biến khác đã có sẵn trong `render.yaml`
- [X]  Deploy + đợi build xong, health check pass (trạng thái **Live**) — URL `https://day12-agent-ohe1.onrender.com`

### Bằng chứng bắt buộc

- [X]  Chụp ảnh dashboard Deploy thành công → `screenshots/dashboard.png` ✅
- [X]  Chụp ảnh/log curl:
  - [X]  `/health` → 200 ✅ (`screenshots/health.png`)
  - [X]  `/ready` → 200 ✅ (`screenshots/ready.png`)
  - [X]  `/ask` không key → 401 ✅ (`screenshots/ask_nokey.png`)
  - [X]  `/ask` có key live → 200 ✅ (đã test thật trả 200)
- [X]  Điền Public URL thật + họ tên + mã HV + platform + biến env (chỉ TÊN biến, không dán giá trị) vào `DEPLOYMENT.md`
- [X]  Xóa hết chữ `(điền ...)` trong `DEPLOYMENT.md`
- [X]  `pytest tests/test_cp5.py -v` → **9/9 PASSED** (4 test LocalFallback bỏ qua vì đã deploy thật)

### Nếu không deploy được lên cloud (Local Fallback, tối đa 9/15đ)

> Không dùng — đã deploy thật lên Render thành công.

- [X]  **Commit:** `"CP5: deploy lên cloud + evidence"`

---

## exercises.md — 10 câu phản ánh (15 điểm)

- [X]  Trả lời **đủ 10 câu**, thay hết dòng `> *Câu trả lời của bạn*` bằng lời của mình
- [X]  Viết dựa trên quan sát thật khi chạy code (không sao chép)
- [X]  Nêu họ tên + mã HV ở đầu file
- [X]  `grade.py` phải đếm được 10/10 câu đã trả lời
- [X]  **Commit:** `"exercises: 10 câu phản ánh"` (đã gộp vào commit bonus)

---

## BONUS — CI/CD với GitHub Actions (+10 điểm, trần 100)

### Tạo `.github/workflows/ci.yml` (tự viết)

- [X]  `name`, `on: [push, pull_request]`
- [X]  Job `test`:
  - `actions/checkout@v4` (ghim version, không dùng `@main`)
  - `setup-python` + `pip install -r requirements.txt`
  - Chạy pytest **giới hạn phạm vi** — loại `test_cp5.py` và `test_bonus_cicd.py` (dùng `--ignore` hoặc `--ignore=tests/test_cp5.py`):
    `pytest tests/test_cp1.py tests/test_cp2.py tests/test_cp3.py tests/test_cp4.py --ignore=tests/test_cp5.py --ignore=tests/test_bonus_cicd.py`
  - Truyền env giả: `env: AGENT_API_KEY: ci-dummy`, `REDIS_URL: "fake://"` (khối `env:` cấp job)
- [X]  Job `build` (sau test): `docker build` hoặc `docker/build-push-action@v6`
- [X]  Job `deploy`:
  - `needs: [test, build]`
  - `if: github.ref == 'refs/heads/main'` (chỉ deploy từ main)
  - Token deploy qua `${{ secrets.<TÊN_SECRET> }}` — KHÔNG hardcode

### Trên GitHub

- [ ]  Tạo Secrets: `RENDER_DEPLOY_HOOK` (secret) + `PUBLIC_URL` (variable) trong Settings → Secrets and variables → Actions → sau đó Re-run workflow
- [X]  Push workflow, mở tab Actions, test/build chạy xanh (deploy cần set secret mới xanh)

### Badge

- [X]  Thêm dòng badge vào đầu `README.md`
- [X]  Thay `<user>`/`<repo>` bằng giá trị thật (`binh39/K3-DAY12-2A202601091-NguyenDinhBinh`), push lên
  - ⚠️ Badge hiện **failing** vì thiếu `RENDER_DEPLOY_HOOK` + `PUBLIC_URL` → set xong Re-run là `passing`

### Kiểm tra

- [X]  `pytest tests/test_bonus_cicd.py -v` → 12/13 pass (chỉ `test_badge_bao_passing` cần workflow chạy xanh)
- [X]  **Commit:** `"BONUS: CI/CD GitHub Actions"`

---

## 🏁 Hoàn thiện & Nộp bài

- [X]  `python grade.py` → mục tiêu ≥ 75/100 (**đạt 100/100**)
- [X]  `pytest tests/ -v` → CP1-CP5 + exercises xanh hết, chỉ badge bonus còn cần set secret
- [X]  Kiểm tra an toàn secret: `git ls-files | grep "^\.env$"` → **KHÔNG** in ra gì
- [X]  Không còn `NotImplementedError` trong `app/`: `grep -rn "NotImplementedError" app/`
- [ ]  (Bonus) README có badge `passing` — cần set `RENDER_DEPLOY_HOOK` + `PUBLIC_URL` rồi Re-run
- [X]  Kiểm tra tên thư mục đúng format `DAY12-<MãHV>-<HọTên>` (viết liền, không dấu)
- [X]  Nhiều commit ở nhiều mốc thời gian (CP0→CP1→CP2→CP3→CP4→CP5→Bonus→exercises)
- [X]  `screenshots/` có ảnh health/ready/ask_nokey (có thể thêm dashboard.png)
- [ ]  `git add -A` → `git commit -m "Hoàn thành lab Day 12"` → `git push` (chờ user xác nhận)
- [ ]  Nộp link repository (public) lên Codelab
