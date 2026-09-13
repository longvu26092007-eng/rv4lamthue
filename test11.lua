--[[
    TEMPLE OF TIME - 3 METHOD TEST
    ==========================================
    Button 1: KAITUN V4
      -> CommF_:InvokeServer("requestEntrance", Vector3.new(28310.0234, 14895.1123, 109.456741))

    Button 2: BANANA HUB
      -> Port movement style used by the Banana source:
         invisible proxy block + TweenService + character follows proxy
         -> target = race-specific "Teleport To Trial Door" CFrame.

    Purpose:
      - Isolate exactly which method works on the current account/server.
      - No Kaitun FSM / AbilitySync / HTTP / Gear / Combat / Trial logic.
      - No external UI library required.

    NOTE:
      Banana source available here exposes the trial-door targets and `_tp`
      proxy-tween implementation. This file ports those mechanics directly.
]]

-- ============================================================
-- SERVICES / BOOT
-- ============================================================
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

local function waitForCharacter(timeout)
    timeout = timeout or 20

    local deadline = os.clock() + timeout

    while os.clock() < deadline do
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")

        if char and hum and root and hum.Health > 0 then
            return char, hum, root
        end

        task.wait(0.1)
    end

    return nil
end

local Remotes =
    ReplicatedStorage:FindFirstChild("Remotes")
    or ReplicatedStorage:WaitForChild("Remotes", 20)

local CommF_ =
    Remotes
    and (
        Remotes:FindFirstChild("CommF_")
        or Remotes:WaitForChild("CommF_", 20)
    )

if not CommF_ then
    warn("[TEMPLE TEST] CommF_ not found")
    return
end

-- ============================================================
-- CONSTANTS
-- ============================================================
local KAITUN_TEMPLE_ENTRY =
    Vector3.new(
        28310.0234,
        14895.1123,
        109.456741
    )


-- Banana Hub "Temple of Time" direct requestEntrance target.
local BANANA_TEMPLE_ENTRY =
    Vector3.new(
        28286.35546875,
        14895.3017578125,
        102.62469482421875
    )

-- Banana Auto Race V4 / Pull Lever NPC flow.
local BANANA_V4_NPC_POS =
    Vector3.new(
        2959.87231,
        2282.42139,
        -7216.23193
    )

local BANANA_V4_TEMPLE_POS =
    Vector3.new(
        28286.35546875,
        14896.5078125,
        102.62469482421875
    )

local BANANA_DOOR_CFRAME = {
    Human =
        CFrame.new(
            29221.822,
            14890.975,
            -205.991
        ),

    Skypiea =
        CFrame.new(
            28960.158,
            14919.624,
            235.039
        ),

    Fishman =
        CFrame.new(
            28231.175,
            14890.975,
            -211.641
        ),

    Cyborg =
        CFrame.new(
            28502.681,
            14895.975,
            -423.727
        ),

    Ghoul =
        CFrame.new(
            28674.244,
            14890.676,
            445.431
        ),

    Mink =
        CFrame.new(
            29012.341,
            14890.975,
            -380.149
        ),
}

-- Banana source uses TweenSpeed or 300.
local BANANA_TWEEN_SPEED =
    tonumber(
        getgenv
        and getgenv().TweenSpeed
        or nil
    )
    or 300

-- ============================================================
-- SAFE POSITION HELPERS
-- Fixes the "attempt to index ... Position" class of errors.
-- ============================================================
local function positionOf(value)
    local kind = typeof(value)

    if kind == "Vector3" then
        return value
    end

    if kind == "CFrame" then
        return value.Position
    end

    if kind == "Instance"
        and value:IsA("BasePart")
    then
        return value.Position
    end

    return nil
end

local function cframeOf(value)
    local kind = typeof(value)

    if kind == "CFrame" then
        return value
    end

    if kind == "Vector3" then
        return CFrame.new(value)
    end

    if kind == "Instance"
        and value:IsA("BasePart")
    then
        return value.CFrame
    end

    return nil
end

local function distanceTo(value)
    local targetPos = positionOf(value)
    if not targetPos then
        return math.huge
    end

    local _, _, root = waitForCharacter(1)
    if not root then
        return math.huge
    end

    return (root.Position - targetPos).Magnitude
end

local function getRace()
    local data =
        LocalPlayer:FindFirstChild("Data")

    local race =
        data
        and data:FindFirstChild("Race")

    return race and tostring(race.Value) or nil
end

-- ============================================================
-- SMALL UI
-- ============================================================
local guiParent
pcall(function()
    guiParent =
        (gethui and gethui())
        or CoreGui
end)

guiParent = guiParent or CoreGui

