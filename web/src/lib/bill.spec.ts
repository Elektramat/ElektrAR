import { describe, expect, it } from 'vitest';
import { billLines, billTotal, linePrice } from './bill';
import type { Cable, SalesUnit } from './pricing';
import { createRoom, createRun, parseRooms, roomCableLength, sortRooms, type Room } from './rooms';

const perMeter: SalesUnit = { type: 'perMeter', step: 1, minimum: 1 };

function cable(id: string, price: number, sales: SalesUnit = perMeter): Cable {
	return {
		id,
		sku: `sku-${id}`,
		name: `Kabel ${id}`,
		crossSection: '3x1,5 mm²',
		use: 'x',
		pricePerMeter: price,
		sales,
		stock: 'x',
		imageUrl: null,
		productUrl: 'https://www.elektramat.nl/x',
		isSample: false
	};
}

function room(name: string, runs: [string, number[]][] = []): Room {
	return {
		id: name,
		name,
		createdAt: '2026-11-19T10:00:00.000Z',
		updatedAt: '2026-11-19T10:00:00.000Z',
		runs: runs.map(([cableId, segments], i) => ({ id: `${name}-${i}`, cableId, segments }))
	};
}

// Same cases as KabelmeterTests/BillTests.swift (cable part).
describe('shared cart (Bill)', () => {
	it('adds up cables of one type, then rounds once', () => {
		// Two cables of 2,3 m with no reserve: (2,3 + 2) * 2 = 8,6 m -> 9 m, not 5 + 5 = 10 m.
		const lines = billLines(
			[room('A', [['c', [2.3]]]), room('B', [['c', [1.3, 1]]])],
			[cable('c', 1.5)],
			0
		);
		expect(lines).toHaveLength(1);
		expect(lines[0].quantity).toBeCloseTo(9, 9);
		expect(linePrice(lines[0])).toBe(13.5);
		expect(lines[0].rooms).toEqual(['A', 'B']);
	});

	it('chooses rolls for the total', () => {
		const lines = billLines(
			[room('A', [['r', [8]]])],
			[cable('r', 1, { type: 'fixedLengths', lengthsM: [10, 25] })],
			0.15
		);
		expect(lines[0].pieces).toEqual([25]); // 8 * 1,15 + 2 = 11,2 m
	});

	it('keeps one line per cable type, in order of first use, and names each room once', () => {
		const lines = billLines(
			[
				room('Keuken', [
					['b', [3]],
					['a', [4]],
					['b', [1]]
				]),
				room('Hal', [['a', [2]]])
			],
			[cable('a', 1), cable('b', 2)],
			0.15
		);
		expect(lines.map((l) => l.productId)).toEqual(['b', 'a']);
		expect(lines[0].rooms).toEqual(['Keuken']);
		expect(lines[1].rooms).toEqual(['Keuken', 'Hal']);
		// b: (3 * 1,15 + 2) + (1 * 1,15 + 2) = 8,6 -> 9 m; a: (4 * 1,15 + 2) + (2 * 1,15 + 2) = 10,9 -> 11 m
		expect(lines.map((l) => l.quantity)).toEqual([9, 11]);
		expect(billTotal(lines)).toBe(9 * 2 + 11 * 1);
	});

	it('skips unknown cables and empty rooms', () => {
		expect(billLines([room('Leeg')], [cable('c', 1)], 0.15)).toEqual([]);
		expect(billLines([room('A', [['weg', [5]]])], [cable('c', 1)], 0.15)).toEqual([]);
		expect(billTotal([])).toBe(0);
	});
});

describe('rooms', () => {
	it('needs a name and trims it', () => {
		expect(createRoom('   ')).toBeNull();
		expect(createRoom('  Keuken ')?.name).toBe('Keuken');
	});

	it('makes a cable only from a real length', () => {
		expect(createRun('c', [0, 0])).toBeNull();
		expect(createRun('c', [])).toBeNull();
		expect(createRun('c', [1, Number.NaN])).toBeNull();
		expect(createRun('c', [-1, 2])).toBeNull();
		expect(createRun('c', [2.5, 0, 4])?.segments).toEqual([2.5, 4]);
	});

	it('adds up the cable length of a room', () => {
		expect(
			roomCableLength(
				room('A', [
					['c', [2.5, 4]],
					['c', [1]]
				])
			)
		).toBe(7.5);
	});

	it('lists the newest room first', () => {
		const old = room('Oud');
		const recent = { ...room('Nieuw'), updatedAt: '2026-11-19T12:00:00.000Z' };
		expect(sortRooms([old, recent]).map((r) => r.name)).toEqual(['Nieuw', 'Oud']);
	});

	it('drops broken stored data instead of crashing', () => {
		expect(parseRooms(null)).toEqual([]);
		expect(parseRooms('not json')).toEqual([]);
		expect(parseRooms('{"a":1}')).toEqual([]);
		const good = room('A', [['c', [2]]]);
		const stored = JSON.stringify([good, { id: 'x' }, { ...good, id: 'b', name: ' ' }]);
		expect(parseRooms(stored)).toEqual([good]);
	});
});
