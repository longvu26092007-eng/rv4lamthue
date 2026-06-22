--[[
    Auto.lua  -  Auto Pull Lever (Race V4) - BAM CHUAN func.txt
    ----------------------------------------------------------------------
    Luong:
      1) CHECK DIEU KIEN  -> dat thi qua buoc 2
                          -> khong dat thi set _G.KhongDatYeuCau = "<ly do>"
      2) PULL LEVER (theo func.txt:7305-7438):
         a) RaceV4Progress state machine: Check -> Begin/Teleport/Continue
            (set ExSeb khi Check >= 3)
         b) Khi ExSeb: neu server khong co Mirage -> hop bang API name=mirage
         c) Khi co Mirage -> bay len dao (WorldPivot+500), CHI keo ban dem:
            - ep MoonAngularSize=60 + khoa camera theo gio (5 khung gio)
            - nhan "T" -> wait(17)
            - cham tung Part 'Part' (Transparency 0) bang TP+Space den khi
              tang hinh -> CheckTempleDoor == true la xong
    ----------------------------------------------------------------------
]]

--==================  SERVICES  ==================--
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local TeleportService   = game:GetService("TeleportService")
local TweenService      = game:GetService("TweenService")
local VIM               = game:GetService("VirtualInputManager")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

--==================  CONFIG  ==================--
local CONFIG = {
    MirageApiUrl   = "http://fi11.bot-hosting.net:20758/api/name=mirage", -- API lay server co dao
    TweenSpeed     = 320,    -- toc do bay (studs/s)
    LoopWait       = 0.5,    -- nhip vong lap chinh
    RequireRaceV3  = true,   -- bat buoc co RaceEnergy (Race V3) moi chay
    MaxPlayer      = 12,     -- chi hop vao server con cho (player < MaxPlayer)
    AllowCrossPlace = false, -- true = cho phep hop sang placeid khac game hien tai
    Team           = "Pirates", -- phe mac dinh khi acc chua chon (Pirates / Marines)
}

--==================  TIEN ICH CHUNG  ==================--
local function getRemotes()
    return ReplicatedStorage:FindFirstChild("Remotes")
end

-- PlaceId cua chinh minh (nguon su that, khong hard-code)
local MyPlaceId = game.PlaceId

-- Cac PlaceId Third Sea da biet (fast-path, khong can goi mang)
-- 7449423635 = Third Sea chuan; 100117331123089 cung xuat hien trong API name=mirage
local THIRD_SEA_PLACES = {
    [7449423635]      = true,
    [100117331123089] = true,
}
-- PlaceId Sea 2 (New World) - de biet dang o Sea 2 thi TravelZou len thang Sea 3
local SEA2_PLACES = {
    [4442272183]     = true,
    [79091703265657] = true,
}

local httpGet -- forward declare (dinh nghia o phan API ben duoi)

-- Place hien tai co phai noi co Mirage khong?
--   1) nam trong danh sach Third Sea da biet, HOAC
--   2) chinh placeid cua minh xuat hien trong API name=mirage (tu xac nhan)
local _placeOkCache = nil
local function IsMiragePlace()
    if THIRD_SEA_PLACES[MyPlaceId] then return true end
    if _placeOkCache ~= nil then return _placeOkCache end
    local body = httpGet and httpGet(CONFIG.MirageApiUrl)
    local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if ok and type(decoded) == "table" and type(decoded.data) == "table" then
        for _, s in ipairs(decoded.data) do
            if tonumber(s.placeid) == MyPlaceId then
                _placeOkCache = true
                return true
            end
        end
    end
    _placeOkCache = false
    return false
end

