# CMakeLists.txt — módulo dual `microros-transport`.
#
# Selección de implementación en build time (docs/03-estrategia-dual-rust-cpp.md):
#   cmake -DVITA_IMPL=c    ...  -> enlaza impl-c/ (por defecto)
#   cmake -DVITA_IMPL=rust ...  -> compila impl-rust/ con cargo y enlaza el .a
#
# Build para la Vita (en el PC, con VitaSDK):
#   cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake -DVITA_IMPL=c -B build
# Build host (tests de paridad, también via tools/run-parity-tests.sh sin CMake):
#   cmake -B build && cmake --build build && ctest --test-dir build

cmake_minimum_required(VERSION 3.16)
project(microros_transport C)

set(VITA_IMPL "c" CACHE STRING "Implementación a enlazar: c | rust")

if(VITA_IMPL STREQUAL "rust")
    set(RUST_DIR ${CMAKE_CURRENT_SOURCE_DIR}/impl-rust)
    if(CMAKE_CROSSCOMPILING)
        # Target tier-3 de la Vita: requiere nightly + build-std (ADR 0003).
        set(CARGO_TARGET armv7-sony-vita-newlibeabihf)
        set(CARGO_CMD cargo +nightly rustc --release --crate-type staticlib
            -Zbuild-std=std,panic_abort --target ${CARGO_TARGET})
        set(RUST_LIB ${RUST_DIR}/target/${CARGO_TARGET}/release/libmicroros_transport_rust.a)
    else()
        set(CARGO_CMD cargo rustc --release --crate-type staticlib)
        set(RUST_LIB ${RUST_DIR}/target/release/libmicroros_transport_rust.a)
    endif()

    add_custom_command(
        OUTPUT ${RUST_LIB}
        COMMAND ${CARGO_CMD}
        WORKING_DIRECTORY ${RUST_DIR}
        COMMENT "cargo build (microros_transport_rust, ${VITA_IMPL})"
        VERBATIM
    )
    # ALL: en cross-compile el test de paridad está desactivado, así que nadie
    # consumiría este target y `cmake --build` no emitiría el .a. Con ALL el
    # módulo es construible de forma independiente para la Vita.
    add_custom_target(microros_transport_rust_build ALL DEPENDS ${RUST_LIB})

    add_library(microros_transport STATIC IMPORTED GLOBAL)
    set_target_properties(microros_transport PROPERTIES IMPORTED_LOCATION ${RUST_LIB})
    add_dependencies(microros_transport microros_transport_rust_build)
    target_include_directories(microros_transport INTERFACE include)
else()
    add_library(microros_transport STATIC impl-c/microros_transport.c)
    # impl-c/microros_transport.c incluye net_udp.h (header del módulo vecino,
    # contrato único C). Sin enlazar net-udp: solo necesitamos el header para
    # compilar; los símbolos los resuelve el binario final (la app). Mismo -I
    # que usa la paridad en host (tests/host_common_flags).
    target_include_directories(microros_transport PUBLIC
        include
        ${CMAKE_CURRENT_SOURCE_DIR}/../net-udp/include)
endif()

# Test de paridad: solo tiene sentido donde se puede ejecutar (host).
if(NOT CMAKE_CROSSCOMPILING)
    enable_testing()
    add_executable(microros_transport_parity_test tests/parity_test.c)
    target_compile_definitions(microros_transport_parity_test PRIVATE IMPL_NAME="${VITA_IMPL}")
    target_link_libraries(microros_transport_parity_test microros_transport)
    add_test(NAME microros_transport_parity COMMAND microros_transport_parity_test)
endif()
