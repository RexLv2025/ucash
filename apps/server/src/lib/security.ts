import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';

const SECRET = process.env.PII_SECRET || 'ucash-dev-pii-secret-2026';
const KEY = crypto.createHash('sha256').update(SECRET).digest();

export function encryptPII(plain: string): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', KEY, iv);
  const enc = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString('base64')}.${enc.toString('base64')}.${tag.toString('base64')}`;
}

export function decryptPII(payload: string): string {
  try {
    const [ivB64, dataB64, tagB64] = payload.split('.');
    const decipher = crypto.createDecipheriv('aes-256-gcm', KEY, Buffer.from(ivB64, 'base64'));
    decipher.setAuthTag(Buffer.from(tagB64, 'base64'));
    return Buffer.concat([decipher.update(Buffer.from(dataB64, 'base64')), decipher.final()]).toString('utf8');
  } catch {
    return '';
  }
}

export function maskPhone(phone: string): string {
  if (!phone || phone.length < 7) return phone;
  return `${phone.slice(0, 3)}****${phone.slice(-4)}`;
}

export function maskIdCard(id: string): string {
  if (!id || id.length < 8) return id;
  return `${id.slice(0, 4)}**********${id.slice(-2)}`;
}

export function maskBankCard(cardNo: string): string {
  const digits = cardNo.replace(/\s/g, '');
  return `**** **** **** ${digits.slice(-4)}`;
}

export function hashPassword(pwd: string): string {
  return bcrypt.hashSync(pwd, 10);
}

export function verifyPassword(pwd: string, hash: string | null | undefined): boolean {
  if (!hash) return false;
  return bcrypt.compareSync(pwd, hash);
}

/** 身份证校验位（GB 11643-1999） */
export function validateIdCard(id: string): boolean {
  if (!/^\d{17}[\dXx]$/.test(id)) return false;
  const weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
  const checks = ['1', '0', 'X', '9', '8', '7', '6', '5', '4', '3', '2'];
  let sum = 0;
  for (let i = 0; i < 17; i++) sum += Number(id[i]) * weights[i];
  return checks[sum % 11] === id[17].toUpperCase();
}

export function birthYearFromId(id: string): number | null {
  if (!/^\d{17}[\dXx]$/.test(id)) return null;
  return Number(id.slice(6, 10));
}

export function genderFromId(id: string): string | null {
  if (!/^\d{17}[\dXx]$/.test(id)) return null;
  return Number(id[16]) % 2 === 1 ? 'male' : 'female';
}
