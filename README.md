# FS25_CropControlOverride

A lightweight Farming Simulator 25 script mod that **disables selected crops for AI use** globally — without editing the base game or map XMLs. Configuration is externalised to `modSettings`, with **per-save files** supported.

> **Scope:** AI-only toggle (`useForFieldJob`). No PDA re-ordering or hiding.  
> **Policy:** New-save only for newly added fruits (engine limitation).

## Current test release

The current recommended test build is:

**v2.0.0-beta.2**

Download it from the GitHub Releases page and use the asset named:

`FS25_CropControlOverride_2.0.0-alpha.80-release-config.zip`

Older alpha releases are retained for history only.

---

## ✨ Features

- **Disable crops for AI**: prevents them from being used in field jobs (`useForFieldJob = false`).
- **Template + per-save configs**  
  - Template: `modSettings/FS25_CropControlOverride/config.xml`  
  - Per-save: `modSettings/FS25_CropControlOverride/saves/<saveId>.xml`
- **Automatic config creation** on first run (seeded from the map’s currently registered fruit types).
- **Safe XML I/O** via GIANTS `XMLFile` API (no `io.open` for config).
- **Console helpers**:
  - `ccoReload` — re-read and apply the current save’s config.
  - `ccoWhichConfig` — show which XML file is being used right now.
  - `ccoListAI` — list all fruit types with their current `useForFieldJob` flag.

---

## 🧠 How it works

- Hooks into **`FSBaseMission:loadMapFinished`** and applies AI toggles once all fruit types are registered.
- Ensures a **template** exists at (a template is available for download from this repository, but is not included within the mod ZIP):

Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/config.xml

- Ensures a **per-save config** exists at:

Documents/My Games/FarmingSimulator2025/modSettings/FS25_CropControlOverride/saves/<saveId>.xml

- The **per-save file** (if present) is always used. The template is only a fallback/seed.

---

## ⚙️ Configuration

### Structure
<cropControl>
<fruits>
  <!-- enabled="true" allows AI jobs; enabled="false" disables AI jobs -->
  <fruit name="WHEAT" enabled="true"/>
  <fruit name="COTTON" enabled="false"/>
</fruits>
</cropControl>

    Crop names must match the fruitType name (case-insensitive).

    If you omit a crop from the XML, it defaults to enabled (AI uses the map’s original setting).

Editing which file?

    For an existing save, edit:
    modSettings/FS25_CropControlOverride/saves/<saveId>.xml

    For new saves, edit the template first:
    modSettings/FS25_CropControlOverride/config.xml
    (that file is copied when the per-save file is created on first load)

Use ccoWhichConfig to confirm which file is active.
⚠️ Limitations

    New-save only for newly added fruits: When a map adds new fruit types, an old save won’t gain the new fruit density layers automatically. Those fruits will only appear in the PDA/machinery on a new save created after the map update. This is an FS engine limitation and out of scope for this mod.

    No PDA/UI changes: The mod doesn’t reorder or hide crops in the PDA. It only toggles whether AI can use them.

🔍 Debugging

    ccoWhichConfig — shows the exact path the mod is currently reading.

    Edit that XML (enabled="true/false").

    ccoReload — reapply without restarting.

    ccoListAI — confirm the useForFieldJob flags changed.

    ccListFlags - shows current flag status of a given fruitType

📥 Install

    Drop the mod (folder or ZIP) into:

        Windows: Documents/My Games/FarmingSimulator2025/mods/

    Enable Crop Control Override in the in-game Mod Manager.

    Start or load a save. The mod creates config files in modSettings on first run.

🧪 Compatibility

    Built for FS25 (no FS22 legacy hooks).

    Map-agnostic. Custom fruits are fine as long as they’re properly registered by the map.

    Coexists with growth/calendar/economy mods (those determine PDA/Prices).

📝 License

MIT


---

# (Optional) `modDesc.xml` description tweak
Update the `<description>` so testers don’t expect PDA changes:

<description>
  <![CDATA[
  Disables selected crops for AI field jobs (useForFieldJob) based on config files in modSettings.
  Template: modSettings/FS25_CropControlOverride/config.xml
  Per-save: modSettings/FS25_CropControlOverride/saves/&lt;saveId&gt;.xml
  Note: New-save only for newly added fruits. No PDA reordering or hiding.
  ]]>
</description>
