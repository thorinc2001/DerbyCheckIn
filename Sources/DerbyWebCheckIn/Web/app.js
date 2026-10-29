// Derby Web Check In — browser side. The Mac running the app holds the one copy of the
// event; every change goes to it, and every computer polls it to stay up to date.
'use strict';

const MAX_CAR_NAME = 20;
const S = {
  state: null,        // last state from the host: { version, event, problems, counts, folder }
  selected: null,     // selected racer id
  search: '',
  group: '',
  status: 'all',
  settingsOpen: false,
  settingsTab: 'general',
};

// ---------- small helpers ----------

const $ = (sel) => document.querySelector(sel);

function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'value') el.value = v;
    else if (k === 'checked') el.checked = v;
    else if (k === 'disabled') el.disabled = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat(Infinity)) {
    if (kid == null || kid === false) continue;
    el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return el;
}

const ev = () => S.state?.event;
const racer = (id) => ev()?.racers.find((r) => r.id === id);
const groupFor = (rank) => ev()?.groups.find((g) => g.rank === rank);
const fullName = (r) => `${r.firstName} ${r.lastName}`.trim();
const groupName = (r) => r.subgroup || r.rank;
const groupLabel = (g) => (!g.subgroup || g.subgroup === g.rank ? g.rank : `${g.subgroup} (${g.rank})`);
const fmtNum = (n) => (Number.isInteger(n) ? String(n) : String(+n.toFixed(2)));

function sortRacers(a, b) {
  const x = [a.lastName.toLowerCase(), a.firstName.toLowerCase()];
  const y = [b.lastName.toLowerCase(), b.firstName.toLowerCase()];
  if (x[0] !== y[0]) return x[0] < y[0] ? -1 : 1;
  if (x[1] !== y[1]) return x[1] < y[1] ? -1 : 1;
  return a.carNumber - b.carNumber;
}

// ---------- talking to the host Mac ----------

function setOnline(ok) {
  $('#offline').hidden = ok;
}

async function api(method, path, body, raw) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    if (raw) opts.body = body;
    else { opts.body = JSON.stringify(body); opts.headers['Content-Type'] = 'application/json'; }
  }
  let res;
  try {
    res = await fetch('/api/' + path, opts);
  } catch (e) {
    setOnline(false);
    throw e;
  }
  setOnline(true);
  if (!res.ok) {
    let msg = 'Something went wrong.';
    try { msg = (await res.json()).error || msg; } catch { /* not JSON */ }
    if (res.status === 404) load();
    await showAlert(msg);
    throw new Error(msg);
  }
  return res;
}

/** Sends a change and shows the event the host sends back. */
async function act(method, path, body, raw) {
  const st = await (await api(method, path, body, raw)).json();
  applyState(st);
  if (st.message) showAlert(st.message);
  return st;
}

async function load() {
  try {
    const res = await fetch('/api/state', { cache: 'no-store' });
    setOnline(true);
    applyState(await res.json());
  } catch {
    setOnline(false);
  }
}

async function poll() {
  try {
    const res = await fetch('/api/version', { cache: 'no-store' });
    const { version } = await res.json();
    setOnline(true);
    if (!S.state || version !== S.state.version) await load();
  } catch {
    setOnline(false);
  }
  setTimeout(poll, 1500);
}

function applyState(st) {
  S.state = st;
  if (S.selected && !racer(S.selected)) S.selected = null;
  render();
}

const patchRacer = (id, change) => act('PATCH', 'racers/' + id, change).catch(() => {});

