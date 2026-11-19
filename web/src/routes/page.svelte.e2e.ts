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

test('advises the cheapest rolls for a roll cable and lists each roll in the cart', async ({
	page
}) => {
	await page.goto('/');
	await newRoom(page, 'Garage');
	await page.getByRole('button', { name: /Wijzig kabel/ }).click();
	await page.getByLabel('Zoek kabel').fill('snelflex');
	const row = page.getByRole('button', { name: /Snelflex/ });
	await expect(row).toContainText('vanaf € 2,09 per meter · rollen van 25 m, 50 m, 100 m');
	await row.click();

	// 50 m → 50 × 1,15 + 2 = 59,5 m → 50 + 25 m (€ 182,17) is cheaper than 100 m (€ 208,77).
	await page.getByLabel('Stuk 1', { exact: true }).fill('50');
	await expect(page.getByText('Rollen: 1 × 50 m + 1 × 25 m')).toBeVisible();
	await expect(page.getByTestId('price')).toHaveText(/182,17/);

	await page.getByRole('button', { name: 'Kabel toevoegen' }).click();
	await expect(page.getByText(/rollen 1 × 50 m \+ 1 × 25 m/)).toBeVisible();
	await page.getByRole('button', { name: /^Winkelwagen, 2 artikelen/ }).click();
	const dialog = page.getByRole('dialog');
	await expect(dialog).toContainText('art.nr. 401170092');
	await expect(dialog).toContainText('art.nr. 401241845');
	await expect(
		page.getByRole('link', { name: 'Bekijk rol 50 m op elektramat.nl' })
	).toHaveAttribute('href', /per-rol-50-meter/);
	await expect(
		page.getByRole('link', { name: 'Bekijk rol 25 m op elektramat.nl' })
	).toHaveAttribute('href', /per-rol-25-meter/);
});

// DESIGN.md, following the iPhone app's BrandStepper (commit 2c09d1e): light grey − and +,
// solid blue with a white icon while pressed, 40 % opacity at the end of the range.
test('reserve stepper turns blue when pressed and fades at the end of the range', async ({
	page
}) => {
	await page.goto('/');
	await newRoom(page, 'Hal');
	await page.getByLabel('Stuk 1', { exact: true }).fill('8');
	const stepper = page.getByRole('group', { name: 'Reserve in procent' });
	const more = stepper.getByRole('button', { name: 'Meer reserve' });

	await expect(more).toHaveCSS('background-color', 'rgb(242, 242, 242)');
	await more.hover();
	await page.mouse.down();
	await expect(more).toHaveCSS('background-color', 'rgb(25, 108, 174)');
	await expect(more).toHaveCSS('color', 'rgb(255, 255, 255)');
	await page.mouse.up();

	// 15 % → 20 % (one click above) → 30 %.
	await more.click();
	await more.click();
	await expect(page.getByText('Reserve 30% + 2 m aansluiting')).toBeVisible();
	await expect(more).toBeDisabled();
	await expect(more).toHaveCSS('opacity', '0.4');
	await expect(stepper.getByRole('button', { name: 'Minder reserve' })).toHaveCSS('opacity', '1');
});

// Following the app's cart button (commit 3a45a5e): solid white with a blue cart, the total
// of all rooms and a green count badge.
test('cart button is solid white with the total and a count badge', async ({ page }) => {
	await page.goto('/');
	const cartButton = page.getByRole('button', { name: /^Winkelwagen, / });
	await expect(cartButton).toHaveAccessibleName('Winkelwagen, 0 artikelen, € 0,00');
	await expect(cartButton).toHaveCSS('background-color', 'rgb(255, 255, 255)');
	await expect(cartButton).toHaveCSS('color', 'rgb(25, 108, 174)');

	await newRoom(page, 'Hal');
	await addCable(page, '8');
	// 8 × 1,15 + 2 = 11,2 → 12 m × € 1,45
	await expect(cartButton).toHaveAccessibleName('Winkelwagen, 1 artikel, € 17,40');
	await expect(cartButton).toContainText('€ 17,40');
	await expect(cartButton.locator('.badge')).toHaveText('1');
	await expect(cartButton.locator('.badge')).toHaveCSS('background-color', 'rgb(101, 184, 9)');
});
