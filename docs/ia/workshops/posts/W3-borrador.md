# W3 — DB-TSDF reducido en la PS Vita: escalera de variantes de bits intercambiables en caliente

**Borrador técnico** (base de `docs/26-db-tsdf-vita.md` [I: el 26 está libre] y del ADR) · 2026-11-12 ·
autor: diseñador-dbtsdf (fable) · estado: diseño, nada medido en hardware.

Marcas: **[V]** leído en el fichero/URL citado o comprobado con un script propio · **[I]** inferencia o
estimación · **[?]** sin dato. Todo tiempo en la Vita es **[I]** hasta medirlo (§7).

Abreviaturas de las fuentes de DB-TSDF (`https://github.com/robotics-upo/DB-TSDF`, clones de solo lectura,
**no se compiló ni ejecutó nada del repo**):

| Prefijo | Rama | Commit | Fecha |
|---|---|---|---|
| `DB16/` | `db_tsdf_16` (HEAD, por defecto) | `663c5a85c9d7e5b545f88a1b290fe9b52986eed2` | 2026-06-08 |
| `DB32/` | `db_tsdf_32` | `08af5ca38a81bae64931df87abf49ee2e6ce17b6` | 2026-03-04 |
| `DBleg/` | `legacy` | `7062aa35b39c2e742bb027ed2ca1af30e212e815` | 2025-09-29 |

Paper: Maese, Merino, Caballero, arXiv:2509.20081 **v1** (única versión; 24-sep-2025),
<https://arxiv.org/html/2509.20081v1>. Contexto previo (no se repite): `docs/ia/auditoria/04a-…` y `04b-…`.

---

## 0. Recomendación

1. **«Bits» = ancho `W` de la máscara de distancia** (código termómetro: `W` bits ⇒ `W+1` niveles). Es lo único
   que cambia el algoritmo: fija el alcance de truncamiento y el kernel máximo útil. Contador y empaquetado son
   consecuencias de formato, fijadas por peldaño.
2. **Escalera V32 → V16 → V8 → V4**, con el vóxel en **una sola palabra de `W/4` bytes** (8 / 4 / 2 / 1 B):
   máscara de `W` bits + contador de impactos (8 bits; 4 en V4). El bit de signo desaparece: es redundante con el
   contador. Kernel máximo sin pérdida (L1): **K = 21 / 11 / 5 / 3**.
3. **No hay contradicción paper ↔ proyecto**: el paper describe V32 (rama `legacy`); el código publicado por
   defecto ya es V16 (los propios autores lo llaman «versión de 16 bits, más ligera»). El proyecto sigue esa
   misma reducción hacia V8 y V4.
4. **Un solo módulo dual `modules/db-tsdf/`** con todas las variantes compiladas, handle opaco, memoria del
   llamador y dos funciones para el cambio en caliente: `dbtsdf_plan` (qué pasaría) y `dbtsdf_reconfigure`
   (hazlo), con un informe que dice si el mapa se conserva, se convierte (exacto o con pérdida) o se reinicia.
5. **Orden**: LaserScan 2D primero (losa de un vóxel de alto, en el hilo principal con presupuesto de ms); nube
   3D decimada y hilo propio solo después de medir (T3, T5). En 2D **toda** la escalera 32→4 corre en tiempo
   real [I]; en 3D, V4–V16 con K ≤ 7.
6. **La calidad se mide en el PC** (la paridad bit a bit garantiza que la Vita produce el mismo mapa); en hardware
   solo tiempo, FPS, latencia y memoria.
7. **Expectativa calibrada (hipótesis a refutar)**: con la entrada limitada por XRCE (≤ 4–15 k puntos/s), bajar
   bits **no cambiará los FPS** con K ≤ 7; cambia la memoria (×2 por peldaño) y el alcance del campo de
   distancia. Si T3 lo confirma, la escalera se queda como selector de memoria/alcance, no de velocidad.

---

## 1. Re-verificación del código y diferencias con 04a

- `git ls-remote` (2026-11-11) y clones `--depth 1` (2026-11-11 y 2026-11-12): **los tres commits coinciden con
  04a** (`04a:11-12`). No hay código nuevo desde el 2026-06-08 **[V]**.
- Clones en `/tmp/claude-1000/-home-jcrex-Proyectos-PSVita-ROS/d90a8c2e-dd6b-4dea-8c32-fe21a8477ad2/scratchpad/dbtsdf/{repo16,repo32,repolegacy}`
  (el scratch es volátil: se borró una vez entre sesiones y se volvió a clonar).

Lo que 04a/04b no decían o hay que corregir (todo **[V]** salvo indicación):

| # | Hallazgo | Fuente |
|---|---|---|
| a | «popcount = distancia L1» solo vale con `distance_mode: "L1"` (valor por defecto del nodo). **Los dos YAML publicados usan `"L2"`**, donde popcount = **rango** de `r²` entre los valores distintos del cubo del kernel (no lineal, depende de K) | `DB16/config/college.yaml:46`, `DB16/config/mai.yaml:46`, `DB16/src/db_tsdf_node.cpp:63`, `DB16/include/db_tsdf/tsdf3d_16.hpp:357-386,430-441` |
| b | El paper define un **tercer** código: `⌈‖(x,y,z)‖₂⌉` (Ec. 3) aunque el texto diga «truncated L1»; la rama `legacy` lo implementa así | paper §III-A/B, Ec. 3; `DBleg/include/db_tsdf/tsdf3d_32.hpp:534-538` |
| c | **La implementación del paper es la rama `legacy`**, no `db_tsdf_32`: rejilla **densa**, K = 21 fijo, 40×40 bins, `OCC_MIN_HITS 50`, sombra 8, `num_threads(20)`, y `uint16_t hits` (el paper dice 8 bits) | `DBleg/include/db_tsdf/tsdf3d_32.hpp:23-28,31-35,38-44,74,155,170-172` |
| d | `db_tsdf_32` (refactor posterior con rejilla de dos niveles): preset college K = **25**, bins **360×360**, sombra 10, `occ_min_hits 80`, L2. Su banco de kernels serían 129 600 × 15 625 × 5 B ≈ 9,4 GiB [I, cuenta propia] | `DB32/config/college.yaml:35-40`, `DB32/include/db_tsdf/grid_32.hpp:26-32` |
| e | Los valores por defecto **del código** (K = 11, bins 40×40, sombra 6, L1, res 0,10, 10 000 celdas) no son los del README (que copia college.yaml) | `DB16/src/db_tsdf_node.cpp:54-64`, `DB16/README.md:130-132` |
| f | **La máscara de distancia del kernel no depende de la dirección**: solo el signo depende del bin. El original guarda 3 600 copias idénticas de las máscaras | `DB16/include/db_tsdf/tsdf3d_16.hpp:430-446` |
| g | **El bit de signo es redundante**: `s == 0` ⟺ `hits == occ_min_hits` (se pone a 0 solo en ese instante y `hits` satura ahí) | `DB16/include/db_tsdf/tsdf3d_16.hpp:240-245`, `DB16/include/db_tsdf/grid_16.hpp:207-210`; simulación propia §A.3 |
| h | **La malla (y por tanto F-score/Chamfer del paper) sale solo de la ocupación**, no de la máscara: `legacy` usa `occupied && d == 0`; las ramas nuevas calculan `is_surface` y no lo usan | `DBleg/src/vtk_mesh_extractor.cpp:38-55`, `DB16/include/db_tsdf/grid_16.hpp:489-502` |
| i | El iterador devuelve `_garbage` por referencia para celdas sin reservar y el bucle escribe en él: el centinela «desconocido» se puede corromper si el FIFO recicla una celda dentro del mismo scan [I] | `DB16/include/db_tsdf/grid_16.hpp:64-69,102`, `DB16/include/db_tsdf/tsdf3d_16.hpp:235-238` |
| j | Las filas `y`,`z` del kernel se eligen acumulando `float` (`y += res`), y el CMake compila con `-march=native -mavx2 -mfma`: el resultado en el borde de un vóxel depende del redondeo y de la contracción FMA | `DB16/include/db_tsdf/tsdf3d_16.hpp:230-233`, `DB16/CMakeLists.txt:8` |
| k | Banco de kernels del paper: 1 600 × 9 261 × (4+1) B = **74,1 MB** (04a lo daba como hipótesis; 04b decía 44 MB) | `DBleg/include/db_tsdf/tsdf3d_32.hpp:31-35` |
| l | Solo la rama `db_tsdf_16` tiene fichero `LICENSE` (MIT). `db_tsdf_32` y `legacy` no lo traen: se pueden ejecutar como oráculo, **no copiar** | `ls` de los tres clones (2026-11-12) |
| m | El paper dice que con vóxeles gruesos «solo se integra el primer retorno por vóxel»; en el código publicado no hay ese filtro (solo se evita la escritura si la máscara no cambia) | paper §IV-B; `grep` sin resultados en las tres ramas; `DB16/include/db_tsdf/tsdf3d_16.hpp:238` |

