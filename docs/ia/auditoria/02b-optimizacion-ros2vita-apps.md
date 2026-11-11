# Auditoría 02b — Optimización de la capa de integración en la Vita (ros2_vita + apps)

**Fecha:** 2026-11-01 · **Equipo:** Optimización B · **Modo:** solo lectura (no se ha compilado ni medido nada).
**Ámbito:** `godot/ros2_vita/` (C++), `godot/loader-patches/`, `godot/vitasdk-stubs/`, `godot/g6-hmi/main.gd`,
`godot/g7-imu/{main,nivel}.gd`, `vita-app/src/{main,uxr_glue,netlog}.c`, `tools/build-godot-template.sh`, y como
dependencias directas `modules/{net-udp,microros-transport,msg-schema}/impl-c` y el cliente XRCE v2.4.3 vendorizado en
`vita-app/third_party/_build/Micro-XRCE-DDS-Client` (sin parches: `git log` = `d44dc3f Release v2.4.3`).
Versión corta para el usuario: `docs/informes/02b-optimizacion-ros2vita-apps.md`.

Convención: **[C]** = comprobado leyendo el código citado; **[H]** = hipótesis (no medida en host ni en hardware);
las cifras de coste en µs son estimaciones de orden de magnitud para un Cortex-A9 a 444 MHz, siempre **[H]**.

---

## 0. Resumen ejecutivo

1. **Todo corre en el hilo principal de Godot**, una vez por frame (`rclgd::_pump`, conectado a
   `SceneTree::process_frame`, `ros_runtime.cpp:643-652`) **[C]**. Bien para G6/G7, pero hereda tres bloqueos largos
   del hilo principal (creación de sesión hasta **10 s**, creación de cada entidad hasta **2 s**, cierre de sesión
   hasta **10 s**) y una espera de **10 ms** por mensaje grande con el stream fiable lleno.
2. **El coste dominante por mensaje no es la red, es el árbol de Variants**: cada mensaje recibido construye y
   tira ~3 árboles completos de `RosMsg` (≈43 objetos `RefCounted` por `nav_msgs/Odometry`, de los que solo se usan
   11), y cada campo codificado/decodificado crea un `StringName` desde UTF-8 (búsqueda en la tabla global con
   mutex). Los arrays `float64[N]` empaquetados se convierten a `Array` de Variants en cada `publish` aunque el
   comentario diga «sin copia» (`ros_msg.cpp:689-723`).
3. **Hipótesis fuerte sobre el stream fiable de salida**: con el patrón `uxr_run_session_time(0)` cada frame, el
   cliente XRCE v2.4.3 **nunca envía HEARTBEAT** mientras los frames duren < 100 ms (ver §3.1). Si el agente solo
   confirma (ACKNACK) en respuesta a un HEARTBEAT, el stream fiable se llena en < 1 s y **todo** `/cmd_vel` sale por
   el desvío *best effort* (`xrce_transport.cpp:418-425`). Se mide gratis con el contador `reliable_full`, que ya
   existe pero ninguna app pinta.
4. **MTU 512** obliga a trocear `/odom` (720 B, 2 datagramas, bitácora `docs/06:107`) y limita *best effort* a un
   mensaje por frame. Subirla a ~1400 B (por debajo de 1472 = 1500 − IP − UDP) elimina la fragmentación de todo lo
   actual con +~30 KiB de RAM.
5. **2 MiB de RAM desperdiciados** en pools de `sceNetInit` que nunca se usan (el cargador ya inicia la red).
6. **Sin detección de caída del agente ni reconexión**: si el agente se reinicia, la app sigue diciendo
   «ROS 2 conectado» y publica al vacío.

---

## 1. Mapa de hilos y del frame

