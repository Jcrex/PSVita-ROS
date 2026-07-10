# 10 — Plan de desarrollo: Objetivos 3 y 4 (rviz2 / mini-rviz en la Vita)

**Fecha:** 2026-07-07 · **Estado:** plan aprobado, ejecución pendiente
**Prerrequisitos cumplidos:** Objetivo 1 (topics, Fase 1) y Objetivo 2
(teleop `/cmd_vel`) cerrados y confirmados en hardware real.

Esta es la **guía operativa completa** para desarrollar los Objetivos 3 y 4
de `docs/00-vision-y-objetivos.md`:

- **Objetivo 3:** compilar rviz2 (o un subconjunto funcional) en la consola.
- **Objetivo 4:** visualizar en la Vita lo que rviz2 visualiza en un PC:
  transformadas TF, el modelo del robot **moviéndose en tiempo real**,
  mapas de ocupación y marcadores.

Además incorpora dos peticiones explícitas del usuario: **UI declarativa
v2** (imágenes, formas, edición visual desde la web) y **visualizador 3D**
del robot con su movimiento simulado en vivo.

---

## 0. Cómo usar esta guía (reglas para la IA ejecutora)

Esta guía está escrita para ser ejecutada por un modelo de IA que **puede
alucinar**. Reglas de obligado cumplimiento:

