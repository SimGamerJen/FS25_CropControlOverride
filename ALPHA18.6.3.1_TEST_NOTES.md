# Alpha 18.6.3.1 — Lua syntax hotfix

Fixes the compiler error:
`RegionalProfileManager.lua:353: Expected <eof>, got 'end'`

Cause:
The Alpha 18.6.3 replacement of `getBundledCustomProfileTemplatePath()` left
four lines from the old implementation after the new function's `end`.

Expected next test:
- Mod compiles and loads.
- Log shows CCO path-resolution diagnostics.
- `_template.xml` is created under
  `modSettings/FS25_CropControlOverride/regionalProfiles/`.
