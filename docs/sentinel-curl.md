# Sentinel Paketfix TK-125

Stand 26.10.2026: Sentinel 1.1.3 ist das neueste offizielle Image. Curl und
libcurl 8.22.0-r0 enthalten CVE-2026-92392, behoben ab 8.23.0-r0.
`sentinel/Dockerfile` leitet das gepatchte Image vom festgelegten offiziellen
Digest ab. Sentinel selbst und seine Laufzeitkonfiguration bleiben unverändert.

Außerhalb der Produktion bauen, Konfiguration gegen die Basis vergleichen und
mit dem genehmigten Trivy scannen. Danach per docker save/load übertragen.
Der Produktionsserver baut nichts.

Coolify 4.5.0 StartSentinel akzeptiert im Produktionsmodus kein eigenes Image;
der Startpfad benutzt die lokale Referenz docker.io/coollabsio/sentinel:1.1.3
und zieht kein Image. Deshalb wird ausschließlich diese lokale Referenz auf
das geprüfte abgeleitete Image gesetzt. Das ist kein offizielles Upstream Image.
Provenienzlabels und unveränderliche Image ID sind im Ticket dokumentiert.
Vorher die bisherige Referenz unter einem Rückfalltag erhalten.

Über StartSentinel mit unveränderter Version neu starten. Die Aktion bewahrt
Token, Mounts, Netz und Healthcheck. Keinen Entwicklungsmodus einschalten.
Anschließend Health, Pushfunktion und unveränderliche laufende Image ID prüfen
und exakt diese ID nachscannen; vor und nach dem Scan muss sie identisch sein.

Rückweg: die gesicherte ursprüngliche Image ID wieder auf die lokale offizielle
Referenz setzen und dieselbe StartSentinel Aktion ausführen. Kein Volume löschen.
Ein manuelles docker pull derselben Version ersetzt den lokalen Paketfix und
ist deshalb vor erneuter Prüfung nicht erlaubt. Eine neue offizielle Version
wird normal über Coolify übernommen und im CVE Watch erneut geprüft. Falls
Coolify künftig einen Pull im Startpfad ergänzt, ist diese Einbindung vorher
anzupassen. Die laufenden IDs, Scans und Healthbelege sind operative Ticketdaten.
