# FS25 Crop Control Override

**Crop Control Override (CCO)** gives players direct control over which crops can be planted, grown, harvested, shown in the UI, and used by NPC fields and contracts in Farming Simulator 25.

This branch contains the **2.1.0.0 Alpha 10** implementation of full NPC field regeneration.

> **Alpha warning**
>
> This is an experimental build intended for testing on copied or backed-up savegames. NPC regeneration deliberately replaces crops and field states across all unowned fields and rebuilds the available contract board.

---

## Current Alpha Version

**2.1.0.0 Alpha 10**

This alpha adds:

- full NPC field regeneration from the in-game UI;
- preview and confirmation workflow;
- per-crop reseed weighting;
- per-crop NPC field-size limits;
- seasonally valid growth-state reconstruction;
- harvest-window fallback for anomaly crops;
- stale-contract cleanup;
- repeated native contract-board regeneration;
- mission auditing and DEBUG diagnostics;
- multiplayer-aware permission and authority checks.

---

## Main Features

### Crop Control

CCO can control whether each crop is:

- enabled;
- available to NPCs;
- available for sowing;
- available for harvesting;
- available for growth;
- shown in the price table;
- used for field jobs;
- subject to a maximum NPC field size;
- weighted for NPC reseeding.

These settings are persisted per savegame.

### Per-Crop Reseed Weighting

Each crop can be assigned a reseed weight.

Typical values:

- `0` — exclude the crop from NPC regeneration;
- `1` — rare;
- `2–3` — occasional;
- `4–5` — common.

The effective weighting is combined with the crop’s enabled state, NPC permission, and maximum field-size rule.

### Leave Cultivated Weighting

CCO can also include a weighted chance for an NPC field to remain cultivated rather than receive a crop.

This provides a more varied and believable map state after regeneration.

---

## NPC Field Regeneration

Alpha 10 adds full-map NPC regeneration to the **Validation** tab of the CCO interface.

### Preview NPC Regeneration

Use **Preview NPC Regeneration** to build a regeneration plan without changing the savegame.

The preview evaluates every unowned field and reports:

- total NPC fields found;
- fields included or excluded;
- proposed crop distribution;
- authoritative and unverified states;
- restrictions preventing confirmation.

The preview is deterministic. Confirming applies the same plan that was shown.

### Confirm NPC Regeneration

Once a valid preview has been generated, **Confirm NPC Regeneration** applies the plan.

CCO will:

1. regenerate every eligible unowned field;
2. leave player-owned fields unchanged;
3. remove stale unaccepted contracts;
4. wait for field-update tasks to settle;
5. refresh regenerated field-state caches;
6. repeatedly request new native contracts;
7. stop only after several consecutive empty generation cycles;
8. report a concise mission audit summary.

### Safety Restrictions

Regeneration is blocked when:

- an accepted or active contract exists;
- regeneration is already running;
- the preview contains unverified crop states;
- the player does not have permission to edit CCO rules;
- the game instance is not the authoritative server or host.

---

## Seasonal Growth-State Resolution

CCO reconstructs a suitable crop state from the map’s active seasonal growth data.

The resolver supports:

- planting-period detection;
- seasonal `growthMapping` replay;
- the planting period’s own growth transition;
- year-crossing crop lifecycles;
- multi-period harvest windows;
- regrowing lifecycle crops such as grass;
- rejection of expired, withered, wrapped, or post-harvest states.

### Harvest-Window Fallback

Some crops do not replay cleanly from their planting origins even when the map says they are currently harvestable.

For these crops, CCO can use an authoritative harvest-window fallback when:

- the current period is explicitly harvestable;
- natural replay produces no valid current state;
- the crop has a valid harvesting-state range;
- the crop is eligible for field missions.

This allows crops such as:

- wheat;
- oats;
- canola;
- potatoes;

to appear correctly as harvest-ready during their active harvest periods.

---

## Contract Rebuilding

After NPC regeneration, CCO rebuilds the available contract board.

The process:

- removes stale unaccepted contracts;
- preserves safety around accepted contracts;
- waits for field updates to complete;
- refreshes field caches;
- repeatedly invokes native mission generation;
- requires several consecutive empty cycles before stopping.

The native Farming Simulator mission system still decides which eligible fields receive contracts.

A harvest-ready field does **not** automatically guarantee that a contract will be generated for that field.

---

## Mission Audit

At normal INFO logging level, CCO reports a concise summary such as:

