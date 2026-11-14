# V3 · Revisión escéptica y de código de la fase V3 del visor (tareas V10–V12, 2026-11-14)

> Revisor: escéptico + revisor de código (Opus 5.5). Commits revisados (`git log --oneline 7090374..0b31c45`):
> `7622701` (decisiones de Fable sobre V2), `91b9242` (V12), `71c04f7` (V11), `50cf371` (V10), `5851d05` y `fe548f7`
> (fusiones V11 y V12), `7111185` (arreglo de la fusión V10 + V12 en ExploradorTopics), `efe5f1f` (`.uid` de V8),
> `0b31c45` (bitácora). Mandan `docs/adr/0013-visualizacion-topics-godot.md` (y su enmienda 2026-11-14),
> `docs/36-visualizacion-topics-godot.md` (§5, §7, §8, §9, §10), `godot/plantillas/visor/README.md` (decisiones de
> V10–V12) y las revisiones `V1-revision.md`, `V2-revision.md` y `V2-juez-fable.md` (mismo formato).
> Marcas: [V] verificado (lectura de código o ejecución) · [I] inferencia · [?] sin confirmar.

## 1. Qué se ejecutó (host, PC CachyOS)

| Prueba | Antes | Después |
|---|---|---|
| `--check-only` de `visor/**`, `pruebas/visor*.gd`, `ros/vc1.gd`, `visor-ros/selector_escena.gd` (73 scripts) | sin errores | sin errores |
| `pruebas/visor.gd` · `visor_primitivas` · `visor_hud` · `visor_displays` | 57 · 114 · 72 · 105 | igual (`visor_displays`: cifras de cupo de Odom 101 → 100, H2) |
| `visor_directos` · `visor_herramientas` · `visor_relay` · `visor_marcadores` · `visor_tf` | 228 · 70 · 80 · 63 · 79 | igual |
| `visor_escenas` (selector) | 21/21 | **21/21** (ciclo con `main_percepcion`, H1) |
| `visor_percepcion` (V10) | 63/63 | **65/65** (+ PNG de 16 bit, H5; + cupo de Odom en `main_percepcion`, H2) |
| `visor_costmap` (V11) | 54/54 | 54/54 |
| `visor_inspector` (V12) | 63/63 | **64/64** (+ diezmado del trazador, H3) |
| `godot/test/run_host_tests.sh` · runner de `g1-sensores` | — | **294 comprobaciones, 0 fallos** · **16/16** |
| `docker/scripts/test_vita_relay.py` (python3 del PC, venv de rosbags y **dentro de `vita_station`** con OpenCV) | TODO OK | **TODO OK** en los tres (+ 2 casos de cámara, H5) |
| `bash -n docker/vita-ros.sh` | — | sin errores |
| Editor `godot.linuxbsd.editor.x86_64 --headless --editor --quit` en `godot/visor-ros` | — | abre sin errores de escena ni de script (solo el aviso conocido del addon `psvita`, que copia `export-vita-vpk.sh`) |
| `tools/export-vita-vpk.sh godot/visor-ros build/visor-ros.vpk` | — | exporta: **23,2 MB, 136 archivos**, con las 4 escenas (`main`, `main_viz`, `banco_v5`, `main_percepcion`), `selector_escena.gd`, `costmap_textura.gd`, `trazador.gd`, `inspector_texto.gd`, `cajas_3d.gd`, `nube.gd`, `imagen.gd`, `explorador_topics.gd`, `introspeccion_ros.gd`; **no se subió** |
| Relay en vivo en la estación (dominio 47, aislado; `fuente-visor` + `fuente-v2` + relay, 20 s de `/vita/relay_bw`) | — | **hmi** (+ `avisos`) **12,8 KB/s, 103 msg/s** (nominal 19,1; ≤ 20 ✓) · **viz** (+ `marcadores,tf` + `fuente-costmap`) **23,4 KB/s, 128 msg/s** (nominal 35,0 y 153) · **percepcion** (+ `percepcion`) **28,1 KB/s, 124 msg/s** (nominal 40,0 y 154; ≤ 40 ✓) |
| Extremo a extremo por XRCE (dominio 0): `relay percepcion` + fuentes + `godot … res://main_percepcion.tscn -- transporte=xrce compacto=1 agente=127.0.0.1 perfil`, 25 s | — | **29 displays `ok`** (Nube, Cajas3D, Imagen, Cajas2D, Costmap, Trazador, Inspector…); `[perfil-gd] rx_paq=7068 topic_dropped=0 reliable_dropped=0 be_dropped=0 reconexiones=0`; `visor/Nube` 8–9 µs y `visor/Cajas3D` 6 µs por fotograma; `[visor-nube] trozos=122 completas=40 us_max=100 puntos=213` (línea nueva, H7) |

