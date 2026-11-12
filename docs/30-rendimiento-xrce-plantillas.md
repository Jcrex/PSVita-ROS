# 30 — Diagnóstico de rendimiento de las plantillas Godot + XRCE

> Informe de la incidencia de 1–3 FPS en PC. Fecha: 2026-11-12. Alcance: `godot/rbkairos-plus`,
> `godot/g1-sensores` y `godot/dron-mapeo`, con el editor Godot 4.8-dev7 y un agente micro-ROS real
> en UDP loopback 8889. No se ha medido en la PS Vita física.

## 1. Resumen ejecutivo

El problema de FPS en PC está reproducido y corregido: los tres proyectos pasaron de **1–3 FPS a 60 FPS**
con todos los sensores activos y sin errores en los logs de la aplicación [V]. El mundo sin ROS y todos los
sensores en loopback ya funcionaban a 60 FPS, por lo que el render, los modelos y los rayos no eran la causa.

El origen principal fue el envío por XRCE de **RGB crudo 320×240 y profundidad 80×60**, fragmentado en datagramas
de 512 B y mezclado con el resto de sensores. Se añadieron perfiles XRCE, una cola BE y una cola fiable con
reintento, y presupuestos agregados de publicación.

**No se considera cerrada toda la cuestión de transporte.** La sonda posterior encontró que G1 y dron aún
descartan mensajes BE aunque mantienen 60 FPS [V]. RB-KAIROS+ sí terminó sin descartes. La sección 7 deja este
hallazgo separado del problema de FPS para no confundir “va fluido” con “no se pierde ningún dato”.

## 2. Medidas iniciales

Todos los proyectos se ejecutaron con interfaz gráfica y `--print-fps`, no con capturas aisladas [V].

| Escenario | RB-KAIROS+ | G1 | Dron |
|---|---:|---:|---:|
| `sin_ros`, sin crear sensores | 60 | 60 | 60 |
| `transporte=loopback`, todos los sensores | 60 | 60 | 60 |
| XRCE real, código inicial | **1** | **2** | **1** |
| XRCE, cámaras desactivadas | 58 | 58 | 60 |

Conclusión: el cuello de botella solo aparece con cámaras por XRCE. LiDAR 3D, LiDAR 2D, física y render no
explican los 1–3 FPS.

## 3. Desglose de cámaras

Se probaron configuraciones independientes en el dron [V]:

| Configuración | FPS |
|---|---:|
| RGB crudo + JPEG, sin profundidad | **1–2** |
| Sin RGB crudo, profundidad 80×60 + JPEG | **17** |
| Solo JPEG, sin RGB crudo ni profundidad | **60** |
| JPEG 160×120 + profundidad 40×30 a 1 Hz | **60** |
| JPEG 160×120 + profundidad 40×30 a 2 Hz | **60** |

El RGB crudo ocupa 320×240×3 = 230 400 B por imagen. La profundidad 80×60 en `32FC1` ocupa 19 200 B. En XRCE,
cada fragmento usa la MTU de 512 B y el envío fiable llama a `_flush` desde el hilo principal. El resultado es un
bloqueo del render y del resto de publicadores. No es un problema de GPU ni de la cámara de Godot.

## 4. Cambios implementados

### 4.1 Perfil automático por transporte

`ros/contexto_ros.gd` guarda el transporte efectivo. Los sensores aplican `hz_xrce` sin cambiar el perfil completo
de loopback.

- Cámara XRCE: JPEG 160×120 y profundidad 40×30 a 1 Hz; RGB crudo desactivado por defecto.
- RGB crudo sigue disponible en loopback y puede activarse explícitamente con `publicar_rgb_en_xrce`, asumiendo el
  coste de fragmentación.
- OccupancyGrid completo: solo loopback; en XRCE se usan metadatos y teselas compactas.
- LiDAR 3D XRCE: 8 anillos × 30 azimut, como máximo 240 puntos a 1 Hz.
- LiDAR 2D XRCE: 2 Hz; en Vita se conserva el scan estándar pequeño y el formato compacto.
- Odometría y joints: 5 Hz estándar + 5 Hz compacto + TF 5 Hz.
- IMU: 10 Hz en RB-KAIROS+/dron y 5 Hz por cada una de las tres IMU del G1.
- GNSS 2 Hz; presión, campo magnético, rotores y flujo 5 Hz; Range 2 Hz; controlador UR 2 Hz; Unitree 10 Hz.
- Los catálogos `ros/topics.json` separan ahora `loopback` y `perfil_xrce`.

### 4.2 Cola best effort

`godot/ros2_vita/xrce_transport.cpp` copia los mensajes en una cola de 64 y envía uno por `poll()`. Evita el
`ERR_BUSY` al publicar varios sensores en el mismo fotograma. Diagnóstico: `be_pending` y `be_dropped`.

### 4.3 Cola fiable

Se añadió una cola independiente de 32. Si el stream fiable está lleno, el mensaje permanece y se reintenta en el
siguiente `poll()` en lugar de descartarse o bloquear a los demás sensores. Diagnóstico: `reliable_pending`,
`reliable_dropped` y `reliable_full`. Las publicaciones fiables ya no se desvían al stream best effort.

