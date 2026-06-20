-- ============================================================
--  AUTO BLACKBEARD / AUTO DARK FRAGMENT  (Blox Fruits)
--  Bóc tách + tối ưu từ ml7b.lua (Source_SG) — standalone
--  By Vu Nguyen — phiên bản đã sửa bug
-- ============================================================
--  CƠ CHẾ:
--    1. Travel sang Sea 2 (Dressrosa)
--    2. Farm Chest (_ChestTagged) cho tới khi nhặt được "Fist of Darkness"
--    3. Có Fist of Darkness -> bay tới DarkbeardArena.Summoner.Detection để spawn
--    4. Darkbeard xuất hiện -> kill (FastAttack + Ken + Tween)
--    5. Kill xong nhận "Dark Fragment". Đủ Target -> STOP.
-- ============================================================

-- ==========================================
-- [ CONFIG — CHỈNH Ở ĐÂY ]
-- ==========================================
getgenv().BB_CONFIG = getgenv().BB_CONFIG or {
    TargetDarkFragment      = 2,    -- Dừng khi đủ số Dark Fragment này
    MaxChests               = 30,   -- Nhặt tối đa N chest/server rồi hop
    ResetAfterChests        = 15,   -- Cứ N chest thì tự reset (anti-kick)
    BuyHaki                 = true,  -- Tự mua Buso/Geppo/Soru (giúp đánh Darkbeard)
    ShowUI                  = true,
    IslandRoot              = nil,   -- FIX#12: lọc chest theo đảo (vd workspace.Map.<đảo>); nil = cả Sea 2
    MinChestsOnJoin         = 20,    -- #1: mới vào server mà chest hợp lệ < N -> hop ngay (chỉ farm server "giàu")
}
getgenv().BB_HOP = getgenv().BB_HOP or {
    MaxPlayers   = 9,     -- chỉ hop vào server < N người (nil = bỏ qua)
    ForcedRegion = nil,   -- "US" / "EU" / "AP" (nil = bỏ qua)
    HopCooldown  = 8,     -- giây tối thiểu giữa 2 lần hop (chống spam teleport)
    CacheTime    = 60,    -- giây cache danh sách server
    MaxPages     = 100,   -- số trang tối đa khi lấy danh sách server
    Verbose      = false, -- true = in log chi tiết từng bước hop
}

local CFG = getgenv().BB_CONFIG
local HOP = getgenv().BB_HOP

-- ==========================================
-- [ SERVICES & GLOBALS ]
-- ==========================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui        = game:GetService("StarterGui")
local CoreGui           = game:GetService("CoreGui")
local TeleportService   = game:GetService("TeleportService")
local GuiService        = game:GetService("GuiService")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlaceId, JobId = game.PlaceId, game.JobId
local COMMF_

local cloneref = cloneref or clonereference or function(x) return x end

