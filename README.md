# FS25_CropControlOverride v2.0.0-alpha

**FS25_CropControlOverride** is a Farming Simulator 25 script mod that controls which crops / fruitTypes can be used by the game, with a particular focus on preventing unsuitable crops from appearing on NPC-owned fields.

Version `2.0.0-alpha` is a major development branch that moves the mod toward a **console/XML-driven crop policy engine**.

This README applies to the `2.0.0-alpha` branch only.

---

## Alpha Warning

This is an experimental pre-release build.

Use only on test saves or backed-up saves.

Before testing:

- Back up your savegame.
- Back up your existing working version of the mod.
- Do not overwrite a known-working setup unless you are deliberately testing this alpha.
- Expect behaviour, config structure, and command output to change before the final `2.0.0` release.

For the previous stable version, use the `v1.0.0.5` release from GitHub Releases.

---

## What v2.0.0-alpha Is

`2.0.0-alpha` introduces a new policy-based approach for controlling crop behaviour.

The goal is to allow each crop / fruitType to be controlled through XML configuration and console commands, including whether that crop is allowed generally, whether NPC fields may use it, and whether existing NPC fields using that crop should be reset.

This version is intended to support better regional realism and stronger testing workflows than the older stable branch.

---

## Merge Scope

This alpha includes selected script-side concepts from Hyper138’s NPC Crop Control approach.

Included:

- XML-driven crop policy logic.
- NPC crop allow/block handling.
- Per-crop policy options.
- Console diagnostics.
- NPC field scanning.
- NPC field reset workflow.
- Dry-run support for testing reset behaviour safely.

Not included at this stage:

- GUI components.
- In-game graphical configuration menus.
- Any final user-facing interface for non-console users.

This branch is focused on core script behaviour and tester diagnostics.

---

## Core Concepts

Each crop / fruitType can have policy settings.

The important policy concepts are:

| Option | Purpose |
|---|---|
| `enabled` | Whether the crop is generally enabled in the policy system |
| `npcAllowed` | Whether NPC-owned fields are allowed to use this crop |
| `npcMaxHa` | Optional maximum NPC field size for this crop, in hectares |
| `resetNpcFields` | Whether NPC fields using this crop should be reset when correction commands are run |

The main focus of this alpha is NPC crop control.

---

## Example Policy Concept

Example XML-style policy concept:

```xml
<crop name="COTTON" enabled="true" npcAllowed="false" resetNpcFields="true" />
<crop name="ONION" enabled="true" npcAllowed="false" resetNpcFields="true" />
<crop name="WHEAT" enabled="true" npcAllowed="true" />
<crop name="BARLEY" enabled="true" npcAllowed="true" npcMaxHa="8.0" />
````

Example meaning:

```text
COTTON:
  Crop exists but NPC fields should not use it.
  NPC fields already using it may be reset.

ONION:
  Crop exists but NPC fields should not use it.
  NPC fields already using it may be reset.

WHEAT:
  Crop is allowed for NPC fields.

BARLEY:
  Crop is allowed for NPC fields, but NPC use may be constrained by field size.
