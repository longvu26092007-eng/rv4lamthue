--[[
    MYSTERIOUS FORCE / TEMPLE REMOTE DEBUGGER
    =========================================
    Mục tiêu:
      - Bạn tự mở hội thoại "Mysterious Force".
      - Bạn tự bấm "Use it".
      - Script KHÔNG tự gọi requestEntrance / RaceV4Progress.
      - Script sẽ bắt chính xác lệnh remote được game gọi sau khi bấm.

    Bắt:
      * RemoteFunction:InvokeServer(...)
      * RemoteEvent:FireServer(...)
      * Arguments
      * Return values của InvokeServer
      * UI click "Use it" / "Nevermind"
      * HRP teleport / jump
      * Temple arrival

    Log:
      * Bảng UI cuộn
      * F9 console
      * TEMPLE_MYSTERIOUS_FORCE_DEBUG.txt (nếu có writefile)

    Các vị trí chỉ dùng để MONITOR:
      NPC/Race V4 area:
        2959.87231, 2282.42139, -7216.23193

      Temple:
        28286.35546875, 14896.5078125, 102.62469482421875
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
if not LP then
    warn("[TEMPLE DEBUG] LocalPlayer missing")
    return
end

local Remotes =
    RS:FindFirstChild("Remotes")
    or RS:WaitForChild("Remotes", 20)

local CommF =
    Remotes
    and (
        Remotes:FindFirstChild("CommF_")
        or Remotes:WaitForChild("CommF_", 20)
    )

-- ============================================================
-- MONITOR POSITIONS
-- ============================================================
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

local LOG_FILE =
    "TEMPLE_MYSTERIOUS_FORCE_DEBUG.txt"

-- ============================================================
-- CHARACTER HELPERS
-- ============================================================
local function getRoot()
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

local function waitRoot(timeout)
    local deadline =
        os.clock() + (timeout or 15)

    repeat
        local c,h,r = getRoot()
        if r then
            return c,h,r
        end
        task.wait(0.1)
    until os.clock() >= deadline
end

local function distTo(pos)
    local _,_,root = getRoot()
    if not root then
        return math.huge
    end

    return (root.Position - pos).Magnitude
end

-- ============================================================
-- VALUE FORMATTER
-- ============================================================
local function safeFullName(inst)
    local ok, value =
        pcall(function()
            return inst:GetFullName()
        end)

    return ok and value or tostring(inst)
end

local function stringify(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth >= 3 then
        return "<depth-limit>"
    end

    local tv = typeof(v)

    if tv == "Vector3" then
        return string.format(
            "Vector3.new(%.6f, %.6f, %.6f)",
            v.X, v.Y, v.Z
        )

    elseif tv == "CFrame" then
        local p = v.Position
        return string.format(
            "CFrame.new(%.6f, %.6f, %.6f)",
            p.X, p.Y, p.Z
        )

    elseif tv == "Instance" then
        return safeFullName(v)

    elseif tv == "string" then
        if #v > 250 then
            return string.format(
                "%q...",
                v:sub(1, 250)
            )
        end
        return string.format("%q", v)

    elseif tv == "table" then
        if seen[v] then
            return "<recursive-table>"
        end

        seen[v] = true

        local pieces = {}
        local n = 0

        for k,val in pairs(v) do
            n += 1
            if n > 20 then
                pieces[#pieces+1] = "..."
                break
            end

            pieces[#pieces+1] =
                "["
                .. stringify(k, depth + 1, seen)
                .. "]="
                .. stringify(val, depth + 1, seen)
        end

        seen[v] = nil

        return "{"
            .. table.concat(pieces, ", ")
            .. "}"
    end

    return tostring(v)
end

local function pack(...)
    return table.pack(...)
end

local function argsToText(args)
    local pieces = {}

    for i = 1, args.n or #args do
        pieces[#pieces+1] =
            tostring(i)
            .. "="
            .. stringify(args[i])
    end

    if #pieces == 0 then
        return "<no-args>"
    end

    return table.concat(
        pieces,
        " | "
    )
end

-- ============================================================
-- LOGGING
-- ============================================================
local logs = {}
local LogLabel
local CaptureLabel
local AutoScrollFrame

local captureUntil = 0
local captureId = 0

local function flushFile()
    if writefile then
        pcall(function()
            writefile(
                LOG_FILE,
                table.concat(logs, "\n")
            )
        end)
    end
end

local function updateLogUi()
    if not LogLabel then
        return
    end

    local first =
        math.max(
            1,
            #logs - 90
        )

    local tmp = {}

    for i = first, #logs do
        tmp[#tmp+1] = logs[i]
    end

    LogLabel.Text =
        table.concat(tmp, "\n")

    task.defer(function()
        if AutoScrollFrame then
            AutoScrollFrame.CanvasPosition =
                Vector2.new(
                    0,
                    math.max(
                        0,
                        AutoScrollFrame.AbsoluteCanvasSize.Y
                            - AutoScrollFrame.AbsoluteWindowSize.Y
                    )
                )
        end
    end)
end

local function log(tag, text)
    local line =
        string.format(
            "[%.3f][%s] %s",
            os.clock(),
            tostring(tag),
            tostring(text)
        )

    logs[#logs+1] = line

    if #logs > 1000 then
        table.remove(logs, 1)
    end

    print(
        "[TEMPLE DEBUG] "
        .. line
    )

    updateLogUi()
    flushFile()
end

local function captureActive()
    return os.clock() <= captureUntil
end

local function armCapture(seconds, reason)
    seconds = seconds or 10

    captureUntil =
        math.max(
            captureUntil,
            os.clock() + seconds
        )

    captureId += 1

    log(
        "CAPTURE",
        "ARM #"
        .. tostring(captureId)
        .. " for "
        .. tostring(seconds)
        .. "s | "
        .. tostring(reason)
    )
end

-- ============================================================
-- DIALOGUE UI DETECTOR
-- ============================================================
local watchedButtons = {}
local watchedLabels = {}

local function normalizedText(obj)
    local ok, t =
        pcall(function()
            return tostring(obj.Text or "")
        end)

    if ok then
        return t
    end

    return ""
end

local function isUseItText(t)
    t = tostring(t):lower()

    return t == "use it"
        or t:find("use it", 1, true) ~= nil
end

local function isNevermindText(t)
    t = tostring(t):lower()

    return t == "nevermind"
        or t:find("nevermind", 1, true) ~= nil
end

local function isMysteriousForceText(t)
    t = tostring(t):lower()

    return t:find(
        "mysterious force",
        1,
        true
    ) ~= nil
end

local function isRemnantText(t)
    t = tostring(t):lower()

    return t:find(
        "remnant of the past",
        1,
        true
    ) ~= nil
end

local function watchButton(btn)
    if watchedButtons[btn] then
        return
    end

    watchedButtons[btn] = true

    local function checkAndAttach()
        local text =
            normalizedText(btn)

        if isUseItText(text) then
            log(
                "UI",
                'Found dialogue button "Use it" | '
                .. safeFullName(btn)
            )

            btn.Activated:Connect(function()
                armCapture(
                    12,
                    'clicked dialogue option "Use it"'
                )

                log(
                    "UI CLICK",
                    '"Use it" Activated | '
                    .. safeFullName(btn)
                )
            end)

            btn.MouseButton1Click:Connect(function()
                armCapture(
                    12,
                    '"Use it" MouseButton1Click'
                )

                log(
                    "UI CLICK",
                    '"Use it" MouseButton1Click | '
                    .. safeFullName(btn)
                )
            end)

        elseif isNevermindText(text) then
            log(
                "UI",
                'Found dialogue button "Nevermind" | '
                .. safeFullName(btn)
            )

            btn.Activated:Connect(function()
                armCapture(
                    4,
                    'clicked "Nevermind"'
                )

                log(
                    "UI CLICK",
                    '"Nevermind" Activated'
                )
            end)
        end
    end

    checkAndAttach()

    btn:GetPropertyChangedSignal(
        "Text"
    ):Connect(
        checkAndAttach
    )
end

local function watchTextLabel(lbl)
    if watchedLabels[lbl] then
        return
    end

    watchedLabels[lbl] = true

    local function inspect()
        local text =
            normalizedText(lbl)

        if isMysteriousForceText(text) then
            log(
                "DIALOG",
                'Detected title "Mysterious Force" | '
                .. safeFullName(lbl)
            )

            armCapture(
                15,
                "Mysterious Force dialogue visible"
            )

        elseif isRemnantText(text) then
            log(
                "DIALOG",
                'Detected text "A remnant of the past" | '
                .. safeFullName(lbl)
            )

            armCapture(
                15,
                "Mysterious Force body text visible"
            )
        end
    end

    inspect()

    lbl:GetPropertyChangedSignal(
        "Text"
    ):Connect(
        inspect
    )
end

local function inspectGuiObject(obj)
    if obj:IsA("TextButton") then
        watchButton(obj)

    elseif obj:IsA("TextLabel") then
        watchTextLabel(obj)
    end
end

local PlayerGui =
    LP:WaitForChild(
        "PlayerGui",
        15
    )

if PlayerGui then
    for _,obj in ipairs(
        PlayerGui:GetDescendants()
    ) do
        inspectGuiObject(obj)
    end

    PlayerGui.DescendantAdded:Connect(
        function(obj)
            task.defer(
                inspectGuiObject,
                obj
            )
        end
    )
end

-- Manual click/touch near NPC/dialogue also arms capture.
UIS.InputBegan:Connect(
    function(input, processed)
        local mouseOrTouch =
            input.UserInputType
                == Enum.UserInputType.MouseButton1
            or input.UserInputType
                == Enum.UserInputType.Touch

        if not mouseOrTouch then
            return
        end

        if distTo(NPC_POS) <= 200 then
            armCapture(
                10,
                "manual click/touch near V4 NPC"
            )

            log(
                "INPUT",
                "click/touch near NPC"
                .. " | processed="
                .. tostring(processed)
            )
        end
    end
)

-- ============================================================
-- REMOTE TRACE
-- ============================================================
local traceInstalled = false
local oldNamecall

local function isRemoteInstance(obj)
    return typeof(obj) == "Instance"
        and (
            obj:IsA("RemoteFunction")
            or obj:IsA("RemoteEvent")
        )
end

local function remoteLooksRelevant(self, args)
    if self == CommF then
        return true
    end

    local name =
        safeFullName(self):lower()

    if name:find("commf", 1, true)
        or name:find("dialog", 1, true)
        or name:find("temple", 1, true)
        or name:find("race", 1, true)
    then
        return true
    end

    for i = 1, args.n or #args do
        local s =
            tostring(args[i]):lower()

        if s:find("racev4", 1, true)
            or s:find("entrance", 1, true)
            or s:find("temple", 1, true)
            or s:find("teleport", 1, true)
            or s:find("mysterious", 1, true)
        then
            return true
        end
    end

    return false
end

local function installTrace()
    if traceInstalled then
        return true
    end

    if not hookmetamethod
        or not getnamecallmethod
        or not newcclosure
    then
        log(
            "ERROR",
            "Executor thiếu hookmetamethod/getnamecallmethod/newcclosure"
        )
        return false
    end

    local ok, err =
        pcall(function()
            oldNamecall =
                hookmetamethod(
                    game,
                    "__namecall",
                    newcclosure(function(self, ...)
                        local method =
                            getnamecallmethod()

                        local isCall =
                            method == "InvokeServer"
                            or method == "FireServer"

                        if not isCall
                            or not isRemoteInstance(self)
                        then
                            return oldNamecall(
                                self,
                                ...
                            )
                        end

                        local args =
                            pack(...)

                        -- Trong capture window: log TẤT CẢ remote.
                        -- Ngoài window: chỉ log CommF/Temple/Race relevant.
                        local shouldLog =
                            captureActive()
                            or remoteLooksRelevant(
                                self,
                                args
                            )

                        if not shouldLog then
                            return oldNamecall(
                                self,
                                ...
                            )
                        end

                        local fullName =
                            safeFullName(self)

                        local before =
                            os.clock()

                        log(
                            "REMOTE >",
                            method
                            .. " "
                            .. fullName
                            .. " | "
                            .. argsToText(args)
                        )

                        if method == "InvokeServer" then
                            local results =
                                pack(
                                    oldNamecall(
                                        self,
                                        table.unpack(
                                            args,
                                            1,
                                            args.n
                                        )
                                    )
                                )

                            local elapsed =
                                os.clock()
                                - before

                            log(
                                "REMOTE <",
                                "RETURN "
                                .. fullName
                                .. " | dt="
                                .. string.format(
                                    "%.4fs",
                                    elapsed
                                )
                                .. " | "
                                .. argsToText(results)
                            )

                            return table.unpack(
                                results,
                                1,
                                results.n
                            )
                        end

                        oldNamecall(
                            self,
                            table.unpack(
                                args,
                                1,
                                args.n
                            )
                        )

                        log(
                            "REMOTE <",
                            "FIRED "
                            .. fullName
                        )

                        return nil
                    end)
                )
        end)

    if not ok then
        log(
            "ERROR",
            "hook failed: "
            .. tostring(err)
        )
        return false
    end

    traceInstalled = true

    log(
        "TRACE",
        "Remote tracer ON"
    )

    return true
end

-- ============================================================
-- EXTRA DIALOGUE MODULE INSPECTION
-- Only reads metadata; does not execute dialogue actions.
-- ============================================================
local function inspectDialogueModules()
    local listModule =
        RS:FindFirstChild("DialoguesList")

    if not listModule then
        log(
            "DIALOG SCAN",
            "ReplicatedStorage.DialoguesList not found"
        )
        return
    end

    local ok, list =
        pcall(
            require,
            listModule
        )

    if not ok
        or type(list) ~= "table"
    then
        log(
            "DIALOG SCAN",
            "require DialoguesList failed: "
            .. tostring(list)
        )
        return
    end

    local hits = 0

    local function scan(value, path, depth, seen)
        if depth > 5 then
            return
        end

        seen = seen or {}

        if type(value) == "table" then
            if seen[value] then
                return
            end
            seen[value] = true

            for k,v in pairs(value) do
                local p =
                    path
                    .. "."
                    .. tostring(k)

                if type(v) == "string" then
                    local lower =
                        v:lower()

                    if lower:find(
                        "mysterious force",
                        1,
                        true
                    )
                    or lower:find(
                        "remnant of the past",
                        1,
                        true
                    )
                    or lower == "use it"
                    then
                        hits += 1

                        log(
                            "DIALOG SCAN",
                            p
                            .. " = "
                            .. stringify(v)
                        )
                    end

                elseif type(v) == "table" then
                    scan(
                        v,
                        p,
                        depth + 1,
                        seen
                    )
                end
            end
        end
    end

    scan(
        list,
        "DialoguesList",
        0,
        {}
    )

    log(
        "DIALOG SCAN",
        "matches="
        .. tostring(hits)
    )
end

-- ============================================================
-- HRP TELEPORT MONITOR
-- ============================================================
local monitorOn = false

local function startMovementMonitor()
    if monitorOn then
        return
    end

    monitorOn = true

    task.spawn(function()
        local lastPos
        local wasTemple = false

        while true do
            task.wait(0.025)

            local _,_,root =
                getRoot()

            if root then
                local pos =
                    root.Position

                local templeDist =
                    (
                        pos
                        - TEMPLE_POS
                    ).Magnitude

                if lastPos then
                    local jump =
                        (
                            pos
                            - lastPos
                        ).Magnitude

                    if jump >= 100 then
                        log(
                            "HRP",
                            "JUMP "
                            .. string.format(
                                "%.1f",
                                jump
                            )
                            .. " studs | "
                            .. stringify(lastPos)
                            .. " -> "
                            .. stringify(pos)
                            .. " | templeDist="
                            .. string.format(
                                "%.2f",
                                templeDist
                            )
                        )
                    end
                end

                local nowTemple =
                    templeDist <= 100

                if nowTemple
                    and not wasTemple
                then
                    log(
                        "TEMPLE",
                        "ARRIVED | HRP="
                        .. stringify(pos)
                        .. " | dist="
                        .. string.format(
                            "%.3f",
                            templeDist
                        )
                    )
                end

                wasTemple =
                    nowTemple

                lastPos =
                    pos
            end
        end
    end)
end

-- ============================================================
-- UI
-- movable + resizable + scrolling log
-- ============================================================
local guiParent = CoreGui

pcall(function()
    if gethui then
        guiParent = gethui()
    end
end)

local old =
    guiParent:FindFirstChild(
        "MysteriousForceDebugger"
    )

if old then
    old:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "MysteriousForceDebugger"

Gui.ResetOnSpawn = false
Gui.Parent = guiParent

local Frame =
    Instance.new("Frame")

Frame.Size =
    UDim2.fromOffset(
        720,
        430
    )

Frame.Position =
    UDim2.new(
        0.5,
        -360,
        0.5,
        -215
    )

Frame.BackgroundColor3 =
    Color3.fromRGB(
        18,
        21,
        29
    )

Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = Gui

local fc =
    Instance.new("UICorner")

fc.CornerRadius =
    UDim.new(0, 10)

fc.Parent = Frame

local Header =
    Instance.new("TextLabel")

Header.BackgroundTransparency = 1
Header.Position =
    UDim2.fromOffset(12, 7)

Header.Size =
    UDim2.new(
        1,
        -145,
        0,
        30
    )

Header.Font =
    Enum.Font.GothamBold

Header.TextSize = 14
Header.TextColor3 =
    Color3.new(1,1,1)

Header.TextXAlignment =
    Enum.TextXAlignment.Left

Header.Text =
    "MYSTERIOUS FORCE DEBUG | click 'Use it' rồi xem REMOTE > / REMOTE <"

Header.Active = true
Header.Parent = Frame

CaptureLabel =
    Instance.new("TextLabel")

CaptureLabel.BackgroundTransparency = 1
CaptureLabel.AnchorPoint =
    Vector2.new(1,0)

CaptureLabel.Position =
    UDim2.new(
        1,
        -12,
        0,
        7
    )

CaptureLabel.Size =
    UDim2.fromOffset(
        130,
        30
    )

CaptureLabel.Font =
    Enum.Font.Code

CaptureLabel.TextSize = 12
CaptureLabel.TextColor3 =
    Color3.fromRGB(
        150,
        220,
        255
    )

CaptureLabel.TextXAlignment =
    Enum.TextXAlignment.Right

CaptureLabel.Text = "TRACE ON"
CaptureLabel.Parent = Frame

local Scroll =
    Instance.new(
        "ScrollingFrame"
    )

Scroll.Position =
    UDim2.fromOffset(
        12,
        44
    )

Scroll.Size =
    UDim2.new(
        1,
        -24,
        1,
        -118
    )

Scroll.BackgroundColor3 =
    Color3.fromRGB(
        8,
        11,
        17
    )

Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 7
Scroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

Scroll.CanvasSize =
    UDim2.new(0,0,0,0)

Scroll.Parent = Frame

AutoScrollFrame = Scroll

LogLabel =
    Instance.new("TextLabel")

LogLabel.BackgroundTransparency = 1
LogLabel.Position =
    UDim2.fromOffset(
        7,
        5
    )

LogLabel.Size =
    UDim2.new(
        1,
        -14,
        0,
        0
    )

LogLabel.AutomaticSize =
    Enum.AutomaticSize.Y

LogLabel.Font =
    Enum.Font.Code

LogLabel.TextSize = 11
LogLabel.TextColor3 =
    Color3.fromRGB(
        215,
        225,
        240
    )

LogLabel.TextXAlignment =
    Enum.TextXAlignment.Left

LogLabel.TextYAlignment =
    Enum.TextYAlignment.Top

LogLabel.TextWrapped = true
LogLabel.Text = ""
LogLabel.Parent = Scroll

local function makeButton(
    text,
    xScale
)
    local b =
        Instance.new(
            "TextButton"
        )

    b.AnchorPoint =
        Vector2.new(0,1)

    b.Position =
        UDim2.new(
            xScale,
            8,
            1,
            -10
        )

    b.Size =
        UDim2.new(
            0.24,
            -12,
            0,
            48
        )

    b.BackgroundColor3 =
        Color3.fromRGB(
            40,
            47,
            64
        )

    b.BorderSizePixel = 0
    b.Font =
        Enum.Font.GothamBold

    b.TextSize = 11
    b.TextWrapped = true
    b.TextColor3 =
        Color3.new(1,1,1)

    b.Text = text
    b.Parent = Frame

    local c =
        Instance.new(
            "UICorner"
        )

    c.CornerRadius =
        UDim.new(0, 7)

    c.Parent = b

    return b
end

local GoNpc =
    makeButton(
        "GO TO NPC\n(no remote)",
        0
    )

local ArmButton =
    makeButton(
        "ARM ALL REMOTES\n12 SEC",
        0.25
    )

local ScanButton =
    makeButton(
        "SCAN DIALOGUE\nMODULE",
        0.5
    )

local ClearButton =
    makeButton(
        "CLEAR LOG",
        0.75
    )

-- ============================================================
-- DRAG + RESIZE
-- ============================================================
local MIN_W, MIN_H =
    440, 280

local MAX_W, MAX_H =
    1200, 800

local dragging = false
local resizing = false
local dragStart
local startPosition
local resizeStart
local startSize

Header.InputBegan:Connect(
    function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
        or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart =
                input.Position

            startPosition =
                Frame.Position
        end
    end
)

local Resize =
    Instance.new(
        "TextButton"
    )

Resize.AnchorPoint =
    Vector2.new(1,1)

Resize.Position =
    UDim2.new(
        1,
        -3,
        1,
        -3
    )

Resize.Size =
    UDim2.fromOffset(
        24,
        24
    )

Resize.BackgroundColor3 =
    Color3.fromRGB(
        70,
        80,
        105
    )

Resize.BorderSizePixel = 0
Resize.Text = "↘"
Resize.TextColor3 =
    Color3.new(1,1,1)

Resize.TextSize = 13
Resize.ZIndex = 20
Resize.Parent = Frame

Resize.InputBegan:Connect(
    function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
        or input.UserInputType
            == Enum.UserInputType.Touch
        then
            resizing = true
            resizeStart =
                input.Position

            startSize =
                Frame.AbsoluteSize
        end
    end
)

UIS.InputChanged:Connect(
    function(input)
        if dragging
            and (
                input.UserInputType
                    == Enum.UserInputType.MouseMovement
                or input.UserInputType
                    == Enum.UserInputType.Touch
            )
        then
            local delta =
                input.Position
                - dragStart

            Frame.Position =
                UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset
                        + delta.X,
                    startPosition.Y.Scale,
                    startPosition.Y.Offset
                        + delta.Y
                )

        elseif resizing
            and (
                input.UserInputType
                    == Enum.UserInputType.MouseMovement
                or input.UserInputType
                    == Enum.UserInputType.Touch
            )
        then
            local delta =
                input.Position
                - resizeStart

            Frame.Size =
                UDim2.fromOffset(
                    math.clamp(
                        startSize.X
                            + delta.X,
                        MIN_W,
                        MAX_W
                    ),
                    math.clamp(
                        startSize.Y
                            + delta.Y,
                        MIN_H,
                        MAX_H
                    )
                )
        end
    end
)

UIS.InputEnded:Connect(
    function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
        or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragging = false
            resizing = false
        end
    end
)

-- ============================================================
-- BUTTONS
-- ============================================================
GoNpc.MouseButton1Click:Connect(
    function()
        local _,_,root =
            waitRoot(10)

        if not root then
            log(
                "ERROR",
                "HRP not ready"
            )
            return
        end

        installTrace()
        startMovementMonitor()

        local before =
            (
                root.Position
                - NPC_POS
            ).Magnitude

        -- Only move. NO remote.
        root.CFrame =
            CFrame.new(
                NPC_POS
                + Vector3.new(
                    0,
                    3,
                    0
                )
            )

        task.wait(0.2)

        log(
            "MOVE",
            "GO TO NPC"
            .. " | before="
            .. string.format(
                "%.1f",
                before
            )
            .. " | after="
            .. string.format(
                "%.1f",
                distTo(NPC_POS)
            )
            .. " | hãy tự mở Mysterious Force và bấm Use it"
        )
    end
)

ArmButton.MouseButton1Click:Connect(
    function()
        armCapture(
            12,
            "manual ARM button"
        )
    end
)

ScanButton.MouseButton1Click:Connect(
    inspectDialogueModules
)

ClearButton.MouseButton1Click:Connect(
    function()
        logs = {}
        flushFile()
        updateLogUi()

        log(
            "LOG",
            "cleared"
        )
    end
)

-- ============================================================
-- STATUS LOOP
-- ============================================================
task.spawn(function()
    while Gui.Parent do
        task.wait(0.1)

        if CaptureLabel then
            if captureActive() then
                CaptureLabel.Text =
                    "CAPTURE "
                    .. string.format(
                        "%.1fs",
                        math.max(
                            0,
                            captureUntil
                                - os.clock()
                        )
                    )

                CaptureLabel.TextColor3 =
                    Color3.fromRGB(
                        80,
                        255,
                        150
                    )
            else
                CaptureLabel.Text =
                    "TRACE ON"

                CaptureLabel.TextColor3 =
                    Color3.fromRGB(
                        150,
                        220,
                        255
                    )
            end
        end
    end
end)

-- ============================================================
-- START
-- ============================================================
installTrace()
startMovementMonitor()

log(
    "READY",
    "Tracer đã bật. "
    .. "Mở Mysterious Force -> bấm Use it. "
    .. "Debugger sẽ log chính xác remote + args + return."
)

log(
    "POS",
    "npcDist="
    .. string.format(
        "%.1f",
        distTo(NPC_POS)
    )
    .. " | templeDist="
    .. string.format(
        "%.1f",
        distTo(TEMPLE_POS)
    )
)
