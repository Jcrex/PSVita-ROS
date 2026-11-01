# 04b — DB-TSDF en la PS Vita: viabilidad e implementación (informe largo, para la IA)

**Fecha:** 2026-11-01 · **Autor:** agente de viabilidad (flota DB-TSDF) · **Estado:** estudio, nada medido.
Versión corta para el usuario: `docs/informes/04b-dbtsdf-viabilidad-vita.md`.

Marcas: **[V]** leído en fichero/URL citado · **[A]** conocimiento general de arquitectura ·
**[H]** hipótesis/estimación no medida (todas las cifras de rendimiento lo son) · **[?]** sin confirmar.

Código consultado: `https://github.com/robotics-upo/DB-TSDF.git`, commit
`663c5a85c9d7e5b545f88a1b290fe9b52986eed2` (2026-06-08), clon de solo lectura en el scratchpad
(no compilado ni ejecutado). Rutas de DB-TSDF se citan como `DB-TSDF/<fichero>:<línea>`.
Paper: arXiv 2509.20081 (ICRA 2026), <https://arxiv.org/html/2509.20081>.

---

## 0. Resumen ejecutivo

1. **El algoritmo es pequeño y portable.** El núcleo son dos cabeceras C++ (`tsdf3d_16.hpp` 488 líneas,
   `grid_16.hpp` 566) con licencia **MIT** (`DB-TSDF/LICENSE:1`). Lo que ata a Linux/PC es periférico:
   PCL, VTK (Marching Cubes), Eigen, OpenMP y rclcpp (`DB-TSDF/CMakeLists.txt:15-31`). La integración
   en sí (`loadCloud`, `DB-TSDF/include/db_tsdf/tsdf3d_16.hpp:200-250`) solo usa enteros de 16 bits,
   AND de máscaras y un `atan2/asin` por punto: **encaja muy bien en una Cortex-A9** [A].
2. **No hay raycasting**: cada punto actualiza solo un cubo local de K³ vóxeles con un kernel
   direccional precalculado (`tsdf3d_16.hpp:228-246`); el coste por scan es ≈ `N_puntos · K³ · C_op`
   (paper, Ec. 7) y no depende de la resolución. Esto es lo que hace plausible la Vita.
3. **Lo que NO cabe es la configuración del paper/repo**: LiDAR de 64 canales (~65 k puntos/scan,
   Newer College) a 10 Hz y un volumen de 200×200×60 m con 75 000 celdas de 32 KB (≈ 2,4 GB)
   (`DB-TSDF/config/college.yaml:76-84`, `grid_16.hpp:142-143`). Escalado a la Vita: decenas de segundos
   por scan [H].
4. **Red, el cuello real hoy**: `ros2_vita` recibe mensajes de **≤ 16 KB** (`MAX_RX`,
   `godot/ros2_vita/xrce_transport.cpp:137`), MTU 512 y sin fragmentación en *best effort*
   (`xrce_transport.cpp:132-140`, `:411-417`). Una nube cruda de un VLP-16 son ~480 KB/scan.
5. **Recomendación: arquitectura C (híbrida) en dos pasos**, empezando por **B** (la Vita solo visualiza)
   como andamio: (B) primero porque reutiliza el nodo original sin tocar la Vita más que en la vista;
   después (C) una variante **local** del integrador en la Vita (volumen de ~20×20×4 m a 0,10 m, K=5,
   nube **voxelizada en el PC** a 2–5 k puntos, troceada en mensajes *best effort* ≤ 490 B). La A
   (mapeo completo 3D a 10 Hz en la Vita) se descarta.
6. **Lo primero que hay que medir**: microbenchmark de `integrar_scan` en la Vita (C puro, 1–3 hilos,
   333/444 MHz) con escenas sintéticas fijas — puerta **T3** del plan (§6).

---

## 1. Qué hace DB-TSDF exactamente (lo justo para dimensionar)

### 1.1 Estructura de datos [V]
- `VoxelData` = 4 B: `uint16_t d` (máscara de distancia; distancia = `popcount(d)`), `uint8_t s`
  (bit 0: 0 ocupado / 1 libre), `uint8_t hits` (`grid_16.hpp:27-33`).
  *Discrepancia*: el paper habla de 8 B/vóxel y máscara de 32 bits (Sec. III-A); el código usa 16 bits
  y 4 B. **Este informe usa el código.** (La auditoría de código, informe hermano, debería anotarlo.)
- Rejilla de **dos niveles**: `_grid` es un índice denso de punteros con celdas de **1 m³**
  (`_gridSizeX = maxX-minX` en metros enteros, `grid_16.hpp:118-131`); cada celda apunta a un bloque
  de `(1/res)³ + 1` vóxeles (el `+1` guarda el índice de control, `grid_16.hpp:142`) tomado de un
  **búfer circular** de `maxCells` bloques (`grid_16.hpp:143`, `:197`). Cuando el búfer da la vuelta,
  la celda más antigua se recicla y su entrada vuelve al `_dummy` (`grid_16.hpp:201-205`):
  **es una ventana deslizante con memoria acotada**, ideal para embebido.
