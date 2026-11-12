# 31 — Render y visualización sin shaders en la PS Vita: presupuesto y técnicas (LT2)

> **Estado:** workshop W8 cerrado (diseño) el 2026-11-12. Decisión en **ADR 0011**. Posts: `docs/ia/workshops/posts/W8-render.json`.
> Presupuestos = asignación de diseño [I] hasta los experimentos E-W8-0…6. Marcas: [V] · [I] · [?].
> **Autoría y revisión:** diseño de **Fable 5.2** (esfuerzo máximo), con cortes por límites de uso (2026-11-11/12); integración del orquestador (Opus 5.5). El juicio independiente de Fable sobre el ADR queda **pendiente** (regla §4.3: autor Fable → revisor Opus aislado; anotado en `docs/ia/workshops/tablero.json`).

## 0. Resumen (decisión candidata)

1. **Dos capas y dos vistas.** Capa 3D GXM solo para geometría **rígida o estática** (se mueve cambiando el
   `transform` de instancias, que no cuesta memoria de GPU). Capa 2D (CanvasItem, la ruta validada en hardware)
   para lo **denso y dinámico** (puntos, líneas, texto), enviado en **una sola llamada por display**. Vista
   «Planta 2D» (todo CanvasItem, sin proyección) y vista «Orbital 3D» (3D + 2D superpuesto).
2. **Color sin shaders ni color por vértice:** una **textura-paleta** compartida + UV por triángulo en 3D (una
   superficie, un *draw*, y de paso excluye la pasada de luz por vértice); en 2D el color por primitiva ya es gratis.
3. **Raster (mapa, costmap, imagen) = textura** actualizada a baja frecuencia; texto siempre en 2D.
4. **Decodificación:** primero el relay del PC (si el CDR no cabe en 488 B), luego el **C++ que el motor ya trae**
   (JPEG/PNG, `blit_rect`), luego GDScript si cuesta ≤ 2 ms por mensaje, y solo si no, **C en un módulo dual nuevo
   `viz-decode`**.
5. **Presupuesto inicial** (30 FPS con todo; 60 FPS en HMI): 30 000 triángulos y 150 *draws* 3D, 1 500 *quads* 2D,
   16 MiB de texturas, 8 ms de GDScript+red, 9 ms de envío 3D, 3 ms de lienzo. Es una asignación de diseño [I]:
   se cierra con los experimentos E-W8-0…6.
6. **No se parchea el rasterizador en la Fase 1.** Quedan registrados tres parches pequeños y proponibles a
   upstream (actualización de vértices en sitio, color por vértice/líneas 3D, MSAA).

---

## 1. Hechos contrastados en el código (lo que decide el diseño)

Confirman W7/W4 salvo donde se indica **(nuevo)** o **(corrige)**.

