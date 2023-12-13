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

3. Army value view
Shows army metal cost.

4. Army size view
Shows army size in units.

5. Damage done view

6. Damage received view

7. Damage efficiency view

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

--local inSpecMode = false
--local isReplay = Spring.IsReplay()
local haveFullView = false

local ui_scale = tonumber(Spring.GetConfigFloat("ui_scale", 1) or 1)
local widgetScale = 0.8

local topBarPosition
local topBarShowButtons

local viewScreenWidth, viewScreenHeight
local widgetWidth, widgetHeight
local widgetTop, widgetBottom, widgetLeft, widgetRight

local headerWidth, headerHeight
local buttonSideLength

local statsBarWidth, statsBarHeight
local statsAreaWidth, statsAreaHeight

local vsModeMetricWidth, vsModeMetricHeight
local vsModeMetricsAreaWidth, vsModeMetricsAreaHeight

local headerTop, headerBottom, headerLeft, headerRight
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
local fontSizeDefault = 64 * 1.2
local fontSizeMetric
local fontSizeVSBar

local statBarHeightToHeaderHeight = 1.0

local distanceFromTopBar
local distanceFromTopBarDefault = 10

local borderPadding
local borderPaddingDefault = 5
local headerLabelPadding
local headerLabelPaddingDefault = 20
local buttonPadding
local buttonPaddingDefault = 8
local teamDecalPadding
local teamDecalPaddingDefault = 6
local vsModeMetricIconPadding
local vsModeMetricIconPaddingDefault = 6
local teamDecalHeight
local vsModeMetricIconHeight
local barOutlineWidth
local barOutlineWidthDefault = 4
local barOutlinePadding
local barOutlinePaddingDefault = 4
local barCornerSize
local barCornerSizeDefault = 8
local barOutlineCornerSize
local barOutlineCornerSizeDefault = 8
local teamDecalCornerSize
local teamDecalCornerSizeDefault = 8
local vsModeBarTextPadding
local vsModeBarTextPaddingDefault = 20

local barChunkSize
local vsModeBarChunkSize
local vsModeBarMarkerWidth, vsModeBarMarkerHeight
local vsModeBarMarkerWidthDefault = 2
local vsModeBarMarkerHeightDefault = 8
--local barChunkSizeSource = 40      -- from source image

local buttonWidgetSizeIncreaseTooltipName = "spectator_hud_size_increase"
local buttonWidgetSizeDecreaseTooltipName = "spectator_hud_size_decrease"

local sortingTooltipName = "spectator_hud_sorting"
local sortingTooltipTitle = "Sorting"
local sortingPlayerTooltipText = "Sort by Player (click to change)"
local sortingTeamTooltipText = "Sort by Team (click to change)"
local sortingTeamAggregateTooltipText = "Sort by Team Aggregate (click to change)"

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
    { id=3, title="Army Value", tooltip="Army Value in Metal" },
    { id=4, title="Army Size", tooltip="Army Size in Units" },
    { id=5, title="Damage Done", tooltip="Damage Done" },
    { id=6, title="Damage Received", tooltip="Damage Received" },
    { id=7, title="Damage Efficiency", tooltip="Damage Efficiency" },
}

local vsMode = false
local vsModeEnabled = false

local vsModeMetrics = {
    { id=1, icon="iconM", metric="Metal Income"},
    { id=2, icon="iconE", metric="Energy Income"},
    { id=3, icon="iconBP", metric="Build Power"},
    { id=4, icon="iconM", metric="Metal Produced"},
    { id=5, icon="iconE", metric="Energy Produced"},
    { id=6, icon="iconA", metric="Army Value"},
    { id=7, icon="iconD", metric="Damage Dealt"},
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
    barOutlineStart = "LuaUI/Images/spectator_hud/bar-outline-start.png",
    barOutlineMiddle = "LuaUI/Images/spectator_hud/bar-outline-middle.png",
    barOutlineEnd = "LuaUI/Images/spectator_hud/bar-outline-end.png",
    barProgressStart = "LuaUI/Images/spectator_hud/bar-progress-start.png",
    barProgressMiddle = "LuaUI/Images/spectator_hud/bar-progress-middle.png",
    barProgressEnd = "LuaUI/Images/spectator_hud/bar-progress-end.png",
    barProgressStartRed = "LuaUI/Images/spectator_hud/bar-progress-start-red.png",
    barProgressMiddleRed = "LuaUI/Images/spectator_hud/bar-progress-middle-red.png",
    barProgressMiddleBlue = "LuaUI/Images/spectator_hud/bar-progress-middle-blue.png",
    barProgressEndBlue = "LuaUI/Images/spectator_hud/bar-progress-end-blue.png",
    toggleVSMode = "LuaUI/Images/spectator_hud/button-vs.png",
    iconM = "LuaUI/Images/spectator_hud/button-m.png",
    iconE = "LuaUI/Images/spectator_hud/button-e.png",
    iconBP = "LuaUI/Images/spectator_hud/button-bp.png",
    iconA = "LuaUI/Images/spectator_hud/button-a.png",
    iconD = "LuaUI/Images/spectator_hud/button-d.png",
}

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
            return string.format("%d M", amount / million)
        elseif amount >= million then
            return string.format("%.1f M", amount / million)
        elseif amount >= tenThousand then
            return string.format("%d k", amount / thousand)
        elseif amount >= thousand then
            return string.format("%.1f k", amount / thousand)
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

