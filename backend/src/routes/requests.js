const router = require('express').Router();
const { pool, withTx } = require('../db');
const U = require('../util');
const { wrap, allow, HttpError, bad, COMPAT } = U;

const canManage = (user, r) =>
  user.role === 'ADMIN' || (user.role === 'STAFF' && r.hospital_id === user.hospitalId);

async function lockRequest(conn, id) {
  const [rows] = await conn.query('SELECT * FROM blood_requests WHERE request_id = ? FOR UPDATE', [id]);
  if (!rows.length) throw new HttpError(404, 'Request not found');
  return rows[0];
}
async function labelOf(db, bgId) {
  const [[r]] = await db.query('SELECT label FROM blood_groups WHERE bg_id = ?', [bgId]);
  return r.label;
}

// ---------- create / list ----------
router.post('/', allow('PATIENT', 'STAFF'), wrap(async (req, res) => {
  const b = req.body || {};
  const hospitalId = U.reqInt(b.hospital_id || req.user.hospitalId, 'Hospital', 1, 2147483647);
  const units = U.reqInt(b.units_needed, 'Units needed', 1, 20);
  const priority = U.reqEnum(b.priority || 'NORMAL', 'Priority', ['NORMAL', 'URGENT', 'EMERGENCY']);
  const patient = U.reqStr(b.patient_name, 'Patient name', 2, 100);
  const reason = b.reason ? String(b.reason).trim().slice(0, 255) : null;
  const bgId = await U.bgIdOf(U.reqEnum(b.blood_group, 'Blood group', Object.keys(COMPAT)));
  const [h] = await pool.query('SELECT hospital_id FROM hospitals WHERE hospital_id = ?', [hospitalId]);
  if (!h.length) throw bad('Hospital not found');
  const id = await withTx(req.user.id, async (conn) => {
    const [ins] = await conn.query(
      'INSERT INTO blood_requests(requester_id, hospital_id, bg_id, units_needed, priority, patient_name, reason) VALUES (?,?,?,?,?,?,?)',
      [req.user.id, hospitalId, bgId, units, priority, patient, reason]);
    return ins.insertId;
  });
  res.status(201).json({ request_id: id });
}));

router.get('/', allow('PATIENT', 'STAFF', 'ADMIN'), wrap(async (req, res) => {
  const where = [], p = [];
  if (req.user.role === 'PATIENT') { where.push('requester_id = ?'); p.push(req.user.id); }
  if (req.user.role === 'STAFF') { where.push('(hospital_id = ? OR requester_id = ?)'); p.push(req.user.hospitalId, req.user.id); }
  if (req.query.status) { where.push('status = ?'); p.push(req.query.status); }
  const [rows] = await pool.query(
    `SELECT * FROM v_request_details ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
      ORDER BY (status IN ('PENDING','APPROVED')) DESC, FIELD(priority,'EMERGENCY','URGENT','NORMAL'), created_at DESC LIMIT 200`, p);
  res.json(rows);
}));

// ---------- emergency mode: open urgent requests with resources that can serve them ----------
router.get('/emergency', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const where = ["r.status IN ('PENDING','APPROVED')", "r.priority IN ('EMERGENCY','URGENT')"], p = [];
  if (req.user.role === 'STAFF') { where.push('r.hospital_id = ?'); p.push(req.user.hospitalId); }
  const [rows] = await pool.query(
    `SELECT r.request_id, r.hospital_id, h.name AS hospital_name, b.label AS blood_group, r.units_needed,
            r.priority, r.status, r.patient_name, r.created_at
       FROM blood_requests r JOIN hospitals h ON h.hospital_id = r.hospital_id JOIN blood_groups b ON b.bg_id = r.bg_id
      WHERE ${where.join(' AND ')}
      ORDER BY FIELD(r.priority,'EMERGENCY','URGENT'), r.created_at LIMIT 50`, p);
  const stockSql = `SELECT COALESCE(SUM(units_available),0) AS n FROM inventory_batches
                     WHERE hospital_id ${'%OP%'} ? AND status = 'AVAILABLE' AND expiry_date >= CURDATE()
                       AND bg_id IN (SELECT bg_id FROM blood_groups WHERE label IN (?))`;
  for (const r of rows) {
    const groups = COMPAT[r.blood_group];
    const [[local]] = await pool.query(stockSql.replace('%OP%', '='), [r.hospital_id, groups]);
    const [[other]] = await pool.query(stockSql.replace('%OP%', '<>'), [r.hospital_id, groups]);
    r.local_units = Number(local.n);
    r.network_units = Number(other.n);
    r.can_fulfil_locally = r.local_units >= r.units_needed;
  }
  res.json(rows);
}));

