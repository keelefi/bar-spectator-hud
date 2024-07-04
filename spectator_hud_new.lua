function widget:GetInfo()
    return {
        name = "Spectator HUD New",
        desc = "Display Game Metrics",
        author = "CMDR*Zod",
        date = "2024",
        license = "GNU GPL v3 (or later)",
        layer = 1,
        handler = true,
        enabled = false
    }
end

-- TODO: Describe the widget (for on-boarding programmers)

local viewScreenWidth
local viewScreenHeight

local includeDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(includeDir .. "LuaShader.lua")

local mathfloor = math.floor
local mathabs = math.abs

local glColor = gl.Color
local glRect = gl.Rect

local gaiaID = Spring.GetGaiaTeamID()
local gaiaAllyID = select(6, Spring.GetTeamInfo(gaiaID, false))

local statsUpdateFrequency = 2        -- every 2nd frame

local widgetEnabled = nil

local haveFullView = false

local ui_scale = tonumber(Spring.GetConfigFloat("ui_scale", 1) or 1)
local scaleMultiplier = nil

local widgetDimensions = {}
local metricDimensions = {}
local titleDimensions = {}
local knobDimensions = {}
local barDimensions = {}

local textColorWhite = { 1, 1, 1, 1 }

local knobVAO = nil
local metricDisplayLists = {}

local shader = nil

local knobVertexShaderSource = [[
#version 420
#line 10000
//__ENGINEUNIFORMBUFFERDEFS__

layout (location = 0) in vec4 pos;
layout (location = 1) in vec4 posBias;
layout (location = 2) in vec4 aKnobColor;

out vec4 knobColor;

#line 15000
void main() {
    gl_Position = pos + posBias;
    knobColor = aKnobColor;
}
]]

-- Add uniform color for the whole knob
local knobFragmentShaderSource = [[
#version 420
#line 20000
out vec4 FragColor;

in vec4 knobColor;

#line 25000
void main() {
    FragColor = knobColor;
}
]]

local function coordinateScreenToOpenGL(screenCoord, screenSize)
    return screenCoord / screenSize * 2.0 - 1.0
end
local function coordinateScreenXToOpenGL(screenCoord)
    return coordinateScreenToOpenGL(screenCoord, viewScreenWidth)
end
local function coordinateScreenYToOpenGL(screenCoord)
    return coordinateScreenToOpenGL(screenCoord, viewScreenHeight)
end

-- note: the different between defaults and constants is that defaults are adjusted according to
-- screen size, widget size and ui scale. On the other hand, constants do not change.
local constants = {
    darkerBarsFactor = 0.4,
    darkerLinesFactor = 0.7,
    darkerSideKnobsFactor = 0.6,
    darkerMiddleKnobFactor = 0.75,

    darkerDecal = 0.8,

    titleDimensions = {
        heightToWidthFactor = 1.5,
    },

    knobDimensions = {
        heightToWidthFactor = 2,
    },
}

local defaults = {
    widgetDimensions = {
        width = 768,
        -- height is determined by metric height and amount of metrics

        borderPadding = 5,
        distanceFromTopBar = 10,
    },

    metricDimensions = {
        height = 70,
        -- width is same as widget width
    },

    titleDimensions = {
        fontSize = 40,

        padding = 6,
    },

    knobDimensions = {
        fontSize = 32,

        cornerSize = 8,
        outline = 4,
        padding = 8,
    },

    barDimensions = {
        padding = 12,
        lineHeight = 8,
    },
}

local metricKeys = {
    metalIncome = "metalIncome",
    energyConversionMetalIncome = "energyConversionMetalIncome",
    energyIncome = "energyIncome",
    buildPower = "buildPower",
    metalProduced = "metalProduced",
    energyProduced = "energyProduced",
    metalExcess = "metalExcess",
    energyExcess = "energyExcess",
    armyValue = "armyValue",
    defenseValue = "defenseValue",
    utilityValue = "utilityValue",
    economyValue = "economyValue",
    damageDealt = "damageDealt",
    damageReceived = "damageReceived",
    damageEfficiency = "damageEfficiency",
}

local metricsAvailable = {
    -- TODO: add i18n to the titles and tooltips (and texts?)
    { key=metricKeys.metalIncome, title="Metal Income", text="M/s",
      tooltip="Metal income per second" },
    { key=metricKeys.energyConversionMetalIncome, title="Metal Conversion", text="EC",
      tooltip="Metal income from energy conversion" },
    { key=metricKeys.energyIncome, title="Energy Income", text="E/s",
      tooltip="Energy income per second" },
    { key=metricKeys.buildPower, title="Build Power", text="BP",
      tooltip="Build Power" },
    { key=metricKeys.metalProduced, title="Metal Produced", text="MP",
      tooltip="Total metal produced" },
    { key=metricKeys.energyProduced, title="Energy Produced", text="EP",
      tooltip="Total energy produced" },
    { key=metricKeys.metalExcess, title="Metal Excess", text="ME",
      tooltip="Total metal excess" },
    { key=metricKeys.energyExcess, title="Energy Excess", text="EE",
      tooltip="Total energy excess" },
    { key=metricKeys.armyValue, title="Army Value", text="AV",
      tooltip="Army value in metal,\nincl. commander" },
    { key=metricKeys.defenseValue, title="Defense Value", text="DV",
      tooltip="Defense value in metal" },
    { key=metricKeys.utilityValue, title="Utility Value", text="UV",
      tooltip="Utility value in metal" },
    { key=metricKeys.economyValue, title="Economy Value", text="EV",
      tootltip="Economy value in metal" },
    { key=metricKeys.damageDealt, title="Damage Dealt", text="Dmg",
      tooltip="Damage dealt" },
    { key=metricKeys.damageReceived, title="Damage Received", text="DR",
      tooltip="Damage received" },
    { key=metricKeys.damageEfficiency, title="Damage Efficiency", text="D%",
      tooltip="Damage efficiency" },
}
local metricsEnabled = {}

local config = {
    -- TODO: reconsider the configurable options
    useMovingAverage = true,
    movingAverageWindowSize = 16,

    widgetScale = 0.8,

    -- TODO: reconsider the default values
    metalIncome = true,
    energyConversionMetalIncome = false,
    energyIncome = true,
    buildPower = true,
    metalProduced = true,
    energyProduced = true,
    metalExcess = false,
    energyExcess = false,
    armyValue = true,
    defenseValue = false,
    utilityValue = false,
    economyValue = false,
    damageDealt = true,
    damageReceived = false,
    damageEfficiency = false,
}

local OPTION_SPECS = {
    -- TODO: add i18n to the names and descriptions
    {
        configVariable = "widgetScale",
        name = "Widget Size",
        description = "How big widget is",
        type = "slider",
        min = 0.1,
        max = 2,
        step = 0.1,
    },
    {
        configVariable = "useMovingAverage",
        name = "Show Smoothen Values",
        description = "Smoothen out shown values by averaging over a short period of time",
        type = "bool",
    },
    {
        configVariable = "movingAverageWindowSize",
        name = "Smoothen Amount",
        description = "Amount of smoothing applied, higher is more (16 = approx. 1 second).",
        type = "slider",
        min = 4,
        max = 32,
        step = 4,
    },

    -- Note: There are more settings created dynamically from metricsAvailable (see below)
}
for _,metricAvailable in ipairs(metricsAvailable) do
    local newEntry = {}

    newEntry.configVariable = metricAvailable.key
    newEntry.name = metricAvailable.title
    newEntry.description = metricAvailable.tooltip
    newEntry.type = "bool"

    table.insert(OPTION_SPECS, newEntry)
end

local allyTeamTable = nil

local playerData = nil
local teamOrder = nil

local teamStats = nil

local function getOptionId(optionSpec)
    return "spectator_hud_new__" .. optionSpec.configVariable
end

local function getWidgetName()
    return widget:GetInfo().name
end

local function getOptionValue(optionSpec)
    if optionSpec.type == "slider" then
        return config[optionSpec.configVariable]
    elseif optionSpec.type == "bool" then
        return config[optionSpec.configVariable]
    elseif optionSpec.type == "select" then
        -- we have text, we need index
        for i, v in ipairs(optionSpec.options) do
            if config[optionSpec.configVariable] == v then
                return i
            end
        end
    end
end

local reInit -- symbol declaration, function definition later

