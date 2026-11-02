# syntax=docker/dockerfile:1

# Self-hosted OpenLeague image. Bun is the toolchain (ADR-0005), so the image
# installs, builds and runs with Bun exactly as `bun install` / `bun run build`
# / `bun run start` do locally. See docker-compose.yml for the full stack.

ARG BUN_VERSION=1.4.4

FROM oven/bun:${BUN_VERSION}-debian AS base
WORKDIR /app
# Prisma's schema engine (used by `migrate deploy`) links against OpenSSL.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# --- Dependencies -----------------------------------------------------------
FROM base AS deps
# postinstall runs `prisma generate`, which loads prisma/prisma.config.ts and so
# needs DATABASE_URL to be set. It is never connected to.
ENV DATABASE_URL=postgresql://build:build@localhost:5432/build
COPY package.json bun.lock ./
COPY prisma ./prisma
RUN bun install --frozen-lockfile

# --- Build ------------------------------------------------------------------
FROM base AS build
# lib/env.ts skips validation during `next build`, so placeholders suffice.
ENV DATABASE_URL=postgresql://build:build@localhost:5432/build \
    NEXT_TELEMETRY_DISABLED=1
# NEXT_PUBLIC_* values are inlined into the client bundle at build time, so
# they are build args rather than runtime environment.
ARG NEXT_PUBLIC_UMAMI_WEBSITE_ID=""
ARG NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=""
ENV NEXT_PUBLIC_UMAMI_WEBSITE_ID=${NEXT_PUBLIC_UMAMI_WEBSITE_ID} \
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=${NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY}
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN bun run build

# --- Runtime ----------------------------------------------------------------
FROM base AS runner
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000
# node_modules keeps the Prisma CLI so the same image runs migrations.
COPY --from=build --chown=bun:bun /app/package.json /app/next.config.ts ./
COPY --from=build --chown=bun:bun /app/node_modules ./node_modules
COPY --from=build --chown=bun:bun /app/.next ./.next
COPY --from=build --chown=bun:bun /app/public ./public
COPY --from=build --chown=bun:bun /app/prisma ./prisma
USER bun
EXPOSE 3000
CMD ["bun", "run", "start"]
