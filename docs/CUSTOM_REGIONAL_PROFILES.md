# Custom CCO Regional Profiles

CCO crop calendars and MoistureSystem weather profiles are intentionally independent.

## Folder

Place custom profile XML files in:

`Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/regionalProfiles/`

CCO creates the folder when the game loads.

## Example

```xml
<cropCalendarProfile
    id="missouriBootheel"
    displayName="Missouri Bootheel"
    description="My regional crop calendar"
    moistureAliases="missouribootheel">

    <crop name="MAIZE"
          suitability="excellent"
          planting="APR-MAY"
          harvest="SEP-OCT"/>
</cropCalendarProfile>
```

Supported suitability values are:
`excellent`, `good`, `normal`, `marginal`, `poor`, `unsuitable`.

Planting and harvest values use the same month syntax as CCO's built-in profiles,
for example `APR-MAY`, `SEP`, `OCT-NOV`, or comma-separated windows such as
`SEP-OCT,MAR`.

A crop omitted from a custom profile remains neutral/default in suitability and
keeps the map calendar.

Custom profile IDs may not replace CCO built-in profile IDs.

`moistureAliases` is optional. It is only an informational pairing between a
MoistureSystem weather-profile ID and this CCO crop profile. CCO does not infer
latitude or climate and does not alter MoistureSystem.


## Unsuitable policy

Set `unsuitablePolicy` on the root profile:

- `allow` — default. `unsuitable` remains an advisory suitability rating for the player.
- `hide` — removes unsuitable crops from normal loaded seeder selections. It is not a
  hard runtime prohibition.
- `block` — hides unsuitable crops and server-authoritatively prevents sowing them.

NPC regional crop selection already gives `unsuitable` crops zero regional weighting.

## Validation

CCO rejects the entire custom profile before it enters the selector if it contains:

- an invalid or reserved profile ID;
- a built-in/custom profile ID collision;
- an invalid `unsuitablePolicy`;
- a duplicate crop entry;
- an unknown suitability value;
- malformed month syntax;
- only one side of a calendar override (`planting` without `harvest`, or vice versa).

Unknown crop names are intentionally not rejected because a profile may target modded
crops or be reused across maps.

A ready-to-copy template ships in the mod ZIP at:

`templates/customRegionalProfile.xml`


## Automatic starter template

On game load, CCO ensures the custom profile directory exists and creates:

`regionalProfiles/_template.xml`

from the template bundled with the mod.

`_template.xml` is intentionally ignored by the profile loader so the starter
profile does not appear in the Regional Crop Profile selector by accident.
Rename or copy it to another `.xml` filename (for example
`missouriBootheel.xml`) and edit its `id` and `displayName` to activate it.

CCO only creates `_template.xml` when it is missing. It never overwrites a
player's existing `_template.xml`.


## Path resolution fix (Alpha 18.6.3)

CCO captures its own mod directory/name when its Lua source is loaded and derives
the custom profile directory from `getUserProfileAppPath()`. This avoids using
GIANTS globals such as `g_currentModDirectory` or `g_currentModSettingsDirectory`
after other mods have overwritten them during startup.
