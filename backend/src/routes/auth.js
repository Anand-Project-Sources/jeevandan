const router = require('express').Router();
const { pool, withTx } = require('../db');
const U = require('../util');
const { wrap, HttpError, bad } = U;

async function loadProfile(userId, db = pool) {
  const [rows] = await db.query(
    `SELECT u.user_id, u.full_name, u.email, u.phone, r.role_name AS role,
            hs.hospital_id, h.name AS hospital_name, h.is_transplant_center
       FROM users u JOIN roles r ON r.role_id = u.role_id
       LEFT JOIN hospital_staff hs ON hs.user_id = u.user_id
       LEFT JOIN hospitals h ON h.hospital_id = hs.hospital_id
      WHERE u.user_id = ?`, [userId]);
  const u = rows[0];
  if (!u) return null;
  if (u.role === 'DONOR') {
    const [d] = await db.query(
      `SELECT d.donor_id, b.label AS blood_group, d.date_of_birth, d.gender, d.weight_kg, d.city,
              d.last_donation_date, d.is_available, ${U.ELIGIBLE_SQL} AS eligible,
              CASE WHEN d.last_donation_date IS NULL THEN NULL
                   ELSE DATE_ADD(d.last_donation_date, INTERVAL 90 DAY) END AS next_eligible_date
         FROM donors d JOIN blood_groups b ON b.bg_id = d.bg_id WHERE d.user_id = ?`, [userId]);
    u.donor = d[0] || null;
  }
  return u;
}

// simple in-memory login throttle
const attempts = new Map();
function throttle(key) {
  const now = Date.now();
  const rec = (attempts.get(key) || []).filter((t) => now - t < 15 * 60 * 1000);
  if (rec.length >= 10) throw new HttpError(429, 'Too many login attempts. Try again in a few minutes.');
  rec.push(now);
  attempts.set(key, rec);
}

router.get('/lookups', wrap(async (req, res) => {
  const [bloodGroups] = await pool.query('SELECT bg_id, label FROM blood_groups ORDER BY bg_id');
  const [organs] = await pool.query('SELECT organ_id, organ_name FROM organ_types ORDER BY organ_id');
  const [hospitals] = await pool.query(
    'SELECT hospital_id, name, city, facility_type, is_transplant_center FROM hospitals ORDER BY city, name');
  res.json({ bloodGroups, organs, hospitals });
}));

router.post('/auth/register', wrap(async (req, res) => {
  const b = req.body || {};
  const role = U.reqEnum(b.role, 'Role', ['DONOR', 'PATIENT']);
  const fullName = U.reqStr(b.full_name, 'Full name', 2, 100);
  const email = U.reqStr(b.email, 'Email', 5, 120).toLowerCase();
  if (!U.EMAIL_RE.test(email)) throw bad('Enter a valid email address');
  const phone = U.reqPhone(b.phone);
  const password = U.reqPassword(b.password);

  let donor = null;
  if (role === 'DONOR') {
    const dob = U.reqDate(b.date_of_birth, 'Date of birth');
    const age = U.ageFrom(dob);
    if (age < 18 || age > 65) throw bad('Donors must be between 18 and 65 years old');
    const weight = Number(b.weight_kg);
    if (!(weight >= 45 && weight <= 250)) throw bad('Donors must weigh at least 45 kg');
    donor = {
      bg: U.reqEnum(b.blood_group, 'Blood group', Object.keys(U.COMPAT)),
      dob, gender: U.reqEnum(b.gender, 'Gender', ['M', 'F', 'O']), weight,
      city: U.reqStr(b.city, 'City', 2, 60),
    };
  }

  const id = await withTx(null, async (conn) => {
    const [[r]] = await conn.query('SELECT role_id FROM roles WHERE role_name = ?', [role]);
    const [ins] = await conn.query(
      'INSERT INTO users(role_id, full_name, email, phone, password_hash) VALUES (?,?,?,?,?)',
      [r.role_id, fullName, email, phone, U.hashPassword(password)]);
    if (donor) {
      const bgId = await U.bgIdOf(donor.bg, conn);
      await conn.query(
        'INSERT INTO donors(user_id, bg_id, date_of_birth, gender, weight_kg, city) VALUES (?,?,?,?,?,?)',
        [ins.insertId, bgId, donor.dob, donor.gender, donor.weight, donor.city]);
    }
    await U.audit(conn, ins.insertId, 'USER_REGISTERED', 'user', ins.insertId, `role=${role}`);
    return ins.insertId;
  });
  res.status(201).json({ token: U.signToken(id), user: await loadProfile(id) });
}));

router.post('/auth/login', wrap(async (req, res) => {
  const email = String((req.body || {}).email || '').trim().toLowerCase();
  const password = String((req.body || {}).password || '');
  if (!email || !password) throw bad('Email and password are required');
  const key = `${req.ip}|${email}`;
  throttle(key);
  const [rows] = await pool.query('SELECT user_id, password_hash, is_active FROM users WHERE email = ?', [email]);
  if (!rows.length || !rows[0].is_active || !U.verifyPassword(password, rows[0].password_hash))
    throw new HttpError(401, 'Invalid email or password');
  attempts.delete(key);
  await pool.query('INSERT INTO audit_logs(user_id, action, entity, entity_id) VALUES (?,?,?,?)',
    [rows[0].user_id, 'LOGIN', 'user', rows[0].user_id]);
  res.json({ token: U.signToken(rows[0].user_id), user: await loadProfile(rows[0].user_id) });
}));

router.get('/me', U.authenticate, wrap(async (req, res) => {
  res.json(await loadProfile(req.user.id));
}));

router.put('/me', U.authenticate, wrap(async (req, res) => {
  const b = req.body || {};
  await withTx(req.user.id, async (conn) => {
    const sets = [], vals = [];
    if (b.full_name !== undefined) { sets.push('full_name = ?'); vals.push(U.reqStr(b.full_name, 'Full name', 2, 100)); }
    if (b.phone !== undefined) { sets.push('phone = ?'); vals.push(U.reqPhone(b.phone)); }
    if (b.new_password) {
      const [[row]] = await conn.query('SELECT password_hash FROM users WHERE user_id = ?', [req.user.id]);
      if (!U.verifyPassword(String(b.current_password || ''), row.password_hash)) throw bad('Current password is incorrect');
      sets.push('password_hash = ?'); vals.push(U.hashPassword(U.reqPassword(b.new_password)));
    }
    if (sets.length) await conn.query(`UPDATE users SET ${sets.join(', ')} WHERE user_id = ?`, [...vals, req.user.id]);

    if (req.user.role === 'DONOR' && b.donor) {
      const d = b.donor, ds = [], dv = [];
      if (d.city !== undefined) { ds.push('city = ?'); dv.push(U.reqStr(d.city, 'City', 2, 60)); }
      if (d.weight_kg !== undefined) {
        const w = Number(d.weight_kg);
        if (!(w >= 30 && w <= 250)) throw bad('Weight must be between 30 and 250 kg');
        ds.push('weight_kg = ?'); dv.push(w);
      }
      if (d.is_available !== undefined) { ds.push('is_available = ?'); dv.push(d.is_available ? 1 : 0); }
      if (ds.length) await conn.query(`UPDATE donors SET ${ds.join(', ')} WHERE user_id = ?`, [...dv, req.user.id]);
    }
    await U.audit(conn, req.user.id, 'PROFILE_UPDATED', 'user', req.user.id, null);
  });
  res.json(await loadProfile(req.user.id));
}));

module.exports = router;
