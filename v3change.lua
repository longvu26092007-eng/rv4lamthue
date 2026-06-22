--[[
    UpgradeRace.lua  -  Auto Upgrade Race V2 + V3 (BAM CHUAN func.txt)
    ----------------------------------------------------------------------
    Module RIENG, bat/tat doc lap. Tu nhan Data.Race.Value roi lam:
      - V2 (Alchemist + Flower)  -> func 'Evo Race V1'  (func.txt:8335-8399)
      - Cau noi: giet Don Swan mo khoa Wenlocktoad -> func 'Evo Race V2' (8400-8430)
      - V3 theo tung toc (Wenlocktoad, can >= 2.000.000 Beli) -> func 'Evo Race V3' (8431-8757)

    6 toc / 6 cach V3:
      Mink    : nhat 30 Chest (Space)                              (func 8433)
      Human   : giet Fajita + Jeremy + Diamond                     (func 8477)
      Fishman : Fishman Karate -> giet SeaBeast (Z/X/C)            (func 8547)
      Skypiea : PvP giet 1 nguoi toc Skypiea (het -> hop)          (func 8668)
      Cyborg  : LoadFruit 1 trai bat ky tu tui ra roi claim        (ban cung cap)
      Ghoul   : PvP giet nguoi bat ky toi khi xong                 (ban cung cap)

    Khung chung: Wenlocktoad "1"->"2" (start) -> lam task -> "3" (claim, ==-2 la xong)
    ----------------------------------------------------------------------
]]

--==================  SERVICES  ==================--
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")
local VIM               = game:GetService("VirtualInputManager")
local VirtualUser       = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

--==================  CONFIG  ==================--
local CONFIG = {
    MinLevel     = 1500,       -- yeu cau cap do toi thieu
    BeliNeeded   = 2000000,    -- Beli can de claim V3
    TweenSpeed   = 320,
    LoopWait     = 0.4,
    DoV2         = true,       -- bat lam V2 (Alchemist)
    DoV3         = true,       -- bat lam V3 (Wenlocktoad)
    DoDonSwan    = true,       -- bat giet Don Swan de mo khoa Wenlocktoad
}

-- PlaceId 3 sea (moi sea 2 id). Up toc V1-V3 lam o Sea 2 (New World).
local SEA_1 = {["2753915549"] = true, ["85211729168715"] = true}
local SEA_2 = {["4442272183"] = true, ["79091703265657"] = true}
local SEA_3 = {["7449423635"] = true, ["100117331123089"] = true}
local function inSea2() return SEA_2[tostring(game.PlaceId)] == true end

-- Trang thai debug (main loop cap nhat, UI doc) + log dong
local DBG = { v2 = false, wenlock = false, v3 = false }
local LOG = {}
local function pushLog(m)
    table.insert(LOG, os.date("%H:%M:%S") .. "  " .. tostring(m))
    while #LOG > 8 do table.remove(LOG, 1) end
end

--==================  HELPERS  ==================--
local function Remotes() return ReplicatedStorage:FindFirstChild("Remotes") end

-- CommF_ an toan (tra ve nil neu loi)
local function CommF(...)
    local r = Remotes()
    if not (r and r:FindFirstChild("CommF_")) then return nil end
    local args = {...}
    local ok, res = pcall(function() return r.CommF_:InvokeServer(unpack(args)) end)
    if ok then return res end
    return nil
end

local function char() return LocalPlayer.Character end
local function hrp()
    local c = char(); return c and c:FindFirstChild("HumanoidRootPart")
end

-- TP tween (chong kick); notween = nhay thang
local function TP(cf)
    local root = hrp(); if not root then return end
    local h = char():FindFirstChild("Humanoid"); if h then h.Sit = false end
    local dist = (cf.Position - root.Position).Magnitude
    local tw = TweenService:Create(root, TweenInfo.new(math.max(dist / CONFIG.TweenSpeed, 0.1), Enum.EasingStyle.Linear), { CFrame = cf })
    tw:Play(); tw.Completed:Wait()
end
local function notween(cf) local root = hrp(); if root then root.CFrame = cf end end

-- Tween ca chiec boat (keo VehicleSeat) - dung cho Fishman lai thuyen
local function TPBoat(cf, seat, speed)
    if not seat then return end
    speed = speed or 200
    local dist = (cf.Position - seat.Position).Magnitude
    local tw = TweenService:Create(seat, TweenInfo.new(math.max(dist / speed, 0.1), Enum.EasingStyle.Linear), { CFrame = cf })
    tw:Play(); tw.Completed:Wait()
