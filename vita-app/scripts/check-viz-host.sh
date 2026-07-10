#!/usr/bin/env bash
# check-viz-host.sh — verificación EN HOST de la parte testeable del
# mini-rviz (Etapa B3+): hoy la cámara orbital (src/viz/camera.c, lógica
# pura sin headers de la Vita). El dibujo GL (viz.c, ui.c) NO se puede
# verificar aquí: se valida en hardware. Cuando exista el loader VBM
# (E1) su round-trip se añade a esta batería o a check-vbm.sh.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

gcc -std=c99 -Wall -Wextra -Werror -I"$APP_DIR/src" \
    "$APP_DIR/src/viz/camera.c" "$APP_DIR/tests/camera_test.c" \
    -lm -o "$TMP/camera_test"

"$TMP/camera_test"

echo "[check-viz-host] OK: camara orbital verificada en host"
