# Guion para Claude — Lección 08 (IMU, G7a): versión detallada

En esta lección haces la puerta **G7** del proyecto (docs/18 §8) entendiéndola de punta a punta:
abres el proyecto en el **editor de Godot**, lees el script línea a línea, lo ejecutas en el PC,
miras los datos con los **comandos de ROS 2**, lo llevas a la Vita y compruebas en hardware las
unidades y los ejes del sensor. Al final hay retos que **haces tú**.

Pista de la [ruta de aprendizaje](./guion-ruta-aprendizaje.md): P2 (ROS 2), P3 (Godot),
P4 (rclgd/ros2_vita) y un poco de P5 (micro-ROS).

Archivos que recorremos (todo en `godot/g7-imu/`):

| Archivo | Qué es |
|---|---|
| `project.godot` | Ajustes del proyecto: resolución 960×544, renderizador, **IP del agente** (`ros/agent_ip`) |
| `main.tscn` | La **escena**: el árbol de nodos (fondo, textos, nivel de burbuja) |
| `main.gd` | El script del nodo raíz: lee el sensor y publica en ROS 2 |
| `nivel.gd` | El script del nodo `Nivel`: dibuja la burbuja |
| `ros/schema.rsch` | Las definiciones de los mensajes ROS que la Vita sabe codificar |
| `export_presets.cfg` | Cómo se exporta a `.vpk` (título, ID de la app) |

> **Estado:** probado en el PC con `-- demo`: `/vita/imu` a 29,98 Hz con QoS best effort y valores
> correctos. **En hardware falta validar** las unidades y los ejes del sensor (retos 1 y 2).

---

## 1. Qué es una IMU y qué mensaje usa ROS 2

Una **IMU** (*Inertial Measurement Unit*) mide:

- **Aceleración lineal** (acelerómetro), en m/s². Estando quieta mide la gravedad: unos 9,8 m/s²
  hacia arriba. Es contraintuitivo pero correcto: el sensor nota que la mesa lo empuja hacia arriba.
- **Velocidad angular** (giroscopio), en rad/s: lo rápido que gira en cada eje.
- A veces **orientación** (un cuaternión). Godot no la expone en la Vita, así que no la publicamos.

En ROS 2 esto viaja como `sensor_msgs/msg/Imu`. Para ver su definición, entra en la estación
(`docker/vita-ros.sh shell`) y ejecuta:

```bash
ros2 interface show sensor_msgs/msg/Imu
```

Verás `header` (hora y `frame_id`), `orientation` + `orientation_covariance[9]`,
`angular_velocity` + covarianza y `linear_acceleration` + covarianza.

Dos convenciones de ROS que el código respeta:

- **REP-103 (ejes):** x hacia delante, y a la izquierda, z hacia arriba, y unidades del SI (m, s, rad).
- **REP-145 (IMU):** si no hay orientación, `orientation_covariance[0] = -1`. Así quien lea el
  mensaje sabe que debe ignorar `orientation`. Una covarianza toda a ceros significa «desconocida».

## 2. De dónde salen los datos (la cadena completa)

```
sensor de la Vita ──sceMotionGetState()──► display_server_vita.cpp (port godot4-vita, C++)
   └─► Input.set_accelerometer / set_gyroscope / set_gravity (en cada fotograma)
         └─► main.gd: Input.get_accelerometer() …                         (GDScript, tu código)
               └─► RosMsg "sensor_msgs/msg/Imu" ──serialize()──► bytes CDR  (ros_msg.cpp + msg-schema)
                     └─► RosPublisher.publish ──► XrceTransport.publish     (xrce_transport.cpp)
                           └─► uxr_prepare_output_stream + ucdr_serialize    (cliente micro-XRCE-DDS)
                                 └─► cada fotograma rclgd::_pump → uxr_run_session_time(0)
                                       └─► microros-transport → net-udp → sendto() por WiFi
   ─── UDP 8888 ───► micro-ROS Agent (docker, PC) ──DDS──► ros2 topic echo /vita/imu
```

Ábrelos para ver cada salto:

- `toolchains/godot4-vita/engine/platform/vita/display_server_vita.cpp`, función `_process_motion`:
  tres líneas copian `SceMotionState` a `Input`. **No convierte unidades**: llegan tal cual las da el SDK.
- `godot/ros2_vita/ros_runtime.cpp`, `RosPublisher::publish`: comprueba el tipo, serializa y lo pasa
  al transporte.
- `godot/ros2_vita/xrce_transport.cpp`, `publish`: si el mensaje cabe en un datagrama (MTU 512) va
  directo. Si no cabe, solo el stream **fiable** sabe trocearlo. Un `Imu` ocupa unos 320 bytes y cabe.

