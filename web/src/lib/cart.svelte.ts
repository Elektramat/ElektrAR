import { z } from 'zod';
import { browser } from '$app/env';
import { groupRolls, rollPlan, roundToCents, type Cable, type CableRoll } from './pricing';

const KEY = 'kabelmeter.cart.v1';

const itemSchema = z.object({
	cableId: z.string(),
	sku: z.string(),
	name: z.string(),
	crossSection: z.string(),
	pricePerMeter: z.number().min(0),
	meters: z.number().positive(),
	productUrl: z.string(),
	isSample: z.boolean(),
	/** Roll cables only: the roll products, and the length needed by all routes added together. */
	rolls: z
		.array(
			z.object({
				lengthM: z.number().positive(),
				sku: z.string(),
				price: z.number().min(0),
				productUrl: z.string(),
				shopProductId: z.number().int().nullable().optional(),
				stock: z.string().nullable().optional()
			})
		)
		.min(1)
		.optional(),
	required: z.number().positive().optional()
});

export type CartItem = z.infer<typeof itemSchema>;

/** The cheapest rolls for everything added of a roll cable, rounded once; empty for other cables. */
export const itemRolls = (item: CartItem): CableRoll[] =>
	item.rolls ? rollPlan(item.required ?? item.meters, item.rolls) : [];

/** One line per roll size, each with its own article number, price and product page. */
export const rollLines = (item: CartItem) => groupRolls(itemRolls(item));

export const linePrice = (item: CartItem) =>
	item.rolls
		? roundToCents(itemRolls(item).reduce((sum, r) => sum + r.price, 0))
		: roundToCents(item.meters * item.pricePerMeter);

/** Reads stored cart JSON; anything invalid is dropped instead of breaking the app. */
export function parseCart(raw: string | null): CartItem[] {
	if (!raw) return [];
	try {
		const result = z.array(z.unknown()).safeParse(JSON.parse(raw));
		if (!result.success) return [];
		return result.data.flatMap((entry) => {
			const item = itemSchema.safeParse(entry);
			return item.success ? [item.data] : [];
		});
	} catch {
		return [];
	}
}

/**
 * Adds meters; the same cable twice becomes one line, like the iPhone app. For a cable sold as
 * roll products the required lengths are added up and the rolls are chosen once for the total
 * (`required`, the length before rounding to rolls; defaults to `meters`).
 */
export function addTo(
	items: CartItem[],
	cable: Cable,
	meters: number,
	required = meters
): CartItem[] {
	if (!Number.isFinite(meters) || meters <= 0) return items;
	const rolls = cable.rolls && cable.rolls.length > 0 ? cable.rolls : undefined;
	if (rolls && (!Number.isFinite(required) || required <= 0)) return items;
	const withRolls = (item: CartItem, total: number): CartItem => {
		const next = { ...item, rolls, required: total };
		return { ...next, meters: itemRolls(next).reduce((sum, r) => sum + r.lengthM, 0) };
	};
	if (items.some((i) => i.cableId === cable.id)) {
		return items.map((i) => {
			if (i.cableId !== cable.id) return i;
			return rolls
				? withRolls(i, (i.required ?? i.meters) + required)
				: { ...i, meters: i.meters + meters };
		});
	}
	const item: CartItem = {
		cableId: cable.id,
		sku: cable.sku,
		name: cable.name,
		crossSection: cable.crossSection,
		pricePerMeter: cable.pricePerMeter,
		meters,
		productUrl: cable.productUrl,
		isSample: cable.isSample
	};
	return [...items, rolls ? withRolls(item, required) : item];
}

/** In-app cart in localStorage. */
class Cart {
	items = $state<CartItem[]>([]);
	total = $derived(roundToCents(this.items.reduce((sum, i) => sum + linePrice(i), 0)));

	load() {
		if (browser) this.items = parseCart(localStorage.getItem(KEY));
	}

	add(cable: Cable, meters: number, required = meters) {
		this.save(addTo(this.items, cable, meters, required));
	}

	remove(cableId: string) {
		this.save(this.items.filter((i) => i.cableId !== cableId));
	}

	clear() {
		this.save([]);
	}

	private save(next: CartItem[]) {
		this.items = next;
		if (browser) localStorage.setItem(KEY, JSON.stringify(next));
	}
}

export const cart = new Cart();
