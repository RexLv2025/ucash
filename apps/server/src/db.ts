import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
export const DB_PATH = process.env.DB_PATH || path.join(DATA_DIR, 'ucash.db');

if (!fs.existsSync(path.dirname(DB_PATH))) {
  fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
}

/**
 * 使用 Node 内置 node:sqlite（Node 22.5+ / 24 稳定），不依赖任何原生编译模块，
 * 避免 better-sqlite3 的 NODE_MODULE_VERSION ABI 不匹配问题。
 */
export const db = new DatabaseSync(DB_PATH);
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA foreign_keys = ON');
db.exec('PRAGMA busy_timeout = 5000');

const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
db.exec(schema);

let txDepth = 0;

/** 同步事务，支持嵌套（内层用 SAVEPOINT） */
export function tx<T>(fn: () => T): T {
  const depth = txDepth;
  const savepoint = `sp_${depth}`;
  db.exec(depth === 0 ? 'BEGIN IMMEDIATE' : `SAVEPOINT ${savepoint}`);
  txDepth = depth + 1;
  try {
    const result = fn();
    db.exec(depth === 0 ? 'COMMIT' : `RELEASE ${savepoint}`);
    return result;
  } catch (err) {
    try {
      db.exec(depth === 0 ? 'ROLLBACK' : `ROLLBACK TO ${savepoint}`);
    } catch {
      /* 回滚失败时保留原始异常 */
    }
    throw err;
  } finally {
    txDepth = depth;
  }
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

export function audit(
  actorType: string,
  actorId: number | null,
  action: string,
  targetType?: string,
  targetId?: string | number | null,
  detail?: unknown,
  ip?: string
) {
  db.prepare(
    `INSERT INTO audit_logs(actor_type, actor_id, action, target_type, target_id, detail, ip, created_at)
     VALUES(?,?,?,?,?,?,?,?)`
  ).run(
    actorType,
    actorId,
    action,
    targetType ?? null,
    targetId != null ? String(targetId) : null,
    detail ? JSON.stringify(detail) : null,
    ip ?? null,
    new Date().toISOString()
  );
}
