#!/usr/bin/env bash
# run-parity-tests.sh — ejecuta los tests de paridad de los módulos duales
# en el HOST (laptop o PC), contra ambas implementaciones (C y Rust).
#
# Uso:
#   tools/run-parity-tests.sh             # todos los módulos
#   tools/run-parity-tests.sh mem-pool    # solo un módulo
#
# Rust: usa `cargo` local si existe; si no, cae a Docker (imagen rust:1-slim)
# para no instalar nada en la laptop (regla del proyecto).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-host"
mkdir -p "$BUILD_DIR"

RUST_IMAGE="rust:1-slim"

cargo_build() {
    # $1 = directorio impl-rust del módulo
    local dir="$1"
    if command -v cargo >/dev/null 2>&1; then
        (cd "$dir" && cargo build --release)
    else
        docker run --rm -u "$(id -u):$(id -g)" \
            -e CARGO_HOME=/tmp/cargo \
            -v "$dir":/work -w /work "$RUST_IMAGE" \
            cargo build --release
    fi
}

run_module() {
    local mod_dir="$1"
    local name
    name="$(basename "$mod_dir")"
    local test_src="$mod_dir/tests/parity_test.c"
    [[ -f "$test_src" ]] || { echo ">> $name: sin parity_test.c, omitido"; return; }

    # Flags extra de enlace por módulo (p. ej. sockets) leídos de un archivo
    # opcional tests/host_link_flags.
    local extra_flags=()
    if [[ -f "$mod_dir/tests/host_link_flags" ]]; then
        # shellcheck disable=SC2207
        extra_flags=($(cat "$mod_dir/tests/host_link_flags"))
    fi

    echo "=================================================="
    echo ">> Módulo: $name"

    # --- Implementación C ---
    local bin_c="$BUILD_DIR/$name-parity-c"
    gcc -std=c11 -Wall -Wextra -Werror -g \
        -I "$mod_dir/include" -DIMPL_NAME='"c"' \
        "$test_src" "$mod_dir"/impl-c/*.c \
        -o "$bin_c" "${extra_flags[@]+"${extra_flags[@]}"}"
    "$bin_c"

    # --- Implementación Rust ---
    local rust_dir="$mod_dir/impl-rust"
    if [[ -d "$rust_dir" ]]; then
        cargo_build "$rust_dir"
        local rust_lib
        rust_lib="$(ls "$rust_dir"/target/release/lib*.a | head -1)"
        local bin_rust="$BUILD_DIR/$name-parity-rust"
        gcc -std=c11 -Wall -Wextra -Werror -g \
            -I "$mod_dir/include" -DIMPL_NAME='"rust"' \
            "$test_src" "$rust_lib" \
            -o "$bin_rust" "${extra_flags[@]+"${extra_flags[@]}"}"
        "$bin_rust"
    else
        echo ">> $name: sin impl-rust/ (¡módulo dual incompleto!)"
        return 1
    fi
}

if [[ $# -ge 1 ]]; then
    run_module "$REPO_ROOT/modules/$1"
else
    for mod in "$REPO_ROOT"/modules/*/; do
        run_module "$mod"
    done
fi
echo "=================================================="
echo "OK: paridad verificada"
