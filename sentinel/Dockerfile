ARG BASE=docker.io/coollabsio/sentinel:1.1.3@sha256:81f8ab984ea5c5fdbd696ea2f47f08c9e31ec41db7493a657b53a52256e26a82
FROM ${BASE}
# CVE-2026-92392, preserving the upstream Sentinel program and runtime settings.
RUN apk upgrade --no-cache brotli-libs curl libcurl \
 && apk add --no-cache 'brotli-libs>=1.2.1-r0' 'curl>=8.23.0-r0' 'libcurl>=8.23.0-r0'
LABEL org.opencontainers.image.source="https://github.com/Amadudl/coolify-ohne-cve" \
      io.iexlabs.cve-fix="CVE-2026-92392"