local function isArmyUnit(unitDefID)
    if UnitDefs[unitDefID].weapons and (#UnitDefs[unitDefID].weapons > 0) then
        return true
    else
        return false
    end
end

local function getUnitBuildPower(unitDefID)
    if UnitDefs[unitDefID].buildSpeed then
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
            index = index + 1
        end
        table.sort(allyTotals, function(left, right)
            return left.value > right.value
        end)
        result = allyTotals
    end

    return result
end

local function updateStatsMetalIncome()
    teamStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            teamStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                local teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha = Spring.GetTeamColor(teamID)
                local metalIncome = select(4, Spring.GetTeamResources(teamID, "metal")) or 0
                teamStats[allyID][teamID] = {}
                teamStats[allyID][teamID].colorRed = teamColorRed
                teamStats[allyID][teamID].colorGreen = teamColorGreen
                teamStats[allyID][teamID].colorBlue = teamColorBlue
                teamStats[allyID][teamID].colorAlpha = teamColorAlpha
                teamStats[allyID][teamID].value = metalIncome
            end
        end
    end
end

local function updateStatsMetalProduced()
    teamStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            teamStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                local teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha = Spring.GetTeamColor(teamID)
                local historyMax = Spring.GetTeamStatsHistory(teamID)
                local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
                local metalProduced = 0
                if statsHistory and #statsHistory > 0 then
                    metalProduced = statsHistory[1].metalProduced
                end
                teamStats[allyID][teamID] = {}
                teamStats[allyID][teamID].colorRed = teamColorRed
                teamStats[allyID][teamID].colorGreen = teamColorGreen
                teamStats[allyID][teamID].colorBlue = teamColorBlue
                teamStats[allyID][teamID].colorAlpha = teamColorAlpha
                teamStats[allyID][teamID].value = metalProduced
            end
        end
    end
end

local function updateStatsArmyValue()
    teamStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            teamStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                local teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha = Spring.GetTeamColor(teamID)
                local armyValueTotal = 0
                local unitIDs = Spring.GetTeamUnits(teamID)
                for i = 1, #unitIDs do
                    local unitID = unitIDs[i]
                    local currentUnitDefID = Spring.GetUnitDefID(unitID)
                    local currentUnitMetalCost = UnitDefs[currentUnitDefID].metalCost
                    if isArmyUnit(currentUnitDefID) and not Spring.GetUnitIsBeingBuilt(unitID) then
                        armyValueTotal = armyValueTotal + currentUnitMetalCost
                    end
                end
                teamStats[allyID][teamID] = {}
                teamStats[allyID][teamID].colorRed = teamColorRed
                teamStats[allyID][teamID].colorGreen = teamColorGreen
                teamStats[allyID][teamID].colorBlue = teamColorBlue
                teamStats[allyID][teamID].colorAlpha = teamColorAlpha
                teamStats[allyID][teamID].value = armyValueTotal
            end
        end
    end
end

local function updateStatsArmySize()
    teamStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            teamStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                local teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha = Spring.GetTeamColor(teamID)
                local unitIDs = Spring.GetTeamUnits(teamID)
                local armySizeTotal = 0
                for i = 1, #unitIDs do
                    local unitID = unitIDs[i]
                    local currentUnitDefID = Spring.GetUnitDefID(unitID)
                    if isArmyUnit(currentUnitDefID) and not Spring.GetUnitIsBeingBuilt(unitID)then
                        armySizeTotal = armySizeTotal + 1
                    end
                end
                teamStats[allyID][teamID] = {}
                teamStats[allyID][teamID].colorRed = teamColorRed
                teamStats[allyID][teamID].colorGreen = teamColorGreen
                teamStats[allyID][teamID].colorBlue = teamColorBlue
                teamStats[allyID][teamID].colorAlpha = teamColorAlpha
                teamStats[allyID][teamID].value = armySizeTotal
            end
        end
    end
end

local function updateStatsDamageDone()
    teamStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            teamStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                local teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha = Spring.GetTeamColor(teamID)
                local historyMax = Spring.GetTeamStatsHistory(teamID)
                local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
                local damageDealt = 0
                if statsHistory and #statsHistory > 0 then
                    damageDealt = statsHistory[1].damageDealt
                end
                teamStats[allyID][teamID] = {}
                teamStats[allyID][teamID].colorRed = teamColorRed
                teamStats[allyID][teamID].colorGreen = teamColorGreen
                teamStats[allyID][teamID].colorBlue = teamColorBlue
                teamStats[allyID][teamID].colorAlpha = teamColorAlpha
                teamStats[allyID][teamID].value = damageDealt
            end
        end
    end
end

local function updateStatsDamageReceived()
    teamStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            teamStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                local teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha = Spring.GetTeamColor(teamID)
                local historyMax = Spring.GetTeamStatsHistory(teamID)
                local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
                local damageReceived = 0
                if statsHistory and #statsHistory > 0 then
                    damageReceived = statsHistory[1].damageReceived
                end
                teamStats[allyID][teamID] = {}
                teamStats[allyID][teamID].colorRed = teamColorRed
                teamStats[allyID][teamID].colorGreen = teamColorGreen
                teamStats[allyID][teamID].colorBlue = teamColorBlue
                teamStats[allyID][teamID].colorAlpha = teamColorAlpha
                teamStats[allyID][teamID].value = damageReceived
            end
        end
    end
end

local function updateStatsDamageEfficiency()
    teamStats = {}
    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            teamStats[allyID] = {}
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                local teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha = Spring.GetTeamColor(teamID)
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
                local value = math.floor(damageDealt * 100 / damageReceived)
                teamStats[allyID][teamID] = {}
                teamStats[allyID][teamID].colorRed = teamColorRed
                teamStats[allyID][teamID].colorGreen = teamColorGreen
                teamStats[allyID][teamID].colorBlue = teamColorBlue
                teamStats[allyID][teamID].colorAlpha = teamColorAlpha
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
                    local currentUnitMetalCost = UnitDefs[currentUnitDefID].metalCost
                    if isArmyUnit(currentUnitDefID) and not Spring.GetUnitIsBeingBuilt(unitID) then
                        teamArmyValueTotal = teamArmyValueTotal + currentUnitMetalCost
                    end
                    if not Spring.GetUnitIsBeingBuilt(unitID) then
                        teamBuildPower = teamBuildPower + getUnitBuildPower(currentUnitDefID)
                    end
                end
                metalIncomeTotal = metalIncomeTotal + teamMetalIncome
                energyIncomeTotal = energyIncomeTotal + teamEnergyIncome
                buildPowerTotal = buildPowerTotal + teamBuildPower
                metalProducedTotal = metalProducedTotal + teamMetalProduced
                energyProducedTotal = energyProducedTotal + teamEnergyProduced
                armyValueTotal = armyValueTotal + teamArmyValueTotal
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
        if metricChosenTitle == "Metal Income" then
            updateStatsMetalIncome()
        elseif metricChosenTitle == "Metal Produced" then
            updateStatsMetalProduced()
        elseif metricChosenTitle == "Army Value" then
            updateStatsArmyValue()
        elseif metricChosenTitle == "Army Size" then
            updateStatsArmySize()
        elseif metricChosenTitle == "Damage Done" then
            updateStatsDamageDone()
        elseif metricChosenTitle == "Damage Received" then
            updateStatsDamageReceived()
        elseif metricChosenTitle == "Damage Efficiency" then
            updateStatsDamageEfficiency()
        end
    else
        updateStatsVSMode()
    end
end

local function calculateHeaderSize()
    local headerTextHeight = font:GetTextHeight(headerLabelDefault) * fontSize
    headerHeight = math.floor(2 * borderPadding + headerTextHeight)

    -- all buttons on the header are squares and of the same size
    -- their sides are the same length as the header height
    buttonSideLength = headerHeight

    -- currently, we have four buttons
    headerWidth = widgetWidth - 4 * buttonSideLength
end

local function calculateStatsBarSize()
    statsBarHeight = math.floor(headerHeight * statBarHeightToHeaderHeight)
    statsBarWidth = widgetWidth
end

local function calculateVSModeMetricSize()
    vsModeMetricHeight = math.floor(headerHeight * statBarHeightToHeaderHeight)
    vsModeMetricWidth = widgetWidth
end

local function setSortingPosition()
    sortingTop = widgetTop
    sortingBottom = widgetTop - buttonSideLength
    sortingLeft = widgetRight - buttonSideLength
    sortingRight = widgetRight
end

local function setToggleVSModePosition()
    toggleVSModeTop = widgetTop
    toggleVSModeBottom = widgetTop - buttonSideLength
    toggleVSModeLeft = sortingLeft - buttonSideLength
    toggleVSModeRight = sortingLeft
end

local function setButtonWidgetSizeIncreasePosition()
    buttonWidgetSizeIncreaseDimensions = {}
    buttonWidgetSizeIncreaseDimensions["top"] = widgetTop
    buttonWidgetSizeIncreaseDimensions["bottom"] = widgetTop - buttonSideLength
    buttonWidgetSizeIncreaseDimensions["left"] = widgetRight - 4 * buttonSideLength
    buttonWidgetSizeIncreaseDimensions["right"] = widgetRight - 3 * buttonSideLength
end

local function setButtonWidgetSizeDecreasePosition()
    buttonWidgetSizeDecreaseDimensions = {}
    buttonWidgetSizeDecreaseDimensions["top"] = widgetTop
    buttonWidgetSizeDecreaseDimensions["bottom"] = widgetTop - buttonSideLength
    buttonWidgetSizeDecreaseDimensions["left"] = widgetRight - 3 * buttonSideLength
    buttonWidgetSizeDecreaseDimensions["right"] = widgetRight - 2 * buttonSideLength
end

local function setHeaderPosition()
    headerTop = widgetTop
    headerBottom = widgetTop - headerHeight
    headerLeft = widgetLeft
    headerRight = widgetRight - headerWidth

    metricChangeBottom = headerBottom - headerHeight * getAmountOfMetrics()
end

local function setStatsAreaPosition()
    statsAreaTop = widgetTop - headerHeight
    statsAreaBottom = widgetBottom
    statsAreaLeft = widgetLeft
    statsAreaRight = widgetRight
end

local function setVSModeMetricsAreaPosition()
    vsModeMetricsAreaTop = widgetTop - headerHeight
    vsModeMetricsAreaBottom = widgetBottom
    vsModeMetricsAreaLeft = widgetLeft
    vsModeMetricsAreaRight = widgetRight
end

local function calculateWidgetSizeScaleVariables(scaleMultiplier)
    -- Lua has a limit in "upvalues" (60 in total) and therefore this is split
    -- into a separate function
    distanceFromTopBar = math.floor(distanceFromTopBarDefault * scaleMultiplier)
    borderPadding = math.floor(borderPaddingDefault * scaleMultiplier)
    headerLabelPadding = math.floor(headerLabelPaddingDefault * scaleMultiplier)
    buttonPadding = math.floor(buttonPadding * scaleMultiplier)
    teamDecalPadding = math.floor(teamDecalPaddingDefault * scaleMultiplier)
    vsModeMetricIconPadding = math.floor(vsModeMetricIconPaddingDefault * scaleMultiplier)
    barOutlineWidth = math.floor(barOutlineWidthDefault * scaleMultiplier)
    barOutlinePadding = math.floor(barOutlinePaddingDefault * scaleMultiplier)
    barCornerSize = math.floor(barCornerSizeDefault * scaleMultiplier)
    barOutlineCornerSize = math.floor(barOutlineCornerSizeDefault * scaleMultiplier)
    teamDecalCornerSize = math.floor(teamDecalCornerSizeDefault * scaleMultiplier)
    vsModeBarTextPadding = math.floor(vsModeBarTextPaddingDefault * scaleMultiplier)
end

local function calculateWidgetSize()
    local scaleMultiplier = ui_scale * widgetScale * viewScreenWidth / 3840
    calculateWidgetSizeScaleVariables(scaleMultiplier)

    fontSize = math.floor(fontSizeDefault * scaleMultiplier)
    fontSizeMetric = math.floor(fontSize * 0.5)
    fontSizeVSBar = math.floor(fontSize * 0.5)

    widgetWidth = math.floor(viewScreenWidth * 0.20 * ui_scale * widgetScale)

    calculateHeaderSize()
    calculateSortingSize()
    calculateToggleVSModeSize()
    calculateStatsBarSize()
    calculateVSModeMetricSize()
    calculateButtonWidgetSizeIncreaseSize()
    calculateButtonWidgetSizeDecreaseSize()
    statsAreaWidth = widgetWidth
    vsModeMetricsAreaWidth = widgetWidth

    local statBarAmount
    if sortingChosen == "teamaggregate" then
        statBarAmount = getAmountOfAllyTeams()
    else
        statBarAmount = getAmountOfTeams()
    end
    statsAreaHeight = statsBarHeight * statBarAmount
    teamDecalHeight = statsBarHeight - borderPadding * 2 - teamDecalPadding * 2
    vsModeMetricIconHeight = vsModeMetricHeight - borderPadding * 2 - vsModeMetricIconPadding * 2
    barChunkSize = math.floor(teamDecalHeight / 2)
    vsModeBarChunkSize = math.floor(vsModeMetricIconHeight / 2)
    vsModeBarMarkerWidth = math.floor(vsModeBarMarkerWidthDefault * scaleMultiplier)
    vsModeBarMarkerHeight = math.floor(vsModeBarMarkerHeightDefault * scaleMultiplier)

    vsModeMetricsAreaHeight = vsModeMetricHeight * getAmountOfVSModeMetrics()

    if not vsMode then
        widgetHeight = headerHeight + statsAreaHeight
    else
        widgetHeight = headerHeight + vsModeMetricsAreaHeight
    end
end

local function setWidgetPosition()
    -- widget is placed underneath topbar
    if WG['topbar'] then
        local topBarPosition = WG['topbar'].GetPosition()
        local topBarShowButtons = WG['topbar'].getShowButtons()
        widgetTop = topBarShowButtons and (topBarPosition[2] - distanceFromTopBar) or topBarPosition[4]
    else
        widgetTop = viewScreenHeight
    end
    widgetBottom = widgetTop - widgetHeight
    widgetRight = viewScreenWidth
    widgetLeft = widgetRight - widgetWidth

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
                widgetLeft,
                widgetBottom,
                widgetRight,
                widgetTop,
                WG.FlowUI.elementCorner)
        end)
        WG['guishader'].InsertDlist(backgroundShader, 'spectator_hud', true)
    end
