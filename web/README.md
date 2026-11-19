# Kabelmeter PWA

The web version of the Kabelmeter, next to the iPhone app in `../Kabelmeter`. Make rooms
("Mijn ruimtes"), add cables to a room by picking a cable and entering the route lengths, and see
one shared cart worked out from all rooms. Installable as a PWA and
usable offline.

Stack (the parts of the Pitstop stack this app needs): SvelteKit (Svelte 5) with TypeScript,
own components, zod for validation, Vitest, Playwright at 390x844, pnpm. Hosted on Vercel with
`@sveltejs/adapter-vercel`, functions in `fra1`; the page is prerendered, so today there are no
functions. Every branch gets a preview, `main` is production. Not used, because the app has no
backend: Supabase, auth, realtime, photo upload, pg_cron, Web Push, IndexedDB outbox, Bits UI
(the only overlay is a native `<dialog>`).

- No camera measuring: Safari on iPhone does not support WebXR AR. Measuring with the camera
  stays in the iPhone app.
- One source of truth: `scripts/sync-catalog.mjs` copies `Kabelmeter/Resources/cables.json` and
  the cable photos before every `dev` and `build`. The copies in `src/lib/cables.json` and
  `static/cables/` are only a fallback when the app folder is not there. The catalog is checked
  with zod at load (`src/lib/catalog.ts`).
- Same pricing as the app: `src/lib/pricing.ts` is a port of `PricingCalculator.swift`, and both
  run `../shared/pricing-cases.json`.
- Rooms and the shared cart follow the iPhone app (`Project`, `Bill`): rooms are saved in
  localStorage (`src/lib/rooms.ts`, store in `rooms.svelte.ts`); the cart is not stored but
  computed from the rooms (`src/lib/bill.ts`): per cable type the required length of every cable
  (reserve + 2 m connection per cable) is added up over all rooms and rounded once.
- Not in the browser: placing switches, sockets and lights (needs the camera), the automatic cable
  route and the first-run intro (it is about the camera and placing parts).
- Own service worker (`src/service-worker.ts`): caches the build per version.

```sh
pnpm install
pnpm dev            # http://localhost:5173
pnpm test:unit --run
pnpm test:e2e       # builds, previews and runs Playwright at 390x844
pnpm check
pnpm lint
pnpm build
```

Not built: the real shop cart. "Bekijk op elektramat.nl" opens the product page.
