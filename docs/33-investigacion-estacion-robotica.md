# 33 — Investigación «estación robótica»: documento maestro (LT1–LT8 × fases 1–4)

> **Estado:** etapa de investigación cerrada el 2026-11-12. Método multiagente con talleres, tablero y revisión, en
> `docs/ia/workshops/` (README, `tablero.json`, registro de parches, posts).
> **Modelos:** Fable 5.2 para W3, W8 y W9 (diseños y ADR); Opus 5.5 para el resto; Haiku 5.5 para inventarios.
> Sustitución documentada: W10 y W11 los resolvió el orquestador (Opus) porque Fable llegó al límite de uso.
> Marcas: [V] verificado · [I] inferencia · [?] sin confirmar. **Nada de lo marcado «por medir» se da por cierto
> hasta probarlo en la Vita.**

## 1. Resumen ejecutivo (1 minuto)

1. **La Vita sirve como terminal robótica completa**, siempre que el PC adapte los datos. Hay tres cuellos de botella:
   - **Un núcleo efectivo:** WorkerThreadPool = 0, así que escena, render, física y XRCE comparten hilo
     (`worker_thread_pool.cpp:848-857`) [V].
   - **XRCE pequeño:** best effort ≤ 488 B por mensaje; fiable ≈ 7,5 KiB al recibir [V].
   - **3D GXM limitado:** solo dibuja triángulos, sin MultiMesh ni color por vértice [V].
2. **Arquitectura decidida:**
   - Relay y puente en el PC (ADR 0012).
   - URDF horneado en el PC (ADR 0009).
   - Visualización en dos capas: 3D para lo rígido, 2D para lo denso, y raster como textura (ADR 0011).
   - DB-TSDF como módulo dual con escalera de bits (ADR 0010).
3. **Ya funciona:**
   - **En la Vita:** el G1 de Unitree a **60 FPS** con la casa.
   - **En el PC:** el relay a 10, 30, 25 y 20 Hz en ~14 KB/s, con el minimapa del G1.
   - **Plantillas de la sesión paralela (docs 29–30):** RB-KAIROS+, G1 con sensores y dron de mapeo.
4. **Bloqueante P0 de `ros2_vita`:** TF (emisor y oyente) y `RosLogger` no existen en el módulo, aunque la tabla
   de paridad los daba por hechos. Ya está corregida.
5. **Lo siguiente que decide todo son medidas en hardware:** gates G8 (§6).

## 2. Matriz LT × fase (viabilidad)

| LT | Fase 1 · terminal | Fase 2 · cálculo repartido | Fase 3 · DB-TSDF | Fase 4 · autónoma |
|---|---|---|---|---|
| LT1 móviles / Nav2 | **Sí**: teleop con hombre muerto en el puente; metas por `/goal_pose` (nivel 0) o `accion_nav` (doc 32); mapa por teselas (hecho) | **Sí**: proyección de scan, odometría y ensamblado de teselas en la Vita (§5) | Parcial: 2D sobre scan | Por medir |
| LT2 RViz-like (gdviz) | **Parcial**: TF, RobotModel, Map, Path y LaserScan con técnicas 2D/3D sin shaders (doc 31); gdviz necesita 3 archivos del núcleo adaptados (doc 24) | Parcial: decodificación en C (`viz-decode`) si GDScript pasa de 2 ms | — | — |
| LT3 MoveIt 2 | **Parcial**: Servo desde la Vita **no** funciona directo (sello de tiempo y timeout); va por `accion_brazo` del puente (doc 32) | No: la planificación queda en el PC | — | No |
| LT4 URDF | **Sí** (hecho): `tools/urdf2godot` y G1 a 60 FPS (doc 25) | Sí: cinemática directa local desde juntas compactas | — | Sí |
| LT5 simulación | **Sí**: IMU, GPS, odometría y LiDAR 2D por rayos (~180 rayos a 10 Hz, por medir); cámaras y LiDAR 3D solo en PC (doc 28) | Sí: el mismo script en PC y Vita | Entrada de datos | — |
| LT6 drones | **Parcial**: PX4 por su agente uXRCE y `accion_dron` (latido atado al enlace de la Vita, doc 32) | No | — | No |
| LT7 visión | **Sí**: JPEG troceado por el relay; libjpeg-turbo ya está en `libgodot.so`; cajas en formato compacto (doc 28) | Parcial: detector de color en C < 1 ms [I] | — | Por medir |
| LT8 plugins | **Sí [I]**: GDScript se compila en la Vita y `load_resource_pack("ux0:/…")` existe (§4) | — | — | — |

