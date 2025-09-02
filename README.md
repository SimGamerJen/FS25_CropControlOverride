# FS25_CropControlOverride

A lightweight Farming Simulator 25 script mod that **overrides crop (fruit) order and disables selected crops** globally — without editing the base game or map XMLs. Configuration is externalised to `modSettings`, with **per-save files** supported.

---

## ✨ What it does

- Enforces a **custom fruit display order** across PDA/price lists/contracts.
- **Disables specified crops** for players and AI contracts.
- Hides disallowed crops from the **economy/price display** and PDA calendar/map.
- Runs at map load; no map editing required.
- Supports **per-save configuration files** that persist separately from the savegame (so they are not deleted when saving).

---

## 📦 Contents

```
FS25_CropControlOverride/
├─ modDesc.xml
└─ scripts/
   └─ CropControlOverride.lua
```

Key parts:

- `modDesc.xml` registers the Lua.
- `scripts/CropControlOverride.lua` contains the logic and settings loader.

---

## 🧠 How it works

- Hooks into **`FruitTypeManager:loadMapData`** to apply disables *before* AI/jobs/UI cache fruit data.
- Ensures a **template config** exists at (you can manually create this file using the example snippet detail in the Structure section):
  ```
  Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/config.xml
  ```
### NOTE. It is assumed that you are starting a new save and not retrofitting this mod into an existing save, otherwise the modSettings folder will not be created

- When you start a save, it ensures a **per-save config** exists at:
  ```
  Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/saves/<savegameId>.xml
  ```
- That file is then used for all future loads of that save. The game’s own save process will not delete it.
- UI hooks filter crop lists in PDA calendar, map, and price/statistics pages.

---

## ⚙️ Configuration

### Template (global fallback)
The template file is created automatically on first run:
```
modSettings/FS25_CropControlOverride/config.xml
```

### Per-save files
Each save gets its own file under:
```
modSettings/FS25_CropControlOverride/saves/<savegameId>.xml
```

You can edit these with any text/XML editor.

### Structure
```xml
<?xml version="1.0" encoding="utf-8" standalone="no"?>
<cropControl>
  <order>
    <fruit name="WHEAT"/>
    <fruit name="BARLEY"/>
    <fruit name="OAT"/>
    <!-- etc -->
  </order>
  <fruits>
    <fruit name="POTATO" enabled="false"/>
    <fruit name="COTTON" enabled="false"/>
    <!-- set enabled="true" to allow, false to disable -->
  </fruits>
</cropControl>
```

- **`<order>`** controls PDA/price list order.
- **`<fruits>`** controls which crops are enabled/disabled.

---

## 🔍 Logging & Verification

Look for these lines in your log:
```
CCO: using config -> .../modSettings/FS25_CropControlOverride/saves/savegame10.xml
CCO: disabled POTATO
CCO: PDA order applied (20 items)
```

---

## 📥 Install

1. Copy `FS25_CropControlOverride` (or ZIP) to your mods folder:
   - **Windows:** `Documents/My Games/FarmingSimulator2025/mods/`
2. Enable **Crop Control Override** in the in‑game Mod Manager.
3. Start a save. The mod will create config files under `modSettings`. Edit them to your liking.

---

## 🧪 Compatibility

- Designed for **FS25**; no FS22 legacy hooks.
- Intended to be **map‑agnostic**. Custom fruits are fine as long as you use correct names.
- Works alongside growth/calendar mods.

---

## 🤝 Contributing

Issues and PRs welcome! Suggestions for GUI editors or in-game config menus are especially appreciated.

---

## 📜 License

MIT (see `LICENSE`).
