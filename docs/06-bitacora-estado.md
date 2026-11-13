# 06 — Bitácora de estado del proyecto

**Última actualización:** 2026-11-13, cierre de sesión (regla de escenas editables, doc 35, comprobada por el usuario en el editor; `g1-sensores` a 57–58 FPS en la Vita, doc 34 §7.1). Antes, el mismo día: T1 y T2 medidos en la Vita (`g1-sensores` de 23,5 a 57–58 FPS, doc 34 §7.1). Antes, el mismo día: perfil «Vita ligero» de las plantillas (doc 34). Antes: 2026-11-12 (plantillas RB-KAIROS+, G1 y dron con sensores ROS 2 + diagnóstico de rendimiento XRCE); 2026-11-11 (etapa «estación robótica» y proyecto Unitree G1); 2026-11-01 (cierre: G7a/G7b/G7c verdes, primer 3D de Godot en la Vita; antes,
auditoría de la flota, índice en [`docs/ia/auditoria/README.md`](ia/auditoria/README.md)).
El estado vivo está en el primer bloque; debajo, las sesiones abiertas (una por bloque).
**Sesiones anteriores:** [`docs/bitacora/`](bitacora/README.md) (un fichero por mes; la Fase 0/1 en
`docs/bitacora/2026-06-07-fases-0-1.md`). Índice de toda la documentación: [`docs/README.md`](README.md).
**Regla (ADR 0014 §4.2):** tope de 300 líneas; al superarlo o al cerrar el mes, las sesiones más antiguas bajan al
fichero del mes en `docs/bitacora/`.
**Para qué sirve este documento:** retomar el proyecto en frío. Responde:
¿dónde nos quedamos?, ¿qué hace cada programa?, ¿qué arquitectura se empleó?,
¿cuál es el siguiente paso exacto?

---

## 2026-11-13 (PC, noche) — Visor W13, fase V1 (V1–V4) hecha en host (Estado para retomar)

- **Hecho (commits `35c0cae`, `1137018`, `8c9405e`, `0627f0f`, revisión `e45c12a`):** núcleo del visor en
  `godot/plantillas/visor/` (ADR 0013), primitivas y paleta, HUD con pestañas, displays scan/path/pose/mapa/robot con el
  relay actual; proyecto `godot/visor-ros/`; fuente sintética `docker/vita-ros.sh fuente-visor`. Pruebas de host:
  visor 57, primitivas 114, HUD 68, displays 105, host 294/0, runner 14/14; en vivo en host con XRCE + relay: 8 displays OK.
  Revisión y comandos de hardware: `docs/ia/workshops/posts/V1-revision.md`.
- **DESAFÍOS abiertos:** dato caducado en gris de la paleta (no `STALE` azul, contraste 1,6:1; contra doc 36 §2.9.5);
  mapa sin shader en el PC (bucle por celda). En la Vita el scan va en el origen hasta V9 (TfLigero).
- **Falta (usuario):** prueba en la Vita: gates G-W13-H0, E-W8-1 y V3 (≥ 55 FPS, `process` ≤ 4 ms, tesela ≤ 1,5 ms).
- **V5 hecho en host (2026-11-13):** `TIPOS_VISOR` en `godot/plantillas/generar_esquemas.py` (`--visor`; `visor-ros`
  85 tipos, el resto de apps sin cambios) y displays directos `3d/{punto,vector,ejes,imu,fuerza,rango,marcador_simple}`,
  `2d/{poligono,covarianza,gps}`. Pruebas: visor_directos 228/228, visor 57, primitivas 114, HUD 68, displays 105, host
  294/0, runner g1-sensores 14/14; en vivo en host con XRCE + `ros2 topic pub`: 7 tipos. Pendiente: probar en la Vita.
- **Siguiente:** V6 relay rev. 2 ∥ V7 herramientas → V8 ∥ V9.

## 2026-11-13 (PC, noche) — Fase O: organización del repositorio

