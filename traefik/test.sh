#!/bin/sh
set -eu
base=${1:?base image required}
image=${2:?candidate image required}
# Never echo environment values on a mismatch.
fmt='{{json .Config.Entrypoint}}|{{json .Config.Cmd}}|{{.Config.User}}|{{.Config.WorkingDir}}|{{json .Config.Env}}|{{json .Config.ExposedPorts}}|{{json .Config.Volumes}}|{{json .Config.Healthcheck}}'
test "$(docker image inspect -f "$fmt" "$base")" = "$(docker image inspect -f "$fmt" "$image")"
docker run --rm "$image" version | grep -Eq '^Version: +3\.7\.16$'
name=tmp_traefik_cve_$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT INT TERM
docker run -d --name "$name" "$image" --ping --api.insecure=true --entrypoints.traefik.address=:8080 >/dev/null
attempt=0
until docker exec "$name" traefik healthcheck --ping >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  test "$attempt" -lt 30
  sleep 1
done
docker exec "$name" wget -qO- http://127.0.0.1:8080/dashboard/ | grep -qi '<!doctype html>'
docker exec "$name" wget -qO- http://127.0.0.1:8080/api/version | grep -q '3.7.16'
echo 'Runtime config unchanged; version, ping, dashboard and API passed.'
