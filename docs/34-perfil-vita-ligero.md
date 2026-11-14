# 34 — Perfil «Vita ligero» de las plantillas: camino a 60 FPS (T2)

> **Estado:** implementado y probado en host el 2026-11-13 (sesión programada en la nube, Fable 5.2, **sin Vita ni
> PC del usuario**). Todo lo que depende del hardware está marcado **«validar en la Vita»**: el objetivo de
> < 16,7 ms por fotograma **no está medido** todavía.
> Marcas: [V] verificado (archivo:línea o medida) · [I] inferencia · [?] sin confirmar.
> Alcance: `godot/g1-sensores`, `godot/rbkairos-plus`, `godot/dron-mapeo` (biblioteca `godot/plantillas/`).

## 1. Resumen

1. **Dónde se va el tiempo** (log de la Vita del 2026-11-13, `docs/ia/medidas/g1-sensores-vita-2026-11-13.log`,
   tabla en §2): 42 ms por fotograma = scripts de física 22,2 + render 12,4 + `_process` 5,8 + física 0,8 [V].
   Con el robot mirando a la nada (13 093 triángulos) el render sigue costando **9,65 ms** y `_process` 4,7 ms [V]:
   el mundo solo explica ~2,7 ms del render.
2. **Hallazgo nuevo (el más importante):** `build_us` ≈ 3,7–4,6 ms en **todas** las muestras [V]. Es la **luz por
   vértice** del 3D GXM: cada malla cuyo origen se mueve ≥ 1 cm se vuelve a iluminar en la CPU, con un tope de
   3 000 vértices por fotograma (`rasterizer_scene_gxm_vita.inc:591-593, 602-696, 868` del port, commit `d1a5f29`)
   [V en el código]. Un robot articulado andando (35 mallas, 37 899 vértices) agota ese tope **cada fotograma**
   [I]. Además dobla los *draws* de las mallas opacas (`lit=27…121` en el log) [V].
3. **Hecho en esta sesión (todo GDScript y assets; el motor y `ros2_vita` no se tocan):**
   - Mundo ligero: de 26 600–36 500 a **13 400–15 000 triángulos en vista** con el G1 (−55 %), de 83–108 a 50–55
     mallas y de 164–206 a 50–75 superficies, medido en el PC con un contador calibrado contra la Vita (§3) [V].
   - Marcha del G1 sin arrays nuevos por tick (×1,9 en el PC) y modelo URDF con metadatos en caché y sin
     reescribir juntas que no cambian (×2,8 en el PC) [V en PC; en la Vita, por medir].
   - HUD corto sin contorno (de ~305 *quads* a ~45 letras + 1 rectángulo) y refrescado a 4 Hz [I: los *quads*
     reales se ven en `[gxm2d-perf]`].
   - Contadores propios `[perfil-gd]` en el log de la Vita: desglose por sección de lo que hoy es un único número.
   - Interruptor en marcha de la luz por vértice (START) para medir las dos opciones en una sola sesión.
4. **Estimación** [I], con todo lo anterior y luz por vértice **activada**: render ≈ 9–10 ms, `_process` ≈ 4–5 ms,
   tick de física (30 Hz) ≈ 3–5 ms ⇒ fotogramas de 14 ms sin tick y de 18–19 ms con tick ⇒ **40–60 FPS, no 60
   estables**. Con luz por vértice **desactivada**: render ≈ 5–6 ms ⇒ 60 FPS probables. La decisión (aspecto frente a
   FPS) necesita la prueba del §7.

## 2. Medidas de partida en la Vita [V]

Una fila por cada 300 fotogramas del log (µs por fotograma, medias del motor):

| FPS | inst. | triángulos | lit | submit | build | lienzo 2D | `_process` | scripts física | render |
|---|---|---|---|---|---|---|---|---|---|
| 30,2 | 41 | 13 093 | 27 | 2 039 | 3 716 | 1 853 | 4 733 | 17 088 | 9 741 |
| 31,2 | 41 | 13 093 | 30 | 2 036 | 3 867 | 1 847 | 4 590 | 16 484 | 9 648 |
| 28,1 | 46 | 15 049 | 48 | 2 778 | 4 056 | 1 889 | 5 054 | 18 175 | 10 711 |
| 22,2 | 75 | 29 517 | 101 | 5 009 | 4 194 | 1 874 | 5 907 | 23 722 | 13 239 |
| 23,5 | 67 | 28 781 | 97 | 4 681 | 4 000 | 1 870 | 5 859 | 22 053 | 12 594 |
| 21,2 | 84 | 30 963 | 121 | 5 852 | 3 959 | 1 924 | 6 160 | 24 900 | 13 823 |