| Qué | Hilo | Frecuencia | Bloquea | Cita |
|---|---|---|---|---|
| `rclgd::init` → `XrceTransport::start` | principal (desde `_ready` tras un `await`) | 1 vez | sí: `uxr_create_session` reintenta 10 × 1000 ms (`UXR_CONFIG_MAX_SESSION_CONNECTION_ATTEMPTS 10`, `MIN_SESSION_CONNECTION_INTERVAL 1000`, `config.h:46-47`; bucle en `session.c:734-760`) + `_wait` 2000 ms | `xrce_transport.cpp:252-319`, `g6-hmi/main.gd:51-56` |
| `create_publisher` / `create_subscription` | principal | 1 vez por endpoint | sí: 2 ida-vuelta (topic + writer/reader), cada una ≤ 2000 ms (`ENTITY_TIMEOUT_MS`) | `xrce_transport.cpp:141, 196-225, 341-387` |
| `rclgd::_pump` → `poll()` | principal, señal `process_frame` | 1 por frame (30/60 Hz) | no: `uxr_run_session_time(0)`; vacía todo lo recibido con `recv` `DONTWAIT` | `ros_runtime.cpp:685-692`, `xrce_transport.cpp:335-339`, `net_udp.c:255-258` |
| `_on_topic` (callback uxr) | principal, dentro de `poll` | por mensaje | no | `xrce_transport.cpp:227-244` |
| entrega a GDScript (`deliver`) | principal, en `_pump` tras `poll` | por mensaje | no | `ros_runtime.cpp:693-714` |
| timers (`RosTimer::tick`) | principal, en `_pump` | **como máximo 1 disparo por frame** | no | `ros_runtime.cpp:381-390, 715-724` |
| `publish` → `_flush` (mensaje > MTU con stream lleno) | principal | por mensaje grande | **sí, 10 ms** | `xrce_transport.cpp:247-249, 416` |
| `shutdown` → `uxr_delete_session` | principal (también desde `~rclgd`) | 1 vez | **sí, hasta 10 s** si el agente no responde (`session.c:265-279` con 10 reintentos) | `ros_runtime.cpp:627-641`, `xrce_transport.cpp:321-325` |
| worker pool de Godot | 2 hilos (`threading/worker_pool/max_threads=2`) | — | — | `g6-hmi/project.godot`, `g7-imu/project.godot` |

No hay `sceKernelCreateThread` propio en `ros2_vita` **[C]** (grep vacío). El patrón que recomienda `docs/14` §4
(hilo de red productor de `msg-ring`) **no se usa**, aunque `msg_ring.c` se compila dentro de `libgodot.so`
(`SCsub:60-62`) sin que nadie lo llame (código muerto) **[C]**.

**Orden dentro del frame [H]:** en Godot 4, `SceneTree::process` emite `process_frame` *antes* de llamar a los
`_process` de los nodos. Si es así, el timer de G7 publica la IMU leída en el `_process` del frame **anterior**
(`g7-imu/main.gd:167-190` lee; `_publicar` usa `acel_ros`): +1 frame de latencia (16–33 ms). Comprobar en
`scene/main/scene_tree.cpp` del port o con un `print(Engine.get_process_frames())` en ambos sitios.

**Consecuencia de los timers por frame [C]:** `RosTimer::tick` dispara como mucho una vez por llamada
(`ros_runtime.cpp:385-388`). Con `-p hz:=50` en G7 a 30 fps se publican **30 Hz**, no 50; en el host funcionó porque
iba a > 50 fps (bitácora `docs/06:58`). El 19,5 Hz medido de `/cmd_vel` en G6 (`docs/06:105`) encaja con frames
ocasionales > 50 ms que hacen saltar la regla «no disparar en ráfaga» (`ros_runtime.cpp:386-388`) **[H]**.

---

## 2. Rutas calientes, función a función

### 2.1 Publicar (GDScript → CDR → datagrama)

Cadena: `RosPublisher::publish` (`ros_runtime.cpp:306-316`) → `RosMsg::serialize` (`ros_msg.cpp:742-767`) →
`msg_schema_encode` + callbacks `e_*` (`ros_msg.cpp:620-738`) → `XrceTransport::publish` (`xrce_transport.cpp:406-429`)
→ `uxr_prepare_output_stream` + `ucdr_serialize_array_uint8_t` (copia) → en el siguiente `poll`,
`uxr_flash_output_streams` → `cb_write` → `microros_transport_write` → `net_udp_send` → `sceNetSend`.

