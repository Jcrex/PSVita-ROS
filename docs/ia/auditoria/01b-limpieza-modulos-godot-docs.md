# Auditoría 01b — Limpieza de `modules/`, `godot/` y `docs/` (para la IA)

**Fecha:** 2026-11-01 · **Equipo:** Limpieza B (código y documentación) · **Modo:** solo lectura.
Base: `git ls-files` + `git status` (G7a sin versionar = trabajo vivo). Ignorados: `godot/rclgd/`,
`toolchains/`, `.obsidian/`, `node_modules/`, `target/`.

Clasificación: **ARCHIVAR** (superado; mover a `archivo/<ruta original>`), **ACTUALIZAR** (vivo, con
estado/enlaces viejos), **CONSERVAR**, **BORRAR**. Conjeturas marcadas como *hipótesis*.

---

## 1. Módulos duales (`modules/*`) — todos CONSERVAR

Consumidores (grep en código/CMake/SCsub/Cargo, excluyendo docs y web):

| Módulo | Último commit | Consumidores reales | Veredicto |
|---|---|---|---|
| `mem-pool` | 2026-06-28 | `vita-app/CMakeLists.txt:56,90`; crate paraguas `vita-app/rust-modules/Cargo.toml`; lección `docs/tutorial/01` | CONSERVAR |
| `net-udp` | 2026-06-28 | `vita-app` (CMake:57,91, `netlog.c`, `main.c`); `godot/ros2_vita/SCsub` (rama XRCE); `tools/hwprobe/CMakeLists.txt` | CONSERVAR |
| `microros-transport` | 2026-06-28 | `vita-app` (CMake:58,92, `uxr_glue.c`); `godot/ros2_vita/SCsub` + `xrce_transport.cpp` | CONSERVAR |
| `msg-ring` | 2026-10-27 | `godot/ros2_vita/SCsub:22,56` | CONSERVAR |
| `msg-schema` | 2026-10-27 | `godot/ros2_vita/SCsub`, `ros_msg.cpp/.h`, `godot/test`, `tools/gen_msg_schema.py` | CONSERVAR |
| `viz-math` | 2026-10-27 | `vita-app/src/viz/camera.c` (mini-rviz de la app C) | CONSERVAR |
| `msg-cdr` | 2026-10-27 | **solo** el crate paraguas (Cargo). Ningún `.c` ni `ros2_vita` lo llama | CONSERVAR (*nota*) |
| `tf-tree` | 2026-10-27 | **solo** el crate paraguas. Previsto en `docs/19` T3.4.1 (TF en ros2_vita) y T6.5 | CONSERVAR (*nota*) |

- `msg-cdr` y `tf-tree` no tienen consumidor en código, pero están en la paridad
  (`tools/run-parity-tests.sh:93` recorre `modules/*/`), en `build-c-pic.sh:25-29` (todas las
  `impl-c`) y tienen destino declarado: `modules/msg-schema/README.md:8` dice que `msg-cdr` «sigue
  siendo el camino rápido» del mini-rviz; `docs/17:252` igual. Archivar rompería el crate paraguas
  (`Cargo.toml` con `path = ...`) y G2. **No archivar.** Sí conviene que su README diga «sin
  consumidor todavía (mini-rviz / TF de ros2_vita)».
- `modules/{mem-pool,net-udp,microros-transport}/CMakeLists.txt` (2026-06-28): ningún script ni
  `vita-app` los usa (vita-app compila los `.c` directamente, `vita-app/CMakeLists.txt:90-92`). Son la
  plantilla que describe la skill `skills/vita-dual-module/SKILL.md:32,35,89`. Los 5 módulos posteriores
  no tienen `CMakeLists.txt`, pero `modules/msg-ring/README.md:49` aún pide «cross-compilar con
  `-DVITA_IMPL=c|rust`» (mecanismo inexistente para ese módulo). → **CONSERVAR** los 3, **ACTUALIZAR**
  la línea de msg-ring (ver §5). *Hipótesis:* la skill debería dejar de exigir CMake por módulo.