Las dos colas descartan el mensaje más antiguo solo si se excede su capacidad. Por eso los contadores de descarte
son obligatorios para evaluar el resultado; 60 FPS por sí solo no demuestra entrega completa.

## 5. Resultado después de los cambios

| Etapa | RB-KAIROS+ | G1 | Dron |
|---|---:|---:|---:|
| Primer perfil de cámara | 54 | 56–57 | 57 |
| Perfiles reducidos, antes de cola fiable | 60 con errores | 60 sin errores | 60 con errores |
| Con cola fiable, 20 s/proyecto | **60, 0 errores** | **60, 0 errores** | **60, 0 errores** |

La suite de regresión de `ros2_vita` sigue en **294 comprobaciones, 0 fallos** [V]. La plantilla Vita fue
reconstruida y `verify_runtime.py` devolvió **PASS: ELF layout, relocations, main and 694 imports** [V].

## 6. Presupuesto y descartes: hallazgo que impide cerrar todo

La sonda `godot/plantillas/pruebas/rendimiento.gd` mide también `be_dropped` y `reliable_dropped`.

Antes del presupuesto agregado, en 10 s [V]:

| Proyecto | BE descartados | Fiables descartados |
|---|---:|---:|
| RB-KAIROS+ | 746 | 685 |
| G1 | 2204 | 377 |
| Dron | 1735 | 110 |

Después de limitar las frecuencias [V]:

| Proyecto | BE descartados | Fiables descartados | FPS mediana |
|---|---:|---:|---:|
| RB-KAIROS+ | **0** | **0** | 60 |
| G1 | **335** | **0** | 60 |
| Dron | **273** | **0** | 60 |

Los conteos de algunas publicaciones de la sonda superaron la frecuencia nominal mostrada por los sensores, pese
a haber una sola escena y un solo nodo IMU, con física configurada a 60 Hz y `dt=1/60` [V]. No quedó aislada la
causa de esa discrepancia temporal antes de cerrar este informe. Es una cuestión abierta, no una prueba de que el
transporte sea incapaz de sostener el perfil.

**Estado correcto:** el cuello de botella de FPS está resuelto y la cola fiable no presenta descartes. Queda por
revisar el drenaje/programación BE de G1 y dron. No se afirma pérdida cero global ni rendimiento en PS Vita.

## 7. Reproducir las medidas

En el PC, con el editor recompilado:

```fish
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
# Mundo sin sensores
$G --path godot/dron-mapeo --print-fps -- sin_ros
# Sensores sin red XRCE
$G --path godot/dron-mapeo --print-fps -- transporte=loopback
# Agente aislado, no interfiere con la estación normal
docker run --rm -d --name plantillas-bench-agent --net=host --ipc=host microros/micro-ros-agent:jazzy udp4 --port 8889
$G --path godot/dron-mapeo --print-fps -- agente=127.0.0.1 puerto=8889
# Sonda de FPS y contadores (10 s por defecto)
$G --path godot/dron-mapeo --script res://comun/pruebas/rendimiento.gd -- agente=127.0.0.1 puerto=8889 segundos=10
docker stop plantillas-bench-agent
```

La salida `RENDIMIENTO_RESUMEN` incluye FPS, `be_pending`, `be_dropped`, `reliable_pending`,
`reliable_dropped`, `reliable_full`, escrituras, lecturas y publicaciones por sensor.

## 8. Trabajo restante recomendado

1. Registrar en cada publicación BE el timestamp monotónico, el nombre del topic y el tiempo desde la publicación
   anterior para localizar la discrepancia entre la tasa configurada y el conteo de la sonda.
2. Evaluar un planificador común con presupuesto por fotograma y reloj absoluto, en lugar de temporizadores
   independientes, si se confirma que la acumulación de `dt` es la causa.
3. Repetir la sonda en PS Vita: FPS, `be_dropped`, `reliable_dropped`, memoria y latencia. No extrapolar los 60 FPS
   del PC a la consola.
4. Si se necesita RGB/profundidad a alta resolución y frecuencia, usar rclgd/DDS en PC o el relay, no XRCE con MTU
   512 directo. La calidad completa en loopback se conserva para desarrollo.

## 9. VPK actualizados y comprobación de empaquetado

Se reconstruyó la plantilla Vita con las dos colas y se exportaron los tres proyectos con el editor `4.8.dev7` y el
renderer Compatibility. La exportación también normaliza en la copia temporal el renderer y las texturas que el
editor haya marcado como VRAM/S3TC: los cuatro atlas se incluyen como `.ctex` compatibles con RGBA8888 [V].

- `build/rbkairos-plus.vpk`: 23 997 414 B, SHA-256 prefijo `1c8859f036693c44`.
- `build/g1-sensores.vpk`: 24 106 371 B, prefijo `44e8e70c9a7d3326`.
- `build/dron-mapeo.vpk`: 23 609 334 B, prefijo `5b5352dc1891aba6`.

Los tres contienen `robot.json`, `ros/schema.rsch`, escenas `.scn`/`.remap`, los cuatro atlas y no incluyen mallas
PC. Los logs de exportación no contienen errores [V].
