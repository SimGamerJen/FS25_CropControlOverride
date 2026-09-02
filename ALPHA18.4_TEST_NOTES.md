# Alpha 18.4 — Environmental Context Clarification

CCO regional profiles are agronomic profiles authored by CCO. They define crop
calendar intent, suitability and NPC crop weighting.

MoistureSystem is optional environmental context only.

Behaviour:
- MoistureSystem absent: CCO works normally and the UI states that no weather mod is required.
- MoistureSystem present, known profile ID: CCO shows the loaded display name and an
  ID-based profile suggestion. The suggestion is advisory only.
- MoistureSystem present, unknown/custom ID: CCO shows the profile as custom/unmapped
  and assumes no CCO agronomy profile.
- A custom MoistureSystem profile may override a built-in using the same ID, so CCO
  never treats an ID mapping as proof that the profile still contains stock climate data.
- CCO never changes MoistureSystem profile selection, weather override, temperature,
  moisture, rainfall, or weather weights.

The proven regional calendar -> forced NPC regeneration -> contract rebuild transaction
is unchanged.
