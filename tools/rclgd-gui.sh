#!/usr/bin/env bash
# =============================================================================
# rclgd-gui.sh — Godot 4.7.1 + rclgd (jazzy, compilado desde fuente) en un contenedor ROS 2 Jazzy,
# con la pantalla del PC (X11/XWayland + GPU). Guía completa: docs/37-guia-rclgd-gui-pc.md.
#
# El host no tiene ROS: librclgd.so necesita las librerías de /opt/ros/jazzy, así que Godot corre dentro de
# una imagen derivada de la estación (psvita-ros-station:jazzy) con lo que rclgd necesita en ejecución
# (ros_babel_fish) y los paquetes de mensajes que usa el visor y que la estación no trae (octomap, grid_map).
#
# Uso (cualquier shell; el script es bash):
#   tools/rclgd-gui.sh imagen                 construir la imagen psvita-ros-rclgd:jazzy (una vez, ~1-2 min)
#   tools/rclgd-gui.sh doctor                 comprobar pantalla, GPU, rclgd instalado e imagen
#   tools/rclgd-gui.sh puente                 crear/refrescar el proyecto puente del visor (copia, ver abajo)
#   tools/rclgd-gui.sh migrar <origen> [dest] copiar una demo con el plugin viejo de rclgd y migrarla a 3.0.0
#   tools/rclgd-gui.sh editor [proyecto]      abrir el editor Godot 4.7.1 (por defecto, el puente del visor)
#   tools/rclgd-gui.sh jugar [proyecto] [escena] [-- args]   ejecutar una escena (ventana de juego)
#   tools/rclgd-gui.sh comprobar [escena] [s]  sin pantalla: carga una escena del puente y vuelca sus displays
#   tools/rclgd-gui.sh fuente-v14             fuente de Octomap, GridMap, marcadores interactivos y profundidad
#   tools/rclgd-gui.sh godot <args...>        godot-bin con argumentos libres (p. ej. --headless ...)
#   tools/rclgd-gui.sh ros2 <args...>         `ros2 ...` en la misma imagen y red (topic list/echo/hz...)
#   tools/rclgd-gui.sh shell                  bash dentro del contenedor con ROS y rclgd cargados
#
# Variables (con valores por defecto):
#   RCLGD_WS      ~/Proyectos/rclgd-estudio/ws-jazzy     workspace donde se compiló rclgd (tiene install/)
#   PUENTE        ~/Proyectos/rclgd-estudio/visor-rclgd  proyecto puente del visor (fuera del repo)
#   ROS_DOMAIN_ID 0 (el de la estación)                   RCLGD_SHM=1  deja el transporte SHM de Fast DDS
#   RCLGD_HOME    ~/Proyectos/rclgd-estudio/.home-godot  HOME del contenedor (ajustes del editor, ~/.ros/log)
#
# Por qué un proyecto PUENTE y no godot/visor-ros directamente:
#   - visor-ros es un proyecto de godot4-vita 4.8-dev7: features "4.8" y el plugin res://addons/psvita (que no
#     existe fuera del editor de la Vita); rclgd 3.0.0 necesita además res://package.xml (clases tipadas) y su
#     rclgd.gdextension, que el proyecto del repo no tiene (ros2_vita es un módulo estático, no una extensión).
#   - El editor 4.7.1 reimporta los recursos (.import de godot/plantillas/mundo) y crea los .uid que falten: en
#     una COPIA eso no ensucia el repo. `puente` vuelve a copiar (rsync) cuando cambie el código del repo; lo que
#     edites en el puente NO vuelve al repo (llévalo a mano). Decisión de diseño de un modo rclgd permanente en
#     godot/visor-ros: pendiente (doc 37 §7).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ESTUDIO="${ESTUDIO:-$HOME/Proyectos/rclgd-estudio}"
RCLGD_WS="${RCLGD_WS:-$ESTUDIO/ws-jazzy}"
PUENTE="${PUENTE:-$ESTUDIO/visor-rclgd}"
RCLGD_HOME="${RCLGD_HOME:-$ESTUDIO/.home-godot}"
IMAGEN="${RCLGD_IMAGEN:-psvita-ros-rclgd:jazzy}"
BASE="${RCLGD_BASE:-psvita-ros-station:jazzy}"
GODOT_BIN="$RCLGD_WS/install/rclgd/lib/rclgd/godot-bin"

