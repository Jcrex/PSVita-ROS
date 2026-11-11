#!/usr/bin/env bash
# export-vita-vpk.sh — exporta un proyecto Godot 4 a un .vpk de la Vita con el addon psvita
# de godot4-vita y nuestra plantilla (vita_release.zip con ros2_vita). Puerta G4 (docs/18 §8).
#
# Uso:  tools/export-vita-vpk.sh <dir_proyecto> [salida.vpk]
#   p. ej. tools/export-vita-vpk.sh godot/g4-smoke build/g4-smoke.vpk
#
# Por qué sobre una COPIA (docs/18 §7): el editor 4.8-dev7 reescribe project.godot, escenas y
# .godot/imported; si el proyecto se edita con el 4.7.1 de rclgd, no queremos tocar el original.
# El addon y la plantilla no se versionan en el repo (vienen de toolchains/), así que se
# inyectan en la copia: la plantilla va a la ruta por defecto del addon
# (addons/psvita/templates/vita_release.zip) y no hace falta ninguna ruta de máquina en el preset.
#
# Variables (con valores por defecto del PC):
#   GODOT4_DEV7     editor de host 4.8-dev7 (bin/godot.linuxbsd.editor.x86_64 compilado con
#                   GODOT_VERSION_STATUS=dev7; el exportador rechaza cualquier otra versión)
#   VITA_TEMPLATE   plantilla de G3 (variante C: la de hardware, docs/18 §4.5)
#   PSVITA_ADDON    addon psvita del árbol godot4-vita
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G4V="$REPO/toolchains/godot4-vita"
GODOT4_DEV7="${GODOT4_DEV7:-$G4V/engine/bin/godot.linuxbsd.editor.x86_64}"
VITA_TEMPLATE="${VITA_TEMPLATE:-$G4V/out/vita_release.zip}"
PSVITA_ADDON="${PSVITA_ADDON:-$G4V/engine/platform/vita/editor/addons/psvita}"

PROJ="$(cd "${1:?uso: $0 <dir_proyecto> [salida.vpk]}" && pwd)"
OUT="$(realpath -m "${2:-$REPO/build/$(basename "$PROJ").vpk}")"

for f in "$GODOT4_DEV7" "$VITA_TEMPLATE" "$PSVITA_ADDON/plugin.cfg" "$PROJ/project.godot" "$PROJ/export_presets.cfg"; do
    [[ -e "$f" ]] || { echo "ERROR: falta $f"; exit 1; }
done
VER="$("$GODOT4_DEV7" --version 2>/dev/null | tail -1)"
[[ "$VER" == 4.8.dev7* ]] || { echo "ERROR: $GODOT4_DEV7 es $VER; hace falta 4.8.dev7"; exit 1; }

# Copia de trabajo (se borra al salir).
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vita-export.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp -r "$PROJ/." "$WORK/"
rm -rf "$WORK/.godot"
mkdir -p "$WORK/addons"
cp -r "$PSVITA_ADDON" "$WORK/addons/psvita"
mkdir -p "$WORK/addons/psvita/templates"
cp "$VITA_TEMPLATE" "$WORK/addons/psvita/templates/vita_release.zip"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
LOG="$(dirname "$OUT")/$(basename "$OUT" .vpk)-export.log"
echo "Exportando $PROJ -> $OUT (log: $LOG)"
# 1) importar recursos (crea .godot/imported); 2) exportar con el preset "PS Vita".
"$GODOT4_DEV7" --headless --path "$WORK" --import >"$LOG" 2>&1 || true
"$GODOT4_DEV7" --headless --path "$WORK" --export-release "PS Vita" "$OUT" >>"$LOG" 2>&1 || true

if [[ ! -s "$OUT" ]]; then
    echo "ERROR: no se generó $OUT. Últimas líneas del log:"
    tail -30 "$LOG"
    exit 1
fi
echo "Hecho: $OUT ($(du -h "$OUT" | cut -f1)), sha256 $(sha256sum "$OUT" | cut -c1-16)…"
unzip -l "$OUT" | tail -n +4 | head -n -2 | awk '{print "  " $4}' | grep -v '/$' | head -40
