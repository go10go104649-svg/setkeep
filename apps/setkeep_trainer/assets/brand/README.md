# SETKEEP TRAINER brand

UI tokens live in `lib/design/app_colors.dart` in the root SETKEEP package and
are applied through `FamilyPalette.trainer`. Primary #38C6FF, soft #D7F4FF
(20% over white), very soft #EBF9FF (10% over white), dark #0F1720.
Existing screen/splash background remains #F3F7FA.

`trainer_symbol_source.png` is the high-resolution raster master prepared with
built-in image_gen from the approved 2026-09-25 design sheet. No alternate logo
concept was requested. `trainer_icon.png` is the opaque 1024px app/UI export.
Raster artwork retains the reference's cyan shading; UI tokens use exact HEX.

Export on macOS from `apps/setkeep_trainer`:

    swift tool/export_brand.swift

This exports iOS catalog sizes and Android legacy/round/adaptive foreground.
Run `swift tool/export_native_splash.swift` from the repository root to update
the SETKEEP and TRAINER launch logos without changing either app icon.
Adaptive foreground is an opaque dark layer, scaled so
symbol fits the OS mask; background uses the same charcoal token. Do not use
launcher artwork as an Android notification small icon: TRAINER currently has
no native notification producer and no notification icon is required.

Final image_gen prompt:
“Deliver ONE finished OPAQUE app icon, not a transparent isolated asset. It must
have a FULL rectangular solid near-black #0F1720 background filling EVERY pixel
to ALL FOUR EDGES. NO TRANSPARENCY ANYWHERE. Reproduce the EXACT icon at top right
of reference, SK with white S, cyan K two diagonal strokes and white dumbbells
left and right. Remove rounded corners from tile; square opaque background.
Symbol horizontal center, vertical center, occupies 72% width. Faithfully match
the geometry of reference. No text, no shadow, NO GLOW, NO SMUDGES, no background
texture, no vignette, no gradient. Entire background uniform solid dark flat
color. Clean crisp edges. This is a finished dark square app launcher icon, the
DARK BACKGROUND IS ESSENTIAL CONTENT and must not be removed or made transparent.”

No general SETKEEP icon, layout, auth, data or navigation changes are involved.
