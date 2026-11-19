import { expect, test, type Page } from '@playwright/test';

// Runs at 390x844 (playwright.config.ts). The catalog's first cable is YMvK 3x1,5 at € 1,45/m.

async function newRoom(page: Page, name: string) {
	await page.getByRole('button', { name: '+ Nieuwe ruimte' }).click();
	const create = page.getByRole('button', { name: 'Maak', exact: true });
	await expect(create).toBeDisabled();
	await page.getByRole('button', { name, exact: true }).click();
	await create.click();
	await expect(page.getByRole('heading', { name, exact: true })).toBeVisible();
}

async function addCable(page: Page, ...lengths: string[]) {
	for (const [i, length] of lengths.entries()) {
		if (i > 0) await page.getByRole('button', { name: '+ Stuk toevoegen' }).click();
		await page.getByLabel(`Stuk ${i + 1}`, { exact: true }).fill(length);
	}
	await page.getByRole('button', { name: 'Kabel toevoegen' }).click();
}

test('rooms add up into one shared cart', async ({ page }) => {
	await page.goto('/');
	await expect(page.getByRole('heading', { name: 'Kabelmeter' })).toBeVisible();
	await expect(page.getByText('Nog geen ruimtes')).toBeVisible();

	await newRoom(page, 'Woonkamer');
	await expect(page.getByRole('button', { name: 'Vul eerst een lengte in' })).toBeDisabled();

	// 2,5 + 4 + 1 = 7,5 m → 7,5 × 1,15 + 2 = 10,625 → 11 m
	await page.getByLabel('Stuk 1', { exact: true }).fill('2,5');
	await page.getByRole('button', { name: '+ Stuk toevoegen' }).click();
	await page.getByLabel('Stuk 2', { exact: true }).fill('4');
	await page.getByRole('button', { name: '+ Stuk toevoegen' }).click();
	await page.getByLabel('Stuk 3', { exact: true }).fill('1');
	await expect(page.getByText('Deze kabel: 7,5 m')).toBeVisible();
	await expect(page.getByText('Te bestellen: 11 m')).toBeVisible();

	await page.getByRole('button', { name: 'Kabel toevoegen' }).click();
	await expect(page.getByRole('status')).toContainText('Kabel van 7,5 m toegevoegd');
	await expect(page.getByText('Deze kabel: 0,0 m')).toBeVisible();
	await expect(page.getByText(/Kabel 1: /)).toBeVisible();

	await page.getByRole('button', { name: 'Terug naar ruimtes' }).click();
	await newRoom(page, 'Keuken');
	await addCable(page, '2');

	await page.getByRole('button', { name: /^Winkelwagen, / }).click();
	const cart = page.getByRole('dialog');
	await expect(cart).toContainText('Uit 2 ruimtes');
	// Rounded once: (7,5 × 1,15 + 2) + (2 × 1,15 + 2) = 14,925 → 15 m, not 11 + 5 = 16 m.
	await expect(cart).toContainText('15 m ×');
	await expect(cart).toContainText('Keuken, Woonkamer');
	await expect(cart.getByRole('link', { name: 'Bekijk op elektramat.nl' })).toHaveAttribute(
		'href',
		/^https:\/\/www\.elektramat\.nl\//
	);
});

test('marks invalid input and keeps the add button off', async ({ page }) => {
	await page.goto('/');
	await newRoom(page, 'Hal');
	const input = page.getByLabel('Stuk 1', { exact: true });
	await input.fill('abc');
	await expect(input).toHaveAttribute('aria-invalid', 'true');
	await expect(page.getByRole('button', { name: 'Vul eerst een lengte in' })).toBeDisabled();
});

test('rooms survive a reload and deleting one empties the cart', async ({ page }) => {
	await page.goto('/');
	await newRoom(page, 'Zolder');
	await addCable(page, '8');
	await page.reload();

	await expect(page.getByRole('button', { name: 'Open Zolder' })).toContainText('8,0 m kabel');
	page.once('dialog', (dialog) => dialog.accept());
	await page.getByRole('button', { name: 'Verwijder Zolder' }).click();
	await expect(page.getByText('Nog geen ruimtes')).toBeVisible();

	await page.getByRole('button', { name: /^Winkelwagen, / }).click();
	await expect(page.getByRole('dialog')).toContainText('Je winkelwagen is leeg');
});
