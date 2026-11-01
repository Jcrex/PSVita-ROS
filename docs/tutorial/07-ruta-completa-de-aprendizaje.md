# 07 — Tu ruta de aprendizaje

**Meta:** continuar el proyecto solo, revisar lo que escribe la IA y saber explicarlo.

## Cómo trabajamos desde ahora

1. Claude te explica el plan (máx. 500 palabras) y **tú decides**.
2. Claude escribe la base; **tú escribes una parte** (el «reto»).
3. **Tú lanzas los comandos** (docker, ros2, exportar, desplegar).
4. Antes del commit, **revisas el `git diff`** con la lista de abajo.
5. Cada hito deja una lección corta aquí.

## El sistema en 6 capas

```
Tu script .gd  →  ros2_vita (C++)  →  CDR (msg-schema)  →  cliente XRCE
   →  UDP por WiFi  →  agente micro-ROS (docker, PC)  →  ROS 2
```

Si sabes en qué capa estás, sabes dónde buscar el fallo.

## Las 11 pistas

| # | Pista | Sabes que la dominas cuando… |
|---|---|---|
| P1 | Infraestructura (git, docker, FTP) | levantas todo y despliegas un `.vpk` sin chuleta |
| P2 | ROS 2 por comandos | diagnosticas por qué un topic no llega |
| P3 | Godot y GDScript | creas una escena con dos scripts y señales |
| P4 | rclgd / ros2_vita | el mismo script funciona en el PC y en la Vita |
| P5 | micro-ROS / XRCE | explicas qué pasa entre `publish()` y `ros2 topic echo` |
| P6 | Hardware de la Vita | estimas si algo cabe en memoria, CPU y red |
| P7 | C y Rust (lecciones 01–06) | explicas `msg-ring` en los dos lenguajes |
| P8 | Motor y módulo C++ | añades un método a `RosNode` y recompilas |
| P9 | 3D en la Vita | mides cuántos triángulos aguanta a 30 fps |
| P10 | Auditar código | encuentras un fallo que la IA no vio |
| P11 | Apps grandes | escribes un ADR propio |

## Orden recomendado

1. **G7a IMU** → lección [08](./08-godot-imu-primer-sensor.md) (P1–P4)
2. Botones `/vita/joy` y panel trasero (P3, P8)
3. Lecciones 01–06 (P7)
4. Tu ADR sobre la cámara (P5, P6, P11)
5. Escena 3D en la Vita (P9)

## Lista de revisión (P10)

- ¿Entiendo cada línea? Si no, pregunto.
- ¿Hace solo lo que se pidió?
- Objetos `Ros*` guardados en variables del script.
- Topic, tipo y QoS coinciden con quien lo usa.
- Unidades SI y ejes REP-103.
- ¿Cabe en 512 bytes (MTU)?
- C/Rust: límites de buffers, quién libera la memoria, qué hilo escribe.
- ¿Qué está probado y qué falta «validar en hardware»?

## Autoevaluación

Responde de memoria:

1. ¿Por qué no cabe ROS 2 completo en la Vita?
2. Camino de un `Twist` desde el stick hasta turtlesim.
3. ¿Qué hace el agente micro-ROS?
4. ¿Qué es el `.rsch`?
5. ¿Por qué hay módulos en C y en Rust?

## Mis dudas

| Fecha | Duda | Respuesta |
|---|---|---|
| | | |
