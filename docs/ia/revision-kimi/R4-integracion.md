# R4 — Revisión de integración: línea A (Claude, dc6d4bf) × línea B (Kimi, 909e6ab)

**Fecha:** 2026-11-12 · **Tipo:** revisión de solo lectura (no se ha modificado código ni compilado nada).
**Marcas:** [V] verificado en el código citado · [I] inferencia razonada · [?] sin confirmar (hace falta prueba).

## 0. Resumen

Las dos líneas **no chocan en nombres de topic**, pero sí **en el papel de la Vita** y en varios detalles de formato.

- **Línea A:** la Vita es un **visor o cliente**. El PC (`vita_relay`, `g1_sim`) publica formatos compactos y la
  Vita los consume.
- **Línea B:** la Vita (o el PC) es el **simulador o productor**. Godot publica los sensores y además los mismos
  formatos compactos.

Las cabeceras y el orden de bytes coinciden. Un cliente **sí puede leer ambos** con `godot/comun/vita_relay.gd`
cambiando solo los nombres de topic. Hay cuatro divergencias de semántica:

1. qué significa «sin dato» en el scan;
2. el umbral de «libre» en el mapa;
3. qué cuenta la `version`;
4. falta el orden de juntas en B.

Además hay un **riesgo real en el transporte**: el cambio de colas de `xrce_transport.cpp` es FIFO y envía 1
mensaje por `poll()`. Eso añade latencia y, si hay saturación, envía datos viejos. Afecta a cualquier HMI con
hombre muerto, como VAB/1 del doc 32. **No afecta** al relay ni a la recepción.

## 1. Formatos compactos: comparación byte a byte

### 1.1 Scan (`Int16MultiArray`)

| Campo | Línea A (`docker/scripts/vita_relay.py`) | Línea B (`godot/plantillas/sensores/lidar_2d.gd`) | ¿Igual? |
|---|---|---|---|
| Orden de cabecera | `[seq, ang_min_cdeg, inc_cdeg, n, r…]` (`vita_relay.py:40-41`) | `[_secuencia, ang_min_cdeg, inc_cdeg, _n, r…]` (`lidar_2d.gd:92-93`) | **Sí** [V] |
| Unidades | centidegrados y cm (`:40-46`) | centidegrados y cm (`:92-95`) | **Sí** [V] |
| `seq` | `seq & 0x7FFF` (`:40`) | sin máscara (`:92`, `:98`): pasa de 32767 tras ~1,8 h a 5 Hz; `ros2_vita` lo trunca a int16 y sale negativo [I] (`ros_msg.cpp:481` es la lectura; la escritura no se ha comprobado) | **No** (menor) |
| Rayo sin impacto | `0` = sin dato, también si `r > range_max` (`:43-44`) | `range_max·100` (el raycast pone `distancia = rango_max` si no hay impacto, `lidar_2d.gd:69-71`); `0` solo si no es finito (`:95`) | **No**: el cliente dibuja un anillo falso a distancia máxima [V] |
| Diezmado | paso fijo hasta ≤ 180 rayos; el incremento se multiplica por el paso (`:38-41`) | `n` es ya el número de rayos que se trazan (60 en la Vita, `:37`) | compatible |
| Ángulo | marco del sensor, CCW desde +X | marco del sensor; la dirección local `(-sin a, 0, -cos a)` en ejes Godot es CCW desde «adelante» (`:64`) | **Sí** [I] |
| QoS | BE siempre (`:148`) | BE solo si `n ≤ 118` (`:52`); con 270 rayos en el PC va fiable | compatible (la Vita recibe 60) |
| Topic | `/vita/scan_compacto` | `/vita/g1/scan`, `/vita/rbkairos/{front,rear}_scan`, `/vita/drone/scan` (`robot.json`) | **No** (nombres) |

El lector `vita_relay.gd:94-107` (`scan_puntos`) lee el formato B sin cambios. Solo dibuja de más los rayos a
`range_max`.