**Pregunta de control:** ¿por qué un mensaje de más de 512 bytes falla con QoS best effort y no con
reliable? (Respuesta en `xrce_transport.cpp`, comentario sobre la MTU.)

## 3. Abrir el proyecto en el editor de Godot (PC)

El editor tiene que ser **4.8-dev7 con el módulo `ros2_vita` dentro**. Si no lo es, no conoce
`RosNode` ni `RosMsg` y el script sale lleno de errores. En el PC hay dos binarios:

| Binario (en `toolchains/godot4-vita/engine/bin/`) | Para qué |
|---|---|
| `godot.linuxbsd.editor.x86_64` | Sin ventana (`--headless`): lo usa `tools/export-vita-vpk.sh` |
| `godot.linuxbsd.editor.x86_64.gui` | **Con interfaz**: para editar escenas y scripts |

Si falta el `.gui`, se compila así (unos 15–30 min la primera vez, luego incremental):

```bash
cd toolchains/godot4-vita/engine
GODOT_VERSION_STATUS=dev7 scons platform=linuxbsd target=editor \
     custom_modules=$HOME/Proyectos/PSVita-ROS/godot/ros2_vita extra_suffix=gui -j14
```

Qué significa cada parte:

- `platform=linuxbsd target=editor`: un editor para Linux.
- `custom_modules=...`: mete nuestro módulo C++ dentro del motor.
- `extra_suffix=gui`: el binario se llama distinto y no pisa el de exportar. Al no poner
  `x11=no wayland=no ...`, este sí tiene ventana.
- `GODOT_VERSION_STATUS=dev7`: el exportador de la Vita rechaza otra versión.

Abrir el proyecto:

```bash
toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui --editor --path godot/g7-imu
```

> El proyecto activa el plugin `addons/psvita`, que solo existe en la copia que hace el script de
> exportar. El editor avisará de que no lo encuentra: es normal, no afecta para editar.

Recorrido por el editor:

1. **Panel Escena** (arriba a la izquierda): el árbol `Main` → `Fondo`, `Estado`, `Datos`, `Nivel`,
   `Ayuda`. Es exactamente lo que dice `main.tscn` (ábrelo con un editor de texto y compáralo).
2. Haz clic en `Nivel`: el **Inspector** (derecha) muestra su posición y tamaño, y abajo, el
   *Script* `nivel.gd`. El icono de pergamino junto al nodo indica que tiene script.
3. Haz clic en `Main` y luego en el pergamino: se abre `main.gd` en el editor de scripts.
4. **Proyecto → Configuración del proyecto**, activa «Configuración avanzada» y busca `ros`:
   ahí están `agent_ip`, `agent_port`, `domain_id` y `schema_path`.

Ejecutar desde el editor (F5) usa el transporte XRCE de verdad. Necesita el agente en marcha
(`docker/vita-ros.sh up`, apartado 5). Para la señal inventada y el agente local, escribe
`-- demo -p agent_ip:=127.0.0.1` en **Proyecto → Configuración del proyecto → Editor → Run →
Main Run Args** (activa «Avanzado»). El `--` separa los argumentos de Godot de los del juego.

## 4. El script `main.gd`, por bloques

Ábrelo al lado de esta lección.

### 4.1 Cabecera y constantes

- `extends Control`: este script **es** un nodo `Control` (un nodo de interfaz 2D) con código extra.
- Las líneas `##` son comentarios de documentación: el editor los muestra como ayuda.
- `const G := 9.80665`: una constante. `:=` deja que GDScript deduzca el tipo (`float`).
- `SIN_ORIENTACION`: los 9 números de la covarianza de orientación según REP-145.

### 4.2 Referencias a nodos

```gdscript
@onready var lbl_estado: Label = $Estado
const Nivel := preload("res://nivel.gd")
@onready var nivel: Nivel = $Nivel
```

- `$Estado` equivale a `get_node("Estado")`: el hijo con ese nombre en el árbol.
- `@onready`: el valor se asigna justo antes de `_ready()`, cuando los hijos ya existen.
- `preload` carga `nivel.gd` al compilar. Usarlo como tipo le dice a GDScript que `nivel` tiene
  la propiedad `gravedad`. Con `Control` a secas daría error de compilación.

### 4.3 Objetos ROS y por qué son variables del script

`node`, `pub_imu` y `t_pub` están **fuera** de las funciones. Los objetos `Ros*` son `RefCounted`:
Godot los borra cuando nadie los referencia. Si `pub_imu` fuera una variable local de `_ready()`, el
publicador se destruiría al acabar la función. Es el error nº 1 con rclgd (skill `rclgd`, regla 1).

