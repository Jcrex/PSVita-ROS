# W4 — Matriz de portabilidad Ozuba → godot4-vita + ros2_vita (borrador)

> Autor: investigador-portabilidad (opus), perspectiva *Godot render + ROS 2 viz*. 2026-11-11.
> Fuente única de inventario: `docs/ia/workshops/posts/W4-inventario.json`. Clones de solo lectura
> (`scratchpad/ozuba/{gdviz,rclgd_sensors,rclgd_arm_demo}`), sin ejecutar nada.
> Marcas: **[V]** verificado en código/doc citado · **[I]** inferencia · **[?]** duda abierta.

**Abreviaturas de ruta**

| Prefijo | Ruta real |
|---|---|
| `gv:` | clon `gdviz/addons/gdviz/` |
| `gvx:` | clon `gdviz/` (raíz: `examples/`, `addons/rclgd/`, `README.md`) |
| `rs:` | clon `rclgd_sensors/addons/rclgd-sensors/` |
| `arm:` | clon `rclgd_arm_demo/` |
| `GXM:` | `toolchains/godot4-vita/engine/platform/vita/rasterizer_scene_gxm_vita.inc` |
| `TEX:` | `toolchains/godot4-vita/engine/platform/vita/rasterizer_gxm_vita.cpp` |
| `rv:` | `godot/ros2_vita/` |

---

## 0. Hechos del motor y del transporte que deciden la matriz

### 0.1 Lo que dibuja realmente el 3D GXM (más restrictivo que «sin shaders»)

| # | Hecho | Evidencia | Consecuencia para gdviz |
|---|---|---|---|
| R1 | Solo se dibujan superficies `PRIMITIVE_TRIANGLES`; las demás se saltan | `GXM:70`, `GXM:968` **[V]** | `PRIMITIVE_LINES`/`LINE_STRIP`/`POINTS` **invisibles**: `VizShapes.lines/line_strip` (`gv:core/viz_shapes.gd:146,160`) y la nube (`gv:core/viz_point_cloud.gd:173`) |
| R2 | Solo instancias cuya base es un `Mesh` (`owns_mesh`) | `GXM:912` **[V]**; MultiMesh es `DummyMultiMesh` en el almacenamiento base (`servers/rendering/dummy/storage/mesh_storage.h:56`) **[V]** | `MultiMeshInstance3D` **no se dibuja**: `VizPoseVisuals` (`gv:core/viz_pose_visuals.gd:16-17`) ⇒ TF, Odometry, Path, Pose, PoseArray, PoseWithCovariance, vectores; `CUBE_LIST`/`SPHERE_LIST` (`gv:displays/_marker_base.gd:269-280`); `point_stamped.gd:21-22` |
| R3 | Color = `albedo` del material × luz (+ textura `texture_albedo`/`albedo_texture`/`texture`); el aplanado solo copia xyz+uv | `GXM:725-733`, `GXM:1010-1011`, `GXM:77-90` **[V]** | `vertex_color_use_as_albedo` (`gv:core/viz_materials.gd:62,79`) **se ignora**: ejes RGB salen de un color, marcadores con `colors[]` monocromos |
| R4 | `ShaderMaterial` no ejecuta su shader; el backend solo lee parámetros con nombres de albedo/textura | `GXM:755-762` **[V]** | `point_cloud.gdshader` y `occupancy_grid.gdshader` **no corren** (coincide con ADR 0008 enmienda) |
| R5 | Solo la pantalla principal (sin SubViewport) | `GXM:839-841` **[V]**; ADR 0008 §5 enmienda **[V]** | `gv:ui/viz_main.gd:19-20,98` (vista 3D dentro de `SubViewportContainer`) y `gv:displays/camera.gd:33,73` |
| R6 | Presupuesto de triángulos 60 000 (ajustable 2 000–80 000) y *culling* por distancia >22–40 m | `GXM:858`, `gxm_camera_lod.h:9-17` **[V]** | Mapas grandes o nubes lejanas pueden desaparecer **[I]** |
| R7 | Cambiar una malla invalida su caché; el espacio GPU se recupera solo al llenarse el *arena* (luego reconstruye todo) | `GXM:184-213` **[V]** | Mallas regeneradas por mensaje (scan, path, nube) ⇒ riesgo de *rebuild* global periódico **[I]**; medir `invalidations`/`arena_kb` del log `[gxm3d]` (`GXM:1251`) |
| R8 | Toda textura se convierte a RGBA8 en C++ y `texture_2d_update` la recrea | `TEX:60-83` **[V]**, `docs/18:91` **[V]** | Mapa/imagen: actualizar a baja frecuencia; formatos `L8`/`RF` se aceptan pero se expanden |
| R9 | Label3D con *billboard*: no hay ruta específica en GXM | sin coincidencias de billboard en `GXM` salvo los *glows* (`GXM:973`) **[V]** | Etiquetas de TF/marcadores: **[?]** probablemente sin orientación a cámara; alternativa 2D (`Camera3D.unproject_position` + `Label` en `CanvasLayer`) |

### 0.2 Transporte XRCE (lo que puede *llegar* a la Vita)

