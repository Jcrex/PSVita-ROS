# W13 — sensores densos (borrador del investigador `sensores-densos`, ronda 1)

> Borrador para la integración de W13 (no es doc final). Fichas completas, con código, fuentes y criterio de
> verde: `W13-sensores-densos.json` (15 fichas). Marcas: [V] verificado (código leído o ejecutado) · [I] inferido ·
> [?] por comprobar.
>
> **Cómo se ha probado el código** [V]: el editor de host `toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64`
> (4.8-dev7) **trae `ros2_vita` compilado** (`RosNode`, `RosMsg`, `RosQoS`… nativos). Cada script de las fichas se
> ejecutó en headless con mensajes `RosMsg` reales (esquema `godot/g1-sensores/ros/schema.rsch`, ida y vuelta
> `serialize()`/`deserialize()` = lo que llega por XRCE) llamando al callback; los shaders se compilaron (el
> headless sí valida: un shader roto da `SHADER ERROR`). Falta lo que exige GPU o agente: no hay render real ni
> suscripción (`create_subscription` avisa «rclgd.init() primero»). Tiempos medidos en un Ryzen 7 5800X; la Vita
> es del orden de 20–40× más lenta en GDScript [I] (hipótesis de 1,5 µs por instrucción, `docs/31:162`).

## 1. Tabla tipo / codificación → visualizador

| Tipo / codificación | PC (rclgd) | Vita (ros2_vita) | ¿Cabe en 488 B? (CDR medido) |
|---|---|---|---|
| `LaserScan` | `ArrayMesh` `PRIMITIVE_POINTS` bajo el frame, tabla cos/sin, color por intensidad, *decay* = una malla congelada por barrido | 2D: **un** `canvas_item_add_triangle_array` por mensaje (H16-H17) | ≤ 106 rayos sin intensidades con frame `base_scan` (484 B); real → `/vita/scan_compacto` (384 B) |
| `MultiEchoLaserScan` | aplanar a LaserScan (primer/último/más fuerte/todos) y reutilizar | relay → `scan_compacto` | no (360×3 + int. = 11 584 B) |
| `PointCloud2` | decodificador genérico `fields`/`point_step` + diezmado + LUT; `PRIMITIVE_POINTS` con basis ROS→Godot | relay: vóxel 10 cm, Int16 cm, `/vita/nube2d` ≤ 78 pts por trozo → 2D por bandas de altura | no (20 pts xyzi = 461 B; 100 = 1 741 B) |
| `PointCloud` (obsoleto) | convertir a PointCloud2 (como RViz) o respaldo GDScript | relay | sin esquema en la Vita |
| `Image` rgb8, rgba8, mono8, 8UC1, 8UC3 | `Image.create_from_data` con el formato equivalente + `ImageTexture.update` (sin conversión) | solo miniaturas (mono8 20×20 = 448 B BE; 80×60 = 4 848 B fiable); si no, relay → JPEG | casi nunca |
| `Image` bgr8, bgra8, 8UC4 | igual + intercambio `.bgr` en shader `canvas_item` | sin shader: `data.reverse()` + `Image.rotate_180()` (1,8 ms en host) o relay en rgb8 | — |
| `Image` bayer_*8 | gris (`FORMAT_L8`), igual que RViz (sin demosaico) | relay (cv_bridge demosaica) | — |
| `Image` bayer_*16, rgb16, bgr16, rgba16, 16UC3/4, 32FC2+, 64FC* | **hueco** (sin código): RViz2 tampoco los muestra (salvo bayer16 como 8 bit mal leído) | relay | — |
| `Image` 16UC1 / mono16 | `FORMAT_R16` (unorm) + shader con rango y paleta (`z = r·65,535` m) | relay → JPEG coloreado / mono8 | — |
| `Image` 32FC1 | `FORMAT_RF` + shader (0/NaN/Inf transparentes) | relay; 40×30 = 4 848 B fiable (lo que hace `camara.gd`) | — |
| `Image` 16SC1 | `FORMAT_R16I` + shader con `usampler` **[?]** (hueco) | relay | — |
| `Image` yuv422(=uyvy), uyvy, yuyv, yuv422_yuy2 | bytes tal cual como RGBA8 de ancho/2 + shader YUV→RGB | relay | — |
| `Image` nv21, nv24 | hueco: `FORMAT_R8` de alto·1,5 + shader semiplanar (sin código) | relay | — |
| `CompressedImage` jpeg / png | `load_jpg/png_from_buffer` (motor) + `update` | **igual**, QoS fiable (H22) | solo JPEG ≤ 452 B; fiable ≤ ~7,5 KiB |
| `CompressedImage` compressedDepth | **no en Godot**: `image_transport republish compressedDepth raw` y ficha 16UC1/32FC1 | relay | — |
| `CameraInfo` | frustum de 8 líneas (`ImmediateMesh`) + `Camera3D.set_frustum` desde K | cabe (381 B plumb_bob); frustum como prismas o en 2D | **sí** |
| Camera (imagen + escena) | `SubViewport` con fondo transparente y Camera3D en el frame óptico, sobre la imagen | sin SubViewport 3D: «modo cámara» con la cámara principal + imagen HUD | — |
| DepthCloud | **GPU**: textura R16/RF + malla de w×h puntos desproyectada en el vertex shader con K (0 bucles) | relay → `/vita/nube2d` | no |

