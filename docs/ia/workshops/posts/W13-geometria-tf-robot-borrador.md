# W13 · geometria-tf-robot — borrador (ronda 1, 2026-11-13)

> Investigador `geometria-tf-robot` (Opus 5.5). Fichas completas en `W13-geometria-tf-robot.json` (22 fichas, código
> GDScript de 40 líneas como máximo en cada una). Marcas: [V] verificado en código o docs · [I] inferido · [?] por medir o dudoso.
> No he leído los demás posts de W13.

## 1. Tabla tipo → visualizador

CDR calculado con la regla de doc 27, con frame_ids cortos y los 4 B de encapsulado. La calculadora casa con las medidas
de doc 27: PoseStamped 76, Odometry 724, Path 100 = 7 228 y TFMessage 1 = 108 [V]. Tope best effort (BE): 488 B
(`docs/27-xrce-limites-y-relay.md:10`). Columna «Esq.»: si el tipo ya está en `TIPOS` de
`godot/plantillas/generar_esquemas.py:12-39`.

| Tipo | CDR (B) | ¿BE? | Esq. | PC (rclgd) | Vita (ros2_vita) |
|---|---:|:-:|:-:|---|---|
| Point/PointStamped | 44 | sí | no | esfera + historial | esfera 8 tri, pool ≤ 20 |
| Vector3/Vector3Stamped | 52 | sí | no | flecha desde el origen del frame | igual (24 tri) |
| Pose/PoseStamped | 76 | sí | sí | flecha o ejes (RViz Pose) | 3D 1 instancia; planta: triángulo (g6-hmi) |
| PoseArray | 28+56n | n ≤ 8 | no | pool de flechas (MultiMesh si > 500) | relay [x,y,yaw]·n (≤ 39 poses) → triángulos 2D en 1 lote |
| PoseWithCovarianceStamped | 364 | sí | no | flecha + elipsoide 2σ translúcido + discos de orientación | **planta 2D**: elipse polilínea + abanico de yaw; 3D: disco opaco |
| Twist/TwistStamped/…WithCov | 52/76/364 | sí | Twist, TwistStamped | ScrewDisplay (lineal + angular con anillo) | barras HUD + flecha de mando (g6-hmi); 3D opcional |
| Accel/AccelStamped/…WithCov | 76/364 | sí | no | ScrewDisplay | igual |
| Wrench/WrenchStamped | 76 | sí | no | fuerza roja + par amarillo con arco de 315° | arco como cinta (H1), unos 250 tri |
| Quaternion/QuaternionStamped | 60 | sí | no | ejes RGB + RPY en el HUD | igual |
| Transform/TransformStamped | 100 | sí | sí | ejes del hijo + flecha hijo→padre | igual; padre por TfLigero |
| Polygon/PolygonStamped | 28+12n | n ≤ 38 | no | cinta o LINE_STRIP | **planta 2D** (`draw_polyline`); 3D cinta solo si cambia la forma |
| Inertia/InertiaStamped | 108 | sí | no | caja de inercia equivalente + CoM (Jacobi 3×3) | depuración; 2 draws |
| nav_msgs/Odometry | 724 | **no** (fiable, 2 frag) | sí | flechas con tolerancia + keep 100 + covarianza | relay `/vita/pose2d` 40 B; **planta 2D**; 3D keep ≤ 20 |
| nav_msgs/Path | 7 228 (100) | **no** | no | cinta / líneas, un lookup por mensaje | relay `/vita/path_compacto` ≤ 57 pts; cinta ≤ 2 Hz o 2D |
| tf2_msgs/TFMessage | 108·n | n ≤ 4 | sí | display TF sobre `RosTfListener` | **TfLigero** (GDScript) + relay `/vita/tf` troceado |
| JointState + URDF | 1 668 (G1, 29 juntas) | **no** | sí | escena horneada + `set_joints` | relay `/vita/joints` + `/vita/joints_orden` (ya existe) |
| Imu | 316–324 | sí | sí | ejes + flechas acel/giro (como rviz_imu_plugin) | igual; brújula/burbuja en 2D |
| MagneticField | 124 | sí | sí | flecha µT + brújula HUD | igual |
| NavSatFix/NavSatStatus | 125 | sí | sí | rastro ENU + teselas OSM (HTTP) | **solo 2D**, teselas prehorneadas ≤ 9 |
| Range | 52 | sí | sí | cono (RViz Range), alfa 0,5 | cono opaco 16 tri o sector 2D |

