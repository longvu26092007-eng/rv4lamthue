local ENV = (type(getgenv) == "function" and getgenv()) or _G

-- Chống execute trùng làm sinh nhiều FastAttack/BringMob/UI loop cùng lúc.
if ENV.__TYRANT_TRF_STABLE_RUNNING then
    warn("[Auto Tyrant] Script đang chạy - bỏ qua lần execute trùng")
    return
end
ENV.__TYRANT_TRF_STABLE_RUNNING = true
ENV.__TYRANT_TRF_READY = false

ENV.TyrantConfig = ENV.TyrantConfig or {
    Team = "Marines",
    Weapon = "Dragon Talon",
    AutoBuyDragonTalon = true,
    AutoBuso = true,
    TweenSpeed = 330,
    FarmHeight = 18,
    BossHeight = 25,
    AttackDistance = 85,
    AttackDelay = 0.03,
    BringMobs = true,

    -- Phá bình bằng skill của vũ khí đang cầm.
    UseSkillsForVases = true,
    VaseSkillKeys = {"Z", "X", "C"},
    VaseSkillHoldTime = 0.12,
    VaseSkillReleaseDelay = 0.15,
    VaseSkillRetryDelay = 0.18,
    VaseM1Fallback = false,
    VaseAttackHeight = 2,
    VaseStandDistance = 7.5,
    VaseM1Distance = 4,
    VaseMaxAttackAttempts = 12,
    VaseTargetTimeout = 35,
    VaseNoTargetWait = 0.35,
    OriginScanInterval = 1.25,

    -- Giảm tải CPU / FPS drop.
    FastAttackInterval = 0.03,
    BreakableFullScanInterval = 1.75,
    BringMobInterval = 0.15,
    BringDistance = 1500,
    BringTweenSpeed = 300,
    NoclipInterval = 0.30,
    TyrantScanInterval = 0.15,
    MaxVaseTargets = 30
}

-- Cấu hình đánh dấu hoàn thành khi đủ Race + Fragment.
-- Khi đủ điều kiện, script chỉ tạo file <PlayerName>.txt = "Completed-fragment".
-- Không đổi thư mục, không ngắt kết nối và không tắt game.
ENV.fragmenttarget = ENV.fragmenttarget or "........."

local Config = ENV.TyrantConfig

-- Bổ sung giá trị mặc định khi người dùng đã tạo TyrantConfig từ lần chạy trước.
if Config.UseSkillsForVases == nil then Config.UseSkillsForVases = true end
-- Phá 12 bình cố định bằng đủ Z/X/C. Mỗi skill có vị trí đứng và thời gian nhấn riêng.
Config.VaseSkillKeys = {"Z", "X", "C"}
Config.VaseSkillHoldTime = 0.12
Config.VaseSkillReleaseDelay = 0.45
Config.VaseSkillRetryDelay = 0.18
Config.VaseM1Fallback = false
Config.VaseAttackHeight = 1.4
Config.VaseStandDistance = 7.5
Config.VaseM1Distance = nil
Config.VaseMaxAttackAttempts = 12
Config.VaseTargetTimeout = 45
Config.VaseNoTargetWait = tonumber(Config.VaseNoTargetWait) or 0.35
Config.OriginScanInterval = tonumber(Config.OriginScanInterval) or 1.25
Config.FastAttackInterval = tonumber(Config.FastAttackInterval) or 0.03
Config.BreakableFullScanInterval = tonumber(Config.BreakableFullScanInterval) or 1.75
Config.BringMobInterval = tonumber(Config.BringMobInterval) or 0.15
Config.BringDistance = tonumber(Config.BringDistance) or 1500
Config.BringTweenSpeed = tonumber(Config.BringTweenSpeed) or 300
Config.NoclipInterval = tonumber(Config.NoclipInterval) or 0.30
Config.TyrantScanInterval = tonumber(Config.TyrantScanInterval) or 0.15
Config.MaxVaseTargets = tonumber(Config.MaxVaseTargets) or 30

repeat
    task.wait(1)
until game:IsLoaded()
    and game:GetService("Players").LocalPlayer
    and game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local AttackLoaded = false
local Farming = false
local SkillCasting = false
local SkillInputBusy = false
local VaseSkillIndex = 0
local CachedTyrant = nil
local LastTyrantScan = 0
local CachedEyesReady = false
local CachedActiveEyeCount = 0
local EyeReadySince = nil
local CachedEye1 = nil
local CachedEye2 = nil
local CachedEye3 = nil
local CachedEye4 = nil
local EyeConnections = {}
local LastEyeBindAttempt = 0
local CurrentMode = "STARTING"
local CurrentTarget = nil
local LastStatus = ""
local SetStatusLast = ""
local TrackedBreakables = setmetatable({}, {__mode = "k"})
local CachedBreakables = {}
local LastBreakableScan = 0
local VaseModeStartedAt = 0
local LastOriginScan = 0
local InternalSkillReadyAt = {}

-- Cờ chỉ chạy đổi folder đúng 1 lần, tránh gọi liên tục gây spam/disconnect loop.
local FragmentFolderLock = false
local LastFragmentLogAt = 0
local CURRENT_FRAGMENT_LOG_INTERVAL = 30

-- ===== Race target (gate đổi folder) =====
-- ENV.race = "Mink" | "Fishman" | "Skypiea" | "Human" | "Ghoul" | "Cyborg" | "rabbit/shark/angel/..." (alias) | "off" | nil
--   nil / "off" / rỗng -> KHÔNG check race (Completed chỉ phụ thuộc fragmenttarget).
--   Có giá trị       -> phải đạt đúng race đó trước khi ghi Completed-fragment.
local CF_RACE_MAP = {
    rabbit = "Mink", mink = "Mink", shark = "Fishman", fishman = "Fishman",
    angel = "Skypiea", skypiea = "Skypiea", human = "Human",
    ghoul = "Ghoul", cyborg = "Cyborg",
    Mink = "Mink", Fishman = "Fishman", Skypiea = "Skypiea",
    Human = "Human", Ghoul = "Ghoul", Cyborg = "Cyborg",
}
local CF_REROLLABLE = { Mink = true, Fishman = true, Skypiea = true, Human = true }

local function raceOf()
    local d = LocalPlayer:FindFirstChild("Data")
    return (d and d:FindFirstChild("Race") and tostring(d.Race.Value)) or nil
end

-- Forward declare GetCurrentFragments: RaceDriverLoop bên dưới dùng trước khi hàm được định nghĩa.
-- (Sửa lỗi A: RaceDriverLoop gọi nhầm global nil nếu thiếu forward declare.)
local GetCurrentFragments

local function getRaceTarget()
    local raw
    pcall(function() raw = ENV.race end)
    if raw == nil then return nil end
    local key = tostring(raw):lower()
    if key == "" or key == "off" then return false end -- false = explicit off (skip race gate)
    local mapped = CF_RACE_MAP[key]
    if mapped == nil then
        warn(("[Race] ENV.race='%s' khong phai alias hop le -> skip race gate (treated as off)"):format(tostring(raw)))
        return false
    end
    return mapped
end

-- === Driver reroll race ===
-- Chạy nền, mỗi 3s/lần gọi remote phù hợp. Khi race đạt -> biến RaceReady lên true.
local RaceReady = false
local CF_DBG_LAST_LOG = 0
local function dlog(msg)
    warn("[Race] " .. msg)
end
local function RaceDriverLoop(target)
    local lastAct = 0
    dlog(("Driver bat dau, target = %s"):format(target))
    local initWait = 0
    while target and not RaceReady do
        task.wait(0.5)
        initWait = initWait + 0.5
        local cur = raceOf()
        if cur == target then
            RaceReady = true
            dlog(("Race da dat -> %s (RaceReady = true)"):format(target))
            break
        end
        local frag = (GetCurrentFragments and GetCurrentFragments()) or 0
        if CF_REROLLABLE[target] then
            local elapsed = tick() - lastAct
            if frag >= 2500 and (lastAct == 0 or elapsed >= 3) then
                dlog(("Reroll #%d: cur=%s target=%s frag=%d elapsed=%.1f"):format(
                    (lastAct == 0) and 0 or math.floor(elapsed / 3), tostring(cur), target, frag, elapsed))
                -- pcall từng remote để lỗi không giết driver loop (Sửa lỗi C).
                pcall(function()
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("BlackbeardReward", "Reroll", "1")
                end)
                pcall(function()
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("BlackbeardReward", "Reroll", "2")
                end)
                lastAct = tick(); task.wait(1.5)
            elseif frag < 2500 and tick() - CF_DBG_LAST_LOG >= 5 then
                CF_DBG_LAST_LOG = tick()
                dlog(("Cho du frag de reroll: cur=%s target=%s frag=%d/2500"):format(tostring(cur), target, frag))
            end
        elseif target == "Ghoul" and tick() - lastAct >= 3 then
            dlog("Mua Ghoul qua Ectoplasm")
            pcall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("Ectoplasm", "BuyCheck", 4) end)
            task.wait(0.5)
            pcall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("Ectoplasm", "Change", 4) end)
            lastAct = tick(); task.wait(1.5)
        elseif target == "Cyborg" and tick() - lastAct >= 3 then
            dlog("Mua Cyborg qua CyborgTrainer")
            pcall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("CyborgTrainer", "Buy") end)
            lastAct = tick(); task.wait(1.5)
        end
    end
end

do
    local target = getRaceTarget() -- nil = chưa set, false = explicit off, string = cần đạt race này
    if target then
        local cur = raceOf()
        if target == false then
            RaceReady = true -- off -> bỏ qua gate race
        elseif cur == target then
            RaceReady = true
            warn(("[Race] Race hien tai (%s) trung target (%s) -> bo qua driver"):format(tostring(cur), target))
        else
            RaceReady = false
            warn(("[Race] Spawn driver: target=%s, cur=%s"):format(target, tostring(cur)))
            task.spawn(RaceDriverLoop, target)
        end
    else
        RaceReady = true -- chưa set ENV.race -> bỏ qua
        warn("[Race] Khong set ENV.race -> bo qua gate")
    end
end
ENV.RaceTarget = getRaceTarget() or false

local TIKI_CENTER = CFrame.new(-16490.9727, 98.1144867, 1245.58984, -0.034969449, 0, 0.999388516, 0, 1, 0, -0.999388516, 0, -0.034969449)
local TYRANT_ENTRANCE = CFrame.new(-16342.5, 174, 1397)
local ARENA_CENTER = Vector3.new(-16335, 174, 1397)
local DRAGON_TALON_BUY_POS = CFrame.new(5661.616211, 1211.299438, 865.999451)


