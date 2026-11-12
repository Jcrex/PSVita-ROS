# R1 — Revisión de las colas XRCE de Kimi (commit 909e6ab)

> Revisión solo lectura, 2026-11-12. Alcance: `godot/ros2_vita/xrce_transport.cpp` (el `.h` no cambió),
> `docs/30-rendimiento-xrce-plantillas.md`, `godot/ros2_vita/API_PARITY.md`, pruebas `godot/test/`.
> Fuente de micro-XRCE-DDS consultada: `vita-app/third_party/_build/Micro-XRCE-DDS-Client` (tag v2.4.3).
> Leyenda: [V] verificado (código/ejecución/simulación), [I] inferido, [?] hipótesis.

## Tabla de hallazgos

| # | Sev. | Dónde | Hallazgo | Estado |
|---|---|---|---|---|
| 1 | **Alto** | `xrce_transport.cpp:352-377` | Cola BE: **un mensaje por `poll()`** ⇒ techo de FPS mensajes/s BE para *todos* los topics juntos (60/s en PC, 30/s si la Vita cae a 30 FPS). Es la causa de los `be_dropped` de G1 y dron. | [V] |
| 2 | **Alto** | `xrce_transport.cpp:354-356` | Lo preparado en `poll()` se escribe **después** de `uxr_run_session_time` ⇒ sale en el `poll()` siguiente: +1 fotograma fijo, +k fotogramas con k en cola (hasta 64 ⇒ ~1,1 s a 60 FPS, ~2,1 s a 30 FPS). Malo para teleop/TF. | [V] |
| 3 | **Alto** | `godot/plantillas/ros/sensor_base.gd:55-57` (fuera del .cpp, pero explica doc 30 §6) | `fmod` con tolerancia `+0.00001`: cuando el acumulado queda 1e-17 por debajo del periodo, publica pero `fmod` no lo reduce y vuelve a publicar en el siguiente tick ⇒ **2, 5 y 10 Hz se publican al doble**, 25 y 50 Hz a ×1,2. Duplica la carga BE justo en los perfiles XRCE. | [V] simulado |
| 4 | Medio | `xrce_transport.cpp:379-404` | Cola fiable también a **uno por `poll()`** aunque el stream tenga 16 huecos libres; con >FPS msg/s fiables descarta. | [V] |
| 5 | Medio | `xrce_transport.cpp:406-410` | Descarte silencioso del más antiguo en la cola **fiable**: `publish()` devuelve `OK` y el mensaje RELIABLE (o KEEP_ALL) se pierde sin error; antes daba `ERR_BUSY`. | [V] |
| 6 | Medio | `xrce_transport.cpp:397-403` (y `_flush` :260) | Mensaje fragmentado: se hace `pop_front()` antes de serializar y no se mira el `bool` de `ucdr_serialize_array_uint8_t`. Si `_flush` (`uxr_run_session_time(10)`) devuelve `false` porque no todo está confirmado en 10 ms (RTT WiFi), `on_full_output_buffer_fragmented` devuelve error y el mensaje queda truncado en el stream y perdido sin contador. Preexistente, pero la cola lo hereda. | [V] código uxr / [I] en WiFi |
| 7 | Medio | `xrce_transport.cpp:411-416, 424-429` | Memoria: 2 `malloc` + 2 `free` por publicación (nodo de `List` + `CowData` del `PackedByteArray`); antes 0. Cola fiable sin tope de **bytes**: 32 × RGB crudo 230 KB ≈ 7,4 MB. | [V] / [I] fragmentación en Vita |
| 8 | Bajo | `xrce_transport.cpp:366-368` | Al descartar por endpoint inexistente no se actualiza `g_diag.be_pending` (el fiable sí, :387). | [V] |
| 9 | Bajo | `xrce_transport.cpp:53, 394, 398` | `reliable_full` cambia de semántica: ahora cuenta **reintentos por fotograma**, no mensajes (un mensaje atascado 1 s suma 60). Doc 30 lo interpreta como señal de saturación sin decirlo. | [V] |
| 10 | Bajo | `godot/test/project/runner.gd:160` | Las 294 pruebas usan solo `transport:=loopback`: **ninguna cubre las colas XRCE** (ni capacidad, ni descarte, ni orden, ni `stop()`). La afirmación «294/0» no valida el cambio. | [V] ejecutado |
| 11 | Bajo | `xrce_transport.cpp:497-510` | Sin mutex en las colas: igual que antes con la sesión (todo en hilo principal), pero un `publish()` desde un `Thread` de GDScript ahora corrompe una `List` en vez de solo la sesión. Documentar «solo hilo principal». | [I] |

