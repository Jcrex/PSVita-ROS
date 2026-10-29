#!/usr/bin/env bash
# build-c-pic.sh — compila las implementaciones C de TODOS los módulos duales como
# código PIC para la Vita y las junta en libvita_modules_c_pic.a (puerta G2, docs/18 §3).
#
# Para qué: el módulo ros2_vita vive dentro de libgodot.so, un .so PIC que el loader
# de godot4-vita reubica al cargar. Todo lo que entre ahí debe ser PIC y sus símbolos
# externos deben estar en la tabla del loader (tools/check-vita-imports.py).
# En G3 el propio SCons del motor compila los .c que use el módulo con sus flags;
# esta biblioteca sirve para comprobar ANTES (G2) que compilan e importan lo correcto.
#
# Flags = los de platform/vita/detect.py de godot4-vita (template_release, optimize=size).
# Solo en el PC (necesita VitaSDK: source tools/env-devpc.sh).
#
# Uso: tools/build-c-pic.sh [carpeta_salida]   (por defecto toolchains/pic)
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${VITASDK:?source tools/env-devpc.sh}"
OUT="${1:-$REPO/toolchains/pic}"
CC="$VITASDK/bin/arm-vita-eabi-gcc"
AR="$VITASDK/bin/arm-vita-eabi-ar"

CFLAGS=(-Os -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -ftree-vectorize
        -fno-optimize-sibling-calls -fPIC -Wall -Wextra -std=c11)
INC=()
for d in "$REPO"/modules/*/include; do INC+=(-I "$d"); done

mkdir -p "$OUT/obj-c"
rm -f "$OUT"/obj-c/*.o "$OUT/libvita_modules_c_pic.a"
for src in "$REPO"/modules/*/impl-c/*.c; do
    obj="$OUT/obj-c/$(basename "${src%.c}").o"
    echo "CC $src"
    "$CC" "${CFLAGS[@]}" "${INC[@]}" -c "$src" -o "$obj"
done
"$AR" rcs "$OUT/libvita_modules_c_pic.a" "$OUT"/obj-c/*.o
echo "Hecho: $OUT/libvita_modules_c_pic.a"