-- TU TRAVEL LEN SEA 3 (Sea1/khac -> Sea2 -> Sea3). Method chuan tu KaitunV4:
--   TravelZou       = Sea2 -> Sea3
--   TravelDressrosa = Sea1/khac -> Sea2 (vong sau script chay lai se len tiep Sea3)
-- Tra ve true neu DANG di chuyen (chua o Sea3) -> Main nen return cho;
-- false neu da o Sea3 -> chay tiep binh thuong.
local _sea3Started = false
local function EnsureSea3()
    if THIRD_SEA_PLACES[game.PlaceId] then return false end -- da o Sea 3
    if _sea3Started then return true end
    _sea3Started = true
    print("[Auto] Chua o Sea 3 (place " .. tostring(game.PlaceId) .. ") -> tu travel len Sea 3...")
    -- boc thread con: InvokeServer co the yield -> tranh treo luc load neu server cham
    task.spawn(function()
        local R = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")
        while not THIRD_SEA_PLACES[game.PlaceId] do
            pcall(function()
                if SEA2_PLACES[game.PlaceId] then
                    R:InvokeServer("TravelZou")        -- Sea2 -> Sea3
                else
                    R:InvokeServer("TravelDressrosa")  -- Sea1/khac -> Sea2
                end
            end)
            task.wait(5)
        end
    end)
    return true
end

-- TP an toan bang tween (tranh kick anti-cheat khi giật CFrame xa)
local function TP(targetCFrame)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if char:FindFirstChild("Humanoid") then char.Humanoid.Sit = false end
    local dist = (targetCFrame.Position - hrp.Position).Magnitude
    local info = TweenInfo.new(math.max(dist / CONFIG.TweenSpeed, 0.1), Enum.EasingStyle.Linear)
    local tw   = TweenService:Create(hrp, info, { CFrame = targetCFrame })
    tw:Play()
    tw.Completed:Wait()
end

-- Goi remote CommF_ an toan
local function CommF(...)
    local remotes = getRemotes()
    if not remotes or not remotes:FindFirstChild("CommF_") then return nil end
    local ok, res = pcall(function(...)
        return remotes.CommF_:InvokeServer(...)
    end, ...)
    if ok then return res end
    return nil
end

-- Goi remote CommE an toan
local function CommE(...)
    local remotes = getRemotes()
    if not remotes or not remotes:FindFirstChild("CommE") then return end
    pcall(function(...)
        remotes.CommE:FireServer(...)
    end, ...)
end

-- Lever da hoan thanh chua? (templedoorcheck -> bool)
local function IsLeverDone()
    local res = CommF("templedoorcheck")
    if res == nil then res = CommF("CheckTempleDoor") end -- fallback ten remote ban cu
    return res == true
end

-- Ghi file "<PlayerName>.txt" = "Completed-pull" vao workspace executor (chi ghi 1 lan)
local _savedPullFile = false
local function SavePullFile()
    if _savedPullFile then return end
    if type(writefile) ~= "function" then return end -- executor khong ho tro writefile
    local fileName = tostring(LocalPlayer.Name) .. ".txt"
    local ok = pcall(function() writefile(fileName, "Completed-pull") end)
    if ok then
        _savedPullFile = true
        _G.AutoPullFileSaved = fileName
        print("[Auto] Da ghi file: " .. fileName .. " (Completed-pull)")
    end
end

local function getMystic()
    local map = Workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("MysticIsland")
end

-- JOIN TEAM: tham gia phe (Pirates/Marines). Acc moi bi ket man chon phe
-- se khong di chuyen / lam quest duoc cho den khi chon.
-- FIX: join BEN — retry CA 2 cach (remote SetTeam + fallback bam UI ChooseTeam) toi khi
-- co team that. Truoc day chi goi remote 1 lan nen "luc duoc luc khong" (remote chua san /
-- UI chua load kip). Method chuan tu KaitunV4.
local function EnsureTeam()
    -- doi game load xong
    local t0 = tick()
    repeat task.wait() until game:IsLoaded() or tick() - t0 > 15

    if LocalPlayer.Team then return end -- da co phe -> bo qua

    local team = CONFIG.Team
    pcall(function() if getgenv().Team then team = getgenv().Team end end)
    if team ~= "Pirates" and team ~= "Marines" then team = "Pirates" end

    print("[Auto] Chua co phe -> join team:", team)
    local attempts = 0
    while not LocalPlayer.Team and attempts < 40 do
        attempts = attempts + 1

        -- Cach 1: goi thang remote SetTeam
        CommF("SetTeam", team)
        task.wait(0.4)
        if LocalPlayer.Team then break end

        -- Cach 2: fallback bam UI ChooseTeam (getgc) khi remote khong an
        pcall(function()
            local chooseGui = LocalPlayer.PlayerGui:FindFirstChild("ChooseTeam", true)
            local uiCtrl    = LocalPlayer.PlayerGui:FindFirstChild("UIController", true)
            if chooseGui and chooseGui.Visible and uiCtrl and getgc then
                for _, fn in pairs(getgc(true)) do
                    if type(fn) == "function" and getfenv(fn).script == uiCtrl then
                        local consts = getconstants and getconstants(fn)
                        if consts and #consts == 1 and (consts[1] == "Pirates" or consts[1] == "Marines") then
                            if consts[1] == team then pcall(fn, team) end
                        end
                    end
                end
            end
        end)
        task.wait(0.8)
    end
    if LocalPlayer.Team then
        print("[Auto] Da vao team:", tostring(LocalPlayer.Team and LocalPlayer.Team.Name))
    else
        warn("[Auto] Join team that bai sau " .. attempts .. " lan thu")
    end
