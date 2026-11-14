#!/usr/bin/env bash
# check-teleop.sh — verificación EN HOST del mapeo mandos -> Twist del
# Objetivo 2 (sin VitaSDK): compila src/teleop.c + tests/teleop_test.c con
# el gcc del host y corre la batería. teleop.c es lógica pura (sin headers
# de la Vita), así que lo que pasa aquí es exactamente lo que corre en la
# consola; main.c solo hace el puente SceCtrlData -> teleop_entrada.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

gcc -std=c99 -Wall -Wextra -Werror -I"$APP_DIR/src" \
    "$APP_DIR/src/teleop.c" "$APP_DIR/tests/teleop_test.c" \
    -lm -o "$TMP/teleop_test"

"$TMP/teleop_test"

echo "[check-teleop] OK: mapeo mandos->Twist verificado en host"
