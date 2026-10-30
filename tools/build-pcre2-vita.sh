#!/usr/bin/env bash
# build-pcre2-vita.sh — compila PCRE2 (solo la variante de 32 bits) para la Vita y
# la instala en el VitaSDK. Solo en el PC (necesita VitaSDK y cmake).
#
# Por qué: el port godot4-vita compila con builtin_pcre2=False (platform/vita/detect.py)
# y el loader enlaza `pcre2-32`, pero vitasdk/packages NO tiene paquete de pcre2
# (vdpm pcre2 → 404). Se usa la misma versión que trae Godot (thirdparty/README.md).
#
# Uso:  source tools/env-devpc.sh && tools/build-pcre2-vita.sh
# Salida: $VITASDK/arm-vita-eabi/lib/libpcre2-32.a + include/pcre2.h
set -euo pipefail

VER="${PCRE2_VER:-10.47}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$REPO/toolchains/pcre2"            # gitignorado (toolchains/)
# Si no se cargó el entorno del PC, se carga aquí (VitaSDK + cmake de toolchains/).
# shellcheck disable=SC1091
[[ -n "${VITASDK:-}" ]] || source "$REPO/tools/env-devpc.sh" >/dev/null
[[ -n "${VITASDK:-}" ]] || { echo "VITASDK no definido (source tools/env-devpc.sh)"; exit 1; }

mkdir -p "$WORK"
TAR="$WORK/pcre2-$VER.tar.bz2"
[[ -f "$TAR" ]] || curl -fL -o "$TAR" \
    "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$VER/pcre2-$VER.tar.bz2"
[[ -d "$WORK/pcre2-$VER" ]] || tar -C "$WORK" -xjf "$TAR"

# SIN PIC: la enlaza estática el eboot del loader y vita-elf-create no acepta
# relocaciones GOT ("Invalid relocation type 25"); el .so la importa vía loader.
# Solo libpcre2-32 (Godot usa la API _32), estática, sin JIT (la Vita no deja
# mapear memoria ejecutable al homebrew) y sin las herramientas de línea de órdenes.
rm -rf "$WORK/build"
cmake -S "$WORK/pcre2-$VER" -B "$WORK/build" \
    -DCMAKE_TOOLCHAIN_FILE="$VITASDK/share/vita.toolchain.cmake" \
    -DCMAKE_INSTALL_PREFIX="$VITASDK/arm-vita-eabi" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DPCRE2_BUILD_PCRE2_8=OFF -DPCRE2_BUILD_PCRE2_16=OFF -DPCRE2_BUILD_PCRE2_32=ON \
    -DPCRE2_SUPPORT_JIT=OFF -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF
cmake --build "$WORK/build" -j"$(nproc)"
cmake --install "$WORK/build"
ls -la "$VITASDK/arm-vita-eabi/lib/libpcre2-32.a"
