<script lang="ts">
	import { onMount } from 'svelte';
	import { cables } from '#lib/catalog.ts';
	import { billLines, billTotal, linePrice, rollCount } from '#lib/bill.ts';
	import { count, euro, meters, orderLength, pieces, rolls } from '#lib/format.ts';
	import {
		CONNECTION_ALLOWANCE,
		DEFAULT_RESERVE,
		hasRolls,
		quote,
		type Cable
	} from '#lib/pricing.ts';
	import {
		ROOM_SUGGESTIONS,
		createRoom,
		createRun,
		roomCableLength,
		runLength,
		type Room
	} from '#lib/rooms.ts';
	import { rooms } from '#lib/rooms.svelte.ts';

	const DISCLAIMER =
		'Dit is een schatting. Controleer de lengte zelf en laat het aansluiten over aan een installateur.';
	const CABLE_KEY = 'kabelmeter.cable';
	const RESERVE_KEY = 'kabelmeter.reservePercent';

	type Segment = { id: number; text: string };

	/** "2,5" and "2.5" both work; empty or invalid gives null. */
	function parseMeters(text: string): number | null {
		const trimmed = text.trim().replace(',', '.');
		if (trimmed === '') return null;
		const value = Number(trimmed);
		return Number.isFinite(value) && value >= 0 && value <= 10_000 ? value : null;
	}

	let roomId = $state<string | null>(null);
	let creating = $state(false);
	let newName = $state('');
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
		rooms.load();
		isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent);
		const saved = localStorage.getItem(CABLE_KEY);
		if (saved && cables.some((c) => c.id === saved)) cableId = saved;
		const reserve = Number(localStorage.getItem(RESERVE_KEY));
		if (localStorage.getItem(RESERVE_KEY) !== null && reserve >= 0 && reserve <= 30) {
			reservePercent = Math.round(reserve);
		}
	});

	const reserve = $derived(reservePercent / 100);
	const room = $derived(rooms.get(roomId));
	const cable = $derived(cables.find((c) => c.id === cableId) ?? cables[0]);
	const invalidSegment = $derived(
		segments.some((s) => s.text.trim() !== '' && parseMeters(s.text) === null)
	);
	const measured = $derived(segments.reduce((sum, s) => sum + (parseMeters(s.text) ?? 0), 0));
	const result = $derived(invalidSegment ? null : quote(cable, measured, reserve));
	const isRoll = $derived(hasRolls(cable));
	/** "1 × 50 m + 1 × 25 m" for a cable sold as rolls, "11 m" otherwise. */
	const toOrder = $derived(result ? (isRoll ? rolls(result.pieces) : pieces(result.pieces)) : '–');
	const lines = $derived(billLines(rooms.list, cables, reserve));
	const total = $derived(billTotal(lines));
	const roomsInCart = $derived(rooms.list.filter((r) => r.runs.length > 0).length);
	const hasSample = cables.some((c) => c.isSample);
	const filtered = $derived.by(() => {
		const q = query.trim().toLowerCase();
		if (!q) return cables;
		return cables.filter((c) =>
			[c.name, c.crossSection, c.use].some((v) => v.toLowerCase().includes(q))
		);
	});

	const roomTotal = (r: Room) => billTotal(billLines([r], cables, reserve));
	const summary = (r: Room) =>
		r.runs.length === 0 ? 'Leeg' : `${meters(roomCableLength(r))} kabel`;
	const cableOf = (id: string) => cables.find((c) => c.id === id);

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

	function setReserve(percent: number) {
		reservePercent = Math.min(30, Math.max(0, percent));
		localStorage.setItem(RESERVE_KEY, String(reservePercent));
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

	function resetRoute() {
		segments = [{ id: nextId++, text: '' }];
	}

	function show(message: string) {
		toast = message;
		setTimeout(() => {
			if (toast === message) toast = null;
		}, 2200);
	}

	function openRoom(id: string) {
		roomId = id;
		pickerOpen = false;
		resetRoute();
		window.scrollTo(0, 0);
	}

	function closeRoom() {
		roomId = null;
		window.scrollTo(0, 0);
	}

	function startNewRoom() {
		creating = true;
		newName = '';
	}

	function makeRoom(event: SubmitEvent) {
		event.preventDefault();
		const created = createRoom(newName);
		if (!created) return;
		rooms.add(created);
		creating = false;
		openRoom(created.id);
	}

	function deleteRoom(r: Room) {
		const ok = confirm(
			`Ruimte verwijderen?\n\nAlles in ${r.name} verdwijnt, ook uit de winkelwagen.`
		);
		if (ok) rooms.remove(r.id);
	}

	function finishCable() {
		if (!room || !result) return;
		const run = createRun(
			cable.id,
			segments.map((s) => parseMeters(s.text) ?? 0)
		);
		if (!run) return;
		rooms.addRun(room.id, run);
		resetRoute();
		show(`✓ Kabel van ${meters(runLength(run))} toegevoegd`);
	}

	function deleteRun(runId: string) {
		if (!room) return;
		rooms.removeRun(room.id, runId);
		show('Verwijderd');
	}
</script>

{#snippet reserveControl()}
	<div class="reserve">
		<span>
			Reserve {reservePercent}% + {orderLength(CONNECTION_ALLOWANCE)} aansluiting per kabel
		</span>
		<!-- Brand stepper (DESIGN.md): the pressed button turns solid blue with a white icon. -->
		<div class="stepper" role="group" aria-label="Reserve in procent">
			<button
				aria-label="Minder reserve"
				disabled={reservePercent <= 0}
				onclick={() => setReserve(reservePercent - 5)}
			>
				−
			</button>
			<button
				aria-label="Meer reserve"
				disabled={reservePercent >= 30}
				onclick={() => setReserve(reservePercent + 5)}
			>
				+
			</button>
		</div>
	</div>
{/snippet}

<div class="app">
	<header class="header">
		<div>
			<p class="brand-small">Elektramat</p>
			<h1 class="brand">Kabelmeter</h1>
			<p class="tagline">
				Nooit te weinig of te veel kabel. Vul per ruimte je routes in en alles staat samen in je
				winkelwagen.
			</p>
		</div>
		<!-- A solid white pill with a blue cart, the total of all rooms and a green count badge
		     (DESIGN.md: no see-through fills); like CartButton in the app. -->
		<button
			class="icon-button cart-button"
			aria-label={`Winkelwagen, ${count(lines.length, 'artikel', 'artikelen')}, ${euro(total)}`}
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
			<span class="cart-total">{euro(total)}</span>
			{#if lines.length > 0}<span class="badge">{lines.length}</span>{/if}
		</button>
	</header>

	<main>
		{#if !room}
			<section class="card" aria-labelledby="ruimtes">
				<h2 id="ruimtes">Mijn ruimtes</h2>
				{#if rooms.list.length === 0 && !creating}
					<p class="cable-name">Nog geen ruimtes</p>
					<p class="muted">
						Maak een ruimte, zoals de woonkamer of keuken. Daarin vul je de routes van je kabels in.
					</p>
				{/if}
				{#each rooms.list as r (r.id)}
					<div class="room-row">
						<button class="cable-row" onclick={() => openRoom(r.id)} aria-label={`Open ${r.name}`}>
							<div>
								<p class="cable-name">{r.name}</p>
								<p class="cable-meta">{summary(r)}</p>
							</div>
							<span class="room-price">{euro(roomTotal(r))}</span>
						</button>
						<button class="ghost" aria-label={`Verwijder ${r.name}`} onclick={() => deleteRoom(r)}>
							✕
						</button>
					</div>
				{/each}
			</section>

			{#if creating}
				<section class="card" aria-labelledby="nieuw">
					<h2 id="nieuw">Nieuwe ruimte</h2>
					<form class="new-room" onsubmit={makeRoom}>
						<!-- svelte-ignore a11y_autofocus -->
						<input
							class="search"
							aria-label="Naam van de ruimte"
							placeholder="Naam, bijv. Woonkamer"
							maxlength="60"
							autocomplete="off"
							bind:value={newName}
							autofocus
						/>
						<div class="chips">
							{#each ROOM_SUGGESTIONS as suggestion (suggestion)}
								<button
									type="button"
									class="chip"
									aria-pressed={newName === suggestion}
									onclick={() => (newName = suggestion)}
								>
									{suggestion}
								</button>
							{/each}
						</div>
						<p class="muted">In een ruimte vul je per kabel de route in, stuk voor stuk.</p>
						<div class="form-actions">
							<button type="button" class="link-button" onclick={() => (creating = false)}>
								Annuleer
							</button>
							<button type="submit" class="cta small" disabled={newName.trim() === ''}>
								Maak
							</button>
						</div>
					</form>
				</section>
			{/if}

			<section class="card" aria-labelledby="uitleg">
				<h2 id="uitleg">Zo werkt het</h2>
				<p class="muted">
					Maak een ruimte, kies per kabel het type en vul de route in. De winkelwagen telt alle
					ruimtes bij elkaar op. {DISCLAIMER}
				</p>
			</section>
		{:else}
			<div class="room-head">
				<button class="link-button" onclick={closeRoom} aria-label="Terug naar ruimtes">
					‹ Mijn ruimtes
				</button>
				<h2 class="room-title">{room.name}</h2>
			</div>

			<section class="card" aria-labelledby="kabel">
				<h2 id="kabel"><span class="step">1</span>Kies je kabel</h2>
				{#if !pickerOpen}
					<button
						class="cable-row"
						onclick={() => (pickerOpen = true)}
						aria-label={`Gekozen: ${cable.name}. Wijzig kabel`}
					>
						<img
							class="cable-photo"
							src={`/cables/${cable.sku}.jpg`}
							alt=""
							width="56"
							height="56"
						/>
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
									{c.crossSection} · {perMeter(c)}{hasRolls(c)
										? ` · rollen van ${rollSizes(c)}`
										: ''}
								</p>
							</div>
							{#if c.id === cableId}<span class="selected">✓</span>{/if}
						</button>
					{/each}
				{/if}
			</section>

			<section class="card" aria-labelledby="route">
				<h2 id="route"><span class="step">2</span>Vul de route van deze kabel in</h2>
				<p class="muted" style="margin-bottom: 12px">
					Rechte hoeken, zoals een kabel langs de muur loopt: omhoog of omlaag, opzij en weer omlaag
					apart. Per stuk in meters.
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
						Meten met de camera kan in de Kabelmeter-app voor iPhone. Safari op de iPhone
						ondersteunt geen AR-meting in de browser.
					{:else}
						Meten met de camera kan in de Kabelmeter-app voor iPhone. In de browser vul je de lengte
						zelf in.
					{/if}
				</div>
				{#if isRoll}
					<p class="note" style="margin-top: 12px">
						Deze kabel wordt verkocht per rol van {rollSizes(cable)}, elke rol met een eigen prijs.
						Het advies is de combinatie rollen met de laagste totaalprijs voor deze kabel apart. In
						de winkelwagen kiest de app de rollen voor al je kabels van dit type in alle ruimtes
						samen, dat is vaak voordeliger.
					</p>
				{/if}
			</section>

			<section class="card" aria-labelledby="kabels">
				<h2 id="kabels"><span class="step">3</span>Kabels in deze ruimte</h2>
				{#if room.runs.length === 0}
					<p class="muted">Nog leeg. Vul een route in en tik op Kabel toevoegen.</p>
				{/if}
				{#each room.runs as run, index (run.id)}
					{@const c = cableOf(run.cableId)}
					{@const q = c ? quote(c, runLength(run), reserve) : null}
					<div class="line">
						<div class="line-top">
							<span>Kabel {index + 1}: {c?.name ?? 'Kabel'}</span>
							<span>{q ? euro(q.price) : '–'}</span>
						</div>
						<p class="cable-meta">
							{meters(runLength(run))}
							· {count(run.segments.length, 'stuk', 'stukken')}
							{#if q}
								· {c && hasRolls(c)
									? `rollen ${rolls(q.pieces)}`
									: `te bestellen ${pieces(q.pieces)}`}
							{/if}
						</p>
						<button
							class="link-button"
							aria-label={`Verwijder kabel ${index + 1}`}
							onclick={() => deleteRun(run.id)}
						>
							Verwijder
						</button>
					</div>
				{/each}
				{#if room.runs.length > 0}
					<div class="total">
						<span>
							{count(room.runs.length, 'kabel', 'kabels')} · {meters(roomCableLength(room))}
						</span>
						<span>{euro(roomTotal(room))}</span>
					</div>
					<p class="muted">
						Prijs per kabel apart. In de winkelwagen worden alle kabels van hetzelfde type samen
						afgerond, dat is vaak iets voordeliger.
					</p>
				{/if}
				{#if hasSample}
					<p class="muted">
						<span class="sample">Voorbeelddata</span> Sommige prijzen zijn voorbeelden.
					</p>
				{/if}
			</section>
		{/if}
	</main>

	<div class="price-bar" role="region" aria-label={room ? 'Prijs' : 'Ruimtes'}>
		<div class="price-inner">
			{#if room}
				<div class="price-top">
					<div class="lengths" aria-live="polite">
						<p>Deze kabel: {meters(measured)}</p>
						<p>{isRoll ? 'Rollen' : 'Te bestellen'}: {toOrder}</p>
					</div>
					<div class="price" aria-live="polite" data-testid="price">
						{#if result}
							{euro(result.price)}
						{:else}
							{#if isRoll}<small>vanaf</small>{/if}{euro(cable.pricePerMeter)}<small>
								per meter
							</small>
						{/if}
					</div>
				</div>
				{@render reserveControl()}
				<button class="cta" disabled={!result} onclick={finishCable}>
					{result ? 'Kabel toevoegen' : 'Vul eerst een lengte in'}
				</button>
			{:else}
				<button class="cta" onclick={startNewRoom}>+ Nieuwe ruimte</button>
			{/if}
		</div>
	</div>

	<dialog
		bind:this={cartDialog}
		aria-labelledby="cart-title"
		onclick={(e) => e.target === cartDialog && cartDialog?.close()}
	>
		<div class="sheet">
			<div class="sheet-head">
				<h2 id="cart-title">Winkelwagen</h2>
				<button class="link-button" onclick={() => cartDialog?.close()}>Klaar</button>
			</div>
			{#if lines.length === 0}
				<p class="cable-name">Je winkelwagen is leeg</p>
				<p class="muted">Alle kabels die je in je ruimtes invult, komen hier vanzelf bij elkaar.</p>
			{:else}
				<div class="total">
					<span>
						Totaal
						<small class="cable-meta">Uit {count(roomsInCart, 'ruimte', 'ruimtes')}</small>
					</span>
					<span>{euro(total)}</span>
				</div>
				<h3 class="sheet-section">Kabel</h3>
				{#each lines as line (line.productId)}
					<div class="line">
						<div class="line-top"><span>{line.name}</span><span>{euro(linePrice(line))}</span></div>
						{#if line.rollLength !== undefined}
							<!-- One line per roll size: each roll is its own shop product. -->
							<p class="cable-meta">
								{line.detail} · {rollCount(line)} × {euro(line.unitPrice * line.rollLength)} per rol ·
								art.nr. {line.sku}
							</p>
						{:else}
							<p class="cable-meta">
								{line.detail} · {pieces(line.pieces)} × {euro(line.unitPrice)} per meter
							</p>
						{/if}
						<p class="cable-meta">{line.rooms.join(', ')}</p>
						{#if line.isSample}<span class="sample">Voorbeelddata</span>{/if}
						<a
							class="secondary-cta"
							href={line.productUrl}
							target="_blank"
							rel="external noopener noreferrer"
						>
							{line.rollLength !== undefined
								? `Bekijk rol ${orderLength(line.rollLength)} op elektramat.nl`
								: 'Bekijk op elektramat.nl'}
						</a>
					</div>
				{/each}
				{#if lines.some((l) => l.rollLength !== undefined)}
					<p class="cable-meta">
						Rollen gekozen op de laagste totaalprijs voor de lengte van al je kabels samen.
					</p>
				{/if}
				{@render reserveControl()}
			{/if}
			<p class="muted">{DISCLAIMER}</p>
		</div>
	</dialog>

	{#if toast}<div class="toast" role="status">{toast}</div>{/if}
</div>
