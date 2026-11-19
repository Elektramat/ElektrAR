# Elektramat Kabelmeter: build brief for Claude

You are building this iOS app from start to finish during a one-day hackathon. Read this whole file before writing code. Work autonomously, make sensible decisions, and only stop to ask the human when you are genuinely blocked (see "When to ask the human").

The team is three people (two developers, one AI/data engineer). Hard deadline: feature freeze at 17:30, demo day ends 20:00. Time is the scarcest resource: prefer the simplest thing that works on a real device.

## 1. What we are building

**Elektramat Kabelmeter**: an iPhone AR measuring app, like Apple's Measure app, plus a shop layer.

1. The user **picks an Elektramat cable** (name, cross-section, price per meter, photo).
2. The user **measures** by pointing the camera and adding points (e.g. from the electrical cabinet along the wall to where a switch or light goes). The app draws the line and shows the total length.
3. **While measuring, the price updates live**: measured length, length including reserve, and price in euros.
4. When done, **"Voeg toe aan winkelmand"** adds the right cable length to the cart.

One-line pitch: *"Never order too little or too much cable: walk through the room once and the exact length is in your cart."*

### Non-goals (do not build unless all milestones are done)

Switch recognition, AI/vision calls, 3D overlay of new switches, accounts/login, real checkout or payment, Android, iPad layout, localization beyond Dutch, analytics.

## 2. Tech decisions (already made, do not revisit)

- **Language/UI:** Swift 5.9+, SwiftUI. Minimum iOS 17.
- **AR:** ARKit + RealityKit, using `ARView` wrapped in `UIViewRepresentable`. Do not use SceneKit or third-party AR packages.
- **No external dependencies.** No network calls except elektramat.nl: the product page in Safari, and the shop cart in an in-app web view (decided by Jairo on 19 Nov 2026, see `WebShopCart`).
- **UI language: Dutch** (all user-visible strings). **Code, comments, commit messages, docs: English.**
- **Numbers:** format with `Locale(identifier: "nl_NL")` (comma decimals, euro). Internally always meters as `Double`.
- **State:** `@Observable` / `ObservableObject`, whichever is simpler. No Core Data. Persist the cart with `UserDefaults` + `Codable`.

## 3. Project setup

ARKit cannot run in the Simulator, so the human tests on a physical iPhone (ideally a Pro model with LiDAR; the app must also work without LiDAR).

**Step 0 (human does this, ask them if it is not done yet):**
1. Create the project in Xcode: *iOS > App*, SwiftUI, name `Kabelmeter`, in this folder.
2. Set Signing to their "Personal Team" and pick a unique bundle id (a free account requires a unique one).
3. Run the empty app once on the phone to prove signing and install work.

**Then you:**
- Check `xcodebuild -version` and how the project is organized. If the project uses synchronized folders (Xcode 16+), new files in the folder are picked up automatically. If not, do not hand-edit `project.pbxproj`; ask the human to add the files in Xcode, or generate the project with XcodeGen (`project.yml`) if `xcodegen` is available.
- Add the camera usage description as a build setting (`INFOPLIST_KEY_NSCameraUsageDescription`): *"De camera wordt gebruikt om afstanden te meten."* Add `arkit` to required device capabilities only if it does not block simulator builds; otherwise skip it.
- `git init` if there is no repo, add a standard Xcode `.gitignore`, and commit after every milestone with a clear message.

## 4. Architecture

Keep it small and testable. Suggested files under `Kabelmeter/`:

```
KabelmeterApp.swift          App entry
Theme.swift                  All colors, fonts, spacing in ONE place (placeholder palette, easy to swap)
Models/Cable.swift           Cable + SalesUnit
Models/CartItem.swift
Services/CableStore.swift    Loads cables.json from the bundle
Services/PricingCalculator.swift   Pure functions, unit tested
Services/CartStore.swift     In-app cart, persisted
Services/CartService.swift   Protocol + LocalCartService (see section 7)
Measure/MeasureProvider.swift      Protocol (see below)
Measure/ARMeasureProvider.swift    Real ARKit implementation
Measure/SimulatedMeasureProvider.swift   Fake points for Simulator/demo
Measure/MeasureSession.swift       Points, segments, total length, undo/reset
Views/MeasureScreen.swift    Camera + crosshair + price bar + buttons
Views/ARViewContainer.swift  UIViewRepresentable around ARView
Views/CablePickerSheet.swift
Views/PriceBar.swift
Views/CartScreen.swift
Resources/cables.json        Cable data (see section 5)
Resources/CableImages/       One photo per cable, <sku>.jpg
KabelmeterTests/PricingCalculatorTests.swift
README.md, DECISIONS.md
```

### The MeasureProvider seam (important)

