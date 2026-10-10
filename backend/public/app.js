'use strict';
const $ = (s) => document.querySelector(s);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const tag = (t) => `<span class="tag ${esc(t)}">${esc(t)}</span>`;
const S = { token: localStorage.getItem('token'), user: null, lk: null };

async function api(method, path, body) {
  const r = await fetch('/api' + path, {
    method, headers: { 'Content-Type': 'application/json', ...(S.token ? { Authorization: 'Bearer ' + S.token } : {}) },
    body: body ? JSON.stringify(body) : undefined });
  let d = null; try { d = await r.json(); } catch (_) {}
  if (r.status === 401 && S.token) { logout(); }
  if (!r.ok) throw new Error((d && d.error) || 'Request failed (' + r.status + ')');
  return d;
}
const toast = (m) => { const t = $('#toast'); t.textContent = m; t.style.display = 'block'; setTimeout(() => (t.style.display = 'none'), 3000); };
const run = async (fn) => { try { await fn(); } catch (e) { toast(e.message); } };
const form = (f) => Object.fromEntries(new FormData(f).entries());
const opts = (arr, v, l, ph) => (ph ? `<option value="">${ph}</option>` : '') + arr.map((x) => `<option value="${esc(x[v])}">${esc(x[l])}</option>`).join('');
const table = (heads, rows, go) => `<div class="scroll"><table><tr>${heads.map((h) => `<th>${h}</th>`).join('')}</tr>${rows.map((r) => `<tr ${go ? `data-go="${go(r.o)}"` : ''}>${r.c.map((c) => `<td>${c}</td>`).join('')}</tr>`).join('') || `<tr><td class="mut">Nothing here yet</td></tr>`}</table></div>`;

function logout() { S.token = null; S.user = null; localStorage.removeItem('token'); location.hash = ''; render(); }
async function accept(r) { S.token = r.token; S.user = r.user; localStorage.setItem('token', r.token); location.hash = '#/home'; render(); }

const nav = () => {
  const r = S.user.role;
  const l = [['home', 'Dashboard'], ['find', 'Find Blood']];
  if (r === 'PATIENT' || r === 'STAFF') l.push(['new', 'New Request']);
  if (r === 'STAFF' || r === 'ADMIN') l.push(['inventory', 'Inventory'], ['donors', 'Donors']);
  if (r === 'DONOR') l.push(['invites', 'Invitations'], ['history', 'My Donations']);
  l.push(['notes', 'Notifications']);
  return l;
};
function shell(active, html) {
  $('#app').innerHTML = `<header><b>🩸 JEEVANDAN</b>${nav().map(([k, t]) => `<a href="#/${k}" class="${k === active ? 'on' : ''}">${t}</a>`).join('')}
    <span class="sp"></span><span>${esc(S.user.full_name)} (${esc(S.user.role)})</span><a href="#/logout" data-logout>Logout</a></header><main>${html}</main>`;
}

function authView(mode) {
  const reg = mode === 'register';
  $('#app').innerHTML = `<div class="auth card"><h2>🩸 JEEVANDAN</h2><p class="mut">Blood &amp; Organ Donation Management</p>
  <form id="af">${reg ? `<label>I am a</label><select name="role" id="role"><option value="DONOR">Donor</option><option value="PATIENT">Patient / Requester</option></select>
  <label>Full name</label><input name="full_name" required><label>Phone</label><input name="phone" required>` : ''}
  <label>Email</label><input name="email" type="email" required><label>Password</label><input name="password" type="password" required>
  ${reg ? `<div id="dn"><div class="row"><div><label>Blood group</label><select name="blood_group">${opts(S.lk.bloodGroups, 'label', 'label')}</select></div>
  <div><label>Gender</label><select name="gender"><option value="M">Male</option><option value="F">Female</option><option value="O">Other</option></select></div></div>
  <div class="row"><div><label>Date of birth</label><input type="date" name="date_of_birth"></div><div><label>Weight (kg)</label><input type="number" name="weight_kg"></div></div>
  <label>City</label><input name="city"></div>` : ''}
  <button style="width:100%">${reg ? 'Create account' : 'Login'}</button></form>
  <p class="mut">${reg ? '<a href="#/login">Already have an account? Login</a>' : '<a href="#/register">New here? Register</a><br>Demo: admin@jeevandan.test / Demo@1234'}</p></div>`;
  const role = $('#role'); if (role) role.onchange = () => ($('#dn').style.display = role.value === 'DONOR' ? '' : 'none');
  $('#af').onsubmit = (e) => { e.preventDefault(); run(async () => accept(await api('POST', reg ? '/auth/register' : '/auth/login', form(e.target)))); };
}