-- 12 vị trí bình thật trong EagleBossArena do người dùng lấy trực tiếp từ Workspace.
-- Không dùng GetChildren()[index] lúc chạy vì thứ tự child có thể thay đổi; CFrame là khóa ổn định.
local STATIC_VASE_CENTER = Vector3.new(-16275.984642, 157.838229, 1390.372659)
local STATIC_VASE_TARGETS = {
    {Name = "Vase01", Mesh = "Meshes/brokenurns_Cylinder.010", SourceIndex = 19, CFrame = CFrame.new(-16332.5264, 158.071655, 1440.32507, 0.999388874, 0, 0.0349550731, 0, 1, 0, -0.0349550731, 0, 0.999388874)},
    {Name = "Vase02", Mesh = "Meshes/brokenurns_Cylinder.009", SourceIndex = 18, CFrame = CFrame.new(-16335.1641, 158.166733, 1465.64404, 0.999388874, 0, 0.0349550731, 0, 1, 0, -0.0349550731, 0, 0.999388874)},
    {Name = "Vase03", Mesh = "Meshes/brokenurns_Cylinder.009", SourceIndex = 17, CFrame = CFrame.new(-16288.6094, 158.166733, 1470.36816, 0.999388874, 0, 0.0349550731, 0, 1, 0, -0.0349550731, 0, 0.999388874)},
    {Name = "Vase04", Mesh = "Meshes/brokenurns_Cylinder.009", SourceIndex = 16, CFrame = CFrame.new(-16258.001, 156.760635, 1461.40356, 0.999388874, 0, 0.0349550731, 0, 1, 0, -0.0349550731, 0, 0.999388874)},
    {Name = "Vase05", Mesh = "Meshes/brokenurns_Cylinder.014", SourceIndex = 14, CFrame = CFrame.new(-16245.4121, 158.437012, 1463.36597, -0.993159413, 0, 0.116766132, 0, 1, 0, -0.116766132, 0, -0.993159413)},
    {Name = "Vase06", Mesh = "Meshes/brokenurns_Cylinder.009", SourceIndex = 15, CFrame = CFrame.new(-16212.4688, 158.166733, 1466.34387, 0.999388874, 0, 0.0349550731, 0, 1, 0, -0.0349550731, 0, 0.999388874)},
    {Name = "Vase07", Mesh = "Meshes/brokenurns_Cylinder.010", SourceIndex = -1, IsTree = true, CFrame = CFrame.new(-16211.9463, 158.071655, 1322.39807, -0.466439605, 0, -0.884553134, 0, 1, 0, 0.884553134, 0, -0.466439605)},
    {Name = "Vase08", Mesh = "Meshes/brokenurns_Cylinder.009", SourceIndex = 13, CFrame = CFrame.new(-16250.2354, 158.166733, 1313.01941, 0.999388874, 0, 0.0349550731, 0, 1, 0, -0.0349550731, 0, 0.999388874)},
    {Name = "Vase09", Mesh = "Meshes/brokenurns_Cylinder.009", SourceIndex = 12, CFrame = CFrame.new(-16260.2803, 158.166733, 1320.45532, 0.999388874, 0, 0.0349550731, 0, 1, 0, -0.0349550731, 0, 0.999388874)},
    {Name = "Vase10", Mesh = "Meshes/brokenurns_Cylinder.010", SourceIndex = 22, CFrame = CFrame.new(-16296.1162, 157.767914, 1315.79407, -0.463313937, 0, 0.886194229, 0, 1, 0, -0.886194229, 0, -0.463313937)},
    {Name = "Vase11", Mesh = "Meshes/brokenurns_Cylinder.009", SourceIndex = 21, CFrame = CFrame.new(-16286.0586, 155.949478, 1323.83765, 0.999388874, 0, 0.0349550731, 0, 1, 0, -0.0349550731, 0, 0.999388874)},
    {Name = "Vase12", Mesh = "Meshes/brokenurns_Cylinder.009", SourceIndex = 20, CFrame = CFrame.new(-16334.9971, 158.166733, 1321.51672, 0.999388874, 0, 0.0349550731, 0, 1, 0, -0.0349550731, 0, 0.999388874)}
}

local VASE_SKILL_HOLD_TIME = {
    Z = 0.035, -- nhả gần như ngay: Z lao khoảng tối thiểu 100 studs
    X = 0.12,  -- dưới 0.24s để không chuyển sang cưỡi đạn
    C = 0.05
}

local VASE_SKILL_RELEASE_WAIT = {
    Z = 0.65,
    X = 0.50,
    C = 1.45 -- chờ pha bay lên và nổ trở lại StartCFrame
}

local TikiMobs = {
    ["Isle Outlaw"] = true,
    ["Island Boy"] = true,
    ["Sun-kissed Warrior"] = true,
    ["Isle Champion"] = true,
    ["Serpent Hunter"] = true,
    ["Skull Slayer"] = true
}

local function SetStatus(text)
    if LastStatus ~= text then
        LastStatus = text
        SetStatusLast = text
        warn("[Auto Tyrant] " .. text)
    end
end

local function Character()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function Humanoid()
    local char = Character()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function HumanoidRootPart()
    local char = Character()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function Backpack()
    return LocalPlayer:FindFirstChild("Backpack")
end

local function CommF()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CommF_")
end

local function NormalizeName(name)
    return tostring(name or ""):gsub("%s+", ""):lower()
end

local function IsToolMatch(tool, name)
    return tool and tool:IsA("Tool") and NormalizeName(tool.Name) == NormalizeName(name)
end

local function FindTool(name)
    local char = Character()
    local backpack = Backpack()

    if char then
        for _, tool in ipairs(char:GetChildren()) do
            if IsToolMatch(tool, name) then
                return tool
            end
        end
    end

    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if IsToolMatch(tool, name) then
                return tool
            end
        end
    end

    return nil
end

local function FindAnyTool()
    local char = Character()
    local backpack = Backpack()

    if char then
        local tool = char:FindFirstChildWhichIsA("Tool")
        if tool then
            return tool
        end
    end

    if backpack then
        return backpack:FindFirstChildWhichIsA("Tool")
    end

    return nil
end

local function EquipWeapon()
    local hum = Humanoid()
    if not hum then
        return nil
    end

    local requested = FindTool(Config.Weapon)
    if requested then
        if requested.Parent ~= Character() then
            hum:EquipTool(requested)
            task.wait(0.15)
        end
        return FindTool(Config.Weapon)
    end

    local fallback = FindAnyTool()
    if fallback and fallback.Parent ~= Character() then
        hum:EquipTool(fallback)
        task.wait(0.15)
    end

    return Character():FindFirstChildWhichIsA("Tool")
end

local ActivePlayerTween = nil

local function StopPlayerTween()
    if ActivePlayerTween then
        pcall(function()
            ActivePlayerTween:Cancel()
        end)
        ActivePlayerTween = nil
    end
end

-- Tween được lấy theo cơ chế trong buy+farmtalon:
-- tween trực tiếp HumanoidRootPart, chờ đến gần đích rồi hủy và căn lại CFrame.
local function TweenTo(targetCF, speed)
    local hrp = HumanoidRootPart()
    if not hrp or not targetCF then
        return false
    end

    local hum = Humanoid()
    if hum then
        hum.Sit = false
    end

    StopPlayerTween()

    local distance = (hrp.Position - targetCF.Position).Magnitude
    local duration = distance / (speed or Config.TweenSpeed or 300)

    if duration < 0.05 then
        hrp.CFrame = targetCF
        return true
    end

    local tween = TweenService:Create(
        hrp,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        {CFrame = targetCF}
    )
    ActivePlayerTween = tween

    local done = false
    local success = false
    local conn

    conn = tween.Completed:Connect(function(state)
        done = true
        success = state == Enum.PlaybackState.Completed
        if conn then
            conn:Disconnect()
            conn = nil
        end
    end)

    tween:Play()
    local started = tick()

    repeat
        task.wait(0.05)
        hrp = HumanoidRootPart()
        if not hrp then
            break
        end

        if (hrp.Position - targetCF.Position).Magnitude <= 8 then
            success = true
            break
        end
    until done or tick() - started > math.max(duration + 2, 10)

    if ActivePlayerTween == tween then
        ActivePlayerTween = nil
    end

    pcall(function()
        tween:Cancel()
    end)

    if conn then
        conn:Disconnect()
        conn = nil
    end

    hrp = HumanoidRootPart()
    if hrp and (hrp.Position - targetCF.Position).Magnitude <= 12 then
        hrp.CFrame = targetCF
        return true
    end

    return success
end

