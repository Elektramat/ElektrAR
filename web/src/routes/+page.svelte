<script lang="ts">
	import { onMount } from 'svelte';
	import { cables } from '#lib/catalog.ts';
	import { cart, linePrice, rollLines } from '#lib/cart.svelte.ts';
	import { euro, meters, orderLength, pieces, rolls } from '#lib/format.ts';
	import {
		CONNECTION_ALLOWANCE,
		DEFAULT_RESERVE,
		hasRolls,
		quote,
		type Cable
	} from '#lib/pricing.ts';

	const DISCLAIMER =
		'Dit is een schatting. Controleer de lengte zelf en laat het aansluiten over aan een installateur.';
	const CABLE_KEY = 'kabelmeter.cable';

	type Segment = { id: number; text: string };

	/** "2,5" and "2.5" both work; empty or invalid gives null. */
	function parseMeters(text: string): number | null {
		const trimmed = text.trim().replace(',', '.');
		if (trimmed === '') return null;
		const value = Number(trimmed);
		return Number.isFinite(value) && value >= 0 && value <= 10_000 ? value : null;
	}

	let cableId = $state(cables[0].id);
	let segments = $state<Segment[]>([{ id: 1, text: '' }]);
	let reservePercent = $state(Math.round(DEFAULT_RESERVE * 100));
	let query = $state('');
	let pickerOpen = $state(false);
	let toast = $state<string | null>(null);
	let isIOS = $state(false);
	let cartDialog: HTMLDialogElement | undefined = $state();
	let nextId = 2;

	onMount(() => {
		cart.load();
		isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent);
		const saved = localStorage.getItem(CABLE_KEY);
		if (saved && cables.some((c) => c.id === saved)) cableId = saved;
	});

	const cable = $derived(cables.find((c) => c.id === cableId) ?? cables[0]);
	const measured = $derived(segments.reduce((sum, s) => sum + (parseMeters(s.text) ?? 0), 0));
	const result = $derived(quote(cable, measured, reservePercent / 100));
	const isRoll = $derived(hasRolls(cable));
	/** "1 × 50 m + 1 × 25 m" for a cable sold as rolls, "11 m" otherwise. */
	const toOrder = $derived(result ? (isRoll ? rolls(result.pieces) : pieces(result.pieces)) : '–');
	const hasSample = cables.some((c) => c.isSample);
	const filtered = $derived.by(() => {
		const q = query.trim().toLowerCase();
		if (!q) return cables;
		return cables.filter((c) =>
			[c.name, c.crossSection, c.use].some((v) => v.toLowerCase().includes(q))
		);
	});

	/** "€ 1,45 per meter"; a roll cable shows its cheapest price per meter as "vanaf". */
	const perMeter = (c: Cable) => `${hasRolls(c) ? 'vanaf ' : ''}${euro(c.pricePerMeter)} per meter`;

	const rollSizes = (c: Cable) =>
		[...(c.rolls ?? [])]
			.sort((a, b) => a.lengthM - b.lengthM)
			.map((r) => orderLength(r.lengthM))
			.join(', ');

	function chooseCable(id: string) {
		cableId = id;
		localStorage.setItem(CABLE_KEY, id);
		pickerOpen = false;
		query = '';
	}

	function addSegment() {
		segments.push({ id: nextId++, text: '' });
	}

	function removeSegment(id: number) {
		segments =
			segments.length === 1
				? [{ id: segments[0].id, text: '' }]
				: segments.filter((s) => s.id !== id);
	}

	function show(message: string) {
		toast = message;
		setTimeout(() => {
			if (toast === message) toast = null;
		}, 2200);
	}

	function addToCart() {
		if (!result) return;
		cart.add(cable, result.billedLength, result.required);
		show(`${isRoll ? toOrder : orderLength(result.billedLength)} ${cable.name} toegevoegd`);
	}
</script>

