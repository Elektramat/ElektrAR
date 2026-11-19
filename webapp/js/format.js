// Dutch number formatting (comma decimals, euro), like Kabelmeter/Core/Format.swift.

const oneDecimal = new Intl.NumberFormat('nl-NL', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const upToOne = new Intl.NumberFormat('nl-NL', { maximumFractionDigits: 1 });
const euroFormat = new Intl.NumberFormat('nl-NL', { style: 'currency', currency: 'EUR' });

/** "7,4 m" */
export const meters = (v) => `${oneDecimal.format(v)} m`;
/** "10 m" or "10,5 m" */
export const orderLength = (v) => `${upToOne.format(v)} m`;
/** "100 m + 25 m" */
export const pieces = (list) => list.map(orderLength).join(' + ');
/** "€ 9,90" */
export const euro = (v) => euroFormat.format(v);

/** Parses "2,5" or "2.5"; returns NaN for anything else. */
export function parseMeters(text) {
  const clean = String(text).trim().replace(',', '.');
  return /^\d*\.?\d+$/.test(clean) ? Number(clean) : NaN;
}

/** Escapes text for use inside innerHTML. */
export function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}