- **Petición del usuario:** sacar `respaldo-chat-claude/`, archivar decisiones descartadas sin limpiar y ejecutar el
  plan de subagentes (`docs/ia/plan-organizacion-y-visor-2026-11-13.md`). Decisiones del juez Fable 5.2:
  [`ADR 0014`](adr/0014-organizacion-del-repositorio.md) y `docs/ia/organizacion/decision-fable.md`.
- **Hecho:** `respaldo-chat-claude/` fuera del repo (`ef760eb`; **sigue en el historial público** de `main` desde el
  PR #2: purgarlo exige *force-push*, solo si el usuario lo pide). `vita-app/`, `godot/godot35/` y docs 10, 11, 16, 19,
  20, 21 en `archivo/`; piezas vivas en `modules/paraguas-rust/`, `tools/build-xrce-client-vita.sh`,
  `toolchains/xrce/` (ignorado) y `tools/hwprobe/src/`. Índice [`docs/README.md`](README.md), bitácora vieja en
  `docs/bitacora/`, doc 36 + 36a, `tools/check-doc-links.py`, `godot/README.md` por grupos, README raíz, `CLAUDE.md`
  (solo rutas), `AGENTS.md` como puntero, skills al día.
- **Verificado (O3):** paridad OK, host 294/0, runner g1-sensores 14/14, exportación `.vpk` OK, 0 enlaces rotos nuevos.
- **Por validar en el PC al recompilar la plantilla:** que el SCsub de `ros2_vita` encuentre las libs XRCE en
  `toolchains/xrce/` (la guarda de `build-godot-template.sh` aborta si faltan).
- **Siguiente:** Fase V del visor W13 (V1 núcleo → V2 primitivas ∥ V4 HUD → V3 displays), plan §3.

## 2026-11-13 (PC, noche) — W13: visualizar todos los tipos de topic en Godot

- **Petición del usuario:** investigación exhaustiva, con subagentes en paralelo y rclgd como referencia, de cómo
  visualizar todos los tipos de topic en Godot, para traducirlo después a código. **Regla nueva del usuario:** no se
  le preguntan decisiones; las toma un subagente **Fable 5.2**.
- **Workshop W13** (`docs/ia/workshops/W13-visualizacion-topics.md`): 5 investigadores Opus 5.5, 107 fichas por tipo
  con esqueleto GDScript; revisor escéptico (76 V / 18 DESAFÍO / 7 ALT / 6 Por medir; `check-only` 101/107); juez
  Fable 5.2 (D1–D15).
- **Resultado:** [`docs/36-visualizacion-topics-godot.md`](36-visualizacion-topics-godot.md) (catálogo de 82 tipos,
  arquitectura, relay VC/1 rev. 2, QoS, presupuesto, 32 trampas, 16 «Por resolver») y
  [`ADR 0013`](adr/0013-visualizacion-topics-godot.md): visor propio en `godot/plantillas/visor/` (gdviz solo como
  modelo), `_procesar`/`_procesar_compacto` → `_pintar`, planta 2D por defecto en la Vita, HUD 400 quads por pestañas.
- **Sin código todavía**; los esqueletos del doc 36 no han pasado `--check-only`.
- **Cómo retomar:** tareas V1–V15 (doc 36 §10). Fase 1 = V1 núcleo → V2 primitivas → V3 displays con el relay
  actual → V4 HUD. Lo anterior (escenas editables, abajo) sigue pendiente de exportar y probar en la Vita.

## 2026-11-13 (PC, tarde) — Regla de escenas editables

- **Petición del usuario:** que `main.tscn` no esté vacía en el editor y que sea una regla. Informe:
  [`docs/35-regla-escenas-editables.md`](35-regla-escenas-editables.md); regla también en `CLAUDE.md`.
- **Mundo común:** `plantillas/mundo/mundo.tscn` con 27 cajas (`caja_mundo.gd`) y 56 modelos (`asset_mundo.gd`, `@tool`
  con vista previa) agrupados por zonas; **`assets.json` borrado**; `mundo_base.gd` solo adapta la escena (perfil ligero
  igual que antes); `generar-lod-vita.py` anota la escena. Mundo **compartido** (decisión del usuario).
- **Escenas principales:** `Mundo`, `Ambiente`, `Luz` e `InicioRobot` en `main.tscn` de g1-sensores, rbkairos-plus y
  dron-mapeo (`spawn_ros` quitado de `robot.json`); `Casa`, `Luz` y `Ambiente` en `g1-unitree/main.tscn` (la casa se
  sigue editando en `docker/g1/casa.json`).
- **Verificado en host:** mundo idéntico (volcado de mallas y colisiones en los dos perfiles), runner 14/12/12,
  `perfil_ligero` 18/12/12, `presupuesto` OK con las mismas cifras, g1-unitree y loopback sin errores.
- **Editor gráfico: comprobado por el usuario** (ve el mundo y el robot en `main.tscn`).
- **Cierre de la sesión (2026-11-13).** Commits locales **sin push**: `68e75c1` (perfil ligero, parche de la nube),
  `239571f` (medidas T1/T2 en la Vita) y `e892a43` (escenas editables), más los anteriores desde `688cc3c`.
- **Cómo retomar (por orden):**
  1. Exportar `g1-sensores` con las escenas nuevas y probarlo en la Vita (debe seguir a 57–58 FPS; no cambia lo que
     se dibuja): `tools/export-vita-vpk.sh godot/g1-sensores build/g1-sensores.vpk` y
     `tools/deploy-vpk-ftp.sh build/g1-sensores.vpk 192.168.1.94`.
  2. Que el usuario elija `luz_por_vertice` (V = 57 FPS, más clara; O = 58 FPS, algo más oscura) y fijarlo en
     `"mundo"` de `robot.json`.
  3. Bajar ~0,5–1 ms de scripts de física para 60 FPS estables: `sensor/mapeo` y `sensor/mid360_scan` (~0,6 ms
     cada uno), robot ~1,5 ms, sensores por turnos (doc 34 §7.1 y §8.4).
  4. T3: push y PR a `main` (**preguntar antes**). Sin tocar: T4–T7.

## 2026-11-13 (PC, mediodía) — T1 y T2 validados en la Vita: 57–58 FPS

- Parche de la sesión en la nube aplicado (`68e75c1`), `g1-sensores.vpk` exportado en el PC y probado por el usuario
  (1 min con luz V, START, 1 min con luz O). Log: `docs/ia/medidas/g1-sensores-ligero-vita-2026-11-13.log`;
  tabla y análisis en el doc 34 §7.1.
- **De 23,5 a 57,0 FPS (luz V) y 58,1 FPS (luz O).** `physics_scripts` de 22 194 a ~4 000 µs; `process` de 5 800 a
  1 300; triángulos ≤ 15 000. T1 verde. T2 casi: falla `physics_scripts ≤ 2500` y `fps ≥ 58` con luz V.
- START llega bien; luz O se ve algo más oscura. Quitar la luz solo da +1,1 fps (`render` no baja: el tiempo se
  va a esperar el fotograma) → **pendiente de que el usuario elija `luz_por_vertice` por aspecto**.
- **Siguiente paso:** bajar ~0,5–1 ms de scripts de física: `sensor/mapeo` y `sensor/mid360_scan` (~0,6 ms cada
  uno), robot ~1,5 ms, sensores por turnos (doc 34 §8.4). La hipótesis XRCE del §8.2 queda descartada.
- Aspecto de los modelos reducidos: sin comentarios del usuario todavía.

## 2026-11-13 (nube, sesión programada) — Perfil «Vita ligero» de las plantillas (T2)

Sesión de Fable 5.2 lanzada por una tarea programada, **en la nube: sin Vita, sin el PC y sin `toolchains/`**. El
editor de host se compiló allí (`godot4-vita@d1a5f29`, `GODOT_VERSION_STATUS=dev7`, sin XRCE). Informe largo:
[`docs/34-perfil-vita-ligero.md`](34-perfil-vita-ligero.md).

- **T1 (validar la física a 30 ticks en la Vita): SIN HACER, necesita al usuario.** El `.vpk` sigue en
  `ux0:/g1-sensores.vpk` (sha256 fbfa43d5…). Pasos: instalar, usar 1–2 min, cerrar, FTP y en el PC:
  ```fish
  curl -s --max-time 30 "ftp://192.168.1.94:1337/ux0:/data/gxm3d/godot_stderr.log" -o /tmp/g1s-fisica30.log
  grep -E "vita-prof|gxm2d-perf" /tmp/g1s-fisica30.log | tail -6
  ```
  Verde: `fps ≥ 29` y `physics_scripts ≤ 9500` (antes 23,5 y 22 194). Guardar el log en `docs/ia/revision-kimi/`.
- **T2 hecho en host, por validar en la Vita** (solo GDScript y assets; el motor y `ros2_vita` no cambian):
  - Mundo ligero (`mundo_base.gd`, `assets.json`, `tools/generar-lod-vita.py`): cajas fundidas por color, 25 modelos
    con variante `*_vita.obj`, 8 adornos sin dibujar y visibilidad por distancia. En vista con el G1: de
    30 355–36 517 triángulos y 83–108 mallas a **13 455–14 909 y 50–55** (límite 15 000 / 80 del ADR 0011).
  - Contador de render del PC (`contar_dibujado`) **calibrado contra la Vita**: 19 469 triángulos y 53 mallas en
    el PC frente a 19 457 y 52 en el log de la Vita.
  - Marcha del G1 ×1,9 y modelo URDF ×2,8 más rápidos por tick (medido en el PC); HUD corto sin contorno a 4 Hz.
  - Contadores `[perfil-gd]` en el log (µs por sección cada 300 fotogramas) y START para alternar la luz por vértice.
- **Hallazgo:** `build_us` ≈ 3,9 ms fijos por fotograma = luz por vértice del 3D GXM reiluminando las mallas que se
  mueven (tope de 3 000 vértices por fotograma, `rasterizer_scene_gxm_vita.inc:602-696,868`). Con ella activada la
  estimación es 40–60 FPS; desactivada, 60 probables pero con las mallas en tono plano. **Decide la prueba.**
- **Pruebas:** host 294/0; runner 14/12/12; nuevas `perfil_ligero.gd` 18/12/12 y `presupuesto.gd` OK en los 3;
  `movimiento_g1.gd` 0 fallos.
- **Cómo retomar:**
  1. Aplicar el commit de esta sesión en el PC (llegó como parche: `git am`; la sesión no podía hacer push).
  2. T1 con el `.vpk` ya subido. Después, exportar y probar el perfil ligero: comandos y criterio de verde en el
     doc 34 §7 (andar 1 min, START, andar 1 min, bajar el log).
  3. Con el log: decidir `luz_por_vertice` y, si hace falta, seguir por el doc 34 §8 (sombreado horneado en la
     paleta, coste de XRCE en `_process`, G1 de ~8 000 triángulos).
  4. Sin tocar: T3 (push y PR, **preguntar antes**), T4 (TF y RosLogger), T5 (puente ADR 0012), T6 (gates G8),
     T7 (DB-TSDF) y los pendientes menores.

## 2026-11-13 (PC, noche) — `g1-sensores` en la Vita: 23,5 FPS, diagnóstico y primer arreglo

- **Topics en vivo desde la Vita** (perfil XRCE de las plantillas): `/g1s/estado` 10 Hz; `/vita/g1s/pose2d`,
  `/vita/g1s/joints`, `/tf`, 3 IMU 5 Hz; `scan_compacto` 2 Hz; `mapa_tesela` 1 Hz. ~45 msg/s, ritmos exactos, sin
  pérdidas (colas y frecuencias corregidas validadas en hardware). `/cmd_vel` sin datos en modo local (normal).
- **Rendimiento medido** (log del motor, `docs/ia/medidas/g1-sensores-vita-2026-11-13.log`): 42 ms/fotograma
  (23,5 FPS) = scripts de física **22,0 ms** + render 12,4 ms (~29 000 triángulos, 67 instancias, 224 draws 2D) +
  `_process` 5,8 ms + física del motor 0,8 ms. Causa principal: física a 60 ticks con fotogramas de 42 ms ⇒ ~2,5 ticks
  por fotograma (espiral), cada uno con marcha (29 juntas) + `move_and_slide` + 13 sensores + rayos.
- **Arreglo aplicado (sin probar aún):** `g1-sensores/project.godot` con `physics_ticks_per_second.vita=30` y
  `max_physics_steps_per_frame.vita=2` (sobrescritura por la característica «vita»; el PC sigue a 60). `.vpk` subido
  a `ux0:/g1-sensores.vpk` (sha256 fbfa43d5…). Estimación: ~27 ms ⇒ 30 FPS estables.
- **Cómo retomar:**
  1. El usuario instala `ux0:/g1-sensores.vpk`, la usa 1–2 min, cierra y activa el FTP; descargar
     `ux0:/data/gxm3d/godot_stderr.log` y comparar `[vita-prof]`/`[gxm3d]`/`[gxm2d-perf]` con el log guardado.
  2. Para 60 FPS (render 12,4 + process 5,8 ≈ 18 ms > 16,7): perfil «Vita ligero» del mundo de las plantillas
     (≤ 15 000 triángulos y ≤ 150 draws, ADR 0011), HUD con menos draws 2D, abaratar marcha/sensores por tick.
  3. Pendiente de push: commits desde `688cc3c` (rama `ccr-44e2db2a-mr6xqr`); PR a `main` sin abrir.

## 2026-11-13 (PC, tarde) — Reconexión automática de `ros2_vita` y `g1-sensores` igual que `g1-unitree`

- **Reconexión automática** (`xrce_transport.cpp`): tras reiniciar la estación las apps dejaban de publicar (el
  agente olvida la sesión y el cliente no lo notaba). Ahora: sondas fiables (`create_participant` con `UXR_REUSE`)
  si en 3 s no llega nada del agente; con 3 sin respuesta, ping de 30 ms cada 2 s y, al volver, se recrean sesión,
  participante, topics, publicadores y suscriptores con los mismos ids. Probado parando el agente 8 s: `/cmd_vel`
  vuelve a 10 Hz sola. Host 294/0; editores y plantilla Vita (`PASS … 694 imports`) reconstruidos.
- **`g1-sensores`** (agente Opus, `docs/ia/revision-kimi/g1-sensores-controles.md`): mismos mandos, selector de clip,
  root motion y cámara que `g1-unitree` (con `move_and_slide` contra el mundo); modo `fuente_movimiento: g1_sim`
  (✕/Espacio) que sigue `/g1/estado` de `docker/vita-ros.sh g1` y añade los sensores `g1s`. Runner 14/12/12; prueba
  nueva `g1-sensores/pruebas/movimiento_g1.gd`. **Validar en la Vita** (mandos y 60 FPS).

## 2026-11-13 (PC) — G1 en vivo desde la Vita: sesiones fantasma, `/robot_description` y `/map`

- **La Vita conecta en modo ros** (sesiones del agente desde 192.168.1.94): `/cmd_vel` a 20 Hz desde la Vita,
  `/g1/estado` a 25 Hz y `/tf`, `/odom`, `/joint_states` a 50 Hz desde `g1_sim`.
- **Topics «vacíos» = sesiones XRCE fantasma:** 7 sesiones abiertas (6 nodos `/ros2_vita`, 103 topics del dron,
  RB-KAIROS+, G1 antiguo…), porque cada cierre sin despedida dejaba la sesión anunciada y la clave era aleatoria.
  Arreglo en `ros2_vita`: clave estable `hash(nombre de la app | plataforma)` (`-p client_key:=N` para forzarla);
  probado con `kill -9` ×3 + 1 vivo → 1 nodo, «session re-established». Limpiar los de antes: `docker restart vita_agent`.
- **`g1_sim`:** `robot_state_publisher` (`/robot_description` + TF de los 29 joints), `/map` de la casa (latched) y
  `map → odom`; `vita-ros.sh g1-rviz` con `docker/g1/g1.rviz`. Cámara: no existe en `g1-unitree` (está en `g1-sensores`).
- Editores, plantilla Vita (`PASS … 694 imports`) y `.vpk` reconstruidos; host 294/0.