## 3. Presupuestos de partida (asignación de diseño, por medir)

| Recurso | Presupuesto | Fuente |
|---|---|---|
| FPS | 60 en HMI; 30 con todos los displays | doc 31 |
| Triángulos 3D / draw calls | 30 000 / 150 (G1 = 12 633 a 60 FPS, medido) | doc 31, doc 25 |
| Texturas | 16 MiB de los 64 MiB de CDRAM | doc 31, W1 |
| CPU por fotograma | 8 ms GDScript+red · 9 ms envío 3D · 3 ms lienzo | doc 31 |
| RAM | heap del loader 256 MiB; arena de mallas 24 MiB | W1 |
| Red PC → Vita | ≤ 100 KB/s best effort; el relay actual usa ~14 KB/s | doc 27 |
| Red Vita → PC | ~30 KB/s best effort; fiable solo para mensajes pequeños (bloquea al enviar) | doc 27 |

## 4. W10 — Arquitectura abierta: plugins y capa URDF ↔ `ros2_vita`

**Hechos** (W7, revisión de la oleada 1):
- El addon `psvita` exporta los scripts como texto, así que la Vita compila GDScript en cada arranque
  (`platform.gd:151`) [V].
- `GDScript.reload`, `ProjectSettings.load_resource_pack` y `FileAccess`/`DirAccess` sobre `ux0:` están en la
  plantilla [V].
- Las rutas deben ser `ux0:/data/…`, con barra (`ustring.cpp:4293`) [V].
- Que funcione en hardware es [I].

**Decisión propuesta:** plugin = **`.pck` en `ux0:/data/<app>/plugins/`** con un `plugin.json` con estos campos:

| Campo | Contenido |
|---|---|
| `nombre`, `version` | identificación |
| `escena` | escena de entrada (Control 2D o Node3D) |
| `topics` | `[{topic, tipo, qos, rol}]` |
| `esquema` | `.rsch` del plugin |
| `presupuesto` | `{tris, ms, kbps}` |

**Contrato:**
- La app anfitriona carga el `.pck` y el esquema (para que `RosMsg.from_type` conozca los tipos nuevos; hace falta
  que `ros2_vita` admita esquemas acumulados, tarea P1).
- Instancia la escena y le inyecta el `RosNode` compartido (un solo nodo por proceso).
- Comprueba el presupuesto declarado contra el medido y descarga el plugin si lo excede.

Es el modelo de los plugins de gdviz (`GDScript.new()` + `reload`) pero empaquetado, sin compilar código suelto. La
validación es un gate (G8-P). Las plantillas de la sesión paralela (`godot/plantillas/`, doc 29) son el catálogo
natural de plugins.

**Capa URDF:** ADR 0009 y doc 25.
- Escena horneada con los nombres URDF.
- Juntas por array compacto con el orden publicado aparte (`/vita/joints_orden`, fiable + TRANSIENT_LOCAL).
- TF en la Vita cuando exista el P0.

## 5. W11 — Reparto Vita/PC (Fase 2) y prioridades (Fase 4)

**Criterio de corte:** una tarea va a la Vita si cumple las tres condiciones:
- su coste medido es ≤ 2 ms por fotograma en GDScript (o ≤ 5 ms en C con hilo propio);
- su entrada cabe en el presupuesto de red;
- no necesita el grafo ROS completo.

Si no las cumple, va al PC.

| Tarea | Coste estimado en Cortex-A9 | Dónde |
|---|---|---|
| Cinemática directa del robot desde juntas (29 GDL) | < 0,5 ms GDScript [I] | **Vita** (hecho) |
| Integrar odometría / pose 2D | despreciable | **Vita** |
| Ensamblar mapa por teselas → textura (4 Hz) | ~1 ms por tesela en GDScript [I] | **Vita** (hecho) |
| Proyectar LaserScan compacto a 2D | 180 puntos, < 0,5 ms [I] | **Vita** |
| Decodificar JPEG 160×120 | 1–2 ms (libjpeg-turbo del motor) [I] | **Vita** |
| LiDAR 2D simulado por rayos | 50–130 µs por rayo → 180 rayos en 3 fotogramas [I] | Vita (por medir) |
| DB-TSDF 2D (losa) | por medir (T3) | Vita (Fase 3) |
| Decimar o comprimir nubes, OccupancyGrid → teselas, JPEG | — | **PC (relay)** |
| SLAM, Nav2, MoveIt, política RL del G1, inferencia de visión | — | **PC** |

