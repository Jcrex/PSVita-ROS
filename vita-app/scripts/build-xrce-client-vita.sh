#!/usr/bin/env bash
# build-xrce-client-vita.sh — compila microxrcedds_client (+ microcdr) como
# bibliotecas estáticas armv7 para la PS Vita usando VitaSDK.
#
# SE EJECUTA EN EL PC (CachyOS), no en la laptop. Requiere:
#   - VITASDK exportado (p. ej. /usr/local/vitasdk) y arm-vita-eabi-gcc en PATH
#   - git, cmake
#
# Instala en vita-app/third_party/xrce-vita/{include,lib}.
#
# Notas:
#  - Se fija la rama v3.0.x del cliente (compatible con el agente jazzy).
#  - UCLIENT_PROFILE_UDP/TCP/SERIAL/DISCOVERY se apagan: nuestro transporte
#    es CUSTOM (módulo microros-transport); el cliente no debe arrastrar
#    código POSIX que newlib no tiene.
#  - Si la compilación choca con algo de newlib, documentar el muro en
#    docs/02 (sección incógnita dura) antes de parchear.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PREFIX="$APP_DIR/third_party/xrce-vita"
WORK="$APP_DIR/third_party/_build"
XRCE_TAG="${XRCE_TAG:-v3.0.0}"

if [[ -z "${VITASDK:-}" ]]; then
    echo "ERROR: exporta VITASDK (p. ej. /usr/local/vitasdk)" >&2
    exit 1
fi

mkdir -p "$WORK" "$PREFIX"
cd "$WORK"

if [[ ! -d Micro-XRCE-DDS-Client ]]; then
    git clone --depth 1 --branch "$XRCE_TAG" \
        https://github.com/eProsima/Micro-XRCE-DDS-Client.git
fi

cmake -S Micro-XRCE-DDS-Client -B build \
    -DCMAKE_TOOLCHAIN_FILE="$VITASDK/share/vita.toolchain.cmake" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DUCLIENT_SUPERBUILD=ON \
    -DUCLIENT_PROFILE_UDP=OFF \
    -DUCLIENT_PROFILE_TCP=OFF \
    -DUCLIENT_PROFILE_SERIAL=OFF \
    -DUCLIENT_PROFILE_DISCOVERY=OFF \
    -DUCLIENT_PROFILE_CUSTOM_TRANSPORT=ON \
    -DUCLIENT_PROFILE_MULTITHREAD=OFF \
    -DUCLIENT_PROFILE_SHARED_MEMORY=OFF

cmake --build build -j"$(nproc)"
cmake --install build

echo
echo ">> Instalado en $PREFIX"
ls "$PREFIX/lib"
