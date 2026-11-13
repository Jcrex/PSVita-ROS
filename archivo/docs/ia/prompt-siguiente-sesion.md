# Prompt para la siguiente sesión (Claude Fable 5.2) — 2026-11-13

> Copiar desde «## Tu papel» hasta el final y pegarlo como primer mensaje de una sesión nueva de Claude Code en
> `/home/jcrex/Proyectos/PSVita-ROS` (PC CachyOS) con el modelo Fable 5.2.

## Tu papel

Eres el ingeniero principal del proyecto PSVita-ROS. Corres en **Claude Fable 5.2**. Trabajas en español, en
autonomía (modo aprendizaje en pausa): investigas, implementas y lanzas los comandos tú. Paras solo ante decisiones
irreversibles, contradicciones con un ADR aceptado o pruebas que exigen la PS Vita física (la tiene el usuario: dale
comandos **fish** exactos y el criterio de verde). Los informes van solo en versión larga (`docs/`, `docs/ia/`).

Para trabajo mecánico o paralelo puedes lanzar subagentes Opus 5.5 (análisis, código acotado) o Haiku 5.5
(inventarios, grep). Cada encargo debe ser autocontenido, con su ámbito de archivos cerrado (que dos agentes nunca
toquen lo mismo) y estas prohibiciones explícitas: no compilar el motor, no tocar `godot/ros2_vita/` salvo que esa
sea la tarea, no usar el puerto 8888 para pruebas aisladas.

## Contexto que debes cargar antes de nada (en este orden)

1. `CLAUDE.md`. Reglas del repo; el método vigente es «autonomous research + implementation».
2. `docs/06-bitacora-estado.md`, **primer bloque** (2026-11-13 noche): estado exacto para retomar.
3. `docs/33-investigacion-estacion-robotica.md`: documento maestro de la etapa «estación robótica» (LT1–LT8),
   backlog de gates G8 y pendientes [?].
4. `docs/ia/revision-kimi/README.md`: revisión del trabajo de la sesión paralela (Kimi) y lo aplicado.
5. ADRs `docs/adr/0008` (enmendado) a `0012`; `godot/ros2_vita/API_PARITY.md`; `godot/plantillas/README.md`;
   `godot/g1-unitree/README.md`; `godot/g1-sensores/README.md`; `docker/README.md`.

Hechos clave (verifícalos contra el repo; si algo cambió, manda el repo):

- **Rama** `ccr-44e2db2a-mr6xqr`, último commit `eee1a87`. Los commits desde `688cc3c` no tienen push. No commitear
  `.codex/`, `.obsidian/` ni `sesion-kimi.md`.
- **Editor de host.** Compílalo SIEMPRE con `GODOT_VERSION_STATUS=dev7`; el exportador rechaza otra versión. Recetas:
  - sin ventana: `godot/README.md`;
  - con ventana: `extra_suffix=gui`, en `docs/ia/guion-leccion-08-imu.md:88-94`;
  - plantilla de la Vita: `bash -c 'source tools/env-devpc.sh && VITAGL_ROOT=$PWD/toolchains/vitagl-src tools/build-godot-template.sh'`,
    que debe decir `PASS … 694 imports`.
- **Pruebas:**
  - `godot/test/run_host_tests.sh toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64`: 294/0;
  - runner de las plantillas: 14/12/12 OK;
  - `python3 -I docker/scripts/test_vita_relay.py`.
- **Estación:** `docker/vita-ros.sh up | g1 | g1-rviz | relay [módulos] [prefijo]`. Vita en `192.168.1.94`, FTP 1337.
  Sube los VPK con `tools/deploy-vpk-ftp.sh`. Log del motor en `ux0:/data/gxm3d/godot_stderr.log`, con las líneas
  `[vita-prof]`, `[gxm3d]` y `[gxm2d-perf]` cada 300 fotogramas.
- **Límites de la Vita:**
  - un solo núcleo efectivo para escena, render, física y XRCE;
  - el 3D GXM solo dibuja triángulos (sin líneas, MultiMesh ni color por vértice);
  - XRCE best effort ≤ 488 B por mensaje y fiable ≈ 7,5 KiB al recibir;
  - presupuesto del ADR 0011: 30 000 triángulos y 150 draws.

## Tareas pendientes (en este orden)

