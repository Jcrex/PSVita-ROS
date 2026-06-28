#!/usr/bin/env bash
# build-xrce-client-vita.sh — compila microcdr + microxrcedds_client como
# bibliotecas estáticas armv7 para la PS Vita usando VitaSDK.
#
# SE EJECUTA EN EL PC (CachyOS), no en la laptop. Requiere:
#   - VITASDK exportado (source tools/env-devpc.sh) y arm-vita-eabi-gcc en PATH
#   - git, cmake
#
# Instala en vita-app/third_party/xrce-vita/{include,lib}.
#
# Por qué NO usamos el superbuild de eProsima (UCLIENT_SUPERBUILD=ON):
#   el ExternalProject_Add(uclient) de cmake/SuperBuild.cmake NO reenvía
#   CMAKE_TOOLCHAIN_FILE al build interno del cliente (solo lo hace para
#   microcdr). En cross-compilación eso provoca dos fallos: (a) el find_package
#   de microcdr no encuentra el paquete y (b) de encontrarlo, uclient se
#   compilaría para el HOST, no para la Vita. Por eso compilamos los dos
#   subproyectos por separado, ambos con el toolchain, encadenados con
#   CMAKE_PREFIX_PATH. (Muro documentado: era un problema del superbuild,
#   no de newlib.)
#
# Notas:
#  - microcdr v2.0.1 (la versión EXACT que exige el cliente v3.0.0).
#  - UCLIENT_PROFILE_UDP/TCP/SERIAL/DISCOVERY se apagan: nuestro transporte
#    es CUSTOM (módulo microros-transport); el cliente no debe arrastrar
#    código POSIX que newlib no tiene.
#  - *_ISOLATED_INSTALL=OFF: instalamos plano en $PREFIX (sin subcarpeta
#    nombre-versión) para que el encadenado por CMAKE_PREFIX_PATH sea directo.
#  - Si la compilación choca con algo de newlib, documentar el muro en
#    docs/02 (sección incógnita dura) antes de parchear.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PREFIX="$APP_DIR/third_party/xrce-vita"
WORK="$APP_DIR/third_party/_build"
XRCE_TAG="${XRCE_TAG:-v3.0.0}"
CDR_TAG="${CDR_TAG:-v2.0.1}"

if [[ -z "${VITASDK:-}" ]]; then
    echo "ERROR: exporta VITASDK (source tools/env-devpc.sh)" >&2
    exit 1
fi

mkdir -p "$WORK" "$PREFIX"
cd "$WORK"

if [[ ! -d Micro-CDR ]]; then
    git clone --depth 1 --branch "$CDR_TAG" \
        https://github.com/eProsima/Micro-CDR.git
fi
if [[ ! -d Micro-XRCE-DDS-Client ]]; then
    git clone --depth 1 --branch "$XRCE_TAG" \
        https://github.com/eProsima/Micro-XRCE-DDS-Client.git
fi

COMMON_ARGS=(
    -DCMAKE_TOOLCHAIN_FILE="$VITASDK/share/vita.toolchain.cmake"
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_SHARED_LIBS=OFF
)

# 1) microcdr (serialización CDR) — dependencia del cliente.
cmake -S Micro-CDR -B build-microcdr "${COMMON_ARGS[@]}" \
    -DUCDR_ISOLATED_INSTALL=OFF
cmake --build build-microcdr -j"$(nproc)"
cmake --install build-microcdr

# 2) microxrcedds_client (sin superbuild): encuentra microcdr vía $PREFIX.
cmake -S Micro-XRCE-DDS-Client -B build-uclient "${COMMON_ARGS[@]}" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DUCLIENT_SUPERBUILD=OFF \
    -DUCLIENT_ISOLATED_INSTALL=OFF \
    -DUCLIENT_PROFILE_UDP=OFF \
    -DUCLIENT_PROFILE_TCP=OFF \
    -DUCLIENT_PROFILE_SERIAL=OFF \
    -DUCLIENT_PROFILE_DISCOVERY=OFF \
    -DUCLIENT_PROFILE_CUSTOM_TRANSPORT=ON \
    -DUCLIENT_PROFILE_MULTITHREAD=OFF \
    -DUCLIENT_PROFILE_SHARED_MEMORY=OFF
cmake --build build-uclient -j"$(nproc)"
cmake --install build-uclient

echo
echo ">> Instalado en $PREFIX"
ls "$PREFIX/lib"
