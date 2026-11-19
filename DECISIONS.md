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
- Switch placement is a second mode on the same screen ("Kabel meten" / "Schakelaars plaatsen") and reuses the crosshair and "+" button, so the Measure-app flow stays the same.
- Switch and socket data comes from `assets/sku_mapping.csv` + `sku_parts.csv` via `scripts/fixtures_to_json.py` into one `fixtures.json`; the app does not parse CSV.
- The 8 carat rows name models that do not exist (frame material + insert colour, e.g. `witglas-studiowit`); they use the model with the same insert colour (`carat_studiowit`). The frame material is not shown in 3D.
- Fixtures that are not completely orderable (5 of 40) can still be placed, marked "Niet compleet te bestellen" and left out of the total.
- Each placement is an `ARAnchor` named `fixture:<id>`: ARKit keeps it fixed in the room. The orientation is computed from the wall normal (+Z out of the wall, +Y up), so switches always hang upright.
- Placements survive an app restart through an `ARWorldMap` in Documents, saved at most every 3 s while mapped, and when the app goes to the background or the AR view closes. On launch ARKit must recognise the room before they show; "Nieuwe ruimte" drops the saved room.
- Demo-modus and AR have separate placement lists: their coordinates do not mix, and switching Demo-modus must not wipe the saved room.
- Fixtures are not added to the cart yet: the cart is meter-based.
- No Elektramat MCP cart: without a login `cable_create_order` returns only the generic cart URL (no cart id or session), so Safari would show an empty cart. Details in `RemoteCartService`.
