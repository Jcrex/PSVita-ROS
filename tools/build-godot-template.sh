#!/usr/bin/env bash
# build-godot-template.sh — plantilla de exportación de godot4-vita (Godot 4.8-dev7)
# con el módulo `ros2_vita` compilado dentro.
#
# ¡SIN VERIFICAR! (docs/18, puertas G1-G3). Solo en el PC de desarrollo (Linux/WSL,
# VitaSDK, SCons, CMake). Sigue la receta oficial platform/vita/tools/build_release_template.sh
# del propio port, añadiendo: parche del loader, módulo ros2_vita y comprobación de imports.
#
# Uso:
#   tools/build-godot-template.sh --dry-run
#   VITAGL_ROOT=/ruta/vitagl-parcheado tools/build-godot-template.sh [salida]
#
# Variables:
#   VITAGL_ROOT     (obligatoria) VitaGL parcheado: contiene libvitaGL.a y source/vitaGL.h
#                   (ver platform/vita/vitagl/README.md del port)
#   GODOT_VITA_REF  commit/rama del port; por defecto el estudiado (d1a5f29, 2026-10-27)
#   GODOT_WORK      carpeta de trabajo (por defecto toolchains/godot4-vita, gitignorada)
#   RUST_PIC_LIB    opcional: libvita_modules_rust.a construida con tools/build-rust-pic.sh
set -euo pipefail

VITASDK_='\$VITASDK'
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${GODOT_WORK:-$REPO/toolchains/godot4-vita}"
REF="${GODOT_VITA_REF:-d1a5f29}"
OUT="${1:-$WORK/out}"
URL="${GODOT_VITA_URL:-https://github.com/WolffsRoom/godot4-vita.git}"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && { DRY=1; OUT="$WORK/out"; }

run() { echo "+ $*"; [[ $DRY -eq 1 ]] || "$@"; }

if [[ $DRY -eq 0 ]]; then
    [[ -n "${VITASDK:-}" ]] || { echo "VITASDK no definido (source tools/env-devpc.sh)"; exit 1; }
    [[ -n "${VITAGL_ROOT:-}" && -f "$VITAGL_ROOT/libvitaGL.a" ]] \
        || { echo "VITAGL_ROOT debe contener libvitaGL.a (VitaGL parcheado del port)"; exit 1; }
    command -v python3 >/dev/null && python3 -m SCons --version >/dev/null 2>&1 \
        || { echo "falta SCons (python3 -m pip install scons)"; exit 1; }
fi

echo "== 1. Clonar godot4-vita @ $REF =="
run git clone "$URL" "$WORK/engine"
run git -C "$WORK/engine" checkout "$REF"

echo "== 2. Parche del loader: imports de red y helpers que piden los módulos duales =="
run git -C "$WORK/engine" apply --check "$REPO/godot/loader-patches/0001-ros2-vita-imports.patch"
run git -C "$WORK/engine" apply "$REPO/godot/loader-patches/0001-ros2-vita-imports.patch"

echo "== 3. Motor + módulo ros2_vita (≈1–2 h) =="
EXTRA=()
[[ -n "${RUST_PIC_LIB:-}" ]] && EXTRA+=("ros2_vita_rust_lib=$RUST_PIC_LIB")
( cd "$WORK/engine" 2>/dev/null || true
  run python3 -m SCons platform=vita arch=arm32 target=template_release optimize=size \
      disable_path_overrides=no vita_shared=yes vita_gxm3d=yes vita_gl_root="${VITAGL_ROOT:-/ruta/vitagl}" \
      custom_modules="$REPO/godot" "${EXTRA[@]+"${EXTRA[@]}"}" -j"$(nproc)" )

echo "== 4. Comprobar que todo lo que pide el .so lo resuelve el loader =="
run mkdir -p "$OUT"
run cp "$WORK/engine/bin/libgodot_gxm3d.so" "$OUT/libgodot.so"
run "${VITASDK:-$VITASDK_}/bin/arm-vita-eabi-strip" --strip-unneeded "$OUT/libgodot.so"
# verify_runtime.py comprueba relocaciones permitidas (ABS32/GLOB_DAT/JUMP_SLOT/RELATIVE)
# e imports contra default_dynlib.c; si falla con "Imports missing", ver docs/18 §4.2.
run python3 "$WORK/engine/platform/vita/tools/verify_runtime.py" "$OUT/libgodot.so" --report "$OUT/runtime-validation.json"

echo "== 5. Loader + plantilla (vita_release.zip) =="
run cmake -S "$WORK/engine/platform/vita/loader" -B "$OUT/loader" \
    -DVITA_RUNTIME="$OUT/libgodot.so" -DVITA_GAME_DATA="$WORK/engine/platform/vita/tests/mesh3d" \
    -DVITA_GL_ROOT="${VITAGL_ROOT:-/ruta/vitagl}" -DVITA_GXM3D=ON -DVITA_TITLEID=GDVT00001 \
    -DVITA_RUNTIME_BUILD_ID="ros2vita-$REF" \
    -DVITA_BOOT_ANIMATION="$WORK/engine/platform/vita/loader/boot_assets/custom_splash_960x544.dat"
run cmake --build "$OUT/loader" -j"$(nproc)"
run python3 "$WORK/engine/platform/vita/tools/make_editor_template.py" --rgba4444 \
    "$OUT/loader/godot_loader.vpk" "$OUT/vita_release.zip"
echo "Hecho: $OUT/vita_release.zip  → usarlo como 'Custom Template' en Project > Export > PS Vita"
