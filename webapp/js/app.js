// Kabelmeter web app: same cables, pricing, switches and cart as the iOS app.
// Live AR measuring needs WebXR (Chrome on Android); elsewhere the route is entered
// per segment, and switches open in AR Quick Look on iPhone.

import { quote, DEFAULT_RESERVE, CONNECTION_ALLOWANCE, roundToCents } from './pricing.js';
import { meters, orderLength, pieces, euro, parseMeters, esc } from './format.js';
import { isARSupported, startAR } from './ar.js';

const $ = (selector) => document.querySelector(selector);

// Persisted per browser; reads and writes may fail in private mode.
const saved = {
  get(key, fallback) {
    try {
      const value = localStorage.getItem(`km.${key}`);
      return value === null ? fallback : JSON.parse(value);
    } catch {
      return fallback;
    }
  },
  set(key, value) {
    try { localStorage.setItem(`km.${key}`, JSON.stringify(value)); } catch { /* not saved */ }
  },
};

/** Lengths of the simulated route of the iOS Demo-modus: cabinet up, along the ceiling, down, to the switch. */
const EXAMPLE_ROUTE = ['1,4', '3,2', '1,25', '1,4'];
const DISCLAIMER = 'Dit is een schatting. Controleer de lengte zelf en laat het aansluiten over aan een installateur.';

const state = {
  mode: 'measure',
  cables: [],
  fixtures: [],
  loadError: null,
  cableId: saved.get('cableId', null),
  fixtureId: saved.get('fixtureId', null),
  reservePercent: saved.get('reservePercent', DEFAULT_RESERVE * 100),
  segments: saved.get('segments', ['']),
  list: saved.get('list', []), // planned fixtures: { id, fixtureId, arId? }
  cart: saved.get('cart', []),
  arSupported: false,
  quickLook: document.createElement('a').relList?.supports?.('ar') ?? false,
  ar: null,
  arState: { length: 0, confirmed: 0, points: 0, canAdd: false, canPlace: false, message: null },
};

const cable = () => state.cables.find((c) => c.id === state.cableId) ?? state.cables[0] ?? null;
const fixture = () =>
  state.fixtures.find((f) => f.id === state.fixtureId) ?? state.fixtures.find((f) => f.complete) ?? state.fixtures[0] ?? null;
const fixtureById = (id) => state.fixtures.find((f) => f.id === id);

function measured() {
  if (state.ar) return state.arState.length;
  return state.segments.map(parseMeters).filter((v) => Number.isFinite(v) && v > 0).reduce((a, b) => a + b, 0);
}

/** Stored line price; carts saved before prices were stored fall back to meters x price per meter. */
const linePrice = (item) => item.price ?? roundToCents(item.meters * item.pricePerMeter);

const currentQuote = () => (cable() ? quote(cable(), measured(), state.reservePercent / 100) : null);

function listTotal() {
  let price = 0;
  let incomplete = 0;
  for (const item of state.list) {
    const f = fixtureById(item.fixtureId);
    if (f?.price != null) price += f.price; else incomplete += 1;
  }
  return { price: roundToCents(price), incomplete };
}

// MARK: Icons

/** Rendered model preview (data/FixtureImages/<model>.png), or the drawn icon when it is missing. */
function fixturePreview(f, size = 52) {
  if (!f) return fixtureSvg(f, size * 0.6);
  return `<img class="preview" src="data/FixtureImages/${encodeURIComponent(f.model)}.png" alt="" width="${size}" height="${size}" loading="lazy"
    onerror="this.outerHTML=decodeURIComponent('${encodeURIComponent(fixtureSvg(f, size * 0.6))}')">`;
}

function fixtureSvg(f, size = 32) {
  const inner = f?.product === 'stopcontact'
    ? '<circle cx="16" cy="16" r="7.5" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="13" cy="16" r="1.3" fill="currentColor"/><circle cx="19" cy="16" r="1.3" fill="currentColor"/>'
    : '<rect x="9.5" y="9.5" width="13" height="13" rx="2" fill="none" stroke="currentColor" stroke-width="1.6"/>';
  return `<svg viewBox="0 0 32 32" width="${size}" height="${size}" aria-hidden="true"><rect x="3" y="3" width="26" height="26" rx="5" fill="none" stroke="currentColor" stroke-width="1.6"/>${inner}</svg>`;
}

