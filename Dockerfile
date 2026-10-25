# Coolify Abbild ohne die HIGH/CRITICAL Befunde in /usr/bin/mc und /usr/local/bin/cloudflared.
#
# Das offizielle Abbild coollabsio/coolify bringt beide Go Programme als fertige
# Binaries mit (mc aus quay.io/minio/aistor/mc, cloudflared aus dem GitHub Release).
# Trivy meldet darin Befunde in der Go Standardbibliothek, golang.org/x/net,
# google.golang.org/grpc (mc) und github.com/klauspost/compress (cloudflared).
# Beide werden hier aus der Quelle mit aktuellem Go und angehobenen Modulen gebaut
# und an dieselben Pfade mit denselben Rechten (root:root 755) kopiert. Alles andere
# bleibt das offizielle Abbild: Schichten, Entrypoint, Cmd, Nutzer, Umgebung, Healthcheck.
#
# COOLIFY_VERSION setzt die Pipeline auf coolify.v4.version aus
# https://cdn.coollabs.io/coolify/versions.json. BASE kann auf einen Digest zeigen.
ARG COOLIFY_VERSION=4.5.0
ARG BASE=docker.io/coollabsio/coolify:${COOLIFY_VERSION}
# Go 1.27.3: erfuellt go.mod von cloudflared (go 1.27.3) und enthaelt alle stdlib Fixes.
ARG GO_IMAGE=golang:1.27.3-alpine
# MinIO Client: github.com/minio/mc ist archiviert, AIStor mc ist nicht quelloffen.
# Gebaut wird der letzte Stand von master (Commit vom 06.11.2025).
ARG MC_REF=77f82e18b5401a65958f1619df6ebb994634bd88
# cloudflared Version, die im offiziellen Abbild steckt (ARG CLOUDFLARED_VERSION im
# Coolify Dockerfile). Die Pipeline liest sie aus dem Basisabbild.
ARG CLOUDFLARED_REF=2026.10.3

FROM ${GO_IMAGE} AS gobase
RUN apk add --no-cache git make
ENV CGO_ENABLED=0 GOTOOLCHAIN=local GOFLAGS=-trimpath
COPY scripts/raise-modules.sh /usr/local/bin/raise-modules
COPY scripts/check-modules.sh /usr/local/bin/check-modules

FROM gobase AS mc
ARG MC_REF
# Mindestversionen nach Trivy (fixable HIGH/CRITICAL), neuere Versionen bleiben stehen.
ARG MC_MODULES="golang.org/x/net@v0.60.0 google.golang.org/grpc@v1.83.2 github.com/klauspost/compress@v1.18.7 github.com/prometheus/prometheus@v0.311.3"
WORKDIR /src/mc
RUN git init -q . \
 && git fetch -q --depth 1 https://github.com/minio/mc.git "${MC_REF}" \
 && git checkout -q FETCH_HEAD \
 && sh /usr/local/bin/raise-modules ${MC_MODULES}
# Versionsangabe wie upstream (buildscripts/gen-ldflags.go): Zeitpunkt des Commits,
# Praefix DEVELOPMENT, weil es zu diesem Commit kein upstream Release gibt.
RUN set -eu; \
    t=$(TZ=UTC git log -1 --format=%cd --date=format-local:'%Y-%m-%dT%H:%M:%SZ'); \
    ldflags=$(go run buildscripts/gen-ldflags.go "$t"); \
    go build -tags kqueue -ldflags "$ldflags" -o /out/mc . \
 && /out/mc --version \
 && sh /usr/local/bin/check-modules /out/mc ${MC_MODULES}

FROM gobase AS cloudflared
ARG CLOUDFLARED_REF
ARG CLOUDFLARED_MODULES="github.com/klauspost/compress@v1.18.7"
WORKDIR /src/cloudflared
RUN git clone -q --depth 1 --branch "${CLOUDFLARED_REF}" https://github.com/cloudflare/cloudflared.git . \
 && sh /usr/local/bin/raise-modules ${CLOUDFLARED_MODULES}
# Bau wie upstream per make (main.Version aus git describe, main.BuildTime aus dem
# Commit), ohne FIPS und ohne Container Kennung, wie das Release Binary.
RUN set -eu; \
    date=$(TZ=UTC git log -1 --format=%cd --date=format-local:'%Y-%m-%d-%H:%M UTC'); \
    make cloudflared VERSION="${CLOUDFLARED_REF}" DATE="$date" \
 && mkdir -p /out && mv cloudflared /out/cloudflared \
 && /out/cloudflared --version \
 && sh /usr/local/bin/check-modules /out/cloudflared ${CLOUDFLARED_MODULES}

FROM ${BASE}
COPY --from=mc --chown=0:0 --chmod=755 /out/mc /usr/bin/mc
COPY --from=cloudflared --chown=0:0 --chmod=755 /out/cloudflared /usr/local/bin/cloudflared