| # | Hecho | Evidencia | Consecuencia |
|---|---|---|---|
| H1 | Solo `PRIMITIVE_TRIANGLES`; lo demás se salta sin aviso | `GXM:70`, `GXM:968` [V] | Líneas y puntos 3D = triángulos, o van al 2D |
| H2 | Solo instancias cuya base es una malla; sin MultiMesh | `GXM:912` [V] | N objetos = N instancias = N *draws* |
| H3 | El aplanado guarda solo xyz+uv (20 B por vértice, sin índices: 60 B por triángulo); el color sale de `albedo` × tinte y de `texture_albedo` | `GXM:77-113`, `GXM:724-732`, `BR:416-427` [V] | Sin color por vértice; **sí hay UV + textura** |
| H4 | **(nuevo)** Las superficies opacas, estáticas y sin alfa reciben una **segunda pasada** multiplicativa de luz por vértice: otro *draw* y otra malla (16 B por vértice) en el mismo arena | `GXM:996-997`, `GXM:1011-1033`, `BR:471-559` [V] | Con `vertex_lighting` (por defecto activo) los *draws* y los triángulos de GPU casi se **duplican** |
| H5 | **(nuevo)** Esa pasada tiene un cupo de 3 000 vértices recoloreados por fotograma; una superficie de más de 1 000 triángulos nunca entra | `GXM:868`, `GXM:610` [V] | En el G1 solo el torso (2 162 tri) queda fuera; los otros 34 links sí entran (`godot/g1-unitree/robot/mallas_g1_vita/informe.json`) |
| H6 | **(nuevo)** El hash que invalida los colores de luz incluye el origen de la instancia al centímetro | `GXM:590-601` [V] | Un robot que anda pide recolorear todos sus links cada fotograma; el cupo se lo llevan siempre los primeros de la lista [I] |
| H7 | **(nuevo, riesgo)** La malla de luz se crea con las posiciones del momento y solo se recrea si cambia el **número** de vértices | `GXM:606`, `GXM:640-655`, `BR:530-545` [V] | Una ArrayMesh dinámica con nº de vértices constante y material opaco dibujaría la luz en la geometría **antigua** (con escritura de profundidad) [I] → lo dinámico nunca debe ir por la pasada de luz |
| H8 | Se excluye de la pasada de luz toda superficie con `albedo.a ≤ 0,99` o con textura que tenga algún píxel con alfa | `GXM:996-997`, `TEX:78`, `TEX:184-187` [V] | **Interruptor por material** sin tocar el motor |
| H9 | Cada cambio de malla (`clear`, `add_surface`) tira su caché; el arena de 24 MiB **no libera** mallas sueltas: al llenarse se reinicia entero y se reconstruye toda la geometría visible y la caché de luz | `GXM:187-221`, `GXM:1225-1230`, `BR:35`, `BR:450-452` [V] | Lo dinámico en 3D consume 60 B × triángulos × Hz hasta el reinicio (tirón [I]) |
| H10 | `surface_update_vertex_region` es un no-op (heredado del *dummy*) | `servers/rendering/dummy/storage/mesh_storage.h:120` (W7) [V] | No hay actualización en sitio; candidato a parche P1 (§7) |
| H11 | **(nuevo)** Las instancias que no caben en el presupuesto se saltan **enteras**; las «estructurales» (radio ≥ 2 m o a ≤ 1 m) solo las limita el techo configurado | `GXM:934`, `GXM:950` [V] | Una malla grande de puntos puede desaparecer entera: presupuesto holgado y mallas troceadas |
| H12 | **(nuevo)** Descarte por distancia a la **posición de la cámara**: borde a > 40 m siempre; borde a > 22 m si el radio aparente < 0,012 rad | `gxm_camera_lod.h:9-18`, `GXM:917-925` [V] | Cámara cenital ortográfica a ≤ 20 m de altura, o los marcadores lejanos desaparecen |
| H13 | **(nuevo)** `distance_darkening` viene activo: oscurece hasta el 18 % lo que está a > 16 m | `GXM:699-704`, `GXM:774-780`, `GXM:866` [V] | Hay que desactivarlo en una app de visualización |
| H14 | **(nuevo)** Los ajustes `rendering/vita/*` se leen **cada fotograma** con `get_setting` | `GXM:848-869` [V] | Se pueden conmutar en caliente con `ProjectSettings.set_setting` para pruebas A/B sin reexportar [I] |
| H15 | Sin *culling* de caras; filtro POINT forzado en 3D | `BR:370`, `BR:391`, `BR:442` [V] | Cintas planas visibles por las dos caras; texturas de paleta y de mapa exactas |
| H16 | **(nuevo)** El lienzo 2D baja todo a *quads* de 6 vértices en un *pool* de 4 MiB que se rehace cada fotograma; los de color plano se **funden en un solo *draw*** y llevan color por vértice (media por triángulo) | `CAN:73-94`, `CAN:355-397`, `BR:46-107`, `BR:193` [V] | Color por primitiva gratis en 2D; coste de CPU ∝ nº de *quads* **cada fotograma** |
| H17 | **(nuevo)** Una sola llamada crea un lote: `canvas_item_add_triangle_array` (un comando), `draw_multiline_colors` (un comando, líneas de 1 px con color por segmento), `draw_polyline` fina (un comando) | `CULL:1247-1276`, `CULL:980-1003`, `CULL:1779-1797`, `CAN:378-387` [V] | 180 puntos = 1 llamada GDScript, no 180 |
| H18 | **(nuevo)** El lienzo registra su propio coste: `[gxm2d-canvas] calls= avg_canvas_us= avg_items=` cada 300 llamadas | `CAN:570-578` [V] | Métrica que faltaba en la lista de W7 |
| H19 | `ImageTexture.update()` = duplicar + convertir a RGBA8 + `detect_alpha` + crear textura nueva al primer uso; cada textura se redondea a 256 KiB de CDRAM; tope 64 MiB | `TEX:60-84`, `TEX:197-203`, `BR:124-154`, `loader/texture_format.h:14-16` [V] | Máximo 256 texturas; actualizar es caro ∝ píxeles; trocear el mapa |
| H20 | **(nuevo)** El formato de textura es por paquete: `textures/gpu_format` = RGBA4444 (defecto) o RGBA8888 | `editor/addons/psvita/platform.gd:47,309`, `BR:184-190` [V] | Imagen de cámara y degradados de costmap: RGBA8888 (el G1 ya lo usa, `godot/g1-unitree/export_presets.cfg`) |
| H21 | **(nuevo)** vita2d ya tiene vértices con color y acepta líneas y puntos | `toolchains/vitasdk/arm-vita-eabi/include/vita2d.h:21-26,100`, `psp2/gxm.h:104-107` [V] | El parche P2 (§7) no necesita shaders nuevos |
| H22 | **(nuevo)** JPEG/PNG/WebP desde memoria están en la plantilla; el `libjpeg.a` del VitaSDK **no trae SIMD** | símbolos en `toolchains/godot4-vita/out/libgodot.so`; `nm libjpeg.a` sin `jsimd`; `platform/vita/detect.py:228-232` [V] | Decodificar imagen = C escalar del motor, sin código nuestro |
| H23 | El presupuesto adaptativo del port reacciona a la media de envío: > 14 ms recorta, < 9 ms restaura | `GXM:1245-1249` [V] | Umbrales de verde/rojo para `avg_submit_us` |
| H24 | **(nuevo)** `[gxm2d-perf] draws=` cuenta solo lotes 2D; los *draws* 3D se deducen de `[gxm3d] drawn=` + `lit=` | `BR:73-89`, `BR:430-449`, `GXM:1250-1253` [V] | No confundir al leer los logs |
| H25 | Cada mensaje recibido se decodifica entero a un árbol `RosMsg` antes de llamar al script; `int16[]` llega como `PackedInt32Array`, `float32[]` y `uint8[]` por `memcpy` | `rv:ros_runtime.cpp:118-133`, `rv:ros_msg.cpp:432-488` [V] | Los formatos compactos `*MultiArray` son baratos de recibir; los decodificadores C reciben arrays empaquetados |

