import { useState } from 'react';
import { api, fmtDate, fmtMoney } from '../api';
import { Empty, Loading, Modal, useAsync, useToast } from '../components/ui';

export function Marketing() {
  const { data, loading, reload } = useAsync<any>(() => api.get('/api/admin/coupons'), []);
  const { toast, toastNode } = useToast();
  const [creating, setCreating] = useState(false);

  const toggle = async (c: any) => {
    try {
      await api.patch(`/api/admin/coupons/${c.id}`, { status: c.status === 'active' ? 'inactive' : 'active' });
      toast('状态已更新');
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
          <span className="small muted">优惠券与活动配置</span>
          <div className="spacer" />
          <button className="btn btn-primary btn-sm" onClick={() => setCreating(true)}>
            新建优惠券
          </button>
        </div>
        {loading ? (
          <Loading />
        ) : !data?.list?.length ? (
          <Empty text="暂无优惠券" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>编码</th>
                  <th>名称</th>
                  <th>类型</th>
                  <th>优惠力度</th>
                  <th>门槛</th>
                  <th>有效期</th>
                  <th>已用/总量</th>
                  <th>状态</th>
                  <th style={{ textAlign: 'right' }}>操作</th>
                </tr>
              </thead>
              <tbody>
                {data.list.map((c: any) => (
                  <tr key={c.id}>
                    <td className="mono">{c.code}</td>
                    <td>{c.name}</td>
                    <td>{c.type === 'cash' ? '现金满减' : '降息券'}</td>
                    <td>{c.type === 'cash' ? fmtMoney(c.amount_cents) : `${(c.rate_off_bp / 100).toFixed(2)}% 降息`}</td>
                    <td className="muted">{c.min_amount_cents ? fmtMoney(c.min_amount_cents) : '无门槛'}</td>
                    <td className="muted small">
                      {fmtDate(c.valid_from)} ~ {fmtDate(c.valid_to)}
                    </td>
                    <td>
                      {c.used_qty}/{c.total_qty || '不限'}
                    </td>
                    <td>{c.status === 'active' ? <span className="tag tag-success">生效中</span> : <span className="tag tag-gray">已停用</span>}</td>
                    <td style={{ textAlign: 'right' }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => toggle(c)}>
                        {c.status === 'active' ? '停用' : '启用'}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {creating && (
        <CreateCoupon
          onClose={() => setCreating(false)}
          onDone={(msg) => {
            setCreating(false);
            toast(msg);
            reload();
          }}
        />
      )}
    </>
  );
}

function CreateCoupon({ onClose, onDone }: { onClose: () => void; onDone: (m: string) => void }) {
  const today = new Date();
  const plus = (d: number) => {
    const x = new Date(today);
    x.setDate(x.getDate() + d);
    return x.toISOString().slice(0, 10);
  };
  const [form, setForm] = useState({
    code: '',
    name: '',
    type: 'cash',
    amount: '20',
    rateOff: '1',
    minAmount: '1000',
    termLimit: '0',
    validFrom: plus(0),
    validTo: plus(90),
    totalQty: '1000',
  });
  const [busy, setBusy] = useState(false);
  const set = (k: string, v: string) => setForm((f) => ({ ...f, [k]: v }));

  const submit = async () => {
    if (!form.code || !form.name) return onDone('请填写编码与名称');
    setBusy(true);
    try {
      await api.post('/api/admin/coupons', {
        code: form.code.toUpperCase(),
        name: form.name,
        type: form.type,
        amountCents: form.type === 'cash' ? Math.round(Number(form.amount) * 100) : 0,
        rateOffBp: form.type === 'rate' ? Math.round(Number(form.rateOff) * 100) : 0,
        minAmountCents: Math.round(Number(form.minAmount || 0) * 100),
        termLimit: Number(form.termLimit || 0),
        validFrom: form.validFrom,
        validTo: form.validTo,
        totalQty: Number(form.totalQty || 0),
      });
      onDone('优惠券已创建');
    } catch (e: any) {
      onDone(e.message ?? '创建失败');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      title="新建优惠券"
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose}>
            取消
          </button>
          <button className="btn btn-primary" disabled={busy} onClick={submit}>
            创建
          </button>
        </>
      }
    >
      <div className="grid grid-2">
        <div className="field">
          <label>券编码</label>
          <input className="input" placeholder="如 NEW30" value={form.code} onChange={(e) => set('code', e.target.value)} />
        </div>
        <div className="field">
          <label>券名称</label>
          <input className="input" placeholder="如 新客立减 30 元" value={form.name} onChange={(e) => set('name', e.target.value)} />
        </div>
        <div className="field">
          <label>类型</label>
          <select className="select" value={form.type} onChange={(e) => set('type', e.target.value)}>
            <option value="cash">现金满减</option>
            <option value="rate">降息券</option>
          </select>
        </div>
        {form.type === 'cash' ? (
          <div className="field">
            <label>减免金额（元）</label>
            <input className="input" value={form.amount} onChange={(e) => set('amount', e.target.value)} />
          </div>
        ) : (
          <div className="field">
            <label>降息幅度（%）</label>
            <input className="input" value={form.rateOff} onChange={(e) => set('rateOff', e.target.value)} />
          </div>
        )}
        <div className="field">
          <label>使用门槛（元）</label>
          <input className="input" value={form.minAmount} onChange={(e) => set('minAmount', e.target.value)} />
        </div>
        <div className="field">
          <label>限定期限（0 = 不限）</label>
          <input className="input" value={form.termLimit} onChange={(e) => set('termLimit', e.target.value)} />
        </div>
        <div className="field">
          <label>生效日期</label>
          <input className="input" type="date" value={form.validFrom} onChange={(e) => set('validFrom', e.target.value)} />
        </div>
        <div className="field">
          <label>失效日期</label>
          <input className="input" type="date" value={form.validTo} onChange={(e) => set('validTo', e.target.value)} />
        </div>
        <div className="field">
          <label>发放总量</label>
          <input className="input" value={form.totalQty} onChange={(e) => set('totalQty', e.target.value)} />
        </div>
      </div>
      <div className="tiny" style={{ marginTop: 12 }}>
        现金券从末期利息中抵扣；降息券直接下调合同年利率，最低 9%。
      </div>
    </Modal>
  );
}
