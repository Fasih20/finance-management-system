# Stage 1: Install dependencies
FROM node:18-alpine AS deps
# Install libc6-compat for compatibilities of some native modules
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Install dependencies based on the package-lock.json
COPY package.json package-lock.json ./
RUN npm ci

# Stage 2: Build the application
FROM node:18-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Disable Next.js telemetry during build
ENV NEXT_TELEMETRY_DISABLED 1

RUN npm run build

# Prune development dependencies from node_modules to optimize runtime image size
RUN npm prune --production

# Stage 3: Production runner stage
FROM node:18-alpine AS runner
WORKDIR /app

ENV NODE_ENV production
# Disable Next.js telemetry during runtime
ENV NEXT_TELEMETRY_DISABLED 1

# Create non-root system user and group for security
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy assets and configs
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/next.config.mjs ./next.config.mjs

# Copy build artifacts and pruned node_modules with correct ownership
COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules

USER nextjs

EXPOSE 3000

ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

CMD ["npm", "start"]
