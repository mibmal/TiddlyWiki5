ARG NODE_VERSION=18.0.0

# Base Image
FROM node:${NODE_VERSION}-alpine as base
RUN mkdir -p /opt/app
WORKDIR /opt/app
COPY . ./
RUN npm install --prefix /opt/app/a -g
RUN apk add --no-cache tree
RUN tree -fi

# Playwright Tests
FROM mcr.microsoft.com/playwright:focal as playwright-tests
ENV CI=true
WORKDIR /opt/app
COPY . ./
RUN ["./bin/ci-test.sh"]

#Jasmine Tests
FROM base as jasmine-tests
RUN apk add chromium
ENV CHROME_BIN=/usr/bin/chromium-browser
RUN npm run test

#Run TiddlyWiki
FROM node:${NODE_VERSION}-alpine as run
EXPOSE 8080
WORKDIR /opt/app
COPY --from=base /opt/app/a/bin/tiddlywiki .
COPY --from=base /opt/app/boot ./
RUN apk add --no-cache tree
RUN tree -fi
#CMD [ "node", "./tiddlywiki.js", "--init", "server"]
CMD [ "node", "tiddlywiki", "--listen"]
