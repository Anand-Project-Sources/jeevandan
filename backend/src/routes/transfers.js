const router = require('express').Router();
const { pool, withTx } = require('../db');
const U = require('../util');
const { wrap, allow, HttpError, bad, COMPAT } = U;

router.get('/', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const p = [];
  let where = '1=1';
  if (req.user.role === 'STAFF') { where = '(t.from_hospital_id = ? OR t.to_hospital_id = ?)'; p.push(req.user.hospitalId, req.user.hospitalId); }
  const [rows] = await pool.query(
    `SELECT t.transfer_id, t.from_hospital_id, fh.name AS from_hospital, t.to_hospital_id, th.name AS to_hospital,
            b.label AS blood_group, t.units, t.status, t.created_at, t.completed_at, u.full_name AS requested_by
       FROM transfers t JOIN hospitals fh ON fh.hospital_id = t.from_hospital_id
       JOIN hospitals th ON th.hospital_id = t.to_hospital_id
       JOIN blood_groups b ON b.bg_id = t.bg_id JOIN users u ON u.user_id = t.requested_by
      WHERE ${where} ORDER BY (t.status = 'PENDING') DESC, t.created_at DESC LIMIT 100`, p);
  res.json(rows);
}));

// A hospital asks another hospital for stock; "to" is always the requester's own hospital
router.post('/', allow('STAFF'), wrap(async (req, res) => {
  const b = req.body || {};
  const from = U.reqInt(b.from_hospital_id, 'Source hospital', 1, 2147483647);
  const units = U.reqInt(b.units, 'Units', 1, 50);
  const bgId = await U.bgIdOf(U.reqEnum(b.blood_group, 'Blood group', Object.keys(COMPAT)));
  if (from === req.user.hospitalId) throw bad('Choose a different hospital as the source');
  const [h] = await pool.query('SELECT hospital_id FROM hospitals WHERE hospital_id = ?', [from]);
  if (!h.length) throw bad('Source hospital not found');
  const id = await withTx(req.user.id, async (conn) => {
    const [ins] = await conn.query(
      'INSERT INTO transfers(from_hospital_id, to_hospital_id, bg_id, units, requested_by) VALUES (?,?,?,?,?)',
      [from, req.user.hospitalId, bgId, units, req.user.id]);
    return ins.insertId;
  });
  res.status(201).json({ transfer_id: id });
}));

// Source hospital dispatches: deduct (earliest expiry first) and create batches at the destination atomically
router.post('/:id/complete', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  await withTx(req.user.id, async (conn) => {
    const [[t]] = await conn.query('SELECT * FROM transfers WHERE transfer_id = ? FOR UPDATE', [req.params.id]);
    if (!t) throw new HttpError(404, 'Transfer not found');
    if (req.user.role === 'STAFF' && t.from_hospital_id !== req.user.hospitalId)
      throw new HttpError(403, 'Only the sending hospital can complete a transfer');
    if (t.status !== 'PENDING') throw new HttpError(409, `Transfer is already ${t.status}`);
    const [batches] = await conn.query(
      `SELECT batch_id, units_available, collected_on, expiry_date FROM inventory_batches
        WHERE hospital_id = ? AND bg_id = ? AND status = 'AVAILABLE' AND expiry_date >= CURDATE() AND units_available > 0
        ORDER BY expiry_date, batch_id FOR UPDATE`, [t.from_hospital_id, t.bg_id]);
    let need = t.units;
    const moves = [];
    for (const b of batches) {
      if (need <= 0) break;
      const take = Math.min(need, b.units_available);
      moves.push({ ...b, take });
      need -= take;
    }
    if (need > 0) throw new HttpError(409, `Sending hospital has only ${t.units - need} usable unit(s) of this group`);
    for (const m of moves) {
      const [u] = await conn.query(
        'UPDATE inventory_batches SET units_available = units_available - ? WHERE batch_id = ? AND units_available >= ?',
        [m.take, m.batch_id, m.take]);
      if (u.affectedRows !== 1) throw new HttpError(409, 'Stock changed while processing. Please retry.');
      await conn.query(
        `INSERT INTO inventory_batches(hospital_id, bg_id, units_total, units_available, collected_on, expiry_date, source_transfer_id)
         VALUES (?,?,?,?,?,?,?)`,
        [t.to_hospital_id, t.bg_id, m.take, m.take, m.collected_on, m.expiry_date, t.transfer_id]);
    }
    const [f] = await conn.query("UPDATE transfers SET status = 'COMPLETED', completed_at = NOW() WHERE transfer_id = ? AND status = 'PENDING'", [t.transfer_id]);
    if (f.affectedRows !== 1) throw new HttpError(409, 'Transfer already processed');
  });
  res.json({ ok: true });
}));

router.post('/:id/cancel', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  await withTx(req.user.id, async (conn) => {
    const [[t]] = await conn.query('SELECT * FROM transfers WHERE transfer_id = ? FOR UPDATE', [req.params.id]);
    if (!t) throw new HttpError(404, 'Transfer not found');
    if (req.user.role === 'STAFF' && ![t.from_hospital_id, t.to_hospital_id].includes(req.user.hospitalId))
      throw new HttpError(403, 'Not allowed');
    if (t.status !== 'PENDING') throw new HttpError(409, `Transfer is already ${t.status}`);
    await conn.query("UPDATE transfers SET status = 'CANCELLED' WHERE transfer_id = ? AND status = 'PENDING'", [t.transfer_id]);
  });
  res.json({ ok: true });
}));

module.exports = router;
