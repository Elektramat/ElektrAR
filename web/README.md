# Kabelmeter PWA

The web version of the Kabelmeter, next to the iPhone app in `../Kabelmeter`. Pick a cable,
enter the route lengths, see the price and add the length to a cart. Installable as a PWA.

- Next.js (App Router), statically rendered. Deploys on Vercel with Root Directory `web`.
- No camera measuring: Safari on iPhone does not support WebXR AR. Measuring with the camera
  stays in the iPhone app.
- One source of truth: `scripts/sync-catalog.mjs` copies `Kabelmeter/Resources/cables.json`
  and the cable photos before every `dev` and `build`. The copies in `lib/` and `public/cables/`
  are only a fallback when the app folder is not there.
- Same pricing as the app: `lib/pricing.ts` is a port of `PricingCalculator.swift`, and both
  run `../shared/pricing-cases.json`.

```sh
npm install
npm run dev     # http://localhost:3000
npm test        # pricing and formatting
npm run lint
npm run build
```

Not built: the real shop cart. "Bestel op elektramat.nl" opens the product page.