| Hecho | Evidencia |
|---|---|
| MTU 512; *best effort* ≤ ~490 B, mayor se rechaza | `rv:API_PARITY.md:102-103` **[V]** |
| Stream fiable de entrada = 16 huecos × 512 B = 8 KiB; mensaje máx. reconstruido `MAX_RX` 16 KiB | `rv:xrce_transport.cpp:135-137,182,300` **[V]** ⇒ techo efectivo de recepción ≈ 7,5 KiB **[I]** (lo que quepa en 16 fragmentos) |
| Los lectores *reliable* no casan con escritores *best effort* (regla DDS de QoS) | **[I]** (regla estándar DDS); los drivers de lidar/cámara suelen publicar *SensorDataQoS* best effort ⇒ hace falta *relay* en el PC |

Tamaños típicos frente al techo: LaserScan 360 ≈ 2,95 KB (cabe solo en fiable) · OccupancyGrid 384×384 = 147 KB (**no cabe**) · PointCloud2 2 000 pts × 16 B = 32 KB (**no cabe**) · `robot_description` URDF típico decenas de KB (**no cabe**) · JointState 6 ejes ≈ 400 B (cabe en best effort) · TFMessage con 6 transformadas ≈ 660 B (solo fiable) **[I]** (cálculo CDR aproximado).

### 0.3 Superficie real de `ros2_vita` (código, no tabla)

`rv:register_types.cpp:16-22` registra **solo** `rclgd`, `RosMsg`, `RosQoS`, `RosNode`, `RosPublisher`, `RosSubscriber`, `RosTimer` **[V]**. Métodos de `RosNode`: `init, get_name, get_namespace, resolve_frame, create_publisher, create_subscription, create_timer, now, declare/set/get_parameter` (`rv:ros_runtime.cpp:186-198`) **[V]**.

**Discrepancia con `API_PARITY.md`:** la tabla marca `create_tf_broadcaster/send_transform` ✅ y `RosTfListener` 🟡 (`rv:API_PARITY.md:35-36,84`), pero **no hay ninguna clase TF ni `RosLogger` registrada** y `tf-tree` no se enlaza en el módulo (grep vacío en `rv:*.cpp`/`SCsub`) **[V]**. `RosQoS` expone solo `set_/get_*` sin `ADD_PROPERTY` (`rv:ros_runtime.cpp:77-91`) **[V]** ⇒ la sintaxis `qos.durability = …` de gdviz falla en la Vita **[I]**.

---

## 1. Matriz por archivo

Categorías: **TC** tal cual · **AD** adaptar · **C++** reemplazar por C/C++ (módulo dual + `ros2_vita`) · **PC** solo PC · **IMP** imposible en la Vita. Coste S/M/L.

### 1.1 gdviz — `core/` (prioridad)

| Archivo | Cat. | Motivo (evidencia) | Coste |
|---|---|---|---|
| `viz_display.gd` (248) | TC | Nodo base `Node3D`, propiedades, estado; sin GPU **[V]** (`gv:core/viz_display.gd:2-3,111-248`) | S |
| `viz_topic_display.gd` (183) | AD | `qos.history/reliability/durability =` (`:103-105`) necesita propiedades en `RosQoS` **[V]**; `count_publishers` (`:170`) sin API de grafo **[V]** → mensaje «sin datos» | S |
| `viz_context.gd` (172) | AD | `get_topic_names_and_types()` cada 1 s (`:81`) ❌ en XRCE **[V]** → lista de topics de la config o publicada por el PC; `now()` crea un `RosMsg` por llamada (`rv:ros_runtime.cpp:291-298`) **[V]** → cachear por fotograma | S |
| `viz_frame_manager.gd` (199) | AD + C++ | Usa `create_tf_listener`, `get_frame_names`, `frame_exists`, `get_frame_parent`, `get_frame_latest_time`, `lookup_transform(t,s[,stamp])`, `get_last_error` (`:65,91,105,109,111,167-179`) **[V]**; nada existe hoy en `ros2_vita`. `tf-tree` no tiene historial, enumeración ni sello y tope 32 frames (`modules/tf-tree/include/tf_tree.h:10-12,54-80`) **[V]** → ampliar `tf-tree` + clase `RosTfListener`; en GDScript forzar `lookup_mode` LATEST | L (C++) + S (GD) |
| `viz_convert.gd` (184) | TC | Conversión ejes/sellos vía `rclgd.*_vector/quat` ✅ y `RosMsg.from_type` ✅ (`:21,41,88,104`) **[V]** | S |
| `viz_registry.gd` (257) | AD | `GDScript.new()+reload()` (`:134-139`) y rutas `AMENT_PREFIX_PATH` (`:79`) **[V]**; built-ins por `DirAccess` en `res://` funcionan si los `.gd` van en el `.pck` como texto (`docs/18:88-90`) **[I]**. Viabilidad del *runtime compile* en la Vita = otro workshop | S |
| `viz_property.gd`, `viz_status.gd`, `viz_yaml.gd`, `viz_config.gd`, `viz_cloud_field.gd`, `viz_view_controller.gd`, `viz_tool.gd` | TC | Lógica pura (propiedades, parser YAML/.rviz, rayos de cámara) **[V]** (sin APIs GPU ni rclgd fuera de las ✅); `viz_config` usa `FileAccess` → rutas `user://`/`ux0:` **[I]** | S |
| `viz_shapes.gd` (231) | AD (núcleo) | `lines()`/`line_strip()` con `PRIMITIVE_LINES*` (`:137-160`) invisibles (R1) → cintas/prismas de triángulos; `arrow`/`unit_axes` ya son triángulos (`:25-55`) pero con colores por vértice (R3) → una superficie por color | M |
| `viz_materials.gd` (107) | AD (núcleo) | `vertex_color()`/`instance_color()` (`:56-85`) inútiles (R3) → materiales por color con caché; `unlit`/`lit`/`textured_unlit` OK (albedo/textura leídos, `GXM:725`) **[V]**; la iluminación es por objeto según `rendering/vita/per_object_lighting` (`GXM:863,961-962`) **[V]**, no por el flag *unshaded* del material ⇒ colores de viz posiblemente oscurecidos **[?]** (desactivar ese ajuste en la app de viz) | S |
| `viz_pose_visuals.gd` (110) | AD (núcleo) | `MultiMesh` (R2) → hornear N transformadas en **una** `ArrayMesh` por color en CPU (o N `MeshInstance3D` si N ≤ ~50) | M |
| `viz_point_cloud.gd` (351) | C++ / reescribir | Todo el diseño es «blob → textura RF + `VERTEX_ID` en shader» (`:5-16,134-173`) **[V]** ⇒ inviable (R1, R4). Sustituto: puntos decodificados (C) → malla de triángulos (2 por punto, cruz fija o cara a cámara) coloreada por **textura paleta + UV** (R3) | L |
| `viz_image_codec.gd` (259) | AD | rgb8/rgba8/mono8 sin bucles (`Image.create_from_data`, `:40-55`) TC; `bgr*`, 16UC1/32FC1, YUV, Bayer con bucles por píxel (`:130-237`) → caro en GDScript **[I]**; JPEG/PNG por `load_*_from_buffer` (`:74-93`) en C++ del motor, libjpeg/libpng enlazados (`detect.py:228-232`) **[V]** | S (comprimidas) / M (crudas) |
| `viz_mesh_loader.gd` (476) | AD | STL/OBJ/Collada parseados en GDScript (`:96-420`) — lentos a 333–444 MHz **[I]**; `package://` vía ament (`:46-75`) **[V]** → mapear a `res://`; glTF vía `GLTFDocument` (`:420-421`) **[?]** (módulo gltf en la plantilla Vita sin verificar). Mejor: mallas pre-importadas (`.res`/`.glb` importado) en el `.pck` | M |
| `viz_urdf.gd` (298) | TC | `XMLParser` del motor (inventario W4, campo `usa`) **[V]**; ejes vía `rclgd.ros_to_godot_*` (`:216-217`) ✅; coste de parseo una sola vez **[I]** | S |

