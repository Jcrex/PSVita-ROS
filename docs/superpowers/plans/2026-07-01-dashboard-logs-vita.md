# Dashboard de logs en vivo de la Vita — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar la lectura manual de `tools/netlog-listen.sh` por un
dashboard web (`/monitor`) que muestra en vivo el netlog UDP de la Vita,
con historial navegable por sesión.

**Architecture:** Un proceso Node nuevo y ligero (`web/scripts/netlog-ingester.mjs`)
escucha el UDP :9999, limpia y clasifica cada línea, y la guarda en la
SQLite ya existente (`web/data/app.db`). Astro (proceso separado, sin
tocar su arranque) expone `GET /api/monitor/sessions`,
`GET /api/monitor/session/[id]`, `GET /api/monitor/status` y
`GET /api/monitor/stream` (Server-Sent Events, con poll corto sobre la
misma DB) para alimentar la página `/monitor`.

**Tech Stack:** Astro 5 (adaptador `@astrojs/node` standalone, ya en el
proyecto), `better-sqlite3` (ya en el proyecto), `node:dgram` y `node:test`
(built-in de Node 22, sin dependencias nuevas), JS vanilla + `EventSource`
en el navegador (sin frameworks de frontend nuevos).

## Global Constraints

- Spec de referencia: `docs/superpowers/specs/2026-07-01-dashboard-logs-vita-design.md`.
- Solo se diseña/implementa el dashboard de logs (subproyecto 1 de 3);
  analítica y constructor de UI quedan fuera, para specs futuros.
- `tools/netlog-listen.sh` se mantiene intacto como alternativa de
  terminal; solo un proceso puede tener el puerto UDP 9999 a la vez
  (limitación conocida y aceptada, no se resuelve con `SO_REUSEPORT`).
- Herramienta de desarrollo local: sin autenticación, no se expone en el
  futuro dominio público.
- No se integran `ros2 topic echo`/`pub` en la web; siguen siendo
  terminales.
- Sin dependencias nuevas de npm: todo con `better-sqlite3`, `node:dgram`,
  `node:test` y Astro, que ya están en `web/package.json`.
- Docs y comentarios en español; commits con prefijo `feat(web):` o
  `test(web):` según corresponda, uno por tarea coherente.
- El esquema SQL de `vita_sessions`/`vita_log_lines` vive en un único
  archivo (`web/scripts/vita-monitor-schema.sql`, Task 1) leído tanto por
  `db.ts` (import `?raw` de Vite) como por `netlog-ingester.mjs`
  (`readFileSync`, Task 3) — no se duplica el DDL entre los dos procesos.
- El contenedor reinicia solo el proceso del ingestor si muere
  (`web/scripts/docker-entrypoint.sh`, Task 7); el servidor Astro sigue
  siendo el único que recibe señales de apagado de Docker.

---

### Task 1: Esquema compartido y funciones de consulta en `db.ts`

**Files:**
- Create: `web/scripts/vita-monitor-schema.sql`
- Modify: `web/src/lib/db.ts`

**Interfaces:**
- Consumes: nada nuevo (usa el mismo `Database` de `better-sqlite3` ya
  importado en el archivo).
- Produce además `web/scripts/vita-monitor-schema.sql`, que la Task 3
  reutiliza tal cual (mismo archivo, no una copia) para que el ingestor
  (proceso Node separado, sin acceso a `db.ts` en TypeScript) cree las
  mismas tablas sin duplicar el DDL.
- Produces (quedan disponibles para las Tasks 4, 5 y 6):
  - `interface VitaSession { id: number; started_at: string; ended_at: string | null; source_ip: string | null; status: 'en-curso' | 'establecida' | 'fatal' | 'cerrada'; }`
  - `interface VitaLogLine { id: number; session_id: number; received_at: string; raw_text: string; kind: 'normal' | 'hito' | 'fatal'; }`
  - `listSessions(): VitaSession[]`
  - `getSession(id: number): VitaSession | undefined`
  - `getSessionLines(id: number): VitaLogLine[]`
  - `getLatestSession(): VitaSession | undefined`
  - `getLinesAfter(sessionId: number, afterId: number): VitaLogLine[]`
  - `getLastReceivedAt(): string | null`

Esta tarea es de tipo "esquema + envoltorios finos sobre SQL"; el propio
proyecto no tiene tests automatizados para `db.ts` hoy (ver spec, sección
Testing), así que se verifica manualmente contra la DB real en vez de con
TDD estricto.

- [ ] **Step 1: Crear el esquema SQL compartido**

Crear `web/scripts/vita-monitor-schema.sql` (un único archivo fuente de
verdad, leído tanto por `db.ts` — vía import `?raw` de Vite, inlined en
el build de Astro — como por `web/scripts/netlog-ingester.mjs` en la
Task 3 — vía `readFileSync` en runtime, ya que es un proceso Node aparte
que no pasa por el bundler):
```sql
-- vita-monitor-schema.sql — esquema del dashboard /monitor (netlog en
-- vivo de la Vita). Un solo archivo, leído por dos consumidores:
--   - web/src/lib/db.ts (Astro): import ?raw de Vite, se inlinea en el
--     build, por eso no necesita resolver una ruta en runtime.
--   - web/scripts/netlog-ingester.mjs: proceso Node aparte, sin bundler,
--     lo lee con readFileSync relativo a su propio directorio.
CREATE TABLE IF NOT EXISTS vita_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  ended_at TEXT,
  source_ip TEXT,
  status TEXT NOT NULL DEFAULT 'en-curso'
);

CREATE TABLE IF NOT EXISTS vita_log_lines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES vita_sessions(id),
  received_at TEXT NOT NULL DEFAULT (datetime('now')),
  raw_text TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'normal'
);
```

