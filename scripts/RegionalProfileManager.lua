-- FS25_CropControlOverride
-- Regional agronomy profile manager - Alpha 18 foundation.
--
-- CCO owns agronomic suitability, crop-policy weighting and calendar intent.
-- MoistureSystem integration is optional and READ-ONLY. CCO must never mutate
-- MoistureSystem weatherProfile, weather, moisture, temperature or rainfall.

CCO_RegionalProfiles = CCO_RegionalProfiles or {}

local Regional = CCO_RegionalProfiles

Regional.VERSION = "0.5.3.1-alpha18.6.3.1"

-- Capture CCO's own paths while this source is being loaded. GIANTS' globals
-- g_currentModDirectory/g_currentModName are mutable and can point at another
-- mod later during mission startup.
Regional.MOD_DIRECTORY = g_currentModDirectory
Regional.MOD_NAME = g_currentModName or "FS25_CropControlOverride"

local function ensureTrailingSlash(path)
    local value = tostring(path or "")
    if value ~= "" and value:sub(-1) ~= "/" and value:sub(-1) ~= "\\" then
        value = value .. "/"
    end
    return value
end

local function resolveUserProfileAppPath()
    if getUserProfileAppPath ~= nil then
        local ok, value = pcall(getUserProfileAppPath)
        if ok and value ~= nil and tostring(value) ~= "" then
            return ensureTrailingSlash(value)
        end
    end
    return nil
end


Regional.CUSTOM_PROFILE_DIRNAME = "regionalProfiles"
Regional.CUSTOM_PROFILE_SOURCE = "customXml"
Regional.BUILTIN_PROFILE_SOURCE = "builtin"

local VALID_SUITABILITY = {
    excellent=true, good=true, normal=true,
    marginal=true, poor=true, unsuitable=true,
}

local VALID_UNSUITABLE_POLICY = {
    allow=true, hide=true, block=true,
}

local VALID_MONTH = {
    JAN=true, FEB=true, MAR=true, APR=true, MAY=true, JUN=true,
    JUL=true, AUG=true, SEP=true, OCT=true, NOV=true, DEC=true,
}

local function validateMonthExpression(value)
    if value == nil then return true, nil end
    local text = tostring(value):upper():gsub("%s+", "")
    if text == "" then return true, nil end
    if text == "ALL" or text == "ALLYEAR" or text == "ALL_YEAR" then
        return true, nil
    end

    for token in (text .. ","):gmatch("(.-),") do
        if token == "" then
            return false, "empty month token"
        end
        local first, last = token:match("^([A-Z][A-Z][A-Z])%-([A-Z][A-Z][A-Z])$")
        if first ~= nil then
            if VALID_MONTH[first] ~= true or VALID_MONTH[last] ~= true then
                return false, "invalid month range '" .. token .. "'"
            end
        elseif VALID_MONTH[token] ~= true then
            return false, "invalid month token '" .. token .. "'"
        end
    end
    return true, nil
end

local function splitCsv(value)
    local result = {}
    if value == nil then return result end
    for token in tostring(value):gmatch("[^,]+") do
        token = token:gsub("^%s+", ""):gsub("%s+$", "")
        if token ~= "" then table.insert(result, token) end
    end
    return result
end

local function normalizeMonthSpec(value)
    if value == nil then return nil end
    local v = tostring(value):upper():gsub("%s+", "")
    if v == "" or v == "DEFAULT" or v == "MAP" then return nil end
    return v
end

local function safeProfileId(value)
    local id = tostring(value or "")
    if id == "" then return nil end
    if not id:match("^[%w_%-%.]+$") then return nil end
    return id
end

local function safeLog(value)
    return tostring(value or ""):gsub("[\r\n\t]", " ")
end

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

Regional.PROFILE_ORDER = {
    "mapDefault",
    "ukTemperate",
    "centralEurope",
    "mediterranean",
    "usMidwest",
    "brazilCentral",
    "brazilSouth",
}

