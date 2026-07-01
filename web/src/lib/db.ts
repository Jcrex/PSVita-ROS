// db.ts — acceso a SQLite (better-sqlite3, síncrono y sin servidor).
//
// La base vive en web/data/app.db (DB_PATH para sobreescribir; en Docker
// se monta ./web/data como volumen para que sobreviva a los redeploys).
// Hoy guarda el progreso del checklist de instalación por visitante;
// la estructura admite crecer (comentarios, telemetría de la Vita, ...).
import Database from 'better-sqlite3';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import vitaMonitorSchema from '../../scripts/vita-monitor-schema.sql?raw';

const DB_PATH = process.env.DB_PATH ?? resolve('data/app.db');

mkdirSync(dirname(DB_PATH), { recursive: true });

export const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS checklist_progress (
    client_id TEXT NOT NULL,
    guide_slug TEXT NOT NULL,
    step_id TEXT NOT NULL,
    done INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (client_id, guide_slug, step_id)
  );
`);

// vita_sessions / vita_log_lines — dashboard /monitor (netlog en vivo).
// Esquema compartido con web/scripts/netlog-ingester.mjs: ver
// web/scripts/vita-monitor-schema.sql (un solo archivo, no una copia).
db.exec(vitaMonitorSchema);

const upsertStmt = db.prepare(`
  INSERT INTO checklist_progress (client_id, guide_slug, step_id, done, updated_at)
  VALUES (@client_id, @guide_slug, @step_id, @done, datetime('now'))
  ON CONFLICT(client_id, guide_slug, step_id)
  DO UPDATE SET done = @done, updated_at = datetime('now')
`);

const selectStmt = db.prepare(`
  SELECT step_id, done FROM checklist_progress
  WHERE client_id = ? AND guide_slug = ?
`);

export function setStep(
  clientId: string,
  guideSlug: string,
  stepId: string,
  done: boolean,
): void {
  upsertStmt.run({
    client_id: clientId,
    guide_slug: guideSlug,
    step_id: stepId,
    done: done ? 1 : 0,
  });
}

export function getSteps(
  clientId: string,
  guideSlug: string,
): Record<string, boolean> {
  const rows = selectStmt.all(clientId, guideSlug) as {
    step_id: string;
    done: number;
  }[];
  return Object.fromEntries(rows.map((r) => [r.step_id, r.done === 1]));
}

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
  `SELECT * FROM vita_sessions ORDER BY id DESC LIMIT 50`,
);
const getSessionStmt = db.prepare(`SELECT * FROM vita_sessions WHERE id = ?`);
const getSessionLinesStmt = db.prepare(
  `SELECT * FROM vita_log_lines WHERE session_id = ? ORDER BY id ASC`,
);
const getLatestSessionStmt = db.prepare(
  `SELECT * FROM vita_sessions ORDER BY id DESC LIMIT 1`,
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
