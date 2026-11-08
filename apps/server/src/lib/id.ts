import crypto from 'node:crypto';
import { todayStr } from './date.js';

export function genNo(prefix: string): string {
  const d = todayStr().replace(/-/g, '');
  return `${prefix}${d}${crypto.randomInt(100000, 999999)}${crypto.randomInt(10, 99)}`;
}

export function genInviteCode(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < 6; i++) out += alphabet[crypto.randomInt(0, alphabet.length)];
  return out;
}

export function genSmsCode(): string {
  return String(crypto.randomInt(100000, 999999));
}
