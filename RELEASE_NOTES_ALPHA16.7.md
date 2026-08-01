# Crop Control Override 2.1.0.0 Alpha 16.7

This is an **experimental GitHub pre-release** for the 2.1 development line. Use a backed-up test save and do not treat this build as the current ModHub/stable release.

## Headline features

### Save-specific crop-calendar customisation

- Dynamically discovers every seasonal fruit type loaded by the active map and mod stack, including custom map crops.
- Adds a native-style visual crop calendar with January-to-December columns, joined planting and harvesting bars, crop icons, column dividers, and a full legend.
- Adds an **Edit Calendar** action to the game’s built-in Calendar page.
- Supports guarded whole-lifecycle shifts from `-6` to `+6` seasonal periods.
- Supports custom planting and harvesting windows for validated field crops with explicitly exposed lifecycle data.
- Uses a phase-warped version of the map-defined lifecycle rather than inventing or replacing native growth states.
- Requires Preview before Apply and renders proposed changes as an unapplied draft in the calendar grid.
- Preview changes can be cancelled and are automatically discarded when the crop, mode, staged values, tab, or screen changes.
- Supports restoring the captured map-default calendar.
- Stores only save-specific calendar overrides and reconstructs the live calendar from the map baseline when loading.

### Calendar validation and safety

- Reports calendar availability, planting and harvest windows, lifecycle source, state reachability, terminal states, dead ends, and baseline changes.
- Supports crops whose seasonal `initialState` is inferred, while restricting unsafe custom-window editing for those crops.
- Categorises ordinary field, perennial, special, and technical lifecycles for safer editing.
- Reports affected player fields, NPC fields, crop-specific contracts, and the complete available contract board before Apply.
- Accepted or active contracts block calendar application.
- Available contracts are removed and regenerated after a successful calendar Apply or Restore.
- Contract regeneration runs through controlled repeated passes and reports normal completion or a safety-cycle stop.
- Existing field growth states are deliberately left unchanged in this alpha.

### NPC map regeneration

- Adds guarded regeneration of NPC-owned fields against the active CCO crop policy and current seasonal planting conditions.
- Supports cultivated fallback and seasonal reseeding using per-crop reseed weights.
- Rebuilds available contracts after NPC field regeneration.
- Coordinates regeneration and calendar contract rebuilding so the two operations cannot run simultaneously.

### Crop policy and multiplayer

- Retains player and NPC crop enable/disable policy, NPC field-size limitations, per-crop reseed weights, dry-run validation, and blocked-field cleanup.
- Retains server-authoritative multiplayer configuration and admin/master-user editing controls.
- Synchronises calendar shifts and custom calendar overrides from the server to connected clients.
- Restores removed overrides to the captured map baseline on clients.

## Interface changes

- Reworked Calendar tab with native-style continuous planting and harvesting bars.
- Added calendar month dividers and matching column dividers to the crop-rule tables.
- Added a fixed Planting/Harvesting legend beneath the calendar grid.
- Added draft Preview/Cancel behaviour and Apply Restore workflow.
- Updated contributor acknowledgement in the multilingual `modDesc.xml` descriptions.

## Tested during alpha development

- Riverbend Springs with all 26 loaded base-game fruit types.
- A custom-crop map with 38 loaded fruit types and 12 additional map crops.
- Whole-lifecycle shift, persistence, restoration, and baseline comparison.
- Custom WHEAT planting/harvest windows and map-default restoration.
- Player/NPC field-impact reporting without field-state mutation.
- Contract-board removal and repeated regeneration.
- Visual calendar scrolling, icons, joined bars, overlapping planting/harvest windows, dividers, legend, and draft rendering.

## Important known limitation

Changing a crop calendar does **not yet remap existing fields to a corresponding growth state in the new calendar**. Existing player and NPC field growth states are reported but intentionally left unchanged. Field-state reconciliation is planned as a separate experimental development phase because it can directly alter savegame fields.

## Installation

1. Back up the savegame.
2. Download `FS25_CropControlOverride_2.1.0.0_alpha16.7.zip` from this pre-release.
3. Place the ZIP directly in the Farming Simulator 25 mods folder.
4. Enable the mod for the test save.
5. Open CCO with `ALT+C`, or use **Edit Calendar** from the game’s Calendar page.

Do not unzip the mod for normal gameplay use.

## Feedback requested

Please include `log.txt`, the map name, multiplayer/single-player context, the crop involved, the selected calendar mode/windows, and whether existing fields or contracts were present when reporting an issue.

## Contributor acknowledgement

Hyper138, who's NPC field-size limitation concept and development inspired me to build size-limitation functionality into the mod.
