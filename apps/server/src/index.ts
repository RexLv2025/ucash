import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import cron from 'node-cron';
import { ZodError } from 'zod';
import { ApiError, ErrCode, fail } from './lib/http.js';
import { authRouter } from './routes/auth.js';
import { appRouter } from './routes/app.js';
import { adminRouter } from './routes/admin.js';
import { markOverdue } from './services/repay.js';
import { sweepDisbursing } from './services/loan.js';
import { notify } from './services/notify.js';
import { db } from './db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = Number(process.env.PORT || 4000);

app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use((req, _res, next) => {
  if (req.path.startsWith('/api')) {
    // eslint-disable-next-line no-console
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  }
  next();
});

app.get('/health', (_req, res) => res.json({ ok: true, service: 'ucash-server', version: '2.4.0' }));

app.use('/api/auth', authRouter);
app.use('/api/admin', adminRouter);
app.use('/api', appRouter);

// 生产环境托管 Admin 构建产物
const adminDist = path.join(__dirname, '..', '..', 'admin', 'dist');
app.use('/admin', express.static(adminDist));
app.get('/admin/*', (_req, res) => res.sendFile(path.join(adminDist, 'index.html')));

app.use((req, res) => fail(res, ErrCode.NOT_FOUND, `接口不存在: ${req.method} ${req.path}`));

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (err instanceof ZodError) {
    const msg = err.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    return fail(res, ErrCode.PARAM, msg || '参数有误');
  }
  if (err instanceof ApiError) return fail(res, err.code, err.message, err.data);
  // eslint-disable-next-line no-console
  console.error('[unhandled]', err);
  return fail(res, ErrCode.SYSTEM, err?.message || '系统繁忙，请稍后重试');
});

// 启动补偿：处理中断的放款任务
sweepDisbursing();

// 每日 00:05 计提逾期
cron.schedule('5 0 * * *', () => {
  try {
    const r = markOverdue();
    // eslint-disable-next-line no-console
    console.log('[cron] overdue scan', r);
  } catch (e) {
    // eslint-disable-next-line no-console
    console.error('[cron] overdue scan failed', e);
  }
});

app.listen(PORT, '0.0.0.0', () => {
  // eslint-disable-next-line no-console
  console.log(`UCash API ready: http://localhost:${PORT}  (admin: http://localhost:${PORT}/admin)`);
  // eslint-disable-next-line no-console
  console.log(`DB: ${process.env.DB_PATH || 'apps/server/data/ucash.db'}`);
});
