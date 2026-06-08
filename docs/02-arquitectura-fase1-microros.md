# Arquitectura de la Fase 1: micro-ROS y transporte UDP

**Fecha de creación:** 2026-06-08
**Estado:** Fundación aprobada — incógnita dura pendiente de validación

---

## Topología del sistema

La arquitectura de la Fase 1 conecta la PS Vita al grafo ROS2 Jazzy mediante una cadena de dos saltos: la Vita ejecuta el cliente micro-ROS (XRCE-DDS) que se comunica con un agente en el PC, y el agente hace de puente hacia el grafo DDS completo de Jazzy.

```
[ PS Vita 1000 ]                 [ PC CachyOS (Docker) ]
 app homebrew                     micro-ROS Agent (UDP4)
 ├─ microxrcedds_client   <--WiFi/UDP-->  ├─ puentea a DDS
 └─ transporte UDP propio                 └─ ROS2 Jazzy graph
     (sceNet)                                  ├─ topics
                                                ├─ nodos
                                                └─ rviz2/gazebo (en el PC)
```

Esta topología es la única viable dado el hardware y el entorno de ejecución de la Vita (ver `docs/01-hardware-y-plataforma.md`). El grafo ROS2 completo —con sus nodos, topics, servicios y acciones— sigue viviendo en el PC. La Vita es un participante del grafo, no su anfitrión.

---

## micro-ROS en la Vita: `microxrcedds_client`

### Qué es y cómo se integra

**micro-ROS** (más precisamente, `microxrcedds_client`, la implementación del protocolo XRCE-DDS para clientes embebidos) es la pieza central de la Fase 1 en el lado de la Vita. Se compila como una **biblioteca estática para armv7** usando el toolchain VitaSDK (`arm-vita-eabi-gcc` con newlib).

El cliente micro-ROS fue diseñado para microcontroladores con kilobytes de RAM. Compilarlo para la Vita —con 512 MB de RAM y un Cortex-A9 completo— es técnicamente factible en cuanto a recursos, pero requiere superar las diferencias entre newlib y los entornos que `microxrcedds_client` asume normalmente (POSIX ligero o ninguno). La compilación a `staticlib` con el toolchain de la Vita es el primer trabajo de integración de la Fase 1.

### El transporte personalizado: el contrato con `sceNet`

micro-ROS no asume un mecanismo de transporte concreto. En lugar de eso, define una interfaz de **4 callbacks** que el usuario de la biblioteca debe implementar para adaptarla a la plataforma. Estos callbacks son:

- **`open`**: inicializa el transporte, crea el socket UDP con `sceNet` y establece la dirección del agente.
- **`close`**: cierra el socket y libera los recursos de red.
- **`write`**: envía un buffer de bytes al agente mediante `sceNetSendto` (o equivalente).
- **`read`**: recibe bytes del agente con un timeout mediante `sceNetRecvfrom` (o equivalente).

El módulo `microros-transport` encapsula exactamente estos 4 callbacks. Es uno de los tres módulos duales (Rust + C/C++) de la Fase 1, ya que toca directamente las APIs de sistema (`sceNet`) y el comportamiento de red en tiempo real. La implementación C/C++ es el respaldo permanente; la implementación Rust con `#[no_mangle] extern "C"` puede sustituirla en build time con `-DVITA_IMPL=rust`.

El módulo `net-udp` es la capa por debajo: encapsula la inicialización del stack de red de la Vita (`sceNet`/`sceNetCtl`), la creación de sockets UDP y las operaciones de envío/recepción en un contrato C-ABI limpio que `microros-transport` consume.

---

## El agente: micro-ROS Agent en Docker

En el lado del PC corre el **micro-ROS Agent**, un proceso que hace de puente entre el protocolo XRCE-DDS del cliente y el DDS completo del grafo ROS2 Jazzy. Se ejecuta en un contenedor Docker para mantener el entorno del PC limpio y reproducible.

El transporte configurado en el agente es **`udp4`** (UDP sobre IPv4), escuchando en un puerto conocido, por ejemplo el **puerto 8888**. El agente espera conexiones entrantes: cuando el cliente de la Vita establece sesión, el agente materializa en el grafo ROS2 todas las entidades XRCE-DDS que el cliente declara.

Ejemplo de arranque del agente:

