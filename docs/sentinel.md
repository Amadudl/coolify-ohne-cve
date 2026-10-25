# Sentinel (coolify-sentinel)

Stand 25.10.2026: newserver betreibt `docker.io/coollabsio/sentinel:1.1.2`.
Trivy 0.76.1 HIGH/CRITICAL mit Fix: 1 (`brotli-libs 1.2.0-r1`, CVE-2026-111497, Fix `1.2.1-r0`).

## Wie Coolify das Abbild waehlt (Coolify 4.5.0)

- `app/Actions/Server/StartSentinel.php` Zeile 116 und 124:
  `$version = $latestVersion ?? get_latest_sentinel_version();`
  `$image = coolifyRegistryUrl().'/coollabsio/sentinel:'.$version;`
- `get_latest_sentinel_version()` (`bootstrap/helpers/shared.php` Zeile 704) liest `coolify.sentinel.version`
  aus `versions.json` im Coolify Abbild (aktuell `1.1.2`).
- `coolifyRegistryUrl()` (`bootstrap/helpers/shared.php` Zeile 4704) liefert `instance_settings.docker_registry_url`;
  die Oberflaeche erlaubt nur `docker.io` oder `ghcr.io` (`app/Livewire/Settings/Updates.php` Zeile 60).
  Der Name `coollabsio/sentinel` ist fest.
- Ein freies Abbild (`$customImage`) wird nur mit `isDev()` beachtet (StartSentinel Zeile 138 bis 141,
  `app/Livewire/Server/Sentinel.php` Zeile 130), in Produktion nicht.
- `CheckAndStartSentinelJob` und `SentinelController::updateSentinelIfOutdated` vergleichen nur die gemeldete
  Version mit `versions.json` und starten Sentinel bei Abweichung oder Ausfall mit dem obigen Abbild neu.

Ergebnis: Ohne Coolify zu patchen laesst sich kein abgeleitetes Sentinel Abbild einhaengen.
Moegliche Umwege und warum sie nicht taugen:

- Registry auf `ghcr.io` stellen: aendert auch das Helper Abbild und Updates, `ghcr.io/coollabsio/...` gehoert uns nicht.
- Lokalen Tag `docker.io/coollabsio/sentinel:1.1.2` auf dem Server mit einem eigenen Abbild ueberschreiben:
  `docker run` zieht nicht neu, solange der Tag lokal existiert, das wuerde also greifen. Es ist aber ein
  unsichtbarer Eingriff, den jede Bereinigung oder ein `docker pull` zuruecksetzt; nicht empfohlen.

## Upstream Stand

`coollabsio/sentinel:1.1.3` ist am 24.10.2026 erschienen und hat bei Trivy 0.76.1 **0** HIGH/CRITICAL mit Fix.
`versions.json` (CDN und im Abbild 4.5.0) nennt noch `1.1.2`. Sobald Coolify `sentinel.version` auf 1.1.3 hebt,
startet Coolify Sentinel von selbst neu (stuendliche Pruefung bzw. Versionsheader bei jedem Push).
Empfehlung: im Ticket als "wartet auf Coolify" fuehren.

## Nachweis abgeleitetes Abbild (lokal, nicht veroeffentlicht)

Datei `sentinel/Dockerfile`, bauen mit `docker build -t local/sentinel-gepatcht:1.1.2 sentinel`.

```Dockerfile
ARG BASE=docker.io/coollabsio/sentinel:1.1.2
FROM ${BASE}
RUN apk upgrade --no-cache brotli-libs && apk info -v brotli-libs
```

Ergebnis: `brotli-libs-1.2.1-r0`, `/app/sentinel --help` laeuft, Trivy HIGH/CRITICAL mit Fix 0.
