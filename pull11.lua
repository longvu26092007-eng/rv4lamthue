if not LPH_OBFUSCATED then
    LPH_ENCSTR = LPH_ENCSTR or function(...) return ... end
    LPH_NO_VIRTUALIZE = LPH_NO_VIRTUALIZE or function(...) return ... end
end

getgenv().PullLeverConfig = getgenv().PullLeverConfig or {
    ["Enabled"]            = true,
    ["Team"]               = "Pirates",
    ["Hop Mirage"]         = true,
    ["Boost FPS"]          = true,
    ["FPS"]                = 20,
    ["Black Screen"]       = true,

    ["Use Mirage API"]     = true,
    ["Mirage API"]         = "https://baorph.pythonanywhere.com/token?token=8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8&api_key=baorapi&key=mirage",
    ["Avoid Full Server"]  = true,
    ["Max Players"]        = 11,

    -- Lay 30 server MOI NHAT, join lan luot tung cai, cach nhau 1.5s
    ["Fetch Count"]        = 30,
    ["Hop Delay"]          = 1.5,

}

LPH_NO_VIRTUALIZE(function()

local PlayerGui
local _statusLabel, _raceLabel, _seaLabel, _mirrorLabel, _valkLabel, _doorLabel, _progressLabel, _mirageLabel

local _lastStatus = ""

local function SetStatus(text)
    text = tostring(text or "")
    _lastStatus = text

    print("[PullLever] " .. text)

    if _statusLabel then
        -- Ghi vao CoreGui/gethui co the loi neu thread dang o identity
        -- thap (sau khi require module game) -> khong de no giet script.
        pcall(function() _statusLabel.Text = "Status: " .. text end)
    end
end

local function DebugStatus(tag, err)
    local msg = "[" .. tostring(tag) .. "] " .. tostring(err)
    warn("[PullLever] " .. msg)
    SetStatus(msg)
end

local function MakeUI()
    local ok, parent = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not ok or not parent then return end

    local old = parent:FindFirstChild("PullLeverUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "PullLeverUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 999999
    gui.Parent = parent

    local main = Instance.new("Frame")
    main.Name = "StatusContainer"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.fromScale(0.5, 0.5)
    main.Size = UDim2.new(0.8, 0, 0, 390)
    main.BackgroundTransparency = 1
    main.BorderSizePixel = 0
    main.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 7)
    layout.Parent = main

    local function row(order, size, height, bold)
        local label = Instance.new("TextLabel")
        label.Name = "StatusRow" .. tostring(order)
        label.BackgroundTransparency = 1
        label.BorderSizePixel = 0
        label.Size = UDim2.new(1, 0, 0, height)
        label.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
        label.TextSize = size
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextWrapped = true
        label.LayoutOrder = order
        label.Text = ""
        label.Parent = main
        return label
    end

    _statusLabel = row(1, 34, 52, true)
    _seaLabel = row(2, 25, 34, false)
    _raceLabel = row(3, 25, 34, false)
    _mirrorLabel = row(4, 25, 34, false)
    _valkLabel = row(5, 25, 34, false)
    _mirageLabel = row(6, 25, 34, false)
    _doorLabel = row(7, 25, 34, false)
    _progressLabel = row(8, 25, 34, false)

    _statusLabel.Text = "Status: " .. tostring(_lastStatus ~= "" and _lastStatus or "init")
    _seaLabel.Text = "Sea: ?"
    _raceLabel.Text = "Race V3: ?"
    _mirrorLabel.Text = "Mirror Fractal: ?"
    _valkLabel.Text = "Valkyrie Helm: ?"
    _mirageLabel.Text = "Mirage Island: ?"
    _doorLabel.Text = "Temple Door: ?"
    _progressLabel.Text = "RaceV4 Check: ?"

    _G.__PullLeverUIBuilt = true
end

getgenv().PullLeverConfig = getgenv().PullLeverConfig or {}

local Config = getgenv().PullLeverConfig

Config["Enabled"]           = Config["Enabled"] ~= false
Config["Team"]              = Config["Team"] or "Pirates"
Config["Hop Mirage"]        = Config["Hop Mirage"] ~= false
Config["Use Mirage API"]    = Config["Use Mirage API"] ~= false
if tostring(Config["Mirage API"] or "") == "" then
    Config["Mirage API"] = ""
end
Config["Avoid Full Server"] = Config["Avoid Full Server"] ~= false
Config["Max Players"]       = Config["Max Players"] or 11
Config["Fetch Count"]       = math.max(1, math.floor(tonumber(Config["Fetch Count"]) or 30))
Config["Hop Delay"]         = math.max(0.1, tonumber(Config["Hop Delay"]) or 1.5)
Config["Boost FPS"]         = Config["Boost FPS"] ~= false
Config["FPS"]               = Config["FPS"] or 20
Config["Black Screen"]      = Config["Black Screen"] or false

SetStatus("Waiting game loaded...")
if not game:IsLoaded() then
    repeat task.wait(0.5) until game:IsLoaded()
end
SetStatus("Game loaded")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterPlayer     = game:GetService("StarterPlayer")
local TeleportService   = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
local Character, Humanoid, HumanoidRootPart

SetStatus("Creating UI...")
pcall(MakeUI)
SetStatus("UI ready")

SetStatus("Waiting PlayerGui...")
PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 30)
if not PlayerGui then
    SetStatus("PlayerGui timeout")
else
    SetStatus("PlayerGui ready")
end

getgenv().Config = getgenv().Config or {
    TEAM = Config["Team"] or "Pirates"
}
local TeamConfig = getgenv().Config
TeamConfig.TEAM = TeamConfig.TEAM or Config["Team"] or "Pirates"
Config["Team"] = TeamConfig.TEAM

repeat task.wait() until game:GetService("Players").LocalPlayer
repeat task.wait() until game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")

local function ChooseTeamByLargeButton()
    if LocalPlayer.Team ~= nil then
        SetStatus("Team already selected: " .. tostring(LocalPlayer.Team.Name))
        return true
    end

    SetStatus("Choosing team: " .. tostring(TeamConfig.TEAM))

    repeat
        task.wait()

        for _, v in pairs(LocalPlayer.PlayerGui:GetChildren()) do
            if string.find(v.Name, "Main") then
                local ok, err = pcall(function()
                    local button = v.ChooseTeam.Container[TeamConfig.TEAM].Frame.TextButton

                    button.Size = UDim2.new(0, 10000, 0, 10000)
                    button.Position = UDim2.new(-4, 0, -5, 0)
                    button.BackgroundTransparency = 1

                    task.wait(0.5)

                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                    task.wait(0.05)
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)

                    task.wait(0.05)
                end)

                if not ok then

                    SetStatus("Waiting ChooseTeam UI...")
                    warn("[PullLever] ChooseTeam UI: " .. tostring(err))
                end
            end
        end
    until LocalPlayer.Team ~= nil and game:IsLoaded()

    SetStatus("Team selected: " .. tostring(LocalPlayer.Team.Name))
    task.wait(3)
    return true
end

ChooseTeamByLargeButton()

