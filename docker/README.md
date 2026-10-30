# `docker/` — estación ROS 2 de PSVita-ROS

Contenedores para trabajar con la PS Vita como nodo ROS 2 sin instalar ROS en el equipo:
el **agente micro-ROS** al que se conecta la Vita, un **monitor** de lo que publica, un **puente
Zenoh** para unir el grafo ROS 2 de dos equipos (PC por ethernet y laptop por WiFi) y una
**simulación de robot** para probar el teleop. Inspirado en el contenedor de IR2134
(`~/Documentos/IR2134/DOCKER`), pero propio del proyecto y versionado aquí para ampliarlo.

> **Estado (2026-10-30):** creado en el PC. Imagen construida; agente + monitor probados de punta a punta
> con la app `godot/g5-xrce` en el host (1 Hz / 10 Hz, «G5 OK»). **Con la Vita (G5–G6, hardware):** agente, monitor y
> `sim` (turtlesim con ventana + `/odom`) funcionan: la HMI `godot/g6-hmi` mueve la tortuga y dibuja su odometría.
> Pendiente: Gazebo/RViz y el puente Zenoh entre dos equipos. `tools/vita-stack.sh` usa ya esta estación por defecto.

## Qué hay dentro

| Servicio | Imagen | Para qué |
|---|---|---|
| `agent` (`vita_agent`) | `microros/micro-ros-agent:jazzy` (oficial) | Agente XRCE-DDS en **UDP 8888**: la Vita se conecta aquí |
| `station` (`vita_station`) | `psvita-ros-station:jazzy` (este `Dockerfile`) | ROS 2 Jazzy desktop (RViz2, rqt), `zenoh-bridge-ros2dds`, turtlesim, TurtleBot3 + Gazebo Harmonic, `tcpdump`, monitor |

Los dos van en la **red del host** (`network_mode: host`) y con **`ipc: host`**: Fast DDS usa memoria
compartida entre procesos del mismo equipo, y sin `ipc: host` los topics se *descubren* pero **no
llegan datos** (visto en G5, 2026-10-30). `ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET` por defecto: con
`LOCALHOST` no se ven los topics entre contenedores (bitácora, 2026-07-10).

## Uso rápido

```bash
cp docker/.env.example docker/.env      # opcional: VITA_IP, ROS_DOMAIN_ID, puerto del agente
docker/vita-ros.sh build                # imagen de la estación (~10-15 min la primera vez)
docker/vita-ros.sh up                   # agente + estación; muestra la IP de este equipo
docker/vita-ros.sh monitor              # ver /vita_hello y /cmd_vel y responder /pc_hello
docker/vita-ros.sh sim                  # turtlesim obedeciendo el /cmd_vel de la Vita
```

La IP que muestra `up` es la que va en `ros/agent_ip` del proyecto Godot (p. ej.
`godot/g5-xrce/project.godot`). En la app de la Fase 1 se configura desde la propia Vita.

## Comandos (`docker/vita-ros.sh`)

| Comando | Qué hace |
|---|---|
| `build` / `up` / `agent` / `down` / `shell` / `status` / `logs [agent\|station]` / `clean` | Ciclo de vida. `agent` levanta solo el agente |
| `monitor [--sin-pc-hello]` | `scripts/vita_monitor.py`: frecuencia y último valor de `/vita_hello` y `/cmd_vel`, «VITA VIVA» si publicó en los últimos 3 s; publica `/pc_hello` a 1 Hz |
| `topics` / `echo [topic]` | `ros2 topic list -t` / `ros2 topic echo` |
| `sim` | turtlesim con `/turtle1/cmd_vel` remapeado a `/cmd_vel` (ligero, sin GPU) + `scripts/turtle_odom.py`, que publica su pose como `/odom` (relativa al inicio) para la HMI de la Vita |
| `sim-tb3` | TurtleBot3 Burger en Gazebo Harmonic (mundo vacío). En Jazzy su `/cmd_vel` es `TwistStamped`; la imagen lo cambia a `Twist` (lo que publica la Vita) en los YAML del puente de Gazebo. GUI: validar en el PC |
| `rviz` / `rqt` / `teleop` | RViz2, `rqt_graph`, `teleop_twist_keyboard` (para probar sin la Vita) |
| `bridge-server` | Puente Zenoh escuchando en TCP 7447 |
| `bridge-client <IP>` | Puente Zenoh conectando al `bridge-server` |
| `sniff [IP_VITA]` | `tcpdump` del UDP de/para la Vita (¿salen sus paquetes? ¿llegan al equipo?) |

## Topología: ¿agente en el PC o en la laptop?

La Vita solo tiene WiFi; el PC está por ethernet. **En la misma LAN del router se alcanzan
directamente** (comprobado: FTP, XRCE y netlog desde el PC, 2026-07-10 y 2026-10-30), así que el
agente puede ir en el PC. Si algún día no fuera así (otra red, aislamiento de clientes WiFi):

1. En la **laptop** (en la WiFi de la Vita): `docker/vita-ros.sh agent` y `docker/vita-ros.sh bridge-server`.
2. En el **PC**: `docker/vita-ros.sh bridge-client <IP de la laptop>`.
3. El grafo ROS 2 queda unido por Zenoh (TCP 7447): `monitor`, `sim` y RViz pueden correr en el PC.

Abrir en el cortafuegos del equipo con el agente: UDP 8888 (agente) y TCP 7447 (Zenoh).

## GPU

`vita-ros.sh` añade `docker-compose.nvidia.yml` si `docker info` muestra el runtime `nvidia` (el PC
lo tiene). Sin NVIDIA (laptop), Gazebo funciona por software, más lento; turtlesim no necesita GPU.

## Ampliar

- Paquetes ROS 2 propios: en `docker/ws/src` (o `VITA_WS_PATH`), compilar con `colcon build` dentro
  de `vita-ros.sh shell`; el entrypoint carga `ws/install` si existe.
- Scripts sueltos: `docker/scripts/` (montado en `/scripts`, solo lectura).
- Más dependencias: añadirlas al `Dockerfile` y `vita-ros.sh build`.