// ---------- donor invitations (declared before /:id) ----------
router.get('/matches/mine', allow('DONOR'), wrap(async (req, res) => {
  const [rows] = await pool.query(
    `SELECT m.match_id, m.status, m.notified_at, r.request_id, r.priority, r.units_needed, b.label AS blood_group,
            h.name AS hospital_name, h.city, h.phone AS hospital_phone
       FROM donor_matches m
       JOIN donors d ON d.donor_id = m.donor_id
       JOIN blood_requests r ON r.request_id = m.request_id
       JOIN blood_groups b ON b.bg_id = r.bg_id
       JOIN hospitals h ON h.hospital_id = r.hospital_id
      WHERE d.user_id = ? ORDER BY m.notified_at DESC LIMIT 50`, [req.user.id]);
  res.json(rows);
}));

router.post('/matches/:matchId/respond', allow('DONOR'), wrap(async (req, res) => {
  const accept = !!(req.body || {}).accept;
  await withTx(req.user.id, async (conn) => {
    const [u] = await conn.query(
      `UPDATE donor_matches m JOIN donors d ON d.donor_id = m.donor_id
          SET m.status = ?, m.responded_at = NOW()
        WHERE m.match_id = ? AND d.user_id = ? AND m.status = 'NOTIFIED'`,
      [accept ? 'ACCEPTED' : 'DECLINED', req.params.matchId, req.user.id]);
    if (u.affectedRows !== 1) throw new HttpError(409, 'Invitation already answered or not found');
    if (accept) {
      await conn.query(
        `INSERT INTO notifications(user_id, type, title, message, related_id)
         SELECT hs.user_id, 'DONOR_MATCH', 'Donor accepted', CONCAT(?, ' accepted blood request #', r.request_id), r.request_id
           FROM donor_matches m JOIN blood_requests r ON r.request_id = m.request_id
           JOIN hospital_staff hs ON hs.hospital_id = r.hospital_id WHERE m.match_id = ?`,
        [req.user.name, req.params.matchId]);
    }
  });
  res.json({ ok: true });
}));

// ---------- detail ----------
router.get('/:id', allow('PATIENT', 'STAFF', 'ADMIN'), wrap(async (req, res) => {
  const [rows] = await pool.query('SELECT * FROM v_request_details WHERE request_id = ?', [req.params.id]);
  if (!rows.length) throw new HttpError(404, 'Request not found');
  const r = rows[0];
  const manage = canManage(req.user, r);
  if (req.user.role === 'PATIENT' && r.requester_id !== req.user.id) throw new HttpError(403, 'Not your request');
  if (req.user.role === 'STAFF' && !manage && r.requester_id !== req.user.id) throw new HttpError(403, 'Not your hospital\'s request');
  const [allocations] = await pool.query(
    `SELECT ra.allocation_id, ra.batch_id, ra.units_allocated, ra.allocated_at, ib.expiry_date, b.label AS blood_group
       FROM request_allocations ra JOIN inventory_batches ib ON ib.batch_id = ra.batch_id
       JOIN blood_groups b ON b.bg_id = ib.bg_id WHERE ra.request_id = ?`, [req.params.id]);
  const [[mc]] = await pool.query(
    "SELECT COUNT(*) AS invited, SUM(status='ACCEPTED') AS accepted FROM donor_matches WHERE request_id = ?", [req.params.id]);
  res.json({ request: r, allocations, can_manage: manage, donors_invited: Number(mc.invited), donors_accepted: Number(mc.accepted || 0) });
}));