```

The exact XML structure may differ depending on the current alpha build, but the policy meaning should follow this model.

---

## FruitType Names

The mod uses FS25 internal fruitType names. If a map is shipped with custom crops, or you have added custom crops by some other method, those crops will be detected and added to the per-save XML file automatically.

Examples:

```text
WHEAT
BARLEY
OAT
CANOLA
SUNFLOWER
SOYBEAN
MAIZE
POTATO
SUGARBEET
COTTON
ONION
CARROT
BEETROOT
PARSNIP
GRASS
MEADOW
```

Names are normally uppercase.

When testing a crop, use the internal fruitType name shown in the game logs or console output.

---

# Console Commands

The `2.0.0-alpha` branch is designed around console-based testing and diagnostics.

Commands are entered in the Farming Simulator 25 developer console.

---

## `ccoWhichConfig`

Shows which CropControlOverride configuration is currently active.

```text
ccoWhichConfig
```

Use this first when testing a savegame.

Purpose:

```text
Confirms which config file/profile the mod has loaded.
```

Recommended use:

```text
ccoWhichConfig
ccoListRules
ccoScanFields
```

This is especially useful when testing per-save configuration, because it confirms whether the expected XML file is being used.

---

## `ccoExplain <FRUITTYPE>`

Explains the effective policy for a specific crop / fruitType.

```text
ccoExplain <FRUITTYPE>
```

Example:

```text
ccoExplain COTTON
```

Expected purpose:

```text
Shows how CropControlOverride currently interprets the selected crop.
```

Typical information should include:

```text
Crop / fruitType name
Whether the crop is enabled
Whether NPC fields are allowed to use it
Whether an NPC max field size applies
Whether NPC fields using this crop are eligible for reset
Which rule/config entry caused the result
```

Use this when a crop appears somewhere unexpected.

Example troubleshooting sequence:

```text
ccoExplain COTTON
ccoScanBlocked
```

---

## `ccoListRules`

Lists the active crop policy rules loaded from configuration.

```text
ccoListRules
```

Purpose:

```text
Shows the currently loaded rules and their effective values.
```

This command is useful for confirming that XML configuration has been parsed correctly.

Expected information may include:

```text
Crop name
enabled
npcAllowed
npcMaxHa
resetNpcFields
Rule source or profile
```

Recommended after editing XML:

```text
ccoReload
ccoListRules
```

---

## `ccoSetCrop <FRUITTYPE> <OPTION> <VALUE>`

Sets or overrides a crop policy option from the console.

```text
ccoSetCrop <FRUITTYPE> <OPTION> <VALUE>
```

Examples:

```text
ccoSetCrop COTTON npcAllowed false
ccoSetCrop ONION npcAllowed false
ccoSetCrop BARLEY npcMaxHa 8.0
ccoSetCrop COTTON resetNpcFields true
```

Supported policy options are expected to include:

```text
enabled
npcAllowed
npcMaxHa
resetNpcFields
```

Purpose:

```text
Allows quick testing of crop policy changes without manually editing XML every time.
```

After changing a crop rule, run:

```text
ccoListRules
ccoExplain <FRUITTYPE>
ccoScanBlocked
```

Example:

```text
ccoSetCrop COTTON npcAllowed false
ccoExplain COTTON
ccoScanBlocked
```

Depending on the alpha build, console changes may be temporary unless saved back to XML.

---

## `ccoReload`

Reloads CropControlOverride configuration.

```text
ccoReload
```

Purpose:

```text
Reloads XML policy configuration without restarting the game.
```

Use this after manually editing configuration files.

Recommended sequence:

```text
ccoReload
ccoWhichConfig
ccoListRules
ccoScanFields
ccoScanBlocked
```

If a crop’s behaviour changes after `ccoReload`, this may indicate that the crop was loaded or modified after the initial CCO startup pass.

---

## `ccoScanFields`

Scans current field crop usage.

```text
ccoScanFields
```

Purpose:

```text
Reports current crop usage across fields and compares it against active policy rules.
```

This is the general field inspection command.

Expected output may include:

```text
Field count scanned
NPC field count
Player field count
Crop present on each field or grouped summary
Whether each crop is allowed for NPC use
Whether field size exceeds npcMaxHa
```

Use this to understand what crops are currently present in the save.

Recommended sequence:

```text
ccoWhichConfig
ccoListRules
ccoScanFields
```

---

## `ccoScanBlocked`

Scans for NPC fields that violate current crop policy.

```text
ccoScanBlocked
```

Purpose:

```text
Shows NPC fields currently using crops that are blocked or outside their configured limits.
```

This is the key command for identifying problem NPC fields.

Examples of blocked conditions:

```text
NPC field uses a crop with npcAllowed=false
NPC field exceeds npcMaxHa for that crop
NPC field uses a crop marked for reset
```

Recommended sequence before resetting fields:

```text
ccoScanFields
ccoScanBlocked
```

Use this command before running any reset command.

---

## `ccoResetNpcFields`

Resets NPC fields that violate crop policy.

```text
ccoResetNpcFields
```

Purpose:

```text
Corrects NPC-owned fields that are using blocked or disallowed crops.
```

This command should only affect NPC fields, not player-owned fields.

Run diagnostics first:

```text
ccoScanBlocked
ccoResetNpcFields
ccoScanBlocked
```

Important:

```text
Back up your save before using reset commands on a real save.
```

---

## `ccoResetNpcFields <FRUITTYPE>`

Resets NPC fields using a specific crop / fruitType.

```text
ccoResetNpcFields <FRUITTYPE>
```

Example:

```text
ccoResetNpcFields COTTON
```

Purpose:

```text
Targets only NPC fields using the specified crop.
```

Recommended sequence:

```text
ccoExplain COTTON
ccoScanBlocked
ccoResetNpcFields COTTON
ccoScanBlocked
```

Use this when testing one crop at a time.

---

## `ccoResetNpcFields dryrun`

Shows what would be reset without changing the save.

```text
ccoResetNpcFields dryrun
```

Purpose:

```text
Performs a safe preview of reset behaviour.
```

This should report affected NPC fields without making changes.

Recommended before any real reset:

```text
ccoScanBlocked
ccoResetNpcFields dryrun
```

---

## `ccoResetNpcFields <FRUITTYPE> dryrun`

Shows what would be reset for a specific crop without changing the save.

```text
ccoResetNpcFields <FRUITTYPE> dryrun
```

Example:

```text
ccoResetNpcFields COTTON dryrun
```

Purpose:

```text
Safely previews which NPC fields using the specified crop would be reset.
```

This is the safest first test for crop-specific correction.

Recommended workflow:

```text
ccoExplain COTTON
ccoScanBlocked
ccoResetNpcFields COTTON dryrun
ccoResetNpcFields COTTON
ccoScanBlocked
```

---

# Recommended Testing Workflows

## First Check After Loading a Save

Run:

```text
ccoWhichConfig
ccoListRules
ccoScanFields
ccoScanBlocked
```

This confirms:

* Which config is loaded.
* Which policy rules are active.
* What crops are currently present.
* Whether any NPC fields violate policy.

---

## After Editing XML Config

Run:

```text
ccoReload
ccoWhichConfig
ccoListRules
ccoScanFields
ccoScanBlocked
```

This confirms the edited XML has been loaded and applied.

---

## Testing One Blocked Crop

Example for cotton:

```text
ccoExplain COTTON
ccoScanBlocked
ccoResetNpcFields COTTON dryrun
```

If the dry run looks correct:

```text
ccoResetNpcFields COTTON
ccoScanBlocked
```

---

## Testing a New Policy Rule from Console

Example:

```text
ccoSetCrop COTTON npcAllowed false
ccoSetCrop COTTON resetNpcFields true
ccoExplain COTTON
ccoScanBlocked
ccoResetNpcFields COTTON dryrun
```

If the result is correct:

```text
ccoResetNpcFields COTTON
ccoScanBlocked
```

---

## Checking Max NPC Field Size

Example:

```text
ccoSetCrop BARLEY npcAllowed true
ccoSetCrop BARLEY npcMaxHa 8.0
ccoExplain BARLEY
ccoScanBlocked
```

This should identify NPC barley fields that exceed the configured size limit, if that logic is active in the alpha build.

---

# Bug Report Command Set

When reporting a problem, please include output from:

```text
ccoWhichConfig
ccoListRules
ccoScanFields
ccoScanBlocked
ccoExplain <AFFECTED_FRUITTYPE>
```

If the issue involves field reset behaviour, also include:

```text
ccoResetNpcFields <AFFECTED_FRUITTYPE> dryrun
```

Example:

```text
ccoWhichConfig
ccoListRules
ccoScanFields
ccoScanBlocked
ccoExplain COTTON
ccoResetNpcFields COTTON dryrun
```

---

# Bug Report Template

Please include:

```text
Mod version:
Map:
Savegame:
New save or existing save:
Other crop / fruitType mods installed:
Affected crop / fruitType:
Relevant rule/config entry:
Expected behaviour:
Actual behaviour:
Did ccoReload change the result:
Console command output:
Log excerpt:
```

For field reset issues, also include:

```text
Dry-run output:
Was the field NPC-owned or player-owned:
Field number if known:
Crop before reset:
Crop after reset:
```

---

# Known Alpha Limitations

This alpha focuses primarily on NPC crop policy logic.

Areas that may still require testing or further implementation include:

* Full PDA crop overlay hiding.
* Full crop calendar hiding.
* Full price table hiding.
* Seeder UI crop selection filtering.
* Contract generation edge cases.
* Field job generation edge cases.
* Late-loaded DLC fruitTypes.
* Map-added fruitTypes.
* Other mods that modify fruitType properties after CCO has loaded.
* Persistence of console-edited rules, depending on implementation state.

Some game systems may cache crop data before CCO applies policy changes.

If behaviour changes after running:

```text
ccoReload
```

then the issue may be related to load order or late crop registration.

---

# Safety Notes

`ccoScanFields`, `ccoScanBlocked`, `ccoExplain`, `ccoWhichConfig`, and `ccoListRules` are diagnostic commands.

`ccoResetNpcFields` is a corrective command and may alter field state.

Always use dry-run first:

```text
ccoResetNpcFields dryrun
```

or:

```text
ccoResetNpcFields <FRUITTYPE> dryrun
```

Then only run the real reset command if the dry-run output is correct.

---

# Compatibility

Designed for:

```text
Farming Simulator 25
```

Test with:

* Base-game maps.
* Mod maps.
* Maps with custom fruitTypes.
* DLC crops.
* Existing savegames.
* New savegames.
* Per-save configuration.
* Global/default configuration.
* Saves with both NPC and player-owned fields.

---

# Development Scope for v2.0.0-alpha

The `2.0.0-alpha` branch focuses on:

* Policy-based crop control.
* NPC field crop restrictions.
* Per-crop XML options.
* Console-driven diagnostics.
* Dry-run field reset testing.
* Safe NPC field correction workflows.
* Integration of selected script-side logic from Hyper138’s NPC Crop Control approach.
* Keeping GUI work out of scope until the script-side behaviour is stable.

---

# Command Summary

```text
ccoWhichConfig
  Shows which configuration file/profile is active.

ccoExplain <FRUITTYPE>
  Explains the effective policy for a specific crop.

ccoListRules
  Lists active crop policy rules.

ccoSetCrop <FRUITTYPE> <OPTION> <VALUE>
  Sets or overrides a crop policy option from the console.

ccoReload
  Reloads XML configuration.

ccoScanFields
  Scans current field crop usage.

ccoScanBlocked
  Scans for NPC fields violating crop policy.

ccoResetNpcFields
  Resets NPC fields violating crop policy.

ccoResetNpcFields <FRUITTYPE>
  Resets NPC fields using a specific crop.

ccoResetNpcFields dryrun
  Previews reset behaviour without changing fields.

ccoResetNpcFields <FRUITTYPE> dryrun
  Previews reset behaviour for a specific crop.
```

---

# Version

```text
FS25_CropControlOverride v2.0.0-alpha
```

Branch:

```text
2.0.0-alpha
```

Status:

```text
Experimental pre-release
```

---

# Licence

Add licence information here.

```
```
