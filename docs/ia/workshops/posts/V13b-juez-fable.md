# V13b · Decisión del juez: ¿se crea ya el módulo dual `modules/viz-decode/`? (2026-11-14)

> Juez: Fable 5.2 (regla del usuario 2026-11-13: las decisiones no se le preguntan). Resuelve la parte `viz-decode` de
> la tarea V13 (`docs/36-visualizacion-topics-godot.md` §10; `docs/ia/workshops/posts/W13-juez-fable.md`, fila V13)
> contra la regla de corte de `docs/adr/0011-presupuesto-render-vita.md` §5 y `docs/31-render-visualizacion-vita.md`
> §4.1 y §4.3. La otra parte de V13 (V13a: `RosQoS`, `latest_only`, tipo resuelto, contadores, `RosTfListener`) ya
> está hecha (commits `3503406`…`6761836`).
> Marcas: [V] verificado en host o en hardware · [I] inferencia · «validar en hardware» donde solo la Vita lo dice.

## Decisión: opción A — no se crea el módulo ahora

**`modules/viz-decode/` no se crea.** Ninguna ruta de decodificación que la Vita ejecuta hoy llega a 2 ms por
mensaje con el factor Vita/PC medido en hardware, ni siquiera con el factor pesimista de diseño. La regla de ADR 0011
§5 («C en el módulo dual solo si GDScript cuesta > 2 ms por mensaje o > 1 ms por fotograma de media») **no se
cumple**, así que el código nativo no está justificado. Queda un gate de hardware con las líneas de log que ya
existen (§4) y la cabecera reducida que habría que implementar si sale rojo (§5).

## 1. Medidas [V]

Banco nuevo `docs/ia/medidas/v13b-banco-decodificacion.gd`: copias de los bucles reales, datos sintéticos, 2 000
repeticiones, mediana y máximo en µs. Ryzen 7 5800X, Godot 4.8-dev7 de host, dos pasadas:

| Ruta | Código real | Mediana (µs) | Máximo (µs) |
|---|---|---|---|
| Tesela de mapa, bucle GDScript (256 `append_array`) | `godot/plantillas/vita_relay.gd` `on_mapa_tesela` | 16 | 28–98 |
| Tesela de mapa, parte del motor (`set_data` + `blit_rect`) | ídem | < 1 | 2 |
| Tesela de costmap, bucle (512 `append_array`) | `godot/plantillas/visor/costmap_textura.gd` `de_tesela` | 31 | 53–86 |
| Trozo de nube, 76 puntos | `godot/plantillas/visor/displays/2d/nube.gd` `_procesar_compacto` | 34–36 | 89–90 |
| `scan_compacto`, 180 rayos, decodificar + pintar | `vita_relay.gd` `scan_puntos` + `displays/2d/scan.gd` `_pintar` | 33 | 70–93 |
| LaserScan directo, 360 rayos, decodificar + pintar | `displays/2d/scan.gd` `_procesar` + `_pintar` | 70–72 | 130–146 |
| PointCloud2 directo, 468 puntos | `displays/2d/nube.gd` `_procesar` | 259–260 | 438–584 |
| OccupancyGrid directo, 86 × 86 celdas | `godot/plantillas/visor/mapa_textura.gd` `de_grid` | 371–373 | 493–633 |

Las cifras de las revisiones («tesela ≤ 102 µs», «tesela de costmap 158 µs», «0,05–0,08 ms por trozo») son **máximos**
de una pasada de pruebas que incluye la primera llamada (construir la LUT, crear la imagen). La mediana en régimen es
3–6 veces menor.

**Factor Vita/PC, medido** [V]: el mismo GDScript, misma sección de `[perfil-gd]`, en el PC
(`docs/34-perfil-vita-ligero.md` §6) y en la Vita (`docs/ia/medidas/g1-sensores-ligero-vita-2026-11-13.log:119`):
`camara` 20 → 410 µs (×20), `hud` 3 → 74 (×25), `mundo` 7 → 151 (×22), `robot` 87 → 1 584 (×18). Solo cuento las
secciones que corren cada fotograma; las de sensores van a ritmo fijo y dependen de los FPS de cada máquina.
Factor de trabajo: **×25**; pesimista: **×40** (el tope de `docs/36a-catalogo-displays.md` §4.5).

## 2. Rutas que la Vita ejecuta (camino compacto, relay VC/1 rev. 2)

