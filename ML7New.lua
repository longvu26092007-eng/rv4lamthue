-- ======================================================================
--  AUTO KAITUN ML7 — VFAndSA / Sanguine Art  (Blox Fruits)
--  Bản TỐI ƯU TOÀN BỘ — By Vu Nguyen
--  • Helpers: cache inventory, detect boss kiểu Banana (RS trước), nil-guard
--  • HopServer: best-of-both (fallback nhiều tầng) + cooldown chống spam
--               + visited-cache 15p (writefile) + return true/false
--  • Darkbeard farm: module sạch (join-gate, depletion-gate, IsDisabled/island)
--    thay cho khối "KAITUNBOSS FULL SOURCE" cũ (bỏ ~400 dòng lặp + bug)
--  • Giữ nguyên orchestration đa-phase + mọi URL load ngoài
-- ======================================================================

-- ==========================================
-- [ CONFIG AREA ]
-- ==========================================
getgenv().Team = "Pirates"
getgenv().Key  = getgenv().Key or "NHAP_KEY_VAO_DAY"
getgenv().Settings = getgenv().Settings or {
    ["Max Chests"]                 = 30,  -- nhặt tối đa N chest/server rồi hop
    ["Reset After Collect Chests"] = 15,  -- cứ N chest thì tự reset (anti-kick)
    ["Min Chests On Join"]         = 20,  -- #1: mới vào mà chest < N -> hop ngay
}

getgenv().HOP_CONFIG = getgenv().HOP_CONFIG or {
    MaxPlayers    = 9,     -- chỉ hop vào server < N người (nil = bỏ qua)
    ForcedRegion  = nil,   -- "US" / "EU" / "AP" (nil = bỏ qua)
    HopCooldown   = 8,     -- giây tối thiểu giữa 2 lần hop (chống spam teleport)
    CacheDuration = 60,    -- giây cache danh sách server
    MaxPages      = 100,   -- số trang tối đa khi lấy danh sách server
    Verbose       = false, -- true = in log hop chi tiết
}

-- Hằng số cố định (theo yêu cầu)
local LOW_CHEST_LEFT  = 10      -- #2: còn < N chest mà chưa đủ quota -> hop
local REVISIT_SECONDS = 15 * 60 -- #3: không vào lại server cũ trong 15 phút
local DF_TARGET       = 2       -- đủ Dark Fragment thì sang bước SA

-- ==========================================
-- [ GAME LOAD ]
-- ==========================================
if not game:IsLoaded() then game.Loaded:Wait() end
repeat task.wait(0.5) until game:IsLoaded()
    and game.Players.LocalPlayer
    and game.Players.LocalPlayer:FindFirstChildWhichIsA("PlayerGui")
task.wait(1)

getgenv().cloneref       = cloneref or clonereference or function(x) return x end
getgenv().isnetworkowner = isnetworkowner or isNetworkOwner or function() return true end
workspace = cloneref(workspace) or cloneref(Workspace)
    or (getrenv and (getrenv().workspace or getrenv().Workspace))
    or cloneref(game:GetService("Workspace"))
getfenv = getfenv or _G or _ENV or shared or function() return {} end

-- ==========================================
-- [ SERVICES & GLOBALS ]
-- ==========================================
RunService          = game:GetService("RunService")
TweenService        = game:GetService("TweenService")
HttpService         = game:GetService("HttpService")
Players             = game:GetService("Players")
ReplicatedStorage   = game:GetService("ReplicatedStorage")
Lighting            = game:GetService("Lighting")
CollectionService   = game:GetService("CollectionService")
UserInputService    = game:GetService("UserInputService")
VirtualInputManager = game:GetService("VirtualInputManager")
StarterGui          = game:GetService("StarterGui")
GuiService          = game:GetService("GuiService")
TeleportService     = game:GetService("TeleportService")

COMMF_         = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")
LocalPlayer    = Players.LocalPlayer
PlaceId, JobId = game.PlaceId, game.JobId
local Player   = LocalPlayer

LocalPlayer.CharacterAdded:Connect(function(v)
    Character        = v
    Humanoid         = v:WaitForChild("Humanoid")
    HumanoidRootPart = v:WaitForChild("HumanoidRootPart")
end)
if LocalPlayer.Character then
    Character        = LocalPlayer.Character
    Humanoid         = Character:FindFirstChild("Humanoid") or Character:WaitForChild("Humanoid")
    HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart") or Character:WaitForChild("HumanoidRootPart")
end

local success, services = pcall(function()
    return {
        UserInputService = UserInputService,
        CoreGui          = game:GetService("CoreGui"),
        Players          = Players,
        CommF            = COMMF_,
    }
end)
if not success then return end

-- ==========================================
-- [ CHỌN TEAM ]
-- ==========================================
task.spawn(function()
    xpcall(function()
        if not LocalPlayer.Team then
            if LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen") then
                repeat task.wait(1) until not LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen")
            end
            xpcall(function()
                COMMF_:InvokeServer("SetTeam", getgenv().Team)
            end, function()
                firesignal(LocalPlayer.PlayerGui["Main (minimal)"].ChooseTeam.Container[getgenv().Team])
            end)
            task.wait(2)
        end
    end, function(err) warn("[Team]", err) end)
end)

-- LƯU Ý: đoạn "chờ nhân vật spawn" được dời xuống SAU khi tạo UI
-- (tránh kẹt luồng chính khiến UI không bao giờ hiện).

-- ==========================================
-- [ HELPER FUNCTIONS ]
-- ==========================================
-- nil-guard: không crash khi attribute MAP chưa có
function CheckSea(n)
    local map = workspace:GetAttribute("MAP")
    if type(map) ~= "string" then return false end
    local num = tonumber(map:match("%d+"))
    return num ~= nil and n == num
end

-- inventory cache (TTL 1s) — giảm spam getInventory tới server
local _invCache, _invTime = nil, 0
function GetInventory(force)
    if not force and _invCache and (tick() - _invTime) < 1 then return _invCache end
    local ok, inv = pcall(function() return COMMF_:InvokeServer("getInventory") end)
    if ok and type(inv) == "table" then _invCache, _invTime = inv, tick() return inv end
    return _invCache or {}