-- Character refs (tự cập nhật khi respawn) ------------------
local Character, Humanoid, HumanoidRootPart
local function BindCharacter(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
end
LocalPlayer.CharacterAdded:Connect(BindCharacter)
if LocalPlayer.Character then BindCharacter(LocalPlayer.Character) end

-- ==========================================
-- [ LOAD GAME + TEAM = PIRATES ]
-- ==========================================
if not game:IsLoaded() then game.Loaded:Wait() end
COMMF_ = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")

task.spawn(function()
    pcall(function()
        if not LocalPlayer.Team then
            if LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen") then
                repeat task.wait(1) until not LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen")
            end
            local ok = pcall(function() COMMF_:InvokeServer("SetTeam", "Pirates") end)
            if not ok then
                pcall(function() firesignal(LocalPlayer.PlayerGui["Main (minimal)"].ChooseTeam.Container.Pirates) end)
            end
        end
    end)
end)

-- Chờ nhân vật sẵn sàng
repeat task.wait(0.5) until Character
    and Character:FindFirstChild("HumanoidRootPart")
    and Character:FindFirstChildWhichIsA("Humanoid")
    and Character:IsDescendantOf(workspace:FindFirstChild("Characters") or workspace)

-- ==========================================
-- [ UI STATUS (tùy chọn) ]
-- ==========================================
local StatusLabel
local function SetText(txt, color)
    if not StatusLabel then return end
    StatusLabel.Text = tostring(txt)
    if color then StatusLabel.TextColor3 = color end
end
if CFG.ShowUI then
    pcall(function()
        if CoreGui:FindFirstChild("BlackbeardUI") then CoreGui.BlackbeardUI:Destroy() end
        local gui = Instance.new("ScreenGui"); gui.Name = "BlackbeardUI"; gui.ResetOnSpawn = false; gui.Parent = CoreGui
        local f = Instance.new("Frame", gui)
        f.Size = UDim2.new(0, 280, 0, 60); f.Position = UDim2.new(0, 20, 0, 200)
        f.BackgroundColor3 = Color3.fromRGB(10, 10, 10); f.Active = true; f.Draggable = true
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
        Instance.new("UIStroke", f).Color = Color3.fromRGB(120, 0, 200)
        local t = Instance.new("TextLabel", f)
        t.Size = UDim2.new(1, 0, 0, 26); t.BackgroundTransparency = 1
        t.Text = "🗡️ Auto Darkbeard"; t.TextColor3 = Color3.fromRGB(180, 100, 255)
        t.Font = Enum.Font.GothamBold; t.TextSize = 14
        StatusLabel = Instance.new("TextLabel", f)
        StatusLabel.Size = UDim2.new(1, -16, 0, 26); StatusLabel.Position = UDim2.new(0, 8, 0, 28)
        StatusLabel.BackgroundTransparency = 1; StatusLabel.Text = "Đang khởi tạo..."
        StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255); StatusLabel.Font = Enum.Font.GothamSemibold
        StatusLabel.TextSize = 12; StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
        StatusLabel.TextWrapped = true
    end)
end

-- ==========================================
-- [ HELPER: INVENTORY (cache 1s — FIX: giảm spam server) ]
-- ==========================================
local _invCache, _invTime = nil, 0
local function GetInventory(force)
    if not force and _invCache and (tick() - _invTime) < 1 then return _invCache end
    local ok, inv = pcall(function() return COMMF_:InvokeServer("getInventory") end)
    if ok and type(inv) == "table" then
        _invCache, _invTime = inv, tick()
        return inv
    end
    return _invCache or {}
end

local function CheckMaterial(name)
    for _, v in ipairs(GetInventory()) do
        if v.Type == "Material" and v.Name == name then return v.Count or 0 end
    end
    return 0
end

local function CheckInventory(...)
    local names = {...}
    for _, v in ipairs(GetInventory()) do
        for _, n in ipairs(names) do if v.Name == n then return true end end
    end
    return false
end

-- ==========================================
-- [ HELPER: TOOL / MONSTER / SEA ]
-- ==========================================
local function CheckTool(name)
    for _, container in ipairs({LocalPlayer.Backpack, Character}) do
        if container then
            for _, t in ipairs(container:GetChildren()) do
                if t:IsA("Tool") and (t.Name == name or t.Name:find(name)) then return true end
            end
        end
    end
    return false
end

-- FIX#6: detect boss kiểu Banana (GetConnectionEnemies — 2.txt:691)
--   - Quét ReplicatedStorage TRƯỚC: boss (Darkbeard) được replicate vào RS ngay
--     khi spawn, thường trước cả khi parent vào workspace.Enemies -> bắt sớm hơn
--   - Nhận string HOẶC table tên (xử lý biến thể "Darkbeard"/"DarkBeard")
--   - Trả về chính Model để đọc HRP/Position trực tiếp
local function GetConnectionEnemies(name)
    local function match(m)
        if not (m:IsA("Model") and m.Name ~= "Blank Buddy") then return false end
        local ok = (typeof(name) == "table" and table.find(name, m.Name)) or m.Name == name
        if not ok then return false end
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
local function CheckMonster(name) return GetConnectionEnemies(name) end

-- Tên boss + toạ độ arena tham chiếu từ Banana (2.txt:1197-1201)
local DARKBEARD_NAMES = { "Darkbeard", "DarkBeard" }
local DARKBEARD_ARENA = CFrame.new(3677.08203125, 62.751937866211, -3144.8332519531)

-- FIX: an toàn khi attribute MAP chưa có (không còn spam error)
local function CheckSea(n)
    local map = workspace:GetAttribute("MAP")
    if type(map) ~= "string" then return false end
    local num = tonumber(map:match("%d+"))
    return num ~= nil and n == num
end

