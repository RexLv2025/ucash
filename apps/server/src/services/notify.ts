import { db } from '../db.js';
import { nowIso } from '../lib/date.js';

export function notify(userId: number, type: string, title: string, content: string, bizNo?: string) {
  db.prepare(`INSERT INTO messages(user_id, type, title, content, biz_no, created_at) VALUES(?,?,?,?,?,?)`).run(
    userId,
    type,
    title,
    content,
    bizNo ?? null,
    nowIso()
  );
}