## 2. Hallazgos de código

### 2.1 Corregidos (confirmados y seguros)

| # | Dónde | Fallo | Escenario concreto | Corrección |
|---|---|---|---|---|
| H1 | `visor-ros/selector_escena.gd` | `main_percepcion.tscn` fuera del ciclo (punto abierto b) [V] | el gate V10 / E-W8-5 no tenía escena en la `.vpk` (la Vita no acepta argumentos): otra exportación solo para V10 | `escenas` = main → main_viz → banco_v5 → **main_percepcion** → main; prueba de `visor_escenas.gd` actualizada |
| H2 | `2d/pose.gd` | pedía `1 + max_rastro` = 101 *quads*; doc 36 §7.2 le da 100 (punto abierto c) [V] | una polilínea de N puntos son N − 1 segmentos: 100 puntos + triángulo = 100 *quads*, no 101; el sobrante quitaba 1 al resto de `sensores_2d` | `_coste` = `1 + max(max_rastro − 1, 0)` y el límite del rastro en la Vita = `min(max_rastro, cupo)`. Con eso `main_percepcion` sigue **2** por encima (ver D2) |
| H3 | `hud/trazador.gd` | todas las muestras al búfer de 64 [V] | `/odom` del TB3 o `<p>/pose2d` llegan a 30 Hz: 64 muestras = 2,1 s, pero la escala x es de `ventana_s` = 10 s ⇒ la gráfica ocupa la **quinta parte derecha** del panel en PC y Vita (la de `main.tscn`) | diezmado por tiempo: `paso_min_s` (−1 = `ventana_s / capacidad` ≈ 0,156 s; 0 = todas). Prueba: 1 s a 30 Hz guarda 7, no 30 |
| H4 | `hud/inspector_texto.gd` | `set_process_unhandled_input(usar_cruceta and visible)` en `conectar` [V] | la pestaña Inspector está oculta al arrancar ⇒ con `usar_cruceta = true` la cruceta no funcionaba nunca | `set_process_unhandled_input(usar_cruceta)`; `_unhandled_input` ya comprueba `is_visible_in_tree()` |
| H5 | `hud/imagen.gd` + `vita_relay_formatos.recomprimir_camara` | solo se rechazaba `compressedDepth` [V] | image_transport «compressed» de una imagen 16UC1/mono16 publica `format = "16UC1; png compressed"`: Godot (`load_png_from_buffer`) y OpenCV (`IMREAD_COLOR`) lo bajan a 8 bit (T4) y se ve casi negro sin aviso | `es_formato_profundo()` (codificación con 16/32F/64F antes del «;») → rechazo con `motivo`; mismo criterio en el relay. Pruebas en los dos lados |
| H6 | `costmap_textura.gd` `al_meta` | meta sin validar `res` ni origen [V] | `res` = 0 o NaN en `costmap_meta` ⇒ `_componer` divide por `res` (∞/NaN en `clampi`) | `res` > 0 y finito, origen finito; si no, la meta se ignora (T2) |
| H7 | `hud/imagen.gd`, `2d/nube.gd` | los gates E-W8-5 (JPEG ≤ 6 ms) y V10 (trozo ≤ 2 ms) no tenían línea de log [V] | `ms_max` y `us_max_trozo` solo se veían en las pruebas: en la Vita no se podía cerrar el gate (como H3/H5 de V2) | `[visor-imagen] imagenes= rechazadas= ms_ultimo= ms_max= tam=` y `[visor-nube] trozos= completas= us_ultimo= us_max= puntos=` cada 5 s (Vita o `-- perfil`); probado en vivo |
| H8 | `2d/nube.gd` `_indices` | caché de índices por nº de vértices sin tope [V] | en el PC el nº de puntos válidos cambia con cada nube ⇒ un `PackedInt32Array` nuevo (hasta 12 000 enteros) por tamaño distinto: crece sin fin en una sesión larga | se vacía al pasar de 16 tamaños |
| H9 | `vita_relay_percepcion.py` | `camara_hz` admite hasta 5 Hz y el presupuesto se comprueba a 3 Hz [V] | `-p camara_hz:=5` ⇒ el perfil `percepcion` pasa a ≈ 46 KB/s sin que `resolver_modulos` lo vea | aviso al arrancar con lo que se pasa (no se cambia el tope: decisión de D13) |
| H10 | `ros/vc1.gd` | la fusión V10 + V11 pegó el bloque «Costmap» al final de `empaquetar_nube` sin separador [V] | solo lectura (cosmético) | separador y líneas en blanco restaurados |

