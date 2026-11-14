# V1 · Revisión escéptica y de código de la fase V1 del visor (tareas V1–V4, 2026-11-13)

> Revisor: escéptico + revisor de código (Opus 5.5). Commits revisados: `35c0cae` (V1), `1137018` (V2), `8c9405e`
> (V4), `0627f0f` (V3) (`git log --oneline 015f350..0627f0f`). Mandan `docs/adr/0013-visualizacion-topics-godot.md`,
> `docs/36-visualizacion-topics-godot.md` (§2, §7, §8, §10) y `godot/plantillas/visor/README.md`.
> Marcas: [V] verificado (lectura de código o ejecución) · [I] inferencia · [?] sin confirmar.

## 1. Qué se ejecutó (host, PC CachyOS)

| Prueba | Antes | Después |
|---|---|---|
| `--check-only` de `visor/**`, `pruebas/visor*.gd`, `vita_relay.gd`, `visor-ros/banco_primitivas.gd` | sin errores | sin errores |
| `pruebas/visor.gd` | 56/56 | **57/57** (+ colores de PaletaViz en el HUD) |
| `pruebas/visor_primitivas.gd` | 110/110 | **114/114** (+ banco E-W8-1) |
| `pruebas/visor_hud.gd` | 68/68 | **68/68** |
| `pruebas/visor_displays.gd` | **103/104** (falla a ratos, H1) | **105/105** (dos pasadas seguidas; + NaN en pose2d) |
| `godot/test/run_host_tests.sh` | — | **294 comprobaciones, 0 fallos** |
| runner de `g1-sensores` | — | **14/14** |
| `docker/scripts/test_vita_relay.py` | — | **TODO OK** |
| `tools/export-vita-vpk.sh godot/visor-ros …` | exporta (23 MB) | exporta (23 MB; incluye `texto_superpuesto.gd` y `banco_primitivas.gd`); **no se subió a la Vita** |
| En vivo en el host: `vita-ros.sh up` + `fuente_prueba_visor.py` + `relay scan,pose,joints,mapa,path` + `visor-ros -- transporte=xrce compacto=1 agente=127.0.0.1 perfil` | — | 8 displays `ok`; `[visor-mapa] teselas=384 media_us=25 max_us=48`; `[perfil-gd]` por display ≤ 13 µs/fotograma; HUD `barra_q=77 pestana_q=48 glifos=93` |

Los `ERROR: RosMsg: tipo … no esta en el esquema` del log (GoalStatusArray, FeedbackMessage, Temperature, Joy, Path)
son los tipos de V5 (esperados, T20).

## 2. Hallazgos de código

### 2.1 Corregidos (confirmados y seguros)

