# V3 · Decisiones del juez sobre los desafíos de la fase V3 del visor (2026-11-14)

> Juez: Fable 5.2 (regla del usuario 2026-11-13: las decisiones no se le preguntan). Resuelve los **DESAFÍOS** D1–D3 de
> `docs/ia/workshops/posts/V3-revision.md` §3 contra `docs/adr/0013-visualizacion-topics-godot.md` (y su enmienda de V2),
> `docs/36-visualizacion-topics-godot.md` §5, §7, §9 y las decisiones V10–V11 de `godot/plantillas/visor/README.md`.
> Marcas: [V] verificado en host · [I] inferencia · «validar en hardware» donde solo la Vita lo dice.

## F1 — Gate G-W13-M5: repaso del costmap ≤ 3 s (resuelve D1)

**Hechos** [V]: el módulo `costmap` declara 10 teselas/s × 276 B (`docker/scripts/vita_relay_formatos.py:176`, doc 36
§5.3), así que un repaso tarda `teselas / 10` s. El gate dice «Nav2 + TB3», y ese caso **no** es el de la fuente de
prueba: el mapa habitual del TB3 es de 384 × 384 celdas a 5 cm (19,2 m) → 192 × 192 a 10 cm = 6 × 12 = **72 teselas =
7,2 s**; el de 20 × 20 m de doc 36a §4.6.2, 91 teselas = 9,1 s. Solo la fuente sintética (10 × 10 m, 28 teselas) cumple.

**Decisión: A + D, con D automática en el relay. El presupuesto de red no cambia.**

- **Tope de teselas** `costmap_teselas_max` = **30** (parámetro nuevo del nodo; 0 = sin tope). El relay sube el
  factor de reducción (entero, por máximo, como ya hacía con `costmap_res_min`) hasta que el costmap reducido quepa en
  30 teselas: `factor_costmap_tope()` y `EstadoCostmap(res_min, teselas_max)` en
  `docker/scripts/vita_relay_formatos.py`. La Vita no cambia: lee la resolución de `costmap_meta`.

  | Costmap de entrada | Antes (solo `res_min` 0,1 m) | Ahora (tope 30) |
  |---|---|---|
  | 10 × 10 m a 5 cm (`fuente-costmap`) | 10 cm, 28 teselas, 2,8 s | igual |
  | TB3 384 × 384 a 5 cm (19,2 m) | 10 cm, 72 teselas, 7,2 s | **20 cm, 18 teselas, 1,8 s** |
  | 20 × 20 m a 5 cm (doc 36a §4.6.2) | 10 cm, 91 teselas, 9,1 s | **20 cm, 28 teselas, 2,8 s** |

- **Gate G-W13-M5 (texto nuevo, doc 36 §9.1):** repaso completo **≤ 3 s** con el tope por defecto (≤ 30 teselas, lo
  garantiza el relay) **y** un parche (`_updates`) visible en **< 1 s**; ≥ 30 FPS; `composicion_us` ≤ 4 000. Con
  `costmap_teselas_max:=0` el repaso es `teselas / 10` s y queda fuera del gate (opción A, a elección de quien lo pida).
- **Por qué no B (30 teselas/s):** +5,5 KB/s y +20 dgr/s permanentes para algo que solo importa al conectar; saca el
  perfil `viz` de sus ≈ 35 KB/s (ADR 0013 §5) antes de haber medido la recepción real (G-W13-R0).
- **Por qué no C (ráfaga tras época nueva):** código nuevo en el camino de envío y un presupuesto «de pico» que
  `comprobar_presupuesto` no sabe expresar; el costmap local rodante (README V11-10) dispararía la ráfaga a cada paso.
- **Coste asumido:** en mapas grandes las celdas del costmap son de 20 cm (4 px del mapa de 5 cm). La reducción es
  por máximo (V11-3): un obstáculo no desaparece, solo engorda. La escala respecto al mapa sigue siendo entera (el
  factor es entero), que es el caso probado byte a byte de la composición (V11-6).
- **Reversión:** `-p costmap_teselas_max:=0` (o un valor mayor) en el relay; no toca la `.vpk`.
- Probado [V]: `test_vita_relay.py` (factores 2 / 4 / 4, 18 teselas con el mapa del TB3, parche con factor 4, sin
  tope 72); en vivo en la estación (dominio 47): `costmap 200×200 → 100×100 a 0.10 m, 28 teselas en cola`.

## F2 — `sensores_2d` en `main_percepcion.tscn` suma 802 (resuelve D2)

**Decisión: opción D. `max_rastro = 98` en el nodo `Odom` de `godot/visor-ros/main_percepcion.tscn`; sin código.**

- Suma [V, `pruebas/visor_percepcion.gd`]: Mapa 1 + Costmap 1 + Plan 112 + Nube 228 + Scan 360 + Odom 98 = **800**
  justos; Odom pide 98 y recibe 98, sin el aviso «pide 100 … recibe 98». `main.tscn` y `main_viz.tscn` no cambian
  (sin nube suman 574; Odom sigue en 100).
