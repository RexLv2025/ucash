import type { Response } from 'express';

export const ErrCode = {
  OK: 0,
  PARAM: 1001,
  UNAUTHORIZED: 1002,
  FORBIDDEN: 1003,
  NOT_FOUND: 1004,
  RATE_LIMIT: 1005,
  IDEMPOTENT: 1006,
  CONFLICT: 1007,

  SMS_CODE: 2001,
  ACCOUNT_FROZEN: 2002,
  PASSWORD: 2003,
  ACCOUNT_CLOSED: 2004,
  SMS_TOO_FREQUENT: 2005,

  NOT_VERIFIED: 3001,
  FACE_FAILED: 3002,
  ID_BOUND: 3003,
  CONTACT_REQUIRED: 3004,
  UNDERAGE: 3005,

  NO_CREDIT: 4001,
  CREDIT_INSUFFICIENT: 4002,
  CREDIT_EXPIRED: 4003,
  CREDIT_REVIEWING: 4004,
  CREDIT_REJECTED: 4005,

  LOAN_AMOUNT: 5001,
  LOAN_TERM: 5002,
  CONTRACT_UNSIGNED: 5003,
  LOAN_PROCESSING: 5004,
  CARD_REQUIRED: 5005,
  COUPON_INVALID: 5006,

  BILL_NOT_FOUND: 6001,
  ALREADY_SETTLED: 6002,
  CARD_INVALID: 6003,
  REPAY_PROCESSING: 6004,
  OVERDUE_BLOCKED: 6005,

  DISBURSE_BANK: 7001,
  DISBURSE_RISK: 7002,

  SYSTEM: 9001,
} as const;

export const ErrMsg: Record<number, string> = {
  0: '成功',
  1001: '参数有误',
  1002: '登录已失效，请重新登录',
  1003: '无访问权限',
  1004: '记录不存在',
  1005: '操作过于频繁，请稍后再试',
  1006: '请求已处理，请勿重复提交',
  1007: '当前状态不允许该操作',
  2001: '验证码错误或已过期',
  2002: '账户已被冻结，请联系客服',
  2003: '手机号或密码错误',
  2004: '账户已注销',
  2005: '验证码发送过于频繁',
  3001: '请先完成实名认证',
  3002: '人脸识别未通过，请重试',
  3003: '该身份证已绑定其他账户',
  3004: '请完成紧急联系人授权',
  3005: '暂不支持向未成年及在校学生提供服务',
  4001: '暂无可用额度，请先申请授信',
  4002: '可用额度不足',
  4003: '授信已过期，请重新申请',
  4004: '授信审批中，请稍候',
  4005: '很遗憾，本次授信未通过',
  5001: '借款金额超出可选范围',
  5002: '暂不支持该还款期数',
  5003: '请先阅读并同意借款合同',
  5004: '借款申请处理中，请勿重复提交',
  5005: '请先绑定收款银行卡',
  5006: '优惠券不可用或已失效',
  6001: '账单不存在',
  6002: '该笔借款已结清',
  6003: '银行卡状态异常，请更换银行卡',
  6004: '还款处理中，请稍候',
  6005: '存在逾期账单，请先结清逾期款项',
  7001: '银行卡状态异常（E1024）',
  7002: '放款风控未通过',
  9001: '系统繁忙，请稍后重试',
};

export class ApiError extends Error {
  code: number;
  httpStatus: number;
  data?: unknown;
  constructor(code: number, message?: string, httpStatus = 200, data?: unknown) {
    super(message || ErrMsg[code] || '未知错误');
    this.code = code;
    this.httpStatus = httpStatus;
    this.data = data;
  }
}

export function ok(res: Response, data: unknown = null, message = '成功') {
  res.json({ code: 0, message, data });
}

export function fail(res: Response, code: number, message?: string, data?: unknown) {
  res.json({ code, message: message || ErrMsg[code] || '操作失败', data: data ?? null });
}
