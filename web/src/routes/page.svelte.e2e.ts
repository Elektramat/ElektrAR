import { expect, test } from '@playwright/test';

// Runs at 390x844 (playwright.config.ts). The catalog's first cable is YMvK 3x1,5 at € 1,45/m.
test('calculates a route and adds it to the cart', async ({ page }) => {
	await page.goto('/');
	await expect(page.getByRole('heading', { name: 'Kabelmeter' })).toBeVisible();

	const cta = page.getByRole('button', { name: 'Vul eerst een lengte in' });
	await expect(cta).toBeDisabled();

	// 2,5 + 4 + 1 = 7,5 m → 7,5 × 1,15 + 2 = 10,625 → 11 m
	await page.getByLabel('Stuk 1', { exact: true }).fill('2,5');
	await page.getByRole('button', { name: '+ Stuk toevoegen' }).click();
	await page.getByLabel('Stuk 2', { exact: true }).fill('4');
	await page.getByRole('button', { name: '+ Stuk toevoegen' }).click();
	await page.getByLabel('Stuk 3', { exact: true }).fill('1');

	await expect(page.getByText('Gemeten: 7,5 m')).toBeVisible();
	await expect(page.getByText('Te bestellen: 11 m')).toBeVisible();

	await page.getByRole('button', { name: 'Voeg 11 m toe aan winkelmand' }).click();
	await expect(page.getByRole('status')).toContainText('11 m');

	await page.getByRole('button', { name: /Winkelmand, 1 artikelen/ }).click();
	await expect(page.getByRole('dialog')).toContainText('Totaal');
	await expect(page.getByRole('link', { name: 'Bestel op elektramat.nl' })).toHaveAttribute(
		'href',
		/^https:\/\/www\.elektramat\.nl\//
	);
});

test('marks invalid input and keeps the cart button off', async ({ page }) => {
	await page.goto('/');
	const input = page.getByLabel('Stuk 1', { exact: true });
	await input.fill('abc');
	await expect(input).toHaveAttribute('aria-invalid', 'true');
	await expect(page.getByRole('button', { name: 'Vul eerst een lengte in' })).toBeDisabled();
});

test('cart survives a reload', async ({ page }) => {
	await page.goto('/');
	await page.getByLabel('Stuk 1', { exact: true }).fill('8');
	await page.getByRole('button', { name: /toe aan winkelmand/ }).click();
	await page.reload();
	await expect(page.getByRole('button', { name: /Winkelmand, 1 artikelen/ })).toBeVisible();
});