/** AR Quick Look needs an <a rel="ar"> whose only child is an image, so the button is drawn as SVG. */
function quickLookButtonImage() {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="520" height="112" viewBox="0 0 520 112"><rect width="520" height="112" rx="28" fill="#196CAE"/><text x="260" y="66" text-anchor="middle" font-family="-apple-system, Helvetica, Arial, sans-serif" font-size="36" font-weight="600" fill="#fff">Bekijk op je muur (AR)</text></svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

// MARK: Rendering

function renderTop() {
  const placing = state.mode === 'place';
  const c = cable();
  const f = fixture();
  $('#chipIcon').innerHTML = placing ? fixturePreview(f, 36) : '🔌';
  $('#chipTitle').textContent = placing ? (f ? fixtureTitle(f) : 'Kies schakelmateriaal') : (c?.name ?? 'Kies een kabel');
  $('#chipSub').textContent = placing ? (f ? fixtureSubtitle(f) : '') : (c ? `${c.crossSection} · ${euro(c.pricePerMeter)}/m` : '');
  const count = state.cart.length;
  $('#cartBadge').hidden = count === 0;
  $('#cartBadge').textContent = String(count);
  $('#cartButton').setAttribute('aria-label', `Winkelmand, ${count} artikelen`);
  for (const button of document.querySelectorAll('.segmented button')) {
    button.setAttribute('aria-pressed', String(button.dataset.mode === state.mode));
  }
}

function fixtureTitle(f) {
  const base = f.product === 'stopcontact' ? 'Stopcontact' : 'Schakelaar';
  return f.mounting === 'opbouw' ? `${base} opbouw` : base;
}
const fixtureSubtitle = (f) => `${f.brand} ${f.line} · ${f.colour.replaceAll('-', ' ')}`;
const fixturePrice = (f) => (f.price != null ? `${euro(f.price)} complete set` : 'Niet compleet te bestellen');

function renderStatus() {
  const el = $('#status');
  let text = state.loadError;
  let warn = Boolean(text);
  if (!text && state.ar) {
    text = state.arState.message;
    warn = Boolean(text);
    if (!text && state.mode === 'measure' && state.arState.points === 0) text = 'Richt op het beginpunt en tik op +';
    if (!text && state.mode === 'place') text = 'Tik op + om te plaatsen';
  }
  el.hidden = !text;
  el.textContent = text ?? '';
  el.classList.toggle('warn', warn);
}

function renderMeasurePanel() {
  const panel = $('#measurePanel');
  panel.hidden = state.mode !== 'measure';
  if (panel.hidden) return;
  const arCard = state.arSupported
    ? `<div class="card"><h3>Meet met de camera</h3>
         <p class="muted small">Richt op de meterkast, tik op + en loop de route af. Lengte en prijs lopen live mee.</p>
         <button type="button" class="primary" data-action="start-ar">Start AR-meting</button></div>`
    : `<div class="card"><p class="muted small">Live meten met de camera werkt in Chrome op Android en in de iPhone-app.
         Vul hier de route stuk voor stuk in: omhoog vanaf de meterkast, langs het plafond, naar de schakelaar.</p></div>`;
  const rows = state.segments
    .map((value, i) => `<div class="segment-row">
        <label for="seg-${i}">Stuk ${i + 1}</label>
        <input id="seg-${i}" data-segment="${i}" inputmode="decimal" enterkeyhint="next" placeholder="0,0" value="${esc(value)}" aria-label="Stuk ${i + 1} in meter">
        <span class="muted">m</span>
        <button type="button" class="icon-button" data-remove="${i}" aria-label="Verwijder stuk ${i + 1}" ${state.segments.length === 1 ? 'disabled' : ''}>✕</button>
      </div>`)
    .join('');
  panel.innerHTML = `${arCard}
    <div class="card">
      <h3>Route in meters</h3>
      ${rows}
      <div class="row-buttons">
        <button type="button" class="secondary" data-action="add-segment">+ Stuk toevoegen</button>
        <button type="button" class="secondary" data-action="example">Voorbeeldroute</button>
      </div>
    </div>`;
}

function renderPlacePanel() {
  const panel = $('#placePanel');
  panel.hidden = state.mode !== 'place';
  if (panel.hidden) return;
  const f = fixture();
  if (!f) {
    panel.innerHTML = '<div class="card"><p>Geen schakelmateriaal gevonden.</p></div>';
    return;
  }
  const parts = f.parts
    .map((p) => `<li><span>${esc(p.description)}</span><span>${p.price != null ? euro(p.price) : ''} <a href="${esc(p.productUrl)}" target="_blank" rel="noopener">bekijk</a></span></li>`)
    .join('');
  let viewButton;
  if (state.arSupported) {
    viewButton = '<button type="button" class="primary" data-action="start-ar">Plaats met de camera</button>';
  } else if (state.quickLook) {
    viewButton = `<a rel="ar" href="data/Models/${encodeURIComponent(f.model)}.usdz"><img src="${quickLookButtonImage()}" alt="Bekijk op je muur (AR)" style="width:100%;height:auto;display:block"></a>`;
  } else {
    viewButton = '<p class="muted small">Open deze pagina op een telefoon om de schakelaar op je eigen muur te zien.</p>';
  }
  const listRows = groupList()
    .map(({ f: item, count, id }) => `<div class="list-row">
        <span>${count} × ${esc(fixtureTitle(item))} <span class="muted small">${esc(item.line)} ${esc(item.colour.replaceAll('-', ' '))}</span></span>
        <span>${item.price != null ? euro(item.price * count) : '<span class="warn-text small">geen prijs</span>'}
          <button type="button" class="icon-button" data-unlist="${esc(id)}" aria-label="Eén minder">−</button></span>
      </div>`)
    .join('');
  panel.innerHTML = `<div class="card">
      <div class="fixture-head"><div class="fixture-icon">${fixturePreview(f, 56)}</div>
        <div><div class="pick-title">${esc(fixtureTitle(f))}</div><div class="muted small">${esc(fixtureSubtitle(f))}</div>
        <div class="small ${f.complete ? '' : 'warn-text'}">${esc(fixturePrice(f))}</div></div></div>
      ${viewButton}
      <button type="button" class="secondary" data-action="list-add" style="margin-top:8px">Zet op mijn lijst</button>
      <ul class="parts">${parts}</ul>
    </div>
    <div class="card"><h3>Mijn lijst</h3>${listRows || '<p class="muted small">Nog niets op de lijst.</p>'}</div>`;
}

/** List grouped per fixture, in the order first added; `id` is the last entry, removed by "−". */
function groupList() {
  const groups = new Map();
  for (const item of state.list) {
    const f = fixtureById(item.fixtureId);
    if (!f) continue;
    const group = groups.get(f.id) ?? { f, count: 0, id: item.id };
    group.count += 1;
    group.id = item.id;
    groups.set(f.id, group);
  }
  return [...groups.values()];
}

function renderBar() {
  const bar = $('#bar');
  if (state.mode === 'place') {
    const total = listTotal();
    bar.innerHTML = `<div class="bar-top">
        <div><div class="length">Op de lijst: ${state.list.length}</div>
          <div class="muted small">${state.ar ? 'Geplaatst in AR komt ook op de lijst' : 'Prijs van complete sets'}</div></div>
        <div><div class="price">${euro(total.price)}</div>
          ${total.incomplete ? `<div class="small warn-text" style="text-align:right">${total.incomplete} zonder prijs</div>` : ''}</div>
      </div>`;
    return;
  }
  const c = cable();
  const q = currentQuote();
  const priceBlock = q
    ? `<div class="price">${euro(q.price)}</div>`
    : c ? `<div class="price">${euro(c.pricePerMeter)}</div><div class="muted small" style="text-align:right">per meter</div>` : '';
  bar.innerHTML = `<div class="bar-top">
      <div><div class="length">Gemeten: ${meters(measured())}</div>
        <div class="length">Te bestellen: ${q ? pieces(q.pieces) : '–'}</div>
        ${c?.isSample ? '<span class="sample-badge">Voorbeelddata</span>' : ''}</div>
      <div>${priceBlock}</div>
    </div>
    <div class="stepper"><span>Reserve ${state.reservePercent}% + ${orderLength(CONNECTION_ALLOWANCE)} aansluiting</span>
      <div><button type="button" data-action="reserve-down" aria-label="Minder reserve" ${state.reservePercent <= 0 ? 'disabled' : ''}>−</button>
      <button type="button" data-action="reserve-up" aria-label="Meer reserve" ${state.reservePercent >= 30 ? 'disabled' : ''}>+</button></div></div>
    <button type="button" class="primary cta" data-action="add-to-cart" ${q && c ? '' : 'disabled'}>Voeg toe aan winkelmand</button>`;
}

function renderAR() {
  const inAR = Boolean(state.ar);
  $('#crosshair').hidden = !inAR;
  $('#arControls').hidden = !inAR;
  if (!inAR) return;
  const placing = state.mode === 'place';
  const can = placing ? state.arState.canPlace && Boolean(fixture()) : state.arState.canAdd;
  $('#crosshair').classList.toggle('active', can);
  $('#arAdd').disabled = !can;
  $('#arAdd').setAttribute('aria-label', placing ? `Plaats ${fixture() ? fixtureTitle(fixture()) : 'schakelaar'}` : 'Punt toevoegen');
  const arPlaced = state.list.filter((item) => item.arId).length;
  $('#arUndo').disabled = placing ? arPlaced === 0 : state.arState.points === 0;
  $('#arReset').disabled = placing ? arPlaced === 0 : state.arState.points === 0;
}

function renderAll() {
  renderTop();
  renderStatus();
  renderMeasurePanel();
  renderPlacePanel();
  renderBar();
  renderAR();
}

// MARK: Picker and cart sheets

function openPicker() {
  const placing = state.mode === 'place';
  $('#pickerTitle').textContent = placing ? 'Kies schakelmateriaal' : 'Kies een kabel';
  $('#pickerSearch').placeholder = placing ? 'Zoek serie, kleur of type' : 'Zoek kabel';
  $('#pickerSearch').value = '';
  renderPicker();
  $('#picker').showModal();
}

function renderPicker() {
  const query = $('#pickerSearch').value.trim().toLowerCase();
  const matches = (...texts) => !query || texts.some((t) => String(t).toLowerCase().includes(query));
  let html = '';
  if (state.mode === 'place') {
    const items = state.fixtures.filter((f) => matches(fixtureTitle(f), fixtureSubtitle(f), f.productName));
    let line = null;
    for (const f of items) {
      if (f.line !== line) {
        line = f.line;
        html += `<div class="group-title">${esc(line)}</div>`;
      }
      html += `<button type="button" class="pick" data-pick="${esc(f.id)}">
          <span class="thumb">${fixturePreview(f, 52)}</span>
          <span class="pick-text"><span class="pick-title">${esc(fixtureTitle(f))}</span><br>
            <span class="muted small">${esc(f.colour.replaceAll('-', ' '))}</span><br>
            <span class="small ${f.complete ? '' : 'warn-text'}">${esc(fixturePrice(f))}</span></span>
          ${f.id === fixture()?.id ? '<span class="check" aria-label="gekozen">✓</span>' : ''}
        </button>`;
    }
  } else {
    for (const c of state.cables.filter((c) => matches(c.name, c.crossSection, c.use))) {
      html += `<button type="button" class="pick" data-pick="${esc(c.id)}">
          <img src="data/CableImages/${encodeURIComponent(c.sku)}.jpg" alt="" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'thumb',textContent:'🔌'}))">
          <span class="pick-text"><span class="pick-title">${esc(c.name)}</span><br>
            <span class="muted small">${esc(c.crossSection)} · ${esc(c.use)}</span><br>
            <span class="small">${euro(c.pricePerMeter)} per meter · ${esc(c.stock)}</span>
            ${c.isSample ? '<br><span class="sample-badge">Voorbeelddata</span>' : ''}</span>
          ${c.id === cable()?.id ? '<span class="check" aria-label="gekozen">✓</span>' : ''}
        </button>`;
    }
  }
  $('#pickerList').innerHTML = html || `<p class="muted">Niets gevonden voor “${esc(query)}”.</p>`;
}

function renderCart() {
  const body = $('#cartBody');
  if (!state.cart.length) {
    body.innerHTML = `<p class="muted">De winkelmand is leeg. Meet een route en tik op “Voeg toe aan winkelmand”.</p><p class="muted small">${DISCLAIMER}</p>`;
    return;
  }
  const total = roundToCents(state.cart.reduce((sum, item) => sum + linePrice(item), 0));
  body.innerHTML = state.cart
    .map((item, i) => `<div class="cart-item">
        <div class="bar-top"><div><div class="pick-title">${esc(item.name)}</div>
          <div class="muted small">${esc(item.crossSection)} · ${item.pieces ? pieces(item.pieces) : orderLength(item.meters)}</div></div>
          <div class="pick-title">${euro(linePrice(item))}</div></div>
        <div class="row-buttons">
          <a class="secondary" href="${esc(item.productUrl)}" target="_blank" rel="noopener">Bestel op elektramat.nl</a>
          <button type="button" class="secondary" data-cart-remove="${i}">Verwijder</button>
        </div></div>`)
    .join('') +
    `<div class="total"><span>Totaal</span><span>${euro(total)}</span></div>
     <button type="button" class="secondary" data-action="cart-clear">Leegmaken</button>
     <p class="muted small">${DISCLAIMER}</p>`;
}

// MARK: Actions

function toast(message) {
  const el = $('#toast');
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { el.hidden = true; }, 2200);
}