### 1.2 gdviz — displays

| Archivo | Cat. | Motivo | Coste |
|---|---|---|---|
| **`tf.gd`** (217) | AD | Ejes por `VizPoseVisuals` (`:23`, R2), flechas `VizShapes.lines` (`:168`, R1), `Label3D` *billboard* (`:184-185`, R9) **[V]**; depende de `RosTfListener` (P0) | M |
| **`robot_model.gd`** (248) | AD | Suscripción `/robot_description` TRANSIENT_LOCAL+RELIABLE (`:92-96`) — URDF suele exceder el techo de 7,5 KiB **[I]** → usar la fuente «File» ya existente (`:110-120`) con URDF y mallas en `res://`; materiales URDF son colores planos (R3 OK) | M |
| **`laser_scan.gd`** (68) | AD + C++ | Bucle por rayo con `encode_float` (`:51-63`) **[V]** → coste GDScript (§3); además alimenta `_cloud_display` → `VizPointCloud` (IMP) | M |
| `_cloud_display.gd` (287) | AD | Historial/decaimiento y estilos (pura) TC; renderizador = `VizPointCloud` (L) **[V]** (`:97-140,200-254`) | M |
| `point_cloud2.gd`, `point_cloud.gd` | AD | Delgados sobre `_cloud_display` **[V]**; PointCloud2 no cabe por transporte (§0.2) → solo nubes decimadas por el PC | S (tras L) |
| `depth_cloud.gd` (230) | IMP (tal cual) / PC-pre | Reproyección de profundidad en shader (`gv:core/viz_point_cloud.gd:236-266`) **[V]**; imágenes de profundidad no caben **[I]** → que el PC publique la nube ya decimada | — |
| **`map.gd`** (218) | AD + PC-pre | `ShaderMaterial` + textura RF (`:27-30,166-184`) **[V]** (R4); OccupancyGrid 384² no cabe (§0.2) → PC envía mapa reducido/PNG; Vita: textura RGBA en un quad `StandardMaterial3D` (`texture_albedo`, `GXM:725`) | M |
| `grid_cells.gd`, `polygon.gd`, `grid.gd` | AD | `triangles()` OK salvo color por vértice; `polygon.gd:74` y `grid.gd:103` usan líneas (R1) **[V]** | S |
| **`path.gd`** (164) | AD | Línea `VizShapes.lines` (`:154`, R1) + poses `VizPoseVisuals` (`:22`, R2) **[V]**; `Path` con muchas poses excede 490 B (≈ 60 B por pose) → fiable o recortado **[I]** | S–M |
| **`odometry.gd`** (213) | AD | Rastro `VizPoseVisuals` (`:26`, R2); covarianza `MeshInstance3D` con `unlit` (`:27,97`) OK **[V]**; Odometry ≈ 720 B (dos covarianzas 6×6 float64) ⇒ solo fiable **[I]** (G6 ya recibe `/odom`, `docs/06`) | S |
| **`_marker_base.gd`** (387) + `marker.gd`, `marker_array.gd` | AD | ARROW/CUBE/SPHERE/CYLINDER (mallas `MeshInstance3D`) TC; LINE_* (`:254-258`, R1); CUBE/SPHERE_LIST por MultiMesh (`:269-280`, R2); POINTS → `VizPointCloud` (`:314`); TEXT → `Label3D` (`:333`, R9); colores por vértice (`:256,357,373`, R3) **[V]**. MarkerArray real suele exceder 7,5 KiB **[I]** | M |
| `pose.gd`, `pose_array.gd`, `pose_with_covariance.gd`, `_vector_pair.gd` (+`accel/twist/wrench_stamped.gd`), `point_stamped.gd`, `axes.gd`, `effort.gd`, `range.gd` | AD | Todos pasan por `VizPoseVisuals`/MultiMesh o colores por vértice (`axes.gd:48-54`, `point_stamped.gd:21-53`) **[V]**; se arreglan solos al adaptar el núcleo (§1.1) | S c/u |
| `_scalar_sensor.gd` + `temperature/illuminance/fluid_pressure/relative_humidity.gd` | AD | `Label3D` *billboard* (R9); mensajes pequeños **[V]** | S |
| **`image.gd`** (130) | AD | `TextureRect` en panel 2D (`:28-65`); el lienzo GXM dibuja texturas **[I]** (G6 HMI con Controls, `docs/18:350`); recrear textura por frame (R8) → limitar a ≤ 10 Hz | S |
| **`camera.gd`** (261) | AD (parcial) / IMP (superposición 3D) | Superpone la escena 3D a la imagen con `SubViewport` (`:33,73`) **[V]** (R5) → solo imagen 2D sin superposición | M |
| `interactive_markers.gd` (674) | IMP hoy (P2) | `create_client` + `create_request` (`:119,128`) **[V]**: servicios ⏳ en `ros2_vita` (`rv:API_PARITY.md:32`); además líneas/Label3D | L |

