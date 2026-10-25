# coolify-ohne-cve

Abgeleitetes Abbild von `coollabsio/coolify` ohne die HIGH/CRITICAL Befunde, die Trivy
in den mitgelieferten Go Programmen `/usr/bin/mc` und `/usr/local/bin/cloudflared` meldet.
Ticket: TK-119.

Abbild: `ghcr.io/amadudl/coolify-ohne-cve:<coolify version>` und `:latest`
(nur linux/amd64; der Ersatzfall unten kopiert das offizielle Multi Arch Manifest).

## Was geaendert wird

Nur zwei Dateien, jeweils als eigene Schicht ueber dem unveraenderten offiziellen Abbild:

| Pfad | Offiziell (4.5.0) | Hier |
|---|---|---|
| `/usr/bin/mc` | AIStor mc RELEASE.2026-09-06, go1.26.6, x/net 0.58.0, grpc 1.82.1 | quelloffener mc aus `github.com/minio/mc` (master 77f82e1, letzter Stand, Repo archiviert), go1.27.3, x/net 0.60.0, grpc 1.83.2, compress 1.18.7, prometheus 0.311.3 |
| `/usr/local/bin/cloudflared` | Release 2026.10.3, compress 1.18.0 | Tag 2026.10.3 aus der Quelle, compress 1.18.7, gleiche Versionsangabe |

Eigentuemer und Rechte bleiben `root:root 755`. Entrypoint, Cmd, Nutzer (`www-data`),
Umgebung, Healthcheck und alle Basisschichten sind identisch, nur die Labels
`org.opencontainers.image.*` beschreiben die Herkunft dieses Abbilds.

Warum der quelloffene mc: AIStor mc ist nicht quelloffen und auch das neueste
`quay.io/minio/aistor/mc` (RELEASE.2026-09-19) ist noch mit go1.26.6 gebaut;
`dl.min.io` liefert fuer den alten mc nur noch 410. Im Coolify Container selbst wird
mc fuer Sicherungen nicht aufgerufen (Coolify fuehrt `mc` im Helper Container aus),
cloudflared dient dort als SSH ProxyCommand (`cloudflared access ssh --hostname %h`).

## Bauen und pruefen

```sh
docker build --build-arg COOLIFY_VERSION=4.5.0 -t local/coolify-ohne-cve:4.5.0 .
TRIVY_STRICT=1 sh test.sh coollabsio/coolify:4.5.0 local/coolify-ohne-cve:4.5.0
```

`test.sh` vergleicht mit dem offiziellen Abbild:

1. Entrypoint, Cmd, Nutzer, Arbeitsverzeichnis, Umgebung, Ports, Healthcheck, Plattform gleich, Labels bis auf `org.opencontainers.image.*` gleich
2. Basisschichten unveraendert, genau zwei neue Schichten
3. Pfade, Eigentuemer, Rechte gleich, beide Binaries tatsaechlich ersetzt
4. `mc --version`, `cloudflared --version` (gleiche Version wie offiziell), `php artisan --version`
5. `cloudflared access ssh --help` kennt `--hostname`
6. mc gegen einen S3 Server (`rclone serve s3`): `alias set`, `cp`, `pipe --checksum MD5`, `stat --json`, globales `--resolve`, Rueckweg mit `cmp`
7. Coolify startet mit PostgreSQL 15 und Redis 7 bis `healthy`, `/api/health` liefert `OK`
8. Trivy 0.76.1 HIGH/CRITICAL mit Fix: 0 in mc und cloudflared, kein Befund, den das offizielle Abbild nicht hat; mit `TRIVY_STRICT=1` 0 im ganzen Abbild

Schalter: `SKIP_STACK=1`, `SKIP_TRIVY=1`, `TRIVY="trivy --cache-dir ..."`, `S3_IMAGE`, `PG_IMAGE`, `REDIS_IMAGE`.

## Pipeline

`workflow/build.yml` ist der fertige GitHub Actions Workflow. Er liegt nicht unter
`.github/workflows`, weil das Token, mit dem das Repo angelegt wurde, keinen
`workflow` Scope hat. Aktivieren (mit einem Token mit `workflow` Scope oder im Web UI):

```sh
git apply workflow/aktivieren.patch   # legt .github/workflows/build.yml an
```

Ablauf: alle 15 Minuten, bei Push auf `main` und von Hand. Liest `coolify.v4.version`
aus `https://cdn.coollabs.io/coolify/versions.json`. Liegt der Tag schon gepatcht in GHCR,
passiert nichts. Sonst: bauen (Basis per Digest), `test.sh`, Trivy Bericht (blockiert nicht),
Tags `<version>` und `latest` pushen. Zugang zu GHCR nur ueber eine temporaere
`DOCKER_CONFIG` je Schritt mit `GITHUB_TOKEN` (`packages: write`), kein `docker login`; Trivy laeuft
per Digest festgelegt und ohne Zugangsdaten auf der Platte. Der Bau prueft mit `go version -m`
(`scripts/check-modules.sh`), dass die angehobenen Module wirklich im Binary stecken.

Ersatzfall: Scheitert Bau oder Test, wird `coollabsio/coolify:<version>` unveraendert
(gleicher Digest) als `ghcr.io/amadudl/coolify-ohne-cve:<version>` veroeffentlicht und der Lauf
endet rot mit Hinweis in der Zusammenfassung. So bricht das naechtliche Coolify Update nie
an einem fehlenden Tag ab. Ein Ersatz Tag wird planmaessig hoechstens stuendlich erneut gepatcht
versucht (Abstand zum letzten fehlgeschlagenen Lauf, daher `actions: read`). Ein gepatchter Tag
aus einem aelteren Stand von `main` (Label `org.opencontainers.image.revision`) wird ebenso neu
gebaut, ein fehlendes `latest` nachgezogen. Ein bereits gepatchter
Tag wird nie durch den Ersatz ueberschrieben; scheitert ein erzwungener Neubau, bleibt er stehen
und der Lauf endet rot. Ist der Zustand des Ziel Tags nicht pruefbar (Netz, Rate Limit), bricht
der Lauf ohne Veroeffentlichung ab und der naechste Lauf versucht es erneut.

## Einbindung auf dem Server

Siehe [docs/einbindung.md](docs/einbindung.md) (Sicherung, Umstellung, Rueckweg).
Sentinel: [docs/sentinel.md](docs/sentinel.md).

## Lizenzen

- `/usr/bin/mc`: MinIO Client, GNU AGPLv3 (`LICENSE` im Quellstand `github.com/minio/mc` Commit
  `77f82e18b5401a65958f1619df6ebb994634bd88`). Geaendert wird nur `go.mod`/`go.sum` (angehobene Module per
  `scripts/raise-modules.sh`), Bau nach `Dockerfile`. Wer das Abbild weitergibt (auch ein oeffentliches GHCR Paket),
  muss den vollstaendigen Quellstand dazu anbieten (AGPLv3 Abschnitt 6): Upstream Commit plus dieses Repo. Solange
  dieses Repo privat ist, erfuellt das Label `org.opencontainers.image.source` das nicht.
- `/usr/local/bin/cloudflared`: Apache License 2.0, Tag wie im offiziellen Abbild, nur `go.mod`/`go.sum` geaendert.
- Alles andere stammt unveraendert aus `coollabsio/coolify` (Apache License 2.0).