end

--==================  BUOC 1: CHECK DIEU KIEN  ==================--
-- Tra ve true neu dat het; nguoc lai set _G.KhongDatYeuCau va tra ve false.
local function CheckDieuKien()
    _G.KhongDatYeuCau = nil

    -- 1. Nhan vat da load
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then
        _G.KhongDatYeuCau = "Nhan vat chua load (khong co HumanoidRootPart)"
        return false
    end

    -- 2. Phai o noi co Mirage (Third Sea) - tu check theo placeid cua chinh minh
    if not IsMiragePlace() then
        _G.KhongDatYeuCau = ("Place hien tai (%s) khong phai noi co Mirage / Third Sea")
            :format(tostring(MyPlaceId))
        return false
    end

    -- 3. Co du lieu Race
    local data = LocalPlayer:FindFirstChild("Data")
    if not (data and data:FindFirstChild("Race")) then
        _G.KhongDatYeuCau = "Khong doc duoc Data.Race cua nhan vat"
        return false
    end

    -- 4. Da mo Race V3 (co RaceEnergy) -> moi keo can gat duoc
    if CONFIG.RequireRaceV3 then
        local energy = char:FindFirstChild("RaceEnergy")
        if not energy then
            _G.KhongDatYeuCau = "Chua mo Race V3 (khong tim thay RaceEnergy)"
            return false
        end
    end

    -- 5. Lever da xong roi thi khong can lam nua
    if IsLeverDone() then
        _G.KhongDatYeuCau = "Da hoan thanh Pull Lever tu truoc (templedoorcheck = true)"
        return false
    end

    return true
end

--==================  HOP SERVER CO MIRAGE (API)  ==================--
function httpGet(url) -- gan vao bien da forward-declare o tren
    local fns = { (syn and syn.request), (http and http.request), request, http_request }
    for _, fn in ipairs(fns) do
        if type(fn) == "function" then
            local ok, res = pcall(fn, { Url = url, Method = "GET" })
            if ok and res and res.Body then return res.Body end
        end
    end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok then return body end
    return nil
end

-- API tra ve: {"count":N,"data":[{"jobid":"..","placeid":N,"player":N}, ...],"success":true}
-- Chon server cung placeid voi game hien tai, con cho, it nguoi nhat.
local function pickMirageServer(body)
    if not body or body == "" then return nil end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(decoded) ~= "table" or type(decoded.data) ~= "table" then
        return nil
    end

    local function scan(samePlaceOnly)
        local best
        for _, s in ipairs(decoded.data) do
            local jobid   = s.jobid or s.JobId or s.jobId
            local placeid = tonumber(s.placeid or s.placeId)
            local player  = tonumber(s.player) or 0
            if jobid and jobid ~= game.JobId and player < CONFIG.MaxPlayer then
                local okPlace = (not samePlaceOnly) or (placeid == game.PlaceId)
                if okPlace and (not best or player < best.player) then
                    best = { jobid = jobid, placeid = placeid or game.PlaceId, player = player }
                end
            end
        end
        return best
    end

    -- uu tien server cung place; chi cross-place khi duoc cho phep
    local best = scan(true)
    if not best and CONFIG.AllowCrossPlace then best = scan(false) end
    return best
end

