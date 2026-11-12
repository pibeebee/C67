FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home pocket && mkdir -p /data && chown pocket:pocket /data
WORKDIR /app
COPY poc-journey/apps/c67-pocket-engine-lab/Server/server.py poc-journey/apps/c67-pocket-engine-lab/Server/visit_advice.py ./Server/
COPY packages/PocketEngine/Sources/PocketEngine/Resources/catalog.json packages/PocketEngine/Sources/PocketEngine/Resources/preference-labels.json ./Sources/PocketEngine/Resources/
ENV POCKET_HOST=0.0.0.0 POCKET_PORT=8792 PYTHONUNBUFFERED=1
USER 10001
EXPOSE 8792
VOLUME ["/data"]
CMD ["python3", "Server/server.py", "--data-dir", "/data"]