---

## 2. Pregunta 1 — qué significa «reducir bits»

### 2.1 La discrepancia, resuelta

| | Paper (arXiv v1) | Rama `legacy` | Rama `db_tsdf_32` | Rama `db_tsdf_16` (por defecto) |
|---|---|---|---|---|
| Máscara | 32 bits | `uint32_t` | `uint32_t` | **`uint16_t`** |
| Signo | 1 bit | `uint8_t` (bit 0) | `uint8_t` | `uint8_t` |
| Contador | 8 bits | `uint16_t` | `uint8_t` | `uint8_t` |
| Bytes/vóxel | 8 | 8 (`static_assert`) | 8 (2 de relleno) | **4** |
| K | 21 | 21 fijo | 5 / 25 (YAML), 11 (código) | 5 / 7 (YAML), 11 (código) |
| Bins | 40×40 | 40×40 | 360×360 (YAML) | 60×60 (YAML) |
| Código de distancia | texto «L1», Ec. 3 `⌈L2⌉` | `⌈L2⌉` | L1 o rango-L2 | L1 o rango-L2 |
| Rejilla | densa | densa | dos niveles + FIFO | dos niveles + FIFO |
| Tiempo publicado | ~150 ms/scan | — | — | 20–40 ms/scan |

Fuentes **[V]**: paper §III-A, §III-B, Ec. 3 y 7, §IV-B; `DBleg/…/tsdf3d_32.hpp:23-44`;
`DB32/…/grid_32.hpp:26-32`; `DB16/…/grid_16.hpp:27-33`; `DB16/docs/index.html:209-210,283-287`
(«The figures and tables above reflect the 32-bit variant evaluated in the paper… The 16-bit version released in
this repository is a newer, leaner iteration that runs in just 20–40 ms per scan»).

Conclusión: **«32 bits + signo + contador = 8 B» es el peldaño V32 y «16 bits de base» es el peldaño V16, que
ya publicaron los autores.** No hay métricas de calidad de V16 en ningún sitio **[?]**.

### 2.2 Tres hechos que fijan la definición

1. **La máscara es un código termómetro** **[V]**. Siempre vale `(1<<r)−1` (`r` bits bajos a 1;
   `tsdf3d_16.hpp:434`) y `AND` de dos termómetros = termómetro del mínimo (`:236-238`). Una máscara de `W` bits
   tiene `W+1` estados: guarda `log2(W+1)` bits de información (32 → 5,04; 16 → 4,09; 8 → 3,17; 4 → 2,32).
   El nivel `W` (todo a 1) significa «sin tocar / más lejos que el alcance».
2. **`W` acota el kernel útil** **[V script propio, §A.1]**. Una entrada del kernel cuyo nivel es ≥ `W` es todo
   unos: un `AND` que no hace nada. K máximo en el que **ninguna** entrada se desperdicia:

   | `W` | L1 (`\|x\|+\|y\|+\|z\|`) | rango-L2 (YAML publicados) | `⌈L2⌉` (paper) |
   |---|---|---|---|
   | 4 | **3** | 3 | 3 |
   | 8 | **5** | 3 | 9 |
   | 16 | **11** | 5 | 17 |
   | 32 | **21** | 9 | 35 |

   En L1 la regla es `3·R ≤ W−1` con `R = (K−1)/2`. **Los pares de los autores caen justo en ese límite**: paper
   W = 32 ↔ K = 21; valor por defecto del nodo de 16 bits ↔ K = 11 (`DB16/src/db_tsdf_node.cpp:64`) **[I]**: no
   lo dicen, pero coincide en los dos casos.
3. **Signo y contador**: el signo sobra (hallazgo g) y el contador necesita `⌈log2(T+1)⌉` bits (`T` =
   `occ_min_hits`): 1 bit con T = 1 (mai.yaml), 6 con T = 50 (college.yaml). La información real de un vóxel del
   paper son ~11 bits guardados en 64.

### 2.3 Las cuatro lecturas posibles

| Lectura | Qué cambia | Veredicto |
|---|---|---|
| (a) bits de la máscara = niveles de distancia = alcance y K máximo | el algoritmo (alcance, coste K³) | **Eje que define la variante** |
| (b) cuantizar el contador | cuántos impactos se pueden exigir (T máx.) | Consecuencia de formato: 8 bits salvo V4 (4 bits, T ≤ 15) |
| (c) empaquetar varios vóxeles por palabra | memoria y ancho SIMD | Consecuencia de formato: el vóxel es una palabra de `W/4` B; una palabra NEON de 128 bits lleva 2/4/8/16 vóxeles |
| (d) combinación | — | **Recomendada**, con (a) como eje y (b), (c) fijados por peldaño |

**Definición recomendada.** *Variante V`W`* = DB-TSDF con máscara termómetro de `W` bits, `W ∈ {32, 16, 8, 4}`.
Cada vóxel es **un entero sin signo de `W/4` bytes**: bits `[0, W)` máscara; bits `[W, W+c)` contador de
impactos (`c = 8`; `c = 4` en V4); el resto, reservado a 0. «Ocupado» ⟺ `contador == T`. «Reducir bits» =
bajar un peldaño: mitad de bytes por vóxel, mitad de niveles de distancia, kernel máximo sin pérdida 21 → 11 →
5 → 3.

Por qué una palabra por vóxel y no planos separados (SoA): la actualización completa es
`v' = satura((v & KAND) + KADD)`; con el kernel guardado en el mismo formato (unos fuera de la máscara en `KAND`,
un 1 en el campo del contador en `KADD`) el `AND` no toca el contador y la suma no toca la máscara. Un solo flujo
de memoria por punto (una línea de caché en vez de dos) y el mismo código genérico para los cuatro peldaños
(`u8/u16/u32/u64`) **[I]**.

### 2.4 Alternativas registradas (no recomendadas ahora)

| Alternativa | A favor | En contra | Cuándo reconsiderarla |
|---|---|---|---|
| **Distancia en binario + `min`** (4 bits = 15 niveles en 1 B con contador de 4) | misma información que V16 con la memoria de V4; `min` es tan barato como `AND` en ARM/NEON | deja de ser la máscara de DB-TSDF; pierde el truco portable «`AND` de una palabra = varios vóxeles» (útil en Rust sin intrínsecas); otra familia de pruebas | si E-Q2 demuestra que el alcance de V4/V8 no basta **y** la memoria aprieta. Cabría como otro valor del enum de variante sin romper la ABI |
| SoA compacto (V16 a 3 B, V32 a 5 B) | −25 % / −37 % de memoria | dos flujos de memoria; rompe «una palabra por vóxel» | si un mapa 3D a 5 cm no cabe en V16 y no se quiere bajar a V8 |
| Todo `AND` con T = 1 (bit «libre» dentro de la palabra) | un único `AND` por fila, sin suma | un punto ruidoso ocupa para siempre; solo vale T = 1 | optimización interna tras T3, sin tocar el header |

---

## 3. Pregunta 2 — la escalera

### 3.1 Peldaños y presets canónicos

| Peldaño | `W` | Vóxel | K canónico (máx. L1) | Niveles L1 con K canónico | Alcance en el eje | Alcance a 5 cm / 10 cm | Origen |
|---|---|---|---|---|---|---|---|
| **V32** | 32 | `u64`, 8 B | 21 (21) | 0–30 | 10 vóx | 0,50 m / 1,00 m | paper / `legacy` |
| **V16** | 16 | `u32`, 4 B | 7 (11) | 0–9 (0–15 con K = 11) | 3 vóx (5) | 0,15 m / 0,30 m | `db_tsdf_16` (college K = 7, mai K = 5) |
| **V8** | 8 | `u16`, 2 B | 5 (5) | 0–6 | 2 vóx | 0,10 m / 0,20 m | nuevo |
| **V4** | 4 | `u8`, 1 B | 3 (3) | 0–3 | 1 vóx | 0,05 m / 0,10 m | nuevo |

