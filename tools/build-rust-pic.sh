#!/usr/bin/env bash
# build-rust-pic.sh — libvita_modules_rust.a en modo PIC y SIN std, para enlazarla dentro de
# libgodot.so (módulo ros2_vita con ros2_vita_rust_lib=...). Verificado en G2 (2026-10-29, PC; docs/18 §3)
#
# Por qué es distinto del build de la app C (vita-app/CMakeLists.txt):
#  - El runtime de godot4-vita es un .so PIC que el loader reubica: solo admite
#    relocaciones R_ARM_ABS32/GLOB_DAT/JUMP_SLOT/RELATIVE (verify_runtime.py). El target
#    Rust usa relocation_model=static por defecto => hay que forzar `pic`.
#  - -Zbuild-std=core (sin std): los módulos son no_std; así no se arrastran pthread/TLS
#    (el loader solo trae stubs mínimos de TLS) ni más imports de libc.
#  - --target-dir propio (toolchains/pic/rust-target): con el target/ de siempre, este build
#    PIC SOBRESCRIBIRÍA el libvita_modules_rust.a estático que enlaza vita-app (misma ruta).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${VITASDK:?source tools/env-devpc.sh}"
cd "$REPO/vita-app/rust-modules"
TARGET_DIR="${RUST_PIC_TARGET_DIR:-$REPO/toolchains/pic/rust-target}"
# `export` para que cargo (y el `core` de -Zbuild-std) reciba el flag. Antes iba como
# `RUSTFLAGS=... \` seguido de otra asignación: eso solo crea variables del shell, NO las
# pasa a cargo, y el staticlib salía sin PIC (MOVW/MOVT_ABS; lo destapó G3, 2026-10-30).
export RUSTFLAGS="${RUSTFLAGS:-} -C relocation-model=pic"
cargo +nightly rustc --release --crate-type staticlib --target-dir "$TARGET_DIR" \
    -Zbuild-std=core --target armv7-sony-vita-newlibeabihf
LIB="$TARGET_DIR/armv7-sony-vita-newlibeabihf/release/libvita_modules_rust.a"
# Comprobación: código PIC no lleva relocaciones absolutas MOVW/MOVT.
NABS=$("$VITASDK/bin/arm-vita-eabi-readelf" -rW "$LIB" | grep -c "MOVW_ABS\|MOVT_ABS" || true)
[[ "$NABS" == 0 ]] || { echo "ERROR: $LIB tiene $NABS relocaciones MOVW/MOVT_ABS (no es PIC)"; exit 1; }
echo "Hecho: $LIB (0 relocaciones MOVW/MOVT_ABS)"
echo "Siguiente: tools/check-vita-imports.py --dynlib <godot4-vita>/platform/vita/loader/default_dynlib.c --nm \$VITASDK/bin/arm-vita-eabi-nm $LIB"
