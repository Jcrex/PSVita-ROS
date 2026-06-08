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
| `get_message_definition` | Devuelve el texto de definición `.msg` de un tipo de mensaje. ⚠️ Pendiente de validar en el PC (ver Estado). |
| `echo_topic` | Captura una muestra de un tópico y la devuelve como JSON. ⚠️ Pendiente de validar en el PC (ver Estado). |
| `list_interfaces` | Lista todos los tipos de mensaje presentes en el grafo. |

---

## Estado

- `list_topics`, `list_nodes`, `get_topic_type`, `list_interfaces`: implementados
  en `RclpyBackend` y listos para validar en el PC con un grafo ROS2 activo.
- `get_message_definition` y `echo_topic` en `RclpyBackend`: lanzarán
  `NotImplementedError` hasta completar la implementación en el PC. Ambas
  tools funcionan correctamente con el `FakeBackend` (tests en el laptop pasan).

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

Añade la siguiente entrada a `.mcp.json` en la raíz del proyecto (o en la
configuración global de Claude Code según prefieras):

```json
{
  "mcpServers": {
    "ros2-introspection": {
      "command": "python",
      "args": ["-m", "ros2_introspection.server"],
      "transport": "stdio"
    }
  }
}
```

> El transporte **stdio** es el predeterminado del MCP SDK; no se necesita
> puerto ni servidor HTTP.

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
