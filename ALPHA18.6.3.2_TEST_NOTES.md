# Alpha 18.6.3.2 — FSM integration compatibility restoration

## Why
The Alpha 18.6.3.1 branch audit found no FSM integration API source at all.
The Farm Sim Manager CCO integration/refactor line contains a protected public
API 1.2 surface which must not be lost as calendar/regional work advances.

## Expected log
After map load:
`CCO [INFO] integration API 1.2 published (... CCO 2.1.0.0-alpha.18.6.3.2)`

## Runtime check
In the console/Lua debugger:
`g_currentMission.cropControlOverrideIntegration`
must be a table.

Expected methods include:
- buildNpcMapRegenerationPlan
- confirmNpcMapRegeneration
- updateNpcMapRegeneration
- getActiveContractCount
- getContractBoardSummary
- getNpcMapRegenerationEquivalence
- startNpcMapRegeneration
- getNpcMapRegenerationStatus

## Build guard
Run:
`python tools/check_fsm_compat.py`

Expected:
`FSM compatibility audit: PASS`

## Important architecture note
Current Farm Sim Manager production career creation does not require CCO at
runtime. FSMBootstrap vendors the proven shared FieldRegenerationCore directly.
This build restores the CCO public integration surface so later Alpha work does
not silently break cross-mod compatibility.