**Prioridades de la Fase 4** (la teleop no se degrada):
1. Entrada, `/cmd_vel` e hilo principal primero.
2. El cálculo pesado va en un hilo nativo del módulo C. Solo tras medir el hilo (E-H8) y con CapUnlocker, que
   libera USER_1/2.
3. Watchdog: si un fotograma pasa de 25 ms, el cálculo cede su turno; si `/cmd_vel` no sale en 100 ms, la HMI lo
   avisa.
4. El robot para solo por la puerta de mando del puente (ADR 0012).

## 6. Backlog de gates G8+ (hardware)

| Gate | Objetivo | Prueba | Verde si | Workshop |
|---|---|---|---|---|
| **G8-G1** | G1 en la Vita | `build/g1-unitree.vpk`, modo marcha | **VERDE (2026-11-11): 60 FPS** | proyecto G1 |
| G8-G1-ros | G1 en vivo | `docker/vita-ros.sh g1` y modo ros | `/g1/estado` ≥ 20 Hz en el HUD, sin cortes en 5 min | W2 |
| G8-relay | Minimapa por relay | `relay` + mapa; modo ros | 42 teselas en < 5 s; ≥ 55 FPS | W2/W8 |
| G8-H7/H8 | NEON y núcleos | hwprobe E-H7/E-H8 (doc 14 §9) | ratio NEON/escalar medido; ¿2.º hilo nativo estable? | W1 |
| G8-mem | RAM real | logs `[memory]`/`[vita-memory]` por FTP | memoria libre con el G1 cargado ≥ 100 MiB | W1 |
| G8-xrce | Techos XRCE | barrido tamaño × QoS × Hz (doc 27 §4) | curva medida; pérdida best effort < 5 % a 25 Hz | W2 |
| G8-render | Presupuesto de render | E-W8-0…6 (doc 31 §6) | 30 000 triángulos y 150 draws a ≥ 30 FPS | W8 |
| G8-rayos | LiDAR por rayos | `w12-raybench` (doc 28) | 180 rayos/100 ms sin bajar de 55 FPS | W12 |
| G8-jpeg | Imagen | JPEG 160×120 por el relay | decodificar ≤ 2 ms; 5 fps de imagen | W12 |
| G8-P | Plugin `.pck` | cargar un `.pck` de `ux0:/data/…/plugins/` | escena y script del plugin funcionan | W10 |
| G8-TF | TF en `ros2_vita` | implementar P0 y `send_transform` de 3 frames | visible en RViz2 a 10 Hz | W4 |
| T3 (DB-TSDF) | Microbenchmark | V4–V32, 1–3 hilos, 333/444 MHz | ms por scan medidos; decide si se sigue | W3 |

## 7. Pendientes [?]

**Se resuelven en el PC:**
- Si el agente respeta la MTU del cliente al subirla a ~1 400 (doc 27).
- Calidad de V4/V8 frente a V16 en los datasets del paper (oráculo en docker, doc 26).
- Paridad C/Rust del futuro `modules/db-tsdf`.
- Esquemas acumulados en `ros2_vita` (para plugins).
- TF y logger P0.
- Clases tipadas T3.2.4.

**Se resuelven en la Vita:**
- Núcleos usables con el shim de pthread (E-H8).
- Si 444 MHz se mantiene con WiFi.
- RAM real.
- Techos de XRCE en WiFi real.
- Coste por rayo y por JPEG.
- Carga de `.pck` desde `ux0:/`.
- Por qué el modo ros del G1 no llegó al agente el 2026-11-11: la app ya muestra el diagnóstico.

## 8. Índice de documentos y ADR de la etapa

docs 24 (portabilidad Ozuba) · 25 (URDF) · 26 (DB-TSDF) · 27 (XRCE y relay) · 28 (sensores y visión) ·
29–30 (plantillas y rendimiento, de la sesión paralela) · 31 (render) · 32 (acciones y puente) · 33 (este).
ADR 0008 (enmendado: el 3D entra en alcance) · 0009 URDF · 0010 DB-TSDF · 0011 render · 0012 puente.
