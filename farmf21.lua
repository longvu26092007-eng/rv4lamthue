--[[
    FarmFrag.lua  -  Auto Farm + Summon "Tyrant of the Skies" (Sea 3)
    ----------------------------------------------------------------------
    - Ban A (huy_Banana / 1.txt / 5.txt:11795-11875): farm mob spawn boss + danh boss + summon pad.
    - Combat = 1 ham danh sach (RegisterAttack + RegisterHit) kieu AttackNoCoolDown KaitunV4 (khong chong nhau).
    - Khong o Sea 3 -> tu len Sea 3 (TravelZou). Load team (SetTeam). Co bang Status/Debug (keo tha + nut bat/tat).

    getgenv().FarmTyrant  = true   -- bat auto farm Tyrant (mac dinh true)
    getgenv().SummonTyrant = false  -- bat summon (dap be) khi chua co boss
    getgenv().Team        = "Pirates" -- phe khi acc chua chon
    ----------------------------------------------------------------------
]]

--==================  SERVICES  ==================--
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")
local VIM               = game:GetService("VirtualInputManager")
local UserInputService  = game:GetService("UserInputService")
local LocalPlayer       = Players.LocalPlayer

--==================  CONFIG  ==================--
local CONFIG = {
    TweenSpeed = 340,
    LoopWait   = 0.3,
    Team       = "Pirates",
}

-- co bat/tat (doc getgenv neu co)
local STATE = { farm = true, summon = false }
local SUMMON_NEED = 300        -- so quai can giet de 4 mat dai bang sang (4 mat x 75 = 300)
pcall(function()
    if getgenv().FarmTyrant ~= nil then STATE.farm = getgenv().FarmTyrant end
    if getgenv().SummonTyrant ~= nil then STATE.summon = getgenv().SummonTyrant end
    if getgenv().SummonNeed then SUMMON_NEED = tonumber(getgenv().SummonNeed) or 300 end
    if getgenv().Team then CONFIG.Team = getgenv().Team end
end)

-- Sea 3 (Third Sea) - noi co Tyrant
local SEA_3 = { ["7449423635"] = true, ["100117331123089"] = true }
local function inSea3() return SEA_3[tostring(game.PlaceId)] == true end

--==================  DEBUG / LOG  ==================--
local killCount = 0            -- dem quai Tiki da giet (phia minh thay chet)
local DBG = { action = "...", tyrant = false, mobs = 0, team = "?" }
local LOG = {}
local function pushLog(m)
    table.insert(LOG, os.date("%H:%M:%S") .. "  " .. tostring(m))
    while #LOG > 8 do table.remove(LOG, 1) end
end
local function Status(m) _G.FarmFragStatus = m; pushLog(m); print("[Frag] " .. tostring(m)) end

--==================  HELPERS  ==================--
local function Remotes() return ReplicatedStorage:FindFirstChild("Remotes") end
local function CommF(...)
    local r = Remotes(); if not (r and r:FindFirstChild("CommF_")) then return nil end
    local a = { ... }
    local ok, res = pcall(function() return r.CommF_:InvokeServer(unpack(a)) end)
    if ok then return res end
    return nil
end
local function char() return LocalPlayer.Character end
local function hrp() local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end

-- ===== BAY MUOT (tham khao KaitunV4 module:topos) =====
-- noclip: BodyClip (BodyVelocity velocity=0) + CanCollide=false -> chong physics keo (het giat)
local _noclip = false
task.spawn(function()
    while task.wait() do
        local c = char()
        local h = c and c:FindFirstChild("Humanoid")
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if _noclip and h and root and not h.Sit and not root.Anchored then
            if not root:FindFirstChild("BodyClip") then
                local bv = Instance.new("BodyVelocity")
                bv.Name = "BodyClip"; bv.MaxForce = Vector3.new(1e5, 1e5, 1e5); bv.Velocity = Vector3.zero
                bv.Parent = root
            end
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
            end
        elseif root then
            local bc = root:FindFirstChild("BodyClip"); if bc then bc:Destroy() end
        end
    end
end)

