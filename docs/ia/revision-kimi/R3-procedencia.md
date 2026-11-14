# R3: revisión de procedencia, licencias, modelos y empaquetado (commit 909e6ab)

Fecha: 2026-11-12. Revisor: Claude Opus 5.5. Es una revisión **solo de lectura**: no se ha compilado nada ni se ha ejecutado código de los clones.
Objeto: las afirmaciones de `docs/29-plantillas-robots-sensores.md` §4–§9 (autor: Kimi K3.1 Pro) y los proyectos
`godot/rbkairos-plus/`, `godot/g1-sensores/`, `godot/dron-mapeo/` y `godot/plantillas/mundo/`.

Fuentes primarias: se descargaron con `git fetch --depth 1 <sha>` en
`/tmp/claude-1000/-home-jcrex-Proyectos-PSVita-ROS/d90a8c2e-dd6b-4dea-8c32-fe21a8477ad2/scratchpad/revk/`. Se añadió
`unitree_sdk2@aaf69cb` (HEAD del 2026-11-12) para contrastar topics e identificadores.
Leyenda: [V] verificado, [I] inferido, [?] hipótesis. Severidades: **Alta**, **Media**, **Baja** e **Info**.

## Resumen

La procedencia está bien hecha: los 6 commits existen, los LICENSE copiados son idénticos byte a byte, el Xacro
contiene los equipos que se afirman, el URDF tiene 40 links y 39 joints con nombres de escena idénticos, los `.msg`
son idénticos al upstream, los recuentos de triángulos son exactos y los `title_id` son únicos.
Hallazgos:

- **Media 1:** el 53 % de los bytes de las mallas RB-KAIROS+ son aristas `l` inútiles (6,6 MiB).
- **Media 2:** en el G1, el código 3401 no existe en el SDK de Unitree, y las API 7101–7107 devuelven éxito sin hacer nada.
- **Media 3:** algunos topics del G1 son de Go2 o inventados, y la tabla no lo dice.
- **Baja:** detalles de nombres y licencias.

## 1. RB-KAIROS+