- Valor inicial de la palabra: máscara a unos, contador 0 (`0x0F`, `0x00FF`, `0x0000FFFF`, `0x00000000FFFFFFFF`),
  igual que `allocCell` (`DB16/…/grid_16.hpp:207-210`).
- Sombra por defecto: `shadow_radius = 5` como los YAML (`college.yaml:45`, `mai.yaml:45`); con K ≤ 7 el cubo la
  recorta a medio cubo detrás del impacto (K = 5: 75 de 125 entradas; K = 7: 192 de 343) **[V script §A.1]**.
  `T` por defecto 1 (mai.yaml:42). Ambos se afinan en E-Q1 **[?]**.
- Cada peldaño admite K menores (V16 con K = 5 es el preset mai). Con K mayor que el máximo, parte del kernel
  son `AND` inútiles: V8 + K = 7 (L1) pierde 32 de 343 entradas (9,3 %); V4 + K = 5 (L1), 68 de 125 (54 %).
- Dato sobre los presets publicados **[V script]**: college de 16 bits (K = 7, rango-L2) ya desperdicia 56 de 343
  entradas (16,3 %); college de 32 bits (K = 25, rango-L2), 14 700 de 15 625 (94 %).
- **Modo 2D** (losa de un vóxel de alto, kernel K×K×1, para LaserScan): mismo código con el bucle `z` de una
  vuelta. Equivale exactamente a la rebanada central del 3D con puntos coplanarios **[V simulación §A.3]**, así
  que el oráculo 3D también lo valida. En 2D el límite sin pérdida sube a K = 3 / 7 / 15 / 31 (`2R ≤ W−1`).

### 3.2 Banco de kernels

El original guarda por bin `K³` máscaras + `K³` signos (`DB16/…/tsdf3d_16.hpp:15-19,418-419`). Como la máscara
no depende del bin (hallazgo f), el port guarda **una** tabla de máscaras y, por bin, solo el mapa de bits de la
sombra:

| K, `W`, bins | Original | Compacto (`K³·W/8 + bins·⌈K³/8⌉`) |
|---|---|---|
| 3, 4, 60×60 | 190 KiB | 14 KiB |
| 5, 8, 60×60 | 879 KiB | 56 KiB |
| 7, 16, 60×60 | 3,5 MiB | 152 KiB |
| 11, 16, 40×40 | 6,1 MiB | 264 KiB |
| 21, 32, 40×40 | 70,7 MiB | 1,8 MiB |

**[V aritmética, §A.2]**. La tabla de máscaras de K = 5 en V8 son 250 B: vive siempre en L1 (32 KiB por núcleo,
`docs/14:51` [A]).

### 3.3 Memoria para mapas realistas

Supuestos **[I]**: celdas de 1 m³ como el original (`grid_16.hpp:126-142`); el port reserva **solo las celdas que
toca el kernel** (el original reserva las 27 vecinas de cada punto, `tsdf3d_16.hpp:203-210`); origen Z desplazado
para que suelo y techo no caigan en un borde de celda. En interior 3D, suelo y techo tocan casi todas las
columnas: la rejilla de dos niveles ahorra poco.

| Escenario | Celdas ocupadas [I] | Vóxeles (5 cm / 10 cm) | V32 | V16 | V8 | V4 |
|---|---|---|---|---|---|---|
| Casa 10×8×2,5 m, 3D, **5 cm** | 240 (≈ todas las de 10×8×3) | 1,92 M | 14,6 MiB | 7,3 MiB | 3,7 MiB | 1,8 MiB |
| Casa, 3D, **10 cm** | 240 | 0,24 M | 1,8 MiB | 0,9 MiB | 0,46 MiB | 0,23 MiB |
| Casa con la política original (27 vecinas), 5 cm | ~600 | 4,8 M | 36,6 MiB | 18,3 MiB | 9,2 MiB | 4,6 MiB |
| Oficina 30×30×3 m, 3D, **5 cm** | ~2 250 de 2 700 | 18 M | **137 MiB ✗** | **68,7 MiB ✗** | 34,3 MiB | 17,2 MiB |
| Oficina, 3D, **10 cm** | ~2 250 | 2,25 M | 17,2 MiB | 8,6 MiB | 4,3 MiB | 2,1 MiB |
| Casa, LaserScan 2D, 5 cm | ~60 de 80 columnas | 24 000 | 0,18 MiB | 0,09 MiB | 0,05 MiB | 0,02 MiB |
| Oficina, LaserScan 2D, 5 cm | ~400 de 900 | 160 000 | 1,2 MiB | 0,6 MiB | 0,3 MiB | 0,15 MiB |

✗ = por encima del tope propuesto de 64 MiB para el mapa (04b §2.2). Índice de celdas: 2 B por m³ del volumen
(oficina: 5,4 KiB). **Lectura**: la memoria solo decide el peldaño en **3D a 5 cm con mapas de tamaño oficina**;
a 10 cm o en 2D cualquier peldaño cabe sobrado. La memoria libre real con Godot cargado está **Por medir** (M2).

### 3.4 Coste por scan

Modelo **[I]** (el de 04b §2.1, sin cambios): ciclos por punto = `C_fijo + K^d · c`, con `c` = 12–40 ciclos por
vóxel en escalar (12 todo en L1; 40 con fallos de caché) y `C_fijo` = 300–700 (bin con `atan2f`/`asinf`,
búsqueda de celda, arranque de filas) en 3D o 100–200 en 2D (el bin sale del ángulo del rayo, sin libm).
NEON por filas: grupos de 16 B (`AND` + suma saturada + `min`, 3 operaciones más carga y guardado), 15–45 ciclos
por grupo.

| Peldaño / K | Ops por punto (K³) | Ciclos/punto escalar | Ciclos/punto NEON | Ganancia NEON | Bytes tocados por punto |
|---|---|---|---|---|---|
| V4 / 3 | 27 | 624–1 780 | 435–1 105 | ×1,4–1,6 | 27 |
| V8 / 5 | 125 | 1 800–5 700 | 675–1 825 | ×2,7–3,1 | 250 |
| V16 / 7 | 343 | 4 416–14 420 | 1 770–5 110 | ×2,5–2,8 | 1 372 |
| V16 / 11 | 1 331 | 16 272–53 940 | 5 745–17 035 | ×2,8–3,2 | 5 324 |
| V32 / 21 | 9 261 | 111 k–371 k | 73 k–219 k | ×1,5–1,7 | 74 088 |

Tiempo por scan a **444 MHz**, escalar (a 333 MHz, ×1,33) **[I, §A.2]**:

| Entrada | V4/K3 | V8/K5 | V16/K7 | V16/K11 | V32/K21 |
|---|---|---|---|---|---|
| LaserScan 180 rayos, **2D** | 0,1–0,2 ms | 0,2–0,5 ms | 0,3–0,9 ms | 0,6–2,0 ms | 2,2–7,2 ms |
| LaserScan 180 rayos, 3D | 0,3–0,7 ms | 0,7–2,3 ms | 1,8–5,9 ms | 6,6–22 ms | 45–150 ms |
| Nube 1 500 puntos | 2–6 ms | 6–19 ms | 15–49 ms | 55–182 ms | 0,4–1,3 s |
| Nube 3 000 puntos | 4–12 ms | 12–39 ms | 30–97 ms | 110–364 ms | 0,75–2,5 s |

Carga sostenida (porcentaje de un núcleo a 444 MHz):

| Puntos/s | K = 3 | K = 5 | K = 7 | K = 11 | K = 21 |
|---|---|---|---|---|---|
| 1 800 (180 rayos × 10 Hz) | 0,3–0,7 % | 0,7–2,3 % | 1,8–5,8 % | 6,6–22 % | 45–150 % (3D) |
| 4 000 (techo prudente por XRCE) | 0,6–1,6 % | 1,6–5,1 % | 4–13 % | 15–49 % | 100–334 % |
| 15 000 (3 000 × 5 Hz) | 2–6 % | 6–19 % | 15–49 % | 55–182 % | ✗ |

**Lecturas [I]:**
- Con la entrada que deja pasar XRCE (≤ ~200 datagramas/s y ≤ 100 KB/s en total, `docs/27:42-43`; 76–78 puntos
  por datagrama, `docs/27:65,102`), **el cuello es la red, no la CPU**, mientras K ≤ 7.