| # | Función / línea | Memoria por mensaje | CPU | Problema | Propuesta |
|---|---|---|---|---|---|
| P1 | `main.gd` G6:100, G7:201 `RosMsg.from_type(...)` cada publicación | Twist: 3 objetos RefCounted + 3 HashMap; Imu: 6 objetos + 3 `PackedFloat64Array(9)` + HashMaps | `init_idx` recursivo (`ros_msg.cpp:200-214`), `String::utf8` del nombre del tipo y de cada campo, `StringName(...)` por campo; `msg_schema_find_type` lineal con `strcmp` (`msg_schema.c:125-139`) | árbol nuevo 20–30 veces/s para tirarlo | **Reutilizar un mensaje** creado en `_ready` (el `publish` serializa al instante, `ros_runtime.cpp:313`). En C++: caché `HashMap<String,uint32_t>` de tipos y `Vector<String>` de nombres de tipo |
| P2 | G7:202 `node.now()` | +1 `RosMsg` Time (`ros_runtime.cpp:498-506`) | `from_type` + 2 `set_member` | objeto efímero por publicación | con mensaje reutilizado: escribir `m.header.stamp.sec/nanosec` (o añadir `RosNode.stamp(msg)` en C++) |
| P3 | G7:204 `PackedFloat64Array(SIN_ORIENTACION)` | Array const → packed (9 Variants) y en `_coerce` **packed → `Array` → packed** (`ros_msg.cpp:281-303`) | ~3 conversiones de 9 elementos | constante reasignada 30 veces/s | asignarla una vez (mensaje reutilizado) y en `_coerce` atajo: si `v.get_type()` ya es el packed canónico y la longitud vale, devolver `v` tal cual |
| P4 | `RosMsg::_set` → `_find_field` (`ros_msg.cpp:239-255`) | `String(p_name).utf8()` = 1 malloc por asignación | búsqueda lineal con `strcmp` sobre los campos | cada `m.x = ...` en GDScript | tabla por tipo `HashMap<StringName,uint16_t>` construida al cargar el esquema |
| P5 | `e_prim`, `e_prim_array`, `e_array_len`, `e_begin_struct`, `e_string` (`ros_msg.cpp:629, 651, 674, 689, 730`) | `StringName(String::utf8(name))` **por campo y mensaje**: decodifica UTF-8, hash, **mutex global de StringName** | Imu ≈ 21 campos ⇒ 21 búsquedas; Odometry ≈ 30 | el nombre viene del pool de cadenas del esquema (puntero estable) | al cargar el esquema, precalcular `HashMap<const char*,StringName>` (clave = puntero, hash trivial) o `Vector<StringName>` por fila de campo; los callbacks la consultan |
| P6 | `e_prim_array` (`ros_msg.cpp:686-724`) | ruta «directa» solo para `U8`, y aun así copia a `scratch`; para `F64` hace `Array a = v` ⇒ **36 Variants por covarianza** (Odometry ×2, Imu ×3 de 9) | conversión + `_store_le` elemento a elemento | el comentario «sin copia» no se cumple | atajos sin conversión para `PackedFloat64Array`/`PackedFloat32Array`/`PackedInt32Array`/`PackedByteArray` (en ARM LE el layout ya es el del CDR): `*data = packed.ptr()` y guardar el packed en el contexto para que viva hasta el `memcpy` del codificador |
| P7 | `RosMsg::serialize` (`ros_msg.cpp:748-757`) | `out.resize(1024)` + `resize(written)` = 1–2 malloc; si > 1 KiB, re-codifica entero duplicando | 1 pasada (o varias) | Odometry y mensajes > 1 KiB codifican 2 veces | buffer reutilizable por `RosPublisher` (`Vector<uint8_t>` miembro) que recuerde el tamaño del último mensaje; o calcular tamaño y codificar directamente en el `ucdrBuffer` de `uxr_prepare_output_stream` (quita la copia de P8) |
| P8 | `XrceTransport::publish` (`xrce_transport.cpp:427`) | copia `p_data` → hueco del stream | memcpy | segunda copia | ver P7 (opcional, ganancia pequeña) |
| P9 | `RosPublisher::publish` (`ros_runtime.cpp:311`) | — | comparación de `String` del tipo por publicación | menor | comparar `type_idx` (entero) |
| P10 | `XrceTransport::publish` *best effort* (`xrce_transport.cpp:425`) | buffer BE = 512 B (`BEST_EFFORT_BUF`) | — | **un solo mensaje BE por frame**: el segundo `uxr_prepare_output_stream` falla (`output_best_effort_stream.c:40-50`, no vacía solo) ⇒ `ERR_BUSY` + `ERR_FAIL` que imprime | ante el fallo, `uxr_flash_output_streams(&session)` y reintentar una vez |
| P11 | `ERR_FAIL_*` en `publish` (`xrce_transport.cpp:414-425`) | — | cada error escribe en `ux0:data/gxm3d/godot_stderr.log` (bitácora `docs/06:73`) | a 20–60 Hz, E/S a la tarjeta en el hilo principal **[H]** | limitar: contar en `g_diag` y avisar 1 vez/s |

### 2.2 Recibir (datagrama → GDScript)

Cadena: `poll` → `uxr_run_session_time(0)` (`session.c:321-339`) → `listen_message_reliably` (`session.c:686-732`) →
`recv_custom_msg` (`custom_transport.c:58-97`) → `cb_read` → `net_udp_recv` (`sceNetRecv` `DONTWAIT`) →
`_on_topic` (`xrce_transport.cpp:227-244`) → `rclgd::_rx_trampoline` (`ros_runtime.cpp:669-683`) → `_pump`
(`:693-714`) → `RosSubscriber::deliver` (`:325-341`) → `RosMsg::deserialize` (`ros_msg.cpp:580-592`) →
`callback.call(msg)`.

