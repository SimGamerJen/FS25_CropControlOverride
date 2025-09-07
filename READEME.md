# FS25\_CropControlOverride

A lightweight Farming Simulator 25 script mod that **disables selected crops for AI use** globally — without editing the base game or map XMLs. Configuration is externalised to `modSettings`, with **per-save files** supported.

---

## ✨ Features

* **Disable crops for AI**: prevents them from being used in field jobs (`useForFieldJob = false`).
* **Template + per-save configs**:

  * Global template at `modSettings/FS25_CropControlOverride/config.xml`
  * Per-save configs stored in `modSettings/FS25_CropControlOverride/saves/<saveId>.xml`
  * Safe location (not deleted when the game saves).
* **Automatic config creation**: generates a config on first run if missing (uses defaults from the map’s registered fruit types).
* **Safe XML I/O**: no risky `io.open` — uses GIANTS’ XMLFile API only.
* **Console command**: `ccoReload` lets you reapply changes without restarting the game.

---

## 📂 Contents

```
FS25_CropControlOverride/
├─ modDesc.xml
└─ scripts/
   └─ CropControlOverride.lua
```

---

## 🧠 How it works

* Hooks into **`FSBaseMission:loadMapFinished`** to apply disables *after* the map registers all fruit types.
* Ensures a **template config** exists at:

  ```
  Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/config.xml
  ```
* When you start a save, it ensures a **per-save config** exists at:

  ```
  Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/saves/<saveId>.xml
  ```
* That file is then used for all future loads of that save. The game’s own save process will not delete it.
* The mod only toggles **AI usage flags** — it does not change PDA order, visibility, or economy data.

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
  <fruits>
    <fruit name="POTATO" enabled="false"/>
    <fruit name="COTTON" enabled="false"/>
    <!-- set enabled="true" to allow AI jobs, false to disable -->
  </fruits>
</cropControl>
```

* **`<fruits>`**: crops to enable/disable for AI.

---

## ⚠️ Limitations

* **New-save only for new crops**: if a map adds new fruit types after you’ve already created a save, those fruits will not appear in PDA/machinery on that save. This is an FS engine limitation — new density channels are only added at save creation.
* **No PDA filtering/order**: this mod does not reorder or hide crops in the PDA. All visible crops are handled by the map.

---

## 🔍 Debugging

Console commands:

* `ccoReload` — reloads the config XML for the current save and reapplies it immediately.

---

## 📥 Install

1. Copy `FS25_CropControlOverride` (or ZIP) to your mods folder:

   * **Windows:** `Documents/My Games/FarmingSimulator2025/mods/`
2. Enable **Crop Control Override** in the in-game Mod Manager.
3. Start a save. The mod will create config files under `modSettings`. Edit them to your liking.

---

## 🧪 Compatibility

* Designed for **FS25**; no FS22 legacy hooks.
* Intended to be **map-agnostic**. Custom fruits are fine as long as you use correct names.
* Works alongside growth/calendar mods.

---

## 🤝 Contributing

Issues and PRs welcome! Suggestions for GUI editors or in-game config menus are especially appreciated.

---

## 📜 License

MIT (see `LICENSE`).

---
