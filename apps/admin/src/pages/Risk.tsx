import { useState } from 'react';
import { api, fmtDateTime } from '../api';
import { Empty, Loading, useAsync, useToast } from '../components/ui';

export function Risk() {
  const [tab, setTab] = useState<'rules' | 'decisions'>('rules');
  const { toast, toastNode } = useToast();
  const rules = useAsync<any>(() => api.get('/api/admin/risk-rules'), []);
  const decisions = useAsync<any>(() => api.get('/api/admin/risk-decisions'), []);

  const toggle = async (r: any) => {
    try {
      await api.patch(`/api/admin/risk-rules/${r.id}`, { enabled: !r.enabled });
      toast(r.enabled ? '规则已停用' : '规则已启用');
      rules.reload();
    } catch (e: any) {
      toast(e.message ?? '操作失败', true);
    }
  };

  return (
    <>
      {toastNode}
      <div className="card">
        <div className="toolbar">
          <button className={`btn ${tab === 'rules' ? 'btn-navy' : 'btn-ghost'} btn-sm`} onClick={() => setTab('rules')}>
            规则配置
          </button>
          <button className={`btn ${tab === 'decisions' ? 'btn-navy' : 'btn-ghost'} btn-sm`} onClick={() => setTab('decisions')}>
            决策记录
          </button>
          <div className="spacer" />
          <span className="tiny">规则调整实时生效，命中结果写入决策快照可回溯</span>
        </div>

        {tab === 'rules' ? (
          rules.loading ? (
            <Loading />
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>优先级</th>
                    <th>规则</th>
                    <th>字段</th>
                    <th>条件</th>
                    <th>动作</th>
                    <th>评分影响</th>
                    <th>状态</th>
                    <th style={{ textAlign: 'right' }}>操作</th>
                  </tr>
                </thead>
                <tbody>
                  {(rules.data?.list ?? []).map((r: any) => (
                    <tr key={r.id}>
                      <td className="mono">{r.priority}</td>
                      <td>{r.name}</td>
                      <td className="mono">{r.field}</td>
                      <td className="mono">
                        {r.operator} {r.value}
                      </td>
                      <td>
                        <span className={`tag ${r.action === 'reject' ? 'tag-danger' : r.action === 'manual' ? 'tag-warning' : 'tag-success'}`}>
                          {r.action === 'reject' ? '拒绝' : r.action === 'manual' ? '转人工' : '评分'}
                        </span>
                      </td>
                      <td className={r.score_delta === 0 ? 'muted' : r.score_delta > 0 ? '' : ''} style={{ color: r.score_delta > 0 ? '#12b76a' : r.score_delta < 0 ? '#e5484d' : undefined }}>
                        {r.score_delta > 0 ? `+${r.score_delta}` : r.score_delta}
                      </td>
                      <td>{r.enabled ? <span className="tag tag-success">启用</span> : <span className="tag tag-gray">停用</span>}</td>
                      <td style={{ textAlign: 'right' }}>
                        <button className="btn btn-ghost btn-sm" onClick={() => toggle(r)}>
                          {r.enabled ? '停用' : '启用'}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )
        ) : decisions.loading ? (
          <Loading />
        ) : !decisions.data?.list?.length ? (
          <Empty text="暂无决策记录" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>时间</th>
                  <th>用户</th>
                  <th>场景</th>
                  <th>评分</th>
                  <th>决策</th>
                  <th>命中规则</th>
                </tr>
              </thead>
              <tbody>
                {decisions.data.list.map((d: any) => (
                  <tr key={d.id}>
                    <td className="muted small">{fmtDateTime(d.createdAt)}</td>
                    <td className="mono">{d.phone}</td>
                    <td>{d.scene === 'credit' ? '授信' : '用信'}</td>
                    <td style={{ fontWeight: 600 }}>{d.score}</td>
                    <td>
                      <span className={`tag ${d.decision === 'approve' ? 'tag-success' : d.decision === 'reject' ? 'tag-danger' : 'tag-warning'}`}>
                        {d.decision === 'approve' ? '通过' : d.decision === 'reject' ? '拒绝' : '转人工'}
                      </span>
                    </td>
                    <td style={{ whiteSpace: 'normal', maxWidth: 320 }} className="small muted">
                      {d.hitRules?.length ? d.hitRules.map((h: any) => h.name).join('；') : '无'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}