- [ ] **Step 2: Ejecutar ese esquema desde `db.ts`**

En `web/src/lib/db.ts`, añadir el import al principio del archivo (junto a
los que ya existen) y ejecutar el esquema justo después del bloque
existente `db.exec(\`CREATE TABLE IF NOT EXISTS checklist_progress...\`)`:
```ts
import vitaMonitorSchema from '../../scripts/vita-monitor-schema.sql?raw';
```
```ts
// vita_sessions / vita_log_lines — dashboard /monitor (netlog en vivo).
// Esquema compartido con web/scripts/netlog-ingester.mjs: ver
// web/scripts/vita-monitor-schema.sql (un solo archivo, no una copia).
db.exec(vitaMonitorSchema);
```

- [ ] **Step 3: Añadir tipos, prepared statements y funciones al final del archivo**

Al final de `web/src/lib/db.ts`, después de `getSteps`, añadir:
```ts
export interface VitaSession {
  id: number;
  started_at: string;
  ended_at: string | null;
  source_ip: string | null;
  status: 'en-curso' | 'establecida' | 'fatal' | 'cerrada';
}

export interface VitaLogLine {
  id: number;
  session_id: number;
  received_at: string;
  raw_text: string;
  kind: 'normal' | 'hito' | 'fatal';
}

const listSessionsStmt = db.prepare(
  `SELECT * FROM vita_sessions ORDER BY started_at DESC LIMIT 50`,
);
const getSessionStmt = db.prepare(`SELECT * FROM vita_sessions WHERE id = ?`);
const getSessionLinesStmt = db.prepare(
  `SELECT * FROM vita_log_lines WHERE session_id = ? ORDER BY id ASC`,
);
const getLatestSessionStmt = db.prepare(
  `SELECT * FROM vita_sessions ORDER BY started_at DESC LIMIT 1`,
);
const getLinesAfterStmt = db.prepare(
  `SELECT * FROM vita_log_lines WHERE session_id = ? AND id > ? ORDER BY id ASC`,
);
const getLastReceivedAtStmt = db.prepare(
  `SELECT MAX(received_at) AS last FROM vita_log_lines`,
);

export function listSessions(): VitaSession[] {
  return listSessionsStmt.all() as VitaSession[];
}

export function getSession(id: number): VitaSession | undefined {
  return getSessionStmt.get(id) as VitaSession | undefined;
}

export function getSessionLines(id: number): VitaLogLine[] {
  return getSessionLinesStmt.all(id) as VitaLogLine[];
}

export function getLatestSession(): VitaSession | undefined {
  return getLatestSessionStmt.get() as VitaSession | undefined;
}

export function getLinesAfter(sessionId: number, afterId: number): VitaLogLine[] {
  return getLinesAfterStmt.all(sessionId, afterId) as VitaLogLine[];
}

export function getLastReceivedAt(): string | null {
  const row = getLastReceivedAtStmt.get() as { last: string | null };
  return row.last;
}
```

- [ ] **Step 4: Verificar que el build tipa y ejecuta el esquema bien**

```bash
cd web
corepack enable pnpm && pnpm install    # si no se ha hecho ya en esta máquina
pnpm build 2>&1 | tail -20
```
Expected: build sin errores de TypeScript (el import `?raw` debe resolver
sin problema — Astro incluye los tipos de Vite; si aparece un error de
tipos en ese import, añadir `web/src/env.d.ts` con
`/// <reference types="astro/client" />` y repetir).

```bash
rm -f data/app.db && pnpm dev &
sleep 2
curl -s localhost:4321/api/checklist > /dev/null   # fuerza a cargar db.ts (400 esperado, no importa)
sqlite3 data/app.db ".tables"
```
Expected: la salida de `.tables` incluye `checklist_progress`,
`vita_sessions` y `vita_log_lines`.

```bash
kill %1   # para el pnpm dev del paso anterior
```

- [ ] **Step 5: Commit**

```bash
git add web/scripts/vita-monitor-schema.sql web/src/lib/db.ts
git commit -m "feat(web): esquema compartido y consultas de sesiones/líneas de netlog"
```

---

### Task 2: Funciones puras de parseo del netlog (`netlog-parser.mjs`)

**Files:**
- Create: `web/scripts/netlog-parser.mjs`
- Test: `web/scripts/netlog-parser.test.mjs`

**Interfaces:**
- Consumes: nada (funciones puras, sin dependencias).
- Produces (usadas por la Task 3):
  - `cleanLine(input: Buffer | string): string`
  - `classifyKind(text: string): 'normal' | 'hito' | 'fatal'`
  - `isSessionStart(text: string): boolean`
  - `deriveStatusUpdate(text: string): 'establecida' | 'fatal' | 'cerrada' | null`

- [ ] **Step 1: Escribir el test que falla**

Crear `web/scripts/netlog-parser.test.mjs`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanLine,
  classifyKind,
  isSessionStart,
  deriveStatusUpdate,
} from './netlog-parser.mjs';

test('cleanLine quita bytes de control/ruido binario al inicio', () => {
  const noisy =
    Buffer.from([0x01, 0x02, 0xff, 0xfe]).toString('utf8') +
    '[vita-ros2] red inicializada; agente=192.168.1.108:8888';
  assert.equal(
    cleanLine(noisy),
    '[vita-ros2] red inicializada; agente=192.168.1.108:8888',
  );
});

test('cleanLine no toca una línea ya limpia', () => {
  assert.equal(
    cleanLine('[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello'),
    '[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello',
  );
});

