# `g1-unitree` — Unitree G1 en Godot 4 (PC y PS Vita), con el control oficial de Unitree y una casa

Encargo del usuario (2026-11-11): importar el URDF del Unitree G1, moverlo con los repositorios oficiales de
Unitree y hacerlo andar por una casa generada, por fases. Estado: **las tres fases funcionan en el PC**
(probado con el motor 4.8-dev7 de host con `ros2_vita`, el mismo de la Vita). **Validar en hardware**: FPS y
`/g1/estado` en la Vita (gate G8-G1 abajo).

## Arquitectura

```
                     PC (docker/vita-ros.sh g1)                                   Vita o PC (Godot)
 unitree_rl_gym ── g1_12dof.xml + motion.pt ──► g1_sim.py (MuJoCo 500 Hz,          main.gd
 (oficial, BSD-3)                               política 50 Hz, casa.json)          ├─ robot/g1_*.tscn  (urdf2godot)
                                                  │  ▲                              ├─ casa/casa.tscn   (casa.py)
                         /g1/estado (BE, 25 Hz) ──┘  └── /cmd_vel (BE, 20 Hz) ◄──── ├─ marcha.gd  (clips locales)
                         /joint_states, /odom, /tf → RViz2                          └─ colision_casa.gd
                              micro-ROS Agent (UDP 8888) ◄══ XRCE (ros2_vita) ══►
```

| Fase | Qué | Dónde |
|---|---|---|
| 1 · importar | URDF `g1_29dof_rev_1_0` (39 links, 29 joints móviles) → escena Godot con los **mismos nombres** de link/joint. Mallas diezmadas con Blender: 393 252 → **12 633** triángulos (Vita) y 60 633 (PC). Sin física (Jolt está desactivado en el port, `detect.py:83`): cinemática pura (`urdf_robot.gd`). | `tools/urdf2godot/`, `robot/` |
| 2 · desplazamiento | Control **oficial**: política de marcha `motion.pt` de `unitree_rl_gym` en el modelo MuJoCo oficial `g1_12dof.xml` (12 GDL de piernas; brazos y cintura a 0). Dos modos: **marcha** (8 clips grabados de la política, integrados con *root motion*; no necesita red) y **ros** (simulación en vivo). | `docker/g1/g1_sim.py`, `anim/`, `marcha.gd` |
| 3 · casa | Casa de 10 × 8 m (salón, cocina, dormitorio, baño, recibidor, 16 muebles) descrita **una vez** en `casa.json` → colisiones en MuJoCo + escena Godot (34 cajas, ~400 triángulos, muros recortados a 1,1 m para verla desde arriba) + mapa `casa/mapa.pgm/.yaml` a 5 cm (Nav2, LT1). | `docker/g1/casa.{json,py}`, `casa/` |

## Mandos

| Vita | Teclado/ratón (PC) | Acción |
|---|---|---|
| stick izq. ↑↓ (a tope = correr) | W / S (+ Mayús) | adelante / atrás |
| stick izq. ←→ | A / D | girar |
| L / R | Q / E | paso lateral |
| stick der. | arrastrar | cámara (sigue al robot por detrás) |
| cruceta ↑↓ | rueda | zoom |
| ✕ | Espacio | modo: marcha → ros → de pie → barrido |
| △ | R | volver al inicio |
| ○ | C | vista cenital de la casa |

## Cómo se usa

```fish
# PC: ver el proyecto (motor de host con ros2_vita)
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
$G --path godot/g1-unitree                      # modo marcha (local)
$G --path godot/g1-unitree -- modo=ros          # en vivo: antes, en otra terminal, docker/vita-ros.sh g1
# Vita
tools/export-vita-vpk.sh godot/g1-unitree build/g1-unitree.vpk
tools/deploy-vpk-ftp.sh build/g1-unitree.vpk     # instalar desde VitaShell; agente = ros/agent_ip
```

Regenerar piezas: robot `tools/urdf2godot/urdf2godot.py <urdf> --proyecto godot/g1-unitree --nombre g1_vita --tris 12000`
(y `g1_pc --tris 60000`); clips `docker/vita-ros.sh g1-clips`; casa
`docker/g1/casa.py docker/g1/casa.json --godot godot/g1-unitree/casa/casa.tscn --mapa godot/g1-unitree/casa/mapa`;
esquema `tools/gen_msg_schema.py -o godot/g1-unitree/ros/schema.rsch std_msgs/msg/Float32MultiArray geometry_msgs/msg/Twist`.
La imagen del simulador: `docker/vita-ros.sh g1-build` (necesita la de la estación).

## Decisiones y por qué

- **`/g1/estado` compacto** (`Float32MultiArray`, 19 valores = 76 B, *best effort*) en vez de `JointState`
  (29 nombres + 3 arrays ≈ 1,5 KB): un `JointState` no cabe en un datagrama XRCE (MTU 512) y en *best effort* se
  rechaza; en fiable se fragmenta y bloquea el hilo principal (W1). `/joint_states` y `/tf` se siguen
  publicando para RViz2.
- **Orden de joints** = `JOINTS_PIERNAS` de `g1_sim.py` = `joints` de `anim/g1_marcha.json`
  (left/right × hip_pitch, hip_roll, hip_yaw, knee, ankle_pitch, ankle_roll).
- **Hombre muerto**: sin `/cmd_vel` en 0,5 s la orden pasa a cero (el robot marca el paso quieto).
- **Clips**: todos empiezan en la fase 0 del ciclo de 0,8 s de la política, así se cambia de clip en el mismo
  fotograma con 0,25 s de mezcla sin saltos.
- **Colisión local** 2D (círculo de 0,25 m contra cajas) leída de la propia `casa.tscn`; en modo ros colisiona
  MuJoCo con las mismas cajas.
- **Render en la Vita**: solo `MeshInstance3D` + `BoxMesh`/`ArrayMesh` + `StandardMaterial3D` con color albedo,
  que es lo que el rasterizador GXM dibuja (W7: sin líneas, puntos, MultiMesh ni color por vértice).

## Pendiente

- **Gate G8-G1 (hardware)**: instalar el `.vpk`, comprobar ≥ 30 FPS en modo marcha (línea `gxm2d-perf` del log
  `ux0:data/gxm3d/godot_stderr.log`) y ≥ 20 Hz de `/g1/estado` en modo ros (HUD), y que el robot no atraviese
  paredes. Si los FPS no llegan: bajar a `--tris 6000`.
- Brazos: la política oficial de marcha es de 12 GDL; para mover brazos/cintura hace falta la política de
  29 GDL o el `LocoClient` del SDK real (`unitree_sdk2`, topics `rt/lowcmd`/`rt/lowstate` de `unitree_hg`).
- Robot real: el mismo `/cmd_vel` puede ir al `LocoClient` de `unitree_sdk2_python` con un nodo puente.