Lo que está bien [V]: copia profunda de los datos (`memcpy` a `PackedByteArray` propio, vida independiente del
llamador); FIFO por cola; descarte del más antiguo con contador; `stop()` vacía ambas colas y pone a cero
`*_pending` (:346-349); `g_diag = XrceDiag()` en `start()` reinicia contadores; no hay mezcla de streams (BE solo
va a `best_effort_out`, fiable solo a `reliable_out`; se eliminó el desvío fiable→BE); los ids de publicador no se
reutilizan (`next_id` no se reinicia) así que una entrada huérfana nunca va a otro writer; HEARTBEAT/ACKNACK
siguen saliendo porque `uxr_run_session_time` llama a `uxr_flash_output_streams` y procesa ACKNACK en cada
`poll()` (`session.c:321-339`); sin TLS ni hilos nuevos.

## Detalle

### 1. Techo de throughput BE (alto) [V]

`_publish_pending()` saca exactamente un elemento por `poll()`, y `poll()` se llama una vez por fotograma desde
`rclgd::_pump` en `process_frame` (`ros_runtime.cpp:478-485`). Por tanto el caudal BE máximo es FPS msg/s
sumando todos los topics BE, con independencia de su tamaño (un `Imu` de 300 B ocupa un datagrama entero de
la ventana). Si la suma de frecuencias BE supera los FPS, la cola crece hasta 64 y empieza `be_dropped`. Eso
cuadra con doc 30 §6 (G1 335 y dron 273 descartes en 10 s tras el presupuesto) y con el hallazgo 3, que
duplica la carga.

El motivo original (doc 30 §4.2: «evita el `ERR_BUSY` al publicar varios sensores en el mismo fotograma») es
real: el stream BE tiene un único buffer de 512 B (`output_best_effort_stream.c:34-51`) que se vacía solo al
llamar a `uxr_flash_output_streams`/`uxr_run_session*`. Pero la solución correcta no es limitar a uno por
fotograma sino **vaciar el buffer y reintentar**, que es no bloqueante (`sendto` UDP):

```cpp
// publish(), rama best effort (sin cola):
ucdrBuffer ub;
if (uxr_prepare_output_stream(&session, best_effort_out, ep->entity, &ub, (uint32_t)p_len) == UXR_INVALID_REQUEST_ID) {
	uxr_flash_output_streams(&session); // envía el datagrama BE acumulado (y lo fiable sin enviar)
	if (uxr_prepare_output_stream(&session, best_effort_out, ep->entity, &ub, (uint32_t)p_len) == UXR_INVALID_REQUEST_ID) {
		g_diag.be_dropped++;
		return ERR_BUSY;
	}
}
ucdr_serialize_array_uint8_t(&ub, p_data, p_len);
```

Así varios mensajes pequeños se empaquetan en un datagrama de 512 B, no hay copias ni `malloc`, y la latencia
vuelve a ser la de antes. Si se quiere un presupuesto por fotograma (para no saturar la WiFi de la Vita), que sea
en **bytes/datagramas por `poll()`** con un bucle de drenaje, no en «1 mensaje».

### 2. Latencia añadida (alto) [V]

Orden en `poll()` (:352-357): primero `uxr_run_session_time(&session, 0)` (envía lo que haya), después
`_publish_pending()` / `_publish_reliable_pending()` (prepara). Lo preparado en el fotograma N sale en el
`run_session` del N+1. Mínimo +16,7 ms a 60 FPS (+33 ms a 30 FPS en la Vita) sobre el diseño anterior, más un
fotograma por cada mensaje que tenga delante en la cola. Arreglo: drenar las colas **antes** de
`uxr_run_session_time`, o llamar a `uxr_flash_output_streams` tras drenar.

### 3. Doble publicación por `fmod` (alto; causa probable de doc 30 §6) [V]

`sensor_base.gd:53-57`:

```gdscript
_acumulado += dt
var periodo := 1.0 / hz
if _acumulado + 0.00001 < periodo:
	return
_acumulado = fmod(_acumulado, periodo)
```

Con `dt = 1/60` y `periodo = 0.2` (5 Hz), 12 sumas dan 0.19999999999999998 (< 0.2). La tolerancia deja publicar,
pero `fmod(0.19999…, 0.2)` devuelve 0.19999…, no 0; en el tick siguiente `_acumulado ≈ 0.2167` y se publica
otra vez. Simulación con `double` (GDScript `float` es `double`) en 600 ticks (10 s):

| hz | publicados | esperado |
|---:|---:|---:|
| 1 | 10 | 10 |
| 2 | **39** | 20 |
| 5 | **99** | 50 |
| 10 | **199** | 100 |
| 15 | 150 | 150 |
| 20 | 200 | 200 |
| 25 | **299** | 250 |
| 30 | 300 | 300 |
| 50 | **599** | 500 |

Justamente los perfiles XRCE (2, 5, 10 Hz: doc 30 §4.1) salen al doble ⇒ los conteos de la sonda superan la
frecuencia nominal (doc 30 §6) y la carga BE real es casi el doble de la presupuestada. Arreglo:

