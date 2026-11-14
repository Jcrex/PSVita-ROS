# V2 · Revisión escéptica y de código de la fase V2 del visor (tareas V5–V9, 2026-11-14)

> Revisor: escéptico + revisor de código (Opus 5.5). Commits revisados (`git log --oneline dbe5b85..7d369f9`):
> `e58f389` (V5), `4a2adb0` (V7), `045b9f3` (V6), `b6e2ed3` (V8), `47c8077` (V9), `8c794e0` (fusión V8 + V9),
> `6b2c348` (arreglo de la fusión: `huella_f32_bits`), `7d369f9` (bitácora). Mandan `docs/adr/0013-visualizacion-topics-godot.md`,
> `docs/36-visualizacion-topics-godot.md` (§5, §6, §7, §8, §10), `godot/plantillas/visor/README.md` (decisiones de
> V5–V9) y la revisión anterior `docs/ia/workshops/posts/V1-revision.md` (mismo formato).
> Marcas: [V] verificado (lectura de código o ejecución) · [I] inferencia · [?] sin confirmar.

## 1. Qué se ejecutó (host, PC CachyOS)

| Prueba | Antes | Después |
|---|---|---|
| `--check-only` de `visor/**`, `pruebas/visor*.gd`, `ros/vc1.gd` (57 scripts) | sin errores | sin errores |
| `pruebas/visor.gd` · `visor_primitivas.gd` · `visor_hud.gd` · `visor_displays.gd` | 57 · 114 · 70 · 105 | igual |
| `pruebas/visor_directos.gd` (V5) · `visor_herramientas.gd` (V7) · `visor_relay.gd` (V6) | 228 · 70 · 80 | igual |
| `pruebas/visor_marcadores.gd` (V8) | 62/62 | **63/63** (+ malla vieja del pool, H4; falla sin el arreglo: 62/63) |
| `pruebas/visor_tf.gd` (V9) | 78/78 | **79/79** (caso A cambiado por H1; + una sola suscripción a pose2d, H2) |
| `godot/test/run_host_tests.sh` · runner de `g1-sensores` | — | **294 comprobaciones, 0 fallos** · **16/16** |
| `docker/scripts/test_vita_relay.py` (python3 y venv de rosbags) | — | **TODO OK** (tamaños CDR = rosbags) |
| `generar_esquemas.py --visor` / sin `--visor` | — | `cmp` idéntico a `visor-ros/ros/schema.rsch` / a `dron-mapeo` |
| `tools/export-vita-vpk.sh godot/visor-ros build/visor-ros.vpk` | — | exporta (23,2 MB, 118 archivos; lleva `fabrica_marcadores.gd`, `tf_ligero.gd`, `herramientas/**`, `hud/{consola,diagnostico}.gd`); **no se subió** |
| En vivo: `vita-ros.sh up` + `fuente-visor` + `fuente-v2 avisos,marcadores,tf` + `relay hmi,marcadores,tf` (8 hijos en `tf_lista`) + `visor-ros -- transporte=xrce compacto=1 agente=127.0.0.1 perfil` | — | 22 displays `ok`; TfLigero con 11 marcos, `base_link` bajo `odom`, map → odom (0,62; 0,30) m como la fuente; 31 marcadores vivos = 31 nodos, 73 estados completos en 15 s, `sin_sitio=0`; LINE_STRIP 49 *quads*; `[perfil-gd]` por display ≤ 9 µs (Marcadores 8–9, TF 1); `/vita/tf` a 10,000 Hz |
| Red medida (`/vita/relay_bw`) | — | `hmi,marcadores,tf` = **24,2 KB/s, 134 msg/s** (31,2 nominal); `hmi` solo = **12,9 KB/s, 103 msg/s** (≤ 20 ✓) |
| `vita-ros.sh netem 192.168.1.250 10` / `netem off` (IP ficticia) | — | `prio bands 4` + `netem loss 10%` en la banda 4 + filtro `u32` a esa IP; `off` deja `fq_codel` como estaba |

