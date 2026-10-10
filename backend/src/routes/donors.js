const router = require('express').Router();
const { pool } = require('../db');
const { wrap, allow, ELIGIBLE_SQL, HttpError } = require('../util');

// Staff/admin: search donors (contact details only visible to staff/admin)
router.get('/', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const { bg, city, eligible } = req.query;
  const where = ['u.is_active = 1', 'd.is_available = 1'];
  const p = [];
  if (bg) { where.push('b.label = ?'); p.push(bg); }
  if (city) { where.push('d.city LIKE ?'); p.push(`%${city}%`); }
  if (eligible === '1') where.push(ELIGIBLE_SQL);
  const [rows] = await pool.query(
    `SELECT d.donor_id, u.full_name, u.phone, b.label AS blood_group, d.city, d.last_donation_date,
            ${ELIGIBLE_SQL} AS eligible,
            (SELECT COUNT(*) FROM donations x WHERE x.donor_id = d.donor_id) AS total_donations
       FROM donors d JOIN users u ON u.user_id = d.user_id JOIN blood_groups b ON b.bg_id = d.bg_id
      WHERE ${where.join(' AND ')}
      ORDER BY eligible DESC, u.full_name LIMIT 200`, p);
  res.json(rows);
}));

// Donor: own donation history
router.get('/me/history', allow('DONOR'), wrap(async (req, res) => {
  const [rows] = await pool.query(
    `SELECT dn.donation_id, dn.donated_on, dn.units, h.name AS hospital_name, h.city
       FROM donations dn
       JOIN donors d ON d.donor_id = dn.donor_id
       JOIN hospitals h ON h.hospital_id = dn.hospital_id
      WHERE d.user_id = ? ORDER BY dn.donated_on DESC`, [req.user.id]);
  res.json(rows);
}));

module.exports = router;