```gdscript
_acumulado += dt
if _acumulado + 0.00001 < periodo:
	return
_acumulado = maxf(0.0, _acumulado - periodo) # o: restar y, si sigue >= periodo, poner a 0 (no ráfagas)
```

(`mapeo_2d.gd:68` usa otro esquema sin `fmod`; revisar igualmente.) Doc 30 §8.1–8.2 sospechaba de la
acumulación de `dt`; la causa concreta es esta.

### 4. Cola fiable a uno por `poll()` (medio) [V]

`_publish_reliable_pending()` también saca uno por fotograma aunque `uxr_prepare_reliable_buffer_to_write`
(`output_reliable_stream.c:54-99`) admitiría varios en los 16 huecos. Doc 30 §6 mide 377–685 descartes
fiables antes del presupuesto. Arreglo: bucle `while (!reliable_pending.is_empty())` que se detiene en el primer
`UXR_INVALID_REQUEST_ID` (stream lleno), con tope de fragmentados por fotograma para no encadenar `_flush`.
Mejor aún: escribir directo en el stream en `publish()` y encolar solo si está lleno.

### 5. Descarte silencioso de fiables (medio) [V]

`_enqueue_reliable` (:406-410) tira el más antiguo y `publish()` devuelve `OK` (:508-509). Un publicador con
QoS RELIABLE/KEEP_ALL pierde datos sin aviso; antes había `ERR_BUSY`/`reliable_full`. Proponer: devolver
`ERR_BUSY` (o descartar el **nuevo**) cuando la cola fiable está llena, y documentar en `API_PARITY.md` que la
fiabilidad es KEEP_LAST(32) solo en el tramo Vita↔agente.

### 6. Fragmentado truncado sin contador (medio, preexistente) [V]/[I]

`uxr_prepare_output_stream_fragmented` solo reserva el primer bloque; el resto lo pide
`on_full_output_buffer_fragmented` (`write_access.c:148-203`) durante la serialización, llamando a `_flush`. Si
`_flush` devuelve `false` — `uxr_run_session_time` devuelve «todos los streams confirmados» (`session.c:335`), y
con 10 ms de espera sobre WiFi lo normal es que no — el callback devuelve `true` (error) y la serialización
termina a medias. El código ignora el retorno (:403) y ya hizo `pop_front()` (:401): mensaje perdido sin
contador y fragmentos sin `FLAG_LAST_FRAGMENT` en el stream. Arreglo: `_flush` que devuelva
`uxr_run_session_time(...) || hay huecos libres` (o usar `uxr_run_session_until_confirm_delivery` con tope), y
contar el fallo de `ucdr_serialize_array_uint8_t`. Además, cada mensaje grande sigue bloqueando el hilo
principal ~10 ms por cada 16 fragmentos (la causa de los 1–3 FPS de doc 30 §3): la cola no lo evita.

### 7. Memoria (medio) [V]/[I]

Por publicación: un nodo de `List` y un bloque `CowData`; `Pending p = front()->get()` (:364, :383) solo sube el
contador de referencias (sin `malloc`). En la Vita (newlib, montón compartido con Godot) a decenas de msg/s
favorece la fragmentación [I]. La cola fiable admite mensajes de cualquier tamaño: 32 imágenes crudas ≈ 7,4 MB.
Arreglo: con el hallazgo 1 la cola BE desaparece; para la fiable, anillo preasignado o tope en bytes.

### 8–11 (bajos)

- :366-368 no actualiza `be_pending` tras `pop_front()`.
- `reliable_full` pasa a contar reintentos; renombrar o contar solo la primera vez por mensaje.
- Las pruebas de host (ejecutadas: `godot/test/run_host_tests.sh toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64`
  ⇒ «294 comprobaciones, 0 fallos») no tocan XRCE (`runner.gd:160` fija loopback). Proponer una prueba con el
  agente de `docker/` (opcional, saltada si no hay agente) que publique 200 BE pequeños en un fotograma y compruebe
  `be_dropped == 0` y recepción con `ros2 topic echo`/suscripción propia, y otra de `stop()` con colas llenas.
- Colas sin mutex: documentar que `publish()` es solo del hilo principal.

## Respuestas a las preguntas del encargo

1. **Colas**: copia y vida correctas, FIFO, descarte con contador, `stop()` limpio, sin mezcla de streams. Fallos:
   throughput (1, 4), descarte silencioso de fiables (5), `malloc` por mensaje y sin tope de bytes (7).
2. **Semántica**: sí, limita a FPS msg/s por cola y añade ≥1 fotograma de latencia. No rompe la fragmentación más
   de lo que ya estaba (6), ni HEARTBEAT/ACKNACK.
3. **Docs/pruebas**: doc 30 y `API_PARITY.md` describen fielmente el código, pero presentan el «uno por `poll()`»
   como solución sin decir que es un techo de caudal; las pruebas no cubren las colas.
4. **Conteos > frecuencia nominal**: bug de `fmod` + tolerancia en `sensor_base.gd:55-57` (hallazgo 3).