## 2. Hallazgos de código

### 2.1 Corregidos (confirmados y seguros)

| # | Dónde | Fallo | Escenario concreto | Corrección |
|---|---|---|---|---|
| H1 | `visor_ros.gd` `marco_mundo_pose2d` + `visor-ros/main.tscn` | con `marco_pose2d = "odom"` y el relay **sin** módulo `tf`, TfLigero nunca conoce «map» y `transformada()` devuelve la identidad para todo [V, `visor_tf.gd` caso A antiguo] | el gate V9 pedía editar la escena (`tf_relay`, `marco_pose2d`) y la Vita no acepta argumentos: con esa escena, los gates V1/V3 (relay sin `tf`) volvían a pintar el scan en el origen (N1 de V1) | si `marco_pose2d` no está unido al fijo, pose2d cuelga del fijo (= decisión V9-2); en cuanto llega map → odom, el siguiente pose2d cuelga la base de odom. `main.tscn` lleva `marco_pose2d = "odom"` y `tf_relay = true`: una sola `.vpk` para todos los gates |
| H2 | `robot_joints.gd` + `visor_ros.gd` | V9 añadió la suscripción de VisorRos a `<p>/pose2d` sin quitar la del robot: **3 lectores** (VisorRos, Robot, Odom) [V] | cada lector XRCE recibe su copia [I]: 40 B × 30 Hz × 3 = 3,6 KB/s y 90 datagramas/s de los ~200 (`docs/27:42-43`); V1-N2 ya lo marcaba con 2 | señal `VisorRos.pose2d_tf(m)`; el robot se cuelga de ella si `suscrito_pose2d()`. Quedan 2 lectores (VisorRos y Odom, ver N5). Prueba en `visor_tf.gd` |
| H3 | `visor_ros.gd` (`[perfil-gd]`) | el criterio del gate V6 es `reliable_dropped` = 0, pero `visor-ros` no lo escribía en ningún log [V] | el usuario no podía cerrar V6 sin un depurador | `[perfil-gd] … rx_paq= topic_dropped= reliable_dropped= be_dropped= reconexiones=` (de `rclgd.get_transport_info()`, solo ros2_vita) |
| H4 | `fabrica_marcadores.gd` `_hornear_si_cambia` | la firma se guarda en el nodo, no ligada a la malla [V] | con el tope alcanzado el gestor reutiliza un nodo de otro tipo (V8-4): CUBE_LIST → pool → CUBO → pool → la MISMA CUBE_LIST ⇒ firma igual ⇒ se queda el **cubo** (y con el intervalo de 1 s de la Vita, también durante 1 s con datos distintos). Prueba nueva: 62/63 sin el arreglo | meta `malla`: firma e intervalo solo valen si `n.mesh` es la malla horneada |
| H5 | `3d/marcadores.gd` | los gates M1–M3 piden «nº de hijos constante» y nada lo escribía [V] | sin log, M2 solo se ve a ojo | `[visor-marc] vivos= nodos= hijos= tope= sin_sitio= completos= rechazados=` cada 5 s (en la Vita o con `-- perfil`) |
| H6 | `2d/poses.gd` | sin `topic_vita` por defecto: en la Vita iba en **directo** (`PoseArray` está en `TIPOS_VISOR`) [V] | `/particle_cloud` de AMCL (> 8 poses = > 488 B) no llega nunca y el display queda «ok» sin datos; el README de V9 dice «en la Vita `<p>/poses`» | `topic_vita = "poses"` por defecto (la escena puede vaciarlo) |
| H7 | `2d/marcadores_2d.gd` | `absf(NaN)` como ancho de línea (`maxf(1, NaN)` = NaN) [V] | trozo de `marcador_puntos` corrupto o de otro emisor: `draw_polyline` con ancho NaN | ancho no finito → 0 (mínimo en px) |
| H8 | estación | no había forma de pasar `tf_lista` al relay ni publicadores para V6/V8/V9 ni pérdida controlada para M3 [V] | los gates de hardware no eran reproducibles | `vita-ros.sh relay [mód] [pref] [ritmo] [tf_lista]`, `fuente-v2 [modos] [n]` (`docker/scripts/fuente_prueba_v2.py`: `avisos`, `marcadores`, `vida`, `tf`; probado en la estación) y `netem <IP_VITA> [%]` / `netem off` (solo hacia la Vita) |

