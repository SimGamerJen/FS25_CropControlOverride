# P6.0 — Shared Field Regeneration Core Extraction

## Objective

Extract the field-regeneration implementation proven by the FSM P5.0–P5.2 Kinlaig tests into a reusable source module without changing CCO behaviour.

This phase is a refactor only. It does not yet make Farm Sim Manager consume the core directly and it does not alter the active CCO 2.1 development line.

## Branches

- Proven integration parent: `integration/fsm-bootstrap-alpha10.3`
- P6.0 refactor: `refactor/field-regeneration-core-alpha10.3`
- Frozen Alpha 10.3 baseline remains untouched: `archive/v2.1.0.0-alpha10.3-regen-only`

## Shared core

Canonical source:

`/scripts/shared/FieldRegenerationCore.lua`

Current identity:

- core version: `0.1.0`
- core API: `1`
- source owner: `FS25_CropControlOverride`

The shared core owns:

- NPC field discovery and identity
- candidate fruit evaluation using consumer-supplied policy
- seasonal growth-state resolution
- deterministic weighted plan generation
- semantic live-state equivalence
- cultivated/crop `FieldUpdateTask` writes
- active-contract safety checks
- stale available-contract purge
- field-state cache settle/refresh
- native contract-board refill lifecycle
- completion state

The shared core contains no CCO GUI or CCO XML configuration dependency. CCO supplies policy callbacks for crop permission, per-crop weight and leave-cultivated weight.

## CCO bridge

`/scripts/shared/CCOFieldRegenerationCoreBridge.lua` attaches the shared engine to `CropControlOverride` after the CCO host has defined its policy methods.

Existing CCO method names remain available and delegate to the shared engine. The legacy Alpha 10.3 regeneration implementations remain in `CropControlOverride.lua` temporarily as a P6.0 fallback/reference, but the FSM integration API refuses to publish unless the shared core has successfully attached. This prevents a passing P6.0 test from silently exercising the legacy implementation.

`CropControlOverride.lua` must remain unchanged in this phase.

## Integration identity

Public integration contract remains API `1.2`.

P6.0 build marker:

`2.1.0.0-alpha.10.3-fsm.4-core0.1`

Expected publication log includes:

`fieldCore 0.1.0 api=1 source=FS25_CropControlOverride`

## Immediate parity test — P5.2 saved/reloaded artifact

Use the accepted P5.2 Kinlaig save with FSMBootstrap 0.5.2.0.

### Load acceptance

The log must contain both:

- `shared field-regeneration core 0.1.0 attached`
- `integration API 1.2 published (2.1.0.0-alpha.10.3-fsm.4-core0.1; ... fieldCore 0.1.0 api=1 source=FS25_CropControlOverride)`

There must be no shared-core attach or integration-publication warning.

### Read-only preview

Run:

`fsmBootstrapFields`

Expected parity with P5.2:

- live fields: 48
- source tasks: 7 resolved / 0 unresolved
- Starting Farm source fields: 20, 22, 23, 35
- NPC source fields: 3, 6, 31
- CCO NPC fields: 44
- planned: 44
- excluded: 0
- unverified: 0
- overlap: 0
- `confirmAllowed=true`
- action field/crop/growth-state plan remains deterministic and matches the accepted P5.2 target.

### Equivalence/no-op

Run once:

`fsmBootstrapFieldsApply`

Then:

`fsmBootstrapFieldsStatus`

Expected:

- planned=44
- alreadyMatching=44
- needsMutation=0
- equivalence unresolved=0
- noOp=true
- queued=0
- staleContractsRemoved=0
- refillCycles=0
- freshContracts=14
- FSM lifecycle COMPLETE

Forbidden during the no-op run:

- stale contract deletion
- field task enqueue
- field-state cache refresh
- contract refill lifecycle

The existing contract board must remain untouched.

## Full mutation parity

After no-op parity passes, rerun against a pre-P5.1 Kinlaig backup if available.

Expected parity with accepted P5.1:

- planned=44
- queued=44
- skipped=0
- field-state cache refresh=44 / failure=0
- Starting Farm fields remain outside the plan
- stale available contracts are removed only after all safety gates pass
- contract board refills through the existing native lifecycle
- save/reload persistence remains valid
- second run returns the P5.2 no-op result.

## P6.0 acceptance

P6.0 can be accepted when:

1. the shared core attaches and is explicitly reported;
2. integration API publication is refused if attachment fails;
3. P5.2 deterministic/no-op parity passes through the shared core;
4. mutation parity passes on a clean pre-regeneration artifact;
5. `CropControlOverride.lua` remains unchanged relative to `integration/fsm-bootstrap-alpha10.3`;
6. stable and current CCO development branches remain untouched.

Only after acceptance should FSMBootstrap vendor the same shared core directly and remove CCO as a runtime requirement for FSM career field generation.