### 4.4 `_ready()`: conectar, parámetros, publicador, timer

1. `await get_tree().process_frame`: espera un fotograma para que se vea «Conectando…».
2. `rclgd.init(args)` abre la sesión XRCE con el agente. Si falla, `get_transport_info()` dice en
   qué paso (red, socket, sesión). Es la pantalla de diagnóstico que ya salvó la G5.
3. `RosNode.new()` + `init("vita_imu", "")`: el nodo ROS. En la Vita **una sesión XRCE = un
   participante DDS**: por eso `ros2 topic info -v` muestra el nodo como `ros2_vita`.
4. `declare_parameter` / `get_parameter`: valores que se cambian al arrancar sin tocar código
   (`-- -p hz:=50`). Hay seis: `hz`, `topic`, `frame_id`, `escala_acel`, `escala_giro`, `ejes`.
5. `RosQoS` con `BEST_EFFORT` y `depth 5`: la QoS típica de sensores (ver 5.3).
6. `create_publisher(topic, "sensor_msgs/msg/Imu", qos)`: el tipo va **como texto**. Así el mismo
   script funciona en el PC con rclgd y en la Vita (`API_PARITY.md`, regla de scripts portables).
7. `create_timer(1.0 / hz, _publicar)`: `_publicar` es un `Callable` (una referencia a la función)
   y el timer la llama periódicamente en el hilo principal.

### 4.5 `_process(delta)`: leer el sensor cada fotograma

- En modo `demo` se inventa una señal (un balanceo). Sin `demo`, se lee `Input.get_*`.
- **Tara del giroscopio:** un giroscopio quieto no marca exactamente 0. Ese error constante es el
  *sesgo*. Al pulsar △ se promedian las muestras de 1 s y luego se restan.
- `_a_ros(v * escala)`: convierte las unidades y reordena los ejes.
- `nivel.gravedad = grav_cruda`: le pasa el dato al nodo hijo. El *setter* de `nivel.gd` pide
  redibujar.

**Ojo con el ritmo:** el sensor se lee una vez por fotograma (unos 60 Hz o menos en la Vita) y el
timer publica a `hz`. Si `hz` supera los fps, se publican muestras repetidas. Por eso el valor por
defecto es 30.

### 4.6 `_publicar()`: construir el mensaje

```gdscript
var m := RosMsg.from_type("sensor_msgs/msg/Imu")
m.header.stamp = node.now()
m.orientation_covariance = PackedFloat64Array(SIN_ORIENTACION)
m.linear_acceleration.x = acel_ros.x
```

- `from_type` crea un mensaje vacío usando `ros/schema.rsch`. Si el tipo no está en el esquema,
  devuelve `null`.
- Los campos se escriben con puntos, igual que en Python con rclpy.
- **Los arrays se asignan enteros** (`PackedFloat64Array`): no se puede hacer
  `m.orientation_covariance[0] = -1`, porque se modificaría una copia (regla de rclgd).
- `node.now()` es la hora del **reloj de la Vita**, que no está sincronizada con el PC. Si
  comparas marcas de tiempo entre máquinas, verás desfase (pendiente: `uxr_synchronize_session`).

### 4.7 `_parsear_ejes` y `_a_ros`: reordenar ejes

El sensor tiene sus propios ejes, que no tienen por qué coincidir con REP-103. El parámetro `ejes`
dice, para cada eje ROS (x, y, z), de qué eje del sensor sale y con qué signo:

```
ejes:="-y,x,z"   ⇒   ros.x = -sensor.y,  ros.y = sensor.x,  ros.z = sensor.z
```

Un `Vector3` se puede indexar (`v[0]` es `v.x`). Por eso la lista guarda índices `[índice, signo]`.

### 4.8 `nivel.gd`

Un `Control` que solo dibuja: `_draw()` con `draw_arc`, `draw_line` y `draw_circle`. La variable con
`set(valor):` es un **setter**: código que se ejecuta cada vez que alguien asigna la propiedad.
Separar el dibujo en su propio nodo y script es la forma normal de organizar un proyecto Godot.

## 5. Probarlo en el PC (sin la Vita)

### 5.1 Arrancar la estación (agente micro-ROS + ROS 2 Jazzy en docker)

```bash
docker/vita-ros.sh up        # agente en UDP 8888 + contenedor "station" con ROS 2
docker/vita-ros.sh status    # qué contenedores corren y la IP de este equipo
```

