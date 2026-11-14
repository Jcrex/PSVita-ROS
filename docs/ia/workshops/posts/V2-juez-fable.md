# V2 · Decisiones del juez sobre los desafíos de la fase V2 del visor (2026-11-14)

> Juez: Fable 5.2 (regla del usuario 2026-11-13: las decisiones no se le preguntan). Resuelve los **DESAFÍOS** de
> `docs/ia/workshops/posts/V2-revision.md` (N3, N7 y la tabla de veredictos) contra `docs/adr/0013-visualizacion-topics-godot.md`,
> `docs/36-visualizacion-topics-godot.md` §5, §7, §9 y la sentencia `docs/ia/workshops/posts/W13-juez-fable.md` (D7, D14).
> Marcas: [V] verificado en host · [I] inferencia · «validar en hardware» donde solo la Vita lo dice.

## F1 — Gates de marcadores: qué cifra vale (resuelve N3)

**Hechos** [V]: el «48» de los gates venía de `docs/31:237-246` (marcadores + poses + rastro = 48 en Viz), no de un
cupo de marcadores. Los límites reales son tres y no coinciden: cupo de la capa `marcadores` 12 (HMI) / 32 (Viz)
(D7; `godot/plantillas/visor/visor_ros.gd:28-33`), estado completo del relay ≤ 33 (D14;
`docker/scripts/vita_relay_formatos.py:528`) y `TOPE_VITA` = 48 (`godot/plantillas/visor/displays/3d/marcadores.gd:25`).

**Decisión: no se cambia ningún límite; se corrigen los gates.**

| Límite | Valor | Se queda porque |
|---|---:|---|
| Cupo HMI de `marcadores` | 12 | D7: 80 instancias a 60 FPS; `main.tscn` ya gasta 60 (robot 40 + TF 8 + 12). Subirlo se lo quita al robot o a la reserva |
| Cupo Viz de `marcadores` | 32 | D7 / ADR 0011 §6 |
| Estado completo del relay | 33 | D14: 3 trozos de 11. Un 4.º trozo (44) cuesta +2,4 KB/s y +5 dgr/s y la Vita no puede dibujar más de 32 |
| `TOPE_VITA` | 48 | red de seguridad del camino **directo** (`Marker` suelto no pasa por el relay); nunca manda: siempre gana el cupo |

| Gate | Perfil y escena | Fuente (`fuente-v2`) | Verde |
|---|---|---|---|
| **G-W13-M1** (obligatorio) | **HMI**, `main.tscn` | `marcadores 31` (33 en el estado) | `[visor-marc] nodos=12`, `hijos` constante; `drawn` +12; `avg_submit_us` ≤ 6 000; **≥ 55 FPS** |
| **G-W13-M1v** (obligatorio para dar por bueno el perfil Viz) | **Viz**, `main_viz.tscn` | `marcadores 31` | `nodos=32`; `drawn` +32; `avg_submit_us` ≤ 9 000; **≥ 30 FPS** |
| **G-W13-M2** (opcional) | HMI | `vida` (**48**, a propósito por encima de todos los topes) | 5 min: `nodos` = cupo (12) e `hijos` constantes; `[vita-memory]` estable; `sin_sitio` y `cortados` creciendo es lo esperado |
| **G-W13-M3** (obligatorio) | HMI | `marcadores 31` + `netem 10 %` | ningún sólido fuera de sitio > 0,4 s; `process` ≤ 4 000 µs; `/vita/marcadores` ≤ 15 KB/s (33 marcadores = 3 trozos) |

- M1 en HMI usa los umbrales **del perfil HMI** (≥ 55 FPS, 6 000 µs; doc 36 §7), no los de Viz que tenía la tabla: en
  HMI el visor promete 60 FPS con 12 marcadores, y eso es lo que hay que medir.
- El «48» sobrevive solo en M2, como carga de estrés: lo que se comprueba es que el pool no crece, no que se dibujen.
- **Descartado:** subir el relay a 44/48 (más red para nada); subir el cupo HMI (rompe D7); bajar `TOPE_VITA` a 32
  (no cambia ningún comportamiento).
