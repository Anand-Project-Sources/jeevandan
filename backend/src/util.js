const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { pool } = require('./db');

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const bad = (m) => new HttpError(400, m);
const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// ---- passwords: scrypt with per-user salt (no external dependency) ----
function hashPassword(pw) {
  const salt = crypto.randomBytes(16).toString('hex');
  return `${salt}:${crypto.scryptSync(pw, salt, 64).toString('hex')}`;
}
function verifyPassword(pw, stored) {
  const [salt, hash] = String(stored).split(':');
  if (!salt || !hash) return false;
  const candidate = crypto.scryptSync(pw, salt, 64);
  const expected = Buffer.from(hash, 'hex');
  return candidate.length === expected.length && crypto.timingSafeEqual(candidate, expected);
}
const signToken = (userId) => jwt.sign({ uid: userId }, process.env.JWT_SECRET, { expiresIn: '12h' });

// ---- auth middleware ----
async function authenticate(req, res, next) {
  try {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : null;
    if (!token) throw new HttpError(401, 'Authentication required');
    let payload;
    try { payload = jwt.verify(token, process.env.JWT_SECRET); }
    catch (_) { throw new HttpError(401, 'Session expired, please log in again'); }
    const [rows] = await pool.query(
      `SELECT u.user_id, u.full_name, u.is_active, r.role_name AS role, hs.hospital_id
         FROM users u JOIN roles r ON r.role_id = u.role_id
         LEFT JOIN hospital_staff hs ON hs.user_id = u.user_id
        WHERE u.user_id = ?`, [payload.uid]);
    if (!rows.length || !rows[0].is_active) throw new HttpError(401, 'Account not available');
    req.user = { id: rows[0].user_id, name: rows[0].full_name, role: rows[0].role, hospitalId: rows[0].hospital_id };
    next();
  } catch (e) { next(e); }
}
const allow = (...roles) => (req, res, next) =>
  roles.includes(req.user.role) ? next() : next(new HttpError(403, 'You are not allowed to perform this action'));

// ---- validation helpers ----
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
function reqStr(v, name, min = 1, max = 200) {
  if (typeof v !== 'string' || v.trim().length < min || v.trim().length > max)
    throw bad(`${name} is required (${min}-${max} characters)`);
  return v.trim();
}
function reqInt(v, name, min, max) {
  const n = Number(v);
  if (!Number.isInteger(n) || n < min || n > max) throw bad(`${name} must be a whole number between ${min} and ${max}`);
  return n;
}
function reqEnum(v, name, list) {
  if (!list.includes(v)) throw bad(`${name} must be one of: ${list.join(', ')}`);
  return v;
}
function reqDate(v, name) {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v) || isNaN(Date.parse(v))) throw bad(`${name} must be a date (YYYY-MM-DD)`);
  return v;
}
function reqPhone(v) {
  const p = String(v || '').replace(/[\s-]/g, '');
  if (!/^\+?[0-9]{10,13}$/.test(p)) throw bad('Phone must be 10-13 digits');
  return p;
}
function reqPassword(v) {
  if (typeof v !== 'string' || v.length < 8 || !/[A-Za-z]/.test(v) || !/[0-9]/.test(v))
    throw bad('Password must be at least 8 characters and contain a letter and a digit');
  return v;
}
function ageFrom(dob) {
  const d = new Date(dob), n = new Date();
  let a = n.getFullYear() - d.getFullYear();
  const m = n.getMonth() - d.getMonth();
  if (m < 0 || (m === 0 && n.getDate() < d.getDate())) a--;
  return a;
}

// ---- blood group logic ----
// Red-cell compatibility: recipient group -> donor groups that can safely give to them
const COMPAT = {
  'O-': ['O-'], 'O+': ['O-', 'O+'], 'A-': ['O-', 'A-'], 'A+': ['O-', 'O+', 'A-', 'A+'],
  'B-': ['O-', 'B-'], 'B+': ['O-', 'O+', 'B-', 'B+'],
  'AB-': ['O-', 'A-', 'B-', 'AB-'], 'AB+': ['O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+'],
};
// Organs: ABO compatibility only (Rh ignored); final matching is a clinical decision
function organDonorGroups(label) {
  const abo = label.replace(/[+-]/, '');
  const ok = { O: ['O'], A: ['O', 'A'], B: ['O', 'B'], AB: ['O', 'A', 'B', 'AB'] }[abo] || [];
  return Object.keys(COMPAT).filter((l) => ok.includes(l.replace(/[+-]/, '')));
}
async function bgIdOf(label, db = pool) {
  const [r] = await db.query('SELECT bg_id FROM blood_groups WHERE label = ?', [label]);
  if (!r.length) throw bad('Unknown blood group');
  return r[0].bg_id;
}
async function audit(conn, userId, action, entity, entityId, details) {
  await conn.query('INSERT INTO audit_logs(user_id, action, entity, entity_id, details) VALUES (?,?,?,?,?)',
    [userId, action, entity, entityId, details ? String(details).slice(0, 500) : null]);
}

const ELIGIBLE_SQL = '(d.last_donation_date IS NULL OR DATEDIFF(CURDATE(), d.last_donation_date) >= 90)';

function errorHandler(err, req, res, _next) {
  if (err.status) return res.status(err.status).json({ error: err.message });
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'Invalid JSON body' });
  if (err.sqlState === '45000') return res.status(409).json({ error: err.sqlMessage });
  if (err.code === 'ER_DUP_ENTRY') {
    const m = String(err.sqlMessage || '');
    return res.status(409).json({ error: m.includes('email') ? 'Email is already registered' : 'This record already exists' });
  }
  if (err.errno === 3819) return res.status(400).json({ error: 'Value violates a database constraint' });
  if (err.code === 'ER_NO_REFERENCED_ROW_2') return res.status(400).json({ error: 'Referenced record does not exist' });
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
}

module.exports = {
  HttpError, bad, wrap, hashPassword, verifyPassword, signToken, authenticate, allow,
  EMAIL_RE, reqStr, reqInt, reqEnum, reqDate, reqPhone, reqPassword, ageFrom,
  COMPAT, organDonorGroups, bgIdOf, audit, ELIGIBLE_SQL, errorHandler,
};