// Text fields send their value shortly after typing stops, and again when you leave them.
const timers = {};
const lastSent = {};
function textField(key, value, commit, opts = {}) {
  const tag = opts.multiline ? 'textarea' : 'input';
  const el = h(tag, {
    class: 'field ' + (opts.cls || ''), 'data-key': key, value: value ?? '',
    placeholder: opts.placeholder, maxlength: opts.maxLength, inputmode: opts.inputmode,
    type: opts.multiline ? null : 'text', autocomplete: 'off', spellcheck: opts.spellcheck ?? null,
  });
  lastSent[key] = el.value;
  const send = () => {
    clearTimeout(timers[key]);
    if (el.value === lastSent[key]) return;
    lastSent[key] = el.value;
    commit(el.value);
  };
  if (!opts.onChangeOnly) el.addEventListener('input', () => { clearTimeout(timers[key]); timers[key] = setTimeout(send, 450); });
  el.addEventListener('change', send);
  el.addEventListener('blur', send);
  if (!opts.multiline) el.addEventListener('keydown', (e) => { if (e.key === 'Enter') el.blur(); });
  if (opts.onInput) el.addEventListener('input', () => opts.onInput(el.value));
  return el;
}

/** Rebuilds a container without losing what you're typing in a focused field. */
function rebuild(container, build) {
  const active = document.activeElement;
  const key = active && container.contains(active) ? active.dataset.key : null;
  const typed = key ? { value: active.value, start: active.selectionStart, end: active.selectionEnd } : null;
  const scroll = container.scrollTop;
  container.replaceChildren(...[build()].flat());
  if (key) {
    const again = container.querySelector(`[data-key="${CSS.escape(key)}"]`);
    if (again) {
      if ('value' in again && typed.value !== undefined && again.tagName !== 'SELECT') {
        again.value = typed.value;
      }
      again.focus({ preventScroll: true });
      try { again.setSelectionRange(typed.start, typed.end); } catch { /* not a text field */ }
    }
  }
  container.scrollTop = scroll;
}

// ---------- dialogs and menus ----------

function sheet(content, { small = false, onClose } = {}) {
  const scrim = h('div', { class: 'scrim' });
  const box = h('div', { class: 'sheet' + (small ? ' small' : '') }, content);
  scrim.append(box);
  const close = () => { scrim.remove(); document.removeEventListener('keydown', onKey); onClose?.(); };
  const onKey = (e) => { if (e.key === 'Escape') close(); };
  document.addEventListener('keydown', onKey);
  $('#layer').append(scrim);
  return { box, close };
}

function showAlert(message, title = 'Derby Web Check In') {
  return new Promise((resolve) => {
    const ok = h('button', { class: 'btn primary', onclick: () => { s.close(); } }, 'OK');
    const s = sheet([
      h('div', { class: 'body' }, h('div', { class: 'dialog-title' }, title), h('div', { class: 'dialog-msg' }, message)),
      h('div', { class: 'foot' }, ok),
    ], { small: true, onClose: resolve });
    ok.focus();
  });
}

function confirmDialog(title, message, action, { destructive = false } = {}) {
  return new Promise((resolve) => {
    let result = false;
    const yes = h('button', { class: 'btn ' + (destructive ? 'danger' : 'primary'), onclick: () => { result = true; s.close(); } }, action);
    const s = sheet([
      h('div', { class: 'body' }, h('div', { class: 'dialog-title' }, title), h('div', { class: 'dialog-msg muted' }, message)),
      h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: () => s.close() }, 'Cancel'), yes),
    ], { small: true, onClose: () => resolve(result) });
    yes.focus();
  });
}

let openPop = null;
function popMenu(anchor, items) {
  closePop();
  const pop = h('div', { class: 'pop' }, items.map((it) => it === '-' ? h('hr')
    : h('button', { class: it.danger ? 'danger' : '', disabled: it.disabled, onclick: () => { closePop(); it.run(); } }, it.label)));
  document.body.append(pop);
  const r = anchor.getBoundingClientRect();
  const w = pop.offsetWidth;
  pop.style.top = `${Math.min(r.bottom + 4, innerHeight - pop.offsetHeight - 8)}px`;
  pop.style.left = `${Math.max(8, Math.min(r.right - w, innerWidth - w - 8))}px`;
  openPop = pop;
  setTimeout(() => document.addEventListener('click', closePop, { once: true }));
}
function closePop() { openPop?.remove(); openPop = null; }

// ---------- rendering ----------

function render() {
  if (!S.state) return;
  const e = ev();
  $('#eventName').textContent = e.eventName;
  document.title = `${e.eventName} – Derby Web Check In`;
  renderFilters();
  renderList();
  renderDetail();
  if (S.settingsOpen) renderSettings();
}

