import React, { useEffect, useState } from 'react';
import { api, getToken, setToken } from './api';
import { Dashboard } from './pages/Dashboard';
import { Credit } from './pages/Credit';
import { Loans } from './pages/Loans';
import { Bills } from './pages/Bills';
import { Repayments } from './pages/Repayments';
import { Users } from './pages/Users';
import { Risk } from './pages/Risk';
import { Marketing } from './pages/Marketing';
import { Config } from './pages/Config';

type RouteKey = 'dashboard' | 'credit' | 'loans' | 'bills' | 'repayments' | 'users' | 'risk' | 'marketing' | 'config';

const MENU: { group: string; items: { key: RouteKey; label: string; icon: string }[] }[] = [
  { group: '概览', items: [{ key: 'dashboard', label: '工作台', icon: '▦' }] },
  {
    group: '业务管理',
    items: [
      { key: 'credit', label: '授信审批', icon: '✓' },
      { key: 'loans', label: '借款订单', icon: '¥' },
      { key: 'bills', label: '账单与逾期', icon: '▤' },
      { key: 'repayments', label: '还款流水', icon: '⇄' },
    ],
  },
  { group: '客户', items: [{ key: 'users', label: '用户管理', icon: '☺' }] },
  { group: '风控', items: [{ key: 'risk', label: '规则与决策', icon: '⚑' }] },
  {
    group: '运营',
    items: [
      { key: 'marketing', label: '优惠券', icon: '◎' },
      { key: 'config', label: '运营配置', icon: '⚙' },
    ],
  },
];

const TITLES: Record<RouteKey, string> = {
  dashboard: '工作台',
  credit: '授信审批',
  loans: '借款订单',
  bills: '账单与逾期台账',
  repayments: '还款流水',
  users: '用户管理',
  risk: '风控规则与决策',
  marketing: '优惠券管理',
  config: '运营配置',
};

function currentRoute(): RouteKey {
  const h = window.location.hash.replace('#/', '') as RouteKey;
  return (TITLES[h] ? h : 'dashboard') as RouteKey;
}

export default function App() {
  const [authed, setAuthed] = useState(Boolean(getToken()));
  const [route, setRoute] = useState<RouteKey>(currentRoute());
  const [admin, setAdmin] = useState<{ name: string; role: string } | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    const onHash = () => {
      setRoute(currentRoute());
      setAuthed(Boolean(getToken()));
    };
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  useEffect(() => {
    if (!authed) return;
    api
      .get('/api/admin/dashboard')
      .then(() => {
        const raw = localStorage.getItem('ucash.admin.profile');
        if (raw) setAdmin(JSON.parse(raw));
      })
      .catch(() => {});
  }, [authed]);

  if (!authed) return <Login onSuccess={() => setAuthed(true)} />;

  const go = (k: RouteKey) => {
    window.location.hash = `#/${k}`;
    setRoute(k);
    setRefreshKey((x) => x + 1);
  };

  const logout = () => {
    setToken(null);
    localStorage.removeItem('ucash.admin.profile');
    setAuthed(false);
    window.location.hash = '#/login';
  };

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-logo">U</div>
          <div>
            <div className="brand-name">UCash</div>
            <div className="brand-sub">运营管理后台 v2.4</div>
          </div>
        </div>
        <nav className="nav">
          {MENU.map((g) => (
            <div key={g.group}>
              <div className="nav-group">{g.group}</div>
              {g.items.map((it) => (
                <div key={it.key} className={`nav-item ${route === it.key ? 'active' : ''}`} onClick={() => go(it.key)}>
                  <span className="nav-icon">{it.icon}</span>
                  {it.label}
                </div>
              ))}
            </div>
          ))}
        </nav>
        <div className="sidebar-foot">© 2026 UCash · 仅限授权人员</div>
      </aside>
      <div className="main">
        <header className="topbar">
          <h1>{TITLES[route]}</h1>
          <div className="spacer" />
          <div className="admin-chip">
            <div className="admin-avatar">{(admin?.name ?? 'A').slice(0, 1)}</div>
            <span>{admin?.name ?? '管理员'}</span>
            <span className="tiny">{admin?.role ?? ''}</span>
          </div>
          <button className="btn btn-ghost btn-sm" onClick={logout}>
            退出
          </button>
        </header>
        <main className="content">
          <Page key={`${route}-${refreshKey}`} route={route} />
        </main>
      </div>
    </div>
  );
}

function Page({ route }: { route: RouteKey }) {
  switch (route) {
    case 'dashboard':
      return <Dashboard />;
    case 'credit':
      return <Credit />;
    case 'loans':
      return <Loans />;
    case 'bills':
      return <Bills />;
    case 'repayments':
      return <Repayments />;
    case 'users':
      return <Users />;
    case 'risk':
      return <Risk />;
    case 'marketing':
      return <Marketing />;
    case 'config':
      return <Config />;
    default:
      return <Dashboard />;
  }
}

function Login({ onSuccess }: { onSuccess: () => void }) {
  const [username, setUsername] = useState('admin');
  const [password, setPassword] = useState('Admin@123');
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setErr(null);
    try {
      const data = await api.post('/api/admin/login', { username, password });
      setToken(data.token);
      localStorage.setItem('ucash.admin.profile', JSON.stringify(data.admin));
      window.location.hash = '#/dashboard';
      onSuccess();
    } catch (e: any) {
      setErr(e.message ?? '登录失败');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-page">
      <div className="login-left">
        <h1>UCash 运营后台</h1>
        <p>授信审批、放款管理、账单与逾期台账、风控规则配置、用户与营销管理，一站式覆盖现金贷业务全流程。</p>
        <div className="login-badges">
          <span className="login-badge">实时指标</span>
          <span className="login-badge">人工审批</span>
          <span className="login-badge">风控可回溯</span>
          <span className="login-badge">全量审计</span>
        </div>
      </div>
      <div className="login-right">
        <form className="login-card" onSubmit={submit}>
          <h2>登录</h2>
          <div className="sub">请使用管理员账号登录</div>
          <div className="field">
            <label>账号</label>
            <input className="input" value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" />
          </div>
          <div className="field">
            <label>密码</label>
            <input className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" />
          </div>
          {err && <div style={{ color: '#e5484d', fontSize: 12.5, marginBottom: 12 }}>{err}</div>}
          <button className="btn btn-primary" type="submit" disabled={loading}>
            {loading ? '登录中…' : '登录'}
          </button>
          <div className="login-tip">
            演示账号：admin / Admin@123（超级管理员）
            <br />
            approver / Approve@123（审批员）· risk / Risk@123（风控）
          </div>
        </form>
      </div>
    </div>
  );
}
