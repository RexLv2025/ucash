import Database from 'better-sqlite3';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
export const DB_PATH = process.env.DB_PATH || path.join(DATA_DIR, 'ucash.db');

if (!fs.existsSync(path.dirname(DB_PATH))) {
  fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
}

export const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
db.exec(schema);

export function tx<T>(fn: () => T): T {
  const runner = db.transaction(fn);
  return runner();
}

export function getSetting<T = any>(key: string, fallback: T): T {
  const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(key) as { value: string } | undefined;
  if (!row) return fallback;
  try {
    return JSON.parse(row.value) as T;
  } catch {
    return fallback;
  }
}

export function setSetting(key: string, value: unknown, remark?: string) {
  db.prepare(
    `INSERT INTO settings(key, value, remark, updated_at) VALUES(?,?,?,?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, remark = COALESCE(excluded.remark, settings.remark), updated_at = excluded.updated_at`
  ).run(key, JSON.stringify(value), remark ?? null, new Date().toISOString());
}

export function audit(actorType: string, actorId: number | null, action: string, targetType?: string, targetId?: string | number | null, detail?: unknown, ip?: string) {
  db.prepare(
    `INSERT INTO audit_logs(actor_type, actor_id, action, target_type, target_id, detail, ip, created_at)
     VALUES(?,?,?,?,?,?,?,?)`
  ).run(actorType, actorId, action, targetType ?? null, targetId != null ? String(targetId) : null, detail ? JSON.stringify(detail) : null, ip ?? null, new Date().toISOString());
}
