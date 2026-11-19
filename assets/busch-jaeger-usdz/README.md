# Busch-Jaeger schakelmateriaal: USDZ models for AR

38 models covering 9 design lines × their Elektramat colourways × (light switch, socket), plus surface-mount (opbouw) variants for Reflex SI and future linear.

## Conventions
- **Format:** USDZ (ARKit profile), works in RealityKit, SceneKit and AR Quick Look.
- **Scale:** real size, metres, Y-up.
- **Pivot:** centre of the back face. The back sits on the wall at z = 0 and **+Z points out of the wall**.
- **Quick Look:** each file carries `preliminary:anchoring` = vertical plane, so it snaps to walls.
- **Parts:** each file has `Frame`, `Rocker` or `CentrePlate`, plus `PinHoles` / `EarthClips` on sockets, and `Housing` on opbouw variants. Materials are `Frame` and `Insert`, so you can recolour at runtime.
- **Metadata:** `customData` on `/Root` holds line, colour, product type, frame size and depth from the wall. The same data is in `manifest.json`.

## RealityKit
```swift
let anchor = AnchorEntity(.plane(.vertical, classification: .wall, minimumBounds: [0.1, 0.1]))
let model = try await Entity(named: "busch-jaeger_future-linear_studiowit_schakelaar")
// Vertical plane anchors use +Y as the wall normal; the models use +Z.
model.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
model.position.y = 0.0005   // avoid z-fighting with the wall
anchor.addChild(model)
arView.scene.addAnchor(anchor)
```
Check the orientation once on a device. If a model shows up rotated in the wall plane, add a rotation about the anchor's Y axis.
NL mounting height for switches is typically ~1.05 m. That is up to the app (raycast hit + offset).

## Dimensions used (1-gang, mm)
| Line | Frame | Thickness | Rocker/plate | Switch / socket height |
|---|---|---|---|---|
| Busch-Duro 2000 SI | 81 | 11 | 54 | 18 / 14 |
| Reflex SI | 81 | 11 | 54 | 18 / 14 |
| Busch-art linear | 85 | 8.6 | 69.5 | 16.2 / 14.1 |
| future linear | 80 | 11 | 63 | 17 / 14 |
| Busch-balance SI | 81 | 12 | 55 | 18 / 14 |
| solo (shadow gap) | 87 | 11 | 63 | 17 / 14 |
| carat | 107 | 7 | 63 | 17 / 14 |
| Busch-axcent | 91 | 11 | 63 | 17 / 14 |
| alpha | 81* | 11* | 55* | 18 / 14* |

Sources: Busch-Jaeger tender texts and datasheets (future linear, Reflex SI, solo, carat, art linear) and retailer spec listings.
*alpha: no published figures found; these are estimates based on the alpha exclusive frame.
Corner and edge radii and the rocker curvature are eyeballed to match each line's look. Colours are approximations of the RAL references Busch-Jaeger quotes.

## Regenerate / add lines
```
pip install usd-core
python generate.py out        # writes out/usdz/*.usdz + out/manifest.json
python preview.py out         # contact sheet (needs matplotlib)
```
To add a line or colour, add an entry to `LINES` in `generate.py`. Other brands (Gira, Jung, Niko, …) use the same template; only the numbers change.
