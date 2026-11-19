# Elektramat Kabelmeter

iPhone AR measuring app with a shop layer: pick a cable, measure the route with the camera,
see the length and price update live, and add the right length to the cart.
Built for the Elektramat hackathon of 19 November 2026. See `CLAUDE.md` for the full brief.

## Build and run on a device

1. Open `Kabelmeter.xcodeproj` in Xcode (Xcode 27).
2. Signing uses the Personal Team that is set in the project. A free account needs a unique
   bundle id; the app expires after 7 days and must be installed again.
3. Pick your iPhone as the run destination and press Run.
4. First run on the phone: Settings > General > VPN & Device Management > trust the developer.

ARKit does not run in the Simulator. In the Simulator, and in Demo-modus on a device,
the app uses simulated points. Long-press the "Kabelmeter" title to switch Demo-modus on or off.

## Tests

The pure logic (pricing, cart, measuring session, catalog) lives in `Kabelmeter/Core` and is
also a Swift package, so it is tested on the Mac without a simulator:

```sh
swift test
```

## Replace the cable data

`Kabelmeter/Resources/cables.json` holds sample data (`"isSample": true`, shown with a
"Voorbeelddata" badge). To use the real export:

```sh
python3 scripts/csv_to_cables_json.py export.csv > Kabelmeter/Resources/cables.json
swift test   # checks that the file decodes
```

Expected CSV columns: `sku, name, cross_section, use, price_per_meter, sales_type, step_m,
minimum_m, lengths_m, stock, image_url, product_url`. `sales_type` is `perMeter` (uses
`step_m`, `minimum_m`) or `fixedLengths` (uses `lengths_m`, separated by `;`). Decimals may use
a comma or a dot. Note: the catalog test currently expects every cable to be sample data;
update `testBundledSampleDataDecodes` when the real export arrives.

## Pricing

`required = measured * (1 + reserve) + 2 m`, reserve 15% by default (0 to 30% in the app).
Rounded up to how the cable is sold: whole steps with a minimum, or the cheapest combination
of fixed roll lengths. See `Kabelmeter/Core/PricingCalculator.swift`.

## Known limits

- Sample cable data and prices until the real export arrives.
- The cart lives in the app. "Bestel op elektramat.nl" opens the product page; there is no
  webshop cart integration yet (see `RemoteCartService` for the open questions).
- Long distances can drift by a few percent; the reserve covers that.
- The app only estimates a material quantity. It gives no installation instructions.
