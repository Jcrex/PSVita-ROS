#!/usr/bin/env bash
# vita-doctor.sh — diagnóstico del entorno de desarrollo (laptop o PC).
# Solo LEE: no instala nada. Imprime qué falta y para qué sirve.
#
# Uso: tools/vita-doctor.sh
# Salida: [OK] / [--] (falta, opcional en este rol) / [!!] (falta y es necesario)
# Código de salida: número de [!!].
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bad=0

ok()   { printf '  [OK] %-28s %s\n' "$1" "$2"; }
miss() { printf '  [--] %-28s %s\n' "$1" "$2"; }
need() { printf '  [!!] %-28s %s\n' "$1" "$2"; bad=$((bad+1)); }

have() { command -v "$1" >/dev/null 2>&1; }

echo "== Taller (laptop / host: tests de paridad, docs, web, MCP) =="
have gcc    && ok gcc "$(gcc -dumpversion)" || need gcc "tests de paridad C"
if have cargo; then ok cargo "$(cargo --version | cut -d' ' -f2)"
elif have docker; then ok "cargo (vía docker)" "rust:1-slim"
else need cargo "tests de paridad Rust (o docker)"; fi
have node   && ok node "$(node --version)" || miss node "web (Astro)"
have pnpm   && ok pnpm "$(pnpm --version)" || miss pnpm "web (corepack enable)"
have python3 && ok python3 "$(python3 --version | cut -d' ' -f2)" || miss python3 "MCP"
have docker && ok docker "agente micro-ROS y ROS2 Jazzy" || miss docker "agente micro-ROS / robotnik_dev"

echo "== PC de desarrollo (cross-compilación a la Vita) =="
if [[ -n "${VITASDK:-}" && -d "$VITASDK" ]]; then ok VITASDK "$VITASDK"
else miss VITASDK "source tools/env-devpc.sh (solo PC)"; fi
have arm-vita-eabi-gcc && ok arm-vita-eabi-gcc "$(arm-vita-eabi-gcc -dumpversion)" || miss arm-vita-eabi-gcc "VitaSDK"
have cargo-vita && ok cargo-vita "" || miss cargo-vita "cargo +nightly install cargo-vita"
if have rustup; then
    rustup toolchain list 2>/dev/null | grep -q nightly && ok "rust nightly" "" || miss "rust nightly" "-Zbuild-std (ADR 0003)"
else miss rustup "toolchain Rust del PC"; fi
have scons && ok scons "$(scons --version 2>/dev/null | grep -m1 -o 'v[0-9.]*')" || miss scons "solo para compilar Godot"
have cmake && ok cmake "$(cmake --version | head -1 | cut -d' ' -f3)" || miss cmake "vita-app"
if [[ -n "${VITASDK:-}" ]]; then
    for lib in vitaGL libvita2d; do
        find "$VITASDK/arm-vita-eabi/lib" -name "*${lib#lib}*" 2>/dev/null | grep -q . \
            && ok "$lib" "" || miss "$lib" "vdpm"
    done
fi

echo "== Artefactos del repo =="
[[ -f "$REPO_ROOT/vita-app/third_party/install/lib/libmicroxrcedds_client.a" ]] \
    && ok "cliente XRCE (ARM)" "" \
    || miss "cliente XRCE (ARM)" "vita-app/scripts/build-xrce-client-vita.sh (PC)"
ls "$REPO_ROOT"/vita-app/build*/*.vpk >/dev/null 2>&1 && ok ".vpk" "" || miss ".vpk" "PC: vita-build-package"

echo "== Godot 4 / godot4-vita (docs/18) =="
[[ -d "$REPO_ROOT/toolchains/godot4-vita/engine" ]] && ok "godot4-vita clonado" "" \
    || miss "godot4-vita clonado" "tools/build-godot-template.sh (PC)"
python3 -m SCons --version >/dev/null 2>&1 && ok "SCons (python3 -m SCons)" "" || miss "SCons" "python3 -m pip install scons"
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)' 2>/dev/null \
    && ok "Python >= 3.12" "" || miss "Python >= 3.12" "lo pide el port (BUILDING.md)"
[[ -n "${VITAGL_ROOT:-}" && -f "${VITAGL_ROOT:-}/libvitaGL.a" ]] && ok "VITAGL_ROOT (VitaGL parcheado)" "$VITAGL_ROOT" \
    || miss "VITAGL_ROOT" "VitaGL parcheado del port (platform/vita/vitagl/README.md)"
have x86_64-w64-mingw32-gcc && ok "MinGW-w64 (editor Windows, opcional)" "" || miss "MinGW-w64" "solo para el editor de Windows"

echo
if [[ $bad -eq 0 ]]; then echo "Entorno mínimo del taller: OK"; else echo "Faltan $bad herramientas necesarias"; fi
exit $bad