| # | Dónde | Fallo | Escenario concreto | Corrección |
|---|---|---|---|---|
| H1 | `plantillas/vita_relay.gd:35` | `_t_ultima := 0.0` frente a `ahora = ticks/1000`: la **primera** subida de la textura del mapa se bloquea hasta que el motor lleva 250 ms vivo [V] | `pruebas/visor_displays.gd:169` (`actualizar_textura() == true`) falló 1 de cada pocas pasadas (103/104 en esta revisión); en la app, el mapa tarda un fotograma más si llega al arrancar | `_t_ultima := -1000.0` |
| H2 | `displays/3d/robot_joints.gd` `_al_pose2d` | `robot.transform = t` borra la escala propia del nodo [V] | Vita sin `escena_robot`: los EJES de respaldo (`scale = 0,5`) pasan a tamaño 1 con el primer `pose2d`; una escena con escala en su raíz la pierde igual | `t.scaled_local(robot.scale)` |
| H3 | `displays/2d/pose.gd`, `displays/3d/pose.gd`, `robot_joints.gd` | pose con NaN/Inf llega a `draw_colored_polygon` / `transform` (T2) [V] | `/odom` de un EKF sin iniciar (NaN) o `pose2d` con NaN: polígono inválido en cada redibujo, flecha/robot con `transform` NaN | se ignora (`is_finite`), prueba nueva en `visor_displays.gd` |
| H4 | `display_ros_{3d,2d,hud}.gd` | `_seccion` se fijaba en `conectar`, pero `_process` corre los dos fotogramas anteriores [V] | con `Perfil` activo, `[perfil-gd] … =0 …`: una sección con nombre vacío (visto en la prueba en vivo) | `_seccion` en `_enter_tree` |
| H5 | `visor_ros.gd` | nadie activaba `Perfil` en `visor-ros` (solo lo hace `aplicacion_robot.gd:88`) [V] | en la Vita, los `Perfil.sumar` de las bases no se volcaban: sin desglose por display para el gate «`process` ≤ 4 ms» | `VisorRos` lo activa en la Vita o con `-- perfil` (si nadie lo hizo) y vuelca `[perfil-gd]` cada 300 fotogramas con el informe del HUD (`hud_barra_q`, `hud_pestana_q`, `hud_glifos`) |
| H6 | `godot/visor-ros/main.tscn` | sin `TextoSuperpuesto` ni `VisorRos.texto`, que pide el árbol de doc 36 §2.7 [V] | un display 3D que llame a `visor.texto.poner(…)` falla con `null` | nodo `VisorRos/Hud/Texto` (debajo de `GestorHud`) y `texto = Hud/Texto` |
| H7 | `display_ros_hud.gd` y widgets | colores provisionales (pendiente anotado por V2 y V4) | — | ver §4 (integración) |
| H8 | gate E-W8-1 de V2 | no había escena para medirlo: en la Vita `visor-ros` solo tiene 1 instancia 3D [V] | el criterio de hardware de V2 (80 instancias, `lit=` = 0) no se podía comprobar | `godot/visor-ros/banco_primitivas.gd` en `main.tscn`: 80 primitivas (8 formas × 7 colores, 50 variantes), **apagado al arrancar**, Select (o B en el PC) lo enciende; prueba en `visor_primitivas.gd` (las 80 dentro del frustum) |
| H9 | fuente sintética de V3 | vivía fuera del repo (`scratchpad/fuente_v3.py`) [V]; `fuente_prueba_relay.py` solo da `/map` y `/scan` | el usuario no podía reproducir la prueba de V3 ni alimentar el HUD | `docker/scripts/fuente_prueba_visor.py` + `docker/vita-ros.sh fuente-visor` (map, scan, odom, joint_states, plan, battery_state, barometer, temperature); probado en la estación (`ros2 topic hz /odom` = 20,0) |

### 2.2 No corregidos (riesgo anotado, o tarea posterior)

