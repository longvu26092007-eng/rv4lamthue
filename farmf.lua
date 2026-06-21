--[[
    FarmFrag.lua  -  Auto Farm + Summon "Tyrant of the Skies" (Sea 3)
    ----------------------------------------------------------------------
    - Ban A (huy_Banana / 1.txt / 5.txt:11795-11875): farm mob spawn boss + danh boss + summon pad.
    - Combat = 3 lop danh chong (be tu KaitunV4): RegisterAttack/RegisterHit + LeftClickRemote + RegisterHit ma hoa.
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
    TweenSpeed = 300,
    LoopWait   = 0.3,
    Team       = "Pirates",
}

-- co bat/tat (doc getgenv neu co)
local STATE = { farm = true, summon = false }
pcall(function()
    if getgenv().FarmTyrant ~= nil then STATE.farm = getgenv().FarmTyrant end
    if getgenv().SummonTyrant ~= nil then STATE.summon = getgenv().SummonTyrant end
    if getgenv().Team then CONFIG.Team = getgenv().Team end
end)

-- Sea 3 (Third Sea) - noi co Tyrant
local SEA_3 = { ["7449423635"] = true, ["100117331123089"] = true }
local function inSea3() return SEA_3[tostring(game.PlaceId)] == true end

--==================  DEBUG / LOG  ==================--
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

local function TP(cf)
    local root = hrp(); if not root then return end
    local h = char():FindFirstChild("Humanoid"); if h then h.Sit = false end
    local dist = (cf.Position - root.Position).Magnitude
    local tw = TweenService:Create(root, TweenInfo.new(math.max(dist / CONFIG.TweenSpeed, 0.1), Enum.EasingStyle.Linear), { CFrame = cf })
    tw:Play(); tw.Completed:Wait()
end

local function goToSea3() CommF("TravelZou") end -- TravelZou = Teleport Third Sea

--==================  LOAD TEAM  ==================--
local function EnsureTeam()
    local t0 = tick()
    repeat task.wait() until game:IsLoaded() or tick() - t0 > 15
    if LocalPlayer.Team then DBG.team = tostring(LocalPlayer.Team); return end
    local team = CONFIG.Team
    if team ~= "Pirates" and team ~= "Marines" then team = "Pirates" end
    Status("Load team -> SetTeam: " .. team)
    CommF("SetTeam", team)
    local t1 = tick()
    repeat task.wait() until LocalPlayer.Team or tick() - t1 > 8
    DBG.team = LocalPlayer.Team and tostring(LocalPlayer.Team) or "?"
end

--==================  COMBAT: 3 LOP DANH CHONG (be tu KaitunV4)  ==================--
local function equipFirstWeapon()
    local c = char(); if not c then return end
    for _, v in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if v:IsA("Tool") and tostring(v.ToolTip) == "Melee" then c.Humanoid:EquipTool(v); return end
    end
    for _, v in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if v:IsA("Tool") then c.Humanoid:EquipTool(v); return end
    end
end
local function buso() if char() and not char():FindFirstChild("HasBuso") then CommF("Buso") end end

local ATK = { on = false }
local ATK_RANGE = 60
local _Modules       = ReplicatedStorage:FindFirstChild("Modules")
local _Net           = _Modules and _Modules:FindFirstChild("Net")
local RegisterAttack = _Net and (_Net:FindFirstChild("RE/RegisterAttack") or _Net:WaitForChild("RE/RegisterAttack", 5))
local RegisterHit    = _Net and (_Net:FindFirstChild("RE/RegisterHit") or _Net:WaitForChild("RE/RegisterHit", 5))
local _cloneref      = cloneref or function(x) return x end

local encRemote, encId
for _, name in ipairs({ "Util", "Common", "Remotes", "Assets", "FX" }) do
    local c = ReplicatedStorage:FindFirstChild(name)
    if c then
        for _, n in ipairs(c:GetChildren()) do
            if n:IsA("RemoteEvent") and n:GetAttribute("Id") then encRemote, encId = n, n:GetAttribute("Id") end
        end
        c.ChildAdded:Connect(function(n)
            if n:IsA("RemoteEvent") and n:GetAttribute("Id") then encRemote, encId = n, n:GetAttribute("Id") end
        end)
    end
end

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

-- LOP 1
task.spawn(function()
    while task.wait() do
        if ATK.on and RegisterAttack and RegisterHit then
            pcall(function()
                local ts = atkTargets(); if #ts == 0 then return end
                local list, base = {}, nil
                local arms = { "RightLowerArm", "RightUpperArm", "LeftLowerArm", "LeftUpperArm", "RightHand", "LeftHand" }
                for _, t in ipairs(ts) do
                    if not t:GetAttribute("IsBoat") then
                        local p = t:FindFirstChild(arms[math.random(#arms)]) or t.PrimaryPart or t:FindFirstChild("HumanoidRootPart")
                        if p then list[#list + 1] = { t, p }; base = p end
                    end
                end
                if base then RegisterAttack:FireServer(0); RegisterHit:FireServer(base, list) end
            end)
        end
    end
end)

-- LOP 2
task.spawn(function()
    while task.wait() do
        if ATK.on then
            pcall(function()
                local c = char(); if not c then return end
                local tool = c:FindFirstChildOfClass("Tool")
                if not tool or tool.ToolTip == "Gun" then return end
                local ts = atkTargets(); if #ts == 0 then return end
                if tool:FindFirstChild("LeftClickRemote") then
                    for _, e in ipairs(ts) do
                        local eh = e:FindFirstChild("HumanoidRootPart")
                        if eh then
                            local dir = (eh.Position - c:GetPivot().Position).Unit
                            pcall(function() tool.LeftClickRemote:FireServer(dir, 1) end)
                        end
                    end
                elseif RegisterAttack and RegisterHit then
                    local list, base = {}, nil
                    for _, e in ipairs(ts) do
                        local head = e:FindFirstChild("Head") or e:FindFirstChild("HumanoidRootPart")
                        if head then list[#list + 1] = { e, head }; base = head end
                    end
                    if base then RegisterAttack:FireServer(0); RegisterHit:FireServer(base, list) end
                end
            end)
        end
    end
end)

-- LOP 3 (ma hoa)
task.spawn(function()
    while task.wait(0.05) do
        if ATK.on and _Net and RegisterAttack and RegisterHit then
            pcall(function()
                local c = char(); local root = hrp(); if not (c and root) then return end
                local tool = c:FindFirstChildOfClass("Tool")
                if not (tool and (tool:GetAttribute("WeaponType") == "Melee" or tool:GetAttribute("WeaponType") == "Sword")) then return end
                local parts = {}
                local folder = Workspace:FindFirstChild("Enemies")
                if folder then for _, v in ipairs(folder:GetChildren()) do
                    local vh, hum = v:FindFirstChild("HumanoidRootPart"), v:FindFirstChild("Humanoid")
                    if v ~= c and vh and hum and hum.Health > 0 and (vh.Position - root.Position).Magnitude <= ATK_RANGE then
                        for _, _v in ipairs(v:GetChildren()) do
                            if _v:IsA("BasePart") then parts[#parts + 1] = { v, _v } end
                        end
                    end
                end end
                if #parts == 0 then return end
                local head = parts[1][1]:FindFirstChild("Head"); if not head then return end
                RegisterAttack:FireServer()
                RegisterHit:FireServer(head, parts, {}, tostring(LocalPlayer.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15))
                if encRemote and encId then
                    _cloneref(encRemote):FireServer(
                        string.gsub("RE/RegisterHit", ".", function(ch)
                            return string.char(bit32.bxor(string.byte(ch), math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1))
                        end),
                        bit32.bxor(encId + 909090, _Net.seed:InvokeServer() * 2), head, parts)
                end
            end)
        end
    end
end)

-- bring + giet 1 muc tieu bang 3 lop (khong spam chieu - day la quai)
local function bringAndKill(v, untilFn)
    if not (v and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart")) then return end
    equipFirstWeapon()
    ATK.on = true
    repeat
        buso()
        pcall(function()
            v.HumanoidRootPart.CanCollide = false
            v.Humanoid.WalkSpeed = 0
            v.HumanoidRootPart.Size = Vector3.new(50, 50, 50)
            if v:FindFirstChild("Head") then v.Head.CanCollide = false end
        end)
        TP(v.HumanoidRootPart.CFrame * CFrame.new(0, 40, 0))
        task.wait(0.2)
    until not v.Parent or v.Humanoid.Health <= 0 or (untilFn and untilFn())
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
local function getTyrant()
    local e = Workspace:FindFirstChild("Enemies")
    return e and e:FindFirstChild(TYRANT)
end

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
            TP(TYRANT_SPAWN)
        end
    end
end

-- summon: dap 7 be bang Z/X/C (khi chua co boss)
local function summonStep()
    for _, cf in ipairs(TYRANT_PADS) do
        if not (STATE.summon and inSea3()) or getTyrant() then break end
        DBG.action = "Summon: dap be"
        TP(cf * CFrame.new(0, 5, 0)); task.wait(0.5)
        pcall(function()
            for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
                if tool:IsA("Tool") then
                    char().Humanoid:EquipTool(tool); task.wait(0.1)
                    for _, k in ipairs({ "Z", "X", "C" }) do
                        VIM:SendKeyEvent(true, k, false, game); task.wait(0.05); VIM:SendKeyEvent(false, k, false, game)
                    end
                end
            end
        end)
        task.wait(2)
    end
end

--==================  UI STATUS / DEBUG  ==================--
local function MakeUI()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    local old = parent:FindFirstChild("FarmFragUI"); if old then old:Destroy() end
    local gui = Instance.new("ScreenGui")
    gui.Name = "FarmFragUI"; gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 320, 0, 280); main.Position = UDim2.new(0, 18, 0, 100)
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
    local lBoss   = row(16, Color3.fromRGB(255, 170, 170), true, 4)
    local lLogT   = row(14, Color3.fromRGB(120, 130, 150), true, 5); lLogT.Text = "Log:"
    local lLog    = row(96, Color3.fromRGB(160, 165, 180), false, 6)

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
        main.Size = mini and UDim2.new(0, 320, 0, 30) or UDim2.new(0, 320, 0, 280)
    end)

    task.spawn(function()
        while gui.Parent do
            task.wait(0.3)
            lStatus.Text = "● " .. tostring(_G.FarmFragStatus or DBG.action or "...")
            lSea.Text  = ("Place: %s  (%s)   |   Team: %s"):format(tostring(game.PlaceId), inSea3() and "Sea 3" or "KHONG Sea 3", DBG.team)
            lBoss.Text = ("Tyrant: %s    |    Mob spawn gan: %d"):format(DBG.tyrant and "✅ co" or "❌ chua", DBG.mobs)
            lLog.Text  = table.concat(LOG, "\n")
        end
    end)
end
pcall(MakeUI)

--==================  MAIN LOOP  ==================--
local function Main()
    print("[Frag] Place:", game.PlaceId, "| Farm:", STATE.farm, "| Summon:", STATE.summon)
    EnsureTeam()
    while task.wait(CONFIG.LoopWait) do
        local ok, err = pcall(function()
            if not hrp() then DBG.action = "Cho nhan vat load"; return end
            if not inSea3() then
                DBG.action = "Khong o Sea 3 -> len Sea 3 (TravelZou)"
                Status(DBG.action)
                goToSea3()
                return
            end
            if STATE.summon and not getTyrant() then
                summonStep()
            elseif STATE.farm then
                farmStep()
            else
                DBG.action = "Tat ca OFF (bat Farm/Summon tren UI)"
            end
        end)
        if not ok then warn("[Frag] loop err:", tostring(err)); ATK.on = false end
    end
end

Main()
