# syntax=docker/dockerfile:1
FROM python:3.12-slim AS base

# Non-root runtime user
RUN groupadd --system app && useradd --system --gid app --home /app app

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --require-hashes=false -r requirements.txt

COPY app.py .

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz').status==200 else 1)"

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
