#!/bin/sh
# Hebt Go Module auf eine Mindestversion an (Argumente: modul@version ...).
# Neuere Versionen im Modulgraph bleiben stehen, es wird nie zurueckgesetzt.
# Danach go mod tidy und, falls das Projekt vendort, go mod vendor.
# Jeder Fehler bricht ab. Ein Modul, das nicht im Modulgraph steht, wird gemeldet und
# uebersprungen; scripts/check-modules.sh prueft danach das fertige Binary.
set -eu

# Modulgraph einmal vollstaendig lesen; Fehler (Netz, Proxy, go.mod) brechen hier ab,
# statt ein Modul faelschlich als "nicht vorhanden" zu werten.
graph=$(go list -mod=mod -m -f '{{.Path}} {{.Version}}' all)

for spec in "$@"; do
  mod=${spec%@*}
  want=${spec#*@}
  have=$(printf '%s\n' "$graph" | awk -v m="$mod" '$1 == m { print $2 }')
  if [ -z "$have" ]; then
    echo "$mod: nicht im Modulgraph, uebersprungen"
    continue
  fi
  lowest=$(printf '%s\n%s\n' "$have" "$want" | sort -V | head -n 1)
  if [ "$have" != "$want" ] && [ "$lowest" = "$have" ]; then
    go get "$mod@$want"
    echo "$mod: $have -> $want"
  else
    echo "$mod: $have bleibt"
  fi
done

go mod tidy
if [ -d vendor ]; then
  go mod vendor
fi
