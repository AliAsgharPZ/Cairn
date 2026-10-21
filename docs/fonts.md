# Fonts — provenance and bundling

## Arad (Persian primary typeface)

- Source repo: https://github.com/MohamadDarvishi/Arad (cloned 2026-10-21)
- Author: Mohamad Darvishi — License: **SIL Open Font License 1.1** (`OFL.txt`)
- Bundled at `apps/cairn_app/assets/fonts/arad/`:
  - `AradVF.ttf` — variable font. SHA-256:
    `cd45c0bbe78ec6bd45b6f90d294feed37e08b1038c75a30d7388a51bc22bd42e`
  - `AradFDVF.ttf` — variable font with Persian (Farsi) digit forms.
  - Static weights: Regular, Medium, SemiBold, Bold, ExtraBold, Light.
  - `OFL.txt`, `AUTHORS.txt` (license compliance).
- Decorative "Dots" variants and Thin/ExtraLight/Black/ExtraBlack statics were
  intentionally **not** bundled (bundle size); they can be added on request.
- Arad is the primary typeface for all Persian text in the product (UI, chat,
  dialogs, tool output, errors, in-app docs).

## Inter (Latin companion)

- License: SIL OFL 1.1. To be added in M2 from the official rsms/inter release
  when the theme layer is built (recorded here so provenance stays explicit).
- Used for Latin text where Oracle's proprietary Oracle Sans cannot ship.

## Notes

- Oracle Sans (referenced by DESIGN.md) is proprietary and non-redistributable;
  Cairn never bundles it. Headline serif register in DESIGN.md references
  Georgia; on Android/Windows app surfaces Cairn uses the sans ladder only —
  an adaptation recorded in `docs/design.md` (M2).
