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
    ["Mirage API"]         = "https://baorph.pythonanywhere.com/token?api_key=baorapi&token=LH8UzJvtTZfmndW1&key=mirage",
    ["Avoid Full Server"]  = true,
    ["Max Players"]        = 11,

    -- Lay DUNG 5 server Mirage usable MOI NHAT; thu JobId cach nhau 2 giay
    ["Fetch Count"]        = 5,
}

-- PullLever V5.3 - __ServerBrowser ONLY | 5 newest / 2s | anti-rubberband | Completed-pull
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

-- Endpoint thuc te duoc goi bang key=mirage.
-- API envelope hien tai van co the tra data.key == "island"; day la binh thuong.
-- Khong rewrite URL dua theo data.key.
Config["Avoid Full Server"] = Config["Avoid Full Server"] ~= false
Config["Max Players"]       = Config["Max Players"] or 11
Config["Fetch Count"]       = 5
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
local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterPlayer     = game:GetService("StarterPlayer")

local LocalPlayer = Players.LocalPlayer
local Character, Humanoid, HumanoidRootPart

-- ============================================================
-- MIRAGE LOCAL STATE ONLY
--
-- JOIN JOBID CHI DUNG:
--   ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", JobId)
--
-- KHONG TeleportService.
-- KHONG shared blacklist / claim / join_fail file.
-- JoinedMirageJobs chi ton tai trong RAM cua session hien tai de
-- khong lap lai ngay JobId vua thu that bai.
-- ============================================================
local JoinedMirageJobs = {}

local function FindMirageIsland()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("MysticIsland") or nil
end

local function GetServerBrowser()
    return ReplicatedStorage:FindFirstChild("__ServerBrowser")
end

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

-- ============================================================
-- CHARACTER BINDER
-- Chống race-condition sau respawn/hop:
-- callback Character cũ không được phép ghi đè Root/Humanoid của Character mới.
-- ============================================================
local CharacterGeneration = 0

local function BindCharacter(character)
    CharacterGeneration += 1
    local generation = CharacterGeneration

    Character = character
    Humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
    HumanoidRootPart = character and character:FindFirstChild("HumanoidRootPart") or nil

    if not character then
        return
    end

    task.spawn(function()
        local deadline = os.clock() + 20

        while os.clock() < deadline
            and generation == CharacterGeneration
            and LocalPlayer.Character == character
        do
            local hum = character:FindFirstChildOfClass("Humanoid")
            local root = character:FindFirstChild("HumanoidRootPart")

            if hum and root then
                if generation == CharacterGeneration
                    and LocalPlayer.Character == character
                then
                    Character = character
                    Humanoid = hum
                    HumanoidRootPart = root
                end
                return
            end

            task.wait(0.1)
        end
    end)
end

local function RefreshCharacter()
    local current = LocalPlayer.Character

    if current ~= Character then
        BindCharacter(current)
    elseif current then
        Humanoid = current:FindFirstChildOfClass("Humanoid")
        HumanoidRootPart = current:FindFirstChild("HumanoidRootPart")
    end

    return Character, Humanoid, HumanoidRootPart
end

SetStatus("Waiting character...")
while true do
    RefreshCharacter()

    if Character
        and Character.Parent
        and Humanoid
        and HumanoidRootPart
        and Humanoid.Health > 0
    then
        break
    end

    task.wait(0.15)
end
SetStatus("Character ready")

LocalPlayer.CharacterAdded:Connect(function(character)
    BindCharacter(character)
end)