## 2. Decodificadores comunes y dónde corre cada uno

Regla de corte de `docs/31 §4.1` aplicada (relay si > 488 B → C++ del motor → GDScript si ≤ 2 ms → C `viz-decode`):

| Decodificador | Qué hace | PC | Vita |
|---|---|---|---|
| **PointCloud2 genérico** | `off[name] = offset` desde `fields`; `decode_float(i·point_step + off)`; `is_bigendian` → `bswap32()` (solo si todos los campos son de 4 B); NaN fuera con `Vector3.is_finite()`; `rgb` = `decode_u32` → `Color8`; diezmado `paso = ceil(n / max)` | GDScript: ≈ 0,2 µs/punto (10k = 1,9 ms) [V host]. Ruta rápida si xyz(i) float32 contiguos: `to_vector3_array()`/`to_vector4_array()` (36–48 µs/10k, Godot ≥ 4.7) [V]. Para > 50k pts a 10 Hz: **textura RGBAF/RF + vertex shader con `VERTEX_ID`** (hueco, recomendado) | no se decodifica PointCloud2: el relay manda Int16; `vizd_cloud_cm` en C cuando exista (docs/31:195) |
| **Conversor de codificaciones** | tabla `encoding → Image.Format` + modo de shader (0 directo, 1 bgr, 2 R16, 3 RF, yuv aparte) | todo en GPU; CPU ≈ 0 (create_from_data 2 µs; R16 0,3 ms a 640×480) | solo rgb8/mono8/JPEG/PNG; bgr sin shader con `reverse()+rotate_180()`; lo demás en el relay (cv_bridge) |
| **Mapas de color** | arcoíris de RViz (HSV 0→0,833) en LUT de 256 para puntos; `GradientTexture1D` para imágenes; paleta de 16 por altura en 2D | LUT en GDScript / gradiente en shader | LUT de 16 en 2D (color por vértice gratis, H16); en 3D la textura-paleta de docs/31 §2.1 |
| **Tabla de direcciones del scan** | cos/sin recalculados solo si cambian `angle_min`, `angle_increment` o n | 720 rayos: 711 → 263–340 µs | arreglo ya propuesto en docs/31:210; C `vizd_scan_xy` después |
| **JPEG/PNG** | motor (libjpeg-turbo sin SIMD en la Vita) | 1,7 ms 640×480 | 3–6 ms 160×120 con subida [I] |

