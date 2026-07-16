# FS25 Crop Control Override

**Version:** 2.1.0.0 Alpha 10  
**Game:** Farming Simulator 25  
**Status:** Stable release  
**Author:** SimGamerJen, Hyper138

Crop Control Override is a per-save crop policy manager for Farming Simulator 25. It allows players to control which crops are permitted for the player, which crops NPC farmers may use, and whether NPC crop planting should be limited by field size.

The mod is designed for players who want tighter control over crop realism, map-specific crop suitability, roleplay save rules, NPC field behaviour, and cleanup of NPC fields that no longer match the active crop policy.

## Current stable release

The current recommended release is:

**v2.1.0.0 Alpha 10** from the `feature/npc-map-regeneration` branch.

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
| Reseed Weight | Relative `0–5` chance of this crop being selected during NPC-field reseeding. `0` excludes it from reseeding without disabling it. |

This allows you to create map-specific or region-specific crop rules without editing the map directly.

Examples:

- Disable rice, cotton, sugarcane, or other crops unsuitable for a region.
- Allow the player to use a crop but stop NPC farmers from planting it.
- Allow NPC farmers to use a crop only on smaller fields.
- Validate existing NPC fields after changing policy.
- Reset or reseed NPC fields that no longer comply with the active rules.

---

## Release highlights

Version `2.0.3.5` expands the NPC-field reseed system with per-crop weighting, retains deterministic reseed behaviour, completes the disabled-crop sowing safeguards introduced in 2.0.3.4, and improves German localisation coverage.

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
- Per-crop reseed weights from `0` to `5`.
- A global `leaveCultivated` weight.
- Deterministic weighted reseed selection.
- Dry-run before confirm workflow.
- Diagnostic console commands.
- Multiplayer-aware settings flow for local host and dedicated servers.
- Server-authoritative per-save XML handling for dedicated multiplayer.
- Read-only rule viewing for normal dedicated-server clients.
- Admin/master-user editing support for elevated multiplayer users.
- Immediate removal of disabled crops from compatible sowing-machine selectors.
- Server-authoritative sowing safeguards for players, helpers, and multiplayer clients.
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

### Reseed Weight

Values:

```text
0 / 1 / 2 / 3 / 4 / 5
```

Controls how strongly the selected crop participates in weighted NPC-field reseeding.

- `0` excludes the crop from CCO reseeding.
- `1` gives the crop a very low relative chance.
- `5` gives the crop the highest normal relative chance.
- A crop with weight `0` can still remain enabled for players and NPC policy; only automatic CCO reseeding is excluded.
- The setting is stored per crop in the active savegame XML and is synchronised in multiplayer.

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

CCO uses a per-crop weighting system for NPC-field reseeding.

The only global reseed candidate setting is:

```xml
<settings>
    <reseedCandidateWeights leaveCultivated="1"/>
</settings>
```

Each crop rule stores its own reseed weight:

```xml
<fruits>
    <fruit name="BARLEY"
           enabled="true"
           npcAllowed="mapDefault"
           npcMaxHa="0"
           resetNpcFields="true"
           reseedWeight="5"/>
</fruits>
```

### Per-crop weights

| Value | Behaviour |
|---|---|
| `0` | Never selected by CCO reseeding. The crop itself is not disabled. |
| `1` | Very low relative chance. |
| `2` | Low relative chance. |
| `3` | Medium relative chance. |
| `4` | High relative chance. |
| `5` | Highest normal relative chance. |

Weights are relative. A crop at `5` is five times as likely to be selected as a crop at `1`, provided both crops pass all seasonal, policy, field-size, and compatibility checks.

### Leave cultivated weight

`leaveCultivated` remains a global weighted pseudo-candidate. When selected, the reset field is left cultivated instead of being reseeded.

Example:

```xml
<reseedCandidateWeights leaveCultivated="1"/>
```

With three valid crops weighted `5`, `3`, and `1`, the weighted pool is effectively:

```text
CROP_A x5
CROP_B x3
CROP_C x1
LEAVE_CULTIVATED x1
```

Set `leaveCultivated="0"` to prevent weighted reseed variety from intentionally leaving a field cultivated when valid crop candidates exist.

### Migration from earlier configs

Existing per-save XML files are migrated automatically when loaded:

- missing per-crop `reseedWeight` values default to `5`;
- obsolete `seasonalMission` and `seasonalLifecycle` settings are removed;
- the existing `leaveCultivated` value is retained;
- existing crop permissions and field-size rules are preserved.

The migrated active configuration can be reloaded from disk without restarting FS25 by running:

```text
ccoReload
```

Do not save through the GUI between manually editing the XML and running `ccoReload`, because the currently loaded rules could overwrite the external edits.

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
- Crop has `reseedWeight="0"`.
- Crop is valid but loses deterministic weighted selection.