### 1.3 gdviz — tools, views, UI, shaders, otros

| Archivo | Cat. | Motivo | Coste |
|---|---|---|---|
| **`tools/set_goal.gd`** (31) | TC | Solo declara tipo/topic/color sobre `_pose_tool.gd` **[V]** (`PoseStamped` → `/goal_pose`, ~80 B, best effort OK **[I]**) | S |
| `tools/_pose_tool.gd` (128) | AD | Flecha de arrastre con `VizShapes.lines` (`:92-94`, R1) **[V]**; entrada `InputEventMouseButton/Motion` (`:47-70`) → táctil (emulación ratón **[?]**) o stick+botón; `create_publisher(topic, type)` y `RosMsg.from_type` ✅ | S |
| `tools/set_initial_pose.gd`, `publish_point.gd` | AD | Igual que `_pose_tool` / línea **[V]** | S |
| `tools/measure.gd`, `select.gd`, `interact.gd`, `focus_camera.gd`, `move_camera.gd` | AD | Rayos y cámara puros; `measure.gd` usa línea + Label3D (`:32,77`) **[V]**; `interact` depende de interactive markers (P2) | S |
| `views/orbit.gd`, `fps.gd`, `top_down_ortho.gd`, `xy_orbit.gd`, `third_person_follower.gd` | AD | Matemática de cámara TC; entrada de ratón/rueda → sticks/táctil **[I]**; `orbit.gd` usa `SphereMesh` como foco (malla, OK) | S c/u |
| `ui/viz_main.gd` (616) | AD (fuerte) | Vista 3D en `SubViewport` (`:19-20,98`, R5) → 3D en el viewport raíz + UI en `CanvasLayer`; `FileDialog ACCESS_FILESYSTEM` (`:196-197`) → selector propio; `OS.get_cmdline_user_args` (`:598`) → ajustes de proyecto | L |
| `ui/viz_displays_panel.gd`, `viz_property_rows.gd`, `viz_add_display_dialog.gd`, `viz_views_panel.gd`, `viz_tool_properties_panel.gd`, `viz_selection_panel.gd`, `viz_time_panel.gd`, `viz_pick_popup.gd`, `viz_color_popup.gd` | AD | Controles 2D; funcionan en el lienzo **[I]**, pero la densidad es de escritorio (960×544 y táctil) → UI reducida | M (conjunto) |
| `ui/viz_capture.gd` (127) | PC | Captura `get_viewport().get_texture().get_image()` + `quit` para CI (`:100-106`) **[V]**; sin uso en la Vita | — |
| `shaders/point_cloud.gdshader` (233), `shaders/occupancy_grid.gdshader` (65) | IMP | Shaders propios no se ejecutan (R4) **[V]** | — |
| `gvx:addons/rclgd/rclgd.gd` | PC | `EditorPlugin` que genera clases sombra (`gen_editor_support`) **[V]**; eliminado en rclgd actual (`rv:API_PARITY.md:65`) | — |
| `gvx:addons/rclgd/ros_init.gd` | AD | Autoload `rclgd.init(args)` (`:36`) → añadir `-p agent_ip:=…` (`rv:API_PARITY.md:99-101`) | S |
| `gvx:addons/rclgd/gen/*.gd` (≈ 120) | TC (clave) | Clases sombra en **GDScript puro**: `extends RosMsg`, `init("tipo")`, propiedades vía `get_member/set_member` (p. ej. `rclgd_sensors/addons/rclgd/gen/RosSensorMsgsImu.gd:1-20`) **[V]** — todo existe en `RosMsg` de la Vita (`rv:ros_msg.cpp:718-729`) ⇒ **puente gratuito hasta T3.2.4** para `RosXxx.new()` **[I]**; los mensajes *recibidos* siguen siendo `RosMsg` | S |
| `gvx:examples/gdviz_plugins/*.gd` | AD | Contrato de plugin (§4); `battery_display` usa Label3D (R9) | S |
| `gvx:main.tscn` | AD | Solo `Control` + `viz_main.gd` + `viz_capture.gd` **[V]**; quitar `viz_capture` | S |