- **Regla que queda escrita** (doc 36 §7.2, ADR 0013): las texturas de planta (Mapa y Costmap, 1 *quad* cada una)
  **cuentan dentro de los 800** de sensores 2D; la escena que lleve scan, nube y path completos deja 98 para poses y
  odometría. Es una propiedad de escena editable (regla doc 35), no un recorte silencioso del código.
- **Por qué no B (Mapa y Costmap a la capa `mundo`):** `mundo` cuenta **instancias 3D** (80 / 150 de ADR 0011 §6);
  meter ahí *quads* 2D mezcla unidades en las dos cuentas (el 2D dibujaría 802 con 800 declarados) y toca
  `2d/mapa.gd` y `2d/costmap.gd`, compartidos por las cuatro escenas, justo antes de los gates de hardware.
- **Por qué no A ni C:** A deja un aviso permanente en el log que hay que explicar en cada gate; C (N4: el costmap
  reserva 0 cuando compone) deja 801.
- N4 se queda como está: el *quad* reservado del Costmap es el que usa cuando no hay mapa sobre el que componer.
- Rastro: 97 puntos en vez de 99 a 30 Hz de `pose2d` diezmado por distancia; no se nota.

## F3 — `camara_hz` hasta 5 con el presupuesto a 3 Hz (resuelve D3)

**Decisión: el presupuesto manda. Más de 3 Hz solo si el relay entero sigue ≤ 40 KB/s nominales.**

- `camara_hz_efectivo(modulos, pedido)` (`vita_relay_formatos.py`, función pura con prueba): calcula la suma nominal
  de los módulos activos con la cámara al ritmo pedido. Si pasa de **40 KB/s** (`KB_PERFIL_MAX`, la suma del mayor
  perfil declarado, ADR 0013 §5) o de 200 dgr/s, la cámara **se queda en 3 Hz** y el relay lo avisa; si cabe, se
  concede (hasta `CAMARA_HZ_MAX` = 5) y lo dice.

  | Módulos | `camara_hz:=5` | Resultado |
  |---|---|---|
  | `percepcion` | 46,0 KB/s, 168 dgr/s | **3 Hz** (39,998 KB/s) + aviso |
  | `hmi,camara` | 34,1 KB/s, 143 dgr/s | **5 Hz** concedidos |
  | `viz,camara` | 50 KB/s | 3 Hz + aviso |

- Es la recomendación del revisor (tope 3 en `percepcion`, 5 con `camara` suelto) expresada por presupuesto y no por
  nombre de perfil: vale igual para una lista de módulos hecha a mano.
- **Por qué no bajar `CAMARA_HZ_MAX` a 3:** D13 admite 5 Hz y `hmi,camara` a 5 Hz cabe con margen. **Por qué no solo el
  aviso (H9):** un aviso no impide que el perfil deje de cumplir lo que el ADR declara.
- Los 3 Hz se conceden siempre (el tope duro de 100 KB/s / 200 dgr/s ya lo comprueba `resolver_modulos` al arrancar).
- Probado [V] en vivo (estación, dominio 47): `camara: camara_hz 5 daría 46.0 KB/s y 168 dgr/s … se queda en 3 Hz` con
  `percepcion`; `camara: 5 Hz concedidos (34.1 KB/s nominales ≤ 40)` con `hmi,camara`.
- **Validar en hardware:** que 5 Hz de imagen fiable (≈ 7 fragmentos por imagen) no llene el flujo fiable de entrada
  (16 × 512 B); hasta entonces el guion de gates usa 3 Hz.

## Pruebas (host, PC CachyOS)

| Prueba | Resultado |
|---|---|
| 13 suites `godot/plantillas/pruebas/visor*.gd` | 54 · 228 · 105 · 21 · 57 · 70 · 72 · 64 · 63 · **66** (`visor_percepcion`, +1) · 114 · 80 · 79, todas verdes |
| `godot/test/run_host_tests.sh` · runner de `g1-sensores` | 294 comprobaciones, 0 fallos · 16/16 |
| `docker/scripts/test_vita_relay.py` (python3 del PC y dentro de `vita_station`) | TODO OK (+ tope de teselas, + `camara_hz_efectivo`) |
| `tools/export-vita-vpk.sh godot/visor-ros build/visor-ros.vpk` | reexportada (23,2 MB; cambia `main_percepcion.tscn`); **no subida** |

## Archivos

- Tocados: `docker/scripts/{vita_relay_formatos,vita_relay,vita_relay_percepcion,test_vita_relay}.py`;
  `godot/visor-ros/main_percepcion.tscn`; `godot/plantillas/pruebas/visor_percepcion.gd`;
  `godot/plantillas/visor/README.md`; doc 36 §7.2 y §9.1; doc 36a §4.5.6; ADR 0013 (enmienda); `V3-revision.md` §3 y §5;
  `docs/06-bitacora-estado.md`.
- El guion de hardware (`V3-revision.md` §5) no cambia de pasos: cambian el criterio de G-W13-M5 y la lista de avisos
  esperables (ya no sale el de Odom en F8). Hay que **subir** la `.vpk` reexportada.
