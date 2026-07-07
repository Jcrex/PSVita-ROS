// ui-layout.ts — schema y validación del layout de UI de la app Vita.
//
// Es el contrato del editor /taller/ui: lo usan el borrador (POST a SQLite)
// y "aplicar" (escritura a vita-app/ui/layout.json). Los límites son un
// ESPEJO CONSCIENTE de vita-app/scripts/gen-ui-header.mjs (el codegen debe
// funcionar sin la web, así que re-valida por su cuenta): si cambian aquí,
// cambiar también allí (y ui_types.h si cambia el charset o maxTexto).

export const UI_PANTALLA_W = 960;
export const UI_PANTALLA_H = 544;

export const UI_LIM = {
  maxWidgets: 32,
  maxTexto: 63,
  escalaMin: 0.5,
  escalaMax: 3.0,
} as const;

export const UI_TIPOS = ['panel', 'label', 'valor'] as const;
export type UiTipo = (typeof UI_TIPOS)[number];

// Enum cerrado, espejo de ui_binding en vita-app/src/ui_types.h.
export const UI_BINDINGS = [
  'estado_conexion',
  'contador_publicados',
  'ultimo_pc_hello',
  'agente',
] as const;
export type UiBinding = (typeof UI_BINDINGS)[number];

export interface UiWidget {
  tipo: UiTipo;
  x: number;
  y: number;
  w?: number; // solo panel
  h?: number; // solo panel
  color: string; // "#rrggbb"
  borde?: string; // solo panel, opcional
  escala?: number; // solo label/valor (por defecto 1.0)
  texto?: string; // solo label
  binding?: UiBinding; // solo valor
}

export interface UiLayout {
  version: 1;
  fondo: string;
  widgets: UiWidget[];
}

const COLOR_RE = /^#[0-9a-fA-F]{6}$/;
// Solo ASCII imprimible: el texto acaba en un literal C y en la fuente PGF.
const TEXTO_RE = /^[\x20-\x7e]+$/;

type Resultado = { ok: true; layout: UiLayout } | { ok: false; error: string };

function esEntero(v: unknown, min: number, max: number): v is number {
  return typeof v === 'number' && Number.isInteger(v) && v >= min && v <= max;
}

/** Valida un layout arbitrario (body de un POST). Devuelve el layout ya
 * "limpio" (solo los campos del schema, sin extras del cliente). */
export function validarLayout(entrada: unknown): Resultado {
  const mal = (error: string): Resultado => ({ ok: false, error });
  if (typeof entrada !== 'object' || entrada === null) return mal('el layout no es un objeto');
  const raiz = entrada as Record<string, unknown>;
  if (raiz.version !== 1) return mal('version debe ser 1');
  if (typeof raiz.fondo !== 'string' || !COLOR_RE.test(raiz.fondo)) {
    return mal('fondo debe ser "#rrggbb"');
  }
  if (!Array.isArray(raiz.widgets) || raiz.widgets.length < 1 || raiz.widgets.length > UI_LIM.maxWidgets) {
    return mal(`widgets debe ser un array de 1..${UI_LIM.maxWidgets}`);
  }

  const widgets: UiWidget[] = [];
  for (const [i, cual] of raiz.widgets.entries()) {
    const w = cual as Record<string, unknown>;
    const err = (m: string) => mal(`widget #${i}: ${m}`);
    if (!UI_TIPOS.includes(w.tipo as UiTipo)) return err('tipo debe ser panel|label|valor');
    if (!esEntero(w.x, 0, UI_PANTALLA_W - 1)) return err('x fuera de rango');
    if (!esEntero(w.y, 0, UI_PANTALLA_H - 1)) return err('y fuera de rango');
    if (typeof w.color !== 'string' || !COLOR_RE.test(w.color)) return err('color debe ser "#rrggbb"');

    const limpio: UiWidget = { tipo: w.tipo as UiTipo, x: w.x, y: w.y, color: w.color };
    if (limpio.tipo === 'panel') {
      if (!esEntero(w.w, 1, UI_PANTALLA_W) || !esEntero(w.h, 1, UI_PANTALLA_H)) {
        return err('panel necesita w y h en rango');
      }
      if (limpio.x + w.w > UI_PANTALLA_W || limpio.y + w.h > UI_PANTALLA_H) {
        return err(`el panel se sale de la pantalla ${UI_PANTALLA_W}x${UI_PANTALLA_H}`);
      }
      limpio.w = w.w;
      limpio.h = w.h;
      if (w.borde !== undefined) {
        if (typeof w.borde !== 'string' || !COLOR_RE.test(w.borde)) return err('borde debe ser "#rrggbb"');
        limpio.borde = w.borde;
      }
    } else {
      const escala = w.escala ?? 1.0;
      if (typeof escala !== 'number' || escala < UI_LIM.escalaMin || escala > UI_LIM.escalaMax) {
        return err(`escala fuera de [${UI_LIM.escalaMin}, ${UI_LIM.escalaMax}]`);
      }
      limpio.escala = escala;
      if (limpio.tipo === 'label') {
        if (
          typeof w.texto !== 'string' ||
          w.texto.length < 1 ||
          w.texto.length > UI_LIM.maxTexto ||
          !TEXTO_RE.test(w.texto)
        ) {
          return err(`texto debe ser 1..${UI_LIM.maxTexto} chars ASCII imprimibles`);
        }
        limpio.texto = w.texto;
      } else {
        if (!UI_BINDINGS.includes(w.binding as UiBinding)) {
          return err(`binding debe ser uno de: ${UI_BINDINGS.join('|')}`);
        }
        limpio.binding = w.binding as UiBinding;
      }
    }
    widgets.push(limpio);
  }
  return { ok: true, layout: { version: 1, fondo: raiz.fondo, widgets } };
}
