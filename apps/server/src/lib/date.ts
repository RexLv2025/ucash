/** 日期工具：还款日按「放款日 + N 个月」计算，遇到月末自动压到当月最后一天 */

export function pad(n: number) {
  return n < 10 ? `0${n}` : String(n);
}

export function todayStr(d: Date = new Date()): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function nowIso(d: Date = new Date()): string {
  return d.toISOString();
}

export function parseDate(s: string): Date {
  const [y, m, d] = s.split('-').map(Number);
  return new Date(y, (m || 1) - 1, d || 1);
}

export function daysInMonth(year: number, month1: number): number {
  return new Date(year, month1, 0).getDate();
}

/** 加 N 个月，日期按月末截断 */
export function addMonthsClamped(dateStr: string, months: number): string {
  const d = parseDate(dateStr);
  const totalMonth = d.getMonth() + months;
  const year = d.getFullYear() + Math.floor(totalMonth / 12);
  const month1 = (totalMonth % 12) + 1;
  const day = Math.min(d.getDate(), daysInMonth(year, month1));
  return `${year}-${pad(month1)}-${pad(day)}`;
}

/** 放款日 → 每期还款日 */
export function buildDueDates(disbursedDate: string, termMonths: number): string[] {
  return Array.from({ length: termMonths }, (_, idx) => addMonthsClamped(disbursedDate, idx + 1));
}

/** 两个日期相差天数（to - from） */
export function diffDays(from: string, to: string): number {
  const a = parseDate(from).getTime();
  const b = parseDate(to).getTime();
  return Math.round((b - a) / 86400000);
}

export function todayDateStr(): string {
  return todayStr();
}
