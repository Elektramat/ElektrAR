// Dutch number formatting, same output as Kabelmeter/Core/Format.swift.
const nl = 'nl-NL';

export const meters = (v: number) =>
	`${v.toLocaleString(nl, { minimumFractionDigits: 1, maximumFractionDigits: 1 })} m`;

export const orderLength = (v: number) =>
	`${v.toLocaleString(nl, { minimumFractionDigits: 0, maximumFractionDigits: 1 })} m`;

export const pieces = (p: number[]) => p.map(orderLength).join(' + ');

export const euro = (v: number) => v.toLocaleString(nl, { style: 'currency', currency: 'EUR' });

/** "2 × 50 m + 1 × 25 m": rolls grouped by length, longest first. */
export const rolls = (p: number[]) => {
	const counts = new Map<number, number>();
	for (const length of p) counts.set(length, (counts.get(length) ?? 0) + 1);
	return [...counts]
		.sort((a, b) => b[0] - a[0])
		.map(([length, n]) => `${n} × ${orderLength(length)}`)
		.join(' + ');
};
