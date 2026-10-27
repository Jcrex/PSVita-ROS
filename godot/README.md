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