function renderFilters() {
  const sel = $('#groupFilter');
  if (S.group && !groupFor(S.group)) S.group = '';
  rebuild(sel, () => [h('option', { value: '' }, 'All groups'), ...ev().groups.map((g) => h('option', { value: g.rank }, groupLabel(g)))]);
  sel.value = S.group;
}

function filtered() {
  const q = S.search.trim().toLowerCase();
  return ev().racers
    .filter((r) => !S.group || r.rank === S.group)
    .filter((r) => {
      switch (S.status) {
        case 'waiting': return !r.checkedInAt;
        case 'checkedIn': return !!r.checkedInAt;
        case 'needsInspection': return r.inspection.passed !== true;
        default: return true;
      }
    })
    .filter((r) => !q || fullName(r).toLowerCase().includes(q) || String(r.carNumber) === q || r.carName.toLowerCase().includes(q))
    .sort(sortRacers);
}

function renderList() {
  const list = $('#list');
  const racers = filtered();
  list.replaceChildren(...racers.map((r) => h('li', {
    class: r.id === S.selected ? 'sel' : '', role: 'option', 'aria-selected': r.id === S.selected ? 'true' : 'false',
    onclick: () => select(r.id),
  },
  h('span', { class: 'num' }, r.carNumber > 0 ? `#${r.carNumber}` : '—'),
  h('span', { class: 'who' },
    h('div', { class: 'name' }, fullName(r) || 'New Racer'),
    h('div', { class: 'sub' }, [groupName(r) || 'No group', r.carName].filter(Boolean).join(' · '))),
  r.exclude ? h('span', { class: 'st muted', title: 'Excluded from racing' }, '⦸') : null,
  r.inspection.passed === false ? h('span', { class: 'st bad', title: 'Failed inspection' }, '✖') : null,
  r.checkedInAt ? h('span', { class: 'st good', title: 'Checked in' }, '✔︎') : h('span', { class: 'st muted', title: 'Not checked in' }, '○'),
  )));
  if (!racers.length) list.append(h('li', { class: 'empty' }, ev().racers.length ? 'No racers match.' : 'No racers yet.'));
  const all = ev().racers;
  $('#count').textContent = `${all.filter((r) => r.checkedInAt).length} of ${all.length} checked in`;
}

function select(id) {
  S.selected = id;
  document.body.classList.toggle('show-detail', !!id);
  $('#btnBack').hidden = !id;
  renderList();
  renderDetail();
  $('#detail').scrollTop = 0;
}

function section(title, rows, { headerRight, note } = {}) {
  return h('div', { class: 'section' },
    title || headerRight ? h('div', { class: 'section-head' }, h('h3', null, title || ''), headerRight || null) : null,
    h('div', { class: 'card' }, rows),
    note ? h('div', { class: 'note' }, note) : null);
}
const row = (label, ...ctl) => h('div', { class: 'row' }, h('label', null, label), h('div', { class: 'ctl' }, ctl));

function renderDetail() {
  const detail = $('#detail');
  const r = racer(S.selected);
  if (!r) {
    document.body.classList.remove('show-detail');
    $('#btnBack').hidden = true;
    detail.replaceChildren(h('div', { class: 'empty-state' },
      h('div', { class: 'big-i' }, '🏎'),
      h('h2', null, 'No Racer Selected'),
      h('div', null, 'Pick a racer on the left, add a new one, or import a pre-registration roster.'),
      h('div', { class: 'actions' },
        h('button', { class: 'btn', onclick: newRacer }, 'New Racer'),
        h('button', { class: 'btn', onclick: importRoster }, 'Import Roster…'))));
    return;
  }
  rebuild(detail, () => racerForm(r));
}