local function RefreshCharacter()
    Character        = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    Humanoid         = Character:WaitForChild("Humanoid")
    HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
end

SetStatus("Waiting character...")
repeat
    task.wait(0.5)
until LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
SetStatus("Character ready")
RefreshCharacter()
LocalPlayer.CharacterAdded:Connect(function()
    task.spawn(RefreshCharacter)
end)

SetStatus("Waiting Data/Race...")
repeat
    task.wait(1)
until LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Race")
SetStatus("Data/Race ready: " .. tostring(LocalPlayer.Data.Race.Value))

local Remotes = {}
setmetatable(Remotes, {
    __index = function(_, Key)
        return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Key, 30)
    end
})
local CommF_ = Remotes.CommF_
local CommE  = Remotes.CommE

local Sea, SeaIndex = "Unknown", 0

local function GetSeaIndex()
    local placeId = game.PlaceId

    if placeId == 85211729168715 or placeId == 2753915549 then
        return 1, "Main"
    elseif placeId == 79091703265657 or placeId == 4442272183 then
        return 2, "Dressrosa"
    elseif placeId == 100117331123089 or placeId == 7449423635 then
        return 3, "Zou"
    end

    local ok, mapAttr = pcall(function() return workspace:GetAttribute("MAP") end)
    if ok and mapAttr ~= nil then
        local mapNum = tostring(mapAttr):match("%d+")
        if mapNum then
            local n = tonumber(mapNum)
            if n == 1 then return 1, "Main" end
            if n == 2 then return 2, "Dressrosa" end
            if n == 3 then return 3, "Zou" end
        end
    end

    return 0, "Unknown"
end

local function RefreshSea()
    SeaIndex, Sea = GetSeaIndex()
    return SeaIndex, Sea
end

local function EnsureSea3()
    RefreshSea()

    if SeaIndex == 3 then
        return true
    end

    SetStatus("Not Sea 3 | Current: " .. tostring(Sea) .. " -> TravelZou")

    pcall(function()
        CommF_:InvokeServer("TravelZou")
    end)

    task.wait(8)

    RefreshSea()

    if SeaIndex ~= 3 then
        SetStatus("Still not Sea 3 (" .. tostring(Sea) .. ") -> cho server xu ly, retry vong sau")
        return false
    end

    SetStatus("Now in Sea 3")
    return true
end

RefreshSea()

local ConChoChisiti36 = {
    PlayerData = {},
    Backpack   = {},
}

local function RefreshPlayerData()
    local data = LocalPlayer:FindFirstChild("Data")
    if not data then return end
    for _, c in data:GetChildren() do
        pcall(function() ConChoChisiti36.PlayerData[c.Name] = c.Value end)
    end
end

-- ============================================================
-- THREAD IDENTITY
-- require(...) module cua game se ha identity cua thread hien tai
-- xuong muc script game -> sau do ghi vao CoreGui/gethui bi loi
-- "cannot access 'Instance' (lacking capability Plugin)".
-- Boc lai de luon tra identity ve muc cao sau khi require.
-- ============================================================
local _setidentity = setthreadidentity or setidentity or set_thread_identity
    or (syn and syn.set_thread_identity)
local _getidentity = getthreadidentity or getidentity or get_thread_identity
    or (syn and syn.get_thread_identity)

local function RaiseIdentity()
    if not _setidentity then return nil end
    local prev
    if _getidentity then
        local ok, v = pcall(_getidentity)
        if ok then prev = v end
    end
    pcall(_setidentity, 8)
    return prev
end

local function RestoreIdentity(prev)
    if not _setidentity then return end
    pcall(_setidentity, prev or 8)
end

-- ============================================================
-- INVENTORY (update moi): doc qua ItemReplicationService +
-- Inventory controller + ItemConfig thay cho CommF_ getInventory
-- (getInventory khong con tra Mirror Fractal sau update).
--   Backpack[<Display.Name>] = { Name=, Count=, Category=, ItemId= }
-- ============================================================
local InvModules = {
    Inventory   = nil,
    ItemConfig  = nil,
    ItemService = nil,
    KEYS        = nil,
    Ready       = false,
}

-- Tim node theo duong dan, khong index truc tiep de loi bao ro rang
-- thay vi treo hoac "attempt to index nil".
local function ResolvePath(root, path)
    local node = root
    for _, name in ipairs(path) do
        if typeof(node) ~= "Instance" then return nil, name end
        local child = node:FindFirstChild(name)
        if not child then return nil, name end
        node = child
    end
    return node
end

local _invLoadWarned = false
local _invTilesWarned = false

local function LoadInventoryModules()
    if InvModules.Ready then return true end

    local paths = {
        Inventory   = { "Controllers", "UI", "Inventory" },
        ItemConfig  = { "ItemConfig" },
        ItemService = { "ItemReplicationService" },
        KEYS        = { "ItemReplicationService", "KEYS" },
    }

    local nodes = {}
    for key, path in pairs(paths) do
        local node, missing = ResolvePath(ReplicatedStorage, path)
        if not node then
            if not _invLoadWarned then
                _invLoadWarned = true
                warn("[Inventory] Khong tim thay ReplicatedStorage."
                    .. table.concat(path, ".")
                    .. " (thieu '" .. tostring(missing) .. "')")
            end
            return false
        end
        nodes[key] = node
    end

    -- require module cua game co the doi identity khac nhau tuy
    -- executor. Thu lan luot 2 (script game) -> 8 -> giu nguyen.
    -- Dung `false` lam sentinel "khong doi identity": neu de nil trong
    -- table constructor thi ipairs se cat mat phan tu do.
    local candidates = _setidentity and {2, 8, false} or {false}
    local lastErr

    for _, ident in ipairs(candidates) do
        local prev = RaiseIdentity()
        if ident and _setidentity then pcall(_setidentity, ident) end
        local ok, err = pcall(function()
            InvModules.Inventory   = require(nodes.Inventory)
            InvModules.ItemConfig  = require(nodes.ItemConfig)
            InvModules.ItemService = require(nodes.ItemService)
            InvModules.KEYS        = require(nodes.KEYS)
        end)

        RestoreIdentity(prev)

        if ok and type(InvModules.Inventory) == "table"
            and type(InvModules.ItemService) == "table" then
            InvModules.Ready = true
            return true
        end

        lastErr = err
        InvModules.Inventory, InvModules.ItemConfig = nil, nil
        InvModules.ItemService, InvModules.KEYS = nil, nil
    end

    if not _invLoadWarned then
        _invLoadWarned = true
        warn("[Inventory] require that bai: " .. tostring(lastErr))
    end
    return false
end

local function InventoryModulesInitialized()
    if not InvModules.Ready then return false end
    local ok, res = pcall(function()
        return InvModules.Inventory:GetIfInitialized()
            and InvModules.ItemService.IsInitialized == true
    end)
    return ok and res == true
end

