'use strict';
// Extra screens: matching/notify, record donation, transfers, organ module, admin (users, staff, audit)
const bind = (sel, ev, fn) => document.querySelectorAll(sel).forEach((b) => (b['on' + ev] = () => run(() => fn(b))));

async function matchesUI(id) {
  const m = await api('GET', `/requests/${id}/matches`);
  $('#mt').innerHTML = `<h2>Matching</h2><p>Usable stock at this hospital: <b>${m.local_units}</b> unit(s)</p>
    ${table(['Hospital', 'City', 'Group', 'Units', 'Nearest expiry'], m.stock.map((s) => ({ c: [esc(s.hospital_name), esc(s.city), esc(s.blood_group), s.units_available, esc(s.nearest_expiry)] })))}
    <h2 style="margin-top:16px">Eligible donors</h2>${table(['', 'Name', 'Group', 'City', 'Phone', ''], m.donors.map((d) => ({ c: [
      d.already_notified ? '' : `<input type="checkbox" class="dn" value="${d.donor_id}" style="width:auto;margin:0">`, esc(d.full_name), esc(d.blood_group), esc(d.city) + (d.same_city ? ' ✓' : ''), esc(d.phone), d.already_notified ? 'Notified' : ''] })))}
    <button id="nd">Notify selected donors</button>`;
  $('#nd').onclick = () => run(async () => {
    const ids = [...document.querySelectorAll('.dn:checked')].map((c) => +c.value);
    const r = await api('POST', `/requests/${id}/notify-donors`, { donor_ids: ids }); toast(r.notified + ' donor(s) notified'); matchesUI(id);
  });
}

