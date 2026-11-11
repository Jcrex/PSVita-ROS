# =============================================================================
# Estación ROS 2 de PSVita-ROS (docker/README.md)
# =============================================================================
# Un contenedor para trabajar con la PS Vita como nodo ROS 2:
#   - ROS 2 Jazzy (desktop: RViz2, rqt)
#   - Puente Zenoh (zenoh-bridge-ros2dds): une el grafo ROS 2 del PC y el de la laptop
#     por TCP aunque estén en redes distintas (ethernet / WiFi), como en IR2134
#   - Simulación para probar el teleop de la Vita: turtlesim (ligero) y TurtleBot3 en Gazebo Harmonic
#   - Monitor de la Vita (scripts/vita_monitor.py): /vita_hello, /cmd_vel, responde /pc_hello
# El agente micro-ROS va en un servicio aparte (imagen oficial microros/micro-ros-agent:jazzy).
# =============================================================================
FROM osrf/ros:jazzy-desktop

ENV DEBIAN_FRONTEND=noninteractive
LABEL description="PSVita-ROS — estación ROS 2 Jazzy (monitor, puente Zenoh, simulación)"

RUN apt-get update && apt-get install -y --no-install-recommends \
    # herramientas y red (diagnóstico de la WiFi de la Vita)
    bash-completion curl gnupg ca-certificates less nano tmux \
    iputils-ping iproute2 net-tools dnsutils tcpdump netcat-openbsd socat \
    # simulación
    ros-jazzy-turtlesim \
    ros-jazzy-ros-gz \
    ros-jazzy-turtlebot3 ros-jazzy-turtlebot3-gazebo ros-jazzy-turtlebot3-description \
    ros-jazzy-teleop-twist-keyboard \
    # utilidades ROS
    ros-jazzy-rqt-graph ros-jazzy-rqt-topic ros-jazzy-rqt-plot ros-jazzy-rqt-console \
    ros-jazzy-topic-tools \
    ros-jazzy-rmw-zenoh-cpp \
    && rm -rf /var/lib/apt/lists/*

# Zenoh: binarios oficiales de Eclipse (igual que IR2134). El paquete trae un servicio systemd:
# se neutraliza systemctl durante la instalación porque en un contenedor no hay systemd.
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.eclipse.org/zenoh/debian-repo/zenoh-public-key \
      | gpg --dearmor --yes --output /etc/apt/keyrings/zenoh-public-key.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/zenoh-public-key.gpg] https://download.eclipse.org/zenoh/debian-repo/ /" \
      > /etc/apt/sources.list.d/zenoh.list && \
    apt-get update && \
    mv /usr/bin/systemctl /usr/bin/systemctl.bak 2>/dev/null || true && \
    printf '#!/bin/sh\nexit 0\n' > /usr/bin/systemctl && chmod +x /usr/bin/systemctl && \
    apt-get install -y --no-install-recommends zenoh-bridge-ros2dds && \
    rm -f /usr/bin/systemctl && (mv /usr/bin/systemctl.bak /usr/bin/systemctl 2>/dev/null || true) && \
    rm -rf /var/lib/apt/lists/*

# TurtleBot3 (Jazzy) espera geometry_msgs/TwistStamped en /cmd_vel, pero la Vita publica Twist (como
# rclgd y el teleop de la Fase 1). Lo indica el propio YAML: "If you use Twist, change the type to Twist".
RUN sed -i 's#ros_type_name: "geometry_msgs/msg/TwistStamped"#ros_type_name: "geometry_msgs/msg/Twist"#' \
      /opt/ros/jazzy/share/turtlebot3_gazebo/params/turtlebot3_*_bridge.yaml && \
    ! grep -q TwistStamped /opt/ros/jazzy/share/turtlebot3_gazebo/params/turtlebot3_burger_bridge.yaml

ENV ROS_DISTRO=jazzy \
    TURTLEBOT3_MODEL=burger \
    QT_X11_NO_MITSHM=1

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && \
    echo 'source /opt/ros/jazzy/setup.bash' >> /root/.bashrc && \
    echo '[ -f /ws/install/setup.bash ] && source /ws/install/setup.bash' >> /root/.bashrc

WORKDIR /ws
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
