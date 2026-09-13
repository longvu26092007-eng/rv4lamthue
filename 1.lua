--[[
    RACE V4 TEMPLE - STANDALONE TEST
    =================================
    Bản tách riêng để test flow vào Temple trước khi ghép vào Kaitun V4.

    Runtime đã xác nhận khi bấm:
        Mysterious Force -> Use it

    game gọi:
        CommF_:InvokeServer("RaceV4Progress", "Teleport")

    Flow test:
      CHECK
        -> state 1: Check + Begin
        -> state 2: tới NPC area + Teleport
        -> state 3: Check + Continue
        -> state 4: progression ready
      Sau Teleport:
        -> chờ HRP tới Temple <= 100 studs
        -> log SUCCESS / NO MOVE

    Không có Auto Trial / AbilitySync / Kaitun FSM / Tween proxy / HTTP.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
if not LP then
    warn("[RACE V4 TEST] LocalPlayer missing")
    return
end

local Remotes =
    ReplicatedStorage:FindFirstChild("Remotes")
    or ReplicatedStorage:WaitForChild("Remotes", 20)

local CommF =
    Remotes
    and (
        Remotes:FindFirstChild("CommF_")
        or Remotes:WaitForChild("CommF_", 20)
    )

if not CommF then
    warn("[RACE V4 TEST] CommF_ missing")
    return
end

local NPC_POS = Vector3.new(
    2959.87231,
    2282.42139,
    -7216.23193
)

local TEMPLE_POS = Vector3.new(
    28286.35546875,
    14896.5078125,
    102.62469482421875
)

local TEMPLE_CONFIRM_DISTANCE = 100
local OBSERVE_TIMEOUT = 8
local RETRY_COOLDOWN = 4

local function getCharacter()
    local char = LP.Character
    local hum =
        char
        and char:FindFirstChildOfClass("Humanoid")
    local root =
        char
        and char:FindFirstChild("HumanoidRootPart")

    if char and hum and root and hum.Health > 0 then
        return char, hum, root
    end
end

local function waitCharacter(timeout)
    local deadline =
        os.clock()
        + (timeout or 15)

    repeat
        local c,h,r = getCharacter()
        if r then
            return c,h,r
        end
        task.wait(0.1)
    until os.clock() >= deadline
end

local function distanceTo(pos)
    local _,_,root = getCharacter()
    if not root then
        return math.huge
    end
    return (root.Position - pos).Magnitude
end

local logs = {}
local LogLabel
local Scroll

local function addLog(tag, msg)
    local line =
        string.format(
            "[%.3f][%s] %s",
            os.clock(),
            tostring(tag),
            tostring(msg)
        )

    logs[#logs + 1] = line

    if #logs > 300 then
        table.remove(logs, 1)
    end

    print("[RACE V4 TEST] " .. line)

    if LogLabel then
        LogLabel.Text = table.concat(logs, "\n")

        task.defer(function()
            if Scroll then
                Scroll.CanvasPosition =
                    Vector2.new(
                        0,
                        math.max(
                            0,
                            Scroll.AbsoluteCanvasSize.Y
                                - Scroll.AbsoluteWindowSize.Y
                        )
                    )
            end
        end)
    end
end

local function raceCheck()
    local t0 = os.clock()

    local ok, result =
        pcall(function()
            return CommF:InvokeServer(
                "RaceV4Progress",
                "Check"
            )
        end)

    addLog(
        "CHECK",
        "ok="
        .. tostring(ok)
        .. " | result="
        .. tostring(result)
        .. " | dt="
        .. string.format("%.3fs", os.clock() - t0)
    )

    if not ok then
        return nil, result
    end

    return result
end

local function raceBegin()
    local t0 = os.clock()

    local ok, result =
        pcall(function()
            return CommF:InvokeServer(
                "RaceV4Progress",
                "Begin"
            )
        end)

    addLog(
        "BEGIN",
        "ok="
        .. tostring(ok)
        .. " | result="
        .. tostring(result)
        .. " | dt="
        .. string.format("%.3fs", os.clock() - t0)
    )

    return ok, result
end

local function raceContinue()
    local t0 = os.clock()

    local ok, result =
        pcall(function()
            return CommF:InvokeServer(
                "RaceV4Progress",
                "Continue"
            )
        end)

    addLog(
        "CONTINUE",
        "ok="
        .. tostring(ok)
        .. " | result="
        .. tostring(result)
        .. " | dt="
        .. string.format("%.3fs", os.clock() - t0)
    )

    return ok, result
end

local function moveToNpc()
    local _,_,root = waitCharacter(10)

    if not root then
        addLog("NPC", "Character/HRP not ready")
        return false
    end

    local before =
        (root.Position - NPC_POS).Magnitude

    root.CFrame =
        CFrame.new(NPC_POS)

    task.wait(0.15)

    local after =
        distanceTo(NPC_POS)

    addLog(
        "NPC",
        "before="
        .. string.format("%.1f", before)
        .. " | after="
        .. string.format("%.1f", after)
    )

    return true
end

local function raceTeleport()
    local before =
        distanceTo(TEMPLE_POS)

    local t0 = os.clock()

    local ok, result =
        pcall(function()
            return CommF:InvokeServer(
                "RaceV4Progress",
                "Teleport"
            )
        end)

    addLog(
        "TELEPORT",
        "ok="
        .. tostring(ok)
        .. " | result="
        .. tostring(result)
        .. " | dt="
        .. string.format("%.3fs", os.clock() - t0)
        .. " | beforeDist="
        .. string.format("%.1f", before)
    )

    if not ok then
        return false, result
    end

    local deadline =
        os.clock()
        + OBSERVE_TIMEOUT

    local best = before

    while os.clock() < deadline do
        task.wait(0.05)

        local d =
            distanceTo(TEMPLE_POS)

        if d < best then
            best = d
        end

        if d <= TEMPLE_CONFIRM_DISTANCE then
            addLog(
                "SUCCESS",
                "ARRIVED TEMPLE | dist="
                .. string.format("%.3f", d)
            )

            return true, result
        end
    end

    local after =
        distanceTo(TEMPLE_POS)

    addLog(
        "NO MOVE",
        "afterDist="
        .. string.format("%.1f", after)
        .. " | best="
        .. string.format("%.1f", best)
    )

    return false, result
end

local busy = false
local lastRunAt = -math.huge

local function runFullTest()
    if busy then
        addLog("FLOW", "busy=true")
        return
    end

    local now = os.clock()

    if now - lastRunAt < RETRY_COOLDOWN then
        addLog(
            "FLOW",
            "cooldown "
            .. string.format(
                "%.1fs",
                RETRY_COOLDOWN - (now - lastRunAt)
            )
        )
        return
    end

    lastRunAt = now
    busy = true

    task.spawn(function()
        addLog("FLOW", "START")

        local state = raceCheck()

        if state == nil then
            addLog("FLOW", "Check failed")

        elseif state == 1 then
            addLog("FLOW", "state=1 -> Check + Begin")

            raceCheck()
            raceBegin()

            task.wait(0.5)

            local after = raceCheck()

            addLog(
                "FLOW",
                "after Begin state="
                .. tostring(after)
                .. " | bấm FULL TEST lại"
            )

        elseif state == 2 then
            addLog("FLOW", "state=2 -> NPC + Teleport")

            if moveToNpc() then
                raceTeleport()
            end

        elseif state == 3 then
            addLog("FLOW", "state=3 -> Check + Continue")

            raceCheck()
            task.wait(1)
            raceContinue()

            task.wait(0.5)

            local after = raceCheck()

            addLog(
                "FLOW",
                "after Continue state="
                .. tostring(after)
            )

        elseif state == 4 then
            addLog("FLOW", "state=4 READY / COMPLETE")

            moveToNpc()
            raceTeleport()

        else
            addLog(
                "FLOW",
                "unknown state="
                .. tostring(state)
            )
        end

        addLog("FLOW", "END")
        busy = false
    end)
end

local parent = CoreGui

pcall(function()
    if type(gethui) == "function" then
        parent = gethui()
    end
end)

local old =
    parent:FindFirstChild(
        "RaceV4TempleStandaloneTest"
    )

if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "RaceV4TempleStandaloneTest"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(650, 410)
Frame.Position = UDim2.new(0.5, -325, 0.5, -205)
Frame.BackgroundColor3 = Color3.fromRGB(18, 21, 29)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = Gui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = Frame

local Header = Instance.new("TextLabel")
Header.BackgroundTransparency = 1
Header.Position = UDim2.fromOffset(12, 7)
Header.Size = UDim2.new(1, -24, 0, 28)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1, 1, 1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text = "RACE V4 TEMPLE - STANDALONE TEST"
Header.Active = true
Header.Parent = Frame

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12, 42)
Scroll.Size = UDim2.new(1, -24, 1, -120)
Scroll.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 7
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.Parent = Frame

LogLabel = Instance.new("TextLabel")
LogLabel.BackgroundTransparency = 1
LogLabel.Position = UDim2.fromOffset(7, 5)
LogLabel.Size = UDim2.new(1, -14, 0, 0)
LogLabel.AutomaticSize = Enum.AutomaticSize.Y
LogLabel.Font = Enum.Font.Code
LogLabel.TextSize = 11
LogLabel.TextColor3 = Color3.fromRGB(215, 225, 240)
LogLabel.TextWrapped = true
LogLabel.TextXAlignment = Enum.TextXAlignment.Left
LogLabel.TextYAlignment = Enum.TextYAlignment.Top
LogLabel.Text = ""
LogLabel.Parent = Scroll

local function makeButton(text, xScale, callback)
    local b = Instance.new("TextButton")

    b.AnchorPoint = Vector2.new(0, 1)
    b.Position = UDim2.new(xScale, 8, 1, -12)
    b.Size = UDim2.new(0.19, -8, 0, 50)
    b.BackgroundColor3 = Color3.fromRGB(40, 47, 64)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextWrapped = true
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Text = text
    b.Parent = Frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 7)
    c.Parent = b

    b.MouseButton1Click:Connect(callback)

    return b
end

makeButton(
    "CHECK",
    0,
    function()
        task.spawn(raceCheck)
    end
)

makeButton(
    "BEGIN",
    0.2,
    function()
        task.spawn(raceBegin)
    end
)

makeButton(
    "GO NPC",
    0.4,
    function()
        task.spawn(moveToNpc)
    end
)

makeButton(
    "TELEPORT",
    0.6,
    function()
        task.spawn(raceTeleport)
    end
)

local FullButton =
    makeButton(
        "FULL TEST",
        0.8,
        runFullTest
    )

FullButton.BackgroundColor3 =
    Color3.fromRGB(45, 95, 70)

local dragging = false
local dragStart
local startPos

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = true
        dragStart = input.Position
        startPos = Frame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging
        and (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        )
    then
        local d = input.Position - dragStart

        Frame.Position =
            UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + d.X,
                startPos.Y.Scale,
                startPos.Y.Offset + d.Y
            )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = false
    end
end)

addLog("READY", "Standalone RaceV4 Temple test loaded")
addLog(
    "INFO",
    "TempleDist="
    .. string.format("%.1f", distanceTo(TEMPLE_POS))
)
addLog("INFO", "Test nhanh nhất: bấm FULL TEST")
