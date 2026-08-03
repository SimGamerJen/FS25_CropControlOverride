# FS25 Crop Control Override

Crop Control Override (CCO) is a per-save crop-policy and crop-calendar manager for Farming Simulator 25.

This branch contains the experimental **2.1.0.0 Alpha 16.7** development build. It is intended for GitHub testing and should not be treated as the current stable or ModHub release.

## Current stable release

The stable release remains the `main` branch / current ModHub-compatible 2.0.x line.

For the experimental NPC map-regeneration and crop-calendar features, use:

- Branch: `release/v2.1.0.0-alpha16.7`
- Runtime build: `2.1.0.0-alpha.16.7`
- `modDesc.xml` version: `2.1.0.0`

Back up the savegame before testing this branch.

## Alpha 16.7 highlights

### Save-specific crop-calendar editing

- Dynamically discovers seasonal fruit types loaded by the active map and mod stack, including custom map crops.
- Adds a native-style January-to-December crop calendar with crop icons, planting bars, harvesting bars, joined month segments, month dividers, and a fixed legend.
- Adds an **Edit Calendar** action to the game’s built-in Calendar page.
- Supports guarded whole-lifecycle shifts from `-6` to `+6` seasonal periods.
- Supports custom planting and harvesting windows for validated field crops with explicitly available lifecycle data.
- Generates custom calendars by phase-warping the captured map lifecycle rather than replacing native growth states.
- Requires Preview before Apply.
- Allows preview cancellation and automatically discards stale drafts when the crop, mode, staged values, tab, or screen changes.
- Supports restoring the captured map-default calendar.
- Stores overrides per savegame and rebuilds the live calendar from the map baseline on load.

### Calendar validation and safety

- Reports planting and harvesting windows, lifecycle source, reachable states, terminal states, dead ends, and baseline changes.
- Supports crops with inferred seasonal `initialState`, while keeping unsafe custom-window editing disabled for those crops.
- Categorises ordinary field, perennial, special, and technical lifecycles.
- Reports affected player fields, NPC fields, crop-specific contracts, and the available contract board before applying changes.
- Blocks Apply while accepted or active contracts are present.
- Removes and regenerates available contracts after a successful calendar Apply or Restore.
- Coordinates repeated contract-refill passes and reports normal completion or a safety-cycle stop.

### NPC map regeneration

- Adds guarded regeneration of NPC-owned fields against the active CCO crop policy and current seasonal planting conditions.
- Supports cultivated fallback and seasonal reseeding using per-crop reseed weights.
- Rebuilds available contracts after NPC field regeneration.
- Prevents NPC regeneration and calendar contract rebuilding from running simultaneously.

### Crop policy and multiplayer

- Retains player and NPC crop enable/disable rules.
- Retains NPC field-size limits, per-crop reseed weights, dry-run validation, and blocked-field cleanup.
- Retains server-authoritative multiplayer configuration and admin/master-user editing controls.
- Synchronises calendar shifts and custom calendar overrides from the server to connected clients.
- Restores removed client overrides to the captured map baseline.

## Important known limitation

Changing a crop calendar does **not yet remap existing fields to a corresponding growth state in the new calendar**. Existing player and NPC field states are included in impact reporting but are deliberately left unchanged in Alpha 16.7.

Field-state reconciliation is planned as a separate experimental development phase because it directly mutates savegame fields and requires additional safeguards.

## Installation for testing

1. Back up the savegame.
2. Package the mod source so that `modDesc.xml` is at the root of `FS25_CropControlOverride.zip`.
3. Place the ZIP directly in the Farming Simulator 25 mods folder.
4. Enable the mod for the test save.
5. Open CCO with `ALT+C`, or use **Edit Calendar** from the game’s Calendar page.

A ready-to-install mod ZIP is supplied separately with this branch-content bundle.

## Main interface

- **ALL RULES** — view and edit all crop-policy rules.
- **DISABLED** — view globally disabled crops.
- **SIZE LIMITED** — view crops with NPC field-size restrictions.
- **NPC DISABLED** — view crops that NPC farmers may not plant.
- **VALIDATION** — inspect existing NPC fields that conflict with active rules and use the guarded dry-run/confirmation workflow.
- **CALENDAR** — inspect and edit loaded crop calendars using guarded Shift or Custom Windows modes.
- **SUMMARY** — review the active configuration, rule counts, and validation state.
- **HELP** — view in-game operating guidance.

## Useful console commands

- `ccoGui`
- `ccoStatus`
- `ccoWhichConfig`
- `ccoReload`
- `ccoValidateSave`
- `ccoScanBlocked`
- `ccoResetBlocked dryrun`
- `ccoResetBlocked`
- `ccoListNpcCandidates`
- `ccoSeasonProbe`
- `ccoGrowthProbe`
- `ccoCalendarReport`
- `ccoCalendarShiftApply`
- `ccoCalendarCustomPreview`
- `ccoCalendarCustomApply`
- `ccoHelp`

## Feedback

When reporting an issue, include:

- `log.txt`
- map name
- single-player, local multiplayer, or dedicated-server context
- crop involved
- selected calendar mode and proposed windows/shift
- whether existing fields or contracts were present
- steps required to reproduce the problem

## Contributor acknowledgement

Hyper138, who's NPC field-size limitation concept and development inspired me to build size-limitation functionality into the mod.

## Licence and redistribution

This repository is maintained by SimGamerJen. Preserve the existing attribution and repository history when redistributing or contributing changes.