function vibrate(ms = 15) {
  navigator.vibrate?.(ms);
}

function addToCart() {
  const c = cable();
  const q = currentQuote();
  if (!c || !q) return;
  // The line price is stored: roll cables cost the sum of their roll prices, not meters x price per meter.
  const existing = state.cart.find((item) => item.cableId === c.id);
  if (existing) {
    existing.price = roundToCents(linePrice(existing) + q.price);
    existing.pieces = [...(existing.pieces ?? [existing.meters]), ...q.pieces];
    existing.meters += q.billedLength;
  } else {
    state.cart.push({ cableId: c.id, sku: c.sku, name: c.name, crossSection: c.crossSection, pricePerMeter: c.pricePerMeter, meters: q.billedLength, pieces: q.pieces, price: q.price, productUrl: c.productUrl });
  }
  saved.set('cart', state.cart);
  vibrate(30);
  toast(`${orderLength(q.billedLength)} ${c.name} toegevoegd`);
  renderTop();
}

function addToList(fixtureId, arId = null) {
  state.list.push({ id: crypto.randomUUID(), fixtureId, ...(arId ? { arId } : {}) });
  saved.set('list', state.list);
}

function removeFromList(id) {
  const item = state.list.find((entry) => entry.id === id);
  if (item?.arId) state.ar?.removePlaced(item.arId);
  state.list = state.list.filter((entry) => entry.id !== id);
  saved.set('list', state.list);
}

