# Alpha 18.6 — Custom regional profiles

Primary test folder:
`modSettings/FS25_CropControlOverride/regionalProfiles/`

Tests:
1. No XML files: built-ins only.
2. Valid XML: appears as `Display Name (Custom)`.
3. Invalid suitability: rejected in log.
4. Built-in ID collision: rejected.
5. Omitted crop: map calendar / neutral suitability remains.
6. Preview and Apply: uses the same established regional transaction.
7. Save/reload with selected custom profile: selection survives while XML remains present.
8. Optional moistureAliases: matching MoistureSystem ID is advisory only.

Multiplayer note: Alpha 18.6 loads custom profile definitions from each machine's
local modSettings folder. Dedicated-server/MP definition synchronization is not
yet added; use matching custom profile XMLs on host/server and clients while this
feature is in alpha testing.
