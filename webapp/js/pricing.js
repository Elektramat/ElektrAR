// Pricing rules, ported 1:1 from Kabelmeter/Core/PricingCalculator.swift.
// All lengths in meters, prices in euros. Pure functions, tested in tests/pricing.test.mjs.

export const DEFAULT_RESERVE = 0.15;
export const MAX_RESERVE = 0.30;
/** 1 m at each end of the route. */
export const CONNECTION_ALLOWANCE = 2.0;
/** Absorbs floating point noise, so 10.000000001 m does not become 11 m. */
const TOLERANCE = 1e-6;

export function roundToCents(value) {
  return Math.round(value * 100) / 100;
}

export function requiredLength(measured, reserve, allowance = CONNECTION_ALLOWANCE) {
  const r = Math.min(Math.max(reserve, 0), MAX_RESERVE);
  return Math.max(0, measured) * (1 + r) + allowance;
}

/** Returns null when nothing is measured yet (the UI then shows the price per meter). */
export function quote(cable, measured, reserve, allowance = CONNECTION_ALLOWANCE) {
  if (!Number.isFinite(measured) || measured <= 0) return null;
  const required = requiredLength(measured, reserve, allowance);
  if (cable.rolls?.length) {
    // Sold as separate roll products, each with its own price.
    const plan = rollPlan(required, cable.rolls);
    const billed = plan.reduce((a, r) => a + r.lengthM, 0);
    return { measured, required, pieces: plan.map((r) => r.lengthM), billedLength: billed, price: roundToCents(plan.reduce((a, r) => a + r.price, 0)) };
  }
  const pieces = billedPieces(required, cable.sales);
  const billedLength = pieces.reduce((a, b) => a + b, 0);
  return { measured, required, pieces, billedLength, price: roundToCents(billedLength * cable.pricePerMeter) };
}

export function billedPieces(required, sales) {
  if (sales.type === 'perMeter') {
    const steps = Math.ceil(required / sales.step - TOLERANCE);
    return [Math.max(sales.minimum ?? 0, steps * sales.step)];
  }
  return cheapestRolls(required, sales.lengthsM);
}

/**
 * The combination of rolls with the smallest total length that covers `required`
 * (price is per meter, so shortest total = cheapest). Ties: fewest rolls.
 */
export function cheapestRolls(required, lengths) {
  const sorted = [...new Set(lengths.filter((l) => l > 0))].sort((a, b) => a - b);
  if (sorted.length === 0) return [];
  const largest = sorted[sorted.length - 1];
  const single = sorted.find((l) => l >= required - TOLERANCE);
  if (single !== undefined) return [single];

  const target = Math.ceil(required * 100 - TOLERANCE);
  const sizes = sorted.map((l) => Math.round(l * 100));
  const limit = target + Math.max(...sizes);
  if (limit > 2_000_000) return greedyRolls(required, sorted, largest);

  const fewest = new Int32Array(limit + 1).fill(-1);
  const last = new Int32Array(limit + 1).fill(-1);
  fewest[0] = 0;
  for (let s = 1; s <= limit; s++) {
    for (let i = 0; i < sizes.length; i++) {
      const prev = s - sizes[i];
      if (prev >= 0 && fewest[prev] >= 0 && (fewest[s] < 0 || fewest[prev] + 1 < fewest[s])) {
        fewest[s] = fewest[prev] + 1;
        last[s] = i;
      }
    }
  }
  let s = target;
  while (s <= limit && fewest[s] < 0) s++;
  if (s > limit) return greedyRolls(required, sorted, largest);
  const pieces = [];
  while (s > 0) {
    pieces.push(sorted[last[s]]);
    s -= sizes[last[s]];
  }
  return pieces.sort((a, b) => b - a);
}

function greedyRolls(required, sorted, largest) {
  const full = Math.floor(required / largest - TOLERANCE);
  const pieces = Array(full).fill(largest);
  const rest = required - full * largest;
  if (rest > TOLERANCE) pieces.push(sorted.find((l) => l >= rest - TOLERANCE) ?? largest);
  return pieces;
}

/** Sum of straight segments between consecutive points ({x,y,z} in meters). */
export function pathLength(points) {
  let total = 0;
  for (let i = 1; i < points.length; i++) total += distance(points[i - 1], points[i]);
  return total;
}

export function distance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);
}

/**
 * The rolls to order for `required` meters: the combination with the lowest total price that
 * covers the length (a shorter roll costs more per meter). Ties: fewest rolls, then least left
 * over. Longest roll first. Port of PricingCalculator.rollPlan in Swift.
 */
export function rollPlan(required, rolls) {
  const options = rolls.filter((r) => r.lengthM > 0 && r.price >= 0);
  if (!options.length || required <= TOLERANCE) return [];
  const cms = options.map((r) => Math.round(r.lengthM * 100));
  const costs = options.map((r) => Math.round(r.price * 100));
  const targetCm = Math.ceil(required * 100 - TOLERANCE);
  if (targetCm + Math.max(...cms) > 2_000_000) return greedyRollPlan(required, options);
  const gcd = (a, b) => (b === 0 ? a : gcd(b, a % b));
  const step = cms.reduce(gcd, 0);
  const sizes = cms.map((c) => c / step);
  const target = Math.ceil(targetCm / step);
  const limit = target + Math.max(...sizes);
  const cost = new Array(limit + 1).fill(Infinity);
  const count = new Array(limit + 1).fill(Infinity);
  const last = new Array(limit + 1).fill(-1);
  cost[0] = 0;
  count[0] = 0;
  for (let s = 1; s <= limit; s++) {
    for (let i = 0; i < sizes.length; i++) {
      if (sizes[i] > s || cost[s - sizes[i]] === Infinity) continue;
      const c = cost[s - sizes[i]] + costs[i];
      const n = count[s - sizes[i]] + 1;
      if (c < cost[s] || (c === cost[s] && n < count[s])) {
        cost[s] = c;
        count[s] = n;
        last[s] = i;
      }
    }
  }
  let best = -1;
  for (let s = target; s <= limit; s++) {
    if (cost[s] === Infinity) continue;
    if (best < 0 || cost[s] < cost[best] || (cost[s] === cost[best] && count[s] < count[best])) best = s;
  }
  if (best < 0) return greedyRollPlan(required, options);
  const plan = [];
  for (let s = best; s > 0; s -= sizes[last[s]]) plan.push(options[last[s]]);
  return plan.sort((a, b) => b.lengthM - a.lengthM);
}

function greedyRollPlan(required, options) {
  const best = options.reduce((a, b) => (b.price / b.lengthM < a.price / a.lengthM ? b : a));
  const full = Math.floor(required / best.lengthM - TOLERANCE);
  const plan = Array(full).fill(best);
  const rest = required - full * best.lengthM;
  if (rest > TOLERANCE) {
    const covering = options.filter((r) => r.lengthM >= rest - TOLERANCE).sort((a, b) => a.price - b.price)[0];
    plan.push(covering ?? best);
  }
  return plan.sort((a, b) => b.lengthM - a.lengthM);
}
