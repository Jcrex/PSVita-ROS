#!/bin/bash
# Entrypoint de la estación ROS 2 de PSVita-ROS: carga ROS 2 y el workspace (si existe) y ejecuta
# el comando pedido (bash por defecto).
set -e
source /opt/ros/jazzy/setup.bash
[ -f /ws/install/setup.bash ] && source /ws/install/setup.bash
exec "$@"
