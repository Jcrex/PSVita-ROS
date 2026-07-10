# 11 — Diseño del mini-rviz (Plan B de los Objetivos 3 y 4)

**Fecha:** 2026-07-10 · **Estado:** diseño aprobado — implementación en curso
(etapas B–E de `docs/10-plan-objetivos-3-4.md`)

Este es el diseño fino del visualizador propio que activa el ADR 0006:
rviz2 nativo no es portable (evidencia en `docs/04`), así que la Vita
renderiza con **vitaGL** un subconjunto de lo que rviz2 mostraría,
alimentado por la sesión micro-ROS/XRCE ya validada en hardware.

---

## 1. Alcance del MVP (qué entra y qué no)

**Entra (criterio estrella: el robot moviéndose en tiempo real):**

| Elemento | Fuente de datos | Render |
|---|---|---|
| Grid del suelo (10×10 m, paso 1 m) | — | líneas GL en Z=0 |
| Ejes del mundo y ejes por frame TF | `/tf` (`tf2_msgs/TFMessage`) | 3 líneas RGB por frame |
| Modelo del robot (VBM, ver §4) | URDF convertido en la web | primitivas + mallas |
| Animación del robot | `/joint_states` + `/tf` | FK por frame (viz-math) |
| Marcadores CUBE/SPHERE/CYLINDER/ARROW/LINE_STRIP | `visualization_msgs/Marker` | primitivas |
| Mapa de ocupación ≤ 256×256 | `nav_msgs/OccupancyGrid` | textura sobre quad en Z=0 |
| Cámara orbital (yaw/pitch/dist + target) | stick derecho + L/R | mat4 look_at propia |

**No entra (consecuencias aceptadas del ADR 0006):** plugins/displays
arbitrarios, PointCloud2 (extensión futura, tope de puntos por ancho de
banda), historial temporal de TF (solo último valor por frame, ver
`modules/tf-tree/`), mapas grandes, texto 3D, mallas sin "cocer".

## 2. Modos de la app (TELEOP ↔ VIZ)

La app conserva TODO el Objetivo 2. Se añade un modo:

- **TELEOP (actual):** UI declarativa vita2d + publicación `/cmd_vel`.
- **VIZ (nuevo):** escena 3D vitaGL. El teleop SIGUE publicando (el
  operador puede mover el robot mientras lo ve).
- **Conmutación: SELECT.** Decidido en ADR 0007 (2026-07-10): **todo
  vitaGL** — vitaGL no puede soltar el GPU una vez inicializado
  (`eglTerminate` es no-op; sin `sceGxmTerminate` en la lib), así que
  vita2d sale del proyecto y `ui.c` se reescribe como backend vitaGL
  (quads + fuente bitmap propia). El layout.json/codegen NO cambia.
  Los modos son estados del bucle sobre el mismo contexto GL (2D
  ortográfico vs 3D perspectiva).

Bucle: el render 3D vive en el bucle actual (`uxr_run_session_time` de
50 ms ⇒ ~20 fps). Si el modo VIZ necesita más fluidez, se baja el
timeout en ese modo y se mide con el netlog (no asumir).

## 3. Flujo de datos completo

```
              PC/web (/taller/modelo)                    Vita (app)
URDF+mallas ──► parser visor3d.ts ──► exportador vbm.ts ──► model.vbm ──FTP──► ux0:/data/vitaros/model.vbm
                                                                                    │ vbm.c (loader host-testeable)
grafo ROS2 ──agente XRCE (laptop)──► on_topic(main.c) ──► modules/msg-cdr ──► estado viz
  /tf ────────────────────────────────────────────────────► modules/tf-tree ──► pose de base_link
  /joint_states ──────────────────────────────────────────► FK (viz-math) ────► poses de links
  /marker, /map ──────────────────────────────────────────► listas acotadas ──► draw
                                                                                    ▼
                                                            src/viz/ (vitaGL): grid+ejes+robot+markers+mapa
```

Reparto de responsabilidades (regla del repo: lo verificable en host se
verifica en host):

- `modules/viz-math` (dual C+Rust): vec3/quat/mat4, column-major.
- `modules/msg-cdr` (dual): deserializar TFMessage/JointState/Marker/
  OccupancyGrid desde `(buf,len)` a structs planos con topes, sin malloc.
- `modules/tf-tree` (dual): tabla de ≤32 frames, último valor, lookup
  componiendo cadenas padre→hijo.
- `vita-app/src/viz/vbm.c`: loader del modelo, C puro sin headers Vita
  (test host `check-vbm.sh`).
- `vita-app/src/viz/{viz,camera,draw_prims}.c`: solo el dibujo es
  código Vita-only ("validar en hardware").

## 4. Formato VBM v1 (Vita Binary Model)

La Vita no parsea URDF/XML ni mallas DAE/STL: la web "cuece" el modelo.
**Little-endian, alineación natural, versión en el magic — cambiar algo
= subir a VBM2.**

```
Header:  char[4]  magic = "VBM1"
         uint32   n_links, n_joints, n_mesh_vertices_total
Por link (n_links):
         char[64] nombre (NUL-padded)
         uint32   n_prims
         Por prim: uint32 tipo (0=caja 1=cilindro 2=esfera 3=malla)
                   float[3] dim        (caja: xyz; cil: r,len,-; esf: r,-,-;
                                        malla: n_verts,-,-)
                   float[4] color RGBA
                   float[3] offset xyz + float[4] quat xyzw (origen visual)
                   [si malla: n_verts × 6 floats (pos xyz + normal xyz),
                    triángulos ya expandidos, sin índices]
Por joint (n_joints):
         char[64] nombre
         uint32   tipo (0=fixed 1=revolute 2=continuous 3=prismatic)
         uint32   link_padre, link_hijo (índices)
         float[3] origen xyz + float[4] quat xyzw
         float[3] eje
         float[2] límites lo/hi (0,0 si no aplica)
```

Topes v1: ≤ 32 links, ≤ 32 joints, ≤ 20k vértices totales (≈ 0.5 MB en
RAM), ≤ 16 prims/link. El exportador web rechaza modelos que excedan.

## 5. Presupuesto de red y memoria (medir, no suponer)

Datos base de `docs/10` §10.4 y `main.c` (`STREAM_BUFFER_SIZE 4096 ×
STREAM_HISTORY 4`):

- `/tf` con 10 transforms ≈ <1 KB por mensaje: cabe hoy.
- `/joint_states` de 12 joints ≈ ~600 B: cabe hoy.
- Markers: ≤16 retenidos; un Marker ≈ 200 B: cabe.
- `OccupancyGrid` 256×256 = 65 KB: NO cabe en el buffer actual — exige
  subir el stream de entrada (p. ej. 16 KB×4) y medir con netlog el
  tiempo de fragmentación XRCE; si no es viable, tope 128×128 y
  documentarlo aquí.
- RAM total nueva estimada: modelo VBM 0.5 MB + mapa 64 KB + estado viz
  <100 KB — holgado en 512 MB.

## 6. Configuración de la escena (E5)

Igual que la UI: declarativa. `vita-app/ui/viz.json` (frame base, grid
on/off, colores, qué topics mostrar) → `gen-viz-header.mjs` → header →
la app lo interpreta; editor en la web. Sin parsear JSON en la Vita.

## 7. Criterio de cierre del Objetivo 4

Con `robot_state_publisher` + `joint_state_publisher` publicando desde
el contenedor de la laptop, **el robot en la pantalla de la Vita se
mueve igual que en `/visor3d` de la web con los mismos datos**, mientras
el modo TELEOP sigue controlando `/cmd_vel` (regresión Objetivo 2).