**Caso real (G1) releído con estos hechos** [V salvo donde se indica]: 35 `MeshInstance3D` del robot (12 633
triángulos) + 34 cajas de la casa con 21 materiales, sin `StaticBody3D` y con los ajustes `rendering/vita/*` por
defecto (`godot/g1-unitree/project.godot`). Con luz por vértice eso son 69 *draws* base + hasta 68 de luz = **≈ 137
*draws*** y ≈ 13 000 + 10 900 triángulos de GPU por fotograma [I]. G7c (59 FPS) eran 20 instancias y 5 574
triángulos (`docs/06-bitacora-estado.md:56-58`): el G1 es ×3,4 en *draws* y ×2,3 en triángulos, sin medir todavía
(gate G8-G1).

---

## 2. Técnicas sin shaders

### 2.1 Color en 3D: textura-paleta + UV (sustituye al «material por color»)

- Una `ImageTexture` de 16×16 (256 colores: cubo 6×6×6, 16 grises, colores REP-103 de ejes, rampas de altura y de
  intensidad) y **un** `StandardMaterial3D` con `albedo_texture` = paleta, compartido por todas las primitivas de
  visualización. Los tres vértices de cada triángulo llevan el UV del centro de su texel: el filtro POINT (H15)
  devuelve el color exacto.
- Un texel reservado con alfa 0 marca la textura como «con alfa» (H8): esas superficies **no entran en la pasada
  de luz** (ni *draw* doble, ni riesgo H7) y se pintan con el tinte por objeto, que se satura a 1 con ambiente
  ≥ 0,3 y una luz direccional de energía ≥ 1 (`GXM:773-813`: base + 0,12 + 0,6 × luz, recortado a 1) [V fórmula].
- Resultado: **una superficie y un *draw* por malla, con cualquier número de colores**. La alternativa «una
  superficie por color» (bandas de altura con N materiales) cuesta N *draws* y N mallas en el arena: descartada.
- Coste: 1 textura (256 KiB de CDRAM por el redondeo, H19). Marcadores con color arbitrario: se cuantiza al texel
  más cercano, o material propio con `albedo_color` (entonces sí recibe luz por vértice, que en esferas y cilindros
  ayuda a leer la forma).

### 2.2 Líneas

| Caso | Técnica | Triángulos |
|---|---|---|
| Sobre el suelo (rejilla, Path, huella) | cinta plana de ancho *w* (visible por las dos caras, H15) | 2 por segmento |
| En el espacio (enlaces TF, `LINE_STRIP` 3D) | prisma triangular sin tapas, o 2D superpuesto | 6 por segmento |
| Ejes de un frame | 3 cajas finas en **una** malla compartida, UV a rojo/verde/azul | 36 por frame |
| Planta 2D / superposición | `draw_multiline_colors` (1 px exacto) o `draw_polyline` con ancho | 1–2 *quads* por segmento |

Sin MSAA (el cargador usa `vita2d_init_advanced`, `BR:193`), una caja más fina que ~1,5 px parpadea. Con la cámara
del G1 (fov 55°, focal ≈ 522 px) el grosor mínimo es `1,5 · d / 522`: 9 mm a 3 m, 29 mm a 10 m [I, geometría].
Regla: grosor por tramos de distancia aplicado como **escala de la instancia** (no reconstruye malla).

### 2.3 Puntos (LaserScan, nubes)

- **2D (defecto):** un triángulo o un cuadrado por punto en una sola llamada
  `RenderingServer.canvas_item_add_triangle_array(ci, indices, puntos, colores)`; el color por vértice se promedia
  por triángulo (`CAN:373`), así que la banda de altura o la intensidad salen gratis. Tamaño en píxeles constante:
  siempre visibles.
- **3D (promoción, tras E-W8-2):** una única `ArrayMesh` con UV a paleta, reconstruida con
  `clear_surfaces()` + `add_surface_from_arrays()`. Un triángulo plano por punto se pierde de canto: tetraedro
  (4 tri) o cruz de dos triángulos.
- **Descartado:** un `MeshInstance3D` por punto (180–360 *draws*).

### 2.4 Raster y texto

- Mapa/costmap: `Image` RGBA8 persistente → `ImageTexture` → en 3D un quad en el suelo (POINT = celdas nítidas),
  en 2D `draw_texture_rect` con filtro NEAREST (`CAN:60-70`). **Una sola textura compuesta por capa**: en 3D no hay
  ordenación de transparencias y la profundidad se escribe siempre (W7; `GXM:1029-1034`), así que un costmap
  translúcido sobre el mapa no tiene orden garantizado [I]; el costmap se compone en CPU sobre la misma imagen.
