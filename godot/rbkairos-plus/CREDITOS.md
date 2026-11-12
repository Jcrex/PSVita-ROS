# Créditos

- RB-KAIROS+ y sensores Robotnik: `RobotnikAutomation/robotnik_description` @ `751059edd6af3a9c083018cfaee59e4496d46580` y `robotnik_sensors` @ `e5186c343910b86a924201edb256f79eb0f73295`, BSD-3-Clause. Mallas diezmadas con `tools/urdf2godot`; avisos en `ros/LICENSE.robotnik_description` y `ros/LICENSE.robotnik_sensors`.
- UR10e: `UniversalRobots/Universal_Robots_ROS2_Description`, BSD-3-Clause; aviso en `ros/LICENSE.ur_description` y commit registrado en `ros/fuentes.json`.
- Catálogo de simulación: `RobotnikAutomation/robotnik_simulation` @ `8273bc97470c6c4ec532b4223f0af0e0ab18e644`, BSD-3-Clause.
- Mundo: véase `comun/mundo/CREDITOS.md`.

## Notas de la revisión (2026-11-12)

- **control_msgs** (`ros-controls/control_msgs@ab911bf`, BSD-3-Clause, `ros/LICENSE.control_msgs`): solo se derivan
  las definiciones de `JointTrajectoryControllerState` para `ros/schema.rsch`; no se redistribuye su código.
- **robotnik_simulation**: el `LICENSE` raíz y el README dicen BSD-3, pero sus `package.xml` declaran Apache-2.0
  (incoherencia de upstream). De ese repo solo se toman nombres de topics y prefijos; no se copia código.
- La malla D435 de robotnik_sensors podría derivar de la de Intel realsense-ros (Apache-2.0) [?]; si el proyecto se
  publica fuera, confirmarlo o sustituirla por una caja.