- **Reversión:** si M1v sale rojo, el cupo Viz de marcadores baja (24 → 16) en `CUPOS` y el relay con
  `max_marcadores` (D14 ya lo prevé); si M1 sale rojo, orden de ADR 0011 §8.

## F2 — Gate V5 sin escena en la Vita (resuelve N7 y V5-13)

**Decisión: escena de prueba nueva y conmutable sin reexportar; no se pospone.**

- `godot/visor-ros/banco_v5.tscn` [V]: los 10 displays directos de V5 como **nodos** (regla doc 35): Punto, Vector,
  Orientacion, Imu, Fuerza, Rango, Marcador (3D) y Huella, Covarianza, Gps (planta 2D). Perfil **Viz** (capa `poses`:
  12 de 16; en HMI solo caben 4). Sin robot ni relay: todo llega en directo.
- `godot/visor-ros/main_viz.tscn` [V]: escena **heredada** de `main.tscn` con `perfil = VIZ` y el TF con 32 marcos
  (sirve a M1v y, de paso, quita N8 en Viz). Hereda cualquier cambio de `main.tscn` (V10–V12).
- `godot/visor-ros/selector_escena.gd` (nodo `SelectorEscena` en las tres escenas): en la Vita, **L + R mantenidos y
  START** pasa a la siguiente (`main` → `main_viz` → `banco_v5` → `main`); en el PC, **F9**. Guarda la elección en
  `user://visor_escena.txt` y la escena principal la lee al arrancar: si el cambio en caliente fallara en hardware
  (cierra y reabre la sesión XRCE [I]), basta cerrar y abrir la app. Log: `[visor-escena] escena= archivo=`.
- No se meten los displays V5 en `main.tscn`: no caben en `poses` de HMI (12 > 4) y son 10 lectores XRCE más.
- `visor_ros.gd`: `_conectar_deferred` ya no falla si la escena se cambia antes de conectar (4 líneas).
- Prueba de host nueva: `godot/plantillas/pruebas/visor_escenas.gd` (**21/21**); las otras nueve siguen verdes
  (57, 114, 70, 105, 228, 70, 80, 63, 79).

**Guion del gate V5** (fish, PC; estación arriba, sin relay; en la Vita L + R + START hasta `banco_v5`):

```fish
function pub; docker exec -d vita_station bash -lc "source /opt/ros/jazzy/setup.bash; ros2 topic pub -r 5 $argv"; end
pub /clicked_point geometry_msgs/msg/PointStamped "'{header: {frame_id: map}, point: {x: 1.0, y: 0.5, z: 0.2}}'"
pub /vector geometry_msgs/msg/Vector3Stamped "'{header: {frame_id: map}, vector: {x: 1.0, y: 1.0, z: 0.5}}'"
pub /orientacion geometry_msgs/msg/QuaternionStamped "'{header: {frame_id: map}, quaternion: {z: 0.383, w: 0.924}}'"
pub /imu sensor_msgs/msg/Imu "'{header: {frame_id: map}, orientation: {w: 1.0}, linear_acceleration: {z: 9.81}, angular_velocity: {z: 0.5}}'"
pub /ft_sensor geometry_msgs/msg/WrenchStamped "'{header: {frame_id: map}, wrench: {force: {x: 1.0, z: 0.5}, torque: {z: 1.0}}}'"
pub /sonar sensor_msgs/msg/Range "'{header: {frame_id: map}, field_of_view: 0.5, min_range: 0.1, max_range: 3.0, range: 1.5}'"
pub /marcador visualization_msgs/msg/Marker "'{header: {frame_id: map}, ns: v5, id: 1, type: 1, pose: {position: {x: -1.0, y: 1.0, z: 0.25}, orientation: {w: 1.0}}, scale: {x: 0.5, y: 0.5, z: 0.5}, color: {r: 1.0, g: 0.5, a: 1.0}}'"
pub /footprint geometry_msgs/msg/PolygonStamped "'{header: {frame_id: map}, polygon: {points: [{x: 1.0, y: 1.0}, {x: -1.0, y: 1.0}, {x: -1.0, y: -1.0}, {x: 1.0, y: -1.0}]}}'"
pub /amcl_pose geometry_msgs/msg/PoseWithCovarianceStamped "'{header: {frame_id: map}, pose: {pose: {position: {x: 2.0}, orientation: {w: 1.0}}, covariance: [0.25,0,0,0,0,0, 0,0.1,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0.07]}}'"
pub /fix sensor_msgs/msg/NavSatFix "'{header: {frame_id: map}, latitude: 40.0, longitude: -3.0, altitude: 600.0}'"
# al acabar: docker exec vita_station pkill -f "ros2 topic pub"
```

