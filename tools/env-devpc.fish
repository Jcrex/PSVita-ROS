# Entorno de desarrollo del PC CachyOS — toolchains locales del proyecto
# Uso:  source tools/env-devpc.fish   (desde la raíz del repo o con ruta absoluta)
#
# Todo vive en toolchains/ (gitignorado): VitaSDK, rustup/cargo y cmake portable.
# No toca el perfil global del shell; cargarlo solo cuando se trabaje en el proyecto.

set -l repo (dirname (dirname (realpath (status filename))))

set -gx VITASDK $repo/toolchains/vitasdk
set -gx RUSTUP_HOME $repo/toolchains/rustup
set -gx CARGO_HOME $repo/toolchains/cargo

fish_add_path -g $VITASDK/bin
fish_add_path -g $CARGO_HOME/bin
fish_add_path -g $repo/toolchains/cmake/bin

echo "Entorno PSVita-ROS cargado:"
echo "  VITASDK = $VITASDK"
echo "  rustc   = "(rustc --version 2>/dev/null; or echo 'NO ENCONTRADO')
echo "  cmake   = "(cmake --version 2>/dev/null | head -1; or echo 'NO ENCONTRADO')
