# 27 — Límites de XRCE por tipo de mensaje y relay en el PC (`vita_relay`)

> **Estado:** workshop W2 cerrado el 2026-11-11 (Opus 5.5, `docs/ia/workshops/posts/W2-xrce.json`). Usa las cifras
> de red de W1 (revisadas: VERIFICADO salvo el techo de recepción, corregido abajo). Tamaños CDR medidos con
> `rosbags` (store ROS2_JAZZY) [V]; frecuencias y anchos de banda en WiFi real **por medir**.
> Marcas: [V] verificado · [I] inferencia · [?] sin confirmar.

## Resumen

- **Best effort:** cabe un mensaje si su CDR ocupa ≤ **488 B** (cabecera de 24 B + MTU de 512,
  `godot/ros2_vita/xrce_transport.cpp:411-415`). Las suscripciones best effort usan un único búfer sin fragmentar
  (`:384`), así que un mensaje mayor **no llega nunca** [V].
- **Fiable:** fragmenta. Al enviar desde la Vita, `_flush` **bloquea el hilo principal**, que es el mismo del render
  (`:247, :416`). Al recibir, la ventana es de 16 huecos de 512 B, con un techo de ≈ **7,5 KiB** por mensaje
  (`input_reliable_stream.c:64-92`). Corrección de la revisión: el límite no es `MAX_RX` (16 KiB) [V].
- **Qué cabe en crudo:** casi nada de RViz. LaserScan de 360 rayos = 1 504 B, JointState de 29 juntas = 1 668 B,
  TF del G1 = 4 796 B, OccupancyGrid 384² = 147 560 B. Caben Odometry (724 B, solo en fiable), PoseStamped (76 B)
  e Imu (316 B) [V].
- **Decisión candidata** (W2, falta su ADR): un nodo **`vita_relay`** en el PC que publica a ritmo fijo el último
  valor recibido, siempre en best effort y en mensajes de ≤ 488 B. Suma ≈ 30 KB/s, dentro del presupuesto de
  100 KB/s. El patrón ya funciona en el G1: `/g1/estado`, Float32MultiArray de 19 valores (76 B) a 25 Hz.
- **Experimento barato:** subir la MTU del cliente a ~1 400 y el historial a 32–64. No se ha comprobado si el agente
  respeta la MTU del cliente [?].
- **Zenoh-Pico:** alternativa solo si hiciera falta fiable grande sin PC; port estimado en 1–3 semanas [I].

---

## 0. Límites de partida (verificados)

| Límite | Valor | Fuente |
|---|---|---|
| MTU transporte | 512 B | `godot/ros2_vita/xrce_transport.cpp:132-140` [V] |
| Best effort (BE) | `len + 24 ≤ 512` ⇒ **≤ 488 B CDR**; si no, `ERR_OUT_OF_MEMORY` | `xrce_transport.cpp:411-415` [V] |
| Fiable TX | fragmenta con `_flush = uxr_run_session_time(10)` ⇒ **bloquea** el hilo principal | `xrce_transport.cpp:247-249,416` [V] |
| Fiable RX | historial 16×512 B ⇒ techo ≈ 16×(512−~24) ≈ **7,5–7,8 KiB** reensamblado; `MAX_RX` 16 KiB no es el cuello | `:136-137,182,300` [V]; techo exacto [I] |
| Fiable lleno al publicar | desvía al BE (`reliable_full++`) | `:418-425` [V] |
| Suscripción BE | `request_data` sobre `best_effort_in` ⇒ el agente no puede fragmentar ahí: mensaje > ~490 B **se pierde** | `:384` [V]; comportamiento del agente [I] |
| Durabilidad | VOLATILE / TRANSIENT_LOCAL soportadas | `:155-158` [V] |
| Poll | 1 vez/frame `uxr_run_session_time(0)` | `:337` [V]; que drene todos los datagramas pendientes [I, upstream `session.c`] |
| Presupuestos (de W1) | TX BE ≈ 1 datagrama/frame ≈ 30 KB/s; RX fiable ≈ 16×500 B/RTT_ef ≈ 120–160 KB/s con RTT 50 ms; WiFi FTP 0,55–1,6 MB/s | W1 Q3/Q1 [I] |

