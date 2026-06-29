-- pull_lever.lua  -  Script doc lap chi lam nhiem vu: Pull Lever (Temple Door)
-- Phu thuoc: executable phai ho tro cac ham executor (request, writefile, readfile,
-- isfile, hookfunction, hookmetamethod, getrawmetatable, setreadonly, newcclosure,
-- getnamecallmethod, sethiddenproperty, isnetworkowner, fireproximityprompt,
-- fireclickdetector, queue_on_teleport, ...).
-----------------------------------------------------------------------------------

if not LPH_OBFUSCATED then
    LPH_ENCSTR = LPH_ENCSTR or function(...) return ... end
    LPH_NO_VIRTUALIZE = LPH_NO_VIRTUALIZE or function(...) return ... end
end

-----------------------------------------------------------------------------------
-- 0. CONFIG
-----------------------------------------------------------------------------------
getgenv().PullLeverConfig = getgenv().PullLeverConfig or {
    ["Enabled"]            = true,
    ["Team"]               = "Pirates",
    ["Allowed Races"]      = {"Mink", "Human", "Skypiea", "Fishman"},
    ["Auto Roll Race"]     = false,
    ["Use Server API"]     = true,
    ["Hop Mirage"]         = true,
    ["Boost FPS"]          = true,
    ["FPS"]                = 20,
    ["Black Screen"]       = true,

    -- Mirage API (server noi co Mirage dang spawn)
    ["Use Mirage API"]     = true,
    ["Mirage API"]         = "http://fi12.bot-hosting.cloud:20112/api/name=mirage",
    ["Avoid Full Server"]  = true,
    ["Max Players"]        = 11,
}

LPH_NO_VIRTUALIZE(function()

-----------------------------------------------------------------------------------
-- 1. STATUS / UI nho
-----------------------------------------------------------------------------------
local PlayerGui
local _statusLabel, _raceLabel, _seaLabel, _mirrorLabel, _valkLabel, _doorLabel, _progressLabel

local _lastStatus = ""

local function SetStatus(text)
    text = tostring(text or "")
    _lastStatus = text

    print("[PullLever] " .. text)

    if _statusLabel then
        _statusLabel.Text = "Status: " .. text
    end
end

-- Hien loi ro rang len UI + warn (khong pcall im lang)
local function DebugStatus(tag, err)
    local msg = "[" .. tostring(tag) .. "] " .. tostring(err)
    warn("[PullLever] " .. msg)
    SetStatus(msg)
end

local function MakeUI()
    if _G.__PullLeverUIBuilt then return end
    local ok, parent = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not ok or not parent then return end

    local old = parent:FindFirstChild("PullLeverUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "PullLeverUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 240, 0, 150)
    main.Position = UDim2.new(0, 20, 0, 220)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(70, 90, 160)
    stroke.Thickness = 1

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 26)
    bar.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
    bar.BorderSizePixel = 0
    bar.Parent = main
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -10, 1, 0)
    title.Position = UDim2.new(0, 8, 0, 0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextColor3 = Color3.fromRGB(235, 235, 245)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Pull Lever"
    title.Parent = bar

    local body = Instance.new("Frame")
    body.BackgroundTransparency = 1
    body.Position = UDim2.new(0, 10, 0, 30)
    body.Size = UDim2.new(1, -20, 1, -36)
    body.Parent = main
    local layout = Instance.new("UIListLayout", body)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 3)

    local function row(order)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Size = UDim2.new(1, 0, 0, 16)
        l.Font = Enum.Font.Gotham
        l.TextSize = 12
        l.TextColor3 = Color3.fromRGB(210, 210, 220)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextWrapped = true
        l.LayoutOrder = order
        l.Text = ""
        l.Parent = body
        return l
    end

    _statusLabel  = row(1); _statusLabel.Text  = "Status: init"
    _seaLabel     = row(2); _seaLabel.Text     = "Sea: ?"
    _raceLabel    = row(3); _raceLabel.Text    = "Race: ?"
    _mirrorLabel  = row(4); _mirrorLabel.Text  = "Mirror Fractal: ?"
    _valkLabel    = row(5); _valkLabel.Text    = "Valkyrie Helm: ?"
    _doorLabel    = row(6); _doorLabel.Text    = "Temple Door: ?"
    _progressLabel = row(7); _progressLabel.Text = "RaceV4 Check: ?"

    _G.__PullLeverUIBuilt = true
end

-----------------------------------------------------------------------------------
-- 2. WAIT LOAD + SET TEAM
-----------------------------------------------------------------------------------
-- Default config an toan: neu nguoi dung quen config ngoai thi khong loi nil,
-- neu co config ngoai thi van uu tien config ngoai.
getgenv().PullLeverConfig = getgenv().PullLeverConfig or {}

local Config = getgenv().PullLeverConfig

