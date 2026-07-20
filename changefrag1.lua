-- ==========================================
-- [ FRAGMENT CHECKER + AUTO SEA 3 ]
-- Chức năng:
--   1. Đợi game load
--   2. Kiểm tra Sea hiện tại
--   3. Sea 1 -> Sea 2 -> Sea 3
--   4. Chỉ kiểm Fragment khi đã ở Sea 3
--   5. Đủ Fragment -> ghi Completed-fragment
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

-- Fragment yêu cầu
getgenv().fragmentchange = getgenv().fragmentchange or 8000
local TARGET_FRAG = tonumber(getgenv().fragmentchange) or 8000

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

local function GetCurrentSea()
    local placeId = game.PlaceId

    if SEA1_PLACE_IDS[placeId] then
        return 1
    elseif SEA2_PLACE_IDS[placeId] then
        return 2
    elseif SEA3_PLACE_IDS[placeId] then
        return 3
    end

    -- Kiểm tra thêm bằng thuộc tính MAP nếu PlaceId mới
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
MainFrame.Size = UDim2.new(0, 340, 0, 135)
MainFrame.Position = UDim2.new(0.5, -170, 0.5, -67)
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
Title.Text = "Theo Dõi Fragment"
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
SeaLabel.Position = UDim2.new(0, 10, 0, 38)
SeaLabel.BackgroundTransparency = 1
SeaLabel.Text = "🌊 Sea hiện tại: Đang kiểm tra..."
SeaLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
SeaLabel.Font = Enum.Font.GothamBold
SeaLabel.TextSize = 12
SeaLabel.TextXAlignment = Enum.TextXAlignment.Left
SeaLabel.Parent = MainFrame

local ActionStatus = Instance.new("TextLabel")
ActionStatus.Size = UDim2.new(1, -20, 0, 22)
ActionStatus.Position = UDim2.new(0, 10, 0, 63)
ActionStatus.BackgroundTransparency = 1
ActionStatus.Text = "Trạng thái: Đang khởi tạo..."
ActionStatus.TextColor3 = Color3.fromRGB(200, 200, 200)
ActionStatus.Font = Enum.Font.Gotham
ActionStatus.TextSize = 12
ActionStatus.TextXAlignment = Enum.TextXAlignment.Left
ActionStatus.Parent = MainFrame

local FragLabel = Instance.new("TextLabel")
FragLabel.Size = UDim2.new(1, -20, 0, 22)
FragLabel.Position = UDim2.new(0, 10, 0, 88)
FragLabel.BackgroundTransparency = 1
FragLabel.Text = "🔮 Fragments: ... / " .. tostring(TARGET_FRAG)
FragLabel.TextColor3 = Color3.fromRGB(200, 160, 255)
FragLabel.Font = Enum.Font.GothamBold
FragLabel.TextSize = 13
FragLabel.TextXAlignment = Enum.TextXAlignment.Left
FragLabel.Parent = MainFrame

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
            warn(
                "[CheckFrag] TravelDressrosa lần "
                    .. tostring(attempt)
                    .. "/3"
            )

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
            warn(
                "[CheckFrag] TravelZou lần "
                    .. tostring(attempt)
                    .. "/3"
            )

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

-- Chỉ chạy Fragment Checker khi đã ở Sea 3.
-- Khi đang teleport, script hiện tại sẽ dừng.
-- Executor/loader cần tự chạy lại script sau teleport.
if not EnsureSea3() then
    warn(
        "[CheckFrag] Chưa ở Sea 3. "
            .. "Sau khi teleport, hãy để loader tự chạy lại script."
    )
    return
end

-- ==========================================
-- [ CHECK FRAGMENT VÀ GHI FILE ]
-- ==========================================

task.spawn(function()
    while task.wait(3) do
        local currentFrag = GetFragments()

        FragLabel.Text =
            "🔮 Fragments: "
            .. tostring(currentFrag)
            .. " / "
            .. tostring(TARGET_FRAG)

        if currentFrag >= TARGET_FRAG then
            FragLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
            ActionStatus.Text = "Trạng thái: Đang ghi file..."

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
                ActionStatus.Text =
                    "Trạng thái: ✅ HOÀN THÀNH (Đã ghi file)"

                warn(
                    "[CheckFrag] Đã ghi "
                        .. tostring(Player.Name)
                        .. ".txt = Completed-fragment"
                )
            else
                ActionStatus.Text = "Trạng thái: ❌ Lỗi ghi file!"

                warn(
                    "[CheckFrag] Lỗi khi tạo file: "
                        .. tostring(err)
                )
            end

            break
        end

        FragLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        ActionStatus.Text =
            "Trạng thái: Đang đợi farm đủ Fragment..."
    end
end)