- Imagen de cámara: `TextureRect` en el HUD.
- Texto (nombres de frames, `TEXT_VIEW_FACING`, HUD): `Label`/`draw_string` en la posición de
  `Camera3D.unproject_position`. `Label3D` y `Sprite3D` quedan fuera (W7: color en `ARRAY_COLOR` ignorado y
  `surface_update_vertex_region` vacío).

---

## 3. Pregunta 1 — Qué va en 3D GXM, qué en 2D y qué en el HUD

Datos de entrada = formatos del relay ya implementado (`docker/scripts/vita_relay.py`, `docs/27 §2`); los que aún
no existen en el relay se marcan *(pendiente)*.

| Display | Vista Orbital 3D | Vista Planta 2D | Triángulos / *draws* 3D | *Quads* 2D por fotograma |
|---|---|---|---|---|
| **RobotModel** | `MeshInstance3D` por link, mallas diezmadas en el PC (`tools/urdf2godot`), `albedo_color`; luz por vértice opcional | icono/huella (polígono) | ≤ 15 000 / ≤ 40 (+40 con luz) | ≤ 4 |
| **TF** | malla «ejes» compartida (36 tri, paleta) instanciada como hija de cada link o de un nodo por frame; nombres en 2D (opcional, ≤ 10) | 2 líneas por frame | 36·N / N (N ≤ 32, tope de `modules/tf-tree`) | 2·N |
| **LaserScan** | **2D superpuesto**: puntos proyectados, lote único (promoción a malla 3D tras E-W8-2) | lote único con el `transform` del CanvasItem | 0 (o 180–720 / 1) | 180–360 |
| **OccupancyGrid / costmap** | quad(s) en el suelo con la textura del mapa | `draw_texture_rect` | 2–18 / 1–9 | 1–9 |
| **Path** | cinta plana reconstruida a 2 Hz (≤ 56 segmentos) | `draw_polyline` | ≤ 112 / 1 | ≤ 112 |
| **Marker / MarkerArray** *(pendiente)* | *pool* de ≤ 48 instancias de primitivas unidad (cubo 12, esfera 64, cilindro 32, flecha 44 tri); `LINE_*`, `POINTS`, `TEXT` → 2D | formas 2D | ≤ 3 000 / ≤ 48 | ≤ 200 |
| **Odometry** | flecha compartida + rastro de ≤ 20 instancias | flecha + polilínea | ≤ 900 / ≤ 21 | ≤ 30 |
| **Pose (PoseStamped)** | flecha o ejes compartidos | flecha | 44 / 1 | 2 |
| **CompressedImage / Image** *(pendiente)* | HUD: `TextureRect` 160×120 (×2 en pantalla) | igual | 0 | 1 |
| **PointCloud2 decimada** *(pendiente)* | **2D superpuesto**: ≤ 468 puntos, color por banda de altura | proyección cenital | 0 (o ≤ 1 872 / 1) | ≤ 468 |
| HUD (FPS, estado, Hz) | `Label` a ≤ 10 Hz (optimización O1 de G7c) | igual | 0 | 200–400 (glifos) |

Notas de coste (todas [I] hasta medir, §6):

- **Instancia rígida:** mover = 1 llamada `set_transform`; cero memoria de GPU. Por eso TF, marcadores, poses y
  robot van en 3D.
- **Superposición 2D en vista orbital:** hay que reproyectar cuando cambian los datos **o** la cámara. En GDScript
  ≈ 10–15 µs por punto (180 puntos ≈ 2–3 ms) → limitar a ≤ 20 Hz; con la función C de §4.3 ≈ 0,03 ms. El precio
  conocido: lo superpuesto no se oculta tras el robot.
- **Planta 2D:** `_draw()` solo cuando llega un mensaje; el desplazamiento y el zoom son el `transform` del nodo
  (lo aplica el C++ del lienzo por vértice, `CAN:26-30`).

---

## 4. Pregunta 2 — Dónde se decodifica

### 4.1 Regla de corte

1. **Bytes.** CDR > 488 B no puede ir en *best effort* (`rv:xrce_transport.cpp:411-415`) → **relay (c)** obligatorio.
   El canal fiable (≤ ≈ 7,5 KiB) solo para datos de ≤ 5 Hz o con TRANSIENT_LOCAL (meta del mapa, orden de joints,
   JPEG ≤ 3 KB).
2. **Tiempo.** En el hilo principal, cada display dispone de **≤ 2 ms por mensaje** (pico) y **≤ 1 ms por
   fotograma de media** a 30 FPS (30 ms/s); la suma de todos, ≤ 4 ms por fotograma. Si GDScript lo cumple →
   **(a)**. Con la hipótesis de 1,5 µs por instrucción GDScript [I] eso son ≈ 1 300 instrucciones por mensaje:
   ≈ 110 elementos a 12 instrucciones, o ≈ 260 a 5 (con tablas).
3. **Antes de escribir C propio**, buscar la ruta por el **C++ del motor**: JPEG/PNG desde memoria (H22),
   `Image.blit_rect`, `Transform3D * PackedVector3Array`, `PackedByteArray.to_float32_array()`. Si hace falta, se
   cambia el formato del relay para que el motor lo sepa leer.
