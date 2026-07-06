// db.ts — acceso a SQLite (better-sqlite3, síncrono y sin servidor).
//
// La base vive en web/data/app.db (DB_PATH para sobreescribir; en Docker
// se monta ./web/data como volumen para que sobreviva a los redeploys).
// Hoy guarda el progreso del checklist de instalación por visitante;
// la estructura admite crecer (comentarios, telemetría de la Vita, ...).
import Database from 'better-sqlite3';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

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

  -- Layout del dashboard ROS2 (/dashboard): lista ordenada de widgets
  -- por visitante (mismo client-id anónimo que el checklist).
  CREATE TABLE IF NOT EXISTS dashboard_layout (
    client_id TEXT PRIMARY KEY,
    layout TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Historial de builds lanzados desde /taller/compilador (solo cuando la
  -- web corre en el PC de desarrollo con TALLER_ENABLED=1).
  CREATE TABLE IF NOT EXISTS build_jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    variante TEXT NOT NULL,
    estado TEXT NOT NULL DEFAULT 'corriendo',
    exit_code INTEGER,
    inicio TEXT NOT NULL DEFAULT (datetime('now')),
    fin TEXT,
    resumen TEXT
  );
`);

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

// ---- dashboard: layout de widgets por visitante ----

const layoutUpsert = db.prepare(`
  INSERT INTO dashboard_layout (client_id, layout, updated_at)
  VALUES (?, ?, datetime('now'))
  ON CONFLICT(client_id) DO UPDATE SET layout = excluded.layout, updated_at = datetime('now')
`);
const layoutSelect = db.prepare(`SELECT layout FROM dashboard_layout WHERE client_id = ?`);

export function setDashboardLayout(clientId: string, layout: string[]): void {
  layoutUpsert.run(clientId, JSON.stringify(layout));
}

export function getDashboardLayout(clientId: string): string[] | null {
  const row = layoutSelect.get(clientId) as { layout: string } | undefined;
  if (!row) return null;
  try {
    const parsed = JSON.parse(row.layout);
    return Array.isArray(parsed) ? parsed.filter((w) => typeof w === 'string') : null;
  } catch {
    return null;
  }
}

// ---- taller: historial de builds del compilador web ----

export interface BuildJob {
  id: number;
  variante: string;
  estado: string;
  exit_code: number | null;
  inicio: string;
  fin: string | null;
  resumen: string | null;
}

const jobInsert = db.prepare(`INSERT INTO build_jobs (variante) VALUES (?)`);
const jobFinish = db.prepare(`
  UPDATE build_jobs SET estado = ?, exit_code = ?, fin = datetime('now'), resumen = ? WHERE id = ?
`);
const jobList = db.prepare(`SELECT * FROM build_jobs ORDER BY id DESC LIMIT ?`);

export function crearBuildJob(variante: string): number {
  return Number(jobInsert.run(variante).lastInsertRowid);
}

export function cerrarBuildJob(
  id: number,
  estado: 'ok' | 'error' | 'cancelado',
  exitCode: number | null,
  resumen: string,
): void {
  jobFinish.run(estado, exitCode, resumen, id);
}

export function listarBuildJobs(limite = 20): BuildJob[] {
  return jobList.all(limite) as BuildJob[];
}
