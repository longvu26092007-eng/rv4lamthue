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

--==================  COMBAT (don gian, tu chua)  ==================--
local function equipFirstWeapon()
    local c = char(); if not c then return end
    -- uu tien Melee, khong thi lay tool dau tien
    for _, v in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if v:IsA("Tool") and tostring(v.ToolTip) == "Melee" then
            c.Humanoid:EquipTool(v); return
        end
    end
    for _, v in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if v:IsA("Tool") then c.Humanoid:EquipTool(v); return end
    end
end

local function clickAttack()
    pcall(function()
        VirtualUser:Button1Down(Vector2.new(1280, 600))
        VirtualUser:Button1Up(Vector2.new(1280, 600))
    end)
end

local function buso()
    if char() and not char():FindFirstChild("HasBuso") then CommF("Buso") end
end

-- Giet mob co Humanoid (TP len dau + click + Z/X/C)
local function killMob(v, stillOn)
    if not (v and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart")) then return end
    equipFirstWeapon()
    repeat
        buso()
        TP(v.HumanoidRootPart.CFrame * CFrame.new(0, 20, 0))
        clickAttack()
        VIM:SendKeyEvent(true, "Z", false, game); VIM:SendKeyEvent(false, "Z", false, game)
        VIM:SendKeyEvent(true, "X", false, game); VIM:SendKeyEvent(false, "X", false, game)
        VIM:SendKeyEvent(true, "C", false, game); VIM:SendKeyEvent(false, "C", false, game)
        task.wait(0.2)
    until not v.Parent or v.Humanoid.Health <= 0 or (stillOn and not stillOn())
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

-- PvP: giet 1 player model (dung cho Skypiea + Ghoul)
local function killPlayer(model)
    equipFirstWeapon()
    repeat
        buso()
        if LocalPlayer.PlayerGui.Main:FindFirstChild("PvpDisabled") and LocalPlayer.PlayerGui.Main.PvpDisabled.Visible then
            CommF("EnablePvp")
        end
        local off = ({ CFrame.new(0,35,1), CFrame.new(0,1,35), CFrame.new(35,1,0), CFrame.new(-35,1,0) })[math.random(1,4)]
        TP(model.HumanoidRootPart.CFrame * off)
        clickAttack()
        VIM:SendKeyEvent(true, "Z", false, game); VIM:SendKeyEvent(false, "Z", false, game)
        VIM:SendKeyEvent(true, "X", false, game); VIM:SendKeyEvent(false, "X", false, game)
        VIM:SendKeyEvent(true, "C", false, game); VIM:SendKeyEvent(false, "C", false, game)
        task.wait(0.2)
    until not model.Parent or (model:FindFirstChild("Humanoid") and model.Humanoid.Health <= 0)
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

            if CONFIG.DoV2 and not isV2Done() then
                doV2()
            elseif CONFIG.DoDonSwan and not wenlockOpen() then
                doDonSwan()
            elseif CONFIG.DoV3 then
                doV3()
                if _G.UpgradeRaceV3Done then return end
            end
        end)
        if not ok then warn("[Race] loop err:", tostring(err)) end
        if _G.UpgradeRaceV3Done then Status("HOAN TAT NANG TOC ✅"); break end
    end
end

Main()
