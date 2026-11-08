import { useState } from 'react';
import { api, fmtDate, fmtDateTime, fmtMoney, fmtMoneyInt, fmtRate } from '../api';
import { Empty, Loading, Modal, Pager, StatusTag, useAsync, useToast } from '../components/ui';

const TABS = [
  { key: '', label: '全部' },
  { key: 'manual', label: '待人工' },
  { key: 'submitted', label: '已提交' },
  { key: 'approved', label: '已通过' },
  { key: 'rejected', label: '已拒绝' },
];

export function Credit() {
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const [detailId, setDetailId] = useState<number | null>(null);
  const { toast, toastNode } = useToast();
  const { data, loading, reload } = useAsync<any>(
    () => api.get(`/api/admin/credit-applications?status=${status}&page=${page}&size=20`),
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
          <button className="btn btn-ghost btn-sm" onClick={reload}>
            刷新
          </button>
        </div>
        {loading ? (
          <Loading />
        ) : !data?.list?.length ? (
          <Empty text="暂无授信申请" />
        ) : (
          <>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>申请编号</th>
                    <th>用户</th>
                    <th>手机号</th>
                    <th>申请金额</th>
                    <th>评分</th>
                    <th>状态</th>
                    <th>申请时间</th>
                    <th style={{ textAlign: 'right' }}>操作</th>
                  </tr>
                </thead>
                <tbody>
                  {data.list.map((r: any) => (
                    <tr key={r.id}>
                      <td className="mono">CR{String(r.id).padStart(6, '0')}</td>
                      <td>{r.name ?? '未实名'}</td>
                      <td className="mono">{r.phone}</td>
                      <td>{fmtMoneyInt(r.applyAmountCents)}</td>
                      <td>
                        <span style={{ color: r.score >= 700 ? '#12b76a' : r.score >= 640 ? '#b97b18' : '#e5484d', fontWeight: 600 }}>{r.score ?? '--'}</span>
                      </td>
                      <td>
                        <StatusTag status={r.status} />
                      </td>
                      <td className="muted small">{fmtDateTime(r.createdAt)}</td>
                      <td style={{ textAlign: 'right' }}>
                        <button className="btn btn-ghost btn-sm" onClick={() => setDetailId(r.id)}>
                          查看 / 审批
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
        <CreditDetail
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

function CreditDetail({ id, onClose, onDone }: { id: number; onClose: () => void; onDone: (msg: string) => void }) {
  const { data, loading } = useAsync<any>(() => api.get(`/api/admin/credit-applications/${id}`), [id]);
  const [limit, setLimit] = useState<string>('');
  const [rate, setRate] = useState<string>('');
  const [reason, setReason] = useState('综合评估未达标，建议 3 个月后重试');
  const [busy, setBusy] = useState(false);

  const submit = async (pass: boolean) => {
    setBusy(true);
    try {
      await api.post(`/api/admin/credit-applications/${id}/review`, {
        pass,
        limitCents: limit ? Math.round(Number(limit) * 100) : undefined,
        rateBp: rate ? Math.round(Number(rate) * 100) : undefined,
        reason: pass ? undefined : reason,
      });
      onDone(pass ? '已通过并激活额度' : '已拒绝该申请');
    } catch (e: any) {
      onDone(e.message ?? '操作失败');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      title={`授信申请 CR${String(id).padStart(6, '0')}`}
      onClose={onClose}
      width={720}
      footer={
        data?.status && ['manual', 'submitted', 'reviewing'].includes(data.status) ? (
          <>
            <button className="btn btn-danger" disabled={busy} onClick={() => submit(false)}>
              拒绝
            </button>
            <button className="btn btn-primary" disabled={busy} onClick={() => submit(true)}>
              通过并激活额度
            </button>
          </>
        ) : (
          <button className="btn btn-ghost" onClick={onClose}>
            关闭
          </button>
        )
      }
    >
      {loading || !data ? (
        <Loading />
      ) : (
        <>
          <dl className="kv" style={{ marginBottom: 18 }}>
            <dt>用户</dt>
            <dd>
              {data.name} · {data.phone}
            </dd>
            <dt>身份证</dt>
            <dd className="mono">{data.idCardMask ?? '--'}</dd>
            <dt>申请金额</dt>
            <dd>{fmtMoney(data.applyAmountCents)}</dd>
            <dt>当前状态</dt>
            <dd>
              <StatusTag status={data.status} />
            </dd>
            <dt>模型评分</dt>
            <dd style={{ fontWeight: 600 }}>{data.score ?? '--'}</dd>
            <dt>建议额度</dt>
            <dd>{data.approvedLimitCents ? fmtMoney(data.approvedLimitCents) : '--'}</dd>
            <dt>申请时间</dt>
            <dd>{fmtDateTime(data.createdAt)}</dd>
          </dl>

          <div style={{ fontWeight: 600, marginBottom: 8 }}>风控命中详情</div>
          {data.risk?.hitRules?.length ? (
            data.risk.hitRules.map((h: any, i: number) => (
              <div className="risk-hit" key={i}>
                {h.name}（{h.field} 实际 {String(h.actual)}，规则 {h.expected}）→ {h.action === 'reject' ? '拒绝' : h.action === 'manual' ? '转人工' : '加减分'}
              </div>
            ))
          ) : (
            <div className="tiny" style={{ marginBottom: 8 }}>
              未命中拒绝类规则
            </div>
          )}

          {data.risk?.snapshot && (
            <div style={{ background: '#f7f8fa', borderRadius: 10, padding: 12, marginTop: 10 }} className="small muted">
              快照：年龄 {data.risk.snapshot.age} · 人脸 {data.risk.snapshot.faceScore} · 月收入 {fmtMoneyInt(data.risk.snapshot.monthlyIncomeCents)} · 多头{' '}
              {data.risk.snapshot.multiLoanCount} · 在贷 {data.risk.snapshot.activeLoans} 笔 · 公积金 {data.risk.snapshot.fundVerified ? '已认证' : '未认证'}
            </div>
          )}

          {['manual', 'submitted', 'reviewing'].includes(data.status) && (
            <div style={{ marginTop: 20, paddingTop: 18, borderTop: '1px solid #eceff3' }}>
              <div style={{ fontWeight: 600, marginBottom: 12 }}>人工审批</div>
              <div className="grid grid-2">
                <div className="field">
                  <label>批准额度（元）</label>
                  <input className="input" placeholder={String((data.approvedLimitCents ?? 500000) / 100)} value={limit} onChange={(e) => setLimit(e.target.value)} />
                </div>
                <div className="field">
                  <label>合同年利率（%）</label>
                  <input className="input" placeholder={String((data.interestRateBp ?? 1800) / 100)} value={rate} onChange={(e) => setRate(e.target.value)} />
                </div>
              </div>
              <div className="field" style={{ marginTop: 12 }}>
                <label>拒绝原因（拒绝时填写）</label>
                <input className="input" value={reason} onChange={(e) => setReason(e.target.value)} />
              </div>
              <div className="tiny" style={{ marginTop: 8 }}>
                留空则沿用系统建议：额度 {fmtMoney(data.approvedLimitCents ?? 0)}，利率 {fmtRate(data.interestRateBp ?? 0)}。当前授信定价区间 9%–24%。
              </div>
            </div>
          )}
        </>
      )}
    </Modal>
  );
}
