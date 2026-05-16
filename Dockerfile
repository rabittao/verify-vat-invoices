FROM mcr.microsoft.com/playwright:v1.58.2-jammy

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    APP_DATA_DIR=/app/app_data \
    NODE_ENV=production

COPY requirements.txt package.json package-lock.json ./

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m pip install --upgrade pip \
    && python3 -m pip install -r requirements.txt \
    && npm ci --omit=dev

COPY app ./app
COPY scripts ./scripts
COPY README.md ./

RUN mkdir -p /app/app_data/uploads /app/app_data/jobs /app/app_data/exports /app/app_data/logs

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
