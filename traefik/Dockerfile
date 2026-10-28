# Keep the official runtime and replace only the binary (TK-119).
ARG BASE=traefik:v3.7.16
FROM node:24-alpine3.24 AS webui
RUN apk add --no-cache git
WORKDIR /src
RUN git init -q . \
 && git fetch -q --depth 1 https://github.com/traefik/traefik.git af6d927c51191ae1df104aaf907793386b816c28 \
 && git checkout -q FETCH_HEAD
WORKDIR /src/webui
ENV VITE_APP_BASE_URL="" VITE_APP_BASE_API_URL="/api"
RUN corepack enable && yarn install --immutable && yarn build:prod

FROM golang:1.27.3-alpine@sha256:b8c9b82affbbb82a020bbcf998dad2ba9516944ac7e883524642a481a9505e9c AS build
RUN apk add --no-cache git
ENV CGO_ENABLED=0 GOTOOLCHAIN=local GOFLAGS=-trimpath
WORKDIR /src
COPY --from=webui /src /src
COPY scripts/raise-modules.sh scripts/check-modules.sh /usr/local/bin/
RUN sh /usr/local/bin/raise-modules.sh github.com/go-jose/go-jose/v4@v4.1.6 \
 && go test github.com/go-jose/go-jose/v4/... \
 && go build -ldflags '-s -w -X github.com/traefik/traefik/v3/pkg/version.Version=3.7.16 -X github.com/traefik/traefik/v3/pkg/version.Codename=langres' -o /out/traefik ./cmd/traefik \
 && sh /usr/local/bin/check-modules.sh /out/traefik github.com/go-jose/go-jose/v4@v4.1.6 \
 && /out/traefik version

FROM ${BASE}
COPY --from=build --chown=1001:1001 --chmod=755 /out/traefik /usr/local/bin/traefik
