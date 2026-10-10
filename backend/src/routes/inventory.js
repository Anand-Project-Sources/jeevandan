const router = require('express').Router();
const { pool, withTx } = require('../db');
const U = require('../util');
const { wrap, allow, HttpError, bad, COMPAT } = U;

// Any logged-in user: find usable (non-expired) stock. bg = recipient group -> compatible donor groups.
router.get('/search', wrap(async (req, res) => {
  const { bg, city } = req.query;
  const exact = req.query.exact === '1';
  const where = ['v.units_available > 0'];
  const p = [];
  if (bg) {
    if (!COMPAT[bg]) throw bad('Unknown blood group');
    where.push('v.blood_group IN (?)');
    p.push(exact ? [bg] : COMPAT[bg]);
  }
  if (city) { where.push('v.city LIKE ?'); p.push(`%${city}%`); }
  p.push(bg || '');
  const [rows] = await pool.query(
    `SELECT v.hospital_id, v.hospital_name, v.city, h.facility_type, h.phone, v.blood_group,
            v.units_available, v.nearest_expiry
       FROM v_inventory_summary v JOIN hospitals h ON h.hospital_id = v.hospital_id
      WHERE ${where.join(' AND ')}
      ORDER BY (v.blood_group = ?) DESC, v.units_available DESC LIMIT 100`, p);
  res.json(rows);
}));

// Hospital stock for all 8 groups (zeros included)
router.get('/hospital-stock', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const hid = req.user.role === 'STAFF' ? req.user.hospitalId : Number(req.query.hospital_id);
  if (!hid) throw bad('hospital_id is required');
  const [rows] = await pool.query(
    'SELECT blood_group, units_available, nearest_expiry FROM v_inventory_summary WHERE hospital_id = ? ORDER BY bg_id', [hid]);
  res.json(rows);
}));

router.get('/batches', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const p = [];
  let where = "ib.status IN ('AVAILABLE','EXPIRED') AND ib.units_available > 0";
  if (req.user.role === 'STAFF') { where += ' AND ib.hospital_id = ?'; p.push(req.user.hospitalId); }
  else if (req.query.hospital_id) { where += ' AND ib.hospital_id = ?'; p.push(Number(req.query.hospital_id)); }
  const [rows] = await pool.query(
    `SELECT ib.batch_id, h.name AS hospital_name, b.label AS blood_group, ib.units_total, ib.units_available,
            ib.collected_on, ib.expiry_date, ib.status, DATEDIFF(ib.expiry_date, CURDATE()) AS days_left
       FROM inventory_batches ib JOIN hospitals h ON h.hospital_id = ib.hospital_id
       JOIN blood_groups b ON b.bg_id = ib.bg_id
      WHERE ${where} ORDER BY ib.expiry_date, ib.batch_id LIMIT 200`, p);
  res.json(rows);
}));

// Record a donation: creates donation + inventory batch (35-day shelf life) atomically
router.post('/donations', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const b = req.body || {};
  const donorId = U.reqInt(b.donor_id, 'Donor', 1, 2147483647);
  const units = U.reqInt(b.units, 'Units', 1, 2);
  const hospitalId = req.user.role === 'STAFF' ? req.user.hospitalId : U.reqInt(b.hospital_id, 'Hospital', 1, 2147483647);
  const date = b.donated_on ? U.reqDate(b.donated_on, 'Donation date') : null;

  const result = await withTx(req.user.id, async (conn) => {
    const [[donor]] = await conn.query(
      `SELECT d.donor_id, d.user_id, d.bg_id, d.is_available, ${U.ELIGIBLE_SQL} AS eligible, u.full_name
         FROM donors d JOIN users u ON u.user_id = d.user_id WHERE d.donor_id = ? FOR UPDATE`, [donorId]);
    if (!donor) throw new HttpError(404, 'Donor not found');
    if (!donor.eligible) throw new HttpError(409, 'Donor donated within the last 90 days and is not eligible yet');
    const [[t]] = await conn.query('SELECT COALESCE(?, CURDATE()) AS d, CURDATE() AS today', [date]);
    if (t.d > t.today) throw bad('Donation date cannot be in the future');
    const [don] = await conn.query(
      'INSERT INTO donations(donor_id, hospital_id, units, donated_on, recorded_by) VALUES (?,?,?,?,?)',
      [donorId, hospitalId, units, t.d, req.user.id]);
    const [batch] = await conn.query(
      `INSERT INTO inventory_batches(hospital_id, bg_id, units_total, units_available, collected_on, expiry_date, source_donation_id)
       VALUES (?,?,?,?,?, DATE_ADD(?, INTERVAL 35 DAY), ?)`,
      [hospitalId, donor.bg_id, units, units, t.d, t.d, don.insertId]);
    await conn.query(
      `INSERT INTO notifications(user_id, type, title, message, related_id)
       VALUES (?, 'SYSTEM', 'Thank you for donating!', 'Your donation was recorded. You can donate again after 90 days.', ?)`,
      [donor.user_id, don.insertId]);
    return { donation_id: don.insertId, batch_id: batch.insertId, donor: donor.full_name };
  });
  res.status(201).json(result);
}));

module.exports = router;