- Celda no asignada ⇒ lecturas devuelven `_garbage` (`grid_16.hpp:229`, `:64-76`).
- Restricción oculta: `_cellSizeX = (uint32_t)(1/res)` (`grid_16.hpp:137`) ⇒ la resolución debe
  dividir 1 m (0,05 / 0,1 / 0,2 / 0,25…). `allocCell` recorre la celda con un `uint16_t j`
  (`grid_16.hpp:207`): con res < ~0,025 m (`_cellSize` > 65 535) el bucle no termina [V/I]. Para la
  Vita da igual (usaremos ≥ 0,05 m), pero el port debe usar `uint32_t`.

### 1.2 Integración de un scan [V]
Ruta: `pointcloudCallback` (`DB-TSDF/src/db_tsdf_node.cpp:217`) → `pcl::fromROSMsg` (`:287`) →
filtro de rango y diezmado `1 de N` (`:296-301`) → `transformPointCloud` a `odom` (`:308`) →
`loadCloud(pts, sensor_pos)` (`:312`) → republica la nube transformada en `/cloud` (`:314-318`).

`loadCloud` (`tsdf3d_16.hpp:200-250`):
1. **Asignación**: por cada punto, `allocCell` en el vecindario 3×3×3 **de celdas de 1 m**
   (`:203-210`) ⇒ 27 accesos al índice por punto, y la primera vez se rellena el bloque entero
   (8000 vóxeles a 0,05 m, `grid_16.hpp:206-211`).
2. **Kernel**: en paralelo con OpenMP (`num_threads(16)`, `:215`), por punto: elige el kernel por
   dirección del rayo con `dirToBin` (`atan2` + `asin` + `norm`, `:333-349`) y recorre K³ vóxeles
   (`:230-246`): `d &= mask[k]`; si `signs[k]==0`, `hits++` hasta `occMinHits` y entonces limpia el bit
   de libre. Puntos cuyo cubo `±2·step` sale del volumen se descartan (`:219-221`).
   Nota: las escrituras concurrentes no son atómicas; el AND es idempotente/commutativo, pero `hits++`
   puede perder incrementos [I]. Para el port en hilos hay que **particionar por espacio** (§4.4).
3. Kernels precalculados: `bins_az × bins_el` (60×60 = 3600 en los yaml) de K³ máscaras u16 + signos
   u8 (`tsdf3d_16.hpp:400-447`), con distancia L1 o L2 por rangos (`:354-397`) y "sombra" detrás del
   impacto dentro de `shadow_radius` (`:443-446`).

### 1.3 Parámetros reales
| Fuente | K | bins | res | volumen | maxCells | otros |
|---|---|---|---|---|---|---|
| `config/mai.yaml:30-46` | 5 | 60×60 | 0,05 | 200×200×30 m | 50 000 | `occ_min_hits 1`, rango ≤ 35 m |
| `config/college.yaml:76-92` | 7 | 60×60 | 0,05 | 200×200×60 m | 75 000 | `occ_min_hits 50`, 1,5–50 m |
| Paper Sec. III-B/C | **21** | 40×40 | 0,05–0,3 | — | — | — |

**El paper y el repo no coinciden en K** (21 vs 5/7) [V]. Importa ×27–74 en el coste por punto.