```text
CCO [INFO] mission audit summary harvestReadyFields=52 readyWithMission=12 readyWithoutMission=40 naturalReady=34 naturalContracts=7 fallbackReady=18 fallbackContracts=5 totalMissions=14 unmatchedMissionFields=2
```

For detailed diagnostics, enable DEBUG logging:

```text
ccoLogLevel DEBUG
```

DEBUG logging includes:

- generated mission inspection;
- mission field-ID resolution;
- per-field contract matching;
- per-crop contract totals;
- natural-versus-fallback comparisons.

---

## Console Commands

The GUI is the recommended workflow, but the console commands remain available.

### NPC Regeneration

```text
ccoRegenerateNpcFields dryrun
```

Builds and logs a regeneration plan without modifying the savegame.

```text
ccoRegenerateNpcFields confirm
```

Applies the currently armed authoritative plan.

```text
ccoRegenerateNpcFields clear
```

Clears the pending regeneration plan.

### Growth Diagnostics

```text
ccoGrowthProbe CROP
```

Example:

```text
ccoGrowthProbe WHEAT
```

Displays seasonal runtime data for the selected crop, including:

- planting periods;
- harvestable periods;
- growth mappings;
- harvesting-state range;
- crop lifecycle metadata.

### Logging

```text
ccoLogLevel INFO
ccoLogLevel DEBUG
```

Use DEBUG only when investigating a problem, as it can generate substantial log output.

---

## Multiplayer

NPC regeneration is designed to run only on the authoritative server or host.

Expected behaviour:

- clients receive the regenerated field states;
- only permitted players can preview or confirm;
- server-side savegame XML remains authoritative;
- accepted contracts block regeneration;
- newly generated contracts are rebuilt on the server.

Dedicated-server and multiplayer testing is still an important part of the Alpha 10 validation phase.

---

## Installation

1. Download the Alpha 10 ZIP.
2. Place it in your Farming Simulator 25 mods directory:

```text
Documents/My Games/FarmingSimulator2025/mods
```

3. Do not extract the ZIP.
4. Enable **FS25_CropControlOverride** when loading the savegame.
5. Back up the savegame before testing NPC regeneration.

---

## Savegame Data

CCO stores save-specific rules in the mod settings directory.

Typical location:

```text
Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/
```

Existing crop rules and reseed weights should be retained when upgrading.

When testing alpha builds, keep a copy of:

- the savegame folder;
- the CCO savegame XML;
- the game log.

---

## Recommended Alpha Test Procedure

1. Back up the savegame.
2. Load the save with Alpha 10.
3. Open CCO.
4. Review crop rules and reseed weights.
5. Open the **Validation** tab.
6. Select **Preview NPC Regeneration**.
7. Review the proposed distribution.
8. Confirm only when all states are authoritative.
9. Check fields visually.
10. Review the contract board.
11. Save and reload.
12. Check the game log for errors.

Please verify:

- player fields remain unchanged;
- disabled or NPC-blocked crops are excluded;
- `npcMaxHa` is respected;
- harvest-ready crops appear correctly;
- contracts refer to regenerated crops;
- no stale mission references remain;
- the save reloads cleanly;
- multiplayer clients see the same field and contract state.

---

## Known Alpha Considerations

- Native mission generation does not create a contract for every eligible field.
- Specialist crops may generate harvest, baling, mowing, or other mission types depending on map and crop configuration.
- Custom maps with unusual growth XML may require additional compatibility work.
- The DEBUG mission audit may not resolve every third-party mission class.
- Full dedicated-server validation is still recommended before a stable 2.1.0.0 release.

---

## Reporting Issues

When reporting a problem, include:

- CCO version;
- map name;
- current month and seasonal period;
- single-player, multiplayer, or dedicated server;
- crop involved;
- whether the crop state came from natural replay or fallback;
- whether a contract was expected or generated;
- relevant game-log lines;
- the CCO savegame XML where appropriate.

Useful examples:

```text
ccoGrowthProbe WHEAT
ccoRegenerateNpcFields dryrun
ccoLogLevel DEBUG
```

---

## Alpha Branch

This README describes the feature branch for:

```text
2.1.0.0 Alpha 10
```

The current stable release line remains separate until the regeneration feature has completed wider map, multiplayer, and save/reload testing.

---

## Credits

Crop Control Override is developed for Farming Simulator 25 to provide more precise crop, NPC, field, and mission control than the base game exposes through its standard settings.
