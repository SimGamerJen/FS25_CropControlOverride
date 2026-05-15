# FS25 Crop Control Override

Version: `2.0.0-alpha.10`

Merged development credit: **SimGamerJen** and **Hyper138**.

Crop Control Override is a per-save crop policy mod for Farming Simulator 25. This merged alpha combines the original CropControlOverride idea with Hyper138's NPC crop-control and field-size governance concept.

## What this build does

- Reads global defaults from `modSettings/FS25_CropControlOverride/config.xml`.
- Creates and uses per-save configs under `modSettings/FS25_CropControlOverride/saves/savegameX.xml`.
- Reads and normalizes pre-2.0.0 / v1 entries such as `<fruit name="ONION" enabled="false" />`.
- Supports v2 crop policy attributes:
  - `enabled`
  - `npcAllowed`
  - `npcMaxHa`
  - `resetNpcFields`
- Applies crop disabling to supported fruitType flags.
- Blocks disabled crops from NPC field selection and sowing missions where the relevant game hooks are available.
- Supports NPC field-size limits, for example allowing maize only on fields up to 5 ha.
- Scans existing saves and can manually reset offending NPC fields to cultivated state.
- Prints a startup validation notice after map load.
- Adds `ccoStatus` and `ccoHelp` for easier testing/release review.
- Moves detailed NPC replacement/block trace messages to DEBUG log level to reduce normal log noise.
- Automatically migrates legacy per-save XMLs to the v2 rule schema.
- Preserves custom or currently undiscovered crop rules during migration and save writes.

## Config locations

Global template/default config:

```text
<UserDocuments>/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/config.xml
```

Per-save config:

```text
<UserDocuments>/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/saves/savegameX.xml
```

The per-save file is preferred when it exists. Use `ccoWhichConfig` to confirm which file is active.

## Config examples

Disable a crop completely and prevent NPC use:

```xml
<fruit name="COTTON" enabled="false" npcAllowed="false" npcMaxHa="0" resetNpcFields="true"/>
```

Allow a crop generally, but restrict NPCs to fields up to 5 ha:

```xml
<fruit name="MAIZE" enabled="true" npcAllowed="true" npcMaxHa="5" resetNpcFields="true"/>
```

Keep the crop enabled and use the map/default NPC setting unless a size rule applies:

```xml
<fruit name="POTATO" enabled="true" npcAllowed="mapDefault" npcMaxHa="10" resetNpcFields="true"/>
```

## Console commands

```text
ccoHelp [rules|scan|reset|debug]
ccoStatus
ccoWhichConfig
ccoReload
ccoListRules [CROP]
ccoListConfigured [CROP]
ccoListUndiscovered
ccoNormalizeConfig [dryrun]
ccoSetCrop <CROP> <enabled:true|false> [npcAllowed:true|false|mapDefault] [npcMaxHa]
ccoExplain <CROP>
ccoListFlags [CROP]
ccoFindFruit <text>
ccoListLimited
ccoListDisabled
ccoListBlockedRules
ccoListNpcCandidates <FIELD_ID>
ccoScanFields [CROP]
ccoScanBlocked [CROP]
ccoScanSummary [CROP]
ccoValidateSave
ccoResetNpcFields [CROP|all] [dryrun]
ccoResetBlocked [dryrun]
ccoDebug on|off|toggle
ccoLogLevel DEBUG|INFO|WARN|ERROR
```

## Legacy config migration

Pre-2.0.0 CCO configs used entries such as:

```xml
<fruit name="COTTON" enabled="false"/>
```

Alpha 9 and later normalize those rules into the v2 schema:

```xml
<fruit name="COTTON" enabled="false" npcAllowed="false" npcMaxHa="0" resetNpcFields="true"/>
```

Migration behaviour:

- `enabled="false"` becomes `enabled="false" npcAllowed="false" npcMaxHa="0" resetNpcFields="true"`.
- `enabled="true"` becomes `enabled="true" npcAllowed="mapDefault" npcMaxHa="0" resetNpcFields="true"` unless explicit v2 values already exist.
- Custom crop rules are preserved even when the fruitType is not loaded on the active map/save.
- Newly discovered map/DLC/mod fruitTypes are added to the per-save XML with default allowed rules.

Useful checks:

