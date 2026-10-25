#!/bin/sh
# Prueft das abgeleitete Abbild gegen das offizielle Coolify Abbild.
#
# Aufruf: sh test.sh <offizielles abbild> <abgeleitetes abbild>
#
# Umgebung (alles optional):
#   TRIVY        Trivy Aufruf, Vorgabe: Container aquasec/trivy:0.76.1 mit Docker Socket
#   TRIVY_STRICT 1 = das ganze Abbild muss 0 HIGH/CRITICAL (fixable) haben.
#                Vorgabe 0 = mc und cloudflared muessen 0 haben und das abgeleitete
#                Abbild darf keinen Befund haben, den das offizielle nicht hat.
#   SKIP_TRIVY   1 = Trivy Pruefung auslassen
#   SKIP_STACK   1 = Startprobe mit PostgreSQL und Redis auslassen
#   S3_IMAGE     S3 Testserver fuer mc, Vorgabe rclone/rclone:1 (rclone serve s3)
#   PG_IMAGE     Vorgabe postgres:15-alpine, REDIS_IMAGE Vorgabe redis:7-alpine
set -eu

ORIG=${1:?offizielles Abbild fehlt}
NEU=${2:?abgeleitetes Abbild fehlt}
TRIVY=${TRIVY:-docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.76.1}
S3_IMAGE=${S3_IMAGE:-rclone/rclone:1}
PG_IMAGE=${PG_IMAGE:-postgres:15-alpine}
REDIS_IMAGE=${REDIS_IMAGE:-redis:7-alpine}
P=tmp_coolifytest_$$
fehler=0

ok() { echo "ok: $*"; }
nok() { echo "FEHLER: $*"; fehler=1; }

aufraeumen() {
  docker rm -f "${P}_s3" "${P}_db" "${P}_redis" "${P}_app" >/dev/null 2>&1 || true
  docker network rm "${P}_net" >/dev/null 2>&1 || true
}
trap aufraeumen EXIT INT TERM

# 1. Laufzeitkonfiguration unveraendert. Labels duerfen sich nur in
#    org.opencontainers.image.* unterscheiden (Herkunft des abgeleiteten Abbilds).
fmt='{{json .Config.Entrypoint}}|{{json .Config.Cmd}}|{{.Config.User}}|{{.Config.WorkingDir}}|{{json .Config.Env}}|{{json .Config.ExposedPorts}}|{{json .Config.Healthcheck}}|{{.Config.StopSignal}}|{{json .Config.Volumes}}|{{.Os}}/{{.Architecture}}'
a=$(docker image inspect -f "$fmt" "$ORIG")
b=$(docker image inspect -f "$fmt" "$NEU")
if [ "$a" = "$b" ]; then ok "Entrypoint, Cmd, Nutzer, Umgebung, Healthcheck, Plattform gleich"; else nok "Laufzeitkonfiguration weicht ab"; echo "  $a"; echo "  $b"; fi
lab='{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{println}}{{end}}'
a=$(docker image inspect -f "$lab" "$ORIG" | grep -v '^org\.opencontainers\.image\.' || true)
b=$(docker image inspect -f "$lab" "$NEU" | grep -v '^org\.opencontainers\.image\.' || true)
if [ "$a" = "$b" ]; then ok "Labels ausser org.opencontainers.image.* gleich"; else nok "Labels weichen ab"; fi

# 2. Basisschichten unveraendert, genau zwei neue Schichten (mc, cloudflared).
la=$(docker image inspect -f '{{len .RootFS.Layers}}' "$ORIG")
lb=$(docker image inspect -f '{{len .RootFS.Layers}}' "$NEU")
if [ "$lb" -eq $((la + 2)) ]; then ok "genau 2 neue Schichten ($la -> $lb)"; else nok "Schichten $la -> $lb, erwartet $((la + 2))"; fi
basis=$(docker image inspect -f '{{range .RootFS.Layers}}{{.}} {{end}}' "$ORIG")
case "$(docker image inspect -f '{{range .RootFS.Layers}}{{.}} {{end}}' "$NEU")" in
  "$basis"*) ok "Basisschichten unveraendert" ;;
  *) nok "Basisschichten weichen ab" ;;
esac

