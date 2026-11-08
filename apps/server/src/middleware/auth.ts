import jwt from 'jsonwebtoken';
import type { NextFunction, Request, Response } from 'express';
import { ApiError, ErrCode } from '../lib/http.js';

const SECRET = process.env.JWT_SECRET || 'ucash-dev-jwt-secret-2026';
const USER_TTL = '30d';
const ADMIN_TTL = '12h';

export interface UserClaims {
  sub: number;
  type: 'user';
  phone: string;
}
export interface AdminClaims {
  sub: number;
  type: 'admin';
  role: string;
  username: string;
}

export interface AuthedRequest extends Request {
  user?: UserClaims;
  admin?: AdminClaims;
}

export function signUserToken(id: number, phone: string) {
  return jwt.sign({ sub: id, type: 'user', phone }, SECRET, { expiresIn: USER_TTL });
}
export function signAdminToken(id: number, username: string, role: string) {
  return jwt.sign({ sub: id, type: 'admin', username, role }, SECRET, { expiresIn: ADMIN_TTL });
}

function readToken(req: Request): string | null {
  const header = req.headers.authorization;
  if (header?.startsWith('Bearer ')) return header.slice(7);
  return null;
}

export function requireUser(req: AuthedRequest, _res: Response, next: NextFunction) {
  const token = readToken(req);
  if (!token) return next(new ApiError(ErrCode.UNAUTHORIZED));
  try {
    const claims = jwt.verify(token, SECRET) as unknown as UserClaims;
    if (claims.type !== 'user') return next(new ApiError(ErrCode.UNAUTHORIZED));
    req.user = claims;
    next();
  } catch {
    next(new ApiError(ErrCode.UNAUTHORIZED));
  }
}

export function optionalUser(req: AuthedRequest, _res: Response, next: NextFunction) {
  const token = readToken(req);
  if (token) {
    try {
      const claims = jwt.verify(token, SECRET) as unknown as UserClaims;
      if (claims.type === 'user') req.user = claims;
    } catch {
      /* ignore */
    }
  }
  next();
}

const ROLE_WEIGHT: Record<string, number> = { ops: 1, risk: 2, approver: 3, super: 9 };

export function requireAdmin(minRole: 'ops' | 'risk' | 'approver' | 'super' = 'ops') {
  return (req: AuthedRequest, _res: Response, next: NextFunction) => {
    const token = readToken(req);
    if (!token) return next(new ApiError(ErrCode.UNAUTHORIZED));
    try {
      const claims = jwt.verify(token, SECRET) as unknown as AdminClaims;
      if (claims.type !== 'admin') return next(new ApiError(ErrCode.UNAUTHORIZED));
      if ((ROLE_WEIGHT[claims.role] ?? 0) < ROLE_WEIGHT[minRole]) return next(new ApiError(ErrCode.FORBIDDEN));
      req.admin = claims;
      next();
    } catch {
      next(new ApiError(ErrCode.UNAUTHORIZED));
    }
  };
}