### 2.2 Fusión V8 + V9 (atención especial)

| Comprobación | Resultado |
|---|---|
| Nombres duplicados en Python (`vita_relay_formatos.py`) | solo `huella_f32` (ya resuelto en `6b2c348`: V9 = `huella_f32_bits`); `IMPLEMENTADOS` se amplía en dos bloques aditivos sin pisarse [V] |
| Constantes y funciones de `vc1.gd` | bloques V9 (`MAX_POSES`, `MAX_TF`, `leer_tf`…) y V8 (`POR_MARCADOR`, `clave_marcador`…) sin nombres comunes; `--check-only` limpio [V] |
| `RegistroDisplays` | orden coherente: `*/marcador_puntos`, `*/poses`, `*/pose_cov` antes del `*MultiArray` genérico; `Marker` → gestor V8 antes del simple de V5 [V]. Falta `*/marcadores` y `*/tf` (N1) |
| `main.tscn` | ids `v8_*`/`v9_tf` únicos; dos nodos «Meta» (barra y herramienta) con padres distintos: solo duplica una línea de `[visor] Meta: ok` [V] |
| Presupuesto de red del relay | cada módulo suma su fila en `PRESUPUESTO`; `hmi,marcadores,tf` = 31,2 KB/s y 139 dgr/s nominales (medido 24,2 / 134); el tf2 del módulo `marcadores` y la `TablaTf` del módulo `tf` son dos suscripciones de **entrada** a `/tf` (no compiten por la red de la Vita) [V] |
| Huellas cruzadas | V8 (`pruebas/visor_marcadores.gd`) y V9 (`pruebas/visor_tf.gd`) pasan en los dos lados [V] |

### 2.3 No corregidos (riesgo anotado o tarea posterior)

| # | Dónde | Hallazgo | Escenario | Destino |
|---|---|---|---|---|
| N1 | `registro_displays.gd` | sin reglas para `*/marcadores` (Float32MultiArray) ni `*/tf` | el ExploradorTopics (V12, PC) abriría el inspector genérico | V12 |
| N2 | `vita_relay.py` `_tx_tf` | `tf_marcos` y `tf_estatico` no pasan por `_pub`: no suman a `relay_bw` | ≤ 544 B al cambiar (latched): despreciable salvo un `/tf_static` que cambie a menudo | anotado |
| N3 | gates G-W13-M1/M2 (doc 36 §9.1) | piden **48** marcadores, pero el estado completo del relay corta en 33 y el cupo de la Vita es 12 (HMI) / 32 (Viz) | M1/M2 en la Vita miden el cupo concedido (12 con `main.tscn` en HMI), no 48 | **DESAFÍO** a la tabla §9.1 (ver §3) |
| N4 | V8 | faltan los `.uid` de `fabrica_marcadores.gd`, `3d/marcadores.gd`, `2d/marcadores_2d.gd`, `pruebas/visor_marcadores.gd` | inocuo (`main.tscn` usa rutas); el editor los creará como «sin seguimiento» al abrirlo | commit del usuario al abrir el editor |
| N5 | `2d/pose.gd` (Odom) | sigue con su propia suscripción a `<p>/pose2d` (2 lectores) | +1,2 KB/s y +30 dgr/s [I] | alimentar el canal desde `VisorRos.pose2d_tf` (cambia CanalDisplay: Hz y caducidad) |
| N6 | herramientas (V7-1) | sus ≤ 4 *quads* no se reservan en la capa `hud` | D6 400 → 404 con una herramienta activa | anotado (≤ 1 %) |
| N7 | V5-13 | los displays V5 no están en ninguna escena | el gate V5 («cada tipo publicado desde el PC se ve en la Vita») no se puede correr con esta `.vpk` | escena de banco de V5 o añadirlos a `visor-ros` cuando se decida |
| N8 | `3d/tf.gd` | con más marcos que cupo, se dibujan los primeros de `get_frame_names()` (orden de llegada) | en la Vita con la fuente `tf`: 11 marcos, cupo 8 ⇒ 3 sin ejes (los últimos en llegar) | usar `filtro` en la escena si importa cuáles |
| N9 | `3d/marcadores.gd` | sin `desconectar()` propio: los nodos siguen visibles tras desconectar | solo al cerrar la escena | anotado |
| N10 | consola oculta | con la pestaña Consola oculta el canal descarta (`max_pendientes` = 12; 138 descartes en 15 s en vivo) | al abrir la pestaña se ven los 6 últimos: es lo diseñado (V6) | — |