| # | Sev. | Hallazgo | Evidencia | Arreglo | |
|---|---|---|---|---|---|
| 1.1 | Info | Los 5 commits citados existen y se descargan: robotnik_simulation `8273bc9…`, robotnik_description `751059e…`, robotnik_sensors `e5186c3…`, Universal_Robots_ROS2_Description `0eb1a86…`, control_msgs `ab911bf…`. Los clones de `toolchains/` están en esos mismos HEAD. | `git fetch --depth 1 origin <sha>` OK; `git -C toolchains/<r> rev-parse HEAD` | — | [V] |
| 1.2 | Info | Los 4 LICENSE de `godot/rbkairos-plus/ros/` son **idénticos** (`cmp`) a los LICENSE de la raíz upstream. | `ros/LICENSE.{robotnik_description,robotnik_sensors,robotnik_simulation,ur_description}` | — | [V] |
| 1.3 | Baja | En robotnik_simulation, el `LICENSE` raíz y el README («Distributed under BSD-3», README.md:105) dicen BSD-3, pero los 5 `package.xml` dicen **Apache-2.0**. La incoherencia es de upstream. `CREDITOS.md` cita BSD-3 sin advertirlo. Del repo solo se toman el catálogo de nombres de topics y el patrón de prefijos; no se copia código. | `robotnik_gazebo_ignition/package.xml:10`, `common/*/package.xml:10` | Añadir una nota en `CREDITOS.md` («package.xml declara Apache-2.0; no se redistribuye código»). | [V] |
| 1.4 | Info | Las mallas UR10e (`meshes/ur10e/visual/*.dae`) quedan bajo el BSD-3 del repo. Solo `ur20` lleva los «Terms and Conditions for Use of Graphical Documentation» de UR, y el UR20 no se usa. | `package.xml:30-32` de ur_description | — | [V] |
| 1.5 | Baja | `ros/fuentes.json` cita control_msgs, pero no hay `LICENSE.control_msgs` ni mención en `CREDITOS.md`. Solo se derivan definiciones de mensajes para `schema.rsch` (BSD-3-Clause según su package.xml). | `godot/rbkairos-plus/ros/fuentes.json:6`, `CREDITOS.md` | Añadir una línea de crédito y su LICENSE, o justificar que no se redistribuye. | [V] |
| 1.6 | Info | El Xacro `robots/rbkairos/rbkairos_plus.urdf.xacro` lleva UR10e (`ur_type` por defecto `ur10e`, l.22-24 y 33-41), VectorNav (l.44), **dos** SICK S300 delantero/trasero (l.55, 67) y RealSense D435 (l.81). | archivo upstream @751059e | — | [V] |
| 1.7 | Info | GPS, cámaras rear/top_ptz y PointCloud2 `top` están solo en el puente: `spawn_robot.launch.py:135,158-164`. La distinción que hace el doc es correcta. | robotnik_simulation @8273bc9 | — | [V] |
| 1.8 | Info | El URDF expandido (`toolchains/rbkairos_plus.urdf`, generado por xacro desde el mismo commit) tiene **40 links y 39 joints** (29 fijos, 6 revolute, 4 continuous). | `grep -c '<link '` = 40, `'<joint '` = 39 | — | [V] |
| 1.9 | Info | Prefijo `robot_`: el Xacro tiene `prefix` vacío por defecto (l.16-18), pero `spawn_robot.launch.py:338` lo fija a `[robot_id, '_']` = `robot_` (RViz por defecto: l.285-286). Las escenas `rbkairos_{vita,pc}.tscn` contienen **los 40 links y los 39 joints con el nombre exacto del URDF**, y no hay ningún link sin nodo. `robot.json:18-20` usa los 6 joints reales del brazo. | comparación con `comm` entre los nodos de la escena y los links/joints del URDF | — | [V] |
| 1.10 | Baja | El URDF expandido y los clones viven en `toolchains/` (sin versionar) y el doc no da el comando xacro exacto. La reproducción depende de esa carpeta. | `docs/29` §4 y §8 (no aparece el xacro) | Documentar en §8 el comando `xacro … prefix:=robot_` y el de `convertir-urdf-dae.py`. | [V] |
| 1.11 | [?] | La malla D435 de robotnik_sensors (`intel_d435_color.dae`, autor «Blender User») podría derivar de la de Intel realsense-ros (Apache-2.0). Upstream no lo indica. | `robotnik_sensors/meshes/depth/intel_realsense_d435/` | Solo si se publica fuera: preguntar o sustituir por una caja. | [?] |

## 2. Unitree G1

