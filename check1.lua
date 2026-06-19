-- ============================================================
-- checktemple.lua — DIAGNOSTIC + UI
-- Mục đích: sau khi NHÂN VẬT load xong mới gọi remote temple-door,
-- in kết quả RA MÀN HÌNH (GUI) + console để biết vì sao bot kẹt "Đang khởi động".
-- Cách dùng: chạy file này trong executor trên 1 account đang kẹt,
-- panel sẽ hiện góc trên-trái; chụp/copy gửi lại.
-- ============================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

-- ============================================================
-- 0) DỰNG UI (panel kéo được, có log cuộn)
-- ============================================================
local function makeUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "TempleCheckUI"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    -- parent an toàn cho mọi executor
    local ok = pcall(function()
        if gethui then sg.Parent = gethui()
        elseif syn and syn.protect_gui then syn.protect_gui(sg); sg.Parent = game:GetService("CoreGui")
        else sg.Parent = game:GetService("CoreGui") end
    end)
    if not ok then sg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

    local root = Instance.new("Frame")
    root.Size = UDim2.new(0, 430, 0, 360)
    root.Position = UDim2.new(0, 24, 0, 24)
    root.BackgroundColor3 = Color3.fromRGB(18, 21, 32)
    root.BorderSizePixel = 0
    root.Active = true
    root.Parent = sg
    Instance.new("UICorner", root).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", root)
    stroke.Color = Color3.fromRGB(46, 167, 255); stroke.Thickness = 1.5; stroke.Transparency = 0.2

    -- title bar
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 40)
    bar.BackgroundColor3 = Color3.fromRGB(27, 34, 51)
    bar.BorderSizePixel = 0
    bar.Parent = root
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 12)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 14, 0, 0)
    title.Size = UDim2.new(1, -56, 1, 0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextColor3 = Color3.fromRGB(46, 167, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "⚔️ TEMPLE CHECK — Diagnostic"
    title.Parent = bar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -34, 0, 6)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 93, 108)
    closeBtn.Text = "✕"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Parent = bar
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
    closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

    -- log scroller
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -52)
    scroll.Position = UDim2.new(0, 8, 0, 46)
    scroll.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 5
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = root
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
    local pad = Instance.new("UIPadding", scroll)
    pad.PaddingTop = UDim.new(0, 6); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
    local list = Instance.new("UIListLayout", scroll)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 3)

    -- kéo thả panel bằng title bar
    local dragging, dragStart, startPos
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = root.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    local order = 0
    local function addRow(text, color)
        order = order + 1
        local lb = Instance.new("TextLabel")
        lb.LayoutOrder = order
        lb.BackgroundTransparency = 1
        lb.Size = UDim2.new(1, 0, 0, 0)
        lb.AutomaticSize = Enum.AutomaticSize.Y
        lb.Font = Enum.Font.Code
        lb.TextSize = 13
        lb.TextWrapped = true
        lb.TextXAlignment = Enum.TextXAlignment.Left
        lb.TextYAlignment = Enum.TextYAlignment.Top
        lb.TextColor3 = color or Color3.fromRGB(232, 235, 242)
        lb.Text = text
        lb.Parent = scroll
    end
    return addRow
end

local addRow = makeUI()

-- ---- log: in ra console + UI (màu theo loại) ----
local C_OK = Color3.fromRGB(34, 211, 154)
local C_ERR = Color3.fromRGB(255, 93, 108)
local C_HEAD = Color3.fromRGB(245, 176, 66)
local C_INFO = Color3.fromRGB(170, 180, 200)
local function L(text, color)
    local line = "[CHECKTEMPLE] " .. text
    print(line); warn(line)
    pcall(addRow, text, color)
end

-- ============================================================
-- 1) ĐỢI NHÂN VẬT LOAD XONG (load xong mới check)
-- ============================================================
local function waitCharacterReady(timeout)
    local t0 = tick()
    local LP = Players.LocalPlayer
    repeat
        local char = LP and LP.Character
        local okc = char
            and char:FindFirstChild("HumanoidRootPart")
            and char:FindFirstChildOfClass("Humanoid")
            and char:FindFirstChildOfClass("Humanoid").Health > 0
        local stillLoading = LP and LP:FindFirstChild("PlayerGui")
            and LP.PlayerGui:FindFirstChild("LoadingScreen")
        if okc and not stillLoading then return true end
        task.wait(0.2)
    until (tick() - t0) > (timeout or 60)
    return false
end

L("Đang đợi nhân vật load xong...", C_INFO)
local ready = waitCharacterReady(60)
L("Nhân vật ready = " .. tostring(ready), ready and C_OK or C_ERR)
task.wait(1)

-- ============================================================
-- 2) GỌI REMOTE: thử nhiều biến thể tên
-- ============================================================
local CommF = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("CommF_")
L("Remotes.CommF_ tồn tại = " .. tostring(CommF ~= nil), CommF and C_OK or C_ERR)

local function tryInvoke(arg)
    if not CommF then return end
    local ok, res = pcall(function() return CommF:InvokeServer(arg) end)
    if ok then
        L(("%s => type=%s | value=%s"):format(arg, typeof(res), tostring(res)),
            (res ~= nil) and C_OK or C_INFO)
        if typeof(res) == "table" then
            for k, v in pairs(res) do
                L(("    .%s = %s (%s)"):format(tostring(k), tostring(v), typeof(v)), C_INFO)
            end
        end
    else
        L(("%s => LỖI: %s"):format(arg, tostring(res)), C_ERR)
    end
end

L("===== KẾT QUẢ REMOTE =====", C_HEAD)
tryInvoke("CheckTempleDoor")
tryInvoke("templedoorcheck")
tryInvoke("TempleDoorCheck")
tryInvoke("CheckTempleDoorStatus")

-- ============================================================
-- 3) DÒ mọi remote có chữ "temple" (lộ tên đúng nếu game đã đổi)
-- ============================================================
L("===== DÒ remote chứa 'temple' =====", C_HEAD)
local remotesFolder = RS:FindFirstChild("Remotes")
local found = 0
if remotesFolder then
    for _, inst in ipairs(remotesFolder:GetDescendants()) do
        if string.find(string.lower(inst.Name), "temple") then
            found = found + 1
            L(("  %s : %s"):format(inst.ClassName, inst.Name), C_OK)
        end
    end
    if found == 0 then L("  (không có remote nào chứa 'temple')", C_INFO) end
else
    L("  Không thấy ReplicatedStorage.Remotes", C_ERR)
end

-- ============================================================
-- 4) Thông tin phụ
-- ============================================================
L("===== THÔNG TIN PHỤ =====", C_HEAD)
local LP = Players.LocalPlayer
local hrp = LP and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
if hrp then
    L(("Vị trí: %d, %d, %d"):format(hrp.Position.X, hrp.Position.Y, hrp.Position.Z), C_INFO)
end
local templeInMap = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Temple of Time") ~= nil
L("Temple of Time trong workspace.Map = " .. tostring(templeInMap), C_INFO)

L("===== XONG — chụp panel này gửi lại =====", C_HEAD)