<div class="app">
	<header class="header">
		<div>
			<p class="brand-small">Elektramat</p>
			<h1 class="brand">Kabelmeter</h1>
			<p class="tagline">
				Nooit te weinig of te veel kabel. Vul je route in en de juiste lengte staat in je
				winkelmand.
			</p>
		</div>
		<!-- A solid white circle with a blue cart and a green count badge (DESIGN.md: no
		     see-through fills). The total is in the label; the price bar shows the route price. -->
		<button
			class="icon-button cart-button"
			aria-label={`Winkelmand, ${cart.items.length} artikelen, ${euro(cart.total)}`}
			onclick={() => cartDialog?.showModal()}
		>
			<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
				<path
					d="M2.5 3.5h2.6l2.6 11"
					fill="none"
					stroke="currentColor"
					stroke-width="2.2"
					stroke-linecap="round"
					stroke-linejoin="round"
				/>
				<path d="M6.4 6.5h14.6l-2.3 8.5H8.2z" fill="currentColor" />
				<circle cx="9.5" cy="19" r="1.7" fill="currentColor" />
				<circle cx="17" cy="19" r="1.7" fill="currentColor" />
			</svg>
			{#if cart.items.length > 0}<span class="badge">{cart.items.length}</span>{/if}
		</button>
	</header>

	<main>
		<section class="card" aria-labelledby="kabel">
			<h2 id="kabel"><span class="step">1</span>Kies je kabel</h2>
			{#if !pickerOpen}
				<button
					class="cable-row"
					onclick={() => (pickerOpen = true)}
					aria-label={`Gekozen: ${cable.name}. Wijzig kabel`}
				>
					<img class="cable-photo" src={`/cables/${cable.sku}.jpg`} alt="" width="56" height="56" />
					<div>
						<p class="cable-name">{cable.name}</p>
						<p class="cable-meta">
							{cable.crossSection} · {perMeter(cable)} · {cable.stock}
						</p>
						{#if cable.isSample}<span class="sample">Voorbeelddata</span>{/if}
					</div>
					<span class="change">Wijzig</span>
				</button>
			{:else}
				<!-- svelte-ignore a11y_autofocus -->
				<input
					class="search"
					type="search"
					placeholder="Zoek kabel"
					aria-label="Zoek kabel"
					bind:value={query}
					autofocus
				/>
				{#if filtered.length === 0}
					<p class="muted">Geen kabel gevonden voor “{query}”.</p>
				{/if}
				{#each filtered as c (c.id)}
					<button
						class="cable-row"
						onclick={() => chooseCable(c.id)}
						aria-pressed={c.id === cableId}
					>
						<img class="cable-photo" src={`/cables/${c.sku}.jpg`} alt="" width="56" height="56" />
						<div>
							<p class="cable-name">{c.name}</p>
							<p class="cable-meta">
								{c.crossSection} · {perMeter(c)}{hasRolls(c) ? ` · rollen van ${rollSizes(c)}` : ''}
							</p>
						</div>
						{#if c.id === cableId}<span class="selected">✓</span>{/if}
					</button>
				{/each}
			{/if}
		</section>

		<section class="card" aria-labelledby="route">
			<h2 id="route"><span class="step">2</span>Vul de lengte van je route in</h2>
			<p class="muted" style="margin-bottom: 12px">
				Meet langs de muur: omhoog, opzij en omlaag apart. Per stuk in meters.
			</p>
			{#each segments as s, index (s.id)}
				{@const invalid = s.text.trim() !== '' && parseMeters(s.text) === null}
				<div class="segment">
					<label for={`seg-${s.id}`}>Stuk {index + 1}</label>
					<input
						id={`seg-${s.id}`}
						inputmode="decimal"
						placeholder="0,0"
						autocomplete="off"
						aria-invalid={invalid}
						bind:value={s.text}
					/>
					<button
						class="ghost"
						aria-label={`Verwijder stuk ${index + 1}`}
						onclick={() => removeSegment(s.id)}
					>
						✕
					</button>
				</div>
			{/each}
			<button class="link-button" onclick={addSegment}>+ Stuk toevoegen</button>
			<div class="note">
				{#if isIOS}
					Meten met de camera kan in de Kabelmeter-app voor iPhone. Safari op de iPhone ondersteunt
					geen AR-meting in de browser.
				{:else}
					Meten met de camera kan in de Kabelmeter-app voor iPhone. In de browser vul je de lengte
					zelf in.
				{/if}
			</div>
		</section>

		<section class="card" aria-labelledby="bestel">
			<h2 id="bestel"><span class="step">3</span>Bestel de juiste lengte</h2>
			<p class="muted">
				We rekenen {reservePercent}% reserve en {orderLength(CONNECTION_ALLOWANCE)} voor de aansluitingen,
				afgerond zoals de kabel verkocht wordt. {DISCLAIMER}
			</p>
			{#if isRoll}
				<p class="note" style="margin-top: 12px">
					Deze kabel wordt verkocht per rol van {rollSizes(cable)}, elke rol met een eigen prijs.
					Het advies is de combinatie rollen met de laagste totaalprijs voor deze kabel apart. In de
					winkelmand kiest de app de rollen voor al je routes met deze kabel samen, dat is vaak
					voordeliger.
				</p>
			{/if}
			{#if hasSample}
				<p class="muted">
					<span class="sample">Voorbeelddata</span> Sommige prijzen zijn voorbeelden.
				</p>
			{/if}
		</section>
	</main>

	<div class="price-bar" role="region" aria-label="Prijs">
		<div class="price-inner">
			<div class="price-top">
				<div class="lengths" aria-live="polite">
					<p>Gemeten: {meters(measured)}</p>
					<p>{isRoll ? 'Rollen' : 'Te bestellen'}: {toOrder}</p>
				</div>
				<div class="price" aria-live="polite" data-testid="price">
					{#if result}
						{euro(result.price)}
					{:else}
						{#if isRoll}<small>vanaf</small>{/if}{euro(cable.pricePerMeter)}<small>per meter</small>
					{/if}
				</div>
			</div>
			<div class="reserve">
				<span>Reserve {reservePercent}% + {orderLength(CONNECTION_ALLOWANCE)} aansluiting</span>
				<!-- Brand stepper (DESIGN.md): the pressed button turns solid blue with a white icon. -->
				<div class="stepper" role="group" aria-label="Reserve in procent">
					<button
						aria-label="Minder reserve"
						disabled={reservePercent <= 0}
						onclick={() => (reservePercent = Math.max(0, reservePercent - 5))}
					>
						−
					</button>
					<button
						aria-label="Meer reserve"
						disabled={reservePercent >= 30}
						onclick={() => (reservePercent = Math.min(30, reservePercent + 5))}
					>
						+
					</button>
				</div>
			</div>
			<button class="cta" disabled={!result} onclick={addToCart}>
				{result ? `Voeg ${toOrder} toe aan winkelmand` : 'Vul eerst een lengte in'}
			</button>
		</div>
	</div>

	<dialog
		bind:this={cartDialog}
		aria-labelledby="cart-title"
		onclick={(e) => e.target === cartDialog && cartDialog?.close()}
	>
		<div class="sheet">
			<div class="sheet-head">
				<h2 id="cart-title">Winkelmand</h2>
				<button class="link-button" onclick={() => cartDialog?.close()}>Klaar</button>
			</div>
			{#if cart.items.length === 0}
				<p class="muted">Je winkelmand is leeg. Vul een route in en voeg de kabel toe.</p>
			{/if}
			{#each cart.items as item (item.cableId)}
				<div class="line">
					<div class="line-top"><span>{item.name}</span><span>{euro(linePrice(item))}</span></div>
					{#if item.rolls}
						<!-- One line per roll size: each roll is its own shop product. -->
						{#each rollLines(item) as { roll, count } (roll.sku)}
							<div class="roll-line">
								<div class="line-top">
									<span>{count} × rol {orderLength(roll.lengthM)}</span>
									<span>{euro(count * roll.price)}</span>
								</div>
								<p class="cable-meta">
									{item.crossSection} · {euro(roll.price)} per rol · art.nr. {roll.sku}
								</p>
								<a
									class="secondary-cta"
									href={roll.productUrl}
									target="_blank"
									rel="external noopener noreferrer"
								>
									Bestel rol {orderLength(roll.lengthM)} op elektramat.nl
								</a>
							</div>
						{/each}
						<p class="cable-meta">
							Rollen gekozen op de laagste totaalprijs voor de lengte van al je routes samen.
						</p>
					{:else}
						<p class="cable-meta">
							{item.crossSection} · {orderLength(item.meters)} × {euro(item.pricePerMeter)} per meter
						</p>
						<a
							class="secondary-cta"
							href={item.productUrl}
							target="_blank"
							rel="external noopener noreferrer"
						>
							Bestel op elektramat.nl
						</a>
					{/if}
					<button class="link-button" onclick={() => cart.remove(item.cableId)}>Verwijder</button>
				</div>
			{/each}
			{#if cart.items.length > 0}
				<div class="total"><span>Totaal</span><span>{euro(cart.total)}</span></div>
				<button class="link-button" onclick={() => cart.clear()}>Winkelmand leegmaken</button>
			{/if}
			<p class="muted">{DISCLAIMER}</p>
		</div>
	</dialog>

	{#if toast}<div class="toast" role="status">{toast}</div>{/if}
</div>
