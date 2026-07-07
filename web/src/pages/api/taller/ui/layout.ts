// /api/taller/ui/layout — GET: el layout de UI actual del repo
// (vita-app/ui/layout.json), para "Cargar el del repo" en /taller/ui.
//
// Solo lectura, así que NO exige TALLER_ENABLED: en un despliegue público
// muestra la UI que trae la app tal cual está commiteada.
import type { APIRoute } from 'astro';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { REPO_ROOT } from '../../../../lib/taller';
import { validarLayout } from '../../../../lib/ui-layout';

export const prerender = false;

export const GET: APIRoute = () => {
  try {
    const crudo = readFileSync(resolve(REPO_ROOT, 'vita-app/ui/layout.json'), 'utf8');
    const res = validarLayout(JSON.parse(crudo));
    if (!res.ok) {
      return new Response(JSON.stringify({ error: `layout.json del repo inválido: ${res.error}` }), { status: 500 });
    }
    return new Response(JSON.stringify({ layout: res.layout }), {
      headers: { 'content-type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: `no se pudo leer vita-app/ui/layout.json: ${(e as Error).message}` }), {
      status: 500,
    });
  }
};
