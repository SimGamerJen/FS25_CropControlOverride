# FS25 Crop Control Override

**Version:** 2.0.0-alpha.102
**Game:** Farming Simulator 25  
**Type:** Script mod / crop policy manager

Crop Control Override manages crop availability and NPC crop behaviour on a per-save basis. It lets you control which crops are available, which crops NPC farmers may plant, and whether NPC crops should be limited by actual field size.

This is a beta test build. Use copied saves and keep backups of important savegames.

---

## Key features

- Editable FS25-style GUI opened with `ALT+C`.
- Per-save crop policy XML files.
- Player crop enable/disable rules.
- NPC crop enable/disable rules.
- NPC crop field-size limits using actual field area, with hectares and acres shown in the GUI.
- Colour-coded crop rules table.
- GUI toggle to show or hide not-loaded crop rules.
- Guarded `APPLY` / `FORCE APPLY` workflow.
- `DISCARD` for staged GUI edits.
- `SAVE DEFAULTS TO CONFIG.XML` with automatic backup.
- `LOAD DEFAULTS` to import template `config.xml` into the active save.
- `VALIDATION` tab with blocked NPC field details.
- GUI blocked-field cleanup by `ALL`, `CROP`, or individual `FIELD`.
- Console diagnostics and cleanup commands remain available.

---

## Configuration hierarchy

Crop Control Override uses two levels of configuration.

### Template config

```text
modSettings/FS25_CropControlOverride/config.xml
```

This is the default/template rule file. It is used as the source for new or reset save-level rule sets.

### Per-save config

```text
modSettings/FS25_CropControlOverride/saves/savegameX.xml
```

This is the active rule file for a specific savegame.

Normal GUI editing writes to the active per-save XML.

---

## Opening the GUI

Default input action:

```text
ALT+C
```

The keybind can be changed from the in-game controls menu.

---

## GUI tabs

```text
ALL RULES | DISABLED | NPC DISABLED | SIZE LIMITED | VALIDATION | SUMMARY | HELP
```

### ALL RULES

Main editing view. Select a crop row, stage changes in the right-side panel, then use `APPLY`.

### DISABLED

Shows crops disabled globally by rule.

### NPC DISABLED

Shows crops NPCs should not plant.

### SIZE LIMITED

Shows crops with an NPC maximum field-size limit.

### VALIDATION

Shows existing NPC fields that violate the active policy and provides guarded cleanup controls.

### SUMMARY

Shows active config path, rule counts, policy summary, validation status, and workflow notes.

### HELP

Shows in-game guidance for navigation, editing, config files, policy terms, and cleanup.

---

## Editing crop rules

Editable staged values:

- **Player Permitted**
- **NPC Permitted**
- **Max Field**
- **Reset NPC Fields**

Changes are staged first. They are not written until `APPLY` or `FORCE APPLY`.

### APPLY

Writes the selected staged crop rule to the active per-save XML if the edited crop passes preflight validation.

Preflight validation is crop-specific. Editing one crop is not blocked by unrelated crops that are already invalid.

### FORCE APPLY

If the edited crop would create blocked NPC fields, the first `APPLY` is blocked and the button changes to `FORCE APPLY`.

Use `FORCE APPLY` only when you deliberately want to save the policy and then review cleanup under `VALIDATION`.

### DISCARD

Resets staged values back to the selected row’s current saved values.

---

## Save Defaults and Load Defaults

### SAVE DEFAULTS TO CONFIG.XML

Exports the current full active rule set to:

```text
modSettings/FS25_CropControlOverride/config.xml
```

Before overwriting the template config, CCO creates a backup in:

```text
modSettings/FS25_CropControlOverride/backups/
```

Existing per-save XML files are not overwritten.

### LOAD DEFAULTS

Imports template `config.xml` into the active save and overwrites the active per-save XML.

Use this when you want the current save to return to the template/default crop policy.

---

## Validation and blocked NPC fields