- `.o` en `modules/*/impl-c/` (p. ej. `net_udp.linuxbsd.editor.x86_64.o`): restos de SCons del motor;
  ignorados por `.gitignore:47-48`. No versionados → fuera de la limpieza git (se pueden borrar a mano
  en el PC; no afectan).

## 2. `godot/`

| Ruta | Último commit | Evidencia | Veredicto |
|---|---|---|---|
| `ros2_vita/` | 2026-10-30 | Producto principal; `build-godot-template.sh` lo usa | CONSERVAR (marcadores, §5) |
| `loader-patches/0001-ros2-vita-imports.patch` | — | `tools/build-godot-template.sh`, `godot/README.md` | CONSERVAR |
| `vitasdk-stubs/dlfcn.h` | — | `build-godot-template.sh:60-63` lo copia al SDK | CONSERVAR |
| `test/` | — | Puerta G1 (`run_host_tests.sh`, 294 comprobaciones) | CONSERVAR |
| `g4-smoke/` | 2026-10-30 `c3f414c` | `tools/export-vita-vpk.sh:6` (ejemplo de uso), `godot/README.md:35,53,59`, `CLAUDE.md:58`, `docs/18:347`, `fases.ts:137-138` | **CONSERVAR como regresión** |
| `g5-xrce/` | 2026-10-30 `91f256e` | `docker/README.md:10,37` (prueba de la estación en host), `godot/README.md:37,68,73`, `docs/18:348` | **CONSERVAR como regresión** |
| `g6-hmi/` | 2026-10-30 `ef31033` | App HMI piloto; `docs/ia/guion-ruta-aprendizaje.md:119` | CONSERVAR |
| `g7-imu/` (sin versionar) | — | Trabajo vivo G7a | CONSERVAR (ver riesgo `.godot/`) |
| `godot35/` | 2026-10-29 (merge) | Histórico 3.5, validado en hardware | **ARCHIVAR (lote final, opcional)** |

**Por qué G4/G5 se conservan:** forman una escalera de diagnóstico. G4 aísla motor+cargador **sin red**
(loopback, fondo verde/rojo); G5 es el XRCE mínimo (un String, ida y vuelta `/pc_hello`). Cuando un
cambio en el cargador o en `XrceTransport` rompa G6/G7, bajar a G5 y luego a G4 separa «red» de
«motor». Además `docker/README.md` usa `g5-xrce` para probar la estación sin Vita. Coste: ~170 líneas
de GDScript + 2 `schema.rsch`. *Opcional:* agruparlos en `godot/puertas/` — no lo recomiendo (rompe
`CLAUDE.md`, `docker/README.md`, `godot/README.md`, `docs/18 §8`, `fases.ts` sin ganancia real).

**`schema.rsch` ×4 (duplicado):** `godot/g{4,5,6,7}-*/ros/schema.rsch` son byte a byte idénticos
(`cmp`/`diff` sin salida, 4928 B cada uno). Godot exige que esté dentro de `res://`, así que no se
puede compartir sin más. → **ACTUALIZAR** (bajo): documentar en `godot/README.md` la orden de
regeneración (`tools/gen_msg_schema.py`, cabecera :12) y, *hipótesis*, que `tools/export-vita-vpk.sh`
lo copie desde una única fuente (`godot/ros/schema.rsch`) en la copia de trabajo (ya trabaja sobre
copia, `export-vita-vpk.sh:35-40`). Riesgo actual: añadir un tipo en uno y olvidar los otros.

**Riesgo G7a (importante antes del commit):** `godot/g7-imu/.godot/` existe y **no está ignorado**
(`git check-ignore -v godot/g7-imu/.godot` sin salida; ningún patrón `.godot` en `.gitignore`).
`git add godot/g7-imu` versionaría la caché del editor. → Añadir `godot/*/.godot/` (o `.godot/`) a
`.gitignore` antes de G7a. Los `*.gd.uid` (Godot ≥ 4.4) **sí** deben versionarse.

### `godot/godot35/` — detalle

- Sustituido por Godot 4 (`docs/06` bloque 2026-10-29; `godot/README.md:97-101`). No lo compila ningún
  flujo actual. Peligro latente documentado en `tools/build-godot-template.sh:69-70`: con
  `custom_modules=$REPO/godot` SCons recogería también `godot35/modules/microros`. Archivarlo quita ese
  riesgo.
