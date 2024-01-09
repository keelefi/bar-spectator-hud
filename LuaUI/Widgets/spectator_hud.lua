function widget:GetInfo()
    return {
        name = "SpectatorHUD",
        desc = "Display Game Metrics",
        author = "CMDR*Zod",
        date = "2023",
        license = "GNU GPL v3 (or later)",
        layer = 1,
        enabled = true
    }
end

--[[
Widget that displays various game metrics. It has the following modes:

1. Income view
Shows metal and energy income per second.
In this mode only mexes and metal converters are considered. Reclaim is ignored.

2. Metal produced view

3. Build power view
Adds up all the build power of the player or team

4. Army value view
Shows army metal cost.

5. Army size view
Shows army size in units.

6. Damage done view

7. Damage received view

8. Damage efficiency view

For each statistic, you can decide if you want to sort per team or per player

The layout of the widget is as follows:

    --------------------------------------------
   |  Select View             | VS |  Sorting  |
    --------------------------------------------
   | P1  <- Bar1                           ->   |
   | P2  <- Bar2                       ->       |
   | P3  <- Bar3                ->              |
   | P4  <- Bar4               ->               |
   | P5  <- Bar5         ->                     |
   | P6  <- Bar6      ->                        |
    --------------------------------------------

where

* Select View is a combobox where the user can select which view to display
* Sorting is a switch the switches between sorting per team or per player
* VS is a toggle between versus mode and normal mode
* P1-P6 are unique player identifiers called player decals (currently just a color box)
* Bar1-Bar6 are value bars showing linear relationship between the values
* Every bar has a text on top showing approximate value as textual represenation
]]

local haveFullView = false

local ui_scale = tonumber(Spring.GetConfigFloat("ui_scale", 1) or 1)
local widgetScale = 0.8

local widgetDimensions = {}
local headerDimensions = {}

local topBarPosition
local topBarShowButtons

local viewScreenWidth, viewScreenHeight

local buttonSideLength

local statsBarWidth, statsBarHeight
local statsAreaWidth, statsAreaHeight

local vsModeMetricWidth, vsModeMetricHeight
local vsModeMetricsAreaWidth, vsModeMetricsAreaHeight

local metricChangeBottom
local sortingTop, sortingBottom, sortingLeft, sortingRight
local toggleVSModeTop, toggleVSModeBottom, toggleVSModeLeft, toggleVSModeRight
local statsAreaTop, statsAreaBottom, statsAreaLeft, statsAreaRight
local vsModeMetricsAreaTop, vsModeMetricsAreaBottom, vsModeMetricsAreaLeft, vsModeMetricsAreaRight

local backgroundShader

local headerLabel = "Metal Income"
local headerLabelDefault = "Metal Income"
--[[ note: headerLabelDefault is a silly hack. GetTextHeight will return different value depending
     on the provided text. Therefore, we need to always provide it with the same text or otherwise
     the widget will keep on resizing depending on the header label.
]]

local sortingBackgroundDisplayList
local toggleVSModeBackgroundDisplayList

local statsAreaBackgroundDisplayList
local vsModeBackgroundDisplayLists = {}

local textColorWhite = { 1, 1, 1, 1 }
local font
local fontSize
local fontSizeMetric
local fontSizeVSBar
local fontSizeVSModeKnob

-- TODO: this constant need to be scaled with widget size, screen size and ui_scale
local statBarHeightToHeaderHeight = 1.0

local distanceFromTopBar

local borderPadding
local headerLabelPadding
local buttonPadding
local teamDecalPadding
local teamDecalShrink
local vsModeMetricIconPadding
local teamDecalHeight
local vsModeMetricIconHeight
local vsModeMetricIconWidth
local barOutlineWidth
local barOutlinePadding
local barOutlineCornerSize
local teamDecalCornerSize
local vsModeBarTextPadding
local vsModeDeltaPadding
local vsModeKnobHeight
local vsModeKnobWidth
local vsModeMetricKnobPadding
local vsModeKnobOutline
local vsModeKnobCornerSize
local vsModeBarTriangleSize

local vsModeBarMarkerWidth, vsModeBarMarkerHeight

local vsModeBarPadding
local vsModeLineHeight

local vsModeBarTooltipOffsetX
local vsModeBarTooltipOffsetY

-- note: the different between defaults and constants is that defaults are adjusted according to
-- screen size, widget size and ui scale. On the other hand, constants do not change.
local constants = {
    darkerBarsFactor = 0.6,
    darkerLinesFactor = 0.9,
    darkerSideKnobsFactor = 0.8,
    darkerMiddleKnobFactor = 0.9,
}

local defaults = {
    fontSize = 64 * 1.2,
    fontSizeVSModeKnob = 32,

    distanceFromTopBar = 10,

    borderPadding = 5,
    headerLabelPadding = 20,
    buttonPadding = 8,
    teamDecalPadding = 6,
    teamDecalShrink = 6,
    vsModeMetricIconPadding = 6,
    barOutlineWidth = 4,
    barOutlinePadding = 4,
    barOutlineCornerSize = 8,
    teamDecalCornerSize = 8,
    vsModeBarTextPadding = 20,
    vsModeDeltaPadding = 20,
    vsModeMetricKnobPadding = 20,
    vsModeKnobOutline =  4,
    vsModeKnobCornerSize = 5,
    vsModeBarTriangleSize = 5,

    vsModeBarMarkerWidth = 2,
    vsModeBarMarkerHeight = 8,

    vsModeBarPadding = 8,
    vsModeLineHeight = 12,

    vsModeBarTooltipOffsetX = 60,
    vsModeBarTooltipOffsetY = -60,
}

local tooltipNames = {}

local sortingTooltipName = "spectator_hud_sorting"
local sortingTooltipTitle = "Sorting"

local toggleVSModeTooltipName = "spectator_hud_versus_mode"
local toggleVSModeTooltipTitle = "Versus Mode"
local toggleVSModeTooltipText = "Toggle Versus Mode on/off"

local gaiaID = Spring.GetGaiaTeamID()
local gaiaAllyID = select(6, Spring.GetTeamInfo(gaiaID, false))

local statsUpdateFrequency = 5        -- every 5 frames

local headerTooltipName = "spectator_hud_header"
local headerTooltipTitle = "Select Metric"
local metricsAvailable = {
    { key="metalIncome", title="Metal Income", text="M/s", defaultValue=true,
      tooltip="Metal income per second" },
    { key="reclaimMetalIncome", title="Metal Reclaim", text="MR", defaultValue=false,
      tooltip="Metal income from reclaim" },
    { key="energyConversionMetalIncome", title="Metal Conversion", text="EC", defaultValue=false,
      tooltip="Metal income from energy conversion" },
    { key="energyIncome", title="Energy Income", text="E/s", defaultValue=true,
      tooltip="Energy income per second" },
    { key="reclaimEnergyIncome", title="Energy Reclaim", text="ER", defaultValue=false,
      tooltip="Energy income from reclaim" },
    { key="buildPower", title="Build Power", text="BP", defaultValue=true,
      tooltip="Build Power" },
    { key="metalProduced", title="Metal Produced", text="MP", defaultValue=true,
      tooltip="Total metal produced" },
    { key="energyProduced", title="Energy Produced", text="EP", defaultValue=true,
      tooltip="Total energy produced" },
    { key="armyValue", title="Army Value", text="AV", defaultValue=true,
      tooltip="Army value in metal,\nincl. commander" },
    { key="defenseValue", title="Defense Value", text="DV", defaultValue=false,
      tooltip="Defense value in metal" },
    { key="utilityValue", title="Utility Value", text="UV", defaultValue=false,
      tooltip="Utility value in metal" },
    { key="economyValue", title="Economy Value", text="EV", defaultValue=false,
      tootltip="Economy value in metal" },
    { key="damageDealt", title="Damage Dealt", text="Dmg", defaultValue=true,
      tooltip="Damage dealt" },
    { key="damageReceived", title="Damage Received", text="DR", defaultValue=false,
      tooltip="Damage received" },
    { key="damageEfficiency", title="Damage Efficiency", text="D%", defaultValue=false,
      tooltip="Damage efficiency" },
}
local metricsEnabled = {}