Config["Enabled"]           = Config["Enabled"] ~= false
Config["Team"]              = Config["Team"] or "Pirates"
Config["Allowed Races"]     = Config["Allowed Races"] or {"Mink", "Human", "Skypiea", "Fishman"}
Config["Auto Roll Race"]    = Config["Auto Roll Race"] or false
Config["Use Server API"]    = Config["Use Server API"] ~= false
Config["Hop Mirage"]        = Config["Hop Mirage"] ~= false
Config["Use Mirage API"]    = Config["Use Mirage API"] ~= false
Config["Mirage API"]        = Config["Mirage API"] or "http://fi12.bot-hosting.cloud:20112/api/name=mirage"
Config["Avoid Full Server"] = Config["Avoid Full Server"] ~= false
Config["Max Players"]       = Config["Max Players"] or 11
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
-- (TeleportService da duoc loai bo: hop server dung __ServerBrowser)
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser       = game:GetService("VirtualUser")
local StarterPlayer     = game:GetService("StarterPlayer")

local LocalPlayer = Players.LocalPlayer
local Character, Humanoid, HumanoidRootPart

-- Tao UI som de moi buoc loading / choose team deu thay status debug
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

local function RefreshCharacter()
    Character        = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    Humanoid         = Character:WaitForChild("Humanoid")
    HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
end
RefreshCharacter()
LocalPlayer.CharacterAdded:Connect(function() RefreshCharacter() end)

-- Tim nut chon team trong GUI (ho tro ca "Main (minimal)" va "Main")
local function GetChooseTeamButton(teamName)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end

    local mainMinimal = pg:FindFirstChild("Main (minimal)")
    if mainMinimal
        and mainMinimal:FindFirstChild("ChooseTeam")
        and mainMinimal.ChooseTeam:FindFirstChild("Container")
    then
        return mainMinimal.ChooseTeam.Container:FindFirstChild(teamName)
    end

    local main = pg:FindFirstChild("Main")
    if main
        and main:FindFirstChild("ChooseTeam")
        and main.ChooseTeam:FindFirstChild("Container")
    then
        return main.ChooseTeam.Container:FindFirstChild(teamName)
    end

    return nil
end

-- Choose team chac chan hon: vua goi remote SetTeam vua firesignal nut, retry 20 lan
local function ChooseTeam()
    local teamName = tostring(Config["Team"] or "Pirates")

    if LocalPlayer.Team then
        SetStatus("Team already selected: " .. tostring(LocalPlayer.Team.Name))
        return true
    end

    SetStatus("Waiting loading screen...")
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg and pg:FindFirstChild("LoadingScreen") then
            repeat
                task.wait(1)
                SetStatus("Waiting LoadingScreen removed...")
            until not pg:FindFirstChild("LoadingScreen")
        end
    end)

    for attempt = 1, 20 do
        if LocalPlayer.Team then
            SetStatus("Team selected: " .. tostring(LocalPlayer.Team.Name))
            return true
        end

        SetStatus("Choose team attempt " .. tostring(attempt) .. " -> " .. teamName)

        local okRemote, errRemote = pcall(function()
            ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_"):InvokeServer("SetTeam", teamName)
        end)

        if not okRemote then
            DebugStatus("SetTeam remote error", errRemote)
        end

        task.wait(0.5)

        if not LocalPlayer.Team then
            local btn = GetChooseTeamButton(teamName)
            if btn then
                local okClick, errClick = pcall(function()
                    firesignal(btn.Activated)
                end)

                if not okClick then
                    okClick, errClick = pcall(function()
                        firesignal(btn.MouseButton1Click)
                    end)
                end

                if not okClick then
                    DebugStatus("ChooseTeam firesignal error", errClick)
                else
                    SetStatus("ChooseTeam button fired")
                end
            else
                SetStatus("ChooseTeam button not found")
            end
        end

        task.wait(1)
    end

    if LocalPlayer.Team then
        SetStatus("Team selected after retry: " .. tostring(LocalPlayer.Team.Name))
        return true
    end

    SetStatus("Choose team failed after retries")
    return false
end

if not ChooseTeam() then
    SetStatus("ChooseTeam failed, script stopped")
    return
end

SetStatus("Waiting character...")
repeat
    task.wait(0.5)
until LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
SetStatus("Character ready")

SetStatus("Waiting Data/Race...")
repeat
    task.wait(1)
until LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Race")
SetStatus("Data/Race ready: " .. tostring(LocalPlayer.Data.Race.Value))

-----------------------------------------------------------------------------------
-- 3. REMOTES WRAPPER (CommF_ log warning de debug)
-----------------------------------------------------------------------------------
local Remotes = {}
setmetatable(Remotes, {
    __index = function(_, Key)
        return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Key, 30)
    end
})
local CommF_ = Remotes.CommF_
local CommE  = Remotes.CommE
local Redeem = Remotes.Redeem

-----------------------------------------------------------------------------------
-- 4. SEA DETECT
-----------------------------------------------------------------------------------
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

