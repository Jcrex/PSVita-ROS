# Dockerfile — web del proyecto PS Vita <-> ROS2 (Astro SSR + SQLite).
#
# Contexto de build = RAÍZ DEL REPO (no web/), porque las guías markdown se
# leen de docs/guias-vita/ en build time. Ver web/docker-compose.yml.
#
# Multi-stage: la imagen final solo lleva el servidor compilado, las deps
# de producción (better-sqlite3) y nada de toolchain.

# ---------- etapa de build ----------
FROM node:22-slim AS build

# Toolchain por si better-sqlite3 no encuentra binario precompilado.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ && rm -rf /var/lib/apt/lists/*

RUN corepack enable pnpm
WORKDIR /app/web

# Capa de dependencias cacheable: solo se reinstala si cambian los locks.
COPY web/package.json web/pnpm-lock.yaml web/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

# Código del sitio + las guías (fuente de verdad en docs/).
COPY web/ ./
COPY docs/guias-vita/ /app/docs/guias-vita/
RUN pnpm build

# Quitar devDependencies del node_modules que viajará a runtime.
RUN pnpm prune --prod

# ---------- etapa de runtime ----------
FROM node:22-slim AS runtime

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=4321 \
    DB_PATH=/app/web/data/app.db

WORKDIR /app/web
COPY --from=build /app/web/dist ./dist
COPY --from=build /app/web/node_modules ./node_modules
COPY --from=build /app/web/package.json ./package.json

# La DB vive en un volumen montado aquí (ver docker-compose.yml).
RUN mkdir -p /app/web/data && chown -R node:node /app/web
USER node

EXPOSE 4321
CMD ["node", "dist/server/entry.mjs"]
