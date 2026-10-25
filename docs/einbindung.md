# Einbindung auf newserver (Plan, nicht ausgefuehrt)

Stand 25.10.2026, gelesen ohne Aenderung auf newserver:

- Coolify 4.5.0, Helper 1.0.18, Registry `docker.io` (`instance_settings.docker_registry_url`)
- Auto Update an, `auto_update_frequency = 59 0 * * *`, Update Pruefung `0 * * * *`, Sicherung vor Update an
- `/data/coolify/source/docker-compose.custom.yml` ueberschreibt bereits `postgres` mit `ghcr.io/amadudl/postgres-ohne-gosu:15.19-alpine`
- `/data/coolify/source/docker-compose.prod.yml` Zeile 9 bis 10: Dienst `coolify`, `image: "${REGISTRY_URL:-docker.io}/coollabsio/coolify:${LATEST_IMAGE:-latest}"`
- `/data/coolify/source/.env`: `LATEST_IMAGE=4.5.0`, `COOLIFY_VERSION=4.5.0`, `REGISTRY_URL=docker.io`
- `/root/.docker/config.json` fehlt, der Server zieht GHCR Abbilder also anonym

## Voraussetzungen

1. Workflow aktiviert (siehe README) und mindestens ein gruener Lauf, `ghcr.io/amadudl/coolify-ohne-cve-public:4.5.0` und `:latest` vorhanden.
2. Das GHCR Paket `coolify-ohne-cve` ist **oeffentlich**. Pakete aus einem privaten Repo sind zuerst privat;
   ohne Umstellung (GitHub, Package settings, Change visibility, Public) scheitert der anonyme Pull und damit jedes
   Coolify Update. Pruefen ohne Zugangsdaten:
   `DOCKER_CONFIG=$(mktemp -d) docker manifest inspect ghcr.io/amadudl/coolify-ohne-cve-public:4.5.0 >/dev/null && echo ok`
3. Das Abbild auf VM claude erneut mit `test.sh` gegen das offizielle pruefen (Pipeline hat das schon getan).

## Wie LATEST_IMAGE in custom.yml aufgeloest wird

`upgrade.sh` (Stand 25.10.2026; Coolify laedt es vor jedem Update neu von
`https://cdn.coollabs.io/coolify/upgrade.sh`, Zeilennummern koennen sich aendern):

- Zeile 5: `LATEST_IMAGE=${1:-latest}`; Coolify (`app/Actions/Server/UpdateCoolify.php`, `update()`) ruft
  `bash /data/coolify/source/upgrade.sh <neue version> <helper version> <registry>` auf, beim Auto Update genauso.
- Zeile 132 bis 138: `docker-compose.custom.yml` wird an die Compose Dateien angehaengt.
- Zeile 148: `REGISTRY_URL=... LATEST_IMAGE=${LATEST_IMAGE} docker compose --env-file .env ... config --images`;
  die Umgebung hat in Compose Vorrang vor `--env-file`, also wird `${LATEST_IMAGE}` in custom.yml zur Zielversion.
- Zeile 264 bis 277: jedes dieser Abbilder wird gezogen, ein Fehlschlag bricht das Update ab (laufende Container bleiben unberuehrt).
- Zeile 282 bis 283: erst danach `LATEST_IMAGE` und `COOLIFY_VERSION` in `.env`.
- Zeile 303 und 346: der Neustart im Helper laeuft mit `LATEST_IMAGE=<zielversion> docker compose ... up -d`.

Lokal nachgestellt mit den Compose Dateien von newserver (Argument 4.5.1, `.env` mit 4.4.9):
`config --images` liefert `ghcr.io/amadudl/coolify-ohne-cve-public:4.5.1`; ohne Umgebung kommt der Wert aus `.env`.
Ergebnis: der Override folgt immer der Version, auf die Coolify gerade aktualisiert.

Zeitfenster: Coolify sieht eine neue Version erst bei der stuendlichen Pruefung, das Update laeuft um 00:59.
Die Pipeline prueft alle 15 Minuten und braucht etwa 10 Minuten, der Tag steht also vor dem Update bereit.
Fehlt er doch, bricht nur dieses naechtliche Update ab, Coolify laeuft auf der alten Version weiter.

## Sicherung vor der Umstellung

```sh
TS=$(date -u +%Y%m%dT%H%M%SZ)
B=/root/coolify-backups/vor-tk119-coolify-$TS
mkdir -p "$B"
docker exec coolify-db pg_dump -U coolify -d coolify -Fc > "$B/coolify.dump"
cp -a /data/coolify/source "$B/source"          # inkl. .env und docker-compose.custom.yml
docker tag coollabsio/coolify:4.5.0 coollabsio/coolify:4.5.0-vor-tk119
docker inspect coolify > "$B/coolify-inspect.json"
```

## Umstellung

1. `docker-compose.custom.yml` um den Dienst `coolify` ergaenzen (Kommentar mit Ticket, Quelle, Rueckweg):

   ```yaml
   services:
     postgres:
       image: ghcr.io/amadudl/postgres-ohne-gosu:15.19-alpine
     coolify:
       image: "ghcr.io/amadudl/coolify-ohne-cve-public:${LATEST_IMAGE:-latest}"
   ```

2. Pruefen, was gezogen wuerde (nur lesend):

   ```sh
   cd /data/coolify/source
   LATEST_IMAGE=4.5.0 docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml \
     -f docker-compose.custom.yml config --images
   ```

   Erwartet: `ghcr.io/amadudl/coolify-ohne-cve-public:4.5.0`, `ghcr.io/amadudl/postgres-ohne-gosu:15.19-alpine`, `redis:7-alpine`.

3. Ueber den offiziellen Weg neu starten (gleiche Argumente wie das letzte Update):

   ```sh
   bash /data/coolify/source/upgrade.sh 4.5.0 1.0.18 docker.io
   ```

4. Nachher: `docker inspect -f '{{.Config.Image}} {{.State.Health.Status}}' coolify` zeigt
   `ghcr.io/amadudl/coolify-ohne-cve-public:4.5.0 healthy`; Coolify UI erreichbar (HTTP 200), Server erreichbar,
   eine S3 Sicherung von Hand ausloesen; laufendes Abbild mit Trivy 0.76.1 scannen (erwartet 0 HIGH/CRITICAL mit Fix).

## Rueckweg

1. Den Block `coolify:` aus `/data/coolify/source/docker-compose.custom.yml` entfernen
   (oder die Sicherung `$B/source/docker-compose.custom.yml` zurueckkopieren).
2. `bash /data/coolify/source/upgrade.sh 4.5.0 1.0.18 docker.io` (Version und Helper der laufenden Instanz).
   Ist Docker Hub nicht erreichbar: `docker tag coollabsio/coolify:4.5.0-vor-tk119 coollabsio/coolify:4.5.0` vorher.
3. Datenbank nur bei Bedarf: `docker exec -i coolify-db pg_restore -U coolify -d coolify --clean --if-exists < "$B/coolify.dump"`.
   Das abgeleitete Abbild aendert weder Schema noch Daten, ein Restore sollte nicht noetig sein.