local vsMode = false
local vsModeEnabled = false

local metricChosenKey = "metalIncome"
local metricChangeInProgress = false
local sortingChosen = "player"
local teamStats = {}
local vsModeStats = {}

local playerData = nil
local teamOrder = nil

local images = {
    sortingPlayer = "LuaUI/Images/spectator_hud/sorting-player.png",
    sortingTeam = "LuaUI/Images/spectator_hud/sorting-team.png",
    sortingTeamAggregate = "LuaUI/Images/spectator_hud/sorting-plus.png",
    toggleVSMode = "LuaUI/Images/spectator_hud/button-vs.png",
}

local options = {
    -- note: metrics table is built from metricsAvailable during configuration load

    useMetalEquivalent70 = false,
    subtractReclaimFromIncome = false,
}
-- silly hack to serve first load of widget
if not options.metrics then
    options.metrics = {}
    for _,metric in ipairs(metricsAvailable) do
        options.metrics[metric.key] = metric.defaultValue
    end
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
            else
                Spring.Echo(string.format("WARNING: addToUnitCache(), unitID %d already added", unitID))
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
            else
                Spring.Echo(string.format("WARNING: removeFromUnitCache(), unitID %d not in unit cache", unitID))
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
            if options.useMetalEquivalent70 then
                result = result + (value[2] / 70)
            end
            return result
        end,
        update = nil,
        remove = function(unitID, value)
            local result = value[1]
            if options.useMetalEquivalent70 then
                result = result + (value[2] / 70)
            end
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
    return math.floor(num * mult + 0.5) / mult
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
            return string.format("%s %03d", addSpaces(math.floor(number / 1000)), number % 1000)
        end
        return number
    end
    return addSpaces(round(amount))
end

local function teamHasCommander(teamID)
    local hasCom = false
	for commanderDefID, _ in pairs(unitDefsToTrack.commanderUnitDefs) do
		if Spring.GetTeamUnitDefCount(teamID, commanderDefID) > 0 then
			local unitList = Spring.GetTeamUnitsByDefs(teamID, commanderDefID)
			for i = 1, #unitList do
				if not Spring.GetUnitIsDead(unitList[i]) then
					hasCom = true
				end
			end
		end
	end
	return hasCom
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

local function getAmountOfTeams()
    local amountOfTeams = 0
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            local teamList = Spring.GetTeamList(allyID)
            amountOfTeams = amountOfTeams + #teamList
        end
    end
    return amountOfTeams
end

local function getMetricFromID(id)
    for _,metric in ipairs(metricsEnabled) do
        if metric.id == id then
            return metric
        end
    end
    return nil
end

local function getMetricChosen()
    for _, currentMetric in ipairs(metricsEnabled) do
        if metricChosenKey == currentMetric.key then
            return currentMetric
        end
    end
    return nil
end

local updateHeaderTooltip -- symbol declaration, function definition later
local function setMetricChosen(metricKey, ignoreUpdateHeader)
    local metricChosenKeyOld = metricChosenKey
    metricChosenKey = metricKey
    local metricChosen = getMetricChosen()
    if not metricChosen then
        metricChosenKey = metricChosenKeyOld
        return
    end

    if ignoreUpdateHeader then
        return
    end

    headerLabel = metricChosen.title
    updateHeaderTooltip()
end

local function buildMetricsEnabled()
    metricsEnabled = {}
    local metricChosenEnabled = false
    index = 1
    for _,metric in ipairs(metricsAvailable) do
        local key = metric.key
        if options.metrics[key] then
            local metricEnabled = table.copy(metric)
            metricEnabled.id = index
            metricsEnabled[index] = metricEnabled
            if metricChosenKey == metricEnabled.key then
                metricChosenEnabled = true
            end
            index = index + 1
        end
    end

    -- nasty hack: currently, widget always requires at least one metric to be enabled.
    -- in case user disables all metrics, just hard-code the widget to enable back the first metric.
    -- this causes a nasty confusion where options think the first metric is disabled, while it isn't.
    -- however, after enabling any metric, options and widget are in sync again.
    if #metricsEnabled == 0 then
        local firstMetricAvailable = table.copy(metricsAvailable[1])
        firstMetricAvailable.id = 1
        metricsEnabled[1] = firstMetricAvailable
        options.metrics[firstMetricAvailable.key]= true
    end

    if not metricChosenEnabled then
        local firstAvailableMetric = metricsEnabled[1]
        setMetricChosen(firstAvailableMetric.key)
    end
end

local function getAmountOfMetrics()
    local totalMetricsAvailable = 0
    for _,metric in ipairs(metricsEnabled) do
        if metric then
            totalMetricsAvailable = totalMetricsAvailable + 1
        end
    end
    return totalMetricsAvailable
end

local function sortStats()
    local result = {}

    if sortingChosen == "player" then
        local temporaryTable = {}
        for _, ally in pairs(teamStats) do
            for _, team in pairs(ally) do
                table.insert(temporaryTable, team)
            end
        end
        table.sort(temporaryTable, function(left, right)
            -- note: we sort in "reverse" i.e. highest value first
            return left.value > right.value
        end)
        result = temporaryTable     -- TODO: remove temporaryTable and use result directly
    elseif sortingChosen == "team" then
        local allyTotals = {}
        local index = 1
        for allyID, ally in pairs(teamStats) do
            local currentAllyTotal = 0
            for _, team in pairs(ally) do
                currentAllyTotal = currentAllyTotal + team.value
            end
            allyTotals[index] = {}
            allyTotals[index].id = allyID
            allyTotals[index].total = currentAllyTotal
            index = index + 1
        end
        table.sort(allyTotals, function(left, right)
            return left.total > right.total
        end)
        local temporaryTable = {}
        for _, ally in pairs(allyTotals) do
            local allyTeamTable = {}
            for _, team in pairs(teamStats[ally.id]) do
                table.insert(allyTeamTable, team)
            end
            table.sort(allyTeamTable, function(left, right)
                return left.value > right.value
            end)
            for _, team in pairs(allyTeamTable) do
                table.insert(temporaryTable, team)
            end
        end
        result = temporaryTable
    elseif sortingChosen == "teamaggregate" then
        local allyTotals = {}
        local index = 1
        for allyID, ally in pairs(teamStats) do
            local currentAllyTotal = 0
            for _, team in pairs(ally) do
                currentAllyTotal = currentAllyTotal + team.value
            end
            local allyTeamCaptainID = Spring.GetTeamList(allyID)[1]
            allyTotals[index] = {}
            allyTotals[index].color = playerData[allyTeamCaptainID].color
            allyTotals[index].value = currentAllyTotal
            allyTotals[index].captainID = allyTeamCaptainID
            index = index + 1
        end
        table.sort(allyTotals, function(left, right)
            return left.value > right.value
        end)
        result = allyTotals
    end

    return result
end

