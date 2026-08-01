-- ==========================================
-- [ FRAGMENT CHECKER + AUTO SEA 3 + AUTO RACE ]
-- Chức năng:
--   1. Đợi game load
--   2. Kiểm tra Sea hiện tại
--   3. Sea 1 -> Sea 2 -> Sea 3
--   4. Chỉ chạy Fragment/Race checker khi đã ở Sea 3
--   5. Nếu bật target race:
--        - Đúng race  -> không reroll
--        - Sai race   -> reroll liên tục đến khi đúng
--   6. Chỉ khi ĐỦ Fragment + ĐÚNG race mới ghi:
--        <PlayerName>.txt = Completed-fragment
--
-- Cấu hình ngoài:
--   getgenv().fragmentchange = 8000
--   getgenv().race = "Mink"
--
-- Race hỗ trợ:
--   "Mink", "Angel", "Human", "Shark", "Off"
--
-- Alias game:
--   Angel = Skypiea
--   Shark = Fishman
-- ==========================================

repeat
    task.wait(1)
until game:IsLoaded()
    and game:GetService("Players").LocalPlayer
    and game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui            = game:GetService("CoreGui")

local Player = Players.LocalPlayer

-- ==========================================
-- [ CẤU HÌNH ]
-- ==========================================

getgenv().fragmentchange = getgenv().fragmentchange or 8000
getgenv().race = getgenv().race or "Off"

local TARGET_FRAG = tonumber(getgenv().fragmentchange) or 8000
local RAW_RACE_TARGET = tostring(getgenv().race or "Off")

-- Thời gian tối thiểu giữa 2 lượt reroll.
-- Không nên đặt quá thấp để tránh gọi remote dồn.
local REROLL_INTERVAL = 2.5

-- PlaceId các Sea
local SEA1_PLACE_IDS = {
    [2753915549] = true,
}

local SEA2_PLACE_IDS = {
    [4442272183] = true,
    [79091703265657] = true,
}

local SEA3_PLACE_IDS = {
    [7449423635] = true,
    [100117331123089] = true,
}

-- ==========================================
-- [ CHUẨN HÓA RACE ]
-- ==========================================

local RACE_ALIAS = {
    human   = "Human",

    mink    = "Mink",
    rabbit  = "Mink",

    angel   = "Skypiea",
    skypiea = "Skypiea",

    shark   = "Fishman",
    fishman = "Fishman",
}

local RACE_DISPLAY = {
    Human   = "Human",
    Mink    = "Mink",
    Skypiea = "Angel",
    Fishman = "Shark",
}

local function CleanText(value)
    return tostring(value or "")
        :lower()
        :gsub("^%s+", "")
        :gsub("%s+$", "")
end

local function NormalizeRace(value)
    local cleaned = CleanText(value):gsub("[^%a]", "")
    return RACE_ALIAS[cleaned]
end

local function IsRaceOff(value)
    local cleaned = CleanText(value)

    return cleaned == ""
        or cleaned == "off"
        or cleaned == "none"
        or cleaned == "nil"
        or cleaned == "false"
end

local RACE_OFF = IsRaceOff(RAW_RACE_TARGET)
local TARGET_RACE = RACE_OFF and nil or NormalizeRace(RAW_RACE_TARGET)
local RACE_CONFIG_VALID = RACE_OFF or TARGET_RACE ~= nil

local function DisplayRace(value)
    local normalized = NormalizeRace(value) or value
    return RACE_DISPLAY[normalized] or tostring(normalized or "Unknown")
end

-- ==========================================
-- [ HÀM HỖ TRỢ ]
-- ==========================================

local function GetCommF()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CommF_")
end

local function GetFragments()
    local value = 0

    pcall(function()
        local data = Player:FindFirstChild("Data")
        local fragments = data and data:FindFirstChild("Fragments")

        if fragments then
            value = tonumber(fragments.Value) or 0
        end
    end)

    return value
end

local function GetCurrentRace()
    local rawRace = nil

    pcall(function()
        local data = Player:FindFirstChild("Data")
        local raceValue = data and data:FindFirstChild("Race")

        if raceValue then
            rawRace = tostring(raceValue.Value)
        end
    end)

    return NormalizeRace(rawRace), rawRace
end

