FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home pocket && mkdir -p /data && chown pocket:pocket /data
WORKDIR /app
COPY --chmod=644 server/pocket/src/server.py server/pocket/src/visit_advice.py ./src/
COPY --chmod=644 packages/PocketEngine/Sources/PocketEngine/Resources/catalog.json packages/PocketEngine/Sources/PocketEngine/Resources/preference-labels.json ./resources/
RUN chmod 755 /app /app/src /app/resources
ENV POCKET_HOST=0.0.0.0 POCKET_PORT=8792 POCKET_RESOURCE_DIR=/app/resources PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
USER 10001
EXPOSE 8792
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl --fail --silent --max-time 3 http://127.0.0.1:8792/health || exit 1
CMD ["python3", "src/server.py", "--data-dir", "/data"]