| # | Dónde | Hallazgo | Escenario | Destino |
|---|---|---|---|---|
| N1 | `display_ros_2d.gd` + D3 | **Scan sin TF en la Vita se dibuja en el origen del mapa**, no en el robot: `transformada("base_scan")` devuelve identidad con `tf = null` [V] | con la fuente sintética el anillo del scan queda fijo en (0, 0) mientras el triángulo de `/odom` da vueltas. Es lo que dice D3, pero en la Vita «el frame ya es el fijo» es falso para el scan | V9 (`TfLigero` alimentado por `pose2d`); hasta entonces, saberlo al mirar la Vita |
| N2 | `robot_joints.gd` + `2d/pose.gd` | dos suscripciones a `<p>/pose2d` (Odom y Robot) ⇒ el agente manda dos copias (40 B a 30 Hz cada una) [I] | +1,2 KB/s y +30 datagramas/s de los ~200 de presupuesto (`docs/27:42-43`) | V9: `TfLigero` como única suscripción |
| N3 | `mapa_textura.gd` `de_grid` (PC) | bucle GDScript por celda y **dos** decodificaciones (Mapa y Mapa3D) por mapa [V] | slam_toolbox republica `/map` cada pocos segundos: 1 000 × 1 000 celdas = 2 × 10⁶ iteraciones por mapa ⇒ tirón visible en el PC [I] | DESAFÍO a la decisión V3-1 (abajo): *shader* `solo_pc` o `MapaTextura` compartida entre los dos displays |
| N4 | `2d/scan.gd` `_pintar` | con cupo parcial se dibujan los **primeros** `cupo` puntos (un sector), no uno de cada k | solo con dos scans en la Vita (prueba «Scan2 recibe 226») | mejora barata cuando haga falta (paso = ⌈n / cupo⌉) |
| N5 | `canal_display.gd` | la primera ventana de `hz_medido` cuenta desde el arranque del motor (`_t_ventana = 0`) [V] | el primer Hz del HUD sale bajo durante 1 s | cosmético |
| N6 | `gestor_hud.gd` | la pestaña oculta conserva su suscripción: en la Vita cada muestra se decodifica entera aunque no se pinte (H25) [I] | p. ej. `/joy` a 20 Hz con la pestaña Mando oculta | ya anotado en doc 36 §2.9.7; medir |
| N7 | `godot/visor-ros/main.tscn` | sin `Mundo` (doc 36 §2.7 lo instancia; decisión V1-8 dijo que V3 lo añadiría y no lo hizo) [V] | sin suelo ni referencia en la vista orbital | pendiente; `plantillas/mundo/mundo.tscn` tiene cambios sin confirmar en el árbol, no se toca aquí |
| N8 | `gestor_hud.gd` | R/L = `JOY_BUTTON_*_SHOULDER` y Select = `JOY_BUTTON_BACK` (banco) [I] | si el port los nombra distinto, no cambian pestaña / no encienden el banco | se ve en hardware (comandos abajo) |

Sin hallazgos en: conversión de ejes (`planta_desde`, `pose_godot`, `C`, quad del mapa 3D, UV norte arriba, yaw
de la planta con y hacia abajo) [V, revisado a mano y por las pruebas]; `RosTfListener.lookup_transform` ya devuelve
ejes de Godot (`godot/rclgd/docs/classes/class_rostflistener.rst`, «already converted») [V]; señales del canal
(se conectan una vez y se desconectan en `desconectar`) [V]; cupos (se liberan en `desconectar`) [V]; `res://comun`
en la exportación (`cp -rL`, la `.vpk` lleva `comun/visor/**`, `comun/ros/**` y `comun/vita_relay.gd`) [V]; API
rclgd ↔ ros2_vita: solo `create_subscription`, `RosQoS.set_*`, `RosMsg.from_type`, `rclgd.ros_to_godot_*` y
`get_transport_info` por `has_method` (`godot/ros2_vita/API_PARITY.md:19,29`) [V]; `_process` sin bucles por
elemento (el bucle de teselas es por mensaje entregado) [V].

## 3. Contra el ADR 0013

- **Nombres** (§1, tabla): VisorRos, RegistroDisplays, CanalDisplay, DisplayRos3D/2D/Hud, GestorHud, PrimitivasViz,
  PaletaViz y TextoSuperpuesto existen con su archivo y su base [V]. TfLigero, FabricaMarcadores y HerramientaVisor
  son V7–V9.
- **Contrato** (§1): los 13 `@export` y los ganchos `conectar`, `_procesar`, `_procesar_compacto`, `_pintar`,
  `_caducar`, `_coste` están en las tres bases [V]. El HUD añade `_dibujar() -> bool` (extensión compatible: quien
  sobrescriba `_draw()` sigue funcionando).
- **Presupuestos:** D6 HUD 400 = `BARRA_MAX` 120 + `PESTANA_MAX` 240 + `MAX_GLIFOS_VITA` 40 [V]. D7: `CUPOS` HMI
  suma 80 y Viz 150, capa a capa como §4 [V]. En `main.tscn` (Vita): barra 114, pestaña Estado 80, sensores 2D 574
  de 800 [V, pruebas].
- **Regla de escenas (doc 35):** displays, HUD, texto y banco son nodos del `.tscn`; el código solo crea pools,
  instancias del banco y el robot instanciado, sin `owner` [V]. Falta el `Mundo` (N7).

### Veredictos sobre las decisiones conservadoras anotadas