local function getOneStat(statKey, teamID)
    local result = 0

    if statKey == "metalIncome" then
        result = select(4, Spring.GetTeamResources(teamID, "metal")) or 0
        if options.subtractReclaimFromIncome then
            local metalReclaim = getOneStat("reclaimMetalIncome", teamID)
            result = result - metalReclaim
        end
    elseif statKey == "reclaimMetalIncome" then
        for unitID,unitPassive in pairs(unitCache[teamID].reclaimerUnits) do
            result = result + unitCache.reclaimerUnits.update(unitID, unitPassive)[1]
        end
        result = math.max(0, result)
    elseif statKey == "energyConversionMetalIncome" then
        for unitID,_ in pairs(unitCache[teamID].energyConverters) do
            result = result + unitCache.energyConverters.update(unitID, 0)
        end
    elseif statKey == "energyIncome" then
        result = select(4, Spring.GetTeamResources(teamID, "energy")) or 0
        if options.subtractReclaimFromIncome then
            local energyReclaim = getOneStat("reclaimEnergyIncome", teamID)
            result = result - energyReclaim
        end
    elseif statKey == "reclaimEnergyIncome" then
        for unitID,unitPassive in pairs(unitCache[teamID].reclaimerUnits) do
            result = result + unitCache.reclaimerUnits.update(unitID, unitPassive)[2]
        end
        result = math.max(0, result)
    elseif statKey == "buildPower" then
        result = cachedTotals[teamID].buildPower
    elseif statKey == "metalProduced" then
        local historyMax = Spring.GetTeamStatsHistory(teamID)
        local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
        if statsHistory and #statsHistory > 0 then
            result = statsHistory[1].metalProduced
        end
    elseif statKey == "energyProduced" then
        local historyMax = Spring.GetTeamStatsHistory(teamID)
        local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
        if statsHistory and #statsHistory > 0 then
            result = statsHistory[1].energyProduced
        end
    elseif statKey == "armyValue" then
        result = cachedTotals[teamID].armyUnits
    elseif statKey == "defenseValue" then
        result = cachedTotals[teamID].defenseUnits
    elseif statKey == "utilityValue" then
        result = cachedTotals[teamID].utilityUnits
    elseif statKey == "economyValue" then
        result = cachedTotals[teamID].economyBuildings
    elseif statKey == "damageDealt" then
        local historyMax = Spring.GetTeamStatsHistory(teamID)
        local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
        local damageDealt = 0
        if statsHistory and #statsHistory > 0 then
            damageDealt = statsHistory[1].damageDealt
        end
        result = damageDealt
    elseif statKey == "damageReceived" then
        local historyMax = Spring.GetTeamStatsHistory(teamID)
        local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
        local damageReceived = 0
        if statsHistory and #statsHistory > 0 then
            damageReceived = statsHistory[1].damageReceived
        end
        result = damageReceived
    elseif statKey == "damageEfficiency" then
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
        result = math.floor(damageDealt * 100 / damageReceived)
    end

    return round(result)
end

local function updateStatsNormalMode(statKey)
    teamStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            teamStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                teamStats[allyID][teamID] = {}

                teamStats[allyID][teamID].color = playerData[teamID].color

                teamStats[allyID][teamID].name = playerData[teamID].name
                teamStats[allyID][teamID].hasCommander = teamHasCommander(teamID)
                teamStats[allyID][teamID].captainID = teamList[1]

                local value = getOneStat(statKey, teamID)
                teamStats[allyID][teamID].value = value
            end
        end
    end
end

local function createVSModeStats()
    -- This function exists as a performance optimization. On every GameFrame()
    -- we update vsmode stats. However, rather than recreating tables in Lua
    -- which would require memory allocation and release and thus extra work for
    -- the garbage collector, we reuse the same memory over and over. It is in
    -- this function the memory is allocated.
    -- As a nice bonus, this function reduces calls to GetTeamColor().
    -- Note that the counter-part to this function where we release memory is not
    -- needed as we are not looking to save memory.

    -- Here's the layout of memory in vsModeStats, formatted in yaml

--[[
vsModeStats:
- <allyID>:
  - <teamID>:
    color: team color
    metric.id: metric.value
  color: team captain color
  colorBar: team captain color for bars
  colorLine: team captain color for lines
  colorKnobSide: team captain color for side knob
  colorKnobMiddle: team captain color for middle knob
  metric.id: metric.value
]]

    vsModeStats = {}

    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            vsModeStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            -- use color of captain
            local colorCaptain = playerData[teamList[1]].color
            vsModeStats[allyID].color = colorCaptain
            vsModeStats[allyID].colorBar = makeDarkerColor(colorCaptain, constants.darkerBarsFactor)
            vsModeStats[allyID].colorLine = makeDarkerColor(colorCaptain, constants.darkerLinesFactor)
            vsModeStats[allyID].colorKnobSide = makeDarkerColor(colorCaptain, constants.darkerSideKnobsFactor)
            vsModeStats[allyID].colorKnobMiddle = makeDarkerColor(colorCaptain, constants.darkerMiddleKnobFactor)
            vsModeStats[allyID].values = {}

            -- build team list and assign colors
            for _,teamID in ipairs(teamList) do
                vsModeStats[allyID][teamID] = {}
                vsModeStats[allyID][teamID].color = { Spring.GetTeamColor(teamID) }
                vsModeStats[allyID][teamID].values = {}
            end

            -- build metrics and assign placeholder values, i.e. zero
            for _,metric in ipairs(metricsEnabled) do
                for _,teamID in ipairs(teamList) do
                    vsModeStats[allyID][teamID].values[metric.id] = 0
                end
                vsModeStats[allyID].values[metric.id] = 0
            end
        end
    end
end

local function updateStatsVSMode()
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            local teamList = Spring.GetTeamList(allyID)
            for _,metric in ipairs(metricsEnabled) do
                local valueAllyTeam = 0
                for _,teamID in ipairs(teamList) do
                    local valueTeam = getOneStat(metric.key, teamID)
                    vsModeStats[allyID][teamID].values[metric.id] = valueTeam
                    valueAllyTeam = valueAllyTeam + valueTeam
                end
                vsModeStats[allyID].values[metric.id] = valueAllyTeam
            end
        end
    end
end

local function updateStats()
    if not vsMode then
        updateStatsNormalMode(metricChosenKey)
    else
        updateStatsVSMode()
    end
end

local function calculateHeaderSize()
    local headerTextHeight = font:GetTextHeight(headerLabelDefault) * fontSize
    headerDimensions.height = math.floor(2 * borderPadding + headerTextHeight)

    -- all buttons on the header are squares and of the same size
    -- their sides are the same length as the header height
    buttonSideLength = headerDimensions.height

    -- currently, we have four buttons
    headerDimensions.width = widgetDimensions.width - 2 * buttonSideLength
end

local function calculateStatsBarSize()
    statsBarHeight = math.floor(headerDimensions.height * statBarHeightToHeaderHeight)
    statsBarWidth = widgetDimensions.width
end

local function calculateVSModeMetricSize()
    vsModeMetricHeight = math.floor(headerDimensions.height * statBarHeightToHeaderHeight)
    vsModeMetricWidth = widgetDimensions.width
end

local function setSortingPosition()
    sortingTop = widgetDimensions.top
    sortingBottom = widgetDimensions.top - buttonSideLength
    sortingLeft = widgetDimensions.right - buttonSideLength
    sortingRight = widgetDimensions.right
end

local function setToggleVSModePosition()
    toggleVSModeTop = widgetDimensions.top
    toggleVSModeBottom = widgetDimensions.top - buttonSideLength
    toggleVSModeLeft = sortingLeft - buttonSideLength
    toggleVSModeRight = sortingLeft
end

local function setHeaderPosition()
    headerDimensions.top = widgetDimensions.top
    headerDimensions.bottom = widgetDimensions.top - headerDimensions.height
    headerDimensions.left = widgetDimensions.left
    headerDimensions.right = widgetDimensions.left + headerDimensions.width

    metricChangeBottom = headerDimensions.bottom - headerDimensions.height * getAmountOfMetrics()
end

local function setStatsAreaPosition()
    statsAreaTop = widgetDimensions.top - headerDimensions.height
    statsAreaBottom = widgetDimensions.bottom
    statsAreaLeft = widgetDimensions.left
    statsAreaRight = widgetDimensions.right
end

