# Módulo dual `msg-cdr`

Deserializadores **CDR** (XCDR1 little-endian) de los mensajes que consume el
mini-rviz: `tf2_msgs/TFMessage`, `sensor_msgs/JointState`,
`nav_msgs/OccupancyGrid` y `visualization_msgs/Marker`. Etapa D2 de `docs/10`.
Sin malloc, sin estado y con **topes fijos**: lo que excede se descarta, se
**cuenta** (`dropped`, `*_dropped`) y se devuelve `MSG_CDR_ERR_CAPACITY` con la
salida parcial válida.

`include/msg_cdr.h` es la única verdad (structs de salida, topes, códigos).

## API

| Función | Qué hace |
|---|---|
| `msg_cdr_strip_encapsulation` | Quita los 4 bytes `00 01 00 00`; rechaza big-endian |
| `msg_cdr_decode_tf_message` | ≤ 32 transforms (`frame_id`, `child_frame_id`, t, q) |
| `msg_cdr_decode_joint_state` | ≤ 32 joints; position/velocity/effort pueden venir vacíos |
| `msg_cdr_decode_occupancy_grid` | metadatos + `data` **cero copias** (puntero al buffer de entrada) |
| `msg_cdr_decode_marker` | cabecera, pose, escala, color, lifetime, hasta 64 puntos/colores; ignora textura/mesh/text |

El buffer de entrada es lo que ve `on_topic()` de la app: payload **sin**
encapsulación; las alineaciones (4/8) se cuentan desde su inicio.

## Fixtures y verificación

- `tests/fixtures/*.bin` se generan con `tests/gen_fixtures.py` usando las
  **definiciones reales de ROS2 Jazzy** del paquete `rosbags` (no de memoria).
- Ver cómo regenerarlas en la cabecera del script. **Pendiente (PC):**
  cruzarlas con `rclpy.serialization` dentro de `robotnik_dev` y comparar con `cmp`
  (docs/10 §D2 pide fixtures de ROS2 real; estas son independientes pero no oficiales).
- `tests/parity_test.c`: valores esperados a mano; **recorte byte a byte** de
  cada fixture (siempre `TRUNCATED`, nunca crash); y un **fuzz determinista**
  de 28 000 mutaciones cuyo hash (códigos de retorno + contadores) debe ser
  idéntico en C y Rust. La impl C además se probó con `-fsanitize=address,undefined`.

## Decisiones

- Mismo estado parcial ante errores en ambas impl (el fuzz lo detectó una vez:
  Rust acumulaba `strings_truncated` al final, C sobre la marcha).
- Marker: no se parsea más allá de `colors` (suficiente para CUBE/SPHERE/CYLINDER/
  ARROW/LINE_STRIP del MVP, docs/11). `text` y mallas quedan como extensión.
- Strings > 63 caracteres se truncan y se cuentan en `strings_truncated`.

## Estado

- [x] Paridad C/Rust en host (2026-10-27), fuzz y sanitizers limpios.
- [ ] **Validar en el PC:** fixtures vs ROS2 real; cross-compilar.
- [ ] **Pendiente de diseño:** `OccupancyGrid` ≤ 256×256 = 64 KB no cabe en el
      stream de entrada actual (`STREAM_BUFFER_SIZE 4096`); subirlo y medir (docs/10 §9.4).
- [ ] Integrar en `main.c` (`on_topic` → decode → `tf-tree`/estado de viz).