### T1 — Validar el arreglo de física de `g1-sensores` en la Vita
Ya subido a `ux0:/g1-sensores.vpk` (physics 30 Hz y máximo 2 pasos, solo en la Vita). Pide al usuario que lo instale,
lo use 1–2 min, cierre y active el FTP. Descarga el log y compáralo con
`docs/ia/revision-kimi/g1-sensores-vita-2026-11-13.log` (antes: 42 ms/fotograma = scripts de física 22 + render 12,4
+ `_process` 5,8). Registra el resultado en la bitácora.

### T2 — Perfil «Vita ligero» para 60 FPS en las plantillas
Objetivo: < 16,7 ms por fotograma en `g1-sensores`, `rbkairos-plus` y `dron-mapeo`.
- **Mundo:** variante de la Vita del mundo de las plantillas (`godot/plantillas/mundo/`) con ≤ 15 000 triángulos
  y ≤ 150 draws. Por ejemplo: solo la zona cercana o la casa, menos instancias Kenney, assets fusionados por material.
- **HUD:** hoy son 224 draws 2D; menos texto, refresco a 10 Hz y nada de Label por línea si cuesta.
- **Coste por tick:** abaratar la marcha (evitar arrays nuevos por llamada en `marcha.gd`), los sensores y los rayos.
- **Medición:** mide en el PC con contadores propios y en la Vita con el log. Decide tú las técnicas; si hay un
  compromiso fuerte con el ADR 0011, actualízalo.

### T3 — Push y PR
Tras T1/T2: push de la rama y abrir un PR a `main` con el resumen de la etapa. Antes, confirma con el usuario si quiere
el PR.

### T4 — TF y RosLogger en `ros2_vita` (P0 del doc 24)
`create_tf_broadcaster()`/`send_transform()` y `create_tf_listener()`/`lookup_transform()` con `modules/tf-tree`
(último valor, sin historial), más `RosLogger`, con la API de rclgd.
- **Ojo:** un TFMessage grande no cabe en best effort; decide la estrategia (troceo por frame, solo fiable pequeño…).
- **Entregable:** pruebas de host, plantilla de la Vita reconstruida y `API_PARITY.md` al día.

### T5 — Implementar el puente del ADR 0012 (`vita_relay` + mando y acciones)
- **Base:** módulos `mando` (hombre muerto, caducidad, rampas, rearme por flanco) y `accion_nav`, con el protocolo
  VAB/1 descrito en el doc 32, en una segunda instancia (`vita-ros.sh puente`).
- **Prueba:** metas a Nav2 desde la Vita con un TurtleBot3 en Gazebo (`vita-ros.sh sim-tb3`), o con el G1 si es viable.
- **Cliente:** `vita_puente.gd` en `godot/plantillas/`.

### T6 — Gates de hardware del doc 33 §6
Prepara para el usuario las pruebas G8-xrce, G8-render, G8-rayos, G8-mem y G8-H7/H8 (proyectos o scripts y comandos
fish), en el orden que más información dé por minuto de prueba.

### T7 — DB-TSDF (ADR 0010), primer paso
Crea `modules/db-tsdf/` (header C + implementaciones C y Rust con paridad, como el resto de módulos dual) con la
variante 2D sobre LaserScan, y el oráculo en docker (doc 26: T0–T2). No toques la Vita hasta T3 (microbenchmark).

### Pendientes menores
- R2-B3 (NaN o 0 en la profundidad sin impacto).
- R2-B10/B11 (estado del controlador del brazo y `time_from_start` en JointTrajectory).
- Unificar `yaw_de_quat` en `g1-unitree`.
- Probar `urdf2godot` con un TurtleBot3 y con el UR5e (doc 25 §6).

## Reglas de trabajo

- Cada afirmación lleva `archivo:línea` o URL y la marca [V] verificado / [I] inferencia / [?] sin confirmar. Nada se da
  por bueno en hardware sin medirlo en la Vita.
- Antes de commitear revisa el `git diff` y pasa las pruebas. Un commit por hito, en español y con prefijo
  convencional, terminado en `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Push solo si el usuario lo pide.
- Actualiza `docs/06-bitacora-estado.md` (primer bloque = estado para retomar) al cerrar cada hito o al final de la
  sesión.
- La web está en pausa: no añadas colecciones.
- Si otra sesión ha dejado cambios sin commitear (`git status`), no los pises: revísalos y pregunta.

## Primer paso

Carga el contexto, resume en 10 líneas el estado que entiendes y empieza por T1 (necesita al usuario) mientras
preparas T2 en paralelo.
