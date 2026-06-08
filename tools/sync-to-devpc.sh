#!/usr/bin/env bash
# Sincroniza este repo al PC de desarrollo CachyOS.
#
# Uso normal (dry-run por defecto, no copia nada, solo muestra):
#   tools/sync-to-devpc.sh
# Ejecutar de verdad:
#   DRY_RUN=0 tools/sync-to-devpc.sh
#
# Destino por defecto: punto de montaje SMB del PC. Ajusta DEST_DEFAULT.
# Variables:
#   DRY_RUN=1|0        (default 1) - 1 = solo simular
#   DEST_OVERRIDE=path - fuerza un destino concreto (usado por tests)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Punto de montaje SMB del PC (CachyOS, 192.168.1.65). Ajustar a tu montaje real:
DEST_DEFAULT="/run/user/$(id -u)/gvfs/smb-share:server=192.168.1.65/ps-vita-ros2"

DRY_RUN="${DRY_RUN:-1}"
DEST="${DEST_OVERRIDE:-$DEST_DEFAULT}"

RSYNC_OPTS=(-av --delete
  --exclude '.git/'
  --exclude '.venv/'
  --exclude '__pycache__/'
  --exclude '*.pyc'
  --exclude '.pytest_cache/'
  --exclude 'build/'
)

if [[ "$DRY_RUN" == "1" ]]; then
  RSYNC_OPTS+=(--dry-run)
  echo ">> DRY-RUN (no copia). Exporta DRY_RUN=0 para sincronizar de verdad."
fi

mkdir -p "$DEST"
echo ">> Sincronizando $REPO_ROOT/ -> $DEST/"
rsync "${RSYNC_OPTS[@]}" "$REPO_ROOT/" "$DEST/"
echo ">> Listo."
