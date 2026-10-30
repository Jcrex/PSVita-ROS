#!/usr/bin/env bash
# vita-stack.sh — arranca/para, con un solo comando, todo lo necesario para
# una sesión en vivo Vita <-> ROS2 (estilo ~/Documentos/IR2134/DOCKER/rmf.sh,
# pero para las piezas de ESTE proyecto). Desde 2026-10-30 el contenedor ROS2 por
# defecto es la estación propia del repo (docker/, vita_station + vita_agent);
# el de IR2134 sigue valiendo con ROS2_DOCKER_DIR=~/Documentos/IR2134/DOCKER
# ROS2_CONTENEDOR=rmf_unified AGENT_NOMBRE=microros-agent. Antes había que acordarse a mano
# de: el contenedor ROS2 (rmf_unified), el micro-ROS agent (un `docker run`
# aparte), el bridge zenoh (REST para el dashboard) y la web — cada uno en
# su terminal, y era fácil dejarse alguno.
#
# Uso:
#   tools/vita-stack.sh all              # todo junto: ros2 + agent + bridge + web
#   tools/vita-stack.sh down             # para agent + bridge + web (ros2 se deja)
#   tools/vita-stack.sh status           # resumen de qué está arriba
#   tools/vita-stack.sh web up           # solo lo que necesites en cada momento
#   tools/vita-stack.sh agent up|down|logs|status
#   tools/vita-stack.sh bridge up|down|logs|status
#   tools/vita-stack.sh ros2 up|down|status
#   tools/vita-stack.sh netlog           # primer plano: escucha el netlog UDP
#
# Variables de entorno (override si tu setup difiere):
#   ROS2_DOCKER_DIR (def. <repo>/docker), ROS2_CONTENEDOR (def. vita_station),
#   AGENT_IMAGEN (def. microros/micro-ros-agent:jazzy), AGENT_NOMBRE (def. vita_agent),
#   AGENT_PUERTO (def. 8888), ZENOH_REST_PUERTO (def. 8000), NETLOG_PUERTO (def. 9999)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

ROS2_DOCKER_DIR="${ROS2_DOCKER_DIR:-$REPO_ROOT/docker}"
ROS2_CONTENEDOR="${ROS2_CONTENEDOR:-vita_station}"
AGENT_IMAGEN="${AGENT_IMAGEN:-microros/micro-ros-agent:jazzy}"
AGENT_NOMBRE="${AGENT_NOMBRE:-vita_agent}"
AGENT_PUERTO="${AGENT_PUERTO:-8888}"
ZENOH_REST_PUERTO="${ZENOH_REST_PUERTO:-8000}"
NETLOG_PUERTO="${NETLOG_PUERTO:-9999}"

