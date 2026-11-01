# 04a — DB-TSDF: análisis del código (informe detallado para la IA)

Fecha: 2026-11-01. Equipo: análisis del código. Objetivo: valorar portar DB-TSDF (o una variante) a la
PS Vita 1000 (Cortex-A9 444 MHz, 3 núcleos de app, NEON sin FP64, VFPv3, 512 MB + 128 MB CDRAM, newlib,
sin LiDAR: la nube llegaría por micro-ROS/XRCE por WiFi).

## 0. Fuentes y método

- Repo: `https://github.com/robotics-upo/DB-TSDF.git`, clonado `--depth 1` en
  `/tmp/claude-1000/-home-jcrex-Proyectos-PSVita-ROS/938836cd-3279-4f07-af4f-be4abf07b1ef/scratchpad/dbtsdf-src/repo`,
  commit `663c5a85c9d7e5b545f88a1b290fe9b52986eed2` (2026-06-08), rama por defecto `db_tsdf_16`.
  Ramas remotas (`git ls-remote`): `db_tsdf_16` (HEAD), `db_tsdf_32` (`08af5ca`), `legacy` (`7062aa3`).
  También se clonó `db_tsdf_32` en `.../dbtsdf-src/repo32` solo para comparar el vóxel.
- **No se compiló ni ejecutó nada del repo** (código no confiable). Todas las citas `fichero:línea` se
  refieren al clon de `db_tsdf_16` salvo que se indique `repo32`.
