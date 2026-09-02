# Native Crop Calendar filtering

CCO integrates directly with the GIANTS `InGameMenuCalendarFrame`.

The filter is presentation-only:
- read mounted fruit types;
- retain fruit types the game marks `shownOnMap`;
- exclude fruit types disabled by the active CCO save rules;
- provide that projected list to the Calendar frame;
- request one native table reload.

No global fruit registration, map XML, save crop state, or game settings are modified.
