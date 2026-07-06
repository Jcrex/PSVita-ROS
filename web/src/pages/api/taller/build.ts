// /api/taller/build — lanza el build real del .vpk en el PC (Opción 1 de
// docs/07 §5): source tools/env-devpc.sh + cmake + empaquetado, exactamente
// el flujo manual de docs/06, disparado por endpoint.
//
// POST { variante: 'c'|'rust', agentIp?, netlogIp? } -> { id } (job SSE)
import type { APIRoute } from 'astro';
import { cerrarBuildJob, crearBuildJob } from '../../../lib/db';
import { IP_RE, taller, tallerActivo, VARIANTES, type Variante } from '../../../lib/taller';

export const prerender = false;

export const POST: APIRoute = async ({ request }) => {
  if (!tallerActivo()) {
    return new Response(JSON.stringify({ error: 'Taller desactivado (TALLER_ENABLED != 1)' }), { status: 403 });
  }
  let body: { variante?: string; agentIp?: string; netlogIp?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), { status: 400 });
  }
  const variante = body.variante as Variante;
  if (!VARIANTES.includes(variante)) {
    return new Response(JSON.stringify({ error: 'variante inválida (c | rust)' }), { status: 400 });
  }
  // IPs opcionales (baked-in en el .vpk): solo formato IPv4 estricto.
  const flags: string[] = [];
  for (const [clave, valor] of [
    ['AGENT_IP', body.agentIp],
    ['NETLOG_IP', body.netlogIp],
  ] as const) {
    if (valor === undefined || valor === '') continue;
    if (!IP_RE.test(valor)) {
      return new Response(JSON.stringify({ error: `${clave} no es una IPv4 válida` }), { status: 400 });
    }
    flags.push(`-D${clave}=${valor}`);
  }

  // Script construido SOLO con valores de allowlist/regex (ver taller.ts).
  const script = `
set -eo pipefail
echo "[taller] cargando entorno VitaSDK (tools/env-devpc.sh)"
source tools/env-devpc.sh
cd vita-app
echo "[taller] configurando variante ${variante}"
cmake -DCMAKE_TOOLCHAIN_FILE="$VITASDK/share/vita.toolchain.cmake" \\
      -DVITA_IMPL=${variante} ${flags.join(' ')} -B build-${variante}
echo "[taller] compilando"
cmake --build build-${variante}
echo "[taller] listo: vita-app/build-${variante}/vita-ros2-hello.vpk"
`;

  try {
    const dbId = crearBuildJob(`build-${variante}`);
    const job = taller.lanzar('build', `Build .vpk (${variante})`, script, {}, (j) => {
      const resumen = j.lineas.filter(Boolean).slice(-1)[0] ?? '';
      cerrarBuildJob(dbId, j.estado === 'ok' ? 'ok' : 'error', j.exitCode, resumen.slice(0, 300));
    });
    return new Response(JSON.stringify({ id: job.id }), {
      headers: { 'content-type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { status: 409 });
  }
};