- Duplicado parcial: `godot35/vitasdk-stubs/dlfcn.h` es un subconjunto del de Godot 4
  (`godot/vitasdk-stubs/dlfcn.h:11-12` lo dice). Se archiva con el resto.
- **BORRAR** (dentro): `godot35/imagenes/rover-iberus.jpeg.import` (huérfano: el `.jpeg` no existe ni
  en el disco) y `godot35/UI/UIIcons_2.zip` (32 KB, ninguna referencia en `project.godot`/escenas;
  *hipótesis*: material de diseño de la UI; preguntar al usuario).
- Marcadores viejos (si no se archiva): `godot35/modules/microros/micro_ros_gd.cpp:2` y `.h:13`
  «VALIDAR EN EL PC» — ya validado en hardware el 2026-07-13.
- **Qué rompe archivarlo** y hay que cambiar en el mismo commit:
  - `godot35/scripts/build-vita-template.sh:18` `REPO=../../..` → `../../../..`; `:49,:61,:81,:84`
    rutas `$REPO/godot/godot35/...` → `$REPO/archivo/godot/godot35/...`.
  - `web/src/content.config.ts:56` (`godot/godot35/README.md`) → nueva ruta o colección `archivo`.
  - `web/Dockerfile` (añadir `COPY archivo/ /app/archivo/` si se crea la colección).
  - `.dockerignore:16-18`, `.gitignore:47` (rutas).
  - `README.md:11,81,143-144`, `godot/README.md:97-101`, `CLAUDE.md` (bloque `godot/godot35/`),
    `web/src/data/fases.ts:84,89`, `tools/build-godot-template.sh:70` (comentario),
    `godot/vitasdk-stubs/dlfcn.h:11-12` (comentario).

## 3. `docs/`

### 3.1 Duplicado de numeración `09`

| Ruta | Refs entrantes | Estado | Veredicto |
|---|---|---|---|
| `docs/09-objetivo2-control-robot.md` | 10+ (README:131, docs/06, 10, 13, 20, 21, `godot/README.md:38`, `g6-hmi/main.gd:3`) | vivo (mapeo de mandos de G6) | CONSERVAR con el número 09 |
| `docs/09-guia-pruebas-stack.md` | **0** | obsoleto en parte: describe `rmf_unified`/`rmf.sh` de IR2134 (`:29-30,86,89,119`), pero `tools/vita-stack.sh:5,23` usa ya por defecto la estación `docker/` (`vita_station`) | **ACTUALIZAR + renumerar** a `docs/23-guia-pruebas-stack.md` |

Renombrar es seguro (0 enlaces); en la web cambia el slug (`09-guia-pruebas-stack` →
`23-guia-pruebas-stack`), sin enlaces internos que romper. Alternativa: fusionar su contenido en
`docker/README.md` y archivarlo.

### 3.2 `docs/superpowers/` (6 ficheros, no está en ninguna colección de la web)

| Fichero | Fecha | Estado | Veredicto |
|---|---|---|---|
| `plans/2026-06-08-fundacion-psvita-ros2.md` + `specs/…-design.md` | 2026-06-08 | Fase 0 cerrada; 61 casillas `[ ]` sin marcar aunque se ejecutó | ARCHIVAR |
| `plans/2026-07-01-dashboard-logs-vita.md` | 2026-07-01 | ejecutado (dashboard `/monitor` en main, `docs/06:570`) | ARCHIVAR |
| `specs/2026-07-01-dashboard-logs-vita-design.md` | 2026-07-02 | **citado por código vivo**: `web/src/pages/monitor.astro:3`, `web/scripts/netlog-ingester.mjs:7`, `web/README.md:28,78` | ARCHIVAR **y** actualizar esas 4 referencias (o CONSERVAR en sitio si se prefiere no tocar `web/`) |
| `specs/2026-07-12-tutorial-vita-c-rust-design.md` | 2026-07-12 | superado por `docs/tutorial/07` y `docs/ia/README.md` | ARCHIVAR |
| `plans/2026-07-12-tutorial-vita-c-rust.md` | 2026-07-12 | Tasks 3–7 (lecciones 02–06) **sin hacer**; es el único guion de esas lecciones | **Mover a `docs/ia/`** (p. ej. `docs/ia/plan-lecciones-02-06.md`), no archivar |