local function setVSModeMetricsAreaPosition()
    vsModeMetricsAreaTop = widgetDimensions.top - headerDimensions.height
    vsModeMetricsAreaBottom = widgetDimensions.bottom
    vsModeMetricsAreaLeft = widgetDimensions.left
    vsModeMetricsAreaRight = widgetDimensions.right
end

local function calculateWidgetSizeScaleVariables(scaleMultiplier)
    -- Lua has a limit in "upvalues" (60 in total) and therefore this is split
    -- into a separate function
    distanceFromTopBar = math.floor(defaults.distanceFromTopBar * scaleMultiplier)
    borderPadding = math.floor(defaults.borderPadding * scaleMultiplier)
    headerLabelPadding = math.floor(defaults.headerLabelPadding * scaleMultiplier)
    buttonPadding = math.floor(defaults.buttonPadding * scaleMultiplier)
    teamDecalPadding = math.floor(defaults.teamDecalPadding * scaleMultiplier)
    teamDecalShrink = math.floor(defaults.teamDecalShrink * scaleMultiplier)
    vsModeMetricIconPadding = math.floor(defaults.vsModeMetricIconPadding * scaleMultiplier)
    barOutlineWidth = math.floor(defaults.barOutlineWidth * scaleMultiplier)
    barOutlinePadding = math.floor(defaults.barOutlinePadding * scaleMultiplier)
    barOutlineCornerSize = math.floor(defaults.barOutlineCornerSize * scaleMultiplier)
    teamDecalCornerSize = math.floor(defaults.teamDecalCornerSize * scaleMultiplier)
    vsModeBarTextPadding = math.floor(defaults.vsModeBarTextPadding * scaleMultiplier)
    vsModeDeltaPadding = math.floor(defaults.vsModeDeltaPadding * scaleMultiplier)
    vsModeMetricKnobPadding = math.floor(defaults.vsModeMetricKnobPadding * scaleMultiplier)
    vsModeKnobOutline = math.floor(defaults.vsModeKnobOutline * scaleMultiplier)
    vsModeKnobCornerSize = math.floor(defaults.vsModeKnobCornerSize * scaleMultiplier)
    vsModeBarTriangleSize = math.floor(defaults.vsModeBarTriangleSize * scaleMultiplier)
    vsModeBarPadding = math.floor(defaults.vsModeBarPadding * scaleMultiplier)
    vsModeLineHeight = math.floor(defaults.vsModeLineHeight * scaleMultiplier)
    vsModeBarTooltipOffsetX = math.floor(defaults.vsModeBarTooltipOffsetX * scaleMultiplier)
    vsModeBarTooltipOffsetY = math.floor(defaults.vsModeBarTooltipOffsetY * scaleMultiplier)
end

local function calculateWidgetSize()
    local scaleMultiplier = ui_scale * widgetScale * viewScreenWidth / 3840
    calculateWidgetSizeScaleVariables(scaleMultiplier)

    fontSize = math.floor(defaults.fontSize * scaleMultiplier)
    fontSizeMetric = math.floor(fontSize * 0.5)
    fontSizeVSBar = math.floor(fontSize * 0.5)
    fontSizeVSModeKnob = math.floor(defaults.fontSizeVSModeKnob * scaleMultiplier)

    widgetDimensions.width = math.floor(viewScreenWidth * 0.20 * ui_scale * widgetScale)

    calculateHeaderSize()
    calculateStatsBarSize()
    calculateVSModeMetricSize()
    statsAreaWidth = widgetDimensions.width
    vsModeMetricsAreaWidth = widgetDimensions.width

    local statBarAmount
    if sortingChosen == "teamaggregate" then
        statBarAmount = getAmountOfAllyTeams()
    else
        statBarAmount = getAmountOfTeams()
    end
    statsAreaHeight = statsBarHeight * statBarAmount
    teamDecalHeight = statsBarHeight - borderPadding * 2 - teamDecalPadding * 2
    vsModeMetricIconHeight = vsModeMetricHeight - borderPadding * 2 - vsModeMetricIconPadding * 2
    vsModeMetricIconWidth = vsModeMetricIconHeight * 2
    vsModeBarMarkerWidth = math.floor(defaults.vsModeBarMarkerWidth * scaleMultiplier)
    vsModeBarMarkerHeight = math.floor(defaults.vsModeBarMarkerHeight * scaleMultiplier)
    vsModeKnobHeight = vsModeMetricHeight - borderPadding * 2 - vsModeMetricKnobPadding * 2
    vsModeKnobWidth = vsModeKnobHeight * 5

    vsModeMetricsAreaHeight = vsModeMetricHeight * getAmountOfMetrics()

    if not vsMode then
        widgetDimensions.height = headerDimensions.height + statsAreaHeight
    else
        widgetDimensions.height = headerDimensions.height + vsModeMetricsAreaHeight
    end
end

local function setWidgetPosition()
    -- widget is placed underneath topbar
    if WG['topbar'] then
        local topBarPosition = WG['topbar'].GetPosition()
        widgetDimensions.top = topBarPosition[2] - distanceFromTopBar
    else
        widgetDimensions.top = viewScreenHeight
    end
    widgetDimensions.bottom = widgetDimensions.top - widgetDimensions.height
    widgetDimensions.right = viewScreenWidth
    widgetDimensions.left = widgetDimensions.right - widgetDimensions.width

    setHeaderPosition()
    setSortingPosition()
    setToggleVSModePosition()
    setStatsAreaPosition()
    setVSModeMetricsAreaPosition()
end

local function createBackgroundShader()
    if WG['guishader'] then
        backgroundShader = gl.CreateList(function ()
            WG.FlowUI.Draw.RectRound(
                widgetDimensions.left,
                widgetDimensions.bottom,
                widgetDimensions.right,
                widgetDimensions.top,
                WG.FlowUI.elementCorner)
        end)
        WG['guishader'].InsertDlist(backgroundShader, 'spectator_hud', true)
    end
end

local function drawHeader()
    WG.FlowUI.Draw.Element(
        headerDimensions.left,
        headerDimensions.bottom,
        headerDimensions.right,
        headerDimensions.top,
        1, 1, 1, 1,
        1, 1, 1, 1
    )

    font:Begin()
    font:SetTextColor(textColorWhite)
    font:Print(
        headerLabel,
        headerDimensions.left + borderPadding + headerLabelPadding,
        headerDimensions.bottom + borderPadding + headerLabelPadding,
        fontSize - headerLabelPadding * 2,
        'o'
    )
    font:End()
end

updateHeaderTooltip = function ()
    if WG['tooltip'] then
        local metricChosen = getMetricChosen()
        local tooltipText = metricChosen.tooltip
        WG['tooltip'].AddTooltip(
            headerTooltipName,
            { headerDimensions.left, headerDimensions.bottom, headerDimensions.right, headerDimensions.top },
            tooltipText,
            nil,
            headerTooltipTitle
        )
    end
end

local function updateSortingTooltip()
    if WG['tooltip'] then
        local tooltipText
        if sortingChosen == "player" then
            tooltipText = "Sort by Player (click to change)"
        elseif sortingChosen == "team" then
            tooltipText = "Sort by Team (click to change)"
        elseif sortingChosen == "teamaggregate" then
            tooltipText = "Sort by Team Aggregate (click to change)"
        end
    
        WG['tooltip'].AddTooltip(
            sortingTooltipName,
            { sortingLeft, sortingBottom, sortingRight, sortingTop },
            tooltipText,
            nil,
            sortingTooltipTitle
        )
    end
end

local function updateToggleVSModeTooltip()
    if WG['tooltip'] then
        WG['tooltip'].AddTooltip(
            toggleVSModeTooltipName,
            { toggleVSModeLeft, toggleVSModeBottom, toggleVSModeRight, toggleVSModeTop },
            toggleVSModeTooltipText,
            nil,
            toggleVSModeTooltipTitle
        )
    end
end