Define a `MeasureProvider` protocol (current crosshair world position, tracking state message, add/remove point hooks). `ARMeasureProvider` is the real one. `SimulatedMeasureProvider` produces fake points so the whole UI, pricing and cart can be developed and screenshotted in the Simulator without a device. Select the simulated one with `#if targetEnvironment(simulator)` and also via a hidden "Demo-modus" toggle on the device (long-press on the title) so a demo still works if tracking misbehaves on stage.

## 5. Data

- `cables.json` holds 10 to 15 cables. **The cables come from elektramat.nl product pages via `scripts/scrape_elektramat.py` (decided by Jairo on 19 Nov 2026).** Keep the 10 s delay between requests. Do not invent SKUs or prices; hand-made cables must set `"isSample": true`, which shows a small "Voorbeelddata" badge.
- Write a small script `scripts/csv_to_cables_json.py` that converts the real CSV export into `cables.json`, so replacing the data is a one-minute job. Document the expected columns in `README.md`.

Suggested model:

```json
{
  "id": "sample-001",
  "sku": "SAMPLE-001",
  "name": "Installatiekabel 3x1,5 mm²",
  "crossSection": "3x1,5 mm²",
  "use": "Verlichting",
  "pricePerMeter": 0.99,
  "sales": { "type": "perMeter", "step": 1, "minimum": 1 },
  "stock": "Op voorraad",
  "imageUrl": null,
  "productUrl": "https://www.elektramat.nl",
  "isSample": true
}
```

`sales` is either `perMeter` (with `step` and `minimum`, in meters) or `fixedLengths` (`lengthsM: [10, 25, 50, 100]`). The real way Elektramat sells cable is still an open question, so keep this flexible and isolated in `PricingCalculator`.

## 6. Pricing rules (live price)

```
required = measured * (1 + reserve) + connectionAllowance
```

- `reserve` default **15%**, adjustable in the UI (stepper or slider, 0 to 30%).
- `connectionAllowance` default **2.0 m** (1 m at each end), adjustable or at least a constant in one place.
- **Rounding up** to how the cable is sold:
  - `perMeter`: round up to the next multiple of `step`, at least `minimum`.
  - `fixedLengths`: use the cheapest combination that covers `required` (smallest single length that is large enough, otherwise as many of the largest as needed plus the smallest that covers the rest).
- `price = billedLength * pricePerMeter`. Show: "Gemeten: 7,4 m", "Te bestellen: 10 m", "€ 9,90".
- With nothing measured yet, show the cable's price per meter instead of zero.
- `PricingCalculator` must be pure and covered by unit tests (zero length, exactly on a step, just over a step, minimum order, each sales type, large values).

## 7. Cart

- `CartService` protocol with `add(cable:meters:)`. Ship `LocalCartService` (in-app cart via `CartStore`). The cart screen lists items, quantity in meters, line price and total, and has a **"Zet in winkelmand op elektramat.nl"** button that fills the real shop cart through an in-app web view (`WebShopCart`), plus a per-item link that opens the product page in Safari.
- Real cart integration (the webshop probably runs on Magento, which is unconfirmed) depends on an API we do not know yet. **Do not build a fake network client.** Leave a documented `RemoteCartService` stub with a TODO and the questions to ask: how is cable sold (per meter, per roll, cut to length), are decimal quantities allowed, is there a cart API, and how would a user's session be linked.
- Show this note on the cart screen: *"Dit is een schatting. Controleer de lengte zelf en laat het aansluiten over aan een installateur."*

## 8. Measuring: how it should behave

Mirror Apple's Measure app. Do **not** require tapping on the screen to place a point.

- Full-screen `ARView`. A **crosshair** in the center. A round **"+" button** adds a point at the crosshair; tap it again for the next point.
- Configure `ARWorldTrackingConfiguration` with `planeDetection = [.horizontal, .vertical]`, and `sceneReconstruction = .mesh` only if `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)`. Show `ARCoachingOverlayView` while tracking initializes.
- Each frame, raycast from the screen center: `arView.raycast(from:allowing:alignment:)`, try `.existingPlaneGeometry` first, fall back to `.estimatedPlane` with `.any` alignment. Throttle the work; do not do heavy work on every frame.
- Show a **live preview segment** from the last point to the crosshair. Total length = confirmed segments + the preview segment, so the price changes continuously while the user moves, not only when a point is added.
- Points are small spheres, segments thin boxes or cylinders. Keep entities simple. A segment length label may be a SwiftUI overlay projected from world space, or skipped if it costs too much time (the total in the price bar is what matters).
- Distance = `simd_distance` of world positions in meters. Add a light haptic when a point is added.
- Buttons: **Ongedaan maken** (remove last point), **Opnieuw** (reset), **Klaar** (freeze and show the summary).
- Tracking messages in Dutch: *"Beweeg de telefoon langzaam"*, *"Richt op een muur of vloer"*, *"Te weinig licht"*. If there is no raycast hit, disable the "+" button instead of adding a bad point.
- Disclose accuracy honestly in the summary: long distances can drift by a few percent, which is why the reserve exists.

