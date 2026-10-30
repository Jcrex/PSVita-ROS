#!/usr/bin/env bash
# build-xrce-client-vita.sh — compila microcdr + microxrcedds_client como
# bibliotecas estáticas armv7 para la PS Vita usando VitaSDK.
#
# SE EJECUTA EN EL PC (CachyOS), no en la laptop. Requiere:
#   - VITASDK exportado (source tools/env-devpc.sh) y arm-vita-eabi-gcc en PATH
#   - git, cmake
#
# Instala en vita-app/third_party/xrce-vita/{include,lib} (xrce-vita-pic con XRCE_PIC=1,
# xrce-vita-host con XRCE_HOST=1).
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
#  - XRCE_TAG=v2.4.3: debe coincidir con la versión del AGENTE
#    (microros/micro-ros-agent:jazzy corre libmicroxrcedds_agent.so.2.4.3).
#    El cliente v3.0.0 rompe compatibilidad con agentes < v3.0.0 (release
#    note oficial de eProsima) y el agente descarta el CREATE_CLIENT en
#    silencio — causa raíz diagnosticada el 2026-07-01, ver docs/06.
#  - microcdr v2.0.1 (la versión EXACT que exige el cliente v2.4.3 también,
#    confirmado en su CMakeLists.txt: _microcdr_version=2.0.1).
#  - UCLIENT_PROFILE_UDP/TCP/SERIAL/DISCOVERY se apagan: nuestro transporte
#    es CUSTOM (módulo microros-transport); el cliente no debe arrastrar
#    código POSIX que newlib no tiene.
#  - *_ISOLATED_INSTALL=OFF: instalamos plano en $PREFIX (sin subcarpeta
#    nombre-versión) para que el encadenado por CMAKE_PREFIX_PATH sea directo.
#  - *_PIC=OFF: el código PIC (Position Independent Code) genera relocaciones
#    GOT-relativas (R_ARM_BASE_PREL, tipo 25) que vita-elf-create NO admite
#    ("Invalid relocation type 25!" al empaquetar el .vpk). El homebrew de la
#    Vita es estático/position-dependent, así que apagamos PIC en ambas libs.
#  - XRCE_PIC=1 (Godot 4, puerta G2 de docs/18): compila las MISMAS libs con PIC=ON
#    y las instala en third_party/xrce-vita-pic. Las necesita el módulo ros2_vita,
#    que vive dentro de libgodot.so (un .so PIC que reubica el loader de
#    godot4-vita). Allí la relocación 25 no molesta: no pasa por vita-elf-create,
#    sino por verify_runtime.py. La variante sin PIC (vita-app) no se toca.
#  - Si la compilación choca con algo de newlib, documentar el muro en
#    docs/02 (sección incógnita dura) antes de parchear.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
XRCE_PIC="${XRCE_PIC:-0}"
# XRCE_HOST=1: mismas versiones y perfil, pero para Linux (sin VitaSDK). Lo usan las pruebas de
# host del XrceTransport de godot/ros2_vita (puerta G5, docs/18 §8) contra un agente en docker.
XRCE_HOST="${XRCE_HOST:-0}"
if [[ "$XRCE_HOST" == 1 ]]; then
    PIC=ON; SUFFIX="-host"  # el editor de host es un ejecutable PIE: las .a deben ser PIC
elif [[ "$XRCE_PIC" == 1 ]]; then
    PIC=ON; SUFFIX="-pic"   # para libgodot.so (Godot 4)
else
    PIC=OFF; SUFFIX=""      # para el ELF estático de vita-app
fi
PREFIX="$APP_DIR/third_party/xrce-vita$SUFFIX"
WORK="$APP_DIR/third_party/_build"
XRCE_TAG="${XRCE_TAG:-v2.4.3}"
CDR_TAG="${CDR_TAG:-v2.0.1}"

if [[ "$XRCE_HOST" != 1 && -z "${VITASDK:-}" ]]; then
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

COMMON_ARGS=(-DCMAKE_INSTALL_PREFIX="$PREFIX")
if [[ "$XRCE_HOST" != 1 ]]; then
    COMMON_ARGS+=(-DCMAKE_TOOLCHAIN_FILE="$VITASDK/share/vita.toolchain.cmake")
fi
COMMON_ARGS+=(
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_SHARED_LIBS=OFF
)

# 1) microcdr (serialización CDR) — dependencia del cliente.
cmake -S Micro-CDR -B "build-microcdr$SUFFIX" "${COMMON_ARGS[@]}" \
    -DUCDR_ISOLATED_INSTALL=OFF \
    -DUCDR_PIC="$PIC"
cmake --build "build-microcdr$SUFFIX" -j"$(nproc)"
cmake --install "build-microcdr$SUFFIX"

# 2) microxrcedds_client (sin superbuild): encuentra microcdr vía $PREFIX.
cmake -S Micro-XRCE-DDS-Client -B "build-uclient$SUFFIX" "${COMMON_ARGS[@]}" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DUCLIENT_SUPERBUILD=OFF \
    -DUCLIENT_ISOLATED_INSTALL=OFF \
    -DUCLIENT_PIC="$PIC" \
    -DUCLIENT_PROFILE_UDP=OFF \
    -DUCLIENT_PROFILE_TCP=OFF \
    -DUCLIENT_PROFILE_SERIAL=OFF \
    -DUCLIENT_PROFILE_DISCOVERY=OFF \
    -DUCLIENT_PROFILE_CUSTOM_TRANSPORT=ON \
    -DUCLIENT_PROFILE_MULTITHREAD=OFF \
    -DUCLIENT_PROFILE_SHARED_MEMORY=OFF
cmake --build "build-uclient$SUFFIX" -j"$(nproc)"
cmake --install "build-uclient$SUFFIX"

echo
echo ">> Instalado en $PREFIX"
ls "$PREFIX/lib"
