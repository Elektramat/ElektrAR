// Port of Bill in Kabelmeter/Core/Bill.swift (cables only: the browser cannot place switches
// and sockets). The shared cart is not kept separately: it is worked out from the rooms, so it
// always matches what is designed and nothing can be added twice.
import { orderLength } from './format';
import { billedPieces, requiredLength, rollPlan, roundToCents, type Cable } from './pricing';
import { runLength, type Room } from './rooms';

export type BillLine = {
	/** Cable id; for a roll line the roll's article number. */
	productId: string;
	sku: string;
	name: string;
	/** Cross-section, e.g. "3x1,5 mm²". */
	detail: string;
	/** Price per meter incl. VAT. */
	unitPrice: number;
	/** Meters to order, rounded to how the cable is sold. */
	quantity: number;
	/** Rolls or cut lengths, e.g. [25, 10]. */
	pieces: number[];
	productUrl: string;
	isSample: boolean;
	/** Set for a cable the shop sells as roll products: the length of one roll (m). Then
	 * `pieces` holds one entry per roll and the line is one roll product. */
	rollLength?: number;
	/** Names of the rooms this line comes from. */
	rooms: string[];
};

/** Number of rolls (roll lines only). */
export const rollCount = (line: BillLine) =>
	line.rollLength === undefined ? 0 : line.pieces.length;

export const linePrice = (line: BillLine) => roundToCents(line.quantity * line.unitPrice);

/**
 * Per cable type the measured length of every cable plus reserve and connection allowance
 * (per cable), added up over all rooms and then rounded once to how the cable is sold. A cable
 * sold as roll products gets the cheapest rolls for that total, one line per roll size, each
 * with its own article number, price and product page.
 */
export function billLines(rooms: Room[], cables: Cable[], reserve: number): BillLine[] {
	const byId = new Map(cables.map((c) => [c.id, c]));
	const lines = new Map<string, BillLine>();
	const required = new Map<string, number>();

	for (const room of rooms) {
		for (const run of room.runs) {
			const cable = byId.get(run.cableId);
			const length = runLength(run);
			if (!cable || !(length > 0)) continue;
			required.set(cable.id, (required.get(cable.id) ?? 0) + requiredLength(length, reserve));
			const line = lines.get(cable.id);
			if (line) {
				if (!line.rooms.includes(room.name)) line.rooms.push(room.name);
			} else {
				lines.set(cable.id, {
					productId: cable.id,
					sku: cable.sku,
					name: cable.name,
					detail: cable.crossSection,
					unitPrice: cable.pricePerMeter,
					quantity: 0,
					pieces: [],
					productUrl: cable.productUrl,
					isSample: cable.isSample,
					rooms: [room.name]
				});
			}
		}
	}

	const result: BillLine[] = [];
	for (const [cableId, length] of required) {
		const line = lines.get(cableId);
		const cable = byId.get(cableId);
		if (!line || !cable) continue;
		if (cable.rolls && cable.rolls.length > 0) {
			const plan = rollPlan(length, cable.rolls);
			for (const roll of [...cable.rolls].sort((a, b) => b.lengthM - a.lengthM)) {
				const count = plan.filter((r) => r.sku === roll.sku).length;
				if (count === 0) continue;
				result.push({
					...line,
					productId: roll.sku,
					sku: roll.sku,
					detail: `${cable.crossSection} · rol ${orderLength(roll.lengthM)}`,
					unitPrice: roll.price / roll.lengthM,
					quantity: count * roll.lengthM,
					pieces: new Array<number>(count).fill(roll.lengthM),
					productUrl: roll.productUrl,
					rollLength: roll.lengthM,
					rooms: [...line.rooms]
				});
			}
		} else {
			line.pieces = billedPieces(length, cable.sales);
			line.quantity = line.pieces.reduce((a, b) => a + b, 0);
			result.push(line);
		}
	}
	return result;
}

export const billTotal = (lines: BillLine[]) =>
	roundToCents(lines.reduce((sum, line) => sum + linePrice(line), 0));
