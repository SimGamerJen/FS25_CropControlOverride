# Alpha 18.7.3 — CCO-native Crop Calendar filtering

Independently implemented against GIANTS `InGameMenuCalendarFrame`.

Expected:
1. Disable crops in CCO and Apply.
2. Open the game's main Crop Calendar.
3. Disabled crops are absent.
4. Scrolling remains smooth.
5. Re-enable a crop and Apply.
6. The crop returns on the next Calendar refresh.

Model:
- source: `g_fruitTypeManager:getFruitTypes()`
- game eligibility: `shownOnMap == true`
- CCO eligibility: active per-save rule is not `enabled=false`
- frame model: `InGameMenuCalendarFrame.fruitTypes`
- refresh: one `frame.calendar:reloadData()` per rebuild

Regression:
- Edit Calendar remains available.
- Regional Profiles remain unchanged.
- Seeder filtering/runtime sowing guards remain unchanged.
- FSM Integration API 1.2 compatibility guard must pass.
