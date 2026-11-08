import { useState } from 'react';
import { api, fmtDateTime, fmtMoney } from '../api';
import { Empty, Loading, Pager, StatusTag, useAsync } from '../components/ui';

export function Repayments() {
  const [page, setPage] = useState(1);
  const { data, loading } = useAsync<any>(() => api.get(`/api/admin/repayments?page=${page}&size=20`), [page]);

  const total = data?.list?.reduce((s: number, r: any) => s + r.amountCents, 0) ?? 0;

  return (
    <div className="card">
      <div className="card-head">
        <h3>还款流水</h3>
        <div className="spacer" />
        <span className="tiny">本页合计 {fmtMoney(total)}</span>
      </div>
      {loading ? (
        <Loading />
      ) : !data?.list?.length ? (
        <Empty text="暂无还款记录" />
      ) : (
        <>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>还款单号</th>
                  <th>借款单号</th>
                  <th>用户</th>
                  <th>类型</th>
                  <th>还款金额</th>
                  <th>本金</th>
                  <th>利息</th>
                  <th>罚息</th>
                  <th>状态</th>
                  <th>还款时间</th>
                </tr>
              </thead>
              <tbody>
                {data.list.map((r: any) => (
                  <tr key={r.id}>
                    <td className="mono">{r.repaymentNo}</td>
                    <td className="mono">{r.loanNo}</td>
                    <td>
                      {r.name ?? '--'} <span className="tiny">{r.phone}</span>
                    </td>
                    <td>{r.type === 'settle' ? '提前结清' : '按期还款'}</td>
                    <td style={{ fontWeight: 600 }}>{fmtMoney(r.amountCents)}</td>
                    <td>{fmtMoney(r.principalCents)}</td>
                    <td>{fmtMoney(r.interestCents)}</td>
                    <td style={{ color: r.penaltyCents ? '#e5484d' : undefined }}>{fmtMoney(r.penaltyCents)}</td>
                    <td>
                      <StatusTag status={r.status} />
                    </td>
                    <td className="muted small">{fmtDateTime(r.paidAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pager total={data.total} page={page} size={20} onChange={setPage} />
        </>
      )}
    </div>
  );
}