Sin hallazgos en: QoS (herramientas FIABLE con profundidad 5 PC / 1 Vita y `RosQoS.set_*()` vía
`contexto_ros.gd:25-31`, nunca `qos.reliability =` [V]; Consola fiable 10/5, Diagnóstico BE en la Vita, `tf_marcos` y
`tf_estatico` F+TL profundidad 1, `marcador_texto` fiable 5 [V]); ejes Godot ↔ ROS (`planta_desde` y su inversa en
`suelo_godot`, `TfLigero.desde_ros` = C·R·Cᵀ, links del robot × Cᵀ, sólidos compactos `Basis(UP, yaw)` con C de
determinante +1, puntos con `ros_to_godot_vector`, rumbo de la meta `atan2(Δy, Δx)` en ROS [V, a mano y por las
pruebas]; en vivo, map → odom de la fuente (0,5 + 0,2 sen, 0,3, yaw 0,1) sale en Godot como O = (−0,30; −0,62) =
(−y, −x) ✓); NaN (marcadores directos `valido`, relay `_finitos`, compacto pos/escala/yaw, puntos, `poner_ros`,
`leer_poses`, `desde_pose2d` [V]); fugas del pool (30 ciclos × 40 ADD + DELETEALL y 30 estados con claves nuevas:
nodos constantes [V, pruebas]; en vivo 31 = 31).

## 3. Contra el ADR 0013

- **Presupuesto D7 (instancias 3D, Vita, perfil HMI) sumando `main.tscn`:** Robot 40 (`robot`) + TF 8 (`tf`) +
  Marcadores 12 de los 48 pedidos (`marcadores`) = 60 de 80; Meta3D y Mapa3D son `solo_pc`; el banco E-W8-1 (80) va
  fuera de cupo y apagado (START) [V, pruebas y `visor_ros.gd:28-33`].
- **D6 (HUD 400 *quads*):** barra ≤ 120 (64 en vivo) + pestaña ≤ 240 (Estado 36–76, Diagnóstico 8 × 30 = 240, Consola
  6 × 40 = 240) + 40 glifos; + ≤ 4 de la herramienta activa fuera de cuenta (N6) [V].
- **2D:** `sensores_2d` ≤ 800 (Mapa, Plan, Scan, Odom: 574 en V1); `resto_2d` Marcadores2D 150 de 300 [V].
- **Red (D5.7):** perfil `hmi` 19,1 KB/s nominal, **12,9 medido** (≤ 20 ✓); `viz` sigue sin arrancar (falta `costmap`, V11).
- **Regla de escenas (doc 35):** displays, herramientas y estáticos de TF (`tf_estaticos`, texto en el `.tscn`) son nodos
  o propiedades de la escena; el código crea solo nodos de runtime sin `owner` (pool de marcadores, piezas de la flecha,
  EJES del TF, robot instanciado) [V].

