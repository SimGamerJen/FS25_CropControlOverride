# FS25 Crop Control Override

**Version:** 2.1.0.0  
**Game:** Farming Simulator 25  
**Status:** Production release candidate  
**Author:** SimGamerJen  

Crop Control Override (CCO) is a per-save crop-policy and crop-calendar manager for Farming Simulator 25.

If you have ever started a realistic regional save only to find NPC farmers planting crops that do not belong there, or wanted to change planting windows and crop availability without editing the map itself, CCO is designed for that problem.

It lets the map adapt to the rules of your save rather than forcing your save to accept every crop and calendar decision supplied by the map.

## What CCO can control

For each crop, CCO can manage:

| Setting | Purpose |
|---|---|
| Player Permitted | Whether the crop is available to the player. |
| NPC Permitted | Whether NPC farmers may use the crop. |
| Max Field Size | Optional maximum field size for NPC use. |
| Existing Field Cleanup | Whether existing non-compliant NPC fields participate in validation/cleanup. |
| Reseed Weight | Relative 0-5 chance of selection during CCO NPC-field reseeding. |

Rules are stored per save, so different saves can use completely different crop policies.

## Main features

- Per-save crop rules covering crops loaded by the active map and mod setup.
- Independent player and NPC crop permissions.
- NPC maximum field-size restrictions.
- Individual 0-5 NPC reseed weighting.
- Full Crop Calendar editor.
- Regional Profiles for regional crop suitability and planting/harvest periods.
- Player-created custom Regional Profile XML support.
- Native Crop Calendar integration.
- Nine native calendar sort modes.
- Automatic hiding of CCO-disabled crops from the native Crop Calendar.
- Existing-field validation and preview-first cleanup.
- Guarded full-map NPC field regeneration.
- Existing-field reconciliation after calendar/profile changes.
- Multiplayer and dedicated-server support.
- English, German and French localisation.

## Opening CCO

Default keybind:

```text
ALT+C
```

The binding can be changed in the Farming Simulator controls menu.

The GUI can also be opened from the console:

```text
ccoGui
```

## Crop Calendar

CCO includes a visual crop-calendar editor with planting and harvesting periods for loaded crops.

Supported workflows include:

- Shift a crop lifecycle forward or backward.
- Define custom planting and harvesting windows.
- Preview changes before applying them.
- Cancel unapplied changes.
- Restore the original map-defined calendar.
- Open the CCO Calendar editor directly from the game's native Crop Calendar.

The native Crop Calendar also gains a sorting selector with:

- Native Order
- Alphabetical A-Z
- Plantable A-Z
- Planting Start
- Harvest Start
- Plant Now
- Harvest Now
- Next Planting
- Next Harvest

The selected sort mode is stored as a player UI preference.

## Regional Profiles

Regional Profiles allow a save to use regionally appropriate crop suitability and planting/harvest periods without modifying the underlying map.

CCO includes built-in regional data and also supports player-authored XML profiles under the CCO modSettings directory.

Regional suitability can be used to allow, hide or block crops that do not fit the selected region.

An optional read-only MoistureSystem integration can compare the selected CCO region with the active environmental profile without changing weather settings.

## Validation and existing fields

Changing crop policy can make existing NPC fields non-compliant.

CCO validation reports those fields before cleanup so the player can decide what to do.

Cleanup supports:

- **CULTIVATED** - clear the affected NPC field to cultivated state.
- **RESEED SEASONAL** - select a valid replacement crop using the current seasonal calendar, crop policy and reseed weighting.

The GUI uses a dry-run/confirmation workflow before field state is changed.

Player-owned fields are protected from NPC cleanup and reconciliation workflows.

## Full-map NPC regeneration

CCO can build a guarded full-map NPC regeneration plan using:

- Active player/NPC crop policy.
- Crop field-size limits.
- Reseed weights.
- Regional/calendar restrictions.
- Seasonal crop growth data.
- Contract-safety checks.

The plan is previewed before confirmation and uses deterministic crop selection so the confirmed operation matches the reviewed plan.

## Configuration files

Global/default template:

```text
modSettings/FS25_CropControlOverride/config.xml
```

Per-save configurations:

```text
modSettings/FS25_CropControlOverride/saves/savegameXX.xml
```

Native Calendar sort preference:

```text
modSettings/FS25_CropControlOverride/calendarSort.xml
```

CCO UI preferences:

```text
modSettings/FS25_CropControlOverride/uiSettings.xml
```

Custom Regional Profiles:

```text
modSettings/FS25_CropControlOverride/regionalProfiles/
```

CCO automatically creates a starter custom Regional Profile template when required.

## Multiplayer

CCO supports single-player, local hosted multiplayer and dedicated/cloud multiplayer.

On a dedicated server:

- The server is authoritative for active crop rules.
- Remote clients use the server-synchronised ruleset.
- Normal players are read-only.
- Admin/master users can submit rule changes.
- Validation and cleanup remain server-authoritative.
- Remote clients do not own separate local per-save CCO rule files for the server session.

## Useful console commands

```text
ccoGui
ccoStatus
ccoWhichConfig
ccoReload
ccoValidateSave
ccoScanBlocked
ccoResetBlocked dryrun
ccoResetBlocked
ccoListNpcCandidates
ccoSeasonProbe
ccoGrowthProbe
ccoCalendarReport
ccoCalendarShiftPreview
ccoCalendarShiftApply
ccoCalendarCustomPreview
ccoCalendarCustomApply
ccoCalendarRestore
ccoHelp
```

The GUI is the recommended interface for normal use; console commands are primarily useful for diagnostics and development.

## 2.1.0.0 highlights

- Added the full Crop Calendar editor with visual planting and harvesting periods, preview/cancel workflow and restore-to-map-default support.
- Added Regional Profiles with built-in regional crop calendars and support for player-created XML profiles.
- Added regional crop suitability and optional allow, hide or block policies.
- Added read-only MoistureSystem environmental-profile integration.
- Added guarded full-map NPC field regeneration using the active crop policy and seasonal calendar.
- Added existing-field reconciliation while protecting player-owned fields.
- Added direct **EDIT CALENDAR** access from the native game Crop Calendar.
- Added native Crop Calendar sorting with nine modes.
- Added automatic hiding of CCO-disabled crops from the native Crop Calendar.
- Added persistent disabled-crop visibility preference.
- Added a Weight column showing each crop's 0-5 NPC reseed weighting.
- Excluded the technical MEADOW fruit type from CCO crop management and calendar presentation.
- Added extensive dedicated-server and multiplayer improvements.
- Added crop-selection safeguards, validation improvements, UI refinements, diagnostics and localisation updates.

## Contributor acknowledgement

Hyper138's NPC field-size limitation concept and development inspired the field-size restriction functionality used by CCO.

## Safety

Use a backup before large-scale NPC-field regeneration or cleanup.

CCO deliberately uses preview, validation and confirmation stages before destructive field operations. Changing a crop rule does not automatically wipe existing fields.

## Licence and permissions

Copyright © 2026 SimGamerJen. All rights reserved.

You may download and use this mod for personal use. You may not modify, redistribute, re-upload or publish the mod, in whole or in part, or a derivative version without prior written permission from SimGamerJen.
