--[[
    MYSTERIOUS FORCE DEBUGGER - SAFE TOGGLES
    =========================================
    Mục tiêu:
      - KHÔNG chặn việc bấm NPC / mở menu hội thoại.
      - Từng bước có ON/OFF riêng.
      - Remote tracer mặc định OFF.
      - Bạn mở menu NPC trước, sau đó mới bật Remote Trace + ARM rồi bấm "Use it".

    STEP:
      1) UI WATCH       : chỉ quan sát Mysterious Force / Use it.
      2) CALLBACK SCAN  : đọc connections/constants/upvalues của nút Use it (nếu executor hỗ trợ).
      3) REMOTE TRACE   : hook pass-through cực nhẹ, mặc định OFF.
      4) HRP MONITOR    : theo dõi teleport / Temple arrival.

    QUAN TRỌNG:
      - Script KHÔNG tự gọi RaceV4Progress.
      - Script KHÔNG tự gọi requestEntrance.
      - Remote hook KHÔNG sửa return value, KHÔNG giữ InvokeServer,
        chỉ copy args rồi return oldNamecall(...) ngay.
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

local LP = Players.LocalPlayer
if not LP then
    warn("[MF DEBUG] LocalPlayer missing")
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
-- KNOWN POSITIONS (monitor / go-to only)
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
    "MYSTERIOUS_FORCE_SAFE_DEBUG_LOG.txt"

-- ============================================================
-- FLAGS
-- ============================================================
local Flags = {
    uiWatch = true,
    callbackScan = true,
    remoteTrace = false, -- IMPORTANT: OFF by default
    hrpMonitor = true,
    logAllDuringArm = true,
}

local captureUntil = 0
local traceInstalled = false
local oldNamecall = nil

-- ============================================================
-- CHARACTER
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
-- FORMATTER
-- ============================================================
local function safeFullName(inst)
    local ok, result =
        pcall(function()
            return inst:GetFullName()
        end)
    return ok and result or tostring(inst)
end