Lecturas:

- `submit` (envío 3D) crece con los triángulos: 2,0 ms a 13 093 y 4,7–5,9 ms a 28 800–31 000 ⇒ ~0,17 ms por cada
  1 000 triángulos del mundo [V].
- `build` no depende de los triángulos: 3,7–4,2 ms siempre ⇒ es el tope de 3 000 vértices de la luz por vértice [I].
- El lienzo 2D (HUD) son 1,85–1,9 ms fijos con 222–224 *draws* y 305–307 *quads* [V].
- Scripts de física: a 30 FPS son 2 ticks de 60 Hz por fotograma ⇒ ~8,5 ms por tick; a 23,5 FPS, ~2,55 ticks ⇒
  ~8,7 ms por tick [V]. El arreglo de 30 ticks ya aplicado (T1) deja como mucho 1 tick por fotograma a ≥ 30 FPS.

## 3. Contador de render en el PC, calibrado contra la Vita [V]

`mundo_base.gd:250` `contar_dibujado(raiz, camara, aspecto)` suma triángulos, mallas y superficies de las
`MeshInstance3D` visibles cuya esfera envolvente toca el tronco de la cámara y queda a menos de 40 m (lo mismo que
hacen el motor y `gxm_camera_lod.h:10-19`). Funciona en *headless* (sin GPU); el tronco se calcula con el aspecto de la
Vita (960×544) porque la ventana *headless* es de 64×64.

**Calibración:** primera vista de `g1-sensores` con el mundo completo → PC: **19 469 triángulos, 53 mallas**; Vita
(primera línea `[gxm3d]` del log): **19 457 triángulos, 52 instancias**. Diferencia: 12 triángulos (una caja) [V].
El contador del PC reproduce `submitted_triangles` y `visible_instances`.

Prueba: `pruebas/presupuesto.gd` lleva el robot a 6 puntos, gira la cámara 8 veces en cada uno y se queda con el
peor caso. Falla si el perfil ligero pasa del presupuesto (15 000 triángulos y 80 mallas: la columna «HMI a
60 FPS» del ADR 0011 §6).

| Proyecto (robot) | Mundo completo: triángulos / mallas / superficies | Perfil ligero |
|---|---|---|
| `g1-sensores` (G1: 12 633 / 35 / 35) | 30 355–36 517 / 83–108 / 164–206 | **13 455–14 909 / 50–55 / 50–75** |
| `rbkairos-plus` (11 632 / 22 / 22) | 32 248–35 562 / 77–98 / 159–202 | **13 423–14 430 / 39–45 / 39–70** |
| `dron-mapeo` (552 / 1 / 3) | 21 168–24 482 / 56–76 / 140–182 | **5 887–7 914 / 37–53 / 66–94** |

El G1 y el RB-KAIROS+ ya gastan 12 633 y 11 632 de los 15 000 triángulos: al mundo le quedan ~2 400. Por eso el
radio visible del G1 es 12 m (`godot/g1-sensores/robot.json`, clave `mundo`) y el del dron, que solo tiene 552, 28 m.

## 4. Qué cambia el perfil ligero

Se activa en la Vita (`OS.has_feature("vita")`) y en el PC con `-- lod=vita` (`aplicacion_robot.gd:85`);
`-- mundo=completo` lo anula para comparar. **Solo cambia lo que se dibuja: las colisiones son idénticas** (53
cuerpos y las mismas cajas, comprobado en `pruebas/perfil_ligero.gd`), así que rayos, LiDAR y mapa dan lo mismo.