const V = {
  async home() {
    const r = S.user.role, parts = [];
    if (r === 'ADMIN') {
      const s = await api('GET', '/admin/stats');
      parts.push(`<div class="grid">${[['Donors', s.counts.donors], ['Hospitals', s.counts.hospitals], ['Units in stock', s.total_units], ['Open emergencies', s.emergencies_open], ['Pending transfers', s.pending_transfers], ['Expiring units', s.expiring_units]].map(([a, b]) => `<div class="card stat"><b>${b}</b>${a}</div>`).join('')}</div>
      <div class="card"><h2>Stock by blood group</h2><div class="grid">${s.stock.map((x) => `<div class="stat"><b>${x.units}</b>${esc(x.blood_group)}</div>`).join('')}</div></div>`);
    }
    if (r === 'DONOR') { return V.invites(); }
    const rq = await api('GET', '/requests');
    parts.push(`<div class="card"><h2>Blood requests</h2>${table(['#', 'Patient', 'Group', 'Units', 'Priority', 'Status', 'Hospital'],
      rq.map((x) => ({ o: x, c: [x.request_id, esc(x.patient_name), esc(x.blood_group), x.units_needed, tag(x.priority), tag(x.status), esc(x.hospital_name)] })), (x) => '#/req/' + x.request_id)}</div>`);
    shell('home', parts.join(''));
  },
  async req(id) {
    const d = await api('GET', '/requests/' + id), x = d.request;
    const m = d.can_manage;
    const act = m && x.status === 'PENDING' ? '<button data-act="approve">Verify &amp; approve</button><button class="sec" data-act="reject">Reject</button>' :
      m && x.status === 'APPROVED' ? '<button data-act="fulfil">Fulfil from stock</button><button class="sec" data-act="reject">Reject</button>' : '';
    shell('home', `<div class="card"><h2>Request #${x.request_id} ${tag(x.priority)} ${tag(x.status)}</h2>
      <p><b>${esc(x.patient_name)}</b> needs <b>${x.units_needed}</b> unit(s) of <b>${esc(x.blood_group)}</b> at ${esc(x.hospital_name)}, ${esc(x.city)}</p>
      <p class="mut">${esc(x.reason || '')} ${x.remarks ? '· Remarks: ' + esc(x.remarks) : ''}<br>Requested by ${esc(x.requester_name)} on ${esc(x.created_at)}</p>
      <p>Donors invited: ${d.donors_invited}, accepted: ${d.donors_accepted}</p>${act}<a href="#/home"><button class="sec">Back</button></a></div>
      ${d.allocations.length ? `<div class="card"><h2>Allocated batches</h2>${table(['Batch', 'Group', 'Units', 'Expiry'], d.allocations.map((a) => ({ c: [a.batch_id, esc(a.blood_group), a.units_allocated, esc(a.expiry_date)] })))}</div>` : ''}
      ${m && ['PENDING', 'APPROVED'].includes(x.status) ? '<div id="mt" class="card mut">Loading matches…</div>' : ''}`);
    document.querySelectorAll('[data-act]').forEach((b) => (b.onclick = () => run(async () => {
      const a = b.dataset.act, body = a === 'reject' ? { remarks: prompt('Reason for rejection?') || '' } : {};
      await api('POST', `/requests/${id}/${a}`, body); toast('Done'); V.req(id);
    })));
    if ($('#mt')) run(async () => {
      const mt = await api('GET', `/requests/${id}/matches`);
      $('#mt').innerHTML = '<h2>Matching</h2><pre style="white-space:pre-wrap;font-size:13px">' + esc(JSON.stringify(mt, null, 1).slice(0, 2500)) + '</pre>';
    });
  },
  async find() {
    shell('find', `<div class="card"><h2>Find blood</h2><form id="sf" class="row"><div><label>Blood group needed</label><select name="bg">${opts(S.lk.bloodGroups, 'label', 'label', 'Any')}</select></div>
      <div><label>City</label><input name="city"></div><div><label>&nbsp;</label><button>Search</button></div></form></div><div id="sr"></div>`);
    const go = () => run(async () => {
      const q = new URLSearchParams(Object.entries(form($('#sf'))).filter(([, v]) => v));
      const rows = await api('GET', '/inventory/search?' + q);
      $('#sr').innerHTML = `<div class="card">${table(['Hospital', 'City', 'Type', 'Group', 'Units', 'Nearest expiry', 'Phone'],
        rows.map((x) => ({ c: [esc(x.hospital_name), esc(x.city), esc(x.facility_type), esc(x.blood_group), x.units_available, esc(x.nearest_expiry), esc(x.phone)] })))}</div>`;
    });
    $('#sf').onsubmit = (e) => { e.preventDefault(); go(); }; go();
  },
  async new() {
    const st = S.user.role === 'STAFF';
    shell('new', `<div class="card"><h2>New blood request</h2><form id="nf"><label>Patient name</label><input name="patient_name" required>
      <div class="row"><div><label>Blood group</label><select name="blood_group">${opts(S.lk.bloodGroups, 'label', 'label')}</select></div>
      <div><label>Units</label><input type="number" name="units_needed" value="1" min="1" max="20"></div>
      <div><label>Priority</label><select name="priority"><option>NORMAL</option><option>URGENT</option><option>EMERGENCY</option></select></div></div>
      ${st ? '' : `<label>Hospital</label><select name="hospital_id">${S.lk.hospitals.map((h) => `<option value="${h.hospital_id}">${esc(h.name)} – ${esc(h.city)}</option>`).join('')}</select>`}
      <label>Reason</label><input name="reason"><button>Submit request</button></form></div>`);
    $('#nf').onsubmit = (e) => { e.preventDefault(); run(async () => { const r = await api('POST', '/requests', form(e.target)); location.hash = '#/req/' + r.request_id; }); };
  },
  async inventory() {
    const [st, b] = await Promise.all([S.user.role === 'STAFF' ? api('GET', '/inventory/hospital-stock') : Promise.resolve(null), api('GET', '/inventory/batches')]);
    shell('inventory', `${st ? `<div class="card"><h2>Stock</h2><div class="grid">${st.map((x) => `<div class="stat"><b>${x.units_available}</b>${esc(x.blood_group)}</div>`).join('')}</div></div>` : ''}
      <div class="card"><h2>Batches</h2>${table(['Batch', 'Hospital', 'Group', 'Available', 'Collected', 'Expiry', 'Days left', 'Status'],
      b.map((x) => ({ c: [x.batch_id, esc(x.hospital_name), esc(x.blood_group), `${x.units_available}/${x.units_total}`, esc(x.collected_on), esc(x.expiry_date), x.days_left, tag(x.status)] })))}</div>`);
  },
  async donors() {
    const d = await api('GET', '/donors');
    shell('donors', `<div class="card"><h2>Donors</h2>${table(['Name', 'Group', 'City', 'Phone', 'Last donation', 'Donations', 'Eligible'],
      d.map((x) => ({ c: [esc(x.full_name), esc(x.blood_group), esc(x.city), esc(x.phone), esc(x.last_donation_date || '—'), x.total_donations, x.eligible ? '✅' : '⛔'] })))}</div>`);
  },
  async invites() {
    const m = await api('GET', '/requests/matches/mine');
    shell(S.user.role === 'DONOR' && location.hash === '#/home' ? 'home' : 'invites', `<div class="card"><h2>Donation invitations</h2>${table(['Hospital', 'City', 'Group', 'Units', 'Priority', 'Status', ''],
      m.map((x) => ({ c: [esc(x.hospital_name), esc(x.city), esc(x.blood_group), x.units_needed, tag(x.priority), tag(x.status),
        x.status === 'NOTIFIED' ? `<button data-m="${x.match_id}" data-a="1">Accept</button><button class="sec" data-m="${x.match_id}" data-a="">Decline</button>` : ''] })))}</div>`);
    document.querySelectorAll('[data-m]').forEach((b) => (b.onclick = () => run(async () => { await api('POST', `/requests/matches/${b.dataset.m}/respond`, { accept: !!b.dataset.a }); V.invites(); })));
  },
  async history() {
    const h = await api('GET', '/donors/me/history');
    shell('history', `<div class="card"><h2>My donations</h2>${table(['Date', 'Units', 'Hospital', 'City'], h.map((x) => ({ c: [esc(x.donated_on), x.units, esc(x.hospital_name), esc(x.city)] })))}</div>`);
  },
  async notes() {
    const n = await api('GET', '/notifications');
    shell('notes', `<div class="card"><h2>Notifications <button class="sec" id="ra">Mark all read</button></h2>${n.map((x) =>
      `<p style="${x.is_read ? 'opacity:.6' : ''}"><b>${esc(x.title)}</b><br>${esc(x.message)}<br><span class="mut">${esc(x.created_at)}</span></p>`).join('') || '<p class="mut">No notifications</p>'}</div>`);
    $('#ra').onclick = () => run(async () => { await api('POST', '/notifications/read-all'); V.notes(); });
  },
};

async function render() {
  const h = (location.hash || '#/').slice(2).split('/');
  try {
    if (!S.lk) S.lk = await api('GET', '/lookups');
    if (S.token && !S.user) S.user = await api('GET', '/me');
  } catch (e) { $('#app').innerHTML = `<div class="auth card err">Cannot reach server: ${esc(e.message)}</div>`; return; }
  if (!S.user) return authView(h[0] === 'register' ? 'register' : 'login');
  if (h[0] === 'logout') return logout();
  const name = V[h[0]] ? h[0] : 'home';
  try { await V[name](h[1]); } catch (e) { shell(name, `<div class="card err">${esc(e.message)}</div>`); }
}
document.addEventListener('click', (e) => {
  const tr = e.target.closest('tr[data-go]'); if (tr) location.hash = tr.dataset.go;
  if (e.target.closest('[data-logout]')) { e.preventDefault(); logout(); }
});
addEventListener('hashchange', render); render();