header() {
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🎮 PSVita-ROS — stack de conexión${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
}

contenedor_arriba() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# ---------------- ros2 (estación docker/ del repo, o rmf_unified de IR2134) ----
# Script de ayuda del contenedor: docker/vita-ros.sh (propio) o rmf.sh (IR2134).
ros2_script() {
    if [ -x "$ROS2_DOCKER_DIR/vita-ros.sh" ]; then echo "vita-ros.sh"
    elif [ -x "$ROS2_DOCKER_DIR/rmf.sh" ]; then echo "rmf.sh"
    fi
}
ros2_up() {
    if contenedor_arriba "$ROS2_CONTENEDOR"; then
        echo -e "${GREEN}[✓]${NC} ros2 ($ROS2_CONTENEDOR) ya está arriba"; return 0
    fi
    local sc; sc="$(ros2_script)"
    if [ -z "$sc" ]; then
        echo -e "${RED}[✗]${NC} No encuentro vita-ros.sh ni rmf.sh en $ROS2_DOCKER_DIR (ajusta ROS2_DOCKER_DIR)."; return 1
    fi
    (cd "$ROS2_DOCKER_DIR" && ./"$sc" up)
}
ros2_down() { (cd "$ROS2_DOCKER_DIR" && ./"$(ros2_script)" down); }
ros2_status() {
    contenedor_arriba "$ROS2_CONTENEDOR" \
        && echo -e "${GREEN}[✓]${NC} ros2 ($ROS2_CONTENEDOR): arriba" \
        || echo -e "${YELLOW}[ ]${NC} ros2 ($ROS2_CONTENEDOR): parado"
}

# ---------------- agent (micro-ROS agent: XRCE-DDS Vita <-> ROS2) -------------
agent_up() {
    if contenedor_arriba "$AGENT_NOMBRE"; then
        echo -e "${GREEN}[✓]${NC} agent ya está arriba"; return 0
    fi
    if [ "$(ros2_script)" = "vita-ros.sh" ] && [ "$AGENT_NOMBRE" = "vita_agent" ]; then
        (cd "$ROS2_DOCKER_DIR" && AGENT_PORT="$AGENT_PUERTO" ./vita-ros.sh agent >/dev/null)  # servicio del compose
    else
        docker rm -f "$AGENT_NOMBRE" >/dev/null 2>&1 || true
        docker run -d --name "$AGENT_NOMBRE" --net=host --ipc=host \
            "$AGENT_IMAGEN" udp4 --port "$AGENT_PUERTO" -v6 >/dev/null
    fi
    echo -e "${GREEN}[✓]${NC} agent arriba (UDP :$AGENT_PUERTO). Logs: tools/vita-stack.sh agent logs"
}
agent_down() {
    docker rm -f "$AGENT_NOMBRE" >/dev/null 2>&1 \
        && echo -e "${GREEN}[✓]${NC} agent parado" \
        || echo -e "${YELLOW}[ ]${NC} agent no estaba arriba"
}
agent_logs() { docker logs -f "$AGENT_NOMBRE"; }
agent_status() {
    contenedor_arriba "$AGENT_NOMBRE" \
        && echo -e "${GREEN}[✓]${NC} agent: arriba (UDP :$AGENT_PUERTO)" \
        || echo -e "${YELLOW}[ ]${NC} agent: parado"
}

# ---------------- bridge (zenoh-bridge-ros2dds dentro del contenedor ROS2) ----
# Ya viene instalado en la estación (docker/Dockerfile) y en rmf_unified. Se lanza con --rest-http-port para que
# el dashboard web (web/src/lib/ros2bridge.ts, ZENOH_REST_URL) pueda leer el
# grafo de topics por HTTP en vez de "docker exec" desde la propia web.
bridge_up() {
    if ! contenedor_arriba "$ROS2_CONTENEDOR"; then
        echo -e "${RED}[✗]${NC} '$ROS2_CONTENEDOR' no está arriba (tools/vita-stack.sh ros2 up)."; return 1
    fi
    if docker exec "$ROS2_CONTENEDOR" pgrep -f zenoh-bridge-ros2dds >/dev/null 2>&1; then
        echo -e "${GREEN}[✓]${NC} bridge ya está arriba"; return 0
    fi
    docker exec -d "$ROS2_CONTENEDOR" bash -lc \
        "source /opt/ros/jazzy/setup.bash && zenoh-bridge-ros2dds --rest-http-port $ZENOH_REST_PUERTO > /tmp/zenoh-bridge.log 2>&1"
    sleep 1
    if docker exec "$ROS2_CONTENEDOR" pgrep -f zenoh-bridge-ros2dds >/dev/null 2>&1; then
        echo -e "${GREEN}[✓]${NC} bridge arriba (REST :$ZENOH_REST_PUERTO)"
    else
        echo -e "${RED}[✗]${NC} no arrancó — revisa: docker exec $ROS2_CONTENEDOR cat /tmp/zenoh-bridge.log"
        return 1
    fi
}
bridge_down() {
    docker exec "$ROS2_CONTENEDOR" pkill -f zenoh-bridge-ros2dds >/dev/null 2>&1 \
        && echo -e "${GREEN}[✓]${NC} bridge parado" \
        || echo -e "${YELLOW}[ ]${NC} bridge no estaba arriba"
}
bridge_logs() { docker exec "$ROS2_CONTENEDOR" bash -lc "tail -f /tmp/zenoh-bridge.log"; }
bridge_status() {
    if contenedor_arriba "$ROS2_CONTENEDOR" && docker exec "$ROS2_CONTENEDOR" pgrep -f zenoh-bridge-ros2dds >/dev/null 2>&1; then
        echo -e "${GREEN}[✓]${NC} bridge: arriba (REST :$ZENOH_REST_PUERTO)"
    else
        echo -e "${YELLOW}[ ]${NC} bridge: parado"
    fi
}

# ---------------- web (web/docker-compose.yml) --------------------------------
web_up()   { (cd "$REPO_ROOT/web" && docker compose up -d --build); }
web_down() { (cd "$REPO_ROOT/web" && docker compose down); }
web_logs() { (cd "$REPO_ROOT/web" && docker compose logs -f); }
web_status() {
    contenedor_arriba psvita-ros-web \
        && echo -e "${GREEN}[✓]${NC} web: arriba (http://localhost:4321)" \
        || echo -e "${YELLOW}[ ]${NC} web: parada"
}

# ---------------- netlog (delega en tools/netlog-listen.sh) -------------------
netlog_up() {
    echo -e "${YELLOW}[i]${NC} netlog corre en primer plano en esta terminal (no es un contenedor)."
    exec "$SCRIPT_DIR/netlog-listen.sh" "$NETLOG_PUERTO"
}

status_todo() { header; ros2_status; agent_status; bridge_status; web_status; }

uso() {
    header
    cat <<EOF

Uso: tools/vita-stack.sh <comando>

  all             Arranca ros2 + agent + bridge + web (sesión completa con la Vita)
  down            Para agent + bridge + web (ros2 se deja, por si lo usas para otra cosa)
  status          Resumen de qué está arriba

  ros2   up|down|status       Contenedor ROS2 ($ROS2_CONTENEDOR, delega en $ROS2_DOCKER_DIR/$(ros2_script))
  agent  up|down|logs|status  micro-ROS agent (XRCE-DDS <-> ROS2, UDP :$AGENT_PUERTO)
  bridge up|down|logs|status  zenoh-bridge-ros2dds dentro de $ROS2_CONTENEDOR (REST :$ZENOH_REST_PUERTO)
  web    up|down|logs|status  Web del proyecto (docker compose en web/)
  netlog                      Escucha el netlog UDP de la Vita (primer plano)

Variables de entorno (override): ROS2_DOCKER_DIR, ROS2_CONTENEDOR, AGENT_IMAGEN,
AGENT_NOMBRE, AGENT_PUERTO, ZENOH_REST_PUERTO, NETLOG_PUERTO
EOF
}

comp="${1:-help}"; accion="${2:-}"

case "$comp" in
    all)
        header
        ros2_up && agent_up && bridge_up && web_up
        echo ""; status_todo
        ;;
    down)
        header
        agent_down; bridge_down; web_down
        ;;
    status) status_todo ;;
    ros2)
        case "$accion" in
            up) ros2_up ;; down) ros2_down ;; status|"") ros2_status ;; *) uso ;;
        esac
        ;;
    agent)
        case "$accion" in
            up) agent_up ;; down) agent_down ;; logs) agent_logs ;; status|"") agent_status ;; *) uso ;;
        esac
        ;;
    bridge)
        case "$accion" in
            up) bridge_up ;; down) bridge_down ;; logs) bridge_logs ;; status|"") bridge_status ;; *) uso ;;
        esac
        ;;
    web)
        case "$accion" in
            up) web_up ;; down) web_down ;; logs) web_logs ;; status|"") web_status ;; *) uso ;;
        esac
        ;;
    netlog) netlog_up ;;
    help|*) uso ;;
esac