local Worlds = { [1] = "TravelMain", [2] = "TravelDressrosa", [3] = "TravelZou" }
local function TeleportSea(n)
    local t = Worlds[n]
    if t then pcall(function() COMMF_:InvokeServer(t) end) end
end

-- ==========================================
-- [ COMBAT: FastAttack obfuscated (giữ nguyên cơ chế gốc) ]
-- ==========================================
local remoteAttack, idremote
local seed = 0
pcall(function() seed = ReplicatedStorage.Modules.Net.seed:InvokeServer() end)
task.spawn(function()
    for _, v in ipairs({ReplicatedStorage:FindFirstChild("Util"), ReplicatedStorage:FindFirstChild("Common"),
                        ReplicatedStorage:FindFirstChild("Remotes"), ReplicatedStorage:FindFirstChild("Assets"),
                        ReplicatedStorage:FindFirstChild("FX")}) do
        if v then
            for _, n in ipairs(v:GetChildren()) do
                if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remoteAttack, idremote = n, n:GetAttribute("Id") end
            end
            v.ChildAdded:Connect(function(n)
                if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remoteAttack, idremote = n, n:GetAttribute("Id") end
            end)
        end
    end
end)

local function EquipWeapon(toolTip)
    if not Character then return end
    local cur = Character:FindFirstChildWhichIsA("Tool")
    if cur and cur.ToolTip == toolTip then return end
    for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if t:IsA("Tool") and t.ToolTip == toolTip then Humanoid:EquipTool(t) return end
    end
end

local lastFA = tick()
local function FastAttack(targetName)
    if not HumanoidRootPart or not Character:FindFirstChildWhichIsA("Humanoid")
       or Humanoid.Health <= 0 or not Character:FindFirstChildWhichIsA("Tool") then return end
    if tick() - lastFA <= 0.01 then return end
    local net = ReplicatedStorage.Modules.Net
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies or not (remoteAttack and idremote) then return end
    local hits = { [2] = {} }
    for _, e in ipairs(enemies:GetChildren()) do
        local h = e:FindFirstChild("Humanoid")
        local hrp = e:FindFirstChild("HumanoidRootPart")
        if e ~= Character and (not targetName or e.Name == targetName) and h and hrp and h.Health > 0
           and (hrp.Position - HumanoidRootPart.Position).Magnitude <= 65 then
            local part = e:FindFirstChild("Head") or hrp
            if not hits[1] then hits[1] = part end
            hits[2][#hits[2] + 1] = { e, part }
        end
    end
    if not hits[1] then return end
    pcall(function()
        net:FindFirstChild("RE/RegisterAttack"):FireServer()
        net:FindFirstChild("RE/RegisterHit"):FireServer(unpack(hits))
        cloneref(remoteAttack):FireServer(string.gsub("RE/RegisterHit", ".", function(ch)
            return string.char(bit32.bxor(string.byte(ch), math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1))
        end), bit32.bxor(idremote + 909090, seed * 2), unpack(hits))
    end)
    lastFA = tick()
end

-- ==========================================
-- [ TWEEN (ghost-part, giữ nguyên cơ chế gốc) ]
-- ==========================================
local connection, tween, pathPart, isTweening = nil, nil, nil, false
local function StopTween()
    if tween then pcall(function() tween:Cancel() end) tween = nil end
    if connection then connection:Disconnect() connection = nil end
    if pathPart then pathPart:Destroy() pathPart = nil end
    isTweening = false
end
local function Tween(targetCFrame)
    if not Humanoid or Humanoid.Health <= 0 then
        pcall(function() if workspace:FindFirstChild("TweenGhost") then workspace.TweenGhost:Destroy() end end)
        StopTween() return
    end
    pcall(function() Humanoid.Sit = false end)
    if targetCFrame == false then StopTween() return end
    if isTweening or not targetCFrame then return end
    isTweening = true
    local root = Character:FindFirstChild("HumanoidRootPart")
    if not root then isTweening = false return end
    local distance = (targetCFrame.Position - root.Position).Magnitude
    pathPart = Instance.new("Part")
    pathPart.Name = "TweenGhost"; pathPart.Transparency = 1; pathPart.Anchored = true
    pathPart.CanCollide = false; pathPart.CFrame = root.CFrame; pathPart.Size = Vector3.new(50, 50, 50)
    pathPart.Parent = workspace
    tween = TweenService:Create(pathPart, TweenInfo.new(distance / 250, Enum.EasingStyle.Linear),
        { CFrame = targetCFrame * CFrame.new(0, 5, 0) })
    connection = RunService.Heartbeat:Connect(function()
        if root and pathPart then root.CFrame = pathPart.CFrame * CFrame.new(0, 5, 0) end
    end)
    tween.Completed:Connect(function() StopTween() end)
    tween:Play()
end

local lastKen = tick()
local function KillMonster(name)
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies then
        for _, v in ipairs(enemies:GetChildren()) do
            local h = v:FindFirstChild("Humanoid")
            local hrp = v:FindFirstChild("HumanoidRootPart")
            if v.Name == name and h and h.Health > 0 and hrp then
                local mag = (HumanoidRootPart.Position - hrp.Position).Magnitude
                if mag <= 70 then
                    FastAttack(name)
                    if tick() - lastKen >= 10 then lastKen = tick() pcall(function() ReplicatedStorage.Remotes.CommE:FireServer("Ken", true) end) end
                    Tween(CFrame.new(hrp.Position + (hrp.CFrame.LookVector * 20)
                        + Vector3.new(0, hrp.Position.Y > 60 and -20 or 20, 0)))
                    EquipWeapon("Melee")
                else
                    Tween(hrp.CFrame)
                end
                return
            end
        end
    end
    -- FIX#6: boss còn ở ReplicatedStorage -> bay tới (kiểu Banana/SG)
    for _, v in ipairs(ReplicatedStorage:GetChildren()) do
        local hrp = v:FindFirstChild("HumanoidRootPart")
        if v:IsA("Model") and v.Name == name and hrp then Tween(hrp.CFrame) return end
    end
end

-- ==========================================
-- [ VISITED SERVERS — KHÔNG VÀO LẠI SERVER CŨ TRONG 15 PHÚT ]
--   #3: lưu ra file (writefile) vì RAM bị xoá mỗi lần hop.
--   File: JobId -> os.time() lúc vào. Entry quá 15 phút sẽ bị purge.
-- ==========================================
local VISITED_FILE     = "BB_VisitedServers.json"
local REVISIT_SECONDS  = 15 * 60   -- cố định 15 phút

local function _loadVisited()
    local t = {}
    pcall(function()
        if isfile and isfile(VISITED_FILE) then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(VISITED_FILE)) end)
            if ok and type(decoded) == "table" then t = decoded end
        end
    end)
    local now = os.time()                       -- purge entry cũ
    for jobId, ts in pairs(t) do
        if type(ts) ~= "number" or (now - ts) > REVISIT_SECONDS then t[jobId] = nil end
    end
    return t
