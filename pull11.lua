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
    ["Fetch Count"]        = 30,
}

-- API hop transplanted: newest-first, no shared blacklist/claim
LPH_NO_VIRTUALIZE(function()

local PlayerGui
local _statusLabel, _raceLabel, _seaLabel, _mirrorLabel, _valkLabel, _doorLabel, _progressLabel, _mirageLabel

local _lastStatus = ""

local function SetStatus(text)
    text = tostring(text or "")
    _lastStatus = text

    print("[PullLever] " .. text)

    if _statusLabel then
        _statusLabel.Text = "Status: " .. text
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
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterPlayer     = game:GetService("StarterPlayer")

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

local function RefreshInventory()
    local ok, list = pcall(function()
        return CommF_:InvokeServer("getInventory")
    end)
    ConChoChisiti36.Backpack = {}
    if ok and type(list) == "table" then
        for _, v in list do
            if type(v) == "table" and v.Name then
                ConChoChisiti36.Backpack[v.Name] = v
            end
        end
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
    if not Servers then return end
    local List = {}
    for JobId, v in Servers do
        table.insert(List, { JobId = JobId, Players = v.Count, Region = v.Region })
    end
    if #List == 0 then return end
    local data = List[math.random(1, #List)]
    pcall(function()
        ReplicatedStorage:FindFirstChild("__ServerBrowser"):InvokeServer("teleport", data.JobId)
    end)
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
-- MIRAGE API - FIXED VERSION
--
-- Query:
--   ...&key=mirage
--
-- Payload hien tai:
-- {
--   count = N,
--   items = {
--     "job id: ...; type: mirage; player: 4; placeid: ...",
--     ...
--   },
--   key = "island",
--   ok = true
-- }
--
-- Luu y:
--   URL key=mirage nhung response envelope key=island la BINH THUONG.
--   API: tren = cu, duoi = moi -> doc TU CUOI LEN DAU.
--
-- Ban nay CO Y KHONG co:
--   - shared blacklist file
--   - join_fail file
--   - claim file
--
-- Chi giu JoinedMirageJobs trong RAM cua rieng client de tranh lap JobId
-- trong cung mot session.
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

    -- Backward-compatible object schema.
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
        Players = tonumber(v.players or v.player or v.Players or v.Count) or 0,
        Type = tostring(v.type or v.Type or v.server_type or ""),
        Region = v.Region or v.region,
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
    -- Reverse => list[1] la Mirage moi nhat.
    for i = #source, 1, -1 do
        local one = NormalizeServerEntry(source[i])

        if one then
            local tp = tostring(one.Type or ""):lower()

            -- String schema hien tai co nhieu island type.
            -- CHI lay exact type=mirage.
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
        warn("[MirageAPI] API url rong")
        return {}, "url_empty"
    end

    local currentPlaceId = tonumber(game.PlaceId)

    if not forceRefresh
        and CachedMirageServers
        and CachedMiragePlaceId == currentPlaceId
        and os.time() - LastMirageApiFetch < 20
    then
        return CachedMirageServers, "cache"
    end

    SetStatus("Fetching Mirage API...")

    local ok, res = HttpRequest({
        Url = url,
        Method = "GET",
        Headers = {
            ["Accept"] = "application/json",
            ["User-Agent"] = "Roblox/WinInet",
        },
    })

    if not ok then
        warn("[MirageAPI] Request failed: " .. tostring(res))
        return {}, "request_failed"
    end

    local statusCode = tonumber(res.StatusCode or res.status_code or res.Status or 0)
    local body = res.Body or res.body or ""

    print(
        "[MirageAPI] Status="
        .. tostring(statusCode)
        .. " BodyLen="
        .. tostring(#body)
    )

    if statusCode ~= 0 and (statusCode < 200 or statusCode >= 300) then
        warn("[MirageAPI] Bad status: " .. tostring(statusCode))
        return {}, "http_" .. tostring(statusCode)
    end

    local data = JsonDecodeSafe(body)
    if not data then
        warn(
            "[MirageAPI] JSON decode failed. Body head: "
            .. tostring(body):sub(1, 300)
        )
        return {}, "json_decode_failed"
    end

    -- Query key=mirage nhung envelope key=island -> khong xem la loi.
    if data.key ~= nil then
        print("[MirageAPI] Response envelope key=" .. tostring(data.key))
    end

    local servers = ExtractServerList(data)

    if #servers > 0 then
        LastMirageApiFetch = os.time()
        CachedMiragePlaceId = currentPlaceId
        CachedMirageServers = servers
    else
        CachedMirageServers = nil
        CachedMiragePlaceId = nil
    end

    print(
        "[MirageAPI] Parsed "
        .. tostring(#servers)
        .. " Mirage server(s) | bottom->top | newest first"
    )

    SetStatus("Mirage API servers: " .. tostring(#servers))

    if #servers <= 0 then
        return {}, "parsed_empty"
    end

    return servers, "ok"
end

-- ============================================================
-- LOCAL-ONLY VISITED / TELEPORT STATE
-- KHONG ghi file, KHONG shared blacklist, KHONG shared claim.
-- ============================================================
local JoinedMirageJobs = {}

local PendingMirageJoinJobId = nil
local PendingMirageJoinAt = 0
local PendingMirageTeleportStarted = false

local MIRAGE_JOIN_PENDING_TIMEOUT = 6
local MIRAGE_JOIN_STARTED_TIMEOUT = 20

JoinJobIdByServerBrowser = function(jobId)
    if not jobId or tostring(jobId) == "" then
        return false, "invalid_job"
    end

    jobId = tostring(jobId)

    if jobId == tostring(game.JobId) then
        return false, "same_job"
    end

    local sb = ReplicatedStorage:FindFirstChild("__ServerBrowser")
    if not sb then
        warn("[ServerBrowser] Khong tim thay __ServerBrowser")
        return false, "browser_missing"
    end

    PendingMirageJoinJobId = jobId
    PendingMirageJoinAt = os.clock()
    PendingMirageTeleportStarted = false

    local ok, result = pcall(function()
        return sb:InvokeServer("teleport", jobId)
    end)

    if not ok then
        PendingMirageJoinJobId = nil
        PendingMirageJoinAt = 0
        PendingMirageTeleportStarted = false

        warn("[ServerBrowser] Join JobId loi: " .. tostring(result))
        return false, tostring(result)
    end

    print(
        "[ServerBrowser] Sent Mirage teleport | JobId="
        .. jobId
        .. " | Result="
        .. tostring(result)
    )

    return true, result
end

TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, message)
    if player ~= LocalPlayer then
        return
    end

    local pending = PendingMirageJoinJobId
    if not pending then
        return
    end

    -- Local-only visited: skip lai JobId nay trong session hien tai.
    JoinedMirageJobs[pending] = true

    PendingMirageJoinJobId = nil
    PendingMirageJoinAt = 0
    PendingMirageTeleportStarted = false

    CachedMirageServers = nil
    LastMirageApiFetch = 0

    warn(
        "[MirageAPI] TeleportInitFailed "
        .. tostring(teleportResult)
        .. " | "
        .. tostring(message or "")
        .. " | JobId="
        .. tostring(pending)
    )
end)

pcall(function()
    LocalPlayer.OnTeleport:Connect(function(state)
        if not PendingMirageJoinJobId then
            return
        end

        local stateText = tostring(state)

        if stateText:find("Started")
            or stateText:find("Waiting")
            or stateText:find("InProgress")
        then
            PendingMirageTeleportStarted = true

        elseif stateText:find("Failed") then
            local pending = PendingMirageJoinJobId
            JoinedMirageJobs[pending] = true

            PendingMirageJoinJobId = nil
            PendingMirageJoinAt = 0
            PendingMirageTeleportStarted = false

            CachedMirageServers = nil
            LastMirageApiFetch = 0
        end
    end)
end)

local function HopMirageByAPI()
    local cfg = getgenv().PullLeverConfig or {}

    if cfg["Use Mirage API"] == false then
        return false, "disabled"
    end

    -- Khong spam JobId moi neu teleport cu van dang pending.
    if PendingMirageJoinJobId then
        local elapsed = os.clock() - PendingMirageJoinAt
        local timeout =
            PendingMirageTeleportStarted
            and MIRAGE_JOIN_STARTED_TIMEOUT
            or MIRAGE_JOIN_PENDING_TIMEOUT

        if elapsed < timeout then
            SetStatus(
                (PendingMirageTeleportStarted
                    and "Teleport started, waiting... "
                    or "Waiting Mirage teleport ")
                .. string.format("%.1f", elapsed)
                .. "s | "
                .. tostring(PendingMirageJoinJobId):sub(1, 8)
            )
            return true, "teleport_pending"
        end

        -- Timeout local-only: bo JobId nay trong session nay, khong ghi blacklist.
        local stale = PendingMirageJoinJobId
        JoinedMirageJobs[stale] = true

        PendingMirageJoinJobId = nil
        PendingMirageJoinAt = 0
        PendingMirageTeleportStarted = false

        CachedMirageServers = nil
        LastMirageApiFetch = 0

        warn(
            "[MirageAPI] Pending timeout | JobId="
            .. tostring(stale)
        )
    end

    local servers, fetchReason = GetMirageServersFromAPI(false)

    if type(servers) ~= "table" or #servers <= 0 then
        SetStatus("Mirage API empty | " .. tostring(fetchReason))
        return false, fetchReason or "api_empty"
    end

    local currentPlaceId = tonumber(game.PlaceId)
    local maxPlayers = tonumber(cfg["Max Players"] or 11) or 11
    local avoidFull = cfg["Avoid Full Server"] ~= false
    local fetchCount =
        math.max(
            1,
            math.floor(tonumber(cfg["Fetch Count"]) or 30)
        )

    local candidates = {}
    local stats = {
        total = #servers,
        samePlace = 0,
        wrongPlace = 0,
        sameJob = 0,
        full = 0,
        visited = 0,
        usable = 0,
    }

    -- servers da newest-first do ExtractServerList reverse.
    for _, server in ipairs(servers) do
        local jobId = tostring(server.JobId or "")
        local placeId = tonumber(server.PlaceId)
        local players = tonumber(server.Players) or 0

        -- placeId nil van cho phep: __ServerBrowser teleport JobId trong place hien tai.
        local samePlace = (placeId == nil) or (placeId == currentPlaceId)
        local notSameJob = jobId ~= "" and jobId ~= tostring(game.JobId)
        local notVisited = not JoinedMirageJobs[jobId]
        local notFull = (not avoidFull) or players <= maxPlayers

        if samePlace then stats.samePlace += 1 else stats.wrongPlace += 1 end
        if not notSameJob then stats.sameJob += 1 end
        if not notFull then stats.full += 1 end
        if not notVisited then stats.visited += 1 end

        if samePlace
            and notSameJob
            and notVisited
            and notFull
        then
            candidates[#candidates + 1] = server
            stats.usable += 1

            if #candidates >= fetchCount then
                break
            end
        end
    end

    print(
        "[MirageAPI] Filter"
        .. " total=" .. tostring(stats.total)
        .. " samePlace=" .. tostring(stats.samePlace)
        .. " usable=" .. tostring(stats.usable)
        .. " full=" .. tostring(stats.full)
        .. " visited=" .. tostring(stats.visited)
        .. " wrongPlace=" .. tostring(stats.wrongPlace)
    )

    if #candidates == 0 then
        -- Refresh de lay cac item moi o cuoi API.
        CachedMirageServers = nil
        LastMirageApiFetch = 0

        SetStatus(
            "Mirage API no usable"
            .. " | full=" .. tostring(stats.full)
            .. " visited=" .. tostring(stats.visited)
            .. " place=" .. tostring(stats.wrongPlace)
        )

        return false, "filtered_empty"
    end

    -- QUAN TRONG: candidates dang theo thu tu MOI -> CU.
    -- Khong random nua.
    local server = candidates[1]
    local jobId = tostring(server.JobId)

    SetStatus(
        "Join newest Mirage"
        .. " | Players=" .. tostring(server.Players)
        .. " | "
        .. jobId:sub(1, 8)
    )

    print(
        "[MirageAPI] Pick newest"
        .. " JobId=" .. jobId
        .. " PlaceId=" .. tostring(server.PlaceId)
        .. " Players=" .. tostring(server.Players)
        .. " Type=" .. tostring(server.Type or "?")
        .. " Candidates=" .. tostring(#candidates)
    )

    local joinStarted, joinResult =
        JoinJobIdByServerBrowser(jobId)

    if joinStarted then
        -- Khong mark visited ngay.
        -- Chi mark neu teleport fail/timeout; neu teleport thanh cong script roi session.
        return true, "teleport_started"
    end

    JoinedMirageJobs[jobId] = true
    CachedMirageServers = nil
    LastMirageApiFetch = 0

    return false, "invoke_failed:" .. tostring(joinResult)
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

local TweenConn, TweenInstance, TweenGhost, IsTweening = nil, nil, nil, false
local function NoclipLoop()
    if LocalPlayer.Character then
        for _, c in LocalPlayer.Character:GetDescendants() do
            if c:IsA("BasePart") and c.CanCollide and c.Name ~= "HumanoidRootPart" then
                c.CanCollide = false
            end
        end
    end
end
RunService.Stepped:Connect(NoclipLoop)

local function StopTween()
    if TweenInstance then pcall(function() TweenInstance:Cancel() end) TweenInstance = nil end
    if TweenConn then TweenConn:Disconnect() TweenConn = nil end
    if TweenGhost then pcall(function() TweenGhost:Destroy() end) TweenGhost = nil end
    IsTweening = false
end

function TweenTo(Position)

    if not Character or not Character:FindFirstChild("Humanoid")
        or Character.Humanoid.Health <= 0 or not HumanoidRootPart then
        StopTween()
        return
    end

    if Position == false then
        StopTween()
        return
    end
    if not Position then return end

    Position = typeof(Position) ~= "CFrame" and ConvertTo(CFrame, Position) or Position
    if typeof(Position) == "CFrame" then
        local p = Position.p
        Position = CFrame.new(p.X, math.max(p.Y, 5), p.Z)
    end

    local root = HumanoidRootPart
    local dist = (Position.Position - root.Position).Magnitude

    if dist <= 200 then
        StopTween()
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        root.CFrame = Position
        return
    end

    if IsTweening then return end
    IsTweening = true

    local ghost = Instance.new("Part")
    ghost.Name = "TweenGhost"
    ghost.Transparency = 1
    ghost.Anchored = true
    ghost.CanCollide = false
    ghost.Size = Vector3.new(4, 4, 4)
    ghost.CFrame = root.CFrame
    ghost.Parent = workspace
    TweenGhost = ghost

    TweenInstance = TweenService:Create(
        ghost,
        TweenInfo.new(dist / 330, Enum.EasingStyle.Linear),
        { CFrame = Position }
    )

    TweenConn = RunService.Heartbeat:Connect(function()
        if root and root.Parent and ghost and ghost.Parent then
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                root.CFrame = ghost.CFrame
            end)
        end
    end)

    TweenInstance.Completed:Connect(function()
        StopTween()
    end)

    TweenInstance:Play()
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
        if Config["Hop Mirage"] then
            SetStatus("Khong co Mirage -> Hop Mirage API")
            local apiStarted, apiReason = HopMirageByAPI()
            if not apiStarted then
                SetStatus("Mirage API fallback | " .. tostring(apiReason))
                Hop("Mirage API: " .. tostring(apiReason))
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
            local apiStarted, apiReason = HopMirageByAPI()
            if not apiStarted then
                SetStatus("Mirage API fallback | " .. tostring(apiReason))
                Hop("Mirage API: " .. tostring(apiReason))
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

local function UIUpdateTick()
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
