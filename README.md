# FS25_CropControlOverride

A lightweight Farming Simulator 25 script mod that **overrides crop (fruit) order and disables selected crops** globally — without editing the base game or map XMLs. Configuration is externalised to `modSettings`, with **per-save files** supported.

---

## ✨ Features

- **Disable crops**: prevent them from being seeded, harvested, used in jobs, or shown in the PDA.
- **Custom PDA order**: (optional) reorder crops in the PDA calendar, map, and statistics.
- **Template + per-save configs**:  
  - Global template at `modSettings/FS25_CropControlOverride/config.xml`  
  - Per-save configs stored in `modSettings/FS25_CropControlOverride/saves/<saveId>.xml`  
  - Safe location (not deleted when the game saves).
- **Automatic config creation**: generates a config on first run if missing (uses defaults baked into Lua).
- **Safe XML I/O**: no risky `io.open` — uses GIANTS’ XMLFile API only.
- **UI filtering**: hides disabled crops from PDA calendar, price list, and map.
- **Debug system**: centralised logging with log levels, runtime toggles, and optional file output.

---

## 📂 Contents

```
FS25_CropControlOverride/
├─ modDesc.xml
└─ scripts/
   ├─ CropControlOverride.lua
   └─ Debug.lua
```

---

## 🧠 How it works

- Hooks into **`FruitTypeManager:loadMapData`** to apply disables *before* AI/jobs/UI cache fruit data.
- Ensures a **template config** exists at:
  ```
  Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/config.xml
  ```
- When you start a save, it ensures a **per-save config** exists at:
  ```
  Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/saves/<saveId>.xml
  ```
- That file is then used for all future loads of that save. The game’s own save process will not delete it.
- UI hooks filter crop lists in PDA calendar, map, and price/statistics pages.
- Debug logging goes both to the GIANTS log and to per-save log files under:
  ```
  Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/logs/<saveId>.log
  ```

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
modSettings/FS25_CropControlOverride/saves/<saveId>.xml
```

You can edit these with any text/XML editor.

### Structure
```xml
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

- **`<order>`** controls PDA/price list order (applied in hooks).  
- **`<fruits>`** controls which crops are enabled/disabled.

---

## 🔍 Logging & Debugging

The mod ships with a centralised `Debug.lua` system.

### Log levels
- **DEBUG**: Very verbose; includes crop disables and table dumps.
- **INFO**: Normal operational messages.
- **WARN**: Warnings (flushes log file immediately).
- **ERROR**: Errors (always logged, even if debug disabled).

### Log destinations
- Always goes to the GIANTS log.
- Also cached and written to:
  ```
  modSettings/FS25_CropControlOverride/logs/<saveId>.log
  ```

### Console commands
- `ccoDebug` — toggle all debug on/off
- `ccoLogLevel DEBUG|INFO|WARN|ERROR` — set verbosity
- `ccoFlush` — force-flush the in-memory buffer to the log file
- `ccoReload` — reloads the config XML for the current save and reapplies it immediately

---

## 📥 Install

1. Copy `FS25_CropControlOverride` (or ZIP) to your mods folder:
   - **Windows:** `Documents/My Games/FarmingSimulator2025/mods/`
2. Enable **Crop Control Override** in the in-game Mod Manager.
3. Start a save. The mod will create config files under `modSettings`. Edit them to your liking.

---

## 🧪 Compatibility

- Designed for **FS25**; no FS22 legacy hooks.
- Intended to be **map-agnostic**. Custom fruits are fine as long as you use correct names.
- Works alongside growth/calendar mods.

---

## 🤝 Contributing

Issues and PRs welcome! Suggestions for GUI editors or in-game config menus are especially appreciated.

---

## 📜 License

MIT (see `LICENSE`).