Presupuesto de diseño adoptado (conservador): **RX ≤ 100 KB/s en total** y ≤ ~200 datagramas/s, para no
competir con el render (un solo núcleo). [I]

**Implementado (2026-11-12):** `XrceTransport` copia los mensajes best effort en una cola de 64 y envía uno por
`poll()`. Si se llena descarta el más antiguo; `rclgd.get_transport_info()` expone `be_pending` y `be_dropped`.
Esto evita el `ERR_BUSY` al publicar varios sensores en el mismo fotograma. Los fiables tienen otra cola de 32,
un mensaje por `poll()` y reintento si el stream está lleno (`reliable_pending`/`reliable_dropped`); ya no se desvía
una publicación fiable al stream best effort. Las plantillas usan QoS fiable en PC para scans completos, JPEG, nubes,
odometría, JointState y LowState. Suite host 294/0 y prueba XRCE real de las tres plantillas verdes.

## 1. Tabla por tipo (CDR medido con `rosbags` store ROS2_JAZZY, incluye 4 B de encapsulado) [V]

Frame_ids cortos (`base_scan`, `map`…); nombres más largos suman bytes.

| Mensaje | CDR (B) | ¿BE? | ¿Fiable RX? | Hz sostenible directo [I] | Adaptador PC |
|---|---:|:-:|:-:|---|---|
| LaserScan 360 sin intens. | 1 504 | no | sí (4 frag) | 5–10 (TB3 publica 5) | `scan_compacto`: Int16 cm, 180 rayos (2°) = 376 B → BE 10–15 Hz |
| LaserScan 360 + intens. | 2 944 | no | sí (7 frag) | ≤ 5 | quitar intensidades + idem |
| LaserScan 720 sin intens. | 2 944 | no | sí | ≤ 5 | decimar a 180/360 |
| LaserScan 720 + intens. | 5 824 | no | justo (12 frag) | 1–2, frágil | decimar + quitar intens. |
| OccupancyGrid 384² | 147 560 | no | **no** | 0 | teselas 32×32 a 2 bit (256 B+cab.) BE, deltas |
| OccupancyGrid 1000² | 1 000 104 | no | **no** | 0 | bajar a 0,2 m (250²) + teselas + ventana |
| Path 100 poses | 7 228 | no | al límite | ≤ 1, frágil | `path_compacto`: ≤ 57 pts (x,y) Float32 = 476 B |
| Path 500 poses | 36 028 | no | **no** | 0 | Douglas-Peucker a ≤ 57 pts |
| PointCloud2 1 000 xyz | 12 117 | no | **no** | 0 | vóxel + Int16 cm xyz (6 B/pt) ⇒ 78 pts/datagrama |
| PointCloud2 5 000 xyz(i) | 60–80 k | no | **no** | 0 | proyectar a 2D / vóxel ≥ 10 cm, ≤ 300 pts |
| CompressedImage JPEG 320×240 q50 | ~6–12 k (contenido) [I] | no | justo/no | ≤ 2, frágil | 160×120 q40 (~2–3 k, fiable 5 Hz) o trocear BE |
| Image 160×120 mono8 | 19 248 | no | **no** | 0 | → JPEG, o 80×60 mono (4 848, fiable) |
| TFMessage G1 ~40 frames | 4 796 | no | sí (10 frag) | ≤ 5 | **no enviar TF**: `/g1/estado` 19 floats = 92 B (FK en Godot) |
| TFMessage 1 tf (odom→base) | 108 | sí | sí | 30–60 | filtrar `/tf` a frames útiles |
| TFMessage TB3 ruedas (2) | 212 | sí | sí | 30 | idem; `/tf_static` fiable + TRANSIENT_LOCAL |
| JointState 29 (pos+vel+eff) | 1 668 | no | sí | 10–20 | Float32 29 pos = 132 B BE, 25–50 Hz |
| JointState 29 (solo pos) | 1 196 | no | sí | 10–20 | idem |
| Marker (1 CUBE) | 229 | sí | sí | — | — |
| MarkerArray 50 CUBE | 11 605 | no | **no** | 0 | Float32 8/marcador [id,tipo,x,y,z,yaw,escala,color] ⇒ 14/datagrama |
| Odometry | 724 | no | sí (2 frag; G6 ok) | 20–30 | `pose2d`: 6 floats (x,y,yaw,vx,vy,wz) = 40 B BE |
| PoseStamped | 76 | sí | sí | 60 | ninguno |
| Twist | 52 | sí | sí | 60 | ninguno |
| Imu | 316 | sí | sí | 30–60 | ninguno (TX Vita ya verificado) |
| Float32MultiArray N (layout vacío) | 16 + 4N | N ≤ 118 | N ≲ 1 900 [I] | BE 25–60 | ventana/troceo si N > 118 |
| Int16MultiArray N | 16 + 2N | N ≤ 236 | — | — | formato compacto base |
| UInt8MultiArray N | 16 + N | N ≤ 472 | — | — | troceo de blobs (PNG/JPEG) |

