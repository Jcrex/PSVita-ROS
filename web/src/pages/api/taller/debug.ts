// /api/taller/debug — depuración en host de los módulos duales (docs/07 §6,
// parte host): compila el parity test con tools/run-parity-tests.sh (los
// binarios salen con -g) y corre gdb en modo batch sobre él.
//
// POST { modulo, impl: 'c'|'rust', gdbScript } -> { id } (job SSE)
//
// El guion de gdb viaja por variable de entorno (nunca interpolado en el
// script bash). Nota de alcance: el taller entero es una herramienta de
// desarrollo local tras TALLER_ENABLED — gdb ejecuta lo que le pidas,
// igual que la terminal del PC.
import type { APIRoute } from 'astro';
import { cerrarBuildJob, crearBuildJob } from '../../../lib/db';
import { MODULOS, taller, tallerActivo, VARIANTES } from '../../../lib/taller';

export const prerender = false;

export const POST: APIRoute = async ({ request }) => {
  if (!tallerActivo()) {
    return new Response(JSON.stringify({ error: 'Taller desactivado (TALLER_ENABLED != 1)' }), { status: 403 });
  }
  let body: { modulo?: string; impl?: string; gdbScript?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), { status: 400 });
  }
  const { modulo, impl } = body;
  if (!MODULOS.includes(modulo as (typeof MODULOS)[number])) {
    return new Response(JSON.stringify({ error: 'módulo inválido' }), { status: 400 });
  }
  if (!VARIANTES.includes(impl as (typeof VARIANTES)[number])) {
    return new Response(JSON.stringify({ error: 'impl inválida (c | rust)' }), { status: 400 });
  }
  const gdbScript = typeof body.gdbScript === 'string' && body.gdbScript.trim()
    ? body.gdbScript
    : 'break main\nrun\nbt\ninfo locals';
  if (gdbScript.length > 4000) {
    return new Response(JSON.stringify({ error: 'guion gdb demasiado largo' }), { status: 400 });
  }

  const script = `
set -uo pipefail
# cargo/cmake locales del proyecto (toolchains/, gitignorado)
source tools/env-devpc.sh >/dev/null 2>&1 || true
echo "[taller] compilando parity test de ${modulo} (C y Rust, con -g)"
if ! tools/run-parity-tests.sh ${modulo}; then
  echo "[taller] AVISO: la paridad falló — razón de más para depurar; seguimos"
fi
BIN="build-host/${modulo}-parity-${impl}"
if [[ ! -x "$BIN" ]]; then
  echo "[taller] no existe $BIN (¿falló la compilación?)"
  exit 1
fi
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
printf 'set confirm off\\nset pagination off\\n%s\\n' "$GDB_SCRIPT" > "$TMP"
echo "[taller] gdb --batch sobre $BIN"
echo "----------------------------------------"
gdb --batch -q -x "$TMP" "$BIN"
`;

  try {
    const dbId = crearBuildJob(`debug-${modulo}-${impl}`);
    const job = taller.lanzar(
      'debug',
      `Debug ${modulo} (${impl})`,
      script,
      { GDB_SCRIPT: gdbScript },
      (j) => {
        cerrarBuildJob(dbId, j.estado === 'ok' ? 'ok' : 'error', j.exitCode,
          (j.lineas.filter(Boolean).slice(-1)[0] ?? '').slice(0, 300));
      },
    );
    return new Response(JSON.stringify({ id: job.id }), {
      headers: { 'content-type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { status: 409 });
  }
};
