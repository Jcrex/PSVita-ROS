#!/usr/bin/env bash
# Test: sync-to-devpc.sh debe copiar el repo a un destino local cuando
# se le pasa un destino rsync local (sin SMB/SSH), respetando .gitignore-ish excludes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$(mktemp -d)"
trap 'rm -rf "$DEST"' EXIT

# Modo test: DEST_OVERRIDE fuerza destino local y DRY_RUN=0 ejecuta de verdad.
DRY_RUN=0 DEST_OVERRIDE="$DEST" "$SCRIPT_DIR/sync-to-devpc.sh"

# Debe haber copiado README.md y docs, pero NO .git, .venv ni .claude
test -f "$DEST/README.md" || { echo "FALLO: README.md no copiado"; exit 1; }
test -d "$DEST/docs" || { echo "FALLO: docs/ no copiado"; exit 1; }
test ! -d "$DEST/.git" || { echo "FALLO: .git no debía copiarse"; exit 1; }
test ! -d "$DEST/.claude" || { echo "FALLO: .claude no debía copiarse"; exit 1; }
echo "OK: sync test passed"
