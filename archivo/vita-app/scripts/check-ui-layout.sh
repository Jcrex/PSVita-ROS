#!/usr/bin/env bash
# check-ui-layout.sh — verificación EN HOST de la UI declarativa (sin VitaSDK):
# regenera src/ui_layout.h desde ui/layout.json y comprueba que el header
# generado compila como C99 estricto (gcc -fsyntax-only). Es lo único del
# renderizado verificable en la laptop (ADR 0005): el dibujado real (ui.c,
# vita2d) se valida en el PC / en hardware.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node "$APP_DIR/scripts/gen-ui-header.mjs"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/tu.c" <<'EOF'
#include "ui_types.h"
#include "ui_layout.h"
int main(void)
{
    /* referenciar los datos para que -Wall no proteste por no-uso */
    return (int)(UI_NUM_WIDGETS > 0u && UI_WIDGETS[0].escala > 0.0f && UI_FONDO != 0u);
}
EOF
gcc -std=c99 -Wall -Wextra -Werror -fsyntax-only -I"$APP_DIR/src" "$TMP/tu.c"

echo "[check-ui-layout] OK: ui_layout.h regenerado y compila (host, C99 -Wall -Wextra -Werror)"