Displays de RViz2 jazzy usados como referencia: `plugins_description.xml` de `rviz_default_plugins`. Hay `PointStamped`,
`Pose`, `PoseArray`, `PoseWithCovariance`, `TwistStamped`, `AccelStamped`, `Wrench`, `Polygon`, `Odometry`, `Path`,
`TF`, `RobotModel`, `Effort` y `Range`. Vector3, Quaternion, Inertia, Imu, MagneticField y NavSatFix **no tienen** display de serie [V].

### ¿Cuándo vista planta 2D? (decisión)

ADR 0011 ya define dos vistas (`docs/adr/0011-presupuesto-render-vita.md:34-35`). Para esta familia propongo que la
**planta 2D sea la vista por defecto en la Vita** para lo que vive en el plano del suelo: Odometry, Path, PoseArray,
PoseWithCovariance (caso 2D, el habitual con AMCL), Polygon (huella), NavSatFix y Range (sector). Motivos:
1 comando por display (H17), color por primitiva gratis (H16), sin riesgo de malla dinámica (H7/H9), y es lo que ya
funciona en hardware (g6-hmi, minimapa del G1). La **orbital 3D** se reserva para lo que es 3D de verdad: TF,
RobotModel, Imu, Wrench/Twist, Inertia y Quaternion.

## 2. Primitivas comunes reutilizables (`res://comun/viz/primitivas.gd`)

Regla: **una malla unidad por forma, compartida, creada una vez; cada visual es un `MeshInstance3D` que solo cambia
`transform`**. Así nunca se reconstruye geometría por mensaje (H9: cada cambio de malla tira su caché y gasta arena),
no hay riesgo H7 y el coste por mensaje es solo de CPU. Material: `albedo_color` con a = 0,99, que según H8 deja la
superficie fuera de la pasada de luz por vértice. Es 1 draw por instancia en vez de 2.

| Primitiva | Construcción (solo `PRIMITIVE_TRIANGLES`) | Tri | Uso |
|---|---|---:|---|
| **Flecha** | asta (tubo de 6 lados) + punta (cono de 6 lados) a lo largo de **−Z** (= +X de ROS); `flecha_hacia(v)` = `Basis.looking_at(v)`, con escala z = \|v\| | 24 | Pose, Odometry, Twist/Accel/Wrench, Vector3, Imu, enlaces TF |
| **Ejes** | 3 cajas finas en una sola malla. Color: en el PC, color por vértice; en la Vita **UV a la textura-paleta** (sin color por vértice, H3; doc 31 §2.1) | 36 | TF, Quaternion, Transform, Pose (forma ejes) |
| **Esfera** | octaedro (Vita) o icosfera de 1 subdivisión (PC) | 8 / 80 | Point, CoM, elipsoide del PC |
| **Disco/elipse** | abanico de 12 triángulos en el plano XY de ROS; la elipse sale de escalar con `Basis(eje_z, θ)·diag(2√λ1, 2√λ2, ε)` | 12 | PoseWithCovariance en la Vita, huella |
| **Elipsoide** | esfera escalada por `C·(V·diag(2√λ))·Cᵀ` (V = autovectores, C = `BASE_ROS_A_GODOT`); translúcida solo en el PC | 80 | PoseWithCovariance y Odometry 3D |
| **Cono** | vértice en el origen, base en z = −1 y radio 0,5, 8 lados sin tapa (H15: sin culling, se ve por dentro) | 8–16 | Range; abanico de yaw en 3D |
| **Arco/anillo** | cinta de 28 segmentos sobre un arco de 315° (como `wrench_visual.cpp`, bucle i = 4..32) + flecha tangente | 56 | par (Wrench), velocidad angular |
| **Cinta (polilínea)** | 2 triángulos por segmento, perpendicular a `UP` (`(b−a)×UP`); se reconstruye solo cuando cambian los puntos y a ≤ 2 Hz en la Vita (ADR 0011 §4) | 2·(n−1) | Path, Polygon |
| **Prisma** | 3 caras por segmento, para líneas en el espacio (enlaces TF largos) | 6/seg | TF, LINE_STRIP 3D |
| **Polilínea 2D** | `draw_polyline` / `draw_multiline_colors` / `canvas_item_add_triangle_array`: 1 comando por display | — | toda la planta 2D |
| **Texto** | `draw_string` en `Camera3D.unproject_position(p)` (tras comprobar `is_position_behind`); **nunca** `Label3D` (ADR 0011 §4) | — | nombres de frames, valores |

