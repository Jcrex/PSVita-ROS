#!/usr/bin/env bash
# build-vita-template.sh — compila el export template de Godot para la
# Vita CON el módulo microros dentro (docs/12). SOLO EN EL PC (VitaSDK).
#
# Uso:
#   ./build-vita-template.sh [c|rust]     # defecto: c
#
# Requiere: VITASDK exportado, scons, zip, y el fork godot-vita
# (GODOT_VITA_SRC o la ruta por defecto de abajo).
#
# El engine (scons) deja bin/vita_template/ con eboot.bin + module/ +
# sce_sys/ (ver platform/vita/SCsub del fork); eso, zipeado, ES el
# template que el exportador busca como vita_release.zip en
# ~/.local/share/godot/templates/3.5.rc5/.
set -euo pipefail

IMPL="${1:-c}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FORK="${GODOT_VITA_SRC:-$HOME/Proyectos/Godot/godot-vita-3.5-rc5-vita1}"
TEMPLATES_DIR="${GODOT_TEMPLATES_DIR:-$HOME/.local/share/godot/templates/3.5.rc5}"

[ -n "${VITASDK:-}" ] || { echo "ERROR: VITASDK no exportado"; exit 1; }
[ -d "$FORK/platform/vita" ] || {
    echo "ERROR: fork godot-vita no encontrado en $FORK"
    echo "       (exporta GODOT_VITA_SRC con la ruta correcta)"
    exit 1
}
case "$IMPL" in c|rust) ;; *) echo "ERROR: impl '$IMPL' (usa c|rust)"; exit 1;; esac

# 1) Dependencias cross-compiladas (XRCE v2.4.3 + microcdr)
if [ ! -f "$REPO/vita-app/third_party/xrce-vita/lib/libmicroxrcedds_client.a" ]; then
    echo "== third_party ausente: compilando microxrcedds_client v2.4.3 =="
    (cd "$REPO/vita-app" && ./scripts/build-xrce-client-vita.sh)
fi

# 2) Variante Rust: staticlib paraguas primero (mismo comando que el
#    CMakeLists de vita-app)
if [ "$IMPL" = "rust" ]; then
    echo "== cargo build (vita_modules_rust -> staticlib armv7 Vita) =="
    (cd "$REPO/vita-app/rust-modules" && cargo +nightly rustc --release \
        --crate-type staticlib -Zbuild-std=std,panic_abort \
        --target armv7-sony-vita-newlibeabihf)
fi

# 2.4) Stubs de cabeceras que el VitaSDK no trae pero código stock de Godot
#      incluye (ver cada .h para el porqué). Se copian al include del SDK si
#      no están ya.
STUB_INC="$VITASDK/arm-vita-eabi/include"
for stub in "$REPO"/godot/vitasdk-stubs/*.h; do
    [ -e "$stub" ] || continue
    dst="$STUB_INC/$(basename "$stub")"
    if [ ! -f "$dst" ]; then
        cp "$stub" "$dst"
        echo "== stub $(basename "$stub"): instalado en el VitaSDK =="
    fi
done

# 2.5) Parches al fork (se aplican sobre el árbol de godot-vita, que va sin
#      git). Idempotente: si ya está aplicado (patch --dry-run --reverse OK)
#      se salta. Ver godot/patches/*.patch para el porqué de cada uno.
for patch in "$REPO"/godot/patches/*.patch; do
    [ -e "$patch" ] || continue
    name="$(basename "$patch")"
    if patch -d "$FORK" -p1 --dry-run --reverse --force <"$patch" >/dev/null 2>&1; then
        echo "== patch $name: ya aplicado, se salta =="
    elif patch -d "$FORK" -p1 --forward <"$patch" >/dev/null 2>&1; then
        echo "== patch $name: aplicado =="
    else
        echo "ERROR: no se pudo aplicar $name (¿fork con versión distinta?)"; exit 1
    fi
done

# 3) Engine + módulo
# El paso Copy("bin/vita_template", ...) de platform/vita/SCsub falla en
# rebuilds si el directorio ya existe ("File exists"). Se limpia el empaquetado
# previo (no los .o, para que el rebuild siga siendo incremental).
rm -rf "$FORK/bin/vita_template" "$FORK/bin/eboot.bin" \
    "$FORK/bin/vita_release_stripped" "$FORK/bin/vita_release.velf"
echo "== scons platform=vita (custom_modules, microros_impl=$IMPL) =="
(cd "$FORK" && scons platform=vita target=release \
    custom_modules="$REPO/godot/modules" microros_impl="$IMPL" -j"$(nproc)")

# 4) Empaquetar e instalar como template local (backup del original)
OUT="$REPO/godot/build"
mkdir -p "$OUT" "$TEMPLATES_DIR"
rm -f "$OUT/vita_release.zip"
(cd "$FORK/bin/vita_template" && zip -r -q "$OUT/vita_release.zip" .)
if [ -f "$TEMPLATES_DIR/vita_release.zip" ] && \
   [ ! -f "$TEMPLATES_DIR/vita_release.zip.orig" ]; then
    cp "$TEMPLATES_DIR/vita_release.zip" "$TEMPLATES_DIR/vita_release.zip.orig"
fi
cp "$OUT/vita_release.zip" "$TEMPLATES_DIR/vita_release.zip"

echo "OK: template (impl=$IMPL) instalado en $TEMPLATES_DIR/vita_release.zip"
echo "Siguiente: editor Godot > Proyecto > Exportar > PlayStation Vita -> .vpk"
