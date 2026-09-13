--[[
TEMPLE NPC CLICK DEBUG
- Script chỉ đưa bạn tới vị trí NPC Race V4.
- Sau đó BẠN tự click/nói chuyện NPC.
- Script KHÔNG tự gọi requestEntrance / RaceV4Progress.
- Nó chỉ TRACE các remote do game/client gọi và theo dõi HRP teleport.

Log:
  Console F9
  TEMPLE_NPC_DEBUG_LOG.txt (nếu executor có writefile)
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes", 20)
local CommF = Remotes and Remotes:WaitForChild("CommF_", 20)

if not LP or not CommF then
    warn("[TEMPLE NPC DEBUG] Missing player/CommF_")
    return
end

-- Banana Pull Lever / Race V4 NPC area.
local NPC_POS = Vector3.new(
    2959.87231,
    2282.42139,
    -7216.23193
)

-- Temple arrival position used by Banana V4 flow.
local TEMPLE_POS = Vector3.new(
    28286.35546875,
    14896.5078125,
    102.62469482421875
)

local LOG_FILE = "TEMPLE_NPC_DEBUG_LOG.txt"

local function getRoot()
    local c = LP.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if c and h and r and h.Health > 0 then
        return c, h, r
    end
end

local function waitRoot(timeout)
    local limit = os.clock() + (timeout or 15)
    repeat
        local c,h,r = getRoot()
        if r then return c,h,r end
        task.wait(0.1)
    until os.clock() >= limit
end

local function fmt(v)
    local t = typeof(v)
    if t == "Vector3" then
        return string.format(
            "Vector3(%.3f, %.3f, %.3f)",
            v.X, v.Y, v.Z
        )
    elseif t == "CFrame" then
        local p = v.Position
        return string.format(
            "CFrame(%.3f, %.3f, %.3f)",
            p.X, p.Y, p.Z
        )
    elseif t == "Instance" then
        return v:GetFullName()
    end
    return tostring(v)
end

local logs = {}
local Status

local function flush()
    if writefile then
        pcall(function()
            writefile(LOG_FILE, table.concat(logs, "\n"))
        end)
    end
end

local function log(s)
    local line = string.format("[%.3f] %s", os.clock(), tostring(s))
    logs[#logs + 1] = line
    print("[TEMPLE NPC DEBUG] " .. tostring(s))
    if Status then
        Status.Text = tostring(s)
    end
    flush()
end

local function argsToText(args)
    local out = {}
    for i = 1, #args do
        out[#out + 1] = tostring(i) .. "=" .. fmt(args[i])
    end
    return table.concat(out, " | ")
end

-- Find nearest likely NPC/model around Banana's NPC coordinate.
local function objPos(obj)
    if obj:IsA("BasePart") then
        return obj.Position
    elseif obj:IsA("Model") then
        local p = obj.PrimaryPart
            or obj:FindFirstChild("HumanoidRootPart")
            or obj:FindFirstChild("Head")
        return p and p.Position
    end
end

local function nearestNpcObject()
    local best, bestD
    bestD = math.huge

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local p = objPos(obj)
            if p then
                local d = (p - NPC_POS).Magnitude
                if d < bestD then
                    bestD = d
                    best = obj
                end
            end
        end
    end

    return best, bestD
end

-- ============================================================
-- REMOTE TRACE
-- ============================================================
local hookOn = false
local oldNamecall

local function installTrace()
    if hookOn then
        return true
    end

    if not hookmetamethod
        or not getnamecallmethod
        or not newcclosure
    then
        log("Executor thiếu hookmetamethod/getnamecallmethod/newcclosure")
        return false
    end

    local ok, err = pcall(function()
        oldNamecall = hookmetamethod(
            game,
            "__namecall",
            newcclosure(function(self, ...)
                local method = getnamecallmethod()
                local args = {...}

                if method == "InvokeServer"
                    or method == "FireServer"
                then
                    local interesting = (self == CommF)

                    if not interesting then
                        for _, a in ipairs(args) do
                            local s = tostring(a):lower()
                            if s:find("racev4")
                                or s:find("requestentrance")
                                or s:find("temple")
                                or s:find("teleport")
                            then
                                interesting = true
                                break
                            end
                        end
                    end

                    if interesting
                        and typeof(self) == "Instance"
                    then
                        local copied = table.clone(args)
                        task.defer(function()
                            log(
                                method
                                .. " | "
                                .. self:GetFullName()
                                .. " | "
                                .. argsToText(copied)
                            )
                        end)
                    end
                end

                return oldNamecall(self, ...)
            end)
        )
    end)

    if not ok then
        log("Hook error: " .. tostring(err))
        return false
    end

    hookOn = true
    log("TRACE ON - bây giờ hãy click/nói chuyện NPC.")
    return true
end

-- ============================================================
-- POSITION / TELEPORT MONITOR
-- ============================================================
local monitorOn = false

local function startMonitor()
    if monitorOn then return end
    monitorOn = true

    task.spawn(function()
        local lastPos
        local wasInTemple = false

        while monitorOn do
            task.wait(0.05)

            local _,_,root = getRoot()
            if root then
                local pos = root.Position
                local templeDist = (pos - TEMPLE_POS).Magnitude

                if lastPos then
                    local jump = (pos - lastPos).Magnitude
                    if jump >= 250 then
                        log(
                            "HRP JUMP "
                            .. string.format("%.1f", jump)
                            .. " studs | FROM "
                            .. fmt(lastPos)
                            .. " -> TO "
                            .. fmt(pos)
                            .. " | TempleDist="
                            .. string.format("%.1f", templeDist)
                        )
                    end
                end

                local nowInTemple = templeDist <= 100
                if nowInTemple and not wasInTemple then
                    log(
                        "ARRIVED TEMPLE | HRP="
                        .. fmt(pos)
                        .. " | dist="
                        .. string.format("%.1f", templeDist)
                    )
                end

                wasInTemple = nowInTemple
                lastPos = pos
            end
        end
    end)
end

-- ============================================================
-- UI
-- ============================================================
local parent = CoreGui
pcall(function()
    if gethui then parent = gethui() end
end)

local old = parent:FindFirstChild("TempleNpcClickDebug")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "TempleNpcClickDebug"
gui.ResetOnSpawn = false
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(480, 240)
frame.Position = UDim2.new(0.5, -240, 0.5, -120)
frame.BackgroundColor3 = Color3.fromRGB(20,23,31)
frame.BorderSizePixel = 0
frame.Active = true
frame.ClipsDescendants = false
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = frame

-- ============================================================
-- WINDOW DRAG + RESIZE
-- ============================================================
local MIN_W, MIN_H = 360, 210
local MAX_W, MAX_H = 900, 650

local dragging = false
local resizing = false
local dragStart
local startPos
local resizeStart
local startSize

local function clampWindowToScreen()
    local cam = workspace.CurrentCamera
    if not cam then return end

    local vp = cam.ViewportSize
    local absPos = frame.AbsolutePosition
    local absSize = frame.AbsoluteSize

    local x = math.clamp(absPos.X, 0, math.max(0, vp.X - absSize.X))
    local y = math.clamp(absPos.Y, 0, math.max(0, vp.Y - absSize.Y))

    frame.Position = UDim2.fromOffset(x, y)
end

local resizeHandle = Instance.new("TextButton")
resizeHandle.Name = "ResizeHandle"
resizeHandle.Size = UDim2.fromOffset(22, 22)
resizeHandle.AnchorPoint = Vector2.new(1, 1)
resizeHandle.Position = UDim2.new(1, -4, 1, -4)
resizeHandle.BackgroundColor3 = Color3.fromRGB(65, 75, 100)
resizeHandle.BorderSizePixel = 0
resizeHandle.Text = "↘"
resizeHandle.TextColor3 = Color3.fromRGB(235, 240, 255)
resizeHandle.TextSize = 14
resizeHandle.Font = Enum.Font.GothamBold
resizeHandle.AutoButtonColor = true
resizeHandle.ZIndex = 20
resizeHandle.Parent = frame

local resizeCorner = Instance.new("UICorner")
resizeCorner.CornerRadius = UDim.new(0, 5)
resizeCorner.Parent = resizeHandle

local function beginDrag(input)
    dragging = true
    dragStart = input.Position
    startPos = frame.Position
end

local function beginResize(input)
    resizing = true
    resizeStart = input.Position
    startSize = frame.AbsoluteSize
end

resizeHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        beginResize(input)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging
        and (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        )
    then
        local delta = input.Position - dragStart

        frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )

    elseif resizing
        and (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        )
    then
        local delta = input.Position - resizeStart
        local newW = math.clamp(startSize.X + delta.X, MIN_W, MAX_W)
        local newH = math.clamp(startSize.Y + delta.Y, MIN_H, MAX_H)

        frame.Size = UDim2.fromOffset(newW, newH)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        if dragging then
            dragging = false
            clampWindowToScreen()
        end

        if resizing then
            resizing = false
            clampWindowToScreen()
        end
    end
end)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12,8)
title.Size = UDim2.new(1,-24,0,28)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.new(1,1,1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "TEMPLE NPC CLICK DEBUG  |  kéo tiêu đề để di chuyển"
title.Active = true
title.Parent = frame

title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        beginDrag(input)
    end
end)

Status = Instance.new("TextLabel")
Status.Position = UDim2.fromOffset(12,44)
Status.Size = UDim2.new(1,-24,1,-132)
Status.BackgroundColor3 = Color3.fromRGB(13,16,23)
Status.BorderSizePixel = 0
Status.Font = Enum.Font.Code
Status.TextSize = 12
Status.TextWrapped = true
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Top
Status.TextColor3 = Color3.fromRGB(220,225,235)
Status.Text = "Loading trace...\nKéo tiêu đề để di chuyển | kéo ↘ để thu/phóng"
Status.Parent = frame

local function button(text, x, w)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w,52)
    b.AnchorPoint = Vector2.new(0, 1)
    b.Position = UDim2.new(0, x, 1, -18)
    b.BackgroundColor3 = Color3.fromRGB(42,48,65)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = Color3.new(1,1,1)
    b.Text = text
    b.Parent = frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,7)
    c.Parent = b
    return b
