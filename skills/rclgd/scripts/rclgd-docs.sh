#!/usr/bin/env bash
# rclgd-docs.sh — documentarse sobre rclgd desde cualquier máquina con git.
#
# Clona (superficial) el repositorio oficial y da acceso rápido a TODA su
# documentación: la web de readthedocs se genera de estos mismos ficheros
# (docs/*.rst + rclgd/doc_classes/*.xml), así que funciona aunque
# rclgd.readthedocs.io no sea accesible.
#
#   rclgd-docs.sh sync [rama]      clona/actualiza (por defecto: jazzy)
#   rclgd-docs.sh ramas            ramas remotas con fecha y último commit
#   rclgd-docs.sh indice           páginas de docs/ y clases disponibles
#   rclgd-docs.sh leer <x>         una página (p. ej. tutorials/basic_usage) o una clase (RosNode)
#   rclgd-docs.sh buscar <regex>   busca en docs, referencia de clases, tests y plantilla
#   rclgd-docs.sh ejemplos <regex> busca solo en los tests GDScript (código que funciona)
#   rclgd-docs.sh cambios [n]      primeras n líneas del CHANGELOG (por defecto 60)
#   rclgd-docs.sh api <dir>        regenera la referencia Markdown (xml_to_md.py)
#   rclgd-docs.sh version          rama, commit, versión de rclgd y de Godot fijada
#   rclgd-docs.sh web              URLs oficiales
#
# Variables: RCLGD_SRC (dir del clon; por defecto ~/.cache/rclgd-src),
#            RCLGD_URL (por defecto https://github.com/Ozuba/rclgd.git).
set -euo pipefail

SRC="${RCLGD_SRC:-$HOME/.cache/rclgd-src}"
URL="${RCLGD_URL:-https://github.com/Ozuba/rclgd.git}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_src() {
    if [[ ! -d "$SRC/.git" ]]; then
        echo "No hay clon en $SRC. Ejecuta primero: $0 sync [rama]" >&2
        exit 1
    fi
}

cmd="${1:-}"; shift || true
case "$cmd" in
    sync)
        branch="${1:-jazzy}"
        if [[ -d "$SRC/.git" ]]; then
            git -C "$SRC" fetch --depth 1 origin "$branch"
            git -C "$SRC" checkout -q -B "$branch" FETCH_HEAD
        else
            git clone --depth 1 --branch "$branch" "$URL" "$SRC"
        fi
        echo "OK: $SRC en $branch @ $(git -C "$SRC" rev-parse --short HEAD)"
        ;;
    ramas)
        git ls-remote --heads "$URL" | awk '{sub("refs/heads/","",$2); print $2"\t"substr($1,1,7)}'
        ;;
    indice)
        need_src
        echo "== Páginas (docs/) =="
        (cd "$SRC/docs" && find getting_started tutorials concepts -name '*.rst' | sort)
        echo "== Clases (rclgd/doc_classes/) =="
        (cd "$SRC/rclgd/doc_classes" && ls *.xml | sed 's/\.xml$//')
        echo "== Tests GDScript (ejemplos ejecutables) =="
        (cd "$SRC/rclgd/test/project/tests" && ls)
        ;;
    leer)
        need_src
        x="${1:?falta la página o la clase}"
        if [[ -f "$SRC/docs/$x.rst" ]]; then
            cat "$SRC/docs/$x.rst"
        elif [[ -f "$SRC/rclgd/doc_classes/$x.xml" ]]; then
            tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
            python3 -I "$HERE/xml_to_md.py" "$SRC/rclgd/doc_classes" "$tmp" >/dev/null
            cat "$tmp/$x.md"
        else
            echo "No existe docs/$x.rst ni la clase $x. Usa: $0 indice" >&2; exit 1
        fi
        ;;
    buscar)
        need_src
        cd "$SRC" && grep -rnI -E "${1:?falta el patrón}" docs rclgd/doc_classes \
            rclgd/test/project rclgd_cli/rclgd_cli/template \
            --include='*.rst' --include='*.xml' --include='*.gd' --include='*.godot' | head -200
        ;;
    ejemplos)
        need_src
        cd "$SRC/rclgd/test/project/tests" && grep -rnI -E -B2 -A8 "${1:?falta el patrón}" . | head -300
        ;;
    cambios)
        need_src
        head -n "${1:-60}" "$SRC/rclgd/CHANGELOG.rst"
        ;;
    api)
        need_src
        out="${1:?falta el directorio de salida}"
        ref="$(git -C "$SRC" rev-parse --abbrev-ref HEAD)@$(git -C "$SRC" rev-parse --short HEAD)"
        python3 -I "$HERE/xml_to_md.py" "$SRC/rclgd/doc_classes" "$out" --ref "$ref"
        ;;
    version)
        need_src
        echo "rama:   $(git -C "$SRC" rev-parse --abbrev-ref HEAD)"
        echo "commit: $(git -C "$SRC" log -1 --format='%h %ad %s' --date=short)"
        grep -E '^(major|minor|patch) ' "$SRC/docs/version.py" | tr '\n' ' '; echo
        grep -m1 'set(GODOT_VERSION' "$SRC/rclgd/CMakeLists.txt"
        ;;
    web)
        cat <<'URLS'
Docs (readthedocs):  https://rclgd.readthedocs.io/en/latest/index.html
Fuente de las docs:  https://github.com/Ozuba/rclgd/tree/rolling/docs  (main/jazzy tienen las mismas)
Referencia de clases: https://github.com/Ozuba/rclgd/tree/rolling/rclgd/doc_classes
Taller ROSCon:       https://github.com/Ozuba/roomba_ws
Ejemplo completo:    https://github.com/Ozuba/turtlesim_rclgd
URLS
        ;;
    *)
        sed -n '2,22p' "$0"; exit 2 ;;
esac