### 2.2 Fusiones V10 / V11 / V12 (atención especial)

| Comprobación | Resultado |
|---|---|
| `vita_relay_formatos.py` | bloques V10 (`PRESUPUESTO["camara"]`, `IMPLEMENTADOS.update`) y V11 (`IMPLEMENTADOS \|=`) aditivos; sin nombres repetidos; `--comprobar viz` = 35,0 KB/s y `percepcion` = 40,0 KB/s [V] |
| `vc1.gd` | bloques percepción y costmap con nombres propios; cosmético H10 [V] |
| `main.tscn` (V11 Costmap + V12 Gráficas/Inspector/Explorador) ← `main_percepcion.tscn` (V10, heredada) | `Nube` con `index="3"` queda entre Plan y Scan **después** de que V11 insertara Costmap: el orden de reserva pasó a Mapa 1 + Costmap 1 + Plan 112 + Nube 228 + Scan 360 = 702 ⇒ Odom recibe 98 (el README de V10 decía 99, escrito antes de la fusión) [V, prueba de escena] |
| `RegistroDisplays` | `*/detecciones` y `*/detecciones3d` antes del `*MultiArray` genérico; `*costmap*` OccupancyGrid antes del mapa; el comodín `*` → inspector (V12) [V]. `*/tf` sigue cayendo en `hud/multiarray.gd` (N1 de V2): inocuo, el explorador no añade displays solo |
| ExploradorTopics × Teleop | ya resuelto en `7111185` [V] |
| HUD (D6) | Cámara 2 + 32 + 150 = 184; Gráficas 3·63 + 25 = 214; Inspector 8 × 30 = 240 (≤ 240 cada una) [V] |
| Presupuesto 2D `resto_2d` | Marcadores2D 150 + Cajas3D 144 = 294 ≤ 300 [V] |

### 2.3 No corregidos (riesgo anotado)

| # | Dónde | Hallazgo | Escenario | Destino |
|---|---|---|---|---|
| N1 | `hud/imagen.gd` (PC) | el *shader* BGR es del `CanvasItem` entero | con `bgr8` crudo el fondo y el texto de la pestaña también se ven con R y B cambiados | cosmético, solo PC |
| N2 | `TablaClasesDet` (relay) | el índice de clase se asigna también a detecciones que luego no entran en las 18/12 mejores | con > 64 clases distintas en la vida del relay, las nuevas salen «?» | anotado: COCO tiene 80 clases, más que `MAX_CLASES_DET` = 64; si un detector COCO las usa todas, subir el tope (la lista viaja como `String` fiable) |
| N3 | `costmap_textura.de_tesela` | 256 `append_array` por tesela (bucle por byte, no por píxel) | 158 µs en el host; en la Vita [?] | se mide con `[visor-costmap] max_us=` en M5 |
| N4 | `2d/costmap.gd` | reserva 1 *quad* aunque no dibuje nada cuando compone sobre el Mapa | parte del exceso de D2 | ver D2 |
| N5 | trazador | rango y solo crece (decisión V12-3) | un pico deja la gráfica aplastada hasta reconectar | aceptado (anotado en V12) |

## 3. DESAFÍOS para el juez (Fable)

> **Resueltos** en `docs/ia/workshops/posts/V3-juez-fable.md` (2026-11-14): D1 = A + D automática (`costmap_teselas_max`
> = 30 en el relay); D2 = D (`max_rastro = 98` en `main_percepcion.tscn`); D3 = más de 3 Hz solo si el relay sigue
> ≤ 40 KB/s. El §5 de abajo ya lleva los criterios resultantes.

### D1 — Gate G-W13-M5 contradictorio (punto abierto a)

**Hechos** [V]: `costmap` = 10 teselas/s × 276 B (`PRESUPUESTO`, doc 36 §5.3); doc 36a §4.6.2 cita un costmap de
20 × 20 m a 10 cm = 200 × 200 celdas = 7 × 13 = **91 teselas** ⇒ repaso completo 9,1 s, no ≤ 3 s. Con la fuente de
prueba (10 × 10 m, 28 teselas) el repaso medido fue 2,9–3,2 s. Los parches salen primero y por cercanía (< 1 s).

