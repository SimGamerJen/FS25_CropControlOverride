# FS25_CropControlOverride

A lightweight Farming Simulator 25 script mod that **overrides crop (fruit) order and disables selected crops** globally — without editing the base game or map XMLs.

---

## ✨ What it does

- Enforces a **custom fruit display order** across PDA/price lists/contracts.
- **Disables specified crops** for players and AI contracts.
- Optionally removes disallowed crops from the **economy/price display** (see `removeFromEconomyDisplay()` call).
- Runs at map load; no savegame editing required.

---

## 📦 Contents

```
FS25_CropControlOverride/
├─ modDesc.xml
└─ scripts/
   └─ CropControlOverride.lua
```

Key parts detected:

- `modDesc.xml` registers the Lua with `<extraSourceFiles>`.
- `scripts/CropControlOverride.lua` contains the logic and debug prints.

---

## 🧠 How it works (Lifecycle & Hooks)

At startup the mod appends a post-load hook to the mission:

```lua
-- In CropControlOverride.lua
function CropControlOverride.init()
    print("CropControlOverride: init() called")
    FSBaseMission.loadMapFinished = Utils.appendedFunction(FSBaseMission.loadMapFinished, function(self)
        CropControlOverride:onLoadMap()
    end)
end

CropControlOverride.init()
```

When the map finishes loading, `onLoadMap()` is invoked. From the visible calls, it is expected to:

```lua
function CropControlOverride:onLoadMap()
    print("CropControlOverride: onLoadMap() triggered")
    self:applyFruitOrder()
    self:disableDisallowedCrops()
    self:removeFromEconomyDisplay()
end
```

> **Note:** If you don’t want to hide disallowed crops from the economy UI, comment out the `removeFromEconomyDisplay()` line.

---

## ⚙️ Configuration

There are two primary tables in `CropControlOverride.lua` you can tailor:

### 1) Fruit order (top → bottom in PDA/price lists)

```lua
CropControlOverride.fruitOrder = {
    "WHEAT","BARLEY","OAT","CANOLA","MAIZE",
    "SORGHUM","SOYBEAN","GRASS","ALFALFA","CLOVER",
    "PEA","LENTILS","RYE","FLAX","TRITICALE","BEANS",
    -- add/remove/swap as needed; keep names matching fruitType names
}
```

**Tips:**  
- Use **fruit type names** exactly as defined by the map or mods.  
- Unknown names are safely ignored by your implementation strategy if you add a guard; otherwise make sure all entries exist on your map.

### 2) Disallowed crops (boolean map)

```lua
CropControlOverride.disallowedCrops = {
    POTATO = true, RICE = true, SUGARBEET = true,
    SUGARCANE = true, COTTON = true, GRAPE = true, OLIVE = true,
    -- set to true to disable, or remove / set to false to allow
}
```

**What “disable” does:** Typically prevents player/AI usage and can be combined with hiding in the economy UI (see below). Exact effects depend on your internal implementation of `disableDisallowedCrops()`.

---

## 🧩 Expected internal helpers

The mod references these helper methods (names inferred from calls):

- `applyFruitOrder()` – Rebuilds the fruit display order used by HUD/PDA/price pages.
- `disableDisallowedCrops()` – Marks configured fruits as unavailable for players/AI.
- `removeFromEconomyDisplay()` – Hides disallowed fruits from the economy price list.

If you’re extending the mod, you’ll typically interact with **`g_fruitTypeManager`**, **`g_fillTypeManager`**, and PDA/price/economy widgets to implement those behaviors.

---

## 🔍 Logging & Verification

You should see these console lines when things are working:

```
CropControlOverride: init() called
CropControlOverride: onLoadMap() triggered
```

Optional (if you add prints inside your helpers):

```
CropControlOverride: applyFruitOrder() – applied N fruits
CropControlOverride: disableDisallowedCrops() – disabled: POTATO, COTTON, ...
CropControlOverride: removeFromEconomyDisplay() – hidden: POTATO, COTTON, ...
```

> If you **do not** see the first two lines, ensure the mod is enabled and `modDesc.xml` lists `scripts/CropControlOverride.lua` under `<extraSourceFiles>`.

---

## 📥 Install

1. Copy the `FS25_CropControlOverride` folder (or ZIP) to your mods folder:
   - **Windows:** `Documents/My Games/FarmingSimulator2025/mods/`
2. Enable **Crop Control Override** in the in‑game Mod Manager.
3. Load your save. Changes apply at map load.

---

## 🧪 Compatibility

- Designed for **FS25**; no FS22 legacy hooks.
- Intended to be **map‑agnostic**. Custom fruits are fine as long as you use correct names.
- Works alongside calendar/growth mods; this only reorders and disables fruit visibility/usage.

---

## 🤝 Contributing

Issues and PRs welcome! Suggestions for per‑map config files and automatic fruit discovery are especially appreciated.

---

## 📜 License

MIT (see `LICENSE` if included in your repo).
