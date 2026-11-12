# 25 — URDF en Godot para la PS Vita: addon `godot-urdf`, `viz_urdf.gd` de gdviz y `tools/urdf2godot`

> **Estado:** cerrado el 2026-11-11 con implementación funcionando: `tools/urdf2godot/` + el proyecto
> `godot/g1-unitree/`, **validado en la Vita a 60 FPS** (usuario, commit `ca510f3`, 2026-11-11). Workshop W5
> (Opus 5.5, `docs/ia/workshops/posts/W5-urdf.json`), revisado por un revisor aislado (**VERIFICADO**, con la
> alternativa «ya existe `tools/urdf2godot`», `posts/revision-oleada1.json`). Decisión en **ADR 0009**.
> Marcas: [V] verificado · [I] inferencia · [?] sin confirmar.

## 1. Resumen

La Vita **no parsea URDF ni lee STL**: recibe una escena `.tscn` ya horneada en el PC con mallas OBJ diezmadas,
los **mismos nombres de link y joint que ROS** y un script cinemático (`urdf_robot.gd`) que aplica `/joint_states`
por nombre. Sin física: Jolt está desactivado en el port (`platform/vita/detect.py:83`) y el addon de la tienda
siempre crea cuerpos rígidos. Primer caso real: Unitree G1, 393 252 → 12 633 triángulos, 60 FPS en la Vita.

## 2. Lo que se estudió

