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

    -- Đợi UI/game ổn định trước khi chọn team.
    ["Team Load Delay"]    = 7,

    -- Di chuyển nhẹ hơn để giảm lỗi bị server kéo ngược / security kick.
    ["Tween Speed"]               = 220,
    ["Direct Teleport Distance"]  = 25,
    ["Tween Update Interval"]     = 0.05,
    ["Tween Correction Limit"]    = 90,
    ["Tween Retry Cooldown"]      = 2,

    ["Use Mirage API"]     = true,
    ["Mirage API"]         = "http://fi12.bot-hosting.cloud:20112/api/name=mirage",
    ["Avoid Full Server"]  = true,
    ["Max Players"]        = 11,
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
Config["Boost FPS"]         = Config["Boost FPS"] ~= false
Config["FPS"]               = Config["FPS"] or 20
Config["Black Screen"]      = Config["Black Screen"] or false

Config["Team Load Delay"]           = math.max(0, tonumber(Config["Team Load Delay"]) or 7)
Config["Tween Speed"]               = math.max(80, tonumber(Config["Tween Speed"]) or 220)
Config["Direct Teleport Distance"]  = math.max(5, tonumber(Config["Direct Teleport Distance"]) or 25)
Config["Tween Update Interval"]     = math.max(0.03, tonumber(Config["Tween Update Interval"]) or 0.05)
Config["Tween Correction Limit"]    = math.max(40, tonumber(Config["Tween Correction Limit"]) or 90)
Config["Tween Retry Cooldown"]      = math.max(0, tonumber(Config["Tween Retry Cooldown"]) or 2)

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

local function WaitBeforeChooseTeam()
    if LocalPlayer.Team ~= nil then
        return
    end

    local delaySeconds = math.floor(tonumber(Config["Team Load Delay"]) or 7)
    for remaining = delaySeconds, 1, -1 do
        SetStatus("Waiting team UI: " .. tostring(remaining) .. "s")
        task.wait(1)

        if LocalPlayer.Team ~= nil then
            return
        end
    end

    -- Đợi thêm Main/ChooseTeam xuất hiện nhưng không treo vô hạn.
    local deadline = os.clock() + 15
    while LocalPlayer.Team == nil and os.clock() < deadline do
        local mainGui = LocalPlayer.PlayerGui and LocalPlayer.PlayerGui:FindFirstChild("Main")
        local chooseTeam = mainGui and mainGui:FindFirstChild("ChooseTeam")
        if chooseTeam then
            break
        end
        SetStatus("Waiting ChooseTeam UI...")
        task.wait(0.5)
    end
end

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

WaitBeforeChooseTeam()
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

local function NormalizeServerEntry(v)

    if type(v) == "string" then
        local s = v:gsub("^%s+", ""):gsub("%s+$", "")
        if s == "" then return nil end
        return {
            JobId   = s,
            PlaceId = nil,
            Players = 0,
            Region  = nil,
            Raw     = v,
        }
    end

    if type(v) ~= "table" then return nil end

    local jobId   = v.JobId or v.jobId or v.jobid or v.job_id or v.id
    local placeId = v.PlaceId or v.placeId or v.placeid or v.place_id or v.place
    local players = v.Players or v.players or v.player or v.Count or v.count or v.playerCount
    local region  = v.Region or v.region

    if type(players) == "string" then
        local n = tostring(players):match("^(%d+)")
        players = tonumber(n) or players
    end

    if not jobId then return nil end

    return {
        JobId   = tostring(jobId),
        PlaceId = tonumber(placeId),
        Players = tonumber(players) or 0,
        Region  = region,
        Raw     = v,
    }
end