## 9. UI sketch (one main screen)

- Top: selected cable chip (name, cross-section, price per meter). Tap opens `CablePickerSheet` (searchable list, photo placeholder, price, stock).
- Center: camera with crosshair.
- Bottom: **PriceBar** (always visible): measured length, length to order, price, reserve control, then the buttons row and the primary button **"Voeg toe aan winkelmand"**.
- Cart: small button with a badge at the top right, opens `CartScreen`.
- Big tap targets, high contrast (this is used standing in a room or on a ladder), Dark Mode supported. All colors via `Theme.swift`.
- No logos, no copied brand assets. If the team supplies design tokens later, only `Theme.swift` should need to change.

## 10. Milestones and acceptance criteria

Work in this order. After each milestone: build, run tests, commit, then tell the human in 2 or 3 lines what to test on the device.

| # | Milestone | Done when |
|---|---|---|
| M0 | Project builds, empty app runs on the phone | Human confirms (Step 0). |
| M1 | Models, `cables.json` (sample), `CableStore`, `PricingCalculator` + unit tests | `xcodebuild test` passes. |
| M2 | Measure screen with `SimulatedMeasureProvider`, PriceBar and picker working in the Simulator | Changing cable or reserve updates price live; screenshot checked. |
| M3 | `ARMeasureProvider` on a real device: crosshair, add/undo/reset, live preview segment, total | Human measures a known length (e.g. a 1 m ruler) and the app is within a few cm. |
| M4 | Live price tied to real measuring + cart (in-app) + cart screen | Measure, pick cable, add to cart, see total, open product URL. |
| M5 | Polish: tracking messages, empty/error states, haptics, Demo-modus, app icon placeholder, README | A full demo run works twice in a row without a crash. |

Time boxes (guideline): M1 + M2 done within about 90 minutes of starting, **M3 working on a device by the go/no-go point at 15:30**. If M3 is not working by then, tell the human clearly and propose the fallback (manual meter input with the same price bar and cart, no AR) so the demo is not lost.

**Stretch, only after M5, in this order:** (1) "Langs de muur" length mode: sum |dx|+|dy|+|dz| per segment instead of the straight line, with a toggle; (2) a cable suggestion from two questions (verlichting of stopcontact, binnen of buiten) using the catalog; (3) accessories (buis, inbouwdozen) added next to the cable.

## 11. Verification you must do yourself

- Build for the Simulator: `xcodebuild -scheme Kabelmeter -destination 'generic/platform=iOS Simulator' build`. Find a simulator with `xcrun simctl list devices available` and run tests with `xcodebuild test -destination 'platform=iOS Simulator,name=<device>'`.
- Take Simulator screenshots with `xcrun simctl io booted screenshot <file>` and look at them for layout problems (long Dutch strings, price bar overlap, small screens).
- You cannot test ARKit yourself. Never claim the AR measuring works until the human confirms on a device. Write AR code defensively (no force unwraps, handle missing raycast hits, handle tracking loss) and say clearly what remains untested.
- Run the full path (pick cable, measure with simulated points, add to cart, open cart) before declaring a milestone done.

## 12. Rules of engagement

- Prefer the simplest implementation. No premature abstraction beyond the two protocols above.
- No secrets, API keys, or personal data in the repo. No analytics or tracking.
- Keep a short `DECISIONS.md` (what you chose and why, one line each) and a `README.md` (how to build, run on a device, replace the cable data, known limits).
- The app only computes a material quantity and never gives installation instructions. Connecting anything in the electrical cabinet is for a qualified installer. Keep the disclaimer from section 7 visible.
- Do not touch signing settings or the bundle id after the human has set them.
- Do not leave dead code or TODOs without a reason; TODOs that point to a known open question (cart API, real sales units) are fine and expected.

## 13. When to ask the human

Ask (one short, concrete question, then keep working on something else if possible) only for:

1. Step 0: creating the Xcode project, signing, first run on the phone.
2. Testing AR on the device and reporting what happened.
3. The real cable export from the product database, and the answers about how cable is sold and whether a cart API exists.
4. A decision that changes scope or the deadline.

Everything else: decide, note it in `DECISIONS.md`, and continue.

## 14. Final deliverables (by feature freeze)

1. App running on the phone with: cable pick, AR measuring, live price, add to cart.
2. `cables.json` with real data if the export arrived, otherwise sample data clearly marked.
3. Unit tests for pricing passing.
4. `README.md` and `DECISIONS.md`.
5. A 2-minute demo script in `DEMO.md`: pick cable, walk from the cabinet to the target point measuring, show the live price, add to cart, show the cart. Include a fallback path using Demo-modus.
