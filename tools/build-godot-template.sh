#!/usr/bin/env bash
# build-godot-template.sh — receta para compilar la plantilla de exportación
# de Godot-Vita 3.5 con el módulo `ros2_vita` dentro.
#
# ¡SIN VERIFICAR! (docs/12 §8, P2). Solo se puede ejecutar en el PC de
# desarrollo (VitaSDK + vdpm). Los pasos salen de la receta publicada por
# Swisha33/Vita-Template-with-network- (scons p=vita target=release tools=no).
#
# Uso:
#   tools/build-godot-template.sh --dry-run           # solo imprime los pasos
#   GODOT_VITA_REF=<commit> tools/build-godot-template.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${GODOT_WORK:-$REPO_ROOT/toolchains/godot-vita}"   # toolchains/ está en .gitignore
GODOT_VITA_URL="${GODOT_VITA_URL:-https://github.com/SonicMastr/godot-vita.git}"
GODOT_VITA_REF="${GODOT_VITA_REF:-3.x}"   # FIJAR a un commit concreto (P2)
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

run() { echo "+ $*"; [[ $DRY -eq 1 ]] || "$@"; }

if [[ $DRY -eq 0 ]]; then
    [[ -n "${VITASDK:-}" ]] || { echo "VITASDK no definido (source tools/env-devpc.sh)"; exit 1; }
    command -v scons >/dev/null || { echo "falta scons"; exit 1; }
fi

echo "== 1. Dependencias de VitaSDK (una vez) =="
run vdpm install vita-rss-libdl pvr_psp2   # "install" según el README de vdpm; versiones antiguas usan `vdpm <paquete>`. Origen: vita-packages-extra (a confirmar)

echo "== 2. Clonar godot-vita ($GODOT_VITA_REF) =="
run git clone "$GODOT_VITA_URL" "$WORK/godot"
run git -C "$WORK/godot" checkout "$GODOT_VITA_REF"

echo "== 3. Enlazar el módulo ros2_vita =="
run ln -sfn "$REPO_ROOT/godot/ros2_vita" "$WORK/godot/modules/ros2_vita"

echo "== 4. Capa ROS (staticlibs cross-compiladas del repo) =="
echo "   (compilar antes vita-app/ con -DVITA_IMPL=rust y apuntar PSVITA_ROS_LIBS)"
export PSVITA_ROS_ROOT="$REPO_ROOT"
export PSVITA_ROS_LIBS="${PSVITA_ROS_LIBS:-$REPO_ROOT/vita-app/build-rust}"

echo "== 5. SCons (≈1–2 h) =="
( cd "$WORK/godot" 2>/dev/null || true
  run scons p=vita target=release tools=no )

echo "== 6. Resultado esperado: bin/vita_release.zip (plantilla de exportación) =="