| # | Sev. | Hallazgo | Evidencia | Arreglo | |
|---|---|---|---|---|---|
| 2.1 | Info | Los `.msg` de `godot/g1-sensores/ros/msg/{unitree_api,unitree_go,unitree_hg}/msg/` (8 + 24 + 11 = 43 archivos) son **idénticos** (`diff -rq`) a `cyclonedds_ws/src/unitree/*/msg` @668d1ec. | diff sin salida | — | [V] |
| 2.2 | Info | Se conserva la licencia BSD-3: `ros/LICENSE.unitree_ros2` es idéntico al LICENSE upstream («Copyright (c) 2016-2024 HangZhou YuShu…»). El aviso BSD del URDF está en `godot/g1-unitree/CREDITOS.md`. | `cmp` OK | — | [V] |
| 2.3 | Info | `/lowstate`, `/lf/lowstate`, `/lowcmd` (unitree_hg) y `/wirelesscontroller` coinciden con unitree_ros2. En ROS 2 el DDS `rt/lowstate` se ve como `/lowstate`, así que es correcto. | `example/src/src/g1/lowlevel/g1_low_level_example.cpp:62-77`; README.md:147 («wireless controller from G1/Go2/B2») | — | [V] |
| 2.4 | Info | `/api/sport/request` + `/api/sport/response` con `api_id=7105` = `ROBOT_API_ID_LOCO_SET_VELOCITY` es correcto para el G1. El LocoClient del G1 usa el servicio «sport», no «loco» (el H1 sí usa «loco»). Los parámetros JSON `{"velocity":[vx,vy,ω],"duration":d}` coinciden. | unitree_ros2 `example/src/include/g1/g1_loco_client.hpp:29,47,161-169`; unitree_sdk2 `include/unitree/robot/g1/loco/g1_loco_api.hpp:11` | `duration` se ignora en `unitree_control.gd:29-31`: documentarlo o aplicarlo. | [V] |
| 2.5 | **Media** | **El código 3401 no existe** en el SDK oficial. Los errores de servidor son 3201–3207, y el de API no implementada es **3203** `UT_ROBOT_ERR_SERVER_API_NOT_IMPL`. Que el doc diga «los desconocidos devuelven 3401» no tiene fuente. | `unitree_sdk2/include/unitree/robot/internal/internal_error.hpp:10-26`; `godot/plantillas/sensores/unitree_control.gd:35`; `docs/29:105` | Usar 3203 (o 3204 si los parámetros son inválidos). | [V] |
| 2.6 | **Media** | 7101–7104, 7106 y 7107 (SetFsmId, BalanceMode, SwingHeight, StandHeight, ArmTask, SpeedMode) responden **código 0 = éxito** sin hacer nada. Un cliente real creería que, por ejemplo, el cambio de FSM se aplicó. Los GET 7001–7006 caen en «desconocido», aunque son API reales del LocoClient. | `unitree_control.gd:32-33`; `g1_loco_client.hpp:18-31` | Devolver 3203 para las API no simuladas, o simular el estado mínimo (fsm_id) y responder los GET con `data` JSON. | [V] |
| 2.7 | **Media** | `/sportmodestate` y `/lf/sportmodestate` (unitree_go/SportModeState) son topics de **Go2/B2** («Read the sport mode state from Go2/B2»). La odometría de alto nivel del G1 se publica en `rt/odommodestate` / `rt/lf/odommodestate`. `topics.json` los presenta como del G1. | unitree_ros2 README.md:146; doc G1 «odometer service interface» (ver fuentes) | Renombrar o añadir `/odommodestate`, o marcar «formato Go2, no del G1». | [I] |
| 2.8 | Media | `/imu/torso` y `/imu/pelvis` (sensor_msgs/Imu) son nombres del proyecto. En el G1 real, la IMU del torso sale por `rt/secondary_imu` (unitree_hg/IMUState) y la de la pelvis va dentro de `LowState.imu_state`. `/utlidar/cloud` con frame `utlidar_lidar` es el lidar L1 de **Go2** (README:353-366, «Go2点云» en README_zh:360). El Mid-360 del G1 no figura en unitree_ros2. | `unitree_sdk2/example/g1/low_level/g1_ankle_swing_example.cpp:19`; unitree_ros2 README.md:353-366 | Añadir en `topics.json` una columna «origen: Unitree / Go2 / proyecto» y, si se busca fidelidad, `/secondary_imu`. | [V] para secondary_imu, [?] para el topic real del Mid-360 |
| 2.9 | Baja | El doc escribe `/armsdk`. El topic real es **`rt/arm_sdk`** (ROS: `/arm_sdk`). | `docs/29:107`; unitree_ros2 `g1_arm_sdk_dds_example.cpp:74`; unitree_sdk2 `include/unitree/dds_wrapper/robots/g1/g1_pub.h:74` | Corregir a `/arm_sdk`. | [V] |
| 2.10 | Info | No se verificó la cifra «87 tipos G1 / 44 estándar» del esquema. | — | — | [?] |

## 3. Assets Kenney

