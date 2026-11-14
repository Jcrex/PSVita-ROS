# Siguiente sesión — pasos y acciones pendientes (actualizado el 2026-11-15)

> Lista ordenada para retomar en frío. Estado vivo: primer bloque de `docs/06-bitacora-estado.md`. Reglas de trabajo:
> `CLAUDE.md` (modo autónomo; decisiones técnicas → subagente **Fable 5.2**, sin preguntar al usuario; pruebas de
> hardware y acciones irreversibles → usuario). Comandos para el PC en **fish**.

## 0. Dónde quedó (2026-11-15)

- **Fase O** (organización, ADR 0014) y **Fase V** (visor de topics W13, V1–V15, ADR 0013) hechas y verificadas en
  host. **PR #3 aceptado y fusionado en `main` por el usuario** (2026-11-14).
- **Historial público purgado (2026-11-15, pedido por el usuario):** `respaldo-chat-claude/` reescrito fuera de `main`
  y de `ccr-44e2db2a-mr6xqr` (`git filter-branch`, *force-push*; contenido actual idéntico). Copia de seguridad previa:
  `~/Proyectos/psvita-ros-antes-purga-2026-11-15.bundle`. **Queda un resto que solo GitHub puede quitar:** las
  referencias de solo lectura `refs/pull/2/head` (`ca510f3`) y `refs/pull/3/head` siguen apuntando a los commits
  antiguos (visibles desde las páginas de los PR #2/#3). Para borrarlos del todo: pedirlo al soporte de GitHub
  («remove cached views / sensitive data», https://support.github.com) — acción del usuario. **Cualquier otro clon
  (la laptop) debe hacer `git fetch` + `git reset --hard origin/main`** (no `pull`, o reintroduce los commits viejos).
- **Decisiones del usuario (2026-11-15):** web **en pausa**, aprendizaje **en pausa**, g1-sensores con **luz clara**
  (`"luz_por_vertice": true` en `godot/g1-sensores/robot.json`, «luz V», 57 FPS medidos).
- **Nada del visor se ha probado en la Vita.** rclgd jazzy compilado y probado (45/45) en el PC; el visor con rclgd
  tiene guía de prueba con interfaz para el usuario: `docs/37-guia-rclgd-gui-pc.md` (ver §2).
- Verde en host: 14 suites `godot/plantillas/pruebas/visor*.gd`, `godot/test/run_host_tests.sh`, runner de
  g1-sensores 16/16, `docker/scripts/test_vita_relay.py`, paridad de módulos.

## 1. Prioridad 1 — el usuario prueba TODAS las versiones actuales en la Vita (próxima sesión)

El usuario probará primero todo lo actual en la Vita. Preparar y reexportar al empezar (por si cambió algo):

```fish
cd ~/Proyectos/PSVita-ROS
git pull
tools/export-vita-vpk.sh godot/visor-ros build/visor-ros.vpk
tools/export-vita-vpk.sh godot/g1-sensores build/g1-sensores.vpk
```

1. **g1-sensores** con escenas editables y luz clara: `tools/deploy-vpk-ftp.sh build/g1-sensores.vpk 192.168.1.94`;
   verde = 57–58 FPS como el 2026-11-13 (doc 34 §7.1); con los arreglos de B1–B3 y `-O2` (si entraron, §3) anotar si
   mejora (`[perfil-gd]`, `[gxm2d-perf]`).
2. **Visor**: guion único `docs/ia/workshops/posts/V3-revision.md` §5 (9 lanzamientos, fases F1–F8, funciones
   `recoger`/`bw`/`pub`, tabla de verde). Gates V1–V12: G-W13-H0, E-W8-1 (banco con **START**), V5 (escena banco:
   **L+R+START**), V6 (20 avisos/s 5 min), V7 (meta con ✕ → `/goal_pose`), V8 (M1 12 nodos ≥ 55 FPS, M1v 32 ≥ 30 FPS,
   M2 estrés 48, M3 33), V9 (8 marcos a 10 Hz), V10 (E-W8-5 JPEG ≤ 6 ms), V11 (M5: repaso ≤ 3 s, parche < 1 s), V12
   (pestañas Gráficas/Inspector). Desde Estado, **L ×3** → Consola.
3. Con las mismas fases, gate **G-V13b** (`docs/ia/workshops/posts/V13b-juez-fable.md` §4): `[visor-mapa] max_us`,
   `[visor-costmap] max_us`, `[visor-nube] us_max` ≤ 2000 µs; `[perfil-gd] visor/Scan` ≤ 1000 µs.
4. Logs a Claude → resultados en `docs/36-visualizacion-topics-godot.md` §9.0/§13 y doc 34 (g1-sensores).

## 2. Prioridad 2 — el usuario prueba rclgd con interfaz gráfica en el PC

Seguir `docs/37-guia-rclgd-gui-pc.md` (contenedor jazzy con rclgd compilado + pantalla del host; demo
`rclgd_sensors`; visor con rclgd; criterios por display). Lo marcado «[usuario] verificar en pantalla» solo lo puede
ver él. Volcar el resultado en doc 36 §13.4 (lo no probado con rclgd).

## 3. Prioridad 3 — Claude, tras las pruebas

1. **Arreglar lo que salga rojo** en §1/§2: diagnóstico con logs, arreglo con prueba de host, reexportar, nueva prueba.
   Si G-V13b sale rojo en una ruta: implementar SOLO esa función en `modules/viz-decode/` (dual Rust+C con paridad;
   Rust explicado para principiante).
2. **Bugs y optimizaciones pequeños** (autorizados el 2026-11-15 «si no duran mucho»): B1, B2, B3, `-O2` en SCsub,
   pools de red duplicados — **estado al cerrar la sesión del 2026-11-15: ver la bitácora** (lo que no se hizo, con su
   motivo, sigue aquí).
3. **Decisiones de rclgd para próximas sesiones** (Fable): modo «rclgd» permanente en `godot/visor-ros` y en las
   suites `visor*.gd` (hoy usan `ros2_vita`); si se monta un contenedor/compose propio con rclgd 3.0.0 (apt solo da
   2.1.0); qué parte de la guía doc 37 se automatiza.

## 4. Para próximas sesiones (decidido por el usuario el 2026-11-15)

1. **R1** `shutdown()` desde un timer se sale de rango (`godot/ros2_vita/ros_runtime.cpp`).
2. **Comparar `roomba_hmi` y `rclgd_sensors`** con `godot/plantillas/` y el visor; reusar lo bueno con la regla de
   escenas (doc 35). Clones en `~/Proyectos/rclgd-estudio/` (estado en `docs/24` §Commits estudiados).
3. **Gates fuera del guion:** G-W13-R0 (corte real 488/489 B, docs/27 §4), G-W13-M7, `/tf` real por XRCE con
   `tf_nativo`, coste de `lookup` por fotograma, `latest_only` con un topic directo rápido.
4. **MTU XRCE 512 → ~1400** (transporte + agente; riesgo de fragmentación en la WiFi de la Vita).
5. **X1** hipótesis `poll(0)`/HEARTBEAT: medir `reliable_full` en hardware antes de tocar nada.
6. **g1-sensores a 60 FPS estables:** bajar 0,5–1 ms de scripts de física (`sensor/mapeo`, `sensor/mid360_scan`
   ~0,6 ms cada uno, robot ~1,5 ms, sensores por turnos; doc 34 §8.4).
7. **Integrar el visor en las apps vivas** (g1-sensores, rbkairos-plus, dron-mapeo): `VisorRos` + displays en vez de
   los visualizadores propios de `plantillas/sensores/*` donde aplique.
8. **Tipos sin display** (18 ⏳ de doc 36a §4.0.1): priorizar con Fable.
9. **Tareas viejas sin prioridad:** F1 `deviceQuat` (recompilar motor), reto `/vita/joy`, panel trasero, ADR de cámara.
10. **En pausa por decisión del usuario:** web y modo aprendizaje (no tocar hasta que lo pida).

## 5. Archivos clave

| Qué | Dónde |
|---|---|
| Estado vivo | `docs/06-bitacora-estado.md` (primer bloque) |
| Visor: decisión, catálogo, estado | `docs/adr/0013-*.md`, `docs/36-*.md` (§9.0 gates, §13 estado), `docs/36a-*.md` |
| Visor: código y cómo añadir un display | `godot/plantillas/visor/README.md`, `godot/visor-ros/` |
| Guion de hardware | `docs/ia/workshops/posts/V3-revision.md` §5 |
| Guía rclgd con interfaz | `docs/37-guia-rclgd-gui-pc.md`; receta de compilación en `skills/rclgd/references/versiones.md` |
| Decisiones de Fable | `docs/ia/workshops/posts/{W13,V2,V3,V13b}-juez-fable.md` |
| Organización | `docs/adr/0014-*.md`, `docs/README.md`, `docs/ia/organizacion/` |
| Copia previa a la purga | `~/Proyectos/psvita-ros-antes-purga-2026-11-15.bundle` (borrar cuando se confirme que todo va bien) |
