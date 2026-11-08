/**
 * UCash 端到端验收脚本
 * 覆盖：注册 → 实名 → 人脸 → 联系人 → 授信 → 试算 → 下单 → 放款 → 账单 → 还款 → 结清
 * 用法：npm run e2e   （需先启动 npm run dev）
 */

const BASE = process.env.API_BASE || 'http://localhost:4000';
const PHONE = process.env.E2E_PHONE || '13911112222';

let passed = 0;
let failed = 0;

function log(step: string, ok: boolean, extra = '') {
  const mark = ok ? '✓' : '✗';
  console.log(`${mark} ${step}${extra ? ' — ' + extra : ''}`);
  if (ok) passed++;
  else failed++;
}

interface ApiResult {
  code: number;
  message: string;
  data: any;
}

async function api(method: string, path: string, body?: unknown, token?: string, extraHeaders?: Record<string, string>): Promise<ApiResult> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(extraHeaders ?? {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = (await res.json()) as ApiResult;
  return json;
}

function assert(step: string, cond: boolean, detail = '') {
  log(step, cond, detail);
  if (!cond) throw new Error(`断言失败: ${step} ${detail}`);
}

async function main() {
  console.log(`\n=== UCash 端到端验收 @ ${BASE} ===\n`);

  // 1. 登录（不存在则自动注册）
  const login = await api('POST', '/api/auth/login', { phone: PHONE, code: '123456' });
  assert('登录/注册', login.code === 0, login.data?.user?.phone);
  const token = login.data.token as string;

  // 2. 实名认证
  const idCard = '440305199204151232';
  const realname = await api(
    'POST',
    '/api/kyc/realname',
    { realName: '测试用户', idCard, city: '深圳', occupation: '互联网/技术', monthlyIncomeCents: 1500000 },
    token
  );
  assert('实名认证', realname.code === 0 || realname.code === 3003, realname.message);

  // 3. 人脸识别
  const face = await api('POST', '/api/kyc/face', { score: 95, liveness: true }, token);
  assert('人脸识别', face.code === 0, `相似度 ${face.data?.score ?? '-'}`);

  // 4. 紧急联系人
  const contacts = await api(
    'POST',
    '/api/kyc/contacts',
    { contact1Name: '李强', contact1Phone: '13911112223', contact2Name: '王芳', contact2Phone: '13822223333' },
    token
  );
  assert('联系人授权', contacts.code === 0, contacts.message);

  // 5. 提额认证
  const boost = await api('POST', '/api/kyc/boost', { type: 'fund' }, token);
  assert('公积金认证提额', boost.code === 0, boost.data ? `额度 ${(boost.data.limitAfterCents / 100).toFixed(0)} 元` : '');

  // 6. 授信申请
  const credit = await api('POST', '/api/credit/applications', { amountCents: 1000000, purpose: '日常消费' }, token);
  assert('授信申请', credit.code === 0, `状态 ${credit.data?.status}`);
  if (credit.data?.status === 'rejected') {
    console.log('  授信被拒，终止后续链路:', credit.data?.risk?.rejectReason);
    return;
  }

  const creditInfo = await api('GET', '/api/credit', undefined, token);
  assert('额度查询', creditInfo.code === 0, `可用 ${(creditInfo.data.availableLimitCents / 100).toFixed(2)} 元，年化 ${(creditInfo.data.interestRateBp / 100).toFixed(2)}%`);
  assert('额度已激活', creditInfo.data.status === 'approved');

  // 7. 借款试算
  const quote = await api('POST', '/api/loans/quote', { amountCents: 500000, termMonths: 6 }, token);
  assert('借款试算', quote.code === 0, quote.code === 0 ? `月供 ${(quote.data.monthlyPaymentCents / 100).toFixed(2)}，总息 ${(quote.data.totalInterestCents / 100).toFixed(2)}，IRR ${(quote.data.aprBp / 100).toFixed(2)}%` : quote.message);
  if (quote.code !== 0) return;

  // 账务自洽校验
  const sumPrincipal = quote.data.schedule.reduce((s: number, x: any) => s + x.principalCents, 0);
  const sumTotal = quote.data.schedule.reduce((s: number, x: any) => s + x.totalCents, 0);
  assert('还款计划本金合计 = 借款本金', sumPrincipal === 500000, `${sumPrincipal}`);
  assert('还款计划合计 = 总应还', sumTotal === quote.data.totalRepayCents, `${sumTotal}`);
  assert('年化利率不超过 24%', quote.data.aprBp <= 2400, `${(quote.data.aprBp / 100).toFixed(2)}%`);

  // 8. 绑定银行卡并下单
  const cards = await api('GET', '/api/cards', undefined, token);
  assert('银行卡列表', cards.code === 0 && cards.data.list.length > 0);
  const cardId = cards.data.list[0].id;

  const loan = await api(
    'POST',
    '/api/loans',
    { quoteToken: quote.data.quoteToken, bankCardId: cardId, purpose: '日常消费', contractSigned: true },
    token
  );
  assert('借款下单', loan.code === 0, loan.code === 0 ? `${loan.data.loanNo} 状态 ${loan.data.status}` : loan.message);
  if (loan.code !== 0) return;
  const loanId = loan.data.id;

  // 9. 等待放款
  let detail: any = null;
  for (let i = 0; i < 15; i++) {
    await new Promise((r) => setTimeout(r, 500));
    const d = await api('GET', `/api/loans/${loanId}`, undefined, token);
    detail = d.data;
    if (detail && !['reviewing', 'disbursing'].includes(detail.status)) break;
  }
  assert('放款完成', detail?.status === 'active', `状态 ${detail?.status}`);
  assert('账单已生成', detail?.schedules?.length === 6, `${detail?.schedules?.length} 期`);

  // 10. 账单
  const bills = await api('GET', '/api/bills', undefined, token);
  assert('账单查询', bills.code === 0, `待还 ${bills.data.summary.unpaidCount} 期，合计 ${(bills.data.summary.totalUnpaidCents / 100).toFixed(2)} 元`);
  const firstUnpaid = bills.data.unpaid.find((b: any) => b.loanId === loanId);
  assert('当期账单存在', Boolean(firstUnpaid));

  // 11. 还款试算 + 还款
  const repayQuote = await api('GET', `/api/repayments/quote?loanId=${loanId}&type=normal`, undefined, token);
  assert('还款试算', repayQuote.code === 0, `${(repayQuote.data.totalCents / 100).toFixed(2)} 元`);
  const idemKey = `e2e-idem-${Date.now()}`;
  const repay = await api('POST', '/api/repayments', { loanId, type: 'normal', bankCardId: cardId }, token, { 'Idempotency-Key': idemKey });
  assert('当期还款', repay.code === 0, repay.data ? `${(repay.data.amountCents / 100).toFixed(2)} 元` : repay.message);

  // 幂等：同一 Idempotency-Key 重复提交不得产生第二笔
  const repayAgain = await api('POST', '/api/repayments', { loanId, type: 'normal', bankCardId: cardId }, token, { 'Idempotency-Key': idemKey });
  assert(
    '还款幂等（重复提交不重复扣款）',
    repayAgain.code === 0 && repayAgain.data?.repaymentNo === repay.data?.repaymentNo,
    repayAgain.data?.repaymentNo ?? repayAgain.message
  );

  // 12. 提前结清试算 + 结清
  const settleQuote = await api('GET', `/api/repayments/quote?loanId=${loanId}&type=settle`, undefined, token);
  assert('提前结清试算', settleQuote.code === 0, `应还 ${(settleQuote.data.totalCents / 100).toFixed(2)} 元，节省利息 ${(settleQuote.data.savedInterestCents / 100).toFixed(2)} 元`);
  const settle = await api('POST', '/api/repayments', { loanId, type: 'settle', bankCardId: cardId }, token);
  assert('提前结清', settle.code === 0, settle.data ? `状态 ${settle.data.loanStatus.status}` : settle.message);

  // 13. 结清后额度释放
  const creditAfter = await api('GET', '/api/credit', undefined, token);
  assert('额度已释放', creditAfter.data.usedLimitCents === 0, `已用 ${(creditAfter.data.usedLimitCents / 100).toFixed(2)} 元`);

  // 14. 还款流水
  const repayments = await api('GET', '/api/repayments', undefined, token);
  assert('还款流水', repayments.code === 0 && repayments.data.list.length >= 2, `${repayments.data.list.length} 条`);

  // 账务自洽：每笔流水 金额 = 本金 + 利息 + 罚息
  const badFlows = repayments.data.list.filter(
    (r: any) => r.amountCents !== r.principalCents + r.interestCents + r.penaltyCents
  );
  assert('还款流水账务自洽（金额 = 本息费）', badFlows.length === 0, badFlows.length ? `${badFlows.length} 笔不一致` : '全部一致');

  // 15. 站内信
  const messages = await api('GET', '/api/messages', undefined, token);
  assert('站内信', messages.code === 0 && messages.data.list.length > 0, `${messages.data.list.length} 条`);

  console.log(`\n=== 结果：通过 ${passed} / 失败 ${failed} ===\n`);
  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error('\n执行中断:', e.message);
  console.log(`\n=== 结果：通过 ${passed} / 失败 ${failed + 1} ===\n`);
  process.exit(1);
});