test('cleanLine recorta espacios y saltos de línea sobrantes', () => {
  assert.equal(cleanLine('  hola  \n'), 'hola');
});

test('cleanLine acepta Buffer directamente', () => {
  assert.equal(cleanLine(Buffer.from('hola')), 'hola');
});

test('classifyKind detecta FATAL', () => {
  assert.equal(
    classifyKind('[vita-ros2] FATAL: uxr_create_session fallo'),
    'fatal',
  );
});

test('classifyKind detecta hitos (sesión establecida y criterio cumplido)', () => {
  assert.equal(
    classifyKind('[vita-ros2] *** SESION XRCE ESTABLECIDA: incognita dura OK ***'),
    'hito',
  );
  assert.equal(
    classifyKind('[vita-ros2] criterio 2 de la Fase 1 CUMPLIDO (rx desde PC)'),
    'hito',
  );
});

test('classifyKind por defecto es normal', () => {
  assert.equal(
    classifyKind('[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello'),
    'normal',
  );
});

test('isSessionStart detecta el arranque de una sesión nueva', () => {
  assert.equal(
    isSessionStart('[vita-ros2] red inicializada; agente=192.168.1.108:8888'),
    true,
  );
  assert.equal(
    isSessionStart('[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello'),
    false,
  );
});

test('deriveStatusUpdate detecta sesión establecida, fatal y salida limpia', () => {
  assert.equal(
    deriveStatusUpdate('[vita-ros2] *** SESION XRCE ESTABLECIDA: incognita dura OK ***'),
    'establecida',
  );
  assert.equal(
    deriveStatusUpdate('[vita-ros2] FATAL: uxr_create_session fallo'),
    'fatal',
  );
  assert.equal(
    deriveStatusUpdate('[vita-ros2] saliendo (START pulsado tras 42 mensajes)'),
    'cerrada',
  );
});

test('deriveStatusUpdate devuelve null si la línea no marca cambio de estado', () => {
  assert.equal(
    deriveStatusUpdate('[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello'),
    null,
  );
});
```

- [ ] **Step 2: Ejecutar el test y comprobar que falla**

```bash
cd web
node --test scripts/netlog-parser.test.mjs
```
Expected: FAIL — `Cannot find module '.../netlog-parser.mjs'` (el archivo
todavía no existe).

- [ ] **Step 3: Implementación mínima**

Crear `web/scripts/netlog-parser.mjs`:
```js
// netlog-parser.mjs — funciones puras para interpretar el netlog UDP de
// la Vita (ver vita-app/src/netlog.c y main.c). Sin dependencias: las usa
// tanto el ingestor (netlog-ingester.mjs) como sus propios tests.

export function cleanLine(input) {
  const text = Buffer.isBuffer(input) ? input.toString('utf8') : String(input);
  let start = 0;
  while (start < text.length) {
    const code = text.charCodeAt(start);
    const isControl = code < 0x20 && code !== 0x09;
    const isReplacement = text[start] === '�';
    if (isControl || isReplacement) {
      start++;
    } else {
      break;
    }
  }
  return text.slice(start).trim();
}

export function classifyKind(text) {
  if (text.includes('FATAL')) return 'fatal';
  if (text.includes('SESION XRCE ESTABLECIDA') || text.includes('CUMPLIDO')) {
    return 'hito';
  }
  return 'normal';
}

export function isSessionStart(text) {
  return text.includes('red inicializada');
}

export function deriveStatusUpdate(text) {
  if (text.includes('SESION XRCE ESTABLECIDA')) return 'establecida';
  if (text.includes('FATAL')) return 'fatal';
  if (text.includes('saliendo (START pulsado')) return 'cerrada';
  return null;
}
```

- [ ] **Step 4: Ejecutar el test y comprobar que pasa**

```bash
cd web
node --test scripts/netlog-parser.test.mjs
```
Expected: PASS — 10 tests, 0 fallos.

- [ ] **Step 5: Añadir el script de test a `package.json`**

En `web/package.json`, dentro de `"scripts"`, añadir:
```json
"test:ingester": "node --test scripts/"
```

- [ ] **Step 6: Commit**

```bash
git add web/scripts/netlog-parser.mjs web/scripts/netlog-parser.test.mjs web/package.json
git commit -m "test(web): funciones puras de parseo del netlog con node:test"
```

---

### Task 3: Ingestor UDP → SQLite (`netlog-ingester.mjs`)

**Files:**
- Create: `web/scripts/netlog-ingester.mjs`
- Modify: `web/package.json`

**Interfaces:**
- Consumes: `cleanLine`, `classifyKind`, `isSessionStart`, `deriveStatusUpdate`
  de `./netlog-parser.mjs` (Task 2); `./vita-monitor-schema.sql` (Task 1 —
  mismo archivo, se lee con `readFileSync`, no se copia el DDL).
- Produces: proceso que escribe filas en `vita_sessions` / `vita_log_lines`
  al recibir paquetes UDP. No expone API en proceso; se usa lanzándolo
  (`node scripts/netlog-ingester.mjs`).

No hay TDD estricto aquí (es un proceso con efectos de red + disco); se
verifica end-to-end simulando paquetes UDP reales, igual que se hará en
producción.

- [ ] **Step 1: Escribir el ingestor**

Crear `web/scripts/netlog-ingester.mjs`:
```js
#!/usr/bin/env node
// netlog-ingester.mjs — escucha el netlog UDP de la Vita (ver
// vita-app/src/netlog.c) y lo guarda en la misma SQLite que usa Astro
// (ver src/lib/db.ts), para alimentar el dashboard /monitor.
//
// Proceso separado del servidor Astro (ver
// docs/superpowers/specs/2026-07-01-dashboard-logs-vita-design.md): no
// puede importar db.ts (TypeScript) en runtime, así que lee el MISMO
// archivo de esquema que usa db.ts (./vita-monitor-schema.sql, junto a
// este script) en vez de duplicar el DDL.
import dgram from 'node:dgram';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import Database from 'better-sqlite3';
import {
  cleanLine,
  classifyKind,
  isSessionStart,
  deriveStatusUpdate,
} from './netlog-parser.mjs';