| Ruta | Host (µs) | Vita ×25 (ms) [I] | Vita ×40 (ms) [I] | Hz | ms por fotograma a 30 FPS, ×25 / ×40 | Factor para llegar a 2 ms |
|---|---|---|---|---|---|---|
| Tesela de mapa | 16 | 0,40 | 0,64 | ≤ 20 | 0,27 / 0,43 | ×125 |
| Tesela de costmap | 31 | 0,78 | 1,24 | 10 | 0,26 / 0,41 | ×65 |
| Trozo de nube | 36 | 0,90 | 1,44 | 15 | 0,45 / 0,72 | ×56 |
| Scan compacto | 33 | 0,83 | 1,32 | 10 | 0,28 / 0,44 | ×61 |
| **Suma** | | | | | **1,26 / 2,0** (tope: 4) | |

- Ninguna pasa de 2 ms por mensaje ni de 1 ms por fotograma, y la suma queda en la mitad del tope de 4 ms. Haría
  falta una Vita 56 veces más lenta que el PC en GDScript; lo medido es 18–25.
- **Imagen:** `Image.load_jpg_from_buffer` es C++ del motor (0,1 ms en el host). `viz-decode` no la tocaría. Gate
  propio: E-W8-5.
- **Composición del costmap** (242 µs en el host, hasta ≈ 6 ms [I] en la Vita, ≤ 4 Hz): es `blit_rect`,
  `blend_rect`, `resize` y `ImageTexture.update`, todo C++ del motor. `viz-decode` tampoco la tocaría; si
  `composicion_us` sale rojo en G-W13-M5 el remedio es componer menos región o subir menos textura, no un módulo.
- Lo que C ahorraría en el mejor caso: ≈ 1,2 ms por fotograma a 30 FPS de un presupuesto de 8 ms de GDScript y red
  (ADR 0011 §6). A cambio: una tercera implementación de cada bucle (C, Rust y el GDScript que hay que conservar
  para rclgd en el PC), con paridad de coma flotante que mantener.

## 3. Rutas directas (sin relay)

| Ruta | Mayor mensaje que cabe en ≈ 7,5 KiB fiables | Host (µs) | Vita ×25 (ms) [I] | Por qué no decide |
|---|---|---|---|---|
| LaserScan | 360 rayos (≈ 2,9 KB con `intensities`) | 71 | 1,8 | bajo el umbral; solo fiable y ≤ 5 Hz (doc 31 §4.1 regla 1); el relay da 10 Hz en 384 B |
| PointCloud2 | 468 puntos de 16 B | 260 | 6,5 | **sobre el umbral**, pero una nube real (miles de puntos) no cabe; sin relay no hay vóxel ni cambio al marco fijo, y el cupo es 228 puntos |
| OccupancyGrid | 86 × 86 celdas | 372 | 9,3 | **sobre el umbral**, una vez por mapa (*latched*); un mapa real (384² = 147 KB) no cabe |
| Imagen cruda | no cabe (160 × 120 rgb8 = 57,6 KB) | — | — | solo JPEG por el relay |

Las dos que pasarían de 2 ms están cerradas por la **regla de bytes**, no por CPU: C las haría rápidas pero seguirían
sin caber por XRCE. Siguen siendo rutas «PC» (`mapa_textura.gd` y `nube.gd` ya lo dicen en su cabecera).

## 4. Gate de hardware G-V13b (no pide sesión propia)

Se lee en la sesión de `docs/ia/workshops/posts/V3-revision.md` §5, con la `build/visor-ros.vpk` actual (no se
reexporta: esta decisión no toca código de la aplicación):

| Fase | Línea de `godot_stderr.log` | Verde (no hace falta C) | Rojo |
|---|---|---|---|
| F2 | `[visor-mapa] media_us= max_us=` | `media_us` ≤ 1 000 y `max_us` ≤ 2 000 | → `vizd_tile_rgba` |
| F5 | `[visor-costmap] max_us=` | `max_us` ≤ 2 000 | → `vizd_tile_rgba` |
| F8 | `[visor-nube] us_max=` | `us_max` ≤ 2 000 | → `vizd_cloud_tris` |
| F2 | `[perfil-gd] visor/Scan=` (µs por fotograma) | ≤ 1 000 | → `vizd_scan_tris` |