end

local goNpc = button("GO TO NPC\n(no remote)", 12, 145)
local inspectNpc = button("SHOW NEAREST NPC", 167, 145)
local clearLog = button("CLEAR LOG", 322, 145)


local function relayoutButtons()
    local totalW = frame.AbsoluteSize.X
    local gap = 10
    local margin = 12
    local usable = math.max(300, totalW - margin * 2 - gap * 2)
    local w = math.floor(usable / 3)

    goNpc.Size = UDim2.fromOffset(w, 52)
    inspectNpc.Size = UDim2.fromOffset(w, 52)
    clearLog.Size = UDim2.fromOffset(w, 52)

    goNpc.Position = UDim2.new(0, margin, 1, -18)
    inspectNpc.Position = UDim2.new(0, margin + w + gap, 1, -18)
    clearLog.Position = UDim2.new(0, margin + (w + gap) * 2, 1, -18)
end

frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutButtons)
task.defer(relayoutButtons)

goNpc.MouseButton1Click:Connect(function()
    installTrace()
    startMonitor()

    local _,_,root = waitRoot(10)
    if not root then
        log("HRP not ready")
        return
    end

    local before = (root.Position - NPC_POS).Magnitude

    -- ONLY movement to NPC. No InvokeServer here.
    root.CFrame = CFrame.new(
        NPC_POS + Vector3.new(0,3,0)
    )

    task.wait(0.2)

    local after = (root.Position - NPC_POS).Magnitude
    local obj, d = nearestNpcObject()

    log(
        "AT NPC | before="
        .. string.format("%.1f", before)
        .. " after="
        .. string.format("%.1f", after)
        .. " | nearest="
        .. (obj and obj:GetFullName() or "nil")
        .. " d="
        .. string.format("%.1f", d or math.huge)
        .. " | BÂY GIỜ TỰ CLICK NPC"
    )
end)

inspectNpc.MouseButton1Click:Connect(function()
    local obj, d = nearestNpcObject()
    log(
        "NEAREST NPC OBJECT = "
        .. (obj and obj:GetFullName() or "nil")
        .. " | dist="
        .. string.format("%.1f", d or math.huge)
    )
end)

clearLog.MouseButton1Click:Connect(function()
    logs = {}
    flush()
    log("Log cleared")
end)

installTrace()
startMonitor()

task.spawn(function()
    local _,_,root = waitRoot(15)
    if root then
        local npcD = (root.Position - NPC_POS).Magnitude
        local templeD = (root.Position - TEMPLE_POS).Magnitude
        log(
            "READY | NPCDist="
            .. string.format("%.1f", npcD)
            .. " | TempleDist="
            .. string.format("%.1f", templeD)
            .. " | TRACE ON"
        )
    else
        log("Character timeout")
    end
end)
