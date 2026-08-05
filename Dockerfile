# syntax=docker/dockerfile:1
# The syntax= directive above (must be the first line) pins the BuildKit
# Dockerfile frontend so `docker build --check .` uses a fixed linter-enabled
# parser instead of whatever is bundled with the local engine. It requests the
# built-in syntax/structure check from inside the Dockerfile itself; the CI job
# `.github/workflows/ci.yml` (`dockerfile-check`) runs that check on every PR.
ARG NODE_VERSION=21.6.0
ARG WIKI_NAME="mywiki"
# Space-separated GitHub "owner/repo" plugin sources baked into /usr/src/app/baked-plugins at build time.
# Entry syntax: owner/repo[@ref][:subdir]
#   - ref:    branch or tag; without "@" falls back to TW5_PLUGIN_REF (tag tried first, then branch).
#   - subdir: subdirectory of the extracted tarball to copy (as a whole). Defaults to "plugins".
#             TiddlyWiki's plugin path scan is recursive, so any copy that ends in a folder containing
#             plugin.info is discovered; activation is by plugin.info title (folder names are irrelevant),
#             e.g. "$:/plugins/flibbles/graph". The chart adds /usr/src/app/baked-plugins to
#             TIDDLYWIKI_PLUGIN_PATH and merges each baked plugin.info title into tiddlywiki.info.
# COPY . /usr/src/app/ below already copies the repo's own plugins/ dir into /usr/src/app/plugins, so
# you could omit the download entirely by committing plugin sources here.
#   docker build --build-arg TW5_PLUGINS="flibbles/tw5-graph@v1.7.1 bimlas/tw5-kin-filter@v1.0.1"
ARG TW5_PLUGINS="flibbles/tw5-graph@v1.7.1 flibbles/tw5-vis-network@v10.6.3 flibbles/tw5-relink@v2.6.0 bimlas/tw5-kin-filter@v1.0.1 sobjornstad/TiddlyRemember@v1.4.1:tw-plugin"
ARG TW5_PLUGIN_REF=master

# Base Image
FROM node:${NODE_VERSION}-alpine AS base
WORKDIR /usr/src/app
# Re-declare the plugin ARGs inside the stage: ARGs declared before the first
# FROM do NOT propagate into build stages, so without these the bake loop below
# saw empty $TW5_PLUGINS and produced an empty baked-plugins dir. --build-arg
# on the CLI sets the same-named ARG here and the global one.
ARG TW5_PLUGINS
ARG TW5_PLUGIN_REF=master
RUN apk add dumb-init
RUN apk add curl
COPY package.json .
RUN npm install
COPY . /usr/src/app/

# Bake plugins (generic) so the wiki can load them. Each entry
# "owner/repo[@ref][:subdir]" downloads a GitHub tag tarball (falling back to a
# branch) and copies its `subdir` (default "plugins") into baked-plugins.
# Hardened: we only tar/cp when a tarball was actually fetched, and a failed
# download aborts with a clear per-entry message instead of a cryptic `tar`
# exit-2 on a missing file.
RUN apk add --no-cache curl tar \
    && mkdir -p /usr/src/app/baked-plugins \
    && for entry in $TW5_PLUGINS; do \
         defspec="${entry%%:*}"; subdir="${entry#*:}"; \
         if [ "$subdir" = "$entry" ]; then subdir="plugins"; fi; \
         ref="${defspec#*@}"; repo="${defspec%@*}"; \
         if [ "$ref" = "$defspec" ]; then ref="$TW5_PLUGIN_REF"; fi; \
         name="${repo##*/}"; tarball="/tmp/${name}.tar.gz"; \
         echo "Baking ${repo} (ref: ${ref}, subdir: ${subdir})"; \
         rm -f "$tarball"; \
         curl -fsSL -o "$tarball" "https://github.com/${repo}/archive/refs/tags/${ref}.tar.gz" \
         || curl -fsSL -o "$tarball" "https://github.com/${repo}/archive/refs/heads/${ref}.tar.gz"; \
         if [ -s "$tarball" ]; then \
           tar -xzf "$tarball" -C /tmp \
           && cp -r /tmp/${name}-*/${subdir} /usr/src/app/baked-plugins/ \
           && rm -rf "$tarball"; \
         else \
           echo "ERROR: failed to download plugins from ${repo} (ref: ${ref})" >&2; \
           exit 1; \
         fi; \
       done \
    && chown -R node:node /usr/src/app/baked-plugins

# Playwright Tests
FROM mcr.microsoft.com/playwright:focal AS playwright-tests
ENV CI=true
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install @playwright/test
COPY . /usr/src/app/
RUN npx playwright install --with-deps
RUN ["npx", "playwright", "test"]
RUN npm install
RUN npx playwright install

#Jasmine Tests
FROM base AS jasmine-tests
RUN apk add chromium
ENV CHROME_BIN=/usr/bin/chromium-browser
RUN npm run test

#Run TiddlyWiki
FROM base AS run
EXPOSE 8080
COPY --from=base /usr/bin/dumb-init /usr/bin/dumb-init
USER node
WORKDIR /usr/src/app
COPY --chown=node:node --from=base /usr/src/app/node_modules /usr/src/app/node_modules
COPY --chown=node:node --from=base /usr/src/app/baked-plugins /usr/src/app/baked-plugins
COPY --chown=node:node . /usr/src/app
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "./tiddlywiki.js", "./editions/server", "--listen", "host=0.0.0.0"]