- Con K = 3 manda el coste fijo por punto (300–700 ciclos), no el kernel: ahí importa más quitar `atan2f` que
  vectorizar.
- NEON gana por filas de 16 B; en V32 (2 vóxeles por grupo) gana poco. La plantilla compila con `-Os` y
  `-ftree-vectorize` (`tools/build-c-pic.sh:22-23`): que GCC vectorice el bucle entero sin intrínsecas está
  **Por medir** con `objdump` (no hace falta hardware).
- V32/K21 en 3D no es tiempo real; **en 2D sí** (2–7 ms por scan): la escalera completa se puede enseñar con
  LaserScan.

### 3.5 Calidad esperada

- **El paper no tiene ningún estudio de K, de bits ni de truncamiento [V]**. Datos que sí da (V32, K = 21):
  Mai City (tolerancia 10 cm) Acc 1,7 cm / Comp 4,6 cm / Chamfer-L1 3,1 cm / Recall 93,6 % / **F-score 96,6 %**;
  Newer College (20 cm) 9,1 / 10,7 / 9,9 cm / 92,4 % / **91,3 %**; con decimado 2: 11,4 / 13,1 / 12,3 cm /
  92,7 % / **87,4 %** (paper tablas I y II, §IV-B). De V16 no hay métricas **[?]**.
- **La malla evaluada sale de la ocupación, no de la máscara** (hallazgo h). Consecuencia **[I]**: bajar `W` por
  sí solo **no** debería mover F-score ni Chamfer; los mueve lo que cambia con el peldaño: K (recorta la sombra),
  `T`, bins, resolución y decimado de la entrada. El propio paper explica que la sombra semiesférica sirve para
  confirmar ocupación con pocos scans (§III-B): con K = 3 la sombra es de un vóxel y, con nube decimada, es de
  esperar **peor completitud** (huecos) y algo mejor exactitud (paredes menos gruesas) **[?]**.
- **Lo que `W` sí cambia es el campo de distancia**: alcance (tabla 3.1) y forma. L1 sobreestima la distancia
  euclídea hasta ×√3 en las diagonales; rango-L2 es más fino cerca de la superficie pero no lineal.
- **Estrechar no degrada lo ya integrado**: truncar un mapa V16 a 8 o 4 bits da **exactamente** el mapa que se
  habría obtenido integrando en V8/V4 con el mismo K **[V simulación §A.3: 0 vóxeles distintos en 24 casos]**.

Experimentos propuestos (los dos **en el PC**, sin Vita):

| Id | Qué | Cómo | Verde |
|---|---|---|---|
| **E-Q1** | F-score / Chamfer por peldaño | MaiCity secuencia 01 (`DB16/README.md:80-84`), nube decimada como lo haría el relay (vóxel 10–20 cm), integrada con el módulo propio en host para V32/V16/V8/V4 × {5, 10 cm} × T {1, 2, 3}; nube de vóxeles ocupados con nivel ≤ 1 (criterio de `exportGridToPCD`, `grid_16.hpp:283-285`) contra la malla de referencia del dataset; fila de control = oráculo original con el preset mai | tabla rellena; un peldaño es «apto» si pierde ≤ 2 puntos de F-score frente a V16/K7 a igual resolución |
| **E-Q2** | Error del campo de distancia | mismo mapa; distancia exacta por fuerza bruta a los vóxeles ocupados; error medio de `nivel·res` dentro de la banda, por peldaño y por código (L1 / rango-L2 / `⌈L2⌉`) | tabla rellena; decide el código de distancia por defecto |

---

## 4. Pregunta 3 — interfaz común y cambio en caliente

### 4.1 Decisiones de forma

| Decisión | Elección | Motivo |
|---|---|---|
| Nombre | `modules/db-tsdf/`, `include/db_tsdf.h`, prefijo `dbtsdf_` | deja claro el origen (04b proponía `tsdf-local`); README con atribución MIT y copia de `LICENSE` de `db_tsdf_16` |
| Variantes | **todas en la misma biblioteca**, elegidas por `cfg.mask_bits` | cambio en caliente y comparaciones A/B con dos handles a la vez |
| Handle | opaco; el formato del vóxel **no** aparece en el header | permite añadir variantes (p. ej. binaria) sin romper la ABI |
| Memoria | arena del llamador: `required_size` + `create(backing, len, …)`, sin `malloc` | convención del repo (`modules/tf-tree/include/tf_tree.h:53-58`, `modules/msg-ring/include/msg_ring.h:47-62`) |
| Hilos, reloj, E/S | **ninguno dentro del módulo** | paridad determinista y `#![no_std]` limpio; el hilo vive en la envoltura de Godot (§5.4) |
| Configuración | enteros (`res_mm`, límites en metros enteros) | el original ya trunca los límites a metros (`grid_16.hpp:118-123`) y exige que la resolución divida 1 m (`:137`); comparar configuraciones sin `float` |
| Compatibilidad | `abi` y `struct_size` al principio de la config | añadir campos sin romper a quien enlazó contra el header viejo |

### 4.2 Header (borrador de firmas)

```c
/* db_tsdf.h — contrato C-ABI del módulo dual `db-tsdf` (borrador W3) */
#define DBTSDF_ABI 1
typedef enum { DBTSDF_OK = 0, DBTSDF_ERR_INVALID_ARG = -1, DBTSDF_ERR_BAD_CONFIG = -2,
               DBTSDF_ERR_NO_MEMORY = -3, DBTSDF_ERR_NEEDS_RESET = -4, DBTSDF_ERR_UNSUPPORTED = -5,
               DBTSDF_ERR_BUF_SMALL = -6, DBTSDF_ERR_OUT_OF_MAP = -7 } dbtsdf_status;
typedef enum { DBTSDF_DIST_L1 = 0, DBTSDF_DIST_L2_RANK = 1, DBTSDF_DIST_L2_CEIL = 2 } dbtsdf_dist_mode;

typedef struct {
    uint32_t abi, struct_size;
    int16_t  min_m[3], max_m[3];   /* límites en metros enteros                         */
    uint16_t res_mm;               /* 50, 100, 200, 250…: debe dividir 1000              */
    uint8_t  dims;                 /* 3 = volumen; 2 = losa de un vóxel (LaserScan)      */
    uint8_t  mask_bits;            /* LA VARIANTE: 4, 8, 16 o 32                         */
    uint8_t  kernel_size;          /* impar, 1..21                                       */
    uint8_t  shadow_radius;        /* vóxeles                                            */
    uint8_t  dist_mode;            /* dbtsdf_dist_mode                                   */
    uint8_t  occ_min_hits;         /* T: 1..255 (V4: 1..15)                              */
    uint16_t bins_az, bins_el;
    uint32_t max_cells;            /* 0 = las que quepan en el arena                     */
    uint32_t flags;                /* reservado, 0                                       */
} dbtsdf_config;

typedef struct dbtsdf dbtsdf;      /* opaco */

uint32_t dbtsdf_abi_version(void);
uint32_t dbtsdf_variants_supported(void);                       /* bit W a 1 si está compilada */
int      dbtsdf_config_preset(dbtsdf_config *cfg, uint8_t mask_bits, uint8_t dims, uint16_t res_mm);
int      dbtsdf_config_check(const dbtsdf_config *cfg, uint32_t *bad_field);
size_t   dbtsdf_required_size(const dbtsdf_config *cfg, uint32_t cells);
dbtsdf  *dbtsdf_create(void *backing, size_t backing_len, const dbtsdf_config *cfg, int *status);
void     dbtsdf_clear(dbtsdf *t);                               /* reinicia el mapa: epoch++ */
int      dbtsdf_get_config(const dbtsdf *t, dbtsdf_config *out);

int      dbtsdf_integrate_points(dbtsdf *t, const float *xyz, uint32_t n,
                                 const float origin[3], dbtsdf_scan_stats *acc);
int      dbtsdf_integrate_scan2d(dbtsdf *t, const int16_t *range_cm, uint32_t n, float angle_min,
                                 float angle_inc, const float pose_xyyaw[3], dbtsdf_scan_stats *acc);

int      dbtsdf_plan(const dbtsdf *t, const dbtsdf_config *next, dbtsdf_swap_report *out);
int      dbtsdf_reconfigure(dbtsdf *t, const dbtsdf_config *next, uint8_t policy, dbtsdf_swap_report *out);

int      dbtsdf_query(const dbtsdf *t, const float p[3], dbtsdf_voxel *out);  /* nivel, lejos, ocupado, hits */
int      dbtsdf_slice_xy(const dbtsdf *t, const dbtsdf_slice_req *req, uint8_t *out, size_t out_len);
int      dbtsdf_extract_occupied(const dbtsdf *t, uint32_t *cursor, int16_t *xyz_vox, uint32_t cap, uint32_t *n);
int      dbtsdf_dump(const dbtsdf *t, uint32_t *cursor, dbtsdf_dump_rec *out, uint32_t cap, uint32_t *n);
uint64_t dbtsdf_hash(const dbtsdf *t, uint8_t level_cap);       /* huella canónica del mapa */
int      dbtsdf_get_stats(const dbtsdf *t, dbtsdf_stats *out);
```