local old =
    guiParent:FindFirstChild(
        "Temple2MethodTest"
    )

if old then
    old:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Temple2MethodTest"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = guiParent

local Frame = Instance.new("Frame")
Frame.Name = "Main"
Frame.Size = UDim2.fromOffset(540, 250)
Frame.Position = UDim2.new(0.5, -270, 0.5, -125)
Frame.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
Frame.BorderSizePixel = 0
Frame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Frame

local Stroke = Instance.new("UIStroke")
Stroke.Thickness = 1
Stroke.Color = Color3.fromRGB(80, 110, 255)
Stroke.Parent = Frame

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(14, 10)
Title.Size = UDim2.new(1, -28, 0, 28)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 17
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "TEMPLE OF TIME - KV4 vs BANANA"
Title.Parent = Frame

local Status = Instance.new("TextLabel")
Status.BackgroundColor3 = Color3.fromRGB(14, 17, 24)
Status.BorderSizePixel = 0
Status.Position = UDim2.fromOffset(14, 47)
Status.Size = UDim2.new(1, -28, 0, 72)
Status.Font = Enum.Font.Code
Status.TextSize = 13
Status.TextWrapped = true
Status.TextColor3 = Color3.fromRGB(210, 220, 240)
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Top
Status.Text = "Ready."
Status.Parent = Frame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 7)
StatusCorner.Parent = Status

