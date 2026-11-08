import { api, fmtMoneyInt } from '../api';
import { Loading, useAsync } from '../components/ui';

export function Dashboard() {
  const { data, loading, error } = useAsync<any>(() => api.get('/api/admin/dashboard'), []);

  if (loading) return <Loading />;
  if (error) return <div className="empty">{error}</div>;
  const d = data;
  const maxLoan = Math.max(...d.trend.map((t: any) => t.loanAmountCents), 1);

  return (
    <>
      <div className="grid grid-4">
        <div className="card stat">
          <div className="stat-label">今日新增用户</div>
          <div className="stat-value">{d.today.newUsers}</div>
          <div className="stat-foot">累计注册 {d.portfolio.totalUsers} 人</div>
        </div>
        <div className="card stat">
          <div className="stat-label">今日放款</div>
          <div className="stat-value">{fmtMoneyInt(d.today.loanAmountCents)}</div>
          <div className="stat-foot">{d.today.loanCount} 笔 · 户均 {d.today.loanCount ? fmtMoneyInt(d.today.loanAmountCents / d.today.loanCount) : '¥0'}</div>
        </div>
        <div className="card stat">
          <div className="stat-label">今日还款</div>
          <div className="stat-value">{fmtMoneyInt(d.today.repayAmountCents)}</div>
          <div className="stat-foot">{d.today.repayCount} 笔成功还款</div>
        </div>
        <div className="card stat">
          <div className="stat-label">待处理事项</div>
          <div className="stat-value" style={{ color: d.todo.pendingCredit + d.todo.pendingLoan > 0 ? '#e5484d' : undefined }}>
            {d.todo.pendingCredit + d.todo.pendingLoan}
          </div>
          <div className="stat-foot">
            授信审批 {d.todo.pendingCredit} · 放款审核 {d.todo.pendingLoan}
          </div>
        </div>
      </div>

      <div className="section-gap" />

      <div className="grid grid-4">
        <div className="card stat">
          <div className="stat-label">在贷余额</div>
          <div className="stat-value">{fmtMoneyInt(d.portfolio.balanceCents)}</div>
          <div className="stat-foot">放款本金 {fmtMoneyInt(d.portfolio.inLoanPrincipalCents)}</div>
        </div>
        <div className="card stat">
          <div className="stat-label">逾期率</div>
          <div className="stat-value" style={{ color: d.portfolio.overdueRate > 3 ? '#e5484d' : '#12b76a' }}>
            {d.portfolio.overdueRate}%
          </div>
          <div className="stat-foot">
            逾期 {d.portfolio.overdueCount} 期 · {fmtMoneyInt(d.portfolio.overdueAmountCents)}
          </div>
        </div>
        <div className="card stat">
          <div className="stat-label">授信通过率</div>
          <div className="stat-value">{d.portfolio.creditApprovalRate}%</div>
          <div className="stat-foot">累计申请 {d.today.creditApplications} 笔（今日）</div>
        </div>
        <div className="card stat">
          <div className="stat-label">结清率</div>
          <div className="stat-value">{d.portfolio.settleRate}%</div>
          <div className="stat-foot">已结清借据占比</div>
        </div>
      </div>

      <div className="section-gap" />

      <div className="grid grid-2" style={{ gridTemplateColumns: '1.4fr 1fr' }}>
        <div className="card">
          <div className="card-head">
            <h3>近 7 日放款趋势</h3>
            <div className="spacer" />
            <span className="tiny">单位：元</span>
          </div>
          <div className="card-pad">
            <div className="bar-chart">
              {d.trend.map((t: any) => (
                <div className="bar-col" key={t.date}>
                  <div className="tiny">{t.loanCount}</div>
                  <div className="bar" style={{ height: `${Math.max(3, (t.loanAmountCents / maxLoan) * 100)}%` }} />
                  <div className="bar-label">{t.date.slice(5)}</div>
                </div>
              ))}
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 10 }} className="tiny">
              <span>7 日累计放款 {fmtMoneyInt(d.trend.reduce((s: number, t: any) => s + t.loanAmountCents, 0))}</span>
              <span>7 日累计还款 {fmtMoneyInt(d.trend.reduce((s: number, t: any) => s + t.repayAmountCents, 0))}</span>
            </div>
          </div>
        </div>

        <div className="card">
          <div className="card-head">
            <h3>业务健康度</h3>
          </div>
          <div className="card-pad">
            <HealthRow label="逾期率（余额口径）" value={d.portfolio.overdueRate} target={3} suffix="%" good={d.portfolio.overdueRate <= 3} />
            <HealthRow label="授信通过率" value={d.portfolio.creditApprovalRate} target={35} suffix="%" good={d.portfolio.creditApprovalRate >= 30} />
            <HealthRow label="结清率" value={d.portfolio.settleRate} target={60} suffix="%" good={d.portfolio.settleRate >= 50} />
            <div style={{ marginTop: 18, padding: 12, background: '#f7f8fa', borderRadius: 10 }} className="small muted">
              提示：逾期率超过 3% 需启动催收专项；授信通过率低于 30% 需复核准入规则与流量质量。
            </div>
          </div>
        </div>
      </div>
    </>
  );
}

function HealthRow({ label, value, target, suffix, good }: { label: string; value: number; target: number; suffix: string; good: boolean }) {
  return (
    <div style={{ marginBottom: 16 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, marginBottom: 6 }}>
        <span className="muted">{label}</span>
        <span style={{ color: good ? '#12b76a' : '#e5484d', fontWeight: 600 }}>
          {value}
          {suffix}
        </span>
      </div>
      <div style={{ height: 6, background: '#f0f2f5', borderRadius: 4, overflow: 'hidden' }}>
        <div
          style={{
            width: `${Math.min(100, (value / Math.max(target * 2, 1)) * 100)}%`,
            height: '100%',
            background: good ? '#12b76a' : '#e5484d',
            borderRadius: 4,
          }}
        />
      </div>
      <div className="tiny" style={{ marginTop: 4 }}>
        参考阈值 {target}
        {suffix}
      </div>
    </div>
  );
}
