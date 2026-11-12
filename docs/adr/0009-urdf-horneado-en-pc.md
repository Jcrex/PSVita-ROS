# ADR 0009: Los robots URDF se hornean en el PC (`tools/urdf2godot`) y la Vita solo los anima

- **Estado:** Aceptado el 2026-11-11 — **ejecución validada**: Unitree G1 a 60 FPS en la Vita (usuario, commit `ca510f3`).
- **Fecha:** 2026-11-11
- **Autoría:** redactado por el orquestador (Opus 5.5) a partir del workshop W5 y de la implementación. La regla
  del método pide Fable 5.2 para los ADR; no estaba disponible (límite semanal hasta el 2026-11-14), así que se
  documenta la sustitución. Queda pendiente un juicio de Fable, que no bloquea porque la decisión está medida en hardware.

## Contexto

La LT4 pide robots URDF en Godot, en el PC y en la Vita. Hechos verificados (doc 25, W5, W7):

1. Godot 4.8-dev no trae importador STL. El addon de la tienda `brean/godot-urdf` (v1.2, BSD-3) siempre crea
   física, aplana la jerarquía, no lee `scale` y sus APIs de importación solo existen en el editor.
2. `viz_urdf.gd` de gdviz (MIT) parsea el URDF en tiempo de ejecución y lee STL en GDScript. En la Vita eso sería
   lento (333–444 MHz, un solo núcleo efectivo), no diezma y no resuelve rutas relativas.
3. Jolt está desactivado en el port (`detect.py:83`). El GXM 3D solo dibuja triángulos de `MeshInstance3D`.
4. Un URDF real (G1) tiene 393 k triángulos. Lo validado en la Vita era ~5,6 k (G7c).
5. El URDF ni las mallas caben por XRCE (techo fiable ≈ 7,5 KiB).

## Decisión

1. **Preprocesar en el PC** con `tools/urdf2godot/urdf2godot.py`, que es Python estándar más Blender sin ventana.
   Salida: escena `.tscn` y mallas OBJ diezmadas a un presupuesto de triángulos. Se hacen dos niveles de detalle:
   Vita (~12 k para un humanoide) y PC (~60 k).
2. La escena **conserva los nombres de link y joint** del URDF y su jerarquía, y guarda la cinemática en
   metadata. Su raíz `RosFrame` convierte de ejes ROS a Godot con la misma convención que rclgd.
3. **Runtime solo visual y cinemático** (`urdf_robot.gd`), sin física y sin parsear XML. Aplica las juntas por
   nombre y la pose de la base. Los datos llegan del PC en formato compacto si no caben en un datagrama.
4. xacro se expande antes con `xacro`. Las colisiones del robot no se exportan: la física del robot vive en el PC
   (MuJoCo o Gazebo).

## Alternativas descartadas

- **Addon `godot-urdf` de la tienda como importador:** necesita un importador STL de terceros, crea física que
  habría que desmontar, aplana la jerarquía (faltan frames fijos como cámara e IMU) y no lee `scale`. Sigue siendo
  útil para editar en el PC; se puede contribuir upstream un modo «solo visual».
- **`viz_urdf.gd` de gdviz en la Vita:** parsear en runtime cuesta CPU de un núcleo compartido con render y XRCE,
  y `/robot_description` no llega por XRCE.
- **Física de Godot (`godot_physics_3d`) para el robot:** existe en el port, pero sin medir. Para humanoides, la
  dinámica y el control de verdad están en el simulador del PC (política oficial de Unitree en MuJoCo).

## Consecuencias

- Cada robot nuevo es un paso de build en el PC (~2 s). Las mallas diezmadas se versionan junto al proyecto
  Godot, conservando las licencias (p. ej. BSD-3 de Unitree en `godot/g1-unitree/CREDITOS.md`).
- Las juntas y la base que llegan por red siguen el contrato del relay (doc 27), no `JointState` crudo.
- TF desde o hacia la Vita depende de implementar `create_tf_broadcaster`/listener en `ros2_vita` (P0).
