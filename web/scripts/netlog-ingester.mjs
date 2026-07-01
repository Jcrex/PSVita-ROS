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