| # | Sev. | Hallazgo | Evidencia | Arreglo | |
|---|---|---|---|---|---|
| 3.1 | Info | Los 6 kits son CC0 1.0 según los textos de licencia incluidos (Nature 2.1, Furniture 2.0, City Suburban 2.0, Car 3.1, Food 2.0, Animated Characters Survivors 1.1). Kenney.nl confirma CC0 en la página del kit de personajes. CC0 permite redistribuir parcial o totalmente y no obliga a atribuir. | `godot/plantillas/mundo/assets/licenses/*.txt`; <https://kenney.nl/assets/animated-characters-2> | — | [V] |
| 3.2 | Baja | «Animated Characters 2» ahora se titula **«Animated Characters Survivors»**: es la misma URL, y la licencia incluida dice «Survivors (1.1)». El archivo se llama `kenney_animated-characters-2.txt`. Es solo una incoherencia de nombre. | `licenses/kenney_animated-characters-2.txt:4` | Nombrarlo «Animated Characters Survivors (antes Animated Characters 2)» en `CREDITOS.md` y `docs/29` §7. | [V] |
| 3.3 | Baja | La persona diezmada (`assets/generados/persona.obj`, 400 tris, piel `persona/survivorMaleB.png`) está en `generados/`, junto a los modelos propios. `CREDITOS.md` no la lista como propia (bien), pero la carpeta induce a error. No se puede verificar «25 %» sin el FBX original; 400 tris es plausible. | `generados/persona.mtl:12`; `tools/generar-assets-plantillas.py:122-146` | Moverla a `assets/persona/` o decirlo en `CREDITOS.md`. | [V] ubicación, [?] porcentaje |
| 3.4 | Info | No se redistribuye ningún paquete entero: 128 archivos y 1,16 MiB (OBJ, MTL, `colormap.png` y la piel). No hay FBX/GLB ni el Animal Pack 2D. | `git show --stat 909e6ab` | — | [V] |

## 4. Triángulos y empaquetado

| # | Sev. | Hallazgo | Evidencia | Arreglo | |
|---|---|---|---|---|---|
| 4.1 | Info | Contando las 21 instancias de malla de cada escena: RB-KAIROS+ **Vita 11 620** (chasis `robot_base_link_0` 3 000) y **PC 67 246** (chasis 42 269). Coinciden exactamente. | script sobre `rbkairos_{vita,pc}.tscn` + OBJ | — | [V] |
| 4.2 | Info | Escena completa: los OBJ del mundo suman 24 320 tris en 56 instancias, más las cajas (BoxMesh) de la casa y el terreno. Restando robots, las tres cifras del doc dan mundo = 24 656 / 24 644 / 24 644. Las dos últimas son coherentes al triángulo con G1 PC = 60 633 y dron = 552; la de RB-KAIROS+ (91 902) sobra en 12 tris (una caja). Vita: 24 644 + 12 633 ≈ 37 300 < 60 000. | `assets.json`, `godot/g1-unitree/robot/mallas_g1_*`, `pruebas/escena.gd:18-32` | — | [I] (no se ejecutó Godot) |
| 4.3 | **Media** | **Mallas infladas:** los OBJ de RB-KAIROS+ contienen **aristas sueltas `l`**: 114 588 líneas en `robot_front_rgbd_camera_link_0.obj` (que solo tiene 1 201 caras) y 6,62 MiB de 12,44 MiB en total (53 %). El importador OBJ de Godot no las usa, así que no afectan a los triángulos, pero inflan el repo y el tiempo de importación. Proceden de la exportación OBJ de Blender (aristas sueltas del DAE). | `cut -c1-2 … \| uniq -c`; `git show 909e6ab:…/robot_front_rgbd_camera_link_0.obj` | Filtrar `^l ` (`sed -i '/^l /d'`) o exportar sin aristas, y añadirlo a `diezmar-malla.py` y al flujo de Blender. | [V] bytes, [I] Godot las ignora |
| 4.4 | Info | Los `title_id` son únicos entre los 9 `export_presets.cfg` (RVGD40004–07, 40011, 40021–23; godot35 usa ROSV00001). Las `folder_name` también son únicas. El formato es válido: 4 letras + 5 dígitos. | `grep title_id` + `uniq -d` vacío | — | [V] |
| 4.5 | Info | `exclude_filter` excluye `robot/mallas_*_pc/*`, `*_pc.tscn` y `comun/pruebas/*` (en el dron no hay mallas PC). Los `.vpk` de `build/` (213 / 243 / 167 entradas) no contienen mallas PC ni pruebas, y sus sha256[:16] coinciden con el doc (`1c8859f0…`, `44e8e70c…`, `5b5352dc…`), igual que los tamaños. Los 21 `.mesh` importados del VPK RB-KAIROS+ son idénticos a los de `.godot/imported` actuales, aunque los OBJ tienen mtime 22:47 (posterior al VPK de las 21:01). | `zipfile` + `md5` | — | [V] |
| 4.6 | Info | Los enlaces simbólicos son coherentes: `{rbkairos-plus,g1-sensores,dron-mapeo}/comun → ../plantillas`; `g1-sensores/{robot,anim,marcha.gd} → ../g1-unitree/…`; `g1-unitree/comun → ../comun` (existe, contiene `vita_relay.gd`). Git los guarda como modo 120000. `export-vita-vpk.sh` usa `cp -rL`. `res://comun/mundo/…` resuelve a `plantillas/mundo`. | `git ls-files -s` | Baja: en clones de Windows sin symlinks se rompen; documentarlo. | [V] |

