# Alpha 18.6.3 — Template path-resolution fix

Regression source:
18.6.2 could resolve CCO's custom-profile directory as another mod's
modSettings directory because `g_currentModSettingsDirectory` is mutable.

Observed example:
`modSettings/FS25_ZYX_SeasonalPrices_crossplay/regionalProfiles/`

Fix:
- Capture CCO's own `g_currentModDirectory` and `g_currentModName` at source-load time.
- Derive profile path from `getUserProfileAppPath()/modSettings/<CCO mod name>/`.
- Use captured CCO mod directory for bundled template source.
- Log resolved paths during custom-profile initialization.

Expected:
`.../modSettings/FS25_CropControlOverride/regionalProfiles/_template.xml`

The template remains non-destructive and ignored until renamed/copied.