1. **Nunca inventes una API, un nombre de paquete, un tipo DDS ni una ruta.**
   Cada tarea tiene una sección "Leer antes" con los archivos exactos que
   dan el contexto. Léelos ANTES de escribir código. Si un dato no está en
   el repo ni en esta guía, obtenlo con un comando (sección 9, "Datos duros
   y cómo obtener la verdad") — no lo deduzcas de memoria.
2. **Orden estricto:** las etapas A → F son secuenciales. Dentro de una
   etapa, las tareas también. No empieces una tarea con la anterior a
   medias.
3. **Al terminar CADA tarea:** corre las verificaciones que indica, y si
   son verdes haz UN commit con el mensaje sugerido (prefijos
   convencionales, texto en español). Nunca dejes tests rojos commiteados.
4. **Al cerrar CADA etapa:** actualiza `docs/06-bitacora-estado.md`
   (bloque nuevo con fecha y máquina), `web/src/data/fases.ts` (hitos de
   `fase-3-4`) y este documento (marca la etapa como HECHA). Push a
   `origin main`.
5. **Máquina correcta:** todo lo que compile para la Vita se hace EN EL PC
   (CachyOS, este repo en `~/Proyectos/PSVita-ROS`). Antes de cualquier
   build: `source tools/env-devpc.sh` (bash/zsh) o `.fish`. La laptop solo
   produce texto/código verificable en host.
6. **Lo verificable en host, se verifica en host.** Toda lógica nueva que
   no toque GPU/pantalla va en módulos duales (C+Rust) o en C puro sin
   headers de la Vita, con batería propia estilo
   `vita-app/scripts/check-teleop.sh`. El código solo-Vita (vitaGL,
   vita2d) se marca "validar en hardware" en comentarios y README.
7. **Si encuentras un muro** (error de compilación, símbolo que falta,
   crash): NO lo rodees en silencio. Documenta síntoma exacto + causa raíz
   + fix (o "sin fix, se activa alternativa X") en la bitácora, como se
   hizo con los muros de la Fase 1.
8. **Español** en docs, comentarios y commits. El usuario es principiante
   en Rust: **cada construcción de Rust nueva se explica** en comentarios
   y, si es un concepto nuevo, con una entrada en `docs/rust/`.

### Lecturas obligatorias iniciales (una sola vez, antes de empezar)

| Archivo | Qué te da |
|---|---|
| `CLAUDE.md` | Reglas del repo, roles de máquinas, comandos comunes. |
| `docs/06-bitacora-estado.md` | Estado real actual y muros ya resueltos (NO re-tropezar). |
| `docs/00-vision-y-objetivos.md` | Qué son los Objetivos 3 y 4 y las restricciones transversales. |
| `docs/04-investigacion-portabilidad-rviz2.md` | El método de auditoría y el árbol de decisión de la Etapa A. |
| `docs/03-estrategia-dual-rust-cpp.md` | Cómo se construye un módulo dual (contrato header, paridad). |
| `docs/09-objetivo2-control-robot.md` | Cómo se diseñó/cerró el Objetivo 2 (plantilla de calidad). |
| `vita-app/src/main.c` | El ciclo de vida completo de la app: sesión XRCE, entidades DDS, bucle. |
| `vita-app/README.md` | Mapa de archivos de la app y topología de red (agente EN LA LAPTOP). |
| `modules/net-udp/` (entero) | El módulo dual de referencia: header, impl-c, impl-rust, tests. |
| `docs/adr/` (los 5 ADR) | Decisiones ya tomadas — no las contradigas sin ADR nuevo. |

---

## 1. Estado de partida (lo que YA existe y funciona — no reconstruir)

- **Sesión XRCE estable en hardware** sobre WiFi/UDP contra
  `microros/micro-ros-agent:jazzy` (v2.4.3) corriendo en la laptop
  (192.168.1.108, `--net=host --ipc=host`). Cliente XRCE cross-compilado
  en `vita-app/third_party/xrce-vita/` (gitignored; se regenera con
  `vita-app/scripts/build-xrce-client-vita.sh`).
- **App única** `vita-app/` ("Vita ROS2 Teleop", TITLEID `VROS00001`):
  publica `/vita_hello` (1 Hz) y `/cmd_vel` (~20 Hz), se suscribe a
  `/pc_hello`. Serialización CDR a mano con `ucdr_*`.
- **UI declarativa v1** (ADR 0005): `vita-app/ui/layout.json` →
  `scripts/gen-ui-header.mjs` → `src/ui_layout.h` → intérprete
  `src/ui.c` (vita2d). Editor web en `/taller/ui`.
- **3 módulos duales** con paridad C/Rust verde en host y en el PC.
- **Web Astro** con taller (compilar `.vpk`, deploy FTP, editor UI) y
  **visor 3D en navegador** (`/visor3d`) con **parser URDF propio en
  `web/src/lib/visor3d.ts`** (primitivas + mallas + jerarquía de joints).
- **Toolchain en el repo** (`toolchains/`): VitaSDK v2.540, cmake, rustup
  nightly. vdpm en `toolchains/vdpm/`. libvita2d YA instalada.
- **Deploy**: FTP `curl -T <archivo> ftp://192.168.1.94:1337/ux0:/`
  (VitaShell modo FTP; la IP de la Vita puede cambiar — confirmar).

## 2. Decisión de arquitectura previa (leer antes de tocar nada)

La expectativa razonada (docs/04) es que rviz2 nativo **no** es portable
(rclcpp+DDS+Qt+OGRE contra newlib). El plan asume que la Etapa A lo
confirmará y activa el **Plan B: mini-rviz propio con vitaGL**. Si la
Etapa A sorprendiera en sentido contrario, PARAR y rediseñar las etapas
B–E con el usuario antes de seguir.

Arquitectura objetivo del mini-rviz (Plan B):

```
                    ┌─ PC/web: /taller/modelo ─────────────┐
  URDF del robot ──►│ parser visor3d.ts → exportador VBM   │──► model.vbm
                    └──────────────────────────────────────┘      │ (FTP)
                                                                  ▼
  grafo ROS2 ──agente──► XRCE ──► vita-app ── msg-cdr ──► estado viz
  (/tf, /joint_states,             (main.c)   (módulo      (tf-tree +
   /map, markers)                              dual)        modelo VBM)
                                                              │
                                              viz/ (vitaGL) ◄─┘
                                              cámara + grid + robot
                                              animado + mapa + markers
```

---

## 3. Jerarquía de carpetas final (qué se crea, qué se modifica, qué NO se toca)

```
PSVita-ROS/
├── docs/
│   ├── 04-investigacion-portabilidad-rviz2.md   [MODIFICAR: Etapa A rellena los [abierto]]
│   ├── 06-bitacora-estado.md                    [MODIFICAR: al cerrar cada etapa]
│   ├── 10-plan-objetivos-3-4.md                 [MODIFICAR: marcar etapas hechas]
│   ├── 11-diseno-mini-rviz.md                   [CREAR en B0: diseño fino del Plan B]
│   ├── adr/0006-decision-rviz2-vs-mini-rviz.md  [CREAR en A5]
│   ├── adr/0007-convivencia-vita2d-vitagl.md    [CREAR en B2]
│   └── rust/                                    [CREAR entradas si aparecen construcciones nuevas]
├── modules/
│   ├── mem-pool/, net-udp/, microros-transport/ [NO TOCAR — solo leer como plantilla]
│   ├── viz-math/                                [CREAR en D1: vec3/quat/mat4 dual C+Rust]
│   ├── msg-cdr/                                 [CREAR en D2: deserializadores CDR dual]
│   └── tf-tree/                                 [CREAR en D3: buffer/lookup de TF dual]
├── vita-app/
│   ├── CMakeLists.txt                           [MODIFICAR: fuentes viz/, libs vitaGL, assets]
│   ├── src/main.c                               [MODIFICAR: suscripciones nuevas + modo 3D]
│   ├── src/teleop.{h,c}                         [NO TOCAR — Objetivo 2 cerrado]
│   ├── src/netlog.{h,c}, uxr_glue.{h,c}         [NO TOCAR]
│   ├── src/ui_types.h, ui.c, ui/layout.json     [MODIFICAR en C1: tipos imagen/forma]
│   ├── src/ui_layout.h                          [GENERADO — jamás editar a mano]
│   ├── ui/assets/                               [CREAR en C1: PNGs de la UI]
│   ├── src/viz/                                 [CREAR en B3/E: escena, cámara, robot, mapa]
│   │   ├── viz.h  viz.c                         (orquestación, SOLO Vita)
│   │   ├── camera.{h,c}  draw_prims.{h,c}       (usa viz-math; lógica testeable en host)
│   │   ├── vbm.{h,c}                            (loader del modelo binario; testeable en host)
│   │   └── README.md                            (qué se valida dónde)
│   ├── scripts/check-teleop.sh                  [NO TOCAR]
│   ├── scripts/check-vbm.sh, check-viz-host.sh  [CREAR: baterías host de vbm/cámara]
│   └── tests/                                   [MODIFICAR: añadir tests host nuevos]
├── web/
│   ├── src/lib/visor3d.ts                       [MODIFICAR en E1: exportar también a VBM]
│   ├── src/lib/vbm.ts                           [CREAR en E1: formato binario compartido]
│   ├── src/lib/ui-layout.ts + pages/taller/ui.astro [MODIFICAR en C: espejo UI v2]
│   ├── src/pages/taller/modelo.astro            [CREAR en E1: URDF → VBM → FTP a la Vita]
│   └── src/data/fases.ts                        [MODIFICAR al cerrar hitos]
├── toolchains/                                  [NO TOCAR salvo `./vdpm <paquete>`]
├── tools/run-parity-tests.sh                    [NO TOCAR: descubre modules/*/ solo]
└── auditoria/                                   [CREAR TEMPORAL en A — gitignored, logs de la auditoría]
```

---

## 4. ETAPA A — Auditoría de portabilidad de rviz2 (Objetivo 3, la respuesta) — **HECHA (2026-07-10, en el PC)**

> **Resultado:** rviz2 nativo NO portable (ament/Python, sin dlopen en
> newlib, símbolos glibc, Qt inexistente en vitasdk/packages, OGRE no
> reconoce la plataforma). **ADR 0006 aceptado: Plan B mini-rviz.**
> Evidencia en docs/04 (rellenado) y logs en `auditoria/` del PC.
> A4 no aplicó (nada compiló).

Meta: ejecutar el árbol de decisión de `docs/04` con evidencia real y
registrar la decisión en un ADR. **Salida esperada: docs/04 sin ningún
`[abierto]`** y ADR 0006 decidido.

### A1 — Preparar el terreno de auditoría

- **Leer antes:** `docs/04` completo; `docs/05-setup-entorno-cachyos.md`
  (cómo está montado el toolchain); `vita-app/scripts/build-xrce-client-vita.sh`
  (ejemplo REAL de cómo cross-compilar una lib externa con este toolchain:
  dos cmake encadenados, `CMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake`).
- **Crear:** carpeta `auditoria/` en la raíz + añadirla a `.gitignore`
  (los clones y logs no se versionan; las CONCLUSIONES van a docs/04).
- **Comandos:**
  ```bash
  source tools/env-devpc.sh
  mkdir -p auditoria && grep -q '^auditoria/' .gitignore || echo 'auditoria/' >> .gitignore
  ```

### A2 — Auditar la capa ROS2 (rcutils → rcl → rclcpp)

La forma barata de encontrar el PRIMER muro: empezar por abajo.
`rcutils` es C puro y la base de todo `rclcpp`; si ni él compila, el
resto cae en cascada y ya tienes el muro documentable.

- **Leer antes:** el error de cada intento ANTES de escribir conclusiones.
- **Comandos** (rama `jazzy` — no inventes tags):
  ```bash
  cd auditoria
  git clone --depth 1 -b jazzy https://github.com/ros2/rcutils.git
  cmake -S rcutils -B build-rcutils \
        -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake \
        -DBUILD_TESTING=OFF 2>&1 | tee log-rcutils-configure.txt
  cmake --build build-rcutils 2>&1 | tee log-rcutils-build.txt
  ```
  Nota: fallará probablemente ya en el configure por `ament_cmake`
  (el build system de ROS2 requiere Python+ament instalados para el
  target). Ese YA es un hallazgo de primer orden: **el build system de
  ROS2 no es cross-compilable a newlib sin un workspace colcon completo**.
  Si quieres aislar el código C del build system, segundo intento:
  compilar a mano 3-4 fuentes representativas
  (`arm-vita-eabi-gcc -c rcutils/src/time.c -Ircutils/include ...`) y
  anotar qué headers/símbolos POSIX faltan (esperables: `dlfcn.h`,
  procesos, filesystem completo).
- **Registrar en docs/04:** capa `rclcpp`: `[abierto]` → resultado con el
  error textual exacto (copiado de los logs, no parafraseado de memoria).

### A3 — Auditar Qt y OGRE (documental + un intento de configure)

- **Qt:** no existe port de Qt para VitaSDK (verifícalo, no lo afirmes de
  memoria: `curl -sIL -o /dev/null -w '%{http_code}\n'
  https://github.com/vitasdk/packages/releases/download/master/qt5.tar.xz`
  → esperado 404; y busca en https://github.com/vitasdk/packages la lista
  real). Documenta: Qt requiere backend de ventanas/eventos que la Vita
  no tiene (docs/04 ya lo hipotetiza — conviértelo en hallazgo).
- **OGRE:** un solo intento de configure basta para el registro:
  ```bash
  cd auditoria
  git clone --depth 1 -b v1.12.13 https://github.com/OGRECave/ogre.git
  cmake -S ogre -B build-ogre \
        -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake \
        -DOGRE_BUILD_RENDERSYSTEM_GLES2=ON 2>&1 | tee log-ogre-configure.txt
  ```
  (la versión 1.12.x es la que usa `rviz_rendering` en Jazzy — si dudas,
  verifica en https://github.com/ros2/rviz/blob/jazzy/rviz_rendering/package.xml).
- **Registrar en docs/04** ambos resultados con evidencia.

### A4 — (Solo si TODO lo anterior compilara) auditar integración real

Improbable. Si ocurre: parar, avisar al usuario, rediseñar B–E.

### A5 — ADR 0006: decisión rviz2 nativo vs mini-rviz

- **Leer antes:** `docs/adr/0001-*.md` (formato de ADR del repo) y el
  docs/04 ya rellenado.
- **Crear:** `docs/adr/0006-decision-rviz2-vs-mini-rviz.md` — contexto,
  evidencia (citando los logs), decisión (esperada: Plan B mini-rviz con
  vitaGL), consecuencias (qué NO tendrá el mini-rviz).
- **Cierre de etapa:** actualizar docs/04 (estado: "investigación
  ejecutada"), bitácora, fases.ts. Commit:
  `docs(objetivo3): auditoria rviz2 ejecutada — ADR 0006 decide <resultado>`.

---

## 5. ETAPA B — vitaGL en la app: el lienzo 3D — **CÓDIGO HECHO (2026-07-10) · validación en hardware PENDIENTE**

> B0 hecho (docs/11). B1 hecho (vitaGL+deps instalados y verificados;
> OJO: el paquete es `libmathneon`, `mathneon` da 404). B2 resuelto SIN
> PoC: la Opción 1 es imposible a nivel de API (ADR 0007 → Opción 2,
> todo vitaGL; ui.c reescrito, vita2d/ScePgf fuera). B3: viz/camera +
> viz/viz + modos TELEOP↔VIZ (SELECT) implementados; checks host verdes
> (camera 16/16, ui-layout, teleop) y AMBAS variantes `.vpk` compilan en
> el PC (C 474 KB / Rust 532 KB). **Falta solo:** deploy FTP + ver en la
> consola grid/ejes/cubo + regresión `/cmd_vel` (la Vita estaba
> inaccesible el 2026-07-10).

Meta: una escena 3D mínima (grid + ejes + cubo) dibujada por vitaGL en la
Vita, conviviendo con la UI vita2d existente, con cámara orbital movida
por los mandos. **Aquí está la incógnita dura de esta fase** (ver B2).

### B0 — Diseño fino del mini-rviz

- **Leer antes:** docs/04 §"Plan B", ADR 0006, `vita-app/src/ui.c` y
  `main.c` (cómo se estructura hoy el bucle y el dibujado).
- **Crear:** `docs/11-diseno-mini-rviz.md` con: alcance del MVP
  (grid, ejes TF, modelo VBM animado, marcadores básicos, mapa 2D),
  presupuesto de memoria/ancho de banda (ver §9.4), los modos de la app
  (modo TELEOP 2D actual ↔ modo VIZ 3D, conmutados con SELECT), y el
  formato VBM v1 (ver E1). Commit: `docs(objetivo4): diseño del mini-rviz`.

### B1 — Instalar vitaGL y dependencias

- **Leer antes:** `docs/06` bloque 2026-07-07 (la lección de vdpm: el
  paquete equivocado "instala" con éxito aunque el tar falle — SIEMPRE
  verificar que los archivos aparecieron).
- **Comandos:**
  ```bash
  source tools/env-devpc.sh
  cd toolchains/vdpm
  ./vdpm vitaGL libpng zlib mathneon vitashark SceShaccCgExt taihen
  # VERIFICAR (no confiar en el "Successfully installed"):
  ls "$VITASDK/arm-vita-eabi/lib/"     | grep -iE "vitaGL|png|z\.a|mathneon|shark"
  ls "$VITASDK/arm-vita-eabi/include/" | grep -iE "vitaGL|png"
  ```
  Nota: `vitaGL` y `libpng`/`zlib` existen seguro en vitasdk/packages
  (verificado 2026-07-07 con HTTP 200). `mathneon`, `vitashark`,
  `SceShaccCgExt` y `taihen` son las dependencias TÍPICAS de vitaGL para
  compilar shaders en runtime — si alguno da 404 en vdpm, consulta la
  lista real (§9.1) y el README de vitaGL para tu versión.
- **Commit:** nada (toolchains/ está gitignored) — anota versiones en la
  bitácora al cerrar la etapa.

### B2 — PoC de convivencia vita2d ↔ vitaGL (incógnita dura) + ADR 0007

**Problema real, no hipotético:** vita2d y vitaGL inicializan ambos el
GPU (SceGxm) y en general **no pueden estar activos a la vez**. Hay que
decidir con un experimento en hardware:

- **Opción 1 (preferida si funciona):** modos excluyentes —
  `ui_shutdown()` (vita2d) antes de `viz_init()` (vitaGL) al entrar al
  modo 3D, y viceversa al salir. Riesgo: fugas/crashes al re-init.
- **Opción 2:** todo vitaGL — reescribir el intérprete `ui.c` sobre
  vitaGL (quads texturizados + fuente propia). Más trabajo, un solo dueño
  del GPU. La UI declarativa (layout.json/codegen) NO cambia, solo el
  backend de dibujo.
- **Cómo decidir:** app de prueba mínima que haga
  vita2d init→draw→shutdown → vitaGL init→triángulo→shutdown → vita2d
  otra vez, con logs al netlog en cada paso. Compilar como variante
  aparte (NO tocar la app principal todavía): copia mínima en
  `auditoria/poc-gxm/` con su propio CMakeLists (plantilla: el
  CMakeLists de vita-app recortado).
- **Leer antes:** samples oficiales de vitaGL para la API real y los
  flags de link (NO los inventes):
  ```bash
  cd auditoria && git clone --depth 1 https://github.com/Rinnegatamante/vitaGL.git
  cat vitaGL/samples/sample1/Makefile   # libs exactas de link
  cat vitaGL/samples/sample1/main.c     # vglInit, glClear..., vglSwapBuffers
  cat "$VITASDK/arm-vita-eabi/include/vitaGL.h" | head -100
  ```
- **Crear:** `docs/adr/0007-convivencia-vita2d-vitagl.md` con el
  resultado del experimento y la opción elegida.
- **Verificación:** el PoC corre en la Vita (deploy FTP + netlog) sin
  crash en 3 ciclos de conmutación, o queda documentado que la Opción 2
  es obligatoria.
- **Commit:** `feat(objetivo34): PoC vita2d<->vitaGL + ADR 0007 (<opcion>)`.

### B3 — Escena mínima en la app real

- **Leer antes:** `vita-app/src/main.c` (bucle y modos), el PoC de B2,
  `vita-app/CMakeLists.txt` (cómo se añaden fuentes y libs).
- **Crear:** `vita-app/src/viz/viz.{h,c}` (init/draw/shutdown; grid 10×10
  m, ejes XYZ colorados RGB, un cubo de referencia) y
  `vita-app/src/viz/camera.{h,c}` (cámara orbital: yaw/pitch/dist +
  target; SOLO matemáticas propias → usa el módulo `viz-math` si ya
  existe (D1) o float básico y migra en D1).
- **Modificar:** `main.c` (estado `modo` TELEOP↔VIZ con SELECT, según ADR
  0007), `CMakeLists.txt` (fuentes `src/viz/*.c` + libs de vitaGL según
  el Makefile del sample — cópialas de ahí, no de memoria).
- **NO tocar:** teleop.*, netlog.*, uxr_glue.*, los módulos existentes.
- **Verificación:** compila C y Rust; en hardware: se ve el grid y la
  cámara orbita con el stick derecho EN MODO VIZ y el teleop sigue
  funcionando EN MODO TELEOP (¡regresión del Objetivo 2!:
  `ros2 topic echo /cmd_vel`).
- **Commit:** `feat(objetivo34): escena 3D minima con vitaGL + modo VIZ`.

### Cierre de etapa B

Bitácora + fases.ts (hito Etapa B → hecho) + push.

---

## 6. ETAPA C — UI declarativa v2: imágenes y formas (petición explícita)

Meta: el usuario puede meter **imágenes PNG**, **líneas** y **círculos**
en la pantalla de la app, y editarlos desde la web.

**Regla de los 5 sitios** (ya establecida — si añades un tipo o binding
hay que tocar los 5 o el sistema queda inconsistente):
`vita-app/src/ui_types.h` + `vita-app/scripts/gen-ui-header.mjs` +
`vita-app/src/ui.c` + `web/src/lib/ui-layout.ts` +
`web/src/pages/taller/ui.astro`.

### C1 — Tipos nuevos en el runtime de la app

- **Leer antes:** los 5 archivos de la regla, `vita-app/ui/layout.json`
  actual, y el header real de vita2d para las funciones de dibujo
  (`grep -E "draw_line|fill_circle|draw_texture|load_PNG"
  "$VITASDK/arm-vita-eabi/include/vita2d.h"`).
- **Diseño:**
  - `linea`: x, y (inicio), x2, y2 (fin — reutiliza los campos w/h como
    x2/y2, documentándolo), color, grosor=escala.
  - `circulo`: x, y (centro), radio (campo w), color, relleno.
  - `imagen`: x, y, archivo (campo texto = nombre en `ui/assets/`,
    p. ej. `"logo.png"`), escala. `ui_init()` precarga los PNG de
    `app0:/ui/` con `vita2d_load_PNG_file` a un array de texturas;
    el widget referencia por índice resuelto en el codegen.
- **Crear:** `vita-app/ui/assets/` con al menos un PNG de prueba
  (generarlo con ImageMagick si hace falta:
  `magick -size 64x64 xc:#3b82f6 vita-app/ui/assets/test.png` — verifica
  antes que `magick` existe: `which magick || which convert`).
- **Modificar:** los 5 sitios + `vita-app/CMakeLists.txt` para empaquetar
  los assets dentro del `.vpk`. La macro real admite pares
  `FILE <origen> <destino>`; míralo en
  `$VITASDK/share/vita.cmake` (función `vita_create_vpk`) y añade:
  ```cmake
  vita_create_vpk(... FILE ui/assets/test.png ui/test.png)
  ```
- **Requisito de enlace:** `vita2d_load_PNG_file` necesita libpng+zlib →
  añadir `png` y `z` a `target_link_libraries` (ya instaladas en B1).
- **Verificación:** `bash vita-app/scripts/check-ui-layout.sh` (el
  codegen valida los tipos nuevos y el header compila en host);
  `.vpk` compila; en hardware se ven imagen/línea/círculo.
- **Commit:** `feat(ui-v2): widgets imagen, linea y circulo en la UI declarativa`.

### C2 — Editor web ampliado

- **Leer antes:** `web/src/pages/taller/ui.astro` completo (paleta,
  preview canvas, drag, borrador SQLite) y `web/src/lib/ui-layout.ts`
  (validación espejo).
- **Modificar:** paleta con los 3 widgets nuevos; preview canvas 2D los
  dibuja (línea/círculo nativos; imagen: sube un PNG pequeño y se guarda
  como dataURL en el borrador); "Aplicar al proyecto" escribe también los
  PNG nuevos a `vita-app/ui/assets/` (extiende el endpoint
  `web/src/pages/api/taller/ui/aplicar*` — localízalo con
  `grep -rn "aplicar" web/src/pages/api/taller/`).
- **Límites duros** (validar en AMBOS lados): PNG ≤ 256 KB, ≤ 8 imágenes,
  nombres `[a-z0-9-]+\.png`.
- **Verificación:** `cd web && pnpm build`; probar los endpoints como se
  hizo en el hito del editor (ver bitácora 2026-07-07, punto 4);
  `check-ui-layout.sh` verde con un layout que use los 3 tipos.
- **Commit:** `feat(web): editor /taller/ui v2 — imagenes y formas`.

### Cierre de etapa C

Bitácora + fases.ts + push. La UI v2 es también la base de los paneles
del modo VIZ (etiquetas sobre el 3D usan el mismo sistema).

---

## 7. ETAPA D — Los datos: módulos duales de visualización

Meta: todo lo que el mini-rviz consume (math 3D, mensajes deserializados,
árbol TF) como **módulos duales** con paridad C/Rust verde en host. Es la
etapa MÁS testeable — nada de esto necesita la Vita.

**Plantilla para crear un módulo dual:** copia la estructura de
`modules/net-udp/` (README.md, `include/<nombre>.h` como ÚNICO contrato,
`impl-c/`, `impl-rust/` crate rlib, `tests/parity_test.c`). El runner
`tools/run-parity-tests.sh` descubre `modules/*/` automáticamente — si tu
módulo sigue la estructura, se testea solo. Lee también la skill
`skills/vita-dual-module/` que automatiza el scaffold.

### D1 — `modules/viz-math/`: vec3, quat, mat4

- **Leer antes:** `modules/mem-pool/include/mem_pool.h` (estilo de
  contrato), `docs/03-estrategia-dual-rust-cpp.md`.
- **API mínima** (todo `float`, sin malloc, buffers del llamador):
  `vec3_add/sub/scale/cross/dot/norm`, `quat_from_axis_angle`,
  `quat_mul`, `quat_rotate_vec3`, `quat_to_mat4`,
  `mat4_identity/mul/translate/perspective/look_at`,
  `mat4_transform_point`. Column-major (lo que espera OpenGL — documenta
  esto en el header).
- **Paridad:** tests con valores conocidos a mano (rotación de 90° de
  (1,0,0) alrededor de Z da (0,1,0), etc.) y tolerancia 1e-5.
- **Rust:** explica en comentarios TODO lo nuevo (arrays, slices,
  `#[no_mangle]`, f32) — y si aparece algo no cubierto por
  `docs/rust/00-02`, añade `docs/rust/03-*.md`.
- **Verificación:** `tools/run-parity-tests.sh viz-math` verde.
- **Commit:** `feat(viz-math): modulo dual de matematicas 3D con paridad`.

### D2 — `modules/msg-cdr/`: deserializadores CDR de los mensajes de viz

- **Leer antes:** `vita-app/src/main.c` `on_topic()` (cómo llega un
  `ucdrBuffer`), y **las definiciones REALES de los mensajes** — nunca de
  memoria. Obtenerlas (cualquiera de las dos vías):
  ```bash
  docker exec robotnik_dev bash -lc "source /opt/ros/jazzy/setup.bash && \
    ros2 interface show tf2_msgs/msg/TFMessage --no-comments"
  # idem: sensor_msgs/msg/JointState, visualization_msgs/msg/Marker,
  #       nav_msgs/msg/OccupancyGrid
  ```
  o el MCP `ros2-introspection` (tool `get_message_definition`).
- **Reglas CDR (XCDR1, little-endian)** — ver §9.3. La API del módulo
  recibe `(const uint8_t *buf, size_t len)` y rellena structs C planos
  con topes fijos (p. ej. `MSG_CDR_MAX_TRANSFORMS 32`,
  `MSG_CDR_MAX_JOINTS 32`, `MSG_CDR_MAX_MARKERS 16`, mapa ≤ 256×256).
  Sin malloc. Devuelve error si el mensaje excede topes (y CUENTA los
  descartes para el netlog).
- **Fixtures reales, no inventadas:** genera los binarios de test desde
  ROS2 real y commitéalos en `modules/msg-cdr/tests/fixtures/`:
  ```bash
  docker exec robotnik_dev bash -lc "source /opt/ros/jazzy/setup.bash && python3 - <<'PY'
  from rclpy.serialization import serialize_message
  from tf2_msgs.msg import TFMessage
  from geometry_msgs.msg import TransformStamped
  m = TFMessage()
  t = TransformStamped()
  t.header.frame_id = 'odom'; t.child_frame_id = 'base_link'
  t.transform.translation.x = 1.5; t.transform.rotation.w = 1.0
  m.transforms = [t]
  open('/tmp/tf_fixture.bin','wb').write(serialize_message(m))
  PY"
  docker cp robotnik_dev:/tmp/tf_fixture.bin modules/msg-cdr/tests/fixtures/
  ```
  OJO: `serialize_message` antepone 4 bytes de encapsulación
  (`00 01 00 00` = CDR_LE) — el payload XRCE que ve `on_topic` empieza
  DESPUÉS de esos 4 bytes. El test debe deserializar `fixture+4`.
  Genera fixtures para los 4 tipos con valores variados (varios
  transforms, strings largos, mapa pequeño 4×4).
- **Paridad:** ambas impl deserializan las fixtures a los mismos structs.
- **Verificación:** `tools/run-parity-tests.sh msg-cdr` verde.
- **Commit:** `feat(msg-cdr): deserializadores CDR duales con fixtures ROS2 reales`.

### D3 — `modules/tf-tree/`: buffer y resolución de transformadas

- **Leer antes:** los structs de D2 y `viz-math` de D1.
- **API:** `tf_tree_init/update(transform)/lookup(frame, base, mat4_out)`
  — tabla estática de N frames (32), último valor por frame (sin
  historial temporal — documenta la simplificación vs tf2 real),
  composición de cadenas padre→hijo con viz-math.
- **Paridad:** casos con cadenas de 3 niveles, frames desconocidos,
  ciclos (debe rechazarlos).
- **Verificación:** `tools/run-parity-tests.sh tf-tree` verde y TODOS los
  módulos siguen verdes (`tools/run-parity-tests.sh`).
- **Commit:** `feat(tf-tree): arbol TF dual (ultimo valor por frame)`.

### D4 — Suscripciones nuevas en la app

- **Leer antes:** `vita-app/src/main.c` (bloque de entidades DDS: cómo se
  crean topics/datareaders y el `req[]`/`status[]`; y `on_topic` — llega
  `uxrObjectId object_id` para distinguir qué datareader disparó).
- **Modificar:** `main.c` — datareaders para `rt/tf`
  (`tf2_msgs::msg::dds_::TFMessage_`), `rt/joint_states`
  (`sensor_msgs::msg::dds_::JointState_`) y (tras E3) `rt/map` +
  markers. En `on_topic`, despachar por `object_id.id` al deserializador
  de msg-cdr y volcar al estado de viz. Sube `STREAM_BUFFER_SIZE` de
  entrada si hace falta (ver §9.4) — mide primero.
- **Verificación en hardware:** publicar TF sintético desde la laptop y
  ver el netlog confirmando recepción:
  ```bash
  # dentro del contenedor ROS2 de la laptop:
  ros2 run tf2_ros static_transform_publisher --x 1 --y 0 --z 0 \
      --frame-id odom --child-frame-id base_link
  ```
- **Commit:** `feat(objetivo4): suscripciones /tf y /joint_states via msg-cdr`.

### Cierre de etapa D

Bitácora + fases.ts + push. Paridad completa verde en laptop Y en PC.

---

## 8. ETAPA E — mini-rviz MVP: el robot moviéndose en tiempo real

### E1 — Formato VBM y exportador web (URDF → binario para la Vita)

La Vita NO parsea URDF/XML ni mallas DAE: el PC/web convierte el modelo a
un binario compacto que la app carga directo.

- **Leer antes:** `web/src/lib/visor3d.ts` ENTERO (ya parsea URDF:
  links, joints, primitivas, mallas, materiales — reutilízalo, no
  reimplementes) y `web/src/pages/visor3d.astro` (cómo se usa).
- **Formato VBM v1** (defínelo en `docs/11` y NO lo cambies sin subir la
  versión): little-endian; header `magic "VBM1"`, nº links, nº joints;
  por link: nombre (64 bytes fijos), primitivas (tipo caja/cilindro/
  esfera/malla, dimensiones, color RGBA, offset xyz+quat); mallas
  trianguladas ya "cocidas" (vértices float32 + normales, tope p. ej.
  20k vértices/modelo); por joint: nombre, tipo, padre, hijo, origen,
  eje, límites.
- **Crear:** `web/src/lib/vbm.ts` (exportador TS) +
  `web/src/pages/taller/modelo.astro` (subir URDF+mallas → preview con
  visor3d → botón "Exportar VBM" → descarga y botón "Enviar a la Vita"
  vía el deploy FTP existente, destino `ux0:/data/vitaros/model.vbm`) +
  `vita-app/src/viz/vbm.{h,c}` (loader C, SIN dependencias Vita:
  compilable en host) + `vita-app/scripts/check-vbm.sh` (test host:
  exporta el `vitabot.urdf` de la web con node, carga con el loader C y
  compara link/joint counts y algunas coordenadas).
- **Verificación:** `check-vbm.sh` verde (round-trip web→binario→C).
- **Commit:** `feat(objetivo4): formato VBM + exportador web + loader C con test host`.

### E2 — Render del robot estático

- **Modificar:** `vita-app/src/viz/viz.c` — carga `model.vbm` desde
  `ux0:/data/vitaros/model.vbm` (si no existe: mensaje en pantalla con la
  ruta esperada, NO crash), dibuja primitivas y mallas con vitaGL usando
  las matrices de viz-math.
- **Verificación en hardware:** el VitaBot (el URDF de prueba de la web)
  se ve en 3D en la consola, cámara orbital funcionando.
- **Commit:** `feat(objetivo4): render del modelo VBM en la Vita`.

### E3 — Animación en tiempo real (el corazón del Objetivo 4)

- **Cadena:** `/joint_states` mueve los joints del VBM (revolute:
  rotación sobre el eje; prismatic: traslación) y `/tf` posiciona
  `base_link` en el mundo (tf-tree). Recalcular las matrices por frame
  con viz-math (forward kinematics simple: matriz padre × origen joint ×
  rotación(q) × ... — igual que hace `visor3d.ts` en la web, léelo).
- **Prueba en vivo (desde el contenedor ROS2 de la laptop):**
  ```bash
  ros2 pkg list | grep -E "robot_state_publisher|joint_state_publisher"  # verificar que existen
  ros2 run robot_state_publisher robot_state_publisher --ros-args \
      -p robot_description:="$(cat vitabot.urdf)"
  ros2 run joint_state_publisher joint_state_publisher  # o publicar JointState a mano a 10 Hz
  ```
  El robot en la pantalla de la Vita debe moverse igual que en
  `/visor3d` de la web con los mismos datos. **Ese es el criterio
  estrella del Objetivo 4.**
- **Commit:** `feat(objetivo4): robot animado en tiempo real por /tf y /joint_states`.

### E4 — Marcadores y mapa

- **Markers** (`visualization_msgs/Marker`, tipos CUBE/SPHERE/CYLINDER/
  ARROW/LINE_STRIP): render directo con las primitivas ya existentes.
- **OccupancyGrid:** mapa ≤ 256×256 → textura (1 byte/celda → gris),
  quad en el plano Z=0. Mapas más grandes: descartar con aviso en el
  netlog (documenta el tope — el ancho de banda XRCE manda, §9.4).
- **Prueba:** `ros2 topic pub /marker visualization_msgs/msg/Marker ...`
  y un mapa pequeño publicado a mano o con `nav2_map_server` si está
  disponible (verifica con `ros2 pkg list` antes de asumir).
- **Commit:** `feat(objetivo4): markers y occupancy grid en el mini-rviz`.

### E5 — Panel de la escena editable desde la web (cierra la petición de "editar la visualización")

- Config declarativa `vita-app/ui/viz.json` (qué topics mostrar, colores,
  grid on/off, frame base) → mismo patrón que layout.json: codegen a
  header (`gen-viz-header.mjs`, copia el patrón de `gen-ui-header.mjs`) +
  editor mínimo en `/taller/ui` (una pestaña más) o página propia.
- **Commit:** `feat(objetivo4): escena del mini-rviz declarativa y editable desde la web`.

---

## 9. ETAPA F — Verificación final y cierre

1. **Suite completa en verde**, en laptop y PC:
   ```bash
   tools/run-parity-tests.sh          # ahora con viz-math, msg-cdr, tf-tree
   bash vita-app/scripts/check-teleop.sh
   bash vita-app/scripts/check-ui-layout.sh
   bash vita-app/scripts/check-vbm.sh
   cd web && pnpm build
   ```
2. **Sesión en vivo de cierre** (grabar los hallazgos en la bitácora):
   agente en la laptop + app en modo VIZ + `robot_state_publisher` +
   `joint_state_publisher` + un Marker + (si hay) un mapa. El robot se
   mueve en la pantalla de la Vita en tiempo real. El modo TELEOP sigue
   controlando `/cmd_vel` (regresión Objetivo 2).
3. **Docs:** docs/04 cerrado, ADR 0006/0007 hechos, docs/11 actualizado a
   "implementado", bitácora con bloque de cierre, `fases.ts` con los 6
   hitos de `fase-3-4` en `hecho`, README de vita-app y de cada módulo
   nuevo al día. La web publica todo esto sola (colecciones glob) — los
   docs nuevos están bajo `docs/` y `docs/adr/`, no hace falta colección
   nueva; los README de módulos nuevos aparecen en cuanto exista el
   archivo (verifica en `/docs` de la web tras `pnpm build`).
4. **Commit final:** `feat(objetivo34): mini-rviz MVP — objetivos 3 y 4 cerrados`.

---

## 10. Datos duros y cómo obtener la verdad (anti-alucinación)

### 10.1 Paquetes y toolchain

- vdpm instala DESCARGANDO de
  `https://github.com/vitasdk/packages/releases/download/master/<pkg>.tar.xz`.
  Nombres verificados 2026-07-07 (HTTP 200): `vitaGL`, `libpng`, `zlib`,
  `freetype`, `libjpeg-turbo`, `libvita2d`. NO existen: `vita2d` (404).
  **Siempre** verificar tras instalar que los archivos están en
  `$VITASDK/arm-vita-eabi/{lib,include}` — vdpm reporta éxito aunque el
  tar falle.
- Entorno: `source tools/env-devpc.sh` SIEMPRE antes de compilar.
  Builds de la app: los dos comandos exactos están al inicio de
  `vita-app/CMakeLists.txt` (usa `build-c/` y `build-rust/`).
- Deploy: `curl -T <archivo> ftp://<IP-vita>:1337/ux0:/` con VitaShell en
  modo FTP (SELECT). Si conecta pero no responde el saludo FTP: cerrar y
  reabrir el modo FTP en la consola (hilo colgado — visto 2026-07-07).

### 10.2 La app y sus límites conocidos

- `sceClibPrintf` NO soporta `%f`: preformatear con `snprintf` (newlib)
  — ver el patrón en `main.c` (búsqueda: `linea_log`).
- El bucle principal da una vuelta cada ~50 ms (`uxr_run_session_time`);
  el render 3D vive en ese mismo bucle: presupuesto ~20 fps. Si el modo
  VIZ necesita más, reducir el timeout de run_session en modo VIZ y
  medir (netlog) — no asumir.
- Un binario = un staticlib Rust (crate paraguas
  `vita-app/rust-modules/`): los módulos nuevos duales se añaden AHÍ como
  dependencia para la variante Rust (lee su Cargo.toml y src/lib.rs — el
  patrón re-exporta cada módulo).

### 10.3 CDR/XRCE (para msg-cdr)

- XCDR1 little-endian. Alineación natural de cada tipo RELATIVA al inicio
  del payload (el `ucdrBuffer` de `on_topic` ya viene con el origen
  bien puesto — `main.c` deserializa strings así hoy).
- `string`: uint32 longitud (incluye NUL) + bytes + NUL.
- `sequence<T>`: uint32 número de elementos + elementos.
- `Header`: stamp (int32 sec + uint32 nanosec) + frame_id (string).
- Tipos DDS = `<paquete>::msg::dds_::<Tipo>_` y topic ROS2 `/x` = DDS
  `rt/x` (patrón ya usado en main.c con Twist/String).
- Las definiciones de mensajes SIEMPRE de `ros2 interface show` o del MCP
  (§7 D2) — nunca de memoria.

### 10.4 Presupuesto de red/memoria (medir, no suponer)

- Streams XRCE actuales: `STREAM_BUFFER_SIZE 4096` × `STREAM_HISTORY 4`
  (main.c). Un TFMessage de 10 transforms ≈ 10×(~90 B) < 1 KB: cabe.
  Un OccupancyGrid 256×256 = 65 KB + header: NO cabe en un buffer de
  4 KB — XRCE fragmenta en streams confiables si el buffer del stream lo
  permite; para el mapa, subir el buffer de entrada (p. ej. 16 KB × 4) y
  medir con el netlog cuánto tarda. Si no es viable, tope 128×128 y
  documentar.
- RAM: la app hoy usa vita2d + XRCE sin apuros; el modelo VBM con tope
  20k vértices ≈ 20k×24 B ≈ 0.5 MB: sin problema. NO cargues mallas sin
  tope.

### 10.5 Dónde están las cosas (rutas verificadas)

- Parser URDF web: `web/src/lib/visor3d.ts`; página `web/src/pages/visor3d.astro`.
- Runner de paridad: `tools/run-parity-tests.sh` (descubre `modules/*/`).
- Skills del PC: `skills/vita-dual-module/`, `skills/vita-build-package/`,
  `skills/vita-deploy-logs/`.
- Editor UI web: `web/src/pages/taller/ui.astro` + `web/src/lib/ui-layout.ts`;
  endpoints en `web/src/pages/api/taller/` (localizar con grep).
- Contenedores ROS2 Jazzy: `robotnik_dev` (en el PC y en la laptop);
  en la laptop además `rmf_unified`. El agente micro-ROS SIEMPRE en la
  laptop (`docker run -it --rm --net=host --ipc=host
  microros/micro-ros-agent:jazzy udp4 --port 8888 -v6`).

### 10.6 Qué NO hacer

- No tocar `modules/{mem-pool,net-udp,microros-transport}`,
  `vita-app/src/teleop.*`, `netlog.*`, `uxr_glue.*` (código cerrado y
  validado en hardware; si crees que necesitas cambiarlo, documenta por
  qué en la bitácora y pregunta al usuario).
- No editar `vita-app/src/ui_layout.h` a mano (es generado).
- No usar malloc en módulos duales (regla del repo).
- No cambiar `XRCE_TAG` (v2.4.3 empareja con el agente — el desajuste de
  versión fue EL muro de la Fase 1).
- No asumir que un paquete ROS2 existe en el contenedor: `ros2 pkg list`
  primero.
- No commitear `auditoria/`, `toolchains/`, `third_party/` (gitignored).
