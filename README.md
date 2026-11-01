# Little Imprints

The baby ink-pad keepsake app: a baby's hand or foot presses directly
on the screen — no ink, no mess — and Little Imprints keeps the print
at its **true size**, in a keepsake book with the child's age computed
for every print, a growth timeline, composed pages with decorations,
true-size sharing (image, wallpaper, and actual-size PDF), and the
quiet Nightstand Walk for the charger at night.

**Privacy is a build constraint, not a label:** on-device only. No
account, no server, no analytics, no ads, no camera — prints are made
from touch alone. "Data Not Collected" is simply true.

- Bundle ID: `com.getperkwatch.littleimprints`
- iOS 17+, SwiftUI, no third-party dependencies.
- Spec: `~/workspace/goals/baby-ink-pad-app/files/baby-ink-pad-spec-and-build-list-2026-11-01.md`

## Building

CI lives in the `perkwatch/perkwatch-ios` repo as the dispatch-only
workflow `build-littleimprints.yml` (the self-hosted iMac runner is
registered to that repo). Dispatch it with mode `compile` for a full
Xcode compile + the pure-logic assertion harness, or `release` to
archive and upload to TestFlight (needs the App Store provisioning
profile secret, set up after the App Store Connect record exists).

Versioning mirrors PerkWatch: the committed `CURRENT_PROJECT_VERSION`
is the base; CI bumps +1 for the build, and the base is committed
forward after each upload (bookkeeping commits carry `[skip ci]`).