```bash
docker run -it --rm --net=host microros/micro-ros-agent:jazzy udp4 --port 8888
```

> **Nota:** verificar la disponibilidad del tag `jazzy` en Docker Hub antes de usarlo. Si no existe, usar el tag correspondiente a la distribución de micro-ROS más cercana a Jazzy o compilar el agente manualmente. El tag exacto a usar se documenta en `docs/05-setup-entorno-cachyos.md` y en el ADR correspondiente.

El flag `--net=host` es importante: permite que el contenedor vea el tráfico UDP de la red local sin traducción de puertos (NAT), lo cual simplifica la conectividad con la Vita que está en la misma red WiFi.

---

## Flujo de datos

El flujo de datos en la Fase 1 sigue este recorrido:

1. **La Vita declara entidades XRCE-DDS.** Al arrancar la app, el cliente micro-ROS abre una sesión con el agente y envía mensajes XRCE para crear un participante DDS, publishers y/o subscribers, y los topics asociados.

2. **El agente materializa entidades DDS reales.** El agente recibe las declaraciones XRCE del cliente y crea los equivalentes en el grafo DDS de Jazzy: un participante DDS, publicadores y suscriptores reales. Desde la perspectiva del grafo ROS2, la Vita es un nodo más.

3. **Publicación desde la Vita.** Cuando la app en la Vita quiere publicar, serializa el mensaje en CDR (el formato de serialización de DDS), lo entrega al cliente XRCE que lo fragmenta si es necesario y lo envía por UDP al agente; el agente lo deserializa y lo republica en el bus DDS local.

4. **Recepción en la Vita.** Cuando alguien en el grafo publica en un topic al que la Vita está suscrita, el agente recibe el dato DDS, lo encapsula en XRCE y lo envía por UDP a la Vita; el cliente lo deserializa y lo entrega al callback del suscriptor de la app.

5. **Visibilidad desde el PC.** En cualquier momento, `ros2 topic list` y `ros2 topic echo` en el PC muestran los topics de la Vita como si fueran de cualquier otro nodo ROS2. Esta visibilidad es el criterio de éxito de la Fase 1.

---

## La incógnita dura: ¿levanta la sesión?

La pregunta más importante de toda la Fase 1, y la primera que debe responderse, es esta: **¿el cliente micro-ROS levanta y mantiene una sesión XRCE con el agente usando el transporte UDP propio implementado sobre `sceNet`?**

Esta pregunta es una incógnita dura porque de su respuesta cuelga absolutamente todo lo demás de la Fase 1. Si la sesión no levanta o no es estable, no hay topics, no hay publishers, no hay subscribers, no hay criterio de éxito. Los muros potenciales son varios:

- La inicialización del stack de red de la Vita (`sceNetPoolCreate`, `sceNetInit`) tiene requisitos específicos de orden y tamaño de buffers que deben satisfacerse antes de que cualquier socket sea válido.
- `sceNet` podría no soportar algunas opciones de socket que el cliente micro-ROS intenta configurar (`SO_RCVTIMEO`, por ejemplo).
- El comportamiento del buffer de recepción y el timeout de `recvfrom` sobre `sceNet` podría diferir de lo que el cliente XRCE espera en su bucle de lectura.
- La MTU de la red WiFi de la Vita podría causar fragmentación que el transporte personalizado debe manejar.

El módulo `microros-transport` se desarrolla primero con el objetivo explícito de validar este punto. Hasta que no se tenga un "hello" XRCE exitoso —sesión abierta, agente respondiendo, cliente reconociendo la respuesta— la Fase 1 no está desbloqueada.

---

## Criterio de validación de la Fase 1

El criterio de éxito de la Fase 1 es doble y concreto:

1. **La Vita publica en un topic visible desde el PC.** Ejecutar `ros2 topic echo /vita_hello std_msgs/msg/String` (o el topic elegido) en el PC muestra mensajes que llegan desde la consola.

2. **La Vita recibe un topic publicado desde el PC.** Publicar desde el PC con `ros2 topic pub /pc_hello std_msgs/msg/String "data: 'ping'"` resulta en que la app de la Vita recibe el mensaje y puede confirmarlo (mediante log en pantalla o un LED de notificación).

Cuando ambas condiciones se cumplen de forma estable, la Fase 1 está completada y se puede avanzar al diseño del objetivo 2.
