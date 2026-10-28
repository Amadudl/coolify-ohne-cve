# Traefik Go Jose Korrektur

TK-119, 28.10.2026: CVE-2026-116587 betrifft `github.com/go-jose/go-jose/v4`
in Traefik 3.7.16. `traefik/Dockerfile` baut den unveraenderten Upstream Commit
`af6d927c51191ae1df104aaf907793386b816c28` mit mindestens go-jose 4.1.6 neu.
Das Dashboard wird mit Upstream Tests, Typpruefung und Lint gebaut. Anschliessend
laufen die Go Jose Tests und die bestehende Pruefung der Binary Module.

Die offizielle Laufzeit bleibt unveraendert, nur `/usr/local/bin/traefik` wird ersetzt.
Die Pipeline baut auf GitHub, prueft Laufzeitkonfiguration, Version, Ping,
Dashboard und API und blockiert bei jedem behebbaren HIGH/CRITICAL Befund.
PR Laeufe veroeffentlichen nichts. Main veroeffentlicht das gepruefte Abbild als
`ghcr.io/amadudl/traefik-ohne-cve-public:3.7.16-<commit>` und `:3.7.16`.

Vor Produktion: anonymen Pull pruefen, bestehende Proxy Compose Datei sichern,
alte Image ID fuer Rollback festhalten. Nur die Image Referenz im bestehenden
Coolify Proxy Compose auf den getesteten Digest setzen, keine Ports oder
anderen Einstellungen aendern. Danach Proxy neu erstellen, bestehende HTTPS
Anwendungen und Health pruefen und exakt die laufende Image ID nachscannen.
Bei fehlender Scanabdeckung oder Fehlern bleibt TK-119 offen. Rueckweg ist die
alte Image Referenz mit der gesicherten unveraenderten Proxy Konfiguration.