async function enterAR() {
  let lastConfirmed = 0;
  try {
    state.ar = await startAR({
      overlay: $('#app'),
      getMode: () => state.mode,
      getFixture: fixture,
      onFrame: (s) => {
        state.arState = s;
        lastConfirmed = s.confirmed;
        renderStatus();
        renderBar();
        renderAR();
      },
      onEnd: () => {
        state.ar = null;
        document.body.classList.remove('in-ar');
        // Keep the camera measurement as one route segment.
        if (lastConfirmed > 0) {
          state.segments = [String(Math.round(lastConfirmed * 100) / 100).replace('.', ',')];
          saved.set('segments', state.segments);
        }
        state.list = state.list.map(({ arId, ...rest }) => rest);
        saved.set('list', state.list);
        renderAll();
      },
    });
    document.body.classList.add('in-ar');
    renderAll();
  } catch {
    state.ar = null;
    toast('AR kon niet starten. Vul de route in meters in.');
  }
}

function onClick(event) {
  const target = event.target.closest('button, [data-action]');
  if (!target) return;
  const { action, mode, pick, remove, unlist, cartRemove } = target.dataset;
  if (target.matches('[data-close]')) target.closest('dialog').close();
  else if (mode) {
    state.mode = mode;
    renderAll();
  } else if (pick) {
    if (state.mode === 'place') { state.fixtureId = pick; saved.set('fixtureId', pick); } else { state.cableId = pick; saved.set('cableId', pick); }
    $('#picker').close();
    renderAll();
  } else if (remove !== undefined) {
    state.segments.splice(Number(remove), 1);
    saved.set('segments', state.segments);
    renderMeasurePanel();
    renderBar();
  } else if (unlist) {
    removeFromList(unlist);
    renderAll();
  } else if (cartRemove !== undefined) {
    state.cart.splice(Number(cartRemove), 1);
    saved.set('cart', state.cart);
    renderCart();
    renderTop();
  }

  switch (action) {
    case 'start-ar': enterAR(); break;
    case 'add-segment':
      state.segments.push('');
      saved.set('segments', state.segments);
      renderMeasurePanel();
      $(`#seg-${state.segments.length - 1}`)?.focus();
      break;
    case 'example':
      state.segments = [...EXAMPLE_ROUTE];
      saved.set('segments', state.segments);
      renderMeasurePanel();
      renderBar();
      break;
    case 'reserve-down':
    case 'reserve-up':
      state.reservePercent = Math.min(30, Math.max(0, state.reservePercent + (action === 'reserve-up' ? 5 : -5)));
      saved.set('reservePercent', state.reservePercent);
      renderBar();
      break;
    case 'add-to-cart': addToCart(); break;
    case 'list-add':
      if (fixture()) {
        addToList(fixture().id);
        toast(`${fixtureTitle(fixture())} op de lijst gezet`);
        renderAll();
      }
      break;
    case 'cart-clear':
      state.cart = [];
      saved.set('cart', state.cart);
      renderCart();
      renderTop();
      break;
  }
}

