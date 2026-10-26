FROM node:22-bookworm-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY image.mjs worker.mjs ./
USER node
CMD ["node","worker.mjs"]
