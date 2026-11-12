# ADR 0010: DB-TSDF en la Vita como módulo dual con escalera de variantes V32/V16/V8/V4 intercambiables en caliente

- **Estado:** Aceptado como diseño el 2026-11-12. **Por medir** en hardware (puertas T0–T5 y M1–M9 del doc 26).
  Diseño de Fable 5.2 (workshop W3) con cortes por límites de uso, integrado por el orquestador. El juicio
  independiente de otro modelo sigue pendiente.
- **Fecha:** 2026-11-12

## Contexto

La Fase 3 pide mapeo DB-TSDF reducido en la Vita (arXiv 2509.20081, `robotics-upo/DB-TSDF`), con variantes de
«bits» que conviven y se cambian desde la app. Hechos (doc 26, `docs/ia/auditoria/04a`):

- El paper describe una máscara de 32 bits con un vóxel de 8 B y kernel 21³ (rama `legacy`/`db_tsdf_32`).
- La rama por defecto del código es `db_tsdf_16`: vóxel de 4 B y kernels de 5–7.
- La distancia se codifica como un número de bits a 1 (termómetro) y se integra con un AND.
- En la Vita hay un núcleo efectivo para Godot (W1), XRCE limita la entrada a ≈ 4–15 k puntos/s (W2/doc 27) y la
  regla del repo es un header C + dos implementaciones (C y Rust) con paridad.

## Decisión

1. **«Bits» = ancho `W` de la máscara de distancia.** Fija el alcance de truncamiento y el kernel máximo útil. El
   contador y el empaquetado son consecuencias de formato.
2. **Escalera V32 → V16 → V8 → V4.** El vóxel es una sola palabra de `W/4` bytes (8 / 4 / 2 / 1 B): máscara más
   contador de impactos (8 bits; 4 en V4). Se elimina el bit de signo, que el contador ya implica. Kernel canónico
   K = 21 / 7 / 5 / 3 (L1). No hay contradicción con el paper: V32 es el paper, V16 el código publicado, y el
   proyecto sigue la misma reducción.
3. **Un único módulo dual `modules/db-tsdf/`** con todas las variantes compiladas:
   - handle opaco y memoria aportada por el llamador, sin hilos internos;
   - cambio en caliente con `dbtsdf_plan()` (qué pasaría) y `dbtsdf_reconfigure()` (hacerlo);
   - un informe dice si el mapa se conserva, se convierte (exacto o con pérdida) o se reinicia, y una `epoch` avisa
     a la UI.
4. **Oráculo** = implementación original en docker. La paridad es bit a bit, así que la calidad (F-score/Chamfer) se
   mide en el PC; en la Vita solo se miden tiempo, FPS, latencia y memoria.
5. **Orden de implementación:**
   - primero, LaserScan 2D (losa de un vóxel de alto) en el hilo principal con presupuesto de ms;
   - después, nube 3D decimada por el relay;
   - un hilo propio solo tras medir (CapUnlocker libera USER_1/USER_2, revisión de la oleada 1).

## Alternativas descartadas

- **«Bits» como cuantización del contador o empaquetado de varios vóxeles por palabra:** no cambia el algoritmo ni
  el alcance. Queda como detalle de formato por peldaño.
- **Un módulo por variante:** duplica código y paridad, e impide el cambio en caliente con conversión.
- **Mapear en la Vita con la nube cruda:** no cabe por XRCE (doc 27) y no corre en un núcleo.

## Consecuencias

- **Sin medir, la escalera probablemente no cambia los FPS:** con K ≤ 7 y la entrada limitada por XRCE, el coste de
  integrar es pequeño en cualquier variante [I, a refutar en T3]. Si T3 lo confirma, la escalera sirve para elegir
  memoria (×2 por peldaño) y alcance del campo de distancia.
- El relay ganará un módulo `tsdf` (nube reducida y troceada).
- La envoltura de Godot (`DbTsdfMap`) va en un módulo en árbol aparte de `ros2_vita`; queda abierto hasta W10.