local function updateVSModeTooltips()
    local iconLeft = vsModeMetricsAreaLeft + borderPadding + vsModeMetricIconPadding
    local iconRight = iconLeft + vsModeMetricIconWidth

    if WG['tooltip'] then
        for _, metric in ipairs(metricsEnabled) do
            local bottom = vsModeMetricsAreaTop - metric.id * vsModeMetricHeight
            local top = bottom + vsModeMetricHeight

            local iconBottom = bottom + borderPadding + vsModeMetricIconPadding
            local iconTop = iconBottom + vsModeMetricIconHeight

            WG['tooltip'].AddTooltip(
                string.format("spectator_hud_vsmode_%d", metric.id),
                { iconLeft, iconBottom, iconRight, iconTop },
                metric.tooltip,
                nil,
                metric.title
            )
        end
    end
end

local function deleteHeaderTooltip()
    if WG['tooltip'] then
        WG['tooltip'].RemoveTooltip(headerTooltipName)
    end
end

local function deleteSortingTooltip()
    if WG['tooltip'] then
        WG['tooltip'].RemoveTooltip(sortingTooltipName)
    end
end

local function deleteToggleVSModeTooltip()
    if WG['tooltip'] then
        WG['tooltip'].RemoveTooltip(toggleVSModeTooltipName)
    end
end

local function deleteVSModeTooltips()
    if WG['tooltip'] then
        for _, metric in ipairs(metricsEnabled) do
            WG['tooltip'].RemoveTooltip(string.format("spectator_hud_vsmode_%d", metric.id))
        end
    end
end

local function createSorting()
    sortingBackgroundDisplayList = gl.CreateList(function ()
        WG.FlowUI.Draw.Element(
            sortingLeft,
            sortingBottom,
            sortingRight,
            sortingTop,
            1, 1, 1, 1,
            1, 1, 1, 1
        )
    end)
end

local function createToggleVSMode()
    toggleVSModeBackgroundDisplayList = gl.CreateList(function ()
        WG.FlowUI.Draw.Element(
            toggleVSModeLeft,
            toggleVSModeBottom,
            toggleVSModeRight,
            toggleVSModeTop,
            1, 1, 1, 1,
            1, 1, 1, 1
        )
    end)
end

local function drawSorting()
    gl.Color(1, 1, 1, 1)
    if sortingChosen == "player" then
        gl.Texture(images["sortingPlayer"])
    elseif sortingChosen == "team" then
        gl.Texture(images["sortingTeam"])
    elseif sortingChosen == "teamaggregate" then
        gl.Texture(images["sortingTeamAggregate"])
    end
    gl.TexRect(
        sortingLeft + buttonPadding,
        sortingBottom + buttonPadding,
        sortingRight - buttonPadding,
        sortingTop - buttonPadding
    )
    gl.Texture(false)
end

local function drawToggleVSMode()
    -- TODO: add visual indication when toggle disabled
    gl.Color(1, 1, 1, 1)
    gl.Texture(images["toggleVSMode"])
    gl.TexRect(
        toggleVSModeLeft + buttonPadding,
        toggleVSModeBottom + buttonPadding,
        toggleVSModeRight - buttonPadding,
        toggleVSModeTop - buttonPadding
    )
    gl.Texture(false)

    if vsMode then
        gl.Blending(GL.SRC_ALPHA, GL.ONE)
        gl.Color(1, 0.2, 0.2, 0.2)
        gl.Rect(
            toggleVSModeLeft + buttonPadding,
            toggleVSModeBottom + buttonPadding,
            toggleVSModeRight - buttonPadding,
            toggleVSModeTop - buttonPadding
        )
        gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
    end
end

local function createStatsArea()
    statsAreaBackgroundDisplayList = gl.CreateList(function ()
        WG.FlowUI.Draw.Element(
            statsAreaLeft,
            statsAreaBottom,
            statsAreaRight,
            statsAreaTop,
            1, 1, 1, 1,
            1, 1, 1, 1
        )
    end)
end

local function createVSModeBackgroudDisplayLists()
    vsModeBackgroundDisplayLists = {}
    for _, metric in ipairs(metricsEnabled) do
        local currentBottom = vsModeMetricsAreaTop - metric.id * vsModeMetricHeight
        local currentTop = currentBottom + vsModeMetricHeight
        local currentDisplayList = gl.CreateList(function ()
            WG.FlowUI.Draw.Element(
                vsModeMetricsAreaLeft,
                currentBottom,
                vsModeMetricsAreaRight,
                currentTop,
                1, 1, 1, 1,
                1, 1, 1, 1
            )
        end)
        table.insert(vsModeBackgroundDisplayLists, currentDisplayList)
    end
end

local function darkerColor(red, green, blue, alpha, factor)
    return {red * factor, green * factor, blue * factor, 0.2}
end

local function drawAUnicolorBar(left, bottom, right, top, value, max, color, captainID)
    local captainColorRed, captainColorGreen, captainColorBlue, captainColorAlpha = Spring.GetTeamColor(captainID)
    local captainColorDarker = darkerColor(captainColorRed, captainColorGreen, captainColorBlue, captainColorAlpha, 0.7)
    gl.Color(captainColorDarker[1], captainColorDarker[2], captainColorDarker[3], captainColorDarker[4])
    WG.FlowUI.Draw.RectRound(
        left,
        bottom,
        right,
        top,
        barOutlineCornerSize
    )

    local scaleFactor = (right - left - 2 * (barOutlineWidth + barOutlinePadding)) / max

    local leftInner = left + barOutlineWidth + barOutlinePadding
    local bottomInner = bottom + barOutlineWidth + barOutlinePadding
    local rightInner = left + barOutlineWidth + barOutlinePadding + math.floor(value * scaleFactor)
    local topInner = top - barOutlineWidth - barOutlinePadding

    gl.Color(color)
    gl.Rect(leftInner, bottomInner, rightInner, topInner)

    local function addDarkGradient(left, bottom, right, top)
        gl.Blending(GL.SRC_ALPHA, GL.ONE)

        local middle = math.floor((right + left) / 2)

        gl.Color(0, 0, 0, 0.15)
        gl.Vertex(left, bottom)
        gl.Vertex(left, top)

        gl.Color(0, 0, 0, 0.3)
        gl.Vertex(middle, top)
        gl.Vertex(middle, bottom)

        gl.Color(0, 0, 0, 0.3)
        gl.Vertex(middle, bottom)
        gl.Vertex(middle, top)

        gl.Color(0, 0, 0, 0.15)
        gl.Vertex(right, top)
        gl.Vertex(right, bottom)

        gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
    end
    gl.BeginEnd(GL.QUADS, addDarkGradient, leftInner, bottomInner, rightInner, topInner)
end

local function drawAStatsBar(index, teamColor, amount, max, playerName, hasCommander, captainID)
    local statBarBottom = statsAreaTop - index * statsBarHeight
    local statBarTop = statBarBottom + statsBarHeight

    local teamDecalBottom = statBarBottom + borderPadding + teamDecalPadding
    local teamDecalTop = statBarTop - borderPadding - teamDecalPadding

    local teamDecalSize = teamDecalTop - teamDecalBottom

    local teamDecalLeft = statsAreaLeft + borderPadding + teamDecalPadding
    local teamDecalRight = teamDecalLeft + teamDecalSize

    local shrink = hasCommander and 0 or teamDecalShrink

    WG.FlowUI.Draw.RectRound(
        teamDecalLeft + shrink,
        teamDecalBottom + shrink,
        teamDecalRight - shrink,
        teamDecalTop - shrink,
        teamDecalCornerSize,
        1, 1, 1, 1,
        teamColor
    )
    gl.Color(1, 1, 1, 1)

    local barLeft = teamDecalRight + borderPadding * 2 + teamDecalPadding
    local barRight = statsAreaRight - borderPadding - teamDecalPadding

    local barBottom = teamDecalBottom
    local barTop = teamDecalTop
    drawAUnicolorBar(
        barLeft,
        barBottom,
        barRight,
        barTop,
        amount,
        max,
        teamColor,
        captainID
    )

    local amountText = formatResources(amount, false)
    local amountMiddle = teamDecalRight + math.floor((statsAreaRight - teamDecalRight) / 2)
    local amountCenter = barBottom + math.floor((barTop - barBottom) / 2)
    font:Begin()
        font:SetTextColor(textColorWhite)
        font:Print(
            amountText,
            amountMiddle,
            amountCenter,
            fontSizeMetric,
            'cvo'
        )
    font:End()

    if WG['tooltip'] and playerName then
        local tooltipName = string.format("stat_bar_player_%d", index)
        WG['tooltip'].AddTooltip(
            tooltipName,
            {
                teamDecalLeft,
                teamDecalBottom,
                teamDecalRight,
                teamDecalTop
            },
            playerName
        )
        table.insert(tooltipNames, tooltipName)
    end