Object.assign(V, {
  async donors() {
    const d = await api('GET', '/donors' + (S.dbg ? '?bg=' + encodeURIComponent(S.dbg) : ''));
    shell('donors', `<div class="card"><h2>Donors <select id="dbg" style="width:auto;display:inline-block;margin:0 0 0 10px">${opts(S.lk.bloodGroups, 'label', 'label', 'All groups')}</select></h2>${table(['Name', 'Group', 'City', 'Phone', 'Last donation', 'Donations', 'Eligible', ''],
      d.map((x) => ({ c: [esc(x.full_name), esc(x.blood_group), esc(x.city), esc(x.phone), esc(x.last_donation_date || '—'), x.total_donations, x.eligible ? '✅' : '⛔',
        x.eligible ? `<button data-d="${x.donor_id}">Record donation</button>` : ''] })))}</div>`);
    $('#dbg').value = S.dbg || ''; $('#dbg').onchange = (e) => { S.dbg = e.target.value; V.donors(); };
    bind('[data-d]', 'click', async (b) => {
      const units = prompt('Units donated (1 or 2)?', '1'); if (!units) return;
      const body = { donor_id: +b.dataset.d, units: +units };
      if (S.user.role === 'ADMIN') body.hospital_id = +prompt('Hospital id?', '1');
      await api('POST', '/inventory/donations', body); toast('Donation saved, batch created'); V.donors();
    });
  },
  async transfers() {
    const t = await api('GET', '/transfers'), st = S.user.role === 'STAFF', mine = S.user.hospitalId;
    shell('transfers', `${st ? `<div class="card"><h2>Request stock from another hospital</h2><form id="tf" class="row"><div><label>From hospital</label><select name="from_hospital_id">${S.lk.hospitals.filter((h) => h.hospital_id !== mine).map((h) => `<option value="${h.hospital_id}">${esc(h.name)} – ${esc(h.city)}</option>`).join('')}</select></div>
      <div><label>Group</label><select name="blood_group">${opts(S.lk.bloodGroups, 'label', 'label')}</select></div><div><label>Units</label><input type="number" name="units" value="1" min="1"></div><div><label>&nbsp;</label><button>Request</button></div></form></div>` : ''}
      <div class="card"><h2>Transfers</h2>${table(['#', 'From', 'To', 'Group', 'Units', 'Status', 'By', ''], t.map((x) => ({ c: [x.transfer_id, esc(x.from_hospital), esc(x.to_hospital), esc(x.blood_group), x.units, tag(x.status), esc(x.requested_by),
        x.status === 'PENDING' ? ((S.user.role === 'ADMIN' || x.from_hospital_id === mine) ? `<button data-t="${x.transfer_id}" data-a="complete">Dispatch</button>` : '') + `<button class="sec" data-t="${x.transfer_id}" data-a="cancel">Cancel</button>` : ''] })))}</div>`);
    if (st) $('#tf').onsubmit = (e) => { e.preventDefault(); run(async () => { await api('POST', '/transfers', form(e.target)); V.transfers(); }); };
    bind('[data-t]', 'click', async (b) => { await api('POST', `/transfers/${b.dataset.t}/${b.dataset.a}`); toast('Done'); V.transfers(); });
  },
  async organ() {
    if (S.user.role === 'DONOR') {
      const c = await api('GET', '/organ/consents'), by = Object.fromEntries(c.map((x) => [x.organ_id, x]));
      shell('organ', `<div class="card"><h2>Organ pledge</h2><p class="mut">Pledge records only; no allocation happens here. Your family should know your decision.</p>${table(['Organ', 'Status', ''], S.lk.organs.map((o) => ({ c: [esc(o.organ_name), by[o.organ_id] ? tag(by[o.organ_id].status) : '—',
        by[o.organ_id] && by[o.organ_id].status === 'GIVEN' ? `<button class="sec" data-o="${o.organ_id}" data-s="WITHDRAWN">Withdraw</button>` : `<button data-o="${o.organ_id}" data-s="GIVEN">Pledge</button>`] })))}</div>`);
      return bind('[data-o]', 'click', async (b) => {
        const body = { organ_id: +b.dataset.o, status: b.dataset.s };
        if (b.dataset.s === 'GIVEN') { if (!confirm('Have you informed your family about this decision?')) return; body.family_informed = true; body.witness_name = prompt('Witness name (optional)') || ''; }
        await api('PUT', '/organ/consents', body); V.organ();
      });
    }
    const r = await api('GET', '/organ/requests');
    shell('organ', `${S.user.role === 'STAFF' ? `<div class="card"><h2>New organ request (transplant centres only)</h2><form id="of" class="row"><div><label>Organ</label><select name="organ_id">${opts(S.lk.organs, 'organ_id', 'organ_name')}</select></div>
      <div><label>Group</label><select name="blood_group">${opts(S.lk.bloodGroups, 'label', 'label')}</select></div><div><label>Patient</label><input name="patient_name" required></div><div><label>Age</label><input type="number" name="patient_age" required></div>
      <div><label>Urgency</label><select name="urgency"><option>NORMAL</option><option>URGENT</option><option>CRITICAL</option></select></div><div><label>&nbsp;</label><button>Submit</button></div></form></div>` : ''}
      <div class="card"><h2>Organ requests</h2>${table(['#', 'Organ', 'Group', 'Patient', 'Urgency', 'Status', 'Hospital'], r.map((x) => ({ o: x, c: [x.organ_request_id, esc(x.organ_name), esc(x.blood_group), esc(x.patient_name), tag(x.urgency), tag(x.status), esc(x.hospital_name)] })), (x) => '#/organreq/' + x.organ_request_id)}</div>`);
    if (S.user.role === 'STAFF') $('#of').onsubmit = (e) => { e.preventDefault(); run(async () => { await api('POST', '/organ/requests', form(e.target)); V.organ(); }); };
  },
  async organreq(id) {
    const x = await api('GET', '/organ/requests/' + id), adm = S.user.role === 'ADMIN';
    const nxt = { PENDING: ['UNDER_REVIEW', 'REJECTED'], UNDER_REVIEW: ['VERIFIED', 'REJECTED'], VERIFIED: ['CLOSED'] }[x.status] || [];
    let cand = '';
    if (['UNDER_REVIEW', 'VERIFIED'].includes(x.status)) {
      const c = await api('GET', `/organ/requests/${id}/candidates`);
      cand = `<div class="card"><h2>Compatible pledged donors (anonymised, for clinical review)</h2>${table(['Donor', 'Group', 'City', 'Age', 'Consent date', 'Family informed'], (c.candidates || c).map((d) => ({ c: [d.donor_id, esc(d.blood_group), esc(d.city), d.age, esc(d.consent_date), d.family_informed ? 'Yes' : 'No'] })))}</div>`;
    }
    shell('organ', `<div class="card"><h2>Organ request #${x.organ_request_id} ${tag(x.urgency)} ${tag(x.status)}</h2><p><b>${esc(x.organ_name)}</b> (${esc(x.blood_group)}) for ${esc(x.patient_name)}, age ${x.patient_age}, at ${esc(x.hospital_name)}</p>
      <p class="mut">${esc(x.verification_notes || '')}${x.verified_by ? ' — ' + esc(x.verified_by) : ''}</p>
      ${adm && nxt.length ? `<label>Verification notes (required)</label><input id="vn">${nxt.map((n) => `<button data-v="${n}" class="${n === 'REJECTED' ? 'sec' : ''}">${n.replace('_', ' ')}</button>`).join('')}` : ''}<a href="#/organ"><button class="sec">Back</button></a></div>${cand}`);
    bind('[data-v]', 'click', async (b) => { await api('POST', `/organ/requests/${id}/verify`, { decision: b.dataset.v, notes: $('#vn').value }); V.organreq(id); });
  },
  async audit() {
    const a = await api('GET', '/admin/audit?limit=200');
    shell('audit', `<div class="card"><h2>Audit logs</h2>${table(['Time', 'User', 'Action', 'Entity', 'Details'], a.map((x) => ({ c: [esc(x.created_at), esc(x.user_name || 'system'), esc(x.action), esc(x.entity + ' #' + (x.entity_id ?? '')), esc(x.details || '')] })))}</div>`);
  },
  async users() {
    const u = await api('GET', '/admin/users');
    shell('users', `<div class="card"><h2>Add hospital staff</h2><form id="uf" class="row"><div><label>Name</label><input name="full_name" required></div><div><label>Email</label><input name="email" type="email" required></div><div><label>Phone</label><input name="phone" required></div>
      <div><label>Password</label><input name="password" required></div><div><label>Hospital</label><select name="hospital_id">${S.lk.hospitals.map((h) => `<option value="${h.hospital_id}">${esc(h.name)}</option>`).join('')}</select></div><div><label>&nbsp;</label><button>Create</button></div></form></div>
      <div class="card"><h2>Users</h2>${table(['Name', 'Email', 'Phone', 'Role', 'Hospital', 'Active'], u.map((x) => ({ c: [esc(x.full_name), esc(x.email), esc(x.phone), esc(x.role), esc(x.hospital_name || ''), x.is_active ? '✅' : '⛔'] })))}</div>`);
    $('#uf').onsubmit = (e) => { e.preventDefault(); run(async () => { await api('POST', '/admin/staff', form(e.target)); toast('Staff created'); V.users(); }); };
  },
});
