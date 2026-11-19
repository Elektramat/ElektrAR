// Port of Kabelmeter/Core/PricingCalculator.swift. Both run shared/pricing-cases.json
// (see pricing.test.ts and SharedPricingCasesTests.swift), so they cannot drift apart.

export type SalesUnit =
  | { type: "perMeter"; step: number; minimum: number }
  | { type: "fixedLengths"; lengthsM: number[] };

export type Cable = {
  id: string;
  sku: string;
  name: string;
  crossSection: string;
  use: string;
  pricePerMeter: number;
  sales: SalesUnit;
  stock: string;
  imageUrl: string | null;
  productUrl: string;
  isSample: boolean;
  shopProductId?: number | null;
};

export type Quote = {
  measured: number;
  required: number;
  pieces: number[];
  billedLength: number;
  price: number;
};

export const DEFAULT_RESERVE = 0.15;
export const RESERVE_MIN = 0;
export const RESERVE_MAX = 0.3;
/** 1 m at each end of the route. */
export const CONNECTION_ALLOWANCE = 2.0;
/** Absorbs floating point noise, so 10.000000001 m does not become 11 m. */
const TOLERANCE = 1e-6;

export function requiredLength(measured: number, reserve: number, allowance = CONNECTION_ALLOWANCE): number {
  const r = Math.min(Math.max(reserve, RESERVE_MIN), RESERVE_MAX);
  return Math.max(0, measured) * (1 + r) + allowance;
}

/** null when nothing is measured yet (the UI then shows the price per meter). */
export function quote(cable: Pick<Cable, "pricePerMeter" | "sales">, measured: number, reserve: number,
                      allowance = CONNECTION_ALLOWANCE): Quote | null {
  if (!Number.isFinite(measured) || measured <= 0) return null;
  const required = requiredLength(measured, reserve, allowance);
  const pieces = billedPieces(required, cable.sales);
  const billedLength = pieces.reduce((a, b) => a + b, 0);
  return { measured, required, pieces, billedLength, price: roundToCents(billedLength * cable.pricePerMeter) };
}

export function billedPieces(required: number, sales: SalesUnit): number[] {
  if (sales.type === "perMeter") {
    const steps = Math.ceil(required / sales.step - TOLERANCE);
    return [Math.max(sales.minimum, steps * sales.step)];
  }
  return cheapestRolls(required, sales.lengthsM);
}

/** Smallest total length that covers `required` (price is per meter); ties: fewest rolls. */
export function cheapestRolls(required: number, lengths: number[]): number[] {
  const sorted = [...new Set(lengths.filter((l) => l > 0))].sort((a, b) => a - b);
  const largest = sorted[sorted.length - 1];
  if (largest === undefined) return [];
  const single = sorted.find((l) => l >= required - TOLERANCE);
  if (single !== undefined) return [single];

  const unit = 100; // centimeters
  const target = Math.ceil(required * unit - TOLERANCE);
  const sizes = sorted.map((l) => Math.round(l * unit));
  const limit = target + Math.max(...sizes);
  if (limit > 2_000_000) return greedyRolls(required, sorted, largest);

  const fewest = new Array<number>(limit + 1).fill(Infinity);
  const last = new Array<number>(limit + 1).fill(-1);
  fewest[0] = 0;
  for (let s = 1; s <= limit; s++) {
    for (let i = 0; i < sizes.length; i++) {
      const size = sizes[i];
      if (size <= s && fewest[s - size] + 1 < fewest[s]) {
        fewest[s] = fewest[s - size] + 1;
        last[s] = i;
      }
    }
  }
  let s = target;
  while (s <= limit && fewest[s] === Infinity) s++;
  if (s > limit) return greedyRolls(required, sorted, largest);
  const pieces: number[] = [];
  while (s > 0) {
    const i = last[s];
    pieces.push(sorted[i]);
    s -= sizes[i];
  }
  return pieces.sort((a, b) => b - a);
}

function greedyRolls(required: number, sorted: number[], largest: number): number[] {
  const full = Math.floor(required / largest - TOLERANCE);
  const pieces = new Array<number>(full).fill(largest);
  const rest = required - full * largest;
  if (rest > TOLERANCE) pieces.push(sorted.find((l) => l >= rest - TOLERANCE) ?? largest);
  return pieces;
}

export function roundToCents(value: number): number {
  return Math.round(value * 100) / 100;
}