// ---------- matching: usable stock + eligible donors ----------
router.get('/:id/matches', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const [rows] = await pool.query('SELECT * FROM blood_requests WHERE request_id = ?', [req.params.id]);
  if (!rows.length) throw new HttpError(404, 'Request not found');
  const r = rows[0];
  if (!canManage(req.user, r)) throw new HttpError(403, 'Not allowed');
  const label = await labelOf(pool, r.bg_id);
  const groups = COMPAT[label];
  const [[hosp]] = await pool.query('SELECT city FROM hospitals WHERE hospital_id = ?', [r.hospital_id]);
  const [stock] = await pool.query(
    `SELECT v.hospital_id, v.hospital_name, v.city, v.blood_group, v.units_available, v.nearest_expiry
       FROM v_inventory_summary v WHERE v.units_available > 0 AND v.blood_group IN (?)
      ORDER BY (v.hospital_id = ?) DESC, (v.blood_group = ?) DESC, v.nearest_expiry LIMIT 30`,
    [groups, r.hospital_id, label]);
  const [donors] = await pool.query(
    `SELECT d.donor_id, u.full_name, u.phone, b.label AS blood_group, d.city,
            (d.city = ?) AS same_city,
            EXISTS (SELECT 1 FROM donor_matches m WHERE m.request_id = ? AND m.donor_id = d.donor_id) AS already_notified
       FROM donors d JOIN users u ON u.user_id = d.user_id JOIN blood_groups b ON b.bg_id = d.bg_id
      WHERE b.label IN (?) AND d.is_available = 1 AND u.is_active = 1 AND ${U.ELIGIBLE_SQL}
      ORDER BY same_city DESC, (b.label = ?) DESC, u.full_name LIMIT 30`,
    [hosp.city, r.request_id, groups, label]);
  res.json({ stock, donors, local_units: stock.filter((s) => s.hospital_id === r.hospital_id).reduce((a, s) => a + Number(s.units_available), 0) });
}));

router.post('/:id/notify-donors', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const ids = Array.isArray(req.body.donor_ids) ? req.body.donor_ids.map(Number).filter(Number.isInteger) : [];
  if (!ids.length || ids.length > 20) throw bad('Select between 1 and 20 donors');
  const count = await withTx(req.user.id, async (conn) => {
    const r = await lockRequest(conn, req.params.id);
    if (!canManage(req.user, r)) throw new HttpError(403, 'Not allowed');
    if (!['PENDING', 'APPROVED'].includes(r.status)) throw new HttpError(409, 'Request is closed');
    const label = await labelOf(conn, r.bg_id);
    const [[h]] = await conn.query('SELECT name, city FROM hospitals WHERE hospital_id = ?', [r.hospital_id]);
    const [donors] = await conn.query(
      `SELECT d.donor_id, d.user_id FROM donors d JOIN blood_groups b ON b.bg_id = d.bg_id
        WHERE d.donor_id IN (?) AND d.is_available = 1 AND b.label IN (?) AND ${U.ELIGIBLE_SQL}`, [ids, COMPAT[label]]);
    let n = 0;
    for (const d of donors) {
      const [ins] = await conn.query('INSERT IGNORE INTO donor_matches(request_id, donor_id) VALUES (?,?)', [r.request_id, d.donor_id]);
      if (ins.affectedRows === 1) {
        n++;
        await conn.query(
          `INSERT INTO notifications(user_id, type, title, message, related_id) VALUES (?, 'DONOR_MATCH', ?, ?, ?)`,
          [d.user_id, `${r.priority === 'EMERGENCY' ? 'URGENT: ' : ''}Blood needed`,
           `${r.units_needed} unit(s) of ${label} needed at ${h.name}, ${h.city}. Open the app to respond.`, r.request_id]);
      }
    }
    await U.audit(conn, req.user.id, 'DONORS_NOTIFIED', 'blood_request', r.request_id, `${n} donor(s)`);
    return n;
  });
  res.json({ notified: count });
}));