Los gates V3 y G-W13-M5 piden `max_us` ≤ 1 500: son más estrictos y siguen valiendo para su tarea; entre 1 500 y
2 000 µs el gate de la tarea queda en ámbar pero **no** dispara el módulo. `composicion_us` y `[visor-imagen]` no
cuentan aquí (motor). Si algo sale rojo se implementa **solo** la función de esa fila, con el patrón de
`skills/vita-dual-module/`, y se recompila la plantilla (`tools/build-godot-template.sh` + `verify_runtime.py`).
Validar en hardware.

## 5. Cabecera propuesta (sustituye a la de doc 31 §4.3; sin implementar)

De las seis funciones de doc 31 §4.3 sobran tres: `vizd_project` y `vizd_ribbon` (el visor proyecta con
`Camera3D.unproject_position` y las cintas son de ≤ 112 segmentos a 2 Hz) y `vizd_points_tris` (se funde en las dos
de puntos). Las otras tres se ajustan a los formatos VC/1 rev. 2 reales
(`docker/scripts/vita_relay_formatos.py`):

```c
/* modules/viz-decode/include/viz_decode.h — PROPUESTA (V13b). Funciones puras: sin malloc, sin estado,
 * búferes del llamador. Devuelven lo escrito o -1 si los argumentos no valen. */

/* Celdas empaquetadas (bits = 2 o 4 por celda, LSB primero) de w × h → RGBA8, con las filas al revés
 * (fila 0 del OccupancyGrid abajo, imagen norte arriba). lut_rgba: (1 << bits) colores de 4 B.
 * Mapa: bits 2, 32 × 32, 256 B → 4 096 B. Costmap: bits 4, 32 × 32, 512 B → 4 096 B. */
int vizd_tile_rgba(const uint8_t *celdas, size_t celdas_len, uint32_t w, uint32_t h, uint32_t bits,
                   const uint8_t *lut_rgba, uint8_t *rgba, size_t rgba_cap);

/* n puntos xyz en cm (int16 que ros2_vita entrega como int32, paso 3) → 3n vértices 2D en px (un triángulo
 * de lado `lado_px` por punto, y hacia abajo) y n bandas de altura 0–15. */
int vizd_cloud_tris(const int32_t *xyz_cm, size_t n, float px_por_cm, float lado_px,
                    float z_min_m, float z_max_m, float *xy, size_t xy_cap, uint8_t *banda, size_t banda_cap);

/* n distancias en cm (0 = sin dato) con la tabla de direcciones del llamador (2n floats: cos, sin) →
 * triángulos en px. Sin sin/cos dentro: la tabla la calcula quien llama, así C y Rust dan los mismos bits. */
int vizd_scan_tris(const int32_t *cm, size_t n, const float *dirs, float px_por_m, float lado_px,
                   float *xy, size_t xy_cap);
```

Exposición prevista: clase `RosVizDecode` de `godot/ros2_vita` con métodos estáticos que devuelven
`PackedByteArray` / `PackedVector2Array`; los displays la usan si `ClassDB.class_exists("RosVizDecode")` y, si no
(rclgd en el PC), siguen con el GDScript actual. Una prueba de host compara las dos rutas byte a byte.

## 6. Por qué no B ni C

- **B (crear el módulo ya con 1–2 funciones):** el argumento a favor es ahorrar una ronda de hardware si el gate
  sale rojo. Con margen ×2,2 sobre el factor medido (×56 frente a ×25) la probabilidad de rojo es baja, y el coste es
  seguro: tres implementaciones por bucle, paridad de `float` entre C, Rust y GDScript, y más superficie en la
  plantilla. ADR 0011 §5 pone C como último escalón precisamente para no pagar eso sin una medida.
- **C (mover más trabajo al relay, p. ej. mandar los triángulos ya hechos):** triplica los bytes por punto y rompe
  el presupuesto de red de ADR 0013 §5; el relay ya hace lo caro (vóxel, TF, reducción, JPEG).
- **Reversión:** si G-V13b sale rojo, esta decisión pasa a B para la fila roja, sin cambiar formatos ni displays.

## 7. Archivos

- Nuevos: este documento; `docs/ia/medidas/v13b-banco-decodificacion.gd` (banco reproducible).
- Enmienda fechada en `docs/adr/0011-presupuesto-render-vita.md`; nota en `docs/31-render-visualizacion-vita.md`
  §4.3.
- Sin cambios en `godot/`, `modules/` ni `build/`: paridad, pruebas de host y `.vpk` quedan como las dejó V13a.