-- topos: huy tween cu truoc khi tao moi + toc do co dinh + non-blocking (het giat)
local _activeTween
local function topos(cf)
    local root = hrp(); if not root then return end
    local h = char() and char():FindFirstChild("Humanoid"); if h then h.Sit = false end
    if _activeTween then pcall(function() _activeTween:Cancel(); _activeTween:Destroy() end); _activeTween = nil end
    local dist = (root.Position - cf.Position).Magnitude
    local dur = math.clamp(dist / CONFIG.TweenSpeed, 0.05, 600)
    local tw = TweenService:Create(root, TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), { CFrame = cf })
    _activeTween = tw
    tw.Completed:Once(function() if _activeTween == tw then _activeTween = nil end; pcall(function() tw:Destroy() end) end)
    tw:Play()
end

local getTyrant -- forward declare (gan o phan TYRANT) - de moi noi detect boss duoc

-- TP: bay toi & cho gan toi (blocking). abortFn() = true -> dung ngay (vd boss spawn)
local function TP(cf, arrive, abortFn)
    arrive = arrive or 10
    topos(cf)
    local t0 = tick()
    repeat task.wait()
    until not hrp() or (hrp().Position - cf.Position).Magnitude <= arrive or tick() - t0 > 10
        or (abortFn and abortFn())
end

local function goToSea3() CommF("TravelZou") end -- TravelZou = Teleport Third Sea

--==================  LOAD TEAM  ==================--
-- Chon phe = click UI ChooseTeam (firesignal) nhu KaitunV4 module:join.
-- Acc cu khong co UI ChooseTeam -> da co phe -> bo qua. Khong spam SetTeam.
local function EnsureTeam()
    local t0 = tick()
    repeat task.wait() until game:IsLoaded() or tick() - t0 > 15
    local team = CONFIG.Team
    if team ~= "Pirates" and team ~= "Marines" then team = "Pirates" end
    for _ = 1, 40 do
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local needSelect = false
        if pg then
            for _, g in ipairs(pg:GetChildren()) do
                local ct = g:FindFirstChild("ChooseTeam")
                if ct then
                    needSelect = true
                    local cont = ct:FindFirstChild("Container")
                    local btn = cont and cont:FindFirstChild(team)
                    btn = btn and btn:FindFirstChild("Frame"); btn = btn and btn:FindFirstChild("TextButton")
                    if btn and firesignal then
                        Status("Chon phe (ChooseTeam UI): " .. team)
                        pcall(function() firesignal(btn.Activated) end)
                    end
                    pcall(function() CommF("SetTeam", team) end) -- them remote cho chac
                end
            end
        end
        if not needSelect then break end -- khong co UI -> da co phe
        task.wait(0.5)
    end
    DBG.team = (LocalPlayer.Team and tostring(LocalPlayer.Team)) or "(co san)"
end

--==================  COMBAT: 3 LOP DANH CHONG (be tu KaitunV4)  ==================--
-- equip CHI Melee (getgenv().USESWORD = true thi dung Sword). Khong dung tool khac.
local function equipWeapon()
    local c = char(); local bp = LocalPlayer:FindFirstChild("Backpack")
    if not (c and bp and c:FindFirstChild("Humanoid")) then return end
    local want = "Melee"
    pcall(function() if getgenv().USESWORD then want = "Sword" end end)
    -- da cam dung loai roi -> khoi equip lai (tranh nhap nhay doi qua doi lai)
    local cur = c:FindFirstChildOfClass("Tool")
    if cur and tostring(cur.ToolTip) == want then return end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and tostring(t.ToolTip) == want then
            pcall(function() c.Humanoid:EquipTool(t) end); return
        end
    end
end
local function buso() if char() and not char():FindFirstChild("HasBuso") then CommF("Buso") end end
local function checkmob(v) -- giong checkmob_ KaitunV4
    return v and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0
end