const PORT = Number(process.env.NETLOG_PORT ?? 9999);
const DB_PATH = process.env.DB_PATH ?? resolve('data/app.db');
const IDLE_TIMEOUT_MS = Number(process.env.NETLOG_IDLE_TIMEOUT_MS ?? 30_000);
const IDLE_CHECK_INTERVAL_MS = Number(process.env.NETLOG_IDLE_CHECK_INTERVAL_MS ?? 5000);

mkdirSync(dirname(DB_PATH), { recursive: true });
const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
const schemaSql = readFileSync(
  new URL('./vita-monitor-schema.sql', import.meta.url),
  'utf8',
);
db.exec(schemaSql);

const insertSession = db.prepare(
  `INSERT INTO vita_sessions (started_at, source_ip, status) VALUES (datetime('now'), ?, 'en-curso')`,
);
const closeSessionAuto = db.prepare(`
  UPDATE vita_sessions SET ended_at = datetime('now'),
    status = CASE WHEN status = 'en-curso' THEN 'cerrada' ELSE status END
  WHERE id = ?
`);
const closeSessionExplicit = db.prepare(
  `UPDATE vita_sessions SET ended_at = datetime('now'), status = 'cerrada' WHERE id = ?`,
);
const updateStatus = db.prepare(`UPDATE vita_sessions SET status = ? WHERE id = ?`);
const insertLine = db.prepare(
  `INSERT INTO vita_log_lines (session_id, received_at, raw_text, kind) VALUES (?, datetime('now'), ?, ?)`,
);
const findOpenSession = db.prepare(
  `SELECT id FROM vita_sessions WHERE ended_at IS NULL ORDER BY id DESC LIMIT 1`,
);

let currentSessionId = findOpenSession.get()?.id ?? null;
let lastPacketAt = Date.now();

function openNewSession(sourceIp) {
  if (currentSessionId !== null) {
    closeSessionAuto.run(currentSessionId);
  }
  currentSessionId = insertSession.run(sourceIp).lastInsertRowid;
}

const socket = dgram.createSocket('udp4');

socket.on('error', (err) => {
  console.error('[netlog-ingester] error de socket, ¿puerto ocupado?', err.message);
});

socket.on('message', (msg, rinfo) => {
  lastPacketAt = Date.now();
  const text = cleanLine(msg);
  if (text === '') return;

  const sourceIp = `${rinfo.address}:${rinfo.port}`;
  if (isSessionStart(text) || currentSessionId === null) {
    openNewSession(sourceIp);
  }

  insertLine.run(currentSessionId, text, classifyKind(text));

  const statusUpdate = deriveStatusUpdate(text);
  if (statusUpdate === 'cerrada') {
    closeSessionExplicit.run(currentSessionId);
    currentSessionId = null;
  } else if (statusUpdate) {
    updateStatus.run(statusUpdate, currentSessionId);
  }
});

setInterval(() => {
  if (currentSessionId !== null && Date.now() - lastPacketAt > IDLE_TIMEOUT_MS) {
    closeSessionAuto.run(currentSessionId);
    currentSessionId = null;
  }
}, IDLE_CHECK_INTERVAL_MS);

socket.bind(PORT, () => {
  console.log(`[netlog-ingester] escuchando UDP :${PORT}, DB en ${DB_PATH}`);
});
```

- [ ] **Step 2: Añadir el script de arranque a `package.json`**

En `web/package.json`, dentro de `"scripts"`, añadir:
```json
"ingester": "node scripts/netlog-ingester.mjs"
```

- [ ] **Step 3: Verificar end-to-end con paquetes UDP simulados**

```bash
cd web
rm -f /tmp/test-netlog.db
DB_PATH=/tmp/test-netlog.db NETLOG_PORT=19999 \
  NETLOG_IDLE_TIMEOUT_MS=1000 NETLOG_IDLE_CHECK_INTERVAL_MS=500 \
  node scripts/netlog-ingester.mjs &
INGESTER_PID=$!
sleep 1

node -e "const s=require('dgram').createSocket('udp4'); s.send('[vita-ros2] red inicializada; agente=test', 19999, '127.0.0.1', ()=>s.close());"
sleep 0.5
node -e "const s=require('dgram').createSocket('udp4'); s.send('[vita-ros2] *** SESION XRCE ESTABLECIDA: incognita dura OK ***', 19999, '127.0.0.1', ()=>s.close());"
sleep 0.5

