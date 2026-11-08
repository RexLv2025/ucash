import React, { useEffect, useState } from 'react';
import { STATUS_TEXT } from '../api';

export function Modal({
  title,
  children,
  onClose,
  footer,
  width,
}: {
  title: string;
  children: React.ReactNode;
  onClose: () => void;
  footer?: React.ReactNode;
  width?: number;
}) {
  return (
    <div className="modal-mask" onClick={onClose}>
      <div className="modal" style={width ? { width } : undefined} onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <h3>{title}</h3>
          <div className="spacer" />
          <button className="btn btn-ghost btn-sm" onClick={onClose}>
            关闭
          </button>
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-foot">{footer}</div>}
      </div>
    </div>
  );
}

const DANGER = ['overdue', 'rejected', 'failed'];
const SUCCESS = ['settled', 'paid', 'approved', 'active'];
const WARNING = ['manual', 'unpaid', 'reviewing', 'disbursing', 'partial'];

export function StatusTag({ status }: { status: string }) {
  const cls = DANGER.includes(status) ? 'tag tag-danger' : SUCCESS.includes(status) ? 'tag tag-success' : WARNING.includes(status) ? 'tag tag-warning' : 'tag tag-gray';
  return <span className={cls}>{STATUS_TEXT[status] ?? status}</span>;
}

export function Pager({ total, page, size, onChange }: { total: number; page: number; size: number; onChange: (p: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / size));
  return (
    <div className="pager">
      <span>
        共 {total} 条 · 第 {page}/{pages} 页
      </span>
      <div className="spacer" />
      <button className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => onChange(page - 1)}>
        上一页
      </button>
      <button className="btn btn-ghost btn-sm" disabled={page >= pages} onClick={() => onChange(page + 1)}>
        下一页
      </button>
    </div>
  );
}

export function Empty({ text }: { text: string }) {
  return <div className="empty">{text}</div>;
}

export function Loading() {
  return <div className="loading">加载中…</div>;
}

export function useAsync<T>(fn: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const reload = () => {
    setLoading(true);
    fn()
      .then((d) => {
        setData(d);
        setError(null);
      })
      .catch((e) => setError(e.message ?? '加载失败'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return { data, loading, error, reload };
}

export function useToast() {
  const [msg, setMsg] = useState<{ text: string; error?: boolean } | null>(null);
  useEffect(() => {
    if (!msg) return;
    const t = setTimeout(() => setMsg(null), 2400);
    return () => clearTimeout(t);
  }, [msg]);
  const node = msg ? (
    <div
      style={{
        position: 'fixed',
        bottom: 28,
        left: '50%',
        transform: 'translateX(-50%)',
        background: msg.error ? '#e5484d' : '#0f2b5b',
        color: '#fff',
        padding: '10px 18px',
        borderRadius: 10,
        fontSize: 13,
        zIndex: 200,
        boxShadow: '0 8px 24px rgba(10,20,40,.25)',
      }}
    >
      {msg.text}
    </div>
  ) : null;
  return { toast: (text: string, error = false) => setMsg({ text, error }), toastNode: node };
}
