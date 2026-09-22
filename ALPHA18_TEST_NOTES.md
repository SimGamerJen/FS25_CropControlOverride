# Alpha 18.0 Regional Foundation Test Build

Base: exact uploaded `2.1.0.0-alpha17.1_MP-SEEDER-FIX` build.

This build preserves Alpha 17.1 and adds the first regional-profile runtime layer:

- per-save regional profile persistence;
- multiplayer payload synchronisation of the selected profile;
- regional suitability multipliers for NPC reseed weighting;
- optional, read-only MoistureSystem `weatherProfile` detection;
- `ccoRegionalProfile status`;
- `ccoRegionalProfile list`;
- `ccoRegionalProfile set <profileId>`.

Initial profiles:
`mapDefault`, `ukTemperate`, `centralEurope`, `mediterranean`,
`usMidwest`, `brazilCentral`, `brazilSouth`.

Important: selecting a regional profile does NOT yet rewrite crop calendar windows.
The next implementation step is a whole-profile calendar Preview/Apply workflow.

Prototype yield multipliers exist in the profile manager but are NOT yet applied
to player harvest yield in this build.