### 1.4 rclgd_sensors

| Archivo | Cat. | Motivo | Coste |
|---|---|---|---|
| `ros_sensor.gd` (100) | AD | Base pura: `RosNode`, `create_publisher` con `RosQoS` por *setters* ✅ (`:68-73`), `create_timer` ✅, pero `create_tf_broadcaster/send_transform` (`:30-32`) **no existen** hoy (§0.3) **[V]** | S (tras P0 TF) |
| `publish_queue.gd` (57) | TC | `Thread`+`Mutex`+`Semaphore` puros (`:1-57`) **[V]**; `WorkerThreadPool` limitado a 2 no afecta a `Thread` (`docs/18:94-95`) **[I]**; ojo: `publish()` desde hilo secundario, regla de hilos de `ros2_vita` sin verificar **[?]** | S |
| `ros_imu/ros_imu.gd` (119) | AD | IMU simulada sobre `RigidBody3D` (`:49-68`) con GodotPhysics (Jolt off, `detect.py:83`) **[V]**; en la Vita real lo natural es `Input.get_accelerometer/gyroscope` (`docs/18:98-100`, ya hecho en `godot/g7-imu`) **[V]** | S |
| `ros_gps/ros_gps.gd` (69) | TC | Ruido gaussiano + NavSatFix (`:36-67`) puros **[V]**; tras P0 TF | S |
| `ros_camera/ros_camera.gd` (194) + `depth_compositor.gd` + `DepthCapture.glsl` | IMP | `SubViewport` + `RenderingDevice` + `Compositor` (`:27,45,76-125`) **[V]** (R5; sin RD) | — |
| `ros_lidar/ros_lidar.gd` (423) + `lidar_compositor.gd` + `LidarFaceCapture.glsl` + `LidarStitch.glsl` | IMP → reemplazar | Cubemap de 6 SubViewports + compute (`:32-162`) **[V]** → sustituto en GDScript con `PhysicsDirectSpaceState3D.intersect_ray` (360 rayos, ~5 Hz) **[I]** | M |
| `ros_fisheye_camera/*` (+`FisheyeStitch.glsl`) | IMP | Igual que cámara **[V]** | — |
| `*_gizmo.gd`, `sensor_gizmo.gd`, `plugin.gd` | PC | Editor (`EditorNode3DGizmoPlugin`) **[I]** | — |
| `Scenes/sensors.tscn` | AD | `WorldEnvironment` con `PanoramaSkyMaterial` EXR 2k + Sponza glTF **[V]** (listado del `.tscn`) → cielo/escena ligeros | M |
| `Scenes/FreeCam/freecam.gd`, `FpsOverlay/fps_overlay.gd` | AD / TC | Cámara libre con ratón → sticks; overlay de FPS 2D TC **[I]** | S |

### 1.5 rclgd_arm_demo (solo estudio)

| Archivo | Cat. | Motivo | Coste |
|---|---|---|---|
| `Scenes/arm/arm.gd` (304) | AD (patrón) | Planta: sub `/joint_commands` JointState, pub `/joint_states` 100 Hz, TF 50 Hz (`:25-60,142-148,290-302`) **[V]**; `create_subscriber` (`:145`) es el nombre **antiguo** (ros2_vita solo `create_subscription`) **[V]**; clases sombra `RosSensorMsgsJointState` (`:111,148`) **[V]**; `HingeJoint3D` con motores Jolt (`:13,90,133`) → GodotPhysics o `use_physics=false` (FK) **[I]** | M |
| `Scenes/arm/arm.tscn`, `Scenes/sim/SimEnv.tscn` | AD | 6 `RigidBody3D`+`HingeJoint3D`+`.glb` UR5e; cielo EXR **[V]**; triángulos de los `.glb` sin medir **[?]** | M |
| `addons/rclgd-sensors/*` (copia antigua) | IMP / AD | Versión antigua de la §1.4 (`LidarShader.glsl`, `RenderingDevice`) **[V]** | — |
| `addons/freecam_3D/*` | AD | Ratón → sticks **[I]** | S |
| `move.py` (194) | PC | Controlador rclpy en el PC (README:9-40) **[V]** | — |

---

## 2. Paridad de API rclgd ↔ ros2_vita (uso real en los 3 repos)

Recuento de llamadas fuera de `gen/` (grep sobre los clones) **[V]**. «Estado real» = lo que hay en `rv:*.cpp`, no solo la tabla.

