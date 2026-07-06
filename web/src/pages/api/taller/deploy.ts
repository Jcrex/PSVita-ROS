// /api/taller/deploy — envía el .vpk a la Vita por FTP (modo FTP de
// VitaShell, mismo flujo que docs/06: curl -T … ftp://<vita>:1337/ux0:/).
// La instalación final sigue siendo manual en VitaShell (por diseño).
//
// POST { variante: 'c'|'rust', ip } -> { id } (job SSE)
import type { APIRoute } from 'astro';
import { existsSync } from 'node:fs';
import { cerrarBuildJob, crearBuildJob } from '../../../lib/db';
import { IP_RE, rutaVpk, taller, tallerActivo, VARIANTES, type Variante } from '../../../lib/taller';

export const prerender = false;

export const POST: APIRoute = async ({ request }) => {
  if (!tallerActivo()) {
    return new Response(JSON.stringify({ error: 'Taller desactivado (TALLER_ENABLED != 1)' }), { status: 403 });
  }
  let body: { variante?: string; ip?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), { status: 400 });
  }
  const variante = body.variante as Variante;
  if (!VARIANTES.includes(variante)) {
    return new Response(JSON.stringify({ error: 'variante inválida' }), { status: 400 });
  }
  if (!body.ip || !IP_RE.test(body.ip)) {
    return new Response(JSON.stringify({ error: 'IP de la Vita inválida' }), { status: 400 });
  }
  if (!existsSync(rutaVpk(variante))) {
    return new Response(JSON.stringify({ error: `No existe el .vpk de la variante ${variante}: compílalo primero` }), {
      status: 404,
    });
  }

  const script = `
set -eo pipefail
echo "[taller] subiendo vita-app/build-${variante}/vita-ros2-hello.vpk a ftp://${body.ip}:1337/ux0:/"
echo "[taller] (la Vita debe estar en VitaShell con el modo FTP activado — SELECT)"
curl --connect-timeout 8 -T "vita-app/build-${variante}/vita-ros2-hello.vpk" "ftp://${body.ip}:1337/ux0:/"
echo "[taller] subido. En la Vita: VitaShell -> ux0:/vita-ros2-hello.vpk -> instalar"
`;

  try {
    const dbId = crearBuildJob(`deploy-${variante}`);
    const job = taller.lanzar('deploy', `Deploy FTP (${variante}) → ${body.ip}`, script, {}, (j) => {
      cerrarBuildJob(dbId, j.estado === 'ok' ? 'ok' : 'error', j.exitCode,
        (j.lineas.filter(Boolean).slice(-1)[0] ?? '').slice(0, 300));
    });
    return new Response(JSON.stringify({ id: job.id }), {
      headers: { 'content-type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { status: 409 });
  }
};
