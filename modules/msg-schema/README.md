# Módulo dual `msg-schema`

Codec CDR **genérico guiado por un esquema**: decodifica y codifica cualquier
mensaje ROS2 cuyo tipo esté en un blob `.rsch`, sin código generado por tipo y
sin malloc. Es el equivalente en la Vita de **`ros_babel_fish`**, la pieza que
permite a `rclgd` manejar mensajes arbitrarios en tiempo de ejecución
(`docs/17` §3.2 y §6.2). Lo necesita el `RosMsg` dinámico del módulo Godot
(`godot/ros2_vita/API_PARITY.md`); `msg-cdr` sigue siendo el camino rápido y
tipado para los 4 mensajes del mini-rviz.

`include/msg_schema.h` es la única verdad (formato del blob, API, códigos).

## Cómo encaja

```
PC:   .msg reales de Jazzy ──tools/gen_msg_schema.py (rosbags)──► schema.rsch ──► .pck / ux0:
Vita: payload CDR ──msg_schema_decode──► visitor (Godot construye Variants)
      Variants   ──msg_schema_encode◄── source  (Godot lee propiedades) ──► payload CDR
```

## API (resumen)

| Función | Qué hace |
|---|---|
| `msg_schema_init(&s, blob, len)` | Valida magia, versión, offsets, índices y strings; el struct lo aporta el llamador |
| `find_type / type_name / field_count / field` | Introspección (para que Godot genere propiedades y clases sombra) |
| `msg_schema_decode(s, type, buf, len, &visitor, ctx, &consumed)` | Eventos `begin_struct / prim / string / prim_array / begin_array...` |
| `msg_schema_encode(s, type, &source, ctx, out, cap, &written)` | Pide los valores en orden de campos; padding a cero |

Los arrays primitivos llegan como **(puntero, cuenta) dentro del payload**, sin
copiar (little-endian, posiblemente no alineado: `memcpy`), igual que las rutas
rápidas de `rclgd` hacia `Packed*Array`.

## Verificación (todo en host)

- **24 tipos reales** (std_msgs, geometry_msgs, sensor_msgs: Imu, Joy, LaserScan,
  Image, CompressedImage, NavSatFix, JointState, BatteryState; nav_msgs; tf2;
  visualization_msgs/Marker...) generados con `rosbags`/Jazzy en `tests/gen_fixtures.py`.
- **Decode**: el volcado del visitor debe ser *idéntico* al volcado canónico del
  OBJETO Python (otra implementación independiente).
- **Encode**: re-codificar los eventos reproduce los bytes originales, bit a bit.
- Recortes de payload (siempre `TRUNCATED`) y de buffer de salida (`NO_SPACE`).
- Esquemas inválidos y **fuzz** de payloads y de esquemas con hash idéntico en
  C y Rust; la impl C pasa con `-fsanitize=address,undefined`.

## Límites y decisiones

- `wstring` no soportado (como `rclgd`, que lo excluye). Sin acciones/servicios
  automáticos: se listan sus `_Goal/_Result/_Request/_Response` como mensajes.
- Un tipo sin campos es inválido (ROS añade `structure_needs_at_least_one_member`):
  evita bucles interminables con un blob corrupto.
- Profundidad máxima 16. Longitudes de secuencia validadas contra los bytes que quedan.
- Los *constants* de los `.msg` no van al blob (no viajan en CDR).

## Estado

- [x] Paridad C/Rust en host (2026-10-27), fuzz y sanitizers limpios.
- [ ] **Validar en el PC:** cross-compilar (el crate paraguas ya lo incluye).
- [ ] **Validar en hardware:** coste por mensaje (Image, LaserScan) en la Cortex-A9.
- [ ] Integrar en `godot/ros2_vita` (`RosMsg` dinámico) y en `vita-app` si conviene.
- [ ] Cruzar fixtures con `rclpy.serialization` en `robotnik_dev` (como `msg-cdr`).