| Llamada | Quién la usa (ejemplo) | `API_PARITY.md` | Estado real | Tarea | Prioridad | LT que la necesita **[?]** |
|---|---|---|---|---|---|---|
| `rclgd.init/ok/shutdown` | `gv:ui/viz_main.gd:60-61`, `ros_init.gd` | ✅ | ✅ (`rv:ros_runtime.cpp:344-347`) | — | — | todas |
| `rclgd.godot_to_ros_*` / `ros_to_godot_*` (≈ 49 usos) | `gv:core/viz_convert.gd:21,41` | ✅ | ✅ (`:350-353`) | — | — | todas |
| `RosNode.new()+init` / `resolve_frame` | `rs:ros_sensor.gd:28-31` | 🟡/✅ | ✅ | — | — | todas |
| `create_publisher(topic,"tipo"[,qos])` | `gv:tools/_pose_tool.gd:103` | 🟡 | ✅ con texto | — | — | teleop, planta |
| `create_subscription(topic,"tipo",cb,qos)` | `gv:core/viz_topic_display.gd:124` | ✅ | ✅ | — | — | viz |
| `create_subscriber(...)` (nombre viejo) | `arm:Scenes/arm/arm.gd:145` | — | ❌ | alias o editar script | P2 | planta (estudio) |
| `create_timer` | `rs:ros_sensor.gd:58` | ✅ | ✅ | — | — | planta |
| `now()` (≈ 23 usos, a veces por fotograma) | `gv:core/viz_context.gd:59`, `_marker_base.gd:124` | 🟡 | 🟡 crea un `RosMsg` Time por llamada (`rv:ros_runtime.cpp:291-298`) | sincronizar con el agente; medir coste; cachear en `VizContext` | P1 | viz |
| `RosQoS.new()` + **propiedades** `history/reliability/durability =` | `gv:core/viz_topic_display.gd:103-105`, `robot_model.gd:94-95`, `effort.gd:72` | 🟡 | ❌ sin `ADD_PROPERTY` (`rv:ros_runtime.cpp:77-91`) | añadir `ADD_PROPERTY` (+`depth`) | **P0** | viz |
| `RosQoS` *setters* + constantes | `rs:ros_sensor.gd:68-72` | 🟡 | ✅ | — | — | planta |
| `RosQoS.KEEP_ALL` | `gv:core/viz_topic_display.gd:103` | 🟡 | ✅ constante | — | — | viz |
| `create_tf_broadcaster()` + `send_transform(t, child, parent, static[, stamp])` | `rs:ros_sensor.gd:30-32`, `arm:Scenes/arm/arm.gd:190,296` | ✅ | **❌ no registrado** | implementar (`tf2_msgs/TFMessage` en `/tf`,`/tf_static`; 5.º arg `stamp`) | **P0** | planta, sensores |
| `create_tf_listener(cache)` + `lookup_transform(t,s[,time])`, `get_frame_names`, `frame_exists`, `get_frame_parent`, `get_frame_latest_time`, `get_last_error` | `gv:core/viz_frame_manager.gd:65-179` | 🟡 | **❌ no registrado**; `tf-tree` sin enumeración/sello/padre (`tf_tree.h:54-80`) | clase `RosTfListener` + ampliar `tf-tree` (paridad C/Rust) | **P0** | viz |
| `get_topic_names_and_types()` | `gv:core/viz_context.gd:81` | ❌ | ❌ | sustituto: config o topic `String` JSON publicado por el PC | P1 (lado app) | viz |
| `count_publishers(topic)` | `gv:core/viz_topic_display.gd:170` | ❌ | ❌ | devolver −1/«desconocido» en el script | P2 | viz |
| `declare_parameter/get_parameter` | `gv:ui/viz_main.gd:560-592`, `viz_capture.gd:61-73` | 🟡 | ✅ locales | leer de ajustes de proyecto | — | viz |
| `RosMsg.from_type("…")` | `gv:core/viz_convert.gd:88` | ✅ | ✅ (requiere `.rsch`) | generar esquemas de los tipos de cada display | P1 | todas |
| Clases tipadas `RosXxx.new()` | `rs:ros_imu/ros_imu.gd:27`, `arm.gd:148` | ⏳ T3.2.4 | ⏳; **puente**: clases sombra GDScript de `gen/` compilan contra `RosMsg` | empaquetar `gen/*.gd` del tipo usado | P1 (puente S) | planta, sensores |
| `RosMsg.gen_editor_support` | `gvx:addons/rclgd/rclgd.gd:60` | — eliminado | ❌ | ninguna (solo editor PC) | — | — |
| `create_client` + `create_request` | `gv:displays/interactive_markers.gd:119,128` | ⏳ | ❌ | servicios XRCE | P2 | viz (interactive markers) |
| `get_logger` | (no usado en los 3 repos) | 🟡 | ❌ no registrado | corregir la tabla | — | — |

---

## 3. Decodificación sin shaders: coste por mensaje típico

Supuesto de rendimiento GDScript **[I]** (no hay medida en el repo): ~1–2 µs por operación simple a 333–444 MHz (`docs/18:363` solo cita el riesgo). C en el módulo: ~3–10 ns por elemento **[I]**. Presupuesto de fotograma a 59 FPS ≈ 16,9 ms.

