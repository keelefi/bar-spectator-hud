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
   |  Select View                   |  Sorting  |
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
* P1-P6 are unique player identifiers called player decals (currently just a color box)
* Bar1-Bar6 are value bars showing linear relationship between the values
* Every bar has a text on top showing approximate value as textual represenation
]]

--local inSpecMode = false
--local isReplay = Spring.IsReplay()
local haveFullView = false

local ui_scale = tonumber(Spring.GetConfigFloat("ui_scale", 1) or 1)

local topBarPosition
local topBarShowButtons

local viewScreenWidth, viewScreenHeight
local widgetWidth, widgetHeight
local widgetTop, widgetBottom, widgetLeft, widgetRight

local headerWidth, headerHeight
local sortingWidth, sortingHeight

local statsBarWidth, statsBarHeight
local statsAreaWidth, statsAreaHeight

local headerTop, headerBottom, headerLeft, headerRight
local metricChangeBottom
local sortingTop, sortingBottom, sortingLeft, sortingRight
local statsAreaTop, statsAreaBottom, statsAreaLeft, statsAreaRight

local backgroundShader

local headerLabel = "Metal Income"

local sortingBackgroundDisplayList

local statsAreaBackgroundDisplayList

local font
local fontSize
local fontSizeDefault = 64
local fontSizeMetric

local distanceFromTopBar
local distanceFromTopBarDefault = 10

local borderPadding
local borderPaddingDefault = 5
local headerLabelPadding
local headerLabelPaddingDefault = 10
local sortingIconPadding
local sortingIconPaddingDefault = 8
local teamDecalPadding
local teamDecalPaddingDefault = 6
local teamDecalHeight
local teamDecalCornerSize
local teamDecalCornerSizeDefault = 4

local barChunkSize
--local barChunkSizeSource = 40      -- from source image

local sortingTooltipName = "spectator_hud_sorting"
local sortingTooltipTitle = "Sorting"
local sortingPlayerTooltipText = "Sort by Player (click to change)"
local sortingTeamTooltipText = "Sort by Team (click to change)"

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

local metricChosenID = 1
local metricChangeInProgress = false
local sortingChosen = "player"
local teamStats = {}

local images = {
    sortingPlayer = "LuaUI/Images/spectator_hud/sorting-player.png",
    sortingTeam = "LuaUI/Images/spectator_hud/sorting-team.png",
    barOutlineStart = "LuaUI/Images/spectator_hud/bar-outline-start.png",
    barOutlineMiddle = "LuaUI/Images/spectator_hud/bar-outline-middle.png",
    barOutlineEnd = "LuaUI/Images/spectator_hud/bar-outline-end.png",
    barProgressStart = "LuaUI/Images/spectator_hud/bar-progress-start.png",
    barProgressMiddle = "LuaUI/Images/spectator_hud/bar-progress-middle.png",
    barProgressEnd = "LuaUI/Images/spectator_hud/bar-progress-end.png",
}

local function round(num, idp)
    local mult = 10 ^ (idp or 0)
    return floor(num * mult + 0.5) / mult
end

local function formatRes(number)
    if number < 1000 then
        return string.format("%d", number)
    else
        return string.format("%.1fk", number / 1000)
    end
end

