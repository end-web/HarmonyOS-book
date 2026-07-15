FROM node:22-bookworm-slim AS api-deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM api-deps AS api-build
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-bookworm-slim AS admin-build
WORKDIR /admin
COPY admin/package.json admin/package-lock.json ./
RUN npm ci
COPY admin ./
RUN npm run build

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=api-build /app/package.json ./package.json
COPY --from=api-build /app/node_modules ./node_modules
COPY --from=api-build /app/dist ./dist
COPY --from=admin-build /admin/dist ./public/admin
RUN mkdir -p /app/data && chown -R node:node /app
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/api/v1/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
CMD ["node", "dist/index.js"]