local ATK = { on = false }
local ATK_RANGE = 60
local _Modules       = ReplicatedStorage:FindFirstChild("Modules")
local _Net           = _Modules and _Modules:FindFirstChild("Net")
local RegisterAttack = _Net and (_Net:FindFirstChild("RE/RegisterAttack") or _Net:WaitForChild("RE/RegisterAttack", 5))
local RegisterHit    = _Net and (_Net:FindFirstChild("RE/RegisterHit") or _Net:WaitForChild("RE/RegisterHit", 5))

-- chi danh Enemies (farm boss/mob - khong PvP)
local function atkTargets()
    local root = hrp(); local out = {}
    local folder = Workspace:FindFirstChild("Enemies")
    if not (root and folder) then return out end
    for _, v in ipairs(folder:GetChildren()) do
        local hum, vh = v:FindFirstChild("Humanoid"), v:FindFirstChild("HumanoidRootPart")
        if v ~= char() and hum and vh and hum.Health > 0 and (vh.Position - root.Position).Magnitude <= ATK_RANGE then
            out[#out + 1] = v
        end
    end
    return out
end

-- DANH = copy AttackNoCoolDown KaitunV4 (1808-1858)
local ARMS = { "RightLowerArm", "RightUpperArm", "LeftLowerArm", "LeftUpperArm", "RightHand", "LeftHand" }

-- Lay SendHitsToServer (getsenv PlayerScripts LocalScript) - RETRY toi khi lay duoc (KHONG cache that bai)
local _Z
local function resolveZ()
    if _Z then return _Z end
    if not getsenv then return nil end
    local ps = LocalPlayer:FindFirstChild("PlayerScripts"); if not ps then return nil end
    local b = ps:FindFirstChildOfClass("LocalScript"); if not b then return nil end
    local ok, env = pcall(getsenv, b)
    if ok and env then
        local g = env._G
        if g then _Z = g.SendHitsToServer end
    end
    return _Z
end

local function doAttack()
    local c = char(); if not c then return end
    -- phai DANG CAM vu khi (Tool trong Character)
    local hasTool = false
    for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") then hasTool = true; break end end
    if not hasTool then return end
    if not (RegisterAttack and RegisterHit) then return end
    local ts = atkTargets(); if #ts == 0 then return end
    local l, M = {}, nil
    for _, e in ipairs(ts) do
        if not e:GetAttribute("IsBoat") then
            local p = e:FindFirstChild(ARMS[math.random(#ARMS)]) or e.PrimaryPart
            if p then l[#l + 1] = { e, p }; M = p end
        end
    end
    if not M then return end
    RegisterAttack:FireServer(0)
    local Z = resolveZ()
    if Z then pcall(Z, M, l) else RegisterHit:FireServer(M, l) end -- uu tien SendHitsToServer, ko thi raw
end

task.spawn(function()
    while task.wait() do
        if ATK.on and RegisterAttack and RegisterHit then pcall(doAttack) end
    end
end)

-- bring + giet 1 muc tieu (khong spam chieu - day la quai)
-- Farm 1 muc tieu theo dung logic training KaitunV4:
--   eq (Melee) + haki + bat dong hoa (WalkSpeed/JumpPower 0, ChangeState Physics, SimRadius huge) + topos len dau +20
local function bringAndKill(v, untilFn)
    if not checkmob(v) then return end
    ATK.on = true
    repeat
        -- LUON detect boss: neu Tyrant xuat hien va minh dang KHONG farm boss -> dung ngay
        local b = getTyrant and getTyrant()
        if b and b ~= v then break end
        equipWeapon()
        buso()
        pcall(function()
            local hum, root = v.Humanoid, v.HumanoidRootPart
            root.CanCollide = false
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            hum:ChangeState(14)                                  -- Physics: ngung di chuyen
            if v:FindFirstChild("Head") then v.Head.CanCollide = false end
            if sethiddenproperty then sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge) end
        end)
        topos(v.HumanoidRootPart.CFrame * CFrame.new(0, 20, 0)) -- bay len dau, non-blocking (muot)
        task.wait(0.1)
    until not checkmob(v) or (untilFn and untilFn())
    ATK.on = false
end

--==================  TYRANT (Ban A)  ==================--
local TYRANT       = "Tyrant of the Skies"
local SPAWN_MOBS   = { "Isle Outlaw", "Island Boy", "Isle Champion", "Serpent Hunter", "Skull Slayer", "Sun-kissed Warrior" }
local TYRANT_SPAWN = CFrame.new(-16194.00, 155.21, 1420.71)
local TYRANT_PADS  = {
    CFrame.new(-16250.24, 158.17, 1313.02), CFrame.new(-16297.06, 159.32, 1317.22),
    CFrame.new(-16335.10, 159.33, 1324.89), CFrame.new(-16288.61, 158.17, 1470.37),
    CFrame.new(-16258.00, 156.76, 1461.40), CFrame.new(-16245.41, 158.44, 1463.37),
    CFrame.new(-16212.47, 158.17, 1466.34),
}

local function isSpawnMob(name)
    for _, n in ipairs(SPAWN_MOBS) do if n == name then return true end end
    return false
end
function getTyrant() -- gan vao bien forward-declare o tren
    local e = Workspace:FindFirstChild("Enemies")
    return e and e:FindFirstChild(TYRANT)
end

-- ===== DEM QUAI (tu lam - file goc KHONG co counter cho Tyrant) =====
-- Theo doi quai Tiki bien mat khoi Enemies (~ da giet). 4 mat dai bang, moi mat 75 -> 300.
local _seen = {}
task.spawn(function()
    while task.wait(0.25) do
        DBG.tyrant = getTyrant() ~= nil -- LUON detect boss (UI + trang thai)
        local e = Workspace:FindFirstChild("Enemies")
        if e and inSea3() then
            local aliveNow = {}
            for _, v in ipairs(e:GetChildren()) do
                if isSpawnMob(v.Name) and v:FindFirstChild("Humanoid") then
                    aliveNow[v] = true; _seen[v] = true
                end
            end
            for v in pairs(_seen) do
                if not aliveNow[v] then killCount = killCount + 1; _seen[v] = nil end
            end
        end
    end
end)

-- KIEU A: chi dem kill. 4 mat dai bang, moi mat 75 kill -> 4x75 = 300 -> du thi summon.
local function eyesLit() return math.min(4, math.floor(killCount / 75)) end -- 0..4 mat (theo kill)
local function canSummon() return killCount >= SUMMON_NEED end              -- du 300 -> dap binh

-- 1 buoc farm: co boss -> danh boss; chua co -> farm mob spawn / bay toi spawn
local function farmStep()
    local enemies = Workspace:FindFirstChild("Enemies"); if not enemies then return end
    local boss = enemies:FindFirstChild(TYRANT)
    DBG.tyrant = boss ~= nil
    if boss then
        if boss:FindFirstChild("Humanoid") and boss:FindFirstChild("HumanoidRootPart") and boss.Humanoid.Health > 0 then
            DBG.action = "Danh Tyrant (HP " .. math.floor(boss.Humanoid.Health) .. ")"
            bringAndKill(boss)
        end
    else
        local target, count = nil, 0
        for _, v in ipairs(enemies:GetChildren()) do
            if isSpawnMob(v.Name) and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 then
                count = count + 1
                if not target then target = v end
            end
        end
        DBG.mobs = count
        if target then
            DBG.action = "Farm mob spawn: " .. target.Name
            bringAndKill(target, function() return getTyrant() ~= nil end)
        else
            DBG.action = "Bay toi spawn Tyrant"
            TP(TYRANT_SPAWN, 10, function() return getTyrant() ~= nil end) -- boss ra -> dung ngay
        end
    end
end

-- summon: dap MOI binh (3 lan/luot) - LAP LAI cac be CHO DEN KHI boss spawn thi thoi
-- (binh dat ngau nhien, co luot khong co binh -> phai dap nhieu vong)
local function summonStep()
    while STATE.summon and inSea3() and not getTyrant() do
        for _, cf in ipairs(TYRANT_PADS) do
            if not (STATE.summon and inSea3()) or getTyrant() then break end
            DBG.action = "Summon: dap binh (cho boss spawn)"
            TP(cf * CFrame.new(0, 5, 0)); task.wait(0.3)

            -- GIU Y NGUYEN player khi pha binh: huy tween + ANCHOR (skill khong lam bay)
            local root = hrp()
            if _activeTween then pcall(function() _activeTween:Cancel() end) end
            if root then pcall(function() root.Anchored = true end) end

            pcall(function()
                equipWeapon() -- CHI Melee, khong dung tool khac
                task.wait(0.1)
                for round = 1, 3 do -- dap binh 3 lan bang Z/X/C cua Melee
                    for _, k in ipairs({ "Z", "X", "C" }) do
                        VIM:SendKeyEvent(true, k, false, game); task.wait(0.05); VIM:SendKeyEvent(false, k, false, game)
                    end
                end
            end)

            if root then pcall(function() root.Anchored = false end) end -- LUON mo anchor lai
            task.wait(0.4)
        end
    end
    if getTyrant() then DBG.action = "Tyrant da spawn!" end
end

--==================  UI STATUS / DEBUG  ==================--
local function MakeUI()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    local old = parent:FindFirstChild("FarmFragUI"); if old then old:Destroy() end
    local gui = Instance.new("ScreenGui")
    gui.Name = "FarmFragUI"; gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 320, 0, 304); main.Position = UDim2.new(0, 18, 0, 100)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 24); main.BorderSizePixel = 0
    main.Active = true; main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", main); stroke.Color = Color3.fromRGB(160, 110, 60); stroke.Thickness = 1

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 30); bar.BackgroundColor3 = Color3.fromRGB(34, 30, 40); bar.BorderSizePixel = 0; bar.Parent = main
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -36, 1, 0); title.Position = UDim2.new(0, 10, 0, 0)
    title.Font = Enum.Font.GothamBold; title.TextSize = 13; title.TextColor3 = Color3.fromRGB(235, 235, 245)
    title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "Farm Tyrant  •  Debug"; title.Parent = bar
    local btnMin = Instance.new("TextButton")
    btnMin.Size = UDim2.new(0, 26, 0, 22); btnMin.Position = UDim2.new(1, -30, 0, 4)
    btnMin.BackgroundColor3 = Color3.fromRGB(55, 60, 80); btnMin.Text = "–"; btnMin.Font = Enum.Font.GothamBold
    btnMin.TextSize = 14; btnMin.TextColor3 = Color3.fromRGB(255, 255, 255); btnMin.Parent = bar
    Instance.new("UICorner", btnMin).CornerRadius = UDim.new(0, 6)

    local body = Instance.new("Frame")
    body.BackgroundTransparency = 1; body.Position = UDim2.new(0, 10, 0, 36); body.Size = UDim2.new(1, -20, 1, -44); body.Parent = main
    local layout = Instance.new("UIListLayout", body); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Padding = UDim.new(0, 4)

    -- hang nut toggle
    local btnRow = Instance.new("Frame")
    btnRow.BackgroundTransparency = 1; btnRow.Size = UDim2.new(1, 0, 0, 26); btnRow.LayoutOrder = 1; btnRow.Parent = body
    local function mkToggle(x, label, getv, setv)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.48, 0, 1, 0); b.Position = UDim2.new(x, 0, 0, 0)
        b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(255, 255, 255); b.Parent = btnRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        local function refresh()
            local on = getv()
            b.Text = label .. ": " .. (on and "ON" or "OFF")
            b.BackgroundColor3 = on and Color3.fromRGB(45, 130, 70) or Color3.fromRGB(70, 50, 50)
        end
        b.MouseButton1Click:Connect(function() setv(not getv()); refresh() end)
        refresh()
        return b
    end
    mkToggle(0, "Farm", function() return STATE.farm end, function(v) STATE.farm = v; Status("Farm = " .. tostring(v)) end)
    mkToggle(0.52, "Summon", function() return STATE.summon end, function(v) STATE.summon = v; Status("Summon = " .. tostring(v)) end)

    local function row(h, color, bold, order)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1; l.Size = UDim2.new(1, 0, 0, h)
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham; l.TextSize = 12
        l.TextColor3 = color or Color3.fromRGB(210, 210, 220); l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Top; l.TextWrapped = true; l.LayoutOrder = order; l.Text = ""; l.Parent = body
        return l
    end
    local lStatus = row(30, Color3.fromRGB(255, 210, 120), true, 2)
    local lSea    = row(16, Color3.fromRGB(180, 200, 255), false, 3)
    local lKill   = row(16, Color3.fromRGB(150, 230, 150), true, 4)
    local lBoss   = row(16, Color3.fromRGB(255, 170, 170), true, 5)
    local lLogT   = row(14, Color3.fromRGB(120, 130, 150), true, 6); lLogT.Text = "Log:"
    local lLog    = row(88, Color3.fromRGB(160, 165, 180), false, 7)

    -- keo tha
    local dragging, ds, sp
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; ds = i.Position; sp = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    local mini = false
    btnMin.MouseButton1Click:Connect(function()
        mini = not mini; body.Visible = not mini
        main.Size = mini and UDim2.new(0, 320, 0, 30) or UDim2.new(0, 320, 0, 304)
    end)

    task.spawn(function()
        while gui.Parent do
            task.wait(0.3)
            lStatus.Text = "● " .. tostring(DBG.action or _G.FarmFragStatus or "...")
            lSea.Text  = ("Place: %s  (%s)   |   Team: %s"):format(tostring(game.PlaceId), inSea3() and "Sea 3" or "KHONG Sea 3", DBG.team)
            local ready  = canSummon()
            local remain = math.max(0, SUMMON_NEED - killCount)
            lKill.Text = ("Mat: %d/4  |  Kill: %d/%d  |  Con lai: %d %s"):format(eyesLit(), killCount, SUMMON_NEED, remain, ready and "→ SUMMON" or "")
            lKill.TextColor3 = ready and Color3.fromRGB(120, 230, 120) or Color3.fromRGB(230, 220, 120)
            lBoss.Text = ("Tyrant: %s    |    Mob spawn gan: %d"):format(DBG.tyrant and "✅ co" or "❌ chua", DBG.mobs)
            lLog.Text  = table.concat(LOG, "\n")
        end
    end)