### 1.2 Mapa por teselas

| Campo | A (`vita_relay.py:67-77`) | B (`mapeo_2d.gd:160-180`) | ¿Igual? |
|---|---|---|---|
| Cabecera | `[ver_lo, ver_hi, tx, ty]` | `[_version&255, (_version>>8)&255, tx, ty]` (`:165`) | **Sí** [V] |
| Cuerpo | 256 B; celda `k = j·32+i`, 2 bit LSB primero `<< ((k&3)*2)` | idéntico (`:175-176`) | **Sí** [V] |
| Total | 4 + 256 = **260 B** (CDR 276) | `resize(260)` (`:166`), es decir **los mismos 260 B**. El «teselas 2 bits de 260 B» del doc 29:70 **es el mismo formato**, no otro | **Sí** [V] |
| Orden de filas | `y = ty·32 + j`, fila 0 = abajo (convención OccupancyGrid) | `y = ty·32 + j` (`:170`) sobre su rejilla con origen abajo a la izquierda | **Sí** [V] |
| Celdas | `<0 → 0`; `≥65 → 2`; `≤25 → 1`; **26–64 → 0 (desconocido)** (`:60-64`) | `<0 → 0`; `≥65 → 2`; **resto → 1 (libre)** (`:174`) | **No** [V] |
| Fuera del mapa | 0 | 0 | Sí |
| Inicialización del cuerpo | `bytearray` a cero | `PackedByteArray.resize(260)` seguido de `\|=`. Depende de que `resize` ponga a cero los bytes nuevos | [?]: en Godot 4 no está garantizado en todas las versiones; usar `fill(0)` |
| `version` | **versión del mapa**: sube al llegar un `/map` nuevo (`:234`) y viaja igual en la meta y en las teselas | **contador de teselas**: sube en cada tesela publicada (`:180`), así que la meta y las teselas nunca coinciden | **No** (semántica) |
| Meta | `[res, ancho, alto, ox, oy, ntx, nty, version]`, fiable + TRANSIENT_LOCAL, solo al cambiar el mapa (`:237`) | el mismo array y la misma QoS (`publicador(..., false, true)`, `mapeo_2d.gd:57`), **pero en cada tic** (`:75-76`) | formato igual [V] |
| Topics | `/vita/mapa_meta`, `/vita/mapa_tesela` | `/vita/{g1,rbkairos,drone}/mapa_{meta,tesela}` | nombres |

`vita_relay.gd:49-68` (`on_mapa_tesela`) ignora `ver`. Por eso hoy lee las teselas de B sin problema [V].

Ojo con el umbral: B integra log-odds con −0,4 por pasada libre. Tras una pasada, `p ≈ 40` (`mapeo_2d.gd:94`,
`:136`). Con los umbrales de A esa celda saldría «desconocida» hasta la tercera pasada (−1,2 → `p ≈ 23`) [I].
Unificar el umbral obliga a elegir: o B adopta 25/65 y acepta que el mapa tarde más en «abrirse», o A acepta
«libre < 65».

### 1.3 Pose2d (`Float32MultiArray`)

A: `[x, y, yaw, vx, vy, wz]`, sacado de `/odom` con `twist` en el marco del cuerpo (`vita_relay.py:211-212`).
B: `[p.x, p.y, yaw, v_local.x, v_local.y, w.z]` (`odometria.gd:50`).

**Mismo formato y mismo marco** [V]. Solo cambian los topics: B publica `/g1/pose2d`, `/vita/rbkairos/pose2d` y
`/vita/drone/pose2d`, así que **B tampoco es coherente consigo mismo**: el G1 no usa el prefijo `/vita`.

### 1.4 Juntas

A: `/vita/joints` (Float32, posiciones) más `/vita/joints_orden` (String fiable + TRANSIENT_LOCAL)
(`vita_relay.py:160-161`, `:219-220`).