local function crop(suitability, planting, harvest)
    return { suitability=suitability, planting=planting, harvest=harvest }
end

Regional.PROFILES = {
    mapDefault = {
        id = "mapDefault",
        title = "Map Default",
        description = "Use the map author's calendar and neutral crop suitability.",
        moistureAliases = {},
        crops = {},
    },

    ukTemperate = {
        id = "ukTemperate",
        title = "UK Temperate",
        description = "Cool maritime arable and mixed-farming profile.",
        moistureAliases = {"ukwest", "ukeast"},
        crops = {
            WHEAT=crop("excellent","SEP-OCT","JUL-AUG"),
            BARLEY=crop("excellent","SEP-OCT,MAR","JUL-AUG"),
            OAT=crop("excellent","MAR-APR","AUG-SEP"),
            CANOLA=crop("excellent","AUG-SEP","JUL"),
            POTATO=crop("good","MAR-APR","SEP-OCT"),
            SUGARBEET=crop("good","MAR-APR","SEP-NOV"),
            CORN=crop("good","APR-MAY","OCT-NOV"),
            SOYBEAN=crop("marginal","MAY","SEP-OCT"),
            SUNFLOWER=crop("marginal","APR-MAY","SEP-OCT"),
            SORGHUM=crop("poor","MAY","SEP-OCT"),
            COTTON=crop("unsuitable",nil,nil),
            SUGARCANE=crop("unsuitable",nil,nil),
        },
    },

    centralEurope = {
        id = "centralEurope",
        title = "Central Europe",
        description = "Temperate continental cereal, oilseed and root-crop profile.",
        moistureAliases = {"centraleurope"},
        crops = {
            WHEAT=crop("excellent","SEP-OCT","JUL-AUG"),
            BARLEY=crop("excellent","SEP-OCT,MAR","JUN-AUG"),
            CANOLA=crop("excellent","AUG-SEP","JUL"),
            CORN=crop("excellent","APR-MAY","SEP-NOV"),
            POTATO=crop("good","MAR-APR","AUG-OCT"),
            SUGARBEET=crop("excellent","MAR-APR","SEP-NOV"),
            SUNFLOWER=crop("good","APR","SEP-OCT"),
            SOYBEAN=crop("good","APR-MAY","SEP-OCT"),
            SORGHUM=crop("normal","APR-MAY","SEP-OCT"),
            COTTON=crop("poor","APR","OCT"),
            SUGARCANE=crop("unsuitable",nil,nil),
        },
    },

    mediterranean = {
        id = "mediterranean",
        title = "Mediterranean",
        description = "Warm dry-summer profile favouring winter cereals and heat-tolerant crops.",
        moistureAliases = {"mediterranean"},
        crops = {
            WHEAT=crop("excellent","OCT-DEC","MAY-JUL"),
            BARLEY=crop("excellent","OCT-DEC","MAY-JUN"),
            CANOLA=crop("good","OCT-NOV","MAY-JUN"),
            CORN=crop("good","MAR-APR","AUG-SEP"),
            SUNFLOWER=crop("excellent","MAR-APR","AUG-SEP"),
            SOYBEAN=crop("normal","APR","SEP"),
            SORGHUM=crop("excellent","APR-MAY","AUG-SEP"),
            POTATO=crop("normal","JAN-MAR","MAY-JUN"),
            SUGARBEET=crop("good","FEB-MAR","JUL-SEP"),
            COTTON=crop("good","MAR-APR","SEP-OCT"),
            SUGARCANE=crop("marginal","MAR-APR","OCT-NOV"),
        },
    },

    usMidwest = {
        id = "usMidwest",
        title = "US Midwest",
        description = "Continental row-crop profile centred on maize and soybean.",
        moistureAliases = {"usmidwest"},
        crops = {
            CORN=crop("excellent","APR-MAY","SEP-NOV"),
            SOYBEAN=crop("excellent","APR-JUN","SEP-OCT"),
            WHEAT=crop("good","SEP-OCT,MAR","JUN-JUL"),
            BARLEY=crop("normal","MAR-APR","JUL-AUG"),
            OAT=crop("normal","MAR-APR","JUL-AUG"),
            CANOLA=crop("normal","APR","JUL-AUG"),
            SORGHUM=crop("good","MAY-JUN","SEP-OCT"),
            SUNFLOWER=crop("good","APR-MAY","SEP-OCT"),
            POTATO=crop("normal","APR-MAY","SEP-OCT"),
            SUGARBEET=crop("normal","APR","SEP-OCT"),
            COTTON=crop("marginal","MAY","OCT-NOV"),
            SUGARCANE=crop("unsuitable",nil,nil),
        },
    },

    brazilCentral = {
        id = "brazilCentral",
        title = "Brazil Central",
        description = "Warm central Brazilian profile favouring soybean, maize and tropical cash crops.",
        moistureAliases = {"brazilcentral"},
        crops = {
            SOYBEAN=crop("excellent","SEP-NOV","JAN-MAR"),
            CORN=crop("excellent","SEP-OCT,JAN-MAR","JAN-FEB,MAY-JUL"),
            COTTON=crop("excellent","NOV-JAN","MAY-JUL"),
            SUGARCANE=crop("excellent","SEP-NOV,FEB-MAR","APR-NOV"),
            SORGHUM=crop("excellent","FEB-MAR","JUN-JUL"),
            SUNFLOWER=crop("good","FEB-MAR","JUN-JUL"),
            WHEAT=crop("marginal","MAR-APR","JUL-AUG"),
            BARLEY=crop("poor","APR","AUG"),
            CANOLA=crop("marginal","FEB-MAR","JUN-JUL"),
            POTATO=crop("normal","FEB-APR","JUN-AUG"),
            SUGARBEET=crop("poor","MAR-APR","AUG-SEP"),
        },
    },

    brazilSouth = {
        id = "brazilSouth",
        title = "Brazil South",
        description = "Subtropical southern Brazilian profile with strong cool-season cereal options.",
        moistureAliases = {"brazilsouth"},
        crops = {
            SOYBEAN=crop("excellent","OCT-DEC","FEB-APR"),
            CORN=crop("excellent","AUG-OCT,JAN-FEB","JAN-MAR,JUN-JUL"),
            WHEAT=crop("excellent","APR-JUN","SEP-NOV"),
            BARLEY=crop("good","MAY-JUN","OCT-NOV"),
            CANOLA=crop("excellent","APR-MAY","AUG-SEP"),
            SORGHUM=crop("good","SEP-OCT","JAN-FEB"),
            SUNFLOWER=crop("good","JUL-SEP","DEC-JAN"),
            COTTON=crop("normal","OCT-NOV","MAR-MAY"),
            SUGARCANE=crop("good","SEP-OCT,FEB-MAR","APR-OCT"),
            POTATO=crop("good","FEB-MAR,JUL-AUG","JUN-JUL,NOV-DEC"),
        },
    },
}