### Veredictos de las decisiones anotadas (README del visor, V5–V9)

| Decisión | Veredicto | Motivo |
|---|---|---|
| V5-1 `--visor` opcional | **VERIFICADO** | `cmp` idéntico sin `--visor` (dron-mapeo) y con él (visor-ros) |
| V5-2 feedback de NavigateToPose manual | VERIFICADO [I] | campos y orden = `NavigateToPose.action` de Nav2 Jazzy (current_pose, navigation_time, estimated_time_remaining, number_of_recoveries, distance_remaining); validar contra Nav2 real |
| V5-3 `nav_msgs/Path` en TIPOS_VISOR | VERIFICADO | lo usa V3 en directo en el PC |
| V5-4 `Empty` fuera | VERIFICADO | caso negativo en la prueba |
| V5-5 nombres `ejes`/`fuerza` | VERIFICADO | doc 36 §10 |
| V5-6 anillo del par perpendicular | VERIFICADO | corrige el esqueleto de §4.2.6 |
| V5-7 cupo parcial por orden | VERIFICADO | |
| V5-8 MarcadorSimple | VERIFICADO | el gestor V8 lo sustituye en el registro |
| V5-9 covarianza en planta, abanico ±3 rad | VERIFICADO | |
| V5-10 GPS sin teselas | VERIFICADO | |
| V5-11 polígono con `triangulate_polygon` | VERIFICADO | |
| V5-12 Twist → `base_link` | VERIFICADO | |
| V5-13 displays V5 fuera de `main.tscn` | VERIFICADO / **DESAFÍO al gate** | regla doc 35 sí; pero el gate V5 no tiene escena en la Vita (N7) |
| V6-1 `viz`/`percepcion` no arrancan | VERIFICADO | `--comprobar viz` → «costmap (V11)» |
| V6-2 módulos por defecto sin cambios | VERIFICADO | |
| V6-3 época del mapa | VERIFICADO | en vivo «época 1 (nueva)» una sola vez |
| V6-4 rosout 60 car., cola 20 | VERIFICADO | |
| V6-5 «cambio» = nivel o mensaje | VERIFICADO | la fuente `avisos` cambia el nivel de «bateria» cada 5 s para probarlo |
| V6-6 ritmo `nombre=/topic@hz` | VERIFICADO | |
| V6-7 8 × 30 con el cuadro dentro | VERIFICADO | 240 justos |
| V6-8 diagnóstico directo fiable, profundidad 1 | VERIFICADO | doc 36 §6 |
| V6-9 `relay_info` sin consumir | VERIFICADO (pendiente) | |
| V6-10 «qué módulo sobra» | VERIFICADO | |
| V7-1 `extends Node2D` | VERIFICADO con aviso | ≤ 4 *quads* fuera de D6 (N6) |
| V7-2 ciclo con «ninguna» | **VERIFICADO** | una consola de mano no publica por un roce |
| V7-3 rumbo a 0 por pulsación | **VERIFICADO** | mejor que el esqueleto |
| V7-4 Publish Point vuelve a «ninguna» | VERIFICADO | |
| V7-5 teleop solo activa, Twist cero al soltar | VERIFICADO | |
| V7-6 botones | por medir [I] | gate V7 |
| V7-7 sin cursor por stick | VERIFICADO | |
| V7-8 registro y GestorHud sin cambios | VERIFICADO | |
| V8-1 dos displays, un reparto | **VERIFICADO** | `capa()` decide; nunca dos dibujos |
| V8-2 FNV-1a de 24 bit | VERIFICADO | con 33 claves, choque ≈ 33²/2²⁵ ≈ 3·10⁻⁵ |
| V8-3 claves nuevas tras reciclar | **VERIFICADO** | evita el ciclo vacío |
| V8-4 tope `min(cupo, 48)` y reutilizar otro tipo | VERIFICADO tras H4 | la reutilización entre tipos dejaba la malla vieja |
| V8-5 relay: orden de llegada, sin TF no se manda, TRIANGLE_LIST no viaja, MESH = cubo | VERIFICADO | |
| V8-6 108 puntos por marcador | VERIFICADO | 3 × 36 |
| V8-7 purga 2D por el estado del gestor 3D | VERIFICADO | en vivo: texto y línea purgados con el estado |
| V8-8 ARROW por 2 puntos con CILINDRO girado | VERIFICADO | sin variantes nuevas |
| V8-9 re-horneado ≤ 1/s en la Vita | VERIFICADO tras H4 | |
| V8-10 MESH_RESOURCE solo horneadas | VERIFICADO | |
| V8-11 prueba de bytes fuera de `runner.gd` | VERIFICADO | g1-sensores 16/16 sin cambios |
| V8-12 `MarkerArray` fuera de TIPOS_VISOR | VERIFICADO | no cabe en directo |
| V9-1 TfLigero sin el fijo = sin TF | VERIFICADO | |
| V9-2 `marco_pose2d` "" ⇒ fijo | **DESAFÍO (resuelto, H1)** | un valor puesto y sin `tf` dejaba todo en el origen; ahora cae al fijo hasta que exista el camino |
| V9-3 `tf_relay` apagado por defecto | VERIFICADO en el script; `visor-ros` lo enciende | 3 suscripciones sin tráfico si el relay no tiene `tf` |
| V9-4 estáticos como texto, solo yaw | VERIFICADO | el `tf_estatico` del relay los pisa (probado) |
| V9-5 32 marcos con padres y raíces | **VERIFICADO** | = `TF_TREE_MAX_FRAMES` |
| V9-6 robot colocado por `transformada` | VERIFICADO tras H2 | ya sin suscripción propia |
| V9-7 display TF: cupo 8/32, sin caducidad | VERIFICADO con aviso | qué marcos caben depende del orden (N8) |
| V9-8 recolocar al llegar el mensaje | VERIFICADO | |
| V9-9 poses diezmadas, sin pesos | VERIFICADO tras H6 | |
| V9-10 `pose_cov` con varianzas | VERIFICADO | coherente con `covarianza.gd` |
| V9-11 índices fijos por llegada, estático fiable | VERIFICADO | 544 B > 488 solo en fiable (≈ 7,5 KiB) |
| V9-12 `huella_f32_bits` | VERIFICADO | |
| doc 36 §9.1 G-W13-M1/M2 «48» | **DESAFÍO** | 33 en el relay y 12/32 de cupo (N3): medir con el cupo concedido |

