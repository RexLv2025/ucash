/**
 * 金额与利率计算 —— 全部使用整数分，避免浮点误差。
 * 口径：
 *  - interest_rate_bp：合同年利率（名义，等额本息），基点 1660 = 16.60%
 *  - apr_bp：综合年化利率（IRR），按现金流二分法求解，符合监管「明示年化利率」口径
 */

export const toCents = (yuan: number) => Math.round(yuan * 100);
export const toYuan = (cents: number) => cents / 100;
export const fmtCents = (cents: number) => (cents / 100).toFixed(2);

/** 月供（等额本息） */
export function annuityPayment(principalCents: number, annualRateBp: number, termMonths: number): number {
  const i = annualRateBp / 10000 / 12;
  if (i === 0) return Math.round(principalCents / termMonths);
  const factor = Math.pow(1 + i, termMonths);
  return Math.round((principalCents * i * factor) / (factor - 1));
}

export interface ScheduleItem {
  periodNo: number;
  principalCents: number;
  interestCents: number;
  totalCents: number;
}

/**
 * 生成等额本息还款计划：
 * 每期利息按剩余本金计息，本金 = 月供 − 利息，末期本金取剩余全部（平账）。
 * 返回合计与月供，保证 sum(principal) === 本金、sum(interest) === 总利息。
 */
export function buildSchedule(principalCents: number, annualRateBp: number, termMonths: number) {
  const i = annualRateBp / 10000 / 12;
  const monthly = annuityPayment(principalCents, annualRateBp, termMonths);
  const items: ScheduleItem[] = [];
  let remaining = principalCents;
  for (let p = 1; p <= termMonths; p++) {
    const interest = Math.round(remaining * i);
    let principal: number;
    let total: number;
    if (p === termMonths) {
      principal = remaining;
      total = principal + interest;
    } else {
      principal = monthly - interest;
      if (principal > remaining) principal = remaining;
      total = principal + interest;
    }
    remaining -= principal;
    items.push({ periodNo: p, principalCents: principal, interestCents: interest, totalCents: total });
  }
  const totalInterest = items.reduce((s, x) => s + x.interestCents, 0);
  const totalRepay = items.reduce((s, x) => s + x.totalCents, 0);
  return { items, monthlyPaymentCents: items[0].totalCents, totalInterestCents: totalInterest, totalRepayCents: totalRepay };
}

/** IRR：现金流按 [-本金, 每期还款...]，二分法求月利率，再年化 */
export function irrAnnualBp(principalCents: number, payments: number[]): number {
  const npv = (r: number) => {
    let v = -principalCents;
    for (let k = 0; k < payments.length; k++) v += payments[k] / Math.pow(1 + r, k + 1);
    return v;
  };
  let lo = 0;
  let hi = 1; // 月利率 100% 上限
  if (npv(lo) <= 0) return 0;
  for (let k = 0; k < 200; k++) {
    const mid = (lo + hi) / 2;
    if (npv(mid) > 0) lo = mid;
    else hi = mid;
  }
  const monthly = (lo + hi) / 2;
  const annual = Math.pow(1 + monthly, 12) - 1;
  return Math.round(annual * 10000);
}

/** 应付罚息（逾期本息合计 × 日罚息率 × 天数） */
export function calcPenalty(overdueBaseCents: number, dailyRateBp: number, overdueDays: number): number {
  if (overdueDays <= 0 || overdueBaseCents <= 0) return 0;
  return Math.round((overdueBaseCents * dailyRateBp * overdueDays) / 10000);
}

/** 提前结清：剩余本金 + 当期应计利息（按日）+ 违约金 */
export function calcSettlement(opts: {
  remainingPrincipalCents: number;
  annualRateBp: number;
  daysSinceLastSettle: number;
  penaltyRateBpOfPrincipal: number; // 违约金比例（万分比），0 表示免收
}) {
  const { remainingPrincipalCents, annualRateBp, daysSinceLastSettle, penaltyRateBpOfPrincipal } = opts;
  const accruedInterest = Math.round((remainingPrincipalCents * annualRateBp * Math.max(daysSinceLastSettle, 0)) / 10000 / 360);
  const penalty = Math.round((remainingPrincipalCents * penaltyRateBpOfPrincipal) / 10000);
  return {
    remainingPrincipalCents,
    accruedInterestCents: accruedInterest,
    penaltyCents: penalty,
    totalCents: remainingPrincipalCents + accruedInterest + penalty,
  };
}

/** 金额千分位展示 */
export function formatMoney(cents: number, withSymbol = false): string {
  const yuan = (cents / 100).toFixed(2);
  const [int, dec] = yuan.split('.');
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${withSymbol ? '¥' : ''}${grouped}.${dec}`;
}

/** 利率基点 → 百分比字符串 */
export function formatRate(bp: number, digits = 2): string {
  return (bp / 100).toFixed(digits);
}
