FROM node:24-bookworm-slim
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8788
WORKDIR /app
# Production has no npm dependencies; Node strips the erasable TypeScript syntax.
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src
USER node
EXPOSE 8788
CMD ["node", "--experimental-strip-types", "src/main.ts"]