| # | Función / línea | Memoria por mensaje | Problema | Propuesta |
|---|---|---|---|---|
| R1 | `_on_topic` `static uint8_t buf[MAX_RX]` (16 KiB) + `ucdr_deserialize_array_uint8_t` | copia 1 (necesaria si hubo fragmentos, `docs/06:113`) | correcto; `MAX_RX` 16 KiB > lo que el stream fiable de entrada puede reconstruir (16 × 512 B ≈ 8 KiB) | dejar; documentar el límite real (≈ `RELIABLE_HISTORY × (MTU − cabeceras)`) |
| R2 | `_rx_trampoline` | `RxItem` con `Vector<uint8_t>` (malloc + copia 2) + nodo de `List` (malloc) + `MutexLock` | mutex innecesario hoy (mismo hilo), malloc por mensaje | sustituir `List<RxItem>` por **`msg_ring`** (ya compilado; SPSC sin malloc; política «se descarta el nuevo» documentada en `msg_ring.h`) o, mínimo, un anillo de `Vector` reutilizados |
| R3 | `_pump` `local = inbox` (`ros_runtime.cpp:694-699`) | copia la lista entera (nuevos nodos) y 2 `MutexLock` por elemento (`:701-709`) | asignaciones por frame | intercambiar listas (`swap`) o extraer con `pop_front`; resolver `subs` una vez |
| R4 | `deliver` (`ros_runtime.cpp:329-336`) | `from_type` = **árbol completo por defecto** (Odometry: 11 objetos + 2 × `PackedFloat64Array(36)`) + `PackedByteArray` (malloc + **copia 3**) | el árbol por defecto se tira: `deserialize` lo sustituye (`ros_msg.cpp:590`) | `RosMsg::decode_new(type_idx, ptr, len)` que devuelva directamente la raíz del decodificador; `deserialize(const uint8_t*, size_t)` sin `PackedByteArray` |
| R5 | `d_begin_struct` (`ros_msg.cpp:453-472`) | `m->init_idx(type_idx)` **construye los valores por defecto de todo el subárbol** y el decodificador los pisa uno a uno | Odometry: la raíz del decoder crea otros 11 objetos; cada hijo vuelve a crear el suyo ⇒ **≈ 32 objetos tirados** + 4 covarianzas de 36 rellenas a 0 | `init_shallow(type_idx)` (solo `type_idx`/`ros_name`, sin miembros) para el decodificador: recorre todos los campos y los rellena todos |
| R6 | `d_prim`, `d_string`, `d_prim_array`, `d_begin_struct` (`:463, 482, 491, 552`) | `StringName(String::utf8(name))` por campo (como P5) | ídem | ídem P5 |
| R7 | `init_idx` `ros_name = String::utf8(name)` (`ros_msg.cpp:205`) | 1 String por objeto | se repite por cada objeto anidado | `Vector<String>` de nombres de tipo al cargar el esquema (copia CoW = refcount) |
| R8 | `deserialize` `members = ctx.root->members` (`ros_msg.cpp:590`) | copia del HashMap | innecesaria con R4 | ver R4 |
| R9 | `d_prim_array` BOOL (`:536-539`) | `Array.push_back` por elemento | menor | `resize` + escritura |

**Recuento estimado para `/odom` a 62,5 Hz [H]:** 43 objetos `RefCounted` creados por mensaje (≈ 2700/s), 6
`PackedFloat64Array(36)` (2 útiles), ~30 `StringName` desde UTF-8, 3 copias del payload, 2 mallocs de cola. Si
crear+destruir un objeto Godot con su HashMap cuesta ~10–20 µs en el A9, solo eso son **0,4–0,9 ms por mensaje,
≈ 3–6 % de un núcleo**. Con R4+R5+R6 baja a 11 objetos y 0 `StringName` nuevos (estimación ÷3–÷4).

### 2.3 Sesión y red (XRCE)

