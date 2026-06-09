# CMakeLists.txt — módulo dual `net-udp`.
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
project(net_udp C)

set(VITA_IMPL "c" CACHE STRING "Implementación a enlazar: c | rust")

if(VITA_IMPL STREQUAL "rust")
    set(RUST_DIR ${CMAKE_CURRENT_SOURCE_DIR}/impl-rust)
    if(CMAKE_CROSSCOMPILING)
        # Target tier-3 de la Vita: requiere nightly + build-std (ADR 0003).
        set(CARGO_TARGET armv7-sony-vita-newlibeabihf)
        set(CARGO_CMD cargo +nightly rustc --release --crate-type staticlib
            -Zbuild-std=std,panic_abort --target ${CARGO_TARGET})
        set(RUST_LIB ${RUST_DIR}/target/${CARGO_TARGET}/release/libnet_udp_rust.a)
    else()
        set(CARGO_CMD cargo rustc --release --crate-type staticlib)
        set(RUST_LIB ${RUST_DIR}/target/release/libnet_udp_rust.a)
    endif()

    add_custom_command(
        OUTPUT ${RUST_LIB}
        COMMAND ${CARGO_CMD}
        WORKING_DIRECTORY ${RUST_DIR}
        COMMENT "cargo build (net_udp_rust, ${VITA_IMPL})"
        VERBATIM
    )
    add_custom_target(net_udp_rust_build DEPENDS ${RUST_LIB})

    add_library(net_udp STATIC IMPORTED GLOBAL)
    set_target_properties(net_udp PROPERTIES IMPORTED_LOCATION ${RUST_LIB})
    add_dependencies(net_udp net_udp_rust_build)
    target_include_directories(net_udp INTERFACE include)
else()
    add_library(net_udp STATIC impl-c/net_udp.c)
    target_include_directories(net_udp PUBLIC include)
endif()

# Test de paridad: solo tiene sentido donde se puede ejecutar (host).
if(NOT CMAKE_CROSSCOMPILING)
    enable_testing()
    add_executable(net_udp_parity_test tests/parity_test.c)
    target_compile_definitions(net_udp_parity_test PRIVATE IMPL_NAME="${VITA_IMPL}")
    target_link_libraries(net_udp_parity_test net_udp)
    add_test(NAME net_udp_parity COMMAND net_udp_parity_test)
endif()