| Técnica | Dónde | Efecto medido en el PC |
|---|---|---|
| Cajas del terreno y de la casa fundidas en una malla por color; en las láminas del suelo, solo la cara de arriba | `mundo_base.gd:64-120` | 28 mallas → 11 |
| Variantes de pocos triángulos `*_vita.obj` (clave `modelo_vita`) | `tools/generar-lod-vita.py`, `mundo/assets.json` | 25 de 56 entradas; edificios 2 348–3 496 → 396–666, coches ~2 050 → 345–394 |
| Adornos sin colisión que no se dibujan (clave `"vita": false`): comida, libros, oso | `mundo/assets.json`, `mundo_base.gd:155-157` | 8 entradas, 1 926 triángulos |
| Visibilidad por distancia al robot, con histéresis del 15 %, 4 veces por segundo | `mundo_base.gd:227`, `aplicacion_robot.gd:369` | desde la casa no se dibuja la ciudad |
| Agentes móviles (taxi, persona, animales) quietos mientras no se dibujan | `mundo_base.gd:211-224` | menos cuerpos movidos por fotograma |
| HUD de dos líneas, sin contorno, con un rectángulo detrás; refresco a 4 Hz y solo si cambia el texto; SELECT/H muestra el HUD completo | `aplicacion_robot.gd:314-325, 439` | ~45 letras en vez de ~150 dibujadas dos veces [I] |

Assets del mundo, sumando todas las entradas: 24 320 → 8 036 triángulos [V].

**`tools/generar-lod-vita.py`** reduce por *agrupamiento de vértices* en rejilla (los vértices de una celda se funden
en su media; las caras degeneradas desaparecen) y conserva el color de cada cara con una coordenada de textura
constante, así que no sube el número de superficies. El colapso de aristas (pyfqmr) por grupos de color se probó
antes y se descartó: rompía paredes enteras (comprobado con un render de control). La persona se excluye
(`"lod_vita": false`: brazos y piernas quedaban en hilos). **Validar en la Vita el aspecto** de sillas y coches: el
taxi pierde el detalle de las ruedas. Regenerar: `python3 tools/generar-lod-vita.py` (necesita `numpy` y `pillow`)
y después importar con el editor.

## 5. Coste por tick

| Cambio | Archivo | PC antes → ahora (µs por tick) |
|---|---|---|
| Marcha: una interpolación por (clip, fotograma) sobre búferes reutilizados; el desplazamiento solo interpola x, y y el cuaternión, y reutiliza el final del tramo anterior | `g1-unitree/marcha.gd:65-170` | 9,62 → 5,18 (×1,9) |
| Modelo URDF: metadatos leídos una vez a arrays; la junta que no cambia no se reescribe; nombres resueltos una vez | `g1-unitree/robot/urdf_robot.gd:80-125` (copia idéntica en `rbkairos-plus/robot/`) | 57,8 → 20,5 (×2,8), 29 juntas de las que cambian 12 |
| G1: índice nombre→junta (sin `find()`), `Callable()` en vez de una lambda nueva por tick | `plantillas/robots/humanoide_g1.gd` | — |
| RB-KAIROS+: lista de nombres y búfer de posiciones creados una vez | `plantillas/robots/rbkairos.gd` | — |
| Mapa 2D: celdas libres del rayo en línea (sin llamada por celda ni `Vector2i`) | `plantillas/sensores/mapeo_2d.gd:187` | — |
| Estado Unitree: lista de nombres creada una vez | `plantillas/sensores/unitree_estado.gd` | — |

La marcha nueva da los mismos números que la antigua salvo redondeo (la antigua guardaba pasos intermedios en
float32): error máximo < 1e-5 rad en juntas y < 1e-4 m en desplazamiento tras 400 ticks con 8 cambios de clip
(`pruebas/perfil_ligero.gd`) [V]. `q_joints()` devuelve ahora un búfer reutilizado: quien lo guarde debe copiarlo.

En el PC (x86) el tick completo del robot son 65–87 µs; cuánto es en la Vita lo dirá `[perfil-gd]` (§6). Si el
intérprete de GDScript va ~80 veces más lento en el Cortex-A9 [?], marcha + modelo pasarían de ~5,4 ms a ~2 ms por
tick [I].

## 6. Contadores propios `[perfil-gd]`

`plantillas/ros/perfil.gd`: cada sección mide con `Time.get_ticks_usec()` y cada 300 fotogramas la aplicación
escribe en stderr (en la Vita, `ux0:/data/gxm3d/godot_stderr.log`) una línea como esta (salida real del PC):