| # | Punto | Estado | Riesgo / coste | Propuesta |
|---|---|---|---|---|
| X1 | Heartbeat del stream fiable de salida | `uxr_update_output_stream_heartbeat_timestamp` (`output_reliable_stream.c:195-220`) pone `next_heartbeat_timestamp = now + 100 ms` **en cada llamada** y solo dispara si `now >= next`; `listen_message_reliably` la llama al entrar (`session.c:693-711`) | con `poll()` cada 16–33 ms el plazo nunca vence ⇒ **no se envía HEARTBEAT** **[C]**. Si el agente solo manda ACKNACK al recibir HEARTBEAT **[H]**, `last_acknown` no avanza, el stream (16 huecos) se llena y todo va por *best effort*. Para mensajes > MTU no hay desvío: `_flush` bloquea 10 ms y se descarta (`write_access.c:227-243`) | **Medir primero**: pintar `get_transport_info().reliable_full` en el HUD de G6; si crece ~20/s tras el primer segundo, confirmado. Arreglos: (a) parche de 1 línea en el cliente (no rearmar el plazo si ya estaba armado), (b) hilo de red con `uxr_run_session_time(…, ≥100)`, o (c) declarar `/cmd_vel` BEST_EFFORT (ya es lo que pasa de facto) |
| X2 | MTU 512 (`UXR_CONFIG_CUSTOM_TRANSPORT_MTU`, `config.h:60`) | Odometry 720 B ⇒ 2 fragmentos; BE solo 1 msg/frame; `RELIABLE_SLOT = MTU` | más datagramas, más `sceNetRecv`, reensamblado no contiguo (el bug de G6) | compilar el cliente con `-DUCLIENT_CUSTOM_TRANSPORT_MTU=1400` en `vita-app/scripts/build-xrce-client-vita.sh`; la MTU viaja al agente en CREATE_CLIENT (`session.c:243`, `session_info.c:88`). Coste: 2 × 16 × 1400 ≈ 44 KiB. Probar en host y luego en Vita (WiFi) |
| X3 | Creación de sesión | `uxr_create_session` = 10 reintentos × 1 s | pantalla congelada hasta 10 s sin agente (el `await` de `main.gd:51` solo pinta el texto antes) | `uxr_create_session_retries(&session, 3)` y parámetro `-p connect_retries:=N`; o hilo |
| X4 | Cierre | `stop()` → `uxr_delete_session` (10 reintentos) | **hasta 10 s colgado al salir** con el agente caído **[C por código; H en efecto]** | `uxr_delete_session_retries(&session, 0)` (envía y no espera; `session.c:740-744`) |
| X5 | Caída / reinicio del agente | no hay `uxr_ping_agent_*`, ni contador de silencio, ni señal | la app dice «ROS 2 conectado» (`g6-hmi/main.gd:72,144`) y publica al vacío; para teleop, el robot depende de su propio *watchdog* | (1) contador «ms desde el último paquete recibido» en `g_diag` (en G6 llega `/odom` continuo; en G7 no llega nada ⇒ hace falta ping); (2) ping cada 1–2 s desde un hilo o con `uxr_ping_agent_session(&session, 20, 1)`; (3) reconexión: recordar `(topic, tipo, QoS, ids)` de cada endpoint y recrearlos con los **mismos ids** (`UXR_REPLACE`) para que `RosPublisher::pub_id` siga valiendo; (4) señal `rclgd.connection_changed` |
| X6 | `net_udp_recv` con timeout > 0 (`net_udp.c:259-264`) | `sceNetSetsockopt(SO_RCVTIMEO)` **en cada recepción** | hoy no ocurre en el pump (timeout 0), sí en `_wait`, `_flush` y en `vita-app` (50 ms) | cachear el último timeout en `net_udp_socket` (cambio dual C+Rust con su prueba de paridad) |
| X7 | Pools de `sceNetInit` | cargador: 1 MiB estático (`0001-…patch:66`, el que vale); `net_udp.c:40` `g_net_pool` 1 MiB en `.bss` de `libgodot.so`; `vita_net_init` `memalign` 1 MiB (`xrce_transport.cpp:99-104`) que `sceNetInit` rechaza con EBUSY y no se libera | **2 MiB perdidos** **[C]** (también la versión Rust: `net-udp/impl-rust/src/lib.rs:150-153`) | en `vita_net_init`: no reservar pool (la red ya está hecha) o liberarlo si `rc_netinit == 0x80410110`; en `net-udp`: pool opcional/por puntero del llamador (cambio dual) |
| X8 | Contadores `g_diag` (`xrce_transport.cpp:43-55`) | `int`, globales, sin atómicos | correcto con un hilo; **carrera** si se añade hilo de red | `std::atomic<uint32_t>` o `SafeNumeric` de Godot cuando haya hilo |
| X9 | Tamaños | `reliable_out/in` 2 × 8 KiB, BE 512 B, `MAX_RX` 16 KiB estático, objeto en heap (`memnew`) | ~25 KiB, despreciable en 512 MiB | ajustar con X2 |
| X10 | Clave de cliente (`xrce_transport.cpp:282-284`) | `ticks_usec ^ unix_time*φ` | bien; con reconexión, reutilizar la misma clave | — |

### 2.4 Ciclo de vida y carreras (bugs)