## 4. Cambios en la estación

- `docker/vita-ros.sh relay [mód] [pref] [ritmo] [tf_lista]` (5.º argumento: lista blanca del módulo `tf`).
- `docker/vita-ros.sh fuente-v2 [modos] [n]` → `docker/scripts/fuente_prueba_v2.py`: `avisos` (20 WARN/s + 1 INFO/s
  en `/rosout`; 6 estados en `/diagnostics` a 2 Hz, «bateria» cambia de nivel cada 5 s), `marcadores` (n = 31 sólidos
  CUBE/SPHERE/CYLINDER/ARROW en círculo a 10 Hz + LINE_STRIP de 50 puntos + TEXT), `vida` (48 cubos con `lifetime`
  2 s a 2 Hz y DELETEALL de `vida_b` cada 5 s), `tf` (8 hijos a 10 Hz: map → odom, rueda_izq, rueda_der, torre, brazo,
  pinza, antena, camara; `odom → base_link` desde `/odom`; estático base_link → base_scan).
- `docker/vita-ros.sh netem <IP_VITA> [%]` / `netem off`: `tc prio bands 4` + `netem` en la banda 4 + filtro `u32` a
  la IP de la Vita (el resto del tráfico del PC no se toca). La estación usa la red del host y tiene `NET_ADMIN`.