sqlite3 /tmp/test-netlog.db "SELECT id, status, source_ip, ended_at FROM vita_sessions;"
sqlite3 /tmp/test-netlog.db "SELECT session_id, kind, raw_text FROM vita_log_lines ORDER BY id;"
```
Expected primera consulta: una fila, `status='establecida'`,
`source_ip` empezando por `127.0.0.1:`, `ended_at` vacío (sesión todavía
viva). Expected segunda consulta: dos filas — la primera con
`kind='normal'` y el texto `[vita-ros2] red inicializada; agente=test`, la
segunda con `kind='hito'` y el texto de `SESION XRCE ESTABLECIDA`.

Ahora comprobar el cierre por inactividad (timeout 1s, chequeo cada 0.5s,
así que 2s de margen es de sobra y el resultado no depende de timing
ajustado):
```bash
sleep 2
sqlite3 /tmp/test-netlog.db "SELECT status, ended_at FROM vita_sessions;"
```
Expected: `status='establecida'` (no baja a `cerrada` porque ya no estaba
`en-curso`) y `ended_at` ahora tiene un valor (la sesión se cerró sola).

```bash
kill $INGESTER_PID
rm /tmp/test-netlog.db
```

- [ ] **Step 4: Commit**

```bash
git add web/scripts/netlog-ingester.mjs web/package.json
git commit -m "feat(web): ingestor UDP del netlog de la Vita hacia SQLite"
```

---

### Task 4: Endpoints `GET /api/monitor/sessions`, `/session/[id]`, `/status`

**Files:**
- Create: `web/src/pages/api/monitor/sessions.ts`
- Create: `web/src/pages/api/monitor/session/[id].ts`
- Create: `web/src/pages/api/monitor/status.ts`

**Interfaces:**
- Consumes de `../../../lib/db` (Task 1): `listSessions`, `getSession`,
  `getSessionLines`, `getLastReceivedAt`.
- Produces:
  - `GET /api/monitor/sessions` → `200 VitaSession[]`
  - `GET /api/monitor/session/:id` → `200 { session: VitaSession, lines: VitaLogLine[] }` | `400` | `404`
  - `GET /api/monitor/status` → `200 { lastReceivedAt: string | null }`

- [ ] **Step 1: Crear `web/src/pages/api/monitor/sessions.ts`**

```ts
import type { APIRoute } from 'astro';
import { listSessions } from '../../../lib/db';

export const prerender = false;

export const GET: APIRoute = () => {
  return new Response(JSON.stringify(listSessions()), {
    headers: { 'content-type': 'application/json' },
  });
};
```

- [ ] **Step 2: Crear `web/src/pages/api/monitor/session/[id].ts`**

```ts
import type { APIRoute } from 'astro';
import { getSession, getSessionLines } from '../../../../lib/db';

export const prerender = false;

export const GET: APIRoute = ({ params }) => {
  const id = Number(params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return new Response(JSON.stringify({ error: 'bad id' }), { status: 400 });
  }
  const session = getSession(id);
  if (!session) {
    return new Response(JSON.stringify({ error: 'not found' }), { status: 404 });
  }
  return new Response(
    JSON.stringify({ session, lines: getSessionLines(id) }),
    { headers: { 'content-type': 'application/json' } },
  );
};
```

- [ ] **Step 3: Crear `web/src/pages/api/monitor/status.ts`**

```ts
import type { APIRoute } from 'astro';
import { getLastReceivedAt } from '../../../lib/db';

export const prerender = false;

export const GET: APIRoute = () => {
  return new Response(
    JSON.stringify({ lastReceivedAt: getLastReceivedAt() }),
    { headers: { 'content-type': 'application/json' } },
  );
};
```

- [ ] **Step 4: Verificar los tres endpoints a mano**

```bash
cd web
rm -f /tmp/test-monitor.db
DB_PATH=/tmp/test-monitor.db pnpm dev &
DEV_PID=$!
sleep 2

DB_PATH=/tmp/test-monitor.db NETLOG_PORT=19999 node scripts/netlog-ingester.mjs &
INGESTER_PID=$!
sleep 1

node -e "const s=require('dgram').createSocket('udp4'); s.send('[vita-ros2] red inicializada; agente=test', 19999, '127.0.0.1', ()=>s.close());"
sleep 1

curl -s localhost:4321/api/monitor/sessions | head -c 300; echo
curl -s localhost:4321/api/monitor/session/1 | head -c 300; echo
curl -s localhost:4321/api/monitor/session/999; echo
curl -s localhost:4321/api/monitor/status; echo

kill $DEV_PID $INGESTER_PID
rm /tmp/test-monitor.db
```
Expected: `/sessions` devuelve un array con una sesión `status:"en-curso"`;
`/session/1` devuelve `{"session":{...},"lines":[{...,"raw_text":"[vita-ros2] red inicializada; agente=test",...}]}`;
`/session/999` devuelve `{"error":"not found"}` (404); `/status` devuelve
`{"lastReceivedAt":"<fecha>"}`.

- [ ] **Step 5: Commit**

```bash
git add web/src/pages/api/monitor/sessions.ts web/src/pages/api/monitor/session/\[id\].ts web/src/pages/api/monitor/status.ts
git commit -m "feat(web): endpoints de sesiones e indicador de estado del monitor"
```

---

### Task 5: Endpoint SSE `GET /api/monitor/stream`

**Files:**
- Create: `web/src/pages/api/monitor/stream.ts`

**Interfaces:**
- Consumes de `../../../lib/db` (Task 1): `getLatestSession`, `getLinesAfter`.
- Produces: `GET /api/monitor/stream` — respuesta `text/event-stream` que
  emite eventos `session-changed` (`data: {"sessionId": number}`) y
  mensajes por defecto con una `VitaLogLine` en JSON por línea nueva.

- [ ] **Step 1: Crear `web/src/pages/api/monitor/stream.ts`**

```ts
import type { APIRoute } from 'astro';
import { getLatestSession, getLinesAfter } from '../../../lib/db';

export const prerender = false;

const POLL_MS = 400;