Otras referencias a actualizar si se mueve: `docs/06:570-571,673-674`, `README.md:66`.
Nota: `docs/21:13-14,1265` cita la *skill* `superpowers:` (no la carpeta) → no cambiar.

### 3.3 Planes y estados obsoletos

- **`docs/19-plan-multiagente-migracion-godot4.md`** (2026-10-30) — **ACTUALIZAR** (después, si el
  usuario quiere, ARCHIVAR: el método multiagente quedó superado por el modo aprendizaje; el backlog
  vivo está en `docs/18 §10`). Ya lo señala `docs/06` bloque 2026-10-31. Líneas con ⏳ que están hechas:
  - `:117` T2.2.2 cliente XRCE para host → hecho (`vita-app/third_party/xrce-vita-host`, `SCsub:30`).
  - `:136` T3.1.2 SCsub con uxr/microcdr como `File` → hecho (`SCsub:38`).
  - `:147` T3.3.4 XrceTransport → hecho (`godot/ros2_vita/xrce_transport.cpp`).
  - `:158` T3.5.2 pruebas de XrceTransport en host contra el agente → hecho (G6, `docs/06`).
  - `:173` T5.1.2 editor 4.8-dev7 → hecho. `:176-177` T5.2.1/T5.2.2 → hecho (`tools/export-vita-vpk.sh`).
  - 5.4 despliegue FTP → hecho (`tools/deploy-vpk-ftp.sh`). `:187` T6.1 HMI → hecho (G6).
    T6.2 IMU → en curso. T1.4.1 → en curso.
  - `:357` tablero «G3–G7 pendiente» → G3–G6 verdes, G7 en curso.
  - **`xrce_core.c` no existe** (`git ls-files | grep xrce_core` vacío): el diseño cambió y la lógica
    vive en `xrce_transport.cpp`. Afecta `:119,136,147,246` (puerta H1), `:262,339,397`. También
    `web/src/data/fases.ts:131` (fuera de mi ámbito; avisar al equipo web).
- **`docs/adr/0008-godot-via-modulo-estatico.md:3`**: «la ejecución sigue sin validar en PC y
  hardware (G1–G7)» → falso: G1–G6 verdes (G4–G6 en hardware). ACTUALIZAR.
- **`docs/10-plan-objetivos-3-4.md:3`** «ejecución pendiente» y **`docs/11-diseno-mini-rviz.md:3`**
  «implementación en curso» (sin commits desde 2026-07-10; `vita-app/src/viz` último 2026-07-10) →
  ACTUALIZAR a «en pausa desde 2026-10-27: prioridad Godot 4 (ADR 0008); el 3D sigue en `vita-app/`
  (ADR 0008:45)». *Hipótesis:* el mini-rviz acabará en Godot (T6.5); decisión del usuario.
- **`docs/20-godot35-migracion-historico.md:143,173`** rutas antiguas (`godot/modules`,
  `godot/patches`) → hoy `godot/godot35/...`. ACTUALIZAR si no se archiva; si se archiva, dejar.
  `docs/21` es un plan histórico: no tocar sus rutas.
- **`docs/rust/00-herramientas-y-ecosistema.md:58-62`**: «solo en dos sitios … junta los tres módulos»
  → hoy son 8 módulos y hay un tercer sitio: `tools/build-rust-pic.sh` (staticlib PIC para
  `libgodot.so`). ACTUALIZAR. Hueco conocido: `docs/19` T8.4 (serie Rust sobre PIC/build-std) sin
  escribir.
- **`docs/tutorial/00-guia-del-tutorial.md:11-15,52`** lista lecciones 02–06 que **no existen**
  (`ls docs/tutorial` = 00, 01, 07, 08). ACTUALIZAR: marcarlas «pendiente».
- **`docs/tutorial/01-c-fundamentos-con-mem-pool.md`**: 2798 palabras > regla de 500
  (`docs/ia/README.md`). Es anterior a la regla. ACTUALIZAR *si el usuario lo pide*: versión corta en
  `tutorial/`, larga en `docs/ia/`.
