const router = require('express').Router();
const { pool, withTx } = require('../db');
const U = require('../util');
const { wrap, allow, bad } = U;

router.use(allow('ADMIN'));

router.get('/stats', wrap(async (req, res) => {
  const [[c]] = await pool.query(
    `SELECT (SELECT COUNT(*) FROM donors) AS donors,
            (SELECT COUNT(*) FROM hospitals) AS hospitals,
            (SELECT COUNT(*) FROM users u JOIN roles r ON r.role_id = u.role_id WHERE r.role_name = 'PATIENT') AS patients,
            (SELECT COUNT(*) FROM hospital_staff) AS staff,
            (SELECT COUNT(*) FROM blood_requests WHERE priority = 'EMERGENCY' AND status IN ('PENDING','APPROVED')) AS emergencies_open,
            (SELECT COUNT(*) FROM transfers WHERE status = 'PENDING') AS pending_transfers,
            (SELECT COUNT(*) FROM organ_requests WHERE status IN ('PENDING','UNDER_REVIEW')) AS pending_organ_requests,
            (SELECT COALESCE(SUM(units_available),0) FROM v_expiring_batches) AS expiring_units`);
  const [stock] = await pool.query(
    `SELECT b.label AS blood_group, COALESCE(SUM(ib.units_available), 0) AS units
       FROM blood_groups b
       LEFT JOIN inventory_batches ib ON ib.bg_id = b.bg_id AND ib.status = 'AVAILABLE' AND ib.expiry_date >= CURDATE()
      GROUP BY b.bg_id, b.label ORDER BY b.bg_id`);
  const [byStatus] = await pool.query('SELECT status, COUNT(*) AS count FROM blood_requests GROUP BY status');
  const [months] = await pool.query('SELECT month, donations, units FROM v_donation_stats ORDER BY month DESC LIMIT 6');
  res.json({
    counts: { donors: +c.donors, hospitals: +c.hospitals, patients: +c.patients, staff: +c.staff },
    emergencies_open: +c.emergencies_open, pending_transfers: +c.pending_transfers,
    pending_organ_requests: +c.pending_organ_requests, expiring_units: +c.expiring_units,
    stock: stock.map((s) => ({ blood_group: s.blood_group, units: +s.units })),
    total_units: stock.reduce((a, s) => a + Number(s.units), 0),
    requests_by_status: byStatus.map((s) => ({ status: s.status, count: +s.count })),
    donations_by_month: months.map((m) => ({ month: m.month, donations: +m.donations, units: +m.units })),
  });
}));

router.get('/audit', wrap(async (req, res) => {
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 100, 1), 300);
  const [rows] = await pool.query(
    `SELECT a.log_id, a.action, a.entity, a.entity_id, a.details, a.created_at, u.full_name AS user_name
       FROM audit_logs a LEFT JOIN users u ON u.user_id = a.user_id
      ORDER BY a.log_id DESC LIMIT ?`, [limit]);
  res.json(rows);
}));

router.get('/users', wrap(async (req, res) => {
  const [rows] = await pool.query(
    `SELECT u.user_id, u.full_name, u.email, u.phone, r.role_name AS role, u.is_active, h.name AS hospital_name
       FROM users u JOIN roles r ON r.role_id = u.role_id
       LEFT JOIN hospital_staff hs ON hs.user_id = u.user_id
       LEFT JOIN hospitals h ON h.hospital_id = hs.hospital_id
      ORDER BY r.role_id, u.full_name`);
  res.json(rows);
}));

router.post('/staff', wrap(async (req, res) => {
  const b = req.body || {};
  const name = U.reqStr(b.full_name, 'Full name', 2, 100);
  const email = U.reqStr(b.email, 'Email', 5, 120).toLowerCase();
  if (!U.EMAIL_RE.test(email)) throw bad('Enter a valid email address');
  const phone = U.reqPhone(b.phone);
  const password = U.reqPassword(b.password);
  const hospitalId = U.reqInt(b.hospital_id, 'Hospital', 1, 2147483647);
  const id = await withTx(req.user.id, async (conn) => {
    const [[r]] = await conn.query("SELECT role_id FROM roles WHERE role_name = 'STAFF'");
    const [ins] = await conn.query('INSERT INTO users(role_id, full_name, email, phone, password_hash) VALUES (?,?,?,?,?)',
      [r.role_id, name, email, phone, U.hashPassword(password)]);
    await conn.query('INSERT INTO hospital_staff(user_id, hospital_id, designation) VALUES (?,?,?)',
      [ins.insertId, hospitalId, b.designation ? String(b.designation).slice(0, 60) : null]);
    await U.audit(conn, req.user.id, 'STAFF_CREATED', 'user', ins.insertId, `hospital=${hospitalId}`);
    return ins.insertId;
  });
  res.status(201).json({ user_id: id });
}));

module.exports = router;