## 5. Guion único de hardware (usuario; fish en el PC CachyOS)

Una `.vpk`, cuatro lanzamientos de la app. Cada lanzamiento reescribe los logs de la Vita: recoger tras cada fase
(VitaShell en primer plano, Select = FTP, con la app cerrada). Terminales: T1 estación, T2 fuente base, T3 relay,
T4 fuente-v2, T5 consultas, T6 RViz. Ctrl+C en T3/T4 al cambiar de fase.

```fish
cd ~/Proyectos/PSVita-ROS
# --- 0. Preparación (una vez) -------------------------------------------------------------------------------------
tools/export-vita-vpk.sh godot/visor-ros build/visor-ros.vpk
tools/deploy-vpk-ftp.sh build/visor-ros.vpk 192.168.1.94          # VitaShell → ux0:/visor-ros.vpk → instalar
function recoger --argument-names fase
    curl -s --max-time 30 "ftp://192.168.1.94:1337/ux0:/data/gxm3d/godot_stderr.log" -o /tmp/v2-$fase.err
    curl -s --max-time 30 "ftp://192.168.1.94:1337/ux0:/data/gxm3d/godot_stdout.log" -o /tmp/v2-$fase.out
    grep -hE '\[(gxm2d-perf|gxm3d|vita-prof|perfil-gd|visor-mapa|visor-marc|visor-banco|visor-herr)\]' /tmp/v2-$fase.err /tmp/v2-$fase.out | tail -n 40
end
docker/vita-ros.sh up                                              # T1 (luego: docker/vita-ros.sh logs agent)
docker/vita-ros.sh fuente-visor                                    # T2: mapa, scan, odom, joints, plan, HUD

# --- F1 · fase V1: HUD (G-W13-H0) y banco con START (E-W8-1). Sin relay ----------------------------------------------
#   Vita: abrir «ROS2 Vita Visor», 60 s en la pestaña Estado; START (banco de 80); 30 s; cerrar.
recoger f1

# --- F2 · V3 + V9 (TF) + V7 (herramientas). Relay hmi + tf con 8 hijos ------------------------------------------------
docker/vita-ros.sh relay hmi,tf /vita "" odom,rueda_izq,rueda_der,torre,brazo,pinza,antena,camara   # T3
docker/vita-ros.sh fuente-v2 tf                                    # T4
docker/vita-ros.sh rviz                                            # T6: Fixed Frame «map», añadir TF y LaserScan
#   Vita: abrir, 90 s (mapa por teselas; el scan sigue al robot; ejes del TF). Comparar con RViz.
#   V7: SELECT ×2 → barra «Meta»; tocar y arrastrar → flecha naranja (no publica); ✕ → publica.
docker/vita-ros.sh echo /goal_pose                                 # T5 (Ctrl+C y el siguiente)
#   SELECT → «Pose inicial»: tocar, arrastrar, ✕.
docker/vita-ros.sh echo /initialpose
#   SELECT → «Punto»: un toque (sin ✕).
docker/vita-ros.sh echo /clicked_point
#   cerrar la app.
recoger f2

# --- F3 · V6: 20 avisos/s durante 5 min. Relay hmi ------------------------------------------------------------------
docker/vita-ros.sh relay hmi                                       # T3 (Ctrl+C al anterior)
docker/vita-ros.sh fuente-v2 avisos                                # T4 (Ctrl+C al anterior)
#   Vita: abrir; L una vez (L va hacia ATRÁS y da la vuelta: Estado → Consola); 5 min en Consola;
#   L otra vez → Diagnóstico (ver «bateria» cambiar de color); cerrar.
recoger f3

# --- F4 · V8: G-W13-M1 y G-W13-M3. Relay hmi + marcadores ----------------------------------------------------------
docker/vita-ros.sh relay hmi,marcadores                            # T3
docker/vita-ros.sh fuente-v2 marcadores                            # T4 (31 sólidos + línea + texto a 10 Hz)
#   Vita: abrir, 60 s (M1). Después, M3 durante 2 min:
docker/vita-ros.sh netem 192.168.1.94 10                           # T5: 10 % de pérdida SOLO hacia la Vita
docker exec -it vita_station bash -lc "source /opt/ros/jazzy/setup.bash; ros2 topic bw /vita/marcadores"
docker/vita-ros.sh netem off                                       # ¡siempre al acabar!
#   (Opcional, G-W13-M2: Ctrl+C en T4, `docker/vita-ros.sh fuente-v2 vida`, 5 min.) Cerrar la app.
recoger f4
```

