# Alpha 18.6.1 — Custom profile UX and unsuitable policy

## New
- Playable ZIP includes `templates/customRegionalProfile.xml`.
- Custom root supports `unsuitablePolicy="allow|hide|block"`.
- Default policy is `allow`.
- `hide` filters unsuitable crops from normal loaded seeder seed lists.
- `block` also hard-blocks sowing through CCO's existing runtime sowing guards.
- Regional Apply refreshes loaded sowing-machine seed lists after success.
- Preview reports the active unsuitable policy.

## Validation
The whole custom profile is rejected on:
- invalid/reserved profile ID;
- ID collision;
- invalid unsuitablePolicy;
- duplicate crop;
- invalid suitability;
- malformed month expression;
- planting without harvest or harvest without planting.

Unknown crop names remain permitted for modded/cross-map profiles.

## Regression
No changes to:
- calendar lifecycle reconstruction;
- Preview/Apply confirmation model;
- forced NPC regeneration;
- contract board rebuild;
- MoistureSystem weather ownership.

## MP alpha note
Profile definitions still come from local modSettings. Use matching XML definitions
on server/host and clients until profile-definition synchronization is implemented.