local function _RefreshInventoryInner()
    -- LoadInventoryModules da tu warn mot lan roi, khong warn lai o day
    -- vi main loop goi moi 1s -> spam console.
    if not LoadInventoryModules() then
        return
    end

    if not InventoryModulesInitialized() then
        return
    end

    local Inventory   = InvModules.Inventory
    local ItemConfig  = InvModules.ItemConfig
    local ItemService  = InvModules.ItemService
    local KEYS        = InvModules.KEYS

    -- So luong theo ItemId
    local amounts = {}
    local okQty, qtyList = pcall(function()
        return ItemService:GetItems(KEYS.QUANTITY)
    end)
    if okQty and type(qtyList) == "table" then
        for _, item in pairs(qtyList) do
            if type(item) == "table" and item.ItemId then
                amounts[item.ItemId] = (amounts[item.ItemId] or 0)
                    + (tonumber(item.Value) or 0)
            end
        end
    end

    local okTiles, tiles = pcall(function() return Inventory:GetTiles() end)
    if not okTiles or type(tiles) ~= "table" then
        -- Chi warn mot lan: main loop goi moi 1s.
        if not _invTilesWarned then
            _invTilesWarned = true
            warn("[Inventory] GetTiles that bai: " .. tostring(tiles))
        end
        return
    end
    _invTilesWarned = false

    local backpack, seen, total = {}, {}, 0

    for _, tile in pairs(tiles) do
        local id = type(tile) == "table" and tile.ItemId or nil

        if id and not seen[id] then
            seen[id] = true

            local okCfg, config = pcall(function()
                return ItemConfig.match(id):unwrap()
            end)

            if okCfg and type(config) == "table" and config.Display then
                local name = config.Display.Name
                    or (config.Index and config.Index.StorageKey)
                    or tostring(id)

                backpack[tostring(name)] = {
                    Name     = tostring(name),
                    Count    = amounts[id] or 1,
                    Category = config.Display.Category,
                    ItemId   = id,
                }
                total = total + 1
            end
        end
    end

    -- Chi ghi de khi doc duoc it nhat 1 item, tranh xoa trang cache
    -- khi inventory chua replicate xong.
    if total > 0 then
        ConChoChisiti36.Backpack = backpack
    end
end

-- Goi vao module cua game co the ha identity giua duong. Luon tra
-- identity ve muc cao sau khi doc xong, ke ca khi loi.
local function RefreshInventory()
    local prev = RaiseIdentity()
    local ok, err = pcall(_RefreshInventoryInner)
    RestoreIdentity(prev)
    if not ok then
        warn("[Inventory] RefreshInventory loi: " .. tostring(err))
    end
end

CommE.OnClientEvent:Connect(function(...)
    local t = {...}
    if type(t[1]) == "string" and t[1]:find("Item") then
        RefreshInventory()
    end
end)

RefreshPlayerData()
RefreshInventory()

local function IfTableHaveIndex(t)
    if type(t) ~= "table" then return false end
    for _ in t do return true end
end

-- ============================================================
-- INTERNAL FIXED SETTINGS
-- Cac gia tri nay KHONG doc tu getgenv/config, nen client ben ngoai
-- khong the tang/giam toc do hoac TTL trong luc script dang chay.
-- Muc tween duoc chon can bang: khong qua nhanh, khong qua cham.
-- ============================================================
local FIXED_TWEEN_SPEED = 215
local FIXED_TWEEN_ACCELERATION = 480
local FIXED_TWEEN_DECELERATION = 650
local FIXED_TWEEN_ARRIVAL = 6
local FIXED_TWEEN_MIN_SPEED = 34

-- 20 client cung mot workspace: blacklist/claim/cache dung chung.
local MIRAGE_BLACKLIST_TTL = 15 * 60
local MIRAGE_JOIN_FAIL_TTL = 2 * 60
local MIRAGE_CLAIM_TTL = 35
local MIRAGE_API_CACHE_TTL = 15
local MIRAGE_API_LOCK_TTL = 8
local MIRAGE_JOIN_CONFIRM_WAIT = 4.0
local MIRAGE_NO_ISLAND_CHECKS = 3
local MIRAGE_NO_ISLAND_CHECK_DELAY = 1.25
local MIRAGE_JITTER_MIN = 0.20
local MIRAGE_JITTER_MAX = 0.85

local MIRAGE_SHARED_ROOT = "mirage_shared"
local MIRAGE_USE_FOLDERS = type(makefolder) == "function"
local MIRAGE_BLACKLIST_DIR = MIRAGE_SHARED_ROOT .. "/blacklist"
local MIRAGE_FAIL_DIR = MIRAGE_SHARED_ROOT .. "/join_fail"
local MIRAGE_CLAIM_DIR = MIRAGE_SHARED_ROOT .. "/claim"
local MIRAGE_API_CACHE_FILE = MIRAGE_USE_FOLDERS
    and (MIRAGE_SHARED_ROOT .. "/api_cache.json")
    or "mirage_shared_api_cache.json"
local MIRAGE_API_LOCK_FILE = MIRAGE_USE_FOLDERS
    and (MIRAGE_SHARED_ROOT .. "/api_fetch.lock")
    or "mirage_shared_api_fetch.lock"

local MIRAGE_CLIENT_TOKEN = table.concat({
    tostring(LocalPlayer.UserId or 0),
    tostring(math.random(100000, 999999)),
    tostring(os.time()),
}, ":")

local function SharedFilesReady()
    return type(isfile) == "function"
        and type(readfile) == "function"
        and type(writefile) == "function"
end

local function EnsureSharedFolders()
    if type(makefolder) ~= "function" then
        return false
    end

    for _, folder in ipairs({
        MIRAGE_SHARED_ROOT,
        MIRAGE_BLACKLIST_DIR,
        MIRAGE_FAIL_DIR,
        MIRAGE_CLAIM_DIR,
    }) do
        pcall(function()
            if type(isfolder) ~= "function" or not isfolder(folder) then
                makefolder(folder)
            end
        end)
    end

    return true
end

EnsureSharedFolders()

local function SafeJobId(jobId)
    return tostring(jobId or "")
        :gsub("[^%w%-_]", "_")
end

local function DeleteFileSafe(path)
    if type(delfile) == "function" then
        pcall(function()
            if type(isfile) ~= "function" or isfile(path) then
                delfile(path)
            end
        end)
    end
end

local function ReadFileSafe(path)
    if not SharedFilesReady() then return nil end

    local ok, value = pcall(function()
        if not isfile(path) then return nil end
        return readfile(path)
    end)

    return ok and value or nil
end

local function WriteFileSafe(path, value)
    if not SharedFilesReady() then return false end
    local ok = pcall(function()
        writefile(path, tostring(value or ""))
    end)
    return ok
end

local function TimedPathActive(path, ttl)
    local raw = ReadFileSafe(path)
    if type(raw) ~= "string" then return false end

    local stamp = tonumber(raw:match("^(%d+)"))
    if not stamp then
        DeleteFileSafe(path)
        return false
    end

    if os.time() - stamp < ttl then
        return true
    end

    DeleteFileSafe(path)
    return false
end

local function BlacklistPath(jobId)
    local safe = SafeJobId(jobId)
    return MIRAGE_USE_FOLDERS
        and (MIRAGE_BLACKLIST_DIR .. "/" .. safe .. ".txt")
        or ("mirage_shared_blacklist_" .. safe .. ".txt")