The **VALIDATION** tab lists blocked NPC fields, including:

- field ID
- crop
- actual field size
- blocking reason

Two concepts are intentionally separate:

### NPC-disabled crops

Crops the rules say NPCs should not plant.

### Blocked NPC fields

Existing NPC fields in the current save that already violate the active policy.

---

## GUI cleanup workflow

Blocked NPC field cleanup is available from the **VALIDATION** tab.

Recommended order:

```text
RESET SCOPE
RESET BLOCKED DRY-RUN
CONFIRM RESET
```

### RESET SCOPE

Cycles through available cleanup targets:

```text
ALL
CROP: <crop>
FIELD: <fieldId> <crop>
```

### RESET BLOCKED DRY-RUN

Shows what would be reset for the selected scope.

This does not modify the save state.

### CONFIRM RESET

Only appears after a dry-run finds blocked fields. It performs the reset for the selected scope.

After a reset, reopen `VALIDATION` or run another dry-run after refresh.

---

## Field-size limits

`Max Field` uses actual field area where available.

Farmland or plot area is used only as a last-resort fallback because plots can include yards, roads, woodland, or multiple field pieces.

Diagnostic command:

```text
ccoFieldSizeProbe <FIELD_ID>
```

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

The GUI is the preferred editing method for normal use.

### Field scanning and validation

```text
ccoScanFields [CROP]
ccoScanBlocked [CROP]
ccoScanSummary [CROP]
ccoValidateSave
ccoListNpcCandidates <FIELD_ID>
ccoFieldSizeProbe <FIELD_ID>
```

### Cleanup

```text
ccoResetBlocked dryrun
ccoResetBlocked
ccoResetNpcFields [CROP|all] [dryrun]
```

The GUI cleanup workflow is recommended for normal use.

### Debug/logging

```text
ccoDebug on|off|toggle
ccoLogLevel DEBUG|INFO|WARN|ERROR
```

---

## Testing notes

Please report:

- GUI layout/rendering issues
- crops appearing in the wrong filtered tab
- validation mismatches
- blocked NPC fields not appearing as expected
- Save Defaults or Load Defaults issues
- any case where APPLY does not target `saves/savegameX.xml`
- reset scope issues with `ALL`, `CROP`, or `FIELD`
- log warnings or script errors

Attach the relevant `log.txt` section where possible.

---

## Known future work

- Convert the standalone GUI into a proper in-game menu frame.
- Consider converting Validation output into a selectable table.
- Continue localisation and ModHub readiness polish.
- Wider map/mod crop testing.

---

## Changelog

### 2.0.0-alpha.102

- Cleaned up README for the current GUI workflow.
- Updated in-game HELP, SUMMARY, and VALIDATION wording.
- Replaced legacy console-led cleanup guidance with current GUI reset workflow.
- Clarified Save Defaults vs Load Defaults.
- Clarified actual field size versus farmland/plot size.
- No code behaviour changes from alpha.96.

### 2.0.0-alpha.102

- Fixed RESET BLOCKED DRY-RUN remaining disabled for structured field-level reset scopes.
- Added scope-aware blocked-field counting for GUI reset controls.

### 2.0.0-alpha.102

- Added field-level reset scope.
- RESET SCOPE now supports ALL, CROP, and FIELD targets.

### 2.0.0-alpha.102

- Removed potentially stale remaining-blocked count from reset completion messages.

### 2.0.0-alpha.102

- Added crop-scoped reset.

### 2.0.0-alpha.102

- Fixed field-size checks to prefer actual field area over farmland/plot area.
- Added `ccoFieldSizeProbe`.

### 2.0.0-alpha.102

- Swapped NPC DISABLED and LIMITED tab order.
- Changed APPLY preflight validation to check only the edited crop.
- Replaced GUI RELOAD with LOAD DEFAULTS.

---

## Credits

Developed by SimGamerJen and Hyper138.