end

local function _saveVisited(t)
    pcall(function() if writefile then writefile(VISITED_FILE, HttpService:JSONEncode(t)) end end)
end

local VisitedServers = _loadVisited()
if JobId and JobId ~= "" then                   -- đánh dấu server hiện tại "đã vào"
    VisitedServers[JobId] = os.time()
    _saveVisited(VisitedServers)
end

local function IsRecentlyVisited(jobId)
    local ts = VisitedServers[jobId]
    return ts ~= nil and (os.time() - ts) <= REVISIT_SECONDS
end

-- ==========================================
-- [ HOP SERVER — BEST-OF-BOTH ]
--   blackbeard: cooldown chống spam + return true/false + pcall + stale-cache
--   DRACO V17.3: fallback nhiều tầng (bỏ region → toàn bộ list → random teleport)
--                + TeleportInitFailed error handler
--   #3: bỏ qua server đã vào trong 15 phút (relax ở tầng cuối nếu hết lựa chọn)
-- ==========================================
local function HopLog(...) if HOP.Verbose then print("[HOP]", ...) end end

local _serverCache, _serverTime = nil, 0
local function GetServers()
    -- stale-cache: còn hạn thì trả cache
    if _serverCache and (os.time() - _serverTime) < HOP.CacheTime then return _serverCache end
    for i = 1, (HOP.MaxPages or 100) do
        local ok, data = pcall(function()
            return ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer(i)
        end)
        if ok and type(data) == "table" and next(data) then
            _serverCache, _serverTime = data, os.time()
            return data
        end
    end
    HopLog("Không fetch được server mới → dùng cache cũ (nếu có)")
    return _serverCache   -- degrade mượt: trả cache cũ thay vì nil