end

local function drawStatsBars()
    local statsSorted = sortStats(teamStats)

    local max = 1
    for _, currentStat in ipairs(statsSorted) do
        if max < currentStat.value then
            max = currentStat.value
        end
    end

    local index = 1
    for _, currentStat in ipairs(statsSorted) do
        drawAStatsBar(
            index,
            currentStat.color,
            currentStat.value,
            max,
            currentStat.name,
            currentStat.hasCommander,
            currentStat.captainID
        )
        index = index + 1
    end
end

local function drawVSModeKnob(left, bottom, right, top, color, text)
    local greyFactor = 0.5
    local matchingGreyRed = color[1] * greyFactor
    local matchingGreyGreen = color[2] * greyFactor
    local matchingGreyBlue = color[3] * greyFactor
    gl.Color(matchingGreyRed, matchingGreyGreen, matchingGreyBlue, 1)
    WG.FlowUI.Draw.RectRound(
        left,
        bottom,
        right,
        top,
        vsModeKnobCornerSize
    )
    gl.Color(color)
    WG.FlowUI.Draw.RectRound(
        left + vsModeKnobOutline,
        bottom + vsModeKnobOutline,
        right - vsModeKnobOutline,
        top - vsModeKnobOutline,
        vsModeKnobCornerSize
    )

    font:Begin()
        font:SetTextColor(textColorWhite)
        font:Print(
            text,
            math.floor((right + left) / 2),
            math.floor((top + bottom) / 2),
            fontSizeVSModeKnob,
            'cvO'
        )
    font:End()
end

local colorKnobMiddleGrey = { 0.5, 0.5, 0.5, 1 }
local function drawVSBar(left, bottom, right, top, indexLeft, indexRight, metricID)
    local statsLeft = vsModeStats[indexLeft]
    local statsRight = vsModeStats[indexRight]

    local valueLeft = statsLeft.values[metricID]
    local valueRight = statsRight.values[metricID]

    local barTop = top - vsModeBarPadding
    local barBottom = bottom + vsModeBarPadding

    local barLength = right - left - vsModeKnobWidth

    local leftBarWidth
    if valueLeft > 0 or valueRight > 0 then
        leftBarWidth = math.floor(barLength * valueLeft / (valueLeft + valueRight))
    else
        leftBarWidth = math.floor(barLength / 2)
    end
    local rightBarWidth = barLength - leftBarWidth

    local colorMiddleKnob
    if valueLeft > valueRight then
        colorMiddleKnob = statsLeft.colorKnobMiddle
    elseif valueRight > valueLeft then
        colorMiddleKnob = statsRight.colorKnobMiddle
    else
        -- color grey if even
        colorMiddleKnob = colorKnobMiddleGrey
    end

    gl.Color(statsLeft.colorBar)
    gl.Rect(
        left,
        barBottom,
        left + leftBarWidth,
        barTop
    )

    gl.Color(statsRight.colorBar)
    gl.Rect(
        right - rightBarWidth,
        barBottom,
        right,
        barTop
    )

    -- only draw team lines if mouse on bar
    local mouseX, mouseY = Spring.GetMouseState()
    if ((valueLeft > 0) or (valueRight > 0)) and (mouseX > left) and (mouseX < right) and (mouseY > bottom) and (mouseY < top) then
        local scalingFactor = barLength / (valueLeft + valueRight)
        local lineMiddle = math.floor((top + bottom) / 2)

        local lineStart
        local lineEnd = left
        for _, teamID in ipairs(Spring.GetTeamList(indexLeft)) do
            local teamValue = statsLeft[teamID].values[metricID]
            local teamColor = playerData[teamID].color
            lineStart = lineEnd
            lineEnd = lineEnd + math.floor(teamValue * scalingFactor)
            gl.Color(teamColor)
            gl.Rect(
                lineStart,
                barBottom,
                lineEnd,
                barTop
            )
        end

        local lineStart
        local lineEnd = right - rightBarWidth
        for _, teamID in ipairs(Spring.GetTeamList(indexRight)) do
            local teamValue = statsRight[teamID].values[metricID]
            local teamColor = playerData[teamID].color
            lineStart = lineEnd
            lineEnd = lineEnd + math.floor(teamValue * scalingFactor)
            gl.Color(teamColor)
            gl.Rect(
                lineStart,
                barBottom,
                lineEnd,
                barTop
            )
        end

        -- when mouseover, middle knob shows absolute values
        drawVSModeKnob(
            left + leftBarWidth + 1,
            bottom,
            right - rightBarWidth - 1,
            top,
            colorMiddleKnob,
            formatResources(math.abs(valueLeft - valueRight), true)
        )
    else
        local lineMiddle = math.floor((top + bottom) / 2)
        local lineBottom = lineMiddle - math.floor(vsModeLineHeight / 2)
        local lineTop = lineMiddle + math.floor(vsModeLineHeight / 2)

        gl.Color(statsLeft.colorLine)
        gl.Rect(
            left,
            lineBottom,
            left + leftBarWidth,
            lineTop
        )

        gl.Color(statsRight.colorLine)
        gl.Rect(
            right - rightBarWidth,
            lineBottom,
            right,
            lineTop
        )

        local relativeLead = 0
        local relativeLeadMax = 999
        local relativeLeadString = nil
        if valueLeft > valueRight then
            if valueRight > 0 then
                relativeLead = math.floor(100 * math.abs(valueLeft - valueRight) / valueRight)
            else
                relativeLeadString = "Inf"
            end
        elseif valueRight > valueLeft then
            if valueLeft > 0 then
                relativeLead = math.floor(100 * math.abs(valueRight - valueLeft) / valueLeft)
            else
                relativeLeadString = "Inf"
            end
        end
        if relativeLead > relativeLeadMax then
            relativeLeadString = string.format(">%d%%", relativeLeadMax)
        elseif not relativeLeadString then
            relativeLeadString = string.format("%d%%", relativeLead)
        end
        drawVSModeKnob(
            left + leftBarWidth + 1,
            bottom,
            right - rightBarWidth - 1,
            top,
            colorMiddleKnob,
            relativeLeadString
        )
    end
end