end

-- Ve Sea 2 (New World) - TravelDressrosa la remote "Teleport New World"
local function goToSea2()
    CommF("TravelDressrosa")
end

-- Trang thai / log
local function Status(msg)
    _G.UpgradeRaceStatus = msg
    pushLog(msg)
    print("[Race] " .. tostring(msg))
end

-- Thong tin tai khoan
local function raceName()
    local d = LocalPlayer:FindFirstChild("Data")
    return d and d:FindFirstChild("Race") and tostring(d.Race.Value) or "?"
end
local function level()
    local d = LocalPlayer:FindFirstChild("Data")
    return (d and d:FindFirstChild("Level") and d.Level.Value) or 0
end
local function beli()
    local d = LocalPlayer:FindFirstChild("Data")
    return (d and d:FindFirstChild("Beli") and d.Beli.Value) or 0
end

local function hasItem(name)
    return (LocalPlayer.Backpack:FindFirstChild(name) or (char() and char():FindFirstChild(name))) ~= nil
end

--==================  COMBAT: 3 LOP DANH CHONG (be nguyen tu KaitunV4)  ==================--
local function equipFirstWeapon()
    local c = char(); if not c then return end
    for _, v in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if v:IsA("Tool") and tostring(v.ToolTip) == "Melee" then c.Humanoid:EquipTool(v); return end
    end
    for _, v in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if v:IsA("Tool") then c.Humanoid:EquipTool(v); return end
    end
end

local function buso()
    if char() and not char():FindFirstChild("HasBuso") then CommF("Buso") end
end

-- Cong tac danh: on = bat 3 lop; players = co danh ca nguoi (Characters) hay khong
local ATK = { on = false, players = false }
local ATK_RANGE = 60

local _Modules       = ReplicatedStorage:FindFirstChild("Modules")
local _Net           = _Modules and _Modules:FindFirstChild("Net")
local RegisterAttack = _Net and (_Net:FindFirstChild("RE/RegisterAttack") or _Net:WaitForChild("RE/RegisterAttack", 5))
local RegisterHit    = _Net and (_Net:FindFirstChild("RE/RegisterHit") or _Net:WaitForChild("RE/RegisterHit", 5))
local _cloneref      = cloneref or function(x) return x end

-- remote ma hoa (RemoteEvent co attribute Id) cho lop 3
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

-- folder muc tieu: luon Enemies; them Characters khi ATK.players
local function atkFolders()
    local f = { Workspace:FindFirstChild("Enemies") }
    if ATK.players then table.insert(f, Workspace:FindFirstChild("Characters")) end
    return f
end
local function atkTargets()
    local root = hrp(); local out = {}
    if not root then return out end
    for _, folder in ipairs(atkFolders()) do
        if folder then for _, v in ipairs(folder:GetChildren()) do
            local hum, vh = v:FindFirstChild("Humanoid"), v:FindFirstChild("HumanoidRootPart")
            if v ~= char() and hum and vh and hum.Health > 0 and (vh.Position - root.Position).Magnitude <= ATK_RANGE then
                out[#out + 1] = v
            end
        end end
    end
    return out
end

-- LOP 1: RegisterAttack + RegisterHit (kieu AttackNoCoolDown)
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
                if not base then return end
                RegisterAttack:FireServer(0)
                RegisterHit:FireServer(base, list)
            end)
        end
    end
end)

-- LOP 2: LeftClickRemote tung muc tieu (kieu FastAttack)
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

