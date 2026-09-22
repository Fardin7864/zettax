FROM node:22-alpine AS build
RUN corepack enable
WORKDIR /workspace
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY apps/backend/package.json apps/backend/package.json
COPY packages/shared-types/package.json packages/shared-types/package.json
RUN pnpm install --frozen-lockfile
COPY apps/backend apps/backend
COPY packages/shared-types packages/shared-types
RUN pnpm --filter @primevest/shared-types build && pnpm --filter @primevest/backend prisma:generate && pnpm --filter @primevest/backend build

FROM node:22-alpine
WORKDIR /workspace
ENV NODE_ENV=production
COPY --chown=node:node --from=build /workspace/package.json /workspace/pnpm-lock.yaml /workspace/pnpm-workspace.yaml /workspace/tsconfig.base.json ./
COPY --chown=node:node --from=build /workspace/node_modules ./node_modules
COPY --chown=node:node --from=build /workspace/apps/backend ./apps/backend
COPY --chown=node:node --from=build /workspace/packages/shared-types ./packages/shared-types
EXPOSE 3000
USER node
CMD ["node", "apps/backend/dist/apps/backend/src/main.js"]