Grosor mínimo de cajas finas sin MSAA: `1,5·d/522` m (9 mm a 3 m; doc 31:95). Para ajustarlo se escala la instancia
por tramos de distancia, sin tocar la malla.

**Ejes de coordenadas, la regla única.** Mundo y displays van en **ejes de Godot**. La conversión se hace a la entrada con
`rclgd.ros_to_godot_vector/quat`, la misma función en rclgd y en ros2_vita (`API_PARITY.md:19`) y la misma que usa
`RosTfListener`. Con eso, `lookup_transform` y nuestras poses se componen sin más. Una flecha de ROS (+X) cae en −Z
de Godot, que es lo que da `looking_at`. Las matrices (covarianza, inercia) se pasan de base con `C·B·Cᵀ`, donde
`C = BASE_ROS_A_GODOT` (`godot/plantillas/ros/util_ros.gd:6`). Optimización permitida: para polilíneas largas se
construyen los puntos **en ejes ROS** bajo un nodo hijo con `basis = C`, como el `RosFrame` del URDF horneado
(`godot/g1-unitree/robot/urdf_robot.gd:6`). Ahorra n llamadas al motor.

**Marco fijo.** `en_marco_fijo(tf, fijo, header)` tiene la misma firma en las dos plataformas. En el PC usa
`RosTfListener.lookup_transform(fijo, frame_id, stamp)`; con `null`, el display se oculta y muestra
`get_last_error()`, como hace RViz con «No transform». En la Vita usa **TfLigero**, que ignora `time`, o `null`: entonces se
supone que el frame del mensaje ya es el fijo, lo normal con `odom`/`map` desde el relay. Riesgo en el PC: con el stamp,
un mensaje más nuevo que el último TF falla por extrapolación al futuro. Propongo reintentar sin tiempo y marcar el
display en ámbar [I].

**Autovalores.** `Basis.diagonalize()` existe en C++ (`engine/core/math/basis.h:227`), pero **no está expuesto** a
GDScript (`variant_call.cpp:2490-2507`) [V]. Para el caso 2D hay solución cerrada (ficha PoseWithCovariance). Para el
3D, Jacobi cíclico en GDScript (ficha Inertia, ~15 líneas): sirve en el PC y, en la Vita, solo para mensajes raros.

## 3. Arquitectura que propongo para la familia (para el registro de nucleo-generico)

- Cada display es un `Node3D` (o un `Node2D` en planta) con `@export` de parámetros y
  `configurar(nodo: RosNode, listener)`. No crea ni destruye nodos por mensaje: usa pools circulares, como el
  `keep` de Odometry o el historial de Point.
- Un único listener por app, compartido por todos los displays: `RosTfListener` en el PC y `TfLigero` en la Vita.
- Tipos por texto y `msg: RosMsg` mientras no exista T3.2.4 (`API_PARITY.md:67-69`): así el mismo `.gd` corre en el
  PC y en la Vita.
- En la Vita el display elige fuente con `OS.has_feature("vita")`: topic estándar si cabe en 488 B y relay compacto si
  no. Patrón ya usado en `plantillas/ros/sensor_base.gd:24-38`.

