--[[
MYSTERIOUS FORCE SAFE DEBUG V2
==============================
Mục tiêu:
- Không chặn NPC/menu khi tracer OFF.
- Từng bước có ON/OFF riêng.
- Bạn tự click NPC -> menu "Mysterious Force" -> tự bấm "Use it".
- Debugger KHÔNG tự gọi RaceV4Progress / requestEntrance.

STEP:
1 UI WATCH       : tìm menu Mysterious Force + nút Use it
2 CALLBACK SCAN  : đọc callback có sẵn của Use it (nếu executor hỗ trợ)
3 REMOTE TRACE   : trace InvokeServer/FireServer, mặc định OFF
4 HRP MONITOR    : xem teleport/jump tới Temple
5 ALL/ARM        : khi ARM, log mọi remote trong 10 giây

Cách test an toàn:
- Chạy script.
- ĐỂ "3 REMOTE TRACE" = OFF.
- Tự click NPC, mở được menu Mysterious Force.
- Sau khi menu mở: bật REMOTE TRACE.
- Bấm ARM 10 SEC.
- Bấm Use it.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
if not LP then
    warn("[MFDBG] no LocalPlayer")
    return
end

local Remotes = RS:FindFirstChild("Remotes") or RS:WaitForChild("Remotes", 20)
local CommF = Remotes and (Remotes:FindFirstChild("CommF_") or Remotes:WaitForChild("CommF_", 20))

local NPC_POS = Vector3.new(2959.87231, 2282.42139, -7216.23193)
local TEMPLE_POS = Vector3.new(28286.35546875, 14896.5078125, 102.62469482421875)

local LOG_FILE = "MYSTERIOUS_FORCE_SAFE_DEBUG_V2.txt"

local Flags = {
    uiWatch = true,
    callbackScan = false,
    remoteTrace = false,
    hrpMonitor = true,
    allDuringArm = true,
}

local logs = {}
local LogLabel
local Scroll
local ArmLabel

local captureUntil = 0
local traceInstalled = false
local oldNamecall = nil

-- queue để hook KHÔNG log trực tiếp trong __namecall
local remoteQueue = {}

local function getRoot()
    local c = LP.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")

    if c and h and r and h.Health > 0 then
        return c, h, r
    end
end

local function waitRoot(timeout)
    local deadline = os.clock() + (timeout or 15)

    repeat
        local c,h,r = getRoot()
        if r then
            return c,h,r
        end
        task.wait(0.1)
    until os.clock() >= deadline
end

local function distTo(pos)
    local _,_,r = getRoot()
    if not r then
        return math.huge
    end
    return (r.Position - pos).Magnitude
end

local function safeName(obj)
    if typeof(obj) ~= "Instance" then
        return tostring(obj)
    end

    local ok, name = pcall(function()
        return obj:GetFullName()
    end)

    return ok and name or obj.Name
end

local function render(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 2 then
        return "<depth>"
    end

    local t = typeof(v)

    if t == "Vector3" then
        return string.format(
            "Vector3.new(%.6f, %.6f, %.6f)",
            v.X, v.Y, v.Z
        )
    end

    if t == "CFrame" then
        local p = v.Position
        return string.format(
            "CFrame.new(%.6f, %.6f, %.6f)",
            p.X, p.Y, p.Z
        )
    end

    if t == "Instance" then
        return safeName(v)
    end

    if t == "string" then
        local s = v
        if #s > 220 then
            s = s:sub(1, 220) .. "..."
        end
        return string.format("%q", s)
    end

    if t == "table" then
        if seen[v] then
            return "<recursive>"
        end

        seen[v] = true

        local parts = {}
        local n = 0

        for k,val in pairs(v) do
            n += 1
            if n > 12 then
                parts[#parts+1] = "..."
                break
            end

            parts[#parts+1] =
                "[" .. render(k, depth+1, seen) .. "]="
                .. render(val, depth+1, seen)
        end

        seen[v] = nil
        return "{" .. table.concat(parts, ", ") .. "}"
    end

    return tostring(v)
end

local function copyArgs(...)
    local n = select("#", ...)
    local t = {n = n}

    for i = 1, n do
        t[i] = select(i, ...)
    end

    return t
end

local function argsText(args)
    local parts = {}

    for i = 1, args.n or 0 do
        parts[#parts+1] =
            tostring(i) .. "=" .. render(args[i])
    end

    return #parts > 0 and table.concat(parts, " | ") or "<no-args>"
end

local function flush()
    if type(writefile) == "function" then
        pcall(function()
            writefile(LOG_FILE, table.concat(logs, "\n"))
        end)
    end
end

local function refresh()
    if not LogLabel then
        return
    end

    local first = math.max(1, #logs - 120)
    local view = {}

    for i = first, #logs do
        view[#view+1] = logs[i]
    end

    LogLabel.Text = table.concat(view, "\n")

    task.defer(function()
        if Scroll then
            Scroll.CanvasPosition = Vector2.new(
                0,
                math.max(
                    0,
                    Scroll.AbsoluteCanvasSize.Y - Scroll.AbsoluteWindowSize.Y
                )
            )
        end
    end)
end

local function log(tag, msg)
    local line = string.format(
        "[%.3f][%s] %s",
        os.clock(),
        tostring(tag),
        tostring(msg)
    )

    logs[#logs+1] = line

    if #logs > 1000 then
        table.remove(logs, 1)
    end

    print("[MFDBG] " .. line)

    refresh()
    flush()
end

local function arm(seconds, reason)
    seconds = seconds or 10
    captureUntil = math.max(captureUntil, os.clock() + seconds)

    log(
        "ARM",
        tostring(seconds) .. "s | " .. tostring(reason)
    )
end

local function armed()
    return os.clock() <= captureUntil
end

-- ============================================================
-- UI FINDER
-- ============================================================
local PlayerGui = LP:WaitForChild("PlayerGui", 15)

local function textOf(obj)
    local ok, value = pcall(function()
        return tostring(obj.Text or "")
    end)

    return ok and value or ""
end

local function findMysteriousForce()
    if not PlayerGui then
        return nil,nil,nil
    end

    local title
    local body
    local use

    for _,obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local s = textOf(obj):lower()

            if s:find("mysterious force", 1, true) then
                title = obj

            elseif s:find("remnant of the past", 1, true) then
                body = obj

            elseif obj:IsA("TextButton")
                and s:find("use it", 1, true)
            then
                use = obj
            end
        end
    end

    return title, body, use
end

-- ============================================================
-- CALLBACK SCAN
-- ============================================================
local scannedUseButton = nil

local function inspectFunction(fn, label)
    if type(fn) ~= "function" then
        return
    end

    log("CALLBACK", label .. " = " .. tostring(fn))

    local gc = getconstants
    if type(gc) == "function" then
        local ok, constants = pcall(gc, fn)

        if ok and type(constants) == "table" then
            for i,v in ipairs(constants) do
                local low = tostring(v):lower()

                if low:find("race",1,true)
                    or low:find("teleport",1,true)
                    or low:find("entrance",1,true)
                    or low:find("temple",1,true)
                    or low:find("progress",1,true)
                    or low:find("begin",1,true)
                    or low:find("continue",1,true)
                    or low:find("check",1,true)
                then
                    log(
                        "CONST",
                        label .. "[" .. tostring(i) .. "]=" .. render(v)
                    )
                end
            end
        end
    end

    local gu = getupvalues
    if type(gu) == "function" then
        local ok, ups = pcall(gu, fn)

        if ok and type(ups) == "table" then
            for i,v in pairs(ups) do
                local r = render(v)
                local low = r:lower()

                if low:find("race",1,true)
                    or low:find("teleport",1,true)
                    or low:find("entrance",1,true)
                    or low:find("temple",1,true)
                then
                    log(
                        "UPVALUE",
                        label .. "[" .. tostring(i) .. "]=" .. r
                    )
                end
            end
        end
    end
end

local function scanButton(btn)
    if not btn then
        log("SCAN", "Use it button not found")
        return
    end

    local getConns = getconnections
    if type(getConns) ~= "function" then
        log("SCAN", "getconnections unavailable")
        return
    end

    log("SCAN", 'Use it = ' .. safeName(btn))

    local signals = {
        {"Activated", btn.Activated},
        {"MouseButton1Click", btn.MouseButton1Click},
        {"MouseButton1Down", btn.MouseButton1Down},
    }

    for _,entry in ipairs(signals) do
        local signalName = entry[1]
        local signal = entry[2]

        local ok, conns = pcall(getConns, signal)

        if ok and type(conns) == "table" then
            log(
                "SCAN",
                signalName .. " connections=" .. tostring(#conns)
            )

            for i,conn in ipairs(conns) do
                local fn = nil

                pcall(function()
                    fn = conn.Function
                end)

                if type(fn) == "function" then
                    inspectFunction(
                        fn,
                        signalName .. "#" .. tostring(i)
                    )
                end
            end
        end
    end
end

-- ============================================================
-- REMOTE TRACE
-- ultra-light hook: chỉ queue rồi pass-through ngay
-- ============================================================
local function relevantRemote(self, args)
    if self == CommF then
        return true
    end

    local n = ""
    pcall(function()
        n = tostring(self.Name or ""):lower()
    end)

    if n:find("race",1,true)
        or n:find("dialog",1,true)
        or n:find("temple",1,true)
    then
        return true
    end

    for i = 1, args.n or 0 do
        local s = tostring(args[i]):lower()

        if s:find("racev4",1,true)
            or s:find("teleport",1,true)
            or s:find("entrance",1,true)
            or s:find("temple",1,true)
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

    local hm = hookmetamethod
    local gn = getnamecallmethod
    local nc = newcclosure

    if type(hm) ~= "function"
        or type(gn) ~= "function"
    then
        log(
            "TRACE",
            "executor thiếu hookmetamethod/getnamecallmethod"
        )
        return false
    end

    if type(nc) ~= "function" then
        nc = function(f)
            return f
        end
    end

    local ok, err = pcall(function()
        oldNamecall = hm(
            game,
            "__namecall",
            nc(function(self, ...)
                local method = gn()

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

                local args = copyArgs(...)

                if relevantRemote(self, args)
                    or (
                        Flags.allDuringArm
                        and armed()
                    )
                then
                    -- Chỉ queue dữ liệu thô, KHÔNG print/UI/writefile trong hook.
                    remoteQueue[#remoteQueue+1] = {
                        method = method,
                        remote = self,
                        args = args,
                        time = os.clock(),
                    }
                end

                -- pass-through ngay lập tức
                return oldNamecall(self, ...)
            end)
        )
    end)

    if not ok then
        log(
            "TRACE",
            "install failed: " .. tostring(err)
        )
        return false
    end

    traceInstalled = true
    log("TRACE", "installed safely")
    return true
end

-- drain queue ngoài hook
task.spawn(function()
    while true do
        task.wait(0.03)

        if #remoteQueue > 0 then
            local queue = remoteQueue
            remoteQueue = {}

            for _,item in ipairs(queue) do
                local remoteName = safeName(item.remote)

                log(
                    "REMOTE",
                    item.method
                    .. " "
                    .. remoteName
                    .. " | "
                    .. argsText(item.args)
                )
            end
        end
    end
end)

-- ============================================================
-- UI WATCH
-- ============================================================
local lastMenu = false
local lastUse = nil

task.spawn(function()
    while true do
        task.wait(0.2)

        if Flags.uiWatch then
            local title, body, use = findMysteriousForce()

            local open =
                title ~= nil
                or body ~= nil
                or use ~= nil

            if open and not lastMenu then
                log(
                    "UI",
                    "Mysterious Force menu OPEN"
                )
            elseif not open and lastMenu then
                log(
                    "UI",
                    "Mysterious Force menu CLOSED"
                )
            end

            lastMenu = open

            if use and use ~= lastUse then
                lastUse = use

                log(
                    "UI",
                    '"Use it" FOUND | ' .. safeName(use)
                )

                if Flags.callbackScan
                    and scannedUseButton ~= use
                then
                    scannedUseButton = use

                    task.defer(function()
                        scanButton(use)
                    end)
                end
            end
        end
    end
end)

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
                local p = root.Position
                local td = (p - TEMPLE_POS).Magnitude

                if lastPos then
                    local jump =
                        (p - lastPos).Magnitude

                    if jump >= 120 then
                        log(
                            "HRP",
                            "JUMP "
                            .. string.format("%.1f", jump)
                            .. " | "
                            .. render(lastPos)
                            .. " -> "
                            .. render(p)
                            .. " | TempleDist="
                            .. string.format("%.2f", td)
                        )
                    end
                end

                local nowTemple = td <= 100

                if nowTemple and not inTemple then
                    log(
                        "TEMPLE",
                        "ARRIVED | "
                        .. render(p)
                        .. " | dist="
                        .. string.format("%.3f", td)
                    )
                end

                inTemple = nowTemple
                lastPos = p
            end
        else
            lastPos = nil
            inTemple = false
        end
    end
end)

-- ============================================================
-- GUI
-- ============================================================
local parent = CoreGui
pcall(function()
    if type(gethui) == "function" then
        parent = gethui()
    end
end)

local old = parent:FindFirstChild("MFSafeDebugV2")
if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFSafeDebugV2"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(760, 460)
Frame.Position = UDim2.new(0.5,-380,0.5,-230)
Frame.BackgroundColor3 = Color3.fromRGB(18,21,29)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = Gui

local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(0,10)
fc.Parent = Frame

local Header = Instance.new("TextLabel")
Header.BackgroundTransparency = 1
Header.Position = UDim2.fromOffset(12,7)
Header.Size = UDim2.new(1,-180,0,28)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1,1,1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text = "MYSTERIOUS FORCE SAFE DEBUG V2"
Header.Active = true
Header.Parent = Frame

ArmLabel = Instance.new("TextLabel")
ArmLabel.BackgroundTransparency = 1
ArmLabel.AnchorPoint = Vector2.new(1,0)
ArmLabel.Position = UDim2.new(1,-12,0,7)
ArmLabel.Size = UDim2.fromOffset(155,28)
ArmLabel.Font = Enum.Font.Code
ArmLabel.TextSize = 11
ArmLabel.TextXAlignment = Enum.TextXAlignment.Right
ArmLabel.TextColor3 = Color3.fromRGB(170,220,255)
ArmLabel.Text = "ARM: OFF"
ArmLabel.Parent = Frame

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12,42)
Scroll.Size = UDim2.new(1,-24,1,-155)
Scroll.BackgroundColor3 = Color3.fromRGB(8,11,17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 7
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0,0,0,0)
Scroll.Parent = Frame

LogLabel = Instance.new("TextLabel")
LogLabel.BackgroundTransparency = 1
LogLabel.Position = UDim2.fromOffset(7,5)
LogLabel.Size = UDim2.new(1,-14,0,0)
LogLabel.AutomaticSize = Enum.AutomaticSize.Y
LogLabel.Font = Enum.Font.Code
LogLabel.TextSize = 11
LogLabel.TextColor3 = Color3.fromRGB(215,225,240)
LogLabel.TextWrapped = true
LogLabel.TextXAlignment = Enum.TextXAlignment.Left
LogLabel.TextYAlignment = Enum.TextYAlignment.Top
LogLabel.Text = ""
LogLabel.Parent = Scroll

local toggleRefs = {}

local function toggleVisual(btn, key, label)
    local on = Flags[key]

    btn.Text =
        label .. "\n" .. (on and "ON" or "OFF")

    btn.BackgroundColor3 =
        on
        and Color3.fromRGB(42,92,70)
        or Color3.fromRGB(65,45,55)
end

local function makeToggle(key, label, x)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(0,1)
    b.Position = UDim2.new(x,8,1,-72)
    b.Size = UDim2.new(0.195,-10,0,52)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextWrapped = true
    b.TextColor3 = Color3.new(1,1,1)
    b.Parent = Frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,7)
    c.Parent = b

    b.MouseButton1Click:Connect(function()
        if key == "remoteTrace" and not traceInstalled then
            local ok = installTrace()
            if not ok then
                Flags.remoteTrace = false
                toggleVisual(b,key,label)
                return
            end
        end

        Flags[key] = not Flags[key]

        toggleVisual(b,key,label)

        log(
            "TOGGLE",
            label .. "=" .. tostring(Flags[key])
        )
    end)

    toggleRefs[key] = b
    toggleVisual(b,key,label)
end

makeToggle("uiWatch", "1 UI WATCH", 0)
makeToggle("callbackScan", "2 CALLBACK SCAN", 0.2)
makeToggle("remoteTrace", "3 REMOTE TRACE", 0.4)
makeToggle("hrpMonitor", "4 HRP MONITOR", 0.6)
makeToggle("allDuringArm", "5 ALL/ARM", 0.8)

local function action(text, x, cb)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(0,1)
    b.Position = UDim2.new(x,8,1,-12)
    b.Size = UDim2.new(0.24,-10,0,48)
    b.BackgroundColor3 = Color3.fromRGB(40,47,64)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextWrapped = true
    b.TextColor3 = Color3.new(1,1,1)
    b.Text = text
    b.Parent = Frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,7)
    c.Parent = b

    b.MouseButton1Click:Connect(cb)
end

action("GO TO NPC\n(no remote)", 0, function()
    local _,_,root = waitRoot(10)

    if not root then
        log("MOVE","HRP not ready")
        return
    end

    local before = (root.Position - NPC_POS).Magnitude

    root.CFrame =
        CFrame.new(
            NPC_POS + Vector3.new(0,3,0)
        )

    task.wait(0.15)

    log(
        "MOVE",
        "before="
        .. string.format("%.1f",before)
        .. " after="
        .. string.format("%.1f",distTo(NPC_POS))
    )
end)

action("ARM\n10 SEC", 0.25, function()
    arm(10,"manual")
end)

action("SCAN USE IT\nNOW", 0.5, function()
    local _,_,btn = findMysteriousForce()
    scanButton(btn)
end)

action("CLEAR LOG", 0.75, function()
    logs = {}
    flush()
    refresh()
    log("LOG","cleared")
end)

-- drag + resize
local dragging = false
local resizing = false
local dragStart
local startPos
local resizeStart
local startSize

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = true
        dragStart = input.Position
        startPos = Frame.Position
    end
end)

local Resize = Instance.new("TextButton")
Resize.AnchorPoint = Vector2.new(1,1)
Resize.Position = UDim2.new(1,-3,1,-3)
Resize.Size = UDim2.fromOffset(24,24)
Resize.BackgroundColor3 = Color3.fromRGB(70,80,105)
Resize.BorderSizePixel = 0
Resize.Text = "↘"
Resize.TextColor3 = Color3.new(1,1,1)
Resize.TextSize = 13
Resize.ZIndex = 30
Resize.Parent = Frame

Resize.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        resizing = true
        resizeStart = input.Position
        startSize = Frame.AbsoluteSize
    end
end)

UIS.InputChanged:Connect(function(input)
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

    elseif resizing
        and (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        )
    then
        local d = input.Position - resizeStart

        Frame.Size =
            UDim2.fromOffset(
                math.clamp(startSize.X + d.X,500,1200),
                math.clamp(startSize.Y + d.Y,320,850)
            )
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = false
        resizing = false
    end
end)

task.spawn(function()
    while Gui.Parent do
        task.wait(0.1)

        if armed() then
            ArmLabel.Text =
                "ARM: "
                .. string.format("%.1fs",captureUntil-os.clock())

            ArmLabel.TextColor3 =
                Color3.fromRGB(80,255,150)
        else
            ArmLabel.Text = "ARM: OFF"
            ArmLabel.TextColor3 =
                Color3.fromRGB(170,220,255)
        end
    end
end)

log(
    "READY",
    "Remote Trace OFF mặc định. Hãy mở NPC menu trước."
)

log(
    "HOWTO",
    "Menu mở -> bật REMOTE TRACE -> ARM 10s -> bấm Use it."
)

log(
    "HOWTO",
    "Nếu REMOTE TRACE vẫn gây lỗi: để OFF, bật CALLBACK SCAN rồi bấm SCAN USE IT NOW."
)
