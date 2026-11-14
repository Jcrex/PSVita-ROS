#!/usr/bin/env node
// gen-ui-header.mjs — codegen de la UI declarativa: ui/layout.json -> src/ui_layout.h
//
// Uso: node scripts/gen-ui-header.mjs [layout.json] [salida.h]
//      (por defecto los del propio vita-app/)
//
// Es la ÚNICA implementación del codegen: el endpoint web /api/taller/ui/aplicar
// invoca este script (el server es node), y también funciona a mano sin la web.
// La validación se duplica a propósito en web/src/lib/ui-layout.ts (el editor
// valida antes de guardar) — si cambian los límites, cambiar AMBOS.
//
// Sin dependencias externas (node >= 18).
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const APP_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ENTRADA = resolve(process.argv[2] ?? resolve(APP_DIR, 'ui/layout.json'));
const SALIDA = resolve(process.argv[3] ?? resolve(APP_DIR, 'src/ui_layout.h'));

// Límites duros (espejo de web/src/lib/ui-layout.ts y ui_types.h).
const LIM = {
  maxWidgets: 32,
  pantallaW: 960,
  pantallaH: 544,
  maxTexto: 63, // ui_types.h reserva 64 con NUL
  escalaMin: 0.5,
  escalaMax: 3.0,
};
const TIPOS = { panel: 'UI_W_PANEL', label: 'UI_W_LABEL', valor: 'UI_W_VALOR' };
const BINDINGS = {
  estado_conexion: 'UI_B_ESTADO_CONEXION',
  contador_publicados: 'UI_B_CONTADOR_PUBLICADOS',
  ultimo_pc_hello: 'UI_B_ULTIMO_PC_HELLO',
  agente: 'UI_B_AGENTE',
  vel_lineal: 'UI_B_VEL_LINEAL',
  vel_lateral: 'UI_B_VEL_LATERAL',
  cmd_vel: 'UI_B_CMD_VEL',
  contador_cmd: 'UI_B_CONTADOR_CMD',
};
const COLOR_RE = /^#[0-9a-fA-F]{6}$/;
// Solo ASCII imprimible: el texto acaba en un literal C y en la fuente PGF.
const TEXTO_RE = /^[\x20-\x7e]+$/;

function fallar(msg) {
  console.error(`[gen-ui-header] ERROR: ${msg}`);
  process.exit(1);
}

function entero(v, min, max, campo, i) {
  if (!Number.isInteger(v) || v < min || v > max) {
    fallar(`widget #${i}: ${campo}=${JSON.stringify(v)} fuera de rango [${min}, ${max}]`);
  }
  return v;
}

// "#rrggbb" -> literal uint32 con el empaquetado RGBA8 de vita2d:
// r | g<<8 | b<<16 | a<<24 (alfa fijo 0xff). Ver ui_types.h.
function colorC(hex, campo, i) {
  if (typeof hex !== 'string' || !COLOR_RE.test(hex)) {
    fallar(`widget #${i}: ${campo}=${JSON.stringify(hex)} no es "#rrggbb"`);
  }
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  const v = ((0xff << 24) | (b << 16) | (g << 8) | r) >>> 0;
  return `0x${v.toString(16).padStart(8, '0')}u`;
}

function textoC(s, i) {
  if (typeof s !== 'string' || s.length < 1 || s.length > LIM.maxTexto || !TEXTO_RE.test(s)) {
    fallar(`widget #${i}: texto inválido (1..${LIM.maxTexto} chars ASCII imprimibles)`);
  }
  return `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

let layout;
try {
  layout = JSON.parse(readFileSync(ENTRADA, 'utf8'));
} catch (e) {
  fallar(`no se pudo leer/parsear ${ENTRADA}: ${e.message}`);
}
if (layout.version !== 1) fallar(`version=${layout.version} no soportada (esperaba 1)`);
if (!Array.isArray(layout.widgets) || layout.widgets.length < 1 || layout.widgets.length > LIM.maxWidgets) {
  fallar(`widgets debe ser un array de 1..${LIM.maxWidgets}`);
}

const filas = layout.widgets.map((w, i) => {
  const tipo = TIPOS[w.tipo];
  if (!tipo) fallar(`widget #${i}: tipo=${JSON.stringify(w.tipo)} (válidos: panel|label|valor)`);
  const x = entero(w.x, 0, LIM.pantallaW - 1, 'x', i);
  const y = entero(w.y, 0, LIM.pantallaH - 1, 'y', i);
  let ancho = 0, alto = 0, borde = '0x00000000u', escala = 1.0;
  let binding = 'UI_B_NONE', texto = '""';
  const color = colorC(w.color, 'color', i);
  if (w.tipo === 'panel') {
    ancho = entero(w.w, 1, LIM.pantallaW, 'w', i);
    alto = entero(w.h, 1, LIM.pantallaH, 'h', i);
    if (x + ancho > LIM.pantallaW || y + alto > LIM.pantallaH) {
      fallar(`widget #${i}: el panel se sale de la pantalla ${LIM.pantallaW}x${LIM.pantallaH}`);
    }
    if (w.borde !== undefined) borde = colorC(w.borde, 'borde', i);
  } else {
    const e = w.escala ?? 1.0;
    if (typeof e !== 'number' || e < LIM.escalaMin || e > LIM.escalaMax) {
      fallar(`widget #${i}: escala=${JSON.stringify(e)} fuera de [${LIM.escalaMin}, ${LIM.escalaMax}]`);
    }
    escala = e;
    if (w.tipo === 'label') {
      texto = textoC(w.texto, i);
    } else {
      binding = BINDINGS[w.binding];
      if (!binding) {
        fallar(`widget #${i}: binding=${JSON.stringify(w.binding)} (válidos: ${Object.keys(BINDINGS).join('|')})`);
      }
    }
  }
  return `    { ${tipo}, ${x}, ${y}, ${ancho}, ${alto}, ${color}, ${borde}, ${escala.toFixed(2)}f, ${binding}, ${texto} },`;
});

const header = `/**
 * ui_layout.h — GENERADO por scripts/gen-ui-header.mjs a partir de
 * ui/layout.json. NO EDITAR A MANO: editar el JSON (o desde la web en
 * /taller/ui) y regenerar. Verificación en host: scripts/check-ui-layout.sh.
 */
#ifndef VITA_UI_LAYOUT_H
#define VITA_UI_LAYOUT_H

#include "ui_types.h"

#define UI_FONDO ${colorC(layout.fondo ?? '#000000', 'fondo', -1)}

static const ui_widget UI_WIDGETS[] = {
${filas.join('\n')}
};

#define UI_NUM_WIDGETS (sizeof UI_WIDGETS / sizeof UI_WIDGETS[0])

#endif /* VITA_UI_LAYOUT_H */
`;

writeFileSync(SALIDA, header);
console.log(`[gen-ui-header] OK: ${layout.widgets.length} widgets -> ${SALIDA}`);