### A valid crop is not selected often

This is expected when several crops are eligible.

Check the crop's per-save XML rule:

```xml
<fruit name="GRASS" reseedWeight="5"/>
```

Increase or decrease the crop's `reseedWeight` from `0` to `5` to adjust its relative chance. A value of `0` excludes it from CCO reseeding entirely.

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
- Console reset commands do not expose the full GUI reset-mode workflow.
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

### 2.1.0.0 Alpha 10

- Added the full NPC map regeneration workflow to the Validation tab.
- Added preview-first confirmation controls for destructive regeneration.
- UI preview reports planned fields, exclusions, authoritative-state status, and crop distribution.
- Regeneration controls are disabled for read-only multiplayer clients and while regeneration is already running.
- Console regeneration commands remain available for diagnostics.

### 2.1.0.0 Alpha 9.6

- Cleans the validated Alpha 9.5 build into a quieter test baseline.
- Keeps the mission audit summary visible at INFO level.
- Moves per-mission, per-field, and per-crop audit detail to DEBUG level (`ccoLogLevel DEBUG`).
- No intended changes to regeneration, seasonal state resolution, crop selection, field cache refresh, or contract generation.

### 2.1.0.0 Alpha 9.5

- Corrects the diagnostic mission audit so it can resolve field identifiers from numeric fields, nested mission data, field objects, getter methods, and other mission-class layouts.
- Adds one `mission inspect` line per generated mission with mission class, crop, resolved field ID, resolution source, and discovered field-related members.
- Retains Alpha 9.4 regeneration, state resolution, selection, and contract-generation behaviour unchanged.

### 2.1.0.0 Alpha 9.4

- Adds a post-refill mission audit for every regenerated harvest-ready NPC field.
- Reports whether each ready field received a mission, including mission type, mission crop, and natural-versus-fallback state source.
- Adds per-crop and overall totals for ready fields, matched contracts, unmatched ready fields, natural states, and fallback states.
- Diagnostic only: no changes to field regeneration, crop-state resolution, deterministic selection, or mission generation.

### 2.1.0.0 Alpha 9.2

- Preserves planting origins that reached harvest readiness in an earlier period when their final current state remains inside the active harvest range.
- Prevents multi-period harvest crops such as peas and spinach from unnecessarily falling through to the harvest-window fallback.
- Retains Alpha 9.1 origin diagnostics and deterministic hash mixing.

### 2.1.0.0 Alpha 9.1

- Preserves valid natural seasonal `growthMapping` outcomes before considering the harvest-window fallback.
- Adds dry-run diagnostics for natural, replayed, and rejected planting origins and records whether fallback was used.
- Replaces the field-ID-correlated weighted picker with a deterministic rolling hash that better mixes neighbouring field IDs.

### 2.1.0.0 Alpha 9

- Adds an authoritative harvest-window fallback for anomaly crops whose valid planting-origin replays cannot reproduce a standing harvest-ready state.
- The fallback is used only when the current seasonal period is explicitly harvestable and the fruit type provides a valid harvesting-state range.
- Restores eligible crops such as wheat, oats, canola and potatoes to the regeneration pool without reintroducing speculative monthly growth-state estimates.

### 2.1.0.0 Alpha 8.2

- Cleaned and consolidated the validated Alpha 8.1 full-map NPC regeneration implementation.
- Retains authoritative seasonal `growthMapping` replay, planting-period boundary handling, strict harvest-range validation, contract cleanup, field-state refresh and contract-board refill.
- No intended regeneration behaviour change from Alpha 8.1.


### 2.1.0.0 Alpha 8.1

- Applies the selected planting period's own seasonal `growthMapping` before replaying later periods.
- Fixes year-crossing crops such as wheat, barley and canola remaining stuck in their initial state.
- Retains Alpha 8 harvest-range and expired-lifecycle validation.

### 2.1.0.0 Alpha 8

- Tightens seasonal planting-origin validation for full-map NPC regeneration.
- During an active harvest period, only outcomes inside the crop's authoritative harvesting growth-state range are accepted.
- Rejects planting origins that already passed a harvest-ready period and later wrapped back to an early growth state.
- Rejects suspicious long year-crossing lifecycles that return to state 1 or 2 outside a valid planting period.
- Crops with no plausible current standing state are excluded from the regeneration candidate pool.
- Retains the authoritative-state confirmation gate, stale-contract purge, field-state refresh, and contract-board refill.

### 2.1.0.0 Alpha 7