```text
ccoNormalizeConfig dryrun
ccoNormalizeConfig
ccoListConfigured
ccoListUndiscovered
```

## Existing-save cleanup workflow

Use this when CCO is added to a save that was already generated, or after changing crop rules.

```text
ccoWhichConfig
ccoValidateSave
ccoScanBlocked
ccoResetBlocked dryrun
ccoResetBlocked
ccoValidateSave
```

`ccoResetBlocked` only targets NPC-owned fields that violate active CCO rules. It does not intentionally reset player-owned fields. Use `dryrun` first.

## Field-size limit test workflow

Example using maize, allowing NPC maize only on fields up to 5 ha:

```text
ccoSetCrop MAIZE true true 5
ccoReload
ccoScanSummary MAIZE
ccoResetNpcFields MAIZE dryrun
```

If the dry-run output is correct:

```text
ccoResetNpcFields MAIZE
ccoValidateSave
```

## Startup validation

CCO prints a one-line startup validation notice after map load.

If the save is clean, the log should show a pass message with checked/NPC/player field counts.

If blocked NPC fields are found, the log will suggest:

```text
ccoScanBlocked
ccoResetBlocked dryrun
```

This is intentionally only a notice. CCO does not auto-reset fields on load. Manual cleanup remains the safe default.

## Tested alpha workflows

The merged alpha has been validated in-game for:

- Detecting disabled crops already present in a save created without CCO.
- Resetting disabled NPC crop fields to cultivated state.
- Keeping player-owned fields out of reset operations.
- Detecting and resetting NPC field-size violations.
- Revalidating after sleeping one in-game day.
- Compact summary reporting and pass/fail validation.

## Notes

This build is still console/XML driven. A GUI can be added later once the policy engine has had more savegame and map testing.

## Release readiness

Alpha 10 is intended as a beta-candidate preparation build. The validated enforcement paths from alpha 7 through alpha 9 are unchanged. Testing should focus on packaging, command wording, migration behaviour on real older saves, and normal savegame workflows rather than forcing new crop-policy logic changes.

Recommended final pre-beta checks:

```text
ccoStatus
ccoWhichConfig
ccoNormalizeConfig dryrun
ccoListConfigured
ccoListUndiscovered
ccoValidateSave
ccoScanSummary
```


### Alpha 7 NPC candidate diagnostics

`ccoListNpcCandidates <FIELD_ID>` lists every discovered fruitType and explains whether it is a valid NPC planting candidate for the specified field under the current CCO rules. This is intended for testing replacement behaviour when the vanilla NPC crop choice is blocked.

### Alpha 8 release-prep changes

Alpha 8 does not intentionally change the validated field reset or NPC crop replacement logic. It is a polish build for testing and release review.

Changes:

- Added `ccoStatus` for a compact version/config/rule/field health check.
- Added `ccoHelp [rules|scan|reset|debug]` for in-game command discovery.
- Moved detailed NPC crop replacement/block and sow-mission block messages to DEBUG log level. Use `ccoLogLevel DEBUG` when actively testing candidate replacement.
- Kept startup validation and normal command output visible at INFO/default behaviour.


### Alpha 9 migration changes

Alpha 9 keeps the validated alpha 7/8 field reset and NPC replacement logic intact. It adds explicit migration/normalization for pre-2.0.0 per-save XML files and better visibility of configured but undiscovered crop rules.

Changes:

- Auto-normalizes legacy per-save XMLs when loaded.
- Adds `ccoNormalizeConfig [dryrun]`.
- Adds `ccoListConfigured [CROP]`.
- Adds `ccoListUndiscovered`.
- Writes newly discovered custom map crops back to the per-save XML after map load.
- Preserves configured rules for custom/DLC/map crops even when they are not currently discovered.


### Alpha 10 release-prep changes

Alpha 10 is a packaging and beta-candidate preparation build. It does not intentionally alter the validated field reset, NPC crop replacement, or legacy XML migration logic.

Changes:

- Version/build tags updated to `2.0.0-alpha.10`.
- README reorganised for beta-candidate review.
- modDesc description updated to make the migration and release-prep status clearer.
- Keeps custom crop discovery and pre-2.0.0 per-save XML migration from alpha 9.
- Keeps detailed NPC replacement/block traces at DEBUG log level.