- **`docs/06-bitacora-estado.md`** (13 896 palabras, 1469 líneas):
  - `:3` cabecera «Última actualización» de ~1 párrafo encadenado → recortar a la última fecha.
  - `:420` «Dónde nos quedamos (resumen de 1 minuto)» describe la Fase 0/1 (2026-06): quien lee «en
    frío» puede tomarlo por el estado actual → retitular «(histórico, 2026-06)» o partir el fichero
    (*propuesta*: `docs/06b-bitacora-historico-2026.md` con las secciones `:420-1469`).
  - `:665-680` mapa de `docs/` y `skills/` de junio (00–05, adr 0001–0004, rust 00–02, «3 skills»).
- **`docs/12`–`17`**: investigación con banners de decisión ya puestos (`docs/12:2-4`). CONSERVAR.
- **`docs/16`**: lista de páginas pendientes, parcialmente cerrada (`:25-26`). CONSERVAR; repasar.
- **`docs/22`**: «sin aplicar todavía» (correcto). CONSERVAR.
- **`docs/07`, `docs/08`** (web IDE): vivos para la fase web. CONSERVAR.
- **ADR 0001–0007**: aceptados; historia de decisiones. CONSERVAR (no se archivan ADRs).
- **`docs/guias-vita/`**, **`docs/rust/01-05`**, **`docs/ia/`**: CONSERVAR.
  `docs/ia/guion-guia-tutorial-original.md` es la guía 00 antigua, guardada a propósito
  (`docs/ia/README.md`).

## 4. Marcadores «validar en el PC / en hardware»

Obsoletos (ya validados) → ACTUALIZAR:

| Archivo:línea | Dice | Realidad |
|---|---|---|
| `godot/g4-smoke/main.gd:6` | «Validar en hardware.» | G4 verde en hardware 2026-10-30 |
| `godot/g5-xrce/main.gd:9` | «en la Vita: validar en hardware» | G5 verde |
| `godot/g6-hmi/main.gd:11` | idem | G6 verde |
| `godot/ros2_vita/config.py:2`, `register_types.cpp:1`, `register_types.h:1`, `ros_msg.cpp:1` | «para la Vita: validar en el PC (G3)» | G3 PASS; corre en hardware (G4–G6) |
| `godot/ros2_vita/xrce_transport.cpp:2`, `xrce_transport.h:2` | «en la Vita: validar en hardware» | G5/G6 en hardware |
| `godot/ros2_vita/SCsub:2-3` | solo menciona hasta G4 loopback | añadir G5–G6 |
| `godot/README.md:3` | «G1–G4 VERDES» | G1–G6 verdes, G7a en curso (el cuerpo ya lo dice) |
| `godot/README.md:62` | «Validar en hardware.» (paso G4) | hecho |
| `modules/mem-pool/README.md:47-48` | cross-compilación pendiente | hecha (Fase 1, 2026-06/07) y PIC (G2) |
| `modules/net-udp/README.md:15,63` | «compilar en el PC y validar en hardware» | C validado en hardware (Fase 1 y G5) |
| `modules/net-udp/impl-c/net_udp.c:7` | «VALIDAR EN HARDWARE» | validado (C). `impl-rust/src/lib.rs:93` **sigue siendo correcto** (la variante Rust no ha corrido en la Vita; la plantilla de hardware es la C, `docs/06` 2026-10-30) |
| `modules/microros-transport/README.md:68-69` | cross y sesión XRCE real pendientes | hechas (Fase 1 2026-07-01, G5) |
| `modules/msg-ring/README.md:49,52` | cross con `-DVITA_IMPL` pendiente; integrar en Godot | cross hecho en G2 (C y Rust PIC); integrado en `ros2_vita` (`SCsub:22,56`); vita-app aún no |
| `modules/{msg-schema:58,viz-math:37,tf-tree:33,msg-cdr:48}/README.md` | «cross-compilar» | hecho en G2 (`build-c-pic.sh` compila todas las `impl-c`; el paraguas Rust los incluye). Las mediciones en hardware siguen pendientes (correcto) |
| `docs/15-rust-nativo-y-optimizacion-vita.md:50` | «perfil … a validar en el PC» | *hipótesis*: parcialmente hecho con `build-rust-pic.sh` (G2/G3); revisar el perfil concreto |