-- LOP 3: RegisterHit ma hoa (cloneref remote XOR seed)
task.spawn(function()
    while task.wait(0.05) do
        if ATK.on and _Net and RegisterAttack and RegisterHit then
            pcall(function()
                local c = char(); local root = hrp(); if not (c and root) then return end
                local tool = c:FindFirstChildOfClass("Tool")
                if not (tool and (tool:GetAttribute("WeaponType") == "Melee" or tool:GetAttribute("WeaponType") == "Sword")) then return end
                local parts = {}
                for _, folder in ipairs(atkFolders()) do
                    if folder then for _, v in ipairs(folder:GetChildren()) do
                        local vh, hum = v:FindFirstChild("HumanoidRootPart"), v:FindFirstChild("Humanoid")
                        if v ~= c and vh and hum and hum.Health > 0 and (vh.Position - root.Position).Magnitude <= ATK_RANGE then
                            for _, _v in ipairs(v:GetChildren()) do
                                if _v:IsA("BasePart") then parts[#parts + 1] = { v, _v } end
                            end
                        end
                    end end
                end
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

-- Giet QUAI: chi bat 3 lop, KHONG spam chieu (race v2 zombie / boss quest)
local function killMob(v, stillOn)
    if not (v and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart")) then return end
    equipFirstWeapon()
    ATK.players = false
    ATK.on = true
    repeat
        buso()
        TP(v.HumanoidRootPart.CFrame * CFrame.new(0, 18, 0))
        task.wait(0.2)
    until not v.Parent or v.Humanoid.Health <= 0 or (stillOn and not stillOn())
    ATK.on = false
end

local function findEnemy(name)
    for _, v in ipairs(Workspace.Enemies:GetChildren()) do
        if v.Name == name and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then return v end
    end
    local rep = ReplicatedStorage:FindFirstChild(name)
    return rep
end

--==================  DETECT STAGE (theo remote)  ==================--
-- V2 (Alchemist) xong = Alchemist","3" == -2
-- Wenlocktoad mo khoa  = Wenlocktoad","1" ~= nil
-- V3 xong              = Wenlocktoad","3" == -2
local function isV2Done()  return CommF("Alchemist", "3") == -2 end
local function wenlockOpen() return CommF("Wenlocktoad", "1") ~= nil end
local function isV3Done()  return CommF("Wenlocktoad", "3") == -2 end

--==================  V2: ALCHEMIST + FLOWER (func 8335-8399)  ==================--
local FLOWER3_AREA = Vector3.new(976.467651, 111.174057, 1229.1084)
local started_V2 = false

local function doV2()
    Status("V2: Alchemist (Flower)")
    -- start quest neu chua
    if not started_V2 then
        local s = CommF("Alchemist", "1")
        if s == 1 or s == 2 then started_V2 = true end
        CommF("Alchemist", "2")
        return
    end

    if not hasItem("Flower 3") then
        -- giet mob quanh khu Flower 3 toi khi co Flower 3
        if (hrp().Position - FLOWER3_AREA).Magnitude > 800 then
            TP(CFrame.new(FLOWER3_AREA)); return
        end
        for _, v in ipairs(Workspace.Enemies:GetChildren()) do
            if v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0
               and (v.HumanoidRootPart.Position - FLOWER3_AREA).Magnitude <= 800 then
                killMob(v, function() return not hasItem("Flower 3") end)
                if hasItem("Flower 3") then break end
            end
        end
    elseif not hasItem("Flower 2") then
        local f2 = Workspace:FindFirstChild("Flower2")
        if f2 then
            TP(f2.CFrame)
            if (hrp().Position - f2.Position).Magnitude <= 5 then
                VIM:SendKeyEvent(true, "Space", false, game); task.wait(0.5)
                VIM:SendKeyEvent(false, "Space", false, game)
            end
        end
    elseif not hasItem("Flower 1") then
        local f1 = Workspace:FindFirstChild("Flower1")
        if f1 then
            TP(f1.CFrame)
            if (hrp().Position - f1.Position).Magnitude <= 5 and f1.Transparency == 0 then
                VIM:SendKeyEvent(true, "Space", false, game); task.wait(0.5)
                VIM:SendKeyEvent(false, "Space", false, game)
            end
        end
    else
        -- du 3 flower -> nop
        CommF("Alchemist", "3"); task.wait(1)
        if CommF("Alchemist", "3") == -2 then Status("V2 DONE ✅") end
    end
end

--==================  CAU NOI: DON SWAN (func 8400-8430)  ==================--
local DON_SWAN_POS = CFrame.new(2288.802, 15.1870775, 863.034607)
local function doDonSwan()
    Status("Mo khoa Wenlocktoad: giet Don Swan")
    local boss = findEnemy("Don Swan")
    if not boss then TP(DON_SWAN_POS); return end
    if boss:FindFirstChild("Humanoid") then killMob(boss) end
end

--==================  V3 PER-RACE (func 8431-8757 + Cyborg/Ghoul)  ==================--
local started_V3 = false
local function startV3()
    CommF("Wenlocktoad", "1"); task.wait(1)
    CommF("Wenlocktoad", "2")
    local s = CommF("Wenlocktoad", "1")
    if s == 1 or s == 2 then started_V3 = true end
end
local function claimV3()
    CommF("Wenlocktoad", "3"); task.wait(1)
    if CommF("Wenlocktoad", "3") == -2 then
        Status("V3 DONE ✅ (" .. raceName() .. ")")
        _G.UpgradeRaceV3Done = true
        return true
    end
    return false
end

-- MINK: nhat 30 Chest
local mink_count = 0
local function v3_Mink()
    local nearest, best
    for _, v in ipairs(Workspace:GetChildren()) do
        if v.Name:find("Chest") and v:IsA("BasePart") then
            local d = (v.Position - hrp().Position).Magnitude
            if not best or d < best then best = d; nearest = v end
        end
    end
    if nearest then
        repeat
            TP(nearest.CFrame)
            if (nearest.Position - hrp().Position).Magnitude <= 5 then
                VIM:SendKeyEvent(true, "Space", false, game); task.wait(0.5)
                VIM:SendKeyEvent(false, "Space", false, game)
            end
            task.wait()
        until not nearest.Parent
        mink_count = mink_count + 1
        Status("Mink Chest: " .. mink_count .. "/30")
    end
    if mink_count >= 30 then claimV3() end
end

-- HUMAN: giet Fajita + Jeremy + Diamond
local kHuman = { Fajita = false, Jeremy = false, Diamond = false }
local HUMAN_FALLBACK = CFrame.new(-358.2200927734375, 155.2202911376953, 308.691650390625)
local function v3_Human()
    if kHuman.Fajita and kHuman.Jeremy and kHuman.Diamond then claimV3(); return end
    for _, name in ipairs({ "Fajita", "Jeremy", "Diamond" }) do
        if not kHuman[name] then
            local v = findEnemy(name)
            if v then
                if v:FindFirstChild("Humanoid") then killMob(v) else TP(v.HumanoidRootPart.CFrame * CFrame.new(0, 30, 0)) end
                kHuman[name] = true
                return
            end
        end
    end
    TP(HUMAN_FALLBACK); task.wait(1)
end

-- FISHMAN: lai boat PirateBasic ra giet SeaBeast (giu nguyen logic func.txt:8547-8659)
local FISH_SEABEAST_REF = Vector3.new(-3823.920654296875, 76.97933959960938, -11685.7734375)
local FISH_BOAT_TARGET  = CFrame.new(3017.20068359375, -4.25, -2686.33251953125)
local FISH_BUYBOAT_POS  = Vector3.new(-1967.2530517578125, 9.2692289352417, -2579.33154296875)
local Boat = nil

local function attackSeaBeast(v)
    repeat
        local fk = LocalPlayer.Backpack:FindFirstChild("Fishman Karate")
        if fk then char().Humanoid:EquipTool(fk) end
        TP(v.HumanoidRootPart.CFrame * CFrame.new(0, 3, 0))
        for _, key in ipairs({ "Z", "X", "C" }) do
            VIM:SendKeyEvent(true, key, false, game); task.wait(0.4)
            VIM:SendKeyEvent(false, key, false, game); task.wait(0.2)
        end
    until not v.Parent or v.Health.Value <= 0
end

local function v3_Fishman()
    local check_seabest = false
    local check_boat = false

    -- 1) Co SeaBeast (xa diem ref >= 1500) -> mua Fishman Karate + danh
    for _, v in ipairs(Workspace.SeaBeasts:GetChildren()) do
        if v:FindFirstChild("Health") and v.Health.Value > 0 and v:FindFirstChild("HumanoidRootPart")
           and (FISH_SEABEAST_REF - v.HumanoidRootPart.Position).Magnitude >= 1500 then
            check_seabest = true
            CommF("BuyFishmanKarate")
            local h = char():FindFirstChild("Humanoid")
            if h then h.Sit = false end
            wait(1)
            if h and not h.Sit then Boat = nil end
            repeat TP(v.HumanoidRootPart.CFrame * CFrame.new(0, 3, 0)); task.wait()
            until (v.HumanoidRootPart.Position - hrp().Position).Magnitude <= 5
            attackSeaBeast(v)
            if claimV3() then return end
        end
    end

    -- 2) Chua thay SeaBeast -> lai boat PirateBasic toi diem target
    if not check_seabest then
        for _, v in ipairs(Workspace.Boats:GetChildren()) do
            if v.Name == "PirateBasic" and v:FindFirstChild("Owner") and tostring(v.Owner.Value) == LocalPlayer.Name then
                check_boat = true
                local seat = v:FindFirstChild("VehicleSeat")
                local h = char():FindFirstChild("Humanoid")
                if seat then
                    if (FISH_BOAT_TARGET.Position - seat.Position).Magnitude >= 30 then
                        if h and h.Sit then
                            Boat = "Bit"; TPBoat(FISH_BOAT_TARGET, seat, 200)
                        elseif (hrp().Position - seat.Position).Magnitude >= 10 then
                            Boat = nil; TP(seat.CFrame)
                        else
                            Boat = "Bit"; notween(seat.CFrame * CFrame.new(0, 2, 0)); wait(1)
                        end
                    else
                        -- da toi noi -> ngoi yen (Button1) cho SeaBeast spawn
                        if h and h.Sit then
                            pcall(function() VirtualUser:Button1Down(Vector2.new(1280, 600)) end); wait(1)
                        elseif (hrp().Position - seat.Position).Magnitude >= 10 then
                            Boat = nil; TP(seat.CFrame)
                        else
                            Boat = "Bit"; notween(seat.CFrame * CFrame.new(0, 2, 0)); wait(1)
                        end
                    end
                end
            end
        end
    end

    -- 3) Khong co boat -> mua PirateBasic
    if not check_boat and not check_seabest then
        TP(CFrame.new(FISH_BUYBOAT_POS))
        if (FISH_BUYBOAT_POS - hrp().Position).Magnitude <= 3 then
            CommF("BuyBoat", "PirateBasic"); wait(1); Boat = "bit"
        end
    end
end

-- PvP: giet 1 player model (Skypiea + Ghoul) -> 3 lop + SPAM CHIEU Z/X/C
local function killPlayer(model)
    equipFirstWeapon()
    ATK.players = true
    ATK.on = true
    repeat
        buso()
        if LocalPlayer.PlayerGui.Main:FindFirstChild("PvpDisabled") and LocalPlayer.PlayerGui.Main.PvpDisabled.Visible then
            CommF("EnablePvp")
        end
        local off = ({ CFrame.new(0,35,1), CFrame.new(0,1,35), CFrame.new(35,1,0), CFrame.new(-35,1,0) })[math.random(1,4)]
        TP(model.HumanoidRootPart.CFrame * off)
        VIM:SendKeyEvent(true, "Z", false, game); VIM:SendKeyEvent(false, "Z", false, game)
        VIM:SendKeyEvent(true, "X", false, game); VIM:SendKeyEvent(false, "X", false, game)
        VIM:SendKeyEvent(true, "C", false, game); VIM:SendKeyEvent(false, "C", false, game)
        task.wait(0.2)
    until not model.Parent or (model:FindFirstChild("Humanoid") and model.Humanoid.Health <= 0)
    ATK.on = false
end

-- SKYPIEA: giet 1 nguoi toc Skypiea (het -> hop)
local SKY_POS = CFrame.new(638.43811, 71.769989, 918.282898)
local function v3_Skypiea()
    local targetName
    for _, p in ipairs(Players:GetChildren()) do
        if p ~= LocalPlayer and p:FindFirstChild("Data") and p.Data:FindFirstChild("Race") and tostring(p.Data.Race.Value) == "Skypiea" then
            targetName = p.Name; break
        end
    end
    if targetName then
        local m = Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(targetName)
        if m and m:FindFirstChild("HumanoidRootPart") then killPlayer(m) end
        claimV3()
    else
        TP(SKY_POS)
        Status("Skypiea: khong co nguoi toc Skypiea -> hop server")
        if CommF("Wenlocktoad", "3") ~= -2 then
            local sb = ReplicatedStorage:FindFirstChild("__ServerBrowser")
            if sb then pcall(function() local list = sb:InvokeServer(1); for jid, info in pairs(list) do if jid ~= game.JobId then sb:InvokeServer("teleport", jid); break end end end) end
        end
    end
end

-- CYBORG: lay 1 trai bat ky tu tui ra (LoadFruit) roi claim
local function v3_Cyborg()
    -- neu chua co fruit nao trong backpack -> load 1 trai tu kho
    local hasFruitOut = false
    for _, v in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if v:IsA("Tool") and tostring(v.ToolTip):find("Blox Fruit") then hasFruitOut = true; break end
    end
    if char() then
        for _, v in ipairs(char():GetChildren()) do
            if v:IsA("Tool") and tostring(v.ToolTip):find("Blox Fruit") then hasFruitOut = true; break end
        end
    end
    if not hasFruitOut then
        local inv = CommF("getInventoryFruits")
        if type(inv) == "table" then
            for _, f in pairs(inv) do
                local fname = (type(f) == "table") and f.Name or f
                if fname then
                    CommF("F_", "LoadFruit", fname) -- lay trai tu kho ra (gia bao nhieu cung duoc)
                    Status("Cyborg: LoadFruit " .. tostring(fname))
                    task.wait(1)
                    break
                end
            end
        end
    else
        claimV3()
    end
end

-- GHOUL: giet nguoi bat ky toi khi xong
local GHOUL_POS = CFrame.new(638.43811, 71.769989, 918.282898)
local function v3_Ghoul()
    if LocalPlayer.PlayerGui.Main:FindFirstChild("PvpDisabled") and LocalPlayer.PlayerGui.Main.PvpDisabled.Visible then
        CommF("EnablePvp")
    end
    local m
    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        for _, v in ipairs(chars:GetChildren()) do
            if v.Name ~= LocalPlayer.Name and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 then
                m = v; break
            end
        end
    end
    if m then
        killPlayer(m)
        claimV3() -- server dem du 5 nguoi thi "3" == -2
    else
        TP(GHOUL_POS)
        Status("Ghoul: khong co nguoi -> hop server")
        local sb = ReplicatedStorage:FindFirstChild("__ServerBrowser")
        if sb then pcall(function() local list = sb:InvokeServer(1); for jid in pairs(list) do if jid ~= game.JobId then sb:InvokeServer("teleport", jid); break end end end) end
    end
end

local V3_BY_RACE = {
    Mink = v3_Mink, Human = v3_Human, Fishman = v3_Fishman,
    Skypiea = v3_Skypiea, Cyborg = v3_Cyborg, Ghoul = v3_Ghoul,
}

local function doV3()
    if isV3Done() then Status("V3 da xong tu truoc ✅"); _G.UpgradeRaceV3Done = true; return end
    if beli() < CONFIG.BeliNeeded then
        _G.KhongDatYeuCau = ("Thieu Beli cho V3: %d / %d"):format(beli(), CONFIG.BeliNeeded)
        Status(_G.KhongDatYeuCau); return
    end
    if not started_V3 then startV3(); return end
    local fn = V3_BY_RACE[raceName()]
    if fn then Status("V3: " .. raceName()); fn() else Status("Toc '" .. raceName() .. "' khong ho tro V3") end
end

--==================  CHON TOC / REROLL (getgenv().race)  ==================--
-- getgenv().race = "rabbit;shark;angel;human;ghoul;cyborg"
--   rabbit->Mink  shark->Fishman  angel->Skypiea  human  : roll 2500 Fragment toi khi ra
--   ghoul, cyborg : KHONG roll duoc -> lam/mua theo Banana
local RACE_MAP = {
    rabbit = "Mink",    mink = "Mink",
    shark = "Fishman",  fishman = "Fishman",
    angel = "Skypiea",  skypiea = "Skypiea",
    human = "Human",
    ghoul = "Ghoul",
    cyborg = "Cyborg",
}
local REROLLABLE = { Human = true, Mink = true, Fishman = true, Skypiea = true }

local function targetRace()
    local r
    pcall(function() r = getgenv().race end)
    if not r or r == "" then return nil end
    return RACE_MAP[string.lower(tostring(r))]
end

-- Mua Ghoul/Cyborg = remote CO DINH (Banana "Buy Ghoul/Cyborg Race"). Throttle 3s + 1.5s detect.
local _lastBuy = 0

-- GHOUL: Ectoplasm BuyCheck 4 -> Change 4
local function getGhoul()
    if tick() - _lastBuy < 3 then return end
    _lastBuy = tick()
    Status("Buy Ghoul Race (Ectoplasm)")
    CommF("Ectoplasm", "BuyCheck", 4)
    task.wait(0.5)
    CommF("Ectoplasm", "Change", 4)
    task.wait(1.5)
end

-- CYBORG: CyborgTrainer Buy
local function getCyborg()
    if tick() - _lastBuy < 3 then return end
    _lastBuy = tick()
    Status("Buy Cyborg Race (CyborgTrainer)")
    CommF("CyborgTrainer", "Buy")
    task.wait(1.5)
end

-- Tra ve true neu da dung toc (hoac khong set muc tieu); false neu dang doi/lam.
local _lastRoll = 0
local function ensureRace()
    local target = targetRace()
    if not target then return true end           -- khong set getgenv().race
    if raceName() == target then return true end -- da dung toc

    if target == "Ghoul" then getGhoul(); return false end
    if target == "Cyborg" then getCyborg(); return false end

    if REROLLABLE[target] then
        local d = LocalPlayer:FindFirstChild("Data")
        if d and d:FindFirstChild("Fragments") and d.Fragments.Value < 2500 then
            Status("Reroll: thieu Fragment (<2500) | toc hien tai " .. raceName()); return false
        end
        if tick() - _lastRoll >= 3 then           -- moi roll cach nhau 3s
            Status("Reroll race -> " .. target .. " (dang la " .. raceName() .. ")")
            CommF("BlackbeardReward", "Reroll", "1")
            CommF("BlackbeardReward", "Reroll", "2")
            _lastRoll = tick()
            task.wait(1.5)                         -- delay 1.5s detect toc hien tai
        end
        return false
    end
    return true
end

--==================  UI STATUS / DEBUG  ==================--
local function tickMark(b) return b and "✅" or "❌" end

local function seaName()
    local p = tostring(game.PlaceId)
    if SEA_1[p] then return "Sea 1" elseif SEA_2[p] then return "Sea 2" elseif SEA_3[p] then return "Sea 3" end
    return "?"
end

local function fmtNum(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function detailText()
    local r = raceName()
    if r == "Mink" then return "Mink: Chest " .. mink_count .. "/30"
    elseif r == "Human" then return ("Human: Fajita %s Jeremy %s Diamond %s"):format(tickMark(kHuman.Fajita), tickMark(kHuman.Jeremy), tickMark(kHuman.Diamond))
    elseif r == "Fishman" then return "Fishman: lai boat -> giet SeaBeast"
    elseif r == "Skypiea" then return "Skypiea: PvP nguoi toc Skypiea"
    elseif r == "Cyborg" then return "Cyborg: LoadFruit 1 trai"
    elseif r == "Ghoul" then return "Ghoul: PvP giet nguoi"
    end
    return r
end

local function MakeUI()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    local old = parent:FindFirstChild("UpgradeRaceUI"); if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "UpgradeRaceUI"; gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 320, 0, 256)
    main.Position = UDim2.new(0, 18, 0, 110)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    main.BorderSizePixel = 0; main.Active = true; main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(70, 90, 160); stroke.Thickness = 1

    -- title bar (keo tha)
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 30); bar.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
    bar.BorderSizePixel = 0; bar.Parent = main
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -36, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0); title.Font = Enum.Font.GothamBold
    title.TextSize = 13; title.TextColor3 = Color3.fromRGB(235, 235, 245)
    title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "Upgrade Race  •  Debug"
    title.Parent = bar

    local btnMin = Instance.new("TextButton")
    btnMin.Size = UDim2.new(0, 26, 0, 22); btnMin.Position = UDim2.new(1, -30, 0, 4)
    btnMin.BackgroundColor3 = Color3.fromRGB(55, 60, 80); btnMin.Text = "–"
    btnMin.Font = Enum.Font.GothamBold; btnMin.TextSize = 14
    btnMin.TextColor3 = Color3.fromRGB(255, 255, 255); btnMin.Parent = bar
    Instance.new("UICorner", btnMin).CornerRadius = UDim.new(0, 6)

    -- body
    local body = Instance.new("Frame")
    body.BackgroundTransparency = 1; body.Position = UDim2.new(0, 10, 0, 36)
    body.Size = UDim2.new(1, -20, 1, -44); body.Parent = main
    local layout = Instance.new("UIListLayout", body)
    layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Padding = UDim.new(0, 3)

    local function row(h, color, bold, order)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1; l.Size = UDim2.new(1, 0, 0, h)
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        l.TextSize = 12; l.TextColor3 = color or Color3.fromRGB(210, 210, 220)
        l.TextXAlignment = Enum.TextXAlignment.Left; l.TextYAlignment = Enum.TextYAlignment.Top
        l.TextWrapped = true; l.LayoutOrder = order; l.Text = ""; l.Parent = body
        return l
    end

    local lStatus = row(32, Color3.fromRGB(120, 220, 140), true, 1)
    local lInfo   = row(16, Color3.fromRGB(180, 200, 255), false, 2)
    local lSea    = row(16, Color3.fromRGB(180, 200, 255), false, 3)
    local lStage  = row(16, Color3.fromRGB(255, 220, 150), true, 4)
    local lDetail = row(16, Color3.fromRGB(200, 200, 210), false, 5)
    local lLogT   = row(14, Color3.fromRGB(120, 130, 150), true, 6); lLogT.Text = "Log:"
    local lLog    = row(90, Color3.fromRGB(160, 165, 180), false, 7)

    -- keo tha bang title bar
    local dragging, dragStart, startPos
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = main.Position
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    game:GetService("UserInputService").InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    local mini = false
    btnMin.MouseButton1Click:Connect(function()
        mini = not mini
        body.Visible = not mini
        main.Size = mini and UDim2.new(0, 320, 0, 30) or UDim2.new(0, 320, 0, 256)
    end)

    -- vong cap nhat
    task.spawn(function()
        while gui.Parent do
            task.wait(0.3)
            lStatus.Text = "● " .. tostring(_G.UpgradeRaceStatus or "...")
            lStatus.TextColor3 = _G.UpgradeRaceV3Done and Color3.fromRGB(120, 220, 140) or Color3.fromRGB(255, 235, 150)
            local tgt = targetRace()
            local tocStr = raceName() .. ((tgt and tgt ~= raceName()) and (" -> " .. tgt) or "")
            lInfo.Text  = ("Toc: %s   |   Lv: %s   |   Beli: %s"):format(tocStr, fmtNum(level()), fmtNum(beli()))
            lSea.Text   = ("Place: %s  (%s)"):format(tostring(game.PlaceId), seaName())
            lStage.Text = ("V2 %s    Wenlock %s    V3 %s"):format(tickMark(DBG.v2), tickMark(DBG.wenlock), tickMark(DBG.v3 or _G.UpgradeRaceV3Done))
            lDetail.Text = detailText()
            lLog.Text   = table.concat(LOG, "\n")
        end
    end)