`up` levanta **dos contenedores**: `vita_agent` (el agente micro-ROS, que traduce XRCE a DDS) y
`vita_station` (ROS 2 Jazzy con herramientas). Mira `docker/docker-compose.yml` para ver cómo se
definen.

### 5.2 Ejecutar el proyecto con la señal inventada

Desde el editor (F5, con los Main Run Args del apartado 3) o sin interfaz:

```bash
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64   # fish (en zsh: G=...)
$G --headless --path godot/g7-imu -- demo -p agent_ip:=127.0.0.1
```

- Todo lo que va **después de `--`** son argumentos para el juego, no para Godot.
- `-p agent_ip:=127.0.0.1`: el agente está en este mismo equipo.

### 5.3 Mirar los datos con ROS 2

Abre otra terminal y entra en la estación con `docker/vita-ros.sh shell`:

```bash
ros2 topic list -t                    # ¿aparece /vita/imu [sensor_msgs/msg/Imu]?
ros2 topic info -v /vita/imu          # quién publica y con qué QoS (Reliability: BEST_EFFORT)
ros2 topic hz /vita/imu               # frecuencia real (≈30)
ros2 topic echo /vita/imu --once      # un mensaje completo
ros2 topic echo /vita/imu --field linear_acceleration
ros2 run rqt_plot rqt_plot /vita/imu/linear_acceleration/x /vita/imu/linear_acceleration/z
```

`rqt_plot` abre una ventana: lanza `docker/vita-ros.sh shell` desde una terminal del escritorio
del PC (no por SSH). El script da permiso de X11 al contenedor; si no se abre, revisa esa parte de
`docker/vita-ros.sh`.

**Sobre la QoS.** Un suscriptor *reliable* no recibe nada de un publicador *best effort*: son
incompatibles. `ros2 topic echo` se adapta solo, pero tu propio nodo tendría que pedir
`BEST_EFFORT` (o usar el perfil `SensorDataQoS` en rclpy/rclcpp). Es el fallo de la tabla de
`skills/rclgd/references/errores-comunes.md`.

## 6. Llevarlo a la Vita

```bash
tools/export-vita-vpk.sh godot/g7-imu build/g7-imu.vpk
tools/deploy-vpk-ftp.sh build/g7-imu.vpk 192.168.1.94     # VitaShell con FTP activo (SELECT)
```

En la Vita: VitaShell → instalar el `.vpk` → abrir «ROS2 Vita G7 IMU». En el PC:
`docker/vita-ros.sh echo /vita/imu`.

Si la pantalla sale en rojo: lee `paso:` y `netctl` (docs/06, primer bloque, «Diagnóstico en la
Vita»), o los logs por FTP en `ux0:data/gxm3d/godot_stderr.log`.

## 7. Retos (los haces tú)

Los retos 1 y 2 **son trabajo pendiente del proyecto**, no ejercicios inventados. Lo que descubras
se apunta en la bitácora (`docs/06`) y en los valores por defecto de `main.gd`.

**Reto 1 — Unidades del sensor (Vita).** Deja la Vita quieta sobre la mesa y mira la línea
`CRUDO acel … |a| =`:

- Si `|a|` ≈ 1,0, el sensor da **g** y `escala_acel = 9.80665` es correcto.
- Si `|a|` ≈ 9,8, ya da m/s²: arranca con `-p escala_acel:=1.0`, o cambia el valor por defecto.
- Giroscopio: gira la consola **una vuelta** sobre la mesa en unos 2 s. Si el valor de pico ronda
  3 (2π/2 s ≈ 3,1 rad/s), son rad/s. Si ronda 180, son grados/s y `escala_giro` debe ser
  `0.0174533` (π/180).

**Reto 2 — Ejes (Vita).** Con la consola en la mano, pantalla hacia ti:

1. Plana sobre la mesa, pantalla arriba: en ROS, `linear_acceleration.z` debe ser ≈ +9,8.
2. Levanta el borde de delante (el de los gatillos): en REP-103, con el morro hacia arriba, `x`
   debe ser ≈ +9,8. Decide qué es «delante» para la Vita y apúntalo.
3. Levanta el borde izquierdo: `y` ≈ +9,8.
4. Escribe la cadena `ejes` que lo cumple (por ejemplo `-y,x,z`), pruébala con
   `-p ejes:=...` y, si funciona, ponla como valor por defecto en `main.gd`.
5. Si la burbuja de `nivel.gd` se mueve al revés, corrige los signos en su `_draw()`.

**Reto 3 — Ritmo.** Arranca con `-p hz:=100`. ¿Qué marca `ros2 topic hz`? ¿Por qué no llega a 100?
(Pista: apartado 4.5 y los fps de la Vita.)

