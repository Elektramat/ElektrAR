import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { billedPieces, quote, type SalesUnit } from './pricing';
import { count, euro, meters, orderLength, pieces } from './format';
import { parseCatalog } from './catalog';

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

describe('format', () => {
	it('uses Dutch numbers', () => {
		expect(meters(7.4)).toBe('7,4 m');
		expect(orderLength(10)).toBe('10 m');
		expect(orderLength(3.5)).toBe('3,5 m');
		expect(pieces([100, 25])).toBe('100 m + 25 m');
		expect(euro(9.9)).toMatch(/€\s9,90/);
		expect(count(1, 'kabel', 'kabels')).toBe('1 kabel');
		expect(count(3, 'kabel', 'kabels')).toBe('3 kabels');
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
});
