# Alpha 18.1 Regional Profile Workflow

This build replaces the player-facing free-form calendar editor with a Regional
Crop Profile selector while retaining the underlying Alpha 17 calendar engine.

A successful Preview is required before Apply. Apply requires a second explicit
confirmation. The transaction then applies the selected calendar, builds a fresh
authoritative NPC regeneration plan, forcibly regenerates all eligible NPC fields,
removes available contracts and rebuilds the contract board after the field-settle
delay. Accepted/active contracts block the workflow. Player-owned fields are not
regenerated.

The regional month windows and suitability multipliers remain Alpha test data and
need agronomic tuning before public release.

Console:
- ccoRegionalProfile status
- ccoRegionalProfile list
- ccoRegionalProfile preview <profileId>
- ccoRegionalProfile apply <profileId>

Direct `set` is disabled.