end

-- random teleport (lưới an toàn cuối cùng khi không có JobId phù hợp)
local function RandomTeleport(reason)
    HopLog("Random teleport:", reason)
    SetText("Hop random (" .. tostring(reason) .. ")...", Color3.fromRGB(0, 180, 255))
    pcall(function() TeleportService:Teleport(PlaceId, LocalPlayer) end)
end

local _lastHop = 0
local function HopServer(reason)
    -- cooldown chống spam teleport (kể cả khi error-handler gọi dồn)
    if tick() - _lastHop < HOP.HopCooldown then HopLog("Bỏ qua hop (cooldown)") return false end
    _lastHop = tick()
    SetText("Hop server (" .. tostring(reason) .. ")...", Color3.fromRGB(0, 180, 255))

    local servers = GetServers()
    if not servers then
        RandomTeleport("no server data")
        return true
    end

    -- dictionary → mảng, loại server hiện tại
    local arr = {}
    for id, v in pairs(servers) do
        if id ~= JobId then
            arr[#arr + 1] = { JobId = id, Players = (v.Count or v.Players or 0), Region = v.Region }
        end
    end
    HopLog("Nhận", #arr, "servers")
    if #arr == 0 then
        RandomTeleport("empty list")
        return true
    end

    -- lọc theo cờ, relax dần khi hết lựa chọn
    local function collect(useRegion, useVisited, useMax)
        local out = {}
        for _, s in ipairs(arr) do
            if ((not useMax) or (not HOP.MaxPlayers) or s.Players < HOP.MaxPlayers)
               and ((not useRegion) or (not HOP.ForcedRegion) or s.Region == HOP.ForcedRegion)
               and ((not useVisited) or not IsRecentlyVisited(s.JobId)) then
                out[#out + 1] = s
            end
        end
        return out
    end

    -- TẦNG 1: MaxPlayers + Region + chưa vào trong 15p
    local filtered = collect(true, true, true)
    HopLog("Tầng1 (full):", #filtered)
    -- TẦNG 2: bỏ filter region
    if #filtered == 0 then filtered = collect(false, true, true) HopLog("Tầng2 (bỏ region):", #filtered) end
    -- TẦNG 3: bỏ luôn filter "đã vào 15p" (chấp nhận quay lại server cũ)
    if #filtered == 0 then filtered = collect(false, false, true) HopLog("Tầng3 (bỏ visited):", #filtered) end
    -- TẦNG 4: dùng toàn bộ danh sách
    if #filtered == 0 then filtered = arr HopLog("Tầng4 (toàn bộ list):", #filtered) end

    local pick = filtered[math.random(1, #filtered)]
    HopLog("Chọn:", pick.JobId, "| Players:", pick.Players, "| Region:", pick.Region)
    pcall(function() ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer("teleport", pick.JobId) end)
    return true
end

-- ==========================================
-- [ ERROR HANDLING (từ DRACO V17.3, thêm cooldown) ]
-- ==========================================
TeleportService.TeleportInitFailed:Connect(function(_, result, message)
    if result == Enum.TeleportResult.GameFull then
        HopLog("Server đầy → retry")
        task.delay(2, function() HopServer("retry - game full") end)   -- cooldown trong HopServer chặn spam
    elseif result == Enum.TeleportResult.IsTeleporting and message and message:find("previous teleport") then
        pcall(function() StarterGui:SetCore("SendNotification",
            { Title = "Death Hop Found", Text = message, Duration = 8 }) end)
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
-- [ COLLECT CHESTS — FIX: PivotTo + firetouchinterest + timeout ]
-- ==========================================
local function PressSpace()
    VirtualInputManager:SendKeyEvent(true, "Space", false, game)
    VirtualInputManager:SendKeyEvent(false, "Space", false, game)
end

-- gom + sort chest hợp lệ theo khoảng cách (dùng chung cho join-gate, gate #2, CollectChests)
-- FIX#12: lọc chest kiểu Banana (2.txt:6063-6075):
--   • _ChestTagged  → engine quản lý tag, bắt cả chest lồng sâu
--   • not IsDisabled → BỎ chest đã loot (Banana dùng attribute này)
--   • IsDescendantOf(IslandRoot) → chỉ nhặt chest đúng đảo (nil = cả Sea 2)
local function GetValidChests()
    local IslandRoot = CFG.IslandRoot
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

local LOW_CHEST_LEFT = 10   -- #2: cố định — còn dưới 10 chest mà chưa đủ quota thì hop

local chestsAll = 0
local function CollectChests()
    if CheckTool("Fist of Darkness") then Tween(false) return end
    if chestsAll >= CFG.MaxChests then
        if HopServer("max chests") then chestsAll = 0 end
        return
    end

    local chests = GetValidChests()

    -- #2: còn < 10 chest mà chưa gom đủ quota Max Chests -> hop server mới
    -- (không phí thời gian scrape server sắp cạn; sang server giàu chest hơn)
    if #chests < LOW_CHEST_LEFT then
        if not CheckTool("Fist of Darkness") and not CheckMonster("Darkbeard") then
            SetText(("Còn %d chest (<%d), quota %d/%d → hop")
                :format(#chests, LOW_CHEST_LEFT, chestsAll, CFG.MaxChests), Color3.fromRGB(0, 180, 255))
            if HopServer("low chests, quota chưa đủ") then chestsAll = 0 end
        end
        return
    end

    local c = 0
    for i, t in ipairs(chests) do
        local v = t.obj
        if CheckTool("Fist of Darkness") then Tween(false) break end
        if CheckMonster("Darkbeard") then break end
        if v and v.Parent and v.CanTouch and Humanoid and Humanoid.Health > 0 then
            local timeout = tick() + 4   -- FIX: chống kẹt vô hạn 1 chest
            repeat
                task.wait()
                if not (Character and Humanoid and Humanoid.Health > 0) then break end
                Character:PivotTo(v.CFrame)                       -- FIX: PivotTo thay SetPrimaryPartCFrame (deprecated)
                pcall(function()                                  -- FIX: force-touch để chắc chắn nhặt
                    firetouchinterest(HumanoidRootPart, v, 0)
                    firetouchinterest(HumanoidRootPart, v, 1)
                end)
                PressSpace()
            until not v.CanTouch or not v.Parent or CheckTool("Fist of Darkness") or tick() > timeout
            task.delay(2, function() if v then v.CanTouch = false end end)
            c += 1; chestsAll += 1
            SetText(("Chest %d (server) | tổng %d/%d"):format(c, chestsAll, CFG.MaxChests))

            if chestsAll >= CFG.MaxChests then if HopServer("max chests") then chestsAll = 0 end break end
            if CheckTool("Fist of Darkness") then break end
            -- anti-kick: reset định kỳ
            if c >= CFG.ResetAfterChests and not CheckTool("Fist of Darkness") then
                pcall(function() Humanoid:ChangeState(Enum.HumanoidStateType.Dead) end)
                c = 0; task.wait(1)
            end
        end
        if i % 50 == 0 then task.wait() end
    end

    if not CheckTool("Fist of Darkness") and not CheckMonster("Darkbeard") then HopServer("server cleared") end
end

-- ==========================================
-- [ AUTO HAKI (tùy chọn — giúp đánh nhanh hơn) ]
-- ==========================================
if CFG.BuyHaki then
    task.spawn(function()
        while task.wait(5) do
            xpcall(function()
                if not Character or not Humanoid or Humanoid.Health <= 0 then return end
                if not Character:FindFirstChild("HasBuso") then pcall(function() COMMF_:InvokeServer("Buso") end) end
                for _, v in ipairs({ "Buso", "Geppo", "Soru" }) do
                    if not CollectionService:HasTag(Character, v) then
                        local cost = (v == "Geppo" and 1e4) or (v == "Buso" and 2.5e4) or (v == "Soru" and 1e5) or 0
                        if LocalPlayer.Data.Beli.Value >= cost then pcall(function() COMMF_:InvokeServer("BuyHaki", v) end) end
                    end
                end
            end, function(e) warn("[Blackbeard][Haki] " .. tostring(e)) end)
        end
    end)
end

-- ==========================================
-- [ JOIN GATE (#1) — mới vào server: chest hợp lệ < MinChestsOnJoin -> hop ]
-- ==========================================
local function JoinGate()
    -- chỉ gate khi còn phải farm chest
    if CheckMaterial("Dark Fragment") >= CFG.TargetDarkFragment then return end
    if CheckTool("Fist of Darkness") then return end
    if not CFG.MinChestsOnJoin or CFG.MinChestsOnJoin <= 0 then return end

    -- đảm bảo đang ở Sea 2 (nơi farm chest)
    local t0 = tick()
    while not CheckSea(2) and tick() - t0 < 30 do TeleportSea(2) task.wait(4) end
    if not CheckSea(2) then return end

    -- chờ chest stream vào (đếm tới khi >0 hoặc timeout 8s)
    SetText("Join gate: đang đếm chest...", Color3.fromRGB(0, 180, 255))
    local n, wt = 0, tick()
    repeat task.wait(1) n = #GetValidChests() until n > 0 or tick() - wt > 8

    if n < CFG.MinChestsOnJoin then
        SetText(("Join gate: %d chest < %d → hop"):format(n, CFG.MinChestsOnJoin), Color3.fromRGB(255, 120, 0))
        print(("[Blackbeard] Join gate: server %d chest (< %d) → hop"):format(n, CFG.MinChestsOnJoin))
        HopServer("join gate: server ít chest (" .. n .. ")")
        return false   -- đã hop; server mới sẽ chạy lại JoinGate khi script nạp lại
    end
    SetText(("Join gate OK: %d chest"):format(n), Color3.fromRGB(0, 255, 0))
    return true
end

JoinGate()

-- ==========================================
-- [ MAIN LOOP ]
-- ==========================================
local DONE = false
SetText("Bắt đầu farm Dark Fragment...", Color3.fromRGB(255, 200, 0))
print("[Blackbeard] Loaded | Target Dark Fragment = " .. CFG.TargetDarkFragment)

task.spawn(function()
    while task.wait(0.2) do
        if DONE then break end
        xpcall(function()
            -- 1) Đủ Dark Fragment -> DỪNG
            if CheckMaterial("Dark Fragment") >= CFG.TargetDarkFragment then
                DONE = true
                Tween(false)
                SetText("✅ ĐỦ " .. CFG.TargetDarkFragment .. " Dark Fragment! DỪNG.", Color3.fromRGB(0, 255, 0))
                print("[Blackbeard] Hoàn tất: đủ Dark Fragment.")
                return
            end

            -- 2) Không ở Sea 2 -> travel
            if not CheckSea(2) then
                SetText("Travel sang Sea 2 (Dressrosa)...", Color3.fromRGB(0, 180, 255))
                TeleportSea(2)
                task.wait(4)
                return
            end

            -- 3) Darkbeard đang sống -> kill (detect kiểu Banana: RS trước, table tên)
            local db = GetConnectionEnemies(DARKBEARD_NAMES)
            if db then
                SetText("⚔️ Đang giết Darkbeard...", Color3.fromRGB(255, 80, 80))
                repeat
                    task.wait()
                    KillMonster(db.Name)
                until not db.Parent or not db:FindFirstChild("Humanoid") or db.Humanoid.Health <= 0
                    or CheckMaterial("Dark Fragment") >= CFG.TargetDarkFragment
                Tween(false)
                return
            end

            -- 4) Có Fist of Darkness -> spawn Darkbeard
            if CheckTool("Fist of Darkness") then
                local map = workspace:FindFirstChild("Map")
                local arena = map and map:FindFirstChild("DarkbeardArena")
                local summoner = arena and arena:FindFirstChild("Summoner")
                local detection = summoner and summoner:FindFirstChild("Detection")
                SetText("🔮 Spawn Darkbeard...", Color3.fromRGB(180, 100, 255))
                if detection then
                    Tween(detection.CFrame)
                    if (HumanoidRootPart.Position - detection.Position).Magnitude <= 200 then
                        firetouchinterest(detection, HumanoidRootPart, 0); task.wait(0.2)
                        firetouchinterest(detection, HumanoidRootPart, 1)
                    end
                else
                    Tween(DARKBEARD_ARENA)   -- fallback: toạ độ arena Banana (2.txt:1200)
                end
                return
            end

            -- 5) Chưa có item -> farm chest tìm Fist of Darkness
            SetText(("📦 Farm chest tìm Fist of Darkness... (DF: %d/%d)")
                :format(CheckMaterial("Dark Fragment"), CFG.TargetDarkFragment), Color3.fromRGB(255, 200, 0))
            CollectChests()
        end, function(err) warn("[Blackbeard] " .. tostring(err)) end)
    end
end)
