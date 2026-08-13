# CCO 2.1 / Alpha 18 Regional Profile Foundation

This foundation pivots the crop-calendar work toward predefined regional agronomy
profiles instead of making unrestricted calendar editing the primary player-facing
feature.

## Ownership boundaries

CCO owns:

- regional crop suitability;
- planting and harvesting calendar intent;
- NPC crop-selection weighting;
- crop availability policy;
- NPC field regeneration;
- later, an optional regional yield modifier.

CCO does **not** own weather.

MoistureSystem remains responsible for weather/moisture consequences. CCO may
detect its selected weather profile to suggest a matching CCO regional profile,
but CCO must not set or mutate MoistureSystem settings.

## Initial regional profiles

- Map Default
- UK Temperate
- Central Europe
- Mediterranean
- US Midwest
- Brazil Central
- Brazil South

These were selected because they map cleanly onto several of MoistureSystem's
existing weather-profile identifiers while still remaining independent CCO
agronomic profiles.

## Suitability model

| Rating | Yield prototype | NPC weighting prototype |
|---|---:|---:|
| Excellent | 1.15 | 1.50 |
| Good | 1.05 | 1.20 |
| Normal | 1.00 | 1.00 |
| Marginal | 0.90 | 0.50 |
| Poor | 0.75 | 0.15 |
| Unsuitable | 0.00 | 0.00 |

The multipliers are prototype tuning values, not final balance values.

## Integration plan

1. Rebase these additive files onto the exact Alpha 17.1 source.
2. Add per-save `regionalProfile` persistence with `mapDefault` as the migration default.
3. Add a Regional Profile selector to the Calendar UI.
4. Convert profile planting/harvest month lists through the existing CCO calendar engine.
5. Preview the complete profile before Apply.
6. Feed suitability into NPC regeneration and planned-fruit selection.
7. Leave player-owned existing fields protected by the Alpha 17 reconciliation rules.
8. Add yield modifiers only after calendar/NPC behaviour is proven stable.
9. Keep unrestricted custom calendar editing hidden/advanced while regional profiles are the supported path.
10. Keep MoistureSystem integration read-only and optional.

## Important

The crop calendars in this prototype are preliminary and need agronomic validation
before being treated as release data. The architecture is the implementation target;
the exact month masks and multipliers remain test data.