B: `/g1/joints` y `/vita/rbkairos/joints` (Float32, posiciones en el orden de `nombres`, `joint_state.gd:47-49`).
**No publica el orden.** Un cliente no sabe a qué junta corresponde cada valor [V]. El tamaño es 29 × 4 + 16 =
132 B, en BE, y cumple el límite.

### 1.5 `/g1/estado` (19 floats)

| | A (`docker/g1/g1_sim.py:116-117`, consumido en `godot/g1-unitree/main.gd:302-314`) | B (`unitree_estado.gd:81-89`) |
|---|---|---|
| Orden | `[x, y, z_pelvis, qx, qy, qz, qw, q0…q11]` | `[x, y, z+0.78, qx, qy, qz, qw, 12 juntas]` |
| `z` | altura real de la pelvis en MuJoCo (≈ 0,79) | suelo del `CharacterBody3D` + 0,78 constante (ignora el balanceo de `marcha.pose_base()`) [I] |
| Orden de juntas | `marcha.joints` = `anim/g1_marcha.json` | lista fija `marcha_nombres()` (`:92-95`), **idéntica** a `g1_marcha.json` [V] |
| QoS | BE (`g1_sim.py:186-187`) | BE (`unitree_estado.gd:31`) |

**Formato compatible**: `g1-unitree` en modo ros puede ver el G1 de `g1-sensores` sin cambios [I].
**Pero hay conflicto de productores.** Si `docker/vita-ros.sh g1` y `g1-sensores` corren a la vez, los dos
publican `/g1/estado`, `/odom` y `/tf odom→pelvis` (`g1_sim.py:17`, `:219-225` frente a `robot.json` de
g1-sensores y `odometria.gd:85-93`). El resultado es una pose que salta [V].

### 1.6 Contrato único propuesto («VC/1», compacto para la Vita)

1. **Referencia de formato:** los de la línea A (`vita_relay.py`, funciones puras con pruebas). Es lo que fija el
   ADR 0012 §1.
2. **Nombres:** `/vita[/<robot>]/{scan_compacto, pose2d, joints, joints_orden, mapa_meta, mapa_tesela,
   path_compacto}`. El prefijo es configurable en ambos lados:
   - parámetro `prefijo` en el relay;
   - campo `prefijo_compacto` en `robot.json`.
   
   `/g1/estado` se queda como está (patrón validado), con un solo productor activo.
3. **Semántica:**
   - scan: `seq & 0x7FFF`; `0` = sin dato, incluido «sin impacto»;
   - mapa: `version` = época del mapa, igual en la meta y en las teselas; la meta solo se publica al cambiar;
   - celdas: umbral único, que decide el usuario (§1.2).
4. **Quién cambia:**
   - **línea B (plantillas):** máscara de `seq`; 0 sin impacto; `version`; `fill(0)`; nombres; publicar
     `joints_orden`; meta solo al cambiar;
   - **línea A:** parámetro `prefijo` en el relay; mover `vita_relay.gd` a la biblioteca común; documento corto del
     contrato con la tabla de arriba;
   - **ambos:** prueba de paridad Python↔GDScript con el mismo vector de bytes (por ejemplo, el `runner.gd` de B
     compara con un `.bin` generado por `empaquetar_tesela`).

## 2. Código duplicado: `godot/comun/` frente a `godot/plantillas/`

- `godot/comun/` solo contiene `vita_relay.gd` (+ `.uid`) [V].
  `godot/g1-unitree/comun -> ../comun`; `g1-sensores`, `rbkairos-plus` y `dron-mapeo` usan `comun -> ../plantillas`
  [V]. Las dos bibliotecas se montan en el mismo `res://comun/`, de modo que **un proyecto no puede usar las dos a la
  vez** [V].
- `util_ros.gd:47-48` (`yaw_de_quat`) duplica `vita_relay.py:111-112` y la fórmula en línea de
  `g1-unitree/main.gd:312` [V].
