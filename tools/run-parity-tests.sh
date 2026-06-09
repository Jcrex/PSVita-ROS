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
cd "$REPO_ROOT" # los flags por módulo usan rutas relativas al repo

RUST_IMAGE="rust:1-slim"

cargo_build() {
    # $1 = directorio impl-rust del módulo
    local dir="$1"
    # `cargo rustc --crate-type staticlib`: produce el .a estilo C aquí (y
    # solo aquí); los Cargo.toml declaran rlib para poder componer crates.
    if command -v cargo >/dev/null 2>&1; then
        (cd "$dir" && cargo rustc --release --crate-type staticlib)
    else
        # Se monta el REPO entero (no solo el crate): las dependencias de
        # ruta entre módulos (../../net-udp/impl-rust) deben ser visibles.
        local rel="${dir#"$REPO_ROOT"/}"
        docker run --rm -u "$(id -u):$(id -g)" \
            -e CARGO_HOME=/tmp/cargo \
            -v "$REPO_ROOT":/work -w "/work/$rel" "$RUST_IMAGE" \
            cargo rustc --release --crate-type staticlib
    fi
}

run_module() {
    local mod_dir="$1"
    local name
    name="$(basename "$mod_dir")"
    local test_src="$mod_dir/tests/parity_test.c"
    [[ -f "$test_src" ]] || { echo ">> $name: sin parity_test.c, omitido"; return; }

    # Flags extra por módulo (rutas relativas al repo), en archivos opcionales:
    #  - tests/host_common_flags: para ambos builds (p. ej. -I de otro módulo)
    #  - tests/host_c_only:       solo para el build C (p. ej. fuentes .c de
    #    módulos dependidos; en el build Rust esos símbolos ya vienen dentro
    #    del staticlib del crate)
    local extra_flags=() c_only=()
    if [[ -f "$mod_dir/tests/host_common_flags" ]]; then
        # shellcheck disable=SC2207
        extra_flags=($(cat "$mod_dir/tests/host_common_flags"))
    fi
    if [[ -f "$mod_dir/tests/host_c_only" ]]; then
        # shellcheck disable=SC2207
        c_only=($(cat "$mod_dir/tests/host_c_only"))
    fi

    echo "=================================================="
    echo ">> Módulo: $name"

    # --- Implementación C ---
    local bin_c="$BUILD_DIR/$name-parity-c"
    gcc -std=c11 -Wall -Wextra -Werror -g \
        -I "$mod_dir/include" -DIMPL_NAME='"c"' \
        "$test_src" "$mod_dir"/impl-c/*.c \
        "${c_only[@]+"${c_only[@]}"}" \
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
