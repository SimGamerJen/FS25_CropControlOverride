# Alpha 18.7.4 — Yellow custom-calendar legend key

Expected on the CCO CALENDAR tab:
- Green band: Planting
- Red band: Harvesting
- Yellow vertical marker: Override / Preview

The yellow legend marker intentionally matches the yellow side marker displayed
beside calendar rows with an active override or preview state.

Regression:
- Legend remains outside SmoothList clipping.
- Calendar scrolling/layout remains unchanged.
- Native Crop Calendar disabled-crop filtering remains unchanged.
- FSM Integration API 1.2 compatibility guard passes.
