'use strict';
// Dashboards, filters, profile, donor home (matches the Flutter app)
const emTile = (e) => `<tr data-go="#/req/${e.request_id}"><td>${tag(e.priority)}</td><td>#${e.request_id} ${esc(e.patient_name)}</td><td>${esc(e.blood_group)} × ${e.units_needed}</td><td>${esc(e.hospital_name)}</td>
  <td>${e.can_fulfil_locally ? '✔ stock OK' : `✖ short (local ${e.local_units}, other hospitals ${e.network_units})`}</td></tr>`;
const reqTable = (rq) => table(['#', 'Patient', 'Group', 'Units', 'Priority', 'Status', 'Hospital'],
  rq.map((x) => ({ o: x, c: [x.request_id, esc(x.patient_name), esc(x.blood_group), x.units_needed, tag(x.priority), tag(x.status), esc(x.hospital_name)] })), (x) => '#/req/' + x.request_id);
const stockGrid = (st) => `<div class="grid">${st.map((x) => `<div class="stat"><b>${x.units_available ?? x.units}</b>${esc(x.blood_group)}</div>`).join('')}</div>`;

V.home = async function () {
  const r = S.user.role;
  if (r === 'DONOR') return donorHome();
  const em = await api('GET', '/requests/emergency'); let top = '';
  if (r === 'ADMIN') {
    const s = await api('GET', '/admin/stats');
    top = `<div class="grid">${[['Donors', s.counts.donors], ['Hospitals', s.counts.hospitals], ['Patients', s.counts.patients], ['Staff', s.counts.staff], ['Units in stock', s.total_units], ['Open emergencies', s.emergencies_open], ['Pending transfers', s.pending_transfers], ['Pending organ requests', s.pending_organ_requests], ['Expiring units', s.expiring_units]].map(([a, b]) => `<div class="card stat"><b>${b}</b>${a}</div>`).join('')}</div>
      <div class="card"><h2>Stock by blood group</h2>${stockGrid(s.stock)}</div>
      <div class="row"><div class="card"><h2>Requests by status</h2>${table(['Status', 'Count'], s.requests_by_status.map((x) => ({ c: [tag(x.status), x.count] })))}</div>
      <div class="card"><h2>Donations by month</h2>${table(['Month', 'Donations', 'Units'], s.donations_by_month.map((x) => ({ c: [esc(x.month), x.donations, x.units] })))}</div></div>`;
  } else if (r === 'STAFF') {
    const [st, pend, bt] = await Promise.all([api('GET', '/inventory/hospital-stock'), api('GET', '/requests?status=PENDING'), api('GET', '/inventory/batches')]);
    const exp = bt.filter((b) => b.status === 'AVAILABLE' && b.days_left <= 5);
    const low = st.filter((x) => x.units_available < 5).map((x) => x.blood_group);
    top = `<div class="card"><h2>${esc(S.user.hospital_name || 'My hospital')} – stock</h2>${stockGrid(st)}${low.length ? `<p class="err">⚠ Low stock: ${low.join(', ')}</p>` : ''}</div>
      <div class="grid"><div class="card stat"><b>${pend.length}</b>Pending requests</div><div class="card stat"><b>${exp.length}</b>Batches expiring ≤ 5 days</div></div>
      ${exp.length ? `<div class="card"><h2>Expiring soon</h2>${table(['Batch', 'Group', 'Units', 'Expiry', 'Days'], exp.map((b) => ({ c: [b.batch_id, esc(b.blood_group), b.units_available, esc(b.expiry_date), b.days_left] })))}</div>` : ''}`;
  }
  shell('home', `${top}<div class="card"><h2>🚨 Emergency &amp; urgent requests</h2><div class="scroll"><table>${em.map(emTile).join('') || '<tr><td class="mut">No open emergencies</td></tr>'}</table></div></div>
    <div class="card"><h2>Blood requests <select id="rs" style="width:auto;display:inline-block;margin:0 0 0 10px"><option value="">ALL</option>${['PENDING', 'APPROVED', 'FULFILLED', 'REJECTED'].map((s) => `<option>${s}</option>`).join('')}</select></h2><div id="rl"></div></div>`);
  const load = () => run(async () => { $('#rl').innerHTML = reqTable(await api('GET', '/requests' + ($('#rs').value ? '?status=' + $('#rs').value : ''))); });
  $('#rs').onchange = load; load();
};