export const GET: APIRoute = () => {
  const encoder = new TextEncoder();
  let closed = false;
  let activeSessionId: number | null = null;
  let lastLineId = 0;
  let timer: ReturnType<typeof setTimeout>;

  const stream = new ReadableStream({
    start(controller) {
      const send = (event: string | null, data: unknown) => {
        const prefix = event ? `event: ${event}\n` : '';
        controller.enqueue(
          encoder.encode(`${prefix}data: ${JSON.stringify(data)}\n\n`),
        );
      };

      const tick = () => {
        if (closed) return;
        const latest = getLatestSession();
        if (!latest) {
          timer = setTimeout(tick, POLL_MS);
          return;
        }
        if (latest.id !== activeSessionId) {
          activeSessionId = latest.id;
          lastLineId = 0;
          send('session-changed', { sessionId: activeSessionId });
        }
        const newLines = getLinesAfter(activeSessionId, lastLineId);
        for (const line of newLines) {
          lastLineId = line.id;
          send(null, line);
        }
        timer = setTimeout(tick, POLL_MS);
      };
      tick();
    },
    cancel() {
      closed = true;
      clearTimeout(timer);
    },
  });

  return new Response(stream, {
    headers: {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      connection: 'keep-alive',
    },
  });
};
```

- [ ] **Step 2: Verificar el stream a mano con `curl`**

```bash
cd web
rm -f /tmp/test-stream.db
DB_PATH=/tmp/test-stream.db pnpm dev &
DEV_PID=$!
sleep 2

DB_PATH=/tmp/test-stream.db NETLOG_PORT=19999 node scripts/netlog-ingester.mjs &
INGESTER_PID=$!
sleep 1

timeout 3 curl -sN localhost:4321/api/monitor/stream &
sleep 0.5
node -e "const s=require('dgram').createSocket('udp4'); s.send('[vita-ros2] red inicializada; agente=test', 19999, '127.0.0.1', ()=>s.close());"
sleep 0.5
node -e "const s=require('dgram').createSocket('udp4'); s.send('hola desde la vita', 19999, '127.0.0.1', ()=>s.close());"
wait

kill $DEV_PID $INGESTER_PID
rm /tmp/test-stream.db
```
Expected en la salida de `curl`: primero un evento
`event: session-changed` con un `sessionId`, y luego dos `data:` con las
dos líneas mandadas (`red inicializada...` y `hola desde la vita`) en
formato JSON.

- [ ] **Step 3: Commit**

```bash
git add web/src/pages/api/monitor/stream.ts
git commit -m "feat(web): endpoint SSE del monitor de logs de la Vita"
```

---

### Task 6: Página `/monitor` y enlace de navegación

**Files:**
- Create: `web/src/pages/monitor.astro`
- Modify: `web/src/layouts/Base.astro:14-20` (array `nav`)

**Interfaces:**
- Consumes de `../lib/db` (Task 1): `listSessions`, `getSessionLines`,
  `getLastReceivedAt`. Consume en el navegador los endpoints de las
  Tasks 4 y 5 (`/api/monitor/sessions` vía clic, `/api/monitor/session/:id`,
  `/api/monitor/status`, `/api/monitor/stream`).
- Produces: página `/monitor` navegable desde el menú del sitio.

- [ ] **Step 1: Añadir el enlace al nav en `Base.astro`**

En `web/src/layouts/Base.astro`, dentro del array `nav`, añadir una entrada
antes de `/progreso`:
```ts
const nav = [
  { href: '/', label: 'Inicio' },
  { href: '/arquitectura', label: 'Arquitectura' },
  { href: '/docs', label: 'Documentación' },
  { href: '/guias', label: 'Guías Vita' },
  { href: '/monitor', label: 'Monitor' },
  { href: '/progreso', label: 'Progreso' },
];
```

- [ ] **Step 2: Crear `web/src/pages/monitor.astro`**

```astro
---
// monitor.astro — dashboard en vivo del netlog de la Vita. Ver
// docs/superpowers/specs/2026-07-01-dashboard-logs-vita-design.md.
export const prerender = false;
import Base from '../layouts/Base.astro';
import { listSessions, getSessionLines } from '../lib/db';

const sessions = listSessions();
const latest = sessions[0];
const initialLines = latest ? getSessionLines(latest.id) : [];

const statusLabel: Record<string, string> = {
  'en-curso': '🟢 viva',
  establecida: '✅ establecida',
  fatal: '🔴 fatal',
  cerrada: '⚪ cerrada',
};
---