### Criterio de verde

| Gate | Fase | Línea | Verde |
|---|---|---|---|
| **G-W13-H0** (V4) | F1, antes de START | `[gxm2d-perf] quads= draws=`, `[perfil-gd] hud_glifos=` | `quads` ≤ 400 y `draws` ≤ 30 |
| **E-W8-1** (V2) | F1, tras START | `[gxm3d] drawn= lit=`, `[visor-banco] activo=true instancias=80` | `lit=0`, `drawn` ≥ 80, `fps` ≥ 59 |
| **V3** | F2 | `[gxm2d-perf] fps=`, `[vita-prof] process=`, `[visor-mapa] media_us= max_us=` | `fps` ≥ 55; `process` ≤ 4 000 µs; `media_us`, `max_us` ≤ 1 500 |
| **V9** | F2 | `[perfil-gd] visor/TF=`; a la vista | `visor/TF` ≤ 500 µs; el anillo del scan sigue al triángulo de odometría (no en el origen); los EJES de map, odom, base_link y base_scan donde los pone RViz (map → odom ≈ 0,6 m adelante y 0,3 m a la izquierda, yaw 0,1) |
| **V7** | F2 | T5 (`echo`) y `[visor-herr]` en `/tmp/v2-f2.out` | arrastrar sin ✕ no publica; cada ✕ = **un** mensaje con `frame_id: map` y la posición tocada; `/initialpose` con covarianza 0,25 / 0,25 / 0,0685; `/clicked_point` con un toque; cada toque una línea `[visor-herr] … toque n=` (n de uno en uno) |
| **V6** | F3 | `[gxm2d-perf] fps=`, `[perfil-gd] reliable_dropped= topic_dropped=` | 5 min sin bajar de escalón (`fps` ≥ 55 siempre); `reliable_dropped=0`; la consola muestra «W prueba_avisos: aviso N…» con N subiendo; Diagnóstico con «bateria» cambiando de color cada 5 s |
| **G-W13-M1** (V8) | F4, sin netem | `[gxm3d] drawn= avg_submit_us=`, `[visor-marc] nodos= hijos=` | `drawn` sube en el cupo (12 en HMI, N3); `avg_submit_us` ≤ 9 000; `fps` ≥ 30; `nodos=12` y `hijos` constantes |
| **G-W13-M3** (V8) | F4, con netem | `[vita-prof] process=`, `ros2 topic bw`, a la vista | `process` ≤ 4 000 µs; `/vita/marcadores` ≤ 15 KB/s; ningún sólido fuera de sitio > 0,4 s (el estado completo llega a 5 Hz) |
| G-W13-M2 (opc.) | F4, `vida` | `[visor-marc] hijos=` | `hijos` y `nodos` constantes durante 5 min |
| Enlace | todas | `logs agent`, `[perfil-gd] reconexiones=` | sesión establecida; `reconexiones=0` salvo caída provocada |

Qué es esperable y no es fallo: el aviso «Marcadores pide 48 en «marcadores» y recibe 12» (cupo HMI); en F2, 3 de los
11 marcos sin ejes (N8: cupo 8); en F4, `sin_sitio` creciendo (31 marcadores para 12 nodos).
