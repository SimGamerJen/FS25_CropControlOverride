# Alpha 18.6.2 — Automatic custom-profile template

## Expected first-run behaviour
1. Start a save with no `regionalProfiles` folder.
2. CCO creates the folder.
3. CCO creates `regionalProfiles/_template.xml`.
4. `_template.xml` does NOT appear in the Regional Crop Profile selector.

## Player workflow
1. Copy or rename `_template.xml` to a new `.xml` filename.
2. Change `id`, `displayName`, crop data and policy.
3. Reload the save.
4. The profile appears as `Display Name (Custom)`.

## Non-destructive behaviour
- If `_template.xml` already exists, CCO leaves it untouched.
- Existing player custom profiles are never modified by template creation.
- The bundled `templates/customRegionalProfile.xml` remains in the playable ZIP.

## Regression
No changes to Preview/Apply, calendar reconstruction, NPC regeneration,
contract rebuild, unsuitable policy semantics, or MoistureSystem ownership.
