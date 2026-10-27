#!/usr/bin/env bash
# build-rust-pic.sh — libvita_modules_rust.a en modo PIC y SIN std, para enlazarla dentro de
# libgodot.so (módulo ros2_vita con ros2_vita_rust_lib=...). ¡SIN VERIFICAR! (docs/18 §3, puerta G2)
#
# Por qué es distinto del build de la app C (vita-app/CMakeLists.txt):
#  - El runtime de godot4-vita es un .so PIC que el loader reubica: solo admite
#    relocaciones R_ARM_ABS32/GLOB_DAT/JUMP_SLOT/RELATIVE (verify_runtime.py). El target
#    Rust usa relocation_model=static por defecto => hay que forzar `pic`.
#  - -Zbuild-std=core (sin std): los módulos son no_std; así no se arrastran pthread/TLS
#    (el loader solo trae stubs mínimos de TLS) ni más imports de libc.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${VITASDK:?source tools/env-devpc.sh}"
cd "$REPO/vita-app/rust-modules"
RUSTFLAGS="${RUSTFLAGS:-} -C relocation-model=pic" \
cargo +nightly rustc --release --crate-type staticlib \
    -Zbuild-std=core --target armv7-sony-vita-newlibeabihf
LIB="$PWD/target/armv7-sony-vita-newlibeabihf/release/libvita_modules_rust.a"
echo "Hecho: $LIB"
echo "Siguiente: tools/check-vita-imports.py --dynlib <godot4-vita>/platform/vita/loader/default_dynlib.c --nm \$VITASDK/bin/arm-vita-eabi-nm $LIB"
