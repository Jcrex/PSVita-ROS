#!/usr/bin/env bash
# run_host_tests.sh — ejecuta las pruebas de host de ros2_vita (godot/test/project/runner.gd).
# Verde en G1 (2026-10-29, PC). Necesita un Godot 4.8 de HOST compilado con el módulo (docs/18 §7):
#   godot4-vita @ d1a5f29 clonado en toolchains/godot4-vita/engine (la ruta de build-godot-template.sh)
#   cd <godot4-vita> && scons -j14 platform=linuxbsd target=editor custom_modules=<repo>/godot \
#        x11=no wayland=no vulkan=no opengl3=no
#   godot/test/run_host_tests.sh <godot4-vita>/bin/godot.linuxbsd.editor.x86_64
set -euo pipefail
GODOT="${1:?uso: $0 /ruta/al/godot}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$GODOT" --headless --path "$REPO/godot/test/project" --script res://runner.gd -- \
    "fixtures=$REPO/modules/msg-schema/tests/fixtures"