| Opción | Coste | Efecto |
|---|---|---|
| A. Leer el gate como «**parches** ≤ 3 s; repaso completo ≤ teselas/10 s» | ninguno | honesto con el presupuesto; el usuario ve el costmap entero 9 s después de conectar |
| B. `costmap` a 30 teselas/s | +5,5 KB/s y +20 dgr/s: viz = 40,5 KB/s y 173 dgr/s (dentro de 100/200, fuera del ≈ 35 de §5.4) | repaso de 91 en 3,0 s siempre |
| C. Ráfaga solo tras época nueva (30/s hasta vaciar la cola del repaso inicial, luego 10/s) | código en `EstadoCostmap` + presupuesto de pico | repaso inicial ≤ 3 s; medio igual que hoy |
| D. `costmap_res_min` = 0,2 m cuando el costmap pase de 30 teselas | resolución peor (20 cm) en costmaps grandes | 20 × 20 m → 100 × 100 = 28 teselas = 2,8 s, sin tocar la red |

Recomendación del revisor: **A + D** (el gate se mide con ≤ 30 teselas; D como parámetro ya existente, sin código).

### D2 — `sensores_2d` en `main_percepcion.tscn` (punto abierto c, resto)

Tras H2: Mapa 1 + Costmap 1 + Plan 112 + Nube 228 + Scan 360 + Odom 100 = **802 > 800**; Odom recibe 98 (aviso
`VisorRos: Odom pide 100 en «sensores_2d» y recibe 98`). Doc 36 §7.2 suma 800 sin contar el *quad* del mapa.

| Opción | Efecto |
|---|---|
| A. Aceptar el recorte (rastro de 97 puntos; aviso en el log) | sin cambios; 2 *quads* |
| B. Mapa y Costmap a la capa `mundo` (la textura de la planta es «mundo») | `sensores_2d` = 800 justo; `mundo` HMI 12 → usa 1–2 |
| C. Costmap reserva 0 cuando compone sobre el Mapa (N4) | 801; sigue faltando 1 |
| D. `max_rastro = 98` en `main_percepcion.tscn` (propiedad de escena, doc 35) | 800 justo, sin código |

Recomendación: **B** (el coste del mapa no es de sensores) o **D** si no se quiere tocar capas.

### D3 — V10-1 `camara_hz` ≤ 5 frente al presupuesto a 3 Hz

H9 avisa; decidir si `CAMARA_HZ_MAX` baja a 3 (presupuesto cerrado) o si `comprobar_presupuesto` debe recibir el
`camara_hz` real (necesita leer parámetros antes de `resolver_modulos`). Recomendación: tope 3 en el perfil
`percepcion`, 5 solo pidiendo el módulo `camara` suelto.

## 4. Veredictos de las decisiones anotadas (README del visor, V10–V12)

| Decisión | Veredicto | Motivo |
|---|---|---|
| V10-1 tope 2 994 B | VERIFICADO / **DESAFÍO D3** | 39,998 KB/s exactos con 3 Hz; `camara_hz` hasta 5 lo rompe (H9) |
| V10-2 aspecto conservado, cajas en px originales | VERIFICADO | `tam_camara` y `det2d_tam`; prueba 1280×720 → 160×90 |
| V10-3 solo lo nuevo + caducidad | VERIFICADO | en vivo: cajas y nube caducan al parar la fuente |
| V10-4 mejores 18/12, clases por llegada | VERIFICADO con aviso | N2 (índices de clases recortadas) |
| V10-5 det3d y nube al marco fijo en el relay | VERIFICADO | sin TF el ciclo no se manda (como marcadores); yaw solo |
| V10-6 primer punto del vóxel, `floor(v·100 + 0,5)` | **VERIFICADO** | huella `nube` idéntica Python/numpy/GDScript |
| V10-7 fiabilidad (BE por relay, imagen fiable) | VERIFICADO | 2 994 B caben en el flujo fiable de entrada (16 × 512 B, `xrce_transport.cpp:143-144,240`) |
| V10-8 cruda solo PC y 8 bit | VERIFICADO tras H5 | PNG 16 bit «compressed» también fuera; N1 cosmético |
| V10-9 PointCloud2 PC FLOAT32, sin big endian | VERIFICADO tras H8 | |
| V10-10 prueba fuera de `runner.gd` | VERIFICADO | g1-sensores 16/16 |
| V10-11 hallazgo 101 *quads* | **CORREGIDO (H2) / DESAFÍO D2** | queda 802 por la fusión con V11 |
| V11-1 display propio + composición en el Mapa | **VERIFICADO** | 1 *quad*; `compuesto=true` en vivo (V11) |
| V11-2 niveles de 4 bit | VERIFICADO | huella `HUELLA_COSTMAP` cruzada |
| V11-3 reducción por máximo | VERIFICADO | un obstáculo de 5 cm no desaparece |
| V11-4 época y descarte | VERIFICADO | |
| V11-5 gate M5 | **DESAFÍO D1** | 91 teselas = 9,1 s |
| V11-6 composición por regiones | VERIFICADO | byte a byte igual a componer todo (prueba) |
| V11-7 Mapa no sube su textura mientras compone | VERIFICADO | evita 2 subidas de 384² a 4 Hz (T26) |
| V11-8 desconocido 0x708986 | VERIFICADO | como RViz |
| V11-9 PC sin `_updates` | VERIFICADO con aviso | Nav2 necesita `always_send_full_costmap` en el PC |
| V11-10 costmap global por defecto | VERIFICADO | el local rodante cambia de época a cada paso |
| V11-11 orden por cercanía con `/odom` | VERIFICADO | |
| V11-12 prueba fuera de `runner.gd` | VERIFICADO | |
| V12-1 inspector 8 × 30 en la Vita | VERIFICADO | 240 = pestaña entera |
| V12-2 cruceta apagada | VERIFICADO tras H4 | |
| V12-3 trazador (rango que crece, NaN fuera, `caducidad_s` 0, pendientes = capacidad) | VERIFICADO tras **H3** | sin diezmado la ventana de 10 s quedaba en 2 s |
| V12-4 explorador sin añadir en la Vita | VERIFICADO | D9 |
| V12-5 RegistroDisplays sin cambios | VERIFICADO | `*/tf` sigue en multiarray (inocuo) |
| V12-6 caché solo con esquema | VERIFICADO | |