- `g1-sensores` enlaza `g1-unitree/{anim,robot,marcha.gd}`, pero con su **propio** `marcha.gd.uid`
  (`uid://b120mjkec3ga3` frente a `uid://d3o6v33lywyc6`). Es correcto (cada proyecto tiene sus UID). En cambio, abrir
  g1-sensores en el editor puede reescribir los `.uid` o `.import` de `g1-unitree/robot/`, que es compartido [I].

**Fusión sin romper nada** (orden seguro):

1. Copiar `godot/comun/vita_relay.gd` y su `.uid` a `godot/plantillas/vita_relay.gd`, en la raíz de la biblioteca.
   Así `res://comun/vita_relay.gd` **sigue resolviendo** cuando cambie el enlace (`minimapa.gd:6`).
2. Cambiar `godot/g1-unitree/comun -> ../plantillas`.
3. Borrar `godot/comun/` (o dejar `godot/comun -> plantillas` un tiempo, por compatibilidad).
4. Opcional: mover el lector a `plantillas/ros/vita_relay.gd` y ajustar el `preload` en `minimapa.gd:6`.
5. Coste del `.vpk` de g1-unitree: `export-vita-vpk.sh:38` hace `cp -rL` y metería toda la biblioteca, ~2 MB con
   el mundo y las pruebas [V]. Es aceptable, pero conviene excluir `pruebas/` en la exportación o con
   `exclude_filter` en el preset [I].
6. Comprobar con un `--headless --import` de g1-unitree y g1-sensores, y con la exportación. **No requiere scons.**

## 3. Contradicciones entre docs (comprobadas en el código)

| # | Afirmación o regla | Código real | Veredicto |
|---|---|---|---|
| C1 | API_PARITY:35 dice que el TF broadcaster «no existe en ros2_vita». Doc 29:57/197: «Godot publica odom→base» | B **no** usa la API TF. Publica `tf2_msgs/TFMessage` en `/tf` con un publicador normal (`odometria.gd:38-39`, `:85-93`), con 1 transform ≈ 108 B en BE. Es lo que admite el doc 27:71 («filtrar /tf a frames útiles») | **Sin contradicción** [V]. Falta comprobar en la Vita la asignación `transforms = [t]` (secuencia de mensajes) [?] |
| C2 | ADR 0011 §4: prohibido MultiMesh y SubViewport en la ruta 3D de la Vita (doc 31) | `camara.gd` usa `SubViewport` (`:55`), pero tiene `solo_pc = true` (`:36`) y `sensor_base.gd:24-27` lo desactiva en la Vita. No hay MultiMesh, GridMap, CSG ni Label3D en `plantillas/` (grep) | **Se cumple** [V] |
| C3 | ADR 0011 §7: ajustes fijos `rendering/vita/*` y `triangle_budget` | Ningún `project.godot`, **ni de A ni de B**, los tiene (`g1-unitree/project.godot`, `*/project.godot`) | **Incumplido por ambos** [V] |
| C4 | ADR 0012 / doc 27: nada > 488 B en BE; JointState solo compacto | En la Vita B publica: LaserScan de 60 rayos en BE (≈ 300 B, `lidar_2d.gd:26-27`, `:89-91`), Imu en BE (≈ 330 B [I]), TFMessage de 1 transform y compactos. JointState, Odometry y LowState **solo** en el PC (`publicar_estandar_en_vita=false`, `joint_state.gd:36`; `unitree_estado.gd:32`). `ros2_vita` rechaza con `ERR_OUT_OF_MEMORY` lo que no cabe en BE (`xrce_transport.cpp:502-505`) | **Se cumple** [V]. Pero `sensor_base.gd:30-31` crea el publicador fiable de `/odom` y `/joint_states` en la Vita aunque no se use: son entidades XRCE de sobra [V] |
| C5 | Doc 29:59-63 «relay» / «relay troceado» para RGB, JPEG, CameraInfo, profundidad y PointCloud2 | `vita_relay.py` solo tiene `scan, pose, joints, mapa, path` (`:138`). **No hay relay de imagen ni de nube** | **Contradicción** [V]: el doc 29 promete algo que no existe (sería el doc 28 o ADR 0010 «nube decimada», pendiente) |
| C6 | Doc 27:36 (tabla): «Fiable lleno → desvía al BE (`reliable_full++`) `:418-425`» | Ya no es así: `publish()` encola (`xrce_transport.cpp:498-509`). El propio doc 27:48 dice lo contrario | **Contradicción interna** del doc 27 y referencias de línea obsoletas (`:411-415`, `:418-425`, `:453`) [V] |
| C7 | Doc 32:51 y :121 (VAB/1): «fiable con caída a best effort si el stream está lleno», «las publicaciones caen al best effort (`reliable_full++`)» | Igual que C6: ya no cae. Con el WiFi cortado, la cola fiable (32) descarta las **más antiguas** y, al volver, envía 32 órdenes viejas a 1 por fotograma | **Contradicción** [V]. Es inocuo para `/vita/orden`, que es idempotente por `(epoca, seq)` [I]. Ver §4 para `/vita/mando` |
| C8 | ADR 0012 / doc 27: flujo PC → Vita (la Vita es el visor) | B: la Vita es el **simulador** y publica sensores y mapa (`mapeo_2d.gd` en la Vita). No lo recoge ningún ADR | **Hueco de arquitectura** [V]: hace falta un ADR o una nota de que la Vita puede ser productora |
| C9 | Doc 27 / regla «no dar la vuelta por la red» | `mapeo_2d.gd:46` se **suscribe por ROS** al scan que publica su propio sensor hermano (`padre`). En la Vita eso es Vita → agente → Vita por WiFi | Ineficiente [V]. Debería leer `_rangos` del nodo padre directamente |