local function stringify(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth >= 2 then
        return "<depth>"
    end

    local t = typeof(v)

    if t == "Vector3" then
        return string.format(
            "Vector3.new(%.6f, %.6f, %.6f)",
            v.X, v.Y, v.Z
        )
    elseif t == "CFrame" then
        local p = v.Position
        return string.format(
            "CFrame.new(%.6f, %.6f, %.6f)",
            p.X, p.Y, p.Z
        )
    elseif t == "Instance" then
        return safeFullName(v)
    elseif t == "string" then
        return string.format("%q", #v > 180 and v:sub(1,180).."..." or v)
    elseif t == "table" then
        if seen[v] then
            return "<recursive>"
        end

        seen[v] = true
        local out = {}
        local n = 0

        for k,val in pairs(v) do
            n += 1
            if n > 10 then
                out[#out+1] = "..."
                break
            end

            out[#out+1] =
                "["
                .. stringify(k, depth+1, seen)
                .. "]="
                .. stringify(val, depth+1, seen)
        end

        seen[v] = nil
        return "{" .. table.concat(out, ", ") .. "}"
    end

    return tostring(v)
end

local function pack(...)
    return table.pack(...)
end

local function argsText(args)
    local out = {}
    for i = 1, args.n or #args do
        out[#out+1] =
            tostring(i)
            .. "="
            .. stringify(args[i])
    end
    return #out > 0 and table.concat(out, " | ") or "<no-args>"
end

-- ============================================================
-- LOGGING
-- ============================================================
local logs = {}
local LogLabel
local Scroll
local ArmLabel

local function flush()
    if writefile then
        pcall(function()
            writefile(
                LOG_FILE,
                table.concat(logs, "\n")
            )
        end)
    end
end

local function refreshLog()
    if not LogLabel then
        return
    end

    local first =
        math.max(1, #logs - 120)

    local view = {}
    for i = first, #logs do
        view[#view+1] = logs[i]
    end

    LogLabel.Text =
        table.concat(view, "\n")

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

local function log(tag, message)
    local line =
        string.format(
            "[%.3f][%s] %s",
            os.clock(),
            tostring(tag),
            tostring(message)
        )

    logs[#logs+1] = line

    if #logs > 1000 then
        table.remove(logs, 1)
    end

    print("[MF DEBUG] " .. line)
    refreshLog()
    flush()
end

local function arm(seconds, reason)
    seconds = seconds or 10

    captureUntil =
        math.max(
            captureUntil,
            os.clock() + seconds
        )

    log(
        "ARM",
        tostring(seconds)
        .. "s | "
        .. tostring(reason)
    )
end

local function armed()
    return os.clock() <= captureUntil
end

-- ============================================================
-- UI TEXT FINDER (POLLING ONLY - no click callbacks injected)
-- ============================================================
local PlayerGui =
    LP:WaitForChild("PlayerGui", 15)

local lastDialogFound = false
local lastUseButton = nil
local callbackScannedButton = nil

local function getText(obj)
    local ok, value =
        pcall(function()
            return tostring(obj.Text or "")
        end)
    return ok and value or ""
end

local function findMysteriousForceUi()
    if not PlayerGui then
        return nil, nil, nil
    end

    local titleObj = nil
    local bodyObj = nil
    local useButton = nil

    for _,obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("TextLabel")
            or obj:IsA("TextButton")
        then
            local text = getText(obj)
            local lower = text:lower()

            if lower:find("mysterious force", 1, true) then
                titleObj = obj
            elseif lower:find("remnant of the past", 1, true) then
                bodyObj = obj
            elseif obj:IsA("TextButton")
                and lower:find("use it", 1, true)
            then
                useButton = obj
            end
        end
    end

    return titleObj, bodyObj, useButton
end

-- ============================================================
-- CALLBACK INSPECTOR
-- Non-invasive: reads existing connections only.
-- ============================================================
local function inspectFunction(fn, label)
    if type(fn) ~= "function" then
        return
    end

    log(
        "CALLBACK",
        label .. " function=" .. tostring(fn)
    )

    if getconstants then
        local ok, constants =
            pcall(getconstants, fn)

        if ok and type(constants) == "table" then
            for i,v in ipairs(constants) do
                local s =
                    tostring(v)

                local lower =
                    s:lower()

                if lower:find("race", 1, true)
                    or lower:find("teleport", 1, true)
                    or lower:find("entrance", 1, true)
                    or lower:find("temple", 1, true)
                    or lower:find("progress", 1, true)
                    or lower:find("continue", 1, true)
                    or lower:find("begin", 1, true)
                    or lower:find("check", 1, true)
                then
                    log(
                        "CONST",
                        label
                        .. " ["
                        .. tostring(i)
                        .. "]="
                        .. stringify(v)
                    )
                end
            end
        end
    end

    if getupvalues then
        local ok, ups =
            pcall(getupvalues, fn)

        if ok and type(ups) == "table" then
            for i,v in pairs(ups) do
                local rendered =
                    stringify(v)

                local lower =
                    rendered:lower()

                if lower:find("race", 1, true)
                    or lower:find("teleport", 1, true)
                    or lower:find("entrance", 1, true)
                    or lower:find("temple", 1, true)
                then
                    log(
                        "UPVALUE",
                        label
                        .. " ["
                        .. tostring(i)
                        .. "]="
                        .. rendered
                    )
                end
            end
        end
    end
end

local function scanUseButtonCallbacks(button)
    if not button then
        log("CALLBACK", 'No "Use it" button found')
        return
    end

    if not getconnections then
        log("CALLBACK", "getconnections unavailable")
        return
    end

    log(
        "CALLBACK",
        'Scanning "Use it" | '
        .. safeFullName(button)
    )

    local signals = {
        {"Activated", button.Activated},
        {"MouseButton1Click", button.MouseButton1Click},
        {"MouseButton1Down", button.MouseButton1Down},
    }

    for _,entry in ipairs(signals) do
        local name = entry[1]
        local signal = entry[2]

        local ok, conns =
            pcall(
                getconnections,
                signal
            )

        if ok and type(conns) == "table" then
            log(
                "CALLBACK",
                name
                .. " connections="
                .. tostring(#conns)
            )

            for i,conn in ipairs(conns) do
                local fn =
                    conn.Function
                    or conn.function

                if type(fn) == "function" then
                    inspectFunction(
                        fn,
                        name .. "#" .. tostring(i)
                    )
                end
            end
        end
    end
end

-- ============================================================
-- SAFE REMOTE TRACE
-- Installed ONLY when user explicitly enables it.
-- Does not capture return values. It logs args asynchronously
-- and immediately passes the original call through.
-- ============================================================
local function looksRelevant(self, args)
    if self == CommF then
        return true
    end

    local name =
        safeFullName(self):lower()

    if name:find("race", 1, true)
        or name:find("dialog", 1, true)
        or name:find("temple", 1, true)
    then
        return true
    end

    for i = 1, args.n or #args do
        local s =
            tostring(args[i]):lower()

        if s:find("racev4", 1, true)
            or s:find("teleport", 1, true)
            or s:find("entrance", 1, true)
            or s:find("temple", 1, true)
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
            "TRACE",
            "executor thiếu hookmetamethod/getnamecallmethod/newcclosure"
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

                        if not Flags.remoteTrace
                            or (
                                method ~= "InvokeServer"
                                and method ~= "FireServer"
                            )
                            or typeof(self) ~= "Instance"
                            or not (
                                self:IsA("RemoteFunction")
                                or self:IsA("RemoteEvent")
                            )
                        then
                            return oldNamecall(self, ...)
                        end

                        local args =
                            pack(...)

                        local shouldLog =
                            looksRelevant(self, args)
                            or (
                                Flags.logAllDuringArm
                                and armed()
                            )

                        if shouldLog then
                            local remoteName =
                                safeFullName(self)

                            local methodCopy = method
                            local argsCopy =
                                table.clone(args)

                            argsCopy.n = args.n

                            -- Important: log OUTSIDE the namecall path.
                            task.defer(function()
                                log(
                                    "REMOTE",
                                    methodCopy
                                    .. " "
                                    .. remoteName
                                    .. " | "
                                    .. argsText(argsCopy)
                                )
                            end)
                        end

                        -- Immediate transparent pass-through.
                        return oldNamecall(
                            self,
                            ...
                        )
                    end)
                )
        end)

    if not ok then
        log(
            "TRACE",
            "hook install failed: "
            .. tostring(err)
        )
        return false
    end

    traceInstalled = true
    log(
        "TRACE",
        "hook installed (pass-through)"
    )
    return true
end

-- ============================================================
-- HRP MONITOR
-- ============================================================
task.spawn(function()
    local lastPos = nil
    local inTemple = false

    while true do
        task.wait(0.04)

        if Flags.hrpMonitor then
            local _,_,root = getRoot()

            if root then
                local pos =
                    root.Position

                local td =
                    (pos - TEMPLE_POS).Magnitude

                if lastPos then
                    local jump =
                        (pos - lastPos).Magnitude

                    if jump >= 120 then
                        log(
                            "HRP",
                            "JUMP "
                            .. string.format("%.1f", jump)
                            .. " | "
                            .. stringify(lastPos)
                            .. " -> "
                            .. stringify(pos)
                            .. " | templeDist="
                            .. string.format("%.2f", td)
                        )
                    end
                end

                local nowTemple =
                    td <= 100

                if nowTemple and not inTemple then
                    log(
                        "TEMPLE",
                        "ARRIVED | "
                        .. stringify(pos)
                        .. " | dist="
                        .. string.format("%.3f", td)
                    )
                end

                inTemple = nowTemple
                lastPos = pos
            end
        else
            lastPos = nil
            inTemple = false
        end
    end
end)

-- ============================================================
-- UI WATCH POLLER
-- ============================================================
task.spawn(function()
    while true do
        task.wait(0.2)

        if Flags.uiWatch then
            local titleObj, bodyObj, useButton =
                findMysteriousForceUi()

            local found =
                titleObj ~= nil
                or bodyObj ~= nil
                or useButton ~= nil

            if found and not lastDialogFound then
                log(
                    "UI",
                    "Mysterious Force menu detected"
                )
            elseif not found and lastDialogFound then
                log(
                    "UI",
                    "Mysterious Force menu closed"
                )
            end

            lastDialogFound = found

            if useButton
                and useButton ~= lastUseButton
            then
                lastUseButton = useButton

                log(
                    "UI",
                    '"Use it" found | '
                    .. safeFullName(useButton)
                )

                if Flags.callbackScan
                    and callbackScannedButton ~= useButton
                then
                    callbackScannedButton =
                        useButton

                    task.defer(function()
                        scanUseButtonCallbacks(
                            useButton
                        )
                    end)
                end
            end
        end
    end
end)

-- ============================================================
-- GUI
-- ============================================================
local parent = CoreGui
pcall(function()
    if gethui then
        parent = gethui()
    end
end)

local oldGui =
    parent:FindFirstChild(
        "MysteriousForceSafeDebugger"
    )

if oldGui then
    oldGui:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "MysteriousForceSafeDebugger"

Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame =
    Instance.new("Frame")

Frame.Size =
    UDim2.fromOffset(
        760,
        460
    )

Frame.Position =
    UDim2.new(
        0.5,
        -380,
        0.5,
        -230
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

local corner =
    Instance.new("UICorner")

corner.CornerRadius =
    UDim.new(0, 10)

corner.Parent = Frame

local Header =
    Instance.new("TextLabel")

Header.BackgroundTransparency = 1
Header.Position =
    UDim2.fromOffset(12, 7)

Header.Size =
    UDim2.new(
        1,
        -24,
        0,
        28
    )

Header.Font =
    Enum.Font.GothamBold

Header.TextSize = 14
Header.TextColor3 =
    Color3.new(1,1,1)

Header.TextXAlignment =
    Enum.TextXAlignment.Left

Header.Text =
    "MYSTERIOUS FORCE SAFE DEBUG | mở menu trước, bật Remote Trace sau"

Header.Active = true
Header.Parent = Frame

Scroll =
    Instance.new("ScrollingFrame")

Scroll.Position =
    UDim2.fromOffset(
        12,
        42
    )

Scroll.Size =
    UDim2.new(
        1,
        -24,
        1,
        -155
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

LogLabel =
    Instance.new("TextLabel")

LogLabel.BackgroundTransparency = 1
LogLabel.Position =
    UDim2.fromOffset(7,5)

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

LogLabel.TextWrapped = true
LogLabel.TextXAlignment =
    Enum.TextXAlignment.Left

LogLabel.TextYAlignment =
    Enum.TextYAlignment.Top

LogLabel.Text = ""
LogLabel.Parent = Scroll

-- ============================================================
-- TOGGLE FACTORY
-- ============================================================
local toggleButtons = {}

local function setToggleVisual(button, key, label)
    local on =
        Flags[key] == true

    button.Text =
        label
        .. "\n"
        .. (on and "ON" or "OFF")

    button.BackgroundColor3 =
        on
        and Color3.fromRGB(42,92,70)
        or Color3.fromRGB(60,45,55)
end

local function makeToggle(
    key,
    label,
    xScale
)
    local b =
        Instance.new("TextButton")

    b.AnchorPoint =
        Vector2.new(0,1)

    b.Position =
        UDim2.new(
            xScale,
            8,
            1,
            -72
        )

    b.Size =
        UDim2.new(
            0.195,
            -10,
            0,
            52
        )

    b.BorderSizePixel = 0
    b.Font =
        Enum.Font.GothamBold

    b.TextSize = 11
    b.TextWrapped = true
    b.TextColor3 =
        Color3.new(1,1,1)

    b.Parent = Frame

    local c =
        Instance.new("UICorner")

    c.CornerRadius =
        UDim.new(0,7)

    c.Parent = b

    b.MouseButton1Click:Connect(
        function()
            if key == "remoteTrace"
                and not traceInstalled
            then
                local ok =
                    installTrace()

                if not ok then
                    return
                end
            end

            Flags[key] =
                not Flags[key]

            setToggleVisual(
                b,
                key,
                label
            )

            log(
                "TOGGLE",
                label
                .. "="
                .. tostring(
                    Flags[key]
                )
            )
        end
    )

    toggleButtons[key] = b

    setToggleVisual(
        b,
        key,
        label
    )

    return b
end

makeToggle(
    "uiWatch",
    "1 UI WATCH",
    0
)

makeToggle(
    "callbackScan",
    "2 CALLBACK SCAN",
    0.2
)

makeToggle(
    "remoteTrace",
    "3 REMOTE TRACE",
    0.4
)

makeToggle(
    "hrpMonitor",
    "4 HRP MONITOR",
    0.6
)

makeToggle(
    "logAllDuringArm",
    "5 ALL REMOTES/ARM",
    0.8
)

-- ============================================================
-- ACTION BUTTONS
-- ============================================================
local function makeAction(
    text,
    xScale,
    callback
)
    local b =
        Instance.new("TextButton")

    b.AnchorPoint =
        Vector2.new(0,1)

    b.Position =
        UDim2.new(
            xScale,
            8,
            1,
            -12
        )

    b.Size =
        UDim2.new(
            0.24,
            -10,
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
        Instance.new("UICorner")

    c.CornerRadius =
        UDim.new(0,7)

    c.Parent = b

    b.MouseButton1Click:Connect(
        callback
    )

    return b
end

makeAction(
    "GO TO NPC\n(no remote)",
    0,
    function()
        local _,_,root =
            waitRoot(10)

        if not root then
            log("MOVE", "HRP not ready")
            return
        end

        local before =
            (root.Position - NPC_POS).Magnitude

        root.CFrame =
            CFrame.new(
                NPC_POS
                + Vector3.new(0,3,0)
            )

        task.wait(0.15)

        log(
            "MOVE",
            "to NPC | before="
            .. string.format("%.1f", before)
            .. " after="
            .. string.format(
                "%.1f",
                distTo(NPC_POS)
            )
        )
    end
)

makeAction(
    "ARM\n10 SEC",
    0.25,
    function()
        arm(
            10,
            "manual ARM"
        )
    end
)

makeAction(
    "SCAN USE IT\nNOW",
    0.5,
    function()
        local _,_,button =
            findMysteriousForceUi()

        scanUseButtonCallbacks(
            button
        )
    end
)

makeAction(
    "CLEAR LOG",
    0.75,
    function()
        logs = {}
        flush()
        refreshLog()
        log("LOG", "cleared")
    end
)

-- ============================================================
-- MOVABLE + RESIZABLE WINDOW
-- ============================================================
local dragging = false
local resizing = false
local dragStart
local startPos
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
            startPos =
                Frame.Position
        end
    end
)

local Resize =
    Instance.new("TextButton")

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
Resize.ZIndex = 30
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
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
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
                        startSize.X + delta.X,
                        500,
                        1200
                    ),
                    math.clamp(
                        startSize.Y + delta.Y,
                        320,
                        850
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
-- ARM DISPLAY
-- ============================================================
ArmLabel =
    Instance.new("TextLabel")

ArmLabel.BackgroundTransparency = 1
ArmLabel.AnchorPoint =
    Vector2.new(1,0)

ArmLabel.Position =
    UDim2.new(
        1,
        -12,
        0,
        7
    )

ArmLabel.Size =
    UDim2.fromOffset(
        155,
        28
    )

ArmLabel.Font =
    Enum.Font.Code

ArmLabel.TextSize = 11
ArmLabel.TextXAlignment =
    Enum.TextXAlignment.Right

ArmLabel.TextColor3 =
    Color3.fromRGB(
        170,
        220,
        255
    )

ArmLabel.Text = "ARM: OFF"
ArmLabel.Parent = Frame

task.spawn(function()
    while Gui.Parent do
        task.wait(0.1)

        if armed() then
            ArmLabel.Text =
                "ARM: "
                .. string.format(
                    "%.1fs",
                    captureUntil
                        - os.clock()
                )

            ArmLabel.TextColor3 =
                Color3.fromRGB(
                    80,
                    255,
                    150
                )
        else
            ArmLabel.Text =
                "ARM: OFF"

            ArmLabel.TextColor3 =
                Color3.fromRGB(
                    170,
                    220,
                    255
                )
        end
    end
end)

-- ============================================================
-- START
-- ============================================================
log(
    "READY",
    "Remote Trace mặc định OFF để không chặn mở NPC menu."
)

log(
    "HOWTO",
    "1) UI WATCH ON -> tự bấm NPC để mở Mysterious Force."
)

log(
    "HOWTO",
    "2) Khi menu đã mở: bật 3 REMOTE TRACE, bấm ARM 10 SEC, rồi bấm Use it."
)

log(
    "HOWTO",
    "Nếu Remote Trace vẫn làm lỗi: tắt nó và dùng CALLBACK SCAN / SCAN USE IT NOW."
)