end
pcall(MakeUI)

--==================  MAIN LOOP  ==================--
local _hadBoss = false
local function Main()
    print("[Frag] Place:", game.PlaceId, "| Farm:", STATE.farm, "| Summon:", STATE.summon, "| Need:", SUMMON_NEED)
    EnsureTeam()
    while task.wait(CONFIG.LoopWait) do
        _noclip = inSea3() and (STATE.farm or STATE.summon) == true
        local ok, err = pcall(function()
            if not hrp() then DBG.action = "Cho nhan vat load"; return end
            if not inSea3() then
                DBG.action = "Khong o Sea 3 -> len Sea 3 (TravelZou)"
                Status(DBG.action)
                goToSea3()
                return
            end

            local boss = getTyrant()
            DBG.tyrant = boss ~= nil
            -- boss vua summon -> reset dem (mat sang reset sau khi trieu hoi)
            if boss and not _hadBoss then killCount = 0; _seen = {}; Status("Tyrant da spawn -> reset dem") end
            _hadBoss = boss ~= nil

            if boss then
                if STATE.farm then farmStep() else DBG.action = "Boss co san (Farm OFF)" end
            elseif canSummon() then
                -- du 300 kill / mat sang -> chi qua summon khi bat SummonTyrant
                if STATE.summon then summonStep()
                else DBG.action = ("Du %d kill (mat sang) -> bat SummonTyrant de trieu hoi"):format(killCount) end
            elseif STATE.farm then
                farmStep() -- chua du -> farm mob (dem len)
            else
                DBG.action = "Chua du kill & Farm OFF"
            end
        end)
        if not ok then
            warn("[Frag] loop err:", tostring(err)); ATK.on = false
            local r = hrp(); if r then pcall(function() r.Anchored = false end) end -- mo anchor neu ket
        end
    end
end

Main()