local function isArmyUnit(unitDefID)
    if UnitDefs[unitDefID].weapons and (#UnitDefs[unitDefID].weapons > 0) then
        return true
    else
        return false
    end
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

local function getMetricChosen()
    for _, currentMetric in pairs(metricsAvailable) do
        if metricChosenID == currentMetric.id then
            return currentMetric
        end
    end
end

local function getAmountOfMetrics()
    return #metricsAvailable
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
                --Spring.Echo(string.format("metalIncome: %d", metalIncome))
                --[[
                Spring.Echo(string.format("color: {%d, %d, %d, %d}",
                    teamColorRed, teamColorGreen, teamColorBlue, teamColorAlpha))
                ]]
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
                local metalProduced = statsHistory[1].metalProduced
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
                local damageDealt = statsHistory[1].damageDealt
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
                local damageReceived = statsHistory[1].damageReceived
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
                local damageDealt = statsHistory[1].damageDealt
                local damageReceived = statsHistory[1].damageReceived
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

local function updateStats()
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

    --[[
    Spring.Echo(string.format("debug updateStats():"))
    for allyID, ally in pairs(teamStats) do
        Spring.Echo(string.format("  allyID: %d", allyID))
        for teamID, team in pairs(ally) do
            Spring.Echo(string.format("    teamID: %d", teamID))
            Spring.Echo(string.format("      value: %d", team.value))
            Spring.Echo(string.format("      color: %d, %d, %d, %d",
                team.colorRed, team.colorGreen, team.colorBlue, team.colorAlpha))
        end
    end
    ]]
end

local function calculateHeaderSize()
    local headerTextHeight = font:GetTextHeight(headerLabel) * fontSize
    headerHeight = math.floor(2 * borderPadding + headerTextHeight)

    -- note: sorting is a square. therefore, we remove from header width same as the height.
    headerWidth = widgetWidth - headerHeight
end

local function calculateSortingSize()
    sortingHeight = headerHeight   -- same height as header
    sortingWidth = sortingHeight   -- sorting is a square box
end

local function calculateStatsBarSize()
    statsBarHeight = math.floor(headerHeight * 0.80)
    statsBarWidth = widgetWidth
end

local function setSortingPosition()
    sortingTop = widgetTop
    sortingBottom = widgetTop - sortingHeight
    sortingLeft = widgetRight - sortingWidth
    sortingRight = widgetRight
end

local function setHeaderPosition()
    headerTop = widgetTop
    headerBottom = widgetTop - headerHeight
    headerLeft = widgetLeft
    headerRight = widgetRight - sortingWidth

    metricChangeBottom = headerBottom - headerHeight * getAmountOfMetrics()
end

local function setStatsAreaPosition()
    statsAreaTop = widgetTop - headerHeight
    statsAreaBottom = widgetBottom
    statsAreaLeft = widgetLeft
    statsAreaRight = widgetRight
end

local function calculateWidgetSize()
    Spring.Echo(string.format("ui_scale: %f", ui_scale))

    distanceFromTopBar = math.floor(distanceFromTopBarDefault * ui_scale)
    borderPadding = math.floor(borderPaddingDefault * ui_scale)
    headerLabelPadding = math.floor(headerLabelPaddingDefault * ui_scale)
    sortingIconPadding = math.floor(sortingIconPaddingDefault * ui_scale)
    teamDecalPadding = math.floor(teamDecalPaddingDefault * ui_scale)
    teamDecalCornerSize = math.floor(teamDecalCornerSizeDefault * ui_scale)
    fontSize = math.floor(fontSizeDefault * ui_scale)
    fontSizeMetric = math.floor(fontSize / 2)

    Spring.Echo(string.format("fontSize: %d", fontSize))

    widgetWidth = math.floor(viewScreenWidth * 0.20 * ui_scale)

    calculateHeaderSize()
    calculateSortingSize()
    calculateStatsBarSize()
    statsAreaWidth = widgetWidth
    statsAreaHeight = statsBarHeight * getAmountOfTeams()
    teamDecalHeight = statsBarHeight - borderPadding * 2 - teamDecalPadding * 2
    barChunkSize = math.floor(teamDecalHeight / 2)

    widgetHeight = headerHeight + statsAreaHeight
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
    setStatsAreaPosition()

    Spring.Echo(string.format("widget rect: [%d, %d, %d, %d]", widgetLeft, widgetBottom, widgetRight, widgetTop))
    Spring.Echo(string.format("header rect: [%d, %d, %d, %d]", headerLeft, headerBottom, headerRight, headerTop))
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

local function drawSorting()
    gl.Color(1, 1, 1, 1)
    if sortingChosen == "player" then
        gl.Texture(images["sortingPlayer"])
    elseif sortingChosen == "team" then
        gl.Texture(images["sortingTeam"])
    end
    gl.TexRect(
        sortingLeft + sortingIconPadding,
        sortingBottom + sortingIconPadding,
        sortingRight - sortingIconPadding,
        sortingTop - sortingIconPadding
    )
    gl.Texture(false)
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
    drawABar(
        barLeft,
        barBottom,
        barRight,
        barTop,
        amount,
        max
    )

    local amountText = string.format("%d", amount)
    local amountMiddle = teamDecalRight + math.floor((statsAreaRight - teamDecalRight) / 2)
    local amountBottom = teamDecalBottom
    font:Begin()
        font:Print(
            amountText,
            amountMiddle,
            amountBottom,
            fontSizeMetric,
            'co'
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

local function deleteStatsArea()
    gl.DeleteList(statsAreaBackgroundDisplayList)
end

local function init()
    viewScreenWidth, viewScreenHeight = Spring.GetViewGeometry()

    calculateWidgetSize()
    setWidgetPosition()

    createBackgroundShader()
    updateHeaderTooltip()
    createSorting()
    updateSortingTooltip()
    createStatsArea()

    updateStats()
end

local function deInit()
    deleteBackgroundShader()
    deleteHeaderTooltip()
    deleteSorting()
    deleteSortingTooltip()
    deleteStatsArea()
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

function widget:MousePress(x, y, button)
    if (x > headerLeft) and (x < headerRight) and (y > headerBottom) and (y < headerTop) and not metricChangeInProgress then
        metricChangeInProgress = true
        return
    end

    if (x > headerLeft) and (x < headerRight) and (y > metricChangeBottom) and (y < headerTop) and metricChangeInProgress then
        -- no change if user pressed header
        if (y < headerBottom) then
            local metricPressed = getAmountOfMetrics() - math.floor((y - metricChangeBottom) / headerHeight)
            metricChosenID = metricPressed
            local metricChosen = getMetricChosen()
            headerLabel = metricChosen.title
            updateStats()
        end

        metricChangeInProgress = false
        return
    end

    if (x > sortingLeft) and (x < sortingRight) and (y > sortingBottom) and (y < sortingTop) then
        if sortingChosen == "player" then
            sortingChosen = "team"
        elseif sortingChosen == "team" then
            sortingChosen = "player"
        end
        updateSortingTooltip()
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

        gl.CallList(statsAreaBackgroundDisplayList)
        drawStatsBars()

        if metricChangeInProgress then
            drawMetricChange()
        end
    gl.PopMatrix()
end