Structs auxiliares (resumen):
- `dbtsdf_scan_stats` (acumulable): puntos recibidos / integrados / descartados por límites / por NaN, celdas
  reservadas y recicladas, **vóxeles cambiados** (sirve para decidir si hay que redibujar).
- `dbtsdf_swap_report`: `changed` (bits `DBTSDF_CHG_VARIANT|KERNEL|SHADOW|BINS|HITS|DIST_MODE|RES|BOUNDS|DIMS|CELLS`),
  `effect` (`KEPT`, `CONVERTED_EXACT`, `CONVERTED_LOSSY`, `RESET`), `mixed_kernel`, `band_lost`,
  `cells_before/after/evicted`, `capacity_cells`, `bytes_per_cell`, `required_size`, `epoch`.
- `dbtsdf_stats`: `epoch` (sube en cada reinicio), `config_gen` (sube en cada reconfiguración), celdas usadas y
  capacidad, recicladas, scans, puntos, bits por vóxel, bytes de arena usados.
- `dbtsdf_slice_req`: origen y tamaño de la imagen, mm por píxel, banda Z, tipo (`OCC`, `LEVEL`, `HITS`).
- `dbtsdf_hash(t, level_cap)`: FNV-1a de 64 bits sobre `(x, y, z, min(nivel, level_cap), hits)` de los vóxeles
  **distintos del valor inicial**, en orden canónico. No depende del formato ni de qué celdas se reservaron; con
  `level_cap` se comparan variantes distintas.

Reglas de contrato: un handle lo usa **un hilo a la vez**; el resultado no depende de cómo se trocee el array de
puntos ni del orden de los puntos **[V simulación §A.3]**; puntos NaN/Inf o fuera de límites se cuentan y se
saltan (el original salta los que no dejan margen, `tsdf3d_16.hpp:219-221`); nunca se escribe en un centinela
compartido (hallazgo i); bucles de celda con `uint32_t` (fallo de `grid_16.hpp:207`).

### 4.3 Códigos de error

| Código | Cuándo | Qué hace la app |
|---|---|---|
| `INVALID_ARG` | puntero nulo, arena sin alinear a 8, `n` imposible | error de programación: registrar |
| `BAD_CONFIG` | `res_mm` no divide 1000, K par o > 21, `mask_bits` no válido, T > 15 en V4, límites vacíos; `bad_field` dice cuál | marcar el campo en la UI |
| `NO_MEMORY` | el arena no da para esa config; el informe trae `required_size` | proponer peldaño inferior o resolución mayor |
| `NEEDS_RESET` | `reconfigure` con política `CONVERT` y el cambio obliga a reiniciar; **no se toca nada** | diálogo «esto borra el mapa» |
| `UNSUPPORTED` | variante o modo no compilado en esta build | ocultar la opción (`variants_supported`) |
| `BUF_SMALL` | salida truncada en `slice`/`extract`/`dump` | reintentar con el tamaño indicado |
| `OUT_OF_MAP` | consulta fuera de los límites | tratar como desconocido |

### 4.4 Qué cambios reinician el mapa

| Cambio | Efecto | Detalle |
|---|---|---|
| `mask_bits` a **menos** (16→8, 8→4, 16→4…) | `CONVERTED_EXACT` | truncar la máscara: `m & ((1<<W')−1)`; idéntico a haber integrado en V`W'` con el mismo K **[V §A.3]**. En el sitio (la celda encoge); cabe el doble de celdas |
| `mask_bits` a **más** (8→16…) | `CONVERTED_LOSSY`, `band_lost = 1` | niveles < `W` se conservan; «lejos» sigue siendo «lejos». Falta la banda `[W_viejo, W_nuevo)` hasta que se vuelva a observar. **Nunca subestima** la distancia **[V §A.3]**: con K = 7 L1 difiere el 3,9 % de los vóxeles tocados; con K = 11, el 30 %. Si no caben todas las celdas se reciclan las más antiguas (`cells_evicted`) |
| `occ_min_hits` a menos | `CONVERTED_EXACT` | `hits' = min(hits, T')`; ocupado ⟺ `hits ≥ T'` |
| `occ_min_hits` a más | `CONVERTED_LOSSY` (conservador) | los saturados en `T` necesitan `T'−T` impactos más para volver a ser «ocupado» |
| `kernel_size`, `shadow_radius`, `bins_*` | `KEPT`, `mixed_kernel = 1` | se regenera el banco; el mapa sigue siendo válido (el `AND` solo baja) pero mezcla zonas integradas con el kernel viejo |
| `dist_mode` | **`RESET`** | el significado del nivel cambia (L1 ≠ rango-L2 ≠ `⌈L2⌉`): mezclar no tiene sentido |
| `res_mm`, `dims`, límites | **`RESET`** (v1) | cambia la rejilla. v2 opcional: reducir 2:1 con pérdida |
| `max_cells` a menos | `KEPT` + reciclado | se sueltan las celdas más antiguas |
| Filtros de entrada (decimado, rango, Hz) | — | no son del módulo |

**Cómo se avisa a la UI** (tres mecanismos, de más a menos inmediato):
1. `dbtsdf_plan(t, &next, &rep)` **antes** de aplicar: la UI enseña «se conserva / se convierte con pérdida /
   se reinicia», bytes necesarios y capacidad en celdas, y pide confirmación si `effect == RESET`.
2. `dbtsdf_reconfigure` devuelve el mismo informe ya aplicado; la envoltura lo publica como señal de Godot
   (`variant_changed(informe)` y `map_reset(motivo)`), emitida en el hilo principal.
3. `epoch` y `config_gen` en `dbtsdf_stats`: cualquier consumidor (textura cenital, caché) compara y se invalida
   solo, aunque se haya perdido la señal.

**Recuperar un mapa tras un `RESET`** (envoltura, no módulo): guardar los últimos N scans compactos (180 rayos ×
2 B + pose ≈ 370 B; 300 scans ≈ 110 KiB) y **reintegrarlos** con la nueva config, a trozos y con presupuesto.
Para LaserScan con K ≤ 7 son < 0,3 s **[I]**. Hace uniforme cualquier cambio y es exacto dentro de la ventana.

### 4.5 Paridad dual y oráculo

Encaje con la regla del repo (`docs/03:8-14,68-79`; `skills/vita-dual-module/SKILL.md`; `tools/run-parity-tests.sh:73-93`):

```
modules/db-tsdf/
├── include/db_tsdf.h
├── impl-c/db_tsdf.c            # C11; un núcleo genérico instanciado 4 veces (u8/u16/u32/u64)
├── impl-rust/src/lib.rs        # #![no_std], rlib; genéricos o macro_rules! (explicar en docs/rust/)
├── tests/parity_test.c         # la MISMA batería contra C y contra Rust
├── tests/golden/*.h            # huellas doradas generadas con el oráculo
├── tests/oracle/               # Dockerfile fijado a 663c5a8 + oracle_dump.cpp (solo PC, docker)
└── README.md
```

Tres niveles de verdad:

