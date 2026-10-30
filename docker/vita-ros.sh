#!/bin/bash
# =============================================================================
# vita-ros.sh — estación ROS 2 de PSVita-ROS (agente micro-ROS + monitor + puente Zenoh + simulación)
# Uso: docker/vita-ros.sh [comando]   (sin argumentos: ayuda). Detalle en docker/README.md.
# =============================================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
[ -f .env ] && set -a && . ./.env && set +a

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# GPU NVIDIA solo si el runtime existe (PC); en la laptop sin NVIDIA se usa el compose base.
COMPOSE=(docker compose -f docker-compose.yml)
if docker info 2>/dev/null | grep -q "Runtimes:.*nvidia"; then
    COMPOSE+=(-f docker-compose.nvidia.yml)
fi
mkdir -p "${VITA_WS_PATH:-$SCRIPT_DIR/ws}/src"

header() { echo -e "${CYAN}══ PSVita-ROS · estación ROS 2 Jazzy ══${NC}"; }

# Permiso X11 y Xauthority de KDE/Wayland (como rmf.sh de IR2134), solo para las GUI.
gui() {
    xhost +local:docker >/dev/null 2>&1 || true
    local xa
    xa=$(ls /run/user/"$(id -u)"/xauth_* 2>/dev/null | head -1)
    [ -n "$xa" ] && export XAUTHORITY="$xa"
}

up() { gui; "${COMPOSE[@]}" up -d "$@"; }

# Ejecuta un comando ROS en la estación (la levanta si hace falta).
run() {
    up station >/dev/null
    "${COMPOSE[@]}" exec station bash -lc "source /opt/ros/jazzy/setup.bash; $*"
}

ip_pc() { ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}'; }

case "${1:-help}" in
    build)   header; "${COMPOSE[@]}" build --progress=plain station ;;
    up)      header; up; echo -e "${GREEN}[✓]${NC} agente micro-ROS en UDP ${AGENT_PORT:-8888} (IP de este equipo: $(ip_pc)) y estación arriba" ;;
    agent)   header; "${COMPOSE[@]}" up -d agent; echo -e "${GREEN}[✓]${NC} solo el agente (UDP ${AGENT_PORT:-8888}, IP $(ip_pc))" ;;
    down)    header; "${COMPOSE[@]}" down ;;
    shell)   up station >/dev/null; "${COMPOSE[@]}" exec station bash ;;
    logs)    "${COMPOSE[@]}" logs -f "${2:-agent}" ;;
    monitor) run "python3 /scripts/vita_monitor.py ${2:-}" ;;
    topics)  run "ros2 topic list -t" ;;
    echo)    run "ros2 topic echo ${2:-/vita_hello}" ;;
    sim)
        # turtlesim: ligero, sin GPU. La tortuga obedece al /cmd_vel de la Vita y turtle_odom.py
        # publica su pose como /odom (lo que espera la HMI de la Vita, godot/g6-hmi).
        run "python3 /scripts/turtle_odom.py & ODOM_PID=\$!; ros2 run turtlesim turtlesim_node --ros-args -r /turtle1/cmd_vel:=/cmd_vel; kill \$ODOM_PID" ;;
    sim-tb3)
        # TurtleBot3 Burger en Gazebo Harmonic (mundo vacío). Ver README: tipo de /cmd_vel.
        run "ros2 launch turtlebot3_gazebo empty_world.launch.py" ;;
    rviz)    run "rviz2" ;;
    rqt)     run "rqt_graph" ;;
    teleop)  run "ros2 run teleop_twist_keyboard teleop_twist_keyboard" ;;
    bridge-server)
        # En la máquina con la Vita/agente: escucha conexiones Zenoh en TCP 7447.
        echo -e "${YELLOW}Puente Zenoh escuchando en tcp/0.0.0.0:7447 (IP $(ip_pc))${NC}"
        run "zenoh-bridge-ros2dds -l tcp/0.0.0.0:7447" ;;
    bridge-client)
        # En la otra máquina: se conecta al servidor y une los dos grafos ROS 2.
        SERVER="${2:-}"; [ -z "$SERVER" ] && read -rp "IP del equipo con bridge-server: " SERVER
        echo -e "${YELLOW}Puente Zenoh conectando a tcp/$SERVER:7447${NC}"
        run "zenoh-bridge-ros2dds -e tcp/$SERVER:7447" ;;
    sniff)
        # Captura el tráfico UDP de/para la Vita (diagnóstico de red; necesita VITA_IP o argumento).
        VIP="${2:-${VITA_IP:-}}"; [ -z "$VIP" ] && read -rp "IP de la Vita: " VIP
        run "tcpdump -ni any udp and host $VIP" ;;
    status)
        header
        command -v docker >/dev/null && echo -e "${GREEN}[✓]${NC} $(docker --version)"
        docker info 2>/dev/null | grep -q nvidia && echo -e "${GREEN}[✓]${NC} runtime NVIDIA" || echo -e "${YELLOW}[i]${NC} sin GPU NVIDIA (Gazebo por software)"
        echo -e "${CYAN}[i]${NC} IP de este equipo: $(ip_pc) — pon esta IP en ros/agent_ip del proyecto Godot"
        [ -n "${VITA_IP:-}" ] && { ping -c 2 -W 1 "$VITA_IP" >/dev/null 2>&1 && echo -e "${GREEN}[✓]${NC} Vita $VITA_IP responde" || echo -e "${RED}[✗]${NC} Vita $VITA_IP no responde"; }
        "${COMPOSE[@]}" ps -a ;;
    clean)   header; "${COMPOSE[@]}" down -v --rmi local ;;
    help|*)
        header
        cat <<'EOF'
Uso: docker/vita-ros.sh <comando>

  build               construir la imagen de la estación (~10-15 min la primera vez)
  up                  agente micro-ROS + estación      agent   solo el agente
  down | shell | status | logs [agent|station] | clean

  monitor             ver lo que publica la Vita y responderle /pc_hello (G5 en verde)
  topics | echo [topic]
  sim                 turtlesim obedeciendo /cmd_vel + su pose como /odom (ligero)
  sim-tb3             TurtleBot3 en Gazebo Harmonic      rviz | rqt | teleop

  bridge-server       puente Zenoh: escuchar en TCP 7447 (equipo con el agente)
  bridge-client <IP>  puente Zenoh: conectar al servidor (otro equipo)
  sniff [IP_VITA]     capturar el UDP de la Vita (diagnóstico)
EOF
        ;;
esac
