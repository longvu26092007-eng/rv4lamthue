--[[
    changepull.lua  -  Check Pull Lever -> ghi file khi xong
    ----------------------------------------------------------------------
    Luong:
      1) Check xem da pull lever chua (remote "templedoorcheck",
         fallback "CheckTempleDoor" - lay tu Auto.lua:IsLeverDone)
      2) Neu CHUA xong  -> doi 5 giay roi check lai
      3) Neu DA xong     -> ghi file "<PlayerName>.txt" = "Completed-pull"
                            vao workspace executor roi dung.
    ----------------------------------------------------------------------
]]

--==================  SERVICES  ==================--
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local CHECK_INTERVAL = 5  -- giay giua 2 lan check

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

--==================  VONG CHINH  ==================--
local function Main()
    print("[changepull] Bat dau check pull lever (" .. tostring(LocalPlayer.Name) .. ")")
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