| Nivel | Qué compara | Dónde | Criterio |
|---|---|---|---|
| **P1** C ↔ Rust | la misma batería con huellas esperadas embebidas; propiedades: orden de los puntos, troceo, estrechar = integrar estrecho, ensanchar nunca subestima, 2D = rebanada 3D, FIFO determinista, casos límite (NULL, `n = 0`, NaN, fuera de límites, arena pequeña o mal alineada); ASan/UBSan en C | laptop y PC (`tools/run-parity-tests.sh db-tsdf`) | verde en las dos |
| **P2** módulo ↔ **original** | volcado canónico `(x, y, z, nivel, ocupado, hits)` de V16 (y V32 con `db_tsdf_32`) para L1 y rango-L2, K ∈ {3, 5, 7, 11} | PC con docker; el resultado (huellas + volcados pequeños) se versiona, así la laptop no necesita el oráculo | **igualdad exacta** en escenas canónicas; en datos reales, porcentaje medido (se espera ≥ 99,99 % [I]) con cada diferencia clasificada |
| **P3** Vita ↔ host | `dbtsdf_hash` de la escena embebida en la consola, builds C y Rust | hardware (T3) | misma huella que en host |

Condiciones para que P2 sea exacto (**contrato numérico**, detalle en §A.4):
- Oráculo compilado **con nuestros flags**: `-O2 -ffp-contract=off`, sin `-march=native -mfma` (hallazgo j) y sin
  `-fopenmp` (el `#pragma` se ignora ⇒ un hilo; con 16 hilos `hits` no es determinista, `tsdf3d_16.hpp:215-247`).
- `git checkout 663c5a8` dentro de la imagen (el `Dockerfile` original clona HEAD, `DB16/Dockerfile:96`).
- Escenas canónicas: puntos en centros de vóxel, direcciones lejos del borde de un bin, límites con el margen que
  pide el original (`isIntoGrid`, `tsdf3d_16.hpp:108-111,219-221`), `max_cells` grande (sin reciclado).
- El bin de dirección se calcula con **la misma expresión** que el original, incluidas sus promociones a `double`
  por `M_PI` (`tsdf3d_16.hpp:335-348`); en Rust, `atan2f/asinf/sqrtf` de la libm de C por `extern "C"`, como hace
  `viz-math` (`modules/viz-math/README.md:26-28`).
- Diferencias **queridas** y documentadas: reserva de celdas solo donde toca el kernel; voxelizado entero
  (`floor((p−min)·n)` y después `±R`) en vez de acumular `float`; sin escritura en `_garbage`; contador sin bit
  de signo (el volcado sintetiza `ocupado = hits == T`).

Coste del oráculo: imagen con ROS Humble + PCL + VTK (`DB16/Dockerfile:8,45-58`), varios GB; se construye una vez
en el PC. Alternativa si pesa demasiado: compilar solo `tsdf3d_16.hpp` + `grid_16.hpp` con cabeceras PCL/VTK del
sistema base `ubuntu:22.04` (`libpcl-dev`, `libvtk9-dev`, `libeigen3-dev`), sin ROS.

---

## 5. Pregunta 4 — entrada de datos, escalado y convivencia con la teleop

### 5.1 Lo que deja pasar la red (de `docs/27`, ya integrado)

- Un mensaje *best effort* cabe si su CDR ocupa ≤ **488 B**; la recepción fiable llega a ~7,5 KiB
  (`docs/27:10,33`; `tablero.json`, revisión de la oleada 1). Presupuesto de diseño: **≤ 100 KB/s y ≤ ~200
  datagramas/s** en total (`docs/27:42-43`) **[I]**.
- Ya existe `vita_relay` en el PC (`docker/scripts/vita_relay.py`, `docker/vita-ros.sh:69`):
  `/vita/scan_compacto` (Int16MultiArray, 10 Hz, `[seq, ang_min_cdeg, inc_cdeg, n, r0..]` en cm, n ≤ 180;
  `vita_relay.py:10,35`), `/vita/pose2d` (30 Hz, `:11`) y `/vita/mapa_tesela` (mapa hecho **en el PC**: es la
  arquitectura B de 04b, ya disponible como oráculo visual).
- Un LaserScan crudo de 360 rayos son 1 504 B: no cabe en *best effort* (`docs/27:57`).

### 5.2 Formatos de entrada para el TSDF (propuesta; módulo `tsdf` del relay)

| Topic | Tipo | Contenido | Tamaño | Por qué |
|---|---|---|---|---|
| `/vita/tsdf_scan` | Int16MultiArray, BE | `[seq, x_cm, y_cm, z_cm, yaw_cdeg, ang_min_cdeg, inc_cdeg, n, r0..r179]` | 188 int16 = 392 B | **pose del sensor en el mismo mensaje y del mismo instante** (el relay la saca de tf2 en el PC). Con `scan_compacto` + `pose2d` sueltos, a 1 rad/s y 3 m el desfase de hasta 33 ms son ~10 cm: uno o dos vóxeles de emborronado **[I]** |
| `/vita/tsdf_nube` | Int16MultiArray, BE | `[seq, trozo, n_trozos, ox_cm, oy_cm, oz_cm, n, x0,y0,z0, …]` ya en el marco del mapa | ≤ 76 puntos por datagrama | nube voxelizada en el PC (10–20 cm); perder un trozo = perder 76 puntos, el mapa lo tolera |
| `/vita/tsdf_ack` (Vita → PC) | Float32MultiArray, BE | `[seq, us_integración, epoch, celdas, descartados]` | 36 B | medir latencia con el reloj del PC y vigilar el mapa desde ROS |

La Vita no necesita TF con historial (`tf-tree` solo guarda el último valor, `modules/tf-tree/include/tf_tree.h:9-11`).
El módulo recibe `float xyz` o `(rangos, pose)`: **el formato de red se decodifica en la envoltura**, no en el
módulo dual.

Camino alternativo si el techo de XRCE resulta bajo para nubes (decisión del usuario, va contra «todo por ROS»):
un socket UDP propio con `net-udp` (hay 4, `modules/net-udp/include/net_udp.h:31`) leído por el hilo de mapeo,
con datagramas de ~1 400 B. Solo si T5 lo exige **[?]**.

### 5.3 Datos reproducibles

| Conjunto | Origen | Uso |
|---|---|---|
| **A (2D)** | TurtleBot3 en la estación (`docker/vita-ros.sh sim-tb3`, `docker/README.md:47`), 60 s; se graba el rosbag **y** la salida del relay en un fichero (`300 scans × 392 B ≈ 118 KiB`) | (1) pruebas en host con huella por peldaño; (2) **banco embebido** en la Vita, sin red (CPU pura, comprueba la huella); (3) `ros2 bag play` → relay → Vita para latencia de punta a punta |
| **B (3D)** | MaiCity secuencia 01 (script del original, ~215 MB, `DB16/README.md:80-84`), decimada a 1–3 k puntos/scan con poses de referencia | E-Q1/E-Q2 en host; banco 3D en la Vita |
| Sintético | sala analítica + PRNG con semilla, generado en el propio banco | microbench T3 sin ficheros |

### 5.4 Convivencia con la teleop

Hechos del port **[V]**: Godot usa un hilo para todo (`WorkerThreadPool` = 0, W1 P1b:
`toolchains/godot4-vita/engine/core/object/worker_thread_pool.cpp:848-857`); el único hilo aparte es el de audio,
creado con la clase `Thread` de Godot y con afinidad por `sceKernelChangeThreadCpuAffinityMask`
(`…/platform/vita/audio_driver_vita.cpp:127-143`). La tabla de símbolos que el cargador ofrece al `.so` **sí**
tiene `pthread_create`, `pthread_join`, `nanosleep`, `clock_gettime`, `memalign`, `sceKernelGetThreadId` y
`sceKernelChangeThreadCpuAffinityMask`, y **no** tiene `sceKernelCreateThread`, `sceKernelChangeThreadPriority`,
`sceKernelDelayThread`, `pthread_cond_wait`, `sem_wait` ni `sceKernelAllocMemBlock`
(`…/platform/vita/loader/default_dynlib.c:1233,1288`; `grep` del 2026-11-11). Medido en G7c: ~17 ms por
fotograma con render ≈ 11,6 ms (`docs/06:61`).

Consecuencias de diseño:

| Fase | Dónde se integra | Para qué entrada | Riesgo |
|---|---|---|---|
| **3a** | **hilo principal**, a trozos, con presupuesto por fotograma (1,5 ms por defecto) | LaserScan 2D: 0,1–7 ms por scan según peldaño (§3.4) | mínimo: sin hilos nuevos |
| **3b** | **hilo propio** con `Thread` de Godot (pthread), afinidad a `USER_2`, espera con `nanosleep` | nube 3D, K ≥ 7, V32 | viabilidad **Por medir** (M3); la prioridad baja exige añadir `sceKernelChangeThreadPriority` a la tabla del cargador (`godot/loader-patches/`) |

