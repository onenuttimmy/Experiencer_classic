------------------------------------------------------------
-- Experiencer by Sonaza (https://sonaza.com)
-- Licensed under MIT License
-- See attached license text in file LICENSE
-- Optimized for WoW Classic (Era/SoD)
------------------------------------------------------------

local ADDON_NAME, Addon = ...;
local _;

-- SAFE REGISTRATION
local module = Addon:GetModule("reputation", true)
if not module then
    module = Addon:RegisterModule("reputation", {
        label       = "Reputation",
        order       = 2,
        savedvars   = {
            global = {
                ShowRemaining = true,
                ShowGainedRep = true,
                
                AutoWatch = {
                    Enabled = false,
                    IgnoreInactive = true,
                },
            },
        },
    });
end

module.tooltipText = "You can quickly scroll through recently gained reputations by scrolling the mouse wheel while holding down shift key."

module.recentReputations = {};
module.hasCustomMouseCallback = true;

------------------------------------------------------------
-- 1. HELPER FUNCTIONS 
------------------------------------------------------------

-- CLASSIC HELPER: Find ID by name because Classic GetWatchedFactionInfo often lacks returns
function module:GetReputationID(faction_name)
    local numFactions = GetNumFactions();
    local index = 1;
    while index <= numFactions do
        local name, _, _, _, _, _, _, _, isHeader, isCollapsed, _, _, _, factionID = GetFactionInfo(index);
        
        if(isHeader and isCollapsed) then
            ExpandFactionHeader(index);
            numFactions = GetNumFactions();
        end
        
        if(name == faction_name) then
            return index, factionID;
        end
            
        index = index + 1;
    end
    
    return nil
end

function module:GetStandingColorText(standing)
    local colors = {
        [1] = {r=0.80, g=0.13, b=0.13}, -- hated
        [2] = {r=1.00, g=0.25, b=0.00}, -- hostile
        [3] = {r=0.93, g=0.40, b=0.13}, -- unfriendly
        [4] = {r=1.00, g=1.00, b=0.00}, -- neutral
        [5] = {r=0.00, g=0.70, b=0.00}, -- friendly
        [6] = {r=0.00, g=1.00, b=0.00}, -- honored
        [7] = {r=0.00, g=0.60, b=1.00}, -- revered
        [8] = {r=0.00, g=1.00, b=1.00}, -- exalted
    }
    
    local label = GetText("FACTION_STANDING_LABEL" .. standing, UnitSex("player"));
    if not label then label = "Rank " .. standing end -- Fallback
    
    if not colors[standing] then standing = 4 end -- Safety Fallback to Neutral color

    return string.format('|cff%02x%02x%02x%s|r',
        colors[standing].r * 255,
        colors[standing].g * 255,
        colors[standing].b * 255,
        label
    );
end

------------------------------------------------------------
-- 2. EVENT HANDLERS
------------------------------------------------------------

function module:UPDATE_FACTION(event, ...)
    local name = GetWatchedFactionInfo();
    
    -- We removed levelUpRequiresAction (Paragon) logic here as it doesn't exist in Classic
    
    local instant = false;
    if(name ~= module.Tracked or not name) then
        instant = true;
        module.AutoWatchUpdate = 0;
    end
    module.Tracked = name;
    
    module:Refresh(instant);
end

local reputationPattern = FACTION_STANDING_INCREASED:gsub("%%s", "(.-)"):gsub("%%d", "(%%d*)%%");

function module:CHAT_MSG_COMBAT_FACTION_CHANGE(event, message, ...)
    if not message then return end
    local reputation, amount = message:match(reputationPattern);
    amount = tonumber(amount) or 0;
    
    if(not reputation) then return end
    
    if not module.recentReputations then module.recentReputations = {} end
    
    if(not module.recentReputations[reputation]) then
        module.recentReputations[reputation] = {
            amount = 0,
        };
    end
    
    module.recentReputations[reputation].amount = module.recentReputations[reputation].amount + amount;
    
    if(self.db.global.AutoWatch.Enabled and module.AutoWatchUpdate ~= 2) then
        local factionListIndex, factionID = module:GetReputationID(reputation);
        if(not factionListIndex) then return end
        
        if(self.db.global.AutoWatch.IgnoreInactive and IsFactionInactive(factionListIndex)) then return end
        
        module.AutoWatchUpdate = 1;
        module.AutoWatchRecentTimeout = 0.1;
        
        if(not module.AutoWatchRecent[reputation]) then
            module.AutoWatchRecent[reputation] = 0;
        end
        module.AutoWatchRecent[reputation] = module.AutoWatchRecent[reputation] + amount;
    end
end

------------------------------------------------------------
-- 3. INITIALIZATION
------------------------------------------------------------

function module:Initialize()
    module:RegisterEvent("UPDATE_FACTION");
    module:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE");
    
    local name = GetWatchedFactionInfo();
    module.Tracked = name;
    
    if(name) then
        module.recentReputations[name] = {
            amount = 0;
        };
    end
    
    module.AutoWatchRecent = {};
    module.AutoWatchUpdate = 0;
    module.AutoWatchRecentTimeout = 0;
end

------------------------------------------------------------
-- 4. REMAINING MODULE LOGIC
------------------------------------------------------------

function module:IsDisabled()
    return false;
end

function module:GetSortedRecentList()
    local sortedList = {};
    for name, data in pairs(module.recentReputations) do
        tinsert(sortedList, {name = name, data = data});
    end
    table.sort(sortedList, function(a, b)
        if(a == nil and b == nil) then return false end
        if(a == nil) then return true end
        if(b == nil) then return false end
        
        return a.name < b.name;
    end);
    for index, data in ipairs(sortedList) do
        module.recentReputations[data.name].sortedIndex = index;
    end
    return sortedList;
end

function module:OnMouseWheel(delta)
    if(IsShiftKeyDown()) then
        local recentRepsList = module:GetSortedRecentList();
        if(not recentRepsList or #recentRepsList == 0) then return end
        
        local currentIndex = nil;
        local name = GetWatchedFactionInfo();
        if(name) then
            currentIndex = module.recentReputations[name] and module.recentReputations[name].sortedIndex or 1;
        else
            currentIndex = 1;
        end
        
        currentIndex = currentIndex - delta;
        if(currentIndex > #recentRepsList) then currentIndex = 1 end
        if(currentIndex < 1) then currentIndex = #recentRepsList end
        
        if(recentRepsList[currentIndex]) then
            local factionIndex = module:GetReputationID(recentRepsList[currentIndex].name);
            if factionIndex then
                SetWatchedFactionIndex(factionIndex);
            end
        end
    end
end

-- Removed CanLevelUp() as Paragon rewards don't exist in Classic

function module:GetText()
    if(not module:HasWatchedReputation()) then
        return "No active watched reputation";
    end
    
    local primaryText = {};
    local secondaryText = {};
    
    local name, standing, minReputation, maxReputation, currentReputation, factionID = GetWatchedFactionInfo();
    
    -- Fallback for name/ID in Classic
    if (not factionID and name) then
        _, factionID = module:GetReputationID(name);
    end

    local standingText = module:GetStandingColorText(standing);
    local isCapped = (standing == MAX_REPUTATION_REACTION); -- Exalted
    
    if(not isCapped) then
        local remainingReputation = maxReputation - currentReputation;
        local realCurrentReputation = currentReputation - minReputation;
        local realMaxReputation = maxReputation - minReputation;
        
        local progress = 0;
        if (realMaxReputation > 0) then
            progress = realCurrentReputation / realMaxReputation;
        end
        
        local color = Addon:GetProgressColor(progress);
        
        if(self.db.global.ShowRemaining) then
            tinsert(primaryText,
                string.format("%s (%s): %s%s|r (%s%.1f|r%%)", name, standingText, color, BreakUpLargeNumbers(remainingReputation), color, 100 - progress * 100)
            );
        else
            tinsert(primaryText,
                string.format("%s (%s): %s%s|r / %s (%s%.1f|r%%)", name, standingText, color, BreakUpLargeNumbers(realCurrentReputation), BreakUpLargeNumbers(realMaxReputation), color, progress * 100)
            );
        end
    else
        -- Exalted / Capped
        tinsert(primaryText,
            string.format("%s (%s)", name, standingText)
        );
    end
    
    if(self.db.global.ShowGainedRep and module.recentReputations[name]) then
        if(module.recentReputations[name].amount > 0) then
            tinsert(secondaryText, string.format("+%s |cffffcc00rep|r", BreakUpLargeNumbers(module.recentReputations[name].amount)));
        end
    end
    
    return table.concat(primaryText, "  "), table.concat(secondaryText, "  ");
end

function module:HasChatMessage()
    return GetWatchedFactionInfo() ~= nil, "No watched reputation.";
end

function module:GetChatMessage()
    local name, standing, minReputation, maxReputation, currentReputation, factionID = GetWatchedFactionInfo();
    
    if (not factionID and name) then _, factionID = module:GetReputationID(name) end

    -- Classic Fix: Fallback for standing label
    local label = GetText("FACTION_STANDING_LABEL" .. standing, UnitSex("player")); 
    if not label then label = "Standing " .. standing end
    local standingText = label;

    local isCapped = (standing == MAX_REPUTATION_REACTION);
    
    if(not isCapped) then
        local remaining_rep = maxReputation - currentReputation;
        local progress = 0
        if (maxReputation - minReputation > 0) then
            progress = (currentReputation - minReputation) / (maxReputation - minReputation);
        end
        
        return string.format("%s with %s: %s/%s (%d%%) with %s to go",
            standingText,
            name,
            BreakUpLargeNumbers(currentReputation - minReputation),
            BreakUpLargeNumbers(maxReputation - minReputation),
            progress * 100,
            BreakUpLargeNumbers(remaining_rep)
        );
    else
        return string.format("%s with %s",
            standingText,
            name
        );
    end
end

function module:GetBarData()
    local data    = {};
    data.id       = nil;
    data.level    = 0;
    data.min      = 0;
    data.max      = 1;
    data.current  = 0;
    data.rested   = nil;
    data.visual   = nil;
    
    if(module:HasWatchedReputation()) then
        local name, standing, minReputation, maxReputation, currentReputation, factionID = GetWatchedFactionInfo();
        
        if (not factionID and name) then _, factionID = module:GetReputationID(name) end
        
        data.id = factionID;
        data.level = standing;
        
        local isCapped = (standing == MAX_REPUTATION_REACTION);
        
        if(not isCapped) then
            data.min     = minReputation;
            data.max     = maxReputation;
            data.current = currentReputation;
        else
            data.min     = 0;
            data.max     = 1;
            data.current = 1;
        end
    end
    
    return data;
end

function module:GetOptionsMenu()
    local menudata = {
        {
            text = "Reputation Options",
            isTitle = true,
            notCheckable = true,
        },
        {
            text = "Show remaining reputation",
            func = function() self.db.global.ShowRemaining = true; module:RefreshText(); end,
            checked = function() return self.db.global.ShowRemaining == true; end,
        },
        {
            text = "Show current and max reputation",
            func = function() self.db.global.ShowRemaining = false; module:RefreshText(); end,
            checked = function() return self.db.global.ShowRemaining == false; end,
        },
        {
            text = " ", isTitle = true, notCheckable = true,
        },
        {
            text = "Show gained reputation",
            func = function() self.db.global.ShowGainedRep = not self.db.global.ShowGainedRep; module:Refresh(); end,
            checked = function() return self.db.global.ShowGainedRep; end,
            isNotRadio = true,
        },
        {
            text = "Auto watch most recent reputation",
            func = function() self.db.global.AutoWatch.Enabled = not self.db.global.AutoWatch.Enabled; end,
            checked = function() return self.db.global.AutoWatch.Enabled; end,
            hasArrow = true,
            isNotRadio = true,
            menuList = {
                {
                    text = "Ignore inactive reputations",
                    func = function() self.db.global.AutoWatch.IgnoreInactive = not self.db.global.AutoWatch.IgnoreInactive; end,
                    checked = function() return self.db.global.AutoWatch.IgnoreInactive; end,
                    isNotRadio = true,
                },
            },
        },
        {
            text = " ", isTitle = true, notCheckable = true,
        },
        {
            text = "Set Watched Faction",
            isTitle = true,
            notCheckable = true,
        },
    };
    
    local reputationsMenu = module:GetReputationsMenu();
    for _, data in ipairs(reputationsMenu) do
        tinsert(menudata, data);
    end
    
    tinsert(menudata, { text = "", isTitle = true, notCheckable = true, });
    tinsert(menudata, {
        text = "Open reputations panel",
        func = function() ToggleCharacter("ReputationFrame"); end,
        notCheckable = true,
    });
    
    return menudata;
end

function module:MenuSetWatchedFactionIndex(factionIndex)
    SetWatchedFactionIndex(factionIndex);
    CloseMenus();
end

function module:GetRecentReputationsMenu()
    local factions = {
        {
            text = " ", isTitle = true, notCheckable = true,
        },
        {
            text = "Recent Reputations", isTitle = true, notCheckable = true,
        },
    };
    
    local recentRepsList = module:GetSortedRecentList();
    for _, rep in ipairs(recentRepsList) do
        local name = rep.name;
        local data = rep.data;
        
        local factionIndex, factionID = module:GetReputationID(name);
        
        if factionIndex then 
            local _, _, standing, _, _, _, _, _, isHeader, isCollapsed, hasRep, isWatched, isChild = GetFactionInfo(factionIndex);
            local standing_text = module:GetStandingColorText(standing);
            
            tinsert(factions, {
                text = string.format("%s (%s)  +%s rep this session", name, standing_text, BreakUpLargeNumbers(data.amount)),
                func = function()
                    module:MenuSetWatchedFactionIndex(factionIndex);
                end,
                checked = function() return isWatched end,
            })
        end
    end
    
    if(#recentRepsList == 0) then
        return false;
    end
    
    return factions;
end

function module:GetReputationProgressByFactionID(factionID)
    if(not factionID) then return nil end
    
    if not GetFactionInfoByID then return nil end

    local name, _, standing, minReputation, maxReputation, currentReputation = GetFactionInfoByID(factionID);
    if(not name or not minReputation or not maxReputation) then return nil end
    
    local isCapped = (standing == MAX_REPUTATION_REACTION);
    
    return currentReputation - minReputation, maxReputation - minReputation, isCapped;
end

function module:GetReputationsMenu()
    local factions = {};
    
    local previous, current = nil, nil;
    local depth = 0;
    
    local factionIndex = 1;
    local numFactions = GetNumFactions();
    while factionIndex <= numFactions do
        local name, _, standing, _, _, _, _, _, isHeader, isCollapsed, hasRep, isWatched, isChild, factionID = GetFactionInfo(factionIndex);
        if(name) then
            local progressText = "";
            if(factionID) then
                local currentRep, nextThreshold, isCapped = module:GetReputationProgressByFactionID(factionID);
                
                if(currentRep and not isCapped) then
                    progressText = string.format("  (|cfffff2ab%s|r / %s)", BreakUpLargeNumbers(currentRep), BreakUpLargeNumbers(nextThreshold));
                end
            end
                
            local standingText = module:GetStandingColorText(standing);
            
            if(isHeader and isCollapsed) then
                ExpandFactionHeader(factionIndex);
                numFactions = GetNumFactions();
            end
            
            if(isHeader and isChild and current) then -- Second tier header
                if(depth == 2) then
                    current = previous;
                    previous = nil;
                end
                
                if(not hasRep) then
                    tinsert(current, {
                        text = name,
                        hasArrow = true,
                        notCheckable = true,
                        menuList = {},
                    })
                else
                    local index = factionIndex;
                    tinsert(current, {
                        text = string.format("%s (%s)%s", name, standingText, progressText),
                        hasArrow = true,
                        func = function()
                            module:MenuSetWatchedFactionIndex(index);
                        end,
                        checked = function() return isWatched; end,
                        menuList = {},
                    })
                end
                
                previous = current;
                current = current[#current].menuList;
                tinsert(current, {
                    text = name,
                    isTitle = true,
                    notCheckable = true,
                })
                
                depth = 2
                
            elseif(isHeader) then -- First tier header
                tinsert(factions, {
                    text = name,
                    hasArrow = true,
                    notCheckable = true,
                    menuList = {},
                })
                
                current = factions[#factions].menuList;
                tinsert(current, {
                    text = name,
                    isTitle = true,
                    notCheckable = true,
                })
                
                depth = 1
            elseif(not isHeader) then -- First and second tier faction
                local index = factionIndex;
                tinsert(current, {
                    text = string.format("%s (%s)%s", name, standingText, progressText),
                    func = function()
                        module:MenuSetWatchedFactionIndex(factionIndex);
                    end,
                    checked = function() return isWatched end,
                })
            end
        end
        
        factionIndex = factionIndex + 1;
    end
    
    local recent = module:GetRecentReputationsMenu();
    if(recent ~= false) then
        for _, data in ipairs(recent) do tinsert(factions, data) end
    end
    
    return factions;
end

function module:HasWatchedReputation()
    return GetWatchedFactionInfo() ~= nil;
end

function module:AllowedToBufferUpdate()
    return module.AutoWatchUpdate == 0;
end

function module:Update(elapsed)
    if (module.AutoWatchUpdate == 1) then
        if (module.AutoWatchRecentTimeout > 0.0) then
            module.AutoWatchRecentTimeout = module.AutoWatchRecentTimeout - elapsed;
        end
        
        if (module.AutoWatchRecentTimeout <= 0.0) then
            local selectedFaction = nil;
            local largestGain = 0;
            for faction, gain in pairs(module.AutoWatchRecent) do
                if (gain > largestGain) then
                    selectedFaction = faction;
                    largestGain = gain;
                end
            end
            
            local name = GetWatchedFactionInfo();
            if (selectedFaction and selectedFaction ~= name) then
                local factionListIndex, factionID = module:GetReputationID(selectedFaction);
                if(factionListIndex) then
                    SetWatchedFactionIndex(factionListIndex);
                end
                module.AutoWatchUpdate = 2;
            else
                module.AutoWatchUpdate = 0;
            end
            
            module.AutoWatchRecentTimeout = 0;
            wipe(module.AutoWatchRecent);
        end
    end
end