LocalPlayer.CharacterRemoving:Connect(function(character)
    if Character == character then
        CharacterGeneration += 1
        Character = nil
        Humanoid = nil
        HumanoidRootPart = nil
    end
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

local CachedServers, LastServersDataPulled

local function GetServers()
    if LastServersDataPulled
        and CachedServers
        and os.time() - LastServersDataPulled < 15
    then
        return CachedServers
    end

    local browser = ReplicatedStorage:FindFirstChild("__ServerBrowser")
    if not browser then
        warn("[ServerBrowser] __ServerBrowser missing")
        return nil
    end

    for i = 1, 100 do
        local ok, data = pcall(function()
            return browser:InvokeServer(i)
        end)

        if ok and IfTableHaveIndex(data) then
            CachedServers = data
            LastServersDataPulled = os.time()
            return data
        end

        task.wait()
    end

    return nil
end

local function Hop(Reason)
    print("[PullLever] Fallback Hop: " .. tostring(Reason))

    local Servers = GetServers()
    if not Servers then
        SetStatus("Fallback ServerBrowser empty")
        return false
    end

    local maxPlayers = tonumber(Config["Max Players"] or 11) or 11
    local avoidFull = Config["Avoid Full Server"] ~= false
    local List = {}

    for JobId, v in Servers do
        local players = tonumber(v and v.Count) or 0
        local notSame = tostring(JobId) ~= tostring(game.JobId)
        local notFull = (not avoidFull) or players <= maxPlayers

        if notSame and notFull then
            table.insert(List, {
                JobId = JobId,
                Players = players,
                Region = v and v.Region,
            })
        end
    end

    if #List == 0 then
        SetStatus("Fallback no usable server")
        return false
    end

    local data = List[math.random(1, #List)]
    local browser = ReplicatedStorage:FindFirstChild("__ServerBrowser")

    if not browser then
        return false
    end

    local ok, err = pcall(function()
        browser:InvokeServer("teleport", data.JobId)
    end)

    if not ok then
        warn("[ServerBrowser] Fallback teleport failed: " .. tostring(err))
        return false
    end

    return true
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
-- MIRAGE API (baorph): query key=mirage, envelope key=island
--
-- Vi du:
-- {
--   "api_url": "https://baorph.pythonanywhere.com/token",
--   "count": 29,
--   "items": [
--     "job id: <GUID>; type: mirage; player: 4; placeid: 100117331123089",
--     ...
--   ],
--   "key": "island",
--   "ok": true
-- }
--
-- QUAN TRONG:
-- API sap xep DU LIEU CU O TREN, MOI O DUOI.
-- Vi vay ExtractServerList() doc items TU CUOI LEN DAU.
-- list[1] = server moi nhat.
--
-- Query URL dung key=mirage, nhung payload co the tron nhieu type:
--   mirage / mysticisland / prehistoricisland
-- Nen loc CHINH XAC Type == "mirage" trong items.
-- ============================================================
local function NormalizeServerEntry(v)
    if type(v) == "string" then
        local jobId = v:match("[Jj][Oo][Bb]%s*[Ii][Dd]%s*:%s*([%x%-]+)")
        local serverType = v:match("[Tt][Yy][Pp][Ee]%s*:%s*([^;]+)")
        local players = tonumber(v:match("[Pp][Ll][Aa][Yy][Ee][Rr]%s*:%s*(%d+)")) or 0
        local placeId = tonumber(v:match("[Pp][Ll][Aa][Cc][Ee][Ii][Dd]%s*:%s*(%d+)"))

        if not jobId or jobId == "" then
            return nil
        end

        if serverType then
            serverType = tostring(serverType):match("^%s*(.-)%s*$")
        end

        return {
            JobId = jobId,
            PlaceId = placeId,
            Players = players,
            Type = serverType,
            Raw = v,
        }
    end

    -- Fallback object schema cu.
    if type(v) ~= "table" then
        return nil
    end

    local jobId =
        v.raw_job_id
        or v.job_id
        or v.jobid
        or v.JobId
        or v.id

    if not jobId or tostring(jobId) == "" then
        return nil
    end

    return {
        JobId = tostring(jobId),
        PlaceId = tonumber(v.place_id or v.placeid or v.PlaceId),
        Players = tonumber(v.players or v.player or v.Players) or 0,
        Type = tostring(v.type or v.Type or v.server_type or ""),
        Raw = v,
    }
end

local function ExtractServerList(data)
    local list = {}

    if type(data) ~= "table" then
        return list
    end

    if data.ok == false then
        warn("[MirageAPI] API returned ok=false")
        return list
    end

    local source = data.items or data.data or data.servers
    if type(source) ~= "table" then
        return list
    end

    -- API: tren = cu, duoi = moi.
    -- Doc nguoc de uu tien server moi nhat.
    for i = #source, 1, -1 do
        local one = NormalizeServerEntry(source[i])

        if one then
            local tp = tostring(one.Type or ""):lower()

            -- Payload key=mirage van co the chua mysticisland/prehistoricisland.
            -- Schema string hien tai: CHI lay type=mirage.
            -- Schema object cu khong co Type: van cho phep de backward-compatible.
            if type(one.Raw) == "string" then
                if tp == "mirage" then
                    list[#list + 1] = one
                end
            elseif tp == "" or tp == "mirage" then
                list[#list + 1] = one
            end
        end
    end

    return list
end

local LastMirageApiFetch = 0
local CachedMirageServers = nil
local CachedMiragePlaceId = nil

local function GetMirageServersFromAPI(forceRefresh)
    local cfg = getgenv().PullLeverConfig or {}
    local url = tostring(cfg["Mirage API"] or "")

    if url == "" then
        warn("[MirageAPI] Mirage API url rong -> bo qua")
        return {}, "url_empty"
    end

    local currentPlaceId = tonumber(game.PlaceId)

    if CachedMirageServers
        and CachedMiragePlaceId == currentPlaceId
        and os.time() - LastMirageApiFetch < 20 then
        return CachedMirageServers, "cache"
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
        warn("[MirageAPI] Request failed: " .. tostring(res))
        return {}, "request_failed"
    end

    local statusCode = tonumber(res.StatusCode or res.status_code or res.Status or 0)
    local body = res.Body or res.body or ""

    print("[MirageAPI] Status=" .. tostring(statusCode) .. " BodyLen=" .. tostring(#body))

    if statusCode ~= 0 and (statusCode < 200 or statusCode >= 300) then
        warn("[MirageAPI] Bad status: " .. tostring(statusCode))
        return {}, "http_" .. tostring(statusCode)
    end

    local data = JsonDecodeSafe(body)
    if not data then
        warn("[MirageAPI] JSON decode failed. Body head: " .. tostring(body):sub(1, 300))
        return {}, "json_decode_failed"
    end

    -- Luu y: URL query dang la key=mirage, nhung API envelope hien tai
    -- tra data.key = "island". Khong dung data.key de suy ra query selector.
    local responseKey = tostring(data.key or "")
    if responseKey ~= "" then
        print("[MirageAPI] Response envelope key=" .. responseKey)
    end

    local servers = ExtractServerList(data)

    if #servers > 0 then
        LastMirageApiFetch = os.time()
        CachedMiragePlaceId = currentPlaceId
        CachedMirageServers = servers
    end

    print(
        "[MirageAPI] Parsed " .. tostring(#servers)
        .. " server(s) | key=" .. tostring(data.key)
        .. " | bottom->top | newest first"
    )
    SetStatus("Mirage API servers: " .. tostring(#servers))

    if #servers <= 0 then
        return {}, "parsed_empty"
    end

    return servers, "ok"
end

JoinJobIdByServerBrowser = function(jobId)
    if not jobId or tostring(jobId) == "" then
        return false, "invalid_job"
    end

    jobId = tostring(jobId)

    if jobId == tostring(game.JobId) then
        return false, "same_job"
    end

    local browser = GetServerBrowser()
    if not browser then
        warn("[ServerBrowser] Khong tim thay __ServerBrowser")
        return false, "browser_missing"
    end

    -- "teleport" o day CHI la action name cua __ServerBrowser remote.
    -- Khong lien quan TeleportService.
    local ok, result = pcall(function()
        return browser:InvokeServer("teleport", jobId)
    end)

    if not ok then
        warn(
            "[ServerBrowser] Join JobId loi | "
            .. jobId
            .. " | "
            .. tostring(result)
        )
        return false, tostring(result)
    end

    print(
        "[ServerBrowser] SENT JobId="
        .. jobId
        .. " | result="
        .. tostring(result)
    )

    return true, result
end

-- Lay toi 30 server Mirage moi nhat theo thu tu API TU DUOI LEN TREN.
-- Moi thoi diem chi co 1 teleport pending; khong spam nhieu JobId lien tiep.
local MIRAGE_BATCH_SIZE = 5
local MIRAGE_JOB_DELAY = 2.0

local function HopMirageByAPI()
    local cfg = getgenv().PullLeverConfig or {}

    if cfg["Use Mirage API"] == false then
        return false, "disabled"
    end

    -- Neu server hien tai da co Mirage: TUYET DOI KHONG HOP.
    if FindMirageIsland() then
        return false, "mirage_present"
    end

    -- Chay lien tuc theo batch:
    -- fetch API -> 5 newest usable -> #1..#5 cach 2s
    -- -> het 5 thi fetch API moi ngay.
    while cfg["Use Mirage API"] ~= false do
        if FindMirageIsland() then
            return false, "mirage_present"
        end

        CachedMirageServers = nil
        CachedMiragePlaceId = nil
        LastMirageApiFetch = 0

        local servers, fetchReason = GetMirageServersFromAPI(true)

        if type(servers) ~= "table" or #servers <= 0 then
            SetStatus(
                "Mirage API empty | "
                .. tostring(fetchReason)
                .. " -> refetch"
            )
            task.wait(1)
            continue
        end

        -- API request co the mat thoi gian; check lai Mirage truoc khi join.
        if FindMirageIsland() then
            return false, "mirage_present"
        end

        local currentPlaceId = tonumber(game.PlaceId)
        local maxPlayers = tonumber(cfg["Max Players"] or 11) or 11
        local avoidFull = cfg["Avoid Full Server"] ~= false

        local candidates = {}
        local stats = {
            total = #servers,
            full = 0,
            wrongPlace = 0,
            sameJob = 0,
            visited = 0,
        }

        -- ExtractServerList da reverse:
        -- index 1 = item DUOI CUNG API = MOI NHAT.
        for _, server in ipairs(servers) do
            local jobId = tostring(server.JobId or "")
            local placeId = tonumber(server.PlaceId)
            local players = tonumber(server.Players) or 0

            local samePlace =
                (placeId == nil)
                or (placeId == currentPlaceId)

            local notSameJob =
                jobId ~= ""
                and jobId ~= tostring(game.JobId)

            local notFull =
                (not avoidFull)
                or players <= maxPlayers

            local notVisited =
                not JoinedMirageJobs[jobId]

            if not samePlace then stats.wrongPlace += 1 end
            if not notSameJob then stats.sameJob += 1 end
            if not notFull then stats.full += 1 end
            if not notVisited then stats.visited += 1 end

            if samePlace
                and notSameJob
                and notFull
                and notVisited
            then
                candidates[#candidates + 1] = server

                if #candidates >= MIRAGE_BATCH_SIZE then
                    break
                end
            end
        end

        print(
            "[ServerBrowser][MirageAPI]"
            .. " total=" .. tostring(stats.total)
            .. " newestUsable=" .. tostring(#candidates)
            .. " full=" .. tostring(stats.full)
            .. " visited=" .. tostring(stats.visited)
            .. " wrongPlace=" .. tostring(stats.wrongPlace)
        )

        if #candidates == 0 then
            -- API co data nhung tat ca candidate hien tai da thu/khong usable.
            -- Nghi ngan roi fetch lai API; KHONG random fallback server.
            SetStatus(
                "Mirage API no new usable -> refetch"
                .. " | full=" .. tostring(stats.full)
                .. " visited=" .. tostring(stats.visited)
            )
            task.wait(1)
            continue
        end

        -- ====================================================
        -- DUNG 5 NEWEST USABLE:
        -- #1 -> 2s -> #2 -> 2s -> ... -> #5.
        -- Join CHI qua __ServerBrowser.
        -- ====================================================
        for i, server in ipairs(candidates) do
            if FindMirageIsland() then
                SetStatus("Mirage vua replicate -> dung ServerBrowser")
                return false, "mirage_present"
            end

            local jobId = tostring(server.JobId or "")

            if jobId ~= "" then
                SetStatus(
                    "ServerBrowser "
                    .. tostring(i)
                    .. "/"
                    .. tostring(#candidates)
                    .. " | Players="
                    .. tostring(server.Players)
                    .. " | "
                    .. jobId:sub(1, 8)
                    .. " | next=2s"
                )

                print(
                    "[ServerBrowser] TRY "
                    .. tostring(i)
                    .. "/"
                    .. tostring(#candidates)
                    .. " | JobId="
                    .. jobId
                    .. " | Players="
                    .. tostring(server.Players)
                    .. " | Type="
                    .. tostring(server.Type or "?")
                )

                local ok, result =
                    JoinJobIdByServerBrowser(jobId)

                -- Neu Invoke loi thi bo qua JobId nay.
                -- Neu Invoke accepted nhung client chua roi session sau 2s,
                -- script se tiep tuc JobId tiep theo dung yeu cau.
                if not ok then
                    warn(
                        "[ServerBrowser] FAILED "
                        .. jobId
                        .. " | "
                        .. tostring(result)
                    )
                end

                task.wait(MIRAGE_JOB_DELAY)

                -- Neu code con chay o session nay thi coi JobId vua thu la da dung.
                JoinedMirageJobs[jobId] = true
            end
        end

        -- Het 5 -> force fetch 5 newest usable MOI ngay trong ham nay.
        CachedMirageServers = nil
        CachedMiragePlaceId = nil
        LastMirageApiFetch = 0

        SetStatus(
            "Het "
            .. tostring(#candidates)
            .. " ServerBrowser JobId -> fetch 5 moi"
        )

        task.wait(0.15)
    end

    return false, "disabled"
end

local function ConvertTo(Type, Data)
    if typeof(Data) ~= "table" then
        return Type.new(Data.x, Data.y, Data.z)
    end
    return Type.new(Data.x, Data.y, Data.z)
end

local function CaculateDistance(Origin, Destination)
    RefreshCharacter()

    if not HumanoidRootPart or not HumanoidRootPart.Parent then
        return math.huge
    end

    Origin = Origin or HumanoidRootPart.CFrame
    Destination = Destination or HumanoidRootPart.CFrame

    local a =
        typeof(Origin) == "CFrame" and Origin.Position
        or (typeof(Origin) == "Vector3" and Origin or ConvertTo(Vector3, Origin))

    local b =
        typeof(Destination) == "CFrame" and Destination.Position
        or (typeof(Destination) == "Vector3" and Destination or ConvertTo(Vector3, Destination))

    return (a - b).Magnitude
end

-- ============================================================
-- TWEEN MODULE (BAN MOI - anti-cheat movement)
--
-- Game da chan 2 kieu cu:
--   1) ghost/proxy part + ghi root.CFrame moi Heartbeat
--   2) snap root.CFrame truc tiep khi dist <= 200
-- Ban nay tween THANG HumanoidRootPart bang TweenService, doi
-- character stable truoc khi chay, va tu phat hien server keo nguoc
-- (jump >= 45 studs) de tween lai.
-- ============================================================
-- SPEED phai khai bao TRUOC ham Tween ben duoi, vi Tween() doc bien nay.
-- Neu de sau, `local` chua ton tai luc dinh nghia ham -> Lua bat vao global nil
-- -> tween chay 300 thay vi 250.
local SPEED = 250

local TweenInstance = nil
local TweenSerial = 0
local TweenGoal = nil
local TweenObject = nil

local function getCFrame(v)
    if not v then return nil end
    if typeof(v) == "CFrame" then return v end
    if typeof(v) == "Vector3" then return CFrame.new(v) end
    if typeof(v) ~= "Instance" then return nil end
    if v:IsA("BasePart") then return v.CFrame end
    if v:IsA("Model") then
        local ok, cf = pcall(function() return v:GetPivot() end)
        if ok and cf then return cf end
        local root = v.PrimaryPart or v:FindFirstChild("HumanoidRootPart")
        if root then return root.CFrame end
    end
    if v:IsA("CFrameValue") then return v.Value end
    if v:IsA("Vector3Value") then return CFrame.new(v.Value) end
    return nil
end

local function CancelTween()
    TweenSerial += 1
    TweenGoal = nil
    TweenObject = nil
    if TweenInstance then
        pcall(function() TweenInstance:Cancel() end)
        TweenInstance = nil
    end
end

local function MovementLocked(char)
    if not char then return true end
    if char:FindFirstChild("AntiMover") then return true end
    local ok, tagged = pcall(function()
        return CollectionService:HasTag(char, "Teleporting")
    end)
    if ok and tagged then return true end
    return false
end

-- Không quét GetDescendants mỗi frame nữa.
-- Với nhiều client, Stepped + GetDescendants gây CPU thừa rất lớn.
local function ApplyNoclip()
    local char = LocalPlayer.Character
    if not char then return end

    for _, c in char:GetDescendants() do
        if c:IsA("BasePart")
            and c.CanCollide
            and c.Name ~= "HumanoidRootPart"
        then
            c.CanCollide = false
        end
    end
end

task.spawn(function()
    while task.wait(0.25) do
        pcall(ApplyNoclip)
    end
end)

local function WaitMovementStable(serial, targetObject, timeout)
    local deadline = tick() + (timeout or 2.5)
    local lastPos = targetObject and targetObject.Position
    local stableFor = 0
    while serial == TweenSerial and targetObject and targetObject.Parent and tick() < deadline do
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then
            return false
        end
        -- Tween bi cancel giua khong trung = nhan vat roi tu do. Roi thi moi tick
        -- di ~10 studs, khong bao gio thoa "<= 2 studs" -> cho het timeout va roi
        -- suot ca 2-4s. Triet velocity de dung han roi stable ngay.
        pcall(function()
            targetObject.AssemblyLinearVelocity = Vector3.zero
        end)
        if MovementLocked(char) then
            stableFor = 0
        else
            local pos = targetObject.Position
            if lastPos and (pos - lastPos).Magnitude <= 2 then
                stableFor += 0.05
                if stableFor >= 0.2 then
                    return true
                end
            else
                stableFor = 0
            end
            lastPos = pos
        end
        task.wait(0.05)
    end
    return serial == TweenSerial and targetObject and targetObject.Parent
        and not MovementLocked(LocalPlayer.Character)
end

local function PlayTween(serial, targetObject, targetCFrame, speed)
    if serial ~= TweenSerial or not targetObject or not targetObject.Parent then
        return false
    end
    local distance = (targetObject.Position - targetCFrame.Position).Magnitude
    if distance <= 2 then
        TweenInstance = nil
        return true
    end
    local duration = math.max(distance / speed, 0.05)
    local tw = TweenService:Create(
        targetObject,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        {CFrame = targetCFrame}
    )
    TweenInstance = tw
    tw:Play()
    return true
end

local function Tween(targetCFrame, targetObject)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if targetCFrame == false then
        CancelTween()
        return
    end
    if not hum or hum.Health <= 0 or not root then
        CancelTween()
        return
    end
    targetCFrame = getCFrame(targetCFrame)
    if not targetCFrame then
        return
    end
    targetObject = targetObject or root
    if not targetObject or not targetObject.Parent then
        return
    end
    if targetObject == root then
        hum.Sit = false
    end
    local sameGoal = TweenGoal
        and TweenObject == targetObject
        and (TweenGoal.Position - targetCFrame.Position).Magnitude <= 3
    if sameGoal and TweenInstance and TweenInstance.PlaybackState == Enum.PlaybackState.Playing then
        return
    end
    CancelTween()
    local serial = TweenSerial
    TweenGoal = targetCFrame
    TweenObject = targetObject
    local speed = tonumber(getgenv().tweenspeed) or tonumber(SPEED) or 300
    task.spawn(function()
        -- DI THANG: khong cho stable truoc khi chay (cai do lam tre 2-3s moi luot).
        -- Chi cho khi dang bi lock cung (AntiMover / tag Teleporting), vi luc do
        -- ghi CFrame se danh nhau voi teleport cua game.
        if MovementLocked(char) then
            if not WaitMovementStable(serial, targetObject, 1) then
                return
            end
        end
        if serial ~= TweenSerial then
            return
        end

        PlayTween(serial, targetObject, targetCFrame, speed)

        -- Vong nay CHI giam sat, KHONG cancel giua duong nua.
        -- Ban truoc cancel khi thay nhay >= 45 studs/tick, nhung 1 tick that co the
        -- hitch len 0.2s -> 250*0.2 = 50 studs -> tuong la server keo nguoc ->
        -- cancel -> roi tu do -> tween lai: dung cai "bay 1 ti roi rot" ban gap.
        -- Server co keo nguoc that thi TweenService van ghi tiep theo duong noi suy
        -- nen no tu keo lai, khong can can thiep.
        while serial == TweenSerial and targetObject.Parent do
            task.wait(0.1)

            char = LocalPlayer.Character
            hum = char and char:FindFirstChild("Humanoid")
            if not hum or hum.Health <= 0 then
                CancelTween()
                return
            end

            -- Den dich.
            if (targetObject.Position - targetCFrame.Position).Magnitude <= 3 then
                if TweenInstance then
                    pcall(function() TweenInstance:Cancel() end)
                end
                TweenInstance = nil
                return
            end

            -- Tween chet giua duong (het duration ma chua toi, hoac vua bi lock roi
            -- nha ra) -> phat lai NGAY tu vi tri hien tai, khong cho stable.
            if not MovementLocked(char)
                and (not TweenInstance
                    or TweenInstance.PlaybackState ~= Enum.PlaybackState.Playing) then
                PlayTween(serial, targetObject, targetCFrame, speed)
            end
        end
    end)
end

local function IsTweening()
    return TweenInstance ~= nil and TweenInstance.PlaybackState == Enum.PlaybackState.Playing
end

-- Dich ma luong hold cua Mirage dang giu (xem MIRAGE MOVEMENT ben duoi).
-- Khai bao o day de TweenTo() xoa duoc no: neu khong, di chuyen cua Race
-- se bi luong hold keo nguoc ve Mirage moi 0.3s.
local MirageHoldTarget = nil

-- TweenTo() giu nguyen chu ky cu (DoRaceV4Progress dang goi):
--   TweenTo(false) -> cancel
--   Position dang {x,y,z} -> ConvertTo
--   clamp Y >= 5 nhu ban cu
-- Khac ban cu: KHONG con snap root.CFrame khi dist <= 200, vi snap chinh la
-- cai game dang chan. Main loop goi lai moi 3s nen van hoi tu ve dich.
function TweenTo(Position)
    MirageHoldTarget = nil

    if Position == false then
        CancelTween()
        return
    end
    if not Position then return end

    Position = typeof(Position) ~= "CFrame" and ConvertTo(CFrame, Position) or Position
    if typeof(Position) == "CFrame" then
        local p = Position.Position
        Position = CFrame.new(p.X, math.max(p.Y, 5), p.Z)
    end

    Tween(Position)
end


-- ============================================================
-- MIRAGE MOVEMENT (V5.4) - dung Tween() moi
--
-- Controller proxy + Heartbeat cu da bo: ghi root.CFrame moi frame
-- la dung cai game dang chan, va no se danh nhau voi TweenService
-- cua Tween() moi (ca hai cung ghi root.CFrame).
--
-- Tween() moi da tu lo phan chong keo nguoc:
--   - doi character stable truoc khi chay
--   - phat hien nhay >= 45 studs -> cancel, cho stable, tween lai
-- Nen o day chi con lop mong goi Tween(), giu nguyen ten ham cu
-- de cac cho goi khong phai sua.
-- ============================================================
local MIRAGE_TWEEN_SPEED = SPEED
local MIRAGE_SNAP_DISTANCE = 6

-- Giu ten MirageMovement.cancel() vi 3 cho trong main loop dang goi.
-- (MirageHoldTarget khai bao o tren, ngay truoc TweenTo.)
local MirageMovement = {}

function MirageMovement.cancel()
    MirageHoldTarget = nil
    CancelTween()
end

-- Ban cu HOLD bang cach ghi root.CFrame moi Heartbeat. Bo cach do (bi chan),
-- thay bang: cu 0.3s kiem tra troi khoi dich thi Tween() lai.
-- Can thiet vi target Mirage cao +300 studs, khong giu thi roi xuong va
-- check CaculateDistance(top) < 20 trong DoMirageBlueGear se khong bao gio dung.
task.spawn(function()
    while task.wait(0.3) do
        local target = MirageHoldTarget
        if target then
            local root = HumanoidRootPart
            if root and root.Parent
                and (root.Position - target.Position).Magnitude > MIRAGE_SNAP_DISTANCE then
                pcall(Tween, target)
            end
        end
    end
end)

function MirageMovement.moveTo(targetCFrame)
    RefreshCharacter()

    local root = HumanoidRootPart
    local hum = Humanoid

    if not root
        or not root.Parent
        or not hum
        or hum.Health <= 0
        or typeof(targetCFrame) ~= "CFrame"
    then
        MirageMovement.cancel()
        return false
    end

    MirageHoldTarget = targetCFrame

    -- Da o dich: khong tween nua, va KHONG snap CFrame (snap la cai bi chan).
    local dist = (root.Position - targetCFrame.Position).Magnitude
    if dist <= MIRAGE_SNAP_DISTANCE then
        return true
    end

    -- Tween() tu bo qua neu goal cu van dang chay (sameGoal check),
    -- nen goi lai moi tick trong main loop la an toan.
    Tween(targetCFrame)
    return false
end

-- Heartbeat ghi root.CFrame moi frame da bo (xem comment o tren):
-- no vua bi game chan, vua danh nhau voi TweenService trong Tween().

local function TweenToMirage(targetCFrame)
    return MirageMovement.moveTo(targetCFrame)
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

-- ============================================================
-- COMPLETED PULL MARKER
-- Khi CheckTempleDoor == true:
--   <PlayerName>.txt = Completed-pull
-- ============================================================
local function WriteCompletedPull()
    local outputFile = tostring(LocalPlayer.Name) .. ".txt"
    local content = "Completed-pull"

    if type(writefile) ~= "function" then
        warn("[PullLever] writefile unavailable -> cannot create " .. outputFile)
        return false
    end

    local ok, err = pcall(function()
        writefile(outputFile, content)
    end)

    if not ok then
        warn("[PullLever] Completed-pull write failed: " .. tostring(err))
        return false
    end

    local verified = true

    if type(isfile) == "function" then
        local vok, exists = pcall(isfile, outputFile)
        if vok and exists ~= true then
            verified = false
        end
    end

    if verified and type(readfile) == "function" then
        local rok, body = pcall(readfile, outputFile)
        if rok and tostring(body or "") ~= content then
            verified = false
        end
    end

    if verified then
        print(
            "[PullLever] CREATED "
            .. outputFile
            .. " = "
            .. content
        )
        return true
    end

    warn("[PullLever] Completed-pull verify failed: " .. outputFile)
    return false
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

-- Cho tween den dich thuc su.
-- Ban tween cu snap root.CFrame khi dist <= 200 -> goi TweenTo() xong la coi nhu
-- da den, ban remote ngay dong sau van dung vi tri. Ban moi bo snap (snap la cai
-- game chan) nen tween can thoi gian that -> phai cho, khong thi Check/TeleportBack
-- ban ra luc con dang bay giua duong.
-- Co timeout: khong den duoc thi van chay tiep nhu ban cu, khong treo main loop.
local function WaitArrive(target, timeout, tolerance)
    timeout = timeout or 15
    tolerance = tolerance or 25

    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        if CaculateDistance(target) <= tolerance then
            return true
        end
        task.wait(0.15)
    end

    return false
end

local function DoRaceV4Progress()
    SetStatus("Temple: dang chay RaceV4Progress")

    local gate = CFrame.new(3032, 2280, -7325)
    TweenTo(gate)
    WaitArrive(gate, 20, 25)

    if CaculateDistance(gate) < 30 then
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Begin") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Check") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Teleport") end)
        task.wait(2)

        -- Server vua teleport vao temple. Diem nay o trong temple nen thuong gan,
        -- ban cu snap tuc thi; ban moi phai cho tween xong roi moi TeleportBack.
        local inside = CFrame.new(28613, 14896, 106)
        TweenTo(inside)
        WaitArrive(inside, 15, 25)

        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Check") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "TeleportBack") end)
        task.wait(3)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Continue") end)
    end
end

local function DoMirageBlueGear()
    local mirage = FindMirageIsland()

    -- Replication settle:
    -- tranh vua vao server, UI/Map sap replicate ma da gui API teleport mat.
    if not mirage then
        for _ = 1, 10 do
            task.wait(0.1)
            mirage = FindMirageIsland()
            if mirage then
                break
            end
        end
    end

    if not mirage then
        MirageMovement.cancel()

        if Config["Hop Mirage"] then
            SetStatus("Khong co Mirage -> Hop Mirage API")

            local apiStarted, apiReason =
                HopMirageByAPI()

            -- Neu API guard phat hien Mirage vua replicate:
            -- KHONG fallback server hop; main loop se tween ngay tick tiep.
            if apiReason == "mirage_present" then
                SetStatus("Mirage vua spawn/replicate -> GIU SERVER")
                return
            end

            if not apiStarted and apiReason ~= "mirage_present" then
                SetStatus(
                    "Mirage API stopped | "
                    .. tostring(apiReason)
                )
            end
        else
            SetStatus("Khong co Mirage (Hop Mirage = false)")
        end

        return
    end

    -- ========================================================
    -- CO MIRAGE = TUYET DOI KHONG HOP SERVER.
    -- Luon di ra Mirage truoc.
    -- ========================================================
    local blue = GetBlueGear()

    if blue then
        SetStatus("Mirage YES + Blue Gear -> Tween")
        TweenToMirage(blue)
        return
    end

    local top =
        mirage:GetModelCFrame()
        + Vector3.new(0, 300, 0)

    SetStatus(
        "Mirage YES -> Tween ra island"
        .. " | speed="
        .. tostring(MIRAGE_TWEEN_SPEED)
    )
    TweenToMirage(top)

    if CaculateDistance(top) >= 20 then
        return
    end

    -- Da o tren Mirage.
    -- Gio sai thi DUNG TAI MIRAGE cho den dung gio, KHONG hop.
    local hour = math.floor(Lighting.ClockTime)

    if not (hour >= 12 or hour < 5) then
        SetStatus(
            "Da o Mirage -> doi dung gio | Clock="
            .. tostring(math.floor(Lighting.ClockTime))
        )
        return
    end

    -- Dung gio: quay camera ve moon + activate race ability.
    SetStatus("Mirage OK -> ActivateAbility")

    pcall(function()
        LocalPlayer.CameraMaxZoomDistance = 0.5
        LocalPlayer.CameraMaxZoomDistance = 200

        workspace.CurrentCamera.CFrame =
            CFrame.new(
                workspace.CurrentCamera.CFrame.Position,
                Lighting:GetMoonDirection()
                    + workspace.CurrentCamera.CFrame.Position
            )
    end)

    pcall(function()
        ReplicatedStorage
            :WaitForChild("Remotes")
            :WaitForChild("CommE")
            :FireServer("ActivateAbility")
    end)
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
        MirageMovement.cancel()
        local wrote = WriteCompletedPull()

        if wrote then
            SetStatus("Temple Door da mo -> Completed-pull")
        else
            SetStatus("Temple Door da mo -> DONE (marker write failed)")
        end

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