end

local function drawHeader()
    WG.FlowUI.Draw.Element(
        headerLeft,
        headerBottom,
        headerRight,
        headerTop,
        1, 1, 1, 1,
        1, 1, 1, 1
    )

    font:Begin()
    font:SetTextColor({ 1, 1, 1, 1 })
    font:Print(
        headerLabel,
        headerLeft + borderPadding + headerLabelPadding,
        headerBottom + borderPadding + headerLabelPadding,
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
            { headerLeft, headerBottom, headerRight, headerTop },
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
            tooltipText = sortingPlayerTooltipText
        elseif sortingChosen == "team" then
            tooltipText = sortingTeamTooltipText
        elseif sortingChosen == "teamaggregate" then
            tooltipText = sortingTeamAggregateTooltipText
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
    local buttonMiddleX = buttonWidgetSizeIncreaseDimensions["left"] +
        math.floor((buttonWidgetSizeIncreaseDimensions["right"] - buttonWidgetSizeIncreaseDimensions["left"]) / 2)
    local buttonMiddleY = buttonWidgetSizeIncreaseDimensions["bottom"] +
        math.floor((buttonWidgetSizeIncreaseDimensions["top"] - buttonWidgetSizeIncrease["bottom"]) / 2)
    font:Begin()
        font:SetTextColor({ 1, 1, 1, 1 })
        font:Print(
            "+",
            buttonMiddleX,
            buttonMiddleY,
            fontSize,
            'cvo'
        )
    font:End()
end

local function drawButtonWidgetSizeDecrease()
    local buttonMiddleX = buttonWidgetSizeDecreaseDimensions["left"] +
        math.floor((buttonWidgetSizeDecreaseDimensions["right"] - buttonWidgetSizeDecreaseDimensions["left"]) / 2)
    local buttonMiddleY = buttonWidgetSizeDecreaseDimensions["bottom"] +
        math.floor((buttonWidgetSizeDecreaseDimensions["top"] - buttonWidgetSizeDecreaseDimensions["bottom"]) / 2)
    font:Begin()
        font:SetTextColor({ 1, 1, 1, 1 })
        font:Print(
            "+",
            buttonMiddleX,
            buttonMiddleY,
            fontSize,
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

local function drawAUnicolorBar(left, bottom, right, top, value, max, color)
    gl.Color(0, 0, 0, 1)
    --[[
    gl.Rect(
        left,
        bottom,
        right,
        top + barOutlineWidth
    )
    gl.Rect(
        left,
        bottom,
        left + barOutlineWidth,
        top
    )
    gl.Rect(
        left,
        top - barOutlineWidth,
        right,
        top
    )
    gl.Rect(
        left - barOutlineWidth,
        bottom,
        right,
        top
    )
    ]]
    --gl.Rect(left, bottom, right, top)
    WG.FlowUI.Draw.RectRound(
        left,
        bottom,
        right,
        top,
        barOutlineCornerSize
    )

    local scaleFactor = (right - left - 2 * (barOutlineWidth + barOutlinePadding)) / max

    gl.Color(color)
    gl.Rect(
        left + barOutlineWidth + barOutlinePadding,
        bottom + barOutlineWidth + barOutlinePadding,
        left + barOutlineWidth + barOutlinePadding + math.floor(value * scaleFactor),
        top - barOutlineWidth - barOutlinePadding
    )
end

local function drawAMulticolorBar(left, bottom, right, top, values, colors)
    gl.Color(0, 0, 0, 1)
    gl.Rect(left, bottom, right, top)

    local total = 0
    for i=1,#values do
        total = total + values[i]
    end

    local scaleFactor = (right - left - 2 * barPadding) / total

    local valueStart = 0
    local valueEnd = 0
    for i=1,#values do
        valueStart = valueEnd
        valueEnd = valueStart + values[i]

        local currentLeft = math.floor(left + barPadding + valueStart * scaleFactor)
        local currentRight = math.floor(currentLeft + values[i] * scaleFactor)

        gl.Color(colors[i])
        gl.Rect(
            currentLeft,
            bottom + barPadding,
            currentRight,
            top - barPadding
        )
    end
end

local function drawABar(left, bottom, right, top, amount, max)
    gl.Color(1, 1, 1, 1)
    gl.Texture(images["barOutlineStart"])
    gl.TexRect(
        left,
        bottom,
        left + barChunkSize,
        top
    )

    gl.Color(1, 1, 1, 1)
    gl.Texture(images["barOutlineMiddle"])
    gl.TexRect(
        left + barChunkSize,
        bottom,
        right - barChunkSize,
        top
    )

    gl.Color(1, 1, 1, 1)
    gl.Texture(images["barOutlineEnd"])
    gl.TexRect(
        right - barChunkSize,
        bottom,
        right,
        top
    )

    local right2 = left + math.floor((right - left) * amount / max)

    -- make sure we have a least some pixels in the bar
    if (right2 - left) < (barChunkSize * 2) then
        right2 = left + barChunkSize * 2
    end

    gl.Color(1, 1, 1, 1)
    gl.Texture(images["barProgressStart"])
    gl.TexRect(
        left,
        bottom,
        left + barChunkSize,
        top
    )

    gl.Color(1, 1, 1, 1)
    gl.Texture(images["barProgressMiddle"])
    gl.TexRect(
        left + barChunkSize,
        bottom,
        right2 - barChunkSize,
        top
    )

    gl.Color(1, 1, 1, 1)
    gl.Texture(images["barProgressEnd"])
    gl.TexRect(
        right2 - barChunkSize,
        bottom,
        right2,
        top
    )

    gl.Texture(false)
end

local function drawAStatsBar(index, teamColor, amount, max)
    local statBarBottom = statsAreaTop - index * statsBarHeight
    local statBarTop = statBarBottom + statsBarHeight

    local teamDecalBottom = statBarBottom + borderPadding + teamDecalPadding
    local teamDecalTop = statBarTop - borderPadding - teamDecalPadding

    local teamDecalSize = teamDecalTop - teamDecalBottom

    local teamDecalLeft = statsAreaLeft + borderPadding + teamDecalPadding
    local teamDecalRight = teamDecalLeft + teamDecalSize

    WG.FlowUI.Draw.RectRound(
        teamDecalLeft,
        teamDecalBottom,
        teamDecalRight,
        teamDecalTop,
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
        teamColor
    )
    --[[
    drawABar(
        barLeft,
        barBottom,
        barRight,
        barTop,
        amount,
        max
    )
    ]]

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
            max)
        index = index + 1
    end
end

local function drawVSBar(valueRed, valueBlue, left, bottom, right, top)
    local barLength = math.floor(right - left)

    local divider = 0
    if valueRed > 0 or valueBlue > 0 then
        divider = left + math.floor(barLength * valueRed / (valueRed + valueBlue))
    else
        if valueRed == 0 then
            if valueBlue == 0 then
                divider = left + math.floor(barLength / 2)
            else
                divider = left + vsModeBarChunkSize
            end
        else
            divider = right - vsModeBarChunkSize
        end
    end

    gl.Texture(images["barProgressStartRed"])
    gl.TexRect(
        left,
        bottom,
        left + vsModeBarChunkSize,
        top
    )
    gl.Texture(images["barProgressMiddleRed"])
    gl.TexRect(
        left + vsModeBarChunkSize,
        bottom,
        divider,
        top
    )

    gl.Texture(images["barProgressMiddleBlue"])
    gl.TexRect(
        divider,
        bottom,
        right - vsModeBarChunkSize,
        top
    )
    gl.Texture(images["barProgressEndBlue"])
    gl.TexRect(
        right - vsModeBarChunkSize,
        bottom,
        right,
        top
    )

    gl.Color(1, 1, 1, 1)
    gl.Texture(images["barOutlineStart"])
    gl.TexRect(
        left,
        bottom,
        left + vsModeBarChunkSize,
        top
    )
    gl.Texture(images["barOutlineMiddle"])
    gl.TexRect(
        left + vsModeBarChunkSize,
        bottom,
        right - vsModeBarChunkSize,
        top
    )
    gl.Texture(images["barOutlineEnd"])
    gl.TexRect(
        right - vsModeBarChunkSize,
        bottom,
        right,
        top
    )

    gl.Color(1, 1, 1, 1)
    local markers = {{0.2, 1}, {0.4, 1}, {0.5, 2}, {0.6, 1}, {0.8, 1}}
    for _, marker in ipairs(markers) do
        markerX = left + math.floor(barLength * marker[1])
        gl.Rect(
            markerX - vsModeBarMarkerWidth * marker[2],
            top - vsModeBarMarkerHeight * marker[2],
            markerX + vsModeBarMarkerWidth * marker[2],
            top
        )
        gl.Rect(
            markerX - vsModeBarMarkerWidth * marker[2],
            bottom,
            markerX + vsModeBarMarkerWidth * marker[2],
            bottom + vsModeBarMarkerHeight * marker[2]
        )
    end

    font:Begin()
        font:SetTextColor({ 1, 1, 1, 1 })
        font:Print(
            formatResources(valueRed, true),
            --divider - vsModeBarTextPadding,
            left + vsModeBarTextPadding,
            bottom + math.floor((top - bottom) / 2),
            fontSizeVSBar,
            --'rvO'
            'vO'
        )
        font:SetTextColor({ 1, 1, 1, 1 })
        font:Print(
            formatResources(valueBlue, true),
            --divider + vsModeBarTextPadding,
            right - vsModeBarTextPadding,
            bottom + math.floor((top - bottom) / 2),
            fontSizeVSBar,
            --'vO'
            'rvO'
        )
    font:End()
end

local function drawVSModeMetrics()
    local indexRed, indexBlue
    if vsModeStats[0].color[1] == 1 then
        indexRed = 0
        indexBlue = 1
    else
        indexRed = 1
        indexBlue = 0
    end

    for _, vsModeMetric in ipairs(vsModeMetrics) do
        local bottom = vsModeMetricsAreaTop - vsModeMetric.id * vsModeMetricHeight
        local top = bottom + vsModeMetricHeight

        local iconLeft = vsModeMetricsAreaLeft + borderPadding + vsModeMetricIconPadding
        local iconRight = iconLeft + vsModeMetricIconHeight
        local iconBottom = bottom + borderPadding + vsModeMetricIconPadding
        local iconTop = iconBottom + vsModeMetricIconHeight

        local iconImage = images[vsModeMetric.icon]
        gl.Color(1, 1, 1, 1)
        gl.Texture(iconImage)
        gl.TexRect(
            iconLeft,
            iconBottom,
            iconRight,
            iconTop
        )

        local valueRed, valueBlue
        if vsModeMetric.metric == "Metal Income" then
            valueRed = vsModeStats[indexRed].metalIncome
            valueBlue = vsModeStats[indexBlue].metalIncome
        elseif vsModeMetric.metric == "Energy Income" then
            valueRed = vsModeStats[indexRed].energyIncome
            valueBlue = vsModeStats[indexBlue].energyIncome
        elseif vsModeMetric.metric == "Build Power" then
            valueRed = vsModeStats[indexRed].buildPower
            valueBlue = vsModeStats[indexBlue].buildPower
        elseif vsModeMetric.metric == "Metal Produced" then
            valueRed = vsModeStats[indexRed].metalProduced
            valueBlue = vsModeStats[indexBlue].metalProduced
        elseif vsModeMetric.metric == "Energy Produced" then
            valueRed = vsModeStats[indexRed].energyProduced
            valueBlue = vsModeStats[indexBlue].energyProduced
        elseif vsModeMetric.metric == "Army Value" then
            valueRed = vsModeStats[indexRed].armyValue
            valueBlue = vsModeStats[indexBlue].armyValue
        elseif vsModeMetric.metric == "Damage Dealt" then
            valueRed = vsModeStats[indexRed].damageDone
            valueBlue = vsModeStats[indexBlue].damageDone
        end

        drawVSBar(
            valueRed,
            valueBlue,
            iconRight + borderPadding + vsModeMetricIconPadding * 2,
            iconBottom,
            vsModeMetricsAreaRight - borderPadding - vsModeMetricIconPadding * 2,
            iconTop)
    end
end

local function drawMetricChange()
    WG.FlowUI.Draw.Selector(
        headerLeft,
        metricChangeBottom,
        headerRight,
        headerBottom
    )

    -- TODO: this is not working, find out why
    local mouseX, mouseY = Spring.GetMouseState()
    if (mouseX > headerLeft) and (mouseX < headerRight) and (mouseY > headerBottom) and (mouseY < metricChangeBottom) then
        local mouseHovered = math.floor((mouseY - metricChangeBottom) / headerHeight)
        local highlightBottom = metricChangeBottom + mouseHovered * headerHeight
        local highlightTop = highlightBottom + headerHeight
        WG.FlowUI.Draw.SelectHighlight(
            headerLeft,
            highlightBottom,
            headerRight,
            highlighTop
        )
    end

    font:Begin()
        local distanceFromTop = 0
        local amountOfMetrics = getAmountOfMetrics()
        for _, currentMetric in ipairs(metricsAvailable) do
            local textLeft = headerLeft + borderPadding + headerLabelPadding
            local textBottom = metricChangeBottom + borderPadding + headerLabelPadding +
                (amountOfMetrics - distanceFromTop - 1) * headerHeight
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

    calculateWidgetSize()
    setWidgetPosition()

    createBackgroundShader()
    updateHeaderTooltip()
    createSorting()
    updateSortingTooltip()
    createToggleVSMode()
    updateToggleVSModeTooltip()
    deleteButtonWidgetSizeIncrease()
    updateButtonWidgetSizeIncreaseTooltip()
    deleteButtonWidgetSizeDecrease()
    updateButtonWidgetSizeDecreaseTooltip()
    createStatsArea()
    createVSModeBackgroudDisplayLists()

    vsModeEnabled = getAmountOfAllyTeams() == 2

    updateStats()
end

local function deInit()
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

    init()
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
    if (x > headerLeft) and (x < headerRight) and (y > headerBottom) and (y < headerTop) and not metricChangeInProgress then
        metricChangeInProgress = true
        return
    end

    if metricChangeInProgress then
        if (x > headerLeft) and (x < headerRight) and (y > metricChangeBottom) and (y < headerTop) then
            -- no change if user pressed header
            if (y < headerBottom) then
                local metricPressed = getAmountOfMetrics() - math.floor((y - metricChangeBottom) / headerHeight)
                setMetricChosen(metricPressed)
                if vsMode then
                    vsMode = false
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

    if haveFullView then
        if WG['topbar'] then
            local topBarShowButtonsOld = topBarShowButtons
            topBarShowButtons = WG['topbar'].getShowButtons()
            if topBarShowButtons ~= topBarShowButtonsOld then
                reInit()
                return
            end
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
