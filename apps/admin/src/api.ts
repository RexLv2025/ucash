const TOKEN_KEY = 'ucash.admin.token';

export class ApiError extends Error {
  code: number;
  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}
export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

async function request<T = any>(method: string, path: string, body?: unknown): Promise<T> {
  const token = getToken();
  const res = await fetch(path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  if (json && json.code === 0) return json.data as T;
  if (json && json.code === 1002) {
    setToken(null);
    window.location.hash = '#/login';
  }
  throw new ApiError(json?.code ?? 9001, json?.message ?? '请求失败');
}

export const api = {
  get: <T = any>(path: string) => request<T>('GET', path),
  post: <T = any>(path: string, body?: unknown) => request<T>('POST', path, body),
  patch: <T = any>(path: string, body?: unknown) => request<T>('PATCH', path, body),
  put: <T = any>(path: string, body?: unknown) => request<T>('PUT', path, body),
};

export const fmtMoney = (cents: number | null | undefined, symbol = true) => {
  const v = (cents ?? 0) / 100;
  const s = v.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return symbol ? `¥${s}` : s;
};
export const fmtMoneyInt = (cents: number | null | undefined) => {
  const v = (cents ?? 0) / 100;
  return `¥${v.toLocaleString('zh-CN', { maximumFractionDigits: 0 })}`;
};
export const fmtRate = (bp: number | null | undefined) => `${((bp ?? 0) / 100).toFixed(2)}%`;
export const fmtDate = (iso?: string | null) => (iso ? iso.slice(0, 10) : '--');
export const fmtDateTime = (iso?: string | null) => (iso ? iso.slice(0, 16).replace('T', ' ') : '--');

export const STATUS_TEXT: Record<string, string> = {
  reviewing: '审核中',
  disbursing: '放款中',
  active: '还款中',
  overdue: '已逾期',
  settled: '已结清',
  rejected: '未通过',
  failed: '放款失败',
  unpaid: '待还款',
  paid: '已还清',
  partial: '部分还款',
  approved: '已通过',
  manual: '待人工',
  submitted: '已提交',
  inactive: '已停用',
};
