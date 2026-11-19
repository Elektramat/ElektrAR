# Decisions

One line each: what we chose and why.

- New project `Kabelmeter` in this repo instead of the earlier "installatieplanner" prototype: the brief and plan describe the Kabelmeter. The old prototype stays in `~/Documents/Untitled Project`.
- Kept the signing team and bundle id that were set for the first device run, so the installed profile keeps working.
- Deployment target iOS 26.0 instead of the Xcode 27 default: the test iPhone runs iOS 26.4.
- Pure logic in `Kabelmeter/Core`, also exposed as a Swift package: no iOS simulator runtime is installed, so `swift test` on the Mac runs the unit tests.
- `fixedLengths` uses an exact search for the cheapest roll combination (fewest rolls on a tie): the "largest rolls + smallest for the rest" rule ordered up to 45 m too much (1152 m → 1200 m instead of 1155 m).
- Floating point tolerance of 1e-6 m before rounding up, so 10.000000001 m is billed as 10 m.
- Adding the same cable twice merges into one cart line with the meters added up.
- Raycast from the screen center 15 times per second, `.existingPlaneGeometry` first, then `.estimatedPlane`; the "+" button is disabled without a hit.
- "Te weinig licht" when ARKit's ambient intensity is below 150 lumen.
- Segments are thin boxes scaled along their length; no per-segment labels (the total in the price bar is what matters).
- Demo-modus is stored in `@AppStorage`, so it survives an app restart during the demo.
- Cursor is averaged over the last 5 hits (a jump over 10 cm is followed at once) and held for 0.5 s when ARKit loses the surface: less jitter, "+" stays usable.
- Raycast falls back to detected vertical planes extended infinitely, so a wall ARKit saw only partly still gives a hit. Risk: past a corner the extended plane can give a wrong hit.
- Segments within 8° of vertical or level snap to it ("Verticaal" / "Waterpas"). Without a surface hit, aiming within 2.5° of the vertical line through the last point measures along that line, like Apple's Measure app.
- LiDAR (Pro models) is used automatically through scene reconstruction and estimated-plane raycasts; no separate code path.
- Cable data from the elektramat.nl product pages (schema.org data) at Jairo's request, instead of sample data: the database export had not arrived. Waits 10 s between requests, per robots.txt.
- Only "per meter" products (whole meters, minimum 1, as the shop's quantity field allows). Rolls and reels are separate products with their own price, so `fixedLengths` is not used yet.
- Price per meter including VAT: the app shows a consumer price.
- Photos ship in the bundle as `<sku>.jpg` (JPEG, 300 px, 164 KB in total) instead of loading from the site: the demo must work without Wi-Fi.
- "Langs de muur" is the default route mode: each segment counts horizontal distance + height difference, and is drawn as a vertical then a horizontal leg. A straight 45° line undercounts a wall route by ~30%, more than the reserve. "Rechte lijn" stays available.
- The cart only takes the confirmed points (at least 2). The live price still includes the preview to the crosshair.
- A segment snapped to vertical takes its height from where the camera ray passes the vertical line, not from the hit depth (which is often wrong on plain walls without LiDAR).
- LiDAR devices read the smoothed LiDAR depth at the crosshair first (3x3 center pixels, high confidence only), then raycast the estimated surface; no infinite-plane fallback. Devices without LiDAR keep plane → estimated → infinite wall.
- Camera denied shows a card with "Open Instellingen" and "Gebruik demo-modus" instead of a black screen.