local function IsRaceRequirementMet()
    if RACE_OFF then
        return true
    end

    if not RACE_CONFIG_VALID or not TARGET_RACE then
        return false
    end

    local currentRace = GetCurrentRace()
    return currentRace == TARGET_RACE
end

local function GetCurrentSea()
    local placeId = game.PlaceId

    if SEA1_PLACE_IDS[placeId] then
        return 1
    elseif SEA2_PLACE_IDS[placeId] then
        return 2
    elseif SEA3_PLACE_IDS[placeId] then
        return 3
    end

    local mapName = tostring(workspace:GetAttribute("MAP") or "")

    if mapName == "Sea1" then
        return 1
    elseif mapName == "Sea2" then
        return 2
    elseif mapName == "Sea3" then
        return 3
    end

    return 0
end

-- ==========================================
-- [ TẠO UI ]
-- ==========================================

if CoreGui:FindFirstChild("CheckFragUI") then
    CoreGui.CheckFragUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CheckFragUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 370, 0, 165)
MainFrame.Position = UDim2.new(0.5, -185, 0.5, -82)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(0, 255, 255)
Stroke.Parent = MainFrame

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundTransparency = 1
Title.Text = "Theo Dõi Fragment + Race"
Title.TextColor3 = Color3.fromRGB(0, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = MainFrame

local Line = Instance.new("Frame")
Line.Size = UDim2.new(1, 0, 0, 1)
Line.Position = UDim2.new(0, 0, 1, 0)
Line.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
Line.BorderSizePixel = 0
Line.Parent = Title

local SeaLabel = Instance.new("TextLabel")
SeaLabel.Size = UDim2.new(1, -20, 0, 22)
SeaLabel.Position = UDim2.new(0, 10, 0, 36)
SeaLabel.BackgroundTransparency = 1
SeaLabel.Text = "🌊 Sea hiện tại: Đang kiểm tra..."
SeaLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
SeaLabel.Font = Enum.Font.GothamBold
SeaLabel.TextSize = 12
SeaLabel.TextXAlignment = Enum.TextXAlignment.Left
SeaLabel.Parent = MainFrame

local RaceLabel = Instance.new("TextLabel")
RaceLabel.Size = UDim2.new(1, -20, 0, 22)
RaceLabel.Position = UDim2.new(0, 10, 0, 60)
RaceLabel.BackgroundTransparency = 1
RaceLabel.Text = "🧬 Race: Đang kiểm tra..."
RaceLabel.TextColor3 = Color3.fromRGB(255, 210, 100)
RaceLabel.Font = Enum.Font.GothamBold
RaceLabel.TextSize = 12
RaceLabel.TextXAlignment = Enum.TextXAlignment.Left
RaceLabel.Parent = MainFrame

local FragLabel = Instance.new("TextLabel")
FragLabel.Size = UDim2.new(1, -20, 0, 22)
FragLabel.Position = UDim2.new(0, 10, 0, 84)
FragLabel.BackgroundTransparency = 1
FragLabel.Text = "🔮 Fragments: ... / " .. tostring(TARGET_FRAG)
FragLabel.TextColor3 = Color3.fromRGB(200, 160, 255)
FragLabel.Font = Enum.Font.GothamBold
FragLabel.TextSize = 13
FragLabel.TextXAlignment = Enum.TextXAlignment.Left
FragLabel.Parent = MainFrame

local ActionStatus = Instance.new("TextLabel")
ActionStatus.Size = UDim2.new(1, -20, 0, 45)
ActionStatus.Position = UDim2.new(0, 10, 0, 109)
ActionStatus.BackgroundTransparency = 1
ActionStatus.Text = "Trạng thái: Đang khởi tạo..."
ActionStatus.TextColor3 = Color3.fromRGB(200, 200, 200)
ActionStatus.Font = Enum.Font.Gotham
ActionStatus.TextSize = 12
ActionStatus.TextWrapped = true
ActionStatus.TextXAlignment = Enum.TextXAlignment.Left
ActionStatus.TextYAlignment = Enum.TextYAlignment.Top
ActionStatus.Parent = MainFrame

-- ==========================================
-- [ KIỂM TRA VÀ CHUYỂN SEA ]
-- ==========================================

local function EnsureSea3()
    local sea = GetCurrentSea()

    if sea == 3 then
        SeaLabel.Text = "🌊 Sea hiện tại: Sea 3"
        SeaLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
        return true
    end

    local CommF_ = GetCommF()

    if not CommF_ then
        ActionStatus.Text = "Trạng thái: ❌ Không tìm thấy CommF_"
        warn("[CheckFrag] Không tìm thấy remote CommF_")
        return false
    end

    if sea == 1 then
        SeaLabel.Text = "🌊 Sea hiện tại: Sea 1"
        ActionStatus.Text = "Trạng thái: Đang chuyển Sea 1 → Sea 2..."

        for attempt = 1, 3 do
            warn("[CheckFrag] TravelDressrosa lần " .. tostring(attempt) .. "/3")

            pcall(function()
                CommF_:InvokeServer("TravelDressrosa")
            end)

            task.wait(5)

            if GetCurrentSea() ~= 1 then
                return false
            end
        end

        ActionStatus.Text =
            "Trạng thái: ⚠ Không thể sang Sea 2, kiểm tra điều kiện mở Sea"
        return false
    end

    if sea == 2 then
        SeaLabel.Text = "🌊 Sea hiện tại: Sea 2"
        ActionStatus.Text = "Trạng thái: Đang chuyển Sea 2 → Sea 3..."

        for attempt = 1, 3 do
            warn("[CheckFrag] TravelZou lần " .. tostring(attempt) .. "/3")

            pcall(function()
                CommF_:InvokeServer("TravelZou")
            end)

            task.wait(5)

            if GetCurrentSea() ~= 2 then
                return false
            end
        end

        ActionStatus.Text =
            "Trạng thái: ⚠ Không thể sang Sea 3, kiểm tra điều kiện mở Sea"
        return false
    end

    SeaLabel.Text = "🌊 Sea hiện tại: Không xác định"
    SeaLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    ActionStatus.Text =
        "Trạng thái: Không nhận diện được Sea từ PlaceId/MAP"

    return false
end

if not EnsureSea3() then
    warn(
        "[CheckFrag] Chưa ở Sea 3. "
            .. "Sau khi teleport, hãy để loader tự chạy lại script."
    )
    return
end

-- ==========================================
-- [ AUTO REROLL RACE ]
-- ==========================================

local lastRerollAt = 0
local rerollAttempt = 0

local function TryRerollRace()
    if RACE_OFF then
        return true, "race_off"
    end

    if not RACE_CONFIG_VALID or not TARGET_RACE then
        return false, "invalid_target"
    end

    local currentRace, currentRaw = GetCurrentRace()

    -- Đúng target thì tuyệt đối không gọi remote reroll.
    if currentRace == TARGET_RACE then
        return true, "already_match"
    end

    if (tick() - lastRerollAt) < REROLL_INTERVAL then
        return false, "cooldown"
    end

    local CommF_ = GetCommF()

    if not CommF_ then
        return false, "commf_missing"
    end

    lastRerollAt = tick()
    rerollAttempt = rerollAttempt + 1

    RaceLabel.Text =
        "🧬 Race: "
        .. DisplayRace(currentRaw or currentRace)
        .. " → target "
        .. DisplayRace(TARGET_RACE)

    RaceLabel.TextColor3 = Color3.fromRGB(255, 120, 120)

    ActionStatus.Text =
        "Trạng thái: Đang reroll race lần "
        .. tostring(rerollAttempt)
        .. " → "
        .. DisplayRace(TARGET_RACE)

    warn(
        "[CheckFrag][Race] Reroll lần "
            .. tostring(rerollAttempt)
            .. " | current="
            .. tostring(currentRaw or currentRace)
            .. " | target="
            .. DisplayRace(TARGET_RACE)
    )

    local ok1, result1 = pcall(function()
        return CommF_:InvokeServer(
            "BlackbeardReward",
            "Reroll",
            "1"
        )
    end)

    task.wait(0.35)

    if IsRaceRequirementMet() then
        return true, "matched_after_step_1"
    end

    local ok2, result2 = pcall(function()
        return CommF_:InvokeServer(
            "BlackbeardReward",
            "Reroll",
            "2"
        )
    end)

    task.wait(1.5)

    if IsRaceRequirementMet() then
        return true, "matched_after_step_2"
    end

    if not ok1 and not ok2 then
        warn(
            "[CheckFrag][Race] Remote reroll lỗi: "
                .. tostring(result1)
                .. " | "
                .. tostring(result2)
        )
        return false, "remote_error"
    end

    return false, "not_match_yet"
end

-- ==========================================
-- [ GHI FILE KHI ĐỦ CẢ HAI ĐIỀU KIỆN ]
-- ==========================================

local completed = false

local function WriteCompletedFile()
    if completed then
        return true
    end

    local success, err = pcall(function()
        if type(writefile) ~= "function" then
            error("Executor không hỗ trợ writefile")
        end

        writefile(
            tostring(Player.Name) .. ".txt",
            "Completed-fragment"
        )
    end)

    if success then
        completed = true

        warn(
            "[CheckFrag] Đã ghi "
                .. tostring(Player.Name)
                .. ".txt = Completed-fragment"
        )

        return true
    end

    warn(
        "[CheckFrag] Lỗi khi tạo file: "
            .. tostring(err)
    )

    return false, err
end

-- ==========================================
-- [ VÒNG KIỂM TRA CHÍNH ]
-- ==========================================

task.spawn(function()
    while not completed do
        task.wait(1)

        local currentFrag = GetFragments()
        local currentRace, currentRaw = GetCurrentRace()

        local fragmentReady = currentFrag >= TARGET_FRAG
        local raceReady = IsRaceRequirementMet()

        FragLabel.Text =
            "🔮 Fragments: "
            .. tostring(currentFrag)
            .. " / "
            .. tostring(TARGET_FRAG)

        if fragmentReady then
            FragLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        else
            FragLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        end

        if not RACE_CONFIG_VALID then
            RaceLabel.Text =
                "🧬 Race target không hợp lệ: "
                .. tostring(RAW_RACE_TARGET)

            RaceLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
            ActionStatus.Text =
                'Trạng thái: ❌ getgenv().race chỉ nhận '
                .. '"Mink", "Angel", "Human", "Shark", "Off"'

            task.wait(3)

        elseif RACE_OFF then
            RaceLabel.Text =
                "🧬 Race: OFF (bỏ qua điều kiện race)"

            RaceLabel.TextColor3 = Color3.fromRGB(170, 170, 170)

            if fragmentReady then
                ActionStatus.Text =
                    "Trạng thái: Đủ Fragment, đang ghi file..."

                local ok = WriteCompletedFile()

                if ok then
                    ActionStatus.Text =
                        "Trạng thái: ✅ HOÀN THÀNH (Race OFF)"
                else
                    ActionStatus.Text =
                        "Trạng thái: ❌ Lỗi ghi file!"
                end
            else
                ActionStatus.Text =
                    "Trạng thái: Race OFF, đang đợi đủ Fragment..."
            end

        elseif not raceReady then
            RaceLabel.Text =
                "🧬 Race: "
                .. DisplayRace(currentRaw or currentRace)
                .. " / Target: "
                .. DisplayRace(TARGET_RACE)

            RaceLabel.TextColor3 = Color3.fromRGB(255, 100, 100)

            local _, reason = TryRerollRace()

            if reason == "not_match_yet" then
                ActionStatus.Text =
                    "Trạng thái: Chưa đúng race, tiếp tục reroll..."
            elseif reason == "remote_error" then
                ActionStatus.Text =
                    "Trạng thái: ⚠ Remote reroll lỗi, đang thử lại..."
            elseif reason == "commf_missing" then
                ActionStatus.Text =
                    "Trạng thái: ❌ Không tìm thấy CommF_"
            end

        else
            RaceLabel.Text =
                "🧬 Race: "
                .. DisplayRace(currentRaw or currentRace)
                .. " ✅"

            RaceLabel.TextColor3 = Color3.fromRGB(0, 255, 120)

            -- Chỉ ghi file khi ĐỦ CẢ Fragment và race.
            if fragmentReady and raceReady then
                ActionStatus.Text =
                    "Trạng thái: Đủ Fragment + đúng Race, đang ghi file..."

                local ok = WriteCompletedFile()

                if ok then
                    ActionStatus.Text =
                        "Trạng thái: ✅ HOÀN THÀNH (Đủ Fragment + đúng Race)"
                else
                    ActionStatus.Text =
                        "Trạng thái: ❌ Lỗi ghi file!"
                end
            else
                ActionStatus.Text =
                    "Trạng thái: Race đã đúng, đang đợi farm đủ Fragment..."
            end
        end
    end
end)