function Regional:normalizeProfileId(profileId)
    local id = tostring(profileId or "mapDefault")
    if self.PROFILES[id] ~= nil then return id end
    return "mapDefault"
end

function Regional:getProfile(profileId)
    return self.PROFILES[self:normalizeProfileId(profileId)]
end

function Regional:getProfileIds()
    local ids = {}
    for _, id in ipairs(self.PROFILE_ORDER or {}) do
        if self.PROFILES[id] ~= nil then ids[#ids + 1] = id end
    end
    return ids
end

function Regional:getCalendarSpec(profileId, cropName)
    local profile = self:getProfile(profileId)
    if profile.id == "mapDefault" then return nil end
    local spec = profile.crops[string.upper(tostring(cropName or ""))]
    if spec == nil or spec.planting == nil or spec.harvest == nil then return nil end
    return {
        planting=tostring(spec.planting),
        harvest=tostring(spec.harvest),
        suitability=spec.suitability or self.SUITABILITY.NORMAL,
    }
end

function Regional:getSuitability(profileId, cropName)
    local profile = self:getProfile(profileId)
    if profile.id == "mapDefault" then return self.SUITABILITY.NORMAL end
    local crop = profile.crops[string.upper(tostring(cropName or ""))]
    if crop == nil then return self.SUITABILITY.NORMAL end
    return crop.suitability or self.SUITABILITY.NORMAL
end

function Regional:getNpcWeightMultiplier(profileId, cropName)
    return self.NPC_WEIGHT_MULTIPLIER[self:getSuitability(profileId, cropName)] or 1.0
end

function Regional:getYieldMultiplier(profileId, cropName)
    return self.YIELD_MULTIPLIER[self:getSuitability(profileId, cropName)] or 1.0
end



function Regional:getCustomProfileDirectory()
    local userProfile = resolveUserProfileAppPath()
    if userProfile ~= nil then
        return userProfile .. "modSettings/" .. tostring(self.MOD_NAME or "FS25_CropControlOverride")
            .. "/" .. self.CUSTOM_PROFILE_DIRNAME .. "/"
    end

    -- Fallback retained only for environments where getUserProfileAppPath is
    -- unavailable. Do not trust this path as the primary source because the
    -- engine global may belong to another mod at mission-load time.
    local base = g_currentModSettingsDirectory
    if base == nil or tostring(base) == "" then return nil end
    return ensureTrailingSlash(base) .. self.CUSTOM_PROFILE_DIRNAME .. "/"
end


function Regional:getBundledCustomProfileTemplatePath()
    local base = self.MOD_DIRECTORY
    if base == nil or tostring(base) == "" then return nil end
    return ensureTrailingSlash(base) .. "templates/customRegionalProfile.xml"
end

function Regional:getSeededCustomProfileTemplatePath()
    local directory = self:getCustomProfileDirectory()
    if directory == nil then return nil end
    return directory .. "_template.xml"
end

function Regional:ensureCustomProfileTemplate()
    local target = self:getSeededCustomProfileTemplatePath()
    if target == nil then
        return false, "target directory unavailable"
    end
    if fileExists(target) then
        return true, "exists"
    end

    local source = self:getBundledCustomProfileTemplatePath()
    if source == nil or not fileExists(source) then
        return false, "bundled template unavailable"
    end

    local sourceXml = loadXMLFile("CCO_CustomRegionalTemplateSource", source)
    if sourceXml == nil then
        return false, "could not open bundled template"
    end

    local root = "cropCalendarProfile"
    local targetXml = XMLFile.create("CCO_CustomRegionalTemplateTarget", target, root)
    if targetXml == nil then
        delete(sourceXml)
        return false, "could not create modSettings template"
    end

    local function copyString(attribute)
        local value = getXMLString(sourceXml, root .. "#" .. attribute)
        if value ~= nil then
            targetXml:setString(root .. "#" .. attribute, tostring(value))
        end
    end

    copyString("id")
    copyString("displayName")
    copyString("description")
    copyString("unsuitablePolicy")
    copyString("moistureAliases")

    local index = 0
    while true do
        local sourceKey = string.format("%s.crop(%d)", root, index)
        if not hasXMLProperty(sourceXml, sourceKey) then break end

        local targetKey = string.format("%s.crop(%d)", root, index)
        local cropName = getXMLString(sourceXml, sourceKey .. "#name")
        local suitability = getXMLString(sourceXml, sourceKey .. "#suitability")
        local planting = getXMLString(sourceXml, sourceKey .. "#planting")
        local harvest = getXMLString(sourceXml, sourceKey .. "#harvest")

        if cropName ~= nil then targetXml:setString(targetKey .. "#name", tostring(cropName)) end
        if suitability ~= nil then targetXml:setString(targetKey .. "#suitability", tostring(suitability)) end
        if planting ~= nil then targetXml:setString(targetKey .. "#planting", tostring(planting)) end
        if harvest ~= nil then targetXml:setString(targetKey .. "#harvest", tostring(harvest)) end

        index = index + 1
    end

    targetXml:save()
    targetXml:delete()
    delete(sourceXml)

    if fileExists(target) then
        print(("[CCO/RegionalProfiles] Created starter template at %s"):format(safeLog(target)))
        return true, "created"
    end

    return false, "template write did not produce a file"
end

function Regional:markBuiltinProfiles()
    for id, profile in pairs(self.PROFILES or {}) do
        if type(profile) == "table" then
            profile.id = profile.id or id
            if profile.isCustom ~= true then
                profile.source = self.BUILTIN_PROFILE_SOURCE
                profile.isCustom = false
            end
        end
    end
end

function Regional:removeLoadedCustomProfiles()
    local keep = {}
    for _, id in ipairs(self.PROFILE_ORDER or {}) do
        local profile = self.PROFILES[id]
        if profile ~= nil and profile.isCustom == true then
            self.PROFILES[id] = nil
        else
            table.insert(keep, id)
        end
    end
    self.PROFILE_ORDER = keep
end

function Regional:validateCustomProfile(profile)
    if type(profile) ~= "table" then return false, "invalid profile object" end
    if safeProfileId(profile.id) == nil then return false, "invalid id" end
    if profile.id == "mapDefault" then return false, "reserved id 'mapDefault'" end
    if profile.title == nil or tostring(profile.title) == "" then
        return false, "displayName is required"
    end

    local policy = string.lower(tostring(profile.unsuitablePolicy or "allow"))
    if VALID_UNSUITABLE_POLICY[policy] ~= true then
        return false, "invalid unsuitablePolicy '" .. tostring(profile.unsuitablePolicy)
            .. "' (expected allow, hide or block)"
    end
    profile.unsuitablePolicy = policy

    if type(profile.crops) ~= "table" then return false, "no crop entries" end

    local count = 0
    for cropName, cropData in pairs(profile.crops) do
        count = count + 1
        if type(cropData) ~= "table" then
            return false, "invalid crop entry for " .. tostring(cropName)
        end

        local suitability = string.lower(tostring(cropData.suitability or "normal"))
        if VALID_SUITABILITY[suitability] ~= true then
            return false, "invalid suitability '" .. tostring(cropData.suitability)
                .. "' for " .. tostring(cropName)
        end
        cropData.suitability = suitability

        local plantingOk, plantingReason = validateMonthExpression(cropData.planting)
        if not plantingOk then
            return false, tostring(cropName) .. " planting: " .. tostring(plantingReason)
        end
        local harvestOk, harvestReason = validateMonthExpression(cropData.harvest)
        if not harvestOk then
            return false, tostring(cropName) .. " harvest: " .. tostring(harvestReason)
        end

        local hasPlanting = cropData.planting ~= nil and tostring(cropData.planting) ~= ""
        local hasHarvest = cropData.harvest ~= nil and tostring(cropData.harvest) ~= ""
        if hasPlanting ~= hasHarvest then
            return false, tostring(cropName)
                .. " must define both planting and harvest, or neither"
        end
    end

    if count == 0 then return false, "no crop entries" end
    return true, nil
end

function Regional:loadCustomProfileXML(path)
    local xmlFile = loadXMLFile("CCO_CustomRegionalProfile", path)
    if xmlFile == nil then return nil, "could not open XML" end

    local root = "cropCalendarProfile"
    local profile = {
        id = safeProfileId(getXMLString(xmlFile, root .. "#id")),
        title = getXMLString(xmlFile, root .. "#displayName"),
        description = getXMLString(xmlFile, root .. "#description") or "Player-defined CCO crop calendar profile.",
        unsuitablePolicy = string.lower(tostring(getXMLString(xmlFile, root .. "#unsuitablePolicy") or "allow")),
        source = self.CUSTOM_PROFILE_SOURCE,
        isCustom = true,
        sourcePath = path,
        moistureAliases = {},
        crops = {},
    }

    for _, alias in ipairs(splitCsv(getXMLString(xmlFile, root .. "#moistureAliases"))) do
        table.insert(profile.moistureAliases, string.lower(tostring(alias)))
    end

    local seenCropNames = {}
    local duplicateCrop = nil
    local index = 0
    while true do
        local key = string.format("%s.crop(%d)", root, index)
        if not hasXMLProperty(xmlFile, key) then break end
        local cropName = getXMLString(xmlFile, key .. "#name")
        if cropName ~= nil and tostring(cropName) ~= "" then
            cropName = tostring(cropName):upper()
            if seenCropNames[cropName] == true then
                duplicateCrop = cropName
            else
                seenCropNames[cropName] = true
                profile.crops[cropName] = {
                    suitability = string.lower(tostring(getXMLString(xmlFile, key .. "#suitability") or "normal")),
                    planting = normalizeMonthSpec(getXMLString(xmlFile, key .. "#planting")),
                    harvest = normalizeMonthSpec(getXMLString(xmlFile, key .. "#harvest")),
                    source = self.CUSTOM_PROFILE_SOURCE,
                }
            end
        end
        index = index + 1
    end

    delete(xmlFile)
    if duplicateCrop ~= nil then
        return nil, "duplicate crop entry '" .. tostring(duplicateCrop) .. "'"
    end
    local ok, reason = self:validateCustomProfile(profile)
    if not ok then return nil, reason end
    return profile, nil
end

function Regional:loadCustomProfiles()
    self:markBuiltinProfiles()
    self:removeLoadedCustomProfiles()

    local directory = self:getCustomProfileDirectory()
    if directory == nil then
        print("[CCO/RegionalProfiles] Custom profile directory unavailable")
        return 0, 0
    end

    createFolder(directory)

    print(("[CCO/RegionalProfiles] Path resolution modName=%s modDir=%s profileDir=%s templateSource=%s"):format(
        safeLog(self.MOD_NAME),
        safeLog(self.MOD_DIRECTORY),
        safeLog(directory),
        safeLog(self:getBundledCustomProfileTemplatePath())))

    local templateOk, templateState = self:ensureCustomProfileTemplate()
    if not templateOk then
        print(("[CCO/RegionalProfiles] Starter template unavailable reason=%s"):format(
            safeLog(templateState)))
    elseif templateState == "exists" then
        print("[CCO/RegionalProfiles] Starter template already present; leaving player file unchanged")
    end

    local files = Files.new(directory)
    local loaded, rejected = 0, 0

    for _, entry in pairs(files.files or {}) do
        local filenameLower = tostring(entry.filename):lower()
        if not entry.isDirectory
            and filenameLower:sub(-4) == ".xml"
            and filenameLower ~= "_template.xml" then
            local profile, reason = self:loadCustomProfileXML(directory .. entry.filename)
            if profile == nil then
                rejected = rejected + 1
                print(("[CCO/RegionalProfiles] Reject custom profile file=%s reason=%s"):format(
                    safeLog(entry.filename), safeLog(reason)))
            elseif self.PROFILES[profile.id] ~= nil then
                rejected = rejected + 1
                print(("[CCO/RegionalProfiles] Reject custom profile id=%s reason=id conflicts with existing profile"):format(
                    safeLog(profile.id)))
            else
                self.PROFILES[profile.id] = profile
                table.insert(self.PROFILE_ORDER, profile.id)
                loaded = loaded + 1
                local cropCount = 0
                for _ in pairs(profile.crops or {}) do cropCount = cropCount + 1 end
                print(("[CCO/RegionalProfiles] Loaded custom profile id=%s title=%s crops=%d"):format(
                    safeLog(profile.id), safeLog(profile.title), cropCount))
            end
        end
    end

    print(("[CCO/RegionalProfiles] Custom profile scan loaded=%d rejected=%d dir=%s"):format(
        loaded, rejected, safeLog(directory)))
    return loaded, rejected
end

function Regional:getProfileDisplayTitle(profile)
    if type(profile) ~= "table" then return "Unknown" end
    local title = tostring(profile.title or profile.id or "Unknown")
    if profile.isCustom == true then return title .. " (Custom)" end
    return title
end


function Regional:getUnsuitablePolicy(profileId)
    local profile = self:getProfile(profileId)
    if profile == nil or profile.id == "mapDefault" then return "allow" end
    local policy = string.lower(tostring(profile.unsuitablePolicy or "allow"))
    if VALID_UNSUITABLE_POLICY[policy] ~= true then return "allow" end
    return policy
end

function Regional:isUnsuitableCrop(profileId, cropName)
    return self:getSuitability(profileId, cropName) == self.SUITABILITY.UNSUITABLE
end

function Regional:getUnsuitablePlayerAction(profileId, cropName)
    if not self:isUnsuitableCrop(profileId, cropName) then return "allow" end
    return self:getUnsuitablePolicy(profileId)
end

function Regional:getMoistureSystemWeatherProfile()
    local context = self:getMoistureSystemContext()
    return context ~= nil and context.profileId or nil
end

-- MoistureSystem is an OPTIONAL environmental context only.
--
-- Important interoperability rule:
-- MoistureSystem user profiles are loaded after its built-in profiles and may
-- replace a built-in profile using the same id. Therefore a matching id is only
-- an advisory mapping hint; CCO must never assume the underlying climate data is
-- still the stock MoistureSystem profile and must never modify it.
function Regional:getMoistureSystemContext()
    local mission = g_currentMission
    if mission == nil then
        return {
            detected = false,
            reason = "missionUnavailable",
        }
    end

    local ms = mission.MoistureSystem or mission.moistureSystem
    if type(ms) ~= "table" or type(ms.settings) ~= "table" then
        return {
            detected = false,
            reason = "notInstalledOrInactive",
        }
    end

    local rawId = ms.settings.weatherProfile
    if rawId == nil or tostring(rawId) == "" then
        return {
            detected = true,
            reason = "noProfileSelected",
            overrideWeather = ms.settings.overrideWeather == true,
        }
    end

    local profileId = string.lower(tostring(rawId))
    local wps = mission.WeatherProfileSystem
    local loadedProfile = nil
    if type(wps) == "table" and type(wps.profiles) == "table" then
        loadedProfile = wps.profiles[profileId] or wps.profiles[tostring(rawId)]
    end

    local displayName = profileId
    if type(loadedProfile) == "table"
        and loadedProfile.displayName ~= nil
        and tostring(loadedProfile.displayName) ~= "" then
        displayName = tostring(loadedProfile.displayName)
    end

    local suggestedProfileId = nil
    for id, profile in pairs(self.PROFILES) do
        for _, alias in ipairs(profile.moistureAliases or {}) do
            if string.lower(tostring(alias)) == profileId then
                suggestedProfileId = id
                break
            end
        end
        if suggestedProfileId ~= nil then break end
    end

    return {
        detected = true,
        profileId = profileId,
        displayName = displayName,
        overrideWeather = ms.settings.overrideWeather == true,
        profileLoaded = loadedProfile ~= nil,
        suggestedProfileId = suggestedProfileId,
        mappingKind = suggestedProfileId ~= nil and "idMapped" or "customOrUnmapped",
        readOnly = true,
    }
end

function Regional:suggestProfileFromMoistureSystem()
    local context = self:getMoistureSystemContext()
    if context == nil or context.detected ~= true or context.profileId == nil then
        return nil, nil
    end
    return context.suggestedProfileId, context.profileId
end

return Regional
