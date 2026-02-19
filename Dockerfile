# syntax=docker/dockerfile:1.7

# ============================================================
# Stage 1: source preparation
# node:22-alpine provides a shell to chmod the entrypoint.
# No npm install is needed — TiddlyWiki has zero prod deps.
# ============================================================
FROM node:22-alpine AS source

WORKDIR /app

# Copy only the runtime-required source tree.
# Largest/most-stable dirs first for better layer caching.
COPY boot/          ./boot/
COPY core/          ./core/
COPY core-server/   ./core-server/
COPY editions/      ./editions/
COPY languages/     ./languages/
COPY plugins/       ./plugins/
COPY themes/        ./themes/
COPY package.json   ./package.json
COPY tiddlywiki.js  ./tiddlywiki.js

# Ensure the entrypoint is executable (git may not preserve bits in CI).
RUN chmod +x ./tiddlywiki.js

# ============================================================
# Stage 2: distroless runtime
# gcr.io/distroless/nodejs22-debian12 contains:
#   /nodejs/bin/node  — the only executable we need
#   nonroot user uid=65532 gid=65532
# No shell, no package manager, minimal attack surface.
# ============================================================
FROM gcr.io/distroless/nodejs22-debian12

EXPOSE 8080

WORKDIR /app

# Copy prepared source, owned by the distroless nonroot user.
COPY --from=source --chown=65532:65532 /app /app

# Wiki data is mounted here at runtime (Kubernetes PVC or docker -v).
# The directory itself is created by an initContainer in Kubernetes.
VOLUME ["/data/wiki"]

# Run as distroless nonroot (uid 65532).
USER nonroot

# ENTRYPOINT must be exec-form — no shell exists in distroless.
# /nodejs/bin/node is the node binary path in this image.
ENTRYPOINT ["/nodejs/bin/node", "tiddlywiki.js"]

# Default: serve the bundled standalone server edition.
# This works out of the box with no PVC pre-population needed.
#
# To serve your own persistent wiki instead, override CMD:
#   docker run ... <image> /data/wiki --listen host=0.0.0.0 port=8080
# Or in Kubernetes, set deployment.spec.template.spec.containers[0].args
CMD ["/app/editions/server", "--listen", "host=0.0.0.0", "port=8080"]
