-- SmartMount for WoW 3.3.5a (Wrath of the Lich King)
-- Picks a random mount from the fastest tier that suits your situation:
--   swimming         -> water mount (Sea Turtle / Riding Turtle) if you own one
--   flyable area     -> fastest flying mount
--   otherwise        -> fastest ground mount
-- Triggered by a button on the Companions tab, by /smartmount, or by an
-- auto-created macro named "SmartMount".

local MACRO_NAME = "SmartMount"
local MACRO_BODY = "/smartmount"
-- 3.3.5a macro icons must be Blizzard built-ins (a custom .tga/.blp can't be used),
-- so use a blue built-in that matches the button art. First substring match wins.
local MACRO_ICON_PREFS = { "ability_mount_charger", "drake_blue", "blueproto", "netherdrake", "seaturtle", "ability_mount_ridinghorse" }
local MACRO_ICON_OLD = "ability_mount_ridinghorse"

-- Folder-proof icon path: ... is the addon folder name ("SmartMount").
-- Survives renames like "SmartMount_7_". Falls back to "SmartMount".
local _addonName = ...
if type(_addonName) ~= "string" or _addonName == "" then _addonName = "SmartMount" end
local FALLBACK_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"
local ICON_CANDIDATES = {
    "Interface\\AddOns\\" .. _addonName .. "\\icon.tga",
    "Interface\\AddOns\\" .. _addonName .. "\\icon.blp",
    "Interface\\AddOns\\" .. _addonName .. "\\icon",
    "Interface\\AddOns\\SmartMount\\icon.tga",
    "Interface\\AddOns\\SmartMount\\icon.blp",
}
local ICON_USED = nil

-- Tries each candidate path; returns the first one the client actually loads.
-- (On 3.3.5a a missing file leaves GetNormalTexture() as nil, so we can probe.)
local function ApplyIcon(b)
    for _, path in ipairs(ICON_CANDIDATES) do
        b:SetNormalTexture(path)
        if b:GetNormalTexture() then
            b:SetPushedTexture(path)
            local pushed = b:GetPushedTexture()
            if pushed then pushed:SetVertexColor(0.7, 0.7, 0.7) end
            ICON_USED = path
            return true
        end
    end
    b:SetNormalTexture(FALLBACK_ICON)
    b:SetPushedTexture(FALLBACK_ICON)
    local fb = b:GetPushedTexture()
    if fb then fb:SetVertexColor(0.7, 0.7, 0.7) end
    ICON_USED = FALLBACK_ICON .. " (fallback)"
    return false
end

SmartMountDB = SmartMountDB or {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SmartMount:|r " .. tostring(msg))
end

------------------------------------------------------------------------
-- Mount classification
------------------------------------------------------------------------
-- Water mounts (spell IDs)
local WATER = { [30174] = true, [64731] = true }

-- Known flying mounts and their speed (best effort; anything missing here is
-- classified from its spell tooltip, or can be fixed with /smartmount set).
local FLYING = {}
local function AddFlying(speed, ...)
    for i = 1, select("#", ...) do
        FLYING[(select(i, ...))] = speed
    end
end
AddFlying(280,
    37015, 44744, 49193, 58615, 64927, 65439, 67336, 71810,   -- Nether/Drakes (arena)
    41513, 41514, 41515, 41516, 41517, 41518,                 -- Netherwing Drakes
    40192,                                                    -- Ashes of Al'ar
    59568, 59569, 59570, 59571, 59650, 59961, 59996, 60002,   -- Drakes / Proto-Drakes
    60021, 60024, 60025, 61294, 63796, 63956, 63963,
    61996, 61997, 44151, 63844, 69395)
AddFlying(310, 72286, 72807, 72808)

-- Hidden tooltip used to read spell descriptions
local scanTip = CreateFrame("GameTooltip", "SmartMountScanTip", UIParent, "GameTooltipTemplate")

local function ReadSpellText(spellID)
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetHyperlink("spell:" .. spellID)
    local text = ""
    for i = 1, scanTip:NumLines() do
        local line = _G["SmartMountScanTipTextLeft" .. i]
        local t = line and line:GetText()
        if t then text = text .. " " .. t end
    end
    return text
end

local cache = {}

-- returns kind ("fly"|"ground"|"water"|"ignore"), speed
local function Classify(spellID)
    if cache[spellID] then return cache[spellID].kind, cache[spellID].speed end

    local kind, speed
    local o = SmartMountDB.overrides and SmartMountDB.overrides[spellID]
    if o then
        kind, speed = o.kind, o.speed or 0
    elseif WATER[spellID] then
        kind, speed = "water", 0
    elseif FLYING[spellID] then
        kind, speed = "fly", FLYING[spellID]
    else
        -- Heuristic from tooltip text (English client wording)
        local text = ReadSpellText(spellID)
        local lower = text:lower()
        local pct = 0
        for n in text:gmatch("(%d+)%%") do
            n = tonumber(n)
            if n and n > pct and n <= 400 then pct = n end
        end
        local flies = lower:find("fly") or lower:find("flight") or lower:find("flying")
        if flies then
            kind = "fly"
            if pct == 0 then
                if lower:find("extremely fast") then pct = 310
                elseif lower:find("very fast") then pct = 280
                elseif lower:find("fast") then pct = 150 end
            end
        else
            kind = "ground"
            if pct == 0 then
                if lower:find("very fast") or lower:find("extremely fast") then pct = 100
                elseif lower:find("fast") then pct = 60 end
            end
        end
        speed = pct
    end

    cache[spellID] = { kind = kind, speed = speed }
    return kind, speed
end

------------------------------------------------------------------------
-- Mount selection
------------------------------------------------------------------------
local function CollectMounts()
    local pools = { fly = {}, ground = {}, water = {} }
    for i = 1, GetNumCompanions("MOUNT") do
        local _, name, spellID = GetCompanionInfo("MOUNT", i)
        if spellID then
            local kind, speed = Classify(spellID)
            if pools[kind] then
                -- NOTE: IsUsableSpell() can't be used here: companion/mount spells are not in
                -- the spellbook, so it returns false for every mount on 3.3.5a.
                table.insert(pools[kind], { index = i, name = name, speed = speed })
            end
        end
    end
    return pools
end

local function PickRandomFastest(pool)
    if #pool == 0 then return nil end
    local best = -1
    for _, m in ipairs(pool) do
        if m.speed > best then best = m.speed end
    end
    local top = {}
    for _, m in ipairs(pool) do
        if m.speed == best then table.insert(top, m) end
    end
    return top[math.random(#top)]
end

local function CanFlyHere()
    if not IsFlyableArea() then return false end
    if GetZoneText() == "Wintergrasp" then return false end
    return true
end

function SmartMount_Do()
    if IsMounted() then
        Dismount()
        return
    end
    if UnitInVehicle and UnitInVehicle("player") then
        VehicleExit()
        return
    end

    local pools = CollectMounts()
    local choice

    if IsSwimming() then
        choice = PickRandomFastest(pools.water)
    end
    if not choice and CanFlyHere() then
        choice = PickRandomFastest(pools.fly)
    end
    if not choice then
        choice = PickRandomFastest(pools.ground)
    end

    if choice then
        CallCompanion("MOUNT", choice.index)
    else
        Print(string.format("No suitable mount found here (mounts known: %d, flying: %d, ground: %d, water: %d).",
            GetNumCompanions("MOUNT"), #pools.fly, #pools.ground, #pools.water))
    end
end

------------------------------------------------------------------------
-- Companions tab button (locked 22px at 310, -50)
------------------------------------------------------------------------
local function PlaceButton(b)
    b:ClearAllPoints()
    -- Locked default placement: 310px right, 50px down from the Companions
    -- window's top-left corner (override: /smartmount button <x> <y>)
    local x = SmartMountDB.btnX
    local y = SmartMountDB.btnY
    if type(x) ~= "number" or type(y) ~= "number" then x, y = 310, -50 end
    -- Fixed 22px button, top-aligned with the Mounts tab (override: /smartmount button size <n>)
    local size = SmartMountDB.btnSize
    if type(size) ~= "number" or size < 12 or size > 64 then size = 22 end
    b:SetWidth(size)
    b:SetHeight(size)
    b:SetPoint("TOPLEFT", PetPaperDollFrameCompanionFrame, "TOPLEFT", x, y)
end

local function CreateButton()
    if SmartMountButton or not PetPaperDollFrameCompanionFrame then return end
    local b = CreateFrame("Button", "SmartMountButton", PetPaperDollFrameCompanionFrame)
    b:SetWidth(22)
    b:SetHeight(22)
    b:SetFrameLevel(PetPaperDollFrameCompanionFrame:GetFrameLevel() + 5)

    ApplyIcon(b)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    PlaceButton(b)
    b:SetScript("OnShow", function(self) PlaceButton(self) end)
    b:SetScript("OnClick", function()
        -- shift is reserved for dragging the macro to your action bars
        if IsShiftKeyDown() then return end
        SmartMount_Do()
    end)
    -- Shift-drag the button onto an action bar: picks up the SmartMount macro
    -- (bars can't hold addon buttons directly, only spells/macros/items).
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        if not IsShiftKeyDown() then return end
        local idx = GetMacroIndexByName(MACRO_NAME)
        if idx == 0 then
            EnsureMacro(false)
            idx = GetMacroIndexByName(MACRO_NAME)
        end
        if idx > 0 then PickupMacro(idx) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Smart Mount")
        GameTooltip:AddLine("Mounts a random mount from the fastest tier for flying, ground or swimming.", 1, 1, 1, 1)
        GameTooltip:AddLine("Click again while mounted to dismount.", 0.7, 0.7, 0.7, 1)
        GameTooltip:AddLine("Shift-drag onto an action bar to put SmartMount on your bars.", 0.7, 0.7, 0.7, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Macro
------------------------------------------------------------------------
local function ResolveMacroIcon()
    -- 3.3.5a wants a numeric icon index (position in the macro icon list)
    local index, tex = 1, nil
    if GetNumMacroIcons and GetMacroIconInfo then
        -- user-pinned icon first (exact texture path via /smartmount macro pin)
        local pin = SmartMountDB.macroIconPin
        if pin then
            for i = 1, GetNumMacroIcons() do
                local t = GetMacroIconInfo(i)
                if t and tostring(t):lower() == tostring(pin):lower() then
                    return i, tostring(t)
                end
            end
        end
        for _, want in ipairs(MACRO_ICON_PREFS) do
            for i = 1, GetNumMacroIcons() do
                local t = GetMacroIconInfo(i)
                if t and tostring(t):lower():find(want, 1, true) then
                    return i, tostring(t)
                end
            end
        end
    end
    return index, tex
end

local function PinMacroIcon()
    if InCombatLockdown() then return end
    local idx = GetMacroIndexByName(MACRO_NAME)
    if idx == 0 then
        Print("No '" .. MACRO_NAME .. "' macro found. Create it first with /smartmount macro.")
        return
    end
    local curTex = GetMacroInfo and select(2, GetMacroInfo(idx))
    if curTex then
        SmartMountDB.macroIconPin = tostring(curTex)
        Print("Pinned macro icon: " .. tostring(curTex) .. ". New macros will use it.")
    else
        Print("Could not read the macro's icon.")
    end
end

local function EnsureMacro(verbose)
    if InCombatLockdown() then return end
    local iconIndex, iconTex = ResolveMacroIcon()
    local existing = GetMacroIndexByName(MACRO_NAME)
    if existing > 0 then
        -- Migrate the icon we set previously (brown horse -> blue) unless the user
        -- picked their own icon; "/smartmount macro" always forces the blue one.
        if GetMacroInfo then
            local _, curTex = GetMacroInfo(existing)
            curTex = curTex and tostring(curTex):lower() or ""
            local isOurs = curTex:find(MACRO_ICON_OLD, 1, true)
                or (iconTex and curTex == iconTex:lower())
                or (SmartMountDB.macroIconPin and curTex == tostring(SmartMountDB.macroIconPin):lower())
            if (verbose or (isOurs and iconTex and curTex ~= iconTex:lower())) and EditMacro then
                local ok = pcall(EditMacro, existing, MACRO_NAME, iconIndex, MACRO_BODY)
                if ok and verbose then Print("Macro '" .. MACRO_NAME .. "' icon updated.") end
                return
            end
        end
        if verbose then Print("Macro '" .. MACRO_NAME .. "' already exists in your macro window (/macro). Drag it to your action bar.") end
        return
    end
    local numAccount, numChar = GetNumMacros()
    local perChar = 0
    if numAccount >= 36 then perChar = 1 end
    if perChar == 1 and numChar >= 18 then
        Print("Macro slots are full; delete a macro, then type /smartmount macro.")
        return
    end

    -- iconIndex/iconTex were resolved above from MACRO_ICON_PREFS
    local ok, err = pcall(CreateMacro, MACRO_NAME, iconIndex, MACRO_BODY, perChar)
    if not ok then
        -- some clients want a boolean / nil style flag instead
        ok, err = pcall(CreateMacro, MACRO_NAME, iconIndex, MACRO_BODY, perChar == 1 and 1 or nil)
    end
    if ok then
        Print("Created macro '" .. MACRO_NAME .. "'. Open /macro and drag it to your action bar.")
    else
        Print("Could not create the macro automatically. Create one manually in /macro with the text: " .. MACRO_BODY)
    end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_SMARTMOUNT1 = "/smartmount"
SLASH_SMARTMOUNT2 = "/smount"
SlashCmdList["SMARTMOUNT"] = function(msg)
    msg = (msg or ""):lower()
    local cmd, a, b = msg:match("^(%S*)%s*(%S*)%s*(%S*)")

    if cmd == "" then
        SmartMount_Do()

    elseif cmd == "list" then
        wipe(cache)
        for i = 1, GetNumCompanions("MOUNT") do
            local _, name, spellID = GetCompanionInfo("MOUNT", i)
            if spellID then
                local kind, speed = Classify(spellID)
                Print(string.format("%s (spell %d): %s, speed %d%%", name, spellID, kind, speed))
            end
        end

    elseif cmd == "set" then
        -- /smartmount set <spellID> <fly|ground|water|ignore> [speed]
        local id = tonumber(a)
        local kind = b
        local speed = tonumber(msg:match("^%S+%s+%S+%s+%S+%s+(%d+)")) or 0
        if id and (kind == "fly" or kind == "ground" or kind == "water" or kind == "ignore") then
            SmartMountDB.overrides = SmartMountDB.overrides or {}
            SmartMountDB.overrides[id] = { kind = kind, speed = speed }
            wipe(cache)
            Print("Set spell " .. id .. " to " .. kind .. ", speed " .. speed .. "%.")
        else
            Print("Usage: /smartmount set <spellID> <fly|ground|water|ignore> [speed%]")
        end

    elseif cmd == "reset" then
        SmartMountDB.overrides = nil
        wipe(cache)
        Print("All overrides cleared.")

    elseif cmd == "macro" then
        -- /smartmount macro        (re)create, using the pinned icon if you set one
        -- /smartmount macro pin    remember the macro's current icon as the default
        if a == "pin" then
            PinMacroIcon()
        else
            EnsureMacro(true)
        end

    elseif cmd == "button" then
        -- /smartmount button <x> <y>   (offset from the frame's top-left corner, locked default 310 -50)
        -- /smartmount button size <12-64>
        -- /smartmount button reset     (back to locked 22px at 310, -50)
        if SmartMountButton then
            local x, y = tonumber(a), tonumber(b)
            if a == "reset" then
                SmartMountDB.btnX, SmartMountDB.btnY, SmartMountDB.btnSize = nil, nil, nil
                PlaceButton(SmartMountButton)
                Print("Button position and size reset.")
            elseif a == "size" then
                local s = tonumber(b)
                if s and s >= 12 and s <= 64 then
                    SmartMountDB.btnSize = s
                    PlaceButton(SmartMountButton)
                    Print("Button size set to " .. s .. ".")
                else
                    Print("Usage: /smartmount button size <12-64>")
                end
            elseif x and y then
                SmartMountDB.btnX, SmartMountDB.btnY = x, y
                PlaceButton(SmartMountButton)
                Print("Button moved to " .. x .. ", " .. y .. ".")
            else
                Print("Usage: /smartmount button <x> <y>  or  /smartmount button reset")
            end
        end

    elseif cmd == "debug" then
        Print("Addon folder name: " .. tostring(_addonName))
        Print("Icon in use: " .. tostring(ICON_USED or "none yet"))
        if SmartMountButton then
            local ntex = SmartMountButton:GetNormalTexture()
            Print("Button texture object: " .. (ntex and "yes" or "nil (file missing!)"))
            if ntex and ntex.GetTexture then
                Print("Texture path: " .. tostring(ntex:GetTexture()))
            end
        else
            Print("Button not created (open Companions window).")
        end
        -- Probe every candidate on a hidden texture to see which files the client can see.
        local probe = SmartMountDebugProbe
        if not probe then
            probe = CreateFrame("Frame", "SmartMountDebugProbe", UIParent)
            probe:Hide()
            SmartMountDebugProbe = probe
        end
        for _, path in ipairs(ICON_CANDIDATES) do
            local t = probe:CreateTexture(nil, "ARTWORK")
            t:SetTexture(path)
            local got = t:GetTexture()
            Print((got and "FOUND " or "missing ") .. path)
            probe:Hide()
        end
        Print("Expected file: Interface\\AddOns\\" .. tostring(_addonName) .. "\\icon.tga (16,402 bytes)")
        Print("If all say missing: file is not there, or WoW needs a FULL restart (close the game, not /reload).")

    else
        Print("/smartmount - mount or dismount")
        Print("/smartmount list - show how each of your mounts is classified")
        Print("/smartmount set <spellID> <fly|ground|water|ignore> [speed%] - fix a classification")
        Print("/smartmount reset - clear overrides")
        Print("/smartmount macro - (re)create the macro (uses your pinned icon if set)")
        Print("/smartmount macro pin - remember the macro's current icon as the default")
        Print("/smartmount button <x> <y> | size <n> | reset - move/resize the button on the Companions/Mounts window")
        Print("/smartmount debug - show which icon file the button loaded")
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("COMPANION_LEARNED")
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- WoW's client seeds the RNG itself; math.randomseed may not exist on 3.3.5a,
        -- so only call whichever seeding function is actually available.
        local seed = (math and math.randomseed) or randomseed
        if type(seed) == "function" then
            seed(time())
        end
        math.random(); math.random(); math.random()
        CreateButton()
        EnsureMacro(false)
    elseif event == "COMPANION_LEARNED" then
        wipe(cache)
    end
end)
