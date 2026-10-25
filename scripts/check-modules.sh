#!/bin/sh
# Prueft ein fertiges Go Binary: jedes angegebene Modul, das im Binary steckt, muss
# mindestens die genannte Version haben (Argumente: binary modul@version ...).
# Grundlage ist `go version -m`, also dieselben Build Infos, die Trivy liest.
set -eu

bin=${1:?Binary fehlt}
shift
info=$(go version -m "$bin")
echo "$info" | sed -n '1p'
fehler=0
for spec in "$@"; do
  mod=${spec%@*}
  want=${spec#*@}
  # Zeilen: "dep <modul> <version> <summe>" oder "=> <ersatz> <version> <summe>"
  have=$(printf '%s\n' "$info" | awk -v m="$mod" '$1 == "dep" && $2 == m { print $3 }')
  if [ -z "$have" ]; then
    echo "$mod: nicht im Binary"
    continue
  fi
  lowest=$(printf '%s\n%s\n' "$have" "$want" | sort -V | head -n 1)
  if [ "$have" = "$want" ] || [ "$lowest" = "$want" ]; then
    echo "$mod: $have (mindestens $want) ok"
  else
    echo "FEHLER: $mod: $have, verlangt mindestens $want"
    fehler=1
  fi
done
exit "$fehler"