# 3. Pfade, Eigentuemer und Rechte wie im Original, Inhalt ersetzt.
rechte='stat -c "%n %a %U:%G" /usr/bin/mc /usr/local/bin/cloudflared'
a=$(docker run --rm --entrypoint sh "$ORIG" -c "$rechte")
b=$(docker run --rm --entrypoint sh "$NEU" -c "$rechte")
if [ "$a" = "$b" ]; then ok "Rechte gleich: $(echo "$b" | tr '\n' ';')"; else nok "Rechte weichen ab: $a / $b"; fi
summen='sha256sum /usr/bin/mc /usr/local/bin/cloudflared | cut -d" " -f1 | tr "\n" " "'
a=$(docker run --rm --entrypoint sh "$ORIG" -c "$summen")
b=$(docker run --rm --entrypoint sh "$NEU" -c "$summen")
if [ "${a%% *}" != "${b%% *}" ] && [ "$(echo "$a" | cut -d' ' -f2)" != "$(echo "$b" | cut -d' ' -f2)" ]; then
  ok "beide Binaries ersetzt"
else
  nok "mindestens ein Binary nicht ersetzt"
fi

# 4. Versionen, ausgefuehrt als Standardnutzer des Abbilds (www-data).
if out=$(docker run --rm --entrypoint mc "$NEU" --version); then
  echo "$out" | sed 's/^/  /'
  if echo "$out" | grep -q 'Runtime: go1\.'; then ok "mc --version"; else nok "mc meldet keine Go Version"; fi
else
  nok "mc --version"
fi
want=$(docker run --rm --entrypoint cloudflared "$ORIG" --version | sed -n 's/^cloudflared version \([^ ]*\).*/\1/p')
if out=$(docker run --rm --entrypoint cloudflared "$NEU" --version); then
  echo "  $out"
  case "$out" in "cloudflared version $want "*) ok "cloudflared --version gleich $want" ;; *) nok "cloudflared Version weicht ab (erwartet $want)" ;; esac
else
  nok "cloudflared --version"
fi
if out=$(docker run --rm --entrypoint php "$NEU" artisan --version); then ok "php artisan --version: $out"; else nok "php artisan --version"; fi

# 5. cloudflared Unterbefehl, den Coolify als SSH ProxyCommand nutzt.
if docker run --rm --entrypoint cloudflared "$NEU" access ssh --help 2>&1 | grep -q -- '--hostname'; then
  ok "cloudflared access ssh --hostname"
else
  nok "cloudflared access ssh --hostname"
fi

docker network create "${P}_net" >/dev/null

# 6. mc gegen einen S3 Server mit den Aufrufen, die Coolify in Sicherungen nutzt:
#    alias set, cp, pipe --checksum MD5, stat --json, globales --resolve, Rueckweg mit cmp.
# Wegwerf Zugang nur fuer diesen Lauf
s3key=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
if docker run -d --name "${P}_s3" --network "${P}_net" "$S3_IMAGE" \
     serve s3 /data --addr :9000 --auth-key "probe,$s3key" >/dev/null 2>&1; then
  sleep 3
  docker exec "${P}_s3" mkdir -p /data/sicherung
  if docker run --rm --network "${P}_net" -e S3="${P}_s3" -e S3KEY="$s3key" --entrypoint sh "$NEU" -c '
      set -e
      export HOME=/tmp
      ip=$(getent hosts "$S3" | cut -d" " -f1)
      r="--resolve $S3:9000=$ip"
      mc alias set $r temporary "http://$S3:9000" probe "$S3KEY" --api S3v4 >/dev/null
      head -c 3000000 /dev/urandom > /tmp/a.bin
      mc cp $r --quiet /tmp/a.bin temporary/sicherung/a.bin >/dev/null
      mc pipe $r --checksum MD5 temporary/sicherung/b.bin < /tmp/a.bin >/dev/null 2>/tmp/pipe.log
      mc stat --json $r temporary/sicherung/b.bin | grep -q "\"status\":\"success\""
      mc cp $r --quiet temporary/sicherung/b.bin /tmp/b.bin >/dev/null
      cmp /tmp/a.bin /tmp/b.bin
      mc cp $r --quiet temporary/sicherung/a.bin /tmp/c.bin >/dev/null
      cmp /tmp/a.bin /tmp/c.bin'; then
    ok "mc alias set, cp, pipe --checksum MD5, stat --json, --resolve gegen S3 ($S3_IMAGE)"
  else
    nok "mc gegen S3 ($S3_IMAGE)"
  fi
else
  nok "S3 Testserver $S3_IMAGE startet nicht"
fi

