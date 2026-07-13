#!/usr/bin/env bash
# uninstall-godot.sh — elimina limpiamente el toolchain de Godot-Vita y TODAS
# las dependencias que build-vita-template.sh fue añadiendo, dejando el VitaSDK
# como estaba antes de empezar la migración a Godot. SOLO EN EL PC.
#
# Uso:
#   ./uninstall-godot.sh [-y] [--clean-fork]
#     -y            no preguntar, asumir "sí"
#     --clean-fork  además, borra los objetos de compilación del fork godot-vita
#                   (bin/, *.o, .sconsign.dblite) para dejarlo virgen
#
# Qué NO toca (son toolchain compartido del proyecto, los usa también vita-app):
#   - VitaSDK base, rustup/cargo, cmake portable (toolchains/)
#   - paquetes vdpm previos a Godot (libvita2d, zlib, libpng, ...)
# Lo que revierte, en orden inverso a como se instaló:
#   1) parches aplicados al fork              (patch -R)
#   2) stubs de cabecera copiados al VitaSDK  (godot/vitasdk-stubs/*.h)
#   3) paquetes vdpm de Godot                 (vdpm -u: pvr_psp2 + códecs)
#   4) template custom instalado en ~/.local/share/godot
#   5) artefactos de build del repo           (godot/build/)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FORK="${GODOT_VITA_SRC:-$HOME/Proyectos/Godot/godot-vita-3.5-rc5-vita1}"
TEMPLATES_DIR="${GODOT_TEMPLATES_DIR:-$HOME/.local/share/godot/templates/3.5.rc5}"

# Cargar entorno del PC si VITASDK no está exportado (para tener vdpm en PATH).
if [ -z "${VITASDK:-}" ] && [ -f "$REPO/tools/env-devpc.sh" ]; then
    # shellcheck disable=SC1091
    source "$REPO/tools/env-devpc.sh" >/dev/null 2>&1 || true
fi

ASSUME_YES=0; CLEAN_FORK=0
for a in "$@"; do
    case "$a" in
        -y) ASSUME_YES=1 ;;
        --clean-fork) CLEAN_FORK=1 ;;
        *) echo "ERROR: argumento desconocido '$a'"; exit 1 ;;
    esac
done

# Paquetes vdpm que instaló build-vita-template.sh / la migración (paso 3).
VDPM_PKGS=(pvr_psp2-3.9-1-arm.tar.xz libjpeg-turbo freetype libogg libvorbis libtheora opus)

echo "== Desinstalación de Godot-Vita =="
echo "  repo      : $REPO"
echo "  fork      : $FORK"
echo "  templates : $TEMPLATES_DIR"
echo "  VitaSDK   : ${VITASDK:-<no detectado>}"
echo "  paquetes vdpm a quitar: ${VDPM_PKGS[*]}"
echo "  clean-fork: $CLEAN_FORK"
if [ "$ASSUME_YES" -ne 1 ]; then
    printf "\n¿Continuar? [y/N] "; read -r ans
    case "$ans" in y|Y|s|S) ;; *) echo "Cancelado."; exit 0 ;; esac
fi

# 1) Revertir parches del fork (idempotente: si no está aplicado, se salta)
for patch in "$REPO"/godot/patches/*.patch; do
    [ -e "$patch" ] || continue
    name="$(basename "$patch")"
    if patch -d "$FORK" -p1 --dry-run --reverse --force <"$patch" >/dev/null 2>&1; then
        patch -d "$FORK" -p1 --reverse --force <"$patch" >/dev/null 2>&1 \
            && echo "  [1] patch revertido: $name"
    else
        echo "  [1] patch no aplicado (se salta): $name"
    fi
done

# 2) Quitar stubs de cabecera del VitaSDK (solo si son NUESTROS: marca interna)
if [ -n "${VITASDK:-}" ]; then
    for stub in "$REPO"/godot/vitasdk-stubs/*.h; do
        [ -e "$stub" ] || continue
        dst="$VITASDK/arm-vita-eabi/include/$(basename "$stub")"
        if [ -f "$dst" ] && grep -q '_STUB_VITA' "$dst" 2>/dev/null; then
            rm -f "$dst" && echo "  [2] stub eliminado: $(basename "$stub")"
        fi
    done
fi

# 3) Desinstalar paquetes vdpm de Godot (vdpm respeta ficheros compartidos)
if command -v vdpm >/dev/null 2>&1; then
    for pkg in "${VDPM_PKGS[@]}"; do
        vdpm -u "$pkg" 2>&1 | sed 's/^/  [3] /'
    done
else
    echo "  [3] AVISO: vdpm no está en PATH; carga tools/env-devpc.sh y reintenta"
fi

# 4) Template custom: restaurar backup .orig si existe, si no borrar
if [ -f "$TEMPLATES_DIR/vita_release.zip.orig" ]; then
    mv -f "$TEMPLATES_DIR/vita_release.zip.orig" "$TEMPLATES_DIR/vita_release.zip"
    echo "  [4] template original restaurado desde .orig"
else
    rm -f "$TEMPLATES_DIR/vita_release.zip"
    echo "  [4] template eliminado"
fi
# limpiar dirs vacíos hacia arriba (3.5.rc5 -> templates -> godot)
rmdir "$TEMPLATES_DIR" "$(dirname "$TEMPLATES_DIR")" \
      "$(dirname "$(dirname "$TEMPLATES_DIR")")" 2>/dev/null || true

# 5) Artefactos de build del repo
rm -rf "$REPO/godot/build" && echo "  [5] godot/build/ eliminado"

# 6) (opcional) dejar el fork virgen de objetos de compilación
if [ "$CLEAN_FORK" -eq 1 ] && [ -d "$FORK" ]; then
    find "$FORK" -name '*.o' -delete 2>/dev/null
    rm -rf "$FORK/bin" "$FORK/.sconsign.dblite" 2>/dev/null
    echo "  [6] objetos de build del fork limpiados (--clean-fork)"
fi

cat <<EOF

== Hecho ==
El VitaSDK vuelve a su estado pre-Godot y el template ha sido retirado.

Pasos manuales OPCIONALES (no automatizados por seguridad):
  - Herramientas de sistema instaladas para Godot, si no las usas para otra cosa:
      sudo pacman -Rns scons zip
  - Fuentes externas del engine (fuera del repo), si quieres recuperar espacio:
      rm -rf "$FORK"
      rm -rf "\$HOME/Proyectos/Godot/vita-packages-extra"
  - El toolchain base (VitaSDK, rust, cmake en toolchains/) NO se toca: lo usa
    también vita-app. No lo borres salvo que abandones todo el proyecto.
EOF
