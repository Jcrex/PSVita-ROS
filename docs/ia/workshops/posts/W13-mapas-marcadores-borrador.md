# W13 · mapas-marcadores — borrador (ronda 1, 2026-11-13)

> Autor: `mapas-marcadores` (Opus 5.5). Fichas completas en `W13-mapas-marcadores.json` (32 fichas, esquema W13).
> Marcas: [V] verificado en código/doc citado · [I] inferencia · [?] sin confirmar. No he leído los demás posts W13.
> Tamaños CDR medidos en esta sesión con `toolchains/rosbags-venv` (Stores.ROS2_JAZZY) [V].

## 1. Tabla tipo → visualizador

| Tipo | PC (rclgd) | Vita (ros2_vita) | ¿Cabe en 488 B? | Vía Vita |
|---|---|---|---|---|
| OccupancyGrid «map» | quad 3D + **shader de paleta** (datos `to_byte_array()` → RGBA8, sin bucles) | quad(s) 3D con textura troceada 128² (H19), LUT+`blit_rect` | no (384² = 147 560 B) | relay VC/1 2 bit (ya existe) |
| OccupancyGrid «costmap» | mismo display, paleta costmap (0 transparente) | compuesto en CPU sobre la textura del mapa (sin orden de transparencias) | no | **propuesto** `/vita/costmap_tesela` 4 bit 32×16 (260 B) |
| OccupancyGrid «raw» | paleta gris | no aplica | — | — |
| map_msgs/OccupancyGridUpdate | `blit_rect` del parche + `update` ≤ 10 Hz | teselas sucias del relay | ≤ 21×21 [I] | relay (hueco: la época) |
| nav_msgs/GridCells | MultiMesh de losas | 2D (1 lote) o fundido en la tesela | ≤ 18 celdas | directo pequeño / relay |
| nav_msgs/MapMetaData | HUD | HUD | sí (84 B) | directo |
| nav2_msgs/Costmap (raw) | R8 directo + paleta con la traducción de Nav2 | como costmap | no | relay |
| nav2_msgs/VoxelGrid | MultiMesh de vóxeles marcados (o la PointCloud2 de Nav2) | no directo | no | relay → nube/tesela |
| grid_map_msgs/GridMap | malla de alturas con color por vértice | raster 2D; 3D estático tras E-W8-2 | no | relay |
| octomap_msgs/Octomap | **viable**: decodificador binario en GDScript (2 B/nodo) → MultiMesh | no directo | no | relay → lista de vóxeles |
| Marker ARROW (pose) | malla unidad flecha | 3D instancia rígida, paleta | sí (229 B) | directo |
| Marker ARROW (points) | cuerpo + cabeza (2 instancias) | igual | sí (277 B) | directo |
| Marker CUBE/SPHERE/CYLINDER | malla unidad compartida + escala | 3D instancia, paleta (1 draw, sin luz) | sí | directo |
| Marker LINE_STRIP | prismas 6 tri/seg, color por vértice | **2D** `draw_polyline_colors` | ≤ 10 puntos | directo / relay |
| Marker LINE_LIST | prismas | 2D; rejillas estáticas = cinta 3D con paleta | ≤ 10 puntos | directo / relay |
| Marker CUBE_LIST / SPHERE_LIST | MultiMesh `use_colors` | malla horneada con paleta (≤ 64, ≤ 1 Hz) o 2D | ≤ 10 | relay |
| Marker POINTS | MultiMesh o 2D | **2D** un lote | ≤ 10 | relay |
| Marker TEXT_VIEW_FACING | Label3D billboard | **Label** del HUD en `unproject_position` | sí (249 B/20 car.) | directo |
| Marker MESH_RESOURCE | tabla `package://`→`res://`; GLTFDocument para .glb | solo mallas horneadas en el .pck | sí (URI) | directo |
| Marker TRIANGLE_LIST | ArrayMesh con ARRAY_COLOR | ArrayMesh con UV a paleta (sin pasada de luz) | ≤ 3 tri | relay |
| Marker ARROW_STRIP (12) | LINE_STRIP + punta [?] | igual | — | — |
| MarkerArray | gestor + chequeo de duplicados | **siempre relay**: estado completo `/vita/marcadores` | no (50 CUBE = 11 605 B) | relay (pendiente) |
| InteractiveMarker(+Update) | cliente propio: servicio + `<ns>/update` + asas Area3D | relay hace de cliente (sin servicios en ros2_vita) | update 1 pose = 132 B | relay |
| InteractiveMarkerFeedback | publicar POSE_UPDATE ≤ 20 Hz al arrastrar | **directo** con táctil frontal | sí (149 B) | directo |
| ImageMarker | Control `_draw` sobre la imagen | igual (solo 2D) | ≤ 15 puntos | directo |
| shape_msgs SolidPrimitive / Mesh / Plane | fábrica (SPHERE = **radio**) / ArrayMesh indexada / PlaneMesh | estáticos, paleta | depende | relay |

