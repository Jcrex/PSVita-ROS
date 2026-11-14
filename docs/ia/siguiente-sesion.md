# Siguiente sesión — pasos y acciones pendientes (escrito el 2026-11-14)

> Lista ordenada para retomar en frío. Estado vivo: primer bloque de `docs/06-bitacora-estado.md`. Reglas de trabajo:
> `CLAUDE.md` (modo autónomo; decisiones → subagente **Fable 5.2**, sin preguntar al usuario; pruebas de hardware y
> acciones irreversibles → usuario). Comandos para el PC en **fish**.

## 0. Dónde quedó (2026-11-14)

- **Fase O** (organización, ADR 0014) y **Fase V** (visor de topics W13, V1–V15, ADR 0013) hechas y verificadas en
  host; publicadas con push y PR a `main` el 2026-11-14 (rama `ccr-44e2db2a-mr6xqr`).
- **Nada del visor se ha probado en la Vita.** Nada se ha probado con rclgd todavía (el usuario clonó rclgd,
  roomba_ws y rclgd_sensors en `~/Proyectos/rclgd-estudio/` el 2026-11-14: ver §3.4).
- Verde en host: 14 suites `godot/plantillas/pruebas/visor*.gd`, `godot/test/run_host_tests.sh` 349/0, runner de
  g1-sensores 16/16, `docker/scripts/test_vita_relay.py` OK, plantilla Vita recompilada con V13a (`verify_runtime.py`
  PASS) y `build/visor-ros.vpk` exportado (no versionado: reexportar si hace falta).

## 1. Prioridad 1 — pruebas del visor en la Vita (usuario)

1. Si el PR se fusionó, `git pull` en el PC. Reexportar por si acaso:
   ```fish
   tools/export-vita-vpk.sh godot/visor-ros build/visor-ros.vpk
   tools/deploy-vpk-ftp.sh build/visor-ros.vpk 192.168.1.94
   ```
2. Seguir el **guion único** `docs/ia/workshops/posts/V3-revision.md` §5 (9 lanzamientos, fases F1–F8, con las
   funciones `recoger`/`bw`/`pub` y la tabla de criterios de verde). Cubre los gates de V1–V12: G-W13-H0, E-W8-1
   (banco con **START**), V5 (escena banco: **L+R+START**), V6 (20 avisos/s 5 min), V7 (meta con ✕ → `/goal_pose`),
   V8 (M1 12 nodos ≥ 55 FPS, M1v 32 ≥ 30 FPS, M2 estrés 48, M3 33), V9 (8 marcos a 10 Hz), V10 (E-W8-5 JPEG ≤ 6 ms),
   V11 (M5: repaso ≤ 3 s, parche < 1 s), V12 (pestañas Gráficas/Inspector). Desde Estado, **L ×3** → Consola.
3. Con las mismas fases, medir el gate **G-V13b** (`docs/ia/workshops/posts/V13b-juez-fable.md` §4):
   `[visor-mapa] max_us`, `[visor-costmap] max_us`, `[visor-nube] us_max` ≤ 2000 µs; `[perfil-gd] visor/Scan` ≤ 1000 µs.
4. Pasar los logs a Claude → volcar resultados en `docs/36-visualizacion-topics-godot.md` §9.0 y §13.
5. Fuera del guion (después): G-W13-R0 (corte real de 488/489 B, docs/27 §4), G-W13-M7, V13a con `/tf` real por XRCE
   (`tf_nativo` en la escena), coste de `lookup` por fotograma, `latest_only` con un topic directo rápido.

## 2. Prioridad 2 — arreglar lo que salga rojo (Claude, autónomo)

- Por cada gate rojo: diagnóstico con los logs, arreglo con prueba de host, reexportar, nueva prueba del usuario.
- Si G-V13b sale rojo en alguna ruta: implementar SOLO esa función en `modules/viz-decode/` (cabecera reducida en
  `V13b-juez-fable.md`), dual Rust+C con paridad (`skills/vita-dual-module/`; explicar el Rust para principiante).
- Decisiones nuevas → subagente Fable; registrar como enmienda fechada de ADR 0013.

## 3. Prioridad 3 — pendientes de sesiones anteriores

1. **g1-sensores** (doc 34 §7.1, §8.4): exportar con las escenas editables y comprobar que sigue a 57–58 FPS; elegir
   `luz_por_vertice` (V = 57 FPS más clara, O = 58 FPS algo más oscura) **— decide Fable si el usuario no opina** — y
   fijarlo en `"mundo"` de `robot.json`; bajar 0,5–1 ms de scripts de física (`sensor/mapeo`, `sensor/mid360_scan`
   ~0,6 ms cada uno, robot ~1,5 ms, sensores por turnos) para 60 FPS estables.
2. **Bugs abiertos de la auditoría** (`docs/ia/organizacion/O1b-auditoria-estado.md`, lote 4): B1 `msg_schema` sin
   comprobar `strings_off <= total`, B2 panic = `loop {}` sin log en el paraguas Rust, B3 desborde `timeout_ms*1000`,
   R1 `shutdown()` desde un timer, X1 hipótesis `poll(0)`/HEARTBEAT. Cada uno con prueba de paridad.
