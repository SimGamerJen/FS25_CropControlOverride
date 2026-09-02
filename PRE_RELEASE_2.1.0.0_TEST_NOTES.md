# Crop Control Override 2.1.0.0 — Pre-release candidate

Runtime version: 2.1.0.0-beta.1

## Main Rules list filters
Two independent visibility toggles are now available under the rules table:
- NOT LOADED: SHOWN/HIDDEN
- DISABLED: SHOWN/HIDDEN

`DISABLED` defaults to SHOWN so existing list behaviour is preserved.

When DISABLED is HIDDEN, rows whose Player rule has `enabled=false` are omitted
from the displayed table only. No CCO rule is changed or saved by this filter.

The filter uses the structured `enabledBool` value supplied by
`CropControlOverride:getGuiRuleRows()` rather than parsing display text.

## Regression
- Show Not Loaded remains independent.
- Weight column remains correct.
- Toggling either filter immediately rebuilds the current table.
- Disabled/NPC Disabled/Size Limited topic views still use the same visibility
  toggles intentionally; turning DISABLED off can therefore hide disabled rows
  within those table views as well.
- One consolidated modDesc changelog remains per language.
- Native Crop Calendar filtering remains unchanged.
- FSM Integration API 1.2 compatibility guard passes.