- Paper: Maese, Merino, Caballero, «DB-TSDF: Directional Bitmask-based Truncated Signed Distance Fields
  for Efficient Volumetric Mapping», arXiv:2509.20081 v1 (24-sep-2025), aceptado en ICRA 2026
  (https://arxiv.org/abs/2509.20081, HTML: https://arxiv.org/html/2509.20081v1; README.md:1-11).
- Web del proyecto: `docs/index.html` del repo (https://robotics-upo.github.io/DB-TSDF/).

Tamaño del código C++ útil: **~1 558 líneas** (`src/db_tsdf_node.cpp` 441, `include/db_tsdf/grid_16.hpp`
566, `include/db_tsdf/tsdf3d_16.hpp` 488, `trilinear_params.hpp` 19, `ElapsedTime.hpp` 44). El núcleo
algorítmico real son ~250 líneas (grid_16.hpp:27-258 + tsdf3d_16.hpp:200-250 + 333-486).

## 1. El algoritmo

### 1.1 Qué es un TSDF

Un *Truncated Signed Distance Field* es una rejilla 3D de vóxeles donde cada vóxel guarda la distancia
(con signo: fuera/dentro de la superficie) a la superficie más cercana, recortada («truncada») a un
máximo. La superficie es el nivel cero, que se extrae con Marching Cubes. Los TSDF clásicos (KinectFusion,
Voxblox, VDBFusion) lanzan rayos desde el sensor y promedian distancias con pesos.

### 1.2 Qué significa «DB»

**Directional Bitmask** (README.md:1; package.xml:6; paper título). Verificado: no es «bitwise» ni
«double buffer».

- **Bitmask**: la distancia no se guarda como número, sino como una máscara de bits cuyo **número de bits
  a 1 = distancia** (en vóxeles). Comentario `uint16_t d; // Manhattan mask (bit-count -> distance)`
  (grid_16.hpp:29); lectura con `__builtin_popcount(cell[j].d)` (grid_16.hpp:283, 329, 413, 489).
  Integrar una medida = `AND` bit a bit de la máscara del vóxel con la del kernel (tsdf3d_16.hpp:236-238):
  como AND solo apaga bits, la distancia **solo puede bajar** → equivale a un `min()` sin comparaciones
  ni flotantes. La máscara de distancia `r` es `0xFFFF >> (16-r)` (r bits bajos a 1; tsdf3d_16.hpp:375, 434).
- **Directional**: hay un banco de kernels precalculados, uno por bin de dirección del rayo
  (azimut × elevación, `bins_az × bins_el`, por defecto en los YAML 60×60 = 3 600; config/college.yaml:43-44).
  Cada kernel K×K×K lleva, además de la máscara de distancia, un **signo** por vóxel: 0 (ocupado) si es el
  vóxel del impacto o cae en la «sombra», semiesfera de radio `shadow_radius` **detrás** del impacto según la
  dirección del rayo (`dir·(x,y,z) >= 0`, tsdf3d_16.hpp:443-446). El bin se elige con `atan2` y `asin`
  (tsdf3d_16.hpp:333-349).

### 1.3 Entradas / salidas / localización

- **Entradas**: `sensor_msgs/PointCloud2` (`in_cloud`, db_tsdf_node.cpp:42, 102-105), de la que solo se usa
  XYZ (`pcl::fromROSMsg` → `PointXYZ`, :286-287), y la **pose del sensor** por TF:
  - modo genérico: `tf2_ros::Buffer::lookupTransform(odom_frame_id, cloud.frame_id, stamp, 100 ms)`
    (:266-274);
  - modo «legacy»: suscripción a un `geometry_msgs/TransformStamped` (`in_tf_topic`, :107-113), histórico de
    100 muestras (:329-331) y emparejado por sello de tiempo con tolerancia 100 ms (:184, 243-261).
- **No localiza**: es solo mapeo con pose conocida. No hay ICP ni optimización; la pose viene de fuera
  (odometría/LIO). El paper dice que hereda el backend TDF de D-LIO, que sí era de localización
  (https://arxiv.org/html/2509.20081v1). Restos de esa herencia: `computeDistInterpolation`
  (tsdf3d_16.hpp:252-304) y `TrilinearParams` (trilinear_params.hpp) **no se llaman** desde el nodo (grep).
  Útiles a futuro si se quisiera localizar contra el mapa (hipótesis).
- **Salidas**:
  - topic `/cloud` (PointCloud2 filtrada y en marco `odom`, db_tsdf_node.cpp:97, 314-318) — **no** publica el
    mapa;
  - 4 servicios `std_srvs/Trigger` que escriben ficheros en un hilo `detach()`: `/save_grid_pcd`,
    `/save_grid_ply`, `/save_grid_csv`, `/save_grid_mesh` (:119-129, 362-424). La malla usa VTK
    (suavizado gaussiano + Marching Cubes por celda; grid_16.hpp:454-549).

### 1.4 Estructura de datos

Rejilla de **dos niveles** (grid_16.hpp):

1. **Celdas de 1 m³** indexadas densamente: `_grid` es un array de `VoxelData*` de tamaño
   `gridSizeX·gridSizeY·gridSizeZ` (en metros, grid_16.hpp:126-131, 158-159). Las no reservadas apuntan a
   un bloque `_dummy` compartido (:153-159). El tamaño de celda **está fijado a 1 m** porque el índice usa
   la parte entera de la coordenada en metros (`(uint32_t)x`, :193-194, 227-228).
2. **Vóxeles** dentro de cada celda: `(1/res)³` vóxeles + 1 de control (:137-142). Con 0,05 m → 20³ = 8 000
   + 1. El vóxel de control guarda el índice de la celda propietaria (:148-149, 214-215).
3. **Pool circular** `_buffer` de `maxCells` celdas reservado y rellenado con `memset` de golpe al arrancar
   (:143-150). Cuando se agota, `allocCell` **recicla la celda más antigua (FIFO)** y pone a `_dummy` el
   puntero de su antiguo dueño (:197-205) → memoria acotada, pero el mapa **olvida** zonas viejas.

Vóxel (rama `db_tsdf_16`), `static_assert(sizeof(VoxelData) == 4)` (grid_16.hpp:27-33):

| Campo | Tipo | Bytes | Significado |
|---|---|---|---|
| `d` | `uint16_t` | 2 | máscara de distancia (popcount = rango/distancia, máx. 16) |
| `s` | `uint8_t` | 1 | bit0: signo, 0 ocupado / 1 libre |
| `hits` | `uint8_t` | 1 | contador de impactos (satura en `occ_min_hits`) |

Rama `db_tsdf_32` (la del paper): `uint32_t d` + 2×`uint8_t` = **8 B con padding** (repo32
`include/db_tsdf/grid_32.hpp:26-31`); el paper y la web dicen 8 B/vóxel y kernel 21³ con 40×40 bins
(arXiv HTML; docs/index.html:267-268). **El código publicado (16 bits) difiere del paper**: 4 B/vóxel,
distancia truncada a 16 vóxeles, kernels 5–7.

### 1.5 Integración (por scan)

`TSDF3D16::loadCloud(cloud, sensor_pos)` (tsdf3d_16.hpp:200-250):

1. **Reserva secuencial** de celdas: para cada punto, las 27 celdas de 1 m vecinas (bucle ±1 m en x,y,z,
   :203-210) — un punto toca hasta 27 celdas.
2. **Bucle paralelo OpenMP** sobre puntos, `num_threads(16)` fijo (:215). Por punto:
   descarta si el kernel saldría de la rejilla (:219-221); calcula bin de dirección (:224-226); recorre
   K³ vóxeles con un iterador que avanza en x y salta de celda cuando cruza el borde (grid_16.hpp:78-88);
   por vóxel: `d &= kernel_mask` (escritura solo si cambia) y, si el signo del kernel es 0 y
   `hits < occ_min_hits`, `++hits`; al llegar al umbral, `s` pasa a ocupado (tsdf3d_16.hpp:233-245).
3. Antes, en el nodo: filtro de rango min/max y diezmado 1 de cada N (db_tsdf_node.cpp:292-301),
   transformación rígida con `pcl::transformPointCloud` (:308).

Observaciones:
- **No hay tallado de espacio libre** (*free-space carving*): las entradas del kernel con signo 1 no hacen
  nada; un vóxel ocupado **nunca vuelve a libre** (tsdf3d_16.hpp:240-245). Mundo estático; el paper lo
  reconoce como trabajo futuro (dinámicos).
- **Carrera de datos**: varios hilos hacen read-modify-write sobre los mismos vóxeles sin atómicos
  (tsdf3d_16.hpp:215-247). La AND es casi idempotente pero se pueden perder actualizaciones y `++hits`
  puede contar de menos. Comportamiento indefinido en C++ formalmente. En una versión propia: particionar
  por región o aceptar el error documentándolo.
- `#pragma omp barrier` fuera de región paralela (tsdf3d_16.hpp:249): huérfano, sin efecto.
- `allocCell` reinicia la celda con `for (uint16_t j = 1; j < _cellSize; ++j)` (grid_16.hpp:207): si
  `res < 0,025 m`, `_cellSize > 65 535` y el bucle **no termina** (bug latente; con 0,05 m no ocurre).

### 1.6 Consulta

- `read(x,y,z)` / `operator()` (grid_16.hpp:222-247): O(1), dos indirecciones (celda → vóxel), coordenadas
  `float`; fuera de celda reservada devuelve `_garbage` (= máx. distancia, libre).
- Distancia = `popcount(d)` (en vóxeles; ×res para metros). Ocupado = `(s & 1) == 0`.
- Exportaciones: recorren **toda** la rejilla de celdas (O(gridSize) + O(celdas×(1/res)³)), grid_16.hpp:260-549.

### 1.7 Complejidad por scan

- Integración: **O(Np · K³)** (paper: T ≈ Np·K³·C_op), independiente de la resolución — de ahí el
  «constant-time» del README (README.md:17). Más la reserva: O(27·Np) búsquedas de celda.
- Precálculo de kernels al arrancar: O(bins · K³) (tsdf3d_16.hpp:412-447).
- Ejemplo (hipótesis de Np): Newer College con Ouster OS1-64 a 1024 columnas ≈ 65 536 puntos/scan;
  con K=7 → ~22,5 M actualizaciones de vóxel por scan; con K=21 (paper) → ~607 M.

## 2. Dependencias

Distribución: **ROS 2 Humble**, Ubuntu 22.04 (README.md:29; Dockerfile `ros-humble-*`). Estándar
**C++20** (CMakeLists.txt:5). El Dockerfile aclara que Ceres/ANN/OpenVDB eran restos y ya no se usan.

| Dependencia | Dónde | Uso real | ¿Bloquea en Vita? | Alternativa |
|---|---|---|---|---|
| rclcpp | package.xml:13; node completo | nodo, parámetros, subs, pubs, servicios | **Sí** | uxr client (micro-ROS/XRCE) ya en `vita-app/` y `modules/microros-transport` |
| tf2, tf2_ros, tf2_geometry_msgs | package.xml:15-17; node.cpp:23-24, 93-94, 268 | pose del sensor | **Sí** | modo legacy: suscribir `TransformStamped`/`Odometry` y emparejar por tiempo (node.cpp:243-261); `modules/tf-tree` |
| message_filters | package.xml:14 | **ninguno** (grep) | No | quitar |
| sensor_msgs, geometry_msgs, std_srvs | package.xml | mensajes | Parcial | `modules/msg-cdr` + `msg-schema` |
| pcl_ros, pcl_conversions, PCL (common, filters, io) | CMakeLists.txt:22-24; node.cpp:27-29, 286-315; grid_16.hpp:12-15 | tipo `PointXYZ`, ROS↔PCL, `transformPointCloud`, guardar PCD/PLY | **Sí** (PCL arrastra Boost, FLANN…) | `struct {float x,y,z;}`, deserializador CDR propio, matriz 3×4 a mano |
| VTK 9 | CMakeLists.txt:29-37; grid_16.hpp:19-25, 454-549 | malla (Marching Cubes) | **Sí** | no exportar malla en la Vita; enviar vóxeles al PC o Marching Cubes propio |
| Boost (thread, chrono) | CMakeLists.txt:25 | **ninguno** en el código (grep) | No | quitar |
| OpenMP | CMakeLists.txt:26, 57; tsdf3d_16.hpp:215 | paralelizar bucle de puntos | Probable (hipótesis: VitaSDK no trae libgomp) | 3 hilos con pthread de VitaSDK o `sceKernelCreateThread`, reparto por puntos |
| Eigen3 | CMakeLists.txt:27; tsdf3d_16.hpp:9 | `Vector3f`, `Matrix4f`, `Quaternionf` | No (header-only, soporta ARM/NEON) | Eigen o `modules/viz-math` |
| `std::filesystem` | grid_16.hpp:9, 356 | export CSV | Hipótesis: soporte dudoso en newlib | quitar con el export |
| `clock_gettime` | ElapsedTime.hpp (no usado por el nodo) | medir tiempo | Hipótesis | `sceKernelGetProcessTimeWide` |
| Flags `-march=native -mavx -mavx2 -mfma` | CMakeLists.txt:8 | autovectorización x86 | **Sí** (no compila en ARM) | `-mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -O3` |

## 3. Perfil de recursos

### 3.1 Memoria

Fórmula del código: `maxCells · (1 + (1/res)³) · sizeof(VoxelData)` (grid_16.hpp:142-143) + punteros
`gridSizeX·Y·Z · sizeof(void*)` (:158) + kernels `bins · K³ · 3 B` (tsdf3d_16.hpp:418-419).

| Config | res | maxCells | Pool de celdas | Punteros (64 bit / 32 bit Vita) | Kernels |
|---|---|---|---|---|---|
| college.yaml:29-37 (200×200×60 m) | 0,05 m | 75 000 | 75 000 × 32 004 B ≈ **2,40 GB** | 2,4 M → 19,2 MB / 9,6 MB | K=7: 3 600×343×3 ≈ 3,7 MB |
| mai.yaml:29-37 (200×200×30 m) | 0,05 m | 50 000 | ≈ **1,60 GB** | 1,2 M → 9,6 / 4,8 MB | K=5: ≈ 1,35 MB |
| Rama 32 bits (paper) | 0,05 m | 75 000 | ≈ 4,8 GB | igual | K=21: 40×40×9 261×5 B ≈ 74 MB (hipótesis: 4 B máscara + 1 B signo) |

Todo se reserva y se escribe con `memset` al arrancar (grid_16.hpp:143-150): **no es perezoso**.
El paper no da memoria medida (solo 8 B/vóxel y la fórmula).

Escalado a la Vita (hipótesis: presupuesto de ~200 MB para el pool, dejando el resto a Godot/red):

| res | B/celda de 1 m³ | Celdas en 200 MB |
|---|---|---|
| 0,05 m | 32 004 | ~6 250 |
| 0,10 m | 4 004 | ~49 950 |
| 0,20 m | 504 | ~396 000 |

Como cada punto reserva 27 celdas vecinas (tsdf3d_16.hpp:203-210), la ocupación real crece con el área
de superficie observada (hipótesis: una franja de ~3 m alrededor de las superficies). El FIFO hace que el
mapa sea una «ventana» de las últimas N celdas.

### 3.2 CPU y tiempos

- Paper (rama 32 bits, K=21, 40×40 bins): Intel Core i7-13620H, 16 hilos, 32 GB RAM; Newer College
  ≈150 ms/scan estable de 0,3 a 0,05 m; 0,05 m sin diezmado 154,8 ± 16,9 ms; con diezmado 2: 91,1 ms
  (https://arxiv.org/html/2509.20081v1). No reporta tiempo de Mai City. Hilos usados: no dice; el código
  fija 16 (tsdf3d_16.hpp:215).
- Web/README de la versión 16 bits: **20–40 ms por scan** (docs/index.html:277-287), sin detallar CPU
  (hipótesis: la misma máquina).
- El nodo imprime el tiempo por frame (db_tsdf_node.cpp:320-322).

**Estimación para la Vita (hipótesis, sin medir)**: 3 núcleos × 444 MHz ≈ 1,3 Gciclos/s. Si una
actualización de vóxel cuesta ~10 ciclos con caché caliente, ~130 M act./s; peor con fallos de caché
(acceso disperso a celdas de 32 KB). Escenarios:

| Np (tras diezmar) | K | Actualizaciones | Tiempo estimado Vita |
|---|---|---|---|
| 65 536 | 7 | 22,5 M | ~0,2–0,7 s (no tiempo real) |
| 10 000 | 5 | 1,25 M | ~10–40 ms |
| 5 000 | 5 | 0,6 M | ~5–20 ms |

Más `dirToBin` por punto (`atan2f`, `asinf`, `sqrt`; tsdf3d_16.hpp:335-343), coste menor frente a K³.
**Cuello de botella previsible: la red**, no la CPU: una PointCloud2 XYZ+intensidad de 65 k puntos ≈
1–2 MB/scan; a 10 Hz serían 80–160 Mbit/s, muy por encima de lo realista para el WiFi de la Vita
(hipótesis: < 20 Mbit/s útiles) y de la fragmentación XRCE. → diezmar/filtrar en el robot (VoxelGrid) a
≤ 5–10 k puntos y/o bajar la frecuencia.

### 3.3 SIMD, hilos y precisión

- **No hay intrínsecos SIMD** (grep de `immintrin`, `_mm`, `__m256`: 0 resultados). Solo flags de
  autovectorización AVX2/FMA y `-fopenmp-simd` sin `#pragma omp simd` (CMakeLists.txt:8). En la Vita no
  se pierde nada explícito; NEON (128 bit) podría vectorizar la fila x del kernel (K vóxeles contiguos):
  con la estructura AoS de 4 B, `vld4.8`/`vld2.16` desintercalan `d`; mejor pasar a SoA (máscaras
  `uint16_t` contiguas → `vandq_u16` de 8 en 8). Ojo: la fila puede cruzar de celda (grid_16.hpp:81-86).
- **Hilos**: OpenMP con 16 hilos fijos; el resto es el executor single-thread de `rclcpp::spin` (node.cpp:432)
  y hilos `detach()` para exportar (:365-372).
- **float vs double**: el núcleo es `float` (rejilla, kernels, puntos). `double` aparece en: parámetros ROS
  (node.cpp:48-57, 163, 177), filtro de rango (`d2` double, :292-297), `computeDistInterpolation(const
  double&…)` (no usado), y **promociones implícitas por `M_PI`** (double) en `dirToBin` y `binToDir`
  (tsdf3d_16.hpp:338, 342-343, 406-407). En la Vita, NEON no tiene FP64 pero VFPv3 sí hace double escalar
  (más lento): cambiar `M_PI` por `float(M_PI)`/`M_PIf` y el filtro a float. Coste bajo, por punto.
- Enteros: índices `uint32_t` (grid_16.hpp:556); en la Vita los punteros son de 32 bits, y el pool debe
  caber en el espacio de direcciones del proceso (hipótesis: decenas–cientos de MB usables por una app).

## 4. Mapa de ficheros

| Fichero | Responsabilidad | Líneas | Portabilidad Vita |
|---|---|---|---|
| `include/db_tsdf/grid_16.hpp:27-258` | `VoxelData`, `GRID16`: rejilla 2 niveles, pool FIFO, iterador, lectura | 232 | **Portable** (malloc grande, C++ básico); revisar bucle `uint16_t` (:207) |
| `include/db_tsdf/grid_16.hpp:260-452` | export PCD/PLY (PCL) y CSV (`std::filesystem`) | 193 | **Bloqueante** tal cual → eliminar o reescribir sin PCL |
| `include/db_tsdf/grid_16.hpp:454-549` | malla con VTK (gaussiano + Marching Cubes) | 96 | **Bloqueante** → hacer en el PC |
| `include/db_tsdf/tsdf3d_16.hpp:15-112` | `DirectionalKernel`, `TSDF3D16::setup`, exportadores | 98 | Portable |
| `include/db_tsdf/tsdf3d_16.hpp:114-197` | variantes `loadCloud` con yaw / RPY y filtro AABB | 84 | Requiere cambios (`pcl::PointXYZ` → struct propio) |
| `include/db_tsdf/tsdf3d_16.hpp:200-250` | **integración** (reserva + kernel AND + hits, OpenMP) | 51 | Requiere cambios (OpenMP → hilos Vita, quitar PCL, decidir carreras) |
| `include/db_tsdf/tsdf3d_16.hpp:252-304` | interpolación trilineal de distancia (herencia D-LIO, no usada) | 53 | Portable (pasar `double`→`float`) |
| `include/db_tsdf/tsdf3d_16.hpp:333-486` | `dirToBin`, generación de kernels L1/L2 y vista previa | 154 | Portable (Eigen; `std::map/set`, iostream); `M_PI`→float |
| `include/db_tsdf/trilinear_params.hpp` | polinomio trilineal | 19 | Portable |
| `include/ElapsedTime.hpp` | cronómetro `clock_gettime` (no usado por el nodo) | 44 | Requiere cambios (hipótesis) |
| `src/db_tsdf_node.cpp` | nodo ROS 2: parámetros, TF, filtro, PCL, pub `/cloud`, servicios | 441 | **Bloqueante** → reescribir sobre uxr/XRCE; lógica de filtro (:292-301) y emparejado TF legacy (:243-261) reutilizables |
| `CMakeLists.txt` | build ament, flags x86 AVX | 87 | **Bloqueante** → CMake VitaSDK |
| `package.xml` | dependencias ROS (ament, Humble) | 38 | N/A en Vita |
| `config/*.yaml` | presets college/mai | 46+46 | Referencia de parámetros |
| `launch/mapper_launch.py`, `config/rviz/*` | lanzamiento + RViz | 66 / 189×2 | N/A (lado PC) |
| `Dockerfile`, `scripts/download_*.sh` | entorno Humble, descarga de datasets | 104 / 93+98 | N/A (no ejecutados) |
| `docs/` | web del proyecto | — | N/A |

## 5. Licencia

- Código: **MIT**, «Copyright (c) 2022 Service Robotics Lab» (LICENSE; package.xml:8). Permite copiar,
  modificar, sublicenciar y redistribuir, con la única condición de conservar el aviso de copyright y la
  licencia en copias o partes sustanciales. **Compatible** con portarlo dentro de PSVita-ROS; hay que
  incluir el LICENSE original en la carpeta del port y citar el origen en el README.
- Paper: CC BY-SA 4.0 en arXiv (https://arxiv.org/abs/2509.20081) — afecta a reutilizar texto/figuras
  (compartir igual), no al código.
- Citar el paper (bibtex en README.md) si se publica algo basado en él.

## 6. Conclusiones para el port

1. El núcleo (rejilla + kernels + integración) es pequeño, C++ simple, `float`, sin SIMD explícito: **es
   portable** y además encaja con la regla del repo de módulo dual Rust + C detrás de un `.h`.
2. Todo lo bloqueante está en la periferia: rclcpp/tf2 (→ XRCE), PCL (→ struct + CDR), VTK (→ PC),
   OpenMP (→ 3 hilos), flags AVX.
3. El límite real es **memoria**: los presets piden 1,6–2,4 GB. En la Vita: res 0,10 m (4 KB/celda) o
   0,05 m con pocos miles de celdas (zona local, FIFO), quizá reducir `uint8 s` a bits empaquetados.
4. El límite de **ancho de banda** obliga a diezmar en el robot (≤ 5–10 k puntos/scan).
5. Puntos a decidir con el usuario: carreras de datos en paralelo, falta de tallado de espacio libre
   (mapa estático), cómo visualizar (no hay topic de mapa; habría que crear uno o pintar en Godot).
