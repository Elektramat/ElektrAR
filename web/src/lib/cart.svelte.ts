import { z } from 'zod';
import { browser } from '$app/env';
import { roundToCents, type Cable } from './pricing';

const KEY = 'kabelmeter.cart.v1';

const itemSchema = z.object({
	cableId: z.string(),
	sku: z.string(),
	name: z.string(),
	crossSection: z.string(),
	pricePerMeter: z.number().min(0),
	meters: z.number().positive(),
	productUrl: z.string(),
	isSample: z.boolean()
});

export type CartItem = z.infer<typeof itemSchema>;

export const linePrice = (item: CartItem) => roundToCents(item.meters * item.pricePerMeter);

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

/** Adds meters; the same cable twice becomes one line, like the iPhone app. */
export function addTo(items: CartItem[], cable: Cable, meters: number): CartItem[] {
	if (!Number.isFinite(meters) || meters <= 0) return items;
	if (items.some((i) => i.cableId === cable.id)) {
		return items.map((i) => (i.cableId === cable.id ? { ...i, meters: i.meters + meters } : i));
	}
	return [
		...items,
		{
			cableId: cable.id,
			sku: cable.sku,
			name: cable.name,
			crossSection: cable.crossSection,
			pricePerMeter: cable.pricePerMeter,
			meters,
			productUrl: cable.productUrl,
			isSample: cable.isSample
		}
	];
}

/** In-app cart in localStorage. */
class Cart {
	items = $state<CartItem[]>([]);
	total = $derived(roundToCents(this.items.reduce((sum, i) => sum + linePrice(i), 0)));

	load() {
		if (browser) this.items = parseCart(localStorage.getItem(KEY));
	}

	add(cable: Cable, meters: number) {
		this.save(addTo(this.items, cable, meters));
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