Regla de capa en la Vita (ADR 0011, docs/31 §0): **sólido rígido → 3D por instancia** (mover = `set_transform`,
0 B de arena); **líneas, puntos, texto → 2D** en un comando por display (H16–H17); **raster → textura**.

## 2. Gestor de marcadores (ficha «Marker (gestor)»)

Semántica copiada de RViz2 Jazzy (`marker_common.cpp`, `marker_base.cpp`):

- **Clave:** diccionario de dos niveles `ns → {id → entrada}`. DELETEALL con `ns` no vacío borra solo ese ns
  (`marker_common.cpp:224-229`) [V]: con dos niveles es `O(n del ns)`, no un barrido de todo (RViz lo deja como TODO,
  `:112`).
- **Acciones:** 0 ADD = MODIFY; 2 DELETE; 3 DELETEALL. Si cambia `type` se recrea (`:282-287`). NaN/Inf ⇒ se rechaza (`:195-213`).
- **Caducidad:** si `lifetime` > 100 000 ns, `expira = now + lifetime` en el reloj **de recepción**
  (`:305`, `marker_base.cpp:84`). En Godot: `Time.get_ticks_msec()`; barrido a 4 Hz en `_process`.
- **frame_locked:** sin él, el transform se resuelve una vez con `header.stamp`; con él, cada fotograma
  (`marker_base.cpp:100-115`). PC: `RosTfListener.lookup_transform(fixed, frame, stamp)` (devuelve Transform3D en ejes
  Godot o `null`). Vita: sin TF listener (API_PARITY.md:36) ⇒ solo marco fijo o frames del robot local.
- **Reciclado:** los nodos borrados se ocultan y vuelven a un pool por tipo; nunca `queue_free` en régimen estable
  (cero asignaciones, nº de hijos constante). Tope `max_marcadores` = 48 en la Vita (ADR 0011: 3 000 tri, 48 draws).
- **Orden:** primero el transform del marco·pose, después `Fab.aplicar` (que fija malla, material y `scale`).
- API extra que usan otras fichas: `mover_ns(ns, t)`, `borrar_ns(ns)` (marcadores interactivos), `poner_compacto(clave,
  tipo, t, escala, color)` y `retener_solo(claves)` (cliente del relay).

## 3. Fábrica de primitivas (`res://comun/viz/fabrica.gd`, propuesta)

Un único script estático compartido por Marker, InteractiveMarker, shape_msgs y otros displays:

| Función | Qué hace |
|---|---|
| `malla(forma)` | mallas **unidad** cacheadas: CUBO=1, ESFERA=2, CILINDRO=3 (mismos números que `Marker.type`), FLECHA, CILINDRO_Z/CONO_Z (eje −Z para flechas de puntos), CONO. Segmentos 32 en PC, 8 en la Vita |
| `escala(s)` | ROS (x,y,z) → ejes locales de Godot `(s.y, s.z, s.x)` (de `ros = (−g.z, −g.x, g.y)`) |
| `pose(p)` | Pose → Transform3D con `rclgd.ros_to_godot_vector/quat` (existen en rclgd y ros2_vita, API_PARITY.md:19) |
| `material(c)` | PC: StandardMaterial3D cacheado por `Color.to_rgba32()`, transparente si a < 1 |
| `material_vertices()` | unshaded + `vertex_color_use_as_albedo` + sin culling (líneas, triángulos, MultiMesh) |
| `Paleta.uv(c)`, `Paleta.material()`, `Paleta.color(i, a)` | Vita: textura 16×16 (docs/31 §2.1) con un texel de alfa 0 ⇒ fuera de la pasada de luz (H8, evita H7); UV al centro del texel más cercano |
| `crear(tipo)`, `aplicar(n, m)` | despacho por tipo a `aplicar_forma`, `aplicar_flecha_pose/puntos`, `aplicar_texto`, listas, `malla_triangulos`, `cargar_malla` |
| `lineas_3d(pts, cols, ancho, tira)` | prismas de 3 caras (6 tri/segmento) con color por vértice (PC) |
| `hornear_lista(m, octaedro)` | Vita: CUBE_LIST/SPHERE_LIST en UNA malla con UV de paleta (12 u 8 tri por elemento); tablas `CUBO_CARAS`/`OCTA_CARAS` |
| `primitiva(sp)`, `prisma`, `malla_shape`, `plano` | shape_msgs |
| `resolver(uri)`, `cargar_malla(uri)` | MESH_RESOURCE: `package://` por tabla, `.tscn/.res/.glb` horneados; en PC `GLTFDocument` |

Material de la Vita: una variante de malla unidad por (forma, texel) cacheada (≈ 1 KB cada una) en lugar de N
materiales: 1 draw por marcador y sin pasada de luz. Opción «sombreado» = material con `albedo_color` (2 draws, H4).

## 4. Formatos compactos propuestos (relay, ADR 0012; ninguno implementado)