## 4. ¿Afecta el cambio de colas de `xrce_transport.cpp` a `g1-unitree` o a `vita_relay`?

Cambio (909e6ab, `xrce_transport.cpp:352-430`, `:498-509`):

- `publish()` ya no escribe en el stream: **copia** el mensaje a una cola FIFO (BE de 64, fiable de 32).
- `poll()` llama a `uxr_run_session_time(0)` y **después** prepara **un** mensaje BE y **uno** fiable
  (`:352-357`).
- `poll()` corre una vez por `_pump` (`ros_runtime.cpp:478-485`), es decir una vez por fotograma [I].

Consecuencias [V salvo marca]:

1. **Latencia +1 fotograma** para todo lo que se publica: el mensaje se prepara después de `run_session` y no sale
   hasta el `poll()` siguiente. A 59 FPS son ~17–34 ms más.
2. **Techo de envío:** 1 mensaje BE por fotograma, unos 60/s. Antes cabían varios mensajes pequeños por datagrama
   en el mismo fotograma, hasta llenar 512 B [I].
3. **FIFO sin fusión por publicador:** si se produce más de lo que se drena (FPS bajo o muchos sensores), la cola
   crece hasta 64 y se envía **lo antiguo primero**: hasta 64 fotogramas, más de 1 s de retraso.
   - Para teleop o hombre muerto es peor que el comportamiento anterior: el doc 32:75 exige parar en < 0,3 s.
   - El commit lo reconoce: «descartes best effort en G1 y dron».
   - Suma de las plantillas en la Vita con transporte XRCE (`g1-sensores`), contando las `hz_xrce`: ≈ 50 msg/s BE.
     Está al límite del techo de 60 [I].
4. **`godot/g1-unitree` (modo ros):**
   - publica solo `/cmd_vel` en BE a 20 Hz (`main.gd:226-229`, `:287`): 20 < 60, así que **no hay backlog**. Solo
     sufre el punto 1 (+1 fotograma) [V];
   - las suscripciones (`/g1/estado`, `/vita/mapa_*`, `/vita/pose2d`) usan la ruta de recepción, que no cambia
     (`_on_topic`, el stream de entrada y las acknack las gestiona `uxr_run_session_time`) [V].
   - Conclusión: funciona igual; **revalidar en hardware** la sensación del teleop.