```
[perfil-gd] fotogramas=300 camara=20 hud=3 mundo=7 robot=87 sensor/imu_pelvis=10 sensor/joints=15 sensor/mapeo=39
  sensor/mid360_scan=59 sensor/odometria=25 sensor/unitree_estado=78 … triangulos=13244 mallas=40 superficies=43
  luz_vertice=1 ligero=1
```

Valores en µs por fotograma (media). `robot` = marcha + modelo + `move_and_slide`; `sensor/<nombre>` = todo el tick
de ese sensor; `triangulos/mallas/superficies` = el contador del §3 (comparar con `[gxm3d]`). Activo en la Vita y
con `-- perfil` en el PC; `ros/perfil_gd=false` en `project.godot` lo apaga. Lo que **no** mide: el `poll()` de XRCE y
el resto del motor; sale por diferencia con `[vita-prof]`.

## 7. Prueba en la Vita (hecha el 2026-11-13; resultado en §7.1)

Primero T1 (el `.vpk` ya subido, solo con el arreglo de física). Después, con estos cambios aplicados en el PC:

```fish
cd /home/jcrex/Proyectos/PSVita-ROS
tools/export-vita-vpk.sh godot/g1-sensores build/g1-sensores.vpk
tools/deploy-vpk-ftp.sh build/g1-sensores.vpk 192.168.1.94
```

En la Vita: instalar `ux0:/g1-sensores.vpk`, abrir, **andar 1 minuto** (HUD: «luz V»), pulsar **START** (HUD: «luz O»),
**andar otro minuto**, cerrar y activar el FTP de VitaShell. En el PC:

```fish
curl -s --max-time 30 "ftp://192.168.1.94:1337/ux0:/data/gxm3d/godot_stderr.log" -o /tmp/g1s-ligero.log
grep -E "vita-prof|gxm3d\] frame|gxm2d-perf|perfil-gd" /tmp/g1s-ligero.log | tail -24
```

**Verde si**, en las líneas con `luz_vertice=1` o en las de `luz_vertice=0`: `fps ≥ 58` en `[gxm2d-perf]`,
`submitted_triangles ≤ 15000`, `physics_scripts ≤ 2500` y `render + process ≤ 13000` en `[vita-prof]`.
Qué mirar si no: `build_us` (debe caer a ~0 con «luz O»), `lit=` (debe ser 0 con «luz O»), `draws=`/`quads=` del
lienzo (deben bajar de 224/307 a menos de 80) y qué sección de `[perfil-gd]` domina.

### 7.1 Resultado en la Vita (2026-11-13, PC) [V]

Log: [`docs/ia/medidas/g1-sensores-ligero-vita-2026-11-13.log`](ia/medidas/g1-sensores-ligero-vita-2026-11-13.log)
(`.vpk` exportado en el PC desde `68e75c1`; incluye también el arreglo de física a 30 ticks de T1, porque el `.vpk` de
T1 se sustituyó antes de ejecutarlo). Medias por bloque de 300 fotogramas, sin el primero (carga):

| | bloques | fps (mín–máx) | render | process | physics_scripts | robot | sensores | triángulos máx |
|---|---|---|---|---|---|---|---|---|
| Antes (log de 02:42) | 6 | 23,5 | 12 459 | 5 807 | 22 194 | — | — | 19 457 |
| Luz V (`luz_vertice=1`) | 9 | **57,0** (55,6–57,6) | 11 045 | 1 305 | 4 165 | 1 589 | 1 907 | 14 696 |
| Luz O (`luz_vertice=0`) | 14 | **58,1** (56,7–58,6) | 11 121 | 1 260 | 3 923 | 1 390 | 1 893 | 15 000 |

(µs por fotograma; `robot` y `sensores` son de `[perfil-gd]`, `sensores` = suma de las 9 secciones `sensor/*`.)

- **T1: verde de sobra** (criterio `fps ≥ 29` y `physics_scripts ≤ 9500`).
- **T2: ×2,4–2,5 en FPS.** Cumple `triángulos ≤ 15 000` (el máximo toca el límite exacto) y `render + process ≤ 13 000`
  (~12 350). `fps ≥ 58` solo con luz O, y por poco; **`physics_scripts ≤ 2500` no se cumple** (~3 900–4 200).
