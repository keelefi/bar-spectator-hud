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

local buttonWidgetSizeIncreaseDimensions
local buttonWidgetSizeDecreaseDimensions

local backgroundShader

local headerLabel = "Metal Income"
local headerLabelDefault = "Metal Income"
--[[ note: headerLabelDefault is a silly hack. GetTextHeight will return different value depending
     on the provided text. Therefore, we need to always provide it with the same text or otherwise
     the widget will keep on resizing depending on the header label.
]]

local buttonWidgetSizeIncreaseBackgroundDisplayList
local buttonWidgetSizeDecreaseBackgroundDisplayList
local sortingBackgroundDisplayList
local toggleVSModeBackgroundDisplayList

local statsAreaBackgroundDisplayList
local vsModeBackgroundDisplayLists = {}

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

local buttonWidgetSizeIncreaseTooltipName = "spectator_hud_size_increase"
local buttonWidgetSizeDecreaseTooltipName = "spectator_hud_size_decrease"

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
    { id=1, title="Metal Income", tooltip="Metal Income" },
    { id=2, title="Metal Produced", tooltip="Metal Produced" },
    { id=3, title="Build Power", tooltip="Build Power" },
    { id=4, title="Army Value", tooltip="Army Value in Metal" },
    { id=5, title="Army Size", tooltip="Army Size in Units" },
    { id=6, title="Damage Done", tooltip="Damage Done" },
    { id=7, title="Damage Received", tooltip="Damage Received" },
    { id=8, title="Damage Efficiency", tooltip="Damage Efficiency" },
}

local vsMode = false
local vsModeEnabled = false

local vsModeMetrics = {
    { id=1, key="metalIncome", text="M/s", metric="Metal Income", tooltip="Metal Income" },
    { id=2, key="energyIncome", text="E/s", metric="Energy Income", tooltip="Energy Income" },
    { id=3, key="buildPower", text="BP", metric="Build Power", tooltip="Build Power" },
    { id=4, key="metalProduced", text="MP", metric="Metal Produced", tooltip="Metal Produced" },
    { id=5, key="energyProduced", text="EP", metric="Energy Produced", tooltip="Energy Produced" },
    { id=6, key="armyValue", text="AV", metric="Army Value", tooltip="Army Value (in metal)" },
    { id=7, key="damageDone", text="Dmg", metric="Damage Dealt", tooltip="Damage Dealt" },
}

local metricChosenID = 1
local metricChangeInProgress = false
local sortingChosen = "player"
local teamStats = {}
local vsModeStats = {}

local images = {
    sortingPlayer = "LuaUI/Images/spectator_hud/sorting-player.png",
    sortingTeam = "LuaUI/Images/spectator_hud/sorting-team.png",
    sortingTeamAggregate = "LuaUI/Images/spectator_hud/sorting-plus.png",
    toggleVSMode = "LuaUI/Images/spectator_hud/button-vs.png",
}

local comDefs = {}
for udefID, def in ipairs(UnitDefs) do
	if def.customParams.iscommander then
		comDefs[udefID] = true
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

local thousand = 1000
local tenThousand = 10 * thousand
local million = thousand * thousand
local tenMillion = 10 * million
local function formatResources(amount, short)
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

local function getPlayerName(teamID)
    local playerID = Spring.GetPlayerList(teamID)
    if playerID and playerID[1] then
        return select(1, Spring.GetPlayerInfo(playerID[1], false))
    end
    return "dead"
end

local function teamHasCommander(teamID)
    local hasCom = false
	for commanderDefID, _ in pairs(comDefs) do
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