local function drawVSModeMetrics()
    local indexLeft = teamOrder and teamOrder[1] or 0
    local indexRight = teamOrder and teamOrder[2] or 1
    for _, metric in ipairs(metricsEnabled) do
        local bottom = vsModeMetricsAreaTop - metric.id * vsModeMetricHeight
        local top = bottom + vsModeMetricHeight

        local iconLeft = vsModeMetricsAreaLeft + borderPadding + vsModeMetricIconPadding
        local iconRight = iconLeft + vsModeMetricIconWidth
        local iconBottom = bottom + borderPadding + vsModeMetricIconPadding
        local iconTop = iconBottom + vsModeMetricIconHeight

        local iconHCenter = math.floor((iconRight + iconLeft) / 2)
        local iconVCenter = math.floor((iconTop + iconBottom) / 2)
        local iconText = metric.text

        font:Begin()
            font:SetTextColor(textColorWhite)
            font:Print(
                iconText,
                iconHCenter,
                iconVCenter,
                fontSizeVSBar,
                'cvo'
            )
        font:End()

        local leftKnobLeft = iconRight + borderPadding + vsModeMetricIconPadding * 2
        local leftKnobBottom = iconBottom
        local leftKnobRight = leftKnobLeft + vsModeKnobWidth
        local leftKnobTop = iconTop
        drawVSModeKnob(
            leftKnobLeft,
            leftKnobBottom,
            leftKnobRight,
            leftKnobTop,
            vsModeStats[indexLeft].colorKnobSide,
            formatResources(vsModeStats[indexLeft].values[metric.id], true)
        )

        local rightKnobRight = vsModeMetricsAreaRight - borderPadding - vsModeMetricIconPadding * 2
        local rightKnobBottom = iconBottom
        local rightKnobLeft = rightKnobRight - vsModeKnobWidth
        local rightKnobTop = iconTop
        drawVSModeKnob(
            rightKnobLeft,
            rightKnobBottom,
            rightKnobRight,
            rightKnobTop,
            vsModeStats[indexRight].colorKnobSide,
            formatResources(vsModeStats[indexRight].values[metric.id], true)
        )

        drawVSBar(
            leftKnobRight,
            iconBottom,
            rightKnobLeft,
            iconTop,
            indexLeft,
            indexRight,
            metric.id
        )
    end
end

local function mySelector(px, py, sx, sy)
    -- modified version of WG.FlowUI.Draw.Selector

    local cs = (sy-py)*0.05
	local edgeWidth = math.max(1, math.floor((sy-py) * 0.05))

	-- faint dark outline edge
	WG.FlowUI.Draw.RectRound(px-edgeWidth, py-edgeWidth, sx+edgeWidth, sy+edgeWidth, cs*1.5, 1,1,1,1, { 0,0,0,0.5 })
	-- body
	WG.FlowUI.Draw.RectRound(px, py, sx, sy, cs, 1,1,1,1, { 0.05, 0.05, 0.05, 0.8 }, { 0.15, 0.15, 0.15, 0.8 })

	-- highlight
	gl.Blending(GL.SRC_ALPHA, GL.ONE)
	-- top
	WG.FlowUI.Draw.RectRound(px, sy-(edgeWidth*3), sx, sy, edgeWidth, 1,1,1,1, { 1,1,1,0 }, { 1,1,1,0.035 })
	-- bottom
	WG.FlowUI.Draw.RectRound(px, py, sx, py+(edgeWidth*3), edgeWidth, 1,1,1,1, { 1,1,1,0.025 }, { 1,1,1,0  })
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)

	-- button
	WG.FlowUI.Draw.RectRound(px, py, sx, sy, cs, 1, 1, 1, 1, { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.14 })
	--WG.FlowUI.Draw.Button(sx-(sy-py), py, sx, sy, 1, 1, 1, 1, 1,1,1,1, nil, { 1, 1, 1, 0.1 }, nil, cs)
end

local function drawMetricChange()
    mySelector(
        headerDimensions.left,
        metricChangeBottom,
        headerDimensions.right,
        headerDimensions.bottom
    )

    -- TODO: this is not working, find out why
    local mouseX, mouseY = Spring.GetMouseState()
    if (mouseX > headerDimensions.left) and
            (mouseX < headerDimensions.right) and
            (mouseY > headerDimensions.bottom) and
            (mouseY < metricChangeBottom) then
        local mouseHovered = math.floor((mouseY - metricChangeBottom) / headerDimensions.height)
        local highlightBottom = metricChangeBottom + mouseHovered * headerDimensions.height
        local highlightTop = highlightBottom + headerDimensions.height
        WG.FlowUI.Draw.SelectHighlight(
            headerDimensions.left,
            highlightBottom,
            headerDimensions.right,
            highlighTop
        )
    end

    font:Begin()
        font:SetTextColor(textColorWhite)
        local distanceFromTop = 0
        local amountOfMetrics = getAmountOfMetrics()
        for _, currentMetric in ipairs(metricsEnabled) do
            local textLeft = headerDimensions.left + borderPadding + headerLabelPadding
            local textBottom = metricChangeBottom + borderPadding + headerLabelPadding +
                (amountOfMetrics - distanceFromTop - 1) * headerDimensions.height
            font:Print(
                currentMetric.title,
                textLeft,
                textBottom,
                fontSize - headerLabelPadding * 2,
                'o'
            )
            distanceFromTop = distanceFromTop + 1
        end
    font:End()
end

local function deleteBackgroundShader()
    if WG['guishader'] then
        WG['guishader'].DeleteDlist('spectator_hud')
        backgroundShader = gl.DeleteList(backgroundShader)
    end
end

local function deleteSorting()
    gl.DeleteList(sortingBackgroundDisplayList)
end

local function deleteToggleVSMode()
    gl.DeleteList(toggleVSModeBackgroundDisplayList)
end

local function deleteStatsArea()
    gl.DeleteList(statsAreaBackgroundDisplayList)
end

local function deleteVSModeBackgroudDisplayLists()
    for _, vsModeBackgroundDisplayList in ipairs(vsModeBackgroundDisplayLists) do
        gl.DeleteList(vsModeBackgroundDisplayList)
    end
end

local function init()
    buildMetricsEnabled()

    viewScreenWidth, viewScreenHeight = Spring.GetViewGeometry()

    widgetDimensions = {}
    headerDimensions = {}

    calculateWidgetSize()
    setWidgetPosition()

    createBackgroundShader()
    updateHeaderTooltip()
    createSorting()
    updateSortingTooltip()
    createToggleVSMode()
    updateToggleVSModeTooltip()
    createStatsArea()
    createVSModeBackgroudDisplayLists()

    vsModeEnabled = getAmountOfAllyTeams() == 2
    if not vsModeEnabled then
        vsMode = false
    end

    if vsMode then
        updateVSModeTooltips()
    end

    buildUnitDefs()
    buildUnitCache()

    createVSModeStats()
    updateStats()
end

local function deInit()
    if WG['tooltip'] then
        for _, tooltipName in ipairs(tooltipNames) do
            WG['tooltip'].RemoveTooltip(tooltipName)
        end
    end

    deleteBackgroundShader()
    deleteHeaderTooltip()
    deleteSorting()
    deleteSortingTooltip()
    deleteToggleVSMode()
    deleteToggleVSModeTooltip()
    deleteStatsArea()
    deleteVSModeBackgroudDisplayLists()
end

local function reInit()
    deInit()

    font = WG['fonts'].getFont()

    init()
end

local function tearDownVSMode()
    deleteVSModeTooltips()
end

local function processPlayerCountChanged()
    reInit()
end

local function checkAndUpdateHaveFullView()
    local haveFullViewOld = haveFullView
    haveFullView = select(2, Spring.GetSpectatingState())
    return haveFullView ~= haveFullViewOld
end

