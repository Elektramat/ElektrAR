// Port of Kabelmeter/Core/PricingCalculator.swift. Both run shared/pricing-cases.json
// (see pricing.test.ts and SharedPricingCasesTests.swift), so they cannot drift apart.

export type SalesUnit =
	| { type: 'perMeter'; step: number; minimum: number }
	| { type: 'fixedLengths'; lengthsM: number[] };

/** One roll size of a cable the shop sells as separate roll products. A shorter roll costs more
 * per meter, so each roll has its own price (incl. VAT, for the whole roll), article number and
 * product page. */
export type CableRoll = {
	lengthM: number;
	sku: string;
	price: number;
	productUrl: string;
	shopProductId?: number | null;
	stock?: string | null;
};

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
	/** Cables sold as rolls of several lengths, each with its own price. Then `sales` is
	 * `fixedLengths` with the same lengths and `pricePerMeter` is the cheapest one. */
	rolls?: CableRoll[] | null;
};

/** True when the shop sells this cable as roll products. */
export const hasRolls = (cable: Pick<Cable, 'rolls'>) => (cable.rolls ?? []).length > 0;

export type Quote = {
	measured: number;
	required: number;
	pieces: number[];
	billedLength: number;
	/** billedLength * pricePerMeter rounded to cents; for roll products the sum of the roll prices. */
	price: number;
};

export const DEFAULT_RESERVE = 0.15;
export const RESERVE_MIN = 0;
export const RESERVE_MAX = 0.3;
/** 1 m at each end of the route. */
export const CONNECTION_ALLOWANCE = 2.0;
/** Absorbs floating point noise, so 10.000000001 m does not become 11 m. */
const TOLERANCE = 1e-6;

export function requiredLength(
	measured: number,
	reserve: number,
	allowance = CONNECTION_ALLOWANCE
): number {
	const r = Math.min(Math.max(reserve, RESERVE_MIN), RESERVE_MAX);
	return Math.max(0, measured) * (1 + r) + allowance;
}

/** null when nothing is measured yet (the UI then shows the price per meter). */
export function quote(
	cable: Pick<Cable, 'pricePerMeter' | 'sales' | 'rolls'>,
	measured: number,
	reserve: number,
	allowance = CONNECTION_ALLOWANCE
): Quote | null {
	if (!Number.isFinite(measured) || measured <= 0) return null;
	const required = requiredLength(measured, reserve, allowance);
	if (cable.rolls && cable.rolls.length > 0) {
		const plan = rollPlan(required, cable.rolls);
		return {
			measured,
			required,
			pieces: plan.map((r) => r.lengthM),
			billedLength: plan.reduce((a, r) => a + r.lengthM, 0),
			price: roundToCents(plan.reduce((a, r) => a + r.price, 0))
		};
	}
	const pieces = billedPieces(required, cable.sales);
	const billedLength = pieces.reduce((a, b) => a + b, 0);
	return {
		measured,
		required,
		pieces,
		billedLength,
		price: roundToCents(billedLength * cable.pricePerMeter)
	};
}

export function billedPieces(required: number, sales: SalesUnit): number[] {
	if (sales.type === 'perMeter') {
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

/**
 * The rolls to order for `required` meters: the combination with the lowest total price that
 * covers the length. A shorter roll costs more per meter, so the cheapest combination is not
 * always the shortest one. Ties: fewest rolls, then least left over. Longest roll first.
 * Exact search on whole centimeters; falls back to "best price per meter, then the cheapest
 * roll that covers the rest" for absurd lengths. Port of PricingCalculator.rollPlan.
 */
export function rollPlan(required: number, rolls: CableRoll[]): CableRoll[] {
	const options = rolls.filter((r) => r.lengthM > 0 && r.price >= 0);
	if (options.length === 0 || !(required > TOLERANCE)) return [];
	const unit = 100; // centimeters
	const sizes = options.map((r) => Math.round(r.lengthM * unit));
	const costs = options.map((r) => Math.round(r.price * 100));
	const target = Math.ceil(required * unit - TOLERANCE);
	const limit = target + Math.max(...sizes);
	if (limit > 2_000_000) return greedyRollPlan(required, options);

	const cost = new Array<number>(limit + 1).fill(Infinity);
	const count = new Array<number>(limit + 1).fill(Infinity);
	const last = new Array<number>(limit + 1).fill(-1);
	cost[0] = 0;
	count[0] = 0;
	for (let s = 1; s <= limit; s++) {
		for (let i = 0; i < sizes.length; i++) {
			const size = sizes[i];
			if (size > s || cost[s - size] === Infinity) continue;
			const c = cost[s - size] + costs[i];
			const n = count[s - size] + 1;
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
		if (best < 0 || cost[s] < cost[best] || (cost[s] === cost[best] && count[s] < count[best])) {
			best = s;
		}
	}
	if (best < 0) return greedyRollPlan(required, options);
	const plan: CableRoll[] = [];
	for (let s = best; s > 0; s -= sizes[last[s]]) plan.push(options[last[s]]);
	return plan.sort((a, b) => b.lengthM - a.lengthM);
}

function greedyRollPlan(required: number, options: CableRoll[]): CableRoll[] {
	const best = options.reduce((a, b) => (b.price / b.lengthM < a.price / a.lengthM ? b : a));
	const full = Math.floor(required / best.lengthM - TOLERANCE);
	const plan = new Array<CableRoll>(full).fill(best);
	const rest = required - full * best.lengthM;
	if (rest > TOLERANCE) {
		const covering = options
			.filter((r) => r.lengthM >= rest - TOLERANCE)
			.reduce<CableRoll | null>((a, b) => (a === null || b.price < a.price ? b : a), null);
		plan.push(covering ?? best);
	}
	return plan.sort((a, b) => b.lengthM - a.lengthM);
}

/** Rolls grouped by size, longest first: one entry per roll product with how many to order. */
export function groupRolls(plan: CableRoll[]): { roll: CableRoll; count: number }[] {
	const groups = new Map<string, { roll: CableRoll; count: number }>();
	for (const roll of plan) {
		const group = groups.get(roll.sku);
		if (group) group.count++;
		else groups.set(roll.sku, { roll, count: 1 });
	}
	return [...groups.values()].sort((a, b) => b.roll.lengthM - a.roll.lengthM);
}

export function roundToCents(value: number): number {
	return Math.round(value * 100) / 100;
}
