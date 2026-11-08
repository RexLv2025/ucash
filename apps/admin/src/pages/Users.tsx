import { useState } from 'react';
import { api, fmtDateTime, fmtMoney, fmtMoneyInt } from '../api';
import { Empty, Loading, Modal, Pager, useAsync, useToast } from '../components/ui';

export function Users() {
  const [keyword, setKeyword] = useState('');
  const [page, setPage] = useState(1);
  const [edit, setEdit] = useState<any | null>(null);
  const { toast, toastNode } = useToast();
  const { data, loading, reload } = useAsync<any>(
    () => api.get(`/api/admin/users?keyword=${encodeURIComponent(keyword)}&page=${page}&size=20`),
    [page]
  );

  return (
    <>
      {toastNode}
      <div className="card">
        <div className="toolbar">
          <input
            className="input"
            placeholder="搜索手机号 / 姓名 / 邀请码"
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                setPage(1);
                reload();
              }
            }}
            style={{ width: 240 }}
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
          <div className="spacer" />
          <span className="tiny">共 {data?.total ?? 0} 位用户</span>
        </div>
        {loading ? (
          <Loading />
        ) : !data?.list?.length ? (
          <Empty text="未找到用户" />
        ) : (
          <>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>用户</th>
                    <th>手机号</th>
                    <th>总额度</th>
                    <th>已用</th>
                    <th>在贷笔数</th>
                    <th>风险等级</th>
                    <th>状态</th>
                    <th>注册时间</th>
                    <th style={{ textAlign: 'right' }}>操作</th>
                  </tr>
                </thead>
                <tbody>
                  {data.list.map((u: any) => (
                    <tr key={u.id}>
                      <td>
                        {u.name ?? '未实名'} <span className="tiny">{u.idCardMask ?? ''}</span>
                      </td>
                      <td className="mono">{u.phone}</td>
                      <td>{fmtMoneyInt(u.creditLimitCents)}</td>
                      <td>{fmtMoneyInt(u.usedLimitCents)}</td>
                      <td>{u.activeLoans}</td>
                      <td>
                        <span className="tag">{u.riskLevel}</span>
                      </td>
                      <td>
                        {u.status === 'active' ? (
                          <span className="tag tag-success">正常</span>
                        ) : u.status === 'frozen' ? (
                          <span className="tag tag-danger">冻结</span>
                        ) : (
                          <span className="tag tag-gray">注销</span>
                        )}
                        {u.blacklist && <span className="tag tag-danger" style={{ marginLeft: 6 }}>黑名单</span>}
                      </td>
                      <td className="muted small">{fmtDateTime(u.createdAt)}</td>
                      <td style={{ textAlign: 'right' }}>
                        <button className="btn btn-ghost btn-sm" onClick={() => setEdit(u)}>
                          管理
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

      {edit && (
        <UserManage
          user={edit}
          onClose={() => setEdit(null)}
          onDone={(msg) => {
            setEdit(null);
            toast(msg);
            reload();
          }}
        />
      )}
    </>
  );
}

function UserManage({ user, onClose, onDone }: { user: any; onClose: () => void; onDone: (m: string) => void }) {
  const [limit, setLimit] = useState(String(user.creditLimitCents / 100));
  const [busy, setBusy] = useState(false);

  const saveLimit = async () => {
    setBusy(true);
    try {
      await api.post(`/api/admin/users/${user.id}/limit`, { creditLimitCents: Math.round(Number(limit) * 100), reason: '后台人工调整' });
      onDone('额度已调整');
    } catch (e: any) {
      onDone(e.message ?? '操作失败');
    } finally {
      setBusy(false);
    }
  };

  const toggle = async (status: 'active' | 'frozen', blacklist?: boolean) => {
    setBusy(true);
    try {
      await api.post(`/api/admin/users/${user.id}/status`, { status, blacklist });
      onDone(status === 'frozen' ? '账户已冻结' : '账户已恢复');
    } catch (e: any) {
      onDone(e.message ?? '操作失败');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      title={`用户管理 · ${user.name ?? user.phone}`}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>
            关闭
          </button>
          <button className="btn btn-primary" disabled={busy} onClick={saveLimit}>
            保存额度
          </button>
        </>
      }
    >
      <dl className="kv" style={{ marginBottom: 20 }}>
        <dt>手机号</dt>
        <dd className="mono">{user.phone}</dd>
        <dt>总额度 / 已用</dt>
        <dd>
          {fmtMoney(user.creditLimitCents)} / {fmtMoney(user.usedLimitCents)}
        </dd>
        <dt>在贷</dt>
        <dd>
          {user.activeLoans} 笔 · {fmtMoney(user.inLoanCents)}
        </dd>
        <dt>状态</dt>
        <dd>{user.status === 'active' ? '正常' : user.status === 'frozen' ? '已冻结' : '已注销'}</dd>
      </dl>

      <div className="field" style={{ marginBottom: 16 }}>
        <label>调整总额度（元）</label>
        <input className="input" value={limit} onChange={(e) => setLimit(e.target.value)} />
      </div>

      <div className="row" style={{ gap: 10, flexWrap: 'wrap' }}>
        {user.status === 'active' ? (
          <button className="btn btn-danger" disabled={busy} onClick={() => toggle('frozen')}>
            冻结账户
          </button>
        ) : (
          <button className="btn btn-success" disabled={busy} onClick={() => toggle('active')}>
            恢复账户
          </button>
        )}
        <button className="btn btn-ghost" disabled={busy} onClick={() => toggle('active', true)}>
          加入黑名单
        </button>
        <button className="btn btn-ghost" disabled={busy} onClick={() => toggle('active', false)}>
          移出黑名单
        </button>
      </div>
      <div className="tiny" style={{ marginTop: 12 }}>
        高危操作（冻结、拉黑）将写入审计日志；调整额度会同步站内信通知用户。
      </div>
    </Modal>
  );
}
