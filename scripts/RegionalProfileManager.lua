-- FS25_CropControlOverride
-- Regional profile foundation for the 2.1 development line.
--
-- IMPORTANT:
-- * CCO owns agronomic profile selection, crop suitability and calendar intent.
-- * MoistureSystem integration is optional and READ-ONLY.
-- * This module never changes MoistureSystem weatherProfile, weather, moisture,
--   rain, temperature or any other environmental setting.
--
-- This file is intentionally additive so it can be rebased cleanly onto the
-- current Alpha 17.1 source once that exact build is available.

CCO_RegionalProfiles = CCO_RegionalProfiles or {}

local Regional = CCO_RegionalProfiles

Regional.VERSION = "0.1.0-alpha18-foundation"

Regional.SUITABILITY = {
    EXCELLENT  = "excellent",
    GOOD       = "good",
    NORMAL     = "normal",
    MARGINAL   = "marginal",
    POOR       = "poor",
    UNSUITABLE = "unsuitable",
}

Regional.YIELD_MULTIPLIER = {
    excellent  = 1.15,
    good       = 1.05,
    normal     = 1.00,
    marginal   = 0.90,
    poor       = 0.75,
    unsuitable = 0.00,
}

Regional.NPC_WEIGHT_MULTIPLIER = {
    excellent  = 1.50,
    good       = 1.20,
    normal     = 1.00,
    marginal   = 0.50,
    poor       = 0.15,
    unsuitable = 0.00,
}