end
function CheckMaterial(x)
    for _, v in ipairs(GetInventory()) do
        if v.Type == "Material" and v.Name == x then return v.Count or 0 end
    end
    return 0
end
function CheckInventory(...)
    local names = {...}
    for _, v in ipairs(GetInventory()) do
        for _, n in ipairs(names) do if v.Name == n then return true end end
    end
    return false
end
function GetMaterialCount(matName, inv)
    inv = inv or GetInventory()
    for _, item in ipairs(inv) do
        if item.Name == matName then return item.Count or 0 end
    end
    return 0
end

function CheckTool(v)
    for _, x in next, {LocalPlayer.Backpack, Character} do
        if x then
            for _, v2 in next, x:GetChildren() do
                if v2:IsA("Tool") and (v2.Name == v or v2.Name:find(v)) then return true end
            end
        end
    end
    return false
end

-- detect boss kiểu Banana (GetConnectionEnemies): quét ReplicatedStorage TRƯỚC
-- (boss được replicate vào RS ngay khi spawn) -> bắt sớm hơn. Nhận nhiều tên.
function CheckMonster(...)
    local names = {...}
    local function match(m)
        if not (m:IsA("Model") and m.Name ~= "Blank Buddy") then return false end
        local hit = false
        for _, n in ipairs(names) do
            if m.Name == n or m.Name:lower():find(n:lower()) then hit = true break end
        end
        if not hit then return false end
        local h = m:FindFirstChild("Humanoid")
        local r = m:FindFirstChild("HumanoidRootPart")
        return (h and r and h.Health > 0) and true or false
    end
    for _, m in ipairs(ReplicatedStorage:GetChildren()) do if match(m) then return m end end
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies then
        for _, m in ipairs(enemies:GetChildren()) do if match(m) then return m end end
    end
    return false
end

function EquipWeapon(v)
    if not Character then return end
    local tool = Character:FindFirstChildWhichIsA("Tool")
    if tool and tool.ToolTip == v then return end
    for _, x in next, LocalPlayer.Backpack:GetChildren() do
        if x:IsA("Tool") and x.ToolTip == v then Humanoid:EquipTool(x) return end
    end
end

-- FastAttack (giữ nguyên cơ chế obfuscated gốc)
local remoteAttack, idremote
local seed = 0
-- FIX UI: InvokeServer YIELD — để TOP-LEVEL mà remote 'seed' treo sẽ CHẶN luồng chính → UI (tạo bên
-- dưới) KHÔNG BAO GIỜ hiện ("load team không lên UI"). Đẩy vào task.spawn → seed lấy nền, luồng chính
-- chạy thẳng tới tạo UI. FastAttack đọc seed (mặc định 0) → set đúng sau ~tích tắc, không ảnh hưởng.
task.spawn(function()
    pcall(function() seed = ReplicatedStorage.Modules.Net.seed:InvokeServer() end)
end)
task.spawn(function()
    for _, v in next, {ReplicatedStorage:FindFirstChild("Util"), ReplicatedStorage:FindFirstChild("Common"),
                       ReplicatedStorage:FindFirstChild("Remotes"), ReplicatedStorage:FindFirstChild("Assets"),
                       ReplicatedStorage:FindFirstChild("FX")} do
        if v then
            for _, n in next, v:GetChildren() do
                if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remoteAttack, idremote = n, n:GetAttribute("Id") end
            end
            v.ChildAdded:Connect(function(n)
                if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remoteAttack, idremote = n, n:GetAttribute("Id") end
            end)
        end
    end
end)