Nota: un `dim[]` en `layout` añade ~16 B + etiqueta por dimensión; enviar layout vacío. [V cálculo]

## 2. Diseño mínimo de `vita_relay` (paquete Python rclpy, en `docker/`)

Un solo nodo con módulos activables por parámetro (`modulos:=[scan,pose,mapa,path,...]`). Entrada con la QoS
del robot (sensor data BE para scan; fiable para mapa/plan). **Salida siempre BE, ≤ 488 B, a frecuencia fija con
"último valor"** (un timer, no reenviar en el callback) salvo lo marcado.

| Salida | Tipo | QoS | Hz | Formato |
|---|---|---|---|---|
| `/vita/scan_compacto` | Int16MultiArray | BE depth 1 | 10 | `[seq, ang_min_cdeg, inc_cdeg, n, r0..r179]` cm, 0 = sin dato; 184 int16 = 384 B |
| `/vita/pose2d` | Float32MultiArray | BE | 30 | `[x,y,yaw,vx,vy,wz]` de `/odom` o TF map→base |
| `/vita/estado` (patrón G1) | Float32MultiArray | BE | 25 | como `/g1/estado`: 19 floats (`docker/g1/g1_sim.py:13-15,187,211`) |
| `/vita/joints` | Float32MultiArray | BE | 25 | 29 posiciones en orden fijo del URDF (orden publicado una vez en `/vita/joints_orden` fiable+TRANSIENT_LOCAL) |
| `/vita/mapa_tesela` | UInt8MultiArray | BE | ≤ 20 teselas/s | `[ver_mapa u16, tx u8, ty u8, res_cm u8, ...]` + 32×32 celdas a 2 bit (libre/ocupado/desconocido) = 256 B; envía primero las cercanas al robot y luego solo las cambiadas (hash por tesela) |
| `/vita/mapa_meta` | Float32MultiArray | **fiable + TRANSIENT_LOCAL** | al cambiar | `[res, ancho, alto, origen_x, origen_y, n_teselas, version]` |
| `/vita/path_compacto` | Float32MultiArray | BE | 2 | `[n, x0,y0,…]` tras Douglas-Peucker (ε 5 cm) y recorte a ≤ 57 pts desde la pose actual |
| `/vita/marcadores` | Float32MultiArray | BE | 5 | 8 floats/marcador, troceado `[seq, trozo, n_trozos, ...]` |
| `/vita/nube2d` | Int16MultiArray | BE | 5 | vóxel 10 cm, xyz cm, ≤ 78 pts por trozo |
| `/vita/camara` | CompressedImage o UInt8MultiArray troceado | fiable (1 msg ≤ 3 KB) o BE troceado | 5 | JPEG 160×120 q40 (re-codificado con OpenCV) |