| | Tienda `brean/godot-urdf` | Upstream `askarkg12/godot_urdf` | gdviz `viz_urdf.gd` + `viz_mesh_loader.gd` |
|---|---|---|---|
| Versión estudiada | **v1.2** (la ficha dice v1.0; selector v1.2 «unstable»), zip 32 330 B, sha256 `9a70211a…dd07e`, idéntico al tag v1.2 de codeberg.org/brean/godot_urdf; `main` va 19 commits por delante (2026-11-02) [V] | `5708be4` (2025-04-22), abandonado (issue #5 anuncia el fork) [V] | `7d05d35` (2026-08-02) [V] |
| Licencia | BSD-3 (2026 Andreas Bresser) | BSD-3 (2024) | MIT (2026 Miguel Oroz Zubasti) |
| Tamaño | ~1 900 líneas, 25 `.gd` | ~450 líneas, 9 `.gd`; no compila solo (le faltan los addons godot_xml y stl_importer) | parte de gdviz |
| Modo | `EditorImportPlugin` → `.tscn` (APIs solo de editor) + `urdf_loader.gd` (`@tool`, carga con botón) | solo importación | solo runtime (parsea `/robot_description`) |
| Física | **siempre** RigidBody3D/StaticBody3D + Hinge/Generic6DOF; posado cinemático solo en el editor (`godot_robot.gd:27-31`) | CharacterBody3D por colisión | ninguna (posa por TF) |
| Jerarquía y nombres | aplana la jerarquía; fusiona links fijos (sin nodo para `imu_in_pelvis`, `d435_link`…); bug de nombres en v1.2 (corregido en main `ca9f4d3`) | nodo por link con jerarquía | `"link_"+nombre`, todos los links |
| STL | necesita importador externo: **Godot 4.8-dev no trae importador STL** [V] | addon externo | lector propio binario + ASCII |
| `scale` de malla | no lo lee; escala global por defecto **0,001** | — | sí |
| mimic / prismatic / floating / xacro | falta / FK sí, física bloqueada / falta / falta | falta | parsea, sin FK |

Detalle con `archivo:línea`: `docs/ia/workshops/posts/W5-urdf.json` (tabla P2 completa).

## 3. Opción elegida: hornear en el PC con `tools/urdf2godot`

```
robot.urdf ──urdf2godot.py──► Blender -b (diezma cada malla, OBJ en ejes del link)
                         └──► robot.tscn: Robot(script) → RosFrame(ROS→Godot) → Base(odom→raíz) → links/joints con nombres URDF
Vita: robot.tscn + urdf_robot.gd  ◄── /joint_states (o formato compacto) por nombre ── PC
```

- **Reparto del presupuesto** de triángulos ∝ n^0,75 por malla con mínimo (las piezas pequeñas conservan forma).
- **Transformaciones**: RPY de URDF = Rz·Ry·Rx (ejes fijos); `Transform3D(...)` del `.tscn` **por filas** (comprobado
  cargando la escena en el motor 4.8-dev7: ROS z → Godot y, ROS x → Godot −z) [V].
- **Metadata por joint**: `urdf_type`, `urdf_axis`, `urdf_origin`, `urdf_lower/upper`, `urdf_mimic*`; el script
  aplica `origen · R(eje, q)` (revolute/continuous) u `origen · T(eje·q)` (prismatic) y respeta límites.
- **Render en la Vita**: solo `MeshInstance3D` + `ArrayMesh`/`BoxMesh`/`CylinderMesh` + `StandardMaterial3D`
  (albedo), lo único que el GXM dibuja (W7: sin líneas, MultiMesh ni color por vértice) [V].
- **Soporta**: revolute, continuous, prismatic, fixed (floating/planar → fijos), límites, mimic, STL/OBJ/DAE con
  `scale`, `package://` (`--paquete`), rutas relativas, primitivas, colores. **No**: xacro (expandir antes), colisiones,
  inercias, texturas.

## 4. Medidas

| Caso | Triángulos | Dónde | Resultado |
|---|---|---|---|
| G1 original (29 GDL) | 393 252 | — | inviable (la arena de mallas del port es de 24 MiB; >3 072 vértices por llamada caen a la ruta CPU, `gxm_bridge.c:378`) [V] |
| G1 `g1_vita` | 12 633 | Vita | **60 FPS** estables con la casa (34 cajas) y el HUD (usuario, 2026-11-11) [V] |
| G1 `g1_pc` | 60 633 | PC | 60 FPS |
| Conversión | — | PC | ~2 s (Blender sin ventana) |

## 5. Capa URDF ↔ `ros2_vita`

- **Entrada de juntas:** `set_joints(nombres, posiciones)` acepta un `sensor_msgs/JointState` tal cual. Pero un
  `JointState` de 29 juntas ocupa **1 668 B** de CDR (W2): no cabe en best effort (≤ 488 B) y en fiable se
  fragmenta y bloquea el hilo principal al enviar. Por eso el G1 usa `/g1/estado` (Float32MultiArray de 19 valores,
  76 B, best effort 25 Hz) con el orden de juntas fijado por contrato (`docker/g1/g1_sim.py: JOINTS_PIERNAS`).
  Generalización → relay del PC que reempaqueta `/joint_states` en arrays compactos por robot (doc 27).
- **Pose de la base:** `set_base_pose_ros(pos, quat)` en el marco del mundo de ROS.
- **TF:** publicar o consumir TF desde la Vita está **bloqueado** hasta que exista `create_tf_broadcaster`/listener
  en `ros2_vita` (P0, `API_PARITY.md` corregido el 2026-11-11). Además el TF del G1 ocupa 4,8 KB (W2).
- **`/robot_description` en la Vita:** descartado. Parsear XML en GDScript a 333–444 MHz y leer 19 MB de STL es
  lento, y el URDF no cabe por XRCE (≈ 7,5 KiB de techo fiable) [V/I].

## 6. Pendiente

- Probar `urdf2godot` con un TurtleBot3 (DAE + `package://`) y con el UR5e (patrón de `rclgd_arm_demo`).
- Exportar también los frames fijos útiles (cámara, IMU, LiDAR) como `Marker3D` para colgar sensores.
- Contribución upstream posible a `brean/godot_urdf`: modo «solo visual» y lectura de `scale` (issues abiertas
  #13 xacro, #22) [I].
