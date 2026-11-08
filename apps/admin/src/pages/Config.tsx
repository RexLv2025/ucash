import { useEffect, useState } from 'react';
import { api, fmtDateTime } from '../api';
import { Empty, Loading, useAsync, useToast } from '../components/ui';

export function Config() {
  const { data, loading, reload } = useAsync<any>(() => api.get('/api/admin/settings'), []);
  const logs = useAsync<any>(() => api.get('/api/admin/audit-logs'), []);
  const { toast, toastNode } = useToast();
  const [form, setForm] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (data?.settings) setForm(data.settings);
  }, [data]);

  const set = (k: string, v: string) => setForm((f) => ({ ...f, [k]: v }));

  const save = async () => {
    setBusy(true);
    try {
      await api.put('/api/admin/settings', form);
      toast('配置已保存');
      reload();
    } catch (e: any) {
      toast(e.message ?? '保存失败', true);
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      {toastNode}
      <div className="grid grid-2" style={{ gridTemplateColumns: '1.1fr 1fr', alignItems: 'start' }}>
        <div className="card">
          <div className="card-head">
            <h3>运营参数</h3>
            <div className="spacer" />
            <button className="btn btn-primary btn-sm" disabled={busy} onClick={save}>
              保存配置
            </button>
          </div>
          <div className="card-pad">
            {loading ? (
              <Loading />
            ) : (
              <>
                <div className="grid grid-2">
                  <div className="field">
                    <label>客服热线</label>
                    <input className="input" value={form.service_phone ?? ''} onChange={(e) => set('service_phone', e.target.value)} />
                  </div>
                  <div className="field">
                    <label>服务时间</label>
                    <input className="input" value={form.service_time ?? ''} onChange={(e) => set('service_time', e.target.value)} />
                  </div>
                </div>
                <div className="field" style={{ marginTop: 14 }}>
                  <label>首页公告</label>
                  <textarea
                    className="input"
                    style={{ height: 72, padding: 10, resize: 'vertical' }}
                    value={form.notice ?? ''}
                    onChange={(e) => set('notice', e.target.value)}
                  />
                </div>
                <div className="field" style={{ marginTop: 14 }}>
                  <label>Banner 配置（JSON 数组）</label>
                  <textarea
                    className="input mono"
                    style={{ height: 120, padding: 10, resize: 'vertical' }}
                    value={form.banners ?? '[]'}
                    onChange={(e) => set('banners', e.target.value)}
                  />
                </div>
                <div className="field" style={{ marginTop: 14 }}>
                  <label>协议名称配置（JSON）</label>
                  <textarea
                    className="input mono"
                    style={{ height: 90, padding: 10, resize: 'vertical' }}
                    value={form.agreements ?? '{}'}
                    onChange={(e) => set('agreements', e.target.value)}
                  />
                </div>
                <div className="tiny" style={{ marginTop: 12 }}>
                  保存后 App 端下次进入首页即生效。配置变更会写入审计日志。
                </div>
              </>
            )}
          </div>
        </div>

        <div className="card">
          <div className="card-head">
            <h3>审计日志（最近 200 条）</h3>
            <div className="spacer" />
            <button className="btn btn-ghost btn-sm" onClick={() => logs.reload()}>
              刷新
            </button>
          </div>
          {logs.loading ? (
            <Loading />
          ) : !logs.data?.list?.length ? (
            <Empty text="暂无审计记录" />
          ) : (
            <div className="table-wrap" style={{ maxHeight: 520, overflowY: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th>时间</th>
                    <th>操作人</th>
                    <th>动作</th>
                    <th>对象</th>
                  </tr>
                </thead>
                <tbody>
                  {logs.data.list.map((l: any) => (
                    <tr key={l.id}>
                      <td className="muted small">{fmtDateTime(l.created_at)}</td>
                      <td>
                        {l.actor_type === 'admin' ? '管理员' : l.actor_type === 'user' ? '用户' : '系统'} #{l.actor_id ?? '-'}
                      </td>
                      <td className="mono small">{l.action}</td>
                      <td className="muted small">
                        {l.target_type ?? '-'} {l.target_id ?? ''}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
