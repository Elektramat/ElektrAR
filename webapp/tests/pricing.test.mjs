// Run: node --test webapp/tests
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { quote, billedPieces, cheapestRolls, requiredLength, pathLength, rollPlan, CONNECTION_ALLOWANCE } from '../js/pricing.js';
import { meters, orderLength, euro, parseMeters } from '../js/format.js';
import { wallPose } from '../js/wallpose.js';

const perMeter = { pricePerMeter: 0.99, sales: { type: 'perMeter', step: 1, minimum: 1 } };
const rolls = { pricePerMeter: 1, sales: { type: 'fixedLengths', lengthsM: [10, 25, 50, 100] } };

test('nothing measured gives no quote', () => {
  assert.equal(quote(perMeter, 0, 0.15), null);
  assert.equal(quote(perMeter, -1, 0.15), null);
  assert.equal(quote(perMeter, NaN, 0.15), null);
});

test('required length adds reserve and allowance', () => {
  assert.equal(requiredLength(10, 0.15), 10 * 1.15 + CONNECTION_ALLOWANCE);
  assert.equal(requiredLength(10, 0.5), 10 * 1.3 + 2, 'reserve is capped at 30%');
});

test('per meter rounds up to the next step', () => {
  const q = quote(perMeter, 7.4, 0.15); // 7.4 * 1.15 + 2 = 10.51
  assert.deepEqual(q.pieces, [11]);
  assert.equal(q.price, 10.89);
});

test('exactly on a step is not rounded up', () => {
  assert.deepEqual(billedPieces(10.000000001, perMeter.sales), [10]);
  assert.deepEqual(billedPieces(10, { type: 'perMeter', step: 5, minimum: 0 }), [10]);
  assert.deepEqual(billedPieces(10.01, { type: 'perMeter', step: 5, minimum: 0 }), [15]);
});

test('minimum order applies', () => {
  assert.deepEqual(billedPieces(3, { type: 'perMeter', step: 1, minimum: 5 }), [5]);
});

test('fixed lengths: smallest single roll that covers', () => {
  assert.deepEqual(billedPieces(22, rolls.sales), [25]);
  assert.deepEqual(billedPieces(10, rolls.sales), [10]);
});

test('fixed lengths: cheapest combination for long routes', () => {
  // Same as the Swift test: 1155 m, not "12 x 100" (= 1200 m).
  assert.equal(cheapestRolls(1152, [10, 25, 50, 100]).reduce((a, b) => a + b, 0), 1155);
  assert.deepEqual(cheapestRolls(110, [10, 25, 50, 100]), [100, 10]);
});

test('large values stay finite', () => {
  const q = quote(perMeter, 5000, 0.15);
  assert.equal(q.billedLength, 5752);
});

test('path length sums segments', () => {
  assert.equal(pathLength([{ x: 0, y: 0, z: 0 }, { x: 3, y: 0, z: 0 }, { x: 3, y: 4, z: 0 }]), 7);
});

test('dutch formatting', () => {
  assert.equal(meters(7.44), '7,4 m');
  assert.equal(orderLength(10), '10 m');
  assert.equal(euro(9.9).replace(/\s/g, ' '), '€ 9,90');
  assert.equal(parseMeters('2,5'), 2.5);
  assert.ok(Number.isNaN(parseMeters('abc')));
});

test('wall pose faces the camera and stays upright', () => {
  const m = wallPose({ x: 1, y: 1, z: 0 }, { x: 0, y: 0, z: -1 }, { x: 1, y: 1.5, z: 2 }, 0);
  assert.deepEqual([m[8], m[9], m[10]].map((v) => Math.round(v) + 0), [0, 0, 1]); // +Z out of the wall
  assert.deepEqual([m[4], m[5], m[6]].map((v) => Math.round(v) + 0), [0, 1, 0]); // +Y up
  assert.deepEqual([m[12], m[13], m[14]], [1, 1, 0]);
  assert.equal(wallPose({ x: 0, y: 0, z: 0 }, { x: 0, y: 1, z: 0 }, { x: 0, y: 1.5, z: 1 }), null, 'floor');
});

// The cases the iPhone app and the other web app also run (shared/pricing-cases.json).
const shared = JSON.parse(readFileSync(new URL('../../shared/pricing-cases.json', import.meta.url)));

test('shared cases: pieces', () => {
  for (const c of shared.pieces) assert.deepEqual(billedPieces(c.required, c.sales), c.pieces, JSON.stringify(c));
});

test('shared cases: quotes', () => {
  for (const c of shared.quotes) {
    const q = quote({ pricePerMeter: c.pricePerMeter, sales: c.sales }, c.measured, c.reserve);
    if (c.quote === null) assert.equal(q, null);
    else assert.deepEqual({ billedLength: q.billedLength, price: q.price }, c.quote, JSON.stringify(c));
  }
});

// Snelflex 3x2,5 rolls as on elektramat.nl on 19 Nov 2026.
const snelflex = [
  { lengthM: 100, price: 208.77 },
  { lengthM: 50, price: 117.66 },
  { lengthM: 25, price: 64.51 },
];

test('rolls: cheapest total price, not shortest length', () => {
  assert.deepEqual(rollPlan(120, snelflex).map((r) => r.lengthM), [100, 25]); // 273,28 < 100+50 (326,43)
  assert.deepEqual(rollPlan(60, snelflex).map((r) => r.lengthM), [50, 25]); // 182,17 < 100 (208,77)
  assert.deepEqual(rollPlan(26, snelflex).map((r) => r.lengthM), [50]); // 117,66 < 2 x 25 (129,02)
  assert.deepEqual(rollPlan(0, snelflex), []);
});

test('rolls: quote sums the roll prices', () => {
  const q = quote({ pricePerMeter: 2.09, sales: { type: 'fixedLengths', lengthsM: [100, 50, 25] }, rolls: snelflex }, 50, 0.15);
  // 50 * 1.15 + 2 = 59.5 m -> 50 + 25
  assert.deepEqual(q.pieces, [50, 25]);
  assert.equal(q.price, 182.17);
});