3. **Optimizaciones** (lote 5): MTU XRCE 512 → ~1400, quitar pools de red duplicados, `-O2` para los `.c` en SCsub.
4. **rclgd en el PC** — el usuario clonó el 2026-11-14 en `~/Proyectos/rclgd-estudio/` (fuera del repo, no versionado):
   - `rclgd/` (Ozuba/rclgd) en rama **`jazzy`** @ `d8221d3` (3.0.0, 2026-11-04): **mismo código que `fb12a65`** (la
     base de la skill y de `godot/rclgd/`); solo cambia el CHANGELOG. **Compilado desde fuente y probado el
     2026-11-14: 45/45 pruebas del propio rclgd** con Godot 4.7.1 (receta en `skills/rclgd/references/versiones.md`
     §Compilar). Instalación en `~/Proyectos/rclgd-estudio/ws-jazzy/install`, Godot 4.7.1 en
     `ws-jazzy/build/rclgd/godot-engine/`, logs en `~/Proyectos/rclgd-estudio/.build-logs/`.
   - `roomba_ws/` (Ozuba/roomba_ws @ `8332acb`): su `docker/` instala `ros-jazzy-rclgd` por **apt, que solo ofrece
     2.1.0** (sin clases tipadas ni RosLogger): **no vale tal cual**. Usar la compilación de fuente de arriba (o
     cambiar su Dockerfile para montar `ws-jazzy/install`).
   - **Siguiente paso concreto:** ejecutar las suites del visor con rclgd en el contenedor jazzy: copiar
     `godot/visor-ros` (y `godot/plantillas` como `comun`) a un directorio temporal, añadir `librclgd.so` +
     `rclgd.gdextension` como hace `run_tests.sh` de rclgd, y lanzar `godot/plantillas/pruebas/visor*.gd` con el
     Godot 4.7.1 de `ws-jazzy` (ojo: las suites usan hoy `ros2_vita`; puede hacer falta un modo «rclgd» en
     `godot/visor-ros/project.godot` y en las pruebas: decide Fable).
   - `rclgd_sensors/` (Ozuba/rclgd_sensors @ `420d4d4`): LiDAR 360 por GPU, IMU, cámara RGBA y GPS en Godot con
     `addons/rclgd-sensors`. Ya estudiado en `docs/24` (MIT; su LiDAR/cámara por GPU no van en la Vita).
   - **Tareas:** (a) validar el visor con rclgd real: lo no probado de doc 36 §13.4 (servicio de marcadores
     interactivos, InteractiveMarkerUpdate, Octomap, GridMap, `TfLigero` frente a `RosTfListener` ± 1 mm, extras V14);
     (b) comparar los patrones de `roomba_hmi` y `rclgd_sensors` con `godot/plantillas/` (HMI, sensores) y el visor:
     reusar lo bueno respetando la regla de escenas (doc 35); (c) registrar en `docs/24` §estado qué cambió entre
     las versiones estudiadas y estas.
5. **Integrar el visor en las apps vivas** (g1-sensores, rbkairos-plus, dron-mapeo): usar `VisorRos` + displays en vez
   de los visualizadores propios de `plantillas/sensores/*` donde aplique (regla de escenas, doc 35).
6. **Tipos sin display** (18 ⏳ de doc 36a §4.0.1): priorizar con Fable.

## 4. Decisiones que siguen abiertas para el usuario (no técnicas)

- **Historial público:** `respaldo-chat-claude/` (29 transcripciones, sin secretos; solo rutas `/home/jcrex`) sigue en
  el historial de `main` desde el PR #2. Purgarlo exige reescribir `main` con *force-push*: solo si el usuario lo pide.
- **Web** (en pausa desde 2026-11-01): seguir o abandonar.
- **Aprendizaje** (en pausa desde 2026-11-11): reanudar cuando el usuario quiera.
- Tareas viejas sin prioridad: F1 `deviceQuat` (recompilar motor), reto `/vita/joy`, panel trasero, ADR de cámara.

## 5. Archivos clave

| Qué | Dónde |
|---|---|
| Estado vivo | `docs/06-bitacora-estado.md` (primer bloque) |
| Visor: decisión, catálogo, estado | `docs/adr/0013-*.md`, `docs/36-*.md` (§9.0 gates, §13 estado), `docs/36a-*.md` |
| Visor: código y cómo añadir un display | `godot/plantillas/visor/README.md`, `godot/visor-ros/` |
| Guion de hardware | `docs/ia/workshops/posts/V3-revision.md` §5 |
| Decisiones de Fable | `docs/ia/workshops/posts/{W13,V2,V3,V13b}-juez-fable.md` |
| Organización | `docs/adr/0014-*.md`, `docs/README.md`, `docs/ia/organizacion/` |
| Plan ejecutado | `docs/ia/plan-organizacion-y-visor-2026-11-13.md` (Fases O y V cerradas) |