4. Si nada de lo anterior llega → **(b)** función C en el módulo dual `viz-decode` (§4.3), expuesta por `ros2_vita`
   (ADR 0008 §1: la lógica en `modules/*`, el C++ solo expone).
5. Todo lo que se ejecute **cada fotograma** con más de ~30 elementos va a (b) o se rediseña para ejecutarse por
   mensaje.

### 4.2 Reparto por display

| Display | Mensaje hacia la Vita | Bytes · Hz | Decodificación | Coste estimado [I] |
|---|---|---|---|---|
| RobotModel | `/vita/joints` Float32 ×29 | 132 · 25 | (a) con constantes cacheadas | hoy ≈ 3 ms/mensaje (`get_meta` ×5 por joint, `godot/g1-unitree/robot/urdf_robot.gd:62-73`); cacheado ≈ 0,7 ms |
| TF | ninguno (cinemática local); frames sueltos: `/vita/tf_compacto` ×7 floats *(pendiente)* | ≤ 464 · 10 | (a) | ≈ 20 µs por frame |
| LaserScan | `/vita/scan_compacto` Int16 ×184 | 384 · 10 | (a) con tabla de direcciones; (b) cuando exista | hoy ≈ 3 ms (`cos`/`sin` por rayo, `godot/comun/vita_relay.gd:94-107`); tabla ≈ 1,3 ms; C ≈ 0,03 ms |
| OccupancyGrid | `/vita/mapa_tesela` 2 bit 32×32 + meta | 260 · ≤ 20 | (c) + LUT de 256 entradas y `blit_rect`, o PNG del motor | hoy ≈ 20 ms por tesela (`set_pixel` por celda, `vita_relay.gd:55-66`) = 40 % de CPU a 20 teselas/s; LUT ≈ 1–1,5 ms; PNG ≈ 0,3 ms; C ≈ 0,03 ms |
| Path | `/vita/path_compacto` ≤ 57 puntos | 476 · 2 | (a) | ≈ 0,4 ms |
| Marker | `/vita/marcadores` 8 floats *(pendiente)* | ≤ 464 · 5 | (a) | ≈ 1 ms por datagrama (14 marcadores) |
| Odometry / Pose | `/vita/pose2d`; PoseStamped crudo | 40 · 30; 76 | (a) | ≈ 30 µs |
| CompressedImage | JPEG 160×120 q40 *(pendiente)* | 2–3 KB · 5, fiable | (c) + `Image.load_jpg_from_buffer` | ≈ 3–6 ms por imagen (decodificar + subir) |
| PointCloud2 | `/vita/nube2d` Int16 xyz cm *(pendiente)* | ≤ 484 · 5 por trozo | (b); (a) solo por trozos de ≤ 78 puntos | GDScript ≈ 1,7 ms por trozo; C ≈ 0,05 ms |

### 4.3 Módulo dual `viz-decode` (propuesta de cabecera, sin implementar)

Funciones puras sobre búferes del llamador (sin `malloc`, sin estado), C y Rust con paridad en host:

| Función | Entrada → salida |
|---|---|
| `vizd_scan_xy` | n distancias en cm + ángulo inicial e incremento → xy en metros, nº de válidos |
| `vizd_project` | n puntos xyz + matriz 4×4 + tamaño de pantalla → xy de pantalla, índices visibles (descarta detrás de la cámara) |
| `vizd_points_tris` | n puntos de pantalla + tamaño en px → 3n vértices 2D |
| `vizd_cloud_cm` | n puntos Int16 cm + rango de altura → xyz en metros + banda de color |
| `vizd_tile2bit_rgba` | 256 B a 2 bit + LUT de 4 colores → 4 096 B RGBA (con volteo vertical) |
| `vizd_ribbon` | polilínea + ancho → triángulos |

Se expone como métodos estáticos de `ros2_vita` que devuelven `PackedVector2Array` / `PackedColorArray` /
`PackedByteArray`. Coste: 2–3 días + recompilar plantilla (1–2 h) → se agrupa con los otros cambios pendientes del
módulo (clases TF de W4). **No bloquea la Fase 1**: todo lo de §3 funciona antes en GDScript dentro de la regla de
corte, salvo la nube de más de 78 puntos por mensaje.

### 4.4 Hallazgos en el código ya escrito (acciones baratas, sin plantilla nueva)

| Dónde | Qué pasa | Arreglo |
|---|---|---|
| `godot/comun/vita_relay.gd:55-66` | 1 024 `set_pixel` por tesela desde GDScript | LUT byte → 16 B RGBA + `Image.create_from_data` + `blit_rect` (≈ 15× menos [I]) |
| `godot/comun/vita_relay.gd:72-77` | sube la textura **entera** hasta 4 veces por segundo | sub-texturas de 128×128 y subir solo la sucia (≤ 1 por fotograma) |
| `godot/comun/vita_relay.gd:94-107` | `cos`/`sin` y `append` por rayo | tabla de direcciones recalculada solo si cambian `ang_min`/`inc`/`n` |
| `godot/g1-unitree/minimapa.gd:33-36` | `queue_redraw()` cada fotograma | redibujar solo cuando cambien pose, path o mapa |
| `godot/g1-unitree/robot/urdf_robot.gd:62-73` | 5 `get_meta` por joint y por mensaje | cachear origen, eje, límites y tipo en arrays en `_ready` |
| `godot/g1-unitree/casa/casa.tscn` | 34 instancias (68 *draws* con luz) para ~400 triángulos | hornear la casa en **una** malla con paleta (1 *draw*) desde `docker/g1/casa.py` |

