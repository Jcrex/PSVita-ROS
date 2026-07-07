# 09 — Objetivo 2: control de robot (`/cmd_vel` desde los mandos de la Vita)

**Estado:** en implementación (2026-07-07, en el PC).
**Prerrequisito:** Fase 1 completa (sesión XRCE + pub/sub confirmados en
hardware — ver `docs/06-bitacora-estado.md`).

## Qué es

La Vita se convierte en un **mando de teleoperación ROS2**: lee sus sticks
y botones con `sceCtrl` y publica `geometry_msgs/msg/Twist` en el topic
`/cmd_vel` (el estándar de facto para mover bases móviles: turtlesim,
Nav2, diff-drive, mecanum...). Cualquier robot suscrito a `/cmd_vel` en el
grafo ROS2 Jazzy obedece a la consola.

- Topic ROS2: `/cmd_vel` → nombre DDS `rt/cmd_vel`.
- Tipo ROS2: `geometry_msgs/msg/Twist` → tipo DDS
  `geometry_msgs::msg::dds_::Twist_` (dos `Vector3`: `linear` y `angular`,
  6 `double` en total → 48 bytes CDR exactos, todos alineados a 8 desde el
  offset 0 del payload).
- Frecuencia: **20 Hz** (cada 50 ms, por timestamp, en el mismo bucle que
  ya atiende la sesión XRCE en tramos de 50 ms). Un robot real espera
  `cmd_vel` continuo; si deja de llegar, los controladores serios hacen
  su propio failsafe.
- La app **conserva** todo lo de la Fase 1 (`/vita_hello` a 1 Hz y la
  suscripción a `/pc_hello`): sirve de heartbeat y de regresión viva.

## Convención de ejes (REP 103)

`x` adelante, `y` izquierda, `z` arriba; `angular.z` positivo = giro
antihorario (= a la **izquierda**). Todo el mapeo de abajo respeta esto.

## Mapeo de mandos (decisión de diseño, pedida por el usuario)

| Control | Efecto |
|---|---|
| **Stick izquierdo ↑/↓** | `linear.x = ±vel_lineal` (proporcional, adelante/atrás) |
| **Stick izquierdo ←/→** | `angular.z = ±vel_lineal` (proporcional; ← = positivo) |
| **Stick derecho ←/→** | `linear.y = ±vel_lateral` (movimiento lateral proporcional; ← = positivo) |
| **Stick derecho ↑/↓** | ajusta `vel_lateral` en continuo: ±0.5 por segundo a deflexión máxima |
| **Cruceta ↑/↓** | `linear.x = ±vel_lineal` (digital; tiene prioridad sobre el stick) |
| **Cruceta ←/→** | `linear.y = ±vel_lineal` (digital; prioridad sobre el stick derecho) |
| **L** | `angular.z = +0.5` (girar a la izquierda, fijo; prioridad sobre el stick) |
| **R** | `angular.z = −0.5` (girar a la derecha, fijo; L+R a la vez = 0) |
| **△ (triángulo)** | `vel_lineal += 0.5` (flanco de pulsación, tope 2.0) |
| **✕ (cruz)** | `vel_lineal −= 0.5` (flanco; suelo 0.0 = **stop**: con la escala a 0, sticks y cruceta no mueven nada) |
| **START** | salir de la app (igual que la Fase 1) |

Parámetros (constantes en `teleop.h`): `vel_lineal` inicial **0.5**, paso
**0.5**, máximo **2.0**; `vel_lateral` inicial **0.5**, rango **0.0–2.0**,
rampa **0.5/s**; giro fijo de L/R **0.5 rad/s**; zona muerta de los sticks
**±30** sobre el rango crudo 0–255 (centro 128), reescalada para que el
borde de la zona muerta sea 0 y el extremo sea ±1 (sin salto).

Notas del mapeo:
- "Prioridad" = si el control digital está activo, se ignora el analógico
  de ese eje (evita sumas sorpresa; el criterio es determinista).
- `✕` como stop: el usuario pidió "stop o reducir 0.5" — se implementa
  como reducción por pasos cuyo suelo (0.0) es el stop total. Dos
  pulsaciones desde la velocidad por defecto paran el robot.
- `vel_lateral` a 0 también congela el stick derecho: es el mismo
  principio, y el propio stick (↑) lo recupera.

## Arquitectura (regla del repo: lo verificable en laptop, verificado)

- **`vita-app/src/teleop.h` + `teleop.c` — lógica pura, sin headers de la
  Vita.** Recibe una foto de los mandos (`teleop_entrada`: sticks crudos
  0–255 + booleanos de botones) y el `dt`, y devuelve el `Twist` +
  gestiona las escalas y los flancos de ✕/△. Compila y se testea en
  **host** (`scripts/check-teleop.sh`, batería de asserts con gcc), igual
  que el resto de lógica portable del proyecto. `main.c` solo hace el
  puente `SceCtrlData` → `teleop_entrada`.
- **`main.c`**: pasa `sceCtrl` a modo analógico
  (`SCE_CTRL_MODE_ANALOG`), crea el tercer topic/datawriter
  (`rt/cmd_vel`) en la misma sesión/participante, y en el bucle publica
  el Twist a 20 Hz serializando 6 `ucdr_serialize_double` (48 bytes).
- **UI declarativa (ADR 0005)**: 4 bindings nuevos —
  `vel_lineal`, `vel_lateral`, `cmd_vel` (resumen `x±… y±… rz±…`) y el
  layout pasa a mostrar el estado del teleop. Cambios en el enum
  (`ui_types.h`), el codegen (`gen-ui-header.mjs`), `ui.c`, y el espejo
  web (`web/src/lib/ui-layout.ts` + editor `/taller/ui`).

## Cómo probarlo (topología de la Fase 1)

1. Laptop: agente `docker run -it --rm --net=host --ipc=host
   microros/micro-ros-agent:jazzy udp4 --port 8888 -v6` + netlog
   (`tools/netlog-listen.sh 9999` o la web `/monitor`).
2. Vita: lanzar la app (el `.vpk` se sube por FTP:
   `curl -T build-rust/vita-ros2-hello.vpk ftp://192.168.1.94:1337/ux0:/`
   e instalar desde VitaShell).
3. En el contenedor ROS2 Jazzy: `ros2 topic echo /cmd_vel` y mover los
   sticks — los valores deben seguir el mapeo de arriba.
4. La prueba reina: `ros2 run turtlesim turtlesim_node` con un remap
   (`--ros-args -r /turtle1/cmd_vel:=/cmd_vel`) y conducir la tortuga
   desde la Vita.

## Criterios de cierre del Objetivo 2

1. `ros2 topic echo /cmd_vel` muestra Twists correctos al mover cada
   control de la tabla (verificado en vivo).
2. Un robot (turtlesim como mínimo) se mueve obedeciendo a la Vita.
3. La batería host de `teleop` (check-teleop.sh) queda verde en laptop y
   PC, y el mapeo queda documentado aquí y en pantalla (footer de la UI).