| Salida | Tipo | Contenido | Tamaño |
|---|---|---|---|
| `/vita/costmap_tesela` | UInt8MultiArray BE | `[ver_lo, ver_hi, tx, ty, 256 B]`, tesela 32×16 a 4 bit: 0 desconocido, 1 libre, 2–13 degradado, 14 inscrito, 15 letal | 260 B |
| `/vita/marcadores` | Float32MultiArray BE 5 Hz | `[seq, trozo, n_trozos, n]` + 10 floats/marcador `[clave, tipo, x, y, z, yaw, sx, sy, sz, color]`; **estado completo**, no acciones | ≤ 114 floats = 472 B, 11 marcadores |
| `/vita/marcador_puntos` | Float32MultiArray BE | `[seq, clave, tipo, color, n, x0, y0, z0, …]` | ≤ 37 puntos |
| `/vita/marcador_texto` | String fiable al cambiar | `clave|x|y|z|texto` | pequeño |
| `/vita/im_poses` | Float32MultiArray BE | `[n, x, y, z, yaw]×n` de los marcadores interactivos | ≤ 23 IM |

`clave = id ⊕ hash(ns) & 0xFFFFFF` (exacta en float32). `color = índice de paleta + 256·alfa(0–15)`. docs/27:79,105
proponía 8 floats/marcador (14 por datagrama); amplío a 10 para no perder escala anisótropa ni alfa [I, decisión].
Mandar el estado completo hace que un DELETE perdido en BE no deje marcadores fantasma.

## 5. Huecos y riesgos encontrados

1. **Esquemas Vita:** `generar_esquemas.py:12-38` no incluye `visualization_msgs/*`, `nav_msgs/MapMetaData`,
   `nav_msgs/GridCells` ni `shape_msgs`; están en el typestore de rosbags y bastaría añadirlos. `map_msgs`,
   `nav2_msgs`, `grid_map_msgs` y `octomap_msgs` **no** están (habría que registrar los .msg como con control_msgs,
   `:48-51`) [V].
2. **Relay, época del mapa:** `vita_relay.py:234` sube `version` con cada OccupancyGrid; con costmaps (1–5 Hz) o con
   `_updates` cada cambio sería una época nueva. Hay que separar «época» (tamaño/origen) de «teselas sucias» [V código; I impacto].
3. **Relay sin marcadores ni costmap:** módulos actuales `scan, pose, joints, mapa, path` (`vita_relay.py:137`) [V].
4. **InteractiveMarker en la Vita** depende del relay porque `create_client` está ⏳ (API_PARITY.md:31). El feedback sí
   puede ir directo; falta comprobar que la QoS del suscriptor `<ns>/feedback` del servidor case con un publicador BE [?].
5. **Panel trasero** no leído por el port (docs/28:15, :59): el uso propuesto (rotar con el trasero) espera ese parche.
6. **MESH_RESOURCE** en la Vita: solo horneado; módulo gltf de la plantilla sin verificar (docs/24:114) [?].
7. **ARROW_STRIP (12)**: está en Marker.msg de Jazzy pero RViz2 Jazzy no lo dibuja (marker_factory.cpp:71-103) [V];
   semántica propia [?].
8. **Tipo de `uint32[]` en rclgd** (VoxelGrid, MeshTriangle) no comprobado [?]; el código indexa sin tipar.
9. **Rolling costmap local:** su origen se mueve con el robot ⇒ meta y teselas nuevas continuamente; en la Vita
   conviene el costmap global o un local submuestreado [?] hasta medir.
10. **GDScript de los esqueletos** escrito contra la API citada pero no ejecutado; el revisor debería pasarlo por
    `godot --headless --check-only` [I].

## 6. Pruebas en hardware propuestas (criterio de verde)

| Gate | Prueba | Verde |
|---|---|---|
| G-W13-M1 | 48 CUBE/SPHERE/CYLINDER moviéndose a 10 Hz | `drawn` +48, `avg_submit_us` ≤ 9 000, `invalidations` sin cambio, ≥ 30 FPS |
| G-W13-M2 | 48 marcadores con lifetime 2 s y DELETEALL por ns, 5 min | nº de hijos constante, `[vita-memory]` estable |
| G-W13-M3 | `/vita/marcadores` con 10 % de pérdida (netem) | sin fantasmas > 0,4 s, process ≤ 4 ms, ≤ 15 KB/s |
| G-W13-M4 | mapa 384² por relay con LUT+`blit_rect` | process ≤ 4 ms, textura estable 5 min |
| G-W13-M5 | costmap 4 bit (Nav2 + TB3) | refresco completo ≤ 3 s, ≥ 30 FPS |
| G-W13-M6 | arrastre táctil de `basic_controls` | POSE_UPDATE ≈ 20 Hz, latencia < 150 ms |
| G-W13-M7 | LINE_STRIP 50 puntos y POINTS 180 en 2D con cámara orbitando | process + canvas ≤ 2–3 ms |
