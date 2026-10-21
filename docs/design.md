# Design — Oracle DESIGN.md → Cairn theme mapping

Source of truth: `DESIGN.md` at the repo root (installed by
`npx getdesign@latest add oracle`, verified 2026-10-21). This file records how
its tokens map onto Cairn's Flutter theme layer (`apps/cairn_app/lib/ui/`) and
every deliberate adaptation. When this document and DESIGN.md disagree,
DESIGN.md wins for the light theme values.

## Colour tokens (from DESIGN.md)

| DESIGN.md token | Value | Cairn role |
|---|---|---|
| primary | #312d2a | Every primary action fill (charcoal, never coloured CTAs) |
| primary-pressed | #47423e | Pressed state of primary actions |
| on-primary | #ffffff | Labels on filled/inverted surfaces |
| brand-mark | #c74634 | **Wordmark only.** Never a button, link, border or highlight |
| ink | #161513 | Primary text |
| ink-deep | #211e1c | Dark bands / inverted surfaces |
| canvas | #ffffff | Base surface (rung 1) |
| canvas-soft | #fbf9f8 | Section surface (rung 2), disabled-button fill |
| canvas-tint | #f5f4f2 | Supporting surface (rung 3), table headers |
| canvas-warm | #f1efed | Hero/stat surface (rung 4) |
| hairline | #e4e1dd | Borders that separate same-rung surfaces |
| divider | #e9e7e4 | Column rules |
| field-border | #d4cfca | Text input borders |
| link | #006b8f | Inline links (the only coloured text affordance) |
| accent-gold | #f0cc71 | The single ornament: 40×4 rule under hero headline |
| accent-gold-soft | #f7e0a1 | Selected-tab marker on dark subnav (5px) |
| band-teal | #d6e5e5 | Full-band colour moments only |
| band-forest | #33553c | Full-band colour moments only |
| focus | #227e9e | Focus rings |
| error | #d63b25 | Error text/borders (functional, not brand red) |
| disabled-ink | #aea8a2 | Disabled labels |

## Shape, spacing, type

- Radii: none 0 · xs 4 (buttons) · sm 6 (inputs) · md 8 (cards/modals/toasts) ·
  lg 12 (nav tiles) · xl 15 (content cards) · full 9999.
- Spacing ladder: 10 / 12 / 16 / 18 / 20 / 24 / 32 / 48 (section).
- No shadows anywhere; depth is tonal (ladder rungs) + hairlines.
- Type scale (family mapping below): display 300-weight large sans for hero
  registers; headings jump straight to weight 800; body 16/400 (loose 350);
  label 14/500; label-strong 14/600; caption 12/400.
- Buttons: padding 10×16, radius xs, label typography. Primary = charcoal
  fill; secondary = ink outline; tertiary = text only.
- Inputs: canvas fill, field-border, radius sm, padding 12×18.
- Cards/modals/toasts: canvas, hairline border, radius md–xl, no elevation.
- Tables: header row on canvas-tint with caption typography, hairline rows.

## Cairn adaptations (declared, per spec §6)

1. **Fonts.** DESIGN.md names Oracle Sans (proprietary, not redistributable)
   and Georgia. Cairn ships **Arad** for Persian and **Inter** for Latin
   (both OFL) — same weights/sizes/line-heights as the tokens. The Georgia
   serif display register is a web-product-page feature; in-app surfaces use
   the sans ladder only.
2. **Touch targets.** Oracle's web button height (~36px) is below Android's
   48dp guidance; Cairn keeps the visual padding/radius but enforces a 48dp
   minimum hit height on touch platforms.
3. **Dark theme.** DESIGN.md describes a light system. Cairn's dark theme is
   a Cairn extension built from the dark end of the same ladder
   (ink-deep grounds, canvas-direction text, unchanged charcoal/gold/link
   semantics) and is labelled as an extension in-app.
4. **Density.** Desktop (Windows) uses the token spacing as-is; compact
   (phone) maps `section` 48 → 32 and `gutter` 72 → 16 margins, keeping the
   ladder and radii unchanged.
5. **RTL.** Layouts mirror under RTL; directional icons flip; the gold rule
   and tab markers anchor to the reading-start edge.

## Enforcement

`tools/token_lint.py` (M2) fails CI if UI code introduces hex colours outside
this token set or uses brand-mark outside the wordmark widget.
