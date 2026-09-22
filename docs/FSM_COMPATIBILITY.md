# Farm Sim Manager compatibility surface

The Alpha 18 development line must preserve the CCO integration work produced
during Farm Sim Manager development.

## Protected public surface

Source: `scripts/CCOIntegrationApi.lua`

- API contract: `1.2`
- Mission publication key:
  `g_currentMission.cropControlOverrideIntegration`
- Public entries:
  - `buildNpcMapRegenerationPlan`
  - `confirmNpcMapRegeneration`
  - `updateNpcMapRegeneration`
  - `getActiveContractCount`
  - `getContractBoardSummary`
  - `getNpcMapRegenerationEquivalence`
  - `startNpcMapRegeneration`
  - `getNpcMapRegenerationStatus`

Do not rename/remove these without an explicit API-version change and coordinated
Farm Sim Manager/FSMBootstrap compatibility review.

## Shared regeneration core

FSM's current production bootstrap vendors a pinned shared `FieldRegenerationCore`
sourced from the CCO development history. It no longer requires the full CCO mod
to be loaded for first-run career field generation.

The canonical extraction remains on:
`refactor/field-regeneration-core-alpha10.3`

Future changes to regeneration semantics must be checked against that shared-core
contract before FSM intentionally uplifts its pinned revision.

## Alpha 18 rule

Calendar/regional-profile development must not silently erase the integration API.
Run `tools/check_fsm_compat.py` when preparing an Alpha branch/package.