local function GetEnemyFolders()
    local folders = {}
    local enemies = Workspace:FindFirstChild("Enemies")
    if enemies then
        folders[#folders + 1] = enemies
    end

    local origin = Workspace:FindFirstChild("_WorldOrigin")
    if origin and origin:FindFirstChild("Enemies") then
        folders[#folders + 1] = origin.Enemies
    end

    return folders
end

local function BaseEnemyName(name)
    local clean = tostring(name or "")
    clean = clean:gsub("%s*%[Lv%.%s*%d+%]", "")
    clean = clean:gsub("%s*%[Lv%s*%d+%]", "")
    clean = clean:gsub("%s*%[Boss%]", "")
    clean = clean:gsub("%s*%[Raid Boss%]", "")
    return clean:gsub("%s+$", "")
end

local function IsTikiMob(enemy)
    return enemy and TikiMobs[BaseEnemyName(enemy.Name)] == true
end

local function IsTyrant(enemy)
    if not enemy then
        return false
    end
    return string.find(string.lower(enemy.Name), "tyrant", 1, true) ~= nil
end

local function FindTyrant(forceRefresh)
    if not forceRefresh and tick() - LastTyrantScan < Config.TyrantScanInterval then
        if CachedTyrant and CachedTyrant.Parent then
            local hum = CachedTyrant:FindFirstChildOfClass("Humanoid")
            local root = CachedTyrant:FindFirstChild("HumanoidRootPart")
            if hum and root and hum.Health > 0 then
                return CachedTyrant
            end
        end
        return nil
    end

    LastTyrantScan = tick()
    CachedTyrant = nil

    for _, folder in ipairs(GetEnemyFolders()) do
        for _, enemy in ipairs(folder:GetChildren()) do
            if IsTyrant(enemy) then
                local hum = enemy:FindFirstChildOfClass("Humanoid")
                local root = enemy:FindFirstChild("HumanoidRootPart")
                if hum and root and hum.Health > 0 then
                    CachedTyrant = enemy
                    return enemy
                end
            end
        end
    end

    return nil
end

local function GetNearestTikiMob()
    local root = HumanoidRootPart()
    if not root then
        return nil
    end

    local nearest = nil
    local nearestDistance = math.huge

    for _, folder in ipairs(GetEnemyFolders()) do
        for _, enemy in ipairs(folder:GetChildren()) do
            local hum = enemy:FindFirstChildOfClass("Humanoid")
            local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")

            if hum and enemyRoot and hum.Health > 0 and IsTikiMob(enemy) then
                local distance = (root.Position - enemyRoot.Position).Magnitude
                if distance < nearestDistance then
                    nearest = enemy
                    nearestDistance = distance
                end
            end
        end
    end

    return nearest
end

local function FindTikiOutpost()
    local map = Workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("TikiOutpost")
end

local function FindTikiIslandModel()
    local map = Workspace:FindFirstChild("Map")
    local tiki = map and map:FindFirstChild("TikiOutpost")
    return tiki and tiki:FindFirstChild("IslandModel")
end

-- Đọc số Fragment hiện tại theo đúng pattern đã có trong source:
--   game.Players.LocalPlayer.Data.Fragments.Value  (IntValue)
-- Trả về nil nếu chưa có Data/Fragments (nhân vật chưa load).
-- Gán thay vì `local function` để tương thích với forward declare ở phần race gate
-- (RaceDriverLoop gọi hàm này TRƯỚC khi đến định nghĩa này).
GetCurrentFragments = function()
    local ok, value = pcall(function()
        local data = LocalPlayer and LocalPlayer:FindFirstChild("Data")
        local fragments = data and data:FindFirstChild("Fragments")
        return fragments and fragments.Value or nil
    end)
    if not ok or value == nil then
        return nil
    end
    return tonumber(value)
end

-- Khi đủ Race + Fragment, chỉ ghi file hoàn thành.
-- Không đổi thư mục, không ngắt kết nối và không tắt game.
local function TryWriteCompletedFragment()
    if FragmentFolderLock then
        return true
    end

    local rawTarget = ENV.fragmenttarget
    if rawTarget == nil then
        warn("[Fragment] ENV.fragmenttarget nil - bỏ qua ghi Completed-fragment")
        return false
    end

    local target = tonumber(rawTarget)
    if not target or target <= 0 then
        warn(string.format(
            "[Fragment] ENV.fragmenttarget không hợp lệ (%s) - bỏ qua ghi Completed-fragment",
            tostring(rawTarget)
        ))
        return false
    end

    if not RaceReady then
        return false
    end

    local current = GetCurrentFragments()
    if current == nil or current < target then
        return false
    end

    if type(writefile) ~= "function" then
        warn("[Fragment] Executor không hỗ trợ writefile - chưa thể tạo Completed-fragment")
        return false
    end

    local fileName = tostring((LocalPlayer and LocalPlayer.Name) or "UnknownPlayer") .. ".txt"
    local ok, err = pcall(function()
        writefile(fileName, "Completed-fragment")
    end)

    if not ok then
        warn("[Fragment] Lỗi ghi " .. fileName .. ": " .. tostring(err))
        return false
    end

    FragmentFolderLock = true
    ENV.CompletedFragment = true
    ENV.CompletedFragmentFile = fileName
    ENV.CompletedFragmentRace = raceOf()
    ENV.CompletedFragmentValue = current
    ENV.CompletedFragmentTarget = target
    CurrentMode = "Completed-fragment"

    SetStatus(string.format(
        "Completed-fragment | Race=%s | Fragment=%s/%s",
        tostring(ENV.CompletedFragmentRace or "?"),
        tostring(current),
        tostring(target)
    ))
    warn("[Fragment] Đã ghi " .. fileName .. " = Completed-fragment")
    return true
end

-- Gọi nhẹ mỗi vòng lặp: nếu chưa đủ Fragment thì chỉ log số hiện tại + target
-- theo interval (mặc định 30s). Khi đủ thì ghi Completed-fragment đúng một lần.
local function MaybeCheckFragment()
    if FragmentFolderLock then
        return
    end

    -- Gate race: nếu ENV.race được set mà chưa đạt thì chưa ghi Completed-fragment.
    if not RaceReady then
        local now = tick()
        if now - LastFragmentLogAt >= CURRENT_FRAGMENT_LOG_INTERVAL then
            LastFragmentLogAt = now
            warn(string.format(
                "[Fragment] Đang chờ Race đạt target (race hiện tại = %s) - chưa Completed",
                tostring(raceOf() or "?")
            ))
        end
        return
    end

    local rawTarget = ENV.fragmenttarget
    local target = tonumber(rawTarget)
    if not target or target <= 0 then
        return
    end

    local current = GetCurrentFragments()
    if current == nil then
        return
    end

    if current >= target then
        TryWriteCompletedFragment()
        return
    end

    local now = tick()
    if now - LastFragmentLogAt >= CURRENT_FRAGMENT_LOG_INTERVAL then
        LastFragmentLogAt = now
        warn(string.format(
            "[Fragment] Chưa đủ: hiện tại = %s / target = %s (còn thiếu %s)",
            tostring(current),
            tostring(target),
            tostring(target - current)
        ))
    end
end

-- Có đúng bốn mắt runtime và phải kiểm tra đúng bốn đường dẫn cố định:
--   Workspace.Map.TikiOutpost.IslandModel.Eye1
--   Workspace.Map.TikiOutpost.IslandModel.Eye2
--   Workspace.Map.TikiOutpost.IslandModel.IslandChunks.E.Eye3
--   Workspace.Map.TikiOutpost.IslandModel.IslandChunks.E.Eye4
-- Không dùng GetDescendants(); mỗi lần bind chỉ truy cập trực tiếp theo path O(1).
local FINAL_EYE_COLOR = Color3.fromRGB(255, 57, 57)
local EYE_COLOR_TOLERANCE = 10 / 255
local EYE_READY_STABLE_TIME = 0.75
local EXPECTED_EYE_POSITIONS = {
    Eye1 = Vector3.new(-16186.759766, 196.228531, 1440.732788),
    Eye2 = Vector3.new(-16192.060547, 196.052032, 1440.720825)
}

local function GetEyeContainers()
    local islandModel = FindTikiIslandModel()
    local islandChunks = islandModel and islandModel:FindFirstChild("IslandChunks")
    local chunkE = islandChunks and islandChunks:FindFirstChild("E")
    return islandModel, islandChunks, chunkE
end

local function GetFourEyeParts()
    local islandModel, _, chunkE = GetEyeContainers()
    if not islandModel then
        return nil, nil, nil, nil
    end

    local eye1 = islandModel:FindFirstChild("Eye1")
    local eye2 = islandModel:FindFirstChild("Eye2")
    local eye3 = chunkE and chunkE:FindFirstChild("Eye3")
    local eye4 = chunkE and chunkE:FindFirstChild("Eye4")
    return eye1, eye2, eye3, eye4
end

local function IsCorrectEyePart(eye, expectedName)
    if not eye
        or not eye:IsA("BasePart")
        or eye.Name ~= expectedName
        or not eye:IsDescendantOf(Workspace)
    then
        return false
    end

    local islandModel, _, chunkE = GetEyeContainers()
    if expectedName == "Eye1" or expectedName == "Eye2" then
        if eye.Parent ~= islandModel then
            return false
        end

        local expectedPosition = EXPECTED_EYE_POSITIONS[expectedName]
        return expectedPosition == nil
            or (eye.Position - expectedPosition).Magnitude <= 8
    end

    if expectedName == "Eye3" or expectedName == "Eye4" then
        return chunkE ~= nil and eye.Parent == chunkE
    end

    return false
end

local function IsEyeFullyRed(eye, expectedName)
    if not IsCorrectEyePart(eye, expectedName) then
        return false
    end

    local color = eye.Color
    local colorMatches = math.abs(color.R - FINAL_EYE_COLOR.R) <= EYE_COLOR_TOLERANCE
        and math.abs(color.G - FINAL_EYE_COLOR.G) <= EYE_COLOR_TOLERANCE
        and math.abs(color.B - FINAL_EYE_COLOR.B) <= EYE_COLOR_TOLERANCE

    -- Màu là tín hiệu chính. Transparency được kiểm tra để tránh Part đang ẩn/stream dở.
    -- Không ép Material để Eye3/Eye4 vẫn được nhận nếu runtime dùng vật liệu khác Eye1/Eye2.
    return colorMatches and eye.Transparency <= 0.10
end

local function UpdateEyeCache()
    local ready1 = IsEyeFullyRed(CachedEye1, "Eye1")
    local ready2 = IsEyeFullyRed(CachedEye2, "Eye2")
    local ready3 = IsEyeFullyRed(CachedEye3, "Eye3")
    local ready4 = IsEyeFullyRed(CachedEye4, "Eye4")

    CachedActiveEyeCount = (ready1 and 1 or 0)
        + (ready2 and 1 or 0)
        + (ready3 and 1 or 0)
        + (ready4 and 1 or 0)

    CachedEyesReady = CachedActiveEyeCount == 4

    if CachedEyesReady then
        EyeReadySince = EyeReadySince or tick()
    else
        EyeReadySince = nil
    end
end

local function DisconnectEyeWatchers()
    for _, connection in ipairs(EyeConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    EyeConnections = {}
end

local function InvalidateEyeCache(allowImmediateRebind)
    CachedEye1 = nil
    CachedEye2 = nil
    CachedEye3 = nil
    CachedEye4 = nil
    CachedActiveEyeCount = 0
    CachedEyesReady = false
    EyeReadySince = nil
    if allowImmediateRebind then
        LastEyeBindAttempt = 0
    end
end

local function BindEyeWatchers(force)
    local now = tick()
    if not force and now - LastEyeBindAttempt < 1 then
        return false
    end
    LastEyeBindAttempt = now

    local islandModel, islandChunks, chunkE = GetEyeContainers()
    if not islandModel or not islandChunks or not chunkE then
        InvalidateEyeCache()
        return false
    end

    local eye1, eye2, eye3, eye4 = GetFourEyeParts()
    if not IsCorrectEyePart(eye1, "Eye1")
        or not IsCorrectEyePart(eye2, "Eye2")
        or not IsCorrectEyePart(eye3, "Eye3")
        or not IsCorrectEyePart(eye4, "Eye4")
    then
        InvalidateEyeCache()
        return false
    end

    if CachedEye1 == eye1
        and CachedEye2 == eye2
        and CachedEye3 == eye3
        and CachedEye4 == eye4
        and #EyeConnections > 0
    then
        UpdateEyeCache()
        return true
    end

    DisconnectEyeWatchers()
    CachedEye1 = eye1
    CachedEye2 = eye2
    CachedEye3 = eye3
    CachedEye4 = eye4

    local function WatchEye(eye)
        EyeConnections[#EyeConnections + 1] = eye:GetPropertyChangedSignal("Color"):Connect(UpdateEyeCache)
        EyeConnections[#EyeConnections + 1] = eye:GetPropertyChangedSignal("Transparency"):Connect(UpdateEyeCache)
        EyeConnections[#EyeConnections + 1] = eye.AncestryChanged:Connect(function()
            if not eye:IsDescendantOf(Workspace) then
                DisconnectEyeWatchers()
                InvalidateEyeCache(true)
            end
        end)
    end

    WatchEye(eye1)
    WatchEye(eye2)
    WatchEye(eye3)
    WatchEye(eye4)

    local function RebindOnEyeChange(child)
        if child.Name == "Eye1"
            or child.Name == "Eye2"
            or child.Name == "Eye3"
            or child.Name == "Eye4"
            or child.Name == "IslandChunks"
            or child.Name == "E"
        then
            task.defer(function()
                BindEyeWatchers(true)
            end)
        end
    end

    EyeConnections[#EyeConnections + 1] = islandModel.ChildAdded:Connect(RebindOnEyeChange)
    EyeConnections[#EyeConnections + 1] = islandModel.ChildRemoved:Connect(RebindOnEyeChange)
    EyeConnections[#EyeConnections + 1] = islandChunks.ChildAdded:Connect(RebindOnEyeChange)
    EyeConnections[#EyeConnections + 1] = islandChunks.ChildRemoved:Connect(RebindOnEyeChange)
    EyeConnections[#EyeConnections + 1] = chunkE.ChildAdded:Connect(RebindOnEyeChange)
    EyeConnections[#EyeConnections + 1] = chunkE.ChildRemoved:Connect(function(child)
        if child == CachedEye3 or child == CachedEye4 then
            DisconnectEyeWatchers()
            InvalidateEyeCache(true)
        else
            RebindOnEyeChange(child)
        end
    end)

    UpdateEyeCache()
    return true
end

local function SetupEyeWatcher()
    BindEyeWatchers(true)
end

local function GetTyrantEyeProgress()
    if not CachedEye1
        or not CachedEye2
        or not CachedEye3
        or not CachedEye4
        or not CachedEye1:IsDescendantOf(Workspace)
        or not CachedEye2:IsDescendantOf(Workspace)
        or not CachedEye3:IsDescendantOf(Workspace)
        or not CachedEye4:IsDescendantOf(Workspace)
    then
        BindEyeWatchers(false)
    end

    UpdateEyeCache()
    return CachedActiveEyeCount, 4
end

local function AreTyrantEyesReady()
    local activeEyes = GetTyrantEyeProgress()

    -- Chỉ phá bình khi cả bốn Part đều đỏ liên tục đủ thời gian ổn định.
    return activeEyes == 4
        and CachedEyesReady
        and EyeReadySince ~= nil
        and tick() - EyeReadySince >= EYE_READY_STABLE_TIME
end

local EXCLUDED_DYNAMIC_CONTAINERS = {
    Sounds = true,
    EnemySpawns = true,
    EnemyRegions = true,
    Locations = true,
    Characters = true,
    Enemies = true,
    Boats = true,
    SeaBeasts = true,
    SeaEvents = true,
    NPCs = true,
    Effects = true,
    FX = true
}

local EXCLUDED_BREAKABLE_NAMES = {
    tyrantentrance = true,
    bossarena1 = true,
    bossarena2 = true,
    eye1 = true,
    eye2 = true,
    proxysound = true,
    tweenhost = true,
    tweenghost = true,
    surfproxy = true,
    camera = true
}

local PREFERRED_HIT_PART_NAMES = {
    hitbox = 180,
    main = 150,
    root = 140,
    rootpart = 140,
    primary = 130,
    center = 120,
    core = 110,
    handle = 90,
    collision = 80,
    mesh = 20
}

local VASE_ARENA_RADIUS = 145
local VASE_MAX_BOUND_SIZE = 26
local VASE_DUPLICATE_DISTANCE = 2.75

local function IsExcludedDynamicObject(object)
    local node = object
    while node and node ~= Workspace do
        if EXCLUDED_DYNAMIC_CONTAINERS[node.Name] then
            return true
        end
        node = node.Parent
    end
    return false
end

local function GetDynamicRoot(object)
    if not object or not object.Parent then
        return nil
    end

    local origin = Workspace:FindFirstChild("_WorldOrigin")
    if origin and object:IsDescendantOf(origin) then
        local node = object
        while node.Parent and node.Parent ~= origin do
            if EXCLUDED_DYNAMIC_CONTAINERS[node.Parent.Name] then
                return nil
            end
            node = node.Parent
        end
        return node
    end

    return object
end

local function GetObjectBounds(object)
    if not object or not object.Parent then
        return nil, nil
    end

    if object:IsA("BasePart") then
        return object.CFrame, object.Size
    end

    if object:IsA("Model") then
        local ok, cf, size = pcall(function()
            return object:GetBoundingBox()
        end)
        if ok and cf and size then
            return cf, size
        end
    end

    local minPosition = Vector3.new(math.huge, math.huge, math.huge)
    local maxPosition = Vector3.new(-math.huge, -math.huge, -math.huge)
    local found = false

    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local half = descendant.Size * 0.5
            local position = descendant.Position
            minPosition = Vector3.new(
                math.min(minPosition.X, position.X - half.X),
                math.min(minPosition.Y, position.Y - half.Y),
                math.min(minPosition.Z, position.Z - half.Z)
            )
            maxPosition = Vector3.new(
                math.max(maxPosition.X, position.X + half.X),
                math.max(maxPosition.Y, position.Y + half.Y),
                math.max(maxPosition.Z, position.Z + half.Z)
            )
            found = true
        end
    end

    if not found then
        return nil, nil
    end

    local size = maxPosition - minPosition
    return CFrame.new((minPosition + maxPosition) * 0.5), size
end

local function IsReasonableVaseBounds(cf, size)
    if not cf or not size then
        return false
    end

    local maxSize = math.max(size.X, size.Y, size.Z)
    local minSize = math.min(size.X, size.Y, size.Z)

    return (cf.Position - ARENA_CENTER).Magnitude <= VASE_ARENA_RADIUS
        and maxSize >= 0.25
        and maxSize <= VASE_MAX_BOUND_SIZE
        and minSize >= 0.02
end

local function GetPartScore(part, owner)
    if not part or not part:IsA("BasePart") or not part.Parent then
        return -math.huge
    end

    local maxSize = math.max(part.Size.X, part.Size.Y, part.Size.Z)
    if maxSize > VASE_MAX_BOUND_SIZE or (part.Position - ARENA_CENTER).Magnitude > VASE_ARENA_RADIUS then
        return -math.huge
    end

    local lowerName = string.lower(part.Name)
    if EXCLUDED_BREAKABLE_NAMES[lowerName] then
        return -math.huge
    end

    local score = 0
    for key, value in pairs(PREFERRED_HIT_PART_NAMES) do
        if lowerName == key or string.find(lowerName, key, 1, true) then
            score = math.max(score, value)
        end
    end

    if owner and owner:IsA("Model") and owner.PrimaryPart == part then
        score = score + 120
    end
    if part.CanQuery then score = score + 35 end
    if part.CanTouch then score = score + 25 end
    if part.Transparency < 0.98 then score = score + 20 end
    if maxSize >= 0.4 and maxSize <= 12 then score = score + 30 end

    return score
end

local function GetObjectPart(object)
    if not object or not object.Parent then
        return nil
    end

    if object:IsA("BasePart") then
        return GetPartScore(object, object.Parent) > -math.huge and object or nil
    end

    local bestPart = nil
    local bestScore = -math.huge

    if object:IsA("Model") and object.PrimaryPart then
        local score = GetPartScore(object.PrimaryPart, object)
        if score > bestScore then
            bestPart = object.PrimaryPart
            bestScore = score
        end
    end

    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local score = GetPartScore(descendant, object)
            if score > bestScore then
                bestPart = descendant
                bestScore = score
            end
        end
    end

    return bestPart
end

local function GetVaseAimPosition(object)
    local cf, size = GetObjectBounds(object)
    if cf and size and IsReasonableVaseBounds(cf, size) then
        -- Nhắm vào tâm vật thể, hơi nâng lên để tránh tia skill chạm nền trước.
        return cf.Position + Vector3.new(0, math.clamp(size.Y * 0.08, 0.15, 0.8), 0)
    end

    local part = GetObjectPart(object)
    return part and part.Position or nil
end

local function HasBreakableName(object)
    local name = string.lower(object.Name)
    return string.find(name, "vase", 1, true)
        or string.find(name, "pot", 1, true)
        or string.find(name, "jar", 1, true)
        or string.find(name, "urn", 1, true)
        or string.find(name, "bottle", 1, true)
        or string.find(name, "breakable", 1, true)
        or string.find(name, "destructible", 1, true)
end

local function HasBreakableData(object)
    for _, attribute in ipairs({"Health", "HP", "HitPoints", "Breakable", "Destructible"}) do
        if object:GetAttribute(attribute) ~= nil then
            return true
        end
    end

    for _, valueName in ipairs({"Health", "HP", "HitPoints", "MaxHealth"}) do
        local valueObject = object:FindFirstChild(valueName)
        if valueObject and valueObject:IsA("ValueBase") then
            return true
        end
    end

    local ok, tags = pcall(function()
        return CollectionService:GetTags(object)
    end)
    if ok then
        for _, tag in ipairs(tags) do
            local lowerTag = string.lower(tag)
            if string.find(lowerTag, "break", 1, true)
                or string.find(lowerTag, "destroy", 1, true)
                or string.find(lowerTag, "vase", 1, true)
                or string.find(lowerTag, "pot", 1, true)
            then
                return true
            end
        end
    end

    return false
end

local function CountPhysicalParts(object)
    local count = 0
    local interactive = 0
    local visible = 0

    local function ReadPart(part)
        if not part:IsA("BasePart") then return end
        if (part.Position - ARENA_CENTER).Magnitude > VASE_ARENA_RADIUS then return end
        if math.max(part.Size.X, part.Size.Y, part.Size.Z) > VASE_MAX_BOUND_SIZE then return end

        count = count + 1
        if part.CanQuery or part.CanTouch then interactive = interactive + 1 end
        if part.Transparency < 0.98 then visible = visible + 1 end
    end

    if object:IsA("BasePart") then
        ReadPart(object)
    else
        for _, descendant in ipairs(object:GetDescendants()) do
            ReadPart(descendant)
        end
    end

    return count, interactive, visible
end

local function IsArenaBreakable(object, trusted)
    if not object or not object.Parent or IsExcludedDynamicObject(object) then
        return false
    end

    local lowerName = string.lower(object.Name)
    if EXCLUDED_BREAKABLE_NAMES[lowerName] then
        return false
    end

    if object:FindFirstChildOfClass("Humanoid") then
        return false
    end

    local cf, size = GetObjectBounds(object)
    if not IsReasonableVaseBounds(cf, size) then
        return false
    end

    local count, interactive, visible = CountPhysicalParts(object)
    if count <= 0 or count > 80 then
        return false
    end

    if trusted then
        return interactive > 0 or visible > 0
    end

    return HasBreakableName(object)
        or HasBreakableData(object)
        or (interactive > 0 and visible > 0 and math.max(size.X, size.Y, size.Z) <= 14)
end

local function IsBreakableAlive(object)
    if not object or not object.Parent or not object:IsDescendantOf(Workspace) then
        return false
    end

    for _, name in ipairs({"Health", "HP", "HitPoints"}) do
        local attribute = object:GetAttribute(name)
        if type(attribute) == "number" and attribute <= 0 then
            return false
        end

        local valueObject = object:FindFirstChild(name)
        if valueObject and valueObject:IsA("ValueBase") then
            local value = tonumber(valueObject.Value)
            if value and value <= 0 then
                return false
            end
        end
    end

    return GetVaseAimPosition(object) ~= nil
end

local function FindSmallestCandidateRoot(part, limitRoot)
    if not part or not part.Parent then
        return nil
    end

    local node = part.Parent
    while node and node ~= Workspace do
        if node:IsA("Model") then
            local cf, size = GetObjectBounds(node)
            if IsReasonableVaseBounds(cf, size) then
                return node
            end
        end

        if node == limitRoot then
            break
        end
        node = node.Parent
    end

    return part
end

local function ExtractBreakableCandidates(root, trusted)
    local candidates = {}
    local added = {}

    if not root or not root.Parent then
        return candidates
    end

    local rootCF, rootSize = GetObjectBounds(root)
    if IsReasonableVaseBounds(rootCF, rootSize) and IsArenaBreakable(root, trusted) then
        candidates[1] = root
        return candidates
    end

    local parts = {}
    if root:IsA("BasePart") then
        parts[1] = root
    else
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("BasePart")
                and (descendant.Position - ARENA_CENTER).Magnitude <= VASE_ARENA_RADIUS
                and math.max(descendant.Size.X, descendant.Size.Y, descendant.Size.Z) <= VASE_MAX_BOUND_SIZE
            then
                parts[#parts + 1] = descendant
            end
        end
    end

    for _, part in ipairs(parts) do
        local candidate = FindSmallestCandidateRoot(part, root)
        if candidate and not added[candidate] and IsArenaBreakable(candidate, trusted) then
            added[candidate] = true
            candidates[#candidates + 1] = candidate
        end
    end

    return candidates
end

local function TrackBreakableObject(object, source)
    if not object or typeof(object) ~= "Instance" or not object.Parent then
        return nil
    end

    local trusted = source == "RegenModel"
    local root = source == "RegenModel" and object or (GetDynamicRoot(object) or object)
    local candidates = ExtractBreakableCandidates(root, trusted)
    local first = nil

    for _, candidate in ipairs(candidates) do
        TrackedBreakables[candidate] = {
            Source = source or "Unknown",
            AddedAt = tick()
        }
        first = first or candidate

        if source == "RegenModel" then
            local aim = GetVaseAimPosition(candidate)
            local cf, size = GetObjectBounds(candidate)
            if aim then
                warn(string.format(
                    "[Auto Tyrant] Bình runtime: %s | pos=(%.1f, %.1f, %.1f) | size=(%.1f, %.1f, %.1f)",
                    candidate:GetFullName(),
                    aim.X, aim.Y, aim.Z,
                    size and size.X or 0,
                    size and size.Y or 0,
                    size and size.Z or 0
                ))
            end
        end
    end

    if first then
        LastBreakableScan = 0
    end
    return first
end

local function ScanWorldOriginForBreakables(force)
    local now = tick()
    if not force and now - LastOriginScan < Config.OriginScanInterval then
        return
    end
    LastOriginScan = now

    local origin = Workspace:FindFirstChild("_WorldOrigin")
    if not origin then return end

    for _, child in ipairs(origin:GetChildren()) do
        if not EXCLUDED_DYNAMIC_CONTAINERS[child.Name] then
            TrackBreakableObject(child, "OriginScan")
        end
    end
end

local function GetArenaBreakables(forceRefresh)
    local now = tick()
    if forceRefresh or now - LastBreakableScan >= Config.BreakableFullScanInterval then
        ScanWorldOriginForBreakables(forceRefresh)
        LastBreakableScan = now
    end

    local results = {}
    local positions = {}

    local function IsDuplicatePosition(position)
        for _, previous in ipairs(positions) do
            if (previous - position).Magnitude <= VASE_DUPLICATE_DISTANCE then
                return true
            end
        end
        return false
    end

    for object in pairs(TrackedBreakables) do
        if #results >= Config.MaxVaseTargets then break end

        if IsBreakableAlive(object) and IsArenaBreakable(object, true) then
            local aim = GetVaseAimPosition(object)
            local part = GetObjectPart(object)
            if aim and part and not IsDuplicatePosition(aim) then
                positions[#positions + 1] = aim
                results[#results + 1] = {
                    Object = object,
                    Part = part,
                    AimPosition = aim
                }
            end
        else
            TrackedBreakables[object] = nil
        end
    end

    local root = HumanoidRootPart()
    if root then
        table.sort(results, function(a, b)
            return (a.AimPosition - root.Position).Magnitude < (b.AimPosition - root.Position).Magnitude
        end)
    end

    CachedBreakables = results
    return results
end

local function IsRayClearToVase(originPosition, targetPosition, targetObject)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character, Workspace:FindFirstChild("_WorldOrigin")}
    params.IgnoreWater = true

    local result = Workspace:Raycast(originPosition, targetPosition - originPosition, params)
    if not result then
        return true
    end

    local hit = result.Instance
    return hit == targetObject
        or (targetObject:IsA("Model") and hit:IsDescendantOf(targetObject))
        or (targetObject:IsA("BasePart") and hit == targetObject)
end

local function GetVaseStandCFrame(targetObject, keyName)
    local targetPosition = GetVaseAimPosition(targetObject)
    if not targetPosition then return nil end

    -- X bắn thẳng theo Mouse.Hit. Đứng gần vừa đủ và không dùng chế độ cưỡi đạn.
    local distance = 7.5
    local height = 1.4
    local root = HumanoidRootPart()
    local directions = {}

    local function AddDirection(vector)
        vector = Vector3.new(vector.X, 0, vector.Z)
        if vector.Magnitude < 0.1 then return end
        vector = vector.Unit
        for _, old in ipairs(directions) do
            if old:Dot(vector) > 0.985 then return end
        end
        directions[#directions + 1] = vector
    end

    if root then AddDirection(root.Position - targetPosition) end
    AddDirection(ARENA_CENTER - targetPosition)

    for index = 0, 11 do
        local angle = math.rad(index * 30)
        AddDirection(Vector3.new(math.cos(angle), 0, math.sin(angle)))
    end

    local bestCF = nil
    local bestScore = -math.huge

    for _, direction in ipairs(directions) do
        local standPosition = targetPosition + direction * distance + Vector3.new(0, height, 0)
        local castOrigin = standPosition + Vector3.new(0, 1.5, 0)
        local clear = IsRayClearToVase(castOrigin, targetPosition, targetObject)
        local score = clear and 1000 or 0

        if (standPosition - ARENA_CENTER).Magnitude <= VASE_ARENA_RADIUS then
            score = score + 150
        end
        if root then
            score = score - (standPosition - root.Position).Magnitude * 0.05
        end

        if score > bestScore then
            bestScore = score
            bestCF = CFrame.lookAt(standPosition, targetPosition)
        end
    end

    return bestCF
end


local function GetAttackTargets()
    local root = HumanoidRootPart()
    local targets = {}

    if not root then
        return targets
    end

    if CurrentMode == "VASES" then
        -- Bình chỉ được phá bằng skill Z/X/C; tuyệt đối không gửi RegisterHit/M1.
        return targets
    end

    for _, folder in ipairs(GetEnemyFolders()) do
        for _, enemy in ipairs(folder:GetChildren()) do
            local hum = enemy:FindFirstChildOfClass("Humanoid")
            local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
            local head = enemy:FindFirstChild("Head")
            local valid = false

            if hum and enemyRoot and hum.Health > 0 then
                if CurrentMode == "BOSS" then
                    valid = enemy == CurrentTarget or IsTyrant(enemy)
                elseif CurrentMode == "MOBS" then
                    valid = IsTikiMob(enemy)
                end
            end

            if valid and (enemyRoot.Position - root.Position).Magnitude <= Config.AttackDistance then
                targets[#targets + 1] = {
                    enemy,
                    head or enemyRoot
                }
            end
        end
    end

    return targets
end

local function LoadAttack()
    if AttackLoaded then
        return
    end
    AttackLoaded = true

    local Modules = ReplicatedStorage:WaitForChild("Modules")
    local Net = Modules:WaitForChild("Net")
    local RegisterAttack = Net:WaitForChild("RE/RegisterAttack")
    local RegisterHit = Net:WaitForChild("RE/RegisterHit")

    local remoteAttack, idremote
    local seed = nil
    local lastAttack = 0

    pcall(function()
        seed = Net:WaitForChild("seed"):InvokeServer()
    end)

    local remoteFolders = {
        ReplicatedStorage:FindFirstChild("Util"),
        ReplicatedStorage:FindFirstChild("Common"),
        ReplicatedStorage:FindFirstChild("Remotes"),
        ReplicatedStorage:FindFirstChild("Assets"),
        ReplicatedStorage:FindFirstChild("FX")
    }

    local function GetRemoteAttack()
        if remoteAttack and remoteAttack.Parent and idremote then
            return true
        end

        remoteAttack = nil
        idremote = nil

        for _, folder in ipairs(remoteFolders) do
            if folder then
                for _, obj in ipairs(folder:GetChildren()) do
                    if obj:IsA("RemoteEvent") and obj:GetAttribute("Id") then
                        remoteAttack = obj
                        idremote = obj:GetAttribute("Id")
                        return true
                    end
                end
            end
        end

        return false
    end

    -- Giữ cách của buy+farmtalon: cập nhật remote mã hóa ngay khi game tạo remote mới.
    for _, folder in ipairs(remoteFolders) do
        if folder then
            folder.ChildAdded:Connect(function(obj)
                if obj:IsA("RemoteEvent") and obj:GetAttribute("Id") then
                    remoteAttack = obj
                    idremote = obj:GetAttribute("Id")
                end
            end)
        end
    end

    GetRemoteAttack()

    local function EncryptedRegisterHit(hitData)
        if not seed then
            pcall(function()
                seed = Net:WaitForChild("seed"):InvokeServer()
            end)
        end

        if not GetRemoteAttack() or not seed then
            return false
        end

        pcall(function()
            local encodedName = string.gsub("RE/RegisterHit", ".", function(c)
                return string.char(
                    bit32.bxor(
                        string.byte(c),
                        math.floor(Workspace:GetServerTimeNow() / 10 % 10) + 1
                    )
                )
            end)

            remoteAttack:FireServer(
                encodedName,
                bit32.bxor(idremote + 909090, seed * 2),
                unpack(hitData)
            )
        end)

        return true
    end

    local function FastAttack()
        if SkillCasting or CurrentMode == "VASES" then
            return
        end

        local char = Character()
        local hum = Humanoid()

        if not char or not hum or hum.Health <= 0 then
            return
        end

        if not char:FindFirstChildWhichIsA("Tool") then
            return
        end

        if tick() - lastAttack < (Config.AttackDelay or 0.03) then
            return
        end

        -- Giữ bộ lọc mục tiêu của bản Tyrant để đánh đúng Tiki mob / Tyrant / bình.
        local targets = GetAttackTargets()
        if #targets <= 0 then
            return
        end

        local hitData = {
            [1] = targets[1][2],
            [2] = {}
        }

        for _, data in ipairs(targets) do
            hitData[2][#hitData[2] + 1] = {
                data[1],
                data[2]
            }
        end

        pcall(function()
            RegisterAttack:FireServer()
        end)

        pcall(function()
            RegisterHit:FireServer(unpack(hitData))
        end)

        EncryptedRegisterHit(hitData)
        lastAttack = tick()
    end

    -- Xuất cả hai tên để tương thích hai script.
    ENV.DragonTalonFastAttack = FastAttack
    ENV.TyrantFastAttack = FastAttack

    task.spawn(function()
        -- Script nguồn dùng task.wait() mỗi frame. Giữ cùng cơ chế nhưng có interval để giảm tải.
        while task.wait(Config.FastAttackInterval) do
            if Farming and not SkillCasting then
                pcall(FastAttack)
            end
        end
    end)
end

local function NormalAttack(duration)
    local started = tick()

    repeat
        local tool = EquipWeapon()
        if tool then
            pcall(function()
                tool:Activate()
            end)
        end

        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end)

        if ENV.TyrantFastAttack then
            pcall(ENV.TyrantFastAttack)
        end

        task.wait(0.06)
    until tick() - started >= (duration or 0.6) or FindTyrant()
end

-- Dragon Talon la fighting style (melee): khi da so huu, no KHONG nam trong
-- Backpack/Character duoi dang Tool ma o LocalPlayer.Data.Melee.Value.
-- Chi dua vao FindTool se luon "khong thay" -> script cu di mua lai giua luc danh boss.
local function HasMeleeStyle(styleName)
    local ok, value = pcall(function()
        local data = LocalPlayer:FindFirstChild("Data")
        local melee = data and data:FindFirstChild("Melee")
        return melee and melee.Value or nil
    end)
    if not ok or value == nil then
        return false
    end
    return NormalizeName(value) == NormalizeName(styleName)
end

local function PlayerHasDragonTalon()
    return FindTool("Dragon Talon") ~= nil
        or FindTool("DragonTalon") ~= nil
        or HasMeleeStyle("Dragon Talon")
end

local function BuyDragonTalon()
    -- Da co Dragon Talon (tool hoac fighting style) -> khong mua nua.
    if PlayerHasDragonTalon() then
        return true
    end

    -- Dang co Tyrant/boss thi tuyet doi khong tween di mua (se keo nhan vat khoi boss).
    if FindTyrant() then
        return false
    end

    if not Config.AutoBuyDragonTalon then
        return false
    end

    local commf = CommF()
    if not commf then
        return false
    end

    SetStatus("Đang mua Dragon Talon")
    TweenTo(DRAGON_TALON_BUY_POS, Config.TweenSpeed)
    task.wait(0.8)

    for _ = 1, 15 do
        pcall(function()
            commf:InvokeServer("BuyDragonTalon")
        end)

        task.wait(0.5)
        if PlayerHasDragonTalon() then
            return true
        end
    end

    return false
end

local function EnsureWeapon()
    if FindTool(Config.Weapon) then
        return EquipWeapon()
    end

    -- Chi mua khi that su CHUA co Dragon Talon (ke ca dang fighting style o Data.Melee).
    if NormalizeName(Config.Weapon) == NormalizeName("Dragon Talon")
        and not PlayerHasDragonTalon()
    then
        BuyDragonTalon()
    end

    return EquipWeapon()
end


local function GetAimPosition(target)
    if typeof(target) == "Vector3" then
        return target
    end

    if typeof(target) == "CFrame" then
        return target.Position
    end

    if typeof(target) == "Instance" then
        local part = GetObjectPart(target)
        return part and part.Position or nil
    end

    return nil
end

local function SetSkillAimTarget(target)
    ENV.TyrantSkillAimTarget = GetAimPosition(target)
end

local function InstallSkillAimHook()
    if ENV.TyrantSkillAimHookInstalled then
        return true
    end

    if type(getrawmetatable) ~= "function"
        or type(setreadonly) ~= "function"
        or type(newcclosure) ~= "function"
        or type(getnamecallmethod) ~= "function"
        or type(checkcaller) ~= "function"
    then
        warn("[Auto Tyrant] Executor thiếu metamethod hook; skill vẫn được nhấn nhưng aimbot có thể không khóa mục tiêu")
        return false
    end

    local ok, err = pcall(function()
        local mt = getrawmetatable(game)
        local oldNamecall = mt.__namecall

        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local target = ENV.TyrantSkillAimTarget

            if not checkcaller()
                and target
                and (method == "FireServer" or method == "InvokeServer")
            then
                local args = {...}
                local changed = false

                for index = 1, #args do
                    if typeof(args[index]) == "Vector3" then
                        args[index] = target
                        changed = true
                        break
                    elseif typeof(args[index]) == "CFrame" then
                        args[index] = CFrame.new(target)
                        changed = true
                        break
                    end
                end

                if changed then
                    return oldNamecall(self, unpack(args))
                end
            end

            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)

    if ok then
        ENV.TyrantSkillAimHookInstalled = true
        return true
    end

    warn("[Auto Tyrant] Không cài được skill aim hook: " .. tostring(err))
    return false
end

local DEFAULT_SKILL_COOLDOWNS = {
    Z = 6,
    X = 8,
    C = 12,
    V = 15,
    F = 10
}

local function GetSkillFrame(tool, keyName)
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local main = playerGui and playerGui:FindFirstChild("Main")
    local skills = main and main:FindFirstChild("Skills")
    if not skills or not tool then
        return nil
    end

    local toolSkills = skills:FindFirstChild(tool.Name)
        or skills:FindFirstChild(Config.Weapon)
        or skills:FindFirstChild("Dragon Talon")

    return toolSkills and toolSkills:FindFirstChild(keyName) or nil
end

local function CheckCooldownSkill(tool, keyName)
    if tick() < (InternalSkillReadyAt[keyName] or 0) then
        return false
    end

    local skillFrame = GetSkillFrame(tool, keyName)
    if not skillFrame then
        -- UI đôi khi chưa kịp tạo; vẫn cho LocalScript game nhận phím,
        -- nhưng dùng cooldown nội bộ để tránh spam.
        return true
    end

    local cooldown = skillFrame:FindFirstChild("Cooldown")
    if cooldown and cooldown:IsA("GuiObject") then
        return cooldown.Size.X.Scale <= 0.015 and cooldown.Size.X.Offset <= 2
    end

    return true
end

local function MarkSkillUsed(keyName)
    InternalSkillReadyAt[keyName] = tick() + (DEFAULT_SKILL_COOLDOWNS[keyName] or 7)
end

local function SendSkillKey(keyName, isDown)
    local keyCode = Enum.KeyCode[keyName]

    -- Giữ đúng cách của sharkanchor: gửi chuỗi phím trước.
    local ok = pcall(function()
        VirtualInputManager:SendKeyEvent(isDown, keyName, false, game)
    end)

    if not ok and keyCode then
        ok = pcall(function()
            VirtualInputManager:SendKeyEvent(isDown, keyCode, false, game)
        end)
    end

    return ok
end

local function CastVaseSkill(target, keyName)
    if not Config.UseSkillsForVases or SkillInputBusy then
        return false
    end

    keyName = string.upper(tostring(keyName or ""))
    if keyName ~= "Z" and keyName ~= "X" and keyName ~= "C" then
        return false
    end

    local targetPosition = GetAimPosition(target)
    if not targetPosition then
        return false
    end

    local tool = EnsureWeapon()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not tool or not char or tool.Parent ~= char or not hum or hum.Health <= 0 or not root then
        return false
    end

    if not CheckCooldownSkill(tool, keyName) then
        return false
    end

    SkillInputBusy = true
    SkillCasting = true
    SetSkillAimTarget(targetPosition)
    InstallSkillAimHook()

    local bodyClip = root:FindFirstChild("BodyClip")
    local previousForce = bodyClip and bodyClip.MaxForce
    local keyDown = false
    local success = false

    local ok, err = pcall(function()
        hum.Sit = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        -- Z/X đọc Mouse.Hit liên tục. C không đọc Mouse.Hit nhưng vẫn phải quay đúng hướng.
        local flatLook = Vector3.new(targetPosition.X, root.Position.Y, targetPosition.Z)
        if (flatLook - root.Position).Magnitude > 0.1 then
            root.CFrame = CFrame.lookAt(root.Position, flatLook)
        end

        -- Tắt BodyClip trong lúc LocalScript Dragon Talon tự tạo BodyMover.
        if bodyClip then
            bodyClip.MaxForce = Vector3.zero
            bodyClip.Velocity = Vector3.zero
        end

        task.wait(0.08)
        keyDown = SendSkillKey(keyName, true)
        if not keyDown then
            return
        end

        task.wait(VASE_SKILL_HOLD_TIME[keyName] or Config.VaseSkillHoldTime)
        SendSkillKey(keyName, false)
        keyDown = false
        MarkSkillUsed(keyName)

        task.wait(VASE_SKILL_RELEASE_WAIT[keyName] or Config.VaseSkillReleaseDelay)
        success = true
    end)

    if keyDown then
        SendSkillKey(keyName, false)
    end

    SetSkillAimTarget(nil)

    if bodyClip and bodyClip.Parent then
        bodyClip.MaxForce = previousForce or Vector3.new(100000, 100000, 100000)
        bodyClip.Velocity = Vector3.zero
    end

    SkillCasting = false
    SkillInputBusy = false

    if not ok then
        warn("[Auto Tyrant] Lỗi dùng skill " .. tostring(keyName) .. ": " .. tostring(err))
        return false
    end

    if success then
        task.wait(Config.VaseSkillRetryDelay)
    end

    return success
end

local function GetReadyVaseSkillKey()
    local tool = EnsureWeapon()
    if not tool then
        return nil
    end

    local keys = Config.VaseSkillKeys
    for _ = 1, #keys do
        VaseSkillIndex = VaseSkillIndex % #keys + 1
        local keyName = string.upper(tostring(keys[VaseSkillIndex]))
        if CheckCooldownSkill(tool, keyName) then
            return keyName
        end
    end

    return nil
end

local function UseVaseSkill(targetPosition, keyName)
    keyName = string.upper(tostring(keyName or ""))
    if keyName ~= "Z" and keyName ~= "X" and keyName ~= "C" then
        return false, nil
    end

    if CastVaseSkill(targetPosition, keyName) then
        return true, keyName
    end

    return false, nil
end

local function GetStaticVaseAimPosition(target)
    return target.CFrame.Position + Vector3.new(0, 0.75, 0)
end

local function GetStaticVaseStandCFrame(target, keyName)
    local vasePosition = target.CFrame.Position
    local aimPosition = GetStaticVaseAimPosition(target)
    local inward = Vector3.new(
        STATIC_VASE_CENTER.X - vasePosition.X,
        0,
        STATIC_VASE_CENTER.Z - vasePosition.Z
    )

    if inward.Magnitude < 0.1 then
        inward = Vector3.new(0, 0, -1)
    else
        inward = inward.Unit
    end

    local standPosition

    if keyName == "Z" then
        -- Z luôn lao tối thiểu khoảng 100 studs. Đứng 92 studs phía trong arena
        -- để quỹ đạo dash đi xuyên đúng tâm bình thay vì lao từ ngay cạnh bình.
        standPosition = vasePosition + inward * 92 + Vector3.new(0, 3.0, 0)
    elseif keyName == "C" then
        -- C nổ tại StartCFrame sau khi bay lên. Đặt trục X/Z đúng ngay trên bình.
        standPosition = vasePosition + Vector3.new(0, 3.2, 0)
    else
        -- X nhả nhanh là projectile thẳng theo Mouse.Hit.
        standPosition = vasePosition + inward * 14 + Vector3.new(0, 3.0, 0)
    end

    if keyName == "C" then
        local lookPoint = standPosition + inward * 8
        return CFrame.lookAt(standPosition, lookPoint)
    end

    return CFrame.lookAt(standPosition, aimPosition)
end

local function WaitForVaseSkill(preferredKey, timeout)
    local started = tick()
    local keys = Config.VaseSkillKeys

    while not FindTyrant() and AreTyrantEyesReady() do
        local tool = EnsureWeapon()
        if tool then
            preferredKey = string.upper(tostring(preferredKey or ""))
            if preferredKey ~= "" and CheckCooldownSkill(tool, preferredKey) then
                return preferredKey
            end

            for _, keyName in ipairs(keys) do
                keyName = string.upper(tostring(keyName))
                if CheckCooldownSkill(tool, keyName) then
                    return keyName
                end
            end
        end

        if timeout and tick() - started >= timeout then
            return nil
        end
        task.wait(0.10)
    end

    return nil
end

local function AttackStaticVaseTarget(target, preferredKey)
    if not target or FindTyrant() or not AreTyrantEyesReady() then
        return false
    end

    local keyName = WaitForVaseSkill(preferredKey, 15)
    if not keyName then
        return false
    end

    local aimPosition = GetStaticVaseAimPosition(target)
    local standCF = GetStaticVaseStandCFrame(target, keyName)
    if not aimPosition or not standCF then
        return false
    end

    SetStatus(string.format(
        "Bình %s | skill %s | (%.1f, %.1f, %.1f)",
        target.Name,
        keyName,
        aimPosition.X,
        aimPosition.Y,
        aimPosition.Z
    ))

    TweenTo(standCF, Config.TweenSpeed)

    local root = HumanoidRootPart()
    if not root then
        return false
    end

    -- Căn tuyệt đối về CFrame riêng của từng skill trước khi nhấn phím.
    StopPlayerTween()
    root.CFrame = standCF
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    task.wait(0.10)

    -- Khóa lại tâm bình ngay sát thời điểm LocalScript đọc Mouse.Hit.
    SetSkillAimTarget(aimPosition)
    local used, usedKey = UseVaseSkill(aimPosition, keyName)
    SetSkillAimTarget(nil)

    if used then
        warn(string.format(
            "[Auto Tyrant] Cast %s -> %s @ %.2f, %.2f, %.2f",
            tostring(usedKey),
            target.Name,
            aimPosition.X,
            aimPosition.Y,
            aimPosition.Z
        ))
    end

    return used
end

-- Giữ tên hàm cũ để các phần khác không lỗi, nhưng đầu vào giờ là target tĩnh.
local function AttackVaseTarget(target)
    if type(target) == "table" and target.CFrame then
        return AttackStaticVaseTarget(target, nil)
    end
    return false
end


local function TargetCFrame(targetPart, height)
    local position = targetPart.Position + Vector3.new(0, height, 0)
    return CFrame.new(position, targetPart.Position)
end

local function FarmEnemy(enemy, isBoss)
    local hum = enemy and enemy:FindFirstChildOfClass("Humanoid")
    local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")

    if not hum or not enemyRoot or hum.Health <= 0 then
        return
    end

    CurrentTarget = enemy
    CurrentMode = isBoss and "BOSS" or "MOBS"

    local stuckAt = tick()
    local previousHealth = hum.Health

    while Farming and ENV.__TYRANT_TRF_READY
        and enemy.Parent and hum.Parent and enemyRoot.Parent and hum.Health > 0
    do
        local root = HumanoidRootPart()
        local playerHum = Humanoid()

        if not root or not playerHum or playerHum.Health <= 0 then
            break
        end

        EnsureWeapon()

        local height = isBoss and Config.BossHeight or Config.FarmHeight
        local target = TargetCFrame(enemyRoot, height)
        local distance = (root.Position - enemyRoot.Position).Magnitude

        if distance > 80 then
            TweenTo(target, Config.TweenSpeed)
        else
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero

            local followTween = TweenService:Create(
                root,
                TweenInfo.new(0.08, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
                {CFrame = target}
            )
            followTween:Play()
            followTween.Completed:Wait()
        end

        if hum.Health < previousHealth then
            previousHealth = hum.Health
            stuckAt = tick()
        elseif tick() - stuckAt > 15 then
            root.CFrame = target
            NormalAttack(0.5)
            stuckAt = tick()
        end

        task.wait(0.05)
    end

    CurrentTarget = nil
end

local function BreakTyrantVases()
    CurrentMode = "VASES"
    CurrentTarget = nil
    VaseModeStartedAt = tick()
    SetStatus("Đủ 4/4 mắt đỏ - phá 12 bình theo CFrame cố định bằng Z/X/C")

    -- Đi thẳng vào tâm thật của 12 bình, không dùng TyrantEntrance cũ có Y quá cao.
    local entryCF = CFrame.lookAt(
        STATIC_VASE_CENTER + Vector3.new(0, 8, 0),
        STATIC_VASE_CENTER
    )
    TweenTo(entryCF, Config.TweenSpeed)
    task.wait(0.25)

    local pass = 0
    local keys = Config.VaseSkillKeys

    while Farming and ENV.__TYRANT_TRF_READY
        and AreTyrantEyesReady() and not FindTyrant()
    do
        pass = pass + 1

        for index, target in ipairs(STATIC_VASE_TARGETS) do
            if FindTyrant() or not AreTyrantEyesReady() then
                return
            end

            -- Dịch vòng skill theo từng lượt để cùng một bình lần lượt được Z, X và C ghim vào.
            local preferredIndex = ((index + pass - 2) % #keys) + 1
            local preferredKey = string.upper(tostring(keys[preferredIndex]))
            AttackStaticVaseTarget(target, preferredKey)
            task.wait(0.08)
        end

        SetStatus(string.format("Đã quét đủ 12 CFrame - lượt %d, chờ bình hồi/spawn boss", pass))
        task.wait(0.35)
    end
end


local function SetupRegenTracker()
    -- Không cần theo dõi RegenModel/_WorldOrigin nữa vì 12 bình đã có CFrame cố định.
    -- Giữ hàm rỗng để phần khởi tạo phía dưới không phải thay đổi.
end


local function SetupCharacterSupport()
    local noclipConnection = nil

    local function ApplyCharacterSupport(char)
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end

        if not char then
            return
        end

        local function NoclipObject(object)
            if object:IsA("BasePart") then
                object.CanCollide = false
            end
        end

        for _, object in ipairs(char:GetDescendants()) do
            NoclipObject(object)
        end

        noclipConnection = char.DescendantAdded:Connect(NoclipObject)
    end

    ApplyCharacterSupport(LocalPlayer.Character)
    LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.2)
        ApplyCharacterSupport(char)
    end)

    task.spawn(function()
        while task.wait(Config.NoclipInterval) do
            if Farming then
                local root = HumanoidRootPart()
                if root then
                    local bodyClip = root:FindFirstChild("BodyClip")
                    if not bodyClip then
                        bodyClip = Instance.new("BodyVelocity")
                        bodyClip.Name = "BodyClip"
                        bodyClip.MaxForce = Vector3.new(100000, 100000, 100000)
                        bodyClip.Velocity = Vector3.zero
                        bodyClip.Parent = root
                    elseif not SkillCasting then
                        bodyClip.MaxForce = Vector3.new(100000, 100000, 100000)
                        bodyClip.Velocity = Vector3.zero
                    end
                end
            end
        end
    end)
end

local ActiveMobTweens = setmetatable({}, {__mode = "k"})

local function TweenObject(object, targetCF, speed)
    speed = speed or Config.BringTweenSpeed or 300

    if not object or not object.Parent or not targetCF then
        return
    end

    local distance = (targetCF.Position - object.Position).Magnitude
    if distance <= 3 then
        local oldTween = ActiveMobTweens[object]
        if oldTween then
            pcall(function()
                oldTween:Cancel()
            end)
            ActiveMobTweens[object] = nil
        end
        object.CFrame = targetCF
        return
    end

    -- Hủy tween cũ trước khi tạo tween mới để không chồng hàng chục tween trên cùng một mob.
    local oldTween = ActiveMobTweens[object]
    if oldTween then
        pcall(function()
            oldTween:Cancel()
        end)
    end

    local duration = distance / math.max(speed, 1)
    local tween = TweenService:Create(
        object,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        {CFrame = targetCF}
    )
    ActiveMobTweens[object] = tween

    tween.Completed:Connect(function()
        if ActiveMobTweens[object] == tween then
            ActiveMobTweens[object] = nil
        end
    end)

    tween:Play()
end

-- Gom theo cơ chế của buy+farmtalon:
-- tính vị trí trung bình theo tên quái rồi tween các quái cùng loại về một cụm.
local function SetupBringMobs()
    if not Config.BringMobs then
        return
    end

    task.spawn(function()
        local lastSimulationRadius = 0

        while task.wait(Config.BringMobInterval) do
            if CurrentMode == "MOBS" and not SkillCasting then
                local root = HumanoidRootPart()
                local enemiesFolder = Workspace:FindFirstChild("Enemies")

                if root and enemiesFolder then
                    if tick() - lastSimulationRadius >= 1 then
                        lastSimulationRadius = tick()
                        pcall(function()
                            setscriptable(LocalPlayer, "SimulationRadius", true)
                        end)
                        pcall(function()
                            sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
                        end)
                    end

                    local enemies = enemiesFolder:GetChildren()
                    local groups = {}

                    -- Một lượt duy nhất để tính tổng/vị trí trung bình, tránh O(n^2) như bản nguồn.
                    for _, enemy in ipairs(enemies) do
                        if IsTikiMob(enemy) then
                            local hum = enemy:FindFirstChildOfClass("Humanoid")
                            local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")

                            if hum and enemyRoot and hum.Health > 0
                                and (enemyRoot.Position - root.Position).Magnitude <= Config.BringDistance
                            then
                                local key = BaseEnemyName(enemy.Name)
                                local group = groups[key]

                                if not group then
                                    group = {
                                        PositionSum = Vector3.zero,
                                        Count = 0,
                                        Members = {}
                                    }
                                    groups[key] = group
                                end

                                group.PositionSum = group.PositionSum + enemyRoot.Position
                                group.Count = group.Count + 1
                                group.Members[#group.Members + 1] = {
                                    Humanoid = hum,
                                    Root = enemyRoot
                                }
                            end
                        end
                    end

                    for _, group in pairs(groups) do
                        if group.Count > 1 then
                            local averagePosition = group.PositionSum / group.Count
                            local targetCF = CFrame.new(averagePosition)

                            for _, member in ipairs(group.Members) do
                                local hum = member.Humanoid
                                local enemyRoot = member.Root

                                if hum.Parent and enemyRoot.Parent and hum.Health > 0 then
                                    local distance = (enemyRoot.Position - averagePosition).Magnitude

                                    if distance > 3 and distance <= Config.BringDistance then
                                        pcall(function()
                                            enemyRoot.CanCollide = false
                                            enemyRoot.AssemblyLinearVelocity = Vector3.zero
                                            enemyRoot.AssemblyAngularVelocity = Vector3.zero

                                            local animator = hum:FindFirstChild("Animator")
                                            if animator then
                                                animator:Destroy()
                                            end

                                            TweenObject(enemyRoot, targetCF, Config.BringTweenSpeed)
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function SetupTeamAndSea()
    local wantedTeam = tostring(Config.Team or "Marines")
    if wantedTeam == "Pirate" then wantedTeam = "Pirates" end
    if wantedTeam ~= "Marines" and wantedTeam ~= "Pirates" then
        wantedTeam = "Marines"
    end
    Config.Team = wantedTeam

    Farming = false
    ENV.__TYRANT_TRF_READY = false

    local function HasCorrectTeam()
        local teamObject = LocalPlayer.Team
        return teamObject ~= nil and tostring(teamObject.Name) == wantedTeam
    end

    local function CharacterReady()
        local gui = LocalPlayer:FindFirstChild("PlayerGui")
        local loadingScreen = gui and gui:FindFirstChild("LoadingScreen")
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        return not loadingScreen
            and char ~= nil
            and hum ~= nil
            and hum.Health > 0
            and root ~= nil
            and backpack ~= nil
            and char:IsDescendantOf(Workspace)
    end

    local function ClickChooseTeamButton()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return false end

        local wantedWord = wantedTeam == "Marines" and "marine" or "pirate"
        local clicked = false
        for _, object in ipairs(playerGui:GetDescendants()) do
            if object:IsA("GuiButton") then
                local label = string.lower(tostring(object.Name or ""))
                if object:IsA("TextButton") then
                    label = label .. " " .. string.lower(tostring(object.Text or ""))
                end

                if string.find(label, wantedWord, 1, true) then
                    local ok = pcall(function()
                        if type(firesignal) == "function" then
                            firesignal(object.Activated)
                        else
                            object:Activate()
                        end
                    end)
                    clicked = clicked or ok
                end
            end
        end
        return clicked
    end

    local function EnsureTeamAndCharacter()
        local attempt = 0
        while not HasCorrectTeam() do
            attempt = attempt + 1
            SetStatus(string.format("Đang chọn team %s (lần %d)", wantedTeam, attempt))

            local remote = CommF()
            if remote then
                pcall(function()
                    remote:InvokeServer("SetTeam", wantedTeam)
                end)
            end

            if not HasCorrectTeam() then
                pcall(ClickChooseTeamButton)
            end

            task.wait(math.min(2, 0.55 + attempt * 0.08))
        end

        while not CharacterReady() do
            SetStatus("Đã chọn team - đang chờ Character load hoàn chỉnh")
            task.wait(0.5)
        end

        return true
    end

    EnsureTeamAndCharacter()

    -- Giữ đúng hành vi bản trf: xác nhận team xong mới gọi TravelZou.
    if Workspace:GetAttribute("MAP") and Workspace:GetAttribute("MAP") ~= "Sea3" then
        SetStatus("Đã chọn team - đang sang Sea 3")
        local remote = CommF()
        if remote then
            pcall(function()
                remote:InvokeServer("TravelZou")
            end)
        end
        task.wait(1)
    end

    ENV.__TYRANT_TRF_READY = true
    Farming = true
    SetStatus("Team + Character đã sẵn sàng - bắt đầu Auto Tyrant")

    -- Watchdog nhẹ: nếu team/Character mất sau respawn thì dừng toàn bộ farm trước,
    -- khôi phục xong mới bật lại. Không tạo thêm attack/bring loop.
    task.spawn(function()
        while task.wait(2) do
            if not HasCorrectTeam() or not CharacterReady() then
                Farming = false
                ENV.__TYRANT_TRF_READY = false
                pcall(StopPlayerTween)
                SetStatus("Mất team/Character - tạm dừng và khôi phục")
                EnsureTeamAndCharacter()
                ENV.__TYRANT_TRF_READY = true
                Farming = true
                SetStatus("Đã khôi phục team/Character - tiếp tục chạy")
            end

            if Farming and Config.AutoBuso then
                local char = LocalPlayer.Character
                if char and not char:FindFirstChild("HasBuso") then
                    local remote = CommF()
                    if remote then
                        pcall(function()
                            remote:InvokeServer("Buso")
                        end)
                    end
                end
            end
        end
    end)

    return true
end

if not SetupTeamAndSea() then
    ENV.__TYRANT_TRF_STABLE_RUNNING = false
    return
end
SetupEyeWatcher()
SetupCharacterSupport()
SetupBringMobs()
SetupRegenTracker()
InstallSkillAimHook()
LoadAttack()

-- ===== Lightweight Status UI (debug) =====
-- ScreenGui cố định góc trên trái, hiện: race, frag, raceReady, mode, target status.
-- Toggle bằng phím K (mặc định). Có thể tắt bằng ENV.UI_HIDE = true.
do
    if pcall(function()
        local ps = game:GetService("Players")
        local pgui = ps.LocalPlayer and ps.LocalPlayer:FindFirstChild("PlayerGui")
        return pgui and true or false
    end) then
        local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", 5)
        if PlayerGui and not ENV.TyrantUI then
            local gui = Instance.new("ScreenGui")
            gui.Name = "TyrantDebugUI"
            gui.ResetOnSpawn = false
            gui.IgnoreGuiInset = true
            gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

            -- Frame chính
            local frame = Instance.new("Frame")
            frame.Name = "MainFrame"
            frame.Size = UDim2.new(0, 320, 0, 160)
            frame.Position = UDim2.new(0, 10, 0, 10)
            frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
            frame.BackgroundTransparency = 0.05
            frame.BorderSizePixel = 0
            frame.Parent = gui
            Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
            Instance.new("UIStroke", frame).Color = Color3.fromRGB(80, 80, 110)
            Instance.new("UIStroke", frame).Thickness = 1
            Instance.new("UIStroke", frame).Transparency = 0.4

            -- Title bar (kéo được)
            local titleBar = Instance.new("Frame")
            titleBar.Name = "TitleBar"
            titleBar.Size = UDim2.new(1, 0, 0, 26)
            titleBar.Position = UDim2.new(0, 0, 0, 0)
            titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
            titleBar.BackgroundTransparency = 0
            titleBar.BorderSizePixel = 0
            titleBar.Parent = frame
            Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

            local title = Instance.new("TextLabel")
            title.Name = "Title"
            title.Size = UDim2.new(1, -70, 1, 0)
            title.Position = UDim2.new(0, 10, 0, 0)
            title.BackgroundTransparency = 1
            title.Font = Enum.Font.GothamBold
            title.TextSize = 12
            title.TextColor3 = Color3.fromRGB(160, 190, 255)
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Text = "Tyrant Kaitun  [K] toggle"
            title.Parent = titleBar

            -- Nút đóng
            local btnClose = Instance.new("TextButton")
            btnClose.Name = "CloseBtn"
            btnClose.Size = UDim2.new(0, 22, 0, 22)
            btnClose.Position = UDim2.new(1, -60, 0.5, -11)
            btnClose.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
            btnClose.BackgroundTransparency = 0.2
            btnClose.Font = Enum.Font.GothamBold
            btnClose.TextSize = 11
            btnClose.TextColor3 = Color3.new(1, 1, 1)
            btnClose.Text = "X"
            btnClose.Parent = titleBar
            Instance.new("UICorner", btnClose).CornerRadius = UDim.new(0, 6)
            btnClose.MouseButton1Click:Connect(function()
                frame.Visible = false
            end)

            -- Nút reroll manual
            local btnReroll = Instance.new("TextButton")
            btnReroll.Name = "RerollBtn"
            btnReroll.Size = UDim2.new(0, 50, 0, 22)
            btnReroll.Position = UDim2.new(1, -130, 0.5, -11)
            btnReroll.BackgroundColor3 = Color3.fromRGB(60, 140, 220)
            btnReroll.BackgroundTransparency = 0.2
            btnReroll.Font = Enum.Font.GothamBold
            btnReroll.TextSize = 10
            btnReroll.TextColor3 = Color3.new(1, 1, 1)
            btnReroll.Text = "⟳ Roll"
            btnReroll.Parent = titleBar
            Instance.new("UICorner", btnReroll).CornerRadius = UDim.new(0, 6)
            btnReroll.MouseButton1Click:Connect(function()
                local target = ENV.RaceTarget
                if target and type(target) == "string" then
                    local cur = raceOf()
                    if cur ~= target then
                        dlog(("Manual reroll: cur=%s target=%s"):format(tostring(cur), target))
                        pcall(function()
                            ReplicatedStorage.Remotes.CommF_:InvokeServer("BlackbeardReward", "Reroll", "1")
                        end)
                        pcall(function()
                            ReplicatedStorage.Remotes.CommF_:InvokeServer("BlackbeardReward", "Reroll", "2")
                        end)
                    end
                end
            end)

            -- Body text
            local body = Instance.new("TextLabel")
            body.Name = "Body"
            body.Size = UDim2.new(1, -16, 1, -50)
            body.Position = UDim2.new(0, 8, 0, 32)
            body.BackgroundTransparency = 1
            body.Font = Enum.Font.Code
            body.TextSize = 11
            body.TextColor3 = Color3.fromRGB(210, 210, 225)
            body.TextXAlignment = Enum.TextXAlignment.Left
            body.TextYAlignment = Enum.TextYAlignment.Top
            body.Text = "loading..."
            body.Parent = frame

            -- Notif nhỏ khi nhấn reroll
            local notif = Instance.new("TextLabel")
            notif.Name = "Notif"
            notif.Size = UDim2.new(0, 140, 0, 20)
            notif.Position = UDim2.new(1, -148, 1, -28)
            notif.BackgroundColor3 = Color3.fromRGB(40, 120, 220)
            notif.BackgroundTransparency = 0.2
            notif.Font = Enum.Font.GothamBold
            notif.TextSize = 10
            notif.TextColor3 = Color3.new(1, 1, 1)
            notif.Text = "Rerolled!"
            notif.Visible = false
            notif.Parent = frame
            Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 6)

            -- DRAG logic trên titleBar
            local dragging, dragStart, startPos = false, nil, nil
            titleBar.InputBegan:Connect(function(input, gp)
                if gp then return end
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    dragStart = input.Position
                    startPos = frame.Position
                end
            end)
            titleBar.InputEnded:Connect(function(input, gp)
                if gp then return end
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = false
                end
            end)
            game:GetService("RunService").Heartbeat:Connect(function()
                if dragging then
                    local delta = game:GetService("UserInputService"):GetMouseLocation() - dragStart
                    frame.Position = UDim2.new(
                        startPos.X.Scale, startPos.X.Offset + delta.X,
                        startPos.Y.Scale, startPos.Y.Offset + delta.Y
                    )
                end
            end)

            local function render()
                local race, frag, raceReady = "?", "?", "false"
                pcall(function()
                    local d = LocalPlayer and LocalPlayer:FindFirstChild("Data")
                    if d then
                        local r = d:FindFirstChild("Race")
                        if r then race = tostring(r.Value) end
                        local f = d:FindFirstChild("Fragments")
                        if f then frag = tostring(f.Value) end
                    end
                    local rname = ENV.RaceTarget
                    raceReady = tostring(RaceReady)
                    if rname and rname ~= false and race ~= "?" then
                        if race == rname then raceReady = "READY" end
                    elseif rname == false then
                        raceReady = "off"
                    elseif rname == nil then
                        raceReady = "no target"
                    end
                end)
                local mode = CurrentMode or "?"
                local status = SetStatusLast or "?"
                local targetFrag = ENV.fragmenttarget or "?"
                body.Text = string.format(
                    "Race   : %s\nTarget : %s\nFrag   : %s / %s\nStatus : %s\nMode   : %s\nInfo   : %s",
                    race, tostring(ENV.race or "nil"), frag, targetFrag, raceReady, mode, status
                )
            end

            task.spawn(function()
                while task.wait(0.25) do
                    pcall(render)
                end
            end)

            -- Khi nhấn nút reroll -> flash notif
            btnReroll.MouseButton1Click:Connect(function()
                notif.Visible = true
                task.delay(1.5, function() notif.Visible = false end)
            end)

            -- Phím K toggle
            local UIS = game:GetService("UserInputService")
            UIS.InputBegan:Connect(function(input, gp)
                if gp then return end
                if input.KeyCode == Enum.KeyCode.K then
                    frame.Visible = not frame.Visible
                end
            end)

            ENV.TyrantUI = gui
            ENV.TyrantUIFrame = frame
            gui.Parent = PlayerGui
        end
    end
end

if NormalizeName(Config.Weapon) == NormalizeName("Dragon Talon")
    and not PlayerHasDragonTalon()
then
    BuyDragonTalon()
end

while task.wait(0.15) do
    if not Farming or not ENV.__TYRANT_TRF_READY then
        SetStatus("Đang chờ team/Character sẵn sàng")
        task.wait(0.5)
    else
            MaybeCheckFragment()

            local playerHum = Humanoid()

            if not playerHum or playerHum.Health <= 0 then
                SetStatus("Đang chờ nhân vật hồi sinh")
                task.wait(1)
            else
                local tyrant = FindTyrant()

                if tyrant then
                    SetStatus("Đã tìm thấy Tyrant - đang đánh boss")
                    FarmEnemy(tyrant, true)
                elseif AreTyrantEyesReady() then
                    BreakTyrantVases()
                else
                    CurrentMode = "MOBS"
                    CurrentTarget = nil
                    local activeEyes = GetTyrantEyeProgress()
                    SetStatus(string.format("Đang farm NPC Tiki - mắt đỏ %d/4", activeEyes))
                    EnsureWeapon()

                    local mob = GetNearestTikiMob()
                    if mob then
                        FarmEnemy(mob, false)
                    else
                        TweenTo(TIKI_CENTER, Config.TweenSpeed)
                        task.wait(0.8)
                    end
                end
            end
    end
end