local function makeButton(text, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(158, 58)
    b.Position = UDim2.fromOffset(x, 154)
    b.BackgroundColor3 = Color3.fromRGB(42, 48, 65)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextWrapped = true
    b.Text = text
    b.AutoButtonColor = true
    b.Parent = Frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = b

    return b
end

local KaitunButton =
    makeButton(
        "KAITUN V4\nrequestEntrance",
        14
    )

local BananaDirectButton =
    makeButton(
        "BANANA\nTemple requestEntrance",
        191
    )

local BananaV4Button =
    makeButton(
        "BANANA V4\nNPC / RaceV4Progress",
        368
    )

local function setStatus(text)
    text = tostring(text)
    Status.Text = text
    print("[TEMPLE TEST] " .. text)
end

-- ============================================================
-- KAITUN V4 METHOD
-- Exact requestEntrance behavior from uploaded Kaitun V4.
-- ============================================================
local kaitunBusy = false

local function requestKaitun()
    if kaitunBusy then
        setStatus(
            "Kaitun request is already running."
        )
        return
    end

    kaitunBusy = true

    task.spawn(function()
        local _, _, root =
            waitForCharacter(10)

        if not root then
            setStatus(
                "KAITUN: Character/HRP not ready."
            )
            kaitunBusy = false
            return
        end

        local before =
            distanceTo(
                KAITUN_TEMPLE_ENTRY
            )

        setStatus(
            "KAITUN\n"
            .. "before="
            .. string.format("%.1f", before)
            .. "\ncalling requestEntrance..."
        )

        local t0 = os.clock()

        -- Direct, no timeout, exactly one call.
        local ok, result =
            pcall(function()
                return CommF_:InvokeServer(
                    "requestEntrance",
                    KAITUN_TEMPLE_ENTRY
                )
            end)

        local elapsed =
            os.clock() - t0

        task.wait(0.5)

        local after =
            distanceTo(
                KAITUN_TEMPLE_ENTRY
            )

        setStatus(
            "KAITUN\n"
            .. "ok="
            .. tostring(ok)
            .. " result="
            .. tostring(result)
            .. "\n"
            .. "time="
            .. string.format("%.2fs", elapsed)
            .. " | after="
            .. string.format("%.1f", after)
        )

        kaitunBusy = false
    end)
end

-- ============================================================
-- BANANA HUB DIRECT TEMPLE METHOD
-- Exact Banana "Temple of Time" button:
-- CommF_:InvokeServer("requestEntrance", BANANA_TEMPLE_ENTRY)
-- ============================================================
local bananaDirectBusy = false

local function requestBananaDirect()
    if bananaDirectBusy then
        setStatus("BANANA DIRECT: request already running.")
        return
    end

    bananaDirectBusy = true

    task.spawn(function()
        local _, _, root = waitForCharacter(10)
        if not root then
            setStatus("BANANA DIRECT: Character/HRP not ready.")
            bananaDirectBusy = false
            return
        end

        local before = distanceTo(BANANA_TEMPLE_ENTRY)

        setStatus(
            "BANANA DIRECT\n"
            .. "before=" .. string.format("%.1f", before)
            .. "\nrequestEntrance -> 28286..."
        )

        local t0 = os.clock()
        local ok, result = pcall(function()
            return CommF_:InvokeServer(
                "requestEntrance",
                BANANA_TEMPLE_ENTRY
            )
        end)
        local elapsed = os.clock() - t0

        task.wait(0.75)

        local after = distanceTo(BANANA_TEMPLE_ENTRY)

        setStatus(
            "BANANA DIRECT\n"
            .. "ok=" .. tostring(ok)
            .. " result=" .. tostring(result)
            .. "\ntime=" .. string.format("%.2fs", elapsed)
            .. " | after=" .. string.format("%.1f", after)
        )

        bananaDirectBusy = false
    end)
end

-- ============================================================
-- BANANA HUB MOVEMENT PORT
--
-- Source behavior:
--   invisible anchored block
--   TweenService moves block
--   character follows block while block stays near character
--   noclip while moving
-- ============================================================
local bananaBusy = false
local shouldTween = false
local bananaTween = nil

local BananaBlock = Instance.new("Part")
BananaBlock.Name = "BananaTempleProxy"
BananaBlock.Size = Vector3.new(1, 1, 1)
BananaBlock.Anchored = true
BananaBlock.CanCollide = false
BananaBlock.CanTouch = false
BananaBlock.CanQuery = false
BananaBlock.Transparency = 1
BananaBlock.Parent = workspace

local function syncBlockToCharacter()
    local _, _, root =
        waitForCharacter(1)

    if root then
        BananaBlock.CFrame =
            root.CFrame
    end
end

syncBlockToCharacter()

local followConnection =
    RunService.Heartbeat:Connect(function()
        if not shouldTween then
            return
        end

        local char, hum, root =
            waitForCharacter(0.01)

        if not (
            char
            and hum
            and root
            and hum.Health > 0
        ) then
            return
        end

        -- Banana-style noclip during movement.
        for _, obj in ipairs(
            char:GetDescendants()
        ) do
            if obj:IsA("BasePart")
                and obj.CanCollide
            then
                obj.CanCollide = false
            end
        end

        if not BananaBlock.Parent then
            BananaBlock.Parent = workspace
            BananaBlock.CFrame = root.CFrame
        end

        local gap =
            (
                root.Position
                - BananaBlock.Position
            ).Magnitude

        -- Source behavior: root follows proxy while proxy is close.
        -- If something desyncs badly, re-sync proxy instead of snapping root huge distance.
        if gap <= 200 then
            root.CFrame =
                BananaBlock.CFrame
        else
            BananaBlock.CFrame =
                root.CFrame
        end
    end)

local function bananaTp(target)
    local targetCf =
        cframeOf(target)

    if not targetCf then
        return false,
            "invalid_target"
    end

    local char, hum, root =
        waitForCharacter(5)

    if not (
        char
        and hum
        and root
    ) then
        return false,
            "character_not_ready"
    end

    if bananaTween then
        pcall(function()
            bananaTween:Cancel()
            bananaTween:Destroy()
        end)
        bananaTween = nil
    end

    BananaBlock.CFrame =
        root.CFrame

    local distance =
        (
            targetCf.Position
            - root.Position
        ).Magnitude

    local duration =
        math.max(
            0.05,
            distance
            / BANANA_TWEEN_SPEED
        )

    shouldTween = true

    bananaTween =
        TweenService:Create(
            BananaBlock,
            TweenInfo.new(
                duration,
                Enum.EasingStyle.Linear
            ),
            {
                CFrame = targetCf
            }
        )

    bananaTween:Play()

    return true,
        duration
end

local bananaV4Busy = false

local function getRaceV4Progress()
    local ok, value = pcall(function()
        return CommF_:InvokeServer(
            "RaceV4Progress",
            "Check"
        )
    end)

    if not ok then
        return nil, value
    end

    return value, nil
end

local function bananaRaceV4Progress()
    if bananaV4Busy then
        setStatus("BANANA V4: flow already running.")
        return
    end

    bananaV4Busy = true

    task.spawn(function()
        local _, _, root = waitForCharacter(10)
        if not root then
            setStatus("BANANA V4: Character/HRP not ready.")
            bananaV4Busy = false
            return
        end

        local state, checkErr = getRaceV4Progress()

        if state == nil then
            setStatus(
                "BANANA V4: Check error = "
                .. tostring(checkErr)
            )
            bananaV4Busy = false
            return
        end

        setStatus(
            "BANANA V4\nRaceV4Progress Check = "
            .. tostring(state)
        )

        -- State 1: exact Banana Pull Lever logic -> Check + Begin.
        if state == 1 then
            local okCheck, retCheck = pcall(function()
                return CommF_:InvokeServer(
                    "RaceV4Progress",
                    "Check"
                )
            end)

            local okBegin, retBegin = pcall(function()
                return CommF_:InvokeServer(
                    "RaceV4Progress",
                    "Begin"
                )
            end)

            task.wait(0.5)

            local after = select(1, getRaceV4Progress())

            setStatus(
                "BANANA V4 [state 1]\n"
                .. "Check=" .. tostring(okCheck)
                .. "/" .. tostring(retCheck)
                .. " Begin=" .. tostring(okBegin)
                .. "/" .. tostring(retBegin)
                .. "\nafter Check=" .. tostring(after)
                .. " -> BAM LAI NUT V4"
            )

        -- State 2: exact Banana NPC point + RaceV4Progress Teleport.
        elseif state == 2 then
            pcall(function()
                CommF_:InvokeServer(
                    "RaceV4Progress",
                    "Check"
                )
            end)

            local deadline = os.clock() + 30
            local attempt = 0
            local entered = false

            while os.clock() < deadline do
                local char, hum, liveRoot = waitForCharacter(1)

                if not (char and hum and liveRoot and hum.Health > 0) then
                    break
                end

                local templeDist =
                    (liveRoot.Position - BANANA_V4_TEMPLE_POS).Magnitude

                if templeDist <= 15 then
                    entered = true
                    break
                end

                attempt += 1

                -- Exact position used by Banana Pull Lever source.
                liveRoot.CFrame = CFrame.new(BANANA_V4_NPC_POS)

                local okTp, retTp = pcall(function()
                    return CommF_:InvokeServer(
                        "RaceV4Progress",
                        "Teleport"
                    )
                end)

                task.wait(0.15)

                local _, _, rootAfter = waitForCharacter(1)
                local afterDist =
                    rootAfter
                    and (rootAfter.Position - BANANA_V4_TEMPLE_POS).Magnitude
                    or math.huge

                setStatus(
                    "BANANA V4 [state 2]\n"
                    .. "NPC -> Teleport attempt=" .. tostring(attempt)
                    .. " ok=" .. tostring(okTp)
                    .. " ret=" .. tostring(retTp)
                    .. "\nTempleDist=" .. string.format("%.1f", afterDist)
                )

                if afterDist <= 15 then
                    entered = true
                    break
                end
            end

            local _, _, finalRoot = waitForCharacter(1)
            local finalDist =
                finalRoot
                and (finalRoot.Position - BANANA_V4_TEMPLE_POS).Magnitude
                or math.huge

            setStatus(
                "BANANA V4 [state 2]\n"
                .. (entered and "SUCCESS -> TEMPLE" or "TIMEOUT / NO TELEPORT")
                .. "\nattempts=" .. tostring(attempt)
                .. " | dist=" .. string.format("%.1f", finalDist)
            )

        -- State 3: exact Banana flow -> Check, wait 1s, Continue.
        elseif state == 3 then
            local okCheck, retCheck = pcall(function()
                return CommF_:InvokeServer(
                    "RaceV4Progress",
                    "Check"
                )
            end)

            task.wait(1)

            local okContinue, retContinue = pcall(function()
                return CommF_:InvokeServer(
                    "RaceV4Progress",
                    "Continue"
                )
            end)

            task.wait(0.5)
            local after = select(1, getRaceV4Progress())

            setStatus(
                "BANANA V4 [state 3]\n"
                .. "Check=" .. tostring(okCheck)
                .. "/" .. tostring(retCheck)
                .. " Continue=" .. tostring(okContinue)
                .. "/" .. tostring(retContinue)
                .. "\nafter Check=" .. tostring(after)
            )

        elseif state == 4 then
            setStatus(
                "BANANA V4 [state 4]\n"
                .. "RaceV4Progress READY / COMPLETE."
            )
        else
            setStatus(
                "BANANA V4\nUnknown Check state = "
                .. tostring(state)
            )
        end

        bananaV4Busy = false
    end)
end

KaitunButton.MouseButton1Click:Connect(
    requestKaitun
)

BananaDirectButton.MouseButton1Click:Connect(
    requestBananaDirect
)

BananaV4Button.MouseButton1Click:Connect(
    bananaRaceV4Progress
)

-- Initial diagnostic.
task.spawn(function()
    local _, _, root =
        waitForCharacter(15)

    local race = getRace()

    if root then
        setStatus(
            "Ready"
            .. "\nRace="
            .. tostring(race)
            .. " | TempleDist="
            .. string.format(
                "%.1f",
                distanceTo(
                    KAITUN_TEMPLE_ENTRY
                )
            )
        )
    else
        setStatus(
            "Character/HRP timeout."
        )
    end
end)