async function donorHome() {
  const [me, h, m] = await Promise.all([api('GET', '/me'), api('GET', '/donors/me/history'), api('GET', '/requests/matches/mine')]);
  const d = me.donor || {};
  shell('home', `<div class="card"><h2>Hello, ${esc(me.full_name)} 🩸</h2><p>Blood group <b>${esc(d.blood_group)}</b> · ${d.eligible ? '✅ Eligible to donate' : '⛔ Not eligible until ' + esc(d.next_eligible_date || '—')}</p>
    <label style="font-size:15px;color:inherit"><input type="checkbox" id="av" style="width:auto;margin-right:8px" ${d.is_available ? 'checked' : ''}>Available to donate (hospitals can invite me)</label></div>
    <div class="card"><h2>Invitations</h2>${table(['Hospital', 'City', 'Group', 'Units', 'Priority', 'Status', ''], m.map((x) => ({ c: [esc(x.hospital_name), esc(x.city), esc(x.blood_group), x.units_needed, tag(x.priority), tag(x.status),
      x.status === 'NOTIFIED' ? `<button data-m="${x.match_id}" data-a="1">Accept</button><button class="sec" data-m="${x.match_id}" data-a="">Decline</button>` : ''] })))}</div>
    <div class="card"><h2>My donations</h2>${table(['Date', 'Units', 'Hospital', 'City'], h.map((x) => ({ c: [esc(x.donated_on), x.units, esc(x.hospital_name), esc(x.city)] })))}</div>`);
  $('#av').onchange = (e) => run(async () => { await api('PUT', '/me', { donor: { is_available: e.target.checked } }); toast('Updated'); });
  bind('[data-m]', 'click', async (b) => { await api('POST', `/requests/matches/${b.dataset.m}/respond`, { accept: !!b.dataset.a }); donorHome(); });
}

V.find = async function () {
  shell('find', `<div class="card"><h2>Find blood</h2><form id="sf" class="row"><div><label>Blood group needed</label><select name="bg">${opts(S.lk.bloodGroups, 'label', 'label', 'Any')}</select></div>
    <div><label>City</label><input name="city"></div><div><label>&nbsp;</label><button>Search</button></div></form>
    <label style="font-size:14px;color:inherit"><input type="checkbox" id="ex" style="width:auto;margin-right:6px">Exact blood group only (hide compatible groups)</label></div><div id="sr"></div>`);
  const go = () => run(async () => {
    const q = new URLSearchParams(Object.entries(form($('#sf'))).filter(([, v]) => v)); if ($('#ex').checked) q.set('exact', '1');
    const rows = await api('GET', '/inventory/search?' + q);
    $('#sr').innerHTML = `<div class="card">${table(['Hospital', 'City', 'Type', 'Group', 'Units', 'Nearest expiry', 'Phone'], rows.map((x) => ({ c: [esc(x.hospital_name), esc(x.city), esc(x.facility_type), esc(x.blood_group), x.units_available, esc(x.nearest_expiry), esc(x.phone)] })))}</div>`;
  });
  $('#sf').onsubmit = (e) => { e.preventDefault(); go(); }; $('#ex').onchange = go; go();
};

V.notes = async function () {
  const n = await api('GET', '/notifications');
  shell('notes', `<div class="card"><h2>Notifications <button class="sec" id="ra">Mark all read</button></h2>${n.map((x) => `<p data-n="${x.is_read ? '' : x.notification_id}" style="cursor:pointer;${x.is_read ? 'opacity:.6' : 'border-left:3px solid var(--red);padding-left:8px'}"><b>${esc(x.title)}</b><br>${esc(x.message)}<br><span class="mut">${esc(x.created_at)}</span></p>`).join('') || '<p class="mut">No notifications</p>'}</div>`);
  $('#ra').onclick = () => run(async () => { await api('POST', '/notifications/read-all'); V.notes(); });
  bind('[data-n]', 'click', async (p) => { if (p.dataset.n) { await api('POST', `/notifications/${p.dataset.n}/read`); V.notes(); } });
};

V.profile = async function () {
  const me = await api('GET', '/me'), d = me.donor;
  shell('profile', `<div class="card"><h2>My profile</h2><p class="mut">${esc(me.email)} · ${esc(me.role)}${me.hospital_name ? ' · ' + esc(me.hospital_name) : ''}${d ? ' · ' + esc(d.blood_group) : ''}</p>
    <form id="pf"><div class="row"><div><label>Full name</label><input name="full_name" value="${esc(me.full_name)}"></div><div><label>Phone</label><input name="phone" value="${esc(me.phone)}"></div></div>
    ${d ? `<div class="row"><div><label>City</label><input name="city" value="${esc(d.city)}"></div><div><label>Weight (kg)</label><input name="weight_kg" type="number" value="${esc(d.weight_kg)}"></div></div>` : ''}
    <h2>Change password (optional)</h2><div class="row"><div><label>Current password</label><input type="password" name="current_password"></div><div><label>New password</label><input type="password" name="new_password"></div></div><button>Save</button></form></div>`);
  $('#pf').onsubmit = (e) => { e.preventDefault(); run(async () => {
    const f = form(e.target), body = { full_name: f.full_name, phone: f.phone };
    if (d) body.donor = { city: f.city, weight_kg: +f.weight_kg };
    if (f.new_password) { body.new_password = f.new_password; body.current_password = f.current_password; }
    S.user = await api('PUT', '/me', body); toast('Profile updated'); V.profile();
  }); };
};