| # | Bug | Cita | Gravedad | Arreglo |
|---|---|---|---|---|
| B1 | Un timer cuyo callback llama a `rclgd.shutdown()` vacía `timers` mientras `_pump` lo recorre ⇒ `timers[i]` fuera de rango ⇒ `CRASH_BAD_INDEX` | `ros_runtime.cpp:640, 717-723` | media (caso límite, cierre de app) | iterar sobre una copia o salir si `!running` tras cada `tick` |
| B2 | Tras `shutdown()` + `init()`, un `RosPublisher` viejo conserva `pub_id`; el transporte nuevo reinicia `next_id = 1` ⇒ el viejo publica/borra el endpoint de otro | `ros_runtime.cpp:315, 318-323`; `xrce_transport.cpp:191` | baja | generación de sesión en `rclgd` y comprobarla en `publish`/destructores |
| B3 | Los timers se recorren al revés (`for i = size-1 .. 0`): con dos timers que vencen en el mismo frame, dispara antes el creado después | `ros_runtime.cpp:717` | baja (orden no documentado) | recorrer hacia delante con borrado compacto |
| B4 | `RosPublisher::publish` ignora el `Error` del transporte: GDScript no sabe si se envió | `ros_runtime.cpp:315` | baja | devolver `Error` (rclgd devuelve void: mantener API y contar en `get_transport_info`) |
| B5 | `/cmd_vel` QoS por defecto RELIABLE en G6, pero de facto puede ir por BE (X1) sin que el HUD lo diga | `g6-hmi/main.gd:65` | media (diagnóstico engañoso) | pintar `reliable_full` |
| B6 | Mensaje > MTU en un publisher BEST_EFFORT ⇒ `ERR_FAIL` en cada publicación (spam de log) | `xrce_transport.cpp:414-415` | baja hoy (Imu 320 B cabe) | rechazar en `advertise` si el tipo no tiene límite, o contar y avisar 1 vez |
| B7 | `_on_topic` busca el datareader recorriendo todas las suscripciones | `xrce_transport.cpp:230` | ninguna con 1–3 subs | `HashMap<uint16_t,int>` por id de objeto si crecen |

### 2.5 GDScript de las apps

| # | Archivo:línea | Coste por frame | Propuesta | Impacto |
|---|---|---|---|---|
| G1 | `g6-hmi/main.gd:145-148` `hud.text = ...` cada frame | 4 `%` + concatenaciones; si el texto cambia, `Label` re-*shapea* 4 líneas con el TextServer **[H: 0,5–2 ms en el A9]** | refrescar a 5–10 Hz (acumular `delta`) | medio |
| G2 | `g7-imu/main.gd:239-259` `_pintar_hud` cada frame (10 líneas con números que cambian siempre por el ruido del sensor) | ídem ×2,5 | ídem; los valores crudos se pueden pintar a 5 Hz | medio |
| G3 | `g6-hmi/main.gd:149, 175-176` `queue_redraw()` cada frame + **600 `draw_line`** del rastro | 600 comandos de canvas por frame | `draw_polyline` (1 comando) y el rastro en un `Node2D` hijo con `transform` (moverlo no exige redibujar; solo redibujar al añadir puntos) | medio |
| G4 | `g6-hmi/main.gd:100` y `g7-imu/main.gd:201-204` `from_type` + `now()` + covarianza por publicación | ver P1–P3 | reutilizar el mensaje | medio |
| G5 | `g6-hmi/main.gd:131-132` `rastro.remove_at(0)` con 600 puntos | memmove de 4,8 KiB por `/odom` | anillo con índice, o aceptar (barato) | bajo |
| G6 | `g7-imu/nivel.gd:270-273` setter con `queue_redraw` cada frame + `draw_string` | redibujo del control entero | redibujar solo si cambia > umbral | bajo |
| G7 | `g7-imu/main.gd:158-162` `_a_ros` con `Array` sin tipo (`ejes`) | indexación con Variants, 2 veces/frame | `PackedInt32Array` + `PackedFloat32Array` o `Basis` precalculada (una multiplicación de matriz) | bajo |

### 2.6 Compilación y cargador

| # | Punto | Cita | Propuesta | Riesgo |
|---|---|---|---|---|
| C1 | Plantilla con `optimize=size` (-Os) para todo, incluido `ros2_vita` y `msg_schema.c` | `build-godot-template.sh:74` | `env_ros.Append(CCFLAGS=["-O2"])` solo en `SCsub` del módulo (el `.so` crece poco) **[H: +10–30 % en codificar/decodificar]** | bajo; medir tamaño y `verify_runtime.py` |
| C2 | NEON/VFP: no se ve en este repo qué `-mfpu` usa la plataforma del port | — | comprobar con `arm-vita-eabi-readelf -A libgodot.so` (`Tag_Advanced_SIMD_arch`) | — |
| C3 | Parche del cargador: red temprana con pool de 1 MiB | `0001-…patch:61-78` | correcto y necesario (UID_RL_OVERFLOW, `docs/06:153-156`); es el único pool que debe quedar (X7) | — |
| C4 | `dlfcn.h` stub | `vitasdk-stubs/dlfcn.h` | correcto; sin impacto de rendimiento | — |
| C5 | Sin TLS en el `.so` (`docs/18:81-82`) | — | si se crea hilo de red: nada de `thread_local`; los `static` de `_on_topic`/`g_diag` deben quedarse en un solo hilo o protegerse | — |