# 7. Coolify startet mit PostgreSQL und Redis bis healthy (Migrationen, nginx, php-fpm, Horizon).
if [ "${SKIP_STACK:-0}" != "1" ]; then
  pw=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
  docker run -d --name "${P}_db" --network "${P}_net" -e POSTGRES_USER=coolify \
    -e POSTGRES_PASSWORD="$pw" -e POSTGRES_DB=coolify "$PG_IMAGE" >/dev/null
  docker run -d --name "${P}_redis" --network "${P}_net" "$REDIS_IMAGE" redis-server --requirepass "$pw" >/dev/null
  i=0
  until docker exec "${P}_db" pg_isready -q -U coolify -h 127.0.0.1 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 60 ] || break; sleep 1
  done
  key="base64:$(head -c 32 /dev/urandom | base64)"
  docker run -d --name "${P}_app" --network "${P}_net" \
    -e APP_ID=test -e APP_NAME=Coolify -e APP_ENV=production -e APP_KEY="$key" \
    -e DB_HOST="${P}_db" -e DB_USERNAME=coolify -e DB_PASSWORD="$pw" -e DB_DATABASE=coolify \
    -e REDIS_HOST="${P}_redis" -e REDIS_PASSWORD="$pw" \
    -e PUSHER_APP_ID=test -e PUSHER_APP_KEY=test -e PUSHER_APP_SECRET=test "$NEU" >/dev/null
  status=starting
  i=0
  while [ "$i" -lt 60 ]; do
    status=$(docker inspect -f '{{.State.Health.Status}}' "${P}_app" 2>/dev/null || echo fehlt)
    [ "$status" = healthy ] && break
    [ "$status" = unhealthy ] && break
    i=$((i + 1)); sleep 5
  done
  antwort=$(docker exec "${P}_app" curl -s http://127.0.0.1:8080/api/health || true)
  if [ "$status" = healthy ] && [ "$antwort" = OK ]; then
    ok "Coolify healthy, /api/health = OK"
  else
    nok "Coolify Start: Status $status, /api/health = $antwort"
    docker logs "${P}_app" 2>&1 | tail -30
  fi
fi

# 8. Trivy HIGH/CRITICAL mit Fix. Fuer OS Pakete steht statt des Targets (enthaelt den
#    Abbildnamen) die Klasse, damit gleiche Befunde beider Abbilder vergleichbar sind.
#    Ein gescheiterter Scan oder einer ohne OS Ergebnis zaehlt als Fehler, nicht als 0.
TV="$(mktemp -d)"
befunde() {
  # $1 Abbild, $2 Ausgabedatei: SCAN|<klasse> je Ergebnis, sonst Ziel|Paket|CVE
  $TRIVY image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --format template \
    --template '{{range .}}{{$t := .Target}}{{if eq (print .Class) "os-pkgs"}}{{$t = "os"}}{{end}}SCAN|{{.Class}}{{"\n"}}{{range .Vulnerabilities}}{{$t}}|{{.PkgName}}|{{.VulnerabilityID}}{{"\n"}}{{end}}{{end}}' \
    "$1" > "$2.roh" || return 1
  grep -q '^SCAN|os-pkgs$' "$2.roh" || return 1
  grep '|' "$2.roh" | grep -v '^SCAN|' | sort -u > "$2" || true
}
if [ "${SKIP_TRIVY:-0}" != "1" ]; then
  if befunde "$ORIG" "$TV/alt" && befunde "$NEU" "$TV/neu"; then
    na=$(wc -l < "$TV/alt" | tr -d ' ')
    nn=$(wc -l < "$TV/neu" | tr -d ' ')
    echo "  Trivy HIGH/CRITICAL fixable: offiziell $na, abgeleitet $nn"
    sed 's/^/  /' "$TV/neu"
    if grep -qE '^usr/(bin/mc|local/bin/cloudflared)\|' "$TV/neu"; then nok "Trivy Befunde in mc oder cloudflared"; else ok "Trivy: 0 Befunde in mc und cloudflared"; fi
    zusatz=$(comm -13 "$TV/alt" "$TV/neu" | tr '\n' ' ')
    if [ -n "$zusatz" ]; then nok "Trivy Befunde, die das offizielle Abbild nicht hat: $zusatz"; else ok "Trivy: keine zusaetzlichen Befunde"; fi
    if [ "${TRIVY_STRICT:-0}" = "1" ]; then
      if [ "$nn" -eq 0 ]; then ok "Trivy streng: 0 Befunde im ganzen Abbild"; else nok "Trivy streng: $nn Befunde"; fi
    fi
  else
    nok "Trivy Scan fehlgeschlagen oder ohne OS Ergebnis"
  fi
fi
rm -rf "$TV"

if [ "$fehler" -ne 0 ]; then
  echo "Pruefung fehlgeschlagen"
  exit 1
fi
echo "Pruefung bestanden"
