#!/bin/sh
# Geheimnis-Scan ueber die gestagten Aenderungen (IEX-Labs-Hook-Kit v3).
# Nutzt gitleaks, wenn installiert; sonst eingebaute Muster.
# Falsch-Positiv in einer Zeile: Kommentar 'pragma: allowlist secret' anhaengen.
# Projektspezifische Ausnahmen (Pfad-Globs, eine pro Zeile): .githooks/secret-scan-ignore
#
# core.quotePath=false: Pfade mit Umlauten kommen als Klartext statt als
# "\303\244"-Folge in Anfuehrungszeichen (sonst greifen die Datei-Muster nicht).

# 1. Verbotene Dateien (A/C/R: neu, kopiert oder umbenannt, z.B. git mv x .env)
bad=$(git -c core.quotePath=false diff --cached --name-only --diff-filter=ACRT | grep -Ei \
  '(^|/)(\.env(\.[^/]*)?|id_(rsa|ed25519|ecdsa|dsa)|[^/]*\.(pem|key|p12|pfx|jks|keystore)|credentials\.json|service-account[^/]*\.json|key\.properties)$' \
  | grep -Evi '\.(example|sample|template|dist)$|(^|/)\.env\.(example|sample|template)' )
if [ -n "$bad" ]; then
  echo "✗ Commit blockiert: Datei mit moeglichen Geheimnissen gestaged:"
  echo "$bad" | sed 's/^/    /'
  echo "  Aus dem Index nehmen (git rm --cached <datei>) und in .gitignore eintragen."
  exit 1
fi

# 2. gitleaks, falls vorhanden
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks protect --staged --redact --no-banner || {
    echo "✗ Commit blockiert: gitleaks hat ein moegliches Geheimnis gefunden."
    echo "  Falsch-Positiv mit gitleaks: Kommentar 'gitleaks:allow' an die Zeile oder Fingerabdruck in .gitleaksignore"
    echo "  ('pragma: allowlist secret' und .githooks/secret-scan-ignore gelten nur ohne gitleaks)."
    exit 1
  }
  exit 0
fi

# 3. Eingebaute Muster auf hinzugefuegten Zeilen
PATTERNS='(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-(proj-)?[A-Za-z0-9]{32,}|sk-or-v1-[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{16,}|rk_live_[A-Za-z0-9]{16,}|whsec_[A-Za-z0-9]{16,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|GOCSPX-[A-Za-z0-9_-]{20,}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{36}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|(postgres|postgresql|mysql|mongodb(\+srv)?|redis|amqp)://[^:/@ ]+:[^@/ ]{3,}@)'

set -- ':(exclude).githooks/lib/secret-scan.sh'
IGN="$(dirname "$0")/../secret-scan-ignore"
if [ -f "$IGN" ]; then
  # Auch eine letzte Zeile ohne Zeilenende und Windows-Zeilenenden vertragen.
  while IFS= read -r g || [ -n "$g" ]; do
    g=$(printf '%s' "$g" | tr -d '\r')
    case "$g" in ''|'#'*) continue ;; esac
    # Wie in .gitignore gemeint: fuehrendes '/' = Repo-Wurzel. :(glob) ist
    # ohnehin wurzelbezogen; mit '/' wuerde git den Eintrag ablehnen.
    while :; do case "$g" in /*) g=${g#/} ;; *) break ;; esac; done
    [ -n "$g" ] || continue
    set -- "$@" ":(glob,exclude)$g"
  done < "$IGN"
fi

# --no-renames: Eine umbenannte Datei zaehlt vollstaendig als hinzugefuegt, damit
# ein Geheimnis nicht per Umbenennen (ohne geaenderte Zeile) durchrutscht.
# --text: Auch Dateien, die git als binaer einstuft (Attribut -diff/binary in
# .gitattributes, NUL-Byte, z.B. UTF-16 aus PowerShell 5.1), zeilenweise zeigen;
# sonst steht dort nur "Binary files ... differ" und kein Muster greift.
# NUL-Bytes werden entfernt (UTF-16-Text wird so zu lesbarem ASCII), LC_ALL=C
# verhindert, dass grep die Eingabe selbst als binaer verwirft.
# Der Diff landet erst in einer Datei, damit ein Fehler (z.B. ein Eintrag in
# secret-scan-ignore, den git als Pfadangabe ablehnt) den Scan nicht still abschaltet.
diffdatei=$(mktemp "${TMPDIR:-/tmp}/iex-scan.XXXXXX") || {
  echo "✗ Commit blockiert: temporaere Datei fuer den Geheimnis-Scan nicht anlegbar."
  exit 1
}
fehler=$(git -c core.quotePath=false diff --cached --text --no-color --no-ext-diff --no-textconv --no-renames -U0 -- . "$@" 2>&1 > "$diffdatei")
rc=$?
if [ $rc -ne 0 ]; then
  rm -f "$diffdatei"
  echo "✗ Commit blockiert: Geheimnis-Scan konnte die gestagten Aenderungen nicht lesen (git diff Exit $rc):"
  printf '%s\n' "$fehler" | head -5 | sed 's/^/    /'
  if [ -f "$IGN" ]; then
    echo "  Haeufige Ursache: ein Eintrag in .githooks/secret-scan-ignore, den git als Pfad ablehnt"
    echo "  (z.B. '../…' ausserhalb des Repos). Eintraege sind Globs relativ zur Repo-Wurzel, etwa fixtures/**."
  fi
  exit 1
fi
hits=$(tr -d '\000' < "$diffdatei" \
  | LC_ALL=C grep -E '^\+[^+]' \
  | LC_ALL=C grep -v 'pragma: allowlist secret' \
  | LC_ALL=C grep -E "$PATTERNS")
rm -f "$diffdatei"
if [ -n "$hits" ]; then
  echo "✗ Commit blockiert: moegliches Geheimnis in den gestagten Aenderungen:"
  echo "$hits" | sed -E 's/([A-Za-z0-9_-]{6})[A-Za-z0-9_./+=-]{8,}/\1<REDACTED>/g' | head -10 | sed 's/^/    /'
  echo "  Geheimnisse gehoeren in Umgebungsvariablen/Secret-Stores, nie ins Repo."
  echo "  Falsch-Positiv: 'pragma: allowlist secret' an die Zeile oder Pfad in .githooks/secret-scan-ignore."
  exit 1
fi
exit 0