function racerForm(r) {
  const e = ev();
  const p = S.state.problems[r.id] || {};
  const max = e.maxWeightOz;
  const id = r.id;
  const k = (name) => `${id}:${name}`;

  const rankSelect = h('select', { class: 'field', 'data-key': k('rank'), onchange: (x) => patchRacer(id, { rank: x.target.value }) },
    h('option', { value: '' }, 'Choose…'),
    e.groups.map((g) => h('option', { value: g.rank }, groupLabel(g))),
    r.rank && !groupFor(r.rank) ? h('option', { value: r.rank }, groupName(r)) : null);
  rankSelect.value = r.rank;

  const counter = h('span', { class: 'counter' + (r.carName.length >= MAX_CAR_NAME ? ' warn' : '') }, `${r.carName.length}/${MAX_CAR_NAME}`);
  const weightBadge = r.weightOz > max ? h('span', { class: 'bad' }, `✖ Over ${fmtNum(max)} oz`)
    : r.weightOz > 0 ? h('span', { class: 'good' }, '✔︎ OK') : null;

  const toggle = (label, field) => h('label', { class: 'row' }, h('span', null, label),
    h('input', { type: 'checkbox', class: 'switch', checked: r.inspection[field], 'data-key': k(field),
      onchange: (x) => patchRacer(id, { inspection: { [field]: x.target.checked } }) }));

  const result = h('div', { class: 'radios', role: 'radiogroup', 'aria-label': 'Result' },
    [[null, 'Not inspected'], [true, 'Passed'], [false, 'Failed']].map(([v, label]) =>
      h('label', null,
        h('input', { type: 'radio', name: `result-${id}`, checked: (r.inspection.passed ?? null) === v, 'data-key': k(`result-${v}`),
          onchange: () => patchRacer(id, { inspection: { passed: v } }) }),
        label)));

  const photoSlot = (kind, title, icon) => {
    const file = kind === 'racer' ? r.racerPhoto : r.carPhoto;
    return h('div', { class: 'slot' },
      h('div', { class: 'pic' }, file ? h('img', { src: '/photos/' + encodeURIComponent(file), alt: `${title} photo` }) : icon),
      h('strong', null, title),
      h('div', { class: 'btns' },
        h('button', { class: 'btn', onclick: () => openCamera(id, kind) }, '📷 Camera'),
        h('button', { class: 'btn', onclick: () => pickPhoto(id, kind, false) }, 'File…'),
        file ? h('button', { class: 'btn danger', onclick: () => act('DELETE', `racers/${id}/photo/${kind}`).catch(() => {}) }, 'Remove') : null));
  };

  let checkin;
  if (r.checkedInAt) {
    const t = new Date(r.checkedInAt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    checkin = h('div', { class: 'checkin' }, h('span', { class: 'checked' }, `✔︎ Checked in at ${t}`),
      h('button', { class: 'btn', onclick: () => act('POST', `racers/${id}/undo-checkin`).catch(() => {}) }, 'Undo Check-In'));
  } else {
    checkin = h('div', { class: 'checkin' },
      h('div', null,
        p.checkIn ? h('div', { class: 'muted' }, p.checkIn) : null,
        r.inspection.passed !== true ? h('div', { class: 'warn' }, r.inspection.passed === false ? '⚠︎ Car failed inspection' : '⚠︎ Car not inspected yet') : null),
      h('button', { class: 'btn primary big', disabled: !!p.checkIn, onclick: () => act('POST', `racers/${id}/checkin`).catch(() => {}) }, 'Check In'));
  }

  return h('div', { class: 'form' },
    h('h2', null, fullName(r) || 'New Racer'),
    section('Racer', [
      row('First name', textField(k('first'), r.firstName, (v) => patchRacer(id, { firstName: v }), { placeholder: 'First name' })),
      row('Last name', textField(k('last'), r.lastName, (v) => patchRacer(id, { lastName: v }), { placeholder: 'Last name' })),
      row('Race group', rankSelect),
    ]),
    section('Car', [
      row('Car number',
        textField(k('car'), r.carNumber > 0 ? String(r.carNumber) : '', (v) => patchRacer(id, { carNumber: parseInt(v, 10) || 0 }),
          { cls: 'num', inputmode: 'numeric', onChangeOnly: true, placeholder: '—' }),
        h('button', { class: 'btn', disabled: !r.rank, title: "Next free number in this group's series",
          onclick: () => act('POST', `racers/${id}/next-number`).catch(() => {}) }, 'Next Available')),
      p.carNumber ? h('div', { class: 'row warn' }, `⚠︎ ${p.carNumber}`) : null,
      row('Car name',
        textField(k('carName'), r.carName, (v) => patchRacer(id, { carName: v }), {
          maxLength: MAX_CAR_NAME, placeholder: 'Car name',
          onInput: (v) => { counter.textContent = `${v.length}/${MAX_CAR_NAME}`; counter.classList.toggle('warn', v.length >= MAX_CAR_NAME); },
        }), counter),
      row('Weight (oz)',
        textField(k('weight'), r.weightOz > 0 ? fmtNum(r.weightOz) : '', (v) => patchRacer(id, { weightOz: parseFloat(v) || 0 }),
          { cls: 'num', inputmode: 'decimal', onChangeOnly: true, placeholder: '0.00' }),
        weightBadge),
      h('label', { class: 'row' }, h('span', null, 'Exclude from racing'),
        h('input', { type: 'checkbox', class: 'switch', checked: r.exclude, 'data-key': k('exclude'), onchange: (x) => patchRacer(id, { exclude: x.target.checked }) })),
    ], {
      headerRight: h('button', { class: 'btn link', disabled: !fullName(r), onclick: () => act('POST', `racers/${id}/add-car`).then(selectFromState).catch(() => {}) },
        `＋ Add Another Car for ${r.firstName || 'This Racer'}`),
    }),
    section('Inspection', [
      toggle(`Weight is ${fmtNum(max)} oz or less`, 'weightOK'),
      toggle('Length, width and height within limits', 'dimensionsOK'),
      toggle('Ground clearance OK', 'clearanceOK'),
      toggle('Wheels and axles meet the rules', 'wheelsAxlesOK'),
      toggle('No loose parts, liquids or springs', 'noLooseParts'),
      h('div', { class: 'row' }, h('label', null, 'Result'), h('div', { class: 'ctl', style: 'max-width:420px' }, result)),
    ]),
    section('Photos', [h('div', { class: 'photos' }, photoSlot('racer', 'Racer', '👤'), photoSlot('car', 'Car', '🚗'))]),
    section('Notes', [h('div', { class: 'row stack' }, textField(k('notes'), r.notes, (v) => patchRacer(id, { notes: v }), { multiline: true, placeholder: 'Notes' }))]),
    section(null, [checkin]),
    section(null, [h('div', { class: 'row' }, h('button', { class: 'btn danger', onclick: () => deleteRacer(r) }, 'Delete Racer…'))]),
  );
}

function selectFromState(st) {
  if (st.selected) select(st.selected);
}

async function newRacer() {
  const st = await act('POST', 'racers', { rank: S.group }).catch(() => null);
  if (st) {
    selectFromState(st);
    setTimeout(() => $('#detail [data-key$=":first"]')?.focus(), 0);
  }
}

async function deleteRacer(r) {
  const name = fullName(r) || 'this racer';
  if (await confirmDialog(`Delete ${name}?`, 'Their details and photos will be removed.', 'Delete', { destructive: true })) {
    await act('DELETE', 'racers/' + r.id).catch(() => {});
  }
}

// ---------- photos ----------

/** Scales a photo so its longest side is at most 1200 px, as JPEG. */
async function shrink(blob, max = 1200) {
  const url = URL.createObjectURL(blob);
  try {
    const img = await new Promise((resolve, reject) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = () => reject(new Error('unreadable'));
      i.src = url;
    });
    const scale = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
    const c = document.createElement('canvas');
    c.width = Math.round(img.naturalWidth * scale);
    c.height = Math.round(img.naturalHeight * scale);
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    return await new Promise((resolve) => c.toBlob(resolve, 'image/jpeg', 0.85));
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function uploadPhoto(id, kind, blob) {
  let jpeg;
  try { jpeg = await shrink(blob); } catch { return showAlert("That file isn't an image this browser can read."); }
  await act('PUT', `racers/${id}/photo/${kind}`, jpeg, true).catch(() => {});
}

function pickPhoto(id, kind, useCamera) {
  const input = h('input', { type: 'file', accept: 'image/*' });
  if (useCamera) input.setAttribute('capture', 'environment');
  input.addEventListener('change', () => { if (input.files[0]) uploadPhoto(id, kind, input.files[0]); });
  input.click();
}

/** Live camera where the browser allows it (this Mac, or HTTPS); otherwise phones and
 *  tablets open their camera app, and computers choose a file. */
async function openCamera(id, kind) {
  if (!(window.isSecureContext && navigator.mediaDevices?.getUserMedia)) {
    pickPhoto(id, kind, true);
    return;
  }
  let stream = null;
  let shot = null;
  const view = h('div', { class: 'camera' }, h('p', null, 'Starting camera…'));
  const devices = h('select', { class: 'field', hidden: true });
  const take = h('button', { class: 'btn primary', disabled: true }, 'Take Photo');
  const retake = h('button', { class: 'btn', hidden: true }, 'Retake');
  const use = h('button', { class: 'btn primary', hidden: true }, 'Use Photo');
  const s = sheet([
    h('div', { class: 'body' },
      h('div', { class: 'section-head', style: 'margin:0 0 10px' }, h('strong', null, kind === 'racer' ? 'Racer Photo' : 'Car Photo'), devices),
      view),
    h('div', { class: 'foot' },
      h('button', { class: 'btn left', onclick: () => { s.close(); pickPhoto(id, kind, false); } }, 'Choose File Instead'),
      h('button', { class: 'btn', onclick: () => s.close() }, 'Cancel'), retake, use, take),
  ], { onClose: () => stream?.getTracks().forEach((t) => t.stop()) });

  async function start(deviceId) {
    stream?.getTracks().forEach((t) => t.stop());
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: deviceId ? { deviceId: { exact: deviceId }, width: { ideal: 1600 } } : { width: { ideal: 1600 }, facingMode: 'environment' },
        audio: false,
      });
    } catch {
      view.replaceChildren(h('p', null, 'The camera could not be opened. Allow camera access for this page, or choose a photo file instead.'));
      return;
    }
    const video = h('video', { autoplay: true, playsinline: true, muted: true });
    video.srcObject = stream;
    view.replaceChildren(video);
    take.disabled = false;
    const cams = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === 'videoinput');
    if (cams.length > 1) {
      const current = stream.getVideoTracks()[0]?.getSettings().deviceId;
      devices.replaceChildren(...cams.map((c, i) => h('option', { value: c.deviceId }, c.label || `Camera ${i + 1}`)));
      devices.value = current || '';
      devices.hidden = false;
      devices.onchange = () => start(devices.value);
    }
    take.onclick = () => {
      const c = document.createElement('canvas');
      c.width = video.videoWidth;
      c.height = video.videoHeight;
      c.getContext('2d').drawImage(video, 0, 0);
      c.toBlob((blob) => {
        shot = blob;
        view.replaceChildren(h('img', { src: URL.createObjectURL(blob), alt: 'Photo taken' }));
        take.hidden = true; retake.hidden = false; use.hidden = false;
        use.focus();
      }, 'image/jpeg', 0.92);
    };
  }
  retake.onclick = () => { shot = null; take.hidden = false; retake.hidden = true; use.hidden = true; start(devices.hidden ? undefined : devices.value); };
  use.onclick = () => { s.close(); if (shot) uploadPhoto(id, kind, shot); };
  start();
}