### 2.7 `vita-app/` (Fase 1, histórico)

- Bucle con `uxr_run_session_time(&session, 50)` (`main.c:399`): fija el bucle (UI incluida) a ~20 Hz y bloquea el
  dibujo 50 ms por vuelta. Streams de 4 × 4096 B con MTU 512 (`main.c:67-68, 199-202`): cada hueco puede ocupar
  hasta 4 KiB, así que un datagrama puede superar la MTU declarada (UDP lo acepta) y nunca fragmenta **[C]**.
- `netlog_printf` usa 512 B de pila y un `sceNetSend` por línea (`netlog.c:30-41`): bien para logs esporádicos.
- `uxr_glue.c` y `microros_transport.c` son adaptadores 1:1 sin coste.
- Es la referencia de que el patrón «hilo único» funciona; no merece optimización (histórico).

---

## 3. Detalle de las hipótesis clave

### 3.1 HEARTBEAT del stream fiable (X1)

Lectura de `output_reliable_stream.c:195-220` (v2.4.3 sin parches):

```c
if (0 > uxr_seq_num_cmp(stream->last_acknown, stream->last_sent)) {
    if (0 == stream->next_heartbeat_tries)      stream->next_heartbeat_tries = 1;
    else if (current_timestamp >= stream->next_heartbeat_timestamp) { tries++; must_confirm = true; }
    stream->next_heartbeat_timestamp = current_timestamp + MIN_HEARTBEAT_TIME_INTERVAL;   // SIEMPRE
}
```

`listen_message_reliably` (`session.c:693-711`) lo llama en cada vuelta. Con `poll(0)` cada frame
(`xrce_transport.cpp:337`), la diferencia entre llamadas es 16–33 ms < 100 ms ⇒ `must_confirm` nunca es verdad. El
diseño de upstream presupone esperas bloqueantes (p. ej. `uxr_run_session_until_confirm_delivery`).
**Contraindicio:** la bitácora dice que con 4 huecos el stream «se llenaba antes de que llegara la confirmación»
(`docs/06:115`), lo que sugiere que alguna confirmación sí llega (¿ACKNACK espontáneo del agente, o en los frames
largos del arranque?), y `vita-app` publicó `/cmd_vel` fiable a 20 Hz con 4 huecos durante el Objetivo 2. Por eso
queda como **hipótesis a medir**, no como bug confirmado.

**Cómo medir:** (host) `godot --headless --path <copia g6> -- -p agent_ip:=127.0.0.1 demo` y añadir al HUD
`rclgd.get_transport_info().reliable_full`; (agente) `micro-ros-agent udp4 --port 8888 -v6` muestra los
submensajes HEARTBEAT/ACKNACK; (red) `tcpdump -i any udp port 8888` en la estación. Repetir en la Vita.

### 3.2 Coste de RosMsg (R4–R6, P5–P6)

Sin medir. Micro-benchmark propuesto (GDScript, host y Vita, mismo `.rsch` de G6):

```gdscript
var m := RosMsg.from_type("nav_msgs/msg/Odometry"); var b := m.serialize()
var t := Time.get_ticks_usec()
for i in 1000: var r := RosMsg.from_type("nav_msgs/msg/Odometry"); r.deserialize(b)
print("decode µs/msg: ", (Time.get_ticks_usec() - t) / 1000.0)
t = Time.get_ticks_usec()
for i in 1000: m.serialize()
print("encode µs/msg: ", (Time.get_ticks_usec() - t) / 1000.0)
print("objetos: ", Performance.get_monitor(Performance.OBJECT_COUNT))
```

En la Vita, pintar el resultado en el HUD (no hay consola). Antes/después de cada cambio.

---

## 4. Optimizaciones priorizadas