**Reto 4 — Escribir código: publicar también los botones como `sensor_msgs/Joy`.** El esquema ya
incluye `sensor_msgs/msg/Joy`. Añade a `main.gd` un segundo publicador en `/vita/joy`:
`axes` = los dos sticks (4 floats) y `buttons` = 12 enteros con
`Input.is_joy_button_pressed`. Recuerda: arrays enteros (`PackedFloat32Array`, `PackedInt32Array`)
y la referencia guardada en una variable del script. Pruébalo con `ros2 topic echo /vita/joy`.

**Reto 5 — Orientación sin cuaternión (avanzado).** Con la consola quieta, la gravedad da el
balanceo y el cabeceo: `roll = atan2(a.y, a.z)`, `pitch = atan2(-a.x, sqrt(a.y² + a.z²))`.
Muéstralos en el HUD. Después piensa: ¿por qué no puedes sacar el *yaw* (rumbo) de la gravedad?
(La respuesta lleva al magnetómetro y a `deviceQuat` de `SceMotionState`, que el port no expone:
eso sería un parche C++ en `display_server_vita.cpp`.)

**Reto 6 — Auditoría.** Usa la lista de la [ruta, pista P10](./guion-ruta-aprendizaje.md#p10--auditar-código)
sobre `main.gd` y apunta tres cosas que cambiarías y por qué.

## 8. Comprueba que lo has entendido

Deberías poder responder sin mirar:

1. ¿Qué pasaría si `pub_imu` fuera una variable local de `_ready()`?
2. ¿Por qué el tipo del mensaje se pasa como texto y no como `RosSensorMsgsImu`?
3. ¿En qué hilo se ejecuta `_publicar`? ¿Y quién envía de verdad los bytes por UDP, y cuándo?
4. ¿Qué indica `orientation_covariance[0] = -1`?
5. ¿Por qué best effort para la IMU y reliable para `/cmd_vel` en G6?
6. ¿Qué haces si `ros2 topic list` no muestra `/vita/imu`? Da tres comprobaciones en orden.

## Mi progreso

| Paso | Hecho | Notas |
|---|---|---|
| Abrir el proyecto en el editor `.gui` | ☐ | |
| Ejecutarlo en el PC con `demo` y verlo en `ros2 topic echo` | ☐ | |
| Exportar e instalar en la Vita | ☐ | |
| Reto 1 (unidades) | ☐ | |
| Reto 2 (ejes) | ☐ | |
| Retos 3–6 | ☐ | |

## Hallazgo 2026-11-01 — la bola del nivel se mueve «a saltos»

Síntoma (usuario, en hardware): `/vita/imu` publica, pero el círculo de `nivel.gd` salta en vez de
moverse continuo, y los valores del HUD le parecen erráticos.

Causa (verificada en código):
- `display_server_vita.cpp:270` (port godot4-vita) rellena `Input.set_gravity()` con
  `SceMotionState.basicOrientation`.
- `psp2/motion.h:123-129`: `basicOrientation` solo toma **-1, 0 o 1** por eje (orientación «gruesa»
  para rotar pantalla; el umbral lo fija `sceMotionSetAngleThreshold`).
- `g7-imu/main.gd:178,190` lee `Input.get_gravity()` y lo pasa a `nivel.gravedad` ⇒ la bola solo puede
  estar en unas pocas posiciones. **No afecta a `/vita/imu`**: `linear_acceleration` sale de
  `acceleration` (continuo, `:268`) y `angular_velocity` de `angularVelocity` (`:269`).

Arreglo propuesto (reto para el usuario, no aplicado):
- En `main.gd`, dar al nivel la aceleración filtrada en vez de `grav_cruda`: filtro paso bajo
  `grav_filtrada = grav_filtrada.lerp(acel_crudo, 0.1)` por fotograma (en reposo, la aceleración ≈ gravedad).
- Alternativa en C++ (parche al port): usar `rotationMatrix`/`deviceQuat` para una gravedad continua
  (tercera fila de la matriz o rotar (0,0,-1) por el cuaternión) — *hipótesis*, validar signos.

«Errático» — hipótesis a comprobar antes de concluir nada:
- El acelerómetro crudo tiene ruido de unos centésimas de g; a 30 Hz se ve «nervioso». Medir con la
  Vita quieta en la mesa: `|a|` medio y su dispersión (`ros2 topic echo /vita/imu --field linear_acceleration`).
- Si `|a|` ≈ 1 sin escala ⇒ unidades en g (confirma `escala_acel = 9.80665`).
- El giroscopio necesita la tara (△) quieto; sin ella deriva.
