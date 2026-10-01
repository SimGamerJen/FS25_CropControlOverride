# Crop Control Override 2.1.0.0-beta.3

Beta 3 expands the native crop-calendar workflow and includes additional UI consistency fixes identified during in-game testing.

## Changes since Beta 2

- Added native crop-calendar sorting directly into CCO with no dependency on FS25_CropCalendarSort.
- Added a native `SORT: <MODE>` action alongside `EDIT CALENDAR`.
- Added nine sort modes:
  - Native Order
  - Alphabetical A-Z
  - Plantable A-Z
  - Planting Start
  - Harvest Start
  - Plant Now
  - Harvest Now
  - Next Planting
  - Next Harvest
- Added persistent calendar-sort preference under `modSettings/FS25_CropControlOverride/calendarSort.xml`.
- Kept CCO's disabled-crop filtering ahead of calendar sorting so both features work together.
- Excluded the technical `MEADOW` fruit type from CCO crop management and calendar presentation.
- Added persistent `DISABLED: SHOWN/HIDDEN` UI preference under `modSettings/FS25_CropControlOverride/uiSettings.xml`.
- Fixed initial menu population so a persisted `DISABLED: HIDDEN` setting is applied before rule/calendar rows are built.
- Added EN/DE/FR localisation for native calendar sorting controls.

## Behaviour

Calendar sorting changes presentation order only. It does not modify fruit registration, planting or harvest windows, growth states, field state, contracts, or savegame crop data.

`MEADOW` is treated as technical map foliage rather than a player-manageable crop.

## Beta focus

- native Calendar integration and controller/keyboard input;
- sort-mode persistence and current-period ordering;
- CCO Calendar editor + native Calendar interaction;
- disabled-crop visibility persistence;
- dedicated-server / multiplayer validation;
- custom-map and custom-crop compatibility.
