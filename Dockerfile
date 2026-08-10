# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (production-ready)
#
# Multi-stage build:
#   - Stage `builder`: chỉ cài dependency vào /install (không mang compiler)
#   - Stage runtime: copy kết quả install sang, chạy bằng user thường,
#     có HEALTHCHECK, đọc cổng từ biến môi trường PORT cho cloud.
# ═══════════════════════════════════════════════════════════════════

# Stage 1 — builder: cài dependency
FROM python:3.11-slim AS builder

WORKDIR /build

COPY requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2 — runtime: copy kết quả từ builder, chạy app
FROM python:3.11-slim

WORKDIR /app

# Copy toàn bộ thư viện đã cài từ builder sang runtime
COPY --from=builder /install /usr/local

# Copy source code (sau khi cài dependency để tận dụng Docker cache)
COPY app/ app/
COPY utils/ utils/

# Chạy bằng user thường, không dùng root
RUN useradd --system --create-home appuser
USER appuser

EXPOSE 8000

# Health check: image slim không có curl → dùng Python, đọc $PORT
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import os, urllib.request; port = os.getenv('PORT', '8000'); urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=3)"

# Cloud tự gán cổng (Railway, Render...) → đọc $PORT, mặc định 8000
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]