## 5. Guion único de hardware (usuario; fish en el PC CachyOS)

Una `.vpk` (`build/visor-ros.vpk`, ya exportada), **nueve** lanzamientos de la app. Cada lanzamiento reescribe los logs
de la Vita: recoger tras cada fase con la app **cerrada** (VitaShell en primer plano, SELECT = FTP). Terminales:
T1 estación, T2 fuente base, T3 relay, T4 fuente extra, T5 consultas, T6 RViz. Ctrl+C en T3/T4 al cambiar de fase.

Botones (validar en hardware): **L** = pestaña anterior (da la vuelta). En `main.tscn` el orden es Estado, Mando,
Diagnóstico, Consola, Gráficas, Inspector: desde Estado, L ×1 = **Inspector**, ×2 = **Gráficas**, ×3 = **Consola**,
×4 = **Diagnóstico** (V12 añadió dos pestañas: el «L una vez = Consola» del guion de V2 ya no vale). En
`main_percepcion.tscn`, L ×1 = **Cámara**. **START** = banco E-W8-1. **L + R mantenidos + START** = siguiente escena
(main → main_viz → banco_v5 → main_percepcion → main), que se guarda y es la que abre el siguiente lanzamiento.
**SELECT** = herramienta siguiente; **✕** = confirmar.

Subcomandos usados (todos existen en `docker/vita-ros.sh`, comprobado con `bash -n` y lectura del `case`): `up`,
`logs agent`, `fuente-visor`, `relay [mód] [pref] [ritmo] [tf_lista]`, `fuente-v2 [modos] [n]`, `fuente-costmap [s]`,
`netem <IP> [%]` / `netem off`, `echo <topic>`, `rviz`. Contenedor: `vita_station`.

