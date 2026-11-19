import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { billedPieces, quote, rollPlan, type CableRoll, type SalesUnit } from './pricing';
import { count, euro, meters, orderLength, pieces, rolls as formatRolls } from './format';
import { cables, parseCatalog } from './catalog';

/** The Snelflex 3x2,5 rolls: a shorter roll costs more per meter. */
const roll = (lengthM: number, price: number): CableRoll => ({
	lengthM,
	sku: `R${lengthM}`,
	price,
	productUrl: 'https://www.elektramat.nl/',
	shopProductId: lengthM,
	stock: null
});
const snelflexRolls = [roll(100, 208.77), roll(50, 117.66), roll(25, 64.51)];
const snelflex = {
	id: 'S',
	sku: 'R100',
	name: 'Snelflex',
	crossSection: '3x2,5 mm²',
	use: 'x',
	pricePerMeter: 2.0877,
	sales: { type: 'fixedLengths', lengthsM: [100, 50, 25] } as SalesUnit,
	stock: 'x',
	imageUrl: null,
	productUrl: 'https://www.elektramat.nl/',
	isSample: false,
	rolls: snelflexRolls
};

// The same file the Swift tests run (SharedPricingCasesTests), so both apps agree.
const cases = JSON.parse(
	readFileSync(new URL('../../../shared/pricing-cases.json', import.meta.url), 'utf8')
) as {
	pieces: { required: number; sales: SalesUnit; pieces: number[] }[];
	quotes: {
		measured: number;
		reserve: number;
		pricePerMeter: number;
		sales: SalesUnit;
		quote: { billedLength: number; price: number } | null;
	}[];
};

describe('pricing (shared cases)', () => {
	it.each(cases.pieces)('pieces for $required m', (c) => {
		expect(billedPieces(c.required, c.sales)).toEqual(c.pieces);
	});

	it.each(cases.quotes)('quote for $measured m', (c) => {
		const q = quote({ pricePerMeter: c.pricePerMeter, sales: c.sales }, c.measured, c.reserve);
		expect(q?.billedLength ?? null).toBe(c.quote?.billedLength ?? null);
		expect(q?.price ?? null).toBe(c.quote?.price ?? null);
	});

	it('gives no quote for invalid input', () => {
		const cable = {
			pricePerMeter: 1,
			sales: { type: 'perMeter', step: 1, minimum: 1 } as SalesUnit
		};
		expect(quote(cable, -1, 0.15)).toBeNull();
		expect(quote(cable, Number.NaN, 0.15)).toBeNull();
		expect(quote(cable, Number.POSITIVE_INFINITY, 0.15)).toBeNull();
	});

	it('falls back without hanging on huge lengths', () => {
		const p = billedPieces(50_000, { type: 'fixedLengths', lengthsM: [10, 100] });
		expect(p.reduce((a, b) => a + b, 0)).toBe(50_000);
	});
});

// Same cases as RollPlanTests in PricingCalculatorTests.swift.
describe('roll plan', () => {
	const plan = (required: number, options = snelflexRolls) =>
		rollPlan(required, options).map((r) => r.lengthM);

	it('takes the shortest roll for a small length', () => {
		expect(plan(5.2)).toEqual([25]);
		expect(plan(25)).toEqual([25]);
	});
	it('takes the cheapest cover just over a roll', () => {
		expect(plan(25.1)).toEqual([50]); // 117,66 beats 25+25 (129,02)
		expect(plan(60)).toEqual([50, 25]); // 182,17 beats 100 (208,77)
	});
	it('prefers the big roll when it is cheaper', () => {
		expect(plan(80)).toEqual([100]); // 208,77 beats 50+25+25 (246,68)
		expect(plan(100)).toEqual([100]);
	});
	it('combines several rolls', () => {
		expect(plan(150)).toEqual([100, 50]);
		expect(plan(210)).toEqual([100, 100, 25]);
	});
	it('picks the cheapest, not the shortest, combination', () => {
		expect(plan(70)).toEqual([50, 25]);
		expect(plan(70, [roll(100, 150), roll(50, 117.66), roll(25, 64.51)])).toEqual([100]);
	});
	it('needs no rolls for nothing', () => {
		expect(rollPlan(0, snelflexRolls)).toEqual([]);
		expect(rollPlan(10, [])).toEqual([]);
	});
	it('falls back without hanging on huge lengths', () => {
		const p = plan(50_000);
		expect(p.reduce((a, b) => a + b, 0)).toBeGreaterThanOrEqual(50_000);
	});
	it('prices a quote with the roll prices', () => {
		const q = quote(snelflex, 10, 0.15);
		expect(q?.required).toBeCloseTo(13.5, 9);
		expect(q?.pieces).toEqual([25]);
		expect(q?.billedLength).toBe(25);
		expect(q?.price).toBe(64.51);
	});
});

describe('format', () => {
	it('uses Dutch numbers', () => {
		expect(meters(7.4)).toBe('7,4 m');
		expect(orderLength(10)).toBe('10 m');
		expect(orderLength(3.5)).toBe('3,5 m');
		expect(pieces([100, 25])).toBe('100 m + 25 m');
		expect(euro(9.9)).toMatch(/€\s9,90/);
		expect(count(1, 'kabel', 'kabels')).toBe('1 kabel');
		expect(count(3, 'kabel', 'kabels')).toBe('3 kabels');
		expect(formatRolls([100, 50, 50, 25])).toBe('1 × 100 m + 2 × 50 m + 1 × 25 m');
	});
});

describe('catalog', () => {
	const valid = {
		id: 'a',
		sku: 'A',
		name: 'A',
		crossSection: 'x',
		use: 'x',
		pricePerMeter: 1,
		sales: { type: 'perMeter', step: 1, minimum: 1 },
		stock: 'x',
		imageUrl: null,
		productUrl: 'https://www.elektramat.nl/',
		isSample: false
	};
	it('accepts the bundled catalog shape', () => {
		expect(parseCatalog([valid])).toHaveLength(1);
	});
	it('rejects empty fixed lengths, zero step and duplicate ids', () => {
		expect(() =>
			parseCatalog([{ ...valid, sales: { type: 'fixedLengths', lengthsM: [] } }])
		).toThrow();
		expect(() =>
			parseCatalog([{ ...valid, sales: { type: 'perMeter', step: 0, minimum: 1 } }])
		).toThrow();
		expect(() => parseCatalog([valid, valid])).toThrow();
	});
	it('keeps roll products and rejects a bad roll', () => {
		const withRolls = { ...valid, rolls: [roll(25, 64.51)] };
		expect(parseCatalog([withRolls])[0].rolls).toHaveLength(1);
		expect(() => parseCatalog([{ ...valid, rolls: [roll(0, 1)] }])).toThrow();
		expect(() => parseCatalog([{ ...valid, rolls: [roll(25, -1)] }])).toThrow();
	});
	it('has the Snelflex rolls of 25, 50 and 100 m in the bundled catalog', () => {
		const sf = cables.find((c) => c.id === '401169424');
		expect(sf?.rolls?.map((r) => [r.lengthM, r.sku])).toEqual([
			[100, '401169424'],
			[50, '401170092'],
			[25, '401241845']
		]);
	});
});
