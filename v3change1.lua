--[[
    RaceV3Change.lua  -  UI nho: check Race hien tai + dang o V may (V1/V2/V3)
    ----------------------------------------------------------------------
    Detect lay tu UpgradeRace.lua (theo remote CommF_):
      V2 xong = CommF("Alchemist","3")   == -2
      V3 xong = CommF("Wenlocktoad","3")  == -2
      => khong cai nao = V1, V2 xong = V2, V3 xong = V3

    Neu race hien tai DA len V3 -> tao file "<PlayerName>.txt" ghi "Completed-v3"
    ----------------------------------------------------------------------
]]

--==================  SERVICES  ==================--
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer       = Players.LocalPlayer

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

-- Ten toc hien tai (Human / Mink / Fishman / Skypiea / Cyborg / Ghoul...)
local function raceName()
    local d = LocalPlayer:FindFirstChild("Data")
    return d and d:FindFirstChild("Race") and tostring(d.Race.Value) or "?"
end

--==================  DETECT V (V1 / V2 / V3)  ==================--
local function isV2Done() return CommF("Alchemist", "3")  == -2 end
local function isV3Done() return CommF("Wenlocktoad", "3") == -2 end

-- Tra ve 3 / 2 / 1
local function currentV()
    if isV3Done() then return 3 end
    if isV2Done() then return 2 end
    return 1
end

--==================  GHI FILE KHI DA LEN V3  ==================--
local _savedV3 = false
local function saveV3File()
    if _savedV3 then return end
    if type(writefile) ~= "function" then return end   -- executor khong ho tro writefile
    local fileName = tostring(LocalPlayer.Name) .. ".txt"
    local ok = pcall(function() writefile(fileName, "Completed-v4") end)
    if ok then
        _savedV3 = true
        _G.RaceV3FileSaved = fileName
        print("[RaceV3Change] Da ghi file: " .. fileName .. " (Completed-v4)")
    end
end

--==================  UI NHO  ==================--
local function MakeUI()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    local old = parent:FindFirstChild("RaceV3ChangeUI"); if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "RaceV3ChangeUI"; gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 220, 0, 86)
    main.Position = UDim2.new(0, 18, 0, 380)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    main.BorderSizePixel = 0; main.Active = true; main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(70, 90, 160); stroke.Thickness = 1

    -- title bar (keo tha)
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 26); bar.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
    bar.BorderSizePixel = 0; bar.Parent = main
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -10, 1, 0)
    title.Position = UDim2.new(0, 8, 0, 0); title.Font = Enum.Font.GothamBold
    title.TextSize = 12; title.TextColor3 = Color3.fromRGB(235, 235, 245)
    title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "Race Check  •  V3"
    title.Parent = bar

    -- body
    local body = Instance.new("Frame")
    body.BackgroundTransparency = 1; body.Position = UDim2.new(0, 10, 0, 30)
    body.Size = UDim2.new(1, -20, 1, -36); body.Parent = main
    local layout = Instance.new("UIListLayout", body)
    layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Padding = UDim.new(0, 3)

    local function row(color, bold, order, size)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1; l.Size = UDim2.new(1, 0, 0, size or 16)
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        l.TextSize = 13; l.TextColor3 = color or Color3.fromRGB(210, 210, 220)
        l.TextXAlignment = Enum.TextXAlignment.Left; l.TextYAlignment = Enum.TextYAlignment.Top
        l.TextWrapped = true; l.LayoutOrder = order; l.Text = ""; l.Parent = body
        return l
    end

    local lRace = row(Color3.fromRGB(180, 200, 255), true, 1, 18)
    local lVer  = row(Color3.fromRGB(255, 220, 150), true, 2, 18)
    local lFile = row(Color3.fromRGB(120, 220, 140), false, 3, 14)

    -- keo tha bang title bar
    local UIS = game:GetService("UserInputService")
    local dragging, dragStart, startPos
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = main.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    -- vong cap nhat + ghi file khi V3
    task.spawn(function()
        local V_COLOR = {
            [1] = Color3.fromRGB(200, 200, 210),
            [2] = Color3.fromRGB(255, 220, 150),
            [3] = Color3.fromRGB(120, 220, 140),
        }
        while gui.Parent do
            local r = raceName()
            local v = currentV()

            lRace.Text = "Race: " .. r
            lVer.Text  = "Version: V" .. v
            lVer.TextColor3 = V_COLOR[v] or Color3.fromRGB(210, 210, 220)

            if v >= 3 then
                saveV3File()
                lFile.Text = _savedV3
                    and ("Saved: " .. tostring(_G.RaceV3FileSaved))
                    or  "V3 (writefile khong ho tro)"
            else
                lFile.Text = ""
            end

            task.wait(1)
        end
    end)
end

pcall(MakeUI)