<Base title="Monitor" description="Logs en vivo de la PS Vita, por sesión.">
  <h1>Monitor de la Vita <span id="global-status">⚪</span></h1>
  <p style="color:var(--text-dim)">
    Sustituye la lectura manual con <code>tools/netlog-listen.sh</code>:
    cada lanzamiento de <code>vita-ros2-hello</code> queda aquí como una
    sesión navegable.
  </p>

  {sessions.length === 0 && (
    <p>Todavía no ha llegado ningún log de la Vita.</p>
  )}

  <div class="monitor-grid">
    <aside class="panel" id="session-list">
      <h2 style="margin-top:0;border:none">Sesiones</h2>
      <ul id="sessions-ul" style="list-style:none;padding:0">
        {sessions.map((s) => (
          <li>
            <button class="session-btn" data-id={s.id}>
              #{s.id} — {s.started_at}{' '}
              <span class="badge">{statusLabel[s.status]}</span>
            </button>
          </li>
        ))}
      </ul>
    </aside>

    <section class="panel" id="log-panel" data-session-id={latest?.id ?? ''}>
      <h2 style="margin-top:0;border:none" id="log-title">
        {latest ? `Sesión #${latest.id}` : 'Sin sesiones todavía'}
      </h2>
      <pre id="log-lines">{initialLines
        .map((l) => `[${l.received_at}] ${l.raw_text}`)
        .join('\n')}</pre>
    </section>
  </div>

  <style>
    .monitor-grid {
      display: grid;
      grid-template-columns: 240px 1fr;
      gap: 1.2rem;
      align-items: start;
    }
    .session-btn {
      display: block;
      width: 100%;
      text-align: left;
      background: none;
      border: none;
      color: var(--text);
      padding: .4rem .3rem;
      cursor: pointer;
      font: inherit;
      border-radius: 6px;
    }
    .session-btn:hover { background: var(--panel-border); }
    #log-lines {
      max-height: 60vh;
      overflow-y: auto;
      background: var(--bg-soft);
      padding: 1rem;
      border-radius: var(--radius);
      font-family: var(--mono);
      font-size: .85rem;
      white-space: pre-wrap;
    }
    .log-fatal { color: #f87171; }
    .log-hito { color: var(--ok); font-weight: 600; }
  </style>

  <script>
    interface LogLine {
      session_id: number;
      received_at: string;
      raw_text: string;
      kind: 'normal' | 'hito' | 'fatal';
    }

    const logLines = document.getElementById('log-lines')!;
    const logTitle = document.getElementById('log-title')!;
    const logPanel = document.getElementById('log-panel')!;
    const globalStatus = document.getElementById('global-status')!;

    function lineNode(l: { received_at: string; raw_text: string; kind: string }) {
      const span = document.createElement('span');
      span.className =
        l.kind === 'fatal' ? 'log-fatal' : l.kind === 'hito' ? 'log-hito' : '';
      span.textContent = `[${l.received_at}] ${l.raw_text}\n`;
      return span;
    }

    async function loadSession(id: string) {
      const res = await fetch(`/api/monitor/session/${id}`);
      if (!res.ok) return;
      const { session, lines } = await res.json();
      logTitle.textContent = `Sesión #${session.id}`;
      logPanel.dataset.sessionId = String(session.id);
      logLines.innerHTML = '';
      for (const l of lines) logLines.appendChild(lineNode(l));
      logLines.scrollTop = logLines.scrollHeight;
    }

    document.querySelectorAll<HTMLButtonElement>('.session-btn').forEach((btn) => {
      btn.addEventListener('click', () => loadSession(btn.dataset.id!));
    });

    // Vista en vivo: sigue siempre la sesión más reciente vía SSE.
    const source = new EventSource('/api/monitor/stream');
    source.addEventListener('session-changed', () => {
      location.reload();
    });
    source.onmessage = (ev) => {
      const line: LogLine = JSON.parse(ev.data);
      if (logPanel.dataset.sessionId === String(line.session_id)) {
        logLines.appendChild(lineNode(line));
        logLines.scrollTop = logLines.scrollHeight;
      }
    };

    // Indicador global: ¿llegó algo en los últimos 5s?
    async function pollStatus() {
      const res = await fetch('/api/monitor/status');
      const { lastReceivedAt } = (await res.json()) as { lastReceivedAt: string | null };
      const fresh =
        !!lastReceivedAt &&
        Date.now() - new Date(lastReceivedAt.replace(' ', 'T') + 'Z').getTime() < 5000;
      globalStatus.textContent = fresh ? '🟢' : '⚪';
      setTimeout(pollStatus, 5000);
    }
    pollStatus();
  </script>
</Base>
```

- [ ] **Step 3: Verificar en el navegador**

```bash
cd web
rm -f /tmp/test-page.db
DB_PATH=/tmp/test-page.db pnpm dev &
DEV_PID=$!
sleep 2
DB_PATH=/tmp/test-page.db NETLOG_PORT=19999 node scripts/netlog-ingester.mjs &
INGESTER_PID=$!
sleep 1
node -e "const s=require('dgram').createSocket('udp4'); s.send('[vita-ros2] red inicializada; agente=test', 19999, '127.0.0.1', ()=>s.close());"
```
Abrir `http://localhost:4321/monitor` en el navegador: debe aparecer el
enlace "Monitor" en la barra de navegación, una sesión en la lista
izquierda, y la línea `red inicializada` en el panel derecho. Enviar otra
línea:
```bash
node -e "const s=require('dgram').createSocket('udp4'); s.send('[vita-ros2] FATAL: prueba', 19999, '127.0.0.1', ()=>s.close());"
```
Debe aparecer sola, en rojo, sin recargar la página (llega por SSE).
```bash
kill $DEV_PID $INGESTER_PID
rm /tmp/test-page.db
```

- [ ] **Step 4: Commit**

```bash
git add web/src/pages/monitor.astro web/src/layouts/Base.astro
git commit -m "feat(web): página /monitor con vista en vivo y navegación por sesión"
```

---

### Task 7: Empaquetado Docker (dos procesos, un contenedor) y documentación

**Files:**
- Create: `web/scripts/docker-entrypoint.sh`
- Modify: `web/Dockerfile`
- Modify: `web/docker-compose.yml`
- Modify: `web/README.md`

**Interfaces:**
- Consumes: `web/scripts/netlog-ingester.mjs` (Task 3), `dist/server/entry.mjs`
  (build normal de Astro, sin cambios).
- Produces: imagen Docker que arranca ambos procesos (el ingestor con
  reinicio automático si muere) y publica el puerto UDP 9999 además del
  4321 ya existente.

- [ ] **Step 1: Copiar `scripts/` a la etapa de runtime del Dockerfile**

En `web/Dockerfile`, en la etapa `runtime`, después de la línea
`COPY --from=build /app/web/package.json ./package.json`, añadir:
```dockerfile
COPY --from=build /app/web/scripts ./scripts
```

- [ ] **Step 2: Crear el script de arranque con reinicio del ingestor**

Crear `web/scripts/docker-entrypoint.sh`:
```sh
#!/bin/sh
# docker-entrypoint.sh — arranca los dos procesos del contenedor de la web.
#
# El ingestor UDP del netlog (best-effort, no crítico para el dashboard)
# corre en un bucle que lo reinicia si muere, con una pausa corta para no
# entrar en un bucle de reinicio a toda velocidad si el fallo es
# persistente (p. ej. el puerto 9999 ocupado). El servidor Astro es el
# proceso principal: `exec` lo convierte en PID 1, así que recibe
# directamente las señales de `docker stop`/`docker compose down` para un
# apagado limpio. El bucle del ingestor no recibe esa señal explícita,
# pero muere igualmente cuando el contenedor se detiene (todo el
# namespace de procesos se destruye junto con él).
set -e

(
  while true; do
    node scripts/netlog-ingester.mjs
    echo "[docker-entrypoint] netlog-ingester salió (código $?); reintentando en 2s..." >&2
    sleep 2
  done
) &

exec node dist/server/entry.mjs
```

En `web/Dockerfile`, reemplazar:
```dockerfile
CMD ["node", "dist/server/entry.mjs"]
```
por:
```dockerfile
CMD ["sh", "scripts/docker-entrypoint.sh"]
```

- [ ] **Step 3: Publicar el puerto UDP 9999 en `docker-compose.yml`**

En `web/docker-compose.yml`, dentro de `ports:`, añadir la línea del
puerto UDP junto a la ya existente del 4321:
```yaml
    ports:
      - "4321:4321"
      - "9999:9999/udp"
```

- [ ] **Step 4: Documentar en `web/README.md`**

Añadir una fila a la tabla "Mapa" (después de la fila de `/progreso`):
```markdown
| `/monitor` | Dashboard en vivo del netlog de la Vita, por sesión |
| `/api/monitor/*` | Sesiones, líneas y stream SSE (ver `docs/superpowers/specs/2026-07-01-dashboard-logs-vita-design.md`) |
```

Añadir una sección nueva después de "### Cómo funciona el checklist":
```markdown
### Cómo funciona el monitor de logs (`/monitor`)

Reemplaza la lectura manual de `tools/netlog-listen.sh` por una vista web
en vivo. Un proceso Node separado (`scripts/netlog-ingester.mjs`) escucha
el UDP :9999, limpia y clasifica cada línea (normal/hito/fatal) y la
guarda en `data/app.db` (tablas `vita_sessions`/`vita_log_lines`); Astro
expone esos datos por HTTP y por Server-Sent Events. Solo un proceso puede
escuchar el puerto 9999 a la vez, así que `tools/netlog-listen.sh` y este
dashboard son alternativas, no complementos simultáneos.

En Docker, `scripts/docker-entrypoint.sh` arranca ambos procesos: si el
ingestor muere (p. ej. el puerto 9999 falla al abrir), un bucle lo
reinicia solo cada 2s — no hace falta reiniciar el contenedor entero para
recuperar el dashboard.

En desarrollo, arrancar los dos procesos en terminales separadas:
```bash
cd web
pnpm dev          # terminal 1
pnpm ingester     # terminal 2
```

Diseño completo en
`docs/superpowers/specs/2026-07-01-dashboard-logs-vita-design.md`.
```

- [ ] **Step 5: Verificar el contenedor completo**

```bash
cd web
docker compose up -d --build
sleep 3
docker compose logs | grep -E "netlog-ingester|astro|Server listening"
```
Expected: se ve tanto la línea `[netlog-ingester] escuchando UDP :9999...`
como el arranque normal de Astro.

```bash
node -e "const s=require('dgram').createSocket('udp4'); s.send('[vita-ros2] red inicializada; agente=test-docker', 9999, '127.0.0.1', ()=>s.close());"
sleep 1
curl -s localhost:4321/api/monitor/sessions
```
Expected: un array con una sesión cuyo `source_ip` empieza por `127.0.0.1:`.
Abrir `http://localhost:4321/monitor` en el navegador y confirmar
visualmente que aparece.

Ahora comprobar que el ingestor se reinicia solo si muere:
```bash
docker compose exec web sh -c "pkill -f netlog-ingester.mjs"
sleep 3
docker compose logs | grep "netlog-ingester"
```
Expected: se ve la línea `[docker-entrypoint] netlog-ingester salió...
reintentando en 2s...` seguida de un nuevo `[netlog-ingester] escuchando
UDP :9999...` — el proceso volvió a arrancar solo, sin reiniciar el
contenedor.

```bash
docker compose down
```

- [ ] **Step 6: Commit**

```bash
git add web/scripts/docker-entrypoint.sh web/Dockerfile web/docker-compose.yml web/README.md
git commit -m "feat(web): empaquetar el dashboard de monitor en el contenedor de la web"
```

---

## Verificación final (con la Vita real, próxima sesión)

Este plan se verifica de punta a punta con paquetes UDP simulados; queda
pendiente para la próxima vez que la Vita esté encendida: lanzar
`vita-ros2-hello`, dejar `docker compose up` de `web/` corriendo en la
laptop, y confirmar en `http://localhost:4321/monitor` que la sesión real
aparece con las mismas líneas que hoy se leyeron en
`tools/netlog-listen.sh` — marcar ese resultado en
`docs/06-bitacora-estado.md` cuando se haga.