### 1.4 Rendimiento publicado [V paper, Sec. IV-B, Fig. 7]
- CPU: Intel Core i7-13620H (16 hilos; 6P+4E [A]), 32 GB.
- Newer College (Ouster OS-1 de 64 haces a 10 Hz,
  <https://ori-drs.github.io/newer-college-dataset/>): **154,8 ± 16,9 ms/frame** a 0,05 m sin
  diezmado; **91,1 ms** con diezmado 2. Casi constante entre 0,3 y 0,05 m.
- Sin cifras de memoria medidas; sin tiempos de Mai City.

---

## 2. Presupuesto

### 2.1 CPU

**Cargas de entrada** [V datasheets, cuentas propias]:
| Sensor | Puntos/scan | Hz | Puntos/s | Fuente |
|---|---|---|---|---|
| Ouster OS1-64 (paper) | 64×1024 = 65 536 | 10 | 655 k | <https://ori-drs.github.io/newer-college-dataset/>, datasheet OS1 |
| Velodyne VLP-16 | ~30 000 | 10 | ~300 k | <https://cdn.shopify.com/s/files/1/1750/5061/files/63-9229_Rev-H_Puck__Datasheet_Web.pdf> (Hz típico 10 [?]) |
| 32 canales (genérico) | ~60 000 | 10 | ~600 k | [H] |
| LDS-01/02 (TurtleBot3, 2D) | 360 | 5 | 1 800 | <https://emanual.robotis.com/docs/en/platform/turtlebot3/appendix_lds_01/> (360 lecturas: inferido del driver [?]) |

**Coste por punto (modelo de abajo arriba)** [H]:
| Paso | Operaciones | Ciclos A9 estimados |
|---|---|---|
| Transformación + filtro rango | ~20 FLOP f32 | ~30 |
| `dirToBin` (`atan2f`, `asinf`, `sqrtf`) | libm | 150–300 |
| `allocCell` ×27 (índice + comprobación) | ~15 instr. + acceso aleatorio | 400–1 000 (fallos de caché) |
| Kernel K³ (por vóxel: 2 cargas, AND, cmp, store condicional, rama de signo/hits, `++it` con rama de fin de fila y de `_dummy`) | ~10–14 instr. | **12–40 / vóxel** (12 si todo en L1; 40 con fallos a L2/RAM) |

Con K=5 (125 vóxeles): **≈ 2 000–6 000 ciclos/punto**; K=7 (343): ≈ 5 000–15 000; K=21 (9 261): ≈ 110 k–370 k.
Relleno de celdas nuevas: 32 KB por celda a 0,05 m (`memset` + bucle, `grid_16.hpp:206-211`); 4 KB a 0,10 m.

**Calibración con el paper (de arriba abajo)** [H]: 65 k puntos × K=21 ⇒ ~6·10⁸ actualizaciones de
vóxel en 155 ms con ~16 hilos a ~4 GHz ⇒ ~15 ciclos/actualización en x86: coherente con el modelo.
Si el paper usó K=7, 155 ms implicarían ~400 ciclos/actualización — no cuadra con el modelo, lo que
sugiere que el tiempo lo dominan otras cosas (PCL, relleno de celdas, publicación de `/cloud`) [H].
Conclusión: **no se puede escalar el número del paper sin saber K; hay que medir** (§6, T1).

**Capacidad de la Vita** [V docs/14 + docs/18, resto H]:
- 333 MHz con WiFi encendido (docs/14:48, `:61-63`); 444 MHz sin WiFi o a probar (E-H1, docs/14:263).
- Núcleos: homebrew ve 3 de 4 [?] (docs/14:161-164); dentro de Godot `WorkerThreadPool` está limitado
  a 2 y los núcleos 1–2 ya los usan decodificadores en el arranque (docs/18:94-95).
- Presupuesto realista para el mapeo: **1 núcleo dedicado + 1 compartido ≈ 0,5–0,67·10⁹ ciclos/s** [H].
- Factor de escala bruto i7-13620H (16 hilos, ~4 GHz, IPC ~3× la de la A9 [H]) vs Vita (2×333 MHz):
  ≈ **150–200×**. A 444 MHz y 3 núcleos ≈ 70–90×.

**Resultado por escenario** (ciclos totales / 0,6·10⁹ ciclos/s) [H]:
| Escenario | Puntos/scan | K | Tiempo/scan Vita | ¿Tiempo real? |
|---|---|---|---|---|
| Paper (OS1-64, K=21) | 65 k | 21 | **~12–40 s** | No |
| OS1-64 con config repo | 65 k | 7 | ~0,5–1,6 s | No (a 10 Hz) |
| VLP-16 crudo | 30 k | 5 | ~0,1–0,3 s | Al límite (3–10 Hz… sin margen para Godot) |
| VLP-16 voxelizado en el PC a 0,1–0,2 m | 3–5 k | 5 | **~10–50 ms** | **Sí a 2–5 Hz** |
| LDS 2D (360 pts) | 360 | 5 | **~1–4 ms** | Sí, sobrado |

NEON: el bucle de kernel por fila de K vóxeles se puede vectorizar (AND de 8×u16 por instrucción
`vand`), pero la estructura AoS de 4 B (`d,s,hits` entrelazados) y K impar lo dificultan; un port SoA
(`d[]` separado de `s/hits[]`) permitiría AND de filas completas [A/H]. Ganancia esperable ×1,5–3 en el
kernel, no en `allocCell`/`dirToBin` [H]. `dirToBin` se puede sustituir por una LUT (o por
`atan2` aproximado en f32) [H].

### 2.2 Memoria

Fórmula [V `grid_16.hpp:131-158`]: `bloques = maxCells · ((1/res)³+1) · 4 B`;
`índice = Vx·Vy·Vz (m) · sizeof(ptr)` (4 B en ARM32); `kernels = bins · K³ · 3 B` (+ cabeceras de
`std::vector`).

| res | B/celda 1 m³ | Volumen 20×20×4 m (1 600 celdas) | 40×40×6 m (9 600) | 200×200×30 (config mai, 50 000 celdas de pool) |
|---|---|---|---|---|
| 0,05 m | 32 KB | 51 MB | 307 MB ✗ | **1,6 GB ✗** |
| 0,10 m | 4 KB | **6,4 MB** | 38 MB | 200 MB ✗ |
| 0,20 m | 500 B | 0,8 MB | 4,8 MB | 25 MB |
| 0,25 m | 260 B | 0,4 MB | 2,5 MB | 13 MB |

- Índice de punteros: 200×200×30 = 1,2 M × 4 B = 4,8 MB (config mai); 40×40×6 = 9 600 × 4 B = 38 KB.
- Banco de kernels: 3600×125×3 = **1,35 MB** (K=5); K=7: 3,7 MB; paper (1600×9261×3): **44 MB**.
- Ojo: el pool es por **celdas tocadas**, y cada punto reserva su vecindario 3×3×3 m (`tsdf3d_16.hpp:205-209`)
  ⇒ con 0,05 m un solo scan en un pasillo puede pedir cientos de celdas (×32 KB) [I]. En el port conviene
  reservar solo las celdas que cubre el kernel (`±K/2·res`, normalmente 1–8 celdas) [H].

**Presupuesto Vita** [V]: ~365 MiB de usuario con `ATTRIBUTE2=12`; heap newlib 256 MiB (loader) vs
96 MiB (motor) con doble definición pendiente (docs/18:85-88); texturas 64 MiB (docs/18:91).
Propuesta: **≤ 64 MB para el TSDF**, reservados con `sceKernelAllocMemBlock` (USER_MAIN_RW cacheada,
docs/14:74, `:104-105`) fuera del heap, una sola vez al arrancar (regla «sin malloc en el bucle»,
docs/14:123-124). Con 0,10 m eso son ~16 000 celdas (16 000 m³ de ventana). **Holgado.** [H]

### 2.3 Red

**Vita**: WiFi 802.11 b/g/n solo 2,4 GHz (Wikipedia, citada en docs/14:255); 1 flujo a 20 MHz ⇒ PHY
≤ 72 Mbps [A]; útil típico 15–30 Mbps [H] (sin medición pública fiable encontrada; un foro habla de
144 Mbps, no verificado: <https://bandaancha.eu/foros/router-f680-antenas-consulta-1739497>).

**XRCE en `ros2_vita` hoy** [V]:
- MTU 512 (`UXR_CONFIG_CUSTOM_TRANSPORT_MTU`), ~490 B útiles (`xrce_transport.cpp:132-140`,
  `API_PARITY.md:102-103`).
- *Best effort* no fragmenta: un mensaje > MTU se rechaza (`xrce_transport.cpp:411-415`).
- Fiable: 16 huecos de 512 B (`:135-136`, `:181-182`); entrantes reconstruidos hasta **16 KB**
  (`MAX_RX`, `:137`, `:236-241`); salientes ~7,5 KB (`godot/README.md:81`).
- Rendimiento del fiable ≈ 16 × 490 B por ida y vuelta; con RTT WiFi 5–10 ms ⇒ **0,8–1,6 MB/s** [H].

**Tamaños de PointCloud2** [A + cuentas]: `point_step` típico 16 B (x,y,z,intensity) — Velodyne
añade ring/time (22–32 B).
| Nube | Bytes/scan | A 10 Hz | ¿Cabe hoy? |
|---|---|---|---|
| VLP-16 cruda (30 k × 16 B) | 480 KB | 38 Mbps | **No** (> 16 KB/mensaje; > ancho de banda) |
| Voxelizada 0,2 m (~3 k × 12 B) | 36 KB | 2,9 Mbps (a 2 Hz: 0,6 Mbps) | No en un mensaje; **sí troceada** |
| Troceada: 40 pts × 12 B = 480 B + cabecera | ~75 trozos/scan | — | **Sí, best effort** |
| LaserScan LDS (360 × 4 B + cabecera) | ~1,5 KB | 5 Hz | Sí (fiable fragmentado) |

**Decisión de diseño [H]**: enviar desde el PC/robot **trozos pequeños independientes**, cada uno ≤ 490 B,
por *best effort* (perder un trozo = perder 40 puntos; el TSDF lo tolera). Dos formatos posibles:
1. `sensor_msgs/PointCloud2` normal con ~25–35 puntos por mensaje (cabecera ROS ~60–80 B con
   `fields`): **no exige mensaje nuevo**, sí un nodo «troceador» en el PC.
2. Mensaje propio compacto (`vita_msgs/CloudChunk`: origen del sensor f32×3 + pose + `int16[]` cuantizado
   a mm/cm ⇒ 6 B/punto ⇒ ~75 pts/trozo). Más eficiente, pero exige paquete de interfaces en ROS 2.
Además, el troceador puede **transformar al marco `odom`** antes de enviar (como hace DB-TSDF en `/cloud`,
`db_tsdf_node.cpp:308`, `:314-318`) y meter el **origen del sensor** en el trozo; así la Vita no necesita
TF con historial (que `tf-tree` no tiene: `modules/tf-tree/README.md:18-21`).
Alternativa a medio plazo: subir MTU a ~1 400 B y `MAX_RX`/historial (cambio en `ros2_vita` + micro-ROS;
medir pérdidas). [H]

---

## 3. Arquitecturas candidatas

### (A) Mapeo completo en la Vita
La Vita recibe la nube cruda y ejecuta DB-TSDF con el volumen del paper.
- CPU: 12–40 s/scan con el setup del paper (§2.1) ✗. Memoria: 1,6–2,4 GB ✗. Red: 38 Mbps y mensajes de
  480 KB ✗.
- Solo sería viable reduciendo todo (=C).
**Veredicto: descartada.**

### (B) PC/robot mapea, la Vita visualiza («mini-rviz»)
DB-TSDF original corre en el PC (docker, `robotnik_dev` o la estación `docker/`; ojo: el repo apunta a
Humble, README:30). Un nodo puente en el PC extrae lo útil y lo manda a la Vita:
- DB-TSDF **no publica el mapa**: solo `/cloud` (nube transformada) y servicios que escriben ficheros
  (`db_tsdf_node.cpp:97`, `:119-130`; README:137-146). Hace falta un **nodo envoltorio** que enlace las
  cabeceras (son *header-only*) y publique periódicamente:
  - vóxeles superficie (`popcount(d) ≤ 1 && s&1 == 0`, criterio de `exportGridToPCD`,
    `grid_16.hpp:283-285`) como **deltas** por celda de 1 m (natural: la estructura ya es por celdas);
  - o una **proyección 2,5D** (mapa de alturas / `nav_msgs/OccupancyGrid` de una rebanada Z), que ya
    decodifica `msg-cdr` (`modules/msg-cdr/README.md:19`) — con el problema de los 16 KB: ≤ 128×128 por
    mensaje o teselas.
- Vita: dibujo. En Godot 4 Vita el **3D es experimental** (docs/18:51) y el 2D GXM es lo validado
  (docs/18:50, `:61-62`) ⇒ vista **cenital 2D** (textura de alturas o `MultiMeshInstance2D`/`draw_rect`
  por vóxel) es lo seguro. Cuidado: `texture_2d_update` recrea la textura entera (docs/18:91-93) ⇒
  actualizar a 1–2 Hz, no por frame. Vista 3D: opción en `vita-app` vitaGL (ADR 0007, docs/11) o probar
  GXM 3D con `MultiMeshInstance3D` de cubos [?].
- Coste Vita: casi nulo en CPU; red ≈ deltas de pocos KB/s [H].
**Veredicto: la más segura y rápida de demostrar; no aprende nada de TSDF en la Vita.**

### (C) Híbrido: la Vita integra una nube reducida en un volumen local
- PC: troceador (voxel grid 0,1–0,2 m + transformación a `odom` + trozos ≤ 490 B, §2.3).
- Vita: **`tsdf-local`**, port en C/Rust del integrador con: volumen local (p. ej. 20×20×4 m, ventana
  que sigue al robot reutilizando el búfer circular del original), res 0,10 m, K=5, bins 60×60,
  `occ_min_hits` 1–3, y sin PCL/Eigen/VTK/OpenMP.
- Variante **2D/2,5D** para TurtleBot3 + LDS: el mismo kernel direccional en 2D (K² en vez de K³,
  bins solo de azimut) sobre `LaserScan` ⇒ ~25 vóxeles/punto, coste ridículo, y demuestra el concepto.
- Visualización igual que (B), pero con datos propios.
| Criterio | A | B | C |
|---|---|---|---|
| CPU Vita | ✗ (×100–300 fuera) | ~0 | 10–50 ms/scan a 2–5 Hz [H] |
| Memoria Vita | ✗ (GB) | < 10 MB | 6–64 MB [H] |
| Red | ✗ 38 Mbps, 480 KB/msg | KB/s (deltas) | 0,5–3 Mbps en trozos best effort [H] |
| Cambios en el repo | — | nodo PC + vista | nodo PC + módulo dual + vista |
| Riesgo | — | Bajo | Medio (rendimiento por medir) |
| Valor didáctico / «ROS en la Vita» | — | Bajo-medio | **Alto** |

**Recomendación**: **C como objetivo, B como primer escalón** (comparten nodo PC, formato de vista y
la vista Godot; B sirve además de **oráculo visual**: lo que dibuja la Vita en C debe parecerse a lo que
manda el PC en B). Para el robot real del repo (TurtleBot3/turtlesim, `docker/`) empezar por la variante
**2D con LDS**, que no necesita LiDAR 3D.

---

## 4. Encaje en el repo

### 4.1 Módulo dual `modules/tsdf-local/` (regla dual, docs/03:8-14, `:56-67`; skill `vita-dual-module`)
```
modules/tsdf-local/
├── include/tsdf_local.h      # la verdad: structs, topes, códigos
├── impl-c/tsdf_local.c        # C99, sin malloc (memoria del llamador)
├── impl-rust/src/lib.rs       # #![no_std], rlib, extern "C"
├── tests/parity_test.c        # misma batería C y Rust
├── tests/oracle/              # volcados generados con el DB-TSDF original (host, docker)
└── README.md
```
API propuesta (borrador, a decidir con el usuario):
```c
typedef struct { float min[3], max[3]; float res; uint16_t k; uint16_t bins_az, bins_el;
                 uint8_t occ_min_hits, shadow_radius, dist_mode /*0=L1,1=L2*/; uint32_t max_cells; } tsdf_cfg_t;
size_t tsdf_required_size(const tsdf_cfg_t *cfg);            /* bloques + índice + kernels */
int    tsdf_create(tsdf_t **out, const tsdf_cfg_t *cfg, void *mem, size_t len);
int    tsdf_integrate(tsdf_t *t, const float *xyz_world, uint32_t n, const float origin[3],
                      uint32_t *integrated, uint32_t *skipped);
int    tsdf_read(const tsdf_t *t, float x, float y, float z, tsdf_voxel_t *out);  /* d, s, hits */
uint32_t tsdf_extract_surface(const tsdf_t *t, float *xyz_out, uint32_t cap, uint32_t *dropped);
int    tsdf_project_height(const tsdf_t *t, uint8_t *img, uint32_t w, uint32_t h, float z_lo, float z_hi);
int    tsdf_recenter(tsdf_t *t, const float center[3]);       /* ventana local */
```
Decisiones: memoria del llamador (como `tf-tree`, `modules/tf-tree/README.md:13`); `uint32_t` en los
bucles de celda (fallo de `grid_16.hpp:207`); kernels generados en `create` (o tabla precalculada
en el `.pck`); posibilidad de SoA para NEON; `dirToBin` con la **misma** `atan2f/asinf` de libm en C y
Rust (como `viz-math`, `modules/viz-math/README.md:26-28`) para que la paridad sea bit a bit.

### 4.2 Paridad y oráculo
- **Paridad C↔Rust**: escenas sintéticas (pared, esquina, suelo, esfera), mismo hash del volumen
  (como el fuzz de `msg-cdr`, `modules/msg-cdr/README.md:32-35`); recorte de entradas (NaN, fuera de
  volumen, n=0, buffer pequeño); ASan/UBSan en C.
- **Oráculo = DB-TSDF original** en host (docker, no en la laptop sin docker): un `oracle_dump.cpp` que
  incluye `tsdf3d_16.hpp`, integra las mismas nubes y vuelca `(x,y,z,d,s,hits)` de cada vóxel asignado.
  Comparación exacta en vóxeles con el **mismo orden de integración y un solo hilo** (el original con
  16 hilos no es determinista en `hits`, §1.2). Diferencias aceptadas y documentadas: reserva de celdas
  más ajustada (§2.2), ventana local.
- Licencia MIT ⇒ se puede copiar lógica con atribución en el README del módulo [V `LICENSE:1`].

### 4.3 Mensajes (`.rsch`, `tools/gen_msg_schema.py`)
- `sensor_msgs/msg/PointCloud2` (+ `PointField`, `Header`) y `sensor_msgs/msg/LaserScan` ya los
  conoce `rosbags` Jazzy; se añaden al `.rsch` con `gen_msg_schema.py <tipos…>`
  (`tools/gen_msg_schema.py:178-185`). `msg-schema` entrega los arrays primitivos **sin copiar**
  (`modules/msg-schema/README.md:30-32`): `data` del PointCloud2 llega como (puntero, cuenta) — perfecto
  para pasar a `tsdf_integrate` tras desempaquetar `x,y,z` según `fields/point_step`.
- Ruta rápida opcional: `msg_cdr_decode_point_cloud2` / `_laser_scan` en `msg-cdr` (tipado, sin
  esquema) si `msg-schema` resulta caro (medición pendiente, `modules/msg-schema/README.md:59`).
- Si se elige mensaje propio (`CloudChunk`), hay que crear un paquete de interfaces y añadirlo a la
  estación `docker/` y al generador (rosbags admite `.msg` propios [?]).

### 4.4 TF e hilos
- **TF**: `tf-tree` guarda solo el último valor (`modules/tf-tree/README.md:18-21`). Con la nube
  ya transformada en el PC (§2.3) no hace falta; si no, `tf_tree_lookup(odom, sensor)` al recibir es una
  aproximación aceptable a 2–5 Hz con robot lento [H].
- **Hilos** (docs/14:166-174, docs/18:94): Godot ejecuta callbacks en el hilo principal
  (`godot/README.md`, «Reglas heredadas de rclgd»). Patrón:
  - hilo principal: `poll()` XRCE + copiar trozo a un `msg-ring` (SPSC, ya existe);
  - **hilo de mapeo** dedicado (afinidad a un núcleo fijo, `sceKernelCreateThread` con máscara
    `n<<16`, docs/14:142-144), consume el anillo e integra;
  - extracción/proyección para la vista a 1–2 Hz, con doble búfer (el hilo de mapeo escribe el búfer B
    mientras la vista lee el A).
  - Paralelizar la integración en 2 hilos **por mitades del volumen** (cada hilo ignora puntos cuyo cubo
    cae en la otra mitad, o se duplica el borde) evita carreras en `hits` [H].
- En Godot: módulo C++ en árbol junto a `ros2_vita` (`godot/ros2_vita/SCsub`) que expone
  `TsdfLocal` (Object) con `integrate(PackedByteArray, origin)` y `get_height_image()`; el C es el
  respaldo y Rust opcional (docs/15:124-137).

### 4.5 Visualización (Godot 4 Vita)
| Opción | Estado en godot4-vita | Coste | Uso |
|---|---|---|---|
| Textura cenital de alturas/ocupación (L8/RGBA4444) | 2D GXM validado (docs/18:50) | recrea textura (docs/18:91-93) ⇒ 1–2 Hz | **Primera** |
| `MultiMeshInstance2D` / `_draw()` de rects por vóxel superficie | 2D | ~5–20 k rects [H medir] | Segunda |
| `MultiMeshInstance3D` (cubos) / `ImmediateMesh` (puntos) | **3D experimental** (docs/18:51) | desconocido | Experimento aparte |
| vitaGL en `vita-app` (mini-rviz) | ADR 0007, docs/11 | VBO de puntos | Si se quiere 3D seguro |
Marching Cubes (VTK, `grid_16.hpp:454-…`) no se porta en la primera versión.

---

## 5. Riesgos
| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| D1 | Coste por vóxel en la A9 mucho peor que 12–40 ciclos (caché, ramas) | Media | Alto | T3 primero; SoA + NEON; K=3/5; voxelizar más |
| D2 | WiFi/XRCE pierde muchos trozos best effort o satura el `poll` del hilo principal | Media | Medio | medir tasa de pérdida (netlog), limitar Hz, subir MTU |
| D3 | El paper usa K=21/32 bits y el repo K=5–7/16 bits: ¿cuál es «DB-TSDF»? | Alta | Medio | fijar el oráculo al **código** del commit 663c5a8 |
| D4 | No determinismo del original con OpenMP | Alta | Bajo | oráculo con 1 hilo |
| D5 | 3D de Godot Vita no apto | Alta | Medio | vista 2D; 3D en vita-app |
| D6 | Memoria: doble definición del heap (docs/18:85-87) y pools de Godot | Media | Medio | memblock propio; medir `sceKernelGetFreeMemorySize` |
| D7 | CPU a 333 MHz con WiFi (no 444) | Alta | Medio | presupuesto calculado a 333 |
| D8 | Desfase temporal nube/pose sin historial TF | Media | Medio | transformar en el PC |

---

## 6. Plan por etapas (puertas estilo G1–G7)

| Puerta | Dónde | Qué demuestra | Criterio verificable |
|---|---|---|---|
| **T0** | laptop (docker) | Oráculo: DB-TSDF original compila *solo las cabeceras* + `oracle_dump` en un 1 hilo sobre 4 escenas sintéticas | volcados `.bin` reproducibles (mismo hash dos veces) |
| **T1** | laptop/PC host | Microbench del **original** en x86 con K=5/7/21 y 3 k/30 k/65 k puntos | tabla ciclos/vóxel ⇒ resuelve D3 y calibra §2.1 |
| **T2** | laptop | `modules/tsdf-local` C y Rust con paridad + igualdad con el oráculo; ASan/UBSan | `tools/run-parity-tests.sh tsdf-local` verde |
| **T3** | Vita (app C mínima o `hwprobe`) | **Microbenchmark de integración en la Vita**: escena fija, 1/2/3 hilos, 333/444 MHz, K=3/5/7, 0,05/0,10 m; ms/scan y `sceKernelGetFreeMemorySize` | números en la bitácora; go/no-go de C (umbral: ≤ 100 ms para 3 k puntos K=5) |
| **T4** | PC (estación `docker/`) | Nodo troceador (voxeliza, transforma a `odom`, trozos ≤ 490 B best effort) + rosbag de prueba (Mai City o TurtleBot3 sim) | `ros2 topic hz/bw` dentro del presupuesto |
| **T5** | Vita + agente | Godot recibe los trozos (`.rsch` con PointCloud2/LaserScan) y cuenta pérdidas | netlog: % de trozos perdidos a 2/5 Hz |
| **T6** | Vita | **Arquitectura B**: el PC manda proyección 2,5D/vóxeles del DB-TSDF original; vista cenital | se ve el mapa coherente con rviz2 |
| **T7** | Vita | **Arquitectura C 2D**: LDS/LaserScan (turtlebot3 sim) integrado en la Vita | mapa en la Vita ≈ mapa B (diferencia visual mínima) |
| **T8** | Vita | **C 2,5D/3D local** con nube voxelizada; hilo de mapeo con afinidad; FPS de la HMI ≥ 30 | FPS y ms/scan medidos; sin regresión de G6 |

**Qué medir primero**: T1 (barato, resuelve la discrepancia K) y T3 (decide todo). Sin T3 no se
escribe la vista de C.

---

## 7. Lecciones para el usuario (modo aprendizaje)

Encaje con la ruta `docs/tutorial/07-ruta-completa-de-aprendizaje.md`. Conceptos previos, por orden:
1. **Nubes de puntos y PointCloud2**: `fields`, `point_step`, `row_step`, `is_dense`; diferencia con
   `LaserScan`. Reto: decodificar a mano 3 puntos de un fixture con `msg-schema`.
2. **Rejillas de vóxeles y TSDF**: qué es una distancia con signo truncada, por qué «truncada»,
   ocupación vs distancia. Lectura: §III del paper.
3. **Máscaras de bits y `popcount`**: cómo `d &= mask` guarda «la distancia mínima vista» (cada bit
   a cero = una unidad menos). Reto: en C, reproducir el kernel L1 1D de 5 celdas y comprobar a mano.
4. **Memoria de dos niveles y búfer circular** (`grid_16.hpp`): índice de punteros + pool; por qué
   acota la memoria. Reto: calcular la tabla de §2.2 para 0,25 m.
5. **Coste computacional**: ciclos por operación, cachés de 32 B (docs/14:51), por qué K³ manda.
   Reto: el microbenchmark T1 en host con `clock_gettime`.
6. **Transformaciones y TF** (ya visto con `tf-tree`/`viz-math`): marco del sensor → `odom`.
7. **Fragmentación y QoS** en XRCE (MTU 512, best effort vs fiable): por qué trocear la nube.
8. **Hilos y carreras**: por qué `hits++` desde 16 hilos pierde cuentas; partición espacial;
   `msg-ring` SPSC.
9. **Rust**: `#![no_std]`, slices sobre memoria del llamador, `u16::count_ones()` (= popcount),
   `extern "C"` — cada construcción nueva documentada en `docs/rust/` (regla del repo, CLAUDE.md).

---

## 8. Fuentes
- DB-TSDF: <https://github.com/robotics-upo/DB-TSDF> (commit 663c5a8) y página <https://robotics-upo.github.io/DB-TSDF/>.
- Paper: <https://arxiv.org/html/2509.20081> (Sec. III-A/B/C, IV-B, Fig. 7).
- Newer College: <https://ori-drs.github.io/newer-college-dataset/>; Ouster OS1:
  <https://cdn.shopify.com/s/files/1/0400/1752/6943/files/datasheet-rev7-v3p0-os1.pdf>.
- VLP-16: <https://cdn.shopify.com/s/files/1/1750/5061/files/63-9229_Rev-H_Puck__Datasheet_Web.pdf>.
- LDS-01: <https://emanual.robotis.com/docs/en/platform/turtlebot3/appendix_lds_01/>; LDS-02:
  <https://emanual.robotis.com/docs/en/platform/turtlebot3/appendix_lds_02/>.
- Cortex-A9 DMIPS/MHz 2,0–2,5 y CoreMark 2,9/MHz (fuentes secundarias):
  <https://community.element14.com/products/devtools/technicallibrary/w/documents/9939/arm-cortex-a9-overview>,
  <https://www.design-reuse.com/industryexpertblogs/23118/arm-atom-benchmark.html>.
- Repo PSVita-ROS: docs/03, docs/11, docs/14, docs/15, docs/18; `godot/ros2_vita/xrce_transport.cpp`,
  `godot/ros2_vita/API_PARITY.md`, `godot/README.md`; README de `msg-cdr`, `msg-schema`, `tf-tree`, `viz-math`.