| Mensaje | Bytes en cable | ¿Llega hoy? | (a) GDScript CPU | (b) C en `msg-schema`/módulo dual → `PackedVector3Array`/`Image` | (c) PC pre-decimado | Recomendación |
|---|---|---|---|---|---|---|
| LaserScan 360 | ≈ 2,95 KB | solo fiable (fragmentado) y solo si el publicador es fiable (§0.2) **[I]** | bucle `gv:displays/laser_scan.gd:51-63` + cinta de triángulos: 360 × ~15 ops ≈ **5–11 ms** **[I]** → aceptable a 5 Hz, no a 30 | **< 0,2 ms** + construir 720 triángulos ≈ 0,1 ms **[I]** | relay a fiable; o `int16` cm × 180 rayos ≈ 400 B ⇒ cabe en best effort | (c)-relay QoS **+** (b) si se usa > 5 Hz; (a) válido para el primer hito |
| OccupancyGrid 384×384 | 147 KB | **no** (techo ≈ 7,5 KiB) **[V/I]** | LUT 147 456 celdas × ~4 ops ≈ **0,6–1,2 s** **[I]**; el truco `Image L8` sin bucle no sirve porque `int8[]` llega como `PackedInt32Array` (`rv:ros_msg.cpp:476-484`) **[V]** | ≈ 0,5 ms LUT + conversión RGBA8 del motor (`TEX:66`) **[I]**; no resuelve el transporte | mapa reducido (128×128) como `CompressedImage` PNG ≈ 2–6 KB **[I]** → `load_png_from_buffer` (C++) | **(c)** obligatorio; (b) solo si se sube el techo XRCE |
| PointCloud2 decimada 2 000 pts | ≥ 32 KB (xyz+int f32) | **no** **[I]** | 2 000 × ~30 ops (decode + 6 vértices) ≈ **60–120 ms** **[I]** | ≈ 0,2–0,5 ms decode + malla **[I]**; 4 000 triángulos + 5 574 de G7c ≪ 60 000 (`GXM:858`) **[V]** | ≤ 1 000 pts, xyz `int16` (6 B) ≈ 6 KB fiable; o trozos ≤ 480 B best effort (~80 pts/trozo) | **(c)** + (b); (a) inviable |
| CompressedImage JPEG 160×120 | ≈ 3–6 KB **[I]** | sí, fiable | decode en C++ del motor; sin bucle GDScript | — | el PC fija tamaño/calidad | (a) basta; ≤ 10 Hz por R8 |

**Nota de arquitectura (ADR 0008 §1):** la lógica de decodificación no va en el C++ de `ros2_vita` sino en un módulo dual (`modules/*`, C + Rust, paridad) **[V]** (`docs/adr/0008-godot-via-modulo-estatico.md:22-25`); `ros2_vita` solo la expone (p. ej. métodos estáticos que devuelvan `PackedVector3Array`/`Image`). En el PC (rclgd) hace falta un *fallback* GDScript con la misma firma para que el script sea portable **[I]**.

---

## 4. Contrato del sistema de plugins de gdviz (descripción, sin juicio de viabilidad)

| Aspecto | Contrato | Evidencia |
|---|---|---|
| Tipos de plugin | `.gd` que extiende `VizDisplay`, `VizTopicDisplay`, `VizTool` o `VizViewController`; el tipo se infiere recorriendo `get_base_script()` hasta un `get_global_name()` conocido | `gv:core/viz_registry.gd:17-18,169-181` **[V]** |
| Estáticos obligatorios | `viz_name()` (si falta, se rechaza); `viz_category()`, `viz_description()`, `viz_aliases()`; displays: `viz_message_types()`; tools: `viz_shortcut()`, `viz_is_transient()`, `viz_icon()` | `gv:core/viz_registry.gd:185-198`; `gv:core/viz_tool.gd:29-51`; `gv:core/viz_display.gd:47-74` **[V]** |
| Ganchos de instancia | Display: `_viz_setup/_viz_update/_viz_reset/_viz_fixed_frame_changed/_viz_enabled_changed/_viz_teardown/_viz_create_panel`; TopicDisplay: `_viz_topic_setup`, `_viz_message(msg: RosMsg)`, `_viz_active_message_type`; Tool: `_viz_activate/_viz_deactivate/_viz_input/_viz_update/_viz_cursor`; View: `_viz_look_at/_viz_adopt` | `gv:core/viz_display.gd:111-136`, `viz_topic_display.gd:66-82`, `viz_tool.gd:64-82`, `viz_view_controller.gd:45-69` **[V]** |
| Servicios expuestos | `context` (`VizContext`: `ros_node`, `frames` = `VizFrameManager`, `registry`, `scene_root`, `camera`, `now()`, `topics_of_type()`); `add_property()/add_category()`; `set_status()`; `transform_for(msg)`; helpers `screen_ray/ground_point/pick` en tools | `gv:core/viz_context.gd:23-30,56,89`; `viz_display.gd:171-216`; `viz_tool.gd:94-137` **[V]** |
| Descubrimiento | Built-ins: `load()` de `res://addons/gdviz/{displays,tools,views}`; externos: `<ament>/share/<pkg>/gdviz_plugins/**`, `$GDVIZ_PLUGIN_PATH`, `user://plugins` | `gv:core/viz_registry.gd:65-102` **[V]** |
| Carga en tiempo de ejecución | `GDScript.new()`, `source_code=`, `resource_path=` (para que `preload` relativo resuelva), `reload()`; error ⇒ `load_errors` | `gv:core/viz_registry.gd:126-143` **[V]** |
| Reglas | Prohibido `class_name` en externos; archivos `_*.gd` = bases compartidas, no se listan; profundidad ≤ 8; id `paquete/Nombre`, duplicados rechazados; alias mapean a la misma entrada | `gv:core/viz_registry.gd:19-24,130-131,148-157,199-210` **[V]** |
| Ejemplos | `battery_display.gd` (TopicDisplay), `publish_twist_tool.gd` (Tool que publica `Twist`), `turntable_view.gd` (View) | `gvx:examples/gdviz_plugins/*`, `gvx:README.md:40-64` **[V]** |

---

## 5. rclgd_sensors: lógica pura vs GPU