| Decisión | Veredicto | Motivo |
|---|---|---|
| V1-1 TF: `RosTfListener` si existe, si no `null` = todo en el marco fijo | **VERIFICADO** con aviso | coherente con D3 hasta V9; consecuencia visible N1 |
| V1-3 `ros/transport` solo con ros2_vita | VERIFICADO | con rclgd «xrce» activaría el camino compacto por error |
| V1-4 caducidad desde la **llegada** | **VERIFICADO** | el esqueleto de doc 36 §2.9.2 la contaba desde la entrega (`_t_ultimo`): con `hz` bajo caducaría un topic vivo; la implementación es mejor que el diseño |
| V1-5 reintento de arranque cada 3 s | VERIFICADO (host); validar en hardware | |
| V1-6 `set_process(false)` solo en `desactivado`/`sin cupo` | VERIFICADO | |
| V1-8 excluir `comun/mundo/*` | VERIFICADO hoy; **DESAFÍO** al plazo | V3 no instanció el mundo (N7) |
| V2-1 56 + 8 variantes | **VERIFICADO** | garantiza ≤ 64 aunque se pidan los 8 blancos después; probado (192 peticiones) |
| V2-2 cilindro **con tapas** | **VERIFICADO** | la tabla D2 dice 32 tri y «sin tapas»: 8 lados sin tapas son 16; 32 solo cuadra con tapas (8 + 16 + 8) |
| V2-3 anillo 40°–320° | **VERIFICADO** [I sobre la fuente] | i = 4..32 de 36 pasos = 28 segmentos de 10° = 280°, 56 tri; el «315°» de doc 36 §3.2 no casa con su propio i = 4..32 |
| V2-4 octaedro también en el PC | VERIFICADO | un camino de código; icosfera como mejora |
| V2-5 sin culling, unshaded, NEAREST | VERIFICADO; `lit=` por medir (E-W8-1, banco nuevo) | |
| V2-6 paleta en 8 bit con redondeo | VERIFICADO | `set_pixel` trunca; probado |
| V2-7 umbral 100 en las rampas | VERIFICADO | RViz |
| V3-1 mapa **sin shader** (CPU) | **VERIFICADO en la Vita / DESAFÍO en el PC** | en la Vita el estándar no se usa; en el PC el bucle por celda × 2 displays (N3) |
| V3-2 sin sub-texturas 128² | VERIFICADO | 384 teselas a 25 µs en el host; la Vita decide (≤ 1,5 ms) |
| V3-4 `pose2d` solo sin TF | VERIFICADO | evita sumar dos veces |
| V3-6 Mapa3D `solo_pc` en el ejemplo | VERIFICADO | cada display decodifica sus teselas |
| V4-1 colores provisionales | **cerrada** en esta revisión (§4) | |
| V4-3 medidor con 24 muestras | VERIFICADO | 6 × 40 = 240 justos |
| V4-4 joy: 16 segmentos, botones llenos | VERIFICADO | 51 quads |
| V4-8 R/L para cambiar de pestaña | por medir [I] (N8) | |
| doc 36 §2.9.5 `color_estado` → `Paleta.STALE` | **DESAFÍO** | STALE = (40, 23, 176): como **texto** sobre el fondo del HUD da ≈ 1,6:1 de contraste (ilegible). Se usa el gris 242 de la rampa (≈ 3,8:1, distinto del texto vivo 0,9); STALE queda para rellenos de estado (V6) |

## 4. Integración de la paleta (hecha)

`display_ros_hud.gd`: `COLOR_OK/AVISO/ERROR` = `Paleta.OK/WARN/ERROR`; `COLOR_ACENTO` = naranja e `COLOR_INFO`
(nuevo, «ejecutando» de `estado_meta`) = cian de la paleta; `COLOR_CADUCADO` = índice 242 de la rampa de grises
(`I_CADUCADO`); `COLOR_TEXTO` y `COLOR_FONDO` siguen propios del HUD. `estado_meta.gd` ya no lleva su azul suelto.
Solo `COLOR_APAGADO` de joy queda fuera (gris oscuro de botón apagado). Prueba: `visor.gd` «HUD: colores de PaletaViz».