local lastCallFA = tick()
function FastAttack(x)
    if not HumanoidRootPart or not Character:FindFirstChildWhichIsA("Humanoid")
        or Character.Humanoid.Health <= 0 or not Character:FindFirstChildWhichIsA("Tool") then return end
    if tick() - lastCallFA <= 0.01 then return end
    if not (remoteAttack and idremote) then return end
    local enemies = workspace:FindFirstChild("Enemies"); if not enemies then return end
    local t = {}
    for _, e in next, enemies:GetChildren() do
        local h = e:FindFirstChild("Humanoid") local hrp = e:FindFirstChild("HumanoidRootPart")
        if e ~= Character and (x and e.Name == x or not x) and h and hrp and h.Health > 0
            and (hrp.Position - HumanoidRootPart.Position).Magnitude <= 65 then t[#t + 1] = e end
    end
    if #t == 0 then return end
    local n = ReplicatedStorage.Modules.Net
    local h = {[2] = {}}
    for i = 1, #t do local v = t[i]
        local part = v:FindFirstChild("Head") or v:FindFirstChild("HumanoidRootPart")
        if not h[1] then h[1] = part end
        h[2][#h[2] + 1] = {v, part}
    end
    pcall(function()
        n:FindFirstChild("RE/RegisterAttack"):FireServer()
        n:FindFirstChild("RE/RegisterHit"):FireServer(unpack(h))
        cloneref(remoteAttack):FireServer(string.gsub("RE/RegisterHit", ".", function(c)
            return string.char(bit32.bxor(string.byte(c), math.floor(workspace:GetServerTimeNow()/10%10)+1))
        end), bit32.bxor(idremote+909090, seed*2), unpack(h))
    end)
    lastCallFA = tick()
end

-- ==========================================
-- [ TWEEN (ghost-part, có instant-tp khi gần) ]
-- ==========================================
local function getCFrame(v)
    if not v then return nil end
    if typeof(v) == "CFrame" then return v end
    if typeof(v) == "Vector3" then return CFrame.new(v) end
    if typeof(v) ~= "Instance" then return end
    if v:IsA("BasePart") then return v.CFrame end
    if v:IsA("Model") then
        if v.GetPivot then return v:GetPivot() end
        local root = v.PrimaryPart or v:FindFirstChild("HumanoidRootPart")
        if root then return root.CFrame end
    end
    if v:IsA("CFrameValue") then return v.Value end
    if v:IsA("Vector3Value") then return CFrame.new(v.Value) end
end

local connection, tween, pathPart, isTweening = nil, nil, nil, false
function Tween(targetCFrame, target)
    if targetCFrame == false then
        if tween then pcall(function() tween:Cancel() end) tween = nil end
        if connection then connection:Disconnect() connection = nil end
        if pathPart then pathPart:Destroy() pathPart = nil end
        isTweening = false
        return
    end
    targetCFrame = getCFrame(targetCFrame)
    if isTweening or not targetCFrame then return end
    isTweening = true
    local char = LocalPlayer.Character
    if not char then isTweening = false return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then isTweening = false return end
    humanoid.Sit = false
    target = target or root
    local distance = (targetCFrame.Position - target.Position).Magnitude
    if target == root and distance < 200 then
        target.CFrame = targetCFrame
        isTweening = false
        return
    end
    pathPart = Instance.new("Part")
    pathPart.Name = "TweenGhost"; pathPart.Transparency = 1; pathPart.Anchored = true
    pathPart.CanCollide = false; pathPart.CFrame = target.CFrame; pathPart.Size = Vector3.new(50, 50, 50)
    pathPart.Parent = workspace
    tween = TweenService:Create(pathPart, TweenInfo.new(distance / 275, Enum.EasingStyle.Linear), {CFrame = targetCFrame * (function()
        if target ~= root then return CFrame.new(0, 30, 0) end
        return CFrame.new(0, 5, 0)
    end)()})
    connection = RunService.Heartbeat:Connect(function()
        if target and pathPart then
            target.CFrame = pathPart.CFrame * (function()
                if target ~= root then return CFrame.new(0, 30, 0) end
                return CFrame.new(0, 5, 0)
            end)()
        end
    end)
    tween.Completed:Connect(function()
        if connection then connection:Disconnect() connection = nil end
        if pathPart then pathPart:Destroy() pathPart = nil end
        tween = nil
        isTweening = false
    end)
    tween:Play()
end

function BringMonster(name, count) count = count or 3
    if count < 2 then return end
    pcall(function() setscriptable(LocalPlayer, "SimulationRadius", true) end)
    pcall(function() sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge) end)
    xpcall(function()
        local enemies = workspace:FindFirstChild("Enemies"); if not enemies then return end
        local mob, t = {}, nil
        for _, v in next, enemies:GetChildren() do
            local h   = v:FindFirstChild("Humanoid")
            local hrp = v:FindFirstChild("HumanoidRootPart")
            if h and hrp and h.Health > 0 and (not name or v.Name == name)
                and (HumanoidRootPart.Position - hrp.Position).Magnitude <= (count * 250) then
                mob[#mob+1], t = v, t or hrp.CFrame
                if #mob >= count then break end
            end
        end
        if not t then return end
        for i = 1, #mob do
            local hrp = mob[i]:FindFirstChild("HumanoidRootPart")
            if hrp and (not isnetworkowner or isnetworkowner(hrp)) then
                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = t * CFrame.new((i-1) * 2, 0, 0)
            end
        end
    end, function(r) warn("[BringMonster]: " .. tostring(r)) end)
end

local lastKenCall = tick()
function KillMonster(x)
    xpcall(function()
        local enemies = workspace:FindFirstChild("Enemies")
        if enemies and enemies:FindFirstChild(x) then
            for _, v in next, enemies:GetChildren() do
                local vh   = v:FindFirstChild("Humanoid")
                local vhrp = v:FindFirstChild("HumanoidRootPart")
                if vh and vh.Health > 0 and vhrp and v.Name == x then
                    local dx = HumanoidRootPart.Position.X - vhrp.Position.X
                    local dy = HumanoidRootPart.Position.Y - vhrp.Position.Y
                    local dz = HumanoidRootPart.Position.Z - vhrp.Position.Z
                    if (dx*dx + dy*dy + dz*dz) <= 4900 then
                        BringMonster(x, 3)
                        FastAttack(x)
                        if tick() - lastKenCall >= 10 then
                            lastKenCall = tick()
                            pcall(function() ReplicatedStorage.Remotes.CommE:FireServer("Ken", true) end)
                        end
                        Tween(CFrame.new(vhrp.Position + (vhrp.CFrame.LookVector * 20) + Vector3.new(0, vhrp.Position.Y > 60 and -20 or 20, 0)))
                        EquipWeapon("Melee")
                        return
                    end
                    Tween(vhrp.CFrame) return
                end
            end
        end
        -- boss còn ở ReplicatedStorage -> bay tới (kiểu Banana)
        for _, v in next, ReplicatedStorage:GetChildren() do
            local vhrp = v:FindFirstChild("HumanoidRootPart")
            if v:IsA("Model") and vhrp and v.Name == x then Tween(vhrp.CFrame) return end
        end
    end, function(e) warn("[KillMonster]:", e) end)
end

local WorldsConfig = { ["1"] = "TravelMain", ["2"] = "TravelDressrosa", ["3"] = "TravelZou" }
function TeleportSea(sea, msg)
    local target = WorldsConfig[tostring(sea)]
    if not target then return end
    if msg then pcall(function() print(msg) end) end
    pcall(function() COMMF_:InvokeServer(target) end)
end

local function PressSpace()
    VirtualInputManager:SendKeyEvent(true, "Space", false, game)
    VirtualInputManager:SendKeyEvent(false, "Space", false, game)
end

-- ======================================================================
-- [ VISITED SERVERS — không vào lại server cũ trong 15 phút (#3) ]
--   Lưu ra file vì RAM bị xoá mỗi lần hop.
-- ======================================================================
local VISITED_FILE = "AutoKaitunML7_Visited.json"
local function _loadVisited()
    local t = {}
    pcall(function()
        if isfile and isfile(VISITED_FILE) then
            local ok, dec = pcall(function() return HttpService:JSONDecode(readfile(VISITED_FILE)) end)
            if ok and type(dec) == "table" then t = dec end
        end
    end)
    local now = os.time()
    for jobId, ts in pairs(t) do
        if type(ts) ~= "number" or (now - ts) > REVISIT_SECONDS then t[jobId] = nil end
    end
    return t
end
local function _saveVisited(t)
    pcall(function() if writefile then writefile(VISITED_FILE, HttpService:JSONEncode(t)) end end)
end
local VisitedServers = _loadVisited()
if JobId and JobId ~= "" then
    VisitedServers[JobId] = os.time()
    _saveVisited(VisitedServers)
end
local function IsRecentlyVisited(jobId)
    local ts = VisitedServers[jobId]
    return ts ~= nil and (os.time() - ts) <= REVISIT_SECONDS
end

-- ======================================================================
-- [ HOP SERVER — BEST-OF-BOTH ]
--   cooldown chống spam + return true/false + pcall + stale-cache
--   + fallback nhiều tầng (region -> visited -> toàn bộ -> random teleport)
-- ======================================================================
local function HopLog(...) if getgenv().HOP_CONFIG.Verbose then print("[HOP]", ...) end end

local LastServersDataPulled, CachedServers
local function GetServers()
    if LastServersDataPulled and (os.time() - LastServersDataPulled) < getgenv().HOP_CONFIG.CacheDuration then
        return CachedServers
    end
    for i = 1, getgenv().HOP_CONFIG.MaxPages do
        local ok, data = pcall(function()
            return ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer(i)
        end)
        if ok and type(data) == "table" and next(data) then
            LastServersDataPulled, CachedServers = os.time(), data
            return data
        end
    end
    HopLog("Không fetch được server mới -> dùng cache cũ (nếu có)")
    return CachedServers
end

local function RandomTeleport(reason)
    HopLog("Random teleport:", reason)
    pcall(function() TeleportService:Teleport(PlaceId, LocalPlayer) end)
end

local _lastHop = 0
function HopServer(reason, MaxPlayers, ForcedRegion)
    if tick() - _lastHop < getgenv().HOP_CONFIG.HopCooldown then HopLog("Bỏ qua hop (cooldown)") return false end
    _lastHop = tick()
    MaxPlayers   = MaxPlayers   or getgenv().HOP_CONFIG.MaxPlayers
    ForcedRegion = ForcedRegion or getgenv().HOP_CONFIG.ForcedRegion

    local servers = GetServers()
    if not servers then RandomTeleport("no server data") return true end

    local arr = {}
    for id, v in pairs(servers) do
        if id ~= JobId then
            arr[#arr + 1] = { JobId = id, Players = (v.Count or v.Players or 0), Region = v.Region }
        end
    end
    HopLog("Nhận", #arr, "servers | Lý do:", reason)
    if #arr == 0 then RandomTeleport("empty list") return true end

    local function collect(useRegion, useVisited, useMax)
        local out = {}
        for _, s in ipairs(arr) do
            if ((not useMax) or (not MaxPlayers) or s.Players < MaxPlayers)
               and ((not useRegion) or (not ForcedRegion) or s.Region == ForcedRegion)
               and ((not useVisited) or not IsRecentlyVisited(s.JobId)) then
                out[#out + 1] = s
            end
        end
        return out
    end

    local filtered = collect(true, true, true)                              -- MaxPlayers + Region + chưa vào 15p
    HopLog("Tầng1:", #filtered)
    if #filtered == 0 then filtered = collect(false, true, true)  HopLog("Tầng2 (bỏ region):", #filtered) end
    if #filtered == 0 then filtered = collect(false, false, true) HopLog("Tầng3 (bỏ visited):", #filtered) end
    if #filtered == 0 then filtered = arr                          HopLog("Tầng4 (toàn bộ):", #filtered) end

    local pick = filtered[math.random(1, #filtered)]
    HopLog("Chọn:", pick.JobId, "| Players:", pick.Players, "| Region:", pick.Region)
    pcall(function() ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer("teleport", pick.JobId) end)
    return true
end

-- Cho BananaHub / script ngoài gọi được
getgenv().GetServers = GetServers
getgenv().HopServer  = HopServer

-- ==========================================
-- [ ERROR HANDLING (cooldown trong HopServer chặn spam) ]
-- ==========================================
TeleportService.TeleportInitFailed:Connect(function(_, result, message)
    if result == Enum.TeleportResult.GameFull then
        HopLog("Server đầy -> retry")
        task.delay(2, function() HopServer("retry - game full") end)
    elseif result == Enum.TeleportResult.IsTeleporting and message and message:find("previous teleport") then
        pcall(function() StarterGui:SetCore("SendNotification", { Title = "Death Hop Found", Text = message, Duration = 8 }) end)
        task.delay(10, function() pcall(function() game:Shutdown() end) end)
    else
        HopLog("Teleport fail:", tostring(result), message)
        task.delay(3, function() HopServer("retry - teleport fail") end)
    end
end)

GuiService.ErrorMessageChanged:Connect(function()
    if GuiService:GetErrorType() == Enum.ConnectionError.DisconnectErrors then
        while true do
            pcall(function() TeleportService:TeleportToPlaceInstance(PlaceId, JobId, LocalPlayer) end)
            task.wait(5)
        end
    end
end)

-- ==========================================
-- [ UI ]
-- ==========================================
local guiParent = (gethui and gethui()) or services.CoreGui
if guiParent:FindFirstChild("VFAndSA_UI") then guiParent.VFAndSA_UI:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VFAndSA_UI"
ScreenGui.ResetOnSpawn = false
pcall(function() ScreenGui.Parent = guiParent end)

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 300, 0, 175); MainFrame.Position = UDim2.new(0.5, -150, 0.5, -87)
MainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10); MainFrame.Active = true; MainFrame.Draggable = true
Instance.new("UIStroke", MainFrame).Color = Color3.fromRGB(0, 120, 255)
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, 0, 0, 30); Title.Text = "Sanguine Art Kaitun By Vu Nguyen"
Title.TextColor3 = Color3.fromRGB(0, 150, 255); Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold; Title.TextSize = 14

local Line = Instance.new("Frame", MainFrame)
Line.Size = UDim2.new(1, -20, 0, 1); Line.Position = UDim2.new(0, 10, 0, 30)
Line.BackgroundColor3 = Color3.fromRGB(0, 120, 255); Line.BorderSizePixel = 0

local StatusLabel = Instance.new("TextLabel", MainFrame)
StatusLabel.Size = UDim2.new(1, -20, 0, 20); StatusLabel.Position = UDim2.new(0, 10, 0, 34)
StatusLabel.Text = "Status: Checking..."; StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
StatusLabel.BackgroundTransparency = 1; StatusLabel.Font = Enum.Font.GothamSemibold
StatusLabel.TextSize = 11; StatusLabel.TextXAlignment = Enum.TextXAlignment.Left

local MeleeLabel = Instance.new("TextLabel", MainFrame)
MeleeLabel.Size = UDim2.new(1, -20, 0, 16); MeleeLabel.Position = UDim2.new(0, 10, 0, 54)
MeleeLabel.Text = "🥊 Melee: Checking..."; MeleeLabel.TextColor3 = Color3.fromRGB(0, 150, 255)
MeleeLabel.BackgroundTransparency = 1; MeleeLabel.Font = Enum.Font.GothamSemibold
MeleeLabel.TextSize = 11; MeleeLabel.TextXAlignment = Enum.TextXAlignment.Left

local MatFrame = Instance.new("Frame", MainFrame)
MatFrame.Size = UDim2.new(1, -20, 0, 78); MatFrame.Position = UDim2.new(0, 10, 0, 73)
MatFrame.BackgroundTransparency = 1
Instance.new("UIListLayout", MatFrame).Padding = UDim.new(0, 3)

local MaterialChecks = { {"Dark Fragment", DF_TARGET}, {"Vampire Fang", 20}, {"Demonic Wisp", 20} }
local matLabels = {}
for _, data in ipairs(MaterialChecks) do
    local l = Instance.new("TextLabel", MatFrame)
    l.Size = UDim2.new(1, 0, 0, 16); l.BackgroundTransparency = 1
    l.Text = "📦 " .. data[1] .. ": .../" .. data[2]; l.TextColor3 = Color3.fromRGB(200, 200, 200)
    l.Font = Enum.Font.Gotham; l.TextSize = 11; l.TextXAlignment = Enum.TextXAlignment.Left
    matLabels[data[1]] = l
end
local fragL = Instance.new("TextLabel", MatFrame)
fragL.Size = UDim2.new(1, 0, 0, 16); fragL.BackgroundTransparency = 1
fragL.Text = "💎 Fragment: .../5000"; fragL.TextColor3 = Color3.fromRGB(200, 200, 200)
fragL.Font = Enum.Font.Gotham; fragL.TextSize = 11; fragL.TextXAlignment = Enum.TextXAlignment.Left
matLabels["Fragment"] = fragL

local function SetStatus(txt, color)
    StatusLabel.Text = tostring(txt)
    if color then StatusLabel.TextColor3 = color end
end

local function UpdateMaterials()
    local inv = GetInventory(true)
    for _, data in ipairs(MaterialChecks) do
        local count = GetMaterialCount(data[1], inv)
        local label = matLabels[data[1]]
        if label then
            label.Text = string.format("📦 %s: %d/%d", data[1], count, data[2])
            label.TextColor3 = (count >= data[2]) and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(200, 200, 200)
        end
    end
    local fragCount = 0
    pcall(function() fragCount = Player.Data.Fragments.Value end)
    if matLabels["Fragment"] then
        matLabels["Fragment"].Text = string.format("💎 Fragment: %d/5000", fragCount)
        matLabels["Fragment"].TextColor3 = (fragCount >= 5000) and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(200, 200, 200)
    end
end
UpdateMaterials()
task.spawn(function() while task.wait(10) do UpdateMaterials() end end)

services.UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.LeftAlt then MainFrame.Visible = not MainFrame.Visible end
end)

print("[VFAndSA] ✅ Loaded | LeftAlt ẩn/hiện")

-- Chờ nhân vật sẵn sàng — CÓ TIMEOUT 90s để KHÔNG bao giờ kẹt cứng luồng
do
    SetStatus("Đợi nhân vật spawn...", Color3.fromRGB(0, 150, 255))
    local t0 = tick()
    repeat task.wait(0.5) until (Character
        and Character:FindFirstChild("HumanoidRootPart")
        and Character:FindFirstChildWhichIsA("Humanoid")
        and Character:IsDescendantOf(workspace:FindFirstChild("Characters") or workspace))
        or (tick() - t0 > 90)
    if not (Character and Character:FindFirstChild("HumanoidRootPart")) then
        warn("[VFAndSA] Hết 90s chờ nhân vật — vẫn chạy tiếp (có thể cần chọn team thủ công)")
    end
end

SetStatus("Status: Checking Fragment...", Color3.fromRGB(0, 150, 255))

-- ==========================================
-- [ CHECK FRAGMENT (farm Katakuri tới 5000) ]
-- ==========================================
local fragmentOk = false
task.spawn(function()
    local fragCount = 0
    pcall(function()
        fragCount = Player:FindFirstChild("Data") and Player.Data:FindFirstChild("Fragments")
            and Player.Data.Fragments.Value or 0
    end)
    print("[Fragment] " .. fragCount .. "/5000")

    if fragCount >= 5000 then
        fragmentOk = true
        SetStatus("Fragment: " .. fragCount .. "/5000 ✅", Color3.fromRGB(0, 255, 0))
    else
        SetStatus("Fragment: " .. fragCount .. "/5000 → Farm Katakuri...", Color3.fromRGB(255, 200, 0))
        task.spawn(function()
            while task.wait(15) do
                local cur = 0
                pcall(function() cur = Player.Data.Fragments.Value end)
                SetStatus("Fragment: " .. cur .. "/5000 | Farming...")
                if cur >= 5000 then
                    SetStatus("Fragment: 5000 ✅ KICK!", Color3.fromRGB(0, 255, 0))
                    task.wait(2)
                    Player:Kick("\n[ VFAndSA Kaitun ]\nĐã đủ 5000 Fragments!\nRejoin để tiếp tục.")
                    break
                end
            end
        end)
        task.spawn(function()
            getgenv().NewUI  = true
            getgenv().Config = {
                ["Select Method Farm"] = "Farm Katakuri",
                ["Hop Find Katakuri"]  = true,
                ["Start Farm"]         = true,
            }
            loadstring(game:HttpGet("https://raw.githubusercontent.com/obiiyeuem/vthangsitink/main/BananaHub.lua"))()
        end)
        return
    end
end)

repeat task.wait(1) until fragmentOk

-- ==========================================
-- [ PHẦN 0: CHECK SANGUINE ART STATUS ]
-- ==========================================
local saActive = false
local saChecked = false
task.spawn(function()
    local ok, result = pcall(function() return COMMF_:InvokeServer("BuySanguineArt", true) end)
    if ok then
        if type(result) == "string" and result:lower():find("bring me") then
            saActive = false
            SetStatus("SA: ❌ Chưa active", Color3.fromRGB(255, 100, 100))
        else
            saActive = true
            SetStatus("SA: ✅ Đã active! (" .. tostring(result) .. ")", Color3.fromRGB(0, 255, 0))
        end
    else
        SetStatus("SA: ⚠ Lỗi check", Color3.fromRGB(255, 200, 0))
        warn("[P0] Lỗi check SA:", tostring(result))
    end
    saChecked = true
end)

-- helper: check SA active (dùng nhiều nơi)
local function PollSA()
    local ok, res = pcall(function() return COMMF_:InvokeServer("BuySanguineArt", true) end)
    if ok then
        if type(res) ~= "string" then return true end
        if type(res) == "string" and not res:lower():find("bring me") then return true end
    end
    return false
end

-- ==========================================
-- [ PHẦN 0.5: MELEE ĐANG EQUIP ]
-- ==========================================
local currentMelee = "None"
local function GetEquippedMelee()
    for _, container in ipairs({ Player.Character, Player:FindFirstChild("Backpack") }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and tool.ToolTip == "Melee" then
                    return tool.Name, (container == Player.Character)
                end
            end
        end
    end
    return "None", false
end
task.spawn(function()
    task.wait(1)
    while true do
        local meleeName, holding = GetEquippedMelee()
        currentMelee = meleeName
        if meleeName ~= "None" then
            MeleeLabel.Text = "🥊 Melee: " .. meleeName .. " (" .. (holding and "cầm" or "BP") .. ")"
            MeleeLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        else
            MeleeLabel.Text = "🥊 Melee: Không có"
            MeleeLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        end
        task.wait(5)
    end
end)

-- ==========================================
-- [ CHANGE FOLDER AFTER COMPLETED ]
-- ==========================================
getgenv().ChangeFolderOnCompleted = getgenv().ChangeFolderOnCompleted ~= false
getgenv().id1 = getgenv().id1 or "........."
getgenv().id2 = getgenv().id2 or "........."

local CompletedFolderLock = false

local function NormalizeFolderId(value, allowNil)
    if value == nil then return nil, allowNil end
    local s = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" or s == "........." or s:match("^%.+$") or s:lower() == "nil" then
        return nil, allowNil
    end
    return s, true
end

local function ChangeFolderAfterCompleted(reason)
    if CompletedFolderLock then return false end
    if getgenv().ChangeFolderOnCompleted == false then
        warn("[Completed] ChangeFolderOnCompleted = false - bỏ qua")
        return false
    end
    if not getgenv().client then
        warn("[Completed] getgenv().client chưa set - bỏ qua")
        return false
    end
    if typeof(getgenv().client.ChangeToFolder) ~= "function" then
        warn("[Completed] ChangeToFolder không tồn tại - bỏ qua")
        return false
    end
    local id1, ok1 = NormalizeFolderId(getgenv().id1, false)
    local id2, ok2 = NormalizeFolderId(getgenv().id2, false)
    local id3, _   = NormalizeFolderId(getgenv().id3, true)
    if not ok1 or not ok2 then
        warn("[Completed] id1/id2 rỗng - bỏ qua")
        return false
    end
    CompletedFolderLock = true
    warn(("[Completed] %s -> ChangeToFolder id1=%s id2=%s id3=%s"):format(
        tostring(reason or "Completed"), tostring(id1), tostring(id2),
        id3 == nil and "nil" or tostring(id3)
    ))
    local ok, changed = pcall(function()
        return getgenv().client:ChangeToFolder(id1, id2, true, id3)
    end)
    if not ok then
        warn("[Completed] Lỗi ChangeToFolder: " .. tostring(changed))
        CompletedFolderLock = false
        return false
    end
    if changed then
        warn("[Completed] Đổi folder OK → disconnect + shutdown...")
        pcall(function() getgenv().client:Disconnect() end)
        task.wait(5)
        pcall(function() game:Shutdown() end)
        return true
    else
        warn("[Completed] Đổi folder thất bại")
        task.wait(10)
        CompletedFolderLock = false
        return false
    end
end

-- ==========================================
-- [ HÀM GET SA ]
-- ==========================================
local function RunGetSA()
    print("[getSA] SA active! Check melee...")
    task.wait(2)
    if currentMelee == "Sanguine Art" then
        SetStatus("✅ Có SA! Ghi file...", Color3.fromRGB(0, 255, 0))
        pcall(function() writefile(Player.Name .. ".txt", "Completed-melee") end)
        warn("[getSA] Đã ghi: " .. Player.Name .. ".txt → Completed-melee")
        SetStatus("✅ Completed-melee!")
        ChangeFolderAfterCompleted("Completed-melee")
        return
    end
    SetStatus("SA Active → Chạy getSA...", Color3.fromRGB(255, 200, 0))
    task.spawn(function()
        loadstring(game:HttpGet("https://gist.githubusercontent.com/longvu26092007-eng/2f576450d81d7643d532062f82461464/raw/77db4980c68c917613b9cf04848183606816cf12/getSA"))()
    end)
    while true do
        task.wait(5)
        currentMelee = GetEquippedMelee()
        if currentMelee == "Sanguine Art" then
            SetStatus("✅ Có SA! Ghi file...", Color3.fromRGB(0, 255, 0))
            pcall(function() writefile(Player.Name .. ".txt", "Completed-melee") end)
            warn("[getSA] Đã ghi: " .. Player.Name .. ".txt → Completed-melee")
            SetStatus("✅ Completed-melee!")
            ChangeFolderAfterCompleted("Completed-melee")
            break
        else
            SetStatus("Đợi SA... (" .. currentMelee .. ")", Color3.fromRGB(255, 200, 0))
        end
    end
end

-- helper: load BananaHub farm material (dùng cho VF / DW)
local function LoadMaterialFarm(matName)
    task.spawn(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/longvu26092007-eng/ml7/refs/heads/main/ultmiaxrada.lua"))()
    end)
    task.wait(10)
    task.spawn(function()
        getgenv().NewUI  = true
        getgenv().Config = {
            ["Select Material"] = matName,
            ["Farm Material"]   = true,
            ["Start Farm"]      = true,
            ["Hop Sever"]       = true,
        }
        loadstring(game:HttpGet("https://raw.githubusercontent.com/obiiyeuem/vthangsitink/main/BananaHub.lua"))()
    end)
end

-- ======================================================================
-- [ MODULE: DARKBEARD FARM (blackbeard tối ưu — dùng chung helper) ]
--   #1 join-gate | #2 depletion-gate | IsDisabled/island | spawn+kill
-- ======================================================================
local DARKBEARD_NAMES = { "Darkbeard", "DarkBeard" }
local DARKBEARD_ARENA = CFrame.new(3677.08203125, 62.751937866211, -3144.8332519531)

-- gom + sort chest hợp lệ (tag + CanTouch + tên Chest + not IsDisabled + island)
local function GetValidChests()
    local IslandRoot = getgenv().Settings.IslandRoot
    local chests = {}
    for _, v in ipairs(CollectionService:GetTagged("_ChestTagged")) do
        if v and v:IsA("BasePart") and v.CanTouch and v.Name:find("Chest")
           and not v:GetAttribute("IsDisabled")
           and (not IslandRoot or v:IsDescendantOf(IslandRoot)) then
            chests[#chests + 1] = { obj = v, dist = (v.Position - HumanoidRootPart.Position).Magnitude }
        end
    end
    table.sort(chests, function(a, b) return a.dist < b.dist end)
    return chests
end

local chestsAll = 0
local function CollectChests()
    if CheckTool("Fist of Darkness") then Tween(false) return end
    if chestsAll >= getgenv().Settings["Max Chests"] then
        if HopServer("max chests") then chestsAll = 0 end
        return
    end
    local chests = GetValidChests()
    -- #2: còn < 10 chest mà chưa đủ quota -> hop server giàu hơn
    if #chests < LOW_CHEST_LEFT then
        if not CheckTool("Fist of Darkness") and not CheckMonster("Darkbeard") then
            SetStatus(("Còn %d chest (<%d) | quota %d/%d → hop"):format(#chests, LOW_CHEST_LEFT, chestsAll, getgenv().Settings["Max Chests"]), Color3.fromRGB(0, 180, 255))
            if HopServer("low chests") then chestsAll = 0 end
        end
        return
    end
    local c = 0
    for i, t in ipairs(chests) do
        local v = t.obj
        if CheckTool("Fist of Darkness") then Tween(false) break end
        if CheckMonster("Darkbeard") then break end
        if v and v.Parent and v.CanTouch and Humanoid and Humanoid.Health > 0 then
            local timeout = tick() + 4
            repeat
                task.wait()
                if not (Character and Humanoid and Humanoid.Health > 0) then break end
                Character:PivotTo(v.CFrame)
                pcall(function() firetouchinterest(HumanoidRootPart, v, 0) firetouchinterest(HumanoidRootPart, v, 1) end)
                PressSpace()
            until not v.CanTouch or not v.Parent or CheckTool("Fist of Darkness") or tick() > timeout
            task.delay(2, function() if v then v.CanTouch = false end end)
            c += 1; chestsAll += 1
            SetStatus(("Chest %d | tổng %d/%d"):format(c, chestsAll, getgenv().Settings["Max Chests"]))
            if chestsAll >= getgenv().Settings["Max Chests"] then if HopServer("max chests") then chestsAll = 0 end break end
            if CheckTool("Fist of Darkness") then break end
            if c >= getgenv().Settings["Reset After Collect Chests"] then
                pcall(function() Humanoid:ChangeState(Enum.HumanoidStateType.Dead) end)
                c = 0; task.wait(1)
            end
        end
        if i % 50 == 0 then task.wait() end
    end
    if not CheckTool("Fist of Darkness") and not CheckMonster("Darkbeard") then HopServer("server cleared") end
end

-- #1 join-gate: mới vào mà chest < Min -> hop
local function JoinGate()
    if CheckMaterial("Dark Fragment") >= DF_TARGET then return end
    if CheckTool("Fist of Darkness") then return end
    local minC = getgenv().Settings["Min Chests On Join"]
    if not minC or minC <= 0 then return end
    local t0 = tick()
    while not CheckSea(2) and tick() - t0 < 30 do TeleportSea(2) task.wait(4) end
    if not CheckSea(2) then return end
    SetStatus("Join gate: đếm chest...", Color3.fromRGB(0, 180, 255))
    local n, wt = 0, tick()
    repeat task.wait(1) n = #GetValidChests() until n > 0 or tick() - wt > 8
    if n < minC then
        SetStatus(("Join gate: %d chest < %d → hop"):format(n, minC), Color3.fromRGB(255, 120, 0))
        HopServer("join gate: ít chest (" .. n .. ")")
    end
end

-- chạy farm Darkbeard tới khi đủ DF (monitor kick rejoin / getSA khi SA active)
local function StartDarkbeardFarm()
    SetStatus("P1B: DF " .. CheckMaterial("Dark Fragment") .. "/" .. DF_TARGET .. " → Farm Darkbeard...", Color3.fromRGB(255, 200, 0))
    local stop = false

    -- monitor: SA active -> getSA | đủ DF -> kick rejoin
    task.spawn(function()
        while not stop and task.wait(10) do
            local df = CheckMaterial("Dark Fragment")
            SetStatus("P1B: DF " .. df .. "/" .. DF_TARGET .. " | Farming Darkbeard...")
            if PollSA() then
                saActive = true; stop = true
                SetStatus("P1B: SA Active! → GetSA...", Color3.fromRGB(0, 255, 0))
                RunGetSA(); break
            end
            if df >= DF_TARGET then
                stop = true
                SetStatus("P1B: DF đủ " .. DF_TARGET .. " ✅ KICK!", Color3.fromRGB(0, 255, 0))
                task.wait(2)
                Player:Kick("\n[ VFAndSA Kaitun ]\nĐã đủ " .. DF_TARGET .. " Dark Fragment!\nRejoin để tiếp tục.")
                break
            end
        end
    end)

    -- buy haki (giúp đánh nhanh)
    task.spawn(function()
        while not stop and task.wait(4) do
            xpcall(function()
                if not Character or not Humanoid or Humanoid.Health <= 0 then return end
                if not Character:FindFirstChild("HasBuso") then pcall(function() COMMF_:InvokeServer("Buso") end) end
                for _, v in next, {"Buso", "Geppo", "Soru"} do
                    if not CollectionService:HasTag(Character, v) then
                        local cost = (v == "Geppo" and 1e4) or (v == "Buso" and 2.5e4) or (v == "Soru" and 1e5) or 0
                        if LocalPlayer.Data.Beli.Value >= cost then pcall(function() COMMF_:InvokeServer("BuyHaki", v) end) end
                    end
                end
            end, function(err) warn("[Haki]: " .. tostring(err)) end)
        end
    end)

    JoinGate()

    -- vòng farm chính
    task.spawn(function()
        while not stop and task.wait(0.2) do
            xpcall(function()
                if not CheckSea(2) then
                    SetStatus("Travel sang Sea 2 (Dressrosa)...", Color3.fromRGB(0, 180, 255))
                    TeleportSea(2); task.wait(4); return
                end
                local db = CheckMonster(unpack(DARKBEARD_NAMES))
                if db then
                    SetStatus("⚔️ Đang giết Darkbeard...", Color3.fromRGB(255, 80, 80))
                    repeat task.wait() KillMonster(db.Name)
                    until not db.Parent or not db:FindFirstChild("Humanoid") or db.Humanoid.Health <= 0
                       or CheckMaterial("Dark Fragment") >= DF_TARGET
                    Tween(false)
                elseif CheckTool("Fist of Darkness") then
                    local map = workspace:FindFirstChild("Map")
                    local arena = map and map:FindFirstChild("DarkbeardArena")
                    local detection = arena and arena:FindFirstChild("Summoner") and arena.Summoner:FindFirstChild("Detection")
                    SetStatus("🔮 Spawn Darkbeard...", Color3.fromRGB(180, 100, 255))
                    if detection then
                        Tween(detection.CFrame)
                        if (HumanoidRootPart.Position - detection.Position).Magnitude <= 200 then
                            firetouchinterest(detection, HumanoidRootPart, 0); task.wait(0.2)
                            firetouchinterest(detection, HumanoidRootPart, 1)
                        end
                    else
                        Tween(DARKBEARD_ARENA)
                    end
                else
                    CollectChests()
                end
            end, function(err) warn("[Darkbeard]: " .. tostring(err)) end)
        end
    end)
end

-- ==========================================
-- [ PHẦN 1: ORCHESTRATION ]
-- ==========================================
task.spawn(function()
    repeat task.wait(1) until saChecked

    -- NHÁNH A: SA đã active -> getSA luôn
    if saActive then
        print("[P1] SA active từ đầu → RunGetSA")
        RunGetSA()
        return
    end

    -- NHÁNH B: farm nguyên liệu
    print("[P1B] SA chưa active → check nguyên liệu...")
    local inv = GetInventory(true)
    local dfCount = GetMaterialCount("Dark Fragment", inv)

    if dfCount >= DF_TARGET then
        SetStatus("DF " .. dfCount .. "/" .. DF_TARGET .. " ✅ → check VF...", Color3.fromRGB(0, 255, 0))
        local vfCount = GetMaterialCount("Vampire Fang", inv)

        if vfCount >= 20 then
            local dwCount = GetMaterialCount("Demonic Wisp", inv)
            if dwCount >= 20 then
                SetStatus("Đủ materials! Đợi SA active...", Color3.fromRGB(0, 255, 0))
                task.spawn(function()
                    while true do
                        task.wait(10)
                        if PollSA() then saActive = true
                            SetStatus("SA Active! → GetSA...", Color3.fromRGB(0, 255, 0))
                            RunGetSA(); break
                        end
                    end
                end)
            else
                SetStatus("DW " .. dwCount .. "/20 → Farm...", Color3.fromRGB(255, 200, 0))
                LoadMaterialFarm("Demonic Wisp")
                task.spawn(function()
                    while task.wait(15) do
                        local ci = GetInventory(true)
                        SetStatus(string.format("DW %d/20 | VF %d/20 | DF %d/%d",
                            GetMaterialCount("Demonic Wisp", ci), GetMaterialCount("Vampire Fang", ci),
                            GetMaterialCount("Dark Fragment", ci), DF_TARGET))
                        if PollSA() then saActive = true
                            SetStatus("SA Active! → GetSA...", Color3.fromRGB(0, 255, 0))
                            RunGetSA(); break
                        end
                    end
                end)
            end
        else
            SetStatus("VF " .. vfCount .. "/20 → Farm...", Color3.fromRGB(255, 200, 0))
            LoadMaterialFarm("Vampire Fang")
            task.spawn(function()
                while task.wait(10) do
                    local cur = GetMaterialCount("Vampire Fang")
                    SetStatus("VF " .. cur .. "/20 | Farming...")
                    if PollSA() then saActive = true
                        SetStatus("SA Active! → GetSA...", Color3.fromRGB(0, 255, 0))
                        RunGetSA(); break
                    end
                    if cur >= 20 then
                        SetStatus("VF 20/20 ✅ KICK!", Color3.fromRGB(0, 255, 0))
                        task.wait(2)
                        Player:Kick("\n[ VFAndSA Kaitun ]\nĐã đủ 20/20 Vampire Fang!\nRejoin để tiếp tục.")
                        break
                    end
                end
            end)
        end
    else
        -- PHẦN 1B: chưa đủ DF -> farm Darkbeard (module tối ưu)
        StartDarkbeardFarm()
    end
end)