local _lastHop = 0
local function HopToMirageServer()
    -- chong spam hop (cach nhau toi thieu 8s)
    if tick() - _lastHop < 8 then return end
    _lastHop = tick()

    local body   = httpGet(CONFIG.MirageApiUrl)
    local server = pickMirageServer(body)
    if not server then
        warn("[Auto] API khong co server Mirage hop le:", tostring(body))
        return
    end

    print(("[Auto] Hop sang server Mirage: %s | place=%s | player=%d")
        :format(server.jobid, tostring(server.placeid), server.player))

    -- Cung place -> dung __ServerBrowser teleport (chuan trong memory)
    if server.placeid == game.PlaceId then
        local sb = ReplicatedStorage:FindFirstChild("__ServerBrowser")
        if sb then
            local ok = pcall(function() sb:InvokeServer("teleport", server.jobid) end)
            if ok then return end
        end
    end
    -- Khac place hoac khong co __ServerBrowser -> TeleportToPlaceInstance (dung placeid cua server)
    pcall(function()
        TeleportService:TeleportToPlaceInstance(server.placeid, server.jobid, LocalPlayer)
    end)
end

--==================  STATE (giong func.txt)  ==================--
local ExSeb        = false   -- da qua RaceV4Progress (Check >= 3)
local ujihfdg      = false   -- da goi "Continue" mot lan
local PullLeverDone = false  -- da keo xong lever

--==================  RACEV4PROGRESS STATE MACHINE  ==================--
-- func.txt:7307-7354  (CommF_ "RaceV4Progress": Check/Begin/Teleport/Continue)
local function RaceV4Progress()
    local stage = CommF("RaceV4Progress", "Check")
    if stage == 1 then
        CommF("RaceV4Progress", "Check")
        CommF("RaceV4Progress", "Begin")

    elseif stage == 2 then
        CommF("RaceV4Progress", "Check")
        repeat
            task.wait()
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = CFrame.new(2959.87231, 2282.42139, -7216.23193) end
            CommF("RaceV4Progress", "Teleport")
            hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then break end
        until (LocalPlayer.Character.HumanoidRootPart.Position
               - Vector3.new(28286.35546875, 14896.5078125, 102.62469482421875)).Magnitude <= 15

    elseif stage == 3 then
        ExSeb = true
        if not ujihfdg then
            CommF("RaceV4Progress", "Check")
            wait(1)
            CommF("RaceV4Progress", "Continue")
            ujihfdg = true
        end

    elseif stage == 4 then
        ExSeb = true
    end
end

--==================  NGAM TRANG THEO GIO (func.txt:7375-7404)  ==================--
-- Tra ve CFrame camera tuong ung khung gio dem, hoac nil neu ban ngay.
local function MoonCamByHour(hour)
    if not hour then return nil end
    if hour >= 18 and hour < 20 then
        return CFrame.new(256.224945, 10.0014305, 7402.05225, -0.86680156, -0.285385847, -0.408913255, 0, 0.820035219, -0.57231313, 0.498653352, -0.496081918, -0.710807681)
    elseif hour >= 20 and hour < 23 then
        return CFrame.new(276.224945, 10.0014305, 7402.05225, -0.86680156, -0.285385847, -0.408913255, 0, 0.820035219, -0.57231313, 0.498653352, -0.496081918, -0.710807681)
    elseif hour >= 23 then
        return CFrame.new(280.220398, 10.0163631, 7398.78711, -0.99949348, 0.0149384635, 0.028100336, 9.31322464e-10, 0.882983506, -0.469404191, -0.0318243057, -0.469166428, -0.882536292)
    elseif hour >= 0 and hour < 2 then
        return CFrame.new(187.110519, 311.094543, 7251.67285, -0.983385324, 0.120902099, 0.135410622, -7.4505806e-09, 0.745938301, -0.666015029, -0.181530595, -0.654949427, -0.733544707)
    elseif hour >= 2 and hour <= 5 then
        return CFrame.new(17.9850445, 541.176575, 6902.08154, -0.866957009, 0.111039586, 0.485855788, 0, 0.974864244, -0.222799659, -0.498383105, -0.193157732, -0.845165253)
    end
    return nil
end

