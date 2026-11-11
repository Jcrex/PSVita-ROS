# `urdf2godot` — URDF → escena de Godot 4 para la PS Vita (y el PC)

Vía «preprocesar en el PC» de la LT4 (W5, 2026-11-11): la Vita no parsea XML ni STL; recibe una escena `.tscn`
con mallas OBJ ya diezmadas. Primer caso real: Unitree G1 (`godot/g1-unitree`), 393 252 → 12 633 triángulos.

```fish
tools/urdf2godot/urdf2godot.py robot.urdf --proyecto godot/mi-proyecto --dir robot --nombre robot_vita \
    --tris 12000 [--paquete mi_pkg=/ruta/al/paquete]
```

- **Salida**: `robot/<nombre>.tscn`, `robot/mallas_<nombre>/*.obj` e `informe.json` (triángulos antes/después).
  Copiar `urdf_robot.gd` de `godot/g1-unitree/robot/` junto a la escena (la escena lo referencia).
- **Estructura**: `<Robot>` (script) → `RosFrame` (ROS → Godot, `g = (-ros.y, ros.z, -ros.x)`, como rclgd) →
  `Base` (pose odom → link raíz) → links y joints con los **nombres del URDF**. Cada joint guarda en metadata
  `urdf_type`, `urdf_axis`, `urdf_origin`, límites y `mimic`.
- **API en GDScript** (`urdf_robot.gd`): `set_joints(nombres, posiciones)` (un `JointState` tal cual),
  `set_joint(n, q)`, `set_base_pose_ros(pos, quat)`, `nombres_joints_movibles()`.
- **Soporta**: revolute, continuous, prismatic, fixed (floating/planar se tratan como fijos), límites, mimic,
  mallas STL/OBJ/DAE con `scale`, `package://` (con `--paquete`) y rutas relativas, primitivas box/cylinder/sphere,
  colores de material. **No**: xacro (pasar antes `xacro x.urdf.xacro > x.urdf`), colisiones, inercias, texturas.
- **Diezmado**: Blender ≥ 4.2 sin ventana (`blender_diezmar.py`), reparto del presupuesto ∝ triángulos^0,75 con
  un mínimo por malla; sombreado plano (la Vita ilumina por vértice).
- **Comprobado**: el orden `Transform3D(...)` del `.tscn` es por filas (verificado cargando la escena en el motor
  4.8-dev7: ROS z → Godot y, ROS x → Godot −z).
- **Por qué no el addon de la tienda** (`brean/godot-urdf` v1.2) ni `viz_urdf.gd` de gdviz: el addon siempre crea
  física (RigidBody3D + Generic6DOFJoint3D), aplana la jerarquía, no lee `scale` y Godot 4.8 no trae importador
  STL; gdviz parsea en tiempo de ejecución (caro a 333–444 MHz) y no diezma. Detalle en `docs/ia/workshops/posts/W5-urdf.json`.