```fish
cd ~/Proyectos/PSVita-ROS
# --- 0. Preparación (una vez) -------------------------------------------------------------------------------------
# (la .vpk ya está exportada; si se toca algo: tools/export-vita-vpk.sh godot/visor-ros build/visor-ros.vpk)
tools/deploy-vpk-ftp.sh build/visor-ros.vpk 192.168.1.94          # VitaShell → ux0:/visor-ros.vpk → instalar
function recoger --argument-names fase
    curl -s --max-time 30 "ftp://192.168.1.94:1337/ux0:/data/gxm3d/godot_stderr.log" -o /tmp/v3-$fase.err
    curl -s --max-time 30 "ftp://192.168.1.94:1337/ux0:/data/gxm3d/godot_stdout.log" -o /tmp/v3-$fase.out
    grep -hE '\[(gxm2d-perf|gxm3d|vita-prof|vita-memory|perfil-gd|visor-mapa|visor-marc|visor-banco|visor-herr|visor-costmap|visor-imagen|visor-nube|visor-escena)\]' /tmp/v3-$fase.err /tmp/v3-$fase.out | tail -n 60
end
function bw   # ancho de banda real del relay hacia la Vita (bytes/s, mensajes/s), 10 muestras
    docker exec vita_station bash -lc "source /opt/ros/jazzy/setup.bash; timeout 12 ros2 topic echo --qos-reliability best_effort /vita/relay_bw std_msgs/msg/Float32MultiArray --field data"
end
function pub; docker exec -d vita_station bash -lc "source /opt/ros/jazzy/setup.bash; ros2 topic pub -r 5 $argv"; end
docker/vita-ros.sh up                                              # T1 (luego: docker/vita-ros.sh logs agent)
docker/vita-ros.sh fuente-visor                                    # T2: mapa, scan, odom, joints, plan, HUD (toda la sesión)

# --- F1 · main · V1: G-W13-H0 y E-W8-1. Sin relay ------------------------------------------------------------------
#   Vita: abrir «ROS2 Vita Visor» (si abre otra escena: L+R+START hasta main), 60 s en Estado; START (banco de 80); 30 s; cerrar.
recoger f1

# --- F2 · main · V3 + V9 (TF) + V7 (herramientas). Relay hmi + tf con 8 hijos ---------------------------------------
docker/vita-ros.sh relay hmi,tf /vita "" odom,rueda_izq,rueda_der,torre,brazo,pinza,antena,camara   # T3
docker/vita-ros.sh fuente-v2 tf                                    # T4
docker/vita-ros.sh rviz                                            # T6: Fixed Frame «map», añadir TF y LaserScan
#   Vita: abrir, 90 s (mapa, scan sobre el robot, ejes del TF). Comparar con RViz.
#   V7: SELECT ×2 → «Meta»; tocar y arrastrar (no publica); ✕ → publica.
docker/vita-ros.sh echo /goal_pose                                 # T5 (Ctrl+C y el siguiente)
#   SELECT → «Pose inicial»: tocar, arrastrar, ✕.
docker/vita-ros.sh echo /initialpose
#   SELECT → «Punto»: un toque (sin ✕).
docker/vita-ros.sh echo /clicked_point
#   cerrar la app.
recoger f2

# --- F3 · main · V6: 20 avisos/s durante 5 min. Relay hmi ----------------------------------------------------------
docker/vita-ros.sh relay hmi                                       # T3 (Ctrl+C al anterior)
docker/vita-ros.sh fuente-v2 avisos                                # T4 (Ctrl+C al anterior)
bw                                                                 # T5: ≤ 20 000 B/s
#   Vita: abrir; L ×3 → Consola; 5 min; L ×1 más → Diagnóstico («bateria» cambia de color cada 5 s); cerrar.
recoger f3

# --- F4 · main · V8: G-W13-M1, G-W13-M3 (y M2 opcional). Relay hmi + marcadores ----------------------------------
docker/vita-ros.sh relay hmi,marcadores                            # T3
docker/vita-ros.sh fuente-v2 marcadores                            # T4 (31 sólidos + línea + texto a 10 Hz)
#   Vita: abrir, 60 s (M1). Luego M3 durante 2 min:
docker/vita-ros.sh netem 192.168.1.94 10                           # T5: 10 % de pérdida SOLO hacia la Vita
docker exec -it vita_station bash -lc "source /opt/ros/jazzy/setup.bash; ros2 topic bw /vita/marcadores"
docker/vita-ros.sh netem off                                       # ¡siempre al acabar!
#   (Opcional M2: Ctrl+C en T4; docker/vita-ros.sh fuente-v2 vida; 5 min.) Cerrar la app.
recoger f4

# --- F5 · main · V11 (G-W13-M5) + V12 (Gráficas e Inspector). Relay hmi + costmap ---------------------------------
docker/vita-ros.sh relay hmi,costmap                               # T3
docker/vita-ros.sh fuente-costmap                                  # T4 (10 × 10 m a 5 cm → 28 teselas; parches cada 1 s)
bw                                                                 # T5: ≈ 22 000 B/s
#   Vita: abrir con la app YA arrancado el relay y cronometrar a ojo cuándo se completa el costmap en la planta.
#   60 s en Estado (línea base); L ×1 → Inspector 30 s (las filas de pose2d cambian 4 veces/s);
#   L ×1 → Gráficas 60 s (2 series: vx y wz de pose2d, la ventana de 10 s llena todo el ancho).
#   Antes de cerrar: mantener L + R y pulsar START → main_viz (se guarda). Cerrar la app.
recoger f5

# --- F6 · main_viz · G-W13-M1v (perfil Viz entero). Relay viz ------------------------------------------------------
docker/vita-ros.sh relay viz                                       # T3 (marcadores, pose_cov, poses, tf, costmap)
docker/vita-ros.sh fuente-v2 marcadores,tf                         # T4 (deja fuente-costmap en otra terminal o reábrelo)
bw                                                                 # T5: ≤ 35 000 B/s
#   Vita: abrir (debe abrir main_viz directamente); 60 s; L + R + START → banco_v5; cerrar.
recoger f6

# --- F7 · banco_v5 · gate V5 (displays directos). SIN relay ---------------------------------------------------------
#   Ctrl+C en T3 y T4 (el relay no hace falta). Publicar los 10 tipos:
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
#   Vita: abrir (banco_v5); 60 s mirando; L + R + START → main_percepcion; cerrar.
docker exec vita_station pkill -f "ros2 topic pub"
recoger f7

# --- F8 · main_percepcion · V10 (E-W8-5 y percepción). Relay percepcion -------------------------------------------
docker/vita-ros.sh relay percepcion                                # T3
docker/vita-ros.sh fuente-v2 percepcion                            # T4 (cámara 640×480, /detections, /detections_3d, /points)
bw                                                                 # T5: ≤ 40 000 B/s
#   Vita: abrir (main_percepcion); L ×1 → Cámara; 90 s (imagen + cajas 2D; nube en la planta; cajas 3D sobre la vista).
#   Al acabar: L + R + START → main (deja la app como al principio). Cerrar.
recoger f8

# --- F9 · cierre -------------------------------------------------------------------------------------------------------
#   Ctrl+C en T2–T6. Comprobar que el siguiente arranque abre main (o borrar ux0:/data/…/visor_escena.txt, ruta en [visor-escena]).
```

