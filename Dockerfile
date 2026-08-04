ARG NODE_VERSION=21.6.0
ARG WIKI_NAME="mywiki"
# Space-separated GitHub "owner/repo" plugin sources baked into /usr/src/app/baked-plugins at build time.
# Each repo's plugins/ subdirectories are copied wholesale; TiddlyWiki activates them by plugin.info
# title (plugin folder names are irrelevant), e.g. "$:/plugins/flibbles/graph". The chart adds
# /usr/src/app/baked-plugins to TIDDLYWIKI_PLUGIN_PATH and merges each baked plugin.info title into
# tiddlywiki.info so the baked plugins are both discoverable and activated.
# Each entry may pin its own ref with "owner/repo@ref" (branch or tag). Entries without an "@" use
# the TW5_PLUGIN_REF fallback. COPY . /usr/src/app/ below already copies the repo's own plugins/ dir
# into /usr/src/app/plugins, so you could omit the download entirely by committing plugin sources here.
#   docker build --build-arg TW5_PLUGINS="flibbles/tw5-graph@v1.7.1 flibbles/tw5-vis-network@v10.6.3"
ARG TW5_PLUGINS="flibbles/tw5-graph@v1.7.1 flibbles/tw5-vis-network@v10.6.3"
ARG TW5_PLUGIN_REF=master

# Base Image
FROM node:${NODE_VERSION}-alpine AS base
WORKDIR /usr/src/app
RUN apk add dumb-init
RUN apk add curl
COPY package.json .
RUN npm install
COPY . /usr/src/app/

# Bake plugins (generic) so the wiki can load them
RUN apk add --no-cache curl tar \
    && mkdir -p /usr/src/app/baked-plugins \
    && for entry in $TW5_PLUGINS; do \
         repo="${entry%@*}"; ref="${entry#*@}"; \
         if [ "$ref" = "$repo" ]; then ref="$TW5_PLUGIN_REF"; fi; \
         name="${repo##*/}"; \
         echo "Baking plugins from ${repo} (ref: ${ref})"; \
         curl -fsSL -o "/tmp/${name}.tar.gz" "https://github.com/${repo}/archive/refs/tags/${ref}.tar.gz" \
         || curl -fsSL -o "/tmp/${name}.tar.gz" "https://github.com/${repo}/archive/refs/heads/${ref}.tar.gz"; \
         tar -xzf "/tmp/${name}.tar.gz" -C /tmp \
         && cp -r /tmp/${name}-*/plugins/* /usr/src/app/baked-plugins/ \
         && rm -rf "/tmp/${name}"*; \
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
COPY --chown=node:node . /usr/src/app
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "./tiddlywiki.js", "./editions/server", "--listen", "host=0.0.0.0"]
