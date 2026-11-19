# Kabelmeter PWA

The web version of the Kabelmeter, next to the iPhone app in `../Kabelmeter`. Pick a cable,
enter the route lengths, see the price and add the length to a cart. Installable as a PWA and
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

Not built: the real shop cart. "Bestel op elektramat.nl" opens the product page.
