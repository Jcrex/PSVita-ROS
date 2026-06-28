# ros2-introspection MCP

## Qué es

`ros2-introspection` es un servidor MCP (*Model Context Protocol*) que expone
el grafo ROS2 del PC de desarrollo a Claude Code. Permite que el asistente
consulte tópicos, nodos y tipos de mensajes activos sin necesidad de acceso
directo al entorno ROS2.

El servidor corre en el **PC de desarrollo** (donde existe `rclpy` gracias a
ROS2 Jazzy) y se comunica con Claude Code mediante transporte **stdio**.

---

## Tools disponibles

| Tool | Descripción |
|------|-------------|
| `list_topics` | Lista todos los tópicos activos con sus tipos de mensaje. |
| `list_nodes` | Lista todos los nodos activos con su nombre y namespace. |
| `get_topic_type` | Devuelve el tipo de mensaje principal de un tópico dado. |
| `get_message_definition` | Devuelve el texto de definición `.msg` de un tipo de mensaje (resuelto vía `rosidl_runtime_py`/ament index). |
| `echo_topic` | Se suscribe una vez (QoS BEST_EFFORT, compatible con cualquier publisher) y devuelve la primera muestra como dict. `TimeoutError` si no llega nada en el plazo. |
| `list_interfaces` | Lista todos los tipos de mensaje presentes en el grafo. |

---

## Estado

**`RclpyBackend` completo y validado** (2026-06-10) contra un grafo ROS2
Jazzy vivo en el contenedor `robotnik_dev` de la laptop: las 6 tools
funcionan con topics reales (`list_topics`, `get_topic_type`, `echo_topic`
con publisher activo, `get_message_definition` de `std_msgs/String` y
`sensor_msgs/LaserScan`, errores `KeyError`/`TimeoutError` verificados).
Los tests unitarios con `FakeBackend` (5) pasan en la laptop sin ROS2.

Registrado en el Claude Code del PC el 2026-06-28 (ver "Registro en Claude
Code"). En el host del PC no hay `rclpy` (ROS2 vive en contenedores), así que
el server cae a `FakeBackend`; para datos reales se ejecuta donde haya ROS2.

### Selección de backend (no crashea sin ROS2)

`main()` elige el backend según la variable de entorno
`ROS2_INTROSPECTION_BACKEND`:

| Valor | Comportamiento |
|---|---|
| `rclpy` (por defecto) | Usa `RclpyBackend`; si `import rclpy` falla (host sin ROS2), **cae a `FakeBackend`** con un aviso por stderr en vez de abortar. |
| `fake` | Fuerza `FakeBackend` (datos de prueba), sin intentar rclpy ni avisar. |

Esto permite registrar el MCP en cualquier máquina: datos de prueba en el host,
datos reales allí donde `rclpy` existe (un contenedor ROS2 Jazzy).

---

## Instalación en el PC (entorno ROS2 Jazzy)

Dentro del entorno o contenedor donde `rclpy` está disponible:

```bash
# 1. Activa el entorno ROS2 si aún no lo has hecho
source /opt/ros/jazzy/setup.bash

# 2. Instala el paquete MCP (modo editable, sin crear un venv separado para
#    no aislar rclpy, que ya viene del entorno ROS2)
cd mcp/ros2-introspection
pip install -e .
```

### Registro en Claude Code

El registro vive en `.mcp.json` en la raíz del proyecto. **Está gitignorado**
porque la ruta al intérprete es específica de cada máquina (en la laptop el MCP
corre dentro de un contenedor). Plantilla — ajusta `command` a tu Python con el
paquete instalado (el venv del PC, o `python` dentro de un contenedor ROS2):

```json
{
  "mcpServers": {
    "ros2-introspection": {
      "command": "/ruta/al/mcp/ros2-introspection/.venv/bin/python",
      "args": ["-m", "ros2_introspection.server"]
    }
  }
}
```

> El transporte **stdio** es el predeterminado del MCP SDK; no se necesita
> puerto ni servidor HTTP. Tras crear/editar `.mcp.json`, **reinicia Claude
> Code** para que cargue el server.

#### Datos reales con un contenedor ROS2 (prueba rápida en el PC)

El host del PC no tiene `rclpy`. Para ver un grafo vivo, ejecuta el server
dentro de un contenedor ROS2 Jazzy (con el paquete instalado ahí). Como los
contenedores ROS2 usan `network_mode: host`, el grafo DDS se comparte con el
host por `localhost`. Ejemplo de `command` apuntando a un contenedor:

```json
"command": "docker", "args": ["exec", "-i", "<contenedor>", "python3", "-m", "ros2_introspection.server"]
```

(Requiere instalar este paquete dentro del contenedor con `pip install -e .`.)

---

## Prueba en el PC

```bash
# 1. Activa ROS2 Jazzy
source /opt/ros/jazzy/setup.bash

# 2. Lanza un nodo demo en otra terminal
ros2 run demo_nodes_py talker

# 3. Desde Claude Code, llama a la tool list_topics y verifica que
#    /chatter (o los tópicos de tu nodo) aparecen en la respuesta.
```

Si `list_topics` devuelve los tópicos reales del grafo, la integración con
`rclpy` funciona correctamente.