--==================  KEO CAN GAT (func.txt:7356-7434)  ==================--
local function PullLeverOnce()
    local mystic = getMystic()
    if not mystic then return end

    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChild("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- dang ngoi thuyen -> dung day + nhich len
    if hum and hum.Sit then
        hum.Sit = false
        wait(0.5)
        hrp.CFrame = hrp.CFrame * CFrame.new(0, 15, 0)
        wait(1)
        return
    end

    -- bay len dinh dao (WorldPivot + 500); con xa thi TP toi
    local pointer = mystic:GetPivot() * CFrame.new(0, 500, 0)
    if (pointer.Position - hrp.Position).Magnitude > 25 then
        TP(pointer)
        return
    end

    if PullLeverDone then return end

    wait(1)
    -- doc gio tu Lighting.TimeOfDay ("HH:MM:SS")
    local hour  = tonumber(tostring(Lighting.TimeOfDay):match("^(%d+)"))
    local camCF = MoonCamByHour(hour)
    if not camCF then
        print("[Auto] Chua phai ban dem (gio=" .. tostring(hour) .. ") -> doi trang len...")
        return
    end

    -- ngam trang: ep trang to + khoa camera (set 2 lan nhu func.txt)
    pcall(function()
        local sky = Lighting:FindFirstChildOfClass("Sky")
        if sky then sky.MoonAngularSize = 60 end
    end)
    Workspace.CurrentCamera.CFrame = camCF
    wait(0.3)
    Workspace.CurrentCamera.CFrame = camCF

    -- nhan T de keo lever
    wait(1)
    VIM:SendKeyEvent(true,  "T", false, game)
    wait(1)
    VIM:SendKeyEvent(false, "T", false, game)
    wait(17)

    -- cham tung "Part" noi len bang TP + Space den khi tang hinh, roi check temple door
    for _, v in ipairs(mystic:GetChildren()) do
        if v.ClassName == "MeshPart" and v.Name == "Part" and v.Transparency == 0 then
            repeat
                wait(0.2)
                TP(v.CFrame)
                wait(0.5)
                VIM:SendKeyEvent(true,  "Space", false, game)
                wait(0.5)
                VIM:SendKeyEvent(false, "Space", false, game)
            until v.Transparency == 1 or not v.Parent
            wait(0.5)
            if CommF("CheckTempleDoor") == true then
                PullLeverDone = true
                SavePullFile()
                print("[Auto] PULL LEVER HOAN THANH ✅ (CheckTempleDoor = true)")
            end
        end
    end
end

--==================  VONG CHINH BUOC 2 (chuan func.txt)  ==================--
local function RunPullLever()
    print("[Auto] Dieu kien DAT -> bat dau quy trinh Pull Lever (chuan func.txt)")
    while task.wait(CONFIG.LoopWait) do
        local ok, err = pcall(function()
            if PullLeverDone or IsLeverDone() then
                SavePullFile()
                print("[Auto] PULL LEVER HOAN THANH ✅")
                _G.AutoPullLeverDone = true
                return
            end

            if not ExSeb then
                -- chua qua quest -> chay RaceV4Progress (Begin/Teleport/Continue)
                RaceV4Progress()
            elseif not getMystic() then
                -- da qua quest nhung server khong co Mirage -> hop bang API
                HopToMirageServer()
            else
                -- da co Mirage -> keo lever theo dung func.txt
                PullLeverOnce()
            end
        end)
        if not ok then warn("[Auto] loop err:", tostring(err)) end
        if _G.AutoPullLeverDone then break end
    end
end

--==================  ENTRY  ==================--
local function Main()
    print("[Auto] PlaceId cua ban (game.PlaceId) =", MyPlaceId, "| JobId =", game.JobId)

    -- Chua o Sea 3 -> tu travel len Sea 3 roi dung (script se chay lai sau khi teleport)
    if EnsureSea3() then
        print("[Auto] Dang travel len Sea 3... (cho teleport, script chay lai o sea moi)")
        return
    end

    EnsureTeam() -- join team (chon phe) truoc neu acc chua co
    if CheckDieuKien() then
        RunPullLever()
    else
        warn("[Auto] KhongDatYeuCau: " .. tostring(_G.KhongDatYeuCau))
        -- giu trang thai de UI / script khac doc duoc
        local StarterGui = game:GetService("StarterGui")
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Auto Pull Lever",
                Text  = "KhongDatYeuCau: " .. tostring(_G.KhongDatYeuCau),
                Duration = 8,
            })
        end)
    end
end

Main()