| Prio | Cambio | Dónde | Impacto | Riesgo | Medir en host | Medir en Vita |
|---|---|---|---|---|---|---|
| 1 | Pintar `reliable_full`, `topic_dropped`, `rclgd.get_dropped()` en el HUD de G6/G7 | `main.gd` | diagnóstico de X1 (gratis) | nulo | `-- demo` 30 s | igual |
| 2 | Decodificar sin árboles por defecto: `init_shallow` en `d_begin_struct` + `deliver` sin `from_type` ni `PackedByteArray` | `ros_msg.cpp:453-472, 580-592`, `ros_runtime.cpp:325-341` | **alto** (÷3–4 objetos en `/odom`) | bajo (las pruebas de host de G1 cubren `deserialize`) | benchmark §3.2 + `godot/test/` | HUD con µs/msg |
| 3 | Caché de `StringName` por campo y `HashMap` campo→índice por tipo; nombres de tipo y búsqueda de tipo cacheados | `ros_msg.cpp` (carga del esquema) | **alto** (quita mutex global y UTF-8 por campo) | bajo | benchmark | HUD |
| 4 | Atajos packed→puntero en `e_prim_array` y en `_coerce` | `ros_msg.cpp:281-303, 686-724` | medio-alto para mensajes con covarianzas | bajo (layout LE en host x86 y ARM) | paridad de bytes con los *fixtures* de `msg-schema` | — |
| 5 | MTU 1400 en el cliente XRCE | `build-xrce-client-vita.sh` | medio: `/odom` en 1 datagrama, BE con margen | medio (WiFi/IP: no pasar de 1472) | agente docker + `ros2 topic hz /odom` | `odom Hz` del HUD, `read_packets` |
| 6 | Reintentos de sesión 3 y cierre sin espera | `xrce_transport.cpp:287, 323` | medio (UX: 10 s → 3 s; salida instantánea) | bajo | parar el agente y arrancar/salir | igual |
| 7 | BE: vaciar y reintentar al llenarse; limitar `ERR_*` por segundo | `xrce_transport.cpp:414-425` | medio con varios topics BE (G7 IMU + Joy) | bajo | 2 publishers BE a 60 Hz | igual |
| 8 | Reutilizar mensajes en GDScript; HUD a 5–10 Hz; rastro con `draw_polyline` | `g6-hmi/main.gd`, `g7-imu/main.gd` | medio | nulo (y es buen **reto** para el usuario) | `Performance.TIME_PROCESS` | igual |
| 9 | Liberar/no reservar los pools de red sobrantes (2 MiB) | `xrce_transport.cpp:99-113`, `net_udp.c:40` (dual) | 2 MiB de RAM | bajo (el de `net-udp` exige paridad C+Rust) | — | `OS.get_static_memory_usage()` |
| 10 | Detección de caída + reconexión con ids estables | `xrce_transport.cpp`, `ros_runtime.cpp` | alto en robustez | medio | `docker restart` del agente | igual |
| 11 | Cola de entrada con `msg_ring` (sin malloc) | `ros_runtime.cpp:162-172, 669-699` | bajo-medio | bajo | benchmark | — |
| 12 | `-O2` solo para el módulo | `SCsub` | bajo-medio | bajo | tamaño del `.so` | benchmark |
| 13 | Hilo de red (sceKernelCreateThread, afinidad a otro núcleo, prioridad algo mayor que el principal, pila 32 KiB) con `msg_ring` en ambos sentidos | nuevo | alto en latencia/bloqueos y heartbeats | **alto** (sin TLS, carreras en `g_diag`, uxr sin `UCLIENT_PROFILE_MULTITHREAD`) | estrés en host | `SceKernelThreadInfo.currentCpuId`, `changeCpuCount` (docs/14 §4) |
| 14 | Arreglar B1/B2 | `ros_runtime.cpp` | robustez | bajo | prueba GDScript que llama a `shutdown` en un timer | — |

Orden recomendado: 1 → (medir) → 2+3+4 (un hito «RosMsg sin basura», con lección) → 6+7 → 5 → 10 → 13 solo si los
datos lo piden (p. ej. G7 cámara o mensajes > MTU).

---

## 5. Qué NO tocar

- El diseño de un solo hilo es correcto para G6/G7: no introducir el hilo de red sin un dato que lo pida.
- La copia con `ucdr_deserialize_array_uint8_t` en `_on_topic` es necesaria (fragmentos no contiguos, `docs/06:113`).
- El desvío fiable→BE (`xrce_transport.cpp:418-425`) es una buena política para teleop; solo hay que hacerlo visible.
- La red temprana del cargador (`0001-…patch`) es imprescindible (UID_RL_OVERFLOW).

## 6. Propuesta de reto para el usuario (modo aprendizaje)

Prio 1 + prio 8 son puro GDScript: pintar `reliable_full` en el HUD de G6 y reutilizar el `Twist` en
`_publicar_cmd`. Pregunta guía: «¿por qué no hace falta crear un mensaje nuevo si `publish` serializa al
momento?» (`ros_runtime.cpp:313`).
