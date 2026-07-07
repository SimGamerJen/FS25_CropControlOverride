# FS25 Crop Control Override

**Version:** 2.0.1.7  
**Game:** Farming Simulator 25  
**Status:** Stable release  
**Author:** SimGamerJen, Hyper138

Crop Control Override is a per-save crop policy manager for Farming Simulator 25. It allows players to control which crops are permitted for the player, which crops NPC farmers may use, and whether NPC crop planting should be limited by field size.

The mod is designed for players who want tighter control over crop realism, map-specific crop suitability, roleplay save rules, NPC field behaviour, and cleanup of NPC fields that no longer match the active crop policy.

## Current stable release

The current recommended release is:

**v2.0.1.7** from the main branch.

Older alpha and beta releases are retained for history only.

---

## Contents

- [What this mod does](#what-this-mod-does)
- [Release highlights](#release-highlights)
- [Installation](#installation)
- [Opening the GUI](#opening-the-gui)
- [Important concepts](#important-concepts)
- [GUI overview](#gui-overview)
- [Crop rule settings](#crop-rule-settings)
- [Multiplayer support](#multiplayer-support)
- [Validation and blocked NPC fields](#validation-and-blocked-npc-fields)
- [Reset modes](#reset-modes)
- [RESEED SEASONAL and candidate selection](#reseed-seasonal-and-candidate-selection)
- [Reseed weighting XML](#reseed-weighting-xml)
- [Configuration files](#configuration-files)
- [Recommended workflows](#recommended-workflows)
- [Console commands](#console-commands)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [Screenshot checklist](#screenshot-checklist)
- [Changelog](#changelog)

---

## What this mod does

Crop Control Override gives each savegame its own crop policy file. For every crop known to the mod, you can control:

| Setting | Purpose |
|---|---|
| Player Permitted | Whether the crop is available to the player. |
| NPC Permitted | Whether NPC farmers may use the crop. |
| Max Field Size | Optional maximum field size for NPC use of that crop. |
| Reset NPC Fields | Whether blocked NPC fields of that crop may be reset by the cleanup tools. |

This allows you to create map-specific or region-specific crop rules without editing the map directly.

Examples:

- Disable rice, cotton, sugarcane, or other crops unsuitable for a region.
- Allow the player to use a crop but stop NPC farmers from planting it.
- Allow NPC farmers to use a crop only on smaller fields.
- Validate existing NPC fields after changing policy.
- Reset or reseed NPC fields that no longer comply with the active rules.

---

## Release highlights

Version `2.0.1.7` builds on the stable 2.0.0 release with dedicated-server multiplayer support, server-authoritative rule synchronisation, admin/master-user edit permissions, external l10n support, and the NPC crop planning hook update introduced during the multiplayer hotfix cycle.

Key features:

- FS25-style custom GUI.
- Per-save XML configuration.
- Native selector controls for editable rule values.
- Crop table terminology aligned to the details pane:
  - `Player`: `ON / OFF`
  - `NPC`: `Map Default / ON / OFF`
  - `Loaded`: `Yes / No`
- `NOT LOADED` crop visibility toggle.
- Field-level blocked reset scope.
- `RESET MODE` support:
  - `CULTIVATED`
  - `RESEED SEASONAL`
- Seasonal reseed candidate detection using FS25 growth data.
- GRASS lifecycle reseed support.
- XML-configurable reseed candidate weights.
- Weighted deterministic reseed variety.
- Dry-run before confirm workflow.
- Diagnostic console commands.
- Multiplayer-aware settings flow for local host and dedicated servers.
- Server-authoritative per-save XML handling for dedicated multiplayer.
- Read-only rule viewing for normal dedicated-server clients.
- Admin/master-user editing support for elevated multiplayer users.
- External l10n file support for community translations.

---

## Installation

1. Download the mod ZIP.
2. Place the ZIP in your Farming Simulator 25 mods folder.
3. Enable the mod in your savegame.
4. Load the save.
5. Open the Crop Control Override GUI with `ALT+C`.

Typical Windows mod folder:

```text
Documents/My Games/FarmingSimulator2025/mods
```

Do not unzip the mod for normal gameplay use.

---

## Opening the GUI

Default keybind:

```text
ALT+C
```

The keybind can be changed in the Farming Simulator controls menu.

You can also open the GUI from the console:

```text
ccoGui
```

<img width="3840" height="2160" alt="CCO v2.0.x all rules" src="https://github.com/user-attachments/assets/b00e0e57-61a6-47db-ab90-568538857f5f" />

---

## Important concepts

### Loaded crops

A crop can exist in the CCO rule list but not be loaded by the current map or mod stack.

The table shows this using the `Loaded` column:

| Loaded | Meaning |
|---|---|
| Yes | The crop is currently loaded by the game/map/mod stack. |
| No | The crop is in the CCO config but is not currently loaded. |

The `NOT LOADED` visibility toggle lets you show or hide crops that are present in the XML but not currently active in the save.

### Player policy vs NPC policy

Player and NPC permissions are separate.

Example:

| Player | NPC | Meaning |
|---|---|---|
| ON | Map Default | Player can use the crop. NPC behaviour follows map/default behaviour. |
| ON | OFF | Player can use the crop. NPCs should not plant it. |
| OFF | OFF | Crop is disabled from player and NPC use. |

### Map Default

`Map Default` means CCO does not force a specific NPC permission for that crop. The crop follows the map/game/default behaviour unless another CCO rule, field-size rule, or reset workflow applies.

---

## GUI overview

### ALL RULES

Shows all configured crop rules.

Use this tab to select a crop and edit its policy in the details pane.

<img width="3840" height="2160" alt="CCO v2.0.x selected crop" src="https://github.com/user-attachments/assets/042f22eb-5eeb-4652-8b4f-b6dd47718b6e" />

### DISABLED

Shows crops where Player Permitted is `OFF`.

### SIZE LIMITED

Shows crops with an NPC Max Field Size greater than zero.

### NPC DISABLED

Shows crops where NPC Permitted is `OFF`.

### VALIDATION

Shows NPC fields that violate the active crop policy.

This is the most important tab when changing NPC rules or field-size limits.

<img width="3840" height="2160" alt="CCO v2.0.x validation blocked fields" src="https://github.com/user-attachments/assets/285f6ed4-956b-4031-8146-e94d11d6c6fa" />

### SUMMARY

Shows the active configuration path, rule counts, and validation summary.

### HELP

Shows in-game guidance.

---

## Crop rule settings

When you select a crop, the right-hand details pane exposes editable settings.

### Player Permitted

Values:

```text
OFF / ON
```

Controls whether the crop is permitted for player use.

### NPC Permitted

Values:

```text
Map Default / ON / OFF
```

Controls whether NPC farmers may use the crop.

### Max Field (ha)

Sets a maximum NPC field size for the crop.

- `0` means no CCO size limit.
- Any value above `0` limits NPC use to fields at or below that size.
- The table displays both hectares and acres for readability.

Example:

```text
5.0ha / 12.4ac
```

### Reset NPC Fields

Values:

```text
OFF / ON
```

Controls whether CCO cleanup tools may reset blocked NPC fields of this crop.

If this is `OFF`, blocked fields of that crop are not reset by the reset workflow.

---

## Multiplayer support

CCO supports single-player, local hosted multiplayer, and dedicated/cloud multiplayer. The mod uses different authority rules depending on how the save is being run.

| Mode | XML authority | GUI access | Expected behaviour |
|---|---|---|---|
| Single-player | Local player PC | Editable | Uses local `modSettings/FS25_CropControlOverride/config.xml` and the active local per-save XML. |
| Local hosted multiplayer | Host PC | Host editable; joined clients server-synced | The host remains the authority. Joined clients receive the host/server rule state and should not own the rules independently. |
| Dedicated/cloud server | Server | Admin/master users editable; normal players read-only | The dedicated server owns the active per-save XML. Remote clients display a server-synchronised in-memory copy. |

### Dedicated server rule ownership

On a dedicated or cloud-hosted server, CCO treats the server as the only source of truth. The server loads or creates its own active per-save XML and sends the current ruleset to joining clients.

Remote clients should not load, create, or overwrite local CCO save files while connected to a dedicated server. In particular, a cloud-server session should not create local files such as:

```text
modSettings/FS25_CropControlOverride/saves/savegame0.xml
modSettings/FS25_CropControlOverride/saves/savegame1.xml
```

The client GUI uses the server-sent rules in memory only. This prevents dedicated-server rules from overwriting local single-player or local-hosted multiplayer files.

### Multiplayer editing permissions

Normal dedicated-server players can open CCO and view the active server rules, but the rule controls are read-only.

Players who elevate to admin/master-user status through the Farming Simulator multiplayer admin/Farm Management controls can update crop rules. Even for an elevated remote admin, changes are still sent to the server and saved server-side. The remote client does not write local CCO XML.

Admin-edit flow:

```text
Remote admin opens CCO
↓
Client displays the server-synchronised ruleset
↓
Admin changes a rule and clicks APPLY
↓
Request is sent to the server
↓
Server validates admin/master-user permission
↓
Server updates the active server-side savegame XML
↓
Server broadcasts the refreshed ruleset back to clients
```

### Multiplayer safety guarantees

The multiplayer support is designed to preserve existing local behaviour:

- Single-player saves continue to use local per-save XML files.
- Local hosted multiplayer continues to use the host machine as the file authority.
- Dedicated-server clients use server-synchronised rules and do not create local per-save CCO XML files.
- Normal multiplayer players can view rules but cannot change them.
- Admin/master-user edits are validated by the server before the server XML is changed.

---

## Validation and blocked NPC fields

A blocked NPC field is an NPC-owned field that no longer complies with the active CCO rules.

Common causes:

- The crop has been disabled.
- NPC use has been disabled for the crop.
- The crop has a Max Field limit and the field is too large.
- The crop remains in the field after changing rules.

Validation checks existing NPC fields and reports fields that need attention.

Example validation reason:

```text
field 6.81 ha > max 5.00 ha
```

The validation screen supports scoped cleanup, so you do not have to reset every blocked field at once.

Reset scopes include:

```text
ALL
CROP: <crop>
FIELD: <field id> <crop>
```

<img width="3840" height="2160" alt="CCO v2.0.x reset scope" src="https://github.com/user-attachments/assets/0fb38e86-5dfc-410c-bbda-8783ce0d3eef" />

---

## Reset modes

The Validation screen includes `RESET MODE`.

Available modes:

```text
CULTIVATED
RESEED SEASONAL
```

### CULTIVATED

Blocked NPC fields are cleared and reset to cultivated state.

This is the safest cleanup behaviour and matches the earlier reset workflow.

Dry-run example:

```text
resetMode=CULTIVATED action=CULTIVATED reseedCandidate=NONE
```

### RESEED SEASONAL

Blocked NPC fields are reset and then reseeded using a replacement crop selected by the seasonal candidate engine.

Dry-run example:

```text
resetMode=RESEED SEASONAL action=RESEED_SEASONAL reseedCandidate=GRASS
```

If no suitable seasonal candidate is available, CCO falls back to cultivated reset.

Fallback example:

```text
action=CULTIVATED_FALLBACK
```

If the weighted reseed variety chooses to leave a field cultivated, dry-run reports:

```text
action=CULTIVATED_VARIETY
```

<img width="3840" height="2160" alt="CCO v2.0.x reset mode" src="https://github.com/user-attachments/assets/f4bcc844-cb06-49d5-9827-b611c77d5ece" />

---

## RESEED SEASONAL and candidate selection

`RESEED SEASONAL` uses the current game period and crop growth data to find suitable replacement crops.

The seasonal check uses:

```text
growthDataSeasonal.periods[currentPeriod].plantingAllowed
```

A crop must generally pass:

- Crop is loaded.
- Crop is seedable.
- Crop is allowed by CCO player/NPC policy.
- Crop passes Max Field limits.
- Crop is seasonally plantable in the current period.
- Crop is not in the special exclusion list.

### Candidate categories

Candidate diagnostics classify crops as:

| Category | Meaning |
|---|---|
| mission | Standard seasonal field/mission crop. |
| lifecycle | Lifecycle crop allowed for reseed, currently GRASS. |
| blocked | Not eligible as an automatic reseed candidate. |

Example candidate output:

```text
CANOLA OK category=mission reason=allowed seasonal=OK
GRASS  OK category=lifecycle reason=allowed seasonal=OK
```

### Special exclusions

The following crop types are deliberately excluded from automatic reseed candidates for now:

```text
GRAPE
OLIVE
POPLAR
MEADOW
OILSEEDRADISH
RICE
RICELONGGRAIN
```

These may require special handling and should not be injected into ordinary NPC field cleanup automatically.

---

## Reseed weighting XML

CCO supports XML-configurable reseed weighting.

The default bundled config includes:

```xml
<settings>
    <reseedCandidateWeights seasonalMission="5" seasonalLifecycle="5" leaveCultivated="1"/>
</settings>
```

Meaning:

| Attribute | Purpose |
|---|---|
| seasonalMission | Weight for normal seasonal mission crops, such as CANOLA. |
| seasonalLifecycle | Weight for lifecycle crops, currently GRASS. |
| leaveCultivated | Weight for leaving a reset field cultivated instead of reseeding it. |

Values are clamped from `0` to `20`.

Weighted selection is deterministic by field ID. This means the dry-run result should match the confirmed reset result.

### Default weighting

```xml
<reseedCandidateWeights seasonalMission="5" seasonalLifecycle="5" leaveCultivated="1"/>
```

With CANOLA and GRASS both valid, the weighted pool is effectively:

```text
CANOLA x5
GRASS x5
LEAVE_CULTIVATED x1
```

This creates a mostly reseeded map while occasionally leaving a field cultivated.

### Clean map preset

Always reseed where possible:

```xml
<reseedCandidateWeights seasonalMission="5" seasonalLifecycle="5" leaveCultivated="0"/>
```

### Rougher map preset

Leave more fields cultivated after reset:

```xml
<reseedCandidateWeights seasonalMission="4" seasonalLifecycle="4" leaveCultivated="2"/>
```

### Prefer arable crops over grass

```xml
<reseedCandidateWeights seasonalMission="6" seasonalLifecycle="2" leaveCultivated="1"/>
```

### Prefer grass/lifecycle recovery

```xml
<reseedCandidateWeights seasonalMission="3" seasonalLifecycle="6" leaveCultivated="1"/>
```

---

## Configuration files

CCO uses a template/default config and per-save configs.

The active per-save config is stored under:

```text
modSettings/FS25_CropControlOverride/saves/savegameXX.xml
```

The template/default config is stored under:

```text
modSettings/FS25_CropControlOverride/config.xml
```

### Per-save behaviour

When a savegame is loaded, CCO uses the per-save XML if it exists. If it does not exist, CCO creates one from the template config.

This prevents rules for one savegame from unexpectedly changing another savegame.

### Multiplayer file behaviour

In single-player and local hosted multiplayer, the local machine or host machine owns the CCO XML files.

In dedicated/cloud multiplayer, the dedicated server owns the XML files. Remote clients receive the active ruleset from the server and keep it in memory for display. They should not create or update local CCO per-save XML files during that session.

Use `ccoWhichConfig` from the server or host environment when you need to confirm the active file path. On a normal remote client, the GUI reflects the server-synchronised rules rather than a local savegame XML.

### Save Defaults to config.xml

The GUI option `SAVE DEFAULTS TO CONFIG.XML` writes the current active rule set to the template config.

Existing per-save XML files are not overwritten.

### Load Defaults

The GUI option `LOAD DEFAULTS` loads the template config into the active save config.

Use this carefully because it updates the active save’s CCO XML.

---

## Recommended workflows

### Change a crop rule safely

1. Open the GUI with `ALT+C`.
2. Go to `ALL RULES`.
3. Select the crop.
4. Change the desired settings in the details pane.
5. Click `APPLY`.
6. If validation blocks the change, review the warning.
7. Use `FORCE APPLY` only if you intend to allow blocked fields temporarily.
8. Go to `VALIDATION` to review affected NPC fields.

### Change rules on a dedicated server

1. Join the server.
2. Open CCO with `ALT+C`.
3. If you are a normal player, the rules should display as read-only.
4. Elevate to admin/master-user status through the Farming Simulator multiplayer admin/Farm Management controls.
5. Reopen or refresh CCO if needed.
6. Change the rule and click `APPLY`.
7. Confirm the server-side CCO savegame XML updates.
8. Confirm no local client-side CCO `savegame?.xml` file has been created.

### Reset blocked fields to cultivated

1. Go to `VALIDATION`.
2. Choose `RESET SCOPE`.
3. Set `RESET MODE` to `CULTIVATED`.
4. Run `RESET BLOCKED DRY-RUN`.
5. Review the output.
6. Click `CONFIRM RESET`.

### Reseed blocked fields seasonally

1. Go to `VALIDATION`.
2. Choose `RESET SCOPE`.
3. Set `RESET MODE` to `RESEED SEASONAL`.
4. Run `RESET BLOCKED DRY-RUN`.
5. Confirm the candidates look sensible.
6. Click `CONFIRM RESET`.

Expected dry-run example:

```text
field=24 action=RESEED_SEASONAL reseedCandidate=CANOLA
field=65 action=RESEED_SEASONAL reseedCandidate=GRASS
field=77 action=CULTIVATED_VARIETY reseedCandidate=NONE
```

Expected confirm example:

```text
queued field 24 to reseeded crop CANOLA
queued field 65 to reseeded crop GRASS
queued field 77 to cultivated state
```

---

## Console commands

### GUI and status

```text
ccoGui
ccoStatus
ccoWhichConfig
ccoReload
ccoHelp
```

### Rule listing

```text
ccoListRules [CROP]
ccoListConfigured [CROP]
ccoListDisabled
ccoListBlockedRules
ccoListLimited
ccoListUndiscovered
```

### Validation and scanning

```text
ccoValidateSave
ccoScanFields [CROP]
ccoScanBlocked [CROP]
ccoScanSummary
```

### Reset commands

```text
ccoResetBlocked dryrun
ccoResetBlocked
ccoResetNpcFields [CROP|all] [dryrun]
```

The GUI reset workflow is preferred for scoped reset and reseed mode control.

### Candidate diagnostics

```text
ccoListNpcCandidates <FIELD_ID>
ccoSeasonProbe [CROP]
ccoGrowthProbe [CROP]
```

Example:

```text
ccoListNpcCandidates 87
```

Output may include:

```text
CANOLA OK category=mission reason=allowed seasonal=OK
GRASS  OK category=lifecycle reason=allowed seasonal=OK
```

### Crop flags and diagnostics

```text
ccoListFlags [CROP]
ccoFindFruit <namePart>
ccoExplain <CROP>
```

---

## Troubleshooting

### ALT+C does not open the GUI

Check the game log for Lua errors.

If the mod fails to compile or load, the GUI cannot register.

Look for lines like:

```text
Lua compiler error
CCO GUI: custom screen failed
CropControlOverrideMenu class is not available
```

### The GUI opens but shows fallback console output

This usually means the XML GUI or GUI class failed to load.

Check:

- The mod ZIP structure.
- `gui/CropControlOverrideMenu.xml`.
- `scripts/gui/CropControlOverrideMenu.lua`.
- The game log for stack traces.

### Dedicated server client sees default/local rules

On a dedicated server, remote clients should display the server-synchronised ruleset, not their own local `config.xml` or local per-save XML.

Check the game log for CCO sync messages and confirm the client is running the same mod version as the server. A normal remote client should not create a local CCO `savegame0.xml` when joining a dedicated server.

### Dedicated server GUI is read-only

This is expected for normal players. Rule changes are restricted to admin/master users.

To edit rules on a dedicated server, elevate privileges through the Farming Simulator multiplayer admin/Farm Management controls, then reopen or refresh CCO. Changes are still saved by the server, not by the remote client.

### Changes apply to config.xml but not the save XML

The active target should normally be:

```text
modSettings/FS25_CropControlOverride/saves/savegameXX.xml
```

Use:

```text
ccoWhichConfig
```

to confirm which file is active.

### A crop is not offered as a reseed candidate

Run:

```text
ccoListNpcCandidates <FIELD_ID>
```

Reasons may include:

- Crop is not loaded.
- Crop is not seedable.
- Crop is blocked by CCO policy.
- Crop exceeds Max Field limit.
- Crop is not seasonally plantable.
- Crop is specially excluded.
- Crop is valid but loses deterministic weighted selection.

### GRASS is valid but not always selected

This is expected.

GRASS is a lifecycle candidate. It participates in weighted deterministic selection alongside seasonal mission crops.

Check the XML weights:

```xml
<reseedCandidateWeights seasonalMission="5" seasonalLifecycle="5" leaveCultivated="1"/>
```

Increase `seasonalLifecycle` if you want GRASS selected more often.

### Dry-run and confirm do not match

This should not happen under normal conditions.

Possible causes:

- The field state changed between dry-run and confirm.
- Another mod changed the field.
- The save was reloaded with different XML weights.
- The crop candidate set changed.

Run dry-run again immediately before confirm.

---

## Known limitations

- `RESEED SEASONAL` only targets blocked NPC fields in the selected reset scope.
- Player-owned fields are not reset by NPC cleanup.
- Some crop types are excluded from automatic reseed because they may require special handling.
- The GUI does not yet expose reseed weights directly; edit XML manually.
- Console reset commands do not expose the full GUI reset-mode workflow.
- Candidate weighting is category-based, not per-crop.
- Seasonal logic depends on FS25 crop growth data being available for the loaded crop.
- Modded crops may behave differently depending on how their fruit type data is defined.
- Dedicated-server clients depend on the server-synchronised ruleset; if the server/client mod versions differ, GUI state may not match.
- Remote multiplayer editing requires admin/master-user elevation. Normal players are intentionally read-only.

---

## Screenshot checklist

Use these markers to add screenshots later.

### Suggested screenshots

1. `docs/screenshots/cco_all_rules.png`
   - Main crop table on ALL RULES.

2. `docs/screenshots/cco_all_rules_selected.png`
   - Crop selected, details pane visible.

3. `docs/screenshots/cco_not_loaded_toggle.png`
   - NOT LOADED crops shown/hidden.

4. `docs/screenshots/cco_validation_blocked.png`
   - VALIDATION tab with blocked fields.

5. `docs/screenshots/cco_reset_scope.png`
   - RESET SCOPE button showing ALL / CROP / FIELD.

6. `docs/screenshots/cco_reset_mode.png`
   - RESET MODE showing CULTIVATED / RESEED SEASONAL.

7. `docs/screenshots/cco_dry_run_reseed.png`
   - Dry-run output with CANOLA / GRASS / CULTIVATED_VARIETY.

8. `docs/screenshots/cco_summary.png`
   - SUMMARY tab.

9. `docs/screenshots/cco_help.png`
   - HELP tab.

### Markdown screenshot marker format

Use this pattern:

```markdown
<!-- SCREENSHOT: short description -->
<!-- Suggested file: docs/screenshots/example.png -->
![Screenshot placeholder - description](docs/screenshots/example.png)
```

---

## Changelog

### 2.0.1.7

- Added dedicated/cloud multiplayer support with server-authoritative rule synchronisation.
- Added remote client protection so dedicated-server clients do not create or update local CCO per-save XML files.
- Added read-only GUI behaviour for normal dedicated-server players.
- Added admin/master-user permission support for elevated multiplayer users.
- Added server-side validation before accepting multiplayer rule changes.
- Updated NPC crop planning logic to use the FS25 planned-fruit hook rather than the older mission-generation approach.
- Reduced contract-list side effects by avoiding global NPC mission flag mutation for NPC-only blocking.
- Added defensive handling around NPC crop replacement logic.
- Added external l10n file support for translations.
- Fixed input-binding localisation fallback.
- Fixed dedicated-client server sync timing and GUI wait-state behaviour.
- Fixed permission hook load order.

### 2.0.0

- Promoted the beta branch to the main stable release.
- Added native selector controls.
- Added NOT LOADED crop visibility toggle.
- Added field-level reset scope.
- Added RESET MODE.
- Added RESEED SEASONAL.
- Added seasonal reseed candidate detection.
- Added GRASS lifecycle reseed candidate support.
- Added XML-configurable reseed candidate weights.
- Added CULTIVATED_VARIETY weighted pseudo-candidate.
- Added deterministic weighted reseed selection.
- Updated validation, dry-run, confirm, and diagnostic output.

---

## Disclaimer

Use a backup save when making significant crop policy changes, resetting blocked NPC fields, or using reseed workflows. CCO changes active save configuration and can alter NPC field states when reset tools are confirmed.