- **El módulo no sabe de tiempo**: la envoltura trocea (`64–256` puntos por llamada) y mira el reloj entre
  trozos. El resultado no cambia con el troceo.
- **Colas sin cerrojos**: `msg-ring` (SPSC, `modules/msg-ring/include/msg_ring.h:5-9`) para scans (principal →
  mapeo) y para eventos (mapeo → principal); la imagen cenital con doble búfer e índice atómico. Nada de `mutex`
  ni variables de condición (no están en la tabla del cargador y el `std::mutex` ya dio un fallo en el port, W1 P1b).
- **Memoria**: un único `memalign` al arrancar (16 MiB por defecto, configurable), antes de cargar escenas pesadas.
- **Vista**: imagen cenital `L8` de ≤ 128×128 actualizada a ≤ 2 Hz y solo si `voxels_changed > 0`
  (`ImageTexture.update` recrea la textura entera, W7: `…/platform/vita/rasterizer_gxm_vita.cpp:81-83`); el 3D del
  port no dibuja puntos, líneas ni MultiMesh (W7). Coste **Por medir** (M5).
- **Presupuesto por fotograma (hilo principal)**: ≤ 1 ms para sacar mensajes y copiarlos; ≤ 1,5 ms de integración
  en 3a; refresco de textura en un fotograma sin integración.
- **Gobernador y vigilante**:
  1. Scan en curso > 2 × periodo ⇒ se aborta entre trozos, `scans_abortados++`.
  2. Tres abortos seguidos, o tiempo de integración > 50 % del periodo ⇒ **bajar un escalón** (primero decimar ×2,
     luego K, luego peldaño) y avisar en el HUD.
  3. FPS < 30 durante 1 s con el mapeo activo ⇒ pausar vista, luego integración; la teleop no se toca.
  4. Cola llena ⇒ se descarta el scan nuevo (política de `msg-ring`) y se cuenta.
  5. Latido del hilo de mapeo cada trozo; sin latido en 1 s ⇒ se marca caído y se vuelve a 3a.
  6. Interruptor en la UI: mapeo apagado = cero coste.
- **Criterio de no regresión**: `/cmd_vel` mantiene su frecuencia y los FPS no bajan más de un 5 % respecto a la
  misma escena con el mapeo apagado (M7).

### 5.5 Ruta de escalado y puertas

Sustituye y afina T0–T8 de 04b §6:

| Puerta | Dónde | Qué demuestra | Verde |
|---|---|---|---|
| **T0** | PC, docker | oráculo fijado a `663c5a8`, un hilo, flags propios; volcados dorados | misma huella en dos ejecuciones |
| **T1** | PC | microbench x86 del original con K = 5/7/11/21 | tabla ciclos/vóxel; calibra §3.4 |
| **T2** | laptop/PC | módulo dual **V16 escalar**: P1 y P2 exactos (L1 y rango-L2) | `tools/run-parity-tests.sh db-tsdf` |
| **T2b** | laptop/PC | V8, V4, V32, modo 2D, `plan`/`reconfigure`, propiedades | idem + huellas cruzadas con `level_cap` |
| **EQ** | PC | E-Q1 y E-Q2 | tablas de calidad por peldaño |
| **T3** | **Vita**, sin red | banco embebido: ms/scan por peldaño × K × 2D/3D × C/Rust × 333/444 MHz; huella = host | números en la bitácora; **decide** si hace falta NEON y si 3b merece la pena |
| **T4** | PC | relay `tsdf` (scan + pose síncronos, nube troceada) + rosbag A | `ros2 topic hz/bw` dentro del presupuesto |
| **T5** | Vita + agente | recepción sin integrar: Hz, pérdidas, latencia | ≥ 90 % de scans a 10 Hz; pérdidas de trozos anotadas |
| **T6** | Vita | mapa del PC (`/vita/mapa_tesela`) dibujado: referencia visual | se ve coherente con RViz |
| **T7** | Vita | **3a**: LaserScan 2D integrado en la consola, vista cenital, cambio en caliente V4↔V8↔V16↔V32 con aviso | mapa ≈ T6; M7 en verde |
| **T8** | Vita | **3b**: hilo propio + nube 3D decimada; 10 cm → 5 cm; gobernador | FPS, ms/scan y latencia medidos; M7 en verde |
| **T9** | docs | tabla de la escalera **medida** y ADR cerrado | hipótesis del §0.7 confirmada o refutada |

---

## 6. Pregunta 5 — pre-mortem de la Fase 3

«Han pasado tres meses y falló. ¿Por qué?»

| # | Causa | Señal temprana | Mitigación |
|---|---|---|---|
| 1 | **La matriz explotó**: 4 variantes × C y Rust × 2D/3D × 3 códigos de distancia × NEON × conversión. La paridad pasa semanas en rojo | más de un fichero fuente por variante; pruebas que solo cubren V16 | un **núcleo genérico** parametrizado por tipo de palabra (las variantes son datos, no código); T2 solo V16 escalar; nada de NEON ni de `⌈L2⌉` hasta que T3 lo pida; header congelado antes de implementar (regla de la skill) |
| 2 | **Persecución del bit exacto contra el oráculo**: `float` acumulado, FMA, bins en el borde, OpenMP, celdas distintas | P2 «casi» verde con decenas de vóxeles distintos sin explicar | contrato numérico del §4.5: igualdad exacta **solo** en escenas canónicas; en datos reales, umbral medido y diferencias clasificadas; oráculo con nuestros flags y un hilo; volcados dorados versionados (si el repo ajeno desaparece o reescribe la rama, seguimos teniendo la referencia) |
| 3 | **La entrada no llega**: desfase pose–scan, pérdidas, latencia WiFi de 40–190 ms, techo de datagramas | mapa emborronado en los giros; `be_dropped` creciendo | pose dentro del mensaje del scan; T5 **antes** de escribir la vista; banco embebido para separar red de CPU; UDP propio solo como último recurso |
| 4 | **La teleop empeoró o el hilo tumbó el port** | tirones al mover el robot; cuelgues al salir | 3a sin hilos (LaserScan cuesta < 1 ms); hilo solo tras M3 y con el patrón que ya funciona (audio); sin cerrojos; gobernador; interruptor; M7 obligatoria en cada puerta |
| 5 | **La escalera no enseña nada**: a escala Vita todos los peldaños van igual de rápido y caben igual; o V4 es inservible | T3 con diferencias < 20 % entre peldaños | hipótesis pre-registrada (§0.7): la escalera se justifica por memoria y alcance, no por FPS; T1/T3/EQ **antes** de construir la UI de cambio en caliente; si no hay diferencia útil, plegar a dos peldaños (V16 y V4) |

Otras causas vigiladas: memoria (el heap de 256 MiB se comparte con el motor y no hay `sceKernelAllocMemBlock`
en la tabla: reservar al arrancar y medir, M2); poses malas en robot real (sin tallado de espacio libre, un
vóxel ocupado no vuelve a libre, `tsdf3d_16.hpp:240-245`: separar «calidad de pose» de «calidad de bits» usando
simulación o poses de referencia); 444 MHz con WiFi sin confirmar (W1 P4: todo ×1,33 si son 333).

---

## 7. Por medir (solo sale del hardware)

| Id | Pregunta | Prueba | Verde |
|---|---|---|---|
| M1 | ms/scan reales por peldaño | T3: escena embebida, 100 scans, `clock_gettime` alrededor de `integrate`; C y Rust; 2D y 3D; K canónico y K = 5 común | tabla en la bitácora; se sustituye la del §3.4 |
| M2 | arena máxima con Godot cargado | al arrancar la escena, `memalign` de 8/16/32/64 MiB y registro del mayor que funciona; líneas `[memory]`/`[vita-memory]` de los logs (W1 P5d) | ≥ 16 MiB estables tras 10 min |
| M3 | ¿aguanta un hilo propio dentro del `.so`? | `Thread` de Godot + afinidad `USER_2` girando el banco 5 min; FPS y `[vita-prof]` con y sin hilo | sin cuelgues; caída de FPS ≤ 5 % |
| M4 | coste de `reconfigure` | cada transición de la tabla 4.4 sobre el mapa del conjunto A | < 100 ms o se hace a trozos |
| M5 | coste de refrescar la vista | `ImageTexture.update` de 64², 128², 256² `L8`; alternativa `draw_rect` por celda | ≤ 3 ms a 2 Hz |
| M6 | red para el TSDF | T5: `/vita/tsdf_scan` a 5/10 Hz y `/vita/tsdf_nube` a 20/40/80 datagramas/s; contador de `seq` perdidos | ≥ 90 % a 10 Hz |
| M7 | regresión de teleop | en el PC: `ros2 topic hz /cmd_vel` y FPS del HUD con mapeo apagado/encendido | Hz igual; FPS −5 % como mucho |
| M8 | paridad en hardware | `dbtsdf_hash` del banco en la consola, builds C y Rust | igual que en host |
| M9 | 444 MHz con WiFi | W1 P4 (pendiente) | si son 333 MHz, tiempos ×1,33 |
| M10 | ¿vectoriza GCC a `-Os`? | `arm-vita-eabi-objdump -d` del objeto y contar `vand`/`vqadd`/`vmin` (no necesita consola) | decide si hacen falta intrínsecas |