## 5. Tamaño añadido por 909e6ab

En total son 382 archivos y **13,98 MiB** de blobs (las «741 689 inserciones» son líneas de OBJ). Por carpeta:

| MiB | archivos | ruta |
|---|---|---|
| 8,08 | 43 | `godot/rbkairos-plus/robot/mallas_rbkairos_pc/` |
| 4,39 | 43 | `godot/rbkairos-plus/robot/mallas_rbkairos_vita/` |
| 1,16 | 128 | `godot/plantillas/mundo/assets/` |
| < 0,1 | resto | código, esquemas, docs |

Los archivos más grandes: `mallas_rbkairos_pc/robot_base_link_0.obj` (2,75 MB), `…pc/robot_front_rgbd_camera_link_0.obj`
(1,82 MB), `…vita/robot_front_rgbd_camera_link_0.obj` (1,82 MB, **para 1 201 tris**), `…pc/robot_arm_upper_arm_link_0.obj`
(0,67 MB), `…vita/robot_arm_upper_arm_link_0.obj` (0,56 MB) y `city/building-type-b.obj` (0,16 MB).

Qué sobra:

- **Las aristas `l`** (≈ 6,6 MiB, ver 4.3): en la variante Vita, la D435 pasaría de 1,8 MB a unos 0,1 MB.
- **La D435 PC y la Vita son casi iguales** (1,82 MB cada una). La de PC no está diezmada de forma distinta; sobra una o
  conviene diezmarla de verdad.
- Las mallas PC (8 MiB) son discutibles en git: son regenerables desde `toolchains/` con los scripts. Alternativa: Git LFS o
  generarlas en el PC. Decisión del usuario.

No se han añadido binarios de build, `.godot/` ni VPK al repo [V].

## Fuentes externas

- [Página del G1 «odometer service interface» (copia no oficial de la documentación de Unitree)](https://unidocs.2vzdtw8.duckdns.org/doc/home_en_G1_developer_odometer_service_interface.md): `rt/odommodestate` y `rt/lf/odommodestate`. Es un espejo; conviene confirmarlo en support.unitree.com [I].
- [Kenney, Animated Characters Survivors](https://kenney.nl/assets/animated-characters-2): CC0.
- Repos upstream en los commits citados (sección 1) y `unitreerobotics/unitree_sdk2@aaf69cb56c9d5ed63d8b284008ec3a8ab999bec1`.
