import { useState } from 'react';
import { api, fmtDate, fmtDateTime, fmtMoney } from '../api';
import { Empty, Loading, Pager, StatusTag, useAsync, useToast } from '../components/ui';

const TABS = [
  { key: '', label: '全部' },
  { key: 'unpaid', label: '待还' },
  { key: 'overdue', label: '逾期' },
  { key: 'paid', label: '已还' },
];

export function Bills() {
  const [status, setStatus] = useState('overdue');
  const [page, setPage] = useState(1);
  const { toast, toastNode } = useToast();
  const { data, loading, reload } = useAsync<any>(() => api.get(`/api/admin/bills?status=${status}&page=${page}&size=20`), [status, page]);

  const scan = async () => {
    try {
      const r = await api.post('/api/admin/bills/overdue-scan');
      toast(`逾期扫描完成，处理 ${r.affected} 期账单`);
      reload();
    } catch (e: any) {
      toast(e.message ?? '扫描失败', true);
    }
  };

  const waive = async (id: number) => {
    if (!confirm('确认减免该期罚息？此操作将写入审计日志。')) return;
    try {
      await api.post(`/api/admin/bills/${id}/penalty-waive`);
      toast('罚息已减免');
      reload();
    } catch (e: any) {
      toast(e.message ?? '操作失败', true);
    }
  };

  return (
    <>
      {toastNode}
      <div className="card">
        <div className="toolbar">
          {TABS.map((t) => (
            <button
              key={t.key}
              className={`btn ${status === t.key ? 'btn-navy' : 'btn-ghost'} btn-sm`}
              onClick={() => {
                setStatus(t.key);
                setPage(1);
              }}
            >
              {t.label}
            </button>
          ))}
          <div className="spacer" />
          <button className="btn btn-primary btn-sm" onClick={scan}>
            执行逾期扫描
          </button>
          <button className="btn btn-ghost btn-sm" onClick={reload}>
            刷新
          </button>
        </div>
        {loading ? (
          <Loading />
        ) : !data?.list?.length ? (
          <Empty text="暂无账单数据" />
        ) : (
          <>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>借款单号</th>
                    <th>用户</th>
                    <th>期次</th>
                    <th>应还日</th>
                    <th>应还本金</th>
                    <th>应还利息</th>
                    <th>已还</th>
                    <th>罚息</th>
                    <th>状态</th>
                    <th style={{ textAlign: 'right' }}>操作</th>
                  </tr>
                </thead>
                <tbody>
                  {data.list.map((r: any) => {
                    const paid = r.paidPrincipalCents + r.paidInterestCents;
                    const overdue = r.status === 'overdue';
                    return (
                      <tr key={r.id}>
                        <td className="mono">{r.loanNo}</td>
                        <td>
                          {r.name ?? '--'} <span className="tiny">{r.phone}</span>
                        </td>
                        <td>{r.periodNo}</td>
                        <td className={overdue ? '' : 'muted'} style={overdue ? { color: '#e5484d', fontWeight: 500 } : undefined}>
                          {fmtDate(r.dueDate)}
                        </td>
                        <td>{fmtMoney(r.principalCents)}</td>
                        <td>{fmtMoney(r.interestCents)}</td>
                        <td>{fmtMoney(paid)}</td>
                        <td style={{ color: r.penaltyCents ? '#e5484d' : undefined }}>{fmtMoney(r.penaltyCents)}</td>
                        <td>
                          <StatusTag status={r.status} />
                        </td>
                        <td style={{ textAlign: 'right' }}>
                          {overdue && r.penaltyCents > 0 ? (
                            <button className="btn btn-danger btn-sm" onClick={() => waive(r.id)}>
                              减免罚息
                            </button>
                          ) : (
                            <span className="tiny">{r.paidAt ? fmtDateTime(r.paidAt) : '--'}</span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <Pager total={data.total} page={page} size={20} onChange={setPage} />
          </>
        )}
      </div>
    </>
  );
}
