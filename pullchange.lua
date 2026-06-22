--[[
    changepull.lua  -  Detect Sea -> Travel Sea 3 -> Check Pull Lever -> ghi file
    ----------------------------------------------------------------------
    Luong:
      0) Doi nhan vat load xong (co HumanoidRootPart)
      1) DETECT SEA: neu dang o Sea 1/2 -> travel len Sea 3.
         Detect lien tuc moi 15 giay den khi len duoc Sea 3.
      2) Check xem da pull lever chua (remote "templedoorcheck",
         fallback "CheckTempleDoor" - lay tu Auto.lua:IsLeverDone)
      3) Neu CHUA xong  -> doi 5 giay roi check lai
      4) Neu DA xong     -> ghi file "<PlayerName>.txt" = "Completed-pull"
                            vao workspace executor roi dung.
    ----------------------------------------------------------------------
]]

--==================  SERVICES  ==================--
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local CHECK_INTERVAL = 5   -- giay giua 2 lan check lever
local SEA_INTERVAL   = 15  -- giay giua 2 lan detect sea

-- PlaceId Sea 3 (Third Sea - noi co Mirage / can gat). Lay tu Auto.lua:66-69
local THIRD_SEA_PLACES = {
    [7449423635]      = true,
    [100117331123089] = true,
}
-- PlaceId Sea 2 (New World). Lay tu Auto.lua:71-74
local SEA2_PLACES = {
    [4442272183]     = true,
    [79091703265657] = true,
}

--==================  TIEN ICH  ==================--
local function getRemotes()
    return ReplicatedStorage:FindFirstChild("Remotes")
end

-- Goi remote CommF_ an toan (giong Auto.lua)
local function CommF(...)
    local remotes = getRemotes()
    if not remotes or not remotes:FindFirstChild("CommF_") then return nil end
    local ok, res = pcall(function(...)
        return remotes.CommF_:InvokeServer(...)
    end, ...)
    if ok then return res end
    return nil
end

-- DA PULL LEVER CHUA? (templedoorcheck -> bool; fallback ten remote ban cu)
-- Lay nguyen tu Auto.lua:160-165 (IsLeverDone)
local function IsLeverDone()
    local res = CommF("templedoorcheck")
    if res == nil then res = CommF("CheckTempleDoor") end
    return res == true
end

-- Ghi file "<PlayerName>.txt" = "Completed-pull" vao workspace executor (chi ghi 1 lan)
local _savedPullFile = false
local function SavePullFile()
    if _savedPullFile then return end
    if type(writefile) ~= "function" then
        warn("[changepull] Executor khong ho tro writefile -> khong ghi duoc file")
        return
    end
    local fileName = tostring(LocalPlayer.Name) .. ".txt"
    local ok = pcall(function() writefile(fileName, "Completed-pull") end)
    if ok then
        _savedPullFile = true
        print("[changepull] Da ghi file: " .. fileName .. " (Completed-pull)")
    else
        warn("[changepull] Ghi file that bai: " .. fileName)
    end
end

-- Doi nhan vat load xong (co HumanoidRootPart) roi moi lam tiep
local function WaitForCharacter()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    char:WaitForChild("HumanoidRootPart")
    print("[changepull] Nhan vat da load")
    return char
end

-- DETECT SEA + TRAVEL LEN SEA 3 (Sea1 -> Sea2 -> Sea3). Method chuan tu Auto.lua:105-125
--   TravelZou       = Sea2 -> Sea3
--   TravelDressrosa = Sea1/khac -> Sea2
-- Detect lien tuc moi 15 giay den khi len duoc Sea 3 thi dung.
-- Luu y: travel sang sea khac se teleport -> reload place -> script chay lai o sea moi,
-- nen vong lap nay chi lap khi travel chua thanh cong trong cung 1 place.
local function EnsureSea3()
    while not THIRD_SEA_PLACES[game.PlaceId] do
        if SEA2_PLACES[game.PlaceId] then
            print("[changepull] Dang o Sea 2 (place " .. tostring(game.PlaceId) .. ") -> TravelZou len Sea 3")
            CommF("TravelZou")        -- Sea2 -> Sea3
        else
            print("[changepull] Dang o Sea 1/khac (place " .. tostring(game.PlaceId) .. ") -> TravelDressrosa len Sea 2")
            CommF("TravelDressrosa")  -- Sea1/khac -> Sea2
        end
        task.wait(SEA_INTERVAL)
    end
    print("[changepull] Da o Sea 3 (place " .. tostring(game.PlaceId) .. ")")
end

--==================  VONG CHINH  ==================--
local function Main()
    print("[changepull] Khoi dong (" .. tostring(LocalPlayer.Name) .. ")")

    -- B0: doi nhan vat load
    WaitForCharacter()

    -- B1: detect sea -> neu Sea 1/2 thi travel len Sea 3 (detect moi 15s)
    EnsureSea3()

    -- B2: check pull lever, chua xong thi doi 5s check lai
    print("[changepull] Bat dau check pull lever")
    while true do
        local ok, done = pcall(IsLeverDone)
        if ok and done then
            print("[changepull] DA PULL LEVER -> ghi file")
            SavePullFile()
            break
        end
        -- chua xong -> doi 5 giay check lai
        task.wait(CHECK_INTERVAL)
    end
end

Main()
