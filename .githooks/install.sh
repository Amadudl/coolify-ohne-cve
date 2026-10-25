#!/bin/sh
# Macht die versionierten Hooks scharf (einmalig pro Clone).
cd "$(git rev-parse --show-toplevel)" || exit 1
git config core.hooksPath .githooks
# Git fuehrt auf Linux/macOS nur ausfuehrbare Hooks aus.
chmod +x .githooks/pre-commit .githooks/pre-push .githooks/*.sh .githooks/lib/*.sh 2>/dev/null || true
echo "✓ core.hooksPath = .githooks (pre-commit: Geheimnisse, Zeilenenden, Projektpruefungen; pre-push: Claude-Review)"
if ! command -v claude >/dev/null 2>&1; then
  echo "  Hinweis: 'claude' nicht im PATH — das Review vor dem Push wird bis zur Installation uebersprungen."
fi
