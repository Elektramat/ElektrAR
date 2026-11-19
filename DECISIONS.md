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