---

## 5. Pregunta 3 — Presupuesto de render

Asignación de diseño **[I]**: parte de un único dato de hardware (G7c: 59 FPS, 20 instancias, 5 574 triángulos,
`docs/06:56-58`), de los umbrales del propio port (H23) y de la lectura del código. Se confirma o se corrige con §6.

### 5.1 Tiempo de CPU por fotograma (un núcleo efectivo, W1)

| Partida | Viz 30 FPS (33,3 ms) | HMI 60 FPS (16,7 ms) | Campo que lo mide |
|---|---|---|---|
| GDScript + XRCE + decodificación | ≤ 8 ms | ≤ 4 ms | `[vita-prof] process=` |
| 3D: envío de instancias | ≤ 9 ms | ≤ 6 ms | `[gxm3d] avg_submit_us=` (verde ≤ 9 000, rojo > 14 000) |
| 2D: lienzo | ≤ 3 ms | ≤ 2 ms | `[gxm2d-canvas] avg_canvas_us=` |
| Construcciones (malla, textura), pico | ≤ 6 ms | ≤ 3 ms | `[gxm3d] build_us=` |
| Física, animación | ≤ 1 ms | ≤ 0,5 ms | `[vita-prof] physics3d=`, `animation=` |
| Margen (WiFi, picos) | ≥ 6 ms | ≥ 1 ms | `fps=` estable |

Con vsync el resultado se cuantiza: fotograma ≤ 16,7 ms → 60 FPS; ≤ 33,3 ms → 30 FPS.

### 5.2 Geometría 3D (triángulos base; la pasada de luz puede duplicar los de GPU, H4)

| Capa | Triángulos | Instancias = *draws* base |
|---|---:|---:|
| Robot | 15 000 | 40 |
| Entorno horneado, mapa (quads) y rejilla | 3 000 | 12 |
| TF (≤ 32 ejes) | 1 200 | 32 |
| Marcadores, poses, rastro | 3 000 | 48 |
| Dinámico lento (Path) | 500 | 4 |
| Reserva | 7 300 | 14 |
| **Total Viz (30 FPS)** | **30 000** | **150** |
| Total HMI (60 FPS) | 15 000 | 80 |

`rendering/vita/triangle_budget = 40000`: por encima del total para que el descarte por instancia entera (H11) no
actúe dentro del presupuesto.

### 5.3 2D, texturas y memoria de GPU

| Recurso | Presupuesto | Límite duro [V] | Campo |
|---|---|---|---|
| *Quads* 2D por fotograma | 1 500 (HUD 400 + sensores 800 + resto) | ≈ 43 000 (pool de 4 MiB a 96 B) | `[gxm2d-perf] quads=` |
| Lotes 2D | 30 | — | `[gxm2d-perf] draws=` |
| Texturas | 16 MiB y 48 unidades | 64 MiB y 256 unidades | `[vita-memory] textures=`, `cdram_free=` |
| Arena de mallas | 3 MiB residentes; dinámico ≤ 150 KB/s (reinicio cada ≥ 2 min) | 24 MiB | `[gxm3d] arena_kb=`, `invalidations=` |

Texturas previstas: paleta (0,25 MiB), mapa 384² en 9 sub-texturas de 128² (2,25 MiB) o una de 0,75 MiB, imagen
160×120 (0,25 MiB, ×2 durante el relevo), atlas de fuentes e iconos (≈ 2–4 MiB) → ≈ 8 MiB.

Consumo del arena por contenido dinámico (60 B por triángulo, H3/H9), partiendo de ≈ 21,5 MiB libres:

| Malla reconstruida | KB/s | Reinicio del arena cada |
|---|---:|---|
| Path, 112 tri a 2 Hz | 13 | ≈ 28 min |
| Scan, 180 tri a 10 Hz | 108 | ≈ 3,5 min |
| Scan, 720 tri a 10 Hz | 432 | ≈ 52 s |
| Nube, 468 tri a 5 Hz | 140 | ≈ 2,7 min |

### 5.4 Ajustes de proyecto para una app de visualización

```ini
[rendering]
vita/distance_darkening=false   ; H13
vita/shadow_rays=0              ; sin rayos de física para sombras (W7)
vita/light_flares=false
vita/triangle_budget=40000
vita/vertex_lighting=true       ; A/B en E-W8-1: false = la mitad de draws, robot sin sombreado
```

Preset de exportación: `textures/gpu_format="RGBA8888"`. Escena: una `DirectionalLight3D` (energía ≥ 1) y ambiente
≥ 0,3. Cámara cenital ortográfica a ≤ 20 m (H12). Sin `StaticBody3D` de adorno.

### 5.5 Qué leer para cerrarlo