Entradas desde la Vita (TX, presupuesto ~30 KB/s BE): `/cmd_vel` (52 B), `/vita/imu` (316 B), `goal_pose`
PoseStamped fiable (76 B) → el relay lo reenvía a Nav2 `navigate_to_pose` (acción; XRCE no tiene acciones en
ros2_vita) y devuelve el estado como Float32 `[estado, dist_restante]`.

Reglas: ninguna salida > 488 B; suma ≤ 100 KB/s (lo anterior ≈ 10×384 + 30×40 + 25×92 + 20×270 + 2×476 +
5×3000 ≈ 30 KB/s); el relay mide y publica su propio `/vita/relay_bw`.

## 3. Alternativas registradas

| Opción | Pros | Contras | Coste |
|---|---|---|---|
| A. Subir MTU a ~1 400 (< 1 472 sin fragmentación IP) e historial a 32–64 | techo RX 45–90 KB por mensaje; menos cabeceras; cambio de 2 constantes + `-DUXR_CONFIG_CUSTOM_TRANSPORT_MTU` | recompilar cliente (`vita-app/scripts/`) y plantilla Godot; **el agente fragmenta con su propia MTU** [?]: puede que solo mejore TX; memoria estática 2×64×1 400 ≈ 180 KB; fragmentos más grandes = más pérdida por datagrama en WiFi | 0,5–1 día + prueba |
| B. Zenoh-Pico (UDP o TCP) + `zenoh-bridge-ros2dds`/rmw_zenoh (ya hay puente en `docker/vita-ros.sh:73-78`) | fragmentación propia en BE; TCP da fiabilidad sin ventana de 8 KiB; sin agente XRCE | **portar la capa de plataforma** (hilos, sockets sceNet, reloj) de zenoh-pico a la Vita; reescribir `xrce_transport.cpp` tras la interfaz de transporte; CDR igual de grande: el ancho de banda no cambia | 1–3 semanas [I] |
| C. Solo relay (este diseño) | sin tocar la Vita; robusto a pérdidas; formatos pensados para GDScript | lógica en el PC; no es "ROS puro" en la Vita | 2–4 días |

Recomendación [I]: **C ahora; A como experimento barato después** (medir si el agente respeta la MTU mayor);
B solo si se necesita fiable > 8 KiB sin PC intermedio.

## 4. Prueba en hardware (microbenchmark tamaño × QoS)

Lado Vita (reto del usuario): proyecto Godot `w2-bench` que se suscribe a `/w2/rx` (UInt8MultiArray, QoS
parametrizable) y publica cada segundo `/w2/stats` Float32MultiArray `[recibidos, perdidos_por_seq, fps,
reliable_full, topic_dropped]` (`get_diagnostics`, `xrce_transport.cpp:453`). Los 4 primeros bytes de `data`
= seq.

Lado PC (fish):
```fish
docker/vita-ros.sh up
set N 470; set HZ 30; set QOS best_effort
docker/vita-ros.sh shell   # dentro (bash): script python que publica UInt8MultiArray de N bytes a HZ con la QoS
docker/vita-ros.sh echo /w2/stats
```
Barrido: N ∈ {64, 256, 470, 488, 489, 1 500, 4 000, 7 000, 7 700, 8 000} × QoS {BE, fiable} × HZ {10, 30, 60};
y en TX `/w2/tx` desde la Vita con `ros2 topic hz /w2/tx` y `ros2 topic bw /w2/tx`. Confirma: corte BE en
488/489, corte fiable RX ~7,5–7,8 KiB, kB/s fiable vs RTT (anotar `ping` de W1), caída de FPS al fragmentar en TX.