## 3. Hallazgos que afectan a otros posts / al código

1. **Paridad de QoS rota [V]:** en `ros2_vita` `RosQoS` solo tiene `set_reliability()` (sin `ADD_PROPERTY`,
   `godot/ros2_vita/ros_runtime.cpp:76-92`); `qos.reliability = …` da «Invalid assignment of property» en la Vita
   mientras rclgd lo acepta (`ros_qos.cpp:27-28`). **Escribir siempre `qos.set_reliability(...)`** (portable) o añadir
   las propiedades al módulo. Falta en `godot/ros2_vita/API_PARITY.md:79`.
2. **REP-117 y NaN [V]:** `if r < min or r > max: continue` deja pasar NaN; el filtro correcto es
   `if not (r >= min and r <= max)`. Revisar cualquier display de scan que use la forma directa.
3. **Ejes sin bucle [V]:** `basis = Basis(Vector3(0,0,-1), Vector3(-1,0,0), Vector3(0,1,0))` en el nodo del display
   equivale a `rclgd.ros_to_godot_vector` (comprobado con (1,2,3) → (−2,3,−1)); los puntos se quedan en ROS.
4. **PNG de 16 bit [V]:** el cargador PNG de Godot baja a 8 bit (`png_driver_common.cpp:72-106`) → compressedDepth
   y cualquier PNG de profundidad no se pueden leer en Godot sin pérdida.
5. **`FORMAT_R16`, `to_vector*_array`, `bswap*` [V]** existen en Godot 4.7 estable (rclgd) y en 4.8-dev7 (Vita), no
   en 4.4: si alguien usa un editor viejo, el código no compila.
6. **Coste de recepción [V host]:** `RosMsg.deserialize` de una PointCloud2 de 160 KB ≈ 2,6 ms en ros2_vita (host);
   en rclgd los arrays planos son `memcpy` y perezosos (`ros_msg.cpp` caché por miembro). `PointCloud` y
   `MultiEchoLaserScan` envuelven un `RosMsg` por elemento (camino lento de arrays compuestos).
7. **El relay no tiene aún nube ni cámara** (`docker/scripts/vita_relay.py`): `/vita/nube2d` y `/vita/camara` están
   solo diseñados (`docs/27:106-107`). Propongo para `nube2d` la cabecera `[seq, trozo, n_trozos]` (486 B con 78 pts).

## 4. Decisiones tomadas (y por qué)

- **PC: `PRIMITIVE_POINTS` + color por vértice**, no `MultiMeshInstance3D`: un punto = 1 vértice (16–28 B) frente a
  una instancia con transform (48–64 B) y la misma malla; RViz también usa puntos/sprites por defecto. MultiMesh
  solo para el estilo «Boxes/Spheres» (hueco).
- **Imagen: conversión en GPU en el PC, en el relay para la Vita.** Ningún bucle por píxel en GDScript (14–35 ms por
  640×480 en host: inviable incluso en el PC a 30 Hz).
- **compressedDepth y bayer de color: fuera de Godot** (republicador / relay): menos código y sin pérdida.
- **DepthCloud en GPU**: RViz lo hace en CPU; en Godot el vertex shader evita 300k iteraciones de GDScript.

## 5. Huecos

- Ruta GPU para PointCloud2 grandes (textura + `VERTEX_ID`), estilos Boxes/Spheres, *autocompute* del rango de color.
- Filas con relleno (`step ≠ width·bpp`), nv21/nv24, 16SC1, codificaciones de 16 bit de color, demosaico bayer.
- Sincronizar imagen y TF por `stamp` en el display Camera (necesita `lookup_transform` con tiempo; en la Vita no hay
  listener).
- Orden exacto del arcoíris de RViz (`getRainbowColor`, solo leído parcialmente) [?] → parámetro `invertir`.
- Medidas en la Vita: todo lo de §2 en columna Vita es [I] hasta E-W8 / gates de las fichas.