| Línea | Campos | Pregunta que responde |
|---|---|---|
| `[gxm2d-perf]` (`BR:291`) | `fps`, `avg_frame_us`, `quads`, `draws`, `gpu_wait_us` | ¿se sostiene 30/60? ¿cuánto 2D? ¿la CPU espera a la GPU? |
| `[gxm3d]` (`GXM:1250`) | `drawn`, `lit`, `submitted_triangles`, `budget`, `avg_submit_us`, `build_us`, `arena_kb`, `invalidations`, `distance_culled` | coste por *draw*, recorte adaptativo, reconstrucciones, llenado del arena |
| `[gxm2d-canvas]` (`CAN:573`) | `avg_canvas_us`, `avg_items` | µs por *quad* 2D |
| `[vita-prof]` (`main/main.cpp:5062-5078`) | `process`, `render`, `physics3d` | GDScript + red; `render` incluye esperas, no es CPU pura |
| `[vita-memory]` (`BR:109-116`, cada 600 fotogramas) | `textures`, `cdram_free`, `user_free` | fugas al actualizar texturas |

Recogida (fish, PC; app sin carpeta de datos separada → `ux0:data/gxm3d/`):

```fish
set VITA 192.168.1.94
mkdir -p ~/vita-logs
curl -s -o ~/vita-logs/godot_stderr.log ftp://$VITA:1337/ux0:/data/gxm3d/godot_stderr.log
grep -E '\[(gxm2d-perf|gxm2d-canvas|gxm3d|vita-prof|vita-memory)\]' ~/vita-logs/godot_stderr.log | tail -n 40
```

---

## 6. Por medir (prueba y criterio de verde)

Proyecto propuesto `godot/w8-bench/` (GDScript puro, **sin plantilla nueva**): un caso por botón, valores en el HUD
y en `stderr` con el prefijo `[w8]`. Cada caso corre ≥ 20 s (≥ 2 líneas de log).

| Id | Prueba | Se lee | Verde |
|---|---|---|---|
| **E-W8-0** | µs por instrucción GDScript: bucles de 10 000 (aritmética + índice; `cos`/`sin`; llamada al motor; `Image.set_pixel`; `set_joints` de 29 joints) con `Time.get_ticks_usec()` | `[w8] gd_op_us=`, `engine_call_us=` | informativa: fija el N máximo de la regla de corte (§4.1). Si > 3 µs por instrucción, scan y path pasan a (b) |
| **E-W8-1** | Barrido estático: K ∈ {20, 70, 150, 300} instancias × total ∈ {10, 20, 40, 60} mil triángulos; con `vertex_lighting` true/false (conmutado en caliente, H14) | `fps`, `avg_submit_us`, `lit`, `gpu_wait_us` | 30 000 tri / 150 instancias: `fps ≥ 29,5` y `avg_submit_us ≤ 9 000`; 15 000 / 80: `fps ≥ 59`. Deriva µs por *draw* = Δ`avg_submit_us` / ΔK |
| **E-W8-2** | Malla dinámica: ArrayMesh de {180, 720, 2 000} triángulos con paleta, reconstruida a 10 Hz durante 5 min; variante «opaca, mismo nº de vértices, luz por vértice» para confirmar H7 | `build_us`, `arena_kb`, `invalidations`, Δt máximo por ventana de 5 s | 720 tri: `build_us ≤ 2 000`; tirón al reiniciar el arena ≤ 33 ms; sin geometría fantasma. Verde ⇒ LaserScan y nube pueden promocionar a 3D |
| **E-W8-3** | Lienzo denso: {180, 500, 1 000, 2 000} triángulos en una `canvas_item_add_triangle_array`, quietos y con el `transform` moviéndose; variante con `queue_redraw()` + proyección GDScript de 180 puntos | `avg_canvas_us`, `quads`, `draws`, `process` | ≤ 1,5 µs por triángulo (1 000 → ≤ 1,5 ms) y 1 lote; si no, bajar el presupuesto 2D |
| **E-W8-4** | Textura de mapa: `ImageTexture.update()` de 128², 256², 384² a 1 y 4 Hz, como quad 3D y como rect 2D, 10 min; y coste por tesela con `set_pixel`, con LUT y con PNG | Δt máximo, `build_us`, `textures=`, `cdram_free=`; `[w8] tesela_us=` | 128² ≤ 2 ms; 384² ≤ 12 ms; `cdram_free` estable; tesela ≤ 1,5 ms con LUT |
| **E-W8-5** | Imagen: `Image.load_jpg_from_buffer` 160×120 q40 y 320×240 + `update` a 5 y 10 Hz | `[w8] jpg_us=`, `fps`, `textures=` | 160×120 ≤ 6 ms en total y `fps` sin bajar de escalón |
| **E-W8-6** | Escena completa Fase 1 (gate G-W8): robot G1 + casa horneada + mapa 384² + scan 180 + path + 20 TF + 16 marcadores + HUD, con `docker/vita-ros.sh relay` en vivo, 10 min | todas las líneas de §5.5 + `rclgd.get_transport_info()` | `fps ≥ 29,5` en todas las ventanas; `avg_submit_us ≤ 9 000`; `process ≤ 8 000`; `avg_canvas_us ≤ 3 000`; `budget=` sin recortar; `be_dropped` ≈ 0; `/vita/imu` a 30 Hz |