- Replaced elapsed-period growth guesses with authoritative replay of each crop's seasonal `growthMapping` transitions.
- Uses the runtime `isHarvestable` period flag and validates mapped states against each fruit type's harvesting range.
- Evaluates every valid planting origin and selects the most advanced valid current state, preferring harvest-ready outcomes during harvest periods.
- Rejects withered states and harvest states outside the active harvest period.
- Applies authoritative lifecycle handling to grass and other regrowing crops.
- Keeps confirmation blocked only when a selected crop has no complete authoritative mapping path.

### 2.1.0.0 Alpha 6

- Converted full-map NPC regeneration into a guarded diagnostic build while the authoritative seasonal harvest-state source is identified.
- `ccoGrowthProbe CROP` now reports harvest-state metadata, growth-state names and every raw seasonal period entry for the selected crop.
- Dry-run output labels every proposed field action with `authoritative=true|false`.
- `ccoRegenerateNpcFields confirm` is blocked whenever any selected crop state is unverified.
- Grass and other lifecycle crops are resolved before normal planting-period logic.

Diagnostic workflow:

```text
ccoRegenerateNpcFields dryrun
ccoGrowthProbe WHEAT
ccoGrowthProbe OAT
ccoGrowthProbe PEA
ccoGrowthProbe CANOLA
ccoGrowthProbe GRASS
```

Upload the probe sections from `log.txt`. Do not use `confirm` unless the dry-run reports `confirmAllowed=true`.

### 2.1.0.0 Alpha 5

- Uses each fruit type's authoritative `minHarvestingGrowthState` and `maxHarvestingGrowthState` when the current calendar period is harvestable.
- Keeps crops in intermediate calendar periods below the harvesting range rather than advancing one raw foliage state per month.
- Places permanent/regrowing crops such as grass at an established usable state instead of growth state 1.
- Refreshes regenerated `FieldState` caches after field tasks settle and before rebuilding contracts.
- Retains stale-contract removal and repeated native contract-board refill from Alpha 4.

### 2.1.0.0 Alpha 3

- Refuses full-map regeneration while any accepted or active contract exists.
- Deletes all unaccepted/generated contracts before changing NPC fields so stale mission records cannot survive into the savegame.
- Suspends automatic contract generation while the asynchronous field update tasks are being applied.
- Waits five seconds after queueing the field tasks before starting fresh mission generation against the regenerated field states.
- Adds staged log output for stale-contract removal, field-task queueing, and fresh mission generation.
- Keeps the Alpha 1 crop-selection and growth-state logic unchanged for focused contract-lifecycle testing.


### 2.1.0.0 Alpha 1

This alpha introduces an experimental, console-first full-map NPC field regeneration workflow. It is intentionally separate from the existing blocked-field repair feature.

Commands:

```text
ccoRegenerateNpcFields dryrun
ccoRegenerateNpcFields confirm
ccoRegenerateNpcFields clear
```

The dry-run builds and arms an exact field-by-field plan using enabled NPC crops, field-size rules, each crop's `reseedWeight`, and the global `leaveCultivated` weight. Selection is deterministic, so confirmation applies the same plan that was previewed. The plan expires if the seasonal period or year changes.

For each crop, CCO first looks for an explicit growth state in the runtime seasonal data. If none is exposed, it derives a conservative state from the most recent planting window and the crop's available harvesting/foliage states. Crops without a plausible current state are excluded rather than being placed at growth state 1 outside their normal lifecycle.

This is an alpha feature and should be tested on a backed-up save. The existing `RESET BLOCKED` workflow remains unchanged.

### 2.0.3.5

- Replaced category-based reseed weighting with an individual `0–5` weight for every configured crop.
- Added the Reseed Weight control to the crop-rule details pane.
- Defined `0` as an explicit reseed exclusion without disabling the crop itself.
- Retained `leaveCultivated` as the global weighted option for leaving some reset fields cultivated.
- Removed the obsolete `seasonalMission` and `seasonalLifecycle` weighting settings.
- Added per-crop reseed-weight persistence to active savegame XML files.
- Added multiplayer synchronisation for per-crop reseed weights.
- Added automatic migration for existing configs, defaulting missing crop weights to `5`.
- Prevented fallback reseed selection from bypassing crops configured with weight `0`.
- Added and translated new reseed-weight UI text.
- Completed a broader German localisation pass across the GUI and gameplay messages.

### 2.0.3.4

- Removed disabled player crops immediately from compatible sowing-machine seed selectors.
- Restored re-enabled crops without requiring a savegame reload.
- Added server-authoritative sowing and direct-sowing safeguards.
- Prevented stale selections, helpers, multiplayer clients, and compatible third-party worker systems from planting disabled crops.
- Stopped active AI fieldwork when a prohibited crop is selected and displayed a centre-screen warning.
- Improved multiplayer rule delivery with server push, client retry handling, and deferred client policy application.
- Added and completed French localisation support.

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