**Verde:** los diez se ven (esfera magenta, flecha azul, ejes, ejes + flechas de la IMU, flechas + anillo, cono, cubo
naranja; cuadrado verde, elipse rosa y punto del GPS en la planta); `godot_stderr.log` sin `ERR_FAIL` ni «no esta en el
esquema»; `[gxm3d] drawn` ≥ 10; ≥ 30 FPS (perfil Viz). El GPS dibuja un solo punto (fix fijo): correcto.

## F3 — Resto de desafíos y pendientes de `V2-revision.md`

| # | Asunto | Decisión |
|---|---|---|
| V9-2 / H1 | `marco_pose2d` puesto y relay sin `tf` | **Ratificado** el arreglo H1 (cae al marco fijo hasta que exista el camino). Cierra doc 36 §9.3.3: `map → odom` entra por la lista blanca de `tf` cuando haga falta; el relay **no** publica `pose2d` en `map` |
| N1 | registro sin `*/marcadores` ni `*/tf` | A V12 (lo necesita solo el ExploradorTopics); no se toca ahora `registro_displays.gd` |
| N2 | `tf_marcos`/`tf_estatico` fuera de `relay_bw` | Aceptado: latched, ≤ 544 B al cambiar |
| N4 | faltan `.uid` de V8 | Los crea el editor; se suben en el siguiente commit que abra el proyecto |
| N5 | Odom con su propio lector de `pose2d` | Aceptado hasta V13 (1,2 KB/s y 30 dgr/s de 200): cambiar `CanalDisplay` por esto no compensa. Si un perfil roza los 200 dgr/s, es lo primero que se quita |
| N6 | ≤ 4 *quads* de la herramienta fuera de D6 | Se **cuentan dentro de la barra** (≤ 120; hoy 64 en vivo): D6 sigue en 400, sin código |
| N8 | TF: con más marcos que cupo, gana el orden de llegada | HMI: es lo diseñado; quien necesite marcos concretos usa `filtro` en la escena. Viz: `main_viz.tscn` da 32 |
| N9 | marcadores visibles tras desconectar | Aceptado (solo al cerrar la escena, que libera los nodos) |
| N10 | consola oculta descarta | Es el diseño de V6 |
| V7-6 | botones «por medir» | Se mide en el gate V7; L + R + START del selector entra en la misma comprobación |

## Archivos

- Nuevos: `godot/visor-ros/{banco_v5.tscn,main_viz.tscn,selector_escena.gd}`, `godot/plantillas/pruebas/visor_escenas.gd`.
- Tocados (aditivo): `godot/visor-ros/main.tscn` (nodo `SelectorEscena`), `godot/plantillas/visor/visor_ros.gd`
  (guarda en `_conectar_deferred`), `godot/plantillas/visor/README.md`, doc 36 §9.1 y §10, ADR 0013 (enmienda).
- **Validar en hardware:** L + R + START (nombres de botón del port [I]), ruta real de `user://`, cambio de escena en
  caliente con XRCE, y los gates M1, M1v, M3 y V5. Hay que **reexportar y subir** la `.vpk` una vez (lleva las tres escenas).
