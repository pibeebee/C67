FROM python:3.12-slim
WORKDIR /app
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
COPY --chmod=0644 server/pocket/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt \
    && playwright install --with-deps chromium \
    && apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home pocket && mkdir -p /data && chown pocket:pocket /data
COPY --chmod=0644 server/pocket/src/server.py server/pocket/src/resolution.py server/pocket/src/ordering.py ./src/
RUN chmod 0755 /app/src
COPY --chmod=0644 research/poc-journey/apps/c67-pocket-engine-lab/Server/visit_advice.py ./visit_advice.py
ENV POCKET_HOST=0.0.0.0 POCKET_PORT=8792 PYTHONUNBUFFERED=1 POCKET_ADVICE_MODULE=/app/visit_advice.py PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN chmod -R a+rX /ms-playwright
USER 10001
EXPOSE 8792
VOLUME ["/data"]
CMD ["python", "src/server.py", "--data-dir", "/data"]
