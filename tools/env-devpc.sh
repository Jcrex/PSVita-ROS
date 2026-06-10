# Entorno de desarrollo del PC CachyOS — toolchains locales del proyecto
# Uso:  source tools/env-devpc.sh   (bash/zsh)
#
# Todo vive en toolchains/ (gitignorado): VitaSDK, rustup/cargo y cmake portable.
# No toca el perfil global del shell; cargarlo solo cuando se trabaje en el proyecto.

_repo="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

export VITASDK="$_repo/toolchains/vitasdk"
export RUSTUP_HOME="$_repo/toolchains/rustup"
export CARGO_HOME="$_repo/toolchains/cargo"
export PATH="$VITASDK/bin:$CARGO_HOME/bin:$_repo/toolchains/cmake/bin:$PATH"

echo "Entorno PSVita-ROS cargado:"
echo "  VITASDK = $VITASDK"
echo "  rustc   = $(rustc --version 2>/dev/null || echo 'NO ENCONTRADO')"
echo "  cmake   = $(cmake --version 2>/dev/null | head -1 || echo 'NO ENCONTRADO')"
unset _repo
