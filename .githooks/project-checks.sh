#!/bin/sh
# Projektpruefungen fuer den pre-commit Hook (coolify-ohne-cve): Shell Syntax,
# Workflow Patch passt zu workflow/build.yml.
set -e
cd "$(git rev-parse --show-toplevel)"
sh -n test.sh
sh -n scripts/raise-modules.sh
if [ -f workflow/aktivieren.patch ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  (cd "$tmp" && git init -q && git apply "$OLDPWD/workflow/aktivieren.patch" && cmp -s .github/workflows/build.yml "$OLDPWD/workflow/build.yml") \
    || { echo "workflow/aktivieren.patch passt nicht zu workflow/build.yml"; exit 1; }
fi