function bindAR() {
  $('#arAdd').addEventListener('click', () => {
    if (!state.ar) return;
    if (state.mode === 'place') {
      const f = fixture();
      const id = state.ar.place(f);
      if (id) { addToList(f.id, id); vibrate(25); }
    } else if (state.ar.addPoint()) {
      vibrate();
    }
    renderAll();
  });
  $('#arUndo').addEventListener('click', () => {
    if (state.mode === 'place') {
      const last = [...state.list].reverse().find((item) => item.arId);
      if (last) removeFromList(last.id);
    } else {
      state.ar?.undoPoint();
    }
    renderAll();
  });
  $('#arReset').addEventListener('click', () => {
    if (state.mode === 'place') {
      for (const item of state.list.filter((entry) => entry.arId)) removeFromList(item.id);
    } else {
      state.ar?.resetPoints();
    }
    renderAll();
  });
  $('#arExit').addEventListener('click', () => state.ar?.end());
}

async function load() {
  try {
    const [cables, fixtures] = await Promise.all(
      ['data/cables.json', 'data/fixtures.json'].map((url) => fetch(url).then((r) => {
        if (!r.ok) throw new Error(url);
        return r.json();
      })),
    );
    state.cables = cables;
    state.fixtures = fixtures;
  } catch {
    state.loadError = 'Gegevens konden niet worden geladen. Start de app via een webserver (zie README).';
  }
  state.arSupported = await isARSupported();
  renderAll();
}

document.addEventListener('click', onClick);
document.addEventListener('input', (event) => {
  if (event.target.id === 'pickerSearch') renderPicker();
  const index = event.target.dataset?.segment;
  if (index !== undefined) {
    state.segments[Number(index)] = event.target.value;
    saved.set('segments', state.segments);
    renderBar();
  }
});
$('#chip').addEventListener('click', openPicker);
$('#cartButton').addEventListener('click', () => { renderCart(); $('#cart').showModal(); });
for (const dialog of document.querySelectorAll('dialog')) {
  dialog.addEventListener('click', (event) => { if (event.target === dialog) dialog.close(); });
}
bindAR();
renderAll();
load();
