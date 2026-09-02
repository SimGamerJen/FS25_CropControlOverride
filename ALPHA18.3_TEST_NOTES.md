# Crop Control Override 2.1.0.0 Alpha 18.3

Alpha 18.3 is a diagnostics and regional-data quality pass over the proven
Alpha 18.2 regional workflow.

Changes:
- Every calendar row now displays the crop's regional suitability.
- The same line identifies the calendar source: REGIONAL, MAP, or FALLBACK.
- PREVIEW lists exact fallback crop names and reasons.
- log.txt receives one diagnostic line per regional crop/fallback to make profile
  tuning and lifecycle compatibility easier.
- The Alpha 18.2 Apply -> forced NPC regeneration -> contract rebuild transaction
  is intentionally unchanged.

Suitability and month-window values are still Alpha test data. Alpha 18.3 is
intended to expose enough information to tune those values safely before adding
harvest-yield modifiers.
