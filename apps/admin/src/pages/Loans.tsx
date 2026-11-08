import { useState } from 'react';
import { api, fmtDate, fmtDateTime, fmtMoney, fmtMoneyInt, fmtRate } from '../api';
import { Empty, Loading, Modal, Pager, StatusTag, useAsync, useToast } from '../components/ui';

const TABS = [
  { key: '', label: '全部' },
  { key: 'reviewing', label: '审核中' },
  { key: 'active', label: '还款中' },
  { key: 'overdue', label: '已逾期' },
  { key: 'settled', label: '已结清' },
  { key: 'failed', label: '失败' },
];

export function Loans() {
  const [status, setStatus] = useState('');
  const [keyword, setKeyword] = useState('');
  const [page, setPage] = useState(1);
  const [detailId, setDetailId] = useState<number | null>(null);
  const { toast, toastNode } = useToast();
  const { data, loading, reload } = useAsync<any>(
    () => api.get(`/api/admin/loans?status=${status}&keyword=${encodeURIComponent(keyword)}&page=${page}&size=20`),
    [status, page]
  );

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
          <input
            className="input"
            placeholder="搜索借款单号 / 手机号"
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                setPage(1);
                reload();
              }
            }}
            style={{ width: 220 }}
          />
          <button
            className="btn btn-ghost btn-sm"
            onClick={() => {
              setPage(1);
              reload();
            }}
          >
            搜索
          </button>
        </div>
        {loading ? (
          <Loading />
        ) : !data?.list?.length ? (
          <Empty text="暂无借款订单" />
        ) : (
          <>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>借款单号</th>
                    <th>用户</th>
                    <th>本金</th>
                    <th>期限</th>
                    <th>年化(IRR)</th>
                    <th>剩余本金</th>
                    <th>状态</th>
                    <th>放款时间</th>
                    <th style={{ textAlign: 'right' }}>操作</th>
                  </tr>
                </thead>
                <tbody>
                  {data.list.map((r: any) => (
                    <tr key={r.id}>
                      <td className="mono">{r.loanNo}</td>
                      <td>
                        {r.name ?? '--'} <span className="tiny">{r.phone}</span>
                      </td>
                      <td>{fmtMoneyInt(r.principalCents)}</td>
                      <td>{r.termMonths} 期</td>
                      <td>{fmtRate(r.aprBp)}</td>
                      <td>{fmtMoneyInt(r.remainingPrincipalCents)}</td>
                      <td>
                        <StatusTag status={r.status} />
                        {r.status === 'overdue' && <span className="tiny" style={{ color: '#e5484d', marginLeft: 6 }}>{r.overdueDays}天</span>}
                      </td>
                      <td className="muted small">{r.disbursedAt ? fmtDateTime(r.disbursedAt) : '--'}</td>
                      <td style={{ textAlign: 'right' }}>
                        <button className="btn btn-ghost btn-sm" onClick={() => setDetailId(r.id)}>
                          详情
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pager total={data.total} page={page} size={20} onChange={setPage} />
          </>
        )}
      </div>

      {detailId && (
        <LoanDetail
          id={detailId}
          onClose={() => setDetailId(null)}
          onDone={(msg) => {
            setDetailId(null);
            toast(msg);
            reload();
          }}
        />
      )}
    </>
  );
}

function LoanDetail({ id, onClose, onDone }: { id: number; onClose: () => void; onDone: (m: string) => void }) {
  const { data, loading, reload } = useAsync<any>(() => api.get(`/api/admin/loans/${id}`), [id]);
  const [busy, setBusy] = useState(false);

  const act = async (path: string, body?: unknown) => {
    setBusy(true);
    try {
      await api.post(path, body);
      onDone('操作成功');
    } catch (e: any) {
      onDone(e.message ?? '操作失败');
    } finally {
      setBusy(false);
    }
  };

  const l = data?.loan;
  return (
    <Modal
      title={`借款详情 ${l?.loanNo ?? ''}`}
      onClose={onClose}
      width={780}
      footer={
        l && ['reviewing', 'disbursing'].includes(l.status) ? (
          <>
            <button className="btn btn-danger" disabled={busy} onClick={() => act(`/api/admin/loans/${id}/reject`, { reason: '人工审核未通过' })}>
              拒绝放款
            </button>
            <button className="btn btn-primary" disabled={busy} onClick={() => act(`/api/admin/loans/${id}/disburse`)}>
              确认放款
            </button>
          </>
        ) : (
          <button className="btn btn-ghost" onClick={onClose}>
            关闭
          </button>
        )
      }
    >
      {loading || !l ? (
        <Loading />
      ) : (
        <>
          <dl className="kv">
            <dt>用户</dt>
            <dd>
              {l.name} · {l.phone}
            </dd>
            <dt>借款本金</dt>
            <dd>{fmtMoney(l.principalCents)}</dd>
            <dt>期限 / 利率</dt>
            <dd>
              {l.termMonths} 期 · 合同年利率 {fmtRate(l.rateBp)} · 综合年化 {fmtRate(l.aprBp)}
            </dd>
            <dt>总利息 / 总应还</dt>
            <dd>
              {fmtMoney(l.totalInterestCents)} / {fmtMoney(l.totalRepayCents)}
            </dd>
            <dt>状态</dt>
            <dd>
              <StatusTag status={l.status} />
              {l.failCode && <span className="tiny" style={{ marginLeft: 8 }}>{l.failCode} {l.failReason}</span>}
            </dd>
            <dt>放款时间</dt>
            <dd>{l.disbursedAt ? fmtDateTime(l.disbursedAt) : '--'}</dd>
            <dt>首期还款日</dt>
            <dd>{l.firstDueDate ?? '--'}</dd>
            <dt>合同编号</dt>
            <dd className="mono">{l.contractNo}</dd>
          </dl>

          <div style={{ fontWeight: 600, margin: '20px 0 10px' }}>还款计划</div>
          <div className="table-wrap" style={{ border: '1px solid #eceff3', borderRadius: 10 }}>
            <table>
              <thead>
                <tr>
                  <th>期次</th>
                  <th>应还日</th>
                  <th>本金</th>
                  <th>利息</th>
                  <th>应还</th>
                  <th>已还本金</th>
                  <th>罚息</th>
                  <th>状态</th>
                </tr>
              </thead>
              <tbody>
                {(data.schedules ?? []).map((s: any) => (
                  <tr key={s.id}>
                    <td>{s.period_no}</td>
                    <td>{fmtDate(s.due_date)}</td>
                    <td>{fmtMoney(s.principal_cents)}</td>
                    <td>{fmtMoney(s.interest_cents)}</td>
                    <td>{fmtMoney(s.total_cents)}</td>
                    <td>{fmtMoney(s.paid_principal_cents)}</td>
                    <td style={{ color: s.penalty_cents ? '#e5484d' : undefined }}>{fmtMoney(s.penalty_cents)}</td>
                    <td>
                      <StatusTag status={s.status} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {!!data.repayments?.length && (
            <>
              <div style={{ fontWeight: 600, margin: '20px 0 10px' }}>还款流水</div>
              <div className="table-wrap" style={{ border: '1px solid #eceff3', borderRadius: 10 }}>
                <table>
                  <thead>
                    <tr>
                      <th>还款单号</th>
                      <th>类型</th>
                      <th>金额</th>
                      <th>本金</th>
                      <th>利息</th>
                      <th>罚息</th>
                      <th>时间</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.repayments.map((r: any) => (
                      <tr key={r.id}>
                        <td className="mono">{r.repayment_no}</td>
                        <td>{r.type === 'settle' ? '提前结清' : '按期还款'}</td>
                        <td>{fmtMoney(r.amount_cents)}</td>
                        <td>{fmtMoney(r.principal_cents)}</td>
                        <td>{fmtMoney(r.interest_cents)}</td>
                        <td>{fmtMoney(r.penalty_cents)}</td>
                        <td className="muted small">{fmtDateTime(r.paid_at)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </>
      )}
    </Modal>
  );
}