5. **`vita_relay`:** es un nodo rclpy del PC y **no usa ros2_vita**, así que no le afecta [V].
6. Menor: con `!ep`, `_publish_pending` no actualiza `be_pending` (`:366-369`) [V].

**Arreglo propuesto (P0, en ros2_vita):**

- BE: «último valor por publicador», es decir un hueco por `p_id`, que se reemplaza en lugar de encolar.
- En `poll()`: drenar **en bucle** mientras `uxr_prepare_output_stream` acepte y después llamar a
  `uxr_run_session_time(0)` (o `uxr_flash_output_streams`) en el **mismo** `poll()`.
- Fiable: mantener la FIFO, pero también drenar en bucle hasta llenar la ventana.
- Ejecutar la suite de host (294/0) y la prueba XRCE de las plantillas. **No hace falta scons para las pruebas de
  host** [?]; según el doc 18 la plantilla Vita sí lo necesita, y debe hacerlo el usuario o el PC.

## 5. Tareas de integración (ordenadas)

| Prio | Tarea | Quién / dónde | Esfuerzo |
|---|---|---|---|
| **P0** | Cola BE «último por publicador», drenaje en bucle y flush en el mismo `poll()`; actualizar `be_pending` (§4) | `godot/ros2_vita/xrce_transport.cpp` | 0,5 d + prueba en hardware |
| **P0** | Corregir docs 27 (tabla :33-36 y líneas obsoletas) y 32 (:51, :121) sobre «caída a BE» | docs | 1 h |
| **P0** | Un solo productor de `/g1/estado`, `/odom` y `/tf` del G1: documentar «g1_sim **o** g1-sensores», o `topic_compacto` y espacio de nombres distintos en g1-sensores | `g1-sensores/robot.json`, README, `docker/vita-ros.sh` | 1 h |
| **P1** | Contrato VC/1 (§1.6): B corrige `seq`, 0 sin impacto, `version` = época, `fill(0)`, meta solo al cambiar, nombres `/vita/<robot>/…`, publica `joints_orden` | `plantillas/sensores/{lidar_2d,mapeo_2d,joint_state,odometria}.gd`, 3 `robot.json` | 0,5 d |
| **P1** | Decidir el umbral de «libre» (25 frente a 65) y aplicarlo en los dos lados | usuario → relay + `mapeo_2d.gd:174` | 30 min |
| **P1** | Relay con parámetro `prefijo` (y prueba) para servir a `/vita/<robot>/…` desde plantillas que corren en el PC | `docker/scripts/vita_relay.py` | 2 h |
| **P1** | Fusionar `godot/comun` en `godot/plantillas` (§2), con `g1-unitree/comun -> ../plantillas`; comprobar con import headless y exportación | godot/ | 2 h |
| **P1** | Prueba de paridad del formato: vectores de `empaquetar_scan`/`empaquetar_tesela` frente a `runner.gd` y `vita_relay.gd` | `docker/scripts/test_*`, `plantillas/pruebas/runner.gd` | 0,5 d |
| **P1** | ADR o nota «la Vita como productora» (C8) y corrección del doc 29:59-63 (no hay relay de imagen ni de nube, C5) | docs/adr, doc 29 | 2 h |
| **P2** | `mapeo_2d` lee los rangos del sensor padre en lugar de suscribirse por ROS (C9) | `mapeo_2d.gd:46` | 1 h |
| **P2** | No crear en la Vita los publicadores estándar que no se usan (C4) | `sensor_base.gd:30-31` | 30 min |
| **P2** | Ajustes del ADR 0011 §7 en todos los `project.godot` (C3) | godot/*/project.godot | 30 min |
| **P2** | Verificar en hardware `TFMessage.transforms = [t]` y los tamaños CDR reales con frames largos (`robot_front_laser_link`) | Vita | 1 h (usuario) |
| **P2** | Unificar `yaw_de_quat` (util_ros frente a main.gd en línea) | godot | 15 min |