## 4. Huecos y tareas que salen de aquí

1. **Esquemas que faltan en la Vita** (`generar_esquemas.py:12-39`): PointStamped, Vector3Stamped, PoseArray,
   PoseWithCovarianceStamped, AccelStamped (y WithCovariance), WrenchStamped, QuaternionStamped, PolygonStamped,
   InertiaStamped y TwistWithCovarianceStamped. Coste: una línea por tipo y regenerar el `.rsch`.
2. **TF en la Vita:** no hay `RosTfListener` ni `RosTfBroadcaster` (`register_types.cpp:16-22`). Propongo `TfLigero`
   en GDScript ya (ficha con código) y, después, el nativo sobre `modules/tf-tree` con la misma API (P0).
3. **Relay sin módulo `tf`** (`vita_relay.py:21,138`: scan, pose, joints, mapa, path). Hace falta un módulo `tf`:
   lista blanca de frames, trozos de ≤ 4 transforms a 30 Hz BE en `/vita/tf`, y `/tf_static` fiable +
   TRANSIENT_LOCAL en `/vita/tf_static`.
4. **Relay de PoseArray** ([x,y,yaw]·n, ≤ 39 por datagrama) y **covarianza en `/vita/pose2d`**: ampliarlo a
   [x,y,yaw,vx,vy,wz,σxx,σxy,σyy,σyaw] (56 B) para dibujar la elipse de AMCL/odometría en la Vita.
5. **`SHADING_MODE_UNSHADED` en el port:** no sé si el GXM lo respeta [?]. No bloquea, porque a = 0,99 ya saca la
   primitiva de la luz (H8). Comprobarlo con `lit=` en E-W8-1.
6. **Tests que faltan:**
   - `TfLigero` contra los casos de `modules/tf-tree/tests/parity_test.c`, en headless con ros2_vita en loopback.
   - Jacobi 3×3 contra una caja de inercia conocida.
   - Comprobar que `Callable.bind` funciona como callback de `create_subscription` en ros2_vita [I].
   - Comprobar que en TfLigero `if _padre.has(f): a; b` mete las dos sentencias en el `if` (GDScript lo admite en una
     línea [I]).
7. **Presupuesto TF:** con 32 frames, ejes + flechas suman 64 instancias, por encima de las 32 de ADR 0011. En la Vita,
   flechas hijo→padre apagadas por defecto o llevadas a la planta 2D.
8. **NavSatFix:** no guardar latitud/longitud en `Vector2`, que es float32 (1e-5° ≈ 1 m). Teselas: como mucho 9 a la vez en la Vita
   (H19 y 48 texturas). En el PC, respetar la política de uso de los servidores de teselas de OSM [I].
9. **Effort display** (JointState.effort como color o anillo por junta) y **modo «TF por link»** del RobotModel en el
   PC: sin código todavía.
10. **Terceros sin equivalente en RViz de serie:** Imu (rviz_imu_plugin de imu_tools), NavSatFix (rviz_satellite y el
    panel Map de Foxglove). Diseño propio [I], para que lo revise el escéptico.

## 5. Medición (resumen de los criterios de verde de las fichas)

- **3D:** con `[gxm3d] drawn=` y `lit=` (H24) se comprueba que las primitivas no entran en la pasada de luz (`lit=` = 0).
  Verde: FPS ≥ 59 (HMI) y `avg_submit_us` ≤ 9 000 (E-W8-1).
- **2D:** `[gxm2d-canvas] avg_canvas_us` (H18) por debajo de 500 µs para la planta con Odometry + Path + NavSatFix.
- **CPU de GDScript:** `[perfil-gd]` por display (`godot/plantillas/ros/perfil.gd`), como mucho 1 000 µs por fotograma
  sumando todos los de la familia.
- **Paridad visual con RViz2:** capturas lado a lado en el PC con las mismas tolerancias y escalas. Error < 1 cm / 1°
  en poses y ± 5 % en elipses.