local function isArmyUnit(unitDefID)
    if unitDefID and UnitDefs[unitDefID].weapons and (#UnitDefs[unitDefID].weapons > 0) then
        return true
    else
        return false
    end
end

local function getUnitBuildPower(unitDefID)
    if unitDefID and UnitDefs[unitDefID].buildSpeed then
        return UnitDefs[unitDefID].buildSpeed
    else
        return 0
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

local function getAmountOfMetrics()
    return #metricsAvailable
end

local function getMetricChosen()
    for _, currentMetric in ipairs(metricsAvailable) do
        if metricChosenID == currentMetric.id then
            return currentMetric
        end
    end
    return nil
end

local function getAmountOfVSModeMetrics()
    return #vsModeMetrics
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
            local teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha = Spring.GetTeamColor(allyTeamCaptainID)
            allyTotals[index] = {}
            allyTotals[index].colorRed = teamColorRed
            allyTotals[index].colorGreen = teamColorGreen
            allyTotals[index].colorBlue = teamColorBlue
            allyTotals[index].colorAlpha = teamColorAlpha
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

local function updateStatsNormalMode(statToUpdate)
    teamStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            teamStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                teamStats[allyID][teamID] = {}

                local teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha = Spring.GetTeamColor(teamID)
                teamStats[allyID][teamID].colorRed = teamColorRed
                teamStats[allyID][teamID].colorGreen = teamColorGreen
                teamStats[allyID][teamID].colorBlue = teamColorBlue
                teamStats[allyID][teamID].colorAlpha = teamColorAlpha

                teamStats[allyID][teamID].name = getPlayerName(teamID)
                teamStats[allyID][teamID].hasCommander = teamHasCommander(teamID)
                teamStats[allyID][teamID].captainID = teamList[1]

                local value = 0
                if statToUpdate == "Metal Income" then
                    value = select(4, Spring.GetTeamResources(teamID, "metal")) or 0
                elseif statToUpdate == "Metal Produced" then
                    local historyMax = Spring.GetTeamStatsHistory(teamID)
                    local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
                    if statsHistory and #statsHistory > 0 then
                        value = statsHistory[1].metalProduced
                    end
                elseif statToUpdate == "Build Power" then
                    local buildPowerTotal = 0
                    local unitIDs = Spring.GetTeamUnits(teamID)
                    for i = 1, #unitIDs do
                        local unitID = unitIDs[i]
                        if not Spring.GetUnitIsBeingBuilt(unitID) then
                            local currentUnitDefID = Spring.GetUnitDefID(unitID)
                            buildPowerTotal = buildPowerTotal + getUnitBuildPower(currentUnitDefID)
                        end
                    end
                    value = buildPowerTotal
                elseif statToUpdate == "Army Value" then
                    local armyValueTotal = 0
                    local unitIDs = Spring.GetTeamUnits(teamID)
                    for i = 1, #unitIDs do
                        local unitID = unitIDs[i]
                        local currentUnitDefID = Spring.GetUnitDefID(unitID)
                        if currentUnitDefID then
                            local currentUnitMetalCost = UnitDefs[currentUnitDefID].metalCost
                            if isArmyUnit(currentUnitDefID) and not Spring.GetUnitIsBeingBuilt(unitID) then
                                armyValueTotal = armyValueTotal + currentUnitMetalCost
                            end
                        end
                    end
                    value = armyValueTotal
                elseif statToUpdate == "Army Size" then
                    local unitIDs = Spring.GetTeamUnits(teamID)
                    local armySizeTotal = 0
                    for i = 1, #unitIDs do
                        local unitID = unitIDs[i]
                        local currentUnitDefID = Spring.GetUnitDefID(unitID)
                        if isArmyUnit(currentUnitDefID) and not Spring.GetUnitIsBeingBuilt(unitID)then
                            armySizeTotal = armySizeTotal + 1
                        end
                    end
                    value = armySizeTotal
                elseif statToUpdate == "Damage Done" then
                    local historyMax = Spring.GetTeamStatsHistory(teamID)
                    local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
                    local damageDealt = 0
                    if statsHistory and #statsHistory > 0 then
                        damageDealt = statsHistory[1].damageDealt
                    end
                    value = damageDealt
                elseif statToUpdate == "Damage Received" then
                    local historyMax = Spring.GetTeamStatsHistory(teamID)
                    local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
                    local damageReceived = 0
                    if statsHistory and #statsHistory > 0 then
                        damageReceived = statsHistory[1].damageReceived
                    end
                    value = damageReceived
                elseif statToUpdate == "Damage Efficiency" then
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
                    value = math.floor(damageDealt * 100 / damageReceived)
                end
                teamStats[allyID][teamID].value = value
            end
        end
    end
end

local function updateStatsVSMode()
    vsModeStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            vsModeStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            -- use color of captain
            local colorRed, colorGreen, colorBlue, colorAlpha = Spring.GetTeamColor(teamList[1])
            vsModeStats[allyID].color = { colorRed, colorGreen, colorBlue, colorAlpha }
            local metalIncomeTotal = 0
            local energyIncomeTotal = 0
            local buildPowerTotal = 0
            local metalProducedTotal = 0
            local energyProducedTotal = 0
            local armyValueTotal = 0
            local damageDoneTotal = 0
            for _, teamID in ipairs(teamList) do
                vsModeStats[allyID][teamID] = {}
                vsModeStats[allyID][teamID].color = { Spring.GetTeamColor(teamID) }
                local historyMax = Spring.GetTeamStatsHistory(teamID)
                local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
                local teamMetalIncome = select(4, Spring.GetTeamResources(teamID, "metal")) or 0
                local teamEnergyIncome = select(4, Spring.GetTeamResources(teamID, "energy")) or 0
                local teamBuildPower = 0 -- TODO: calculate build power
                local teamMetalProduced = 0
                local teamEnergyProduced = 0
                local teamDamageDone = 0
                if statsHistory and #statsHistory > 0 then
                    teamMetalProduced = statsHistory[1].metalProduced
                    teamEnergyProduced = statsHistory[1].energyProduced
                    teamDamageDone = statsHistory[1].damageDealt
                end
                local teamArmyValueTotal = 0
                local unitIDs = Spring.GetTeamUnits(teamID)
                for i = 1, #unitIDs do
                    local unitID = unitIDs[i]
                    local currentUnitDefID = Spring.GetUnitDefID(unitID)
                    if currentUnitDefID then
                        local currentUnitMetalCost = UnitDefs[currentUnitDefID].metalCost
                        if isArmyUnit(currentUnitDefID) and not Spring.GetUnitIsBeingBuilt(unitID) then
                            teamArmyValueTotal = teamArmyValueTotal + currentUnitMetalCost
                        end
                        if not Spring.GetUnitIsBeingBuilt(unitID) then
                            teamBuildPower = teamBuildPower + getUnitBuildPower(currentUnitDefID)
                        end
                    end
                end
                vsModeStats[allyID][teamID].metalIncome = teamMetalIncome
                metalIncomeTotal = metalIncomeTotal + teamMetalIncome
                vsModeStats[allyID][teamID].energyIncome = teamEnergyIncome
                energyIncomeTotal = energyIncomeTotal + teamEnergyIncome
                vsModeStats[allyID][teamID].buildPower = teamBuildPower
                buildPowerTotal = buildPowerTotal + teamBuildPower
                vsModeStats[allyID][teamID].metalProduced = teamMetalProduced
                metalProducedTotal = metalProducedTotal + teamMetalProduced
                vsModeStats[allyID][teamID].energyProduced = teamEnergyProduced
                energyProducedTotal = energyProducedTotal + teamEnergyProduced
                vsModeStats[allyID][teamID].armyValue = teamArmyValueTotal
                armyValueTotal = armyValueTotal + teamArmyValueTotal
                vsModeStats[allyID][teamID].damageDone = teamDamageDone
                damageDoneTotal = damageDoneTotal + teamDamageDone
            end
            vsModeStats[allyID].metalIncome = metalIncomeTotal
            vsModeStats[allyID].energyIncome = energyIncomeTotal
            vsModeStats[allyID].buildPower = buildPowerTotal
            vsModeStats[allyID].metalProduced = metalProducedTotal
            vsModeStats[allyID].energyProduced = energyProducedTotal
            vsModeStats[allyID].armyValue = armyValueTotal
            vsModeStats[allyID].damageDone = damageDoneTotal
        end
    end
end

local function updateStats()
    if not vsMode then
        local metricChosenTitle = getMetricChosen().title
        updateStatsNormalMode(metricChosenTitle)
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
    headerDimensions.width = widgetDimensions.width - 4 * buttonSideLength
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

local function setButtonWidgetSizeIncreasePosition()
    buttonWidgetSizeIncreaseDimensions = {}
    buttonWidgetSizeIncreaseDimensions["top"] = widgetDimensions.top
    buttonWidgetSizeIncreaseDimensions["bottom"] = widgetDimensions.top - buttonSideLength
    buttonWidgetSizeIncreaseDimensions["left"] = widgetDimensions.right - 4 * buttonSideLength
    buttonWidgetSizeIncreaseDimensions["right"] = widgetDimensions.right - 3 * buttonSideLength
end

local function setButtonWidgetSizeDecreasePosition()
    buttonWidgetSizeDecreaseDimensions = {}
    buttonWidgetSizeDecreaseDimensions["top"] = widgetDimensions.top
    buttonWidgetSizeDecreaseDimensions["bottom"] = widgetDimensions.top - buttonSideLength
    buttonWidgetSizeDecreaseDimensions["left"] = widgetDimensions.right - 3 * buttonSideLength
    buttonWidgetSizeDecreaseDimensions["right"] = widgetDimensions.right - 2 * buttonSideLength
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

    vsModeMetricsAreaHeight = vsModeMetricHeight * getAmountOfVSModeMetrics()

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
    setButtonWidgetSizeIncreasePosition()
    setButtonWidgetSizeDecreasePosition()
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
    font:SetTextColor({ 1, 1, 1, 1 })
    font:Print(
        headerLabel,
        headerDimensions.left + borderPadding + headerLabelPadding,
        headerDimensions.bottom + borderPadding + headerLabelPadding,
        fontSize - headerLabelPadding * 2,
        'o'
    )
    font:End()
end

local function updateHeaderTooltip()
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

local function updateButtonWidgetSizeIncreaseTooltip()
    if WG['tooltip'] then
        WG['tooltip'].AddTooltip(
            buttonWidgetSizeIncreaseTooltipName,
            {
                buttonWidgetSizeIncreaseDimensions["left"],
                buttonWidgetSizeIncreaseDimensions["bottom"],
                buttonWidgetSizeIncreaseDimensions["right"],
                buttonWidgetSizeIncreaseDimensions["top"]
            },
            "Increase Widget Size"
        )
    end
end

local function updateButtonWidgetSizeDecreaseTooltip()
    if WG['tooltip'] then
        WG['tooltip'].AddTooltip(
            buttonWidgetSizeDecreaseTooltipName,
            {
                buttonWidgetSizeDecreaseDimensions["left"],
                buttonWidgetSizeDecreaseDimensions["bottom"],
                buttonWidgetSizeDecreaseDimensions["right"],
                buttonWidgetSizeDecreaseDimensions["top"]
            },
            "Decrease Widget Size"
        )
    end
end

local function updateVSModeTooltips()
    local iconLeft = vsModeMetricsAreaLeft + borderPadding + vsModeMetricIconPadding
    local iconRight = iconLeft + vsModeMetricIconWidth

    if WG['tooltip'] then
        for _, vsModeMetric in ipairs(vsModeMetrics) do
            local bottom = vsModeMetricsAreaTop - vsModeMetric.id * vsModeMetricHeight
            local top = bottom + vsModeMetricHeight

            local iconBottom = bottom + borderPadding + vsModeMetricIconPadding
            local iconTop = iconBottom + vsModeMetricIconHeight

            WG['tooltip'].AddTooltip(
                string.format("spectator_hud_vsmode_%d", vsModeMetric.id),
                { iconLeft, iconBottom, iconRight, iconTop },
                vsModeMetric.tooltip
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

local function deleteButtonWidgetSizeIncreaseTooltip()
    if WG['tooltip'] then
        WG['tooltip'].RemoveTooltip(buttonWidgetSizeIncreaseTooltipName)
    end
end

local function deleteButtonWidgetSizeDecreaseTooltip()
    if WG['tooltip'] then
        WG['tooltip'].RemoveTooltip(buttonWidgetSizeDecreaseTooltipName)
    end
end

local function deleteVSModeTooltips()
    if WG['tooltip'] then
        for _, vsModeMetric in ipairs(vsModeMetrics) do
            WG['tooltip'].RemoveTooltip(string.format("spectator_hud_vsmode_%d", vsModeMetric.id))
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

local function createButtonWidgetSizeIncrease()
    buttonWidgetSizeIncreaseBackgroundDisplayList = gl.CreateList(function ()
        WG.FlowUI.Draw.Element(
            buttonWidgetSizeIncreaseDimensions["left"],
            buttonWidgetSizeIncreaseDimensions["bottom"],
            buttonWidgetSizeIncreaseDimensions["right"],
            buttonWidgetSizeIncreaseDimensions["top"],
            1, 1, 1, 1,
            1, 1, 1, 1
        )
    end)
end

local function createButtonWidgetSizeDecrease()
    buttonWidgetSizeDecreaseBackgroundDisplayList = gl.CreateList(function ()
        WG.FlowUI.Draw.Element(
            buttonWidgetSizeDecreaseDimensions["left"],
            buttonWidgetSizeDecreaseDimensions["bottom"],
            buttonWidgetSizeDecreaseDimensions["right"],
            buttonWidgetSizeDecreaseDimensions["top"],
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

local function drawButtonWidgetSizeIncrease()
    local buttonMiddleX = math.floor((buttonWidgetSizeIncreaseDimensions["right"] +
        buttonWidgetSizeIncreaseDimensions["left"]) / 2)
    local buttonMiddleY = math.floor((buttonWidgetSizeIncreaseDimensions["top"] +
        buttonWidgetSizeIncreaseDimensions["bottom"]) / 2)
    font:Begin()
        font:SetTextColor({ 1, 1, 1, 1 })
        font:Print(
            "+",
            buttonMiddleX,
            buttonMiddleY,
            fontSize - headerLabelPadding * 2,
            'cvo'
        )
    font:End()
end

local function drawButtonWidgetSizeDecrease()
    local buttonMiddleX = math.floor((buttonWidgetSizeDecreaseDimensions["right"] +
        buttonWidgetSizeDecreaseDimensions["left"]) / 2)
    local buttonMiddleY = math.floor((buttonWidgetSizeDecreaseDimensions["top"] +
        buttonWidgetSizeDecreaseDimensions["bottom"]) / 2)
    font:Begin()
        font:SetTextColor({ 1, 1, 1, 1 })
        font:Print(
            "-",
            buttonMiddleX,
            buttonMiddleY,
            fontSize - headerLabelPadding * 2,
            'cvo'
        )
    font:End()
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
    for _, vsModeMetric in ipairs(vsModeMetrics) do
        local currentBottom = vsModeMetricsAreaTop - vsModeMetric.id * vsModeMetricHeight
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
        font:SetTextColor({ 1, 1, 1, 1 })
        font:Print(
            amountText,
            amountMiddle,
            amountCenter,
            fontSizeMetric,
            'cvo'
        )
    font:End()

    if WG['tooltip'] and playerName then
        local tooltipName = string.format("stat_bar_player_%s", playerName)
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
            { currentStat.colorRed, currentStat.colorGreen, currentStat.colorBlue, currentStat.colorAlpha },
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
    local matchingGrey = makeDarkerColor(color, 0.5)
    gl.Color(matchingGrey[1], matchingGrey[2], matchingGrey[3], 1)
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
        font:SetTextColor({ 1, 1, 1, 1 })
        font:Print(
            text,
            math.floor((right + left) / 2),
            math.floor((top + bottom) / 2),
            fontSizeVSModeKnob,
            'cvO'
        )
    font:End()
end

local function drawVSBar(left, bottom, right, top, valueLeft, valueRight, colorLeft, colorRight, leftTeamValues, rightTeamValues, metricTitle)
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

    local knobColor
    if valueLeft > valueRight then
        knobColor = colorLeft
    elseif valueRight > valueLeft then
        knobColor = colorRight
    else
        -- color grey if even
        knobColor = { 0.6, 0.6, 0.6, 1 }
    end

    gl.Color(makeDarkerColor(colorLeft, constants.darkerBarsFactor))
    gl.Rect(
        left,
        barBottom,
        left + leftBarWidth,
        barTop
    )

    gl.Color(makeDarkerColor(colorRight, constants.darkerBarsFactor))
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
        for _, teamValue in ipairs(leftTeamValues) do
            lineStart = lineEnd
            lineEnd = lineEnd + math.floor(teamValue.value * scalingFactor)
            gl.Color(teamValue.color)
            gl.Rect(
                lineStart,
                barBottom,
                lineEnd,
                barTop
            )
        end

        local lineStart
        local lineEnd = right - rightBarWidth
        for _, teamValue in ipairs(rightTeamValues) do
            lineStart = lineEnd
            lineEnd = lineEnd + math.floor(teamValue.value * scalingFactor)
            gl.Color(teamValue.color)
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
            makeDarkerColor(knobColor, constants.darkerMiddleKnobFactor),
            formatResources(math.abs(valueLeft - valueRight), true)
        )

        if WG['tooltip'] then
            local tooltipText = string.format("Left: %s\nRight: %s",
                formatResources(valueLeft, false),
                formatResources(valueRight, false)
            )
            WG['tooltip'].ShowTooltip(
                "spectator_hud_vsmode_mouseover_tooltip",
                tooltipText,
                mouseX + vsModeBarTooltipOffsetX,
                mouseY + vsModeBarTooltipOffsetY,
                metricTitle
            )
        end
    else
        local lineMiddle = math.floor((top + bottom) / 2)
        local lineBottom = lineMiddle - math.floor(vsModeLineHeight / 2)
        local lineTop = lineMiddle + math.floor(vsModeLineHeight / 2)

        gl.Color(makeDarkerColor(colorLeft, constants.darkerLinesFactor))
        gl.Rect(
            left,
            lineBottom,
            left + leftBarWidth,
            lineTop
        )

        gl.Color(makeDarkerColor(colorRight, constants.darkerLinesFactor))
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
            makeDarkerColor(knobColor, constants.darkerMiddleKnobFactor),
            relativeLeadString
        )
    end
end

local function drawVSModeMetrics()
    local indexLeft = 1
    local indexRight = 0
    for _, vsModeMetric in ipairs(vsModeMetrics) do
        local bottom = vsModeMetricsAreaTop - vsModeMetric.id * vsModeMetricHeight
        local top = bottom + vsModeMetricHeight

        local iconLeft = vsModeMetricsAreaLeft + borderPadding + vsModeMetricIconPadding
        local iconRight = iconLeft + vsModeMetricIconWidth
        local iconBottom = bottom + borderPadding + vsModeMetricIconPadding
        local iconTop = iconBottom + vsModeMetricIconHeight

        local iconHCenter = math.floor((iconRight + iconLeft) / 2)
        local iconVCenter = math.floor((iconTop + iconBottom) / 2)
        local iconText = vsModeMetric.text

        font:Begin()
            font:SetTextColor({ 1, 1, 1, 1 })
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
            makeDarkerColor(vsModeStats[indexLeft].color, constants.darkerSideKnobsFactor),
            formatResources(vsModeStats[indexLeft][vsModeMetric.key], true)
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
            makeDarkerColor(vsModeStats[indexRight].color, constants.darkerSideKnobsFactor),
            formatResources(vsModeStats[indexRight][vsModeMetric.key], true)
        )

        local leftTeamValues = {}
        local leftTeamIDs = Spring.GetTeamList(indexLeft)
        for _, teamID in ipairs(leftTeamIDs) do
            table.insert(leftTeamValues, {
                value = vsModeStats[indexLeft][teamID][vsModeMetric.key],
                color = vsModeStats[indexLeft][teamID].color
            })
        end

        local rightTeamValues = {}
        local rightTeamIDs = Spring.GetTeamList(indexRight)
        for _, teamID in ipairs(rightTeamIDs) do
            table.insert(rightTeamValues, {
                value = vsModeStats[indexRight][teamID][vsModeMetric.key],
                color = vsModeStats[indexRight][teamID].color
            })
        end

        drawVSBar(
            leftKnobRight,
            iconBottom,
            rightKnobLeft,
            iconTop,
            vsModeStats[indexLeft][vsModeMetric.key],
            vsModeStats[indexRight][vsModeMetric.key],
            vsModeStats[indexLeft].color,
            vsModeStats[indexRight].color,
            leftTeamValues,
            rightTeamValues,
            vsModeMetric.metric
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
	WG.FlowUI.Draw.RectRound(sx-(sy-py), py, sx, sy, cs, 1, 1, 1, 1, { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.14 })
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
        font:SetTextColor({ 1, 1, 1, 1 })
        local distanceFromTop = 0
        local amountOfMetrics = getAmountOfMetrics()
        for _, currentMetric in ipairs(metricsAvailable) do
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

local function deleteButtonWidgetSizeIncrease()
    gl.DeleteList(buttonWidgetSizeIncreaseBackgroundDisplayList)
end

local function deleteButtonWidgetSizeDecrease()
    gl.DeleteList(buttonWidgetSizeDecreaseBackgroundDisplayList)
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
    createButtonWidgetSizeIncrease()
    updateButtonWidgetSizeIncreaseTooltip()
    createButtonWidgetSizeDecrease()
    updateButtonWidgetSizeDecreaseTooltip()
    createStatsArea()
    createVSModeBackgroudDisplayLists()

    vsModeEnabled = getAmountOfAllyTeams() == 2
    if not vsModeEnabled then
        vsMode = false
    end

    if vsMode then
        updateVSModeTooltips()
    end

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
    deleteButtonWidgetSizeIncrease()
    deleteButtonWidgetSizeIncreaseTooltip()
    deleteButtonWidgetSizeDecrease()
    deleteButtonWidgetSizeDecreaseTooltip()
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

local function setMetricChosen(metricID)
    if metricID < 1 or metricID > getAmountOfMetrics() then
        return
    end

    metricChosenID = metricID

    local metricChosen = getMetricChosen()
    headerLabel = metricChosen.title
    updateHeaderTooltip()
end

function widget:Initialize()
    checkAndUpdateHaveFullView()

    font = WG['fonts'].getFont()

    init()
end

function widget:Shutdown()
    deInit()
end

function widget:TeamDied(teamID)
    checkAndUpdateHaveFullView()

    if haveFullView then
        processPlayerCountChanged()
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
                local metricPressed = getAmountOfMetrics() - math.floor((y - metricChangeBottom) / headerDimensions.height)
                setMetricChosen(metricPressed)
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

    if isInDimensions(x, y, buttonWidgetSizeIncreaseDimensions) then
        widgetScale = widgetScale + 0.1
        reInit()
        return
    end

    if isInDimensions(x, y, buttonWidgetSizeDecreaseDimensions) then
        widgetScale = widgetScale - 0.1
        reInit()
        return
    end
end

function widget:ViewResize()
    reInit()
end
             
function widget:GameFrame(frameNum)
    if not haveFullView then
        return
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

        gl.CallList(buttonWidgetSizeIncreaseBackgroundDisplayList)
        drawButtonWidgetSizeIncrease()

        gl.CallList(buttonWidgetSizeDecreaseBackgroundDisplayList)
        drawButtonWidgetSizeDecrease()

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
    return {
        widgetScale = widgetScale,
        metricChosenID = metricChosenID,
        sortingChosen = sortingChosen,
        vsMode = vsMode,
    }
end

function widget:SetConfigData(data)
    if data.widgetScale then
        widgetScale = data.widgetScale
    end
    if data.metricChosenID then
        metricChosenID = data.metricChosenID
        local metricChosen = getMetricChosen(metricChosenID)
        if metricChosen then
            headerLabel = metricChosen.title
        else
            metricChosen = 1
            headerLabel = "Metal Income"
        end
    end
    if data.sortingChosen then
        sortingChosen = data.sortingChosen
    end
    if data.vsMode then
        vsMode = data.vsMode
    end
end
