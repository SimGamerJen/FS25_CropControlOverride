# Crop Control Override 2.1.0.0-beta.2

Beta 2 is a quality-of-life and UI refinement release for the 2.1 development cycle. It retains the feature set introduced in Beta 1 while improving clarity and consistency in the in-game management screens.

## Changes since Beta 1

- Reworked the VALIDATION tab into a structured management view instead of a fixed-width text report.
- Added clear PASS / ATTENTION status, save field counts, and a blocked-field table with crop, size, reseed candidate, and reason.
- Separated Existing Field Cleanup from NPC Map Regeneration actions.
- Changed RESET SCOPE and RESET MODE to the same selector interaction used elsewhere in CCO.
- Corrected disabled-crop visibility so the ALL RULES toggle no longer suppresses crops on the DISABLED or NPC DISABLED diagnostic tabs.
- Added the shared DISABLED: SHOWN/HIDDEN control to the CALENDAR tab.
- Calendar disabled-crop filtering now survives regional-profile preview/apply refreshes.
- Restored repository documentation when promoting the 2.1 code line.

## Behaviour

No crop-policy, reset, regeneration, or calendar-policy engine behaviour is intentionally changed by this release. The changes are focused on presentation, filtering semantics, and workflow consistency.

## Beta focus

- UI and edge-case validation;
- dedicated-server / multiplayer validation;
- compatibility testing;
- regression testing of calendar and regional-profile workflows.