| Pieza | Pura (portable) | Dependiente de GPU / editor |
|---|---|---|
| `ros_sensor.gd` | ciclo de vida, `_advertise` con QoS, *jitter* inicial, `to_ns`/`write_stamp`, conversiones (`:27-100`) **[V]** | — |
| `publish_queue.gd` | cola acotada con hilo, orden de captura (`:1-57`) **[V]** | — |
| `ros_imu.gd` | derivada de velocidad, gravedad, sesgos *random walk*, covarianzas (`:49-119`) **[V]** — física GodotPhysics **[I]** | — |
| `ros_gps.gd` | error correlacionado y NavSatFix (`:36-69`) **[V]** | — |
| `ros_camera.gd` | construcción de `Image`/`CameraInfo` (`:161-194`) **[V]** | SubViewport, `RenderingDevice`, `Compositor`, `DepthCapture.glsl` (`:27-125`) |
| `ros_lidar.gd` | empaquetado PointCloud2 y campos (`:404-423`) **[V]** | 6 SubViewports + compute + 2 GLSL (`:32-162`) |
| `ros_fisheye_camera.gd` | mensajes (`:213-240`) | SubViewport + `FisheyeStitch.glsl` |
| gizmos / `plugin.gd` | — | solo editor |

---

## 6. rclgd_arm_demo: patrón planta-en-Godot + controlador en PC

- **Patrón [V]** (`arm:README.md:9-40`, `arm:Scenes/arm/arm.gd:1-60`): Godot = planta (actúa por `HingeJoint3D` + servo PID interno, lee ángulos de la física, publica `/joint_states` 100 Hz y todo el árbol TF 50 Hz); `move.py` (rclpy en el PC) = controlador que interpola `JointTrajectory` de `/arm_controller/joint_trajectory` y escribe `/joint_commands` (JointState posición). Interfaz compatible con `joint_trajectory_controller`, así MoveIt/RViz lo mueven sin cambios.
- **Encaje Vita [I]:** JointState 6 ejes ≈ 400 B ⇒ best effort; TF de 6 transformadas ≈ 660 B ⇒ fiable o una `send_transform` por eslabón; 100 Hz de feedback probablemente excesivo para GDScript + XRCE → 30 Hz. Requiere P0 TF broadcaster y alias/cambio `create_subscriber`.
- **Licencia:** sin `LICENSE`, el README no la menciona (`grep -i licen` vacío) **[V]**; solo `package.xml:5` declara `<license>MIT</license>` **[V]**, sin texto ni titular de copyright ⇒ **tratar como sin licencia clara: solo estudiar el patrón, no copiar código** (criterio del encargo).

---

## 7. Licencias y commits estudiados

| Repo | Commit (único en el clon) | Fecha | Licencia | Godot |
|---|---|---|---|---|
| gdviz | `7d05d35ed23a23a67ed403dbdeb967c009313e2e` «Updated tf lookup api» | 2026-08-02 | MIT, © 2026 Miguel Oroz Zubasti (`gvx:LICENSE:1-3`) **[V]** | 4.7.1 (inventario) |
| rclgd_sensors | `420d4d4f2561cc2971cda261f7a32482cb806ccb` «Gizmos, improvements…» | 2026-10-06 | MIT, © 2024 Miguel Oroz Zubasti **[V]** | 4.7 |
| rclgd_arm_demo | `e6c9713d75e226ed47857bd8fefbcb989f642981` «Updated arm logic…» | 2026-06-16 | sin LICENSE; `package.xml` dice MIT **[V]** | 4.6 |

Clones superficiales (1 commit cada uno) **[V]**. Base de paridad: rclgd `4d0a8b3`/`jazzy@fb12a65` (`rv:API_PARITY.md:3-5`) **[V]**; gdviz y rclgd_sensors aún usan clases sombra (`gen/`), anteriores a las clases nativas **[V]**.

---

## 8. Resumen de tareas propuestas

| Id | Tarea | Dónde | Prioridad | Coste |
|---|---|---|---|---|
| T-W4-1 | `RosTfBroadcaster` (`send_transform` 4/5 args) y corregir la tabla de paridad | `rv:` | P0 | M |
| T-W4-2 | `RosTfListener` + ampliar `tf-tree` (enumerar frames, padre, último sello, >32 frames opcional) con paridad C/Rust | `modules/tf-tree`, `rv:` | P0 | L |
| T-W4-3 | `ADD_PROPERTY` en `RosQoS` (history, depth, reliability, durability) | `rv:ros_runtime.cpp` | P0 | S |
| T-W4-4 | Capa «GXM-safe» de gdviz: líneas→cintas, MultiMesh→malla horneada, color por vértice→superficie por color/paleta, Label3D→etiqueta 2D | GDScript (`viz_shapes`, `viz_materials`, `viz_pose_visuals`) | P0 (para viz) | M |
| T-W4-5 | Decodificadores en C (scan→xy, nube→xyz, rejilla→RGBA) + exposición estática + *fallback* GDScript | módulo dual nuevo o `msg-schema` | P1 | M–L |
| T-W4-6 | *Relay* en el PC: QoS fiable, decimación de nubes, mapa→PNG reducido, lista de topics como JSON | `docker/` estación | P1 | M |
| T-W4-7 | Empaquetar clases sombra `gen/*.gd` como puente a T3.2.4 | proyecto Godot | P1 | S |
| T-W4-8 | Sincronizar `now()` con el agente y cachear por fotograma | `rv:`, `VizContext` | P1 | S |
| T-W4-9 | Servicios (cliente) para interactive markers | `rv:` | P2 | L |
| T-W4-10 | Medir: µs/op GDScript, coste de `invalidate_mesh`/arena con mallas dinámicas, Label3D billboard, alpha | hardware | P0 (antes de T-W4-4/5) | S |
