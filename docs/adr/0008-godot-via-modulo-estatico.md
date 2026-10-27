# ADR 0008: Godot en la Vita — módulo C++ estático sobre la capa ROS dual, app separada

- **Estado:** Propuesto (pendiente de validar en PC y hardware; ver docs/12 §8)
- **Fecha:** 2026-10-27

## Contexto

Se quiere poder desarrollar aplicaciones de Vita con Godot que usen ROS2
(`docs/12-investigacion-godot-ros2-vita.md`). Hechos verificados:

1. Existen dos ports no oficiales: `godot-vita` (3.5, GLES2 vía PVR_PSP2)
   y `godot4-vita` (4.x, GXM nativo).
2. Ninguno soporta GDExtension; Rust no soporta enlace dinámico en la
   Vita; por tanto el código nativo debe ir **compilado dentro del motor**.
3. Nuestra pila ROS2 ya funciona en hardware y es modular: header C +
   staticlib (C o Rust) → XRCE → `microros-transport` → `net-udp` (sceNet).
4. ADR 0007: vitaGL es dueño exclusivo del GPU en nuestra app; Godot
   inicializa el GPU por su cuenta → no pueden vivir en el mismo proceso.

## Decisión

1. **Integración = módulo estático de Godot `ros2_vita`** (C++ delgado)
   que llama **solo** a los headers C de `modules/*/include/` y al cliente
   XRCE. Sin lógica propia de ROS en C++: así la implementación Rust o C
   sigue siendo intercambiable (regla transversal del repo).
2. **Dos aplicaciones separadas** que comparten la capa ROS:
   `vita-ros2` (C + vitaGL, existente) y `vita-ros2-godot` (nueva).
   No se intenta incrustar vitaGL/mini-rviz dentro de Godot.
3. **Hilos:** la sesión XRCE (`uxr_run_session_*`) corre en un hilo propio;
   los mensajes entrantes pasan al hilo principal de Godot por una **cola
   SPSC sin bloqueos** (módulo dual `msg-ring`, ya implementado y con
   paridad en host) y se emiten como señales de Godot. Se evita el perfil
   `UCLIENT_PROFILE_MULTITHREAD` salvo que la medición lo exija.
4. **API GDScript objetivo** (provisional, a alinear con rclgd — P1):
   `RosNode.create_publisher(topic, type)`, `publisher.publish(dict)`,
   `RosNode.create_subscription(topic, type)` + señal
   `message_received(topic, dict)`. Tipos soportados al inicio:
   `std_msgs/String`, `geometry_msgs/Twist`, `sensor_msgs/Joy`
   (los de Objetivo 2).
5. **Versión de Godot:** empezar con **3.5 (`godot-vita`)**: plantilla
   reproducible por SCons ya documentada, GLES2 conocido. Reevaluar 4.x
   tras P3/P5. Los módulos se escriben detrás de una fina capa
   (`register_types`) para soportar ambas.
6. **Vías de transición:** Vía A (rclgd en PC) y vía B (rosbridge `ws://`)
   sirven para prototipar sin código nativo (docs/12 §5); no sustituyen
   a la vía C.

## Alternativas descartadas

- **GDExtension / godot-rust (gdext):** imposible sin enlace dinámico.
- **Port propio de Godot:** coste enorme y sin NDA/SDK oficial; ya existen
  dos ports.
- **Godot sobre vitaGL propio + mini-rviz dentro de Godot:** conflicto de
  GPU y el 3D de godot4-vita es experimental (sin shaders propios).
- **Reimplementar XRCE en GDScript sobre `PacketPeerUDP`:** frágil, lento,
  y la plantilla 3.5 oficial no trae sockets.

## Consecuencias

- Se añade `msg-ring` (cola dual) como pieza reutilizable también por
  la app C (red → render del mini-rviz).
- Hay que mantener una **plantilla de exportación propia** (build de
  1–2 h) → script y CI en el PC (pendiente, docs/13 §6).
- El módulo C++ **no es verificable en la laptop**: todo su código lleva
  el marcador "validar en el PC / en hardware".
- Riesgo asumido: ambos ports son proyectos de terceros pequeños; se
  fijará un commit exacto (P2) y se versionarán las plantillas.