local function setOptionValue(optionSpec, value, doReInit)
    if optionSpec.type == "slider" then
        config[optionSpec.configVariable] = value
    elseif optionSpec.type == "bool" then
        config[optionSpec.configVariable] = value
    elseif optionSpec.type == "select" then
        -- we have index, we need text
        config[optionSpec.configVariable] = optionSpec.options[value]
    end

    if doReInit then
        reInit()
    end
end

local function createOnChange(optionSpec)
    return function(i, value, force)
        setOptionValue(optionSpec, value, true)
    end
end

local function createOptionFromSpec(optionSpec)
    local option = table.copy(optionSpec)
    option.configVariable = nil
    option.enabled = nil
    option.id = getOptionId(optionSpec)
    option.widgetname = getWidgetName()
    option.value = getOptionValue(optionSpec)
    option.onchange = createOnChange(optionSpec)
    return option
end

local function checkAndUpdateHaveFullView()
    local haveFullViewOld = haveFullView
    haveFullView = select(2, Spring.GetSpectatingState())
    return haveFullView ~= haveFullViewOld
end


local unitCache = {}
local cachedTotals = {}
local unitDefsToTrack = {}

local function buildUnitDefs()
    local function isCommander(unitDefID, unitDef)
        return unitDef.customParams.iscommander
    end

    local function isReclaimerUnit(unitDefID, unitDef)
        return unitDef.isBuilder and not unitDef.isFactory
    end

    local function isEnergyConverter(unitDefID, unitDef)
        return unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency
    end

    local function isBuildPower(unitDefID, unitDef)
        return unitDef.buildSpeed and (unitDef.buildSpeed > 0)
    end

    local function isArmyUnit(unitDefID, unitDef)
        -- anything with a least one weapon and speed above zero is considered an army unit
        return unitDef.weapons and (#unitDef.weapons > 0) and unitDef.speed and (unitDef.speed > 0)
    end

    local function isDefenseUnit(unitDefID, unitDef)
        return unitDef.weapons and (#unitDef.weapons > 0) and (not unitDef.speed or (unitDef.speed == 0))
    end

    local function isUtilityUnit(unitDefID, unitDef)
        return unitDef.customParams.unitgroup == 'util'
    end

    local function isEconomyBuilding(unitDefID, unitDef)
        return (unitDef.customParams.unitgroup == 'metal') or (unitDef.customParams.unitgroup == 'energy')
    end

    unitDefsToTrack = {}
    unitDefsToTrack.commanderUnitDefs = {}
    unitDefsToTrack.reclaimerUnitDefs = {}
    unitDefsToTrack.energyConverterDefs = {}
    unitDefsToTrack.buildPowerDefs = {}
    unitDefsToTrack.armyUnitDefs = {}
    unitDefsToTrack.defenseUnitDefs = {}
    unitDefsToTrack.utilityUnitDefs = {}
    unitDefsToTrack.economyBuildingDefs = {}

    for unitDefID, unitDef in ipairs(UnitDefs) do
        if isCommander(unitDefID, unitDef) then
            unitDefsToTrack.commanderUnitDefs[unitDefID] = true
        end
        if isReclaimerUnit(unitDefID, unitDef) then
            unitDefsToTrack.reclaimerUnitDefs[unitDefID] = { unitDef.metalMake, unitDef.energyMake }
        end
        if isEnergyConverter(unitDefID, unitDef) then
            unitDefsToTrack.energyConverterDefs[unitDefID] = tonumber(unitDef.customParams.energyconv_capacity)
        end
        if isBuildPower(unitDefID, unitDef) then
            unitDefsToTrack.buildPowerDefs[unitDefID] = unitDef.buildSpeed
        end
        if isArmyUnit(unitDefID, unitDef) then
            unitDefsToTrack.armyUnitDefs[unitDefID] = { unitDef.metalCost, unitDef.energyCost }
        end
        if isDefenseUnit(unitDefID, unitDef) then
            unitDefsToTrack.defenseUnitDefs[unitDefID] = { unitDef.metalCost, unitDef.energyCost }
        end
        if isUtilityUnit(unitDefID, unitDef) then
            unitDefsToTrack.utilityUnitDefs[unitDefID] = { unitDef.metalCost, unitDef.energyCost }
        end
        if isEconomyBuilding(unitDefID, unitDef) then
            unitDefsToTrack.economyBuildingDefs[unitDefID] = { unitDef.metalCost, unitDef.energyCost }
        end
    end
end

local function addToUnitCache(teamID, unitID, unitDefID)
    local function addToUnitCacheInternal(cache, teamID, unitID, value)
        if unitCache[teamID][cache] then
            if not unitCache[teamID][cache][unitID] then
                if cachedTotals[teamID][cache] then
                    local valueToAdd = 0
                    if unitCache[cache].add then
                        valueToAdd = unitCache[cache].add(unitID, value)
                    end
                    cachedTotals[teamID][cache] = cachedTotals[teamID][cache] + valueToAdd
                end
                unitCache[teamID][cache][unitID] = value
            end
        end
    end

    if unitDefsToTrack.reclaimerUnitDefs[unitDefID] then
        addToUnitCacheInternal("reclaimerUnits", teamID, unitID,
                       unitDefsToTrack.reclaimerUnitDefs[unitDefID])
    end
    if unitDefsToTrack.energyConverterDefs[unitDefID] then
        addToUnitCacheInternal("energyConverters", teamID, unitID,
                       unitDefsToTrack.energyConverterDefs[unitDefID])
    end
    if unitDefsToTrack.buildPowerDefs[unitDefID] then
        addToUnitCacheInternal("buildPower", teamID, unitID,
                       unitDefsToTrack.buildPowerDefs[unitDefID])
    end
    if unitDefsToTrack.armyUnitDefs[unitDefID] then
        addToUnitCacheInternal("armyUnits", teamID, unitID,
                       unitDefsToTrack.armyUnitDefs[unitDefID])
    end
    if unitDefsToTrack.defenseUnitDefs[unitDefID] then
        addToUnitCacheInternal("defenseUnits", teamID, unitID,
                       unitDefsToTrack.defenseUnitDefs[unitDefID])
    end
    if unitDefsToTrack.utilityUnitDefs[unitDefID] then
        addToUnitCacheInternal("utilityUnits", teamID, unitID,
                       unitDefsToTrack.utilityUnitDefs[unitDefID])
    end
    if unitDefsToTrack.economyBuildingDefs[unitDefID] then
        addToUnitCacheInternal("economyBuildings", teamID, unitID,
                       unitDefsToTrack.economyBuildingDefs[unitDefID])
    end
end

local function removeFromUnitCache(teamID, unitID, unitDefID)
    local function removeFromUnitCacheInternal(cache, teamID, unitID, value)
        if unitCache[teamID][cache] then
            if unitCache[teamID][cache][unitID] then
                if cachedTotals[teamID][cache] then
                    local valueToRemove = 0
                    if unitCache[cache].remove then
                        valueToRemove = unitCache[cache].remove(unitID, value)
                    end
                    cachedTotals[teamID][cache] = cachedTotals[teamID][cache] - valueToRemove
                end
                unitCache[teamID][cache][unitID] = nil
            end
        end
    end

    if unitDefsToTrack.reclaimerUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("reclaimerUnits", teamID, unitID,
                       unitDefsToTrack.reclaimerUnitDefs[unitDefID])
    end
    if unitDefsToTrack.energyConverterDefs[unitDefID] then
        removeFromUnitCacheInternal("energyConverters", teamID, unitID,
                       unitDefsToTrack.energyConverterDefs[unitDefID])
    end
    if unitDefsToTrack.buildPowerDefs[unitDefID] then
        removeFromUnitCacheInternal("buildPower", teamID, unitID,
                       unitDefsToTrack.buildPowerDefs[unitDefID])
    end
    if unitDefsToTrack.armyUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("armyUnits", teamID, unitID,
                       unitDefsToTrack.armyUnitDefs[unitDefID])
    end
    if unitDefsToTrack.defenseUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("defenseUnits", teamID, unitID,
                       unitDefsToTrack.defenseUnitDefs[unitDefID])
    end
    if unitDefsToTrack.utilityUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("utilityUnits", teamID, unitID,
                       unitDefsToTrack.utilityUnitDefs[unitDefID])
    end
    if unitDefsToTrack.economyBuildingDefs[unitDefID] then
        removeFromUnitCacheInternal("economyBuildings", teamID, unitID,
                       unitDefsToTrack.economyBuildingDefs[unitDefID])
    end
end

local function buildUnitCache()
    unitCache = {}
    cachedTotals = {}

    unitCache.reclaimerUnits = {
        add = nil,
        update = function(unitID, value)
            local reclaimMetal = 0
            local reclaimEnergy = 0
            local metalMake, metalUse, energyMake, energyUse = Spring.GetUnitResources(unitID)
            if metalMake then
                if value[1] then
                    reclaimMetal = metalMake - value[1]
                else
                    reclaimMetal = metalMake
                end
                if value[2] then
                    reclaimEnergy = energyMake - value[2]
                else
                    reclaimEnergy = energyMake
                end
            end
            return { reclaimMetal, reclaimEnergy }
        end,
        remove = nil,
    }
    unitCache.energyConverters = {
        add = nil,
        update = function(unitID, value)
            local metalMake, metalUse, energyMake, energyUse = Spring.GetUnitResources(unitID)
            if metalMake then
                return metalMake
            end
            return 0
        end,
        remove = nil,
    }
    unitCache.buildPower = {
        add = function(unitID, value)
            return value
        end,
        update = nil,
        remove = function(unitID, value)
            return value
        end,
    }
    unitCache.armyUnits = {
        add = function(unitID, value)
            local result = value[1]
            --if options.useMetalEquivalent70 then
            --    result = result + (value[2] / 70)
            --end
            return result
        end,
        update = nil,
        remove = function(unitID, value)
            local result = value[1]
            --if options.useMetalEquivalent70 then
            --    result = result + (value[2] / 70)
            --end
            return result
        end,
    }
    unitCache.defenseUnits = unitCache.armyUnits
    unitCache.utilityUnits = unitCache.armyUnits
    unitCache.economyBuildings = unitCache.armyUnits

    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                unitCache[teamID] = {}
                cachedTotals[teamID] = {}
                unitCache[teamID].reclaimerUnits = {}
                cachedTotals[teamID].reclaimerUnits = 0
                unitCache[teamID].energyConverters = {}
                cachedTotals[teamID].energyConverters = 0
                unitCache[teamID].buildPower = {}
                cachedTotals[teamID].buildPower = 0
                unitCache[teamID].armyUnits = {}
                cachedTotals[teamID].armyUnits = 0
                unitCache[teamID].defenseUnits = {}
                cachedTotals[teamID].defenseUnits = 0
                unitCache[teamID].utilityUnits = {}
                cachedTotals[teamID].utilityUnits = 0
                unitCache[teamID].economyBuildings = {}
                cachedTotals[teamID].economyBuildings = 0
                local unitIDs = Spring.GetTeamUnits(teamID)
                for i=1,#unitIDs do
                    local unitID = unitIDs[i]
                    if not Spring.GetUnitIsBeingBuilt(unitID) then
                        local unitDefID = Spring.GetUnitDefID(unitID)
                        addToUnitCache(teamID, unitID, unitDefID)
                    end
                end
            end
        end
    end
end

local function buildPlayerData()
    playerData = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            local teamList = Spring.GetTeamList(allyID)
            for _,teamID in ipairs(teamList) do
                local playerName = nil
                local playerID = Spring.GetPlayerList(teamID, false)
                if playerID and playerID[1] then
                    -- it's a player
                    playerName = select(1, Spring.GetPlayerInfo(playerID[1], false))
                else
                    local aiName = Spring.GetGameRulesParam("ainame_" .. teamID)
                    if aiName then
                        -- it's AI
                        playerName = aiName
                    else
                        -- player is gone
                        playerName = "(gone)"
                    end
                end

                playerData[teamID] = {}
                playerData[teamID].name = playerName

                local teamColor = { Spring.GetTeamColor(teamID) }
                playerData[teamID].color = teamColor
            end
        end
    end
end

local function makeDarkerColor(color, factor, alpha)
    local newColor = {}

    if factor then
        newColor[1] = color[1] * factor
        newColor[2] = color[2] * factor
        newColor[3] = color[3] * factor
    else
        newColor[1] = color[1]
        newColor[2] = color[2]
        newColor[3] = color[3]
    end

    if alpha then
        newColor[4] = alpha
    else
        newColor[4] = color[4]
    end

    return newColor
end

local function round(num, idp)
    local mult = 10 ^ (idp or 0)
    return mathfloor(num * mult + 0.5) / mult
end

local function formatResources(amount, short)
    local thousand = 1000
    local tenThousand = 10 * thousand
    local million = thousand * thousand
    local tenMillion = 10 * million

    if short then
        if amount >= tenMillion then
            return string.format("%dM", amount / million)
        elseif amount >= million then
            return string.format("%.1fM", amount / million)
        elseif amount >= tenThousand then
            return string.format("%dk", amount / thousand)
        elseif amount >= thousand then
            return string.format("%.1fk", amount / thousand)
        else
            return string.format("%d", amount)
        end
    end

    local function addSpaces(number)
        if number >= 1000 then
            return string.format("%s %03d", addSpaces(mathfloor(number / 1000)), number % 1000)
        end
        return number
    end
    return addSpaces(round(amount))
end

local function buildAllyTeamTable()
    -- Data structure layout:
    -- allyTeamTable
    --  - allyTeamIndex
    --      - colorCaptain
    --      - colorBar
    --      - colorLine
    --      - colorKnobSide
    --      - colorKnobMiddle
    --      - name
    --      - spawn?
    --      - teams
    allyTeamTable = {}

    local allyTeamIndex = 1
    for _,allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            allyTeamTable[allyTeamIndex] = {}

            local teamList = Spring.GetTeamList(allyID)
            local colorCaptain = playerData[teamList[1]].color
            allyTeamTable[allyTeamIndex].color = colorCaptain
            allyTeamTable[allyTeamIndex].colorBar = makeDarkerColor(colorCaptain, constants.darkerBarsFactor)
            allyTeamTable[allyTeamIndex].colorLine = makeDarkerColor(colorCaptain, constants.darkerLinesFactor)
            allyTeamTable[allyTeamIndex].colorKnobSide = makeDarkerColor(colorCaptain, constants.darkerSideKnobsFactor)
            allyTeamTable[allyTeamIndex].colorKnobMiddle = makeDarkerColor(colorCaptain, constants.darkerMiddleKnobFactor)
            allyTeamTable[allyTeamIndex].name = string.format("Team %d", allyID)

            allyTeamTable[allyTeamIndex].teams = {}

            local teamIndex = 1
            for _,teamID in ipairs(teamList) do
                allyTeamTable[allyTeamIndex].teams[teamIndex] = teamID
                teamIndex = teamIndex + 1
            end

            allyTeamIndex = allyTeamIndex + 1
        end
    end
end

local function getAmountOfAllyTeams()
    local amountOfAllyTeams = 0
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            amountOfAllyTeams = amountOfAllyTeams + 1
        end
    end
    return amountOfAllyTeams
end

local function buildMetricsEnabled()
    metricsEnabled = {}
    local index = 1
    for _,metric in ipairs(metricsAvailable) do
        if config[metric.key] then
            local metricEnabled = table.copy(metric)
            metricEnabled.id = index
            metricsEnabled[index] = metricEnabled
            index = index + 1
        end
    end
end

local function getWidgetHeightMax()
    -- TODO: check that we don't overlap with advplayerlist
    return viewScreenHeight / 2
end

local function calculateWidgetDimensions()
    scaleMultiplier = ui_scale * config.widgetScale * viewScreenWidth / 3840

    widgetDimensions.height = math.min(
        math.floor(defaults.metricDimensions.height * #metricsEnabled * scaleMultiplier),
        getWidgetHeightMax())

    scaleMultiplier = widgetDimensions.height / (defaults.metricDimensions.height * #metricsEnabled)

    widgetDimensions.width = math.floor(defaults.widgetDimensions.width * scaleMultiplier)

    widgetDimensions.borderPadding = mathfloor(defaults.widgetDimensions.borderPadding * scaleMultiplier)

    widgetDimensions.right = viewScreenWidth
    widgetDimensions.left = viewScreenWidth - widgetDimensions.width

    widgetDimensions.distanceFromTopBar = mathfloor(defaults.widgetDimensions.distanceFromTopBar * scaleMultiplier)
    if WG['topbar'] then
        local topBarPosition = WG['topbar'].GetPosition()
        widgetDimensions.top = topBarPosition[2] - widgetDimensions.distanceFromTopBar
    else
        widgetDimensions.top = viewScreenHeight
    end
    widgetDimensions.bottom = widgetDimensions.top - widgetDimensions.height
end

local function calculateMetricDimensions()
    metricDimensions.height = widgetDimensions.height / #metricsEnabled
    metricDimensions.width = widgetDimensions.width
end

local function calculateTitleDimensions()
    titleDimensions.fontSize = math.floor(defaults.titleDimensions.fontSize * scaleMultiplier)
    titleDimensions.padding = math.floor(defaults.titleDimensions.padding * scaleMultiplier)

    titleDimensions.height = metricDimensions.height
    titleDimensions.width = math.floor(titleDimensions.height * constants.titleDimensions.heightToWidthFactor)

    titleDimensions.left = widgetDimensions.left + widgetDimensions.borderPadding + titleDimensions.padding
    titleDimensions.right = titleDimensions.left + titleDimensions.width

    titleDimensions.horizontalCenter = math.floor((titleDimensions.right + titleDimensions.left) / 2)
    titleDimensions.verticalCenterOffset = math.floor(titleDimensions.height / 2)
end

local function calculateKnobDimensions()
    knobDimensions.fontSize = math.floor(defaults.knobDimensions.fontSize * scaleMultiplier)
    knobDimensions.padding = math.floor(defaults.knobDimensions.padding * scaleMultiplier)

    knobDimensions.height = metricDimensions.height - 2 * knobDimensions.padding
    knobDimensions.width = knobDimensions.height * constants.knobDimensions.heightToWidthFactor

    knobDimensions.cornerSize = math.floor(defaults.knobDimensions.cornerSize * scaleMultiplier)
    knobDimensions.outline = math.floor(defaults.knobDimensions.outline * scaleMultiplier)

    knobDimensions.leftKnobLeft = titleDimensions.right + knobDimensions.padding
    knobDimensions.leftKnobRight = knobDimensions.leftKnobLeft + knobDimensions.width

    knobDimensions.rightKnobRight = widgetDimensions.right - widgetDimensions.borderPadding - knobDimensions.padding
    knobDimensions.rightKnobLeft = knobDimensions.rightKnobRight - knobDimensions.width
end

local function calculateBarDimensions()
    barDimensions.padding = math.floor(defaults.barDimensions.padding * scaleMultiplier)
    barDimensions.paddingFromMetric = knobDimensions.padding + barDimensions.padding

    local barHeight = knobDimensions.height - 2 * barDimensions.padding
    local lineHeight = defaults.barDimensions.lineHeight * scaleMultiplier
    barDimensions.lineMiddleOffset = math.floor((barHeight - lineHeight) / 2)

    barDimensions.left = knobDimensions.leftKnobRight + 1
    barDimensions.right = knobDimensions.rightKnobLeft - 1

    barDimensions.width = barDimensions.right - barDimensions.left - knobDimensions.width
end

local function calculateDimensions()
    calculateWidgetDimensions()
    calculateMetricDimensions()
    calculateTitleDimensions()
    calculateKnobDimensions()
    calculateBarDimensions()
end

local function updateMetricTextTooltips()
    if WG['tooltip'] then
        for metricIndex,metric in ipairs(metricsEnabled) do
            local bottom = widgetDimensions.top - metricIndex * metricDimensions.height
            local top = bottom + metricDimensions.height

            local left = titleDimensions.left
            local right = titleDimensions.right

            WG['tooltip'].AddTooltip(
                string.format("spectator_hud_vsmode_%d", metric.id),
                { left, bottom, right, top },
                metric.tooltip,
                nil,
                metric.title
            )
        end
    end
end

local function initMovingAverage(movingAverage)
    if not config.useMovingAverage then
        movingAverage.average = 0
        return
    end

    movingAverage.average = 0
    movingAverage.index = 0
    movingAverage.data = {}
    for i=1,config.movingAverageWindowSize do
        movingAverage.data[i] = 0
    end
end

local function updateMovingAverage(movingAverage, newValue)
    if not config.useMovingAverage then
        movingAverage.average = newValue
        return
    end

    if movingAverage.index == 0 then
        for i=1,config.movingAverageWindowSize do
            movingAverage.data[i] = newValue
        end
        movingAverage.average = newValue
        movingAverage.index = 1
    end

    local newIndex = movingAverage.index + 1
    newIndex = newIndex <= config.movingAverageWindowSize and newIndex or 1
    movingAverage.index = newIndex

    local oldValue = movingAverage.data[newIndex]
    movingAverage.data[newIndex] = newValue

    movingAverage.average = movingAverage.average + (newValue - oldValue) / config.movingAverageWindowSize

    if (movingAverage.average * config.movingAverageWindowSize) < 0.5 then
        movingAverage.average = 0
    end
end

local function getOneStat(statKey, teamID)
    -- TODO: refactor the function to be able to fetch multiple metrics at the same time.
    -- For example, metalProduced and metalExcess are fetched with the same call to
    -- Spring.GetTeamResourceStats(teamID, "m"), so calling this function twice is a waste.

    local result = 0

    if statKey == metricKeys.metalIncome then
        result = select(4, Spring.GetTeamResources(teamID, "metal")) or 0
    elseif statKey == metricKeys.energyConversionMetalIncome then
        for unitID,_ in pairs(unitCache[teamID].energyConverters) do
            result = result + unitCache.energyConverters.update(unitID, 0)
        end
    elseif statKey == metricKeys.energyIncome then
        result = select(4, Spring.GetTeamResources(teamID, "energy")) or 0
    elseif statKey == metricKeys.buildPower then
        result = cachedTotals[teamID].buildPower
    elseif statKey == metricKeys.metalProduced then
        --local metalUsed, metalProduced, metalExcessed, metalReceived, metalSent
        local _, metalProduced, _, _, _ = Spring.GetTeamResourceStats(teamID, "m")
        result = metalProduced
    elseif statKey == metricKeys.energyProduced then
        local _, energyProduced, _, _, _ = Spring.GetTeamResourceStats(teamID, "e")
        result = energyProduced
    elseif statKey == metricKeys.metalExcess then
        local _, _, metalExcess, _, _ = Spring.GetTeamResourceStats(teamID, "m")
        result = metalExcess
    elseif statKey == metricKeys.energyExcess then
        local _, _, energyExcess, _, _ = Spring.GetTeamResourceStats(teamID, "e")
        result = energyExcess
    elseif statKey == metricKeys.armyValue then
        result = cachedTotals[teamID].armyUnits
    elseif statKey == metricKeys.defenseValue then
        result = cachedTotals[teamID].defenseUnits
    elseif statKey == metricKeys.utilityValue then
        result = cachedTotals[teamID].utilityUnits
    elseif statKey == metricKeys.economyValue then
        result = cachedTotals[teamID].economyBuildings
    elseif statKey == metricKeys.damageDealt then
        local historyMax = Spring.GetTeamStatsHistory(teamID)
        local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
        local damageDealt = 0
        if statsHistory and #statsHistory > 0 then
            damageDealt = statsHistory[1].damageDealt
        end
        result = damageDealt
    elseif statKey == metricKeys.damageReceived then
        local historyMax = Spring.GetTeamStatsHistory(teamID)
        local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
        local damageReceived = 0
        if statsHistory and #statsHistory > 0 then
            damageReceived = statsHistory[1].damageReceived
        end
        result = damageReceived
    elseif statKey == metricKeys.damageEfficiency then
        local historyMax = Spring.GetTeamStatsHistory(teamID)
        local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
        local damageDealt = 0
        local damageReceived = 0
        if statsHistory and #statsHistory > 0 then
            damageDealt = statsHistory[1].damageDealt
            damageReceived = statsHistory[1].damageReceived
        end
        if damageReceived < 1 then
            -- avoid dividing by 0
            damageReceived = 1
        end
        result = mathfloor(damageDealt * 100 / damageReceived)
    end

    return round(result)
end

local function createTeamStats()
    -- Note: The game uses it's own ID's for AllyTeams and Teams (commonly, allyTeamID and teamID). To optimize lookup,
    -- we use our own indexing instead.

    -- Note2: Our rendering code assumes there's exactly two AllyTeams (in addition to GaiaTeam). However, while we
    -- could hard-code the amount of AllyTeams in statistics code, there's no benefit in doing so. Therefore, the stats
    -- code covers the general case, too.

    -- Data structure layout is as follows:
    -- teamStats:
    --  - metric
    --      - aggregates
    --          - allyTeam 1
    --          - allyTeam 2
    --      - allyTeams
    --          - allyTeam 1
    --              - team 1
    --              - team 2
    --              - ...
    --          - allyTeam 2
    --              - team 1
    --              - team 2
    --              - ...

    teamStats = {}

    for metricIndex,metric in ipairs(metricsEnabled) do
        teamStats[metricIndex] = {}
        teamStats[metricIndex].aggregates = {}
        teamStats[metricIndex].allyTeams = {}
        for allyIndex,allyTeam in ipairs(allyTeamTable) do
            teamStats[metricIndex].aggregates[allyIndex] = 0
            teamStats[metricIndex].allyTeams[allyIndex] = {}
            for teamIndex,teamID in ipairs(allyTeam.teams) do
                teamStats[metricIndex].allyTeams[allyIndex][teamIndex] = {}
                initMovingAverage(teamStats[metricIndex].allyTeams[allyIndex][teamIndex])
            end
        end
    end
end

local function updateStats()
    for metricIndex,metric in ipairs(metricsEnabled) do
        for allyIndex,allyTeam in ipairs(allyTeamTable) do
            local teamAggregate = 0
            for teamIndex,teamID in ipairs(allyTeam.teams) do
                local valueTeam = getOneStat(metric.key, teamID)
                updateMovingAverage(teamStats[metricIndex].allyTeams[allyIndex][teamIndex], valueTeam)
                teamAggregate = teamAggregate + teamStats[metricIndex].allyTeams[allyIndex][teamIndex].average
            end

            teamStats[metricIndex].aggregates[allyIndex] = teamAggregate
        end
    end
end

local function drawMetricKnobText(left, bottom, right, top, text)
    -- note: call this function within a font:Begin() - font:End() block

    --local knobTextAreaWidth = right - left - 2 * metricDimensions.knobOutline
    local knobTextAreaWidth = right - left - 2 * knobDimensions.outline
    --local fontSizeSmaller = fontSizeMetricKnob
    local fontSizeSmaller = knobDimensions.fontSize
    local textWidth = font:GetTextWidth(text)
    while textWidth * fontSizeSmaller > knobTextAreaWidth do
        fontSizeSmaller = fontSizeSmaller - 1
    end

    --font:Begin()
    --    font:SetTextColor(textColorWhite)
        font:Print(
            text,
            mathfloor((right + left) / 2),
            mathfloor((top + bottom) / 2),
            fontSizeSmaller,
            'cvO'
        )
    --font:End()
end

local colorKnobMiddleGrey = { 0.5, 0.5, 0.5, 1 }
local function drawMetricBar(left, bottom, right, top, indexLeft, indexRight, metricIndex, mouseOver)
    local valueLeft = teamStats[metricIndex].aggregates[indexLeft]
    local valueRight = teamStats[metricIndex].aggregates[indexRight]

    local barTop = top - barDimensions.paddingFromMetric
    local barBottom = bottom + barDimensions.paddingFromMetric

    local barLength = barDimensions.width

    local leftBarWidth
    if valueLeft > 0 or valueRight > 0 then
        leftBarWidth = mathfloor(barLength * valueLeft / (valueLeft + valueRight))
    else
        leftBarWidth = mathfloor(barLength / 2)
    end
    local rightBarWidth = barLength - leftBarWidth

    if (not mouseOver) or ((valueLeft == 0) and (valueRight == 0)) then
        glColor(allyTeamTable[indexLeft].colorBar)
        glRect(
            left,
            barBottom,
            left + leftBarWidth,
            barTop
        )

        glColor(allyTeamTable[indexRight].colorBar)
        glRect(
            right - rightBarWidth,
            barBottom,
            right,
            barTop
        )

        local lineBottom = barBottom + barDimensions.lineMiddleOffset
        local lineTop = barTop - barDimensions.lineMiddleOffset

        glColor(allyTeamTable[indexLeft].colorLine)
        glRect(
            left,
            lineBottom,
            left + leftBarWidth,
            lineTop
        )

        glColor(allyTeamTable[indexRight].colorLine)
        glRect(
            right - rightBarWidth,
            lineBottom,
            right,
            lineTop
        )
    else
        -- do "rainbow" colors
        local scalingFactor = barLength / (valueLeft + valueRight)

        local lineStart
        local lineEnd = left
        for teamIndex,teamID in ipairs(allyTeamTable[indexLeft].teams) do
            local teamValue = teamStats[metricIndex].allyTeams[indexLeft][teamIndex].average
            local teamColor = playerData[teamID].color

            lineStart = lineEnd
            lineEnd = lineStart + mathfloor(scalingFactor * teamValue)

            glColor(teamColor)
            glRect(
                lineStart,
                barBottom,
                lineEnd,
                barTop
            )
        end

        local lineStart
        local lineEnd = right - rightBarWidth
        for teamIndex,teamID in ipairs(allyTeamTable[indexRight].teams) do
            local teamValue = teamStats[metricIndex].allyTeams[indexRight][teamIndex].average
            local teamColor = playerData[teamID].color

            lineStart = lineEnd
            lineEnd = lineStart + mathfloor(scalingFactor * teamValue)

            glColor(teamColor)
            glRect(
                lineStart,
                barBottom,
                lineEnd,
                barTop
            )
        end
    end
end

local function drawBars()
    local indexLeft = teamOrder and teamOrder[1] or 1
    local indexRight = teamOrder and teamOrder[2] or 2

    local mouseX, mouseY = Spring.GetMouseState()
    local mouseOnBar= false
    if (mouseX > barDimensions.left) and (mouseX < barDimensions.right) and
        (mouseY > widgetDimensions.bottom) and (mouseY < widgetDimensions.top) then
        mouseOnBar = true
    end

    for metricIndex,metric in ipairs(metricsEnabled) do
        local bottom = widgetDimensions.top - metricIndex * metricDimensions.height
        local top = bottom + metricDimensions.height

        local mouseOver = false
        if mouseOnBar then
            if (mouseY > bottom) and (mouseY < top) then
                mouseOver = true
            end
        end

        drawMetricBar(
            knobDimensions.leftKnobRight,
            bottom,
            knobDimensions.rightKnobLeft,
            top,
            indexLeft,
            indexRight,
            metricIndex,
            mouseOver
        )
    end
end

local function drawText()
    local indexLeft = teamOrder and teamOrder[1] or 1
    local indexRight = teamOrder and teamOrder[2] or 2

    font:Begin()
        font:SetTextColor(textColorWhite)

        for metricIndex,metric in ipairs(metricsEnabled) do
            local bottom = widgetDimensions.top - metricIndex * metricDimensions.height
            local top = bottom + metricDimensions.height
            local left = widgetDimensions.left
            local right = widgetDimensions.right

            -- draw metric text, i.e. M/s etc
            local textHCenter = titleDimensions.horizontalCenter
            local textVCenter = bottom + titleDimensions.verticalCenterOffset
            local textText = metricsEnabled[metricIndex].text

            font:Print(
                textText,
                textHCenter,
                textVCenter,
                titleDimensions.fontSize,
                'cvo'
            )

            local valueLeft = teamStats[metricIndex].aggregates[indexLeft]
            local valueRight = teamStats[metricIndex].aggregates[indexRight]

            -- draw left knob text
            drawMetricKnobText(
                knobDimensions.leftKnobLeft,
                bottom,
                knobDimensions.leftKnobRight,
                top,
                formatResources(valueLeft, true)
            )

            -- draw right knob text
            drawMetricKnobText(
                knobDimensions.rightKnobLeft,
                bottom,
                knobDimensions.rightKnobRight,
                top,
                formatResources(valueRight, true)
            )

            -- draw middle knob text
            local barLength = knobDimensions.rightKnobLeft - knobDimensions.leftKnobRight - knobDimensions.width
            local leftBarWidth
            if valueLeft > 0 or valueRight > 0 then
                leftBarWidth = mathfloor(barLength * valueLeft / (valueLeft + valueRight))
            else
                leftBarWidth = mathfloor(barLength / 2)
            end
            local rightBarWidth = barLength - leftBarWidth

            local relativeLead = 0
            local relativeLeadMax = 999
            local relativeLeadString = nil
            if valueLeft > valueRight then
                if valueRight > 0 then
                    relativeLead = mathfloor(100 * mathabs(valueLeft - valueRight) / valueRight)
                else
                    relativeLeadString = "∞"
                end
            elseif valueRight > valueLeft then
                if valueLeft > 0 then
                    relativeLead = mathfloor(100 * mathabs(valueRight - valueLeft) / valueLeft)
                else
                    relativeLeadString = "∞"
                end
            end
            if relativeLead > relativeLeadMax then
                relativeLeadString = string.format("%d+%%", relativeLeadMax)
            elseif not relativeLeadString then
                relativeLeadString = string.format("%d%%", relativeLead)
            end

            drawMetricKnobText(
                knobDimensions.leftKnobRight + leftBarWidth + 1,
                bottom,
                knobDimensions.rightKnobLeft - rightBarWidth - 1,
                top,
                relativeLeadString
            )
        end  -- for-loop
    font:End()
end

local function createMetricDisplayLists()
    metricDisplayLists = {}

    local left = widgetDimensions.left
    local right = widgetDimensions.right
    for metricIndex,metric in ipairs(metricsEnabled) do
        local bottom = widgetDimensions.top - metricIndex * metricDimensions.height
        local top = bottom + metricDimensions.height

        local newDisplayList = gl.CreateList(function ()
            WG.FlowUI.Draw.Element(
                left,
                bottom,
                right,
                top,
                1, 1, 1, 1,
                1, 1, 1, 1
            )
        end)
        table.insert(metricDisplayLists, newDisplayList)
    end
end

local function deleteMetricDisplayLists()
    for _,metricDisplayList in ipairs(metricDisplayLists) do
        gl.DeleteList(metricDisplayList)
    end
end

local function createKnobVertices(vertexMatrix, left, bottom, right, top, cornerRadius, cornerTriangleAmount)
    local function addCornerVertices(vertexMatrix, startIndex, startAngle, originX, originY, cornerRadiusX, cornerRadiusY)
        -- first, add the corner vertex
        vertexMatrix[startIndex] = originX --rectRight
        vertexMatrix[startIndex+1] = originY -- rectBottom
        vertexMatrix[startIndex+2] = 0
        vertexMatrix[startIndex+3] = 1

        local alpha = math.pi / 2 / cornerTriangleAmount
        for sliceIndex=0,cornerTriangleAmount do
            local x = originX + cornerRadiusX * (math.cos(startAngle + alpha * sliceIndex))
            local y = originY + cornerRadiusY * (math.sin(startAngle + alpha * sliceIndex))

            local vertexIndex = startIndex + (sliceIndex+1)*4

            vertexMatrix[vertexIndex] = x
            vertexMatrix[vertexIndex+1] = y
            vertexMatrix[vertexIndex+2] = 0
            vertexMatrix[vertexIndex+3] = 1
        end
    end

    local function addRectangleVertices(vertexMatrix, startIndex, rectLeft, rectBottom, rectRight, rectTop)
        vertexMatrix[startIndex] = rectLeft
        vertexMatrix[startIndex+1] = rectTop
        vertexMatrix[startIndex+2] = 0 
        vertexMatrix[startIndex+3] = 1

        vertexMatrix[startIndex+4] = rectRight
        vertexMatrix[startIndex+5] = rectTop
        vertexMatrix[startIndex+6] = 0 
        vertexMatrix[startIndex+7] = 1

        vertexMatrix[startIndex+8] = rectLeft
        vertexMatrix[startIndex+9] = rectBottom
        vertexMatrix[startIndex+10] = 0 
        vertexMatrix[startIndex+11] = 1

        vertexMatrix[startIndex+12] = rectRight
        vertexMatrix[startIndex+13] = rectBottom
        vertexMatrix[startIndex+14] = 0 
        vertexMatrix[startIndex+15] = 1
    end

    local vertexIndex = 1

    local amountOfVertices = (cornerTriangleAmount+2)*4 + 5 * 4
    local amountOfTriangles = cornerTriangleAmount*4 + 5 * 2

    local cornerRadiusX = coordinateScreenXToOpenGL(cornerRadius) + 1.0
    local cornerRadiusY = coordinateScreenYToOpenGL(cornerRadius) + 1.0

    local leftOpenGL = coordinateScreenXToOpenGL(left)
    local bottomOpenGL = coordinateScreenYToOpenGL(bottom)
    local rightOpenGL = coordinateScreenXToOpenGL(right)
    local topOpenGL = coordinateScreenYToOpenGL(top)

    local alpha = math.pi / 2 / cornerTriangleAmount
    local b = cornerRadius * math.cos(alpha)
    local a = cornerRadius * math.sin(alpha)

    -- 1. create top-left corner triangles
    addCornerVertices(
        vertexMatrix,
        vertexIndex,
        math.pi/2,
        leftOpenGL + cornerRadiusX,
        topOpenGL - cornerRadiusY,
        cornerRadiusX,
        cornerRadiusY
    )
    vertexIndex = vertexIndex + 4 + (cornerTriangleAmount+1)*4

    -- 2. create top-mid rectangle triangles
    addRectangleVertices(
        vertexMatrix,
        vertexIndex,
        leftOpenGL + cornerRadiusX,
        topOpenGL - cornerRadiusY,
        rightOpenGL - cornerRadiusX,
        topOpenGL
    )
    vertexIndex = vertexIndex + 16

    -- 3. create top-right corner triangles
    addCornerVertices(
        vertexMatrix,
        vertexIndex,
        0,
        rightOpenGL - cornerRadiusX,
        topOpenGL - cornerRadiusY,
        cornerRadiusX,
        cornerRadiusY
    )
    vertexIndex = vertexIndex + 4 + (cornerTriangleAmount+1)*4

    -- 4. create mid-left rectangle triangles
    addRectangleVertices(
        vertexMatrix,
        vertexIndex,
        leftOpenGL,
        bottomOpenGL + cornerRadiusY,
        leftOpenGL + cornerRadiusX,
        topOpenGL - cornerRadiusY
    )
    vertexIndex = vertexIndex + 16

    -- 5. create mid-mid rectangle triangles
    addRectangleVertices(
        vertexMatrix,
        vertexIndex,
        leftOpenGL + cornerRadiusX,
        bottomOpenGL + cornerRadiusY,
        rightOpenGL - cornerRadiusX,
        topOpenGL - cornerRadiusY
    )
    vertexIndex = vertexIndex + 16

    -- 6. create mid-right rectangle triangles
    addRectangleVertices(
        vertexMatrix,
        vertexIndex,
        rightOpenGL - cornerRadiusX,
        bottomOpenGL + cornerRadiusY,
        rightOpenGL,
        topOpenGL - cornerRadiusY
    )
    vertexIndex = vertexIndex + 16

    -- 7. create bottom-left corner triangles
    addCornerVertices(
        vertexMatrix,
        vertexIndex,
        math.pi,
        leftOpenGL + cornerRadiusX,
        bottomOpenGL + cornerRadiusY,
        cornerRadiusX,
        cornerRadiusY
    )
    vertexIndex = vertexIndex + 4 + (cornerTriangleAmount+1)*4

    -- 8. create bottom-mid rectangle triangles
    addRectangleVertices(
        vertexMatrix,
        vertexIndex,
        leftOpenGL + cornerRadiusX,
        bottomOpenGL + cornerRadiusY,
        rightOpenGL - cornerRadiusX,
        bottomOpenGL
    )
    vertexIndex = vertexIndex + 16

    -- 9. create bottom-left corner triangles
    addCornerVertices(
        vertexMatrix,
        vertexIndex,
        -math.pi/2,
        rightOpenGL - cornerRadiusX,
        bottomOpenGL + cornerRadiusY,
        cornerRadiusX,
        cornerRadiusY
    )
    vertexIndex = vertexIndex + 4 + (cornerTriangleAmount+1)*4

    return vertexIndex
end

local function insertKnobIndices(indexData, vertexStartIndex, cornerTriangleAmount)
    local function insertCornerIndices(currentVertexOffset)
        for i=1,cornerTriangleAmount do
            table.insert(indexData, currentVertexOffset + 0)
            table.insert(indexData, currentVertexOffset + i)
            table.insert(indexData, currentVertexOffset + i+1)
        end
        return currentVertexOffset + cornerTriangleAmount + 2
    end

    local function insertRectangleIndices(currentVertexOffset)
        table.insert(indexData, currentVertexOffset)
        table.insert(indexData, currentVertexOffset+1)
        table.insert(indexData, currentVertexOffset+2)
        table.insert(indexData, currentVertexOffset+1)
        table.insert(indexData, currentVertexOffset+2)
        table.insert(indexData, currentVertexOffset+3)
        return currentVertexOffset + 4
    end

    local vertexOffset = vertexStartIndex

    -- 1
    vertexOffset = insertCornerIndices(vertexOffset)

    -- 2
    vertexOffset = insertRectangleIndices(vertexOffset)

    -- 3
    vertexOffset = insertCornerIndices(vertexOffset)

    -- 4
    vertexOffset = insertRectangleIndices(vertexOffset)

    -- 5
    vertexOffset = insertRectangleIndices(vertexOffset)

    -- 6
    vertexOffset = insertRectangleIndices(vertexOffset)

    -- 7
    vertexOffset = insertCornerIndices(vertexOffset)

    -- 8
    vertexOffset = insertRectangleIndices(vertexOffset)

    -- 9
    vertexOffset = insertCornerIndices(vertexOffset)

    return vertexOffset
end

local function createKnobVAO()
    local instanceCount = #metricsEnabled * 3
    local cornerTriangleAmount = 6
    local width = knobDimensions.width
    local height = knobDimensions.height
    local cornerRadius = knobDimensions.cornerSize
    local border = knobDimensions.outline

    if knobVAO then
        knobVAO.vaoInner:Delete()
        knobVAO.vaoOutline:Delete()
    end
    knobVAO = {}
    knobVAO.vaoInner = gl.GetVAO()
    knobVAO.vaoOutline = gl.GetVAO()

    knobVAO.cornerTriangleAmount = cornerTriangleAmount

    -- build vertexVBO
    local vertexDataOutline = {}
    createKnobVertices(
        vertexDataOutline,
        0,
        0,
        width,
        height,
        cornerRadius,
        cornerTriangleAmount
    )
    local vertexDataInner = {}
    createKnobVertices(
        vertexDataInner,
        border,
        border,
        width - border,
        height - border,
        cornerRadius,
        cornerTriangleAmount
    )

    local vertexVBOInner = gl.GetVBO(GL.ARRAY_BUFFER, false)
    vertexVBOInner:Define(#vertexDataInner/4, {
        { id = 0, name = "aPos", size = 4 },
    })
    vertexVBOInner:Upload(vertexDataInner)

    local vertexVBOOutline = gl.GetVBO(GL.ARRAY_BUFFER, false)
    vertexVBOOutline:Define(#vertexDataOutline/4, {
        { id = 0, name = "aPos", size = 4 },
    })
    vertexVBOOutline:Upload(vertexDataOutline)

    -- build indexVBO
    local indexVBOInner = gl.GetVBO(GL.ELEMENT_ARRAY_BUFFER, false)
    local indexVBOOutline = gl.GetVBO(GL.ELEMENT_ARRAY_BUFFER, false)
    local indexData = {}
    local vertexOffset = 0
    vertexOffset = insertKnobIndices(indexData, vertexOffset, cornerTriangleAmount)
    indexVBOInner:Define(#indexData, GL.UNSIGNED_INT)
    indexVBOInner:Upload(indexData)
    indexVBOOutline:Define(#indexData, GL.UNSIGNED_INT)
    indexVBOOutline:Upload(indexData)

    -- create and attach instanceVBO (note: the data is populated separately)
    knobVAO.instanceVBOInner = gl.GetVBO(GL.ARRAY_BUFFER, true)
    knobVAO.instanceVBOInner:Define(instanceCount, {
        { id = 1, name = "posBias", size=4 },
        { id = 2, name = "aKnobColor", size=4 },
    })

    knobVAO.instanceVBOOutline = gl.GetVBO(GL.ARRAY_BUFFER, true)
    knobVAO.instanceVBOOutline:Define(instanceCount, {
        { id = 1, name = "posBias", size=4 },
        { id = 2, name = "aKnobColor", size=4 },
    })

    knobVAO.instances = 0

    knobVAO.vaoInner:AttachVertexBuffer(vertexVBOInner)
    knobVAO.vaoInner:AttachInstanceBuffer(knobVAO.instanceVBOInner)
    knobVAO.vaoInner:AttachIndexBuffer(indexVBOInner)

    knobVAO.vaoOutline:AttachVertexBuffer(vertexVBOOutline)
    knobVAO.vaoOutline:AttachInstanceBuffer(knobVAO.instanceVBOOutline)
    knobVAO.vaoOutline:AttachIndexBuffer(indexVBOOutline)

    return knobVAO
end

local function addKnob(knobVAO, left, bottom, color)
    local instanceData = {}

    -- posBias
    table.insert(instanceData, coordinateScreenXToOpenGL(left)+1.0)
    table.insert(instanceData, coordinateScreenYToOpenGL(bottom)+1.0)
    table.insert(instanceData, 0.0)
    table.insert(instanceData, 0.0)

    -- aKnobColor
    instanceData[5] = color[1]
    instanceData[6] = color[2]
    instanceData[7] = color[3]
    instanceData[8] = color[4]
    knobVAO.instanceVBOInner:Upload(instanceData, -1, knobVAO.instances)

    local greyFactor = 0.5
    instanceData[5] = color[1] * greyFactor
    instanceData[6] = color[2] * greyFactor
    instanceData[7] = color[3] * greyFactor
    instanceData[8] = color[4] * greyFactor
    knobVAO.instanceVBOOutline:Upload(instanceData, -1, knobVAO.instances)

    knobVAO.instances = knobVAO.instances + 1

    return knobVAO.instances
end

local function addSideKnobs()
    local indexLeft = teamOrder and teamOrder[1] or 1
    local indexRight = teamOrder and teamOrder[2] or 2

    local left = widgetDimensions.left
    local right = widgetDimensions.right
    for metricIndex,metric in ipairs(metricsEnabled) do
        local bottom = widgetDimensions.top - metricIndex * metricDimensions.height
        local top = bottom + metricDimensions.height

        local knobBottom = bottom + knobDimensions.padding

        local leftKnobColor = allyTeamTable[indexLeft].colorKnobSide
        local rightKnobColor = allyTeamTable[indexRight].colorKnobSide

        addKnob(knobVAO, knobDimensions.leftKnobLeft, knobBottom, leftKnobColor)
        addKnob(knobVAO, knobDimensions.rightKnobLeft, knobBottom, rightKnobColor)
    end
end

local function addMiddleKnobs()
    local left = widgetDimensions.left
    local right = widgetDimensions.right
    for metricIndex,metric in ipairs(metricsEnabled) do
        local bottom = widgetDimensions.top - metricIndex * metricDimensions.height
        local top = bottom + metricDimensions.height

        local textBottom = bottom + titleDimensions.padding

        local middleKnobLeft = (knobDimensions.rightKnobLeft + knobDimensions.leftKnobRight) / 2 - knobDimensions.width
        local middleKnobBottom = textBottom

        local middleKnobColor = colorKnobMiddleGrey

        addKnob(knobVAO, middleKnobLeft, middleKnobBottom, middleKnobColor)
    end
end

local modifyKnobInstanceData = {0, 0, 0, 0, 0, 0, 0, 0}
local function modifyKnob(knobVAO, instance, left, bottom, color)
    -- note: instead of using a local variable instanceData that rebuild a table every time this function is called,
    -- we use the global variable modifyKnobInstanceData to avoid recreating a table and instead reusing the table.
    --local instanceData = {}

    -- posBias
    modifyKnobInstanceData[1] = coordinateScreenXToOpenGL(left) + 1.0
    modifyKnobInstanceData[2] = coordinateScreenYToOpenGL(bottom) + 1.0
    modifyKnobInstanceData[3] = 0.0
    modifyKnobInstanceData[4] = 0.0

    -- aKnobColor
    modifyKnobInstanceData[5] = color[1]
    modifyKnobInstanceData[6] = color[2]
    modifyKnobInstanceData[7] = color[3]
    modifyKnobInstanceData[8] = color[4]
    knobVAO.instanceVBOInner:Upload(modifyKnobInstanceData, -1, instance-1)

    local greyFactor = 0.5
    modifyKnobInstanceData[5] = color[1] * greyFactor
    modifyKnobInstanceData[6] = color[2] * greyFactor
    modifyKnobInstanceData[7] = color[3] * greyFactor
    modifyKnobInstanceData[8] = color[4] * greyFactor
    knobVAO.instanceVBOOutline:Upload(modifyKnobInstanceData, -1, instance-1)
end

local function moveMiddleKnobs()
    local indexLeft = teamOrder and teamOrder[1] or 1
    local indexRight = teamOrder and teamOrder[2] or 2

    local left = widgetDimensions.left
    local right = widgetDimensions.right
    local instanceOffset = 2 * #metricsEnabled
    for metricIndex,metric in ipairs(metricsEnabled) do
        local bottom = widgetDimensions.top - metricIndex * metricDimensions.height

        local valueLeft = teamStats[metricIndex].aggregates[indexLeft]
        local valueRight = teamStats[metricIndex].aggregates[indexRight]
    
        local knobBottom = bottom + knobDimensions.padding

        local barLength = barDimensions.width

        local leftBarWidth
        if valueLeft > 0 or valueRight > 0 then
            leftBarWidth = mathfloor(barLength * valueLeft / (valueLeft + valueRight))
        else
            leftBarWidth = mathfloor(barLength / 2)
        end

        local middleKnobLeft = knobDimensions.leftKnobRight + leftBarWidth + 1

        local middleKnobColor
        if valueLeft > valueRight then
            middleKnobColor = allyTeamTable[indexLeft].colorKnobMiddle
        elseif valueRight > valueLeft then
            middleKnobColor = allyTeamTable[indexRight].colorKnobMiddle
        else
            -- color grey if even
            middleKnobColor = colorKnobMiddleGrey
        end

        local instanceID = instanceOffset + metricIndex

        modifyKnob(knobVAO, instanceID, middleKnobLeft, knobBottom, middleKnobColor)
    end
end

local function deleteKnobVAO()
    if knobVAO then
        knobVAO.vaoInner:Delete()
        knobVAO.vaoOutline:Delete()
        knobVAO = nil
    end
end

local function drawKnobVAO()
    shader:Activate()

    local amountOfTriangles = 5*2 + 4*knobVAO.cornerTriangleAmount
    knobVAO.vaoOutline:DrawElements(GL.TRIANGLES, amountOfTriangles*3, 0, knobVAO.instances)
    knobVAO.vaoInner:DrawElements(GL.TRIANGLES, amountOfTriangles*3, 0, knobVAO.instances)

    shader:Deactivate()
end

local function initGL4()
    local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs()
    knobVertexShaderSource = knobVertexShaderSource:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)
    knobFragmentShaderSource = knobFragmentShaderSource:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)
    shader = LuaShader(
        {
            vertex = knobVertexShaderSource,
            fragment = knobFragmentShaderSource,
        },
        "spectator_hud"
    )
    local shaderCompiled = shader:Initialize()
    return shaderCompiled
end

local function init()
    viewScreenWidth, viewScreenHeight = Spring.GetViewGeometry()

    buildMetricsEnabled()

    calculateDimensions()

    buildPlayerData()
    buildAllyTeamTable()

    if #metricsEnabled > 0 then
        createKnobVAO()
        addSideKnobs()
        addMiddleKnobs()
    end

    createMetricDisplayLists()

    buildUnitDefs()
    buildUnitCache()

    updateMetricTextTooltips()

    createTeamStats()

    if haveFullView then
        updateStats()

        moveMiddleKnobs()
    end
end

local function deInit()
    deleteMetricDisplayLists()
    deleteKnobVAO()
end

reInit = function ()
    deInit()
    init()
end

function widget:Initialize()
    -- Note: Widget is logically enabled only if there are exactly two teams
    -- If yes, we disable ecostats
    -- If no, we enable ecostats
    -- TODO: should enabling ecostats be an option?
    widgetEnabled = getAmountOfAllyTeams() == 2
    if widgetEnabled then
        if widgetHandler:IsWidgetKnown("Ecostats") then
            widgetHandler:DisableWidget("Ecostats")
        end
    else
        if widgetHandler:IsWidgetKnown("Ecostats") then
            widgetHandler:EnableWidget("Ecostats")
        end
        return
    end

    if not gl.CreateShader then
        -- no shader support, so just remove the widget itself, especially for headless
        widgetHandler:RemoveWidget()
        return
    end

    if not initGL4() then
        widgetHandler:RemoveWidget()
        return
    end

    if WG['options'] ~= nil then
        WG['options'].addOptions(table.map(OPTION_SPECS, createOptionFromSpec))
    end

    checkAndUpdateHaveFullView()

    font = WG['fonts'].getFont()

    init()
end

function widget:Shutdown()
    if WG['options'] ~= nil then
        WG['options'].removeOptions(table.map(OPTION_SPECS, getOptionId))
    end

    deInit()

    if shader then
        shader:Finalize()
    end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
    if not haveFullView then
        return
    end

    if unitCache[unitTeam] then
        addToUnitCache(unitTeam, unitID, unitDefID)
    end
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if not haveFullView then
        return
    end

    -- only track units that have been completely built
    if Spring.GetUnitIsBeingBuilt(unitID) then
        return
    end

    if unitCache[oldTeam] then
        removeFromUnitCache(oldTeam, unitID, unitDefID)
    end

    if unitCache[newTeam] then
        addToUnitCache(newTeam, unitID, unitDefID)
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
    if not haveFullView then
        return
    end

    -- unit might've been a nanoframe
    if Spring.GetUnitIsBeingBuilt(unitID) then
        return
    end

    if unitCache[unitTeam] then
        removeFromUnitCache(unitTeam, unitID, unitDefID)
    end
end


function widget:ViewResize()
    reInit()
end

function widget:GameFrame(frameNum)
    if not widgetEnabled then
        return
    end

    if checkAndUpdateHaveFullView() then
        if haveFullView then
            init()
        else
            deInit()
        end
    end

    if not haveFullView then
        return
    end

    if (frameNum > 0) and (not teamOrder) then
        -- collect player start positions
        local teamStartAverages = {}
        for _, allyID in ipairs(Spring.GetAllyTeamList()) do
            if allyID ~= gaiaAllyID then
                local accumulator = { x = 0, z = 0 }
                local teamList = Spring.GetTeamList(allyID)
                for _,teamID in ipairs(teamList) do
                    local x, _, z = Spring.GetTeamStartPosition(teamID)
                    accumulator.x = accumulator.x + x
                    accumulator.z = accumulator.z + z
                end
                local startAverage= { x = accumulator.x / #teamList, z = accumulator.z / #teamList }
                table.insert(teamStartAverages, { allyID, startAverage })
            end
        end

        local _,rotY,_ = Spring.GetCameraRotation()

        -- sort averages and create team order (from left to right)
        table.sort(teamStartAverages, function (left, right)
            return ((left[2].x * math.cos(rotY) + left[2].z * math.sin(rotY)) <
                    (right[2].x * math.cos(rotY) + right[2].z * math.sin(rotY)))
        end)
        teamOrder = {}
        for i,teamStart in ipairs(teamStartAverages) do
            teamOrder[i] = teamStart[1] + 1    -- note: allyTeam ID's start from 0
        end

        -- update knob colors by overwriting all knobs
        if knobVAO.instances > 0 then
            knobVAO.instances = 0
        end
        addSideKnobs()
        addMiddleKnobs()
    end

    if frameNum % statsUpdateFrequency == 1 then
        updateStats()

        moveMiddleKnobs()
    end
end

function widget:Update(dt)
    if checkAndUpdateHaveFullView() then
        if haveFullView then
            init()
        else
            deInit()
        end
    end
end


function widget:DrawScreen()
    if (not widgetEnabled) or (not haveFullView) then
        return
    end

    for _, metricDisplayList in ipairs(metricDisplayLists) do
        gl.CallList(metricDisplayList)
    end

    if knobVAO then
        drawKnobVAO()
    end
    drawBars()
    drawText()
end

function widget:GetConfigData()
    local result = {}
    for _, option in ipairs(OPTION_SPECS) do
        result[option.configVariable] = getOptionValue(option)
    end
    return result
end

function widget:SetConfigData(data)
    for _, option in ipairs(OPTION_SPECS) do
        local configVariable = option.configVariable
        if data[configVariable] ~= nil then
            setOptionValue(option, data[configVariable], false)
        end
    end
end