### Criterio de verde por gate

| Gate (tarea) | Fase | Línea / fuente | Verde |
|---|---|---|---|
| **G-W13-H0** (V4/V1) | F1, antes de START | `[gxm2d-perf] quads= draws=`, `[perfil-gd] hud_glifos=` | `quads` ≤ 400 y `draws` ≤ 30 en la pestaña Estado |
| **E-W8-1** (V2/V1) | F1, tras START | `[gxm3d] drawn= lit=`, `[visor-banco] activo=true instancias=80` | `lit=0`, `drawn` ≥ 80, `fps` ≥ 59 |
| **V3** | F2 | `[gxm2d-perf] fps=`, `[vita-prof] process=`, `[visor-mapa] media_us= max_us=` | `fps` ≥ 55; `process` ≤ 4 000 µs; `media_us`, `max_us` ≤ 1 500 |
| **V9** | F2 | `[perfil-gd] visor/TF=`; a la vista | `visor/TF` ≤ 500 µs; el scan sigue al triángulo de odometría; EJES de map, odom, base_link, base_scan donde los pone RViz (map → odom ≈ 0,6 m adelante, 0,3 m a la izquierda, yaw 0,1); 3 de 11 marcos sin ejes es lo esperado (cupo 8) |
| **V7** | F2 | T5 `echo`, `[visor-herr]` | arrastrar sin ✕ no publica; cada ✕ = **un** mensaje con `frame_id: map`; `/initialpose` con covarianza 0,25/0,25/0,0685; `/clicked_point` con un toque; `toque n=` de uno en uno |
| **V6** | F3 | `[gxm2d-perf] fps=`, `[perfil-gd] reliable_dropped= topic_dropped=`, `bw` | 5 min con `fps` ≥ 55; `reliable_dropped=0`; consola con «W prueba_avisos: aviso N» subiendo; Diagnóstico con «bateria» cambiando cada 5 s; `bw` ≤ 20 000 B/s |
| **G-W13-M1** (V8) | F4, sin netem | `[gxm3d] drawn= avg_submit_us=`, `[visor-marc] nodos= hijos=` | `nodos=12`, `hijos` constante; `drawn` +12; `avg_submit_us` ≤ 6 000; `fps` ≥ 55 |
| **G-W13-M3** (V8) | F4, con netem | `[vita-prof] process=`, `ros2 topic bw`, a la vista | ningún sólido fuera de sitio > 0,4 s; `process` ≤ 4 000 µs; `/vita/marcadores` ≤ 15 KB/s |
| G-W13-M2 (V8, opc.) | F4, `vida` | `[visor-marc]`, `[vita-memory]` | 5 min: `nodos=12` e `hijos` constantes; memoria estable; `sin_sitio` creciendo es lo esperado |
| **G-W13-M5** (V11) | F5 | `[visor-costmap] teselas= descartadas= max_us= composicion_us= compuesto=`, `[gxm2d-perf] fps=`, cronómetro | `compuesto=true`; `teselas` sube ≈ 50 cada 5 s; `descartadas` ≤ 1 tras el arranque; costmap completo en la planta (paredes magenta con borde cian, degradado azul → rojo) en **≤ 3 s** (28 teselas con esta fuente; con Nav2 + TB3 el relay lo deja en 18 a 20 cm por `costmap_teselas_max` = 30, juez V3 F1) y el obstáculo móvil (parche) refrescado en **< 1 s**; `composicion_us` ≤ 4 000; `max_us` ≤ 1 500; `fps` ≥ 30 (≥ 55 deseable: `main` es HMI) |
| **V12** (Inspector) | F5 | a la vista, `[perfil-gd] hud_pestana=Inspector hud_pestana_q=` | 8 filas de `pose2d` actualizándose; `hud_pestana_q` ≤ 240; `fps` sin bajar de escalón |
| **V12** (Gráficas) | F5 | pares `[perfil-gd] hud_pestana=…` + `[gxm2d-perf] draws= avg_canvas_us=` siguientes, Estado frente a Gráficas | **`draws` +≤ 3** y **`avg_canvas_us` +≤ 300** respecto a Estado; 2 trazas que llenan el ancho (H3) |
| **G-W13-M1v** (V8, perfil Viz) | F6 | `[visor-marc] nodos=`, `[gxm3d] drawn= avg_submit_us=`, `[gxm2d-perf] fps=`, `bw` | `nodos=32`; `drawn` +32; `avg_submit_us` ≤ 9 000; `fps` ≥ 30; `bw` ≤ 35 000 B/s |
| **V5** | F7 | a la vista, `godot_stderr.log`, `[gxm3d] drawn=` | los 10 se ven (esfera magenta, flecha azul, ejes, IMU, flechas + anillo, cono, cubo naranja; cuadrado verde, elipse rosa y punto GPS en la planta); sin `ERR_FAIL` ni «no esta en el esquema»; `drawn` ≥ 10; `fps` ≥ 30 |
| **E-W8-5** (V10) | F8, pestaña Cámara | `[visor-imagen] ms_ultimo= ms_max= tam=160x120` | **`ms_max` ≤ 6,0** (decodificar JPEG + subir textura); `rechazadas=0`; imagen fluida a ≈ 3 Hz |
| **V10** (percepción) | F8 | `[visor-nube] us_max= puntos=`, `[gxm2d-perf] fps=`, `[perfil-gd] reliable_dropped=`, `bw`, a la vista | `us_max` ≤ 2 000 por trozo; `puntos` ≤ 228; `fps` ≥ 55 (HMI); `reliable_dropped=0`; `bw` ≤ 40 000 B/s; cajas 2D con «persona 87%» etc. sobre la imagen y cajas 3D de alambre sobre la vista |
| **Selector** (V2 juez) | F5→F6, F6→F7, F7→F8, F8 | `[visor-escena] siguiente= guardada=true` y, en el lanzamiento siguiente, `[visor-escena] escena=` | el cambio en caliente carga la escena (o, si falla, el siguiente arranque abre la guardada) |
| Enlace | todas | `docker/vita-ros.sh logs agent`, `[perfil-gd] reconexiones=` | sesión establecida; `reconexiones=0` salvo caída provocada |

Esperable y no es fallo: aviso «Marcadores pide 48 … recibe 12» (HMI); en F4, `sin_sitio` creciendo; en F5, una tesela `descartada` al arrancar (llega antes que la meta). En F8 ya **no** debe salir «Odom pide 100 … recibe 98» (juez V3 F2: la escena pide 98).

## 6. Archivos

- Tocados: `godot/visor-ros/selector_escena.gd`; `godot/plantillas/visor/{costmap_textura.gd,README.md}`;
  `displays/2d/{pose,nube}.gd`; `displays/hud/{imagen,trazador,inspector_texto}.gd`; `godot/plantillas/ros/vc1.gd`;
  pruebas `visor_{displays,escenas,inspector,percepcion}.gd`; `docker/scripts/{vita_relay_formatos,vita_relay_percepcion,test_vita_relay}.py`.
- `.uid` que creó el editor (V10 y selector) versionados.
- **Validar en hardware:** todo el §5. Reexportar solo si se toca código (`build/visor-ros.vpk` se reexportó tras las
  decisiones del juez V3: lleva `main_percepcion.tscn` con `max_rastro = 98`).