Correctos (dejar): `godot/g7-imu/main.gd:18`, `nivel.gd:7`, `godot/README.md:39`, `docs/18:261,319`,
`msg-schema/README.md:59`, `viz-math:38`, `msg-ring:50`, `tf-tree:33` (parte de medir),
ADR 0005:67, ADR 0007:83 (vita-app), `docs/10:49`, `docs/11:76`.

## 5. Carpeta de archivados y la web

Propuesta: `archivo/` en la raíz, conservando la ruta original (`archivo/docs/superpowers/...`,
`archivo/godot/godot35/...`, `archivo/docs/20-...`).

**La web:** `archivo/` no está en ninguna colección de `web/src/content.config.ts` → lo archivado
**desaparece de la web**. Como la regla del usuario es «toda la documentación en la web», propongo:

1. `content.config.ts`: colección `archivo` con `glob({ pattern: 'archivo/**/*.md', base: '..' })`.
2. `web/src/lib/docs.ts` `seccionesDocs`: sección «Archivo (histórico)» y ampliar el tipo `key`.
3. `web/Dockerfile`: `COPY archivo/ /app/archivo/` (junto a `:27-34`).
4. Quitar `godot/godot35/README.md` de la colección `codigo` (`content.config.ts:56`).
5. Los `docs/20`, `21` salen de `fundacion` (patrón `[0-9][0-9]-*.md` en `../docs`) al moverlos.

**Nueva carpeta `docs/informes/`** (creada por esta auditoría): tampoco está en ninguna colección.
Por la regla de `CLAUDE.md` hay que añadir colección + sección (la `COPY docs/` ya la cubre).

## 6. Orden de `git mv` propuesto (cada lote = un commit; paridad verde antes)

0. **Antes de todo:** commit de G7a con `.godot/` ignorado (`.gitignore`). No mezclar limpieza con G7a.
1. **Web primero** (para no perder nada): colecciones `archivo` e `informes`, sección y `COPY`.
2. **Lote docs/superpowers:**
   ```bash
   mkdir -p archivo/docs/superpowers
   git mv docs/superpowers/plans/2026-07-12-tutorial-vita-c-rust.md docs/ia/plan-lecciones-02-06.md
   git mv docs/superpowers archivo/docs/superpowers
   ```
   + actualizar `web/src/pages/monitor.astro:3`, `web/scripts/netlog-ingester.mjs:7`,
   `web/README.md:28,78`, `docs/06:570-571`, `README.md:66`, `docs/ia/README.md` (contenido).
3. **Renumerar 09:** `git mv docs/09-guia-pruebas-stack.md docs/23-guia-pruebas-stack.md` + editar
   `:29-30,86,89,119` (estación `docker/`) y su título. Añadir a la tabla de `README.md`.
4. **Ediciones ACTUALIZAR** (sin mover): §3.3 y §4 (docs/19, ADR 0008, docs/10, 11, rust/00, tutorial/00,
   godot/README, marcadores de ros2_vita y g4–g6, READMEs de módulos).
5. **Borrados en godot35:** `git rm godot/godot35/imagenes/rover-iberus.jpeg.import
   godot/godot35/UI/UIIcons_2.zip` (confirmar el zip con el usuario).
6. **Lote godot35 (opcional, el último):**
   ```bash
   mkdir -p archivo/godot archivo/docs
   git mv godot/godot35 archivo/godot/godot35
   git mv docs/20-godot35-migracion-historico.md docs/21-godot35-plan-implementacion-historico.md archivo/docs/
   ```
   + todas las ediciones de §2 «Qué rompe archivarlo». Comprobar con `git grep -n "godot/godot35\|docs/2[01]-"`
   que no quedan rutas viejas fuera de `archivo/`.

**No archivar:** ningún módulo, G4/G5/G6, `loader-patches`, `test`, `vitasdk-stubs`, ADRs.
