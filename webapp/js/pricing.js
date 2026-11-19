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
