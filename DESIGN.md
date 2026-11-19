# Kabelmeter design rules

Hard rules for every screen of the iPhone app (and the web app where they apply). Agreed with
Jairo on 19 November 2026. `KabelmeterTests/DesignRulesTests.swift` fails the build when a view
breaks the checkable ones. All colours come from `Kabelmeter/Theme.swift`; views never name a
colour themselves.

## Colours: Elektramat tokens only

| Role | Token | Hex | Allowed as |
|---|---|---|---|
| Interactive: buttons, selection, links, icons | primary | `#196CAE` | Solid fill with white text, or icon/text on white |
| Main action, at most one per screen | success-110 | `#65B809` | Solid button with white text only |
| Cables and guide lines in AR | secondary | `#34BBDA` | Lines and dots only, never text |
| Warning, selection in AR | warning | `#F7A111` | Icon, line, small dot; never body text |
| Delete, error | alert | `#E53030` | Icon and text for delete or errors |
| Start point (groepenkast) in AR | success | `#70CC0A` | Marker only |
| Text | ink `#1A1A1A`, black-75 `#404040`; white on blue, green or a dark pill | | All other text |
| Surfaces | white cards, black-5 `#F2F2F2` page background, black-15 `#D9D9D9` hairlines | | |

Not allowed:
- Purple, pink, yellow, teal, cyan, or any other system colour, as text or fill.
- See-through variants of brand colours (`.bordered` buttons, `Theme.accent.opacity(…)`
  fills). A disabled control shows its own colours at 40 % opacity; that is the only exception.
- Grey system materials (`.regularMaterial`, `.thinMaterial`, …). Use a white card (`.surface`).
- Coloured text on the camera image. Text there is white on a dark pill
  (`Theme.pillBackground`); a role colour may only show as a dot or icon in front of it.

## Buttons

- Primary: solid blue, white text and icon (`.brandProminentButton()`).
- Main action: solid green, white text and icon (`.brandProminentButton(Theme.cta)`), at most one per screen.
- Secondary on the camera image: white card, blue icon, black label (`CardButtonStyle`).
- Every button in a row has the same height (44 pt in bars, 56 pt for the big actions).
- − and +: `BrandStepper`, never the grey system `Stepper`. The pressed button turns solid blue with a white icon.

## Camera screens (AR)

- At most one bar on top, one line of hint, one card at the bottom. No stacked pickers.
- At least 55 % of the screen height stays camera image.
- Modes and steps live in the bottom card (tabs, a menu), close to the thumb and the "+".
- Hints are one line; longer explanations go in the intro or the info card.
- Labels that follow the crosshair (height) sit above it, never below: the controls and the card are below.

## Typography

- System font. Headings heavy, labels semibold, body regular.
- No text below footnote size on the camera image.