-----------------------------------------------------------------------------------
-- 5. CONCHOCHISITI36 + REFRESH DATA
-----------------------------------------------------------------------------------
local ConChoChisiti36 = {
    PlayerData = {},
    Enemies    = {},
    NPCs       = {},
    Tools      = {},
    Backpack   = {},
}
setmetatable(ConChoChisiti36.Enemies, {
    __index = function(_, Index)
        return Workspace.Enemies:FindFirstChild(Index)
            or ReplicatedStorage:FindFirstChild(Index)
    end
})
setmetatable(ConChoChisiti36.Tools, {
    __index = function(_, Index)
        return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild(Index)
            or LocalPlayer.Backpack:FindFirstChild(Index)
    end
})
setmetatable(ConChoChisiti36.NPCs, {
    __index = function(_, Index)
        return Workspace:FindFirstChild("NPCs") and Workspace.NPCs:FindFirstChild(Index)
            or ReplicatedStorage:FindFirstChild("NPCs") and ReplicatedStorage.NPCs:FindFirstChild(Index)
    end
})

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

-----------------------------------------------------------------------------------
-- 6. STORAGE (dung cho WrapToServer khong nhap lai server)
-----------------------------------------------------------------------------------
local Storage = { Data = {}, WRITE_DELAY = 10 }
local StoragePath = ".pull_lever_storage_" .. tostring(LocalPlayer.UserId)

local function Encode(t)  return HttpService:JSONEncode(t) end
local function Decode(s)  return HttpService:JSONDecode(s or "{}") end

if type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function" then
    pcall(function()
        if not isfile(StoragePath) then writefile(StoragePath, "{}") end
        Storage.Data = Decode(readfile(StoragePath) or "{}")
    end)
end

function Storage:Get(k) return self.Data[k] end
function Storage:Set(k, v)
    self.Data[k] = v
    if type(writefile) == "function" then
        pcall(function() writefile(StoragePath, Encode(self.Data)) end)
    end
end

-----------------------------------------------------------------------------------
-- 7. URL ENCODE + SERVER API + WRAP + HOP
-----------------------------------------------------------------------------------
local function urlencode(str)
    if str == nil then return "" end
    str = tostring(str)
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

local function AsynclyPullServerDatas(Category)
    if not Config["Use Server API"] then return {} end
    local url = ("https://api2.chimovo.com/v1/servers/%s"):format(urlencode(Category))
    local ok, raw = pcall(function()
        return request({
            Url = url,
            Method = "GET",
            Headers = { ["x-authorization"] = "kkk" },
        })
    end)
    if not ok or not raw or raw.Success ~= true then return {} end
    local ok2, decoded = pcall(function() return HttpService:JSONDecode(raw.Body) end)
    if not ok2 then return {} end
    return decoded.data or {}
end

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

-- Forward declare de WrapToServer (dinh nghia phia tren) co the goi duoc
-- Ham that dinh nghia phia duoi (sau WrapToServer).
local JoinJobIdByServerBrowser