local function ExtractServerList(data)
    local list = {}

    if type(data) == "string" then
        local one = NormalizeServerEntry(data)
        if one then table.insert(list, one) end
        return list
    end

    if type(data) ~= "table" then return list end

    local source = data.data or data.servers or data.result or data.results or data

    if type(source) == "string" then
        local one = NormalizeServerEntry(source)
        if one then table.insert(list, one) end
        return list
    end

    if type(source) ~= "table" then return list end

    if source.JobId or source.jobId or source.job_id or source.id then
        local one = NormalizeServerEntry(source)
        if one then table.insert(list, one) end
        return list
    end

    for _, v in pairs(source) do
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
        url = ""
    end
    local currentPlaceId = tonumber(game.PlaceId)

    if CachedMirageServers
        and CachedMiragePlaceId == currentPlaceId
        and os.time() - LastMirageApiFetch < 20 then
        return CachedMirageServers
    end

    print("[MirageAPI] GET " .. tostring(url))
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
        return {}
    end

    local statusCode = tonumber(res.StatusCode or res.status_code or res.Status or 0)
    local body = res.Body or res.body or ""

    print("[MirageAPI] Status=" .. tostring(statusCode) .. " BodyLen=" .. tostring(#body))

    if statusCode ~= 0 and (statusCode < 200 or statusCode >= 300) then
        warn("[MirageAPI] Bad status: " .. tostring(statusCode))
        return {}
    end

    local servers = {}

    local data = JsonDecodeSafe(body)
    if data then
        servers = ExtractServerList(data)
    else
        warn("[MirageAPI] JSON decode failed. Body head: " .. tostring(body):sub(1, 300))
    end

    if #servers == 0 then
        local seen = {}
        for guid in tostring(body):gmatch("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x") do
            if not seen[guid] then
                seen[guid] = true
                table.insert(servers, {
                    JobId   = guid,
                    PlaceId = nil,
                    Players = 0,
                })
            end
        end
        if #servers > 0 then
            warn("[MirageAPI] Fallback: trich " .. tostring(#servers) .. " JobId tho tu body")
        end
    end

    if #servers > 0 then
        LastMirageApiFetch = os.time()
        CachedMiragePlaceId = currentPlaceId
        CachedMirageServers = servers
    end

    print("[MirageAPI] Parsed " .. tostring(#servers) .. " server(s)")
    SetStatus("Mirage API servers: " .. tostring(#servers))
    return servers
end

local JoinedMirageJobs = {}

JoinJobIdByServerBrowser = function(jobId)
    if not jobId or tostring(jobId) == "" then
        warn("[ServerBrowser] JobId rỗng -> bỏ qua")
        return false
    end

    if tostring(jobId) == tostring(game.JobId) then
        warn("[ServerBrowser] Đang ở đúng JobId " .. tostring(jobId) .. " rồi -> bỏ qua")
        return false
    end

    local ok, result = pcall(function()
        return game:GetService("ReplicatedStorage")
            :WaitForChild("__ServerBrowser")
            :InvokeServer("teleport", tostring(jobId))
    end)

    if not ok then
        warn("[ServerBrowser] Join JobId lỗi: " .. tostring(result))
        return false
    end

    warn("[ServerBrowser] Đã gửi lệnh join JobId=" .. tostring(jobId) .. " | Result=" .. tostring(result))
    task.wait(8)
    return true
end

local function HopMirageByAPI()
    local cfg = getgenv().PullLeverConfig or {}

    if cfg["Use Mirage API"] == false then
        return false
    end

    local servers = GetMirageServersFromAPI()
    if type(servers) ~= "table" or #servers <= 0 then
        SetStatus("Mirage API empty -> fallback")
        return false
    end

    local currentPlaceId = tonumber(game.PlaceId)
    local maxPlayers = tonumber(cfg["Max Players"] or 11) or 11
    local avoidFull  = cfg["Avoid Full Server"] ~= false
    local candidates = {}
    local samePlaceCount = 0

    for _, server in ipairs(servers) do
        local jobId   = server.JobId
        local placeId = tonumber(server.PlaceId)
        local players = tonumber(server.Players or 0) or 0

        local samePlace  = placeId ~= nil and placeId == currentPlaceId
        local notSameJob = tostring(jobId) ~= tostring(game.JobId)
        local notVisited = not JoinedMirageJobs[tostring(jobId)]
        local notFull    = (not avoidFull) or players <= maxPlayers

        if samePlace then
            samePlaceCount = samePlaceCount + 1
        end

        if jobId and samePlace and notSameJob and notVisited and notFull then
            table.insert(candidates, server)
        end
    end

    if #candidates == 0 then
        SetStatus(
            "No Mirage JobId for PlaceId=" .. tostring(currentPlaceId)
            .. " | SamePlace=" .. tostring(samePlaceCount)
            .. " -> fallback"
        )
        return false
    end

    local server = candidates[math.random(1, #candidates)]
    local jobId = tostring(server.JobId)
    local players = tonumber(server.Players or 0) or 0
    local placeId = tonumber(server.PlaceId)

    JoinedMirageJobs[jobId] = true

    SetStatus(
        "Join Mirage | PlaceId=" .. tostring(placeId)
        .. " | Players=" .. tostring(players)
        .. " | Candidates=" .. tostring(#candidates)
    )
    print(
        "[MirageAPI] CurrentPlaceId=" .. tostring(currentPlaceId)
        .. " PickPlaceId=" .. tostring(placeId)
        .. " JobId=" .. tostring(jobId)
        .. " Players=" .. tostring(players)
        .. " Region=" .. tostring(server.Region)
    )

    local joined = JoinJobIdByServerBrowser(jobId)
    if joined then
        return true
    end

    task.wait(2)
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

local TweenConn, TweenInstance, TweenGhost, IsTweening = nil, nil, nil, false
local OriginalCanCollide = {}
local TweenCooldownUntil = 0

local function RestoreCollisions()
    for part, oldValue in pairs(OriginalCanCollide) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = oldValue
            end)
        end
    end
    table.clear(OriginalCanCollide)
end

local function NoclipLoop()
    -- Không noclip liên tục khi đang đứng yên; chỉ bật trong lúc tween.
    if not IsTweening or not LocalPlayer.Character then
        return
    end

    for _, c in LocalPlayer.Character:GetDescendants() do
        if c:IsA("BasePart") and c.Name ~= "HumanoidRootPart" then
            if OriginalCanCollide[c] == nil then
                OriginalCanCollide[c] = c.CanCollide
            end
            if c.CanCollide then
                c.CanCollide = false
            end
        end
    end
end
RunService.Stepped:Connect(NoclipLoop)

local function StopTween(reason)
    if TweenInstance then
        pcall(function() TweenInstance:Cancel() end)
        TweenInstance = nil
    end
    if TweenConn then
        TweenConn:Disconnect()
        TweenConn = nil
    end
    if TweenGhost then
        pcall(function() TweenGhost:Destroy() end)
        TweenGhost = nil
    end

    RestoreCollisions()
    IsTweening = false

    if reason and reason ~= "" then
        warn("[PullLever] Tween stopped: " .. tostring(reason))
    end
end

function TweenTo(Position)
    if os.clock() < TweenCooldownUntil then
        return
    end

    if not Character or not Character:FindFirstChild("Humanoid")
        or Character.Humanoid.Health <= 0 or not HumanoidRootPart then
        StopTween("character not ready")
        return
    end

    if LocalPlayer.Team == nil then
        StopTween("team not selected")
        return
    end

    if Position == false then
        StopTween("cancelled")
        return
    end
    if not Position then return end

    Position = typeof(Position) ~= "CFrame" and ConvertTo(CFrame, Position) or Position
    if typeof(Position) == "CFrame" then
        local p = Position.Position
        Position = CFrame.new(p.X, math.max(p.Y, 5), p.Z)
    end

    local root = HumanoidRootPart
    local dist = (Position.Position - root.Position).Magnitude
    local directDistance = tonumber(Config["Direct Teleport Distance"]) or 25
    local tweenSpeed = tonumber(Config["Tween Speed"]) or 220
    local updateInterval = tonumber(Config["Tween Update Interval"]) or 0.05
    local correctionLimit = tonumber(Config["Tween Correction Limit"]) or 90
    local retryCooldown = tonumber(Config["Tween Retry Cooldown"]) or 2

    -- Chỉ dịch chuyển thẳng ở khoảng cách rất ngắn.
    if dist <= directDistance then
        StopTween()
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = Position
        end)
        return
    end

    if IsTweening then
        return
    end
    IsTweening = true

    local ghost = Instance.new("Part")
    ghost.Name = "TweenGhost"
    ghost.Transparency = 1
    ghost.Anchored = true
    ghost.CanCollide = false
    ghost.CanTouch = false
    ghost.CanQuery = false
    ghost.Size = Vector3.new(2, 2, 2)
    ghost.CFrame = root.CFrame
    ghost.Parent = workspace
    TweenGhost = ghost

    TweenInstance = TweenService:Create(
        ghost,
        TweenInfo.new(dist / tweenSpeed, Enum.EasingStyle.Linear),
        { CFrame = Position }
    )

    local accumulator = 0
    TweenConn = RunService.Heartbeat:Connect(function(dt)
        accumulator = accumulator + dt
        if accumulator < updateInterval then
            return
        end
        accumulator = 0

        if not root or not root.Parent or not ghost or not ghost.Parent then
            StopTween("root/ghost missing")
            return
        end

        if not Character or not Character.Parent
            or not Humanoid or Humanoid.Health <= 0
            or LocalPlayer.Team == nil then
            StopTween("character/team changed")
            return
        end

        local gap = (root.Position - ghost.Position).Magnitude

        -- Nếu server kéo nhân vật lệch quá xa, không giật ngược về ghost trong 1 frame.
        -- Dừng và chờ một chút để tránh chuỗi correction/kick.
        if gap > correctionLimit then
            TweenCooldownUntil = os.clock() + retryCooldown
            StopTween("server correction gap=" .. tostring(math.floor(gap)))
            SetStatus("Movement corrected -> pause " .. tostring(retryCooldown) .. "s")
            return
        end

        local ok, err = pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = ghost.CFrame
        end)

        if not ok then
            TweenCooldownUntil = os.clock() + retryCooldown
            StopTween("movement error: " .. tostring(err))
        end
    end)

    TweenInstance.Completed:Connect(function(playbackState)
        if playbackState == Enum.PlaybackState.Completed
            and root and root.Parent
            and ghost and ghost.Parent then
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                root.CFrame = Position
            end)
        end
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