// ---------- import and export ----------

function importRoster() {
  const input = h('input', { type: 'file', accept: '.csv,.txt,text/csv,text/plain' });
  input.addEventListener('change', async () => {
    const file = input.files[0];
    if (!file) return;
    const st = await act('POST', 'import', await file.text(), true).catch(() => null);
    if (st && !st.message) showAlert('Import finished.');
  });
  input.click();
}

// target is 'gprm' or 'derbyNet'.
async function exportFor(checkedInOnly, target) {
  const res = await api('GET', 'export?for=' + target + (checkedInOnly ? '&checkedInOnly=1' : '')).catch(() => null);
  if (!res) return;
  const name = /filename="([^"]+)"/.exec(res.headers.get('Content-Disposition') || '')?.[1] || 'Export.zip';
  const url = URL.createObjectURL(await res.blob());
  const a = h('a', { href: url, download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

// ---------- settings ----------

let settingsSheet = null;
function openSettings(tab) {
  S.settingsTab = tab || S.settingsTab;
  if (!S.settingsOpen) {
    S.settingsOpen = true;
    const content = h('div', { id: 'settings', style: 'display:flex;flex-direction:column;min-height:0' });
    settingsSheet = sheet(content, { onClose: () => { S.settingsOpen = false; settingsSheet = null; } });
  }
  renderSettings();
}

function renderSettings() {
  const root = $('#settings');
  if (!root) return;
  const tabs = [['general', '⚙︎', 'General'], ['groups', '☰', 'Race Groups'], ['storage', '☁︎', 'Storage']];
  const tabBar = h('div', { class: 'tabs' }, tabs.map(([key, icon, label]) =>
    h('button', { class: S.settingsTab === key ? 'on' : '', onclick: () => { S.settingsTab = key; renderSettings(); } },
      h('span', { class: 'i' }, icon), label)));
  const body = h('div', { class: 'body', style: 'min-height:340px' });
  const foot = h('div', { class: 'foot' }, h('button', { class: 'btn primary', onclick: () => settingsSheet?.close() }, 'Done'));
  const old = root.querySelector('.body');
  const keepScroll = old?.scrollTop || 0;
  // Keep focus inside the body across rebuilds.
  if (old) {
    rebuild(old, () => settingsBody());
    root.querySelector('.tabs').replaceWith(tabBar);
    return;
  }
  root.replaceChildren(tabBar, body, foot);
  body.replaceChildren(...[settingsBody()].flat());
  body.scrollTop = keepScroll;
}

function settingsBody() {
  const e = ev();
  if (S.settingsTab === 'general') {
    return [
      section(null, [
        row('Event name', textField('set:event', e.eventName, (v) => act('PATCH', 'settings', { eventName: v }).catch(() => {}))),
        row('Maximum car weight (oz)', textField('set:max', fmtNum(e.maxWeightOz), (v) => {
          const n = parseFloat(v);
          if (n > 0) act('PATCH', 'settings', { maxWeightOz: n }).catch(() => {});
        }, { cls: 'num', inputmode: 'decimal', onChangeOnly: true })),
      ]),
      section(null, [row('Image folder on GPRM PC', textField('set:img', e.imageFolderOnPC,
        (v) => act('PATCH', 'settings', { imageFolderOnPC: v }).catch(() => {}), { placeholder: 'C:\\Derby\\Images', spellcheck: 'false' }))],
      { note: "Where you will copy the export's Images folder on the Windows PC. Used for the ImageFile column; leave blank to leave ImageFile empty." }),
    ];
  }
  if (S.settingsTab === 'storage') {
    return [
      section('Where the event and photos are saved', [
        row('Folder on the check-in Mac', h('span', { style: 'text-align:right;word-break:break-all' }, S.state.folder)),
      ], { note: 'Everything is saved on the Mac running Derby Web Check In. To move it to OneDrive, Google Drive or another folder, open Derby Web Check In › Settings › Storage on that Mac.' }),
    ];
  }
  return groupsTab();
}

function groupsTab() {
  const groups = ev().groups;
  const counts = S.state.counts;
  const move = (i, d) => {
    const ids = groups.map((g) => g.id);
    [ids[i], ids[i + d]] = [ids[i + d], ids[i]];
    act('PUT', 'groups/order', { ids }).catch(() => {});
  };
  const rows = groups.map((g, i) => {
    const count = counts[g.rank] || 0;
    const canNumber = g.startNumber > 0 && count > 0;
    const sameStart = g.startNumber > 0 && groups.find((o) => o.id !== g.id && o.startNumber === g.startNumber);
    const label = g.subgroup || g.rank;
    const menuBtn = h('button', { class: 'btn link', title: 'More', onclick: (x) => {
      x.stopPropagation();
      popMenu(menuBtn, [
        { label: 'Number Cars Without a Number', disabled: !canNumber, run: () => act('POST', `groups/${g.id}/renumber`, { onlyUnnumbered: true }).catch(() => {}) },
        { label: `Renumber All Cars from ${g.startNumber}…`, disabled: !canNumber, run: async () => {
          if (await confirmDialog(`Renumber every car in ${groupLabel(g)}?`,
            `Cars get new numbers from ${g.startNumber} up, in last-name order. Any car already labelled will need a new number label.`,
            `Renumber ${count} Cars`)) {
            act('POST', `groups/${g.id}/renumber`, { onlyUnnumbered: false }).catch(() => {});
          }
        } },
        '-',
        { label: 'Delete Group', danger: true, run: () => act('DELETE', 'groups/' + g.id).catch(() => {}) },
      ]);
    } }, '⋯');
    return h('div', { class: 'grow-row' },
      h('div', { class: 'move' },
        h('button', { disabled: i === 0, title: 'Move up', onclick: () => move(i, -1) }, '▲'),
        h('button', { disabled: i === groups.length - 1, title: 'Move down', onclick: () => move(i, 1) }, '▼')),
      textField(`g:${g.id}:rank`, g.rank, (v) => act('PATCH', 'groups/' + g.id, { rank: v }).then((st) => { if (!groupFor(v.trim())) load(); }).catch(load),
        { onChangeOnly: true, spellcheck: 'false' }),
      textField(`g:${g.id}:sub`, g.subgroup, (v) => act('PATCH', 'groups/' + g.id, { subgroup: v }).catch(() => {}), { onChangeOnly: true }),
      textField(`g:${g.id}:start`, g.startNumber > 0 ? String(g.startNumber) : '', (v) => act('PATCH', 'groups/' + g.id, { startNumber: parseInt(v, 10) || 0 }).catch(() => {}),
        { cls: 'num', inputmode: 'numeric', onChangeOnly: true, placeholder: '—' }),
      h('span', { class: 'r muted cnt', title: `${count} cars in ${label}` }, String(count)),
      menuBtn,
      sameStart ? h('div', { class: 'gwarn' }, `⚠︎ Same start as ${sameStart.subgroup || sameStart.rank}`) : null);
  });
  return [
    h('div', { class: 'ghead' }, h('span'), h('span', null, 'Rank (GPRM)'), h('span', null, 'Subgroup name'), h('span', null, 'Starts at'), h('span', { class: 'r' }, 'Cars'), h('span')),
    h('div', { class: 'card' }, rows),
    h('div', { class: 'section-head', style: 'margin-top:12px' },
      h('button', { class: 'btn', onclick: () => act('POST', 'groups').catch(() => {}) }, '＋ Add Group'),
      h('span', { class: 'note', style: 'text-align:right' }, "Press Return to save a change. Next Available fills each group's numbers from its start.")),
  ];
}

// ---------- start ----------

function setup() {
  $('#search').addEventListener('input', (e) => { S.search = e.target.value; renderList(); });
  $('#groupFilter').addEventListener('change', (e) => { S.group = e.target.value; renderList(); });
  $('#statusFilter').addEventListener('change', (e) => { S.status = e.target.value; renderList(); });
  $('#btnNew').addEventListener('click', newRacer);
  $('#btnImport').addEventListener('click', importRoster);
  $('#btnGroups').addEventListener('click', () => openSettings('groups'));
  $('#btnSettings').addEventListener('click', () => openSettings());
  $('#btnBack').addEventListener('click', () => select(null));
  $('#btnExport').addEventListener('click', (x) => {
    x.stopPropagation();
    popMenu(x.currentTarget, [
      { label: 'Export Checked-In Racers for GPRM…', run: () => exportFor(true, 'gprm') },
      { label: 'Export All Racers for GPRM…', run: () => exportFor(false, 'gprm') },
      '-',
      { label: 'Export Checked-In Racers for DerbyNet…', run: () => exportFor(true, 'derbyNet') },
      { label: 'Export All Racers for DerbyNet…', run: () => exportFor(false, 'derbyNet') },
    ]);
  });
  document.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === ',') { e.preventDefault(); openSettings(); }
  });
  load().then(poll);
}

setup();