end

local function JoinFailPath(jobId)
    local safe = SafeJobId(jobId)
    return MIRAGE_USE_FOLDERS
        and (MIRAGE_FAIL_DIR .. "/" .. safe .. ".txt")
        or ("mirage_shared_join_fail_" .. safe .. ".txt")
end

local function ClaimPath(jobId)
    local safe = SafeJobId(jobId)
    return MIRAGE_USE_FOLDERS
        and (MIRAGE_CLAIM_DIR .. "/" .. safe .. ".txt")
        or ("mirage_shared_claim_" .. safe .. ".txt")
end

local function IsMirageBlacklisted(jobId)
    return TimedPathActive(BlacklistPath(jobId), MIRAGE_BLACKLIST_TTL)
end

local function MarkMirageBlacklisted(jobId, reason)
    if not jobId or tostring(jobId) == "" then return false end
    local content = tostring(os.time()) .. "|" .. tostring(reason or "no_mirage")
    local ok = WriteFileSafe(BlacklistPath(jobId), content)
    if ok then
        warn("[MirageShared] Blacklist 15m: " .. tostring(jobId):sub(1, 8)
            .. " | " .. tostring(reason or "no_mirage"))
    end
    return ok
end

local function IsJoinFailCoolingDown(jobId)
    return TimedPathActive(JoinFailPath(jobId), MIRAGE_JOIN_FAIL_TTL)
end

local function MarkJoinFail(jobId, reason)
    if not jobId or tostring(jobId) == "" then return false end
    local ok = WriteFileSafe(
        JoinFailPath(jobId),
        tostring(os.time()) .. "|" .. tostring(reason or "join_failed")
    )
    if ok then
        warn("[MirageShared] Join fail cooldown 2m: "
            .. tostring(jobId):sub(1, 8))
    end
    return ok
end

local function ReadClaim(jobId)
    local raw = ReadFileSafe(ClaimPath(jobId))
    if type(raw) ~= "string" then return nil, nil end

    local owner, stamp = raw:match("^([^|]+)|(%d+)$")
    stamp = tonumber(stamp)

    if not owner or not stamp then
        DeleteFileSafe(ClaimPath(jobId))
        return nil, nil
    end

    if os.time() - stamp >= MIRAGE_CLAIM_TTL then
        DeleteFileSafe(ClaimPath(jobId))
        return nil, nil
    end

    return owner, stamp
end

local function IsMirageClaimed(jobId)
    local owner = ReadClaim(jobId)
    return owner ~= nil and owner ~= MIRAGE_CLIENT_TOKEN
end

local function TryClaimMirageJob(jobId)
    if not SharedFilesReady() then
        return true
    end

    local owner = ReadClaim(jobId)
    if owner and owner ~= MIRAGE_CLIENT_TOKEN then
        return false
    end

    -- Jitter nho truoc khi ghi de 20 client khong cung va cham file.
    task.wait(MIRAGE_JITTER_MIN
        + math.random() * (MIRAGE_JITTER_MAX - MIRAGE_JITTER_MIN))

    local path = ClaimPath(jobId)
    if not WriteFileSafe(path, MIRAGE_CLIENT_TOKEN .. "|" .. tostring(os.time())) then
        return false
    end

    -- Doc lai: client ghi sau cung la client duy nhat duoc di tiep.
    task.wait(0.08 + math.random() * 0.08)
    local verifiedOwner = ReadClaim(jobId)
    return verifiedOwner == MIRAGE_CLIENT_TOKEN
end

local function ReleaseMirageClaim(jobId)
    local owner = ReadClaim(jobId)
    if owner == MIRAGE_CLIENT_TOKEN then
        DeleteFileSafe(ClaimPath(jobId))
    end
end

