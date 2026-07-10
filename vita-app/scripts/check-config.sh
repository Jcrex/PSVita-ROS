#!/usr/bin/env bash
# check-config.sh — verificación EN HOST de la persistencia de la IP del
# agente (src/config.c, lógica pura + stdio): parse estricto, format y
# round-trip de archivo. La pantalla interactiva (config_ui.c, sceCtrl)
# NO se puede verificar aquí: se valida en hardware.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

gcc -std=c99 -Wall -Wextra -Werror -I"$APP_DIR/src" \
    "$APP_DIR/src/config.c" "$APP_DIR/tests/config_test.c" \
    -o "$TMP/config_test"

"$TMP/config_test" "$TMP"

echo "[check-config] OK: persistencia de IP verificada en host"