local function WrapToServer(Category, Filter, IgnoreHop)
    print("[PullLever] WrapToServer: " .. tostring(Category))
    local List = AsynclyPullServerDatas(Category)
    if type(List) ~= "table" or #List == 0 then return false end
    for _ = 1, #List do
        local Server = List[math.random(math.max(1, #List - 50), #List)]
        if Server and not Storage:Get(Server.JobId) and Server.Players ~= "12/12" then
            if (not Filter or Filter(Server)) and Server.PlaceId == game.PlaceId then
                Storage:Set(Server.JobId, true)

                local joined = JoinJobIdByServerBrowser(Server.JobId)
                if joined then
                    task.wait(5)
                    return true
                end
            end
        end
    end
    if not IgnoreHop then Hop("WrapToServer failed: " .. tostring(Category)) end
    return false
end

-----------------------------------------------------------------------------------
-- 7b. MIRAGE API (custom endpoint fi12.bot-hosting.cloud)
-----------------------------------------------------------------------------------
local function HttpRequest(opts)
    -- Chon ham request tuong thich voi executor
    local req = request or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)

    if type(req) ~= "function" then
        return false, "executor does not support request"
    end

    local ok, res = pcall(function() return req(opts) end)
    if not ok then
        return false, res
    end
    return true, res
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
    if type(v) ~= "table" then return nil end

    local jobId   = v.JobId or v.jobId or v.job_id or v.id
    local placeId = v.PlaceId or v.placeId or v.place_id or v.place
    local players = v.Players or v.players or v.Count or v.count or v.playerCount
    local region  = v.Region or v.region

    if type(players) == "string" then
        local n = tostring(players):match("^(%d+)")
        players = tonumber(n) or players
    end

    if not jobId then return nil end

    return {
        JobId   = tostring(jobId),
        PlaceId = tonumber(placeId) or game.PlaceId,
        Players = tonumber(players) or 0,
        Region  = region,
        Raw     = v,
    }
end

local function ExtractServerList(data)
    local list = {}
    if type(data) ~= "table" then return list end

    local source = data.data or data.servers or data.result or data.results or data

    -- Neu source la 1 server don le (co JobId truc tiep)
    if source.JobId or source.jobId or source.job_id or source.id then
        local one = NormalizeServerEntry(source)
        if one then table.insert(list, one) end
        return list
    end

    -- Neu source la mang/object cac server
    for _, v in pairs(source) do
        local one = NormalizeServerEntry(v)
        if one then table.insert(list, one) end
    end

    return list
end

local LastMirageApiFetch = 0
local CachedMirageServers = nil

local function GetMirageServersFromAPI()
    local cfg = getgenv().PullLeverConfig or {}
    local url = cfg["Mirage API"] or "http://fi12.bot-hosting.cloud:20112/api/name=mirage"

    -- Cache ngan han tranh spam API
    if CachedMirageServers and os.time() - LastMirageApiFetch < 20 then
        return CachedMirageServers
    end

    print("[MirageAPI] GET " .. tostring(url))
    SetStatus("Fetching Mirage API...")

    local ok, res = HttpRequest({
        Url = url,
        Method = "GET",
        Headers = { ["Accept"] = "application/json" },
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

    local data = JsonDecodeSafe(body)
    if not data then
        warn("[MirageAPI] JSON decode failed. Body head: " .. tostring(body):sub(1, 300))
        return {}
    end

    local servers = ExtractServerList(data)

    LastMirageApiFetch = os.time()
    CachedMirageServers = servers

    print("[MirageAPI] Parsed " .. tostring(#servers) .. " server(s)")
    SetStatus("Mirage API servers: " .. tostring(#servers))
    return servers
end

local JoinedMirageJobs = {}

-- Join JobId bang __ServerBrowser (y het file goc sida)
-- KHONG dung TeleportService vi no se kick player ra menu trong 1 so truong hop.
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

    local maxPlayers = tonumber(cfg["Max Players"] or 11) or 11
    local avoidFull  = cfg["Avoid Full Server"] ~= false

    for _, server in ipairs(servers) do
        local jobId   = server.JobId
        local players = tonumber(server.Players or 0) or 0

        local notSameJob = tostring(jobId) ~= tostring(game.JobId)
        local notVisited = not JoinedMirageJobs[tostring(jobId)]
        local notFull    = (not avoidFull) or players <= maxPlayers

        if jobId and notSameJob and notVisited and notFull then
            JoinedMirageJobs[tostring(jobId)] = true

            SetStatus(
                "Join Mirage by __ServerBrowser | JobId="
                .. tostring(jobId)
                .. " | Players="
                .. tostring(players)
            )
            print("[MirageAPI] Pick JobId=" .. tostring(jobId)
                .. " Players=" .. tostring(players)
                .. " Region=" .. tostring(server.Region))

            local joined = JoinJobIdByServerBrowser(jobId)
            if joined then
                return true
            else
                task.wait(2)
            end
        end
    end

    SetStatus("No valid Mirage API server -> fallback")
    return false
end

-----------------------------------------------------------------------------------
-- 8. MOVEMENT
-----------------------------------------------------------------------------------
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

local TweenInstance
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

function TweenTo(Position)
    if not Position or not HumanoidRootPart then return end
    if TweenInstance then pcall(function() TweenInstance:Cancel() end) end
    Position = typeof(Position) ~= "CFrame" and ConvertTo(CFrame, Position) or Position
    if typeof(Position) == "CFrame" then
        local p = Position.p
        Position = CFrame.new(p.X, math.max(p.Y, 5), p.Z)
    end
    local dist = CaculateDistance(HumanoidRootPart.CFrame, Position)
    TweenInstance = TweenService:Create(
        HumanoidRootPart,
        TweenInfo.new(dist / (dist < 18 and 25 or 330), Enum.EasingStyle.Linear),
        { CFrame = Position }
    )
    TweenInstance:Play()
end

-----------------------------------------------------------------------------------
-- 9. COMBAT MINIMAL (can thiet cho UpgradeRaceV3, dac biet Fishman/Mink/Skypiea)
-----------------------------------------------------------------------------------
local _EquipToolDone = {}

local function EquipTool(ToolName)
    if not Character or not Character:FindFirstChild("Humanoid") then return end
    for _, item in LocalPlayer.Backpack:GetChildren() do
        if item:IsA("Tool") and item.Name ~= "Tool"
            and (item.Name == ToolName or item.ToolTip == ToolName) then
            Character.Humanoid:EquipTool(item)
            return
        end
    end
end

local function Attack() end  -- placeholder cho FastAttack (override neu can)

local function LoadFastAttack()
    local src = [[
        local RegisterAttack = require(game.ReplicatedStorage.Modules.Net):RemoteEvent("RegisterAttack", true)
        local RegisterHit    = require(game.ReplicatedStorage.Modules.Net):RemoteEvent("RegisterHit", true)

        local function hits()
            local t = {}
            local hrp = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return t end
            for _, v in pairs(workspace.Enemies:GetChildren()) do
                if v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0
                    and v:FindFirstChild("HumanoidRootPart")
                    and (v.HumanoidRootPart.Position - hrp.Position).Magnitude <= 65 then
                    table.insert(t, v)
                end
            end
            return t
        end

        _G.FastAttackTick = function()
            pcall(function()
                local list = hits()
                if #list == 0 then return end
                local args = { nil, {} }
                for _, v in list do
                    args[1] = args[1] or v.Head
                    table.insert(args[2], { v, v.HumanoidRootPart })
                    table.insert(args[2], v)
                    RegisterAttack:FireServer(0)
                end
                RegisterHit:FireServer(unpack(args))
            end)
        end
    ]]
    pcall(function()
        loadstring(src)()
        Attack = function() pcall(_G.FastAttackTick) end
    end)
end
LoadFastAttack()

-- Mob helpers (combat chinh can thiet cho UpgradeRaceV3)
local function GetMobAsSortedRange()
    local list = {}
    local function scan(parent)
        for _, m in parent:GetChildren() do
            if m and m:FindFirstChild("Humanoid") and m.Humanoid.Health > 0
                and m:FindFirstChild("HumanoidRootPart") then
                table.insert(list, m)
            end
        end
    end
    scan(workspace.Enemies)
    scan(ReplicatedStorage)
    table.sort(list, function(a, b)
        return (a.HumanoidRootPart.Position - HumanoidRootPart.Position).Magnitude
             < (b.HumanoidRootPart.Position - HumanoidRootPart.Position).Magnitude
    end)
    return list
end

local function SearchMobs(MobTable)
    for _, m in GetMobAsSortedRange() do
        if table.find(MobTable, m.Name) then return m end
    end
    for _, name in MobTable do
        local rep = ReplicatedStorage:FindFirstChild(name)
        if rep then return rep end
    end
end

local function LockMob(mob)
    if mob:GetAttribute("_Locked") then return end
    mob:SetAttribute("_Locked", 1)
    pcall(function() mob.HumanoidRootPart.CanCollide = false end)
end

local function GrabMobs(name)
    local mobs = {}
    for _, m in workspace.Enemies:GetChildren() do
        if m.Name == name and m:FindFirstChild("Humanoid") and m.Humanoid.Health > 0
            and m:FindFirstChild("HumanoidRootPart") then
            table.insert(mobs, m)
        end
    end
    if #mobs == 0 then return end
    for _, m in mobs do LockMob(m) end
end

local Angle, lastChange = 40, tick()
local function RoundVec3(v)
    return Vector3.new(math.floor(v.X/10)*10, math.floor(v.Y/10)*10, math.floor(v.Z/10)*10)
end
local function CircleDir(pos)
    if tick() - lastChange > 0.4 then
        Angle = Angle + 80
        lastChange = tick()
        if Angle > 50000 then Angle = 60 end
    end
    local sum = pos + Vector3.new(math.cos(math.rad(Angle))*40, 0, math.sin(math.rad(Angle))*40)
    return CFrame.new(RoundVec3(sum.p))
end

local LastFound = os.time()
function AttackMob(MobTable)
    if type(MobTable) == "string" then MobTable = { MobTable } end
    for _, name in MobTable do
        local mob = SearchMobs(MobTable)
        if mob and mob:IsFirstAncestor("Workspace") then
            LastFound = os.time()
            local count = 0
            while count < 600 do
                if not mob:FindFirstChild("Humanoid") or mob.Humanoid.Health <= 0 then break end
                local hrp = mob:FindFirstChild("HumanoidRootPart")
                if hrp then
                    TweenTo(CircleDir(hrp.CFrame) + Vector3.new(0, 35, 0))
                    if CaculateDistance(hrp.Position + Vector3.new(0, 35, 0)) < 150 then
                        GrabMobs(mob.Name)
                        EquipTool("Melee"); Attack()
                        count = count + 1
                    else
                        return
                    end
                end
                task.wait()
            end
        else
            if os.time() - LastFound > 200 then Hop("No mob"); return end
            -- di chuyen toi spawn khu vuc
            local inst = workspace.Enemies:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name)
            if inst and inst.PrimaryPart then
                TweenTo(inst.PrimaryPart.CFrame + Vector3.new(0, 35, 35))
                task.wait(1)
            end
        end
    end
end

-----------------------------------------------------------------------------------
-- 10. RACE V2
-----------------------------------------------------------------------------------
function DoBartiloQuest()
    local ok, r = pcall(function() return CommF_:InvokeServer("BartiloQuestProgress") end)
    if not ok or type(r) ~= "table" then return false end
    if not r.KilledBandits then
        pcall(function() CommF_:InvokeServer("AbandonQuest") end)
        pcall(function() CommF_:InvokeServer("StartQuest", "BartiloQuest", 1) end)
        AttackMob({"Swan Pirate"})
    elseif not r.KilledSpring then
        if ConChoChisiti36.Enemies.Jeremy then
            AttackMob({"Jeremy"})
        else
            Hop("Need Jeremy (Bartilo)")
        end
    end
end

function UpgradeRaceV2()
    RefreshSea()
    if SeaIndex ~= 2 then
        pcall(function() CommF_:InvokeServer("TravelDressrosa") end)
        task.wait(10); return true
    end
    if not ConChoChisiti36.Backpack["Warrior Helmet"] then
        DoBartiloQuest()
        return true
    end
    -- can ban dem (V2 can dem tren Dressrosa)
    local hour = math.floor(Lighting.ClockTime)
    if not (hour >= 18 or hour < 5) then
        Hop("Finding Night Server for V2"); return true
    end
    pcall(function()
        CommF_:InvokeServer("Alchemist", "1")
        CommF_:InvokeServer("Alchemist", "2")
    end)
    for i = 1, 2 do
        local inInv  = ConChoChisiti36.Tools["Flower " .. i]
        local inWorld = workspace:FindFirstChild("Flower" .. i)
        if not inInv and inWorld and inWorld.Transparency == 0 then
            while not ConChoChisiti36.Tools["Flower " .. i] do
                task.wait()
                TweenTo(inWorld.CFrame + Vector3.new(0, math.random(-1, 2), 0))
            end
        end
    end
    if not ConChoChisiti36.Tools["Flower 3"] then
        AttackMob({"Swan Pirate"})
    else
        if HumanoidRootPart and HumanoidRootPart.Position.Y < 10000 then
            TweenTo(HumanoidRootPart.CFrame + Vector3.new(0, 50, 0))
        end
        pcall(function() CommF_:InvokeServer("Alchemist", "3") end)
    end
    _G.IsRaceV2 = nil
    return true
end

-----------------------------------------------------------------------------------
-- 11. RACE V3
-----------------------------------------------------------------------------------
local function GetNearestChests()
    local best, bestDist = nil, math.huge
    for _, v in workspace:GetDescendants() do
        if (v.Name == "Chest1" or v.Name == "Chest2" or v.Name == "Chest3") and v:IsA("BasePart") then
            local ok, _ = pcall(function() return v.CanTouch end)
            if ok and v.CanTouch then
                local d = CaculateDistance(v.CFrame)
                if d < bestDist then best, bestDist = v, d end
            end
        end
    end
    return best
end

local function GetPlayerBoat()
    for _, boat in workspace:FindFirstChild("Boats") and workspace.Boats:GetChildren() or {} do
        if boat:IsA("Model") then
            local owner = boat:FindFirstChild("Owner")
            local hd    = boat:FindFirstChild("Humanoid")
            if owner and hd and tostring(owner.Value) == LocalPlayer.Name and hd.Value > 0 then
                return boat
            end
        end
    end
end

local function GetSeabeast()
    for _, s in workspace:FindFirstChild("SeaBeasts") and workspace.SeaBeasts:GetChildren() or {} do
        local h = s:FindFirstChild("Health")
        if h and h.Value > 30000 then return s end
    end
end

local BlacklistedPlayers = { [LocalPlayer.Name] = true }
local function GetSkyRacePlayer()
    for _, p in Players:GetPlayers() do
        if p and p ~= LocalPlayer and p.Character and not BlacklistedPlayers[p.Name] then
            local h = p.Character:FindFirstChild("Humanoid")
            if h and h.Health > 0
                and p.Data and p.Data:FindFirstChild("Race")
                and p.Data.Race.Value == "Skypiea"
                and not p:GetAttribute("IslandRaiding")
                and CaculateDistance(p.Character.HumanoidRootPart.CFrame) < 12000
                and p.Character.HumanoidRootPart.CFrame.Y > 0 then
                BlacklistedPlayers[p.Name] = true
                return p
            end
        end
    end
end

local function SendKey(key)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, key, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    end)
end

-- Hook FireServer de lock aim (can cho Fishman Sky race)
do
    local mt = getrawmetatable and getrawmetatable(game)
    if mt and setreadonly and newcclosure then
        pcall(function() setreadonly(mt, false) end)
        local old = mt.__namecall
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            if method == "FireServer" and self and self.Name == "RemoteEvent"
                and getgenv().LastestLockDate and os.time() - getgenv().LastestLockDate < 3 then
                args[1] = getgenv().LockPosition
            end
            return old(self, unpack(args))
        end)
    end
end

local function LockAimPositionTo(pos)
    getgenv().LastestLockDate = os.time()
    local p = typeof(pos) == "CFrame" and pos.p or (typeof(pos) == "Vector3" and pos or ConvertTo(Vector3, pos))
    getgenv().LockPosition = p
end

-- Hook notify (can cho TorchEnabledTime, Elite)
Hooks = { Listeners = {} }
local function RegisterNotify(senque, cb) Hooks.Listeners[senque] = cb end
TorchEnabledTime = 0
DoneCDKTick = 0
RegisterNotify("been spotted approaching", function() _G.PirateRaidSenque = os.time() end)
RegisterNotify("torch", function() TorchEnabledTime = os.time() end)
RegisterNotify("player", function() _G.SkipPlayer = true end)
RegisterNotify("elite", function()
    pcall(function()
        local c = CommF_:InvokeServer("EliteHunter", "Progress")
        _G.EliteCount = c
    end)
end)

pcall(function()
    local notification = require(ReplicatedStorage:WaitForChild("Notification"))
    local old = notification.new
    notification.new = function(a, b)
        local content = tostring(a or "") .. tostring(b or "")
        for k, cb in Hooks.Listeners do
            if content:lower():find(k:lower()) then pcall(cb, content) end
        end
        return old(a, b)
    end
end)

function UpgradeRaceV3()
    -- check V2
    local IsV2 = (function()
        local cached = _G.IsRaceV2
        if cached ~= nil then return cached end
        local v = CommF_:InvokeServer("Alchemist", "1") == -2
        _G.IsRaceV2 = v
        return v
    end)()

    if not IsV2 then return UpgradeRaceV2() end

    RefreshSea()
    if SeaIndex ~= 2 then
        pcall(function() CommF_:InvokeServer("TravelDressrosa") end)
        task.wait(10); return true
    end

    pcall(function()
        CommF_:InvokeServer("Wenlocktoad", "1")
        CommF_:InvokeServer("Wenlocktoad", "2")
    end)

    local race = ConChoChisiti36.PlayerData.Race

    if race == "Mink" then
        local total = 0
        while total < 35 do
            local chest = GetNearestChests()
            if chest then
                repeat
                    task.wait()
                    TweenTo(chest.CFrame + Vector3.new(0, math.random(-2, 2), 0))
                until (not chest.Parent) or (not chest.CanTouch)
                total = total + 1; task.wait(2)
            else
                task.wait(1)
            end
        end
        pcall(function() CommF_:InvokeServer("Wenlocktoad", "3") end)
        _G.IsRaceUpgraded = nil

    elseif race == "Skypiea" then
        local enemy = GetSkyRacePlayer()
        if not enemy then Hop("Find Sky user"); return true end
        pcall(function() CommF_:InvokeServer("EnablePvp") end)
        local t = os.time()
        repeat
            task.wait()
            if not enemy or not enemy.Character or not enemy.Character:FindFirstChild("HumanoidRootPart") then break end
            local hrp = enemy.Character.HumanoidRootPart
            TweenTo(CircleDir(hrp.CFrame) + Vector3.new(0, math.random(-35, 35), 0))
            if math.random(1, 20) == 1 then
                TweenTo(CircleDir(hrp.CFrame) + Vector3.new(0, math.random(300, 3005), 0))
                task.wait(math.random(2, 5) / 10)
            end
            if not ConChoChisiti36.Tools.Yama then
                pcall(function() CommF_:InvokeServer("LoadItem", "Yama") end)
            end
            if CaculateDistance(hrp.CFrame) < 100 then
                EquipTool(math.random(1,2) == 2 and "Sword" or "Melee")
                Attack()
                LockAimPositionTo(hrp.CFrame)
                if math.random(1,2) == 1 then SendKey(math.random(2,3)==2 and "Z" or "X") end
            end
        until os.time() - t > 100 or _G.SkipPlayer
        pcall(function() CommF_:InvokeServer("Wenlocktoad", "3") end)
        _G.IsRaceUpgraded = nil
        _G.SkipPlayer = false

    elseif race == "Fishman" then
        local sb = GetSeabeast()
        if not sb then
            local boat = GetPlayerBoat()
            if not boat then
                TweenTo(CFrame.new(-14, 10, 2955))
                if CaculateDistance(CFrame.new(-14, 10, 2955)) < 10 then
                    pcall(function() CommF_:InvokeServer("BuyBoat", "PirateBrigade") end)
                end
            elseif CaculateDistance(boat.VehicleSeat.CFrame) > 5 then
                TweenTo(boat.VehicleSeat.CFrame + Vector3.new(0, math.random(-1, 2), 0))
            end
        else
            if not ConChoChisiti36.Tools["Sharkman Karate"] then
                pcall(function() CommF_:InvokeServer("BuySharkmanKarate") end)
            end
            repeat
                task.wait()
                if sb.WorldPivot.Position.Y >= -179 then
                    local top = sb.WorldPivot * CFrame.new(0, 300, 0)
                    TweenTo(top); LockAimPositionTo(top)
                    for _, k in { "Z", "X", "C" } do
                        EquipTool(math.random(1,2)==1 and "Melee" or "Sword")
                        SendKey(k)
                    end
                else
                    TweenTo(sb.WorldPivot * CFrame.new(0, 900, 0))
                end
            until not sb or not sb:FindFirstChild("Health") or sb.Health.Value <= 0
            pcall(function() CommF_:InvokeServer("Wenlocktoad", "3") end)
            _G.IsRaceUpgraded = nil
        end

    elseif race == "Human" then
        for _, boss in { "Diamond", "Jeremy", "Orbitus" } do
            while ConChoChisiti36.Enemies[boss]
                and ConChoChisiti36.Enemies[boss]:FindFirstChild("Humanoid")
                and ConChoChisiti36.Enemies[boss].Humanoid.Health > 0 do
                AttackMob({ boss }); task.wait(1)
            end
            if not ConChoChisiti36.Enemies[boss] then Hop("Finding boss for race v3: "..boss); return true end
        end
        pcall(function() CommF_:InvokeServer("Wenlocktoad", "3") end)
        _G.IsRaceUpgraded = nil
    end
    return true
end

-----------------------------------------------------------------------------------
-- 12. PULL LEVER - helpers
-----------------------------------------------------------------------------------
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

-----------------------------------------------------------------------------------
-- 13. DoRaceV4Progress - do Begin/Check/Teleport + Continue
-----------------------------------------------------------------------------------
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

-----------------------------------------------------------------------------------
-- 14. DoMirageBlueGear
-----------------------------------------------------------------------------------
local function DoMirageBlueGear()
    local mirage = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("MysticIsland")
    if not mirage then
        if Config["Hop Mirage"] then
            SetStatus("Khong co Mirage -> Hop Mirage API")
            if not HopMirageByAPI() then
                SetStatus("Mirage API failed -> fallback WrapToServer")
                WrapToServer("Mirage")
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
                SetStatus("Mirage API failed -> fallback WrapToServer")
                WrapToServer("Mirage")
            end
        end
    end
end

-----------------------------------------------------------------------------------
-- 15. BOOST FPS / BLACK SCREEN
-----------------------------------------------------------------------------------
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
            pcall(function() players:FindFirstChild("Main") and players.Main.Enabled = false end)
        end
    end)
end

-----------------------------------------------------------------------------------
-- 16. UI nho
-----------------------------------------------------------------------------------
pcall(MakeUI)

-----------------------------------------------------------------------------------
-- 17. MAIN LOOP - Pull Lever only
-----------------------------------------------------------------------------------
local _lastUiRefresh = 0

local function UIUpdateTick()
    local now = os.time()
    if now - _lastUiRefresh < 1 then return end
    _lastUiRefresh = now
    if not _statusLabel then return end
    _seaLabel.Text     = "Sea: " .. tostring(Sea)
    _raceLabel.Text    = "Race: " .. tostring(ConChoChisiti36.PlayerData.Race or "?")
    _mirrorLabel.Text  = "Mirror Fractal: "  .. (HasMirrorFractal() and "YES" or "NO")
    _valkLabel.Text    = "Valkyrie Helm: "   .. (HasValkyrieHelm()   and "YES" or "NO")
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

    -- 0. Phai o Sea 3 (Zou) truoc khi lam bat ky thu gi
    if not EnsureSea3() then
        task.wait(5); continue
    end

    -- 1. Can Mirror Fractal
    if not HasMirrorFractal() then
        SetStatus("Missing Mirror Fractal")
        task.wait(3); continue
    end

    -- 2. Can Valkyrie Helm
    if not HasValkyrieHelm() then
        SetStatus("Missing Valkyrie Helm")
        task.wait(3); continue
    end

    -- 3. Neu Temple Door da mo -> ket thuc
    if IsTempleDoorOpened() then
        SetStatus("Temple Door da mo -> DONE")
        break
    end

    -- 4. Race chua V3 -> tu lam
    if not IsCurrentRaceV3() then
        -- kiem tra race co hop le khong
        local race = ConChoChisiti36.PlayerData.Race
        if not table.find(Config["Allowed Races"], race) then
            if Config["Auto Roll Race"] and (ConChoChisiti36.PlayerData.Fragments or 0) > 3500 then
                SetStatus("Race "..tostring(race).." khong hop le -> Reroll")
                pcall(function() CommF_:InvokeServer("BlackbeardReward", "Reroll", "2") end)
                task.wait(5); continue
            else
                SetStatus("Race "..tostring(race).." khong hop le, dong script")
                task.wait(5); continue
            end
        else
            SetStatus("Race chua V3 -> UpgradeRaceV3")
            pcall(UpgradeRaceV3)
            task.wait(3); continue
        end
    end

    -- 5. (Da o Sea 3 - EnsureSea3() da dam bao)
    -- (Bo check SeaIndex o day, EnsureSea3 da xu ly o dau vong lap)

    -- 6. RaceV4 Progress chua xong
    if not IsRaceV4ProgressReady() then
        pcall(DoRaceV4Progress)
        task.wait(3); continue
    end

    -- 7. Da V4 Ready -> tim Mirage / Blue Gear
    pcall(DoMirageBlueGear)
    task.wait(3)
end

end)() -- end LPH_NO_VIRTUALIZE