Comandos de ejemplo para el PC (fish), cuando existan relay y banco:

```fish
docker/vita-ros.sh up; docker/vita-ros.sh sim-tb3
docker/vita-ros.sh relay scan,pose,tsdf
docker/vita-ros.sh shell   # dentro: ros2 topic hz /vita/tsdf_scan ; ros2 topic bw /vita/tsdf_scan ; ros2 topic hz /cmd_vel
```

---

## 8. Decisiones para el ADR y cuestiones abiertas

| # | Decisión | Propuesta | Estado |
|---|---|---|---|
| D1 | Definición de «bits» | ancho `W` de la máscara termómetro; vóxel de `W/4` B | recomendada |
| D2 | Peldaños | V32, V16, V8, V4 con K canónico 21 / 7 / 5 / 3 | recomendada |
| D3 | Código de distancia por defecto | L1 (regla `W`↔K limpia; es el valor por defecto del nodo); rango-L2 también soportado por el oráculo; `⌈L2⌉` opcional | provisional hasta E-Q2 |
| D4 | Una biblioteca, handle opaco, memoria del llamador, sin hilos | sí | recomendada (irreversible: es el header) |
| D5 | Semántica del cambio en caliente | tabla 4.4 + `plan`/`reconfigure` + `epoch` | recomendada |
| D6 | Voxelizado entero y reserva ajustada (desviaciones del original) | sí, documentadas | recomendada |
| D7 | Celdas de 1 m como el original, o bloques potencia de 2 | 1 m en v1; potencia de 2 solo si T3 muestra que el índice pesa | abierta |
| D8 | Dónde vive la envoltura de Godot | clase `DbTsdfMap` en un módulo en árbol aparte de `ros2_vita` (no es API de rclgd) | abierta: depende de W10 |
| D9 | Hilo de mapeo | 3a sin hilo; 3b tras M3 | recomendada |
| D10 | `sombra` y `T` por defecto | 5 y 1 (como mai.yaml) | provisional hasta E-Q1 |
| D11 | Canal UDP propio para nubes | no, salvo que T5 lo exija | abierta: decide el usuario |

## 9. Dependencias con otros workshops

- **W1** (hardware): M2, M3, M9 dependen de sus pruebas pendientes (hwprobe E-H7/E-H8, logs de memoria).
- **W2 / `docs/27`**: presupuesto de recepción y `vita_relay`; este diseño solo añade el módulo `tsdf` al relay.
  No se leyeron los posts de W2 (ronda divergente); sí `docs/27` y el `tablero.json` integrado.
- **W7** (motor): la vista es 2D por textura o `draw_rect`; nada de puntos ni MultiMesh en 3D.
- **W10 / W11**: empaquetado como plugin y reparto Vita/PC (D8, D11).

---

## Anexos

### A.1 Estadísticas de kernel (script propio, no ejecuta código ajeno)

`K`, `W`, modo → niveles distintos por debajo de `W`, entradas inútiles (nivel ≥ `W`):

| K | W | L1 | rango-L2 | `⌈L2⌉` |
|---|---|---|---|---|
| 3 | 4 | 4 niv., 0 | 4 niv., 0 | 3 niv., 0 |
| 5 | 4 | 4 niv., 68 (54 %) | 4 niv., 98 (78 %) | 4 niv., 8 (6 %) |
| 5 | 8 | 7 niv., 0 | 8 niv., 32 (26 %) | 5 niv., 0 |
| 5 | 16 | 7 niv., 0 | 10 niv., 0 | 5 niv., 0 |
| 7 | 8 | 8 niv., 32 (9 %) | 8 niv., 250 (73 %) | 7 niv., 0 |
| 7 | 16 | 10 niv., 0 | 16 niv., 56 (16 %) | 7 niv., 0 |
| 11 | 16 | 16 niv., 0 | 16 niv., 1 026 (77 %) | 10 niv., 0 |
| 21 | 32 | 31 niv., 0 | 32 niv., 8 336 (90 %) | 19 niv., 0 |
| 25 | 32 | 32 niv., 280 (2 %) | 32 niv., 14 700 (94 %) | 22 niv., 0 |

Rango-L2: el último rango útil corresponde a `r² = 3` (1,73 vóx) con W = 4; `r² = 8` (2,83) con W = 8;
`r² = 17–18` (≈ 4,2) con W = 16; `r² = 36` (6,0) con W = 32.

### A.2 Aritmética de memoria y coste

Pool = celdas × `(1000/res_mm)^dims` × `W/4` B. Coste = `Np · (C_fijo + K^dims · c)`; ms = ciclos / 444 000.
Tablas de §3.2–3.4 generadas con scripts del scratch (`w3-scripts/kernel_stats.py`, `tables.py`,
`cost_rungs.py`; volátiles, se rehacen en minutos).

### A.3 Propiedades comprobadas por simulación

Reimplementación propia en Python de `tsdf3d_16.hpp:228-246` y `:412-447` sobre una rejilla de 24³ con 120
puntos, modos L1 y rango-L2, K ∈ {3, 5, 7}, T ∈ {1, 3} (`w3-scripts/sim_props.py`):

| Propiedad | Resultado |
|---|---|
| (a) truncar V16 a 8 o 4 bits = integrar directamente en V8/V4 (mismo K) | 0 vóxeles distintos en los 24 casos; `hits` idénticos |
| (b) `signo == 0` ⟺ `hits == T` | se cumple siempre |
| (c) la máscara es siempre un termómetro | se cumple siempre |
| (d) modo 2D = rebanada central del 3D (puntos coplanarios, sensor en el plano) | idéntico en los 6 casos (con rango-L2 hay que usar la tabla de rangos del cubo 3D) |
| (e) el mapa final no depende del orden de los puntos | se cumple |
| (f) ensanchar 8→16 frente a integrar en V16 | difiere el 3,9 % (L1, K = 7), 30 % (L1, K = 11), 34 % (rango-L2, K = 7) de los vóxeles tocados; **ninguno subestima** la distancia |

Estas propiedades pasan a ser pruebas de `tests/parity_test.c`.

### A.4 Contrato numérico para igualar al oráculo

1. Vóxel base por eje: `x' = p.x − min` (float32); `celda = (uint32)x'`; `j = (uint32)((x' − celda) · n)` con
   `n = 1000/res_mm` como float32 — misma secuencia que `grid_16.hpp:251-257`. El kernel cubre `base ± R` en
   enteros. En aritmética exacta coincide siempre con el original; solo puede diferir cuando `(p−min)·n` cae a
   ~1e-6 de un entero.
2. Bin: `az = atan2f(dy, dx)`; si `az < 0`, `az = (float)(az + 2π_double)`;
   `baz = (int)((double)(az · (float)bins_az) / 2π_double)`; `el = asinf(dz / sqrtf(dx² + dy² + dz²))`;
   `bel = (int)(((double)el + π/2) · bins_el / π)`; ambos recortados a `[0, bins−1]`
   (`tsdf3d_16.hpp:335-348`). Suma de cuadrados en el orden `(x² + y²) + z²`, sin FMA.
3. Dirección representativa del bin y signo: `tsdf3d_16.hpp:404-410,443-446` (`≥ 0` en la rama de 16 bits;
   la rama `legacy` usa `> 0`, `DBleg/…/tsdf3d_32.hpp:541`).
4. Rango-L2: tabla de `r²` distintos del cubo **3D** completo, también en modo 2D.
5. Escenas canónicas: generador con centros de vóxel y `frac(az·bins/2π) ∈ [0,1; 0,9]`.