- **START funciona** en el port (`JOY_BUTTON_START`). Con luz O `lit=0` y `build_us=0`, como se esperaba; el usuario ve
  la escena **algo más oscura**, no plana del todo.
- **La luz por vértice apenas pesa en FPS** (+1,1 fps al quitarla) aunque `build_us` baja 3,8 ms → 0: `render` no baja
  (11 045 → 11 121). [I] La hipótesis del §1 (40–60 FPS con luz) era pesimista: el tiempo liberado lo absorbe la
  espera del fotograma dentro de `render` (sincronía vertical / presentación); el submit 3D real es 1,4–2,3 ms con luz O.
- **Lo que queda hasta 16,7 ms** (~0,4–0,6 ms de media, fotogramas sueltos que pierden la sincronía): está en los
  scripts de física. Reparto: robot ~1,4–1,6 ms (marcha + URDF + `move_and_slide`), sensores ~1,9 ms (los dos
  mayores: `sensor/mapeo` ~0,6 ms y `sensor/mid360_scan` ~0,6 ms), cámara 0,4 ms. `process` ya es 1,3 ms: la
  hipótesis del §8.2 (XRCE `poll()` de 4,7 ms) **queda descartada** para esta escena.

## 8. Qué queda si no llega a 60 FPS

Por orden de ganancia esperada [I]:

1. **Luz por vértice desactivada por defecto** (`"mundo": {"luz_por_vertice": false}` en `robot.json`): −3,9 ms de
   `build` y sin segunda pasada. Coste: cada malla con un tono único. Para que no se vea plano, hornear el sombreado
   en la paleta (ADR 0011 §3: un texel por color × orientación de la cara) en `generar-lod-vita.py` y en las cajas
   fundidas. No hecho: necesita ver el resultado en la GPU.
2. **`_process` 4,7 ms sin escena pesada:** casi todo debe de ser el `poll()` de XRCE (~45 mensajes/s) [?]. Se sabrá
   restando `camara + hud + mundo` de `[perfil-gd]`. Si es XRCE: bajar frecuencias en la Vita o publicar por turnos.
3. **G1 de 12 633 triángulos:** es el 84 % del presupuesto. Una variante de ~8 000 (`tools/urdf2godot` + diezmado)
   daría ~0,8 ms de `submit` y, sobre todo, menos vértices que reiluminar.
4. **Sensores por turnos:** que los 13 sensores no coincidan en el mismo tick (desfase inicial de `_acumulado`).

## 9. Límites de esta sesión (honestidad)

- Ejecutada en la nube: sin Vita, sin el PC del usuario, sin `toolchains/`. El editor de host se compiló aquí desde
  `WolffsRoom/godot4-vita@d1a5f29` con `GODOT_VERSION_STATUS=dev7`, **sin XRCE** (no están las libs) y sin Jolt,
  embree ni OpenXR (para acortar la compilación). Las pruebas son de *loopback* y `sin_ros`.
- No se reconstruyó la plantilla de la Vita ni ningún `.vpk` (no hace falta: no cambia código C++).
- El aspecto de los modelos reducidos solo se revisó con un render de control en matplotlib, no en la GPU.
- Los `.obj.import` de los `*_vita.obj` los generó este editor; al exportar en el PC se regeneran solos.
- Fuera de alcance, visto de paso: el G1 parado deriva ~3 cm/s (clip «quieto» con *root motion*), ya antes de estos
  cambios (`pruebas/fisica.gd`).

## 10. Pruebas (host, 2026-11-13)

| Prueba | Resultado |
|---|---|
| `godot/test/run_host_tests.sh` | 294 comprobaciones, 0 fallos |
| `comun/pruebas/runner.gd` en los 3 proyectos | 14/14, 12/12, 12/12 |
| `comun/pruebas/perfil_ligero.gd -- sin_ros lod=vita` (nueva) | 18/18 (g1-sensores), 12/12, 12/12 |
| `comun/pruebas/presupuesto.gd -- sin_ros lod=vita` (nueva) | OK en los 3 |
| `g1-sensores/pruebas/movimiento_g1.gd -- sin_ros` | 0 fallos |
| Escena principal de los 3 proyectos y de `g1-unitree`, 300–400 fotogramas, *loopback* | sin errores de script |