## 5. Prueba en la Vita (para el usuario; fish, PC CachyOS)

Dos fases con la **misma `.vpk`**: A mide el HUD solo (sin relay, la planta queda vacía y `[gxm2d-perf] quads=` es
casi todo HUD) y el banco 3D; B añade el relay para el gate de V3. La Vita guarda stderr en
`ux0:/data/gxm3d/godot_stderr.log` (se lee con VitaShell en modo FTP, con la app cerrada).

```fish
cd ~/Proyectos/PSVita-ROS
tools/export-vita-vpk.sh godot/visor-ros build/visor-ros.vpk
tools/deploy-vpk-ftp.sh build/visor-ros.vpk 192.168.1.94
# En la Vita: VitaShell → ux0:/visor-ros.vpk → instalar («ROS2 Vita Visor», RVGD40030).

# Terminal 1: estación (agente micro-ROS en UDP 8888 de 192.168.1.65)
docker/vita-ros.sh up
docker/vita-ros.sh logs agent            # «session established» al abrir la app

# Terminal 2: datos sintéticos (map, scan, odom, joint_states, plan, battery_state, barometer, temperature)
docker/vita-ros.sh fuente-visor

# FASE A (HUD + banco): abrir la app en la Vita, pestaña Estado (la de arranque), esperar 60 s;
#   pulsar Select (banco de 80 primitivas), esperar 30 s; cerrar la app.
# FASE B (V3): Terminal 3, con la fuente aún en marcha:
docker/vita-ros.sh relay scan,pose,joints,mapa,path /vita
#   abrir la app otra vez, esperar 90 s (mapa entero por teselas), cerrar la app.
#   (Cada lanzamiento reescribe el log: recoger el de la fase A antes de lanzar la B.)

# Recoger el log (VitaShell en primer plano, Select = FTP):
curl -s --max-time 30 "ftp://192.168.1.94:1337/ux0:/data/gxm3d/godot_stderr.log" -o /tmp/visor-v1.log
grep -E '\[(vita-prof|gxm2d-perf|gxm3d|visor-mapa|perfil-gd|visor-banco)\]' /tmp/visor-v1.log | tail -n 60
docker/vita-ros.sh topics                # /vita/* del relay y los topics de la fuente
```

### Criterio de verde

| Gate | Fase | Línea del log | Verde |
|---|---|---|---|
| **G-W13-H0** (V4) | A, banco apagado | `[gxm2d-perf] … quads= draws=` | `quads` ≤ 400 y `draws` ≤ 30; anotar `hud_glifos` de `[perfil-gd]` y `avg_frame_us` para sacar µs por glifo |
| **E-W8-1** (V2) | A, tras Select | `[gxm3d] … drawn= lit=` y `[visor-banco] activo=true instancias=80` | `lit=0` y `drawn` ≥ 80 (81 con los EJES del Robot); `fps` del `[gxm2d-perf]` ≥ 59 |
| **V3** (E-W8-6 sin marcadores) | B | `[gxm2d-perf] fps=`, `[vita-prof] … process=`, `[visor-mapa] media_us= max_us=` | `fps` ≥ 55; `process` ≤ 4000 µs; `media_us` y `max_us` ≤ 1500 |
| Arranque y enlace (V1) | A y B | `logs agent` | sesión establecida; si se reinicia el agente (`docker/vita-ros.sh down` + `up`), los datos vuelven sin reabrir la app |

Qué mirar a simple vista: en A, la barra con batería que baja y «XRCE …p/s», la pestaña Estado con la presión
(la temperatura dice «sin esquema» hasta V5), R/L cambian a la pestaña Mando (joy «sin esquema»); en B, el mapa
100 × 80 con borde negro rellenándose por teselas, el plan verde, el triángulo de odometría dando vueltas con su
rastro y el anillo del scan **fijo en el origen** (N1, esperado hasta V9).
