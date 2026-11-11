# CMakeLists.txt — hwprobe (sonda de hardware, docs/14 §9).
# ¡SIN COMPILAR! Validar en el PC:
#   source tools/env-devpc.sh
#   cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake -B tools/hwprobe/build tools/hwprobe
#   cmake --build tools/hwprobe/build      # -> hwprobe.vpk
# Ejecutar con `tools/netlog-listen.sh 9999` abierto en la laptop.
cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED CMAKE_TOOLCHAIN_FILE AND DEFINED ENV{VITASDK})
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VITASDK}/share/vita.toolchain.cmake"
        CACHE PATH "toolchain file")
endif()

project(hwprobe C)
include("${VITASDK}/share/vita.cmake" REQUIRED)

set(NETLOG_IP "192.168.1.108" CACHE STRING "IP del receptor de logs UDP")
set(NETLOG_PORT "9999" CACHE STRING "Puerto del receptor de logs UDP")
set(VITA_TITLEID "VHWP00001")
# Pasar -DEXTENDED_MEMORY=ON para repetir E-H4/E-H5 con ATTRIBUTE2=12.
option(EXTENDED_MEMORY "mksfoex -d ATTRIBUTE2=12 (memoria ampliada)" OFF)

set(MODULES_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../modules)
set(APP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../vita-app/src)

add_executable(${PROJECT_NAME}
    src/hwprobe.c
    ${APP_DIR}/netlog.c
    ${MODULES_DIR}/net-udp/impl-c/net_udp.c
)
target_include_directories(${PROJECT_NAME} PRIVATE
    ${MODULES_DIR}/net-udp/include
    ${APP_DIR}
)
target_compile_definitions(${PROJECT_NAME} PRIVATE
    NETLOG_IP="${NETLOG_IP}" NETLOG_PORT=${NETLOG_PORT})
target_link_libraries(${PROJECT_NAME} PRIVATE
    SceNet_stub SceNetCtl_stub SceSysmodule_stub SceLibKernel_stub
    ScePower_stub SceSysmem_stub m)

# Memoria ampliada (E-H5): VITA_MKSFOEX_FLAGS lo lee vita_create_vpk. Es el
# mecanismo habitual de los ejemplos de VitaSDK; VERIFICAR en el PC que
# vita.cmake lo usa en esta versión (grep VITA_MKSFOEX_FLAGS $VITASDK/share/vita.cmake).
if(EXTENDED_MEMORY)
    set(VITA_MKSFOEX_FLAGS "${VITA_MKSFOEX_FLAGS} -d ATTRIBUTE2=12")
endif()

vita_create_self(${PROJECT_NAME}.self ${PROJECT_NAME})
vita_create_vpk(${PROJECT_NAME}.vpk ${VITA_TITLEID} ${PROJECT_NAME}.self
    VERSION "01.00" NAME "Vita HW Probe")