local function registerOptions()
    if WG['options'] then
        local optionTable = {}

        for _,metric in ipairs(metricsAvailable) do
            local currentOptionSpec = {}
            currentOptionSpec.widgetname = "SpectatorHUD" -- note: must be same as in widget:GetInfo()
            currentOptionSpec.id = "metrics_" .. metric.key
            currentOptionSpec.value = options.metrics[metric.key]
            currentOptionSpec.name = "Show " .. metric.title
            currentOptionSpec.description = metric.tooltip
            currentOptionSpec.type = "bool"
            currentOptionSpec.onchange = function(i, value)
                options.metrics[metric.key] = value
                reInit()
            end
            table.insert(optionTable, currentOptionSpec)
        end

        local optionSpecUseME70 = {
            widgetname = "SpectatorHUD",
            id = "useMetalEquivalent70",
            value = options.useMetalEquivalent70,
            name = "Use Metal Equivalent 70",
            description = "When displaying metal costs, add energy cost by scaling energy to metal as 70:1",
            type = "bool",
            onchange = function(i, value)
                options.useMetalEquivalent70 = value
                reInit()
            end,
        }
        table.insert(optionTable, optionSpecUseME70)
        local optionSpecSubtractReclaim = {
            widgetname = "SpectatorHUD",
            id = "subtractReclaimFromIncome",
            value = options.subtractReclaimFromIncome,
            name = "Subtract Reclaim From Income",
            description = "Subtract reclaim from income numbers",
            type = "bool",
            onchange = function(i, value) options.subtractReclaimFromIncome = value end,
        }
        table.insert(optionTable, optionSpecSubtractReclaim)
        local optionWidgetSize = {
            widgetname = "SpectatorHUD",
            id = "widgetSize",
            value = widgetScale,
            name = "Widget Size",
            description = "Scale Widget",
            type = "slider",
            min = 0.1,
            max = 2,
            step = 0.1,
            onchange = function(i, value)
                widgetScale = value
                reInit()
            end,
        }
        table.insert(optionTable, optionWidgetSize)

        WG['options'].addOptions(optionTable)
    end
end

local function teardownOptions()
    if WG['options'] then
        local optionTable = {}

        for _,metric in ipairs(metricsAvailable) do
            local optionName = "metrics_" .. metric.key
            table.insert(optionTable, optionName)
        end

        table.insert(optionTable, "useMetalEquivalent70")
        table.insert(optionTable, "subtractReclaimFromIncome")
        table.insert(optionTable, "widgetSize")

        WG['options'].removeOptions(optionTable)
    end
end

function widget:Initialize()
    checkAndUpdateHaveFullView()

    font = WG['fonts'].getFont()

    registerOptions()

    buildPlayerData()

    init()
end

function widget:Shutdown()
    deInit()

    teardownOptions()
end

function widget:TeamDied(teamID)
    checkAndUpdateHaveFullView()

    if haveFullView then
        processPlayerCountChanged()
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

function widget:KeyPress(key, mods, isRepeat)
    if key == 0x132 and not isRepeat and not mods.shift and not mods.alt then
        ctrlDown = true
    end
    return false
end

function widget:KeyRelease(key)
    if key == 0x132 then
        ctrlDown = false
    end
    return false
end

local function isInDimensions(x, y, dimensions)
    return (x > dimensions["left"]) and (x < dimensions["right"]) and (y > dimensions["bottom"]) and (y < dimensions["top"])
end

function widget:MousePress(x, y, button)
    if isInDimensions(x, y, headerDimensions) and not metricChangeInProgress then
        metricChangeInProgress = true
        return
    end

    if metricChangeInProgress then
        if (x > headerDimensions.left) and (x < headerDimensions.right) and
                (y > metricChangeBottom) and (y < headerDimensions.top) then
            -- no change if user pressed header
            if (y < headerDimensions.bottom) then
                local metricID = getAmountOfMetrics() - math.floor((y - metricChangeBottom) / headerDimensions.height)
                local metric = getMetricFromID(metricID)
                setMetricChosen(metric.key)
                if vsMode then
                    vsMode = false
                    tearDownVSMode()
                    reInit()
                end
                updateStats()
            end
        end

        metricChangeInProgress = false
        return
    end

    if (x > sortingLeft) and (x < sortingRight) and (y > sortingBottom) and (y < sortingTop) then
        if sortingChosen == "player" then
            sortingChosen = "team"
        elseif sortingChosen == "team" then
            sortingChosen = "teamaggregate"
        elseif sortingChosen == "teamaggregate" then
            sortingChosen = "player"
        end
        -- we need to do full reinit because amount of rows to display has changed
        reInit()
        return
    end

    if vsModeEnabled then
        if (x > toggleVSModeLeft) and (x < toggleVSModeRight) and (y > toggleVSModeBottom) and (y < toggleVSModeTop) then
            vsMode = not vsMode
            if not vsMode then
                tearDownVSMode()
            end
            reInit()
            return
        end
    end
end

function widget:ViewResize()
    reInit()
end
             
function widget:GameFrame(frameNum)
    if not haveFullView then
        return
    end

    if (frameNum > 0) and (not teamOrder) then
        -- collect player start positions
        local teamStartXAverages = {}
        for _, allyID in ipairs(Spring.GetAllyTeamList()) do
            if allyID ~= gaiaAllyID then
                local xAccumulator = 0
                local teamList = Spring.GetTeamList(allyID)
                for _,teamID in ipairs(teamList) do
                    local x, _, _ = Spring.GetTeamStartPosition(teamID)
                    xAccumulator = xAccumulator + x
                end
                local xAverage = xAccumulator / #teamList
                table.insert(teamStartXAverages, { allyID, xAverage })
            end
        end

        -- sort averages and create team order (from left to right)
        table.sort(teamStartXAverages, function (left, right)
            return left[2] < right[2]
        end)
        teamOrder = {}
        for i,teamStartX in ipairs(teamStartXAverages) do
            teamOrder[i] = teamStartX[1]
        end
    end

    if frameNum % statsUpdateFrequency == 1 then
        updateStats()
    end
end

function widget:Update(dt)
    local haveFullViewOld = haveFullView
    haveFullView = select(2, Spring.GetSpectatingState())
    if haveFullView ~= haveFullViewOld then
        if haveFullView then
            init()
            return
        else
            deInit()
            return
        end
    end
end

function widget:DrawScreen()
    if not haveFullView then
        return
    end

    gl.PushMatrix()
        drawHeader()

        gl.CallList(sortingBackgroundDisplayList)
        drawSorting()

        gl.CallList(toggleVSModeBackgroundDisplayList)
        drawToggleVSMode()

        if not vsMode then
            gl.CallList(statsAreaBackgroundDisplayList)
            drawStatsBars()
        else
            for _, vsModeBackgroundDisplayList in ipairs(vsModeBackgroundDisplayLists) do
                gl.CallList(vsModeBackgroundDisplayList)
            end

            drawVSModeMetrics()
        end

        if metricChangeInProgress then
            drawMetricChange()
        end
    gl.PopMatrix()
end

function widget:GetConfigData()
    local result = {
        widgetScale = widgetScale,
        metricChosenKey = metricChosenKey,
        sortingChosen = sortingChosen,
        vsMode = vsMode,

        useMetalEquivalent70 = options.useMetalEquivalent70,
        subtractReclaimFromIncome = options.subtractReclaimFromIncome,
    }

    for _,metric in ipairs(metricsAvailable) do
        local configKey = "metrics_" .. metric.key
        local value
        if options.metrics[metric.key] then
            value = options.metrics[metric.key]
        else
            value = metric.defaultValue
        end

        result[configKey] = value
    end

    return result
end

function widget:SetConfigData(data)
    if data.widgetScale then
        widgetScale = data.widgetScale
    end
    if data.metricChosenKey then
        metricChosenKey = data.metricChosenKey
    end
    if data.sortingChosen then
        sortingChosen = data.sortingChosen
    end
    if data.vsMode then
        vsMode = data.vsMode
    end

    if data.useMetalEquivalent70 then
        options.useMetalEquivalent70 = data.useMetalEquivalent70
    end
    if data.subtractReclaimFromIncome then
        options.subtractReclaimFromIncome = data.subtractReclaimFromIncome
    end

    options.metrics = {}
    for _,metric in ipairs(metricsAvailable) do
        local configKey = "metrics_" .. metric.key
        local value = metric.defaultValue
        if data[configKey] then
            value = data[configKey]
        end
        options.metrics[metric.key] = value
    end
end