local function RotateServersForClient(list)
    if type(list) ~= "table" or #list <= 1 then
        return list
    end

    local rotated = {}
    local offset = (math.abs(tonumber(LocalPlayer.UserId) or 0) % #list) + 1

    for step = 0, #list - 1 do
        local index = ((offset - 1 + step) % #list) + 1
        rotated[#rotated + 1] = list[index]
    end

    return rotated
end

local function ReadSharedApiCache(placeId)
    local raw = ReadFileSafe(MIRAGE_API_CACHE_FILE)
    if type(raw) ~= "string" or raw == "" then return nil end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    if not ok or type(data) ~= "table" then
        return nil
    end

    if tonumber(data.PlaceId) ~= tonumber(placeId)
        or os.time() - (tonumber(data.Timestamp) or 0) >= MIRAGE_API_CACHE_TTL
        or type(data.Servers) ~= "table"
    then
        return nil
    end

    return data.Servers
end

local function WriteSharedApiCache(placeId, servers)
    if not SharedFilesReady() or type(servers) ~= "table" then return false end

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({
            Timestamp = os.time(),
            PlaceId = tonumber(placeId),
            Servers = servers,
        })
    end)

    return ok and WriteFileSafe(MIRAGE_API_CACHE_FILE, encoded)
end

local function TryAcquireApiFetchLock()
    if not SharedFilesReady() then return true end

    local raw = ReadFileSafe(MIRAGE_API_LOCK_FILE)
    if type(raw) == "string" then
        local owner, stamp = raw:match("^([^|]+)|(%d+)$")
        stamp = tonumber(stamp)
        if owner and stamp and os.time() - stamp < MIRAGE_API_LOCK_TTL
            and owner ~= MIRAGE_CLIENT_TOKEN
        then
            return false
        end
    end

    WriteFileSafe(
        MIRAGE_API_LOCK_FILE,
        MIRAGE_CLIENT_TOKEN .. "|" .. tostring(os.time())
    )
    task.wait(0.08 + math.random() * 0.08)

    local verify = ReadFileSafe(MIRAGE_API_LOCK_FILE)
    return type(verify) == "string"
        and verify:match("^([^|]+)|") == MIRAGE_CLIENT_TOKEN
end

local function ReleaseApiFetchLock()
    local raw = ReadFileSafe(MIRAGE_API_LOCK_FILE)
    if type(raw) == "string"
        and raw:match("^([^|]+)|") == MIRAGE_CLIENT_TOKEN
    then
        DeleteFileSafe(MIRAGE_API_LOCK_FILE)
    end
end

local CurrentServerNoMirageHandled = false
local function ConfirmAndBlacklistCurrentServerNoMirage()
    if CurrentServerNoMirageHandled then
        return IsMirageBlacklisted(game.JobId)
    end

    CurrentServerNoMirageHandled = true

    if IsMirageBlacklisted(game.JobId) then
        return true
    end

    for _ = 1, MIRAGE_NO_ISLAND_CHECKS do
        local map = workspace:FindFirstChild("Map")
        if map and map:FindFirstChild("MysticIsland") then
            return false
        end
        task.wait(MIRAGE_NO_ISLAND_CHECK_DELAY)
    end

    return MarkMirageBlacklisted(game.JobId, "joined_but_no_mirage")
end

local CachedServers, LastServersDataPulled
local function GetServers()
    if LastServersDataPulled and os.time() - LastServersDataPulled < 60 then
        return CachedServers
    end
    for i = 1, 100 do
        local data = ReplicatedStorage:FindFirstChild("__ServerBrowser")
            and ReplicatedStorage.__ServerBrowser:InvokeServer(i)
        if IfTableHaveIndex(data) then
            CachedServers = data
            LastServersDataPulled = os.time()
            return data
        end
    end
end

local function Hop(Reason)
    print("[PullLever] Hop: " .. tostring(Reason))
    local Servers = GetServers()
    if not Servers then return false end

    local candidates = {}
    for JobId, v in Servers do
        local players = tonumber(v.Count) or 0
        local jobId = tostring(JobId)
        if jobId ~= tostring(game.JobId)
            and players <= 11
            and not IsMirageBlacklisted(jobId)
            and not IsJoinFailCoolingDown(jobId)
            and not IsMirageClaimed(jobId)
        then
            candidates[#candidates + 1] = {
                JobId = jobId,
                Players = players,
                Region = v.Region,
            }
        end
    end

    candidates = RotateServersForClient(candidates)

    for _, data in ipairs(candidates) do
        if TryClaimMirageJob(data.JobId) then
            SetStatus("Fallback join | " .. data.JobId:sub(1, 8))
            local beforeJob = tostring(game.JobId)
            local ok = pcall(function()
                ReplicatedStorage:FindFirstChild("__ServerBrowser")
                    :InvokeServer("teleport", data.JobId)
            end)

            if not ok then
                MarkJoinFail(data.JobId, "invoke_error")
                ReleaseMirageClaim(data.JobId)
            else
                task.wait(MIRAGE_JOIN_CONFIRM_WAIT)
                if tostring(game.JobId) == beforeJob then
                    MarkJoinFail(data.JobId, "session_still_alive")
                    ReleaseMirageClaim(data.JobId)
                end
            end
        end
    end

    return false
end

local JoinJobIdByServerBrowser

local function HttpRequest(opts)

    local req = request or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)

    if type(req) ~= "function" then
        return false, "executor does not support request"
    end

    local lastErr
    for attempt = 1, 3 do
        local ok, res = pcall(function() return req(opts) end)
        if ok and type(res) == "table" then
            return true, res
        end
        lastErr = res
        warn("[MirageAPI] request attempt " .. tostring(attempt) .. " failed: " .. tostring(res))
        task.wait(2)
    end
    return false, lastErr
end

local function JsonDecodeSafe(body)
    if type(body) ~= "string" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

-- ============================================================
-- MIRAGE API (baorph): schema moi (2026-07)
--   { count = N, ok = true, key = "island",
--     items = [ "job id: <GUID>; player: <N>[/12]; placeid: <N|None>", ... ] }
-- items la mang STRING, khong phai object.
-- Giu nguyen thu tu API tra ve (khong sort).
-- ============================================================
local function NormalizeServerEntry(v)
    -- Schema moi: string
    if type(v) == "string" then
        local jobId   = v:match("job%s*id:%s*([%x%-]+)")
        local players = tonumber(v:match("player:%s*(%d+)")) or 0
        local placeId = tonumber(v:match("placeid:%s*(%d+)"))  -- "None" -> nil
        if not jobId or jobId == "" then return nil end
        return {
            JobId   = jobId,
            PlaceId = placeId,
            Players = players,
        }
    end
    -- Du phong: object (schema cu)
    if type(v) ~= "table" then return nil end
    local jobId = v.raw_job_id or v.job_id or v.jobid or v.JobId or v.id
    if not jobId or tostring(jobId) == "" then return nil end
    return {
        JobId   = tostring(jobId),
        PlaceId = tonumber(v.place_id or v.placeid or v.PlaceId),
        Players = tonumber(v.players or v.player or v.Players) or 0,
    }
end

local function ExtractServerList(data)
    local list = {}
    if type(data) ~= "table" then return list end

    local source = data.items or data.data or data.servers
    if type(source) ~= "table" then return list end

    for _, v in ipairs(source) do
        local one = NormalizeServerEntry(v)
        if one then table.insert(list, one) end
    end

    return list
end

local LastMirageApiFetch = 0
local CachedMirageServers = nil
local CachedMiragePlaceId = nil

local function GetMirageServersFromAPI()
    local cfg = getgenv().PullLeverConfig or {}
    local url = tostring(cfg["Mirage API"] or "")

    if url == "" then
        warn("[MirageAPI] Mirage API url rong -> bo qua")
        return {}
    end

    local currentPlaceId = tonumber(game.PlaceId)

    if CachedMirageServers
        and CachedMiragePlaceId == currentPlaceId
        and os.time() - LastMirageApiFetch < MIRAGE_API_CACHE_TTL
    then
        return CachedMirageServers
    end

    local shared = ReadSharedApiCache(currentPlaceId)
    if type(shared) == "table" and #shared > 0 then
        CachedMirageServers = shared
        CachedMiragePlaceId = currentPlaceId
        LastMirageApiFetch = os.time()
        SetStatus("Mirage shared cache: " .. tostring(#shared))
        return shared
    end

    local ownsFetchLock = TryAcquireApiFetchLock()
    if not ownsFetchLock then
        -- Mot client khac dang fetch. Doi cache chung toi da 3 giay.
        for _ = 1, 12 do
            task.wait(0.25)
            shared = ReadSharedApiCache(currentPlaceId)
            if type(shared) == "table" and #shared > 0 then
                CachedMirageServers = shared
                CachedMiragePlaceId = currentPlaceId
                LastMirageApiFetch = os.time()
                return shared
            end
        end
    end

    SetStatus("Fetching Mirage API...")

    local ok, res = HttpRequest({
        Url = url,
        Method = "GET",
        Headers = {
            ["Accept"]     = "application/json",
            ["User-Agent"] = "Roblox/WinInet",
        },
    })

    if not ok then
        ReleaseApiFetchLock()
        warn("[MirageAPI] Request failed: " .. tostring(res))
        return {}
    end

    local statusCode = tonumber(res.StatusCode or res.status_code or res.Status or 0)
    local body = res.Body or res.body or ""

    print("[MirageAPI] Status=" .. tostring(statusCode) .. " BodyLen=" .. tostring(#body))

    if statusCode ~= 0 and (statusCode < 200 or statusCode >= 300) then
        ReleaseApiFetchLock()
        warn("[MirageAPI] Bad status: " .. tostring(statusCode))
        return {}
    end

    local data = JsonDecodeSafe(body)
    if not data then
        ReleaseApiFetchLock()
        warn("[MirageAPI] JSON decode failed. Body head: " .. tostring(body):sub(1, 300))
        return {}
    end

    local servers = ExtractServerList(data)

    if #servers > 0 then
        LastMirageApiFetch = os.time()
        CachedMiragePlaceId = currentPlaceId
        CachedMirageServers = servers
        WriteSharedApiCache(currentPlaceId, servers)
    end

    ReleaseApiFetchLock()

    print("[MirageAPI] Parsed " .. tostring(#servers) .. " server(s), moi nhat truoc")
    SetStatus("Mirage API servers: " .. tostring(#servers))
    return servers
end

JoinJobIdByServerBrowser = function(jobId)
    if not jobId or tostring(jobId) == "" then
        return false
    end

    if tostring(jobId) == tostring(game.JobId) then
        return false
    end

    local sb = ReplicatedStorage:FindFirstChild("__ServerBrowser")
    if not sb then
        warn("[ServerBrowser] Khong tim thay __ServerBrowser")
        return false
    end

    local ok, result = pcall(function()
        return sb:InvokeServer("teleport", tostring(jobId))
    end)

    if not ok then
        warn("[ServerBrowser] Join JobId loi: " .. tostring(result))
        return false
    end

    return true
end

-- Lay 30 server moi nhat -> join lan luot tu gan nhat den thu 30,
-- moi lan cach nhau Hop Delay (1.5s). Neu het danh sach van chua
-- vao duoc server nao -> return false de main loop refresh lai.
local PendingMirageJoin = nil

TeleportService.TeleportInitFailed:Connect(function(player, result, message)
    if player ~= LocalPlayer or not PendingMirageJoin then return end

    local jobId = PendingMirageJoin.JobId
    MarkJoinFail(jobId, tostring(result) .. ":" .. tostring(message))
    ReleaseMirageClaim(jobId)
    PendingMirageJoin = nil
end)

local function HopMirageByAPI()
    local cfg = getgenv().PullLeverConfig or {}

    if cfg["Use Mirage API"] == false then
        return false
    end

    local servers = GetMirageServersFromAPI()
    if type(servers) ~= "table" or #servers <= 0 then
        SetStatus("Mirage API empty -> refresh")
        return false
    end

    local currentPlaceId = tonumber(game.PlaceId)
    local maxPlayers = tonumber(cfg["Max Players"] or 11) or 11
    local avoidFull = cfg["Avoid Full Server"] ~= false
    local fetchCount = math.max(1, math.floor(tonumber(cfg["Fetch Count"]) or 30))

    local candidates = {}
    local samePlaceCount = 0
    local skippedBlacklist = 0
    local skippedClaim = 0
    local skippedFail = 0

    for _, server in ipairs(servers) do
        local placeId = tonumber(server.PlaceId)
        local players = tonumber(server.Players) or 0
        local jobId = tostring(server.JobId or "")

        local samePlace = (placeId == nil) or (placeId == currentPlaceId)
        local notSameJob = jobId ~= "" and jobId ~= tostring(game.JobId)
        local notFull = (not avoidFull) or players <= maxPlayers

        if samePlace then samePlaceCount = samePlaceCount + 1 end

        if samePlace and notSameJob and notFull then
            if IsMirageBlacklisted(jobId) then
                skippedBlacklist = skippedBlacklist + 1
            elseif IsJoinFailCoolingDown(jobId) then
                skippedFail = skippedFail + 1
            elseif IsMirageClaimed(jobId) then
                skippedClaim = skippedClaim + 1
            else
                candidates[#candidates + 1] = server
                if #candidates >= fetchCount then break end
            end
        end
    end

    candidates = RotateServersForClient(candidates)

    if #candidates == 0 then
        SetStatus(
            "No candidate | BL=" .. tostring(skippedBlacklist)
            .. " Claim=" .. tostring(skippedClaim)
            .. " Fail=" .. tostring(skippedFail)
        )
        return false
    end

    SetStatus(
        "Mirage candidates=" .. tostring(#candidates)
        .. " | BL=" .. tostring(skippedBlacklist)
        .. " Claim=" .. tostring(skippedClaim)
    )

    for i, server in ipairs(candidates) do
        local jobId = tostring(server.JobId)

        -- Doc lai ngay truoc claim vi client khac co the vua ghi file.
        if not IsMirageBlacklisted(jobId)
            and not IsJoinFailCoolingDown(jobId)
            and TryClaimMirageJob(jobId)
        then
            SetStatus(
                "Join Mirage " .. tostring(i) .. "/" .. tostring(#candidates)
                .. " | P=" .. tostring(server.Players)
                .. " | " .. jobId:sub(1, 8)
            )

            print(
                "[MirageAPI] #" .. tostring(i)
                .. " JobId=" .. jobId
                .. " PlaceId=" .. tostring(server.PlaceId)
                .. " Players=" .. tostring(server.Players)
            )

            local beforeJob = tostring(game.JobId)
            PendingMirageJoin = {
                JobId = jobId,
                StartedAt = tick(),
            }

            local invoked = JoinJobIdByServerBrowser(jobId)

            if not invoked then
                MarkJoinFail(jobId, "invoke_failed")
                ReleaseMirageClaim(jobId)
                PendingMirageJoin = nil
            else
                task.wait(MIRAGE_JOIN_CONFIRM_WAIT)

                -- Teleport thanh cong se reset phien. Con o JobId cu sau 4s
                -- thi chi cooldown 2 phut, KHONG blacklist 15 phut.
                if tostring(game.JobId) == beforeJob then
                    MarkJoinFail(jobId, "session_still_alive")
                    ReleaseMirageClaim(jobId)
                    PendingMirageJoin = nil
                end
            end
        end
    end

    SetStatus("Da thu het candidate -> refresh")
    return false
end

local function ConvertTo(Type, Data)
    if typeof(Data) ~= "table" then
        return Type.new(Data.x, Data.y, Data.z)
    end
    return Type.new(Data.x, Data.y, Data.z)
end

local function CaculateDistance(Origin, Destination)
    Origin = Origin or HumanoidRootPart.CFrame
    Destination = Destination or HumanoidRootPart.CFrame
    local a = typeof(Origin)    == "CFrame" and Origin.Position    or (typeof(Origin)    == "Vector3" and Origin    or ConvertTo(Vector3, Origin))
    local b = typeof(Destination) == "CFrame" and Destination.Position or (typeof(Destination) == "Vector3" and Destination or ConvertTo(Vector3, Destination))
    return (a - b).Magnitude
end

-- ============================================================
-- SAFE VELOCITY TWEEN
-- Giữ nguyên chữ ký TweenTo(Position), nhưng:
--   * không tạo TweenGhost;
--   * không set HumanoidRootPart.CFrame mỗi Heartbeat;
--   * không snap thẳng ở khoảng cách <= 200;
--   * tăng tốc và phanh mượt bằng BodyVelocity;
--   * BodyGyro chỉ xoay theo trục Y để tránh rung/ngửa nhân vật.
-- ============================================================
local SafeMoveTarget = nil
local SafeMoveEnabled = false
local SafeMoveRoot = nil
local SafeMoveVelocity = Vector3.zero
local SafeMoveLastDistance = math.huge
local SafeMoveLastProgressAt = 0

local SAFE_MOVE_VELOCITY_NAME = "PullLeverSafeVelocity"
local SAFE_MOVE_GYRO_NAME = "PullLeverSafeGyro"

local function NoclipLoop()
    if LocalPlayer.Character then
        for _, c in LocalPlayer.Character:GetDescendants() do
            if c:IsA("BasePart")
                and c.CanCollide
                and c.Name ~= "HumanoidRootPart"
            then
                c.CanCollide = false
            end
        end
    end
end
RunService.Stepped:Connect(NoclipLoop)

local function MoveVectorTowards(current, target, maximumChange)
    local difference = target - current
    local magnitude = difference.Magnitude

    if magnitude <= maximumChange or magnitude <= 1e-4 then
        return target
    end

    return current + difference.Unit * maximumChange
end

local function GetSafeMoveActuators(root)
    if not root or not root.Parent then
        return nil, nil
    end

    local velocity = root:FindFirstChild(SAFE_MOVE_VELOCITY_NAME)

    if not velocity then
        velocity = Instance.new("BodyVelocity")
        velocity.Name = SAFE_MOVE_VELOCITY_NAME
        velocity.P = 1500
        velocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        velocity.Velocity = Vector3.zero
        velocity.Parent = root
    end

    local gyro = root:FindFirstChild(SAFE_MOVE_GYRO_NAME)

    if not gyro then
        gyro = Instance.new("BodyGyro")
        gyro.Name = SAFE_MOVE_GYRO_NAME
        gyro.P = 5000
        gyro.D = 900
        gyro.MaxTorque = Vector3.new(0, 1e9, 0)
        gyro.CFrame = root.CFrame
        gyro.Parent = root
    end

    return velocity, gyro
end

local function StopTween()
    SafeMoveEnabled = false
    SafeMoveTarget = nil
    SafeMoveVelocity = Vector3.zero
    SafeMoveLastDistance = math.huge
    SafeMoveLastProgressAt = 0

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if humanoid then
        humanoid.AutoRotate = true
    end

    if root then
        local velocity = root:FindFirstChild(SAFE_MOVE_VELOCITY_NAME)
        local gyro = root:FindFirstChild(SAFE_MOVE_GYRO_NAME)

        if velocity then
            pcall(function()
                velocity:Destroy()
            end)
        end

        if gyro then
            pcall(function()
                gyro:Destroy()
            end)
        end

        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    SafeMoveRoot = nil
end

RunService.Heartbeat:Connect(function(deltaTime)
    if not SafeMoveEnabled or typeof(SafeMoveTarget) ~= "CFrame" then
        return
    end

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not char
        or not humanoid
        or humanoid.Health <= 0
        or not root
        or not root:IsDescendantOf(workspace)
    then
        StopTween()
        return
    end

    if SafeMoveRoot ~= root then
        SafeMoveRoot = root
        SafeMoveVelocity = Vector3.zero
        SafeMoveLastDistance = math.huge
        SafeMoveLastProgressAt = tick()
    end

    humanoid.Sit = false
    humanoid.AutoRotate = false

    local velocityMover, gyro = GetSafeMoveActuators(root)

    if not velocityMover or not gyro then
        return
    end

    deltaTime = math.clamp(tonumber(deltaTime) or 0.016, 0.001, 0.10)

    local targetPosition = SafeMoveTarget.Position
    local offset = targetPosition - root.Position
    local distance = offset.Magnitude
    local arrivalDistance =
        FIXED_TWEEN_ARRIVAL

    -- Không snap CFrame ở đích. Chỉ dừng khi đã bay thật sự tới gần.
    if distance <= arrivalDistance then
        velocityMover.Velocity = Vector3.zero
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        StopTween()
        return
    end

    local maximumSpeed =
        FIXED_TWEEN_SPEED

    local acceleration =
        FIXED_TWEEN_ACCELERATION

    local deceleration =
        FIXED_TWEEN_DECELERATION

    local minimumCruise =
        FIXED_TWEEN_MIN_SPEED

    local brakingDistance = math.max(distance - arrivalDistance, 0)
    local brakingSpeed = math.sqrt(2 * deceleration * brakingDistance)
    local desiredSpeed = math.min(maximumSpeed, brakingSpeed)

    if distance > 30 then
        desiredSpeed =
            math.max(desiredSpeed, math.min(maximumSpeed, minimumCruise))
    end

    local desiredVelocity =
        distance > 1e-3
        and offset.Unit * desiredSpeed
        or Vector3.zero

    local changeRate =
        desiredVelocity.Magnitude < SafeMoveVelocity.Magnitude
        and deceleration
        or acceleration

    SafeMoveVelocity = MoveVectorTowards(
        SafeMoveVelocity,
        desiredVelocity,
        changeRate * deltaTime
    )

    -- Nếu bị giữ tại một vị trí quá lâu, chỉ reset gia tốc.
    -- Không dịch CFrame để thoát kẹt.
    if distance < SafeMoveLastDistance - 1 then
        SafeMoveLastDistance = distance
        SafeMoveLastProgressAt = tick()
    elseif SafeMoveLastProgressAt == 0 then
        SafeMoveLastProgressAt = tick()
    elseif tick() - SafeMoveLastProgressAt >= 3 then
        SafeMoveVelocity =
            offset.Unit * math.min(maximumSpeed, minimumCruise + 25)

        SafeMoveLastProgressAt = tick()
        SafeMoveLastDistance = distance
    end

    velocityMover.Velocity = SafeMoveVelocity
    root.AssemblyAngularVelocity = Vector3.zero

    local flatDirection = Vector3.new(offset.X, 0, offset.Z)

    if flatDirection.Magnitude > 0.05 then
        gyro.CFrame = CFrame.lookAt(
            root.Position,
            root.Position + flatDirection.Unit
        )
    end
end)

function TweenTo(Position)
    if Position == false then
        StopTween()
        return false
    end

    if not Position then
        return false
    end

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not char or not humanoid or humanoid.Health <= 0 or not root then
        StopTween()
        return false
    end

    Position =
        typeof(Position) ~= "CFrame"
        and ConvertTo(CFrame, Position)
        or Position

    if typeof(Position) ~= "CFrame" then
        return false
    end

    local p = Position.Position
    Position = CFrame.new(
        p.X,
        math.max(p.Y, 5),
        p.Z
    ) * (Position - Position.Position)

    local distance = (Position.Position - root.Position).Magnitude
    local arrivalDistance =
        FIXED_TWEEN_ARRIVAL

    if distance <= arrivalDistance then
        StopTween()
        return true
    end

    local targetChanged =
        typeof(SafeMoveTarget) ~= "CFrame"
        or (SafeMoveTarget.Position - Position.Position).Magnitude > 2

    SafeMoveTarget = Position
    SafeMoveEnabled = true

    if SafeMoveRoot ~= root or targetChanged then
        SafeMoveRoot = root
        SafeMoveVelocity = Vector3.zero
        SafeMoveLastDistance = distance
        SafeMoveLastProgressAt = tick()
    end

    humanoid.Sit = false
    humanoid.AutoRotate = false
    GetSafeMoveActuators(root)

    return true
end

function GetBlueGear()
    local mi = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("MysticIsland")
    if not mi then return nil end
    for _, v in mi:GetDescendants() do
        if v:IsA("MeshPart") and v.MeshId == "rbxassetid://10153114969" and v.Transparency ~= 1 then
            return v.CFrame
        end
    end
    return nil
end

local function HasMirrorFractal()
    return ConChoChisiti36.Backpack["Mirror Fractal"] ~= nil
end
local function HasValkyrieHelm()
    return ConChoChisiti36.Backpack["Valkyrie Helm"] ~= nil
end
local function IsTempleDoorOpened()
    local ok, v = pcall(function() return CommF_:InvokeServer("CheckTempleDoor") end)
    return ok and v == true
end
local function IsCurrentRaceV3()
    local ok, v = pcall(function()
        return CommF_:InvokeServer("Wenlocktoad", "3")
    end)
    return ok and v == -2
end
local function IsRaceV4ProgressReady()
    local ok, v = pcall(function() return CommF_:InvokeServer("RaceV4Progress", "Check") end)
    return ok and v == 4
end

local function DoRaceV4Progress()
    SetStatus("Temple: dang chay RaceV4Progress")
    TweenTo(CFrame.new(3032, 2280, -7325))
    if CaculateDistance(CFrame.new(3032, 2280, -7325)) < 30 then
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Begin") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Check") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Teleport") end)
        task.wait(2)
        TweenTo(CFrame.new(28613, 14896, 106))
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Check") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "TeleportBack") end)
        task.wait(3)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Continue") end)
    end
end

local function DoMirageBlueGear()
    local mirage = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("MysticIsland")
    if not mirage then
        ConfirmAndBlacklistCurrentServerNoMirage()

        if Config["Hop Mirage"] then
            SetStatus("Khong co Mirage -> da blacklist server hien tai -> Hop API")
            if not HopMirageByAPI() then
                SetStatus("Mirage API rong -> fallback Hop __ServerBrowser")
                Hop("Mirage API empty")
            end
        else
            SetStatus("Khong co Mirage (Hop Mirage = false)")
        end
        return
    end

    local hour = math.floor(Lighting.ClockTime)
    if hour >= 12 or hour < 5 then
        local blue = GetBlueGear()
        if blue then
            SetStatus("Thay Blue Gear -> Tween")
            TweenTo(blue)
            return
        end
        local top = mirage:GetModelCFrame() + Vector3.new(0, 300, 0)
        SetStatus("Mirage OK, chua co Blue Gear -> ActivateAbility")
        TweenTo(top)
        if CaculateDistance(top) < 20 then
            pcall(function()
                LocalPlayer.CameraMaxZoomDistance = 0.5
                LocalPlayer.CameraMaxZoomDistance = 200
                workspace.CurrentCamera.CFrame = CFrame.new(
                    workspace.CurrentCamera.CFrame.Position,
                    Lighting:GetMoonDirection() + workspace.CurrentCamera.CFrame.Position
                )
            end)
            pcall(function()
                ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommE"):FireServer("ActivateAbility")
            end)
        end
    else
        SetStatus("Sai gio trong ngay -> Hop Mirage API")
        if Config["Hop Mirage"] then
            if not HopMirageByAPI() then
                SetStatus("Mirage API rong -> fallback Hop __ServerBrowser")
                Hop("Mirage API empty")
            end
        end
    end
end

if Config["Boost FPS"] then
    spawn(function()
        while task.wait(30) do pcall(function() setfpscap(Config["FPS"]) end) end
    end)
end
if Config["Black Screen"] then
    pcall(function() StarterPlayer:FindFirstChild("PlayerScripts") end)
    spawn(function()
        local gui = game:GetService("CoreGui")
        local players = LocalPlayer:FindFirstChild("PlayerGui")
        if players then
            pcall(function()
                local m = players:FindFirstChild("Main")
                if m then m.Enabled = false end
            end)
        end
    end)
end

pcall(MakeUI)

local _lastUiRefresh = 0

local function _UIUpdateTickInner()
    local now = os.time()
    if now - _lastUiRefresh < 1 then return end
    _lastUiRefresh = now
    if not _statusLabel then return end
    _seaLabel.Text     = "Sea: " .. tostring(Sea)
    do
        local raceName = tostring(ConChoChisiti36.PlayerData.Race or "?")
        local raceV3 = IsCurrentRaceV3()
        _raceLabel.Text = "Race V3: " .. (raceV3 and "YES" or "NO") .. " | Race: " .. raceName
    end
    _mirrorLabel.Text  = "Mirror Fractal: "  .. (HasMirrorFractal() and "YES" or "NO")
    _valkLabel.Text    = "Valkyrie Helm: "   .. (HasValkyrieHelm()   and "YES" or "NO")
    do
        local mi = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("MysticIsland")
        if mi then
            local okd, dist = pcall(function()
                return math.floor(CaculateDistance(mi:GetModelCFrame()))
            end)
            _mirageLabel.Text = "Mirage Island: YES (" .. (okd and tostring(dist) or "?") .. " studs)"
        else
            _mirageLabel.Text = "Mirage Island: NO"
        end
    end
    local ok, door = pcall(function() return CommF_:InvokeServer("CheckTempleDoor") end)
    _doorLabel.Text    = "Temple Door: "     .. (ok and tostring(door) or "?")
    local ok2, prog = pcall(function() return CommF_:InvokeServer("RaceV4Progress", "Check") end)
    _progressLabel.Text = "RaceV4 Check: "   .. (ok2 and tostring(prog) or "?")
end

-- Ghi vao label o CoreGui/gethui can identity cao. Neu mot require
-- truoc do da ha identity thi day la cho no no ra loi, nen luon
-- raise identity + pcall: UI loi khong duoc lam chet main loop.
local function UIUpdateTick()
    local prev = RaiseIdentity()
    local ok, err = pcall(_UIUpdateTickInner)
    RestoreIdentity(prev)
    if not ok then
        warn("[UI] UIUpdateTick loi: " .. tostring(err))
    end
end

while task.wait(1) do
    if not Config["Enabled"] then
        SetStatus("Disabled"); task.wait(5); continue
    end
    pcall(function() RefreshPlayerData() end)
    pcall(function() RefreshInventory() end)
    RefreshSea()
    UIUpdateTick()

    if not EnsureSea3() then
        task.wait(5)
        continue
    end

    if IsTempleDoorOpened() then
        SetStatus("Temple Door da mo -> DONE")
        break
    end

    if not HasMirrorFractal() then
        SetStatus("Missing Mirror Fractal -> waiting")
        task.wait(3)
        continue
    end

    if not HasValkyrieHelm() then
        SetStatus("Missing Valkyrie Helm -> waiting")
        task.wait(3)
        continue
    end

    if not IsCurrentRaceV3() then
        SetStatus("Race chua V3 -> waiting (Auto UpRace da bo)")
        task.wait(3)
        continue
    end

    if not IsRaceV4ProgressReady() then
        local ok, err = pcall(DoRaceV4Progress)
        if not ok then
            DebugStatus("RaceV4Progress", err)
        end
        task.wait(3)
        continue
    end

    local ok, err = pcall(DoMirageBlueGear)
    if not ok then
        DebugStatus("MirageBlueGear", err)
    end
    task.wait(3)
end

end)()