Regional.PROFILES = {
    mapDefault = {id="mapDefault", title="Map Default", description="Use the map author's calendar and neutral crop suitability.", moistureAliases={}, crops={}},
    ukTemperate = {id="ukTemperate", title="UK Temperate", description="Cool maritime arable and mixed-farming profile.", moistureAliases={"ukwest","ukeast"}, crops={
        WHEAT={suitability="excellent",planting={"SEP","OCT"},harvest={"JUL","AUG"}}, BARLEY={suitability="excellent",planting={"SEP","OCT","MAR"},harvest={"JUL","AUG"}}, OAT={suitability="excellent",planting={"MAR","APR"},harvest={"AUG","SEP"}}, CANOLA={suitability="excellent",planting={"AUG","SEP"},harvest={"JUL"}}, POTATO={suitability="good",planting={"MAR","APR"},harvest={"SEP","OCT"}}, SUGARBEET={suitability="good",planting={"MAR","APR"},harvest={"SEP","OCT","NOV"}}, CORN={suitability="good",planting={"APR","MAY"},harvest={"OCT","NOV"}}, SOYBEAN={suitability="marginal",planting={"MAY"},harvest={"SEP","OCT"}}, SUNFLOWER={suitability="marginal",planting={"APR","MAY"},harvest={"SEP","OCT"}}, SORGHUM={suitability="poor",planting={"MAY"},harvest={"SEP","OCT"}}, COTTON={suitability="unsuitable",planting={},harvest={}}, SUGARCANE={suitability="unsuitable",planting={},harvest={}}}},
    centralEurope = {id="centralEurope", title="Central Europe", description="Temperate continental cereal, oilseed and root-crop profile.", moistureAliases={"centraleurope"}, crops={
        WHEAT={suitability="excellent",planting={"SEP","OCT"},harvest={"JUL","AUG"}}, BARLEY={suitability="excellent",planting={"SEP","OCT","MAR"},harvest={"JUN","JUL","AUG"}}, CANOLA={suitability="excellent",planting={"AUG","SEP"},harvest={"JUL"}}, CORN={suitability="excellent",planting={"APR","MAY"},harvest={"SEP","OCT","NOV"}}, POTATO={suitability="good",planting={"MAR","APR"},harvest={"AUG","SEP","OCT"}}, SUGARBEET={suitability="excellent",planting={"MAR","APR"},harvest={"SEP","OCT","NOV"}}, SUNFLOWER={suitability="good",planting={"APR"},harvest={"SEP","OCT"}}, SOYBEAN={suitability="good",planting={"APR","MAY"},harvest={"SEP","OCT"}}, SORGHUM={suitability="normal",planting={"APR","MAY"},harvest={"SEP","OCT"}}, COTTON={suitability="poor",planting={"APR"},harvest={"OCT"}}, SUGARCANE={suitability="unsuitable",planting={},harvest={}}}},
    mediterranean = {id="mediterranean", title="Mediterranean", description="Warm dry-summer profile favouring winter cereals and heat-tolerant crops.", moistureAliases={"mediterranean"}, crops={
        WHEAT={suitability="excellent",planting={"OCT","NOV","DEC"},harvest={"MAY","JUN","JUL"}}, BARLEY={suitability="excellent",planting={"OCT","NOV","DEC"},harvest={"MAY","JUN"}}, CANOLA={suitability="good",planting={"OCT","NOV"},harvest={"MAY","JUN"}}, CORN={suitability="good",planting={"MAR","APR"},harvest={"AUG","SEP"}}, SUNFLOWER={suitability="excellent",planting={"MAR","APR"},harvest={"AUG","SEP"}}, SOYBEAN={suitability="normal",planting={"APR"},harvest={"SEP"}}, SORGHUM={suitability="excellent",planting={"APR","MAY"},harvest={"AUG","SEP"}}, POTATO={suitability="normal",planting={"JAN","FEB","MAR"},harvest={"MAY","JUN"}}, SUGARBEET={suitability="good",planting={"FEB","MAR"},harvest={"JUL","AUG","SEP"}}, COTTON={suitability="good",planting={"MAR","APR"},harvest={"SEP","OCT"}}, SUGARCANE={suitability="marginal",planting={"MAR","APR"},harvest={"OCT","NOV"}}}},
    usMidwest = {id="usMidwest", title="US Midwest", description="Continental row-crop profile centred on maize and soybean.", moistureAliases={"usmidwest"}, crops={
        CORN={suitability="excellent",planting={"APR","MAY"},harvest={"SEP","OCT","NOV"}}, SOYBEAN={suitability="excellent",planting={"APR","MAY","JUN"},harvest={"SEP","OCT"}}, WHEAT={suitability="good",planting={"SEP","OCT","MAR"},harvest={"JUN","JUL"}}, BARLEY={suitability="normal",planting={"MAR","APR"},harvest={"JUL","AUG"}}, OAT={suitability="normal",planting={"MAR","APR"},harvest={"JUL","AUG"}}, CANOLA={suitability="normal",planting={"APR"},harvest={"JUL","AUG"}}, SORGHUM={suitability="good",planting={"MAY","JUN"},harvest={"SEP","OCT"}}, SUNFLOWER={suitability="good",planting={"APR","MAY"},harvest={"SEP","OCT"}}, POTATO={suitability="normal",planting={"APR","MAY"},harvest={"SEP","OCT"}}, SUGARBEET={suitability="normal",planting={"APR"},harvest={"SEP","OCT"}}, COTTON={suitability="poor",planting={"MAY"},harvest={"OCT","NOV"}}, SUGARCANE={suitability="unsuitable",planting={},harvest={}}}},
    brazilCentral = {id="brazilCentral", title="Brazil Central", description="Warm central Brazilian profile supporting soybean, maize and tropical cash crops.", moistureAliases={"brazilcentral"}, crops={
        SOYBEAN={suitability="excellent",planting={"SEP","OCT","NOV"},harvest={"JAN","FEB","MAR"}}, CORN={suitability="excellent",planting={"JAN","FEB","MAR","SEP","OCT"},harvest={"MAY","JUN","JUL","JAN","FEB"}}, COTTON={suitability="excellent",planting={"NOV","DEC","JAN"},harvest={"MAY","JUN","JUL"}}, SUGARCANE={suitability="excellent",planting={"SEP","OCT","NOV","FEB","MAR"},harvest={"APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV"}}, SORGHUM={suitability="excellent",planting={"FEB","MAR"},harvest={"JUN","JUL"}}, SUNFLOWER={suitability="good",planting={"FEB","MAR"},harvest={"JUN","JUL"}}, WHEAT={suitability="marginal",planting={"MAR","APR"},harvest={"JUL","AUG"}}, BARLEY={suitability="poor",planting={"APR"},harvest={"AUG"}}, CANOLA={suitability="marginal",planting={"FEB","MAR"},harvest={"JUN","JUL"}}, POTATO={suitability="normal",planting={"FEB","MAR","APR"},harvest={"JUN","JUL","AUG"}}, SUGARBEET={suitability="poor",planting={"MAR","APR"},harvest={"AUG","SEP"}}}},
    brazilSouth = {id="brazilSouth", title="Brazil South", description="Subtropical southern Brazilian profile with stronger cool-season cereal options.", moistureAliases={"brazilsouth"}, crops={
        SOYBEAN={suitability="excellent",planting={"OCT","NOV","DEC"},harvest={"FEB","MAR","APR"}}, CORN={suitability="excellent",planting={"AUG","SEP","OCT","JAN","FEB"},harvest={"JAN","FEB","MAR","JUN","JUL"}}, WHEAT={suitability="excellent",planting={"APR","MAY","JUN"},harvest={"SEP","OCT","NOV"}}, BARLEY={suitability="good",planting={"MAY","JUN"},harvest={"OCT","NOV"}}, CANOLA={suitability="excellent",planting={"APR","MAY"},harvest={"AUG","SEP"}}, SORGHUM={suitability="good",planting={"SEP","OCT"},harvest={"JAN","FEB"}}, SUNFLOWER={suitability="good",planting={"JUL","AUG","SEP"},harvest={"DEC","JAN"}}, COTTON={suitability="normal",planting={"OCT","NOV"},harvest={"MAR","APR","MAY"}}, SUGARCANE={suitability="good",planting={"SEP","OCT","FEB","MAR"},harvest={"APR","MAY","JUN","JUL","AUG","SEP","OCT"}}, POTATO={suitability="good",planting={"FEB","MAR","JUL","AUG"},harvest={"JUN","JUL","NOV","DEC"}}}},
}