end

pcall(MakeUI)

--==================  MAIN LOOP  ==================--
local function CheckPre()
    if not hrp() then _G.KhongDatYeuCau = "Nhan vat chua load"; return false end
    if level() < CONFIG.MinLevel then
        _G.KhongDatYeuCau = ("Level thieu: %d / %d"):format(level(), CONFIG.MinLevel)
        return false
    end
    return true
end

local function Main()
    print("[Race] Toc:", raceName(), "| Lv:", level(), "| Beli:", beli(), "| Place:", game.PlaceId)
    while task.wait(CONFIG.LoopWait) do
        local ok, err = pcall(function()
            if not CheckPre() then Status("KhongDatYeuCau: " .. tostring(_G.KhongDatYeuCau)); return end

            -- Up toc V1-V3 phai o Sea 2 -> khong o thi tu ve Sea 2
            if not inSea2() then
                Status("Khong o Sea 2 (place " .. tostring(game.PlaceId) .. ") -> ve Sea 2 (TravelDressrosa)")
                goToSea2()
                return
            end

            -- Chon toc: reroll / mua toi khi dung getgenv().race roi moi up
            if not ensureRace() then return end

            local v2 = isV2Done(); DBG.v2 = v2
            if CONFIG.DoV2 and not v2 then
                doV2()
            else
                local wl = wenlockOpen(); DBG.wenlock = wl
                if CONFIG.DoDonSwan and not wl then
                    doDonSwan()
                elseif CONFIG.DoV3 then
                    doV3()
                    if _G.UpgradeRaceV3Done then return end
                end
            end
            DBG.v3 = _G.UpgradeRaceV3Done == true
        end)
        if not ok then warn("[Race] loop err:", tostring(err)) end
        if _G.UpgradeRaceV3Done then Status("HOAN TAT NANG TOC ✅"); break end
    end
end

Main()
