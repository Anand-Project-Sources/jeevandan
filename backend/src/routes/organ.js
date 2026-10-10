const router = require('express').Router();
const { pool, withTx } = require('../db');
const U = require('../util');
const { wrap, allow, HttpError, bad, COMPAT } = U;

// NOTE: this module supports consent records and eligibility *verification workflow* only.
// It never allocates organs; allocation is a clinical/legal decision (THOA 1994, NOTTO/SOTTO protocols).

router.get('/consents', allow('DONOR'), wrap(async (req, res) => {
  const [rows] = await pool.query(
    `SELECT oc.organ_id, ot.organ_name, oc.status, oc.consent_date, oc.family_informed, oc.witness_name
       FROM organ_consents oc JOIN donors d ON d.donor_id = oc.donor_id JOIN organ_types ot ON ot.organ_id = oc.organ_id
      WHERE d.user_id = ?`, [req.user.id]);
  res.json(rows);
}));

router.put('/consents', allow('DONOR'), wrap(async (req, res) => {
  const b = req.body || {};
  const organId = U.reqInt(b.organ_id, 'Organ', 1, 127);
  const status = U.reqEnum(b.status, 'Status', ['GIVEN', 'WITHDRAWN']);
  const family = !!b.family_informed;
  if (status === 'GIVEN' && !family) throw bad('Please confirm that your family has been informed of your decision');
  const witness = b.witness_name ? String(b.witness_name).trim().slice(0, 100) : null;
  await withTx(req.user.id, async (conn) => {
    const [[d]] = await conn.query('SELECT donor_id FROM donors WHERE user_id = ?', [req.user.id]);
    const [o] = await conn.query('SELECT organ_id FROM organ_types WHERE organ_id = ?', [organId]);
    if (!d || !o.length) throw bad('Invalid donor or organ');
    await conn.query(
      `INSERT INTO organ_consents(donor_id, organ_id, status, consent_date, family_informed, witness_name)
       VALUES (?,?,?,CURDATE(),?,?)
       ON DUPLICATE KEY UPDATE status = VALUES(status), consent_date = CURDATE(),
         family_informed = VALUES(family_informed), witness_name = VALUES(witness_name)`,
      [d.donor_id, organId, status, family, witness]);
    await U.audit(conn, req.user.id, status === 'GIVEN' ? 'ORGAN_CONSENT_GIVEN' : 'ORGAN_CONSENT_WITHDRAWN', 'organ_consent', organId, `organ=${organId}`);
  });
  res.json({ ok: true });
}));

const BASE = `SELECT orq.organ_request_id, orq.hospital_id, h.name AS hospital_name, ot.organ_name, b.label AS blood_group,
                     orq.patient_name, orq.patient_age, orq.urgency, orq.status, orq.verification_notes,
                     orq.created_at, u.full_name AS requested_by, v.full_name AS verified_by
                FROM organ_requests orq
                JOIN hospitals h ON h.hospital_id = orq.hospital_id
                JOIN organ_types ot ON ot.organ_id = orq.organ_id
                JOIN blood_groups b ON b.bg_id = orq.bg_id
                JOIN users u ON u.user_id = orq.requested_by
                LEFT JOIN users v ON v.user_id = orq.verified_by`;

router.get('/requests', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const p = [];
  let where = '';
  if (req.user.role === 'STAFF') { where = 'WHERE orq.hospital_id = ?'; p.push(req.user.hospitalId); }
  const [rows] = await pool.query(`${BASE} ${where} ORDER BY FIELD(orq.status,'PENDING','UNDER_REVIEW','VERIFIED','REJECTED','CLOSED'), FIELD(orq.urgency,'CRITICAL','URGENT','NORMAL'), orq.created_at DESC LIMIT 100`, p);
  res.json(rows);
}));

router.get('/requests/:id', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const [rows] = await pool.query(`${BASE} WHERE orq.organ_request_id = ?`, [req.params.id]);
  if (!rows.length) throw new HttpError(404, 'Organ request not found');
  if (req.user.role === 'STAFF' && rows[0].hospital_id !== req.user.hospitalId) throw new HttpError(403, 'Not allowed');
  res.json(rows[0]);
}));