// ---------- status workflow: PENDING -> APPROVED -> FULFILLED, or REJECTED ----------
router.post('/:id/approve', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  await withTx(req.user.id, async (conn) => {
    const r = await lockRequest(conn, req.params.id);
    if (!canManage(req.user, r)) throw new HttpError(403, 'Not allowed');
    if (r.status !== 'PENDING') throw new HttpError(409, `Request is already ${r.status}`);
    await conn.query("UPDATE blood_requests SET status = 'APPROVED', reviewed_by = ?, remarks = ? WHERE request_id = ? AND status = 'PENDING'",
      [req.user.id, (req.body.remarks || 'Verified').toString().slice(0, 255), r.request_id]);
  });
  res.json({ ok: true });
}));

router.post('/:id/reject', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const remarks = U.reqStr(req.body.remarks, 'Reason for rejection', 3, 255);
  await withTx(req.user.id, async (conn) => {
    const r = await lockRequest(conn, req.params.id);
    if (!canManage(req.user, r)) throw new HttpError(403, 'Not allowed');
    if (!['PENDING', 'APPROVED'].includes(r.status)) throw new HttpError(409, `Request is already ${r.status}`);
    await conn.query('UPDATE blood_requests SET status = ?, reviewed_by = ?, remarks = ? WHERE request_id = ?',
      ['REJECTED', req.user.id, remarks, r.request_id]);
  });
  res.json({ ok: true });
}));

// ---------- fulfilment: one transaction; locks batches, earliest-expiry first, never expired stock ----------
router.post('/:id/fulfil', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const allocations = await withTx(req.user.id, async (conn) => {
    const r = await lockRequest(conn, req.params.id);
    if (!canManage(req.user, r)) throw new HttpError(403, 'Not allowed');
    if (r.status !== 'APPROVED')
      throw new HttpError(409, r.status === 'FULFILLED' ? 'Request is already fulfilled' : 'Only approved requests can be fulfilled');
    const label = await labelOf(conn, r.bg_id);
    const [batches] = await conn.query(
      `SELECT batch_id, units_available FROM inventory_batches
        WHERE hospital_id = ? AND status = 'AVAILABLE' AND expiry_date >= CURDATE() AND units_available > 0
          AND bg_id IN (SELECT bg_id FROM blood_groups WHERE label IN (?))
        ORDER BY (bg_id = ?) DESC, expiry_date ASC, batch_id ASC FOR UPDATE`,
      [r.hospital_id, COMPAT[label], r.bg_id]);
    let need = r.units_needed;
    const plan = [];
    for (const b of batches) {
      if (need <= 0) break;
      const take = Math.min(need, b.units_available);
      plan.push({ batch_id: b.batch_id, take });
      need -= take;
    }
    if (need > 0)
      throw new HttpError(409, `Insufficient unexpired stock: short by ${need} unit(s). Request a transfer or invite donors.`);
    for (const a of plan) {
      await conn.query('INSERT INTO request_allocations(request_id, batch_id, units_allocated) VALUES (?,?,?)',
        [r.request_id, a.batch_id, a.take]);
      const [u] = await conn.query(
        'UPDATE inventory_batches SET units_available = units_available - ? WHERE batch_id = ? AND units_available >= ?',
        [a.take, a.batch_id, a.take]);
      if (u.affectedRows !== 1) throw new HttpError(409, 'Stock changed while processing. Please retry.');
      await U.audit(conn, req.user.id, 'STOCK_ALLOCATED', 'inventory_batch', a.batch_id, `request=${r.request_id}, units=${a.take}`);
    }
    const [f] = await conn.query(
      "UPDATE blood_requests SET status = 'FULFILLED', fulfilled_by = ?, fulfilled_at = NOW() WHERE request_id = ? AND status = 'APPROVED'",
      [req.user.id, r.request_id]);
    if (f.affectedRows !== 1) throw new HttpError(409, 'Request already processed');
    return plan;
  });
  res.json({ ok: true, allocations });
}));

module.exports = router;
