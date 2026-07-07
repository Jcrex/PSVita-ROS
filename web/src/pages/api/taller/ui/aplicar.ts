// /api/taller/ui/aplicar — escribe el layout del editor AL REPO y lo
// verifica: vita-app/ui/layout.json + regeneración de ui_layout.h + check de
// compilación en host (scripts/check-ui-layout.sh), con la salida como job
// del taller (SSE, misma consola que compilar).
//
// POST { layout: UiLayout } -> { id } (job)  |  403 sin TALLER_ENABLED=1
// (escribe archivos del repo y ejecuta procesos: solo PC de desarrollo).
import type { APIRoute } from 'astro';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { REPO_ROOT, taller, tallerActivo } from '../../../../lib/taller';
import { validarLayout } from '../../../../lib/ui-layout';

export const prerender = false;

export const POST: APIRoute = async ({ request }) => {
  if (!tallerActivo()) {
    return new Response(JSON.stringify({ error: 'Taller desactivado (TALLER_ENABLED != 1)' }), { status: 403 });
  }
  let body: { layout?: unknown };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), { status: 400 });
  }
  const res = validarLayout(body.layout);
  if (!res.ok) return new Response(JSON.stringify({ error: res.error }), { status: 400 });

  // El JSON validado se escribe aquí (datos, no script); el job solo corre
  // rutas fijas del repo (regla de taller.ts: nada libre en el script).
  try {
    writeFileSync(
      resolve(REPO_ROOT, 'vita-app/ui/layout.json'),
      JSON.stringify(res.layout, null, 2) + '\n',
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: `no se pudo escribir layout.json: ${(e as Error).message}` }), {
      status: 500,
    });
  }

  const script = `
set -eo pipefail
echo "[taller] layout.json actualizado (${res.layout.widgets.length} widgets)"
echo "[taller] regenerando ui_layout.h y verificando en host"
vita-app/scripts/check-ui-layout.sh
echo "[taller] listo: recompila el .vpk para llevarlo a la Vita"
`;
  try {
    const job = taller.lanzar('ui-aplicar', 'Aplicar UI al proyecto', script);
    return new Response(JSON.stringify({ id: job.id }), {
      headers: { 'content-type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { status: 409 });
  }
};