router.post('/requests', allow('STAFF'), wrap(async (req, res) => {
  const b = req.body || {};
  const [[h]] = await pool.query('SELECT is_transplant_center FROM hospitals WHERE hospital_id = ?', [req.user.hospitalId]);
  if (!h || !h.is_transplant_center) throw new HttpError(403, 'Only registered transplant centres can raise organ requests');
  const organId = U.reqInt(b.organ_id, 'Organ', 1, 127);
  const bgId = await U.bgIdOf(U.reqEnum(b.blood_group, 'Blood group', Object.keys(COMPAT)));
  const name = U.reqStr(b.patient_name, 'Patient name', 2, 100);
  const age = U.reqInt(b.patient_age, 'Patient age', 0, 120);
  const urgency = U.reqEnum(b.urgency || 'NORMAL', 'Urgency', ['NORMAL', 'URGENT', 'CRITICAL']);
  const id = await withTx(req.user.id, async (conn) => {
    const [ins] = await conn.query(
      'INSERT INTO organ_requests(hospital_id, organ_id, bg_id, patient_name, patient_age, urgency, requested_by) VALUES (?,?,?,?,?,?,?)',
      [req.user.hospitalId, organId, bgId, name, age, urgency, req.user.id]);
    await U.audit(conn, req.user.id, 'ORGAN_REQUEST_CREATED', 'organ_request', ins.insertId, `organ=${organId}, urgency=${urgency}`);
    return ins.insertId;
  });
  res.status(201).json({ organ_request_id: id });
}));

// Authorised verification (admin acts as the medical board / authorisation committee)
const NEXT = { PENDING: ['UNDER_REVIEW', 'REJECTED'], UNDER_REVIEW: ['VERIFIED', 'REJECTED'], VERIFIED: ['CLOSED'], REJECTED: [], CLOSED: [] };
router.post('/requests/:id/verify', allow('ADMIN'), wrap(async (req, res) => {
  const decision = U.reqEnum(req.body.decision, 'Decision', ['UNDER_REVIEW', 'VERIFIED', 'REJECTED', 'CLOSED']);
  const notes = U.reqStr(req.body.notes, 'Verification notes', 5, 500);
  await withTx(req.user.id, async (conn) => {
    const [[r]] = await conn.query('SELECT status FROM organ_requests WHERE organ_request_id = ? FOR UPDATE', [req.params.id]);
    if (!r) throw new HttpError(404, 'Organ request not found');
    if (!NEXT[r.status].includes(decision)) throw new HttpError(409, `Cannot move from ${r.status} to ${decision}`);
    await conn.query('UPDATE organ_requests SET status = ?, verified_by = ?, verification_notes = ? WHERE organ_request_id = ?',
      [decision, req.user.id, notes, req.params.id]);
  });
  res.json({ ok: true });
}));

// Consenting, ABO-compatible donors for clinical review ONLY. No contact data, no automatic allocation.
router.get('/requests/:id/candidates', allow('STAFF', 'ADMIN'), wrap(async (req, res) => {
  const [rows] = await pool.query(
    `SELECT orq.hospital_id, orq.organ_id, orq.status, b.label FROM organ_requests orq
       JOIN blood_groups b ON b.bg_id = orq.bg_id WHERE orq.organ_request_id = ?`, [req.params.id]);
  if (!rows.length) throw new HttpError(404, 'Organ request not found');
  const r = rows[0];
  if (req.user.role === 'STAFF' && r.hospital_id !== req.user.hospitalId) throw new HttpError(403, 'Not allowed');
  if (!['UNDER_REVIEW', 'VERIFIED'].includes(r.status))
    throw new HttpError(409, 'Candidates are available only after the request is under review or verified');
  const [cands] = await pool.query(
    `SELECT d.donor_id, b.label AS blood_group, d.city, TIMESTAMPDIFF(YEAR, d.date_of_birth, CURDATE()) AS age,
            oc.consent_date, oc.family_informed
       FROM organ_consents oc JOIN donors d ON d.donor_id = oc.donor_id
       JOIN users u ON u.user_id = d.user_id JOIN blood_groups b ON b.bg_id = d.bg_id
      WHERE oc.organ_id = ? AND oc.status = 'GIVEN' AND u.is_active = 1 AND b.label IN (?)
      ORDER BY (b.label = ?) DESC, oc.consent_date LIMIT 50`,
    [r.organ_id, U.organDonorGroups(r.label), r.label]);
  res.json({
    notice: 'For clinical review only. Candidates are pledged donors with a compatible ABO group. Allocation and any contact must follow THOA 1994 and the authorised transplant committee/NOTTO protocol.',
    candidates: cands,
  });
}));

module.exports = router;