local function upper(value) if value == nil then return nil end return string.upper(tostring(value)) end
function Regional:getProfile(profileId) return self.PROFILES[tostring(profileId or "mapDefault")] or self.PROFILES.mapDefault end
function Regional:getCrop(profileId, cropName) return self:getProfile(profileId).crops[upper(cropName)] end
function Regional:getSuitability(profileId, cropName) local crop=self:getCrop(profileId,cropName); return crop and crop.suitability or self.SUITABILITY.NORMAL end
function Regional:getYieldMultiplier(profileId, cropName) return self.YIELD_MULTIPLIER[self:getSuitability(profileId,cropName)] or 1.0 end
function Regional:getNpcWeightMultiplier(profileId, cropName) return self.NPC_WEIGHT_MULTIPLIER[self:getSuitability(profileId,cropName)] or 1.0 end
function Regional:getCalendarMonths(profileId, cropName) local crop=self:getCrop(profileId,cropName); if crop==nil then return nil,nil end return crop.planting,crop.harvest end
function Regional:getMoistureSystemWeatherProfile()
    local mission=g_currentMission; if mission==nil then return nil end
    local ms=mission.MoistureSystem or mission.moistureSystem
    if type(ms)~="table" or type(ms.settings)~="table" then return nil end
    local value=ms.settings.weatherProfile; if value==nil or tostring(value)=="" then return nil end
    return string.lower(tostring(value))
end
function Regional:suggestProfileFromMoistureSystem()
    local moistureProfile=self:getMoistureSystemWeatherProfile(); if moistureProfile==nil then return nil end
    for profileId,profile in pairs(self.PROFILES) do for _,alias in ipairs(profile.moistureAliases or {}) do if string.lower(tostring(alias))==moistureProfile then return profileId,moistureProfile end end end
    return nil,moistureProfile
end
function Regional:getCompatibilityStatus()
    local moistureProfile=self:getMoistureSystemWeatherProfile(); local suggested=nil
    if moistureProfile~=nil then suggested=self:suggestProfileFromMoistureSystem() end
    return {moistureSystemDetected=moistureProfile~=nil, moistureWeatherProfile=moistureProfile, suggestedProfile=suggested, readOnly=true}
end

return Regional