Además, inspección visual única (captura): colores de paleta exactos, exclusión de la luz con el texel de alfa,
grosor mínimo de cajas finas, nitidez del mapa, orden de transparencias.

Orden recomendado: G8-G1 (ya exportado) → E-W8-0 → E-W8-1 → E-W8-3 → E-W8-4 → E-W8-2 → E-W8-5 → E-W8-6.

---

## 7. Pregunta 4 — Alternativas registradas

| Alternativa | A favor | En contra | Veredicto |
|---|---|---|---|
| **P1. Parche: `mesh_surface_update_vertex_region` escribe en sitio en el arena** | elimina el consumo del arena, las 4 copias por vértice y el riesgo H7 para mallas de topología fija; arregla `Sprite3D`; ~60–100 líneas en `GXM:` | recompilar plantilla (1–2 h); mantener un parche del motor (hoy solo hay uno del cargador, `godot/loader-patches/0001-*.patch`) | **candidato n.º 1** si E-W8-2 sale rojo; proponible a upstream (`WolffsRoom/godot4-vita`) |
| **P2. Parche: color por vértice y líneas/puntos 3D** | vita2d ya dibuja `vita2d_color_vertex` con líneas y puntos (H21); la malla de luz ya es una malla con color (`BR:482-545`); gdviz portaría con menos cambios (W4) | toca `GXM:` y `BR:` (plantilla + cargador); líneas de 1 px sin ancho en perspectiva; la paleta ya cubre el color | registrado; **después de la Fase 1**, solo si la paleta o el 2D resultan insuficientes |
| **P3. MSAA 4× en el cargador** (`vita2d_init_advanced_with_msaa`, `vita2d.h:62`) | quita el parpadeo de cajas finas | más memoria y GPU; la pasada de luz crea su programa con `MULTISAMPLE_NONE` (`BR:502`), habría que tocarla | registrado; medir antes el grosor mínimo |
| **vitaGL de `vita-app/`** (ADR 0006/0007) | líneas y puntos nativos (`vita-app/src/viz/viz.c:29-45`) | proceso aparte: no convive con Godot en la GPU (ADR 0008, contexto 4); habría que duplicar ROS, UI y plugins; ADR 0008 §5 lo deja como histórico | **descartado** |
| **Vista 2D cenital pura** (sin 3D) | la ruta más validada y barata; cubre Nav2 | sin RobotModel 3D ni TF 3D (G1, brazos); contradice la enmienda de ADR 0008 §5 | **absorbida**: es la vista «Planta 2D» de la decisión, no la única |
| **Todo lo dinámico en 3D** (ArrayMesh por mensaje) | profundidad correcta; coste por fotograma nulo | ruta dinámica sin validar en hardware; consumo del arena y reinicios; riesgo H7 | **aplazada** a E-W8-2 (promoción por display) |
| **Un `MeshInstance3D` por punto o por celda** | trivial | 180–360 *draws* por scan; H2 | descartada |
| **Una superficie por color** (bandas con N materiales) | sin texturas | N *draws* y N mallas; la paleta lo hace en 1 | descartada |
| **Ruta de piel** (esqueleto de 1 hueso para forzar la ruta transitoria por CPU, `GXM:1046-1122`) | no usa el arena | depende de un detalle interno (la caché solo se refresca si cambia la versión del esqueleto, `GXM:1048`); copia de vértices cada fotograma | descartada por frágil |
| **Decodificar mensajes ROS crudos en GDScript** | sin relay | no caben por XRCE (W2) y cuestan de 60 ms a 1 s por mensaje (W4 §3) | descartada |
| **`SceJpeg` de Sony** para la imagen | posible aceleración | API sin explorar; `libjpeg` escalar puede bastar a 160×120 | [?] solo si E-W8-5 sale rojo |

---

## 8. ADR

Ver `docs/adr/0011-presupuesto-render-vita.md`.

## 9. Tareas propuestas

| Id | Tarea | Dónde | Prioridad | Coste |
|---|---|---|---|---|
| T-W8-1 | Añadir los ajustes de §5.4 a los proyectos Godot de la Vita | `godot/*/project.godot` | P0 | S |
| T-W8-2 | Proyecto `w8-bench` con E-W8-0…5 | `godot/w8-bench/` | P0 | M (1–2 días) |
| T-W8-3 | Arreglos de §4.4 (LUT de teselas, sub-texturas, tabla del scan, redibujado por cambio, caché de joints) | `godot/comun/`, `godot/g1-unitree/` | P0 | S–M |
| T-W8-4 | Biblioteca de visualización: paleta, ejes, flecha, cinta, primitivas unidad, lote 2D | `godot/comun/viz/` | P1 | M |
| T-W8-5 | Hornear la casa en una malla con paleta | `docker/g1/casa.py` | P1 | S |
| T-W8-6 | Módulos del relay que faltan: marcadores, nube, cámara | `docker/scripts/vita_relay.py` | P1 | M |
| T-W8-7 | Módulo dual `viz-decode` + exposición en `ros2_vita` | `modules/viz-decode/`, `godot/ros2_vita/` | P2 (con la próxima plantilla) | M |
| T-W8-8 | Parche P1 (actualización en sitio) | `godot/loader-patches/` + motor | P2, solo si E-W8-2 rojo | M |
