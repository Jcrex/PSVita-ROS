# Revisión del trabajo de Kimi (commit 909e6ab) y plan de integración de ambas líneas

> 2026-11-12. Cuatro revisores Opus 5.5 aislados y en solo lectura (prohibido compilar el motor):
> R1 XRCE C++ · R2 sensores GDScript · R3 procedencia y licencias · R4 integración con la línea de Claude.
> Detalle con `archivo:línea` en `R1-xrce.md` … `R4-integracion.md`.

## Veredicto

El trabajo de Kimi es **sólido en lo esencial**:
- la procedencia y las licencias están verificadas byte a byte;
- los triángulos son exactos;
- se respetan los límites de la Vita (≤ 488 B en best effort, sin SubViewport ni MultiMesh en la Vita);
- los formatos compactos son compatibles en bytes con `vita_relay`.

Tiene **3 errores críticos de comportamiento** y una **cola de transporte que rompe el hombre muerto**, todos
invisibles con 60 FPS y «0 errores» en el log: el modelo midió fluidez, no corrección de datos.

## Estado (2026-11-12, cierre)

**Aplicado todo el plan P0–P2** salvo lo marcado como aplazado en `arreglos-gdscript.md` (R2-B3 NaN frente a 0 en
profundidad, por confirmar en REP-118; R2-B10/B11 stubs de `estado_controlador` y `JointTrajectory` sin
`time_from_start`, mejoras funcionales; pruebas automáticas de las colas con agente real: cubiertas por la sonda
`plantillas/pruebas/rendimiento.gd`). Verificación: host 294/0; plantillas 14/12/12; sonda con agente real
`be_dropped` 0 en los tres proyectos a 60 FPS; G1 en vivo contra MuJoCo; plantilla Vita `PASS … 694 imports`.
GDScript: `arreglos-gdscript.md` (agente Opus). C++/relay/fusión/mallas/docs: orquestador. Fable no hizo falta.

## Plan de integración

| Prio | Tarea | Origen | Dónde |
|---|---|---|---|
| **P0** | Frecuencias al doble: `fmod` + tolerancia publica dos veces → `_acumulado -= periodo` | R1-3 / R2-C1 | `plantillas/ros/sensor_base.gd:55-57` |
| **P0** | `/tf` en best effort: tf2 lo rechaza (`tf2_echo` no ve `odom`) → `/tf` fiable | R2-C2 | `plantillas/sensores/odometria.gd:39` |
| **P0** | Teleop local: al soltar el mando el robot sigue con la última velocidad → hombre muerto también en local | R2-C3 | `plantillas/robots/robot_ros.gd:85-89` |
| **P0** | Cola BE FIFO de 1 mensaje por `poll()`: techo de ~60 mensajes/s en total, más de 1 s de retraso, rompe el hombre muerto → guardar el último por publicador, vaciar en bucle y hacer flush en el mismo `poll()` (reconstruir la plantilla Vita) | R1-1/2, R4-§4 | `ros2_vita/xrce_transport.cpp:352-377` |
| **P0** | Un único productor de `/g1/estado`, `/odom` y `/tf` del G1 (`g1_sim` **o** `g1-sensores`) | R4 | `g1-sensores/robot.json`, README |
| **P0** | Docs 27 y 32: ya no hay «caída de fiable a best effort» | R4 | docs |
| P1 | Altos de R2: scan con datos de casi un periodo de antigüedad (A1); profundidad invertida (A2); sensores del G1 sin montar en su link (A3); frames inexistentes en TF (A4); altura de `odom→pelvis` (A5); yaw del dron (A6); mapa en espejo y sin `map→odom` (A7) | R2 | ver R2 |
| P1 | Contrato **VC/1**: `seq` con máscara, 0 = sin impacto, `version` = época, publicar `joints_orden`, nombres `/vita/<robot>/…`; umbral de celda «libre» común | R4 | sensores de Kimi + `vita_relay.py` (`prefijo`) |
| P1 | Fusionar `godot/comun` en `godot/plantillas` (`g1-unitree/comun -> ../plantillas`) | R4 | godot/ |
| P1 | Unitree: código 3203 (no 3401); 7101–7107 no deben responder éxito sin hacer nada; `/sportmodestate` y `/utlidar/cloud` son del Go2; IMU del torso = `rt/secondary_imu`; `/arm_sdk` | R3 | `unitree_*.gd`, `topics.json`, doc 29 |
| P1 | Doc 29: no existe relay de cámara ni de nube (se promete) | R4 | doc 29 |
| P1 | Cola fiable: avisar si se descarta (`publish()` devuelve OK) y ponerle tope en bytes | R1 | `xrce_transport.cpp` |
| P2 | Mallas RB-KAIROS+: quitar las aristas sueltas `l` (6,6 MiB) | R3 | OBJ + `diezmar-malla.py` |
| P2 | Pruebas que cubran las colas (hoy solo usan loopback) | R1 | `godot/test/` |
| P2 | Resto de medios y bajos (R1–R4), licencia de control_msgs, nombre del kit de personajes | todos | — |
