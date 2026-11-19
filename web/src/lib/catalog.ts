import { z } from 'zod';
import raw from './cables.json';
import type { Cable } from './pricing';

// Validate the catalog at the boundary, with the same rules as CableCatalog.decode in
// the iPhone app: valid sales units, no negative prices, unique ids.
const salesSchema = z.discriminatedUnion('type', [
	z.object({
		type: z.literal('perMeter'),
		step: z.number().positive(),
		minimum: z.number().min(0)
	}),
	z.object({ type: z.literal('fixedLengths'), lengthsM: z.array(z.number().positive()).min(1) })
]);

export const cableSchema = z.object({
	id: z.string().min(1),
	sku: z.string().min(1),
	name: z.string().min(1),
	crossSection: z.string(),
	use: z.string(),
	pricePerMeter: z.number().min(0),
	sales: salesSchema,
	stock: z.string(),
	imageUrl: z.string().nullable(),
	productUrl: z.string().url(),
	isSample: z.boolean(),
	shopProductId: z.number().int().nullable().optional()
});

export const catalogSchema = z
	.array(cableSchema)
	.min(1)
	.refine((list) => new Set(list.map((c) => c.id)).size === list.length, 'Duplicate cable id');

export function parseCatalog(data: unknown): Cable[] {
	return catalogSchema.parse(data);
}

export const cables: Cable[] = parseCatalog(raw);
