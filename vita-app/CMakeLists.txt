# CMakeLists.txt — app "Vita ROS2 Hello" (Fase 1).
#
# SE COMPILA EN EL PC (CachyOS) con VitaSDK:
#
#   source ~/.bashrc   # VITASDK=/usr/local/vitasdk exportado
#   cd vita-app
#   # 1) compilar microxrcedds_client para la Vita (una vez):
#   ./scripts/build-xrce-client-vita.sh
#   # 2) compilar la app (impl C o Rust de los módulos duales):
#   cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake \
#         -DVITA_IMPL=c -B build && cmake --build build
#   # -> build/vita-ros2-hello.vpk
#
# La skill `vita-build-package` automatiza esto.

cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED CMAKE_TOOLCHAIN_FILE AND DEFINED ENV{VITASDK})
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VITASDK}/share/vita.toolchain.cmake"
        CACHE PATH "toolchain file")
endif()

project(vita-ros2-hello C)
include("${VITASDK}/share/vita.cmake" REQUIRED)

set(VITA_IMPL "c" CACHE STRING "Implementación de los módulos duales: c | rust")
set(VITA_APP_NAME "Vita ROS2 Teleop")
set(VITA_TITLEID "VROS00001")   # 9 caracteres exactos, único por app
set(VITA_VERSION "03.00")       # 03 = Objetivos 3/4 (modo VIZ 3D, ADR 0007)

# IPs por defecto de la Fase 1 (agente y netlog en la laptop, red WiFi).
set(AGENT_IP "192.168.1.108" CACHE STRING "IP del micro-ROS Agent")
set(AGENT_PORT "8888" CACHE STRING "Puerto UDP del agente")
set(NETLOG_IP "192.168.1.108" CACHE STRING "IP del receptor de logs UDP")
set(NETLOG_PORT "9999" CACHE STRING "Puerto del receptor de logs UDP")

set(MODULES_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../modules)

# microxrcedds_client + microcdr cross-compilados (script en scripts/).
set(XRCE_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/third_party/xrce-vita
    CACHE PATH "prefix de instalación de microxrcedds_client para la Vita")

add_executable(${PROJECT_NAME}
    src/main.c
    src/uxr_glue.c
    src/netlog.c
    src/ui.c
    src/teleop.c
    src/config.c
    src/config_ui.c
    src/viz/camera.c
    src/viz/viz.c
)

target_include_directories(${PROJECT_NAME} PRIVATE
    ${MODULES_DIR}/mem-pool/include
    ${MODULES_DIR}/net-udp/include
    ${MODULES_DIR}/microros-transport/include
    ${XRCE_PREFIX}/include
)

target_compile_definitions(${PROJECT_NAME} PRIVATE
    AGENT_IP="${AGENT_IP}"
    AGENT_PORT=${AGENT_PORT}
    NETLOG_IP="${NETLOG_IP}"
    NETLOG_PORT=${NETLOG_PORT}
)

# ---------------------------------------------------------------------
# Selección de implementación de los módulos duales
# ---------------------------------------------------------------------
if(VITA_IMPL STREQUAL "rust")
    # Un solo staticlib con TODOS los módulos Rust (crate paraguas).
    set(RUST_DIR ${CMAKE_CURRENT_SOURCE_DIR}/rust-modules)
    set(CARGO_TARGET armv7-sony-vita-newlibeabihf)
    set(RUST_LIB ${RUST_DIR}/target/${CARGO_TARGET}/release/libvita_modules_rust.a)
    add_custom_command(
        OUTPUT ${RUST_LIB}
        COMMAND cargo +nightly rustc --release --crate-type staticlib
                -Zbuild-std=std,panic_abort --target ${CARGO_TARGET}
        WORKING_DIRECTORY ${RUST_DIR}
        COMMENT "cargo build (vita_modules_rust -> staticlib armv7 Vita)"
        VERBATIM
    )
    add_custom_target(rust_modules_build DEPENDS ${RUST_LIB})
    add_dependencies(${PROJECT_NAME} rust_modules_build)
    target_link_libraries(${PROJECT_NAME} PRIVATE ${RUST_LIB})
else()
    target_sources(${PROJECT_NAME} PRIVATE
        ${MODULES_DIR}/mem-pool/impl-c/mem_pool.c
        ${MODULES_DIR}/net-udp/impl-c/net_udp.c
        ${MODULES_DIR}/microros-transport/impl-c/microros_transport.c
    )
endif()

# ---------------------------------------------------------------------
# Enlace: micro-ROS + stubs del SO de la Vita
# ---------------------------------------------------------------------
target_link_libraries(${PROJECT_NAME} PRIVATE
    ${XRCE_PREFIX}/lib/libmicroxrcedds_client.a
    ${XRCE_PREFIX}/lib/libmicrocdr.a
    # Gráficos: vitaGL y su séquito (ADR 0007 sustituyó a vita2d/ScePgf).
    # El set exacto de libs viene del Makefile de los samples oficiales
    # (auditoria/vitaGL/samples/rotating_cube) — no quitar ninguna:
    # vitashark/SceShaccCgExt/taihen compilan los shaders en runtime y
    # mathneon acelera la matemática. Se instalan con:
    #   ./vdpm vitaGL libpng zlib vitashark SceShaccCgExt taihen libmathneon
    # (¡el paquete es libmathneon, NO mathneon — verificar archivos!)
    vitaGL
    stdc++
    mathneon
    vitashark
    SceShaccCgExt
    taihen_stub
    SceShaccCg_stub
    SceKernelDmacMgr_stub
    SceDisplay_stub
    SceGxm_stub
    SceCommonDialog_stub
    SceAppMgr_stub
    m
    SceNet_stub
    SceNetCtl_stub
    SceSysmodule_stub
    SceCtrl_stub
    SceLibKernel_stub
)

# ---------------------------------------------------------------------
# Empaquetado .vpk (cadena vita-elf-create -> make-fself -> mksfoex ->
# pack-vpk encapsulada por las macros de vita.cmake; ADR 0004)
# ---------------------------------------------------------------------
vita_create_self(${PROJECT_NAME}.self ${PROJECT_NAME})
vita_create_vpk(${PROJECT_NAME}.vpk ${VITA_TITLEID} ${PROJECT_NAME}.self
    VERSION ${VITA_VERSION}
    NAME ${VITA_APP_NAME}
)
