# FS25 Crop Control Override

**Version:** 2.0.0-alpha.90  
**Game:** Farming Simulator 25  
**Type:** Script mod / crop policy manager

Crop Control Override lets you manage which crops are available to the player and which crops NPC farmers are allowed to use. It supports per-save crop rule files, NPC crop validation, blocked-field reporting, and an editable in-game GUI.

This is an alpha build of the 2.0.0 line. It is suitable for testing, but keep backups of important saves.

---

## Key features

- Per-save crop policy XML files.
- Editable FS25-style GUI opened with `ALT+C`.
- Player crop enable/disable rules.
- NPC crop enable/disable rules.
- NPC field-size limits by crop.
- Guarded apply workflow to prevent accidental blocked NPC fields.
- Force Apply workflow for deliberate policy changes.
- Validation tab showing blocked NPC field details and guarded reset actions and guarded reset actions.
- Save Defaults action to export the current active rule set to the template `config.xml`.
- Automatic backup before overwriting template `config.xml`.
- Console commands for diagnostics and cleanup workflows.

---

## Configuration hierarchy

Crop Control Override uses two levels of configuration.

### Template config

```text
modSettings/FS25_CropControlOverride/config.xml
```

This is the default/template rule file. It is used when creating or normalising per-save rule files.

### Per-save config

```text
modSettings/FS25_CropControlOverride/saves/savegameX.xml
```

This is the active rule file for a specific savegame.

The GUI normally edits the active per-save XML. It does **not** automatically overwrite the template config.

---

## Opening the GUI

Default input action:

```text
ALT+C
```

The keybind can be changed from the in-game controls menu if required.

The GUI opens on **ALL RULES**.

---

## GUI tabs

### ALL RULES

Shows all configured crop rules.

Use this tab to select a crop and edit its policy in the right-side details panel.

<<<<<<< HEAD
=======
=======
<img width="3840" height="2160" alt="Screenshot 2026-05-18 151748" src="https://github.com/user-attachments/assets/bed68709-6372-4b09-ab89-bff95cd7944d" />

>>>>>>> 31fb4c7ff0223c0b15a0ffc8dae16ea690cdb116
### DISABLED

Shows crops disabled globally by rule.

A globally disabled crop is unavailable under the crop policy.

### LIMITED

Shows crops with an NPC maximum field-size limit.

A value of `0.00 ha` means no CCO size limit is applied.

### NPC DISABLED

Shows crops that NPCs should not plant.

Globally disabled crops also count as NPC-disabled because they are unavailable to NPCs.

### VALIDATION

Checks the current save against the active crop policy.

If existing NPC fields violate the active rules, this tab lists blocked NPC field details, including field ID, crop, size, and reason.

This tab also provides the guarded cleanup workflow:

```text
RESET BLOCKED DRY-RUN
CONFIRM RESET
```

### SUMMARY

Shows the active config path, rule counts, policy summary, validation status, and config hierarchy notes.

### HELP

Shows in-game guidance for navigation, policy terms, config files, cleanup, and editing.

---

## Editing crop rules

Select a crop row, then use the right-side details panel.

Editable staged values:

- **Player Permitted**
- **NPC Permitted**
- **Max Field (ha)**
- **Reset NPC Fields**

Changes are staged first. They are not written until you use **APPLY**.

### APPLY

Writes the selected staged crop rule to the active per-save XML if validation passes.

After apply, CCO reapplies rules, refreshes the GUI, and reports validation status.

### APPLY BLOCKED

If the staged change would create blocked NPC fields, the first apply is blocked and the XML is not changed.

The button changes to **FORCE APPLY**.

### FORCE APPLY

Writes the staged rule deliberately even if it creates blocked NPC fields.

Use this when you intentionally want to save a new policy and then review/clean up affected NPC fields.

After Force Apply, check the **VALIDATION** tab.

### DISCARD

Resets staged values back to the selected row’s current saved values.

---

## Save Defaults

The **SAVE DEFAULTS TO CONFIG.XML** button is in the right-side details panel.

It exports the current complete active rule set to:

```text
modSettings/FS25_CropControlOverride/config.xml
```

Before overwriting the template config, CCO creates a backup in:

```text
modSettings/FS25_CropControlOverride/backups/
```

Example backup name:

```text
config_backup_YYYYMMDD_HHMMSS.xml
```

Save Defaults does **not** overwrite existing per-save XML files.

---

## Validation and blocked NPC fields

Two concepts are intentionally separate.

### NPC-disabled crops

These are crops the rules say NPCs should not plant.

This is a policy/configuration state.

### Blocked NPC fields

These are existing NPC fields in the current save that already violate the active policy.

This is a save-state validation issue.

Example:

```text
BARLEY NPC Permitted = No
```

If no NPC fields currently contain barley, validation passes.

If an NPC field already contains barley, validation reports a blocked NPC field.

---

## Cleanup workflow

Cleanup remains console-led in this alpha build.

Recommended order:

```text
ccoScanBlocked
ccoResetBlocked dryrun
ccoResetBlocked
```

Use `ccoResetBlocked dryrun` before making save-state changes.

---

## Console commands

### GUI and status

```text
ccoGui
ccoGui rules
ccoGui disabled
ccoGui limited
ccoGui blockedrules
ccoGui blocked
ccoGui help
ccoStatus
ccoWhichConfig
ccoReload
```

### Rule inspection

```text
ccoExplain <CROP>
ccoListRules [CROP]
ccoListConfigured [CROP]
ccoListDisabled
ccoListBlockedRules
ccoListLimited
ccoListUndiscovered
ccoNormalizeConfig [dryrun]
```

### Rule editing

```text
ccoSetCrop <CROP> <enabled:true|false> [npcAllowed:true|false|mapDefault] [npcMaxHa]
```

The GUI is now the preferred editing method for normal use.

### Field scanning and validation

```text
ccoScanFields [CROP]
ccoScanBlocked [CROP]
ccoScanSummary [CROP]
ccoValidateSave
ccoListNpcCandidates <FIELD_ID>
```

### Cleanup

```text
ccoResetBlocked dryrun
ccoResetBlocked
ccoResetNpcFields [CROP|all] [dryrun]
```

### Debug/logging

```text
ccoDebug on|off|toggle
ccoLogLevel DEBUG|INFO|WARN|ERROR
```

NPC replacement and field-blocking detail is logged at DEBUG level.

---

## Notes for alpha testing

- Test on copied saves first.
- Keep backups of important savegames.
- Use the Validation tab after Force Apply.
- Use dry-run cleanup commands before resetting NPC fields.
- Report any GUI rendering issues with screenshots and the relevant log section.

---

## Known future work

- Convert the standalone GUI to a proper in-game menu frame.
- Use native menu button info handling once the menu-frame conversion is done.
- Consider GUI-driven blocked-field cleanup with confirmation prompts.
- Additional localisation polish before ModHub submission.

---

## Changelog

### 2.0.0-alpha.90

- README updated to match the current editable GUI workflow.
- Documented config hierarchy: template `config.xml` vs active per-save XML.
- Documented APPLY / FORCE APPLY / DISCARD workflow.
- Documented SAVE DEFAULTS and automatic backup behaviour.
- Documented Validation tab and blocked NPC field terminology.
- Updated console command documentation.
- No code behaviour changes from alpha.77.

### 2.0.0-alpha.90

- Included the confirmed details-panel placement update: `ruleDetailsPanel position="1080px -50px"`.
- Reduced routine startup/hook/reapply log noise by demoting routine messages to DEBUG.
- Kept important operational APPLY, SAVE DEFAULTS, validation, and cleanup output visible.
- Aligned console wording around NPC-disabled crop rules and blocked NPC fields.

### 2.0.0-alpha.90

- Moved Save Defaults into the right-side details panel.
- Restored footer to navigation/reload/back actions.
- Removed Return/MENU_ACCEPT handling for Save Defaults.

---

## Licence / attribution

This mod is developed for Farming Simulator 25 by SimGamerJen.



### 2.0.0-alpha.90 ModHub TestRunner package refresh

- Replaced `modDesc.xml` with ModHub TestRunner-compliant version supplied by user.
- Replaced DDS icon with ModHub TestRunner-compliant `icon_CropControlOverride.dds`.
- Scripts, GUI, and config files otherwise retained from alpha.88.
