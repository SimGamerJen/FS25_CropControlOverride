# Crop Control Override 2.1.0.0

Crop Control Override 2.1.0.0 is the production release of the 2.1 development line for Farming Simulator 25.

This release expands CCO from crop-policy management into a broader regional crop-management system: per-save crop rules, regional profiles, crop-calendar editing, native calendar sorting, NPC-field validation, safe cleanup and guarded full-map NPC field regeneration.

## Highlights

- Per-save crop availability and NPC planting policy.
- Maximum NPC field-size rules per crop.
- Individual 0-5 NPC reseed weighting.
- Full Crop Calendar editor with preview, custom planting/harvest windows and map-default restore.
- Regional Profiles with regional crop suitability and calendar data.
- Player-authored custom Regional Profile XML support.
- Native Crop Calendar integration with direct **EDIT CALENDAR** access.
- Native Crop Calendar sorting with nine ordering modes.
- Automatic hiding of CCO-disabled crops from the native Crop Calendar.
- Existing-field validation and preview-first cleanup.
- Guarded full-map NPC field regeneration using the active policy and seasonal calendar.
- Existing-field reconciliation while protecting player-owned fields.
- Multiplayer and dedicated-server support with server-authoritative rules.
- English, German and French localisation.

## Changes since the previous ModHub production release

- Added the full Crop Calendar editor with visual planting and harvesting periods, preview/cancel workflow and restore-to-map-default support.
- Added Regional Profiles with built-in regional crop calendars and support for player-created XML profiles.
- Added regional crop suitability and optional allow, hide or block policies for unsuitable crops.
- Added read-only MoistureSystem environmental-profile integration.
- Added guarded full-map NPC field regeneration using the active crop policy and seasonal calendar.
- Added existing-field reconciliation for safely applying calendar and Regional Profile changes to NPC fields while protecting player-owned fields.
- Added direct **EDIT CALENDAR** access from the native game Crop Calendar.
- Added native Crop Calendar sorting with Native Order, A-Z, Plantable A-Z, Planting Start, Harvest Start, Plant Now, Harvest Now, Next Planting and Next Harvest modes.
- Added persistent native calendar-sort preference.
- Added automatic hiding of CCO-disabled crops from the native Crop Calendar.
- Added persistent **DISABLED: SHOWN/HIDDEN** filtering to CCO rule and calendar views.
- Added a Weight column showing each crop's 0-5 NPC reseed weighting.
- Added automatic creation of a starter custom Regional Profile template.
- Excluded the technical MEADOW fruit type from CCO crop management and calendar presentation.
- Added extensive dedicated-server and multiplayer improvements.
- Added crop-selection safeguards, validation improvements, UI refinements, diagnostics and localisation updates.

## Safety

CCO uses preview, validation and confirmation stages before destructive field operations. Crop-rule changes do not automatically wipe fields, and calendar changes can be previewed before being committed.

As with any mod that can alter NPC field state, keeping a backup before large-scale regeneration or cleanup is recommended.
