#!/usr/bin/env bash
# run_host_tests.sh — ejecuta las pruebas de host de ros2_vita (godot/test/project/runner.gd).
# ¡SIN EJECUTAR!: necesita un Godot 4.8 de HOST compilado con el módulo (puerta G1, docs/18 §7):
#   cd <godot4-vita> && scons platform=linuxbsd target=editor custom_modules=<repo>/godot \
#        x11=no wayland=no vulkan=no opengl3=no
#   godot/test/run_host_tests.sh <godot4-vita>/bin/godot.linuxbsd.editor.x86_64
set -euo pipefail
GODOT="${1:?uso: $0 /ruta/al/godot}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$GODOT" --headless --path "$REPO/godot/test/project" --script res://runner.gd -- \
    "fixtures=$REPO/modules/msg-schema/tests/fixtures"