ROJO='\033[0;31m'; VERDE='\033[0;32m'; AMARILLO='\033[1;33m'; CIAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${VERDE}[✓]${NC} $*"; }
info() { echo -e "${CIAN}[i]${NC} $*"; }
aviso(){ echo -e "${AMARILLO}[!]${NC} $*"; }
error(){ echo -e "${ROJO}[✗]${NC} $*" >&2; }

# Paquetes de mensajes del visor (los que aparecen en godot/plantillas/visor y docker/scripts/fuente_prueba*.py).
# Van como <depend> del package.xml del puente: rclgd registra una clase tipada por cada interfaz.
PAQUETES_MSG=(std_msgs geometry_msgs sensor_msgs nav_msgs visualization_msgs diagnostic_msgs action_msgs
              vision_msgs octomap_msgs grid_map_msgs rcl_interfaces)

# --- imagen -------------------------------------------------------------------------------------------------
construir_imagen() {
    docker image inspect "$BASE" >/dev/null 2>&1 || { error "falta $BASE: docker/vita-ros.sh build"; exit 1; }
    info "construyendo $IMAGEN sobre $BASE"
    docker build -t "$IMAGEN" - <<EOF
FROM $BASE
# ros_babel_fish: rclgd la usa en ejecución (mensajes por introspección). octomap/grid_map: tipos V14 del visor.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \\
        ros-jazzy-ros-babel-fish ros-jazzy-tf2-ros ros-jazzy-rclcpp-action \\
        ros-jazzy-octomap-msgs ros-jazzy-grid-map-msgs \\
    && rm -rf /var/lib/apt/lists/*
EOF
    ok "imagen $IMAGEN lista"
}

hay_imagen() { docker image inspect "$IMAGEN" >/dev/null 2>&1; }

# --- contenedor ---------------------------------------------------------------------------------------------
# Godot corre con TU usuario (archivos del proyecto sin dueño root) y HOME propio y persistente.
# Red e IPC del host como la estación (DDS necesita la red real). Fast DDS: solo UDP por defecto, porque la
# memoria compartida entre un proceso root (estación) y uno de usuario puede descubrirse pero no entregar datos.
lanzar() {   # lanzar <-it|-i|""> <comando bash>
    local tty="$1"; shift
    hay_imagen || { error "falta la imagen $IMAGEN: tools/rclgd-gui.sh imagen"; exit 1; }
    [ -x "$GODOT_BIN" ] || { error "no encuentro $GODOT_BIN (¿RCLGD_WS? receta en skills/rclgd/references/versiones.md)"; exit 1; }
    mkdir -p "$RCLGD_HOME"
    local args=(--rm --net=host --ipc=host --user "$(id -u):$(id -g)"
        -e HOME="$RCLGD_HOME" -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
        -e ROS_AUTOMATIC_DISCOVERY_RANGE="${ROS_AUTOMATIC_DISCOVERY_RANGE:-SUBNET}"
        -e RCLGD_WS="$RCLGD_WS"
        -v "$HOME/Proyectos:$HOME/Proyectos")
    [ "${RCLGD_SHM:-0}" = "1" ] || args+=(-e FASTDDS_BUILTIN_TRANSPORTS=UDPv4)
    # Pantalla: X11 directo o XWayland (DISPLAY=:0 en KDE Wayland). Godot 4.7 usa X11 por defecto.
    if [ -n "${DISPLAY:-}" ]; then
        xhost +local: >/dev/null 2>&1 || true
        args+=(-e DISPLAY="$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix:rw)
        local xa="${XAUTHORITY:-}"
        [ -z "$xa" ] && xa=$(ls /run/user/"$(id -u)"/xauth_* 2>/dev/null | head -1 || true)
        [ -n "$xa" ] && [ -f "$xa" ] && args+=(-e XAUTHORITY=/tmp/.Xauthority -v "$xa:/tmp/.Xauthority:ro")
    fi
    # GPU: /dev/dri (Mesa) y, si existe el runtime, la NVIDIA (GL/Vulkan del driver del host).
    if [ -e /dev/dri ]; then
        args+=(--device /dev/dri)
        for g in video render; do getent group "$g" >/dev/null && args+=(--group-add "$(getent group "$g" | cut -d: -f3)"); done
    fi
    if docker info 2>/dev/null | grep -q "Runtimes:.*nvidia"; then
        args+=(--runtime nvidia -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=all)
    fi
    [ -n "$tty" ] && args+=("$tty")
    local wd="$PWD"; case "$wd" in "$HOME/Proyectos"*) ;; *) wd="$RCLGD_HOME" ;; esac
    docker run "${args[@]}" -w "$wd" "$IMAGEN" bash -c \
        "source /opt/ros/jazzy/setup.bash && source '$RCLGD_WS/install/setup.bash' && $*"
}

tty_flag() { [ -t 0 ] && [ -t 1 ] && echo "-it" || echo "-i"; }

# Cita cada argumento para pasarlo dentro de `bash -c`.
citar() { local s=""; for a in "$@"; do s+=" $(printf '%q' "$a")"; done; echo "$s"; }

# --- proyecto puente del visor ------------------------------------------------------------------------------
gdextension() {   # el de la plantilla de `ros2 rclgd create` (3.0.0): librclgd.so junto a godot-bin
    cat <<'EOF'
[configuration]

entry_symbol = "rclgd_init"
compatibility_minimum = "4.7"
reloadable = false

[libraries]
linux.editor.x86_64 = "librclgd.so"
linux.debug.x86_64 = "librclgd.so"
linux.release.x86_64 = "librclgd.so"
EOF
}

# Parches de la COPIA para rclgd (no tocan el repo). Cada uno es una diferencia de API ros2_vita/rclgd hallada
# al probar (doc 37 §6); cuando se arregle en godot/plantillas, el parche deja de aplicarse solo (no encuentra
# el texto) y se puede borrar de aquí.
#   P1  rclgd.init() es void en rclgd y Error en ros2_vita: `var err := rclgd.init(args)` no compila con rclgd
#       («Cannot get return value of call to "init()" because it returns "void"», contexto_ros.gd:16).
parchear_puente() {
    python3 - "$PUENTE/comun/ros/contexto_ros.gd" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
viejo = "\t\tvar err := rclgd.init(args)\n\t\tif err != OK:\n\t\t\treturn err\n"
nuevo = ("\t\t# [puente rclgd, doc 37 P1] rclgd.init() es void en rclgd y Error en ros2_vita\n"
         "\t\tvar err = rclgd.call(\"init\", args)\n"
         "\t\tif not rclgd.ok():\n\t\t\treturn err if err is int and err != OK else FAILED\n")
if viejo in s:
    open(p, "w").write(s.replace(viejo, nuevo)); print("[i] parche P1 aplicado a comun/ros/contexto_ros.gd")
elif "doc 37 P1" not in s:
    print("[!] P1: contexto_ros.gd ha cambiado; revisa si sigue haciendo falta")
PY
}

crear_puente() {
    command -v rsync >/dev/null || { error "falta rsync en el host"; exit 1; }
    local origen="$REPO_ROOT/godot/visor-ros"
    mkdir -p "$PUENTE/addons/rclgd/bin"
    # Copia del proyecto (sin la caché .godot, el project.godot, el preset de la Vita ni el enlace comun) …
    rsync -a --delete --exclude .godot --exclude project.godot --exclude export_presets.cfg --exclude comun \
        --exclude addons --exclude package.xml --exclude LEEME-PUENTE.txt --exclude 'comprobar_rclgd.gd*' "$origen/" "$PUENTE/"
    # … y de godot/plantillas como res://comun (lo que en el repo es el enlace visor-ros/comun -> ../plantillas).
    # Sin pruebas/: usan API solo de ros2_vita (load_schema_file, has_schema, list_types, transport loopback) y con
    # rclgd no compilan; en el editor solo meterían errores rojos (doc 37 §6).
    rsync -a --delete --delete-excluded --exclude __pycache__ --exclude pruebas "$REPO_ROOT/godot/plantillas/" "$PUENTE/comun/"
    # project.godot: el del visor con features 4.7 y sin el plugin psvita (solo existe en el editor de la Vita).
    sed -e 's/config\/features=PackedStringArray("4.8", /config\/features=PackedStringArray("4.7", /' \
        -e '/^\[editor_plugins\]/d' -e '/^enabled=PackedStringArray("res:\/\/addons\/psvita\/plugin.cfg")/d' \
        "$origen/project.godot" > "$PUENTE/project.godot"
    parchear_puente
    gdextension > "$PUENTE/addons/rclgd/bin/rclgd.gdextension"
    cp "$SCRIPT_DIR/rclgd-gui/comprobar_visor.gd" "$PUENTE/comprobar_rclgd.gd"
    mkdir -p "$PUENTE/.godot"
    echo "res://addons/rclgd/bin/rclgd.gdextension" > "$PUENTE/.godot/extension_list.cfg"
    {
        echo '<?xml version="1.0"?>'
        echo '<!-- Generado por tools/rclgd-gui.sh puente: rclgd registra una clase tipada por cada interfaz -->'
        echo '<package format="3">'
        echo '  <name>visor_rclgd</name>'
        echo '  <version>0.0.0</version>'
        echo '  <description>Proyecto puente: godot/visor-ros de PSVita-ROS con rclgd (doc 37)</description>'
        echo '  <maintainer email="noreply@example.com">PSVita-ROS</maintainer>'
        echo '  <license>MIT</license>'
        for p in "${PAQUETES_MSG[@]}"; do echo "  <depend>$p</depend>"; done
        echo '</package>'
    } > "$PUENTE/package.xml"
    cat > "$PUENTE/LEEME-PUENTE.txt" <<EOF
Proyecto puente GENERADO por tools/rclgd-gui.sh puente (repo PSVita-ROS, doc 37).
Es una COPIA de godot/visor-ros + godot/plantillas (como res://comun): lo que edites aquí NO vuelve al repo y
se pierde al volver a ejecutar «puente». Origen: $REPO_ROOT ($(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')).
EOF
    ok "puente listo en $PUENTE (copia de godot/visor-ros @ $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?'))"
}

# --- migrar una demo con el plugin de clases sombra (rclgd < 3.0.0 nativo) ------------------------------------
# Pasos de skills/rclgd/references/mensajes-y-tipos.md «Migrar un proyecto de clases sombra»: sin gen/, sin
# plugin.cfg/rclgd.gd y sin el plugin en project.godot. Se hace sobre una COPIA (los clones quedan intactos).
migrar() {
    local origen="${1:?uso: migrar <proyecto_origen> [destino]}"
    origen="$(cd "$origen" && pwd)"
    local destino="${2:-$ESTUDIO/migrados/$(basename "$origen")}"
    [ -f "$origen/project.godot" ] || { error "$origen no es un proyecto Godot"; exit 1; }
    mkdir -p "$destino"
    rsync -a --delete --exclude .godot --exclude .git "$origen/" "$destino/"
    rm -rf "$destino/addons/rclgd/gen" "$destino/addons/rclgd/plugin.cfg" "$destino/addons/rclgd/rclgd.gd" \
           "$destino/addons/rclgd/rclgd.gd.uid"
    sed -i -e 's#"res://addons/rclgd/plugin.cfg", ##; s#, "res://addons/rclgd/plugin.cfg"##; s#"res://addons/rclgd/plugin.cfg"##' \
        "$destino/project.godot"
    local ext; ext=$(cd "$destino" && find . -name '*.gdextension' -path '*rclgd*' | head -1)
    if [ -n "$ext" ]; then
        mkdir -p "$destino/.godot"; echo "res://${ext#./}" > "$destino/.godot/extension_list.cfg"
    else
        aviso "no hay rclgd.gdextension en $destino: lo creo en addons/rclgd/bin/"
        mkdir -p "$destino/addons/rclgd/bin"; gdextension > "$destino/addons/rclgd/bin/rclgd.gdextension"
        mkdir -p "$destino/.godot"; echo "res://addons/rclgd/bin/rclgd.gdextension" > "$destino/.godot/extension_list.cfg"
    fi
    # Clases tipadas: solo existen para las dependencias del package.xml. Si la demo usa RosSensorMsgs* sin declarar
    # sensor_msgs (le pasa a rclgd_sensors @ 420d4d4), sus scripts no compilan: se añaden los paquetes básicos.
    if [ ! -f "$destino/package.xml" ]; then
        aviso "sin package.xml: no habrá clases tipadas (solo RosMsg dinámico)"
    elif ! grep -qE '<(exec_|build_)?depend>[a-z_]*_msgs</' "$destino/package.xml"; then
        local deps=""; for p in std_msgs geometry_msgs sensor_msgs nav_msgs; do deps+="  <exec_depend>$p</exec_depend>\n"; done
        sed -i "s#</package>#${deps}</package>#" "$destino/package.xml"
        aviso "package.xml sin paquetes de mensajes: añadidos std/geometry/sensor/nav_msgs (clases tipadas)"
    fi
    ok "migrado en $destino"
}

# --- doctor -------------------------------------------------------------------------------------------------
doctor() {
    info "sesión: XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-?} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DISPLAY=${DISPLAY:-}"
    [ -n "${DISPLAY:-}" ] && ok "DISPLAY=$DISPLAY (X11/XWayland)" || error "sin DISPLAY: arranca desde una terminal del escritorio"
    ls /run/user/"$(id -u)"/xauth_* >/dev/null 2>&1 && ok "Xauthority: $(ls /run/user/"$(id -u)"/xauth_* | head -1)" \
        || aviso "sin /run/user/$(id -u)/xauth_*: se usa xhost +local:"
    [ -e /dev/dri ] && ok "/dev/dri presente" || aviso "sin /dev/dri"
    docker info 2>/dev/null | grep -q "Runtimes:.*nvidia" && ok "runtime NVIDIA de docker" || info "sin runtime NVIDIA (Mesa)"
    [ -x "$GODOT_BIN" ] && ok "Godot $(cat "$RCLGD_WS/install/rclgd/share/rclgd/godot_version" 2>/dev/null) en $GODOT_BIN" \
        || error "no está $GODOT_BIN"
    [ -f "$RCLGD_WS/install/rclgd/lib/rclgd/librclgd.so" ] && ok "librclgd.so instalado" || error "falta librclgd.so"
    hay_imagen && ok "imagen $IMAGEN" || aviso "falta la imagen: tools/rclgd-gui.sh imagen"
    [ -f "$PUENTE/project.godot" ] && ok "puente en $PUENTE" || aviso "sin puente: tools/rclgd-gui.sh puente"
    if hay_imagen && [ -n "${DISPLAY:-}" ]; then
        lanzar "" "command -v glxinfo >/dev/null && glxinfo -B 2>&1 | grep -E 'OpenGL renderer|direct rendering' || echo 'glxinfo no está en la imagen'" || true
    fi
}

# --- órdenes ------------------------------------------------------------------------------------------------
cmd="${1:-help}"; shift || true
case "$cmd" in
    imagen)  construir_imagen ;;
    puente)  crear_puente ;;
    migrar)  migrar "$@" ;;
    doctor)  doctor ;;
    editor)
        proyecto="$(cd "${1:-$PUENTE}" && pwd)"
        info "editor Godot 4.7.1 + rclgd en $proyecto (cierra la ventana para salir)"
        lanzar "$(tty_flag)" "\"\$RCLGD_WS/install/rclgd/lib/rclgd/godot-bin\" --editor --path$(citar "$proyecto")" ;;
    jugar)
        proyecto="$(cd "${1:-$PUENTE}" && pwd)"; shift || true
        escena=""; if [ $# -gt 0 ] && [ "$1" != "--" ]; then escena="$1"; shift; fi
        [ "${1:-}" = "--" ] && shift
        info "ejecutando ${escena:-la escena principal} de $proyecto"
        lanzar "$(tty_flag)" "\"\$RCLGD_WS/install/rclgd/lib/rclgd/godot-bin\" --path$(citar "$proyecto" $escena)$( [ $# -gt 0 ] && echo " --$(citar "$@")")" ;;
    comprobar)
        # Sin pantalla: carga una escena del puente N segundos y vuelca el estado de cada display.
        lanzar "" "\"\$RCLGD_WS/install/rclgd/lib/rclgd/godot-bin\" --headless --path$(citar "$PUENTE") --script res://comprobar_rclgd.gd --$(citar "${1:-res://main_pc.tscn}" "${2:-8}")" ;;
    fuente-v14)
        # Octomap, GridMap, marcadores interactivos e imagen de profundidad (extras V14; la estación no los tiene).
        lanzar "$(tty_flag)" "python3 -u$(citar "$SCRIPT_DIR/rclgd-gui/fuente_v14.py")" ;;
    godot)   lanzar "$(tty_flag)" "\"\$RCLGD_WS/install/rclgd/lib/rclgd/godot-bin\"$(citar "$@")" ;;
    ros2)    lanzar "$(tty_flag)" "ros2$(citar "$@")" ;;
    shell)   lanzar "-it" "exec bash" ;;
    help|-h|--help|*) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
