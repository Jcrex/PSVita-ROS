# `godot/` — integración de Godot con la capa ROS de la Vita

> **Estado: ESQUELETO SIN VERIFICAR.** Nada de aquí se ha compilado: la
> laptop no tiene Godot ni VitaSDK y no hay Vita conectada. Todo lleva el
> marcador **validar en el PC / en hardware**. Diseño y razones:
> `docs/adr/0008-godot-via-modulo-estatico.md` y
> `docs/12-investigacion-godot-ros2-vita.md`.

## Qué hay

| Ruta | Qué es |
|---|---|
| `ros2_vita/` | Módulo C++ estático de Godot **3.x** (`godot-vita` 3.5). Expone el nodo `RosNode` a GDScript. |
| `../tools/build-godot-template.sh` | Receta (con `--dry-run`) para compilar la plantilla de exportación con el módulo dentro. |

## Por qué módulo estático y no GDExtension

La Vita no admite enlace dinámico en Rust y el port 4.x de Godot declara
GDExtension como no soportado; el código nativo debe ir dentro del motor.
El módulo es un consumidor fino de los headers C de `modules/*/include/`:
la lógica de ROS vive en los módulos duales (Rust o C), no aquí.

## Flujo previsto

```
hilo de red (XRCE)  ──push──►  msg_ring (SPSC)  ──pop en _process──►  señal GDScript
 on_topic(...)                                     (hilo principal)    message_received(topic_id, bytes)
```

## Pendientes de este directorio (ver docs/12 §8)

- [ ] P2: compilar la plantilla 3.5 y fijar el commit de `godot-vita`.
- [ ] P4: conectar `RosNode` a la sesión XRCE (hoy solo drena el ring).
- [ ] P1: alinear los nombres de la API GDScript con rclgd.
- [ ] Capa para Godot 4 (`initialize_ros2_vita_module(ModuleInitializationLevel)`).

## Godot 3.5 hoy, Godot 4 mañana (2026-10-27)

El módulo se escribe **una vez** con `godot_compat.h` aislando las diferencias
de API (tabla dentro del header). Plan por versión:

| | **3.5** (`godot-vita`) | **4.x** (`godot4-vita`) |
|---|---|---|
| Prioridad | **Primera** (receta de plantilla conocida) | Segunda; tras P3/P5 |
| Editor | Linux/Windows oficial + plantilla propia | **Solo Windows** (editor integrado del port) |
| Registro del módulo | `register_ros2_vita_types()` | `initialize_ros2_vita_module(level)` |
| Bytes | `PoolByteArray` | `PackedByteArray` |
| Sockets de Godot | desactivados en la plantilla oficial; **irrelevante**: ROS usa `sceNet` | por comprobar |
| Mapa de memoria | RAM del port (`ATTRIBUTE2` por comprobar) | `ATTRIBUTE2=12` (~365 MiB) |
| GDExtension | n/a | **no soportado** → módulo estático igualmente |
| Cuándo salta a "viable" | P2 + P4 verificados en hardware | P3 (Windows) + P5 (RAM/FPS) + P4 |

Criterio para adoptar 4.x: que `godot4-vita` pase de "3D experimental" y publique
plantillas reproducibles en Linux; hasta entonces **no se bloquea el trabajo en 3.5**.

## Cómo se usará desde GDScript (diseño provisional, no implementado)

```gdscript
# Misma forma que rclgd en el PC (P1: confirmar nombres reales)
var ros := RosNode.new()
add_child(ros)
ros.connect("message_received", self, "_on_msg")   # 3.5; en 4.x: ros.message_received.connect(...)
func _on_msg(topic_id, cdr):                        # cdr: bytes CDR crudos (ver msg-cdr)
    pass
```
Siguiente capa prevista: decodificar con `msg-cdr` dentro del módulo C++ y emitir
`Dictionary` ya hechos (`tf`, `joint_state`, `marker`) para no exponer CDR a GDScript.
