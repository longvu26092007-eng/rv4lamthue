--[[
================================================================================
 KaitunV4 — BẢN 2 (CLEAN ARCHITECTURE) — PORT ĐẦY ĐỦ HÀNH VI TỪ FILE A
================================================================================
 NGUYÊN TẮC: File A (KaitunV4(2).lua) là SOURCE OF TRUTH về hành vi.
 File này GIỮ kiến trúc module sạch của bản 2, nhưng RUỘT (logic) lấy y chang
 File A — cùng luồng, cùng điều kiện, cùng cách đọc/ghi file sync, cùng cách
 active ability (CommE:FireServer("ActivateAbility")), cùng trial/training/
 post-trial. Chỉ KHÁC ở chỗ: code gọn hơn, ít lỗi hơn, hot-path không HTTP,
 mọi InvokeServer quan trọng có timeout, không WaitForChild vô hạn, không tween
 leak, không spawn loop trong mỗi tick, mọi loop nền check Runtime.alive.

 NGUỒN TRỌNG TÀI: /curmain (server-side) chốt thứ tự main cho MỌI account.
 ĐỒNG BỘ ABILITY: file-based trong folder racev4_vunguyen/ (giờ Hà Nội UTC+7) —
 GIỐNG HỆT File A (KHÔNG dùng /firesignal /donedoor).
================================================================================
]]

--[[ ============================================================================
 [00] SERVICES
============================================================================ ]]
local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local TeleportService      = game:GetService("TeleportService")
local HttpService          = game:GetService("HttpService")
local Lighting             = game:GetService("Lighting")
local TweenService         = game:GetService("TweenService")
local VirtualInputManager  = game:GetService("VirtualInputManager")
local VirtualUser          = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer   -- có thể nil nếu executor inject trước khi player replicate (Ally2 load chậm)

--[[ ============================================================================
 [01] BOOTSTRAP — chờ client load, KHÔNG treo vô hạn (timeout 30s). (File A 5-12)
============================================================================ ]]
do
    if not game:IsLoaded() then game.Loaded:Wait() end
    local t0 = tick()
    repeat
        task.wait(0.1)
        -- FIX (user 2026-07-02): LocalPlayer cache ở trên có thể nil khi inject sớm → PHẢI gán lại
        -- CHÍNH biến module-level (trước đây chỉ gán vào biến 'lp' cục bộ → LocalPlayer kẹt nil vĩnh viễn
        -- → crash :99 LocalPlayer.Name, :850 OnTeleport). Refresh mỗi vòng cho tới khi có.
        LocalPlayer = Players.LocalPlayer or LocalPlayer
        local rem  = ReplicatedStorage:FindFirstChild("Remotes")
        local gui  = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        local loadingScreen = gui and gui:FindFirstChild("LoadingScreen")
        if rem and LocalPlayer and gui and not loadingScreen then break end
    until (tick() - t0) > 30
    -- Chốt chặn cuối: KHÔNG cho chạy tiếp với LocalPlayer nil (nếu timeout mà vẫn chưa có → chờ dứt điểm).
    -- Poll thuần Players.LocalPlayer (KHÔNG dùng PlayerAdded:Wait vì nó trả player bất kỳ, không chắc là mình).
    while not LocalPlayer do
        task.wait(0.2)
        LocalPlayer = Players.LocalPlayer
    end
end

--[[ ============================================================================
 [02] CONFIG — sanitize + validate. CHỈ module này được sửa Config. (File A 46-60)
============================================================================ ]]
local Config = {}
do
    if not getgenv().Config then
        getgenv().Config = {
            ["Allies"]              = { LocalPlayer.Name },
            ["MainAccount"]         = { LocalPlayer.Name },
            ["Method"]              = "Kill Players After Trial",
            ["ResetAfterTrial"]     = true,
            ["Team"]                = "Marines",
            ["Gear"]                = "A-B-B",
            ["VIPServer"]           = false,
            ["Kick Moon"]           = true,
            ["Hop Server FullMoon"] = true,
        }
    end
    local raw = getgenv().Config

    -- File A: Gear phải đúng "X-Y-Z" (5 ký tự). Sai → "A-B-B".
    if not raw["Gear"] or #tostring(raw["Gear"]) ~= 5 then raw["Gear"] = "A-B-B" end

    local function cleanList(t)
        local out = {}
        for _, v in ipairs(t or {}) do
            if type(v) == "string" and v ~= "" then table.insert(out, v) end
        end
        return out
    end
    raw["Allies"]      = cleanList(raw["Allies"])
    raw["MainAccount"] = cleanList(raw["MainAccount"])
    if #raw["Allies"] == 0 then raw["Allies"] = { LocalPlayer.Name } end
    if #raw["MainAccount"] == 0 then raw["MainAccount"] = { LocalPlayer.Name } end

    -- File A 315: Team chỉ Marines/Pirates, mặc định Marines.
    if raw["Team"] ~= "Marines" and raw["Team"] ~= "Pirates" then raw["Team"] = "Marines" end

    Config.raw             = raw
    Config.allies          = raw["Allies"]
    Config.mains           = raw["MainAccount"]
    Config.team            = raw["Team"]
    Config.gear            = raw["Gear"]
    Config.method          = raw["Method"] or "Kill Players After Trial"
    Config.resetAfterTrial = raw["ResetAfterTrial"] ~= false
    Config.vipServer       = raw["VIPServer"] == true
    Config.kickMoon        = raw["Kick Moon"] ~= false
    Config.hopFullMoon     = raw["Hop Server FullMoon"] ~= false
    -- File A 65: mặc định server LOCAL.
    Config.baseUrl         = getgenv().API_URL or "http://127.0.0.1:20425"
    Config.myName          = LocalPlayer.Name

    -- File A 16-17
    Config.SEA3_PLACEIDS = { [7449423635] = true, [100117331123089] = true }
    Config.SEA2_PLACEIDS = { [4442272183] = true, [79091703265657] = true }

    -- hằng số nhịp (gom 1 chỗ cho dễ chỉnh)
    Config.HOP_THROTTLE       = 5      -- File A TeleportManager throttle jobid
    Config.JOB_REVISIT_TTL    = 3600   -- File A 2185
    Config.FULLMOON_TTL       = 5      -- File A 2159
    Config.STATUS_TTL         = 3      -- File A 319
    Config.CURMAIN_INTERVAL   = 0.7    -- File A 517
    Config.HEARTBEAT_INTERVAL = 5      -- File A 388-396
    Config.MAIN_TICK          = 0.35   -- File A 1678
    Config.UI_THROTTLE        = 0.2    -- File A live status 0.2s
    Config.DEAD_JOB_TTL       = 1800   -- File A 2175
    Config.MAIN_TURN_TIMEOUT  = 300    -- File A 1752
    Config.TRAIN_WINDOW       = 300    -- File A 1612
    Config.HELPRESET_TIMEOUT  = 25     -- File A 2005
    -- CLEAN JOIN: fullmoon-join LUÔN do server + 2 Ally điều phối (bỏ tự-hop). Method chỉ là hành vi sau trial.
    Config.scout              = true
    Config.RALLY_HOP_THROTTLE = 5      -- giây: chống spam teleport tới 1 jobid
end

--[[ ============================================================================
 [02b] URL/QUERY HELPER + nonEmpty — encode query an toàn; chuẩn hoá jobid từ server.
============================================================================ ]]
local function urlEncode(v)
    return HttpService:UrlEncode(tostring(v or ""))
end
local function makeQuery(params)
    local parts = {}
    for k, v in pairs(params or {}) do
        table.insert(parts, urlEncode(k) .. "=" .. urlEncode(v))
    end
    return table.concat(parts, "&")
end
local function endpoint(path, params)
    if params then
        return Config.baseUrl .. path .. "?" .. makeQuery(params)
    end
    return Config.baseUrl .. path
end
local function nonEmpty(v)
    v = tostring(v or "")
    if v == "" or v == "nil" or v == "null" then return nil end
    return v
end

--[[ ============================================================================
 [03] LOGGER / DEBUG — ring buffer 200 dòng, chống spam cùng key 15s. (File A 1331-1368)
============================================================================ ]]
local Logger = {}
do
    Logger.logs = {}
    _G.dbgLog   = Logger.logs
    _G.dbgSeq   = 0
    Logger._lastKey = {}
    local MAX, SPAM_TTL = 200, 15

    -- giờ: mặc định os.time; ServerSync gắn clock server sau khi init (serverNow).
    Logger.timeFn = function() return (os and os.time and os.time()) or tick() end

    function Logger.log(msg, level, key)
        level = level or "info"
        key   = key or tostring(msg)
        local t = tick()
        if Logger._lastKey[key] and (t - Logger._lastKey[key]) < SPAM_TTL then return end
        Logger._lastKey[key] = t
        _G.dbgSeq = _G.dbgSeq + 1
        local hm = "--:--:--"
        pcall(function()
            local base = Logger.timeFn()
            local s = math.floor(base + 7 * 3600) % 86400   -- giờ Việt Nam (UTC+7)
            hm = string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
        end)
        Logger.logs[#Logger.logs + 1] = { seq = _G.dbgSeq, text = "[" .. hm .. "] " .. tostring(msg), level = level }
        while #Logger.logs > MAX do table.remove(Logger.logs, 1) end
        if level == "err" or level == "warn" then warn("[KaitunV4] " .. tostring(msg)) end
    end
    function Logger.info(m, k) Logger.log(m, "info", k) end
    function Logger.ok(m, k)   Logger.log(m, "ok", k) end
    function Logger.warn(m, k) Logger.log(m, "warn", k) end
    function Logger.err(m, k)  Logger.log(m, "err", k) end
end

-- DBG/status: tương thích tên File A (một số chỗ port giữ nguyên cách gọi).
local function DBG(msg, level, key) Logger.log(msg, level, key) end

--[[ ============================================================================
 [04] RUNTIME / LIFECYCLE — alive flag, teleport guard, offline-once. (File A 362-456)
============================================================================ ]]
local Runtime = {
    alive        = true,
    teleporting  = false,
    startedAt    = tick(),
    _offlineSent = false,
    _started     = false,
}
function Runtime.stop(reason)
    Runtime.alive = false
    Logger.warn("Runtime.stop: " .. tostring(reason), "runtime_stop")
end

--[[ ============================================================================
 [05] STATUS — _G.statusnow + đẩy vào Debug log (File A 1357-1368)
============================================================================ ]]
local function status(v)
    _G.statusnow = tostring(v)
        .. ((_G.lastRaceI ~= nil) and ("  [i=" .. tostring(_G.lastRaceI) .. "]") or "")
        .. ((_G.lastDoorDist ~= nil) and ("  [d=" .. tostring(math.floor(_G.lastDoorDist))
            .. (_G.lastDoorSrc or "?") .. (_G.lastSameSrv and "/same" or "/diff") .. "]") or "")
    local sv = tostring(v)
    local lvl = "info"
    if sv:find("Lỗi") or sv:find("⚠") or sv:find("FAIL") or sv:find("Died") then lvl = "err"
    elseif sv:find("Doing trial") or sv:find("DONE") or sv:find("Ready") or sv:find("Kill Players") then lvl = "ok" end
    DBG(sv, lvl, sv)
end

--[[ ============================================================================
 [06] FILESTORE — read/write JSON an toàn, reset file khi decode fail.
============================================================================ ]]
local FileStore = {}
function FileStore.readJson(path, default)
    if not (isfile and isfile(path)) then return default end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok and type(data) == "table" then return data end
    pcall(function() writefile(path, "{}") end)
    Logger.warn("FileStore decode fail, reset: " .. path, "fs_reset_" .. path)
    return default
end
function FileStore.writeJson(path, tbl)
    local ok = pcall(function() writefile(path, HttpService:JSONEncode(tbl or {})) end)
    if not ok then Logger.err("FileStore write fail: " .. path, "fs_write_" .. path) end
    return ok
end

--[[ ============================================================================
[06b] CHANGEFOLDER — gọi getgenv().client:ChangeToFolder khi main DONE.
     Config ngoài loader:
         getgenv().change = true|false   (bật/tắt)
         getgenv().id1 = "..."            (bắt buộc)
         getgenv().id2 = "..."            (bắt buộc)
         getgenv().id3 = "..." | "........." | "nil"   (optional, truyền nil nếu trống)
     Lock + cooldown chống spam; success → Disconnect + Shutdown.
============================================================================ ]]
local Hooks = {}   -- BS-6: expose nội bộ (thay cho _G) — StateMachine gọi Hooks.ChangeFolderAfterCompleted
do
    -- lock chống gọi ChangeToFolder trùng lặp
    local _ChangeFolderLock          = false
    local _LastChangeFolderFailAt    = 0
    local _ChangeFolderRetryCooldown = 10

    -- id3 optional: bỏ trống / "........." / "nil" → trả về nil THẬT
    local function NormalizeFolderId(value, allowNil)
        if value == nil then
            return (allowNil and nil or nil), false
        end

        local s = tostring(value)
        s = s:gsub("^%s+", ""):gsub("%s+$", "")

        if s == "" or s == "........." or s:match("^%.+$") then
            return (allowNil and nil or nil), false
        end

        if s:lower() == "nil" then
            return (allowNil and nil or nil), false
        end

        return s, true
    end

    local function ChangeFolderAfterCompleted(reason)
        if not getgenv().change then return false end
        if _ChangeFolderLock then return false end

        if _LastChangeFolderFailAt > 0
            and (tick() - _LastChangeFolderFailAt) < _ChangeFolderRetryCooldown then
            return false
        end

        local client = getgenv().client
        if type(client) ~= "table" and type(client) ~= "userdata" then
            warn("[ChangeFolder] getgenv().client không tồn tại")
            _LastChangeFolderFailAt = tick()
            return false
        end

        if type(client.ChangeToFolder) ~= "function" then
            warn("[ChangeFolder] getgenv().client:ChangeToFolder không tồn tại")
            _LastChangeFolderFailAt = tick()
            return false
        end

        local id1, ok1 = NormalizeFolderId(getgenv().id1, false)
        local id2, ok2 = NormalizeFolderId(getgenv().id2, false)
        local id3      = NormalizeFolderId(getgenv().id3, true)

        if not ok1 or not ok2 then
            warn("[ChangeFolder] Thiếu id1/id2, không gọi ChangeToFolder")
            _LastChangeFolderFailAt = tick()
            return false
        end

        _ChangeFolderLock = true

        warn("[ChangeFolder] Completed -> gọi ChangeToFolder, reason=" .. tostring(reason))

        pcall(function()
            status("[ChangeFolder] Completed -> changing folder...")
        end)

        local ok, ret = pcall(function()
            return client:ChangeToFolder(id1, id2, true, id3)
        end)

        if not ok then
            warn("[ChangeFolder] Lỗi khi gọi ChangeToFolder: " .. tostring(ret))
            pcall(function()
                status("[ChangeFolder] Failed, retry later")
            end)
            _ChangeFolderLock = false
            _LastChangeFolderFailAt = tick()
            return false
        end

        local changed = ret and true or false

        if changed then
            warn("[ChangeFolder] Successfully changed folder, disconnecting to apply changes...")
            pcall(function()
                status("[ChangeFolder] Changed folder -> shutdown")
            end)

            pcall(function()
                if getgenv().client and type(getgenv().client.Disconnect) == "function" then
                    getgenv().client:Disconnect()
                end
            end)

            task.wait(5)

            pcall(function()
                game:Shutdown()
            end)

            return true
        else
            warn("[ChangeFolder] Failed to change folder")
            pcall(function()
                status("[ChangeFolder] Failed, retry later")
            end)
            _ChangeFolderLock = false
            _LastChangeFolderFailAt = tick()
            task.wait(10)
            return false
        end
    end

    -- BS-6: expose qua Hooks (KHÔNG dùng _G) — chỉ trong file
    Hooks.ChangeFolderAfterCompleted = ChangeFolderAfterCompleted
    Hooks.NormalizeFolderId          = NormalizeFolderId
end

-- File A 1-3: xoá cache module cũ (giờ module nhúng thẳng).
pcall(function()
    if isfile and isfile("kaitun_module_bf.lua") and delfile then delfile("kaitun_module_bf.lua") end
end)

--[[ ============================================================================
 [07] NETCLIENT — production HTTP: semaphore GET/POST riêng, retry, cache,
      POST queue O(1) qHead/qTail + coalesce theo key. (File A 75-257)
============================================================================ ]]
local Net = {}
do
    local httprequest = (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
        or (fluxus and fluxus.request)
        or (krnl and krnl.request)
    Net.hasReq = httprequest ~= nil

    Net.logs = {}
    function Net.log(level, msg)
        local line = ("[NET][%s] %s"):format(level, tostring(msg))
        table.insert(Net.logs, line)
        if #Net.logs > 200 then table.remove(Net.logs, 1) end
        if level == "ERR" or level == "WARN" then Logger.warn(line, "net_" .. line:sub(1, 24)) end
    end

    -- 2 semaphore RIÊNG cho GET và POST (File A 97-112)
    local function makeSem(max)
        local cur = 0
        local function acquire()
            local guard = 0
            while cur >= max do
                task.wait(0.03)
                guard = guard + 1
                if guard > 400 then break end -- ~12s thì thôi chờ
            end
            cur = cur + 1
        end
        local function release() cur = math.max(0, cur - 1) end
        return acquire, release
    end
    local acquireGet, releaseGet   = makeSem(4)
    local acquirePost, releasePost = makeSem(4)

    -- request thô: trả ok(bool), status(number), body(string), err (File A 115-143)
    local function rawRequest(method, url, bodyStr)
        if httprequest then
            local res
            local ok, err = pcall(function()
                res = httprequest({
                    Url = url,
                    Method = method,
                    Headers = (method == "POST") and { ["Content-Type"] = "application/json" } or nil,
                    Body = (method == "POST") and bodyStr or nil,
                })
            end)
            if not ok then return false, 0, nil, tostring(err) end
            if type(res) ~= "table" then return false, 0, nil, "no response table" end
            local code = res.StatusCode or res.status_code or res.Status or 0
            local body = res.Body or res.body
            local success = res.Success
            if success == nil then success = (code >= 200 and code < 300) end
            if success then return true, code, body, nil end
            return false, code, body, "http " .. tostring(code)
        else
            if method ~= "GET" then return false, 0, nil, "executor không có hàm request cho POST" end
            local body
            local ok, err = pcall(function() body = game:HttpGet(url) end)
            if ok and body then return true, 200, body, nil end
            return false, 0, nil, tostring(err)
        end
    end
    Net.raw = rawRequest

    -- GET đồng bộ + retry + cache (File A 145-186)
    local cache = {}
    local GET_RETRIES = 3
    function Net.getRaw(url)
        acquireGet()
        local ok, status_, body, err
        for attempt = 1, GET_RETRIES do
            ok, status_, body, err = rawRequest("GET", url, nil)
            if ok then break end
            Net.log("WARN", ("GET fail %d/%d %s : %s"):format(attempt, GET_RETRIES, url, tostring(err)))
            task.wait(0.2 * attempt)
        end
        releaseGet()
        if not ok then Net.log("ERR", "GET bỏ cuộc: " .. url) end
        return ok, body, status_
    end
    function Net.getJSON(url, ttl)
        ttl = ttl or 0
        if ttl > 0 then
            local c = cache[url]
            if c and c.decoded ~= nil and (tick() - c.t) < ttl then return c.decoded end
        end
        local ok, body = Net.getRaw(url)
        if not ok or not body then return nil end
        local good, decoded = pcall(function() return HttpService:JSONDecode(body) end)
        if not good then Net.log("ERR", "JSON decode fail: " .. url); return nil end
        if ttl > 0 then cache[url] = { t = tick(), decoded = decoded } end
        return decoded
    end
    function Net.text(url, ttl)
        ttl = ttl or 0
        if ttl > 0 then
            local c = cache[url]
            if c and c.raw ~= nil and (tick() - c.t) < ttl then return c.raw end
        end
        local ok, body = Net.getRaw(url)
        if not ok then return nil end
        if ttl > 0 then cache[url] = { t = tick(), raw = body } end
        return body
    end

    -- POST: hàng đợi VÒNG O(1) qHead/qTail + worker + retry + coalesce (File A 191-252)
    local postQ = {}
    local qHead = 1   -- vị trí job kế tiếp sẽ lấy
    local qTail = 0   -- vị trí job cuối đã thêm
    local keyed = {}  -- key -> job mới nhất
    local MAX_Q = 800
    local POST_RETRIES = 6
    local function qPush(job)
        qTail = qTail + 1
        postQ[qTail] = job
    end
    local function qPop()
        if qHead > qTail then return nil end
        local job = postQ[qHead]
        postQ[qHead] = nil
        qHead = qHead + 1
        if qHead > qTail then qHead, qTail = 1, 0 end -- reset index khi rỗng → không phình
        return job
    end
    function Net.postJSON(url, tbl, key)
        local bodyStr
        local ok = pcall(function() bodyStr = HttpService:JSONEncode(tbl or {}) end)
        if not ok then Net.log("ERR", "JSON encode fail: " .. url); return end
        local job = { url = url, body = bodyStr, key = key, attempts = 0 }
        if key then
            local old = keyed[key]
            if old then old.replaced = true end -- bỏ job cũ cùng key → chỉ gửi dữ liệu mới nhất
            keyed[key] = job
        end
        if (qTail - qHead + 1) >= MAX_Q then
            qPop()
            Net.log("WARN", "postQ tràn, bỏ job cũ nhất")
        end
        qPush(job)
    end

    local function worker()
        while Runtime.alive do
            local job = qPop()
            if not job or job.replaced then
                task.wait(0.05)
            else
                acquirePost()
                local sok, _, _, err = rawRequest("POST", job.url, job.body)
                releasePost()
                if sok then
                    if job.key and keyed[job.key] == job then keyed[job.key] = nil end
                else
                    job.attempts = job.attempts + 1
                    if (not job.replaced) and job.attempts < POST_RETRIES then
                        Net.log("WARN", ("POST retry %d/%d %s : %s"):format(job.attempts, POST_RETRIES, job.url, tostring(err)))
                        task.wait(0.3 * job.attempts)
                        qPush(job)
                    elseif not job.replaced then
                        Net.log("ERR", ("POST bỏ sau %d lần: %s"):format(job.attempts, job.url))
                        if job.key and keyed[job.key] == job then keyed[job.key] = nil end
                    end
                end
            end
        end
    end
    for _ = 1, 4 do task.spawn(worker) end

    Net.log("INFO", "Net init — hasReq=" .. tostring(Net.hasReq))
end

--[[ ============================================================================
 [08] STATESTORE — status/job cache (hot-path cache-only), role info. (File A 259-359)
============================================================================ ]]
local State = {}
do
    State.myName          = Config.myName
    State.myRole          = "unknown"
    State.myMainIndex     = nil
    State.isAlly          = {}
    State.isMain          = {}     -- = isaccmain File A
    State.mainIndexOf     = {}
    State.statusCache     = {}     -- name -> { t, status }  (File A 318)
    State.mainJobCache    = {}     -- name -> { jobid, time, t } (File A 460)
    State.serverMainOrder = nil    -- _G.srvMainOrder
    State.serverCurMain   = nil    -- _G.srvCurMain
    State.serverCurJobid  = nil    -- _G.srvCurMainJobid
    State._lastCurMainOK  = 0
    -- CLEAN JOIN: field điều hướng do server /curmain trả
    State.fullmoonLocked    = false
    State.gateOpenedOnce    = false
    State.gateOpen          = false
    State.trialPhase        = "idle"
    State.fullmoonJobid     = nil
    State.allyTargetJobid   = nil
    State.main1Name         = nil
    State.requiredAllies    = 2
    State.fullmoonAllyCount = 0
    State.candidateAllyCount= 0
    State.joinSpamInterval  = 5
    State.mainJoinTimeout   = 45
    State.partyOrder        = {}
    State.allyLeader        = nil
    State.lastScoutSignalAt = 0
    -- CLEAN JOIN: chống "chưa trial đã done" — chỉ set done/training khi thật sự đã vào trial lượt này
    State.didEnterTrialThisTurn = false
    State.trialStartedAt        = 0
    State._lastCurrentMain      = nil  -- BS-5: theo dõi current đổi cycle

    for _, v in ipairs(Config.allies) do State.isAlly[v] = true end

    -- hot-path: KHÔNG gọi HTTP. cache trống → "waiting" (đúng File A 355-359).
    function State.getMainStatus(name)
        local c = State.statusCache[name]
        if c then return c.status end
        return "waiting"
    end

    -- POST mainstatus qua queue (retry). Cập nhật cache NGAY để logic dùng giá trị mới (File A 322-326).
    function State.setMyMainStatus(statusStr)
        if not State.myMainIndex then return end
        State.statusCache[State.myName] = { t = tick(), status = statusStr }
        Net.postJSON(endpoint("/mainstatus", { name = State.myName }), { status = statusStr }, "mainstatus")
    end
    -- Báo status cho BẤT KỲ account (kể cả ALLY — không cần myMainIndex). (File A 330-333)
    function State.reportStatus(statusStr)
        State.statusCache[State.myName] = { t = tick(), status = statusStr }
        Net.postJSON(endpoint("/mainstatus", { name = State.myName }), { status = statusStr }, "mainstatus")
    end
end

--[[ ============================================================================
 [09] SAFEREMOTE — InvokeServer trong thread con + timeout (chống yield treo). (File A 571-592)
============================================================================ ]]
local SafeRemote = {}
do
    local _commF
    local function resolve()
        local rem = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
        if not rem then return nil end
        return rem:FindFirstChild("CommF_") or rem:WaitForChild("CommF_", 10)
    end
    _commF = resolve()

    function SafeRemote.invoke(timeout, ...)
        if not _commF then _commF = resolve() end
        if not _commF then return false end
        local args = table.pack(...)
        local done, packed = false, nil
        task.spawn(function()
            packed = table.pack(pcall(function()
                return _commF:InvokeServer(table.unpack(args, 1, args.n))
            end))
            done = true
        end)
        local t0 = tick()
        while not done and (tick() - t0) < timeout do task.wait() end
        if not done or not packed then return false end
        return table.unpack(packed, 1, packed.n)
    end
end

--[[ ============================================================================
 [10] SERVERSYNC — /init, heartbeat(+fullmoon), offline, warmer /curmain (trọng tài),
      net probe, clock sync. (File A 281-313, 368-429, 477-519, 2397-2427)
============================================================================ ]]
local ServerSync = {}
do
    local B = Config.baseUrl

    -- clock sync (File A 2397-2422)
    ServerSync.clockOffset = nil
    function ServerSync.syncClock()
        local t0 = tick()
        local srv = tonumber(Net.text(B .. "/timeserver", 0))
        local t1 = tick()
        if srv then
            ServerSync.clockOffset = (srv + (t1 - t0) / 2) - t1
            return true
        end
        return false
    end
    function ServerSync.now()
        if ServerSync.clockOffset ~= nil then return tick() + ServerSync.clockOffset end
        local srv = tonumber(Net.text(B .. "/timeserver", 1))
        if srv then return srv end
        return (os and os.time and os.time()) or 0
    end
    Logger.timeFn = ServerSync.now

    -- /init: gộp identify + allmains 1 request, retry 8 lần (File A 283-313)
    function ServerSync.init()
        local allies_str = table.concat(Config.allies, ",")
        local mains_str  = table.concat(Config.mains, ",")
        local url = endpoint("/init", { name = Config.myName, allies = allies_str, mains = mains_str })
        local data
        for attempt = 1, 8 do
            data = Net.getJSON(url, 0)
            if data and data.role then break end
            Net.log("WARN", "/init thử lại " .. attempt .. "/8")
            task.wait(0.3 + 0.2 * attempt)
        end
        if data then
            State.myRole = data.role or "unknown"
            if State.myRole == "main" then
                State.myMainIndex = data.index
                State.isMain[Config.myName] = true
                State.mainIndexOf[Config.myName] = data.index
            end
            if data.mains then
                for _, v in ipairs(data.mains) do
                    if v.name and v.name ~= "" then
                        State.isMain[v.name] = true
                        State.mainIndexOf[v.name] = v.index
                    end
                end
            end
            Net.log("INFO", "/init OK role=" .. tostring(State.myRole) .. " index=" .. tostring(State.myMainIndex))
        else
            Net.log("ERR", "/init thất bại hoàn toàn — sẽ retry qua warmer")
        end
    end

    -- Heartbeat kèm cờ fullmoon (File A 368-373). isfullmoon là global khai báo dưới → pcall.
    function ServerSync.sendHeartbeat()
        if not Runtime.alive then return end
        local fm = false
        pcall(function() fm = _G.isfullmoon and _G.isfullmoon() and true or false end)
        local players, allies = 0, 0
        pcall(function() if _G.countServerInfo then players, allies = _G.countServerInfo() end end)
        Net.postJSON(endpoint("/heartbeat", { name = Config.myName }),
            { role = State.myRole, fullmoon = fm, players = players, allies = allies, scout = Config.scout == true }, "heartbeat")
    end

    -- Offline đúng 1 lần, gửi cả POST queue lẫn GET đồng bộ (File A 378-385)
    function ServerSync.sendOffline()
        if Runtime._offlineSent then return end
        Runtime._offlineSent = true
        -- BS-8: GỬI offline TRƯỚC, tắt runtime SAU (tránh worker loop thoát trước khi gửi kịp)
        local url = endpoint("/offline", { name = Config.myName })
        pcall(function()
            if Net.raw then
                Net.raw("POST", url, HttpService:JSONEncode({ role = State.myRole }))
            else
                Net.postJSON(url, { role = State.myRole }, "offline")
            end
        end)
        pcall(function() Net.getRaw(url) end)
        Runtime.alive = false -- tắt SAU CÙNG
    end

    -- /curmain = TRỌNG TÀI (File A 477-488): order, current, current_jobid, current_time, mains[]
    function ServerSync.fetchCurMain()
        if not Net.raw then return nil end
        local ok, _, body = Net.raw("GET", B .. "/curmain", nil)
        if not (ok and body) then return nil end
        local good, res = pcall(function() return HttpService:JSONDecode(body) end)
        if good and res and type(res.order) == "table" then return res end
        return nil
    end

    function ServerSync.startWarmers()
        -- clock (File A 2424-2427)
        task.spawn(function()
            ServerSync.syncClock()
            while Runtime.alive do task.wait(20); pcall(ServerSync.syncClock) end
        end)
        -- heartbeat 5s (File A 388-396)
        task.spawn(function()
            while Runtime.alive do
                ServerSync.sendHeartbeat()
                for _ = 1, Config.HEARTBEAT_INTERVAL do
                    if not Runtime.alive then break end
                    task.wait(1)
                end
            end
        end)
        -- warmer /curmain ~0.7s: 1 request lấy order + status MỌI main + jobid main stt1 (File A 493-519)
        task.spawn(function()
            while Runtime.alive do
                pcall(function()
                    local data = ServerSync.fetchCurMain()
                    if data and type(data.order) == "table" then
                        State.serverMainOrder = data.order
                        State.serverCurMain   = data.current
                        State.serverCurJobid  = data.current_jobid
                        State._lastCurMainOK  = tick()
                        -- BS-5: reset didEnterTrialThisTurn khi (a) fullmoon UNLOCK, (b) current main đổi cycle
                        if State.isMain[State.myName] then
                            local prevLocked = State.fullmoonLocked
                            if prevLocked and (data.fullmoon_locked ~= true) then State.didEnterTrialThisTurn = false end
                            if State._lastCurrentMain ~= nil and data.current ~= State._lastCurrentMain then
                                State.didEnterTrialThisTurn = false
                            end
                        end
                        State._lastCurrentMain = data.current
                        -- CLEAN JOIN: field điều hướng
                        State.fullmoonLocked    = data.fullmoon_locked == true
                        State.gateOpenedOnce    = data.gate_opened_once == true
                        State.gateOpen          = data.gate_open == true
                        State.trialPhase        = tostring(data.trial_phase or "idle")
                        State.fullmoonJobid     = nonEmpty(data.fullmoon_jobid)
                        State.allyTargetJobid   = nonEmpty(data.ally_target_jobid)
                        State.main1Name         = nonEmpty(data.main1_name)
                        State.requiredAllies    = tonumber(data.required_allies or 2) or 2
                        State.allyLeader        = nonEmpty(data.ally_leader)
                        State.fullmoonAllyCount = tonumber(data.fullmoon_ally_count or 0) or 0
                        State.candidateAllyCount= tonumber(data.candidate_ally_count or 0) or 0
                        State.joinSpamInterval  = tonumber(data.join_spam_interval or 5) or 5
                        State.mainJoinTimeout   = tonumber(data.main_join_timeout or 45) or 45
                        State.partyOrder        = (type(data.party_order) == "table") and data.party_order or {}
                        if State.fullmoonJobid or State.allyTargetJobid then State.lastScoutSignalAt = tick() end
                        _G.srvMainOrder    = data.order
                        _G.srvCurMain      = data.current
                        _G.srvCurMainJobid = data.current_jobid
                        -- nóng statusCache cho TẤT CẢ main TRỪ chính mình (self do setMyMainStatus quản lý)
                        if type(data.mains) == "table" then
                            for _, m in ipairs(data.mains) do
                                if m.name and m.name ~= State.myName then
                                    State.statusCache[m.name] = { t = tick(), status = m.status or "waiting" }
                                end
                            end
                        end
                        local curr = data.current
                        if curr and curr ~= State.myName and data.current_jobid and data.current_jobid ~= "" then
                            -- dùng gettimeserver() thay data.current_time để freshness reset mỗi lần poll
                            State.mainJobCache[curr] = { jobid = data.current_jobid, time = gettimeserver(), t = tick() }
                        end
                    end
                end)
                task.wait(Config.CURMAIN_INTERVAL)
            end
        end)
    end

    -- Net probe (File A 405-429)
    function ServerSync.startNetProbe()
        _G.netDiag = "NET: đang kiểm tra…"
        task.spawn(function()
            while Runtime.alive do
                pcall(function()
                    if not Net.raw then _G.netDiag = "NET: thiếu Net.raw"; return end
                    local g0 = tick()
                    local gok = Net.raw("GET", B .. "/timeserver", nil)
                    local gms = math.floor((tick() - g0) * 1000)
                    local pok, pms = nil, 0
                    if Net.hasReq then
                        local p0 = tick()
                        pok = Net.raw("POST", endpoint("/heartbeat", { name = Config.myName }), HttpService:JSONEncode({ role = State.myRole }))
                        pms = math.floor((tick() - p0) * 1000)
                    end
                    _G.netGetOk  = gok and true or false
                    _G.netPostOk = Net.hasReq and (pok and true or false) or nil
                    _G.netDiag = ("req=%s | GET %s %dms | POST %s"):format(
                        tostring(Net.hasReq), gok and "OK" or "FAIL", gms,
                        Net.hasReq and ((pok and "OK " or "FAIL ") .. pms .. "ms") or "N/A (thiếu request)")
                end)
                task.wait(5)
            end
        end)
    end
end

-- serverNow/gettimeserver: tên File A dùng nhiều nơi → alias sang ServerSync.now
local function serverNow() return ServerSync.now() end
local function gettimeserver() return ServerSync.now() end

--[[ ============================================================================
 [11] LIFECYCLE HOOKS — teleport guard, offline-once. (File A 431-456)
============================================================================ ]]
do
    pcall(function()
        LocalPlayer.OnTeleport:Connect(function(stateEnum)
            if stateEnum == Enum.TeleportState.Started or stateEnum == Enum.TeleportState.InProgress then
                Runtime.teleporting = true
            elseif stateEnum == Enum.TeleportState.Failed or stateEnum == Enum.TeleportState.Cancelled then
                Runtime.teleporting = false -- hop hỏng → cho phép offline nếu sau đó rời thật
            end
        end)
    end)
    pcall(function()
        Players.PlayerRemoving:Connect(function(plr)
            if plr == LocalPlayer and not Runtime.teleporting then ServerSync.sendOffline() end
        end)
    end)
    pcall(function() game:BindToClose(function()
        if not Runtime.teleporting then ServerSync.sendOffline() end
    end) end)
end

--[[ ============================================================================
 [12] MOVEMENT — module nhúng File A: topos(tween cancel/clamp/nil-safe), noclip thật,
      eq, haki, join, getdis, anti-AFK. (File A 717-838, 861-872)
============================================================================ ]]
local Movement = {}
do
    local LP = LocalPlayer

    local function getHRP()
        local c = LP.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end
    Movement.getHRP = getHRP

    -- getdis (File A 819-827, 861-863)
    function Movement.getdis(x, y)
        if typeof(x) ~= "CFrame" then return math.huge end
        if not y then
            local hrp = getHRP()
            if not hrp then return math.huge end
            y = hrp.CFrame
        end
        if typeof(y) == "CFrame" then y = y.Position end
        return (x.Position - y).Magnitude
    end
    Movement.distance = function(cf) return Movement.getdis(cf) end

    -- eq (File A 729-741)
    function Movement.equip()
        local char = LP.Character
        local bp = LP:FindFirstChild("Backpack")
        if not (char and bp) then return end
        for _, L in pairs(bp:GetChildren()) do
            if L:IsA("Tool") then
                local tip = L.ToolTip
                if (tip == "Melee" and not _G.USESWORD) or (tip == "Sword" and _G.USESWORD) then
                    if pcall(function() char.Humanoid:EquipTool(L) end) then break end
                end
            end
        end
    end

    -- haki (File A 743-750)
    function Movement.haki()
        local char = LP.Character
        if char and not char:FindFirstChild("HasBuso") then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
            end)
        end
    end

    -- topos: hủy tween cũ + clamp 0.05..600 (200 studs/s cố định) + nil-safe (File A 752-769)
    local _activeTween
    function Movement.cancel()
        if _activeTween then
            pcall(function() _activeTween:Cancel(); _activeTween:Destroy() end)
            _activeTween = nil
        end
    end
    function Movement.topos(targetCFrame, v36)
        if typeof(targetCFrame) ~= "CFrame" then return end
        local hrp = getHRP()
        if not hrp then return end                                  -- respawn → bỏ qua, KHÔNG hang
        if not v36 then pcall(function() LP.Character.Humanoid.Sit = false end) end
        Movement.cancel()
        local dist = (hrp.Position - targetCFrame.Position).Magnitude
        local dur = math.clamp(dist / 200, 0.05, 600)               -- 200 studs/s cố định (cap 600s)
        local tw = TweenService:Create(hrp,
            TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
            { CFrame = targetCFrame })
        _activeTween = tw
        tw.Completed:Once(function()
            if _activeTween == tw then _activeTween = nil end
            pcall(function() tw:Destroy() end)
        end)
        tw:Play()
        return tw
    end
    -- alias Movement.to(cf, opts) cho code module-style
    function Movement.to(cf, options)
        return Movement.topos(cf, options and options.raw)
    end

    -- join team qua ChooseTeam UI firesignal (File A 771-780)
    function Movement.joinTeam(v2)
        v2 = (v2 == "Marines" or v2 == "Pirates") and v2 or "Marines"
        for _, v in pairs(LP.PlayerGui:GetChildren()) do
            if v:FindFirstChild("ChooseTeam") then
                local b = v.ChooseTeam.Container:FindFirstChild(v2)
                b = b and b:FindFirstChild("Frame"); b = b and b:FindFirstChild("TextButton")
                if b then pcall(function() firesignal(b.Activated) end) end
            end
        end
    end

    -- tele bằng __ServerBrowser (File A 782-786)
    function Movement.tele(v)
        pcall(function()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", v or game.JobId)
        end)
    end

    -- noclip: compile loadstring 1 LẦN + single-instance + nil-safe (File A 788-817)
    local _noclipOn = false
    function Movement.enableNoclip(condStr)
        if _noclipOn then return end
        _noclipOn = true
        local okC, fn = pcall(loadstring, condStr or "return true")
        local cond = (okC and type(fn) == "function") and fn or function() return true end
        task.spawn(function()
            while Runtime.alive do
                task.wait()
                local char = LP.Character
                local hum = char and char:FindFirstChild("Humanoid")
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local okR, want = pcall(cond)
                if okR and want and hum and hrp and not hum.Sit then
                    if not hrp:FindFirstChild("BodyClip") then
                        local bv = Instance.new("BodyVelocity")
                        bv.Name = "BodyClip"; bv.MaxForce = Vector3.new(1e5, 1e5, 1e5); bv.Velocity = Vector3.zero
                        bv.Parent = hrp
                    end
                    for _, p in pairs(char:GetDescendants()) do
                        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
                    end
                elseif hrp then
                    local bc = hrp:FindFirstChild("BodyClip")
                    if bc then bc:Destroy() end
                end
            end
        end)
    end

    -- anti-AFK (File A 830-837)
    pcall(function()
        LP.Idled:Connect(function()
            VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        end)
    end)
end

-- alias File A: getdis(...) / module:topos / module:eq / module:haki
local function getdis(...) return Movement.getdis(...) end
local module = {
    topos = function(_, cf, v) return Movement.topos(cf, v) end,
    eq    = function() return Movement.equip() end,
    haki  = function() return Movement.haki() end,
    getdis = function(_, ...) return Movement.getdis(...) end,
}

-- wrapper topos() của File A 865-872: tự kill khi target xa & đang gần temple entry (chống kẹt)
local TEMPLE_ENTRY_POS = Vector3.new(28310.0234, 14895.1123, 109.456741)
local TEMPLE_ENTRY_FAR_CF = CFrame.new(28310.0234, 14895.1123, 109.456741, -0.469690144, -2.85620132e-08, -0.882831335, -3.23509219e-08, 1, -1.51411736e-08, 0.882831335, 2.14487486e-08, -0.469690144)
local function topos(v)
    pcall(function()
        if getdis(v) > 2500 and getdis(TEMPLE_ENTRY_FAR_CF) < 1500 then
            LocalPlayer.Character.Humanoid.Health = 0
        end
    end)
    return Movement.topos(v)
end

--[[ ============================================================================
 [13] WORLDPROBE — lazy getter + cache (KHÔNG WaitForChild vô hạn). (File A 842-980)
============================================================================ ]]
local WorldProbe = {}
do
    local doorCache, trialCache = {}, {}

    local RACE_TRIAL_NAME = {
        ["Human"]   = "Trial of Strength", ["Mink"] = "Trial of Speed", ["Fishman"] = "Trial of Water",
        ["Skypiea"] = "Trial of the King", ["Ghoul"] = "Trial of Carnage",
        ["Cyborg"]  = "Trial of the Machine", ["Draco"] = "Trial of Flames",
    }
    WorldProbe.RACE_TRIAL_NAME = RACE_TRIAL_NAME

    function WorldProbe.getRace()
        local ok, race = pcall(function() return LocalPlayer.Data.Race.Value end)
        return ok and race or nil
    end
    function WorldProbe.getTemple()
        local map = workspace:FindFirstChild("Map")
        return map and map:FindFirstChild("Temple of Time")
    end

    -- getdoor: cache theo race + check Parent (File A 842-859)
    -- Path chuẩn (toạ độ chuẩn) = Corridor.Door.Door; Skypiea = Corridor.Door (part luôn).
    -- Ưu tiên .Door.Door → .Door (nếu tự nó là part, cho Skypiea) → .Entrance (fallback cũ).
    function WorldProbe.getDoorForRace(race)
        race = race or WorldProbe.getRace()
        if not race then return nil end
        local cached = doorCache[race]
        if cached and cached.Parent then return cached end
        local temple = WorldProbe.getTemple()
        if not temple then return nil end
        local corridor = temple:FindFirstChild(race .. "Corridor")
        if not corridor then return nil end
        local door = corridor:FindFirstChild("Door")
        if not door then return nil end
        -- 1) .Door.Door (part cửa thật, toạ độ chuẩn)
        local innerDoor = door:FindFirstChild("Door")
        if innerDoor and innerDoor:IsA("BasePart") then
            doorCache[race] = innerDoor
            return innerDoor
        end
        -- 2) .Door tự nó là part (trường hợp Skypiea)
        if door:IsA("BasePart") then
            doorCache[race] = door
            return door
        end
        -- 3) fallback .Entrance (bản cũ)
        local entrance = door:FindFirstChild("Entrance")
        if entrance then doorCache[race] = entrance end
        return entrance
    end

    -- getRaceTrialPlace: cache theo race (File A 970-980)
    function WorldProbe.getRaceTrialPlace(race)
        race = race or WorldProbe.getRace()
        if not race then return nil end
        local c = trialCache[race]
        if c and c.Parent then return c end
        local wo = workspace:FindFirstChild("_WorldOrigin")
        local loc = wo and wo:FindFirstChild("Locations")
        local nm = RACE_TRIAL_NAME[race]
        local p = (loc and nm) and loc:FindFirstChild(nm) or nil
        if p then trialCache[race] = p end
        return p
    end

    function WorldProbe.getForcefieldState()
        local temple = WorldProbe.getTemple()
        if not temple then return nil end
        local ff
        pcall(function()
            local border = temple:FindFirstChild("FFABorder")
            local field = border and border:FindFirstChild("Forcefield")
            if field then ff = field.Transparency end
        end)
        return ff
    end
    function WorldProbe.distanceToCFrame(cf, fromCf)
        return Movement.getdis(cf, fromCf)
    end
end
-- alias File A
local function getdoor(vv) return WorldProbe.getDoorForRace(vv) end
local function getRaceTrialPlace(race) return WorldProbe.getRaceTrialPlace(race) end

--[[ ============================================================================
 [14] TEMPLEMANAGER — templeState (cache TTL 0.5s, reparent throttle 5s) +
      goToMyDoor. (File A 880-942)
============================================================================ ]]
local TempleManager = {}
do
    local TEMPLE_ENTRY = TEMPLE_ENTRY_POS
    local TEMPLE_ENTRY_CF = CFrame.new(TEMPLE_ENTRY)
    TempleManager.TEMPLE_ENTRY = TEMPLE_ENTRY

    -- templeState: cache 0.5s, reparent MapStash throttle 5s, trả loading/ffup/ffdown (File A 911-942)
    function TempleManager.templeState()
        local t = tick()
        if _G._tsCacheTime and (t - _G._tsCacheTime) < 0.5 then return _G._tsCacheValue end
        _G._tsCacheTime = t
        local temple = WorldProbe.getTemple()
        if not temple then
            if not _G.lastTempleReparent or (tick() - _G.lastTempleReparent) > 5 then
                _G.lastTempleReparent = tick()
                pcall(function()
                    local stash = ReplicatedStorage:FindFirstChild("MapStash")
                    local m = stash and stash:FindFirstChild("Temple of Time")
                    local map = workspace:FindFirstChild("Map")
                    if m and map then m.Parent = map end
                end)
            end
            _G._tsCacheValue = "loading"
            return "loading"
        end
        local ff = WorldProbe.getForcefieldState()
        if ff == 0 then _G._tsCacheValue = "ffup"; return "ffup" end
        _G._tsCacheValue = "ffdown"
        return "ffdown"
    end

    -- goToMyDoor: xa temple >3000 → requestEntrance throttle 4s; gần → topos cửa; trả d<=150 (File A 880-901)
    function TempleManager.goToMyDoor()
        if Movement.getdis(CFrame.new(TEMPLE_ENTRY)) >= 3000 then
            if not _G.lastReqEntrance or (tick() - _G.lastReqEntrance) > 4 then
                _G.lastReqEntrance = tick()
                pcall(function()
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("requestEntrance", TEMPLE_ENTRY)
                end)
            end
            _G.lastDoorSrc = "far"
            return false
        end
        local door = WorldProbe.getDoorForRace()
        if not door then _G.lastDoorSrc = "noload"; return false end
        local char = LocalPlayer.Character
        if not (char and char:FindFirstChild("HumanoidRootPart")) then return false end
        pcall(function() topos(door.CFrame) end)
        local d = Movement.getdis(door.CFrame)
        _G.lastDoorDist = d
        return d <= 150
    end
end
local function goToMyDoor() return TempleManager.goToMyDoor() end
local function templeState() return TempleManager.templeState() end

--[[ ============================================================================
 [15] WORLD HELPERS — isnight / isfullmoon / isSamePlace. (File A 1130-1144)
============================================================================ ]]
local function isnight()
    local c = Lighting.ClockTime
    return (c >= 16 or c < 5)
end
-- FIX detect full moon (user 2026-07-02): MoonPhase attribute KHÔNG tụt ngay khi moon hết
-- (game báo "The full moon ends" nhưng attribute vẫn =5) → Ally tưởng còn moon, báo sai, /fmlost
-- không bao giờ bắn. Dùng Sky.MoonTextureId (asset THẬT, đổi ngay khi hết) như file tham khảo
-- kickendmoon.txt, + loại "fake moon" ban ngày (texture full nhưng ClockTime 5..12).
local FULLMOON_TEXTURE = "http://www.roblox.com/asset/?id=9709149431"
local function moonTextureId()
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if sky and sky.MoonTextureId then return sky.MoonTextureId end
    return ""
end
local function isfullmoon()
    -- ưu tiên texture (chuẩn xác lúc bắt đầu/kết thúc). Sky chưa load → fallback MoonPhase.
    local tex = moonTextureId()
    if tex ~= "" then
        if tex ~= FULLMOON_TEXTURE then return false end
        -- texture = full moon: loại fake moon ban ngày (ClockTime 5..12 = fake theo kickendmoon.txt)
        local c = Lighting.ClockTime
        if c > 5 and c < 12 then return false end
        return true
    end
    return Lighting:GetAttribute("MoonPhase") == 5
end
_G.isfullmoon = isfullmoon   -- để heartbeat (khai báo trước) gọi được
-- Đếm tổng player + số ally đang ở server hiện tại (cho heartbeat → server xếp main theo
-- player và demote Main1 kẹt server full). Đếm distinct ally theo tên (State.isAlly).
local function countServerInfo()
    local players = #Players:GetPlayers()
    local seen, allies = {}, 0
    for _, p in ipairs(Players:GetPlayers()) do
        if State.isAlly[p.Name] and not seen[p.Name] then
            seen[p.Name] = true
            allies = allies + 1
        end
    end
    return players, allies
end
_G.countServerInfo = countServerInfo   -- heartbeat (khai báo trước) gọi qua _G như isfullmoon
local function isSamePlace(serverEntry)
    return serverEntry ~= nil and tonumber(serverEntry.placeid) == game.PlaceId
end

--[[ ============================================================================
 [16] TELEPORTMANAGER — hop fullmoon (cache 1h/placeid/player/blacklist 771) +
      hop server ít người (GetServers/HopServer) + cờ teleport riêng.
      (File A 604-708, 1146-1210)
============================================================================ ]]
local TeleportManager = {}
do
    local CACHE_FILE = "cache_v4.json"
    TeleportManager.deadJobs = {}

    local HOP_CONFIG = {
        MaxPlayers    = 6,
        CacheDuration = 60,
        MaxPages      = 100,
        RetryDelay    = 2,
    }

    function TeleportManager.markVisited(jobId)
        local data = FileStore.readJson(CACHE_FILE, {})
        data[jobId] = math.floor(tick())
        FileStore.writeJson(CACHE_FILE, data)
    end
    function TeleportManager.isSamePlace(entry) return isSamePlace(entry) end

    -- ===== HOP SERVER ÍT NGƯỜI (File A 611-708) =====
    local function _ifTableHaveIndex(j)
        for _ in pairs(j) do return true end
        return false
    end

    local _hopLastPull, _hopCachedServers
    function TeleportManager.getServers()
        if _hopLastPull and _hopCachedServers and (tick() - _hopLastPull) < HOP_CONFIG.CacheDuration then
            return _hopCachedServers
        end
        for i = 1, HOP_CONFIG.MaxPages do
            local ok, data = pcall(function()
                return ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer(i)
            end)
            if ok and data and _ifTableHaveIndex(data) then
                _hopLastPull = tick()
                _hopCachedServers = data
                return data
            end
        end
        DBG("[HOP] Không lấy được danh sách server!", "err")
        return nil
    end

    function TeleportManager.hopLowPlayer(Reason, MaxPlayers)
        MaxPlayers = MaxPlayers or HOP_CONFIG.MaxPlayers
        local Servers = TeleportManager.getServers()
        if not Servers then
            DBG("[HOP] Không có dữ liệu server → bỏ qua, vòng sau thử lại", "err")
            return false
        end
        local ArrayServers = {}
        for id, v in pairs(Servers) do
            if id ~= game.JobId and type(v) == "table" then
                table.insert(ArrayServers, { JobId = id, Players = v.Count or 0 })
            end
        end
        DBG(("[HOP] Nhận được %d server"):format(#ArrayServers), "ok")
        if #ArrayServers == 0 then
            DBG("[HOP] Danh sách server rỗng → bỏ qua", "err")
            return false
        end
        local Filtered = {}
        for _, s in ipairs(ArrayServers) do
            if (not MaxPlayers) or s.Players <= MaxPlayers then table.insert(Filtered, s) end
        end
        DBG(("[HOP] Sau lọc (<=%s người): %d server"):format(tostring(MaxPlayers), #Filtered), "ok")
        if #Filtered == 0 then
            DBG("[HOP] Không có server ít người → dùng toàn bộ danh sách", "err")
            Filtered = ArrayServers
        end
        local ServerData = Filtered[math.random(1, #Filtered)]
        _G.trainHopArmedT = tick()
        DBG(("[HOP] %s → teleport %s (Players=%d)"):format(tostring(Reason), tostring(ServerData.JobId), ServerData.Players), "ok")
        local ok = pcall(function()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", ServerData.JobId)
        end)
        return ok
    end

    -- ===== CLEAN JOIN: hop tới 1 jobid do server chỉ định (throttle 5s/jobid) =====
    local _lastJobHop = {}
    function TeleportManager.hopToJob(jobid, reason)
        jobid = tostring(jobid or "")
        if jobid == "" or jobid == game.JobId then return false end
        if _lastJobHop[jobid] and (tick() - _lastJobHop[jobid]) < Config.RALLY_HOP_THROTTLE then return false end
        _lastJobHop[jobid] = tick()
        _G.rallyHopArmedT = tick()
        _G.lastRallyJob   = jobid
        DBG(("[RALLY] %s -> teleport %s"):format(tostring(reason), tostring(jobid)), "ok", "rally_hop")
        local ok = pcall(function()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", jobid)
        end)
        return ok
    end

    -- Hop server ít người để TRAINING (dùng lại getServers + retry sẵn có)
    function TeleportManager.hopTrainingServer(reason)
        return TeleportManager.hopLowPlayer(reason or "[TRAINING]", 4)
    end

    -- ===== TeleportInitFailed: blacklist 771 + retry đúng cờ (File A 683-708) =====
    pcall(function()
        TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, message)
            if player ~= LocalPlayer then return end
            Runtime.teleporting = false   -- chống kẹt teleporting=true khi fail
            -- (RALLY) Teleport tới jobid server chỉ định fail → báo Node reject (server tự tìm server khác)
            if _G.rallyHopArmedT and (tick() - _G.rallyHopArmedT) < 15 then
                local failedJob = _G.lastRallyJob
                _G.rallyHopArmedT = nil
                _G.lastRallyJob = nil
                if failedJob and failedJob ~= "" then
                    TeleportManager.deadJobs[failedJob] = tick()
                    DBG("[RALLY] Teleport fail jobid=" .. tostring(failedJob) .. " -> reject", "err", "rally_fail")
                    pcall(function()
                        Net.postJSON(
                            endpoint("/rally/reject", { name = State.myName }),
                            { jobid = failedJob, reason = tostring(teleportResult), source = "teleport_fail" },
                            "rally_reject_" .. tostring(failedJob)
                        )
                    end)
                end
                return
            end
            -- (2) HOP ÍT NGƯỜI fail
            if _G.trainHopArmedT and (tick() - _G.trainHopArmedT) < 15 then
                _G.trainHopArmedT = nil
                if teleportResult == Enum.TeleportResult.GameFull then
                    DBG("[HOP] Server đầy → thử hop lại", "err")
                    task.delay(HOP_CONFIG.RetryDelay, function() TeleportManager.hopLowPlayer("Retry - Server đầy") end)
                else
                    DBG("[HOP] Teleport thất bại (" .. tostring(teleportResult) .. ") → thử server khác", "err")
                    task.delay(3, function() TeleportManager.hopLowPlayer("Retry - Teleport fail") end)
                end
                return
            end
            -- (3) ALLY hop fail → chỉ nhả cờ, vòng sau ally tự hop lại (không cướp retry khác)
            if _G.allyHopArmedT and (tick() - _G.allyHopArmedT) < 15 then
                _G.allyHopArmedT = nil
                DBG("[ALLY] Teleport fail (" .. tostring(teleportResult) .. ") → vòng sau hop lại", "err", "ally_tpfail")
            end
        end)
    end)
end
-- alias File A
local function HopServer(reason, maxp) return TeleportManager.hopLowPlayer(reason, maxp) end

--[[ ============================================================================
 [17] MAINQUEUE — thứ tự main (ưu tiên server /curmain, grace 8s). (File A 1378-1433)
============================================================================ ]]
local MainQueue = {}
do
    MainQueue._lastCurrent = nil

    function MainQueue.getOrder()
        if State.serverMainOrder and #State.serverMainOrder > 0 then return State.serverMainOrder end
        local active, waiting, finished = {}, {}, {}
        for _, name in ipairs(Config.mains) do
            local st = State.getMainStatus(name)
            if st == "offline" then
                -- bỏ qua: con đã rời → không tính hàng đợi
            elseif st == "moon" or st == "in_trail" then
                active[#active + 1] = name
            elseif st == "done" or st == "training" then
                finished[#finished + 1] = name
            else
                waiting[#waiting + 1] = name
            end
        end
        local order = {}
        for _, n in ipairs(active)   do order[#order + 1] = n end
        for _, n in ipairs(waiting)  do order[#order + 1] = n end
        for _, n in ipairs(finished) do order[#order + 1] = n end
        return order
    end

    function MainQueue.current()
        if State.serverCurMain then
            MainQueue._lastCurrent = State.serverCurMain
            return State.serverCurMain, 1
        end
        -- /curmain mất → giữ current cũ trong grace 8s (tránh nhảy main)
        if MainQueue._lastCurrent and (tick() - State._lastCurMainOK) < 8 then
            return MainQueue._lastCurrent, 1
        end
        local order = MainQueue.getOrder()
        if #order == 0 then return nil, nil end
        MainQueue._lastCurrent = order[1]
        return order[1], 1
    end

    function MainQueue.sttOf(name)
        for i, v in ipairs(MainQueue.getOrder()) do
            if v == name then return i end
        end
        return nil
    end

    -- cache-only mainJobCache; KHÔNG gọi mạng (File A 1424-1433)
    function MainQueue.isSameServerAsMain(mainName)
        if not mainName then return false, nil end
        local c = State.mainJobCache[mainName]
        if not c or not c.jobid then return false, nil end
        local fresh = (gettimeserver() - (c.time or 0)) < 60
        local same  = fresh and (c.jobid == game.JobId)
        return same, c.jobid
    end
end
-- alias File A
local function getCurrentMainBeingUpgraded() return MainQueue.current() end
local function mainSttOf(name) return MainQueue.sttOf(name) end
local function isSameServerAsMain(name) return MainQueue.isSameServerAsMain(name) end

--[[ ============================================================================
 [18] COMBATACTIONS — getmob1/checkmob_/getplayers/countplayers/attackTick/
      getallweapon/EquipTool/spam-skills/BringMob/GetMobPosition/TweenObject +
      FastAttack/AttackNoCoolDown. (File A 1214-1517, 2039-2395)
============================================================================ ]]
local CombatActions = {}
do
    local LP = LocalPlayer

    -- vị trí 6 ô player trong trial (File A 944-951)
    CombatActions.pos_plr_trial = {
        CFrame.new(28692.3477, 14887.5605, -53.7669983, 0.707131445, -0, -0.707082093, 0, 1, -0, 0.707082093, 0, 0.707131445),
        CFrame.new(28782.7246, 14898.9902, -59.6069946, 0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, 0.707134247),
        CFrame.new(28700.875, 14888.2598, -154.110992, -1, 0, 0, 0, 1, 0, 0, 0, -1),
        CFrame.new(28795.7715, 14888.2598, -112.917999, -0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, -0.707134247),
        CFrame.new(28658.4551, 14888.2598, -121.372009, -0.515037298, 0, -0.857167721, 0, 1, 0, 0.857167721, 0, -0.515037298),
        CFrame.new(28742.4688, 14887.5596, -18.2120056, 0.92051065, 0, 0.390717506, 0, 1, 0, -0.390717506, 0, 0.92051065),
    }

    function CombatActions.getmob1(pos)
        local allmobs = {}
        for _, v in pairs(workspace.Enemies:GetChildren()) do
            if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid")
                and v.Humanoid.Health > 0 and Movement.getdis(v.HumanoidRootPart.CFrame, pos) < 1000 then
                table.insert(allmobs, v)
            end
        end
        return allmobs
    end
    function CombatActions.checkmob_(v)
        return v and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0
    end

    local function noideaforname(v)
        if State.isAlly[v.Name] then return false end
        return true
    end
    function CombatActions.getplayers()
        local plrs = {}
        for _, v in pairs(Players:GetPlayers()) do
            if v ~= LP and v.Character and not State.isMain[v.Name] and noideaforname(v) then
                local hum = v.Character:FindFirstChild("Humanoid")
                local hrp = v.Character:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0 then
                    for _, pos in pairs(CombatActions.pos_plr_trial) do
                        if Movement.getdis(hrp.CFrame, pos) < 10 then
                            plrs[v.Character] = true
                        end
                    end
                end
            end
        end
        return plrs
    end
    function CombatActions.countplayers()
        local c = 0
        for _ in pairs(CombatActions.getplayers()) do c = c + 1 end
        return c
    end

    -- attackTick: offset random đổi mỗi 0.3s, eq/haki throttle 0.4s (File A 1256-1277)
    local _atkOff, _atkT, _atkEqT = CFrame.new(0, 3, 0), 0, 0
    function CombatActions.attackTick(target)
        if tick() - _atkT > 0.3 then
            _atkT = tick()
            local x, z = math.random(1, 4), math.random(1, 4)
            if math.random(1, 2) == 1 then x = -x end
            if math.random(1, 2) == 1 then z = -z end
            _atkOff = CFrame.new(x, 3, z)
        end
        _G.SHOULDSPAMSKILLS = true
        if tick() - _atkEqT > 0.4 then
            _atkEqT = tick()
            pcall(function() Movement.equip() end)
            pcall(function() Movement.haki() end)
        end
        local hrp = target and target:FindFirstChild("HumanoidRootPart")
        if hrp then pcall(function() topos(hrp.CFrame * _atkOff) end) end
    end

    -- weapon / spam-skills (File A 2039-2123)
    local fruits = {
        ['Buddha-Buddha'] = true, ['T-Rex-T-Rex'] = true, ['Dragon-Dragon'] = true, ['Yeti-Yeti'] = true,
        ['Leopard-Leopard'] = true, ['Venom-Venom'] = true, ['Phoenix-Phoenix'] = true, ['Kitsune-Kitsune'] = true,
        ['Mammoth-Mammoth'] = true, ['Gas-Gas'] = true, ["Portal-Portal"] = true,
    }
    local isvalidtooltip = { ["Melee"] = true, ["Blox Fruit"] = true, ["Sword"] = true, ["Gun"] = true }
    local isvalidnameui  = { ["Z"] = true, ["X"] = true, ["C"] = true, ["V"] = true, ["F"] = true }

    local function getallweapon()
        local weapon = {}
        local bp = LP:FindFirstChild("Backpack")
        if bp then
            for _, v in pairs(bp:GetChildren()) do
                if v:IsA("Tool") and isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
            end
        end
        if LP.Character then
            for _, v in pairs(LP.Character:GetChildren()) do
                if v:IsA("Tool") and isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
            end
        end
        return weapon
    end
    local function EquipTool(v)
        local bp = LP:FindFirstChild("Backpack")
        local thua = bp and bp:FindFirstChild(v)
        if thua and LP.Character and LP.Character:FindFirstChild("Humanoid") then
            LP.Character.Humanoid:EquipTool(thua)
        end
    end

    -- GetMobPosition / TweenObject / BringMob (File A 1457-1517)
    local function TweenObject(Object, Pos, Speed)
        if Speed == nil then Speed = 350 end
        if not (Object and Object.Parent) then return end
        local Distance = (Pos.Position - Object.Position).Magnitude
        local dur = math.clamp(Distance / Speed, 0.03, 3)
        local tw = TweenService:Create(Object, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = Pos })
        tw.Completed:Once(function() pcall(function() tw:Destroy() end) end)
        tw:Play()
    end
    local function GetMobPosition(EnemiesName)
        local pos = Vector3.new(0, 0, 0)
        local count = 0
        for _, v in pairs(workspace.Enemies:GetChildren()) do
            if v.Name == EnemiesName and v:FindFirstChild("HumanoidRootPart") then
                pos = pos + v.HumanoidRootPart.Position
                count = count + 1
            end
        end
        if count > 0 then return pos / count end
        return nil
    end
    function CombatActions.BringMob()
        local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myHrp then return end
        local ememe = workspace.Enemies:GetChildren()
        if #ememe > 0 then
            local totalpos = {}
            for _, v in pairs(ememe) do
                if not totalpos[v.Name] then totalpos[v.Name] = GetMobPosition(v.Name) end
            end
            for _, v in pairs(workspace.Enemies:GetChildren()) do
                local hum = v:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
                    if (v.HumanoidRootPart.Position - myHrp.Position).Magnitude <= 350 then
                        for k, f in pairs(totalpos) do
                            if k and v.Name == k and f then
                                local dest = CFrame.new(f.X, f.Y, f.Z)
                                local d = (v.HumanoidRootPart.Position - dest.Position).Magnitude
                                if d > 3 and d <= 280 then
                                    TweenObject(v.HumanoidRootPart, dest, 300)
                                    v.HumanoidRootPart.CanCollide = false
                                    v.Humanoid.WalkSpeed = 0
                                    v.Humanoid.JumpPower = 0
                                    v.Humanoid:ChangeState(14)
                                    pcall(function() sethiddenproperty(LP, "SimulationRadius", math.huge) end)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- spam-skills loop: BẬT theo _G.SHOULDSPAMSKILLS, 1 instance, check Runtime.alive (File A 2071-2123)
    function CombatActions.startSpamSkills()
        task.spawn(function()
            while Runtime.alive do
                task.wait()
                if _G.SHOULDSPAMSKILLS then
                    pcall(function()
                        local char = LP.Character
                        local skillsUI = LP.PlayerGui:FindFirstChild("Main")
                        skillsUI = skillsUI and skillsUI:FindFirstChild("Skills")
                        if not (char and skillsUI) then return end
                        local weapon = getallweapon()
                        for _, v in pairs(weapon) do
                            if not skillsUI:FindFirstChild(v.Name) then EquipTool(v.Name) end
                        end
                        for _, v in pairs(weapon) do
                            if v.Parent ~= char then EquipTool(v.Name) end
                            local ui_ = skillsUI:FindFirstChild(v.Name)
                            if ui_ then
                                for _, vl in pairs(ui_:GetChildren()) do
                                    if isvalidnameui[vl.Name] then
                                        local cooldown_frame = vl:FindFirstChild("Cooldown")
                                        local title_frame = vl:FindFirstChild("Title")
                                        if cooldown_frame and title_frame
                                            and (title_frame.TextColor3 == Color3.new(1, 1, 1) or title_frame.TextColor3 == Color3.fromRGB(255, 255, 255)) then
                                            if cooldown_frame.Size == UDim2.new(0, 0, 1, -1) then
                                                if vl.Name == "V" then
                                                    if not fruits[ui_.Name] then
                                                        VirtualInputManager:SendKeyEvent(true, "V", false, game)
                                                        task.wait(0.1)
                                                        VirtualInputManager:SendKeyEvent(false, "V", false, game)
                                                        task.wait(1.5)
                                                    end
                                                else
                                                    VirtualInputManager:SendKeyEvent(true, vl.Name, false, game)
                                                    task.wait(0.1)
                                                    VirtualInputManager:SendKeyEvent(false, vl.Name, false, game)
                                                    task.wait(1.5)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end)
    end

    -- ===== FastAttack (File A 2228-2323) + AttackNoCoolDown/haki loop (File A 2125-2395) =====
    function CombatActions.startFastAttack()
        local okShake = pcall(function()
            local CameraShakerR = require(ReplicatedStorage.Util.CameraShaker)
            CameraShakerR:Stop()
        end)
        if not okShake then Logger.warn("CameraShaker miss (bỏ qua)", "cam_shake") end

        local _ENV = (getgenv or getrenv or getfenv)()
        local function SafeWaitForChild(parent, childName)
            local ok, result = pcall(function() return parent:WaitForChild(childName, 10) end)
            if not ok then return nil end
            return result
        end
        local Player = LP
        local Remotes = SafeWaitForChild(ReplicatedStorage, "Remotes")
        if not Remotes then return end
        local Modules = SafeWaitForChild(ReplicatedStorage, "Modules")
        local NetMod  = Modules and SafeWaitForChild(Modules, "Net")
        if not NetMod then return end
        local Settings = { AutoClick = true, ClickDelay = 0 }

        if _ENV.rz_FastAttack then return end
        local FastAttack = { Distance = 100 }
        local RegisterAttack = SafeWaitForChild(NetMod, "RE/RegisterAttack")
        local RegisterHit    = SafeWaitForChild(NetMod, "RE/RegisterHit")
        if not (RegisterAttack and RegisterHit) then return end
        local function IsAlive(character)
            return character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0
        end
        local function ProcessEnemies(OthersEnemies, Folder)
            local BasePart = nil
            if not Folder then return nil end
            for _, Enemy in pairs(Folder:GetChildren()) do
                local Head = Enemy:FindFirstChild("Head")
                if Head and IsAlive(Enemy) and Player:DistanceFromCharacter(Head.Position) < FastAttack.Distance then
                    if Enemy ~= Player.Character then
                        table.insert(OthersEnemies, { Enemy, Head })
                        BasePart = Head
                    end
                end
            end
            return BasePart
        end
        function FastAttack:Attack(BasePart, OthersEnemies)
            if not BasePart or #OthersEnemies == 0 then return end
            RegisterAttack:FireServer(Settings.ClickDelay or 0)
            RegisterHit:FireServer(BasePart, OthersEnemies)
        end
        function FastAttack:AttackNearest()
            local OthersEnemies = {}
            local Part1 = ProcessEnemies(OthersEnemies, workspace:FindFirstChild("Enemies"))
            local Part2 = ProcessEnemies(OthersEnemies, workspace:FindFirstChild("Characters"))
            local character = Player.Character
            if not character then return end
            local equippedWeapon = character:FindFirstChildOfClass("Tool")
            if equippedWeapon and equippedWeapon:FindFirstChild("LeftClickRemote") then
                for _, enemyData in ipairs(OthersEnemies) do
                    local enemy = enemyData[1]
                    local ehrp = enemy:FindFirstChild("HumanoidRootPart")
                    if ehrp then
                        local direction = (ehrp.Position - character:GetPivot().Position).Unit
                        pcall(function() equippedWeapon.LeftClickRemote:FireServer(direction, 1) end)
                    end
                end
            elseif #OthersEnemies > 0 then
                self:Attack(Part1 or Part2, OthersEnemies)
            else
                task.wait(0)
            end
        end
        function FastAttack:BladeHits()
            local Equipped = IsAlive(Player.Character) and Player.Character:FindFirstChildOfClass("Tool")
            if Equipped and Equipped.ToolTip ~= "Gun" then self:AttackNearest() else task.wait(0) end
        end
        _ENV.rz_FastAttack = FastAttack
        task.spawn(function()
            while Runtime.alive do
                task.wait(Settings.ClickDelay)
                if Settings.AutoClick then pcall(function() FastAttack:BladeHits() end) end
            end
        end)
    end

    -- haki loop nền (File A 2390-2395)
    function CombatActions.startHakiLoop()
        task.spawn(function()
            while Runtime.alive do
                task.wait()
                pcall(function() Movement.haki() end)
            end
        end)
    end
end
-- alias File A
local function getplayers() return CombatActions.getplayers() end
local function countplayers() return CombatActions.countplayers() end
local function attackTick(t) return CombatActions.attackTick(t) end
local function getmob1(pos) return CombatActions.getmob1(pos) end
local function checkmob_(v) return CombatActions.checkmob_(v) end
local function BringMob() return CombatActions.BringMob() end

--[[ ============================================================================
 [19] GEARMANAGER — checkGear qua SafeRemote (File A 1435-1455)
============================================================================ ]]
local GearManager = {}
do
    -- state cho việc tiêu điểm Gear5 (chống spam SpendPoint → tránh kick)
    local _g5Lock    = false
    local _g5LastTry = 0

    function GearManager.checkGear()
        local _okcg, dt = SafeRemote.invoke(3, "TempleClock", "Check")
        if not (dt and type(dt) == "table") then return end
        if not dt.HadPoint then return end
        local rd = dt.RaceDetails
        if not (rd and rd.Completed ~= nil) then return end

        -- ===== GEAR5 SWAP WINDOW: tiêu điểm thừa để MỞ KHÓA TRIALING =====
        -- Completed==5 + HadPoint: server bắt chọn lại 1 slot sang Alpha/Omega NGƯỢC với
        -- hiện tại thì mới tính → hết "báo đỏ" → vào được in_trial. KHÔNG theo Config.
        -- Thử Gear2=Alpha rồi Gear2=Omega: 1 trong 2 chắc chắn "ngược" → được tính; cái
        -- trùng giá trị hiện tại bị bỏ qua. Lock + cooldown 5s chống spam, KHÔNG retry vô hạn.
        if rd.Completed == 5 then
            if _g5Lock then return end
            if (tick() - _g5LastTry) < 5 then return end
            _g5Lock = true
            _g5LastTry = tick()
            task.spawn(function()
                local cleared = false
                for _, pick in ipairs({ "Alpha", "Omega" }) do
                    DBG("[GEAR-AUTO] ally=" .. State.myName ..
                        " state=max_gear5 action=swap slot=2 to=" .. pick ..
                        " reason=consume_point_unblock_trial", "ok", "gear_auto")
                    SafeRemote.invoke(3, "TempleClock", "SpendPoint", "Gear2", pick)
                    task.wait(1.5)
                    local _ok2, dt2 = SafeRemote.invoke(3, "TempleClock", "Check")
                    if dt2 and dt2.HadPoint == false then cleared = true; break end
                end
                if cleared then
                    DBG("[GEAR-AUTO] ally=" .. State.myName ..
                        " state=max_gear5 action=swap reason=success_point_cleared", "ok", "gear_auto_ok")
                else
                    DBG("[GEAR-AUTO] ally=" .. State.myName ..
                        " state=max_gear5 action=skip reason=server_stuck_no_retry", "warn", "gear_auto_stuck")
                end
                _g5Lock = false
            end)
            return  -- KHÔNG rơi xuống logic claim cũ (đang gọi sai "Gear5"/"Gearnil" cho Gear5)
        end

        local g1, g2, g3 = Config.gear:match("^(.-)%-(.-)%-(.-)$")
        local a23 = { [2] = g1, [3] = g2, [4] = g3 }
        local a24 = { ["A"] = "Alpha", ["B"] = "Omega" }
        local lvl = rd.Completed
        local choosegear = (lvl == 1 or lvl == 5) and "Blank" or a24[a23[lvl]]
        local a = rd.A or 0
        local b = rd.B or 0
        if a >= 2 then
            SafeRemote.invoke(3, "TempleClock", "SpendPoint", "Gear" .. tostring(dt.Completed), "Omega")
        elseif b >= 2 then
            SafeRemote.invoke(3, "TempleClock", "SpendPoint", "Gear" .. tostring(dt.Completed), "Alpha")
        else
            SafeRemote.invoke(3, "TempleClock", "SpendPoint", "Gear" .. tostring(rd.Completed), choosegear)
        end
    end
end
local function checkgear() return GearManager.checkGear() end

--[[ ============================================================================
 [20] TRIALACTIONS — doTrialForMyRace + runTrialPhase. (File A 982-1128)
============================================================================ ]]
local TrialActions = {}
do
    local LP = LocalPlayer

    -- bay từ từ (tween) tới cf, destroy chống leak (File A 996-1006)
    local function flyTo(cf)
        pcall(function()
            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local dist = (cf.Position - hrp.Position).Magnitude
            local dur = math.clamp(dist / 200, 0.05, 600)
            local tw = TweenService:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = cf })
            tw:Play(); task.wait(dur); pcall(function() tw:Destroy() end)
        end)
    end
    -- cầm Melee (fallback Sword/Blox Fruit/Gun) (File A 1007-1022)
    local function equipMelee()
        pcall(function()
            local char = LP.Character
            if not (char and char:FindFirstChild("Humanoid")) then return end
            local melee, anyw
            local bp = LP:FindFirstChild("Backpack")
            if not bp then return end
            for _, t in pairs(bp:GetChildren()) do
                if t:IsA("Tool") then
                    local tip = t.ToolTip
                    if tip == "Melee" then melee = t break
                    elseif tip == "Sword" or tip == "Blox Fruit" or tip == "Gun" then anyw = anyw or t end
                end
            end
            local pick = melee or anyw
            if pick then char.Humanoid:EquipTool(pick) end
        end)
    end

    -- teleport thô (không tự kill như wrapper topos) (File A 993)
    local function tp(cf) pcall(function() Movement.topos(cf) end) end

    -- doTrialForMyRace (File A 989-1111) — y chang per-race
    function TrialActions.doTrialForMyRace()
        local myrace = LP.Data.Race.Value
        local race_trial_place = getRaceTrialPlace(myrace)

        if myrace == "Mink" then
            if tick() - (_G.minkLastTrial or 0) > 3 then task.wait(2) end
            _G.minkLastTrial = tick()
            local sp = _G.minkStartPoint
            if not (sp and sp.Parent) then
                sp = nil
                pcall(function()
                    for _, obj in pairs(workspace:GetDescendants()) do
                        if obj.Name == "StartPoint" then sp = obj break end
                    end
                end)
                _G.minkStartPoint = sp
            end
            if sp then
                local t0 = tick()
                repeat task.wait(); pcall(function() Movement.topos(sp.CFrame * CFrame.new(0, 2, 0)) end)
                until (tick() - t0) > 4
            end

        elseif myrace == "Skypiea" then
            local finish, model
            pcall(function()
                model = workspace.Map:FindFirstChild("SkyTrial")
                model = model and model:FindFirstChild("Model")
                if model then
                    for _, obj in pairs(model:GetDescendants()) do
                        if obj.Name == "snowisland_Cylinder.081" then finish = obj break end
                    end
                    finish = finish or model:FindFirstChild("FinishPart")
                end
            end)
            if not finish then
                local c = _G.skyFinish
                if c and c.Parent then finish = c
                else
                    pcall(function()
                        for _, obj in pairs(workspace:GetDescendants()) do
                            if obj.Name == "snowisland_Cylinder.081" then finish = obj break end
                        end
                    end)
                    _G.skyFinish = finish
                end
            end
            if finish then flyTo(finish.CFrame)
            elseif model then pcall(function() flyTo(model:GetPivot()) end)
            elseif race_trial_place then flyTo(race_trial_place.CFrame) end

        elseif myrace == "Cyborg" then
            pcall(function() tp(workspace.Map.CyborgTrial.Floor.CFrame * CFrame.new(0, 500, 0)) end)

        elseif myrace == "Human" or myrace == "Ghoul" then
            for _, v in pairs(workspace.Enemies:GetChildren()) do
                local hum = v:FindFirstChild("Humanoid")
                local hrp = v:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0
                    and (not race_trial_place or getdis(hrp.CFrame, race_trial_place.CFrame) < 1500) then
                    local t0 = tick()
                    repeat task.wait()
                        equipMelee()
                        Movement.equip(); Movement.haki()
                        tp(hrp.CFrame * CFrame.new(0, 30, 0))
                        pcall(function() sethiddenproperty(LP, "SimulationRadius", math.huge) end)
                        pcall(function() hrp.CanCollide = false; hum.Health = 0 end)
                    until (not v.Parent) or (not v:FindFirstChild("Humanoid")) or v.Humanoid.Health <= 0 or (tick() - t0) > 20
                end
            end

        elseif myrace == "Fishman" then
            for _, v in pairs(workspace.SeaBeasts:GetChildren()) do
                pcall(function()
                    if v:FindFirstChild('Health') and v.Health.Value > 0 and v:FindFirstChild("HumanoidRootPart")
                        and (not race_trial_place or getdis(v.HumanoidRootPart.CFrame, race_trial_place.CFrame) < 1500) then
                        local t0 = tick()
                        repeat task.wait()
                            local bp = LP:FindFirstChild("Backpack")
                            if bp and not bp:FindFirstChild("Sharkman Karate") then
                                SafeRemote.invoke(3, "BuySharkmanKarate")
                            end
                            tp(v.HumanoidRootPart.CFrame * CFrame.new(0, 500, 0))
                            _G.SHOULDSPAMSKILLS = true
                        until (not v.Parent) or (not v:FindFirstChild('Health')) or v.Health.Value <= 0
                            or (not v:FindFirstChild("HumanoidRootPart")) or (tick() - t0) > 25
                        _G.SHOULDSPAMSKILLS = false
                    end
                end)
            end
            -- Draco / khác: File A không có handler riêng → fallback bay vào trial place (status rõ)
        elseif race_trial_place then
            flyTo(race_trial_place.CFrame)
        end
    end

    -- handleRaceTrial(ctx) → trả phase rõ (StateMachine dùng) (File A doTrialForMyRace)
    function TrialActions.handleRaceTrial()
        local race = WorldProbe.getRace()
        if not race then return { ok = false, phase = "missing_object", detail = "no race" } end
        TrialActions.doTrialForMyRace()
        return { ok = true, phase = "running_trial", detail = race }
    end

    -- runTrialPhase: ở khu trial → làm trial (set in_trail nếu main); chưa → ra cửa (File A 1115-1128)
    function TrialActions.runTrialPhase(roleName, isMain)
        local race_trial_place = getRaceTrialPlace(WorldProbe.getRace())
        if race_trial_place and getdis(race_trial_place.CFrame) < 1500 then
            if isMain then
                local st = State.getMainStatus(State.myName)
                if st ~= "in_trail" and st ~= "training" then State.setMyMainStatus("in_trail") end
            end
            status(roleName .. " Doing trial")
            TrialActions.doTrialForMyRace()
            return "running_trial"
        else
            status(roleName .. " Ready for trialing (đợi đồng bộ ability)")
            goToMyDoor()
            return "moving_to_trial"
        end
    end
end
local function doTrialForMyRace() return TrialActions.doTrialForMyRace() end
local function runTrialPhase(roleName, isMain) return TrialActions.runTrialPhase(roleName, isMain) end

--[[ ============================================================================
 [21] TRAINING — trialable/cachedTrialable + doTrainGrind + pressV4 + trainTimeoutHop.
      (File A 953-961, 1283-1329, 1583-1672)
============================================================================ ]]
local Training = {}
do
    local LP = LocalPlayer

    local race_abilities = {
        ["Human"] = "Last Resort", ["Mink"] = "Agility", ["Fishman"] = "Water Body",
        ["Skypiea"] = "Heavenly Blood", ["Ghoul"] = "Heightened Senses",
        ["Cyborg"] = "Energy Core", ["Draco"] = "Primordial Reign",
    }
    Training.race_abilities = race_abilities

    local function checkbackpack(v)
        return (LP.Backpack and LP.Backpack:FindFirstChild(v)) or (LP.Character and LP.Character:FindFirstChild(v))
    end
    Training.checkbackpack = checkbackpack

    -- ===== CACHE LÕI CHO UpgradeRace("Check") =====
    -- Gọi remote 1 lần, chia sẻ cho mọi consumer trong 1 tick.
    -- TTL 1.5s. Raw data: { ok, i, d, f }.
    local _upgradeRaw = { t = -1e9, ok = false, i = nil, d = nil, f = nil }
    local function _getUpgradeRaw()
        local now = tick()
        if (now - _upgradeRaw.t) < 1.5 then
            return _upgradeRaw
        end
        local ok, i, d, f = SafeRemote.invoke(3, "UpgradeRace", "Check")
        _upgradeRaw = { t = now, ok = ok, i = ok and i or nil, d = ok and d or nil, f = ok and f or nil }
        _G.lastRaceI = _upgradeRaw.i
        return _upgradeRaw
    end

    -- trialable (File A 1283-1319) — dùng cache lõi, classify riêng
    function Training.checkTrialable()
        local char = LP.Character
        local raw = _getUpgradeRaw()
        if not (char and char:FindFirstChild("RaceTransformed")) then
            _G.lastRaceI = raw.ok and raw.i or "?"
            if raw.ok and (raw.i == 5 or raw.i == 8) then return false, "done" end
            local race = WorldProbe.getRace()
            local abcxyz = race and checkbackpack(race_abilities[race])
            if abcxyz then return true end
            return false
        end
        if not raw.ok then _G.lastRaceI = "?"; return false end
        _G.lastRaceI = raw.i
        local i, d, f = raw.i, raw.d, raw.f
        if i == 5 or i == 8 then
            return false, "done"
        elseif i == 6 then
            return false, (d or 0) - 2
        elseif i == 1 or i == 3 then
            return false
        elseif i == 2 or i == 4 or i == 7 then
            if f then
                local totalfragments = tonumber(f)
                local frags = 0
                pcall(function() frags = LP.Data.Fragments.Value end)
                if totalfragments and frags >= totalfragments then
                    SafeRemote.invoke(3, "UpgradeRace", "Buy")
                else
                    return false, "raiding"
                end
            end
            return false, f
        elseif i == 0 then
            return true, d
        else
            return false
        end
    end

    -- classifyUpgradeForRole: classifier UpgradeRace("Check") theo role.
    -- MAIN: i==8/5 → main_done (done, không train)
    -- ALLY: i==8/0 → ready_trial; i==5 → done
    -- Trả table { trialable, done, needTrain, canBuyGear, uncertain, i, d, f, reason }
    function Training.checkUpgradeForRole(role)
        local raw = _getUpgradeRaw()
        local i, d, f = raw.i, raw.d, raw.f
        local result = {
            i = i, d = d, f = f,
            trialable = false, done = false,
            needTrain = false, canBuyGear = false,
            uncertain = true, reason = "unknown",
        }
        if not raw.ok or i == nil then
            result.uncertain = true
            result.reason = "check_failed"
        elseif i == 0 then
            result.uncertain = false
            result.trialable = true
            result.reason = "ready_trial"
        elseif i == 8 then
            result.uncertain = false
            if role == "main" then
                result.done = true
                result.reason = "main_done"
            else
                result.trialable = true
                result.reason = "ready_trial"
            end
        elseif i == 5 then
            result.uncertain = false
            result.done = true
            result.reason = role == "main" and "main_done" or "ally_done"
        elseif i == 1 or i == 3 then
            result.uncertain = false
            result.needTrain = true
            result.reason = "need_train"
        elseif i == 6 then
            result.uncertain = false
            result.needTrain = true
            result.reason = "need_train"
        elseif i == 2 or i == 4 or i == 7 then
            result.uncertain = false
            result.canBuyGear = true
            result.reason = "can_buy_gear"
            if f then
                local totalfrags = tonumber(f)
                local frags = 0
                pcall(function() frags = LP.Data.Fragments.Value end)
                if totalfrags and frags >= totalfrags then
                    SafeRemote.invoke(3, "UpgradeRace", "Buy")
                end
            end
        else
            result.uncertain = true
            result.reason = "unknown_i_" .. tostring(i)
        end
        return result
    end

    -- cachedTrialable — đọc từ cache lõi qua checkTrialable (đã dùng _getUpgradeRaw)
    function Training.cachedTrialable()
        return Training.checkTrialable()
    end

    -- pressV4 (File A 1598-1606)
    function Training.pressV4()
        pcall(function()
            local c = LP.Character
            if c and c:FindFirstChild("RaceEnergy") and c.RaceEnergy.Value == 1 then
                VirtualInputManager:SendKeyEvent(true, "Y", false, game)
                VirtualInputManager:SendKeyEvent(false, "Y", false, game)
            end
        end)
    end

    -- trainTimeoutHop (File A 1612-1625) — CHỈ main, dùng hop ít người
    local function trainTimeoutHop(tag)
        if not State.isMain[State.myName] then return false end
        if not _G.trainWinStart then return false end
        if (tick() - _G.trainWinStart) < Config.TRAIN_WINDOW then return false end
        if (_G.trainKills or 0) > 10 then
            _G.trainWinStart = tick(); _G.trainKills = 0
            return false
        end
        status(tag .. " ⏱ Timeout train (kill " .. tostring(_G.trainKills or 0) .. "/5' <=10) → hop server")
        HopServer(("Timeout train kill %d/5phut <=10"):format(_G.trainKills or 0))
        _G.trainWinStart = tick(); _G.trainKills = 0
        return true
    end
    Training.trainTimeoutHop = trainTimeoutHop

    local pos__ = CFrame.new(214.688675, 126.626984, -12600.2236, -0.180400655, -1.09679892e-08, 0.983593225, 1.94620693e-08, 1, 1.47204746e-08, -0.983593225, 2.17983427e-08, -0.180400655)

    -- doTrainGrind (File A 1583-1672)
    function Training.doTrainGrind(tag, AB, reassertFn)
        if reassertFn then reassertFn() end
        if AB == "raiding" then
            local boss = workspace.Enemies:FindFirstChild("Cake Prince") or workspace.Enemies:FindFirstChild("Dough King")
            if boss then
                status(tag .. " Raiding for fragment")
                repeat task.wait()
                    pcall(function() topos(boss.HumanoidRootPart.CFrame * CFrame.new(0, 25, 0)) end)
                    Movement.equip(); Movement.haki(); BringMob()
                until not checkmob_(boss)
            end
            return
        end

        Training.pressV4()
        -- cửa sổ đếm kill (chỉ main) (File A 1626-1633)
        if State.isMain[State.myName] then
            if not _G.trainGrindLastT or (tick() - _G.trainGrindLastT) > 5 then
                _G.trainWinStart = tick(); _G.trainKills = 0
            end
            _G.trainGrindLastT = tick()
            if not _G.trainWinStart then _G.trainWinStart = tick() end
        end

        if getdis(pos__) < 1500 then
            for _, v in ipairs(getmob1(pos__)) do
                if trainTimeoutHop(tag) then return end
                local lastY, lastTf, lastTrainPost = 0, nil, 0
                repeat
                    if trainTimeoutHop(tag) then return end
                    local c  = LP.Character
                    local tf = (c and c:FindFirstChild("RaceTransformed") and c.RaceTransformed.Value) or false
                    if tf then
                        if lastTf ~= true then
                            local hrp = v:FindFirstChild("HumanoidRootPart")
                            if hrp then pcall(function() topos(hrp.CFrame * CFrame.new(0, 150, 0)) end) end
                            status(tag .. " Training (Wait for end V4)")
                            lastTf = true
                        end
                        if (tick() - lastTrainPost) > 4 then if reassertFn then reassertFn() end; lastTrainPost = tick() end
                        task.wait(0.5)
                    else
                        Movement.equip(); Movement.haki(); BringMob()
                        local hrp = v:FindFirstChild("HumanoidRootPart")
                        if hrp then pcall(function() topos(hrp.CFrame * CFrame.new(0, 20, 0)) end) end
                        if lastTf ~= false then
                            status(tag .. " Training (Kill Mobs)")
                            lastTf = false
                        end
                        if (tick() - lastY > 0.4) then lastY = tick(); Training.pressV4() end
                        task.wait()
                    end
                until not checkmob_(v)
                if State.isMain[State.myName] then _G.trainKills = (_G.trainKills or 0) + 1 end
            end
        else
            topos(pos__)
        end
    end

    -- handleTraining(ctx): 1 nhịp grind, trả phase rõ
    function Training.handleTraining(tag, AB, reassertFn)
        Training.doTrainGrind(tag, AB, reassertFn)
        if AB == "raiding" then return "need_fragments" end
        return "training"
    end
end
local function trialable() return Training.checkTrialable() end
local function cachedTrialable() return Training.cachedTrialable() end
local function doTrainGrind(tag, AB, fn) return Training.doTrainGrind(tag, AB, fn) end

--[[ ============================================================================
 [22] ABILITYSYNC — FILE-BASED y chang File A (folder racev4_vunguyen, giờ Hà Nội,
      CommE:FireServer("ActivateAbility")). (File A 2429-2698)
============================================================================ ]]
local AbilitySync = {}
do
    local ABILITY_FIRE_WINDOW = 6
    local AT_DOOR_DIST        = 150
    local START_LEAD          = 5
    local ABILITY_COOLDOWN    = 30
    local TZ_OFFSET           = 7 * 3600
    local SYNC_DIR            = "racev4_vunguyen"
    local START_FILE          = SYNC_DIR .. "/starttime.txt"
    AbilitySync.AT_DOOR_DIST  = AT_DOOR_DIST

    _G.myFireEpoch = _G.myFireEpoch or 0

    function AbilitySync.ensureSyncDir()
        if isfolder and not isfolder(SYNC_DIR) then pcall(function() makefolder(SYNC_DIR) end) end
    end
    AbilitySync.ensureSyncDir()
    -- dọn file cũ ở thư mục gốc (File A 2452-2458)
    pcall(function()
        if isfile and delfile then
            if isfile("checkalready.txt") then delfile("checkalready.txt") end
            if isfile("starttime.txt") then delfile("starttime.txt") end
        end
    end)

    -- giờ Hà Nội (File A 2502-2516)
    local function hanoiSecOfDay(epoch) return math.floor(epoch + TZ_OFFSET) % 86400 end
    local function fmtHanoi(epoch)
        local s = hanoiSecOfDay(epoch)
        return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
    end
    local function parseHanoi(str)
        local h, m, s = string.match(str or "", "(%d+):(%d+):(%d+)")
        if not h then return nil end
        return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
    end

    local function checkFileForLabel(label) return SYNC_DIR .. "/checkalready_" .. string.lower(label) end

    -- toạ độ cửa dự phòng (toạ độ chuẩn Temple of Time, kèm rotation)
    local BANANA_DOOR_CFRAME = {
        Ghoul   = CFrame.new(28673.1953, 14895.6953, 456.095001, -1, 0, 0, 0, 1, 0, 0, 0, -1),
        Cyborg  = CFrame.new(28490.5781, 14900.9951, -422.574005, 0, 0, 1, 0, 1, -0, -1, 0, 0),
        Fishman = CFrame.new(28222.3594, 14895.9961, -211.544006, 0, 0, 1, 0, 1, -0, -1, 0, 0),
        Human   = CFrame.new(29238.8906, 14896.1953, -206.444, 0, 0, -1, 0, 1, 0, 1, 0, 0),
        Mink    = CFrame.new(29022.4375, 14896.1953, -379.760986, 0, 0, -1, 0, 1, 0, 1, 0, 0),
        Skypiea = CFrame.new(28970.0469, 14924.6377, 234.285995, 0, 0, -1, 0, 1, 0, 1, 0, 0),
    }

    -- khoảng cách tới cửa (ưu tiên part thật, fallback Banana) (File A 2480-2498)
    function AbilitySync.distToMyDoor()
        local door = getdoor()
        if door then
            local d = getdis(door.CFrame)
            _G.lastDoorSrc, _G.lastDoorName, _G.lastDoorDist = "R", door.Name, d
            return d
        end
        local cf = BANANA_DOOR_CFRAME[WorldProbe.getRace()]
        if cf then
            local d = getdis(cf)
            _G.lastDoorSrc, _G.lastDoorName, _G.lastDoorDist = "B", "banana", d
            return d
        end
        _G.lastDoorSrc, _G.lastDoorName, _G.lastDoorDist = "X", "none", 1e9
        return 1e9
    end

    -- SAME = mình đang ở ĐÚNG server full moon Ally1 đã chốt (fullmoonJobid) — điểm hẹn chung
    -- của Main + 2 Ally (user 2026-07-02). Trước đây trả true vô điều kiện khi myName==curName,
    -- hoặc auto-true khi đứng fullmoonJobid mà main1 chưa chắc ở đó → SAME giả. Giờ CHỈ dựa vào
    -- game.JobId == fullmoonJobid: main1 và ally cùng so với 1 mốc → "same" chỉ khi thật sự tụ đúng chỗ.
    local _ssCache = { t = -1e9, v = false }
    function AbilitySync.sameServerAsCurrentMain()
        local fm = State.fullmoonJobid
        if fm and fm ~= "" then
            return game.JobId == fm
        end
        -- chưa chốt full moon → chưa có điểm hẹn → không thể "same"
        return false
    end

    function AbilitySync.allyIndexOf(nm)
        for i, v in ipairs(Config.allies) do if v == nm then return i end end
        return nil
    end

    -- label của mình (File A 2545-2553)
    function AbilitySync.myAbilityLabel()
        local curName, curIdx = getCurrentMainBeingUpgraded()
        if curName and State.myName == curName then return "Main" .. tostring(curIdx) end
        local ai = AbilitySync.allyIndexOf(State.myName)
        if ai then return "Ally" .. ai end
        return nil
    end

    -- nhãn bắt buộc true để chốt giờ: main turn + toàn bộ ally (File A 2556-2564)
    function AbilitySync.requiredLabels()
        local _curName, curIdx = getCurrentMainBeingUpgraded()
        local labels = {}
        if curIdx then table.insert(labels, "Main" .. tostring(curIdx)) end
        for i, _ in ipairs(Config.allies) do table.insert(labels, "Ally" .. i) end
        return labels
    end

    -- canactive: đã qua cooldown 30s (File A 2568-2572)
    function AbilitySync.myCanActive()
        local fe = _G.myFireEpoch or 0
        if fe <= 0 then return true end
        return serverNow() >= (fe + ABILITY_COOLDOWN)
    end

    -- đọc ready 1 label (File A 2576-2584)
    function AbilitySync.readLabelReady(label)
        local fp = checkFileForLabel(label)
        if not (isfile and isfile(fp)) then return false end
        local ok, data = pcall(readfile, fp)
        if not ok or not data then return false end
        local door = string.match(data, "doorandability=(%w+)") == "true"
        local cana = string.match(data, "canactiveability=(%w+)") == "true"
        return door and cana
    end

    -- ghi file riêng của mình (File A 2588-2599)
    function AbilitySync.writeMyCheck(label, cond)
        if not label then return end
        AbilitySync.ensureSyncDir()
        local fe = _G.myFireEpoch or 0
        local fireStr = (fe > 0) and fmtHanoi(fe) or "00:00:00"
        pcall(function()
            writefile(checkFileForLabel(label),
                label .. ":doorandability=" .. (cond and "true" or "false")
                .. ";canactiveability=" .. (AbilitySync.myCanActive() and "true" or "false")
                .. ";" .. fireStr)
        end)
    end

    -- đủ tất cả nhãn (File A 2602-2609)
    function AbilitySync.allReady()
        local req = AbilitySync.requiredLabels()
        if #req == 0 then return false end
        for _, lb in ipairs(req) do
            if not AbilitySync.readLabelReady(lb) then return false end
        end
        return true
    end

    -- đọc starttime (File A 2612-2617)
    function AbilitySync.readStart()
        if not (isfile and isfile(START_FILE)) then return nil end
        local ok, data = pcall(readfile, START_FILE)
        if not ok or not data then return nil end
        return parseHanoi((string.gsub(data, "%s", "")))
    end
    -- ghi starttime (main turn chốt) (File A 2649)
    function AbilitySync.writeStart(epoch)
        AbilitySync.ensureSyncDir()
        pcall(function() writefile(START_FILE, fmtHanoi(epoch)) end)
    end

    -- reportAtDoor: ghi check của mình (giữ tên module-style; nội dung = writeMyCheck)
    function AbilitySync.reportAtDoor()
        local label = AbilitySync.myAbilityLabel()
        if not label then return end
        local dd = AbilitySync.distToMyDoor()
        local ss = AbilitySync.sameServerAsCurrentMain()
        _G.lastDoorDist = dd; _G.lastSameSrv = ss
        local cond = (dd < AT_DOOR_DIST) and ss
        _G.myDoorReady = cond and true or false
        AbilitySync.writeMyCheck(label, cond)
    end
    -- maybeFire: main turn chốt starttime khi đủ ready (File A 2641-2651)
    function AbilitySync.maybeFire()
        local curName = getCurrentMainBeingUpgraded()
        if not (curName and State.myName == curName) then return end
        local now = serverNow()
        local last = _G.myStartEpoch or 0
        if (now - last) > (START_LEAD + ABILITY_FIRE_WINDOW) and AbilitySync.allReady() then
            AbilitySync.writeStart(now + START_LEAD)
            _G.myStartEpoch = now
        end
    end
    -- pressAbility: CommE ActivateAbility (File A 2688)
    function AbilitySync.pressAbility()
        _G.myFireEpoch = serverNow()
        pcall(function()
            ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
        end)
    end
    -- pollFire: đọc starttime, bấm trong cửa sổ hợp lệ, latch chống lặp (File A 2673-2698)
    function AbilitySync.pollFire()
        local st = AbilitySync.readStart() or _G.syncStart
        if st then _G.syncStart = st end
        if st and st ~= _G.allyLastFire then
            local age = hanoiSecOfDay(serverNow()) - st
            if age < -43200 then age = age + 86400 end
            if age >= ABILITY_FIRE_WINDOW then
                _G.allyLastFire = st
            elseif age >= 0 and AbilitySync.distToMyDoor() < AT_DOOR_DIST then
                _G.allyLastFire = st
                AbilitySync.pressAbility()
            end
        end
    end

    -- ===== 3 LOOP NỀN (y chang File A 2623-2698), check Runtime.alive =====
    function AbilitySync.startLoops()
        -- write loop 1s (File A 2623-2657)
        task.spawn(function()
            while Runtime.alive do
                pcall(function()
                    _G.myDoorReady = false
                    local label = AbilitySync.myAbilityLabel()
                    if label then
                        local dd = AbilitySync.distToMyDoor()
                        local ss = AbilitySync.sameServerAsCurrentMain()
                        _G.lastDoorDist = dd; _G.lastSameSrv = ss
                        local cond = (dd < AT_DOOR_DIST) and ss
                        _G.myDoorReady = cond and true or false
                        AbilitySync.writeMyCheck(label, cond)
                        local curName = getCurrentMainBeingUpgraded()
                        if curName and State.myName == curName then
                            local now = serverNow()
                            local last = _G.myStartEpoch or 0
                            if (now - last) > (START_LEAD + ABILITY_FIRE_WINDOW) and AbilitySync.allReady() then
                                AbilitySync.writeStart(now + START_LEAD)
                                _G.myStartEpoch = now
                            end
                        end
                    end
                end)
                task.wait(1)
            end
        end)
        -- read starttime loop 1s (File A 2660-2668)
        task.spawn(function()
            while Runtime.alive do
                pcall(function()
                    local v = AbilitySync.readStart()
                    if v then _G.syncStart = v end
                end)
                task.wait(1)
            end
        end)
        -- press loop: ở cửa+ready → 0.1s, chưa → 0.5s (File A 2673-2698)
        task.spawn(function()
            while Runtime.alive do
                if _G.myDoorReady == true then
                    pcall(function()
                        local st = AbilitySync.readStart() or _G.syncStart
                        if st then _G.syncStart = st end
                        if st and st ~= _G.allyLastFire then
                            local age = hanoiSecOfDay(serverNow()) - st
                            if age < -43200 then age = age + 86400 end
                            if age >= ABILITY_FIRE_WINDOW then
                                _G.allyLastFire = st
                            elseif age >= 0 and AbilitySync.distToMyDoor() < AT_DOOR_DIST then
                                _G.allyLastFire = st
                                AbilitySync.pressAbility()
                            end
                        end
                    end)
                    task.wait(0.1)
                else
                    task.wait(0.5)
                end
            end
        end)
    end
end

--[[ ============================================================================
 [23] POSTTRIAL — ffup = kill phase/reset. helpreset main/ally. (File A 1855-2025)
============================================================================ ]]
local PostTrial = {}
do
    local B = Config.baseUrl

    -- Ally auto-reset 1 lần (File A 1966-1982)
    function PostTrial.resetAllyOnce(roleName)
        if _G.allyKillReset then return "ally_reset" end
        _G.allyKillReset = true
        status(roleName .. " Kill-player → AUTO RESET (ally)")
        task.spawn(function()
            pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
            task.wait(1)
            Net.postJSON(B .. "/helpreset", { name = State.myName }, "helpreset")
        end)
        return "ally_reset"
    end

    -- Current main chờ helpreset đủ rồi tự sát + chuyển training (File A 1992-2010)
    function PostTrial.currentMainReset(myStt)
        local allies_str = table.concat(Config.allies, ",")
        if allies_str ~= "" then
            status("[MAIN " .. tostring(myStt) .. "] Waiting for help accs to reset first...")
            local timeout = 0
            repeat
                task.wait(1)
                timeout = timeout + 1
                local res = Net.getJSON(B .. "/helpreset?allies=" .. allies_str, 0)
                if res and res.all_done then break end
            until timeout >= Config.HELPRESET_TIMEOUT
        end
        pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
        task.wait(3)
        State.setMyMainStatus("training")
        Net.postJSON(B .. "/helpreset/clear", {}, "helpreset_clear")
        return "main_reset_done"
    end

    -- Main phụ delay reset (File A 2011-2019)
    function PostTrial.otherMainReset()
        task.spawn(function()
            local delay = (#Config.allies * 2) + 4 + math.random(0, 3)
            task.wait(delay)
            pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
            task.wait(1)
            Net.postJSON(B .. "/helpreset", { name = State.myName }, "helpreset")
        end)
        return "other_main_reset"
    end

    -- Main đang turn (current) kill player trong tầm rồi reset (File A 1984-2020)
    function PostTrial.mainKillThenReset(myStt, currentmain)
        status("[MAIN " .. tostring(myStt) .. "] Kill Players After Trial")
        for plr in pairs(getplayers()) do
            if plr then
                repeat task.wait() attackTick(plr)
                until not plr or not plr.Parent or not plr:FindFirstChild("Humanoid")
                    or not plr:FindFirstChild("HumanoidRootPart") or plr.Humanoid.Health <= 0
                    or templeState() ~= "ffup"
            end
        end
        _G.SHOULDSPAMSKILLS = false
        if countplayers() <= 0 then
            local isCurrentMain = State.isMain[State.myName] and State.myName == currentmain
            local isOtherMain   = State.isMain[State.myName] and State.myName ~= currentmain
            if isCurrentMain then
                return PostTrial.currentMainReset(myStt)
            elseif isOtherMain then
                return PostTrial.otherMainReset()
            end
        end
        return "posttrial_running"
    end
end

--[[ ============================================================================
 [24] TEAMMANAGER — join team bền + recovery loop sau hop.
 ensureTeamSelected() có retry mềm, pcall đúng cách. (File A 528-559)
============================================================================ ]]
local startGameReadyGate
local TeamManager = {}
TeamManager.started = false
TeamManager._started = false
TeamManager._selecting = false

function TeamManager.ensureTeamSelected()
    if not Runtime.alive then return end
    if LocalPlayer.Team then return true end
    local team = Config.team
    local timeout = 60
    local t0 = tick()
    local attempt = 0
    while Runtime.alive and not LocalPlayer.Team and (tick() - t0) < timeout do
        attempt = attempt + 1
        if attempt == 1 or (attempt % 10) == 0 then
            Logger.info("[TEAM] choosing team (attempt " .. tostring(attempt) .. ")", "team_choose")
        end
        SafeRemote.invoke(3, "SetTeam", team)
        task.wait(0.5)
        if LocalPlayer.Team then
            Logger.ok("[TEAM] selected (" .. tostring(team) .. ") attempt=" .. tostring(attempt), "team_ok")
            return true
        end
        -- pcall đúng: nhận cả ok + result
        local ok, chooseGui = pcall(function()
            return LocalPlayer.PlayerGui:FindFirstChild("ChooseTeam", true)
        end)
        if ok and chooseGui and chooseGui.Visible then
            local ok2, uiCtrl = pcall(function()
                return LocalPlayer.PlayerGui:FindFirstChild("UIController", true)
            end)
            if ok2 and uiCtrl and getgc then
                for _, fn in pairs(getgc(true)) do
                    if type(fn) == "function" and getfenv(fn).script == uiCtrl then
                        local consts = getconstants(fn)
                        if consts and #consts == 1 and (consts[1] == "Pirates" or consts[1] == "Marines") then
                            if consts[1] == team then pcall(fn, team) end
                        end
                    end
                end
            end
            -- FIX hop→team: fallback firesignal nút ChooseTeam (File A 179-184) — dùng khi SetTeam/getgc
            -- không chọn được team trên server mới vừa hop. Movement.joinTeam trước đó là dead code.
            pcall(function() Movement.joinTeam(team) end)
        end
        task.wait(1)
    end
    if not LocalPlayer.Team then
        Logger.warn("[TEAM] timeout sau " .. tostring(timeout) .. "s, tiếp tục retry nền", "team_timeout")
    end
    return LocalPlayer.Team ~= nil
end

local function startTeamRecoveryLoop()
    task.spawn(function()
        -- FIX hop→team: KHÔNG wait 10s nữa. Ngay sau boot/hop, ChooseTeam có thể xuất hiện trong
        -- vài giây đầu rồi tự đóng nếu không click kịp. Poll 0.5s trong 60s đầu, sau đó 2s.
        local startT = tick()
        while Runtime.alive do
            local elapsed = tick() - startT
            task.wait(elapsed < 60 and 0.5 or 2)
            if not TeamManager._started then break end
            if LocalPlayer.Team then
                -- đã có team, thỉnh thoảng check lại phòng mất team (server reset, hop mới)
                task.wait(3)
            else
                -- chưa có team → thử ngay
                Logger.info("[TEAM] missing team, retrying", "team_missing")
                status("Recovering team...")
                TeamManager.ensureTeamSelected()
            end
        end
    end)
    -- FIX hop→team: lắng nghe ChooseTeam xuất hiện trong PlayerGui (signal-based, không phụ thuộc poll interval)
    task.spawn(function()
        while Runtime.alive do
            local pgui = LocalPlayer:FindFirstChild("PlayerGui")
            if pgui then
                pgui.ChildAdded:Connect(function(child)
                    if not Runtime.alive then return end
                    if not child:FindFirstChild("ChooseTeam") then return end
                    -- ChooseTeam screen vừa xuất hiện → chọn team ngay
                    task.wait(0.1) -- 1 frame để UI init
                    if not LocalPlayer.Team then
                        Logger.info("[TEAM] ChooseTeam detected (signal) → ensureTeamSelected", "team_signal")
                        status("ChooseTeam detected → selecting team...")
                        TeamManager.ensureTeamSelected()
                    end
                end)
                -- cũng check DescendantAdded phòng ChooseTeam nằm trong ScreenGui con
                pgui.DescendantAdded:Connect(function(desc)
                    if not Runtime.alive then return end
                    if desc.Name ~= "ChooseTeam" then return end
                    task.wait(0.1)
                    if not LocalPlayer.Team then
                        Logger.info("[TEAM] ChooseTeam descendant detected (signal) → ensureTeamSelected", "team_signal_desc")
                        TeamManager.ensureTeamSelected()
                    end
                end)
                break
            end
            task.wait(0.5)
        end
    end)
end

function TeamManager.start()
    if TeamManager.started then return end
    TeamManager.started = true
    Logger.info("[BOOT] waiting game ready", "boot_team")
    startGameReadyGate()
    -- FIX hop→team: bật _started TRƯỚC khi gọi ensureTeamSelected (blocking tới 60s).
    -- Nếu không, recovery loop (break khi not _started) sẽ chết vĩnh viễn lúc server mới
    -- load chậm sau hop → không còn ai chọn lại team.
    TeamManager._started = true
    startTeamRecoveryLoop()
    task.spawn(function()
        Logger.info("[TEAM] choosing team", "team_start")
        TeamManager.ensureTeamSelected()
    end)
end

--[[ ============================================================================
[25] SEAMANAGER — đảm bảo Sea3 (check PlaceId), travel nếu chưa. (File A 14-33)
============================================================================ ]]
local SeaManager = {}
function SeaManager.start()
    if Config.SEA3_PLACEIDS[game.PlaceId] then return end
    task.spawn(function()
        while Runtime.alive and not Config.SEA3_PLACEIDS[game.PlaceId] do
            pcall(function()
                local R = ReplicatedStorage.Remotes.CommF_
                if Config.SEA2_PLACEIDS[game.PlaceId] then
                    R:InvokeServer("TravelZou")        -- Sea2 → Sea3
                else
                    R:InvokeServer("TravelDressrosa")  -- Sea1/khác → Sea2
                end
            end)
            task.wait(5)
        end
    end)
end

--[[ ============================================================================
 [26] TEMPLE DOOR GATE — check 1 lần rồi ghi file riêng account. (File A 1519-1539)
============================================================================ ]]
local TempleDoorGate = {}
do
    local FILE = Config.myName .. "_kaitunv4.json"
    function TempleDoorGate.ready()
        if _G.templeDoorOK then return true end
        local fdata = FileStore.readJson(FILE, {})
        if fdata.templedoor == true then _G.templeDoorOK = true; return true end
        local ok, res = SafeRemote.invoke(3, "CheckTempleDoor")
        if ok and res then
            _G.templeDoorOK = true
            FileStore.writeJson(FILE, { templedoor = true })
            return true
        end
        return res
    end
end

--[[ ============================================================================
[27] ALLY TRAINING GATE — ally chỉ train khi xác nhận ổn định.
Mặc định giữ ready_trialing. Dùng Training.checkUpgradeForRole("ally").
Map UpgradeRace ally: i==8/0 → ready_trial, i==5 → done.
(File A: fix ally training quá sớm)
============================================================================ ]]
local AllyTrainingGate = {}
do
    AllyTrainingGate.started = false
    AllyTrainingGate.state = "ready_trialing"
    AllyTrainingGate.lastReadyAt = tick()
    AllyTrainingGate.notReadySince = 0
    AllyTrainingGate.confirmCount = 0
    AllyTrainingGate.lastI = nil

    function AllyTrainingGate.start()
        if AllyTrainingGate.started then return end
        AllyTrainingGate.started = true
        AllyTrainingGate.lastReadyAt = tick()
    end

    function AllyTrainingGate.tick(roleName)
        if not AllyTrainingGate.started then AllyTrainingGate.start() end
        if State.isMain[State.myName] then
            return "ready_trialing", "is_main", nil
        end
        local result = Training.checkUpgradeForRole("ally")
        local i = result.i
        local eval = result.reason
        local now = tick()

        if eval == "ready_trial" then
            AllyTrainingGate.confirmCount = 0
            AllyTrainingGate.notReadySince = 0
            AllyTrainingGate.lastReadyAt = now
            AllyTrainingGate.lastI = i
            Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=" .. eval .. " confirm=0", "ally_gate_ready")
            AllyTrainingGate.state = "ready_trialing"
            return "ready_trialing", eval, i
        end

        if eval == "done" or eval == "ally_done" then
            AllyTrainingGate.confirmCount = 0
            AllyTrainingGate.notReadySince = 0
            AllyTrainingGate.lastReadyAt = now
            AllyTrainingGate.lastI = nil
            Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=" .. eval .. " confirm=0", "ally_gate_done")
            AllyTrainingGate.state = "ready_trialing"
            return "ready_trialing", eval, i
        end

        if eval == "need_train" then
            if i ~= AllyTrainingGate.lastI then
                AllyTrainingGate.lastI = i
                AllyTrainingGate.confirmCount = 1
                AllyTrainingGate.notReadySince = now
                Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=need_train_first confirm=1", "ally_gate_first")
                AllyTrainingGate.state = "ready_trialing"
                return "ready_trialing", "need_train_first", i
            end
            local stable = (now - AllyTrainingGate.notReadySince) >= 3
            AllyTrainingGate.confirmCount = AllyTrainingGate.confirmCount + 1
            if stable and AllyTrainingGate.confirmCount >= 3 and (now - AllyTrainingGate.lastReadyAt) >= 5 then
                Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=training reason=confirmed confirm=" .. tostring(AllyTrainingGate.confirmCount), "ally_gate_train")
                AllyTrainingGate.state = "training"
                return "training", "confirmed", i
            else
                local reasonStr = "need_train_stable_" .. tostring(math.floor(now - AllyTrainingGate.notReadySince)) .. "s"
                Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=" .. reasonStr .. " confirm=" .. tostring(AllyTrainingGate.confirmCount), "ally_gate_checking")
                AllyTrainingGate.state = "ready_trialing"
                return "ready_trialing", reasonStr, i
            end
        end

        if eval == "can_buy_gear" then
            AllyTrainingGate.confirmCount = 0
            AllyTrainingGate.notReadySince = 0
            AllyTrainingGate.lastI = nil
            Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=can_buy confirm=0", "ally_gate_buy")
            AllyTrainingGate.state = "ready_trialing"
            return "ready_trialing", eval, i
        end

        -- unknown / check_failed
        AllyTrainingGate.confirmCount = 0
        AllyTrainingGate.notReadySince = 0
        AllyTrainingGate.lastI = nil
        Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=" .. eval .. " confirm=0", "ally_gate_unknown")
        AllyTrainingGate.state = "ready_trialing"
        return "ready_trialing", eval, i
    end

    function AllyTrainingGate.reset()
        AllyTrainingGate.confirmCount = 0
        AllyTrainingGate.notReadySince = 0
        AllyTrainingGate.state = "ready_trialing"
    end
end

--[[ ============================================================================
[27b] GAME READY GATE — chờ team/char/data (timeout 45s), KHÔNG block.
(File A 1549-1568)
============================================================================ ]]
startGameReadyGate = function()
    Logger.info("[BOOT] waiting game ready", "boot_gate")
    task.spawn(function()
        local t0 = tick()
        repeat
            task.wait(0.2)
            local c   = LocalPlayer.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local ready = LocalPlayer.Team
                and c and c:FindFirstChild("HumanoidRootPart")
                and hum and hum.Health > 0
                and LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Race")
            if ready then
                Logger.info("[BOOT] playergui ready", "boot_ok_pgui")
                break
            end
        until (tick() - t0) > 45
        _G.gameReady = true
        Logger.ok(("[BOOT] game ready (%.1fs elapsed)"):format(tick() - t0), "boot_ok")
    end)
end

--[[ ============================================================================
 [27c] SCOUTNAVIGATOR — LỚP ĐIỀU HƯỚNG MỎNG (chỉ teleport, KHÔNG chặn trial gốc).
   tick(ctx) → true = đã điều hướng, dừng tick lượt này; false = đã ở đúng nơi → THẢ
   xuống logic trial/training gốc. Fullmoon-join 100% do server + 2 Ally.
============================================================================ ]]
local ScoutNavigator = {}
do
    local _lastAllyHoldHop = 0
    local _lastMainJoinSpam = 0
    local _allyFmConfirmedAt = 0   -- tick lần cuối isfullmoon()==true khi đang đứng ĐÚNG target (chống flicker rời sớm)
    local ALLY_FM_GRACE = 8        -- giây: moon "tắt" dưới ngưỡng này coi là flicker (world chưa load) → VẪN giữ server

    -- Ally1/Ally2 = 2 ally đầu theo thứ tự config
    local function isScoutAlly()
        if State.myRole ~= "ally" then return false end
        for i, nm in ipairs(Config.allies or {}) do
            if nm == Config.myName and i <= (State.requiredAllies or 2) then return true end
        end
        return false
    end
    _G.isScoutAlly = isScoutAlly

    -- Ally1 (LEADER) = ally đầu tiên online do server chốt (ally_leader từ /curmain).
    -- Fallback: nếu server chưa cấp → dùng ally đầu trong Config online. Ally1 là AUTHORITY:
    -- tự /getseverapi (đúng placeid) → hop → xác nhận còn FM → /lockmoon. Ally2 chờ jobid đã chốt rồi join.
    local function isAllyLeader()
        if not isScoutAlly() then return false end
        if State.allyLeader and State.allyLeader ~= "" then
            return State.allyLeader == Config.myName
        end
        -- fallback: ally đầu tiên trong Config == mình
        for _, nm in ipairs(Config.allies or {}) do
            if State.myRole == "ally" then return nm == Config.myName end
        end
        return false
    end
    _G.isAllyLeader = isAllyLeader

    local _lastGetSeverApi = 0     -- chống spam /getseverapi
    local _getSeverApiCooldown = 5  -- giây: Ally1 detect hết FM + xin server mới mỗi 5s (yêu cầu user)
    local _joinMoonReported = false -- tránh POST liên tục khi đang hop
    local _leaderTarget = nil       -- jobid Ally1 tự xin từ /getseverapi (trước khi server chốt)
    local _lastLockMoon = 0         -- chống spam /lockmoon

    -- Ally1 xin server full moon mới (server lọc đúng placeid của Ally1) → set _leaderTarget để hop.
    local function leaderRequestServer(reasonTag)
        if (tick() - _lastGetSeverApi) < _getSeverApiCooldown then return end
        _lastGetSeverApi = tick()
        local placeId = tostring(game.PlaceId)
        task.spawn(function()
            local url = endpoint("/getseverapi", { name = Config.myName, placeid = placeId })
            local ok, body = Net.getRaw(url)
            if ok and body then
                local good, res = pcall(function() return HttpService:JSONDecode(body) end)
                if good and res and res.ok and res.jobid and res.jobid ~= "" then
                    _leaderTarget = tostring(res.jobid)
                    Logger.info("[ALLY1-GETSEV] " .. tostring(reasonTag) .. " server cấp jobid=" .. _leaderTarget
                        .. " (placeid=" .. placeId .. ")", "ally1_getsev")
                else
                    Logger.info("[ALLY1-GETSEV] không có server phù hợp placeid=" .. placeId, "ally1_getsev_nil")
                end
            end
        end)
    end

    -- Ally1 báo server HẾT full moon (phá lock để mọi main dừng join) — chỉ khi đang lock đúng jobid.
    local function leaderReportFmLost(lostJob)
        task.spawn(function()
            pcall(function()
                Net.postJSON(endpoint("/fmlost", { name = Config.myName }),
                    { jobid = lostJob }, "fmlost_" .. tostring(lostJob))
            end)
        end)
    end

    -- ===== Ally1 (LEADER): tự pick server (đúng placeid) → hop → xác nhận còn FM → /lockmoon → giữ =====
    local function allyLeaderTick()
        -- đã có server chốt (fullmoonJobid) → coi đó là đích; chưa có → dùng _leaderTarget tự xin
        local target = State.fullmoonJobid or _leaderTarget
        if not target then
            leaderRequestServer("[no-target]")
            State.reportStatus("moon")
            status("[ALLY1] Xin server full moon (placeid=" .. tostring(game.PlaceId) .. ")...")
            return true
        end
        if game.JobId ~= target then
            -- ĐANG HOP tới server candidate
            _allyFmConfirmedAt = 0
            if not _joinMoonReported then _joinMoonReported = true; State.reportStatus("join_moon") end
            if (tick() - _lastAllyHoldHop) >= (State.joinSpamInterval or 5) then
                _lastAllyHoldHop = tick()
                status("[ALLY1] Hop vào server full moon: " .. tostring(target))
                _G.allyHopArmedT = tick()
                TeleportManager.hopToJob(target, "[ALLY1-JOIN-FULLMOON]")
            end
            return true
        end
        -- ĐÃ Ở target
        _joinMoonReported = false
        if isfullmoon() then
            _allyFmConfirmedAt = tick()
            -- CÒN full moon → CHỐT lên server (/lockmoon) + giữ + báo ally
            if State.fullmoonJobid ~= target and (tick() - _lastLockMoon) >= 3 then
                _lastLockMoon = tick()
                task.spawn(function()
                    pcall(function()
                        Net.postJSON(endpoint("/lockmoon", { name = Config.myName }),
                            { jobid = target }, "lockmoon_" .. tostring(target))
                    end)
                end)
            end
            State.reportStatus("ally")
            status("[ALLY1] Holding FullMoon " .. tostring(target) .. " → CHỐT + ally")
            return false
        elseif _allyFmConfirmedAt > 0 and (tick() - _allyFmConfirmedAt) < ALLY_FM_GRACE then
            -- flicker (world chưa load lại sau hop) → coi như vẫn còn
            State.reportStatus("ally")
            status("[ALLY1] moon flicker (" .. string.format("%.1f", tick() - _allyFmConfirmedAt) .. "s) → giữ")
            return false
        else
            -- HẾT full moon THẬT → phá lock + xin server mới (check mỗi 5s như user yêu cầu)
            _allyFmConfirmedAt = 0
            _leaderTarget = nil
            if State.fullmoonJobid == target then leaderReportFmLost(target) end
            leaderRequestServer("[fm-ended]")
            State.reportStatus("moon")
            status("[ALLY1] FullMoon HẾT → /fmlost + xin server mới...")
            return true
        end
    end

    -- ===== Ally2 (FOLLOWER): CHỜ Ally1 chốt (fullmoonJobid) rồi join theo. KHÔNG tự pick server. =====
    local function allyFollowerTick()
        local target = State.fullmoonJobid   -- chỉ join khi ĐÃ chốt (không dùng candidate/allyTarget mơ hồ)
        if not target then
            _allyFmConfirmedAt = 0
            State.reportStatus("moon")
            status("[ALLY2] Chờ Ally1 chốt server full moon...")
            return true
        end
        if game.JobId ~= target then
            _allyFmConfirmedAt = 0
            if not _joinMoonReported then _joinMoonReported = true; State.reportStatus("join_moon") end
            if (tick() - _lastAllyHoldHop) >= (State.joinSpamInterval or 5) then
                _lastAllyHoldHop = tick()
                status("[ALLY2] Join server full moon Ally1 đã chốt: " .. tostring(target))
                _G.allyHopArmedT = tick()
                TeleportManager.hopToJob(target, "[ALLY2-JOIN-FULLMOON]")
            end
            return true
        end
        _joinMoonReported = false
        if isfullmoon() then
            _allyFmConfirmedAt = tick()
            State.reportStatus("ally")
            status("[ALLY2] Holding FullMoon " .. tostring(target) .. " → ally")
            return false
        elseif _allyFmConfirmedAt > 0 and (tick() - _allyFmConfirmedAt) < ALLY_FM_GRACE then
            State.reportStatus("ally")
            status("[ALLY2] moon flicker → giữ")
            return false
        else
            -- Ally2 thấy hết FM → KHÔNG tự xin server (để Ally1 quyết). Chờ server đổi fullmoonJobid.
            _allyFmConfirmedAt = 0
            State.reportStatus("moon")
            status("[ALLY2] FullMoon hết, chờ Ally1 chốt server mới...")
            return true
        end
    end

    local function allyTick()
        if not isScoutAlly() then
            State.reportStatus("moon")
            status("[ALLY] Scout standby (không phải Ally1/Ally2)")
            return true
        end
        if isAllyLeader() then return allyLeaderTick() end
        return allyFollowerTick()
    end

    local function mainTick(ctx)
        local myStatus = ctx.myStatus
        -- FIX stt1: ưu tiên current do server /curmain cấp (Promt.md §XI dòng 630) → detect main stt1 đúng
        local currentmain = State.serverCurMain or ctx.currentmain
        local fmJob = State.fullmoonJobid

        -- training → hop server ít người (1 lần) rồi THẢ xuống training gốc; done → thả gốc (changefolder)
        -- FIX #4 (user 2026-07-02): CHỈ hop training server sau khi ĐÃ thực sự in_trail lượt này
        -- (_G.didTrialInFM). Nếu chuyển "training" mà CHƯA in_trail (vd cần train i=1/3) → KHÔNG hop,
        -- train TẠI CHỖ. Tránh "Trial done → hop" khống lúc vừa vào server + cắt loop i=3 hop-ra-join-lại.
        if myStatus == "training" then
            if fmJob and game.JobId == fmJob and _G.didTrialInFM and not _G.trainingHopped then
                _G.trainingHopped = true
                _G.didTrialInFM = false
                State.didEnterTrialThisTurn = false -- BS-5: rời fullmoon để training → reset
                status("[TRAINING] In_trial xong → hop low-player training server")
                TeleportManager.hopTrainingServer("[AFTER-TRIAL-TRAINING]")
                return true
            end
            return false
        end
        if myStatus == "done" then return false end
        _G.trainingHopped = false

        -- FIX #3 (user 2026-07-02): TRƯỚC khi join full moon phải check còn cần training không.
        -- Đã xác nhận cần train 3 lần (ctx.trainConfirmed) → KHÔNG join/ready FM, thả xuống StateMachine
        -- để train trước (chặn lỗi i=3: join FM → phát hiện cần train → hop ra → gate còn mở → join lại → loop).
        if ctx.trainConfirmed then return false end

        -- CHƯA lock full moon (hoặc chưa có fmJob) → current báo moon + "Waiting for Ally"; con khác chờ
        -- FIX stt1: thêm "or not fmJob" (Promt.md §XI dòng 639) → tránh hopToJob(nil) khi lock mà jobid chưa propagate
        if not State.fullmoonLocked or not fmJob then
            if currentmain == Config.myName then
                State.setMyMainStatus("moon")
                status("[MAIN] Waiting for Ally (chờ 2 Ally giữ full moon)...")
            else
                -- SPEC MỚI (user 2026-07-02): Main2-6 chờ = "waiting" (KHÔNG để kẹt "checking" từ check window)
                if myStatus ~= "waiting" then State.setMyMainStatus("waiting") end
                status("[MAIN] Waiting for Ally...")
            end
            return true
        end

        -- ĐÃ lock. Main1/current vào TRƯỚC
        if currentmain == Config.myName then
            if game.JobId ~= fmJob then
                -- FIX (user 2026-07-02): CHỈ join full moon khi ĐÃ xác nhận trial được 3 lần (trialConfirmed).
                -- Chưa xác nhận (mới vào server, _G streak reset) → return false, train/grind tại chỗ, KHÔNG join.
                if not ctx.trialConfirmed then return false end
                if (tick() - _lastMainJoinSpam) >= (State.joinSpamInterval or 5) then
                    _lastMainJoinSpam = tick()
                    State.setMyMainStatus("moon")
                    status("[MAIN1] Join server Ally: " .. tostring(fmJob))
                    TeleportManager.hopToJob(fmJob, "[MAIN1-JOIN-FULLMOON]")
                end
                return true
            end
            -- ĐÃ ở FM cùng Ally → ready → THẢ xuống my-turn gốc (door/trial/kill)
            State.setMyMainStatus("ready")
            status("[MAIN1] In FullMoon with Ally → Ready for trialing")
            return false
        end

        -- Main2-6: CHỈ spam join khi đủ 4 cờ (Promt.md §6): locked + gate_open + gate_opened_once + fmJob
        -- (gate_open ≈ Main1 đã báo ready + đủ Ally). Trước đó → thả xuống StateMachine = waiting/train song song.
        -- FIX E (user 2026-07-02): ĐÃ vật lý ở trong FM (game.JobId==fmJob) → LUÔN "ready", KHÔNG phụ thuộc gate.
        -- Trước đây "ready" bị bọc trong điều kiện gate → khi gate chưa mở (current đang training), main ở
        -- FM bị skip → rơi xuống StateMachine, status "moon" cũ (set lúc join) kẹt mãi không chuyển ready.
        if fmJob and game.JobId == fmJob then
            if myStatus ~= "ready" then State.setMyMainStatus("ready") end
            status("[MAIN " .. tostring(ctx.myStt) .. "] In FullMoon (ready) → chờ tới lượt trial theo thứ tự vào")
            return true
        end
        if State.fullmoonLocked and State.gateOpen and State.gateOpenedOnce and fmJob then
            -- FIX (user 2026-07-02): CHỈ join full moon khi ĐÃ xác nhận trial được 3 lần (trialConfirmed).
            -- Chưa xác nhận (mới vào server, _G streak reset) → return false, train/grind tại chỗ, KHÔNG join.
            if not ctx.trialConfirmed then return false end
            -- SPEC MỚI (user 2026-07-02): gate mở → Main2-6 spam join = status "moon"
            -- (moon = "đang làm open gate + spam full moon"). "waiting" chỉ dành cho lúc CHỜ Main1 ready.
            if (tick() - _lastMainJoinSpam) >= (State.joinSpamInterval or 5) then
                _lastMainJoinSpam = tick()
                State.setMyMainStatus("moon")
                status("[MAIN] Gate open → spam join full moon: " .. tostring(fmJob))
                TeleportManager.hopToJob(fmJob, "[MAIN2-6-SPAM-JOIN]")
            end
            return true
        end
        -- gate chưa mở (Main1 chưa ready) → CHỜ → status "waiting" (SPEC MỚI: waiting = đợi Main1 ready)
        if myStatus ~= "waiting" then
            State.setMyMainStatus("waiting")
            status("[MAIN " .. tostring(ctx.myStt) .. "] Waiting Main1 ready (gate chưa mở)...")
        end
        return false
    end

    function ScoutNavigator.tick(ctx)
        if ctx.isMain then return mainTick(ctx) end
        return allyTick()
    end
end

--[[ ============================================================================
 [27b] ALLYFULLMOONWATCH — LOOP NỀN RIÊNG cho Ally1/Ally2 (user 2026-07-02).
   Vì allyTick chạy trong StateMachine.tick, khi Ally đang trial (runTrialPhase yield lâu)
   thì nhịp bị nghẽn → check "hết full moon" bị trễ. Tách loop nền độc lập: mỗi 5s check
   isfullmoon() khi đang ĐỨNG đúng fullmoonJobid. Hết FM (quá grace) → POST /fmlost để PHÁ
   lock + đóng open gate trên server NGAY (không chờ grace 45s), rồi /getseverapi xin server mới.
============================================================================ ]]
local AllyFullMoonWatch = {}
do
    AllyFullMoonWatch.CHECK_INTERVAL = 5
    AllyFullMoonWatch.GRACE = 8          -- moon "tắt" dưới ngưỡng này = flicker (world chưa load) → bỏ qua
    AllyFullMoonWatch.POST_COOLDOWN = 5  -- chống spam /fmlost + /getseverapi
    AllyFullMoonWatch.started = false
    AllyFullMoonWatch._fmConfirmedAt = 0
    AllyFullMoonWatch._lastPostAt = 0

    function AllyFullMoonWatch.start()
        if AllyFullMoonWatch.started then return end
        AllyFullMoonWatch.started = true
        task.spawn(function()
            while Runtime.alive do
                task.wait(AllyFullMoonWatch.CHECK_INTERVAL)
                pcall(AllyFullMoonWatch.check)
            end
        end)
    end

    function AllyFullMoonWatch.check()
        if not Runtime.alive or Runtime.teleporting then return end
        -- chỉ Ally1 (LEADER) mới phá lock: nó là authority giữ FM. Ally2 canh nhưng KHÔNG /fmlost
        -- (tránh phá lock sai khi Ally1 vẫn đang giữ). Ally2 chờ server đổi fullmoonJobid.
        if not (_G.isAllyLeader and _G.isAllyLeader()) then return end
        local fmJob = State.fullmoonJobid
        -- chưa chốt FM hoặc mình chưa đứng đúng server FM → không phải việc của watch này (allyTick lo join)
        if not fmJob or game.JobId ~= fmJob then
            AllyFullMoonWatch._fmConfirmedAt = 0
            return
        end
        if isfullmoon() then
            AllyFullMoonWatch._fmConfirmedAt = tick()
            return
        end
        -- moon vừa tắt: dưới GRACE coi là flicker (world chưa load lại) → chờ
        if AllyFullMoonWatch._fmConfirmedAt > 0
            and (tick() - AllyFullMoonWatch._fmConfirmedAt) < AllyFullMoonWatch.GRACE then
            return
        end
        -- HẾT full moon THẬT (quá grace) → phá lock + xin server mới (throttle)
        if (tick() - AllyFullMoonWatch._lastPostAt) < AllyFullMoonWatch.POST_COOLDOWN then return end
        AllyFullMoonWatch._lastPostAt = tick()
        Logger.info("[ALLY-WATCH] HẾT full moon @ " .. tostring(fmJob) .. " → POST /fmlost (phá lock) + /getseverapi", "ally_watch_lost")
        status("[ALLY-WATCH] FullMoon ended → phá lock + xin server mới...")
        -- 1) phá lock + đóng gate trên server NGAY
        Net.postJSON(endpoint("/fmlost", { name = Config.myName }), { jobid = fmJob }, "fmlost")
        -- 2) xin server full moon mới đúng placeid
        local placeId = tostring(game.PlaceId)
        task.spawn(function()
            local url = endpoint("/getseverapi", { name = Config.myName, placeid = placeId })
            local ok, bodyRes = Net.getRaw(url)
            if ok and bodyRes then
                local good, res = pcall(function() return HttpService:JSONDecode(bodyRes) end)
                if good and res and res.ok and res.jobid and res.jobid ~= "" then
                    Logger.info("[ALLY-WATCH] server gợi ý jobid mới=" .. tostring(res.jobid), "ally_watch_newsev")
                end
            end
        end)
    end
end
_G.AllyFullMoonWatch = AllyFullMoonWatch

--[[ ============================================================================
 [28] STATEMACHINE — flow chính y chang File A main loop (1689-2030).
============================================================================ ]]
local StateMachine = {}
do
    StateMachine.state = "BOOTING"
    StateMachine._lastStatus = nil

    local S = {
        BOOTING = "BOOTING", WAITING_ROLE = "WAITING_ROLE", WAITING_MAIN = "WAITING_MAIN",
        WAITING_MOON = "WAITING_MOON", GOING_DOOR = "GOING_DOOR", -- BS-3: FOLLOWING_MAIN đã xóa (ally không follow main)
        IN_TRIAL = "IN_TRIAL", POST_TRIAL = "POST_TRIAL", TRAINING = "TRAINING",
        DONE = "DONE", ERROR_RECOVER = "ERROR_RECOVER",
    }
    StateMachine.S = S
    function StateMachine.transition(newState, reason)
        if StateMachine.state == newState then return end
        Logger.info(("FSM %s → %s (%s)"):format(StateMachine.state, newState, tostring(reason)), "fsm_" .. newState)
        StateMachine.state = newState
    end

    -- 1 nhịp = bản dịch sạch của main loop File A (giữ nguyên thứ tự nhánh/điều kiện)
    function StateMachine.tick()
        local me = State.myName
        local isMain = State.isMain[me] == true
        _G.ShouldSendData = false

        -- ===== CHECKING GATE (user 2026-07-02): 5s ĐẦU sau khi load team xong chỉ CHECK giai đoạn =====
        -- Mốc _G.teamReadyAt = lần đầu thấy LocalPlayer.Team (sau ChooseTeam). Reset mỗi lần mất team
        -- (hop server mới → chọn team lại → check lại từ đầu). Trong CHECK_WINDOW: KHÔNG join/trial/train,
        -- chỉ để 3-strike đọc remote xác định phase; xong 5s tự chạy tiếp theo status thật của acc.
        if LocalPlayer.Team then
            if not _G.teamReadyAt then _G.teamReadyAt = tick() end
        else
            _G.teamReadyAt = nil
        end
        local CHECK_WINDOW = 5
        local inCheckWindow = _G.teamReadyAt ~= nil and (tick() - _G.teamReadyAt) < CHECK_WINDOW

        local ab, AB = cachedTrialable()
        local currentmain = getCurrentMainBeingUpgraded()
        local myStt = mainSttOf(me) or State.myMainIndex
        local myStatus = ""
        if isMain then myStatus = State.getMainStatus(me) end
        -- CLEAN JOIN: lượt mới (waiting) → reset cờ đã-vào-trial
        if isMain and (myStatus == "waiting" or myStatus == "") then State.didEnterTrialThisTurn = false end

        -- ===== 3-STRIKE TRAINING CHECK (yêu cầu user 2026-07-02) =====
        -- DÙ ĐANG Ở STATUS NÀO (kể cả "ready"), main vừa vào phải CHECK training. Chỉ khi
        -- xác nhận "cần train" 3 LẦN LIÊN TIẾP (mỗi lần cách ≥1.5s = 3 lần đọc remote thật)
        -- mới thật sự chuyển "training" + DỪNG mọi hành động. Tránh vừa vào full moon đã nhảy
        -- training khi chưa kịp check. ready vẫn chạy check này song song (priority ready vẫn cao
        -- nhất — chỉ 3-strike train mới được ghi đè ready). Reset streak ngay khi trialable/done/gear.
        if isMain then
            if not _G.trainCheckLastT or (tick() - _G.trainCheckLastT) >= 1.5 then
                _G.trainCheckLastT = tick()
                local upg = Training.checkUpgradeForRole("main")
                if upg and not upg.uncertain then
                    if upg.needTrain then
                        _G.trainNeedStreak = (_G.trainNeedStreak or 0) + 1
                        _G.trialableStreak = 0
                    elseif upg.trialable or upg.done or upg.canBuyGear then
                        _G.trainNeedStreak = 0
                        _G.trialableStreak = (_G.trialableStreak or 0) + 1
                    end
                    -- uncertain (remote fail) → giữ nguyên streak (không cộng, không reset)
                end
            end
        else
            _G.trainNeedStreak = 0
            _G.trialableStreak = 0
        end
        local trainConfirmed = isMain and (_G.trainNeedStreak or 0) >= 3
        -- FIX (user 2026-07-02): CHỈ open gate + join full moon SAU khi xác nhận TRIALABLE 3 lần liên tiếp
        -- (đọc remote thật, không cần training). Trước khi xác nhận → KHÔNG join, train tại chỗ.
        -- Chặn bug: main1 trial xong hop training server → vào lại _G reset → tưởng waiting → spam join full
        -- moon NGAY khi chưa kịp check training. Giờ phải "trial được 3 lần" mới join.
        local trialConfirmed = isMain and (_G.trialableStreak or 0) >= 3

        -- CHECKING GATE (main): trong 5s đầu sau load team → 3-strike ở trên ĐÃ chạy (đọc remote xác định
        -- phase), nhưng CHƯA hành động (join/trial/train). Báo status "checking" để dashboard thấy đang dò.
        -- Hết 5s tick sau tự chạy tiếp theo status thật. CHỈ áp main (ally có loop hold/getsever riêng).
        if isMain and inCheckWindow then
            if AB ~= "done" then State.reportStatus("checking") end
            status("[MAIN " .. tostring(myStt) .. "] Checking phase (" .. string.format("%.1f", tick() - _G.teamReadyAt) .. "/" .. tostring(CHECK_WINDOW) .. "s)...")
            return
        end

        -- ===== chuẩn hoá status main (File A 1702-1742) =====
        if isMain then
            if AB == "done" then
                if myStatus ~= "done" then State.setMyMainStatus("done"); myStatus = "done"; State.didEnterTrialThisTurn = false end
                -- getgenv().change: ghi file "Completed-<race>" rồi gọi ChangeToFolder (id1,id2,true,id3)
                if getgenv().change and not _G.changeFileWritten then
                    local _okw, _race = pcall(function()
                        return LocalPlayer.Data.Race.Value
                    end)
                    local raceName = _okw and tostring(_race) or "Unknown"
                    local _okw2 = pcall(function()
                        writefile(LocalPlayer.Name .. ".txt", "Completed-" .. raceName)
                    end)
                    if _okw2 then
                        _G.changeFileWritten = true
                        task.spawn(function()
                            if type(Hooks.ChangeFolderAfterCompleted) == "function" then
                                Hooks.ChangeFolderAfterCompleted("Completed-" .. raceName)
                            end
                        end)
                    end
                end
            else
                if myStatus == "done" then State.setMyMainStatus("waiting"); myStatus = "waiting" end
                _G.changeFileWritten = false
                -- CLEAN JOIN: CHỈ chuyển training khi THẬT SỰ đã vào trial lượt này (chống "chưa trial đã done/training")
                if (myStatus == "in_trail" or myStatus == "moon") and not ab and State.didEnterTrialThisTurn then
                    local inOwnFFA = (myStatus == "in_trail") and (templeState() == "ffup")
                        and (getdis(CFrame.new(TEMPLE_ENTRY_POS)) < 2000)
                    if not inOwnFFA then
                        status("[MAIN " .. myStt .. "] Trial completed, switching to training!")
                        State.setMyMainStatus("training"); myStatus = "training"; State.didEnterTrialThisTurn = false
                    else
                        status("[MAIN " .. myStt .. "] Trial done → ở lại kill player (FFA)")
                    end
                end
            end
            if myStatus == "in_trail" and ab then
                local in_temple = getdis(CFrame.new(TEMPLE_ENTRY_POS)) < 3000
                if not in_temple then
                    status("[MAIN " .. myStt .. "] Died in trial, retrying...")
                    State.setMyMainStatus("waiting"); myStatus = "waiting"
                end
            end
        end

        -- ===== VIỆC 1: MAIN STT1 quá 5' chưa xong lượt → tụt cuối (File A 1746-1768) =====
        if isMain then
            if currentmain == me and myStatus ~= "training" and myStatus ~= "done" then
                if not _G.myTurnStart then _G.myTurnStart = tick() end
                if (tick() - _G.myTurnStart) > Config.MAIN_TURN_TIMEOUT then
                    status("[MAIN " .. myStt .. "] ⏱ Quá 5 phút chưa xong lượt → tụt cuối (waiting)")
                    State.setMyMainStatus("waiting"); myStatus = "waiting"
                    _G.inTrial = false
                    _G.myTurnStart = nil
                    return
                end
            else
                _G.myTurnStart = nil
            end
        end

        -- ===== IN-TRIAL LATCH (File A 1770-1809) =====
        local _tplace = getRaceTrialPlace(WorldProbe.getRace())
        local _inTrialNow = (_tplace and ab and getdis(_tplace.CFrame) < 1500 and templeState() ~= "ffup") and true or false
        if _inTrialNow then
            if isMain then
                if myStatus ~= "in_trail" then State.setMyMainStatus("in_trail"); myStatus = "in_trail" end
            elseif not _G.inTrial then
                State.reportStatus("in_trail")
            end
            _G.inTrial = true
            State.didEnterTrialThisTurn = true -- CLEAN JOIN: đã vào trial thật lượt này
            -- FIX #4: đánh dấu ĐÃ in_trail khi đang ở đúng server full moon → cho phép hop training SAU trial
            if isMain and State.fullmoonJobid and game.JobId == State.fullmoonJobid then _G.didTrialInFM = true end
            if State.trialStartedAt == 0 then State.trialStartedAt = tick() end
            StateMachine.transition(S.IN_TRIAL, "in trial zone")
            status((isMain and "[MAIN " .. tostring(myStt) .. "]" or "[ALLY]") .. " 🔥 IN-TRIAL → đang làm trial")
            doTrialForMyRace()
            return
        else
            if _G.inTrial then
                if not isMain then
                    State.reportStatus("ally")
                else
                    local fresh_ab, fresh_AB = trialable()
                    if not fresh_ab then
                        if fresh_AB == "done" then State.setMyMainStatus("done")
                        else State.setMyMainStatus("training") end
                        State.didEnterTrialThisTurn = false -- BS-5: rời trial + chuyển done/training → reset
                    end
                end
            end
            _G.inTrial = false
        end

        -- ===== CLEAN JOIN: LỚP ĐIỀU HƯỚNG (chỉ teleport). true=dừng; false=thả xuống trial/training gốc =====
        if Config.scout then
            local handled = ScoutNavigator.tick({ isMain = isMain, myStatus = myStatus, currentmain = currentmain, myStt = myStt, trainConfirmed = trainConfirmed, trialConfirmed = trialConfirmed })
            if handled then return end
            -- re-read sau ScoutNavigator: có thể đã set ready/moon trong cùng tick này
            if isMain then myStatus = State.getMainStatus(me) end
        end

        -- ===== NHÁNH MAIN (File A 1811-1909) =====
        -- 3-STRIKE: đã xác nhận cần train 3 lần → CHUYỂN training + DỪNG mọi hành động khác
        -- (ghi đè cả "ready"). Đặt TRƯỚC mọi nhánh main để chặn vào trial/door khi thật sự cần train.
        if isMain and trainConfirmed and AB ~= "done" then
            if myStatus ~= "training" then State.setMyMainStatus("training"); myStatus = "training" end
            State.didEnterTrialThisTurn = false
            StateMachine.transition(S.TRAINING, "3-strike need train")
            status("[MAIN " .. myStt .. "] Cần train (xác nhận 3 lần) → training, dừng hành động khác")
            Training.handleTraining("[MAIN " .. myStt .. "]", AB, function() State.setMyMainStatus("training") end)
            return
        end

        if isMain and myStatus == "done" then
            StateMachine.transition(S.DONE, "full gear")
            status("[MAIN " .. myStt .. "] ✅ DONE YOUR RACE - FULL GEAR (Gear2/3/4)!")
            -- safety net: nếu nhánh AB=="done" chưa gọi (vd race detect chậm), vẫn ép đổi folder.
            -- _G.ChangeFolderAfterCompleted tự guard bằng _ChangeFolderLock + cooldown → không spam.
            if getgenv().change and not _G.changeFileWritten then
                task.spawn(function()
                    if type(Hooks.ChangeFolderAfterCompleted) == "function" then
                        Hooks.ChangeFolderAfterCompleted("myStatus=done")
                    end
                end)
            end

        elseif isMain and myStatus == "training" then
            StateMachine.transition(S.TRAINING, "training")
            status("[MAIN " .. myStt .. "] Training (parallel)")
            if not ab then
                State.setMyMainStatus("training")
                Training.handleTraining("[MAIN " .. myStt .. "]", AB, function() State.setMyMainStatus("training") end)
            else
                if myStatus ~= "waiting" then State.setMyMainStatus("waiting") end
                status("[MAIN " .. myStt .. "] Training done → waiting (chờ tới lượt)")
            end

        elseif isMain and currentmain == me then
            StateMachine.transition(S.GOING_DOOR, "my turn")
            status("[MAIN " .. myStt .. "] My turn to upgrade gear!")
            if (myStatus == "waiting" or myStatus == "") and State.getMainStatus(me) ~= "ready" then State.setMyMainStatus("moon") end
            -- BS-3: ĐÃ XÓA self-hop fullmoon (ScoutNavigator đưa vào FM). Chạy thẳng gear/door/trial.
            do
                task.spawn(checkgear)
                _G.ShouldSendData = true
                local ts = templeState()
                if ts == "loading" then
                    status("[MAIN " .. myStt .. "] Đang vào Temple of Time...")
                elseif ts == "ffup" then
                    StateMachine.transition(S.POST_TRIAL, "ffup")
                    if myStatus == "in_trail" then
                        PostTrial.mainKillThenReset(myStt, currentmain)
                    else
                        status("[MAIN " .. myStt .. "] Chờ ở cửa (chưa in_trail → KHÔNG kill)")
                        goToMyDoor()
                    end
                else
                    -- ffdown: gear + ra cửa + ability sync
                    runTrialPhase("[MAIN " .. myStt .. "]", true)
                    AbilitySync.reportAtDoor()
                    AbilitySync.maybeFire()
                end
            end

        elseif isMain then
            -- MAIN CHƯA TỚI LƯỢT: còn train được → train song song; sẵn sàng → waiting (+ stt2-4 bám fullmoon)
            _G.allyKillReset = false
            if (not ab) and AB ~= "done" then
                -- FIX flap i=: theo Promt.md §XIII — CHỈ set status "training" khi ĐÃ vào trial lượt này.
                -- Chưa vào trial (main2-6 đang chờ lượt) → giữ "waiting", vẫn grind tại chỗ, KHÔNG để
                -- status="training" khiến ScoutNavigator kéo khỏi fullmoon rồi bật lại (đá training↔waiting).
                if State.didEnterTrialThisTurn then
                    if myStatus ~= "training" then State.setMyMainStatus("training") end
                else
                    if myStatus == "training" then State.setMyMainStatus("waiting") end
                end
                StateMachine.transition(S.TRAINING, "train parallel")
                status("[MAIN " .. myStt .. "] Training song song (chưa tới lượt)")
                Training.handleTraining("[MAIN " .. myStt .. "]", AB, function()
                    if State.didEnterTrialThisTurn then State.setMyMainStatus("training") end
                end)
            else
                if myStatus == "training" then State.setMyMainStatus("waiting") end
                StateMachine.transition(S.WAITING_MAIN, "waiting turn")
                -- BS-3: ĐÃ XÓA self-hop fullmoon khi waiting (ScoutNavigator lo spam-join)
                status("[MAIN " .. myStt .. "] Waiting for current main: " .. tostring(currentmain))
            end

        else
            -- ===== NHÁNH ALLY (File A 1910-2029) =====
            local roleName = "[ALLY]"
            -- Dùng AllyTrainingGate: chỉ train khi confirmed
            local _, gateReason = AllyTrainingGate.tick(roleName)
            -- BS-3: scout ally GIỮ full moon → KHÔNG train. Nhánh ally-train cũ (gateState=="training"
            -- and not Config.scout) đã XÓA HẲN vì Config.scout luôn = true → code chết vĩnh viễn.
            status(roleName .. " Ready for trialing — " .. tostring(gateReason))
            -- BS-3: scout ally giữ status "ally" do ScoutNavigator set (KHÔNG ghi đè)

            status(roleName .. " Đang dò main đang tới lượt…")
            local mainActive = false
            if currentmain then
                local st = State.getMainStatus(currentmain)
                mainActive = (st == "moon" or st == "in_trail")
                status(roleName .. " main " .. tostring(currentmain) .. " = " .. tostring(st))
            end
            local sameServer = isSameServerAsMain(currentmain)
            -- BS-3: scout ally KHÔNG follow main (server điều phối full moon). Nhánh FOLLOWING_MAIN cũ
            -- ("Hop sang server main" + hop __ServerBrowser) đã XÓA HẲN vì Config.scout luôn = true.
            -- FIX #4: Main1 báo ready → server set trial_phase="trialing" → Ally biết vào trial ngay
            -- khi đang đứng đúng server full moon (không cần đợi main1 đến cửa/moon-active detect).
            local trialingSignal = (State.trialPhase == "trialing")
                and State.fullmoonJobid and State.fullmoonJobid ~= ""
                and game.JobId == State.fullmoonJobid
            if (currentmain and mainActive and sameServer) or trialingSignal or Config.vipServer or (isnight() and isfullmoon()) then
                task.spawn(checkgear)
                _G.ShouldSendData = true
                local ts = templeState()
                if ts == "loading" then
                    status(roleName .. " Đang vào Temple of Time...")
                elseif ts == "ffup" then
                    StateMachine.transition(S.POST_TRIAL, "ally ffup")
                    PostTrial.resetAllyOnce(roleName)
                else
                    _G.allyKillReset = false
                    StateMachine.transition(S.GOING_DOOR, "ally to door")
                    runTrialPhase(roleName, false)
                    AbilitySync.reportAtDoor()
                end
            else
                _G.allyKillReset = false
                StateMachine.transition(S.WAITING_MAIN, "ally wait main")
                status(roleName .. " Waiting for current main: " .. tostring(currentmain))
            end
        end
    end
end

--[[ ============================================================================
 [29] MAINLOOP — tick FSM, xpcall, ERROR_RECOVER. (File A 1674-2037)
============================================================================ ]]
local MainLoop = {}
do
    MainLoop._errStreak = 0
    function MainLoop.start()
        task.spawn(function()
            local checktempledoor = TempleDoorGate.ready()
            while Runtime.alive do
                _G.loopTick = (_G.loopTick or 0) + 1
                _G.loopLastT = tick()
                if not _G.firstLoopHit then
                    _G.firstLoopHit = true
                    status("Vòng chính đã chạy — đang đồng bộ…")
                end
                if not checktempledoor then checktempledoor = TempleDoorGate.ready() end
                if not checktempledoor then
                    status("Chờ mở cửa đền (CheckTempleDoor=" .. tostring(checktempledoor) .. ")")
                else
                    local ok, err = xpcall(StateMachine.tick, debug.traceback)
                    if ok then
                        MainLoop._errStreak = 0
                    else
                        MainLoop._errStreak = MainLoop._errStreak + 1
                        status("⚠ Lỗi vòng chính: " .. tostring(err))
                        Net.log("ERR", "main loop crash: " .. tostring(err))
                        if MainLoop._errStreak >= 5 then
                            StateMachine.transition(StateMachine.S.ERROR_RECOVER, "too many errors")
                            task.wait(2)
                        end
                    end
                end
                task.wait(Config.MAIN_TICK)
            end
        end)
    end
end

--[[ ============================================================================
 [30] NOGUCHI LOOP — mọi account POST jobid mỗi 1s. (File A 2701-2706)
============================================================================ ]]
local function startNoguchiLoop()
    task.spawn(function()
        while Runtime.alive do
            Net.postJSON(endpoint("/noguchi", { name = State.myName }), { jobid = game.JobId }, "noguchi")
            task.wait(1)
        end
    end)
end

--[[ ============================================================================
[31] UIMANAGER — GUI Premium (port File A 2709-3373) + fallback text-only.
UI lỗi KHÔNG được làm chết main loop (mọi thứ bọc pcall).
Recovery loop: nếu GUI mất → tự tạo lại.
============================================================================ ]]
local UIManager = {}
UIManager.started = false
UIManager._creating = false

local function startUIRecoveryLoop()
    task.spawn(function()
        task.wait(10)
        while Runtime.alive do
            task.wait(5)
            if not UIManager.started then break end
            local ok_gui, gui = pcall(function()
                return LocalPlayer.PlayerGui:FindFirstChild("VuNguyenKaitunV4")
            end)
            if ok_gui and not gui then
                Logger.info("[UI] missing, recreating", "ui_recreate")
                status("Recreating UI...")
                UIManager.started = false
                UIManager.start()
                Logger.ok("[UI] created", "ui_ok")
            end
        end
    end)
end

function UIManager.start()
    if UIManager.started then return end
    UIManager.started = true
    Logger.info("[UI] building...", "ui_start")
    -- text-only state luôn có (đề phòng UI build fail)
    task.spawn(function()
        while Runtime.alive do
            pcall(function()
                _G.fullStatus = (_G.statusnow or "…")
                    .. " | role=" .. tostring(State.myRole)
                    .. " | fsm=" .. tostring(StateMachine.state)
                    .. " | cur=" .. tostring(getCurrentMainBeingUpgraded())
            end)
            task.wait(Config.UI_THROTTLE)
        end
    end)

    local okUI = pcall(function()
        local TS = TweenService
        pcall(function()
            local old = LocalPlayer.PlayerGui:FindFirstChild("VuNguyenKaitunV4")
            if old then old:Destroy() end
        end)
        local rgbActive = true
        local function RegisterRGB(obj, offset, s, v, prop)
            local hue = (0.65 + (offset or 0)) % 1
            pcall(function() obj[prop or "Color"] = Color3.fromHSV(hue, s or 0.85, v or 1) end)
        end

        local Gui = Instance.new("ScreenGui")
        Gui.Name = "VuNguyenKaitunV4"; Gui.ResetOnSpawn = false; Gui.IgnoreGuiInset = false
        Gui.DisplayOrder = 1000; Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
        if not playerGui then
            Logger.warn("[UI] PlayerGui timeout, skip UI build", "playergui_timeout")
            return
        end
        Gui.Parent = playerGui

        local Toggle = Instance.new("TextButton")
        Toggle.Size = UDim2.new(0, 54, 0, 54); Toggle.Position = UDim2.new(1, -70, 0.30, 0)
        Toggle.BackgroundColor3 = Color3.fromRGB(18, 20, 28); Toggle.BorderSizePixel = 0
        Toggle.Text = "👑"; Toggle.TextSize = 26; Toggle.Font = Enum.Font.GothamBold
        Toggle.TextColor3 = Color3.fromRGB(255, 255, 255); Toggle.AutoButtonColor = false; Toggle.Parent = Gui
        Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0, 14)
        local togStroke = Instance.new("UIStroke", Toggle)
        togStroke.Thickness = 2.5; togStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        RegisterRGB(togStroke, 0)

        local Panel = Instance.new("Frame")
        Panel.Size = UDim2.new(0, 320, 0, 460); Panel.Position = UDim2.new(0.5, -160, 0.5, -230)
        Panel.BackgroundColor3 = Color3.fromRGB(12, 14, 22); Panel.BorderSizePixel = 0
        Panel.Active = true; Panel.Draggable = true; Panel.Visible = true; Panel.Parent = Gui
        Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 16)
        local pStroke = Instance.new("UIStroke", Panel)
        pStroke.Thickness = 2.5; pStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        RegisterRGB(pStroke, 0)

        local Header = Instance.new("Frame")
        Header.Size = UDim2.new(1, -20, 0, 52); Header.Position = UDim2.new(0, 10, 0, 10)
        Header.BackgroundColor3 = Color3.fromRGB(20, 23, 35); Header.BorderSizePixel = 0; Header.Parent = Panel
        Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)
        local Title = Instance.new("TextLabel")
        Title.Size = UDim2.new(1, -50, 0, 24); Title.Position = UDim2.new(0, 14, 0, 6)
        Title.BackgroundTransparency = 1; Title.Text = "👑 VU NGUYEN KAITUN V4"
        Title.TextColor3 = Color3.fromRGB(255, 255, 255); Title.TextXAlignment = Enum.TextXAlignment.Left
        Title.Font = Enum.Font.GothamBold; Title.TextSize = 15; Title.Parent = Header
        local SubTitle = Instance.new("TextLabel")
        SubTitle.Size = UDim2.new(1, -50, 0, 14); SubTitle.Position = UDim2.new(0, 14, 0, 30)
        SubTitle.BackgroundTransparency = 1; SubTitle.Text = "✦ PREMIUM"
        SubTitle.TextXAlignment = Enum.TextXAlignment.Left; SubTitle.Font = Enum.Font.GothamBold
        SubTitle.TextSize = 11; SubTitle.Parent = Header
        RegisterRGB(SubTitle, 0.1, 0.7, 1, "TextColor3")
        local CloseBtn = Instance.new("TextButton")
        CloseBtn.Size = UDim2.new(0, 30, 0, 30); CloseBtn.Position = UDim2.new(1, -38, 0.5, -15)
        CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50); CloseBtn.BorderSizePixel = 0
        CloseBtn.Text = "✕"; CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        CloseBtn.Font = Enum.Font.GothamBold; CloseBtn.TextSize = 15; CloseBtn.AutoButtonColor = false; CloseBtn.Parent = Header
        Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)
        CloseBtn.MouseButton1Click:Connect(function() Panel.Visible = false end)
        Toggle.MouseButton1Click:Connect(function() Panel.Visible = not Panel.Visible end)

        local TabBar = Instance.new("Frame")
        TabBar.Size = UDim2.new(1, -20, 0, 34); TabBar.Position = UDim2.new(0, 10, 0, 70)
        TabBar.BackgroundColor3 = Color3.fromRGB(16, 18, 28); TabBar.BorderSizePixel = 0; TabBar.Parent = Panel
        Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 9)
        local tabLayout = Instance.new("UIListLayout", TabBar)
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center; tabLayout.Padding = UDim.new(0, 4)

        local PageHolder = Instance.new("Frame")
        PageHolder.Size = UDim2.new(1, -20, 1, -120); PageHolder.Position = UDim2.new(0, 10, 0, 112)
        PageHolder.BackgroundTransparency = 1; PageHolder.BorderSizePixel = 0; PageHolder.Parent = Panel

        local pages, tabBtns = {}, {}
        local function selectTab(name)
            for n, pg in pairs(pages) do pg.Visible = (n == name) end
            for n, b in pairs(tabBtns) do
                local on = (n == name)
                b.BackgroundColor3 = on and Color3.fromRGB(40, 45, 68) or Color3.fromRGB(20, 23, 35)
                b.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 185)
            end
        end
        local function CreatePage(name)
            local page = Instance.new("ScrollingFrame")
            page.Size = UDim2.new(1, 0, 1, 0); page.BackgroundTransparency = 1; page.BorderSizePixel = 0
            page.ScrollBarThickness = 4; page.ScrollBarImageColor3 = Color3.fromRGB(120, 160, 240)
            page.CanvasSize = UDim2.new(0, 0, 0, 0); page.AutomaticCanvasSize = Enum.AutomaticSize.Y
            page.Visible = false; page.Parent = PageHolder
            local l = Instance.new("UIListLayout", page); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Padding = UDim.new(0, 8)
            pages[name] = page
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0, 96, 1, -6); btn.BackgroundColor3 = Color3.fromRGB(20, 23, 35); btn.BorderSizePixel = 0
            btn.Text = name; btn.Font = Enum.Font.GothamBold; btn.TextSize = 12
            btn.TextColor3 = Color3.fromRGB(150, 160, 185); btn.AutoButtonColor = false; btn.Parent = TabBar
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
            btn.MouseButton1Click:Connect(function() selectTab(name) end)
            tabBtns[name] = btn
            return page
        end
        local function addCard(page, order, height)
            local f = Instance.new("Frame")
            f.LayoutOrder = order; f.Size = UDim2.new(1, 0, 0, height)
            f.BackgroundColor3 = Color3.fromRGB(18, 20, 30); f.BorderSizePixel = 0; f.Parent = page
            Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
            return f
        end
        local function StatusCard(page, order)
            local f = addCard(page, order, 72)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -16, 0, 16); t.Position = UDim2.new(0, 12, 0, 8)
            t.BackgroundTransparency = 1; t.Text = "● STATUS"; t.TextColor3 = Color3.fromRGB(140, 200, 255)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 11; t.Parent = f
            local v = Instance.new("TextLabel")
            v.Size = UDim2.new(1, -20, 0, 40); v.Position = UDim2.new(0, 12, 0, 26)
            v.BackgroundTransparency = 1; v.Text = "Đang khởi động..."; v.TextColor3 = Color3.fromRGB(255, 255, 255)
            v.TextXAlignment = Enum.TextXAlignment.Left; v.TextYAlignment = Enum.TextYAlignment.Top
            v.Font = Enum.Font.GothamBold; v.TextSize = 13; v.TextWrapped = true; v.Parent = f
            return v
        end
        local function LabelCard(page, order, titleText, descText)
            local f = addCard(page, order, 50)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -16, 0, 18); t.Position = UDim2.new(0, 12, 0, 7)
            t.BackgroundTransparency = 1; t.Text = titleText; t.TextColor3 = Color3.fromRGB(230, 235, 255)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = f
            local d = Instance.new("TextLabel")
            d.Size = UDim2.new(1, -16, 0, 16); d.Position = UDim2.new(0, 12, 0, 27)
            d.BackgroundTransparency = 1; d.Text = descText or ""; d.TextColor3 = Color3.fromRGB(140, 150, 175)
            d.TextXAlignment = Enum.TextXAlignment.Left; d.Font = Enum.Font.Gotham; d.TextSize = 11
            d.TextTruncate = Enum.TextTruncate.AtEnd; d.Parent = f
            return { SetDesc = function(_, x) d.Text = x end }
        end
        local function ButtonCard(page, order, text, callback)
            local btn = Instance.new("TextButton")
            btn.LayoutOrder = order; btn.Size = UDim2.new(1, 0, 0, 42)
            btn.BackgroundColor3 = Color3.fromRGB(22, 25, 38); btn.BorderSizePixel = 0
            btn.Text = text; btn.Font = Enum.Font.GothamBold; btn.TextSize = 13
            btn.TextColor3 = Color3.fromRGB(245, 250, 255); btn.AutoButtonColor = false; btn.Parent = page
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
            btn.MouseButton1Click:Connect(function()
                local ok, err = pcall(callback)
                if not ok then warn("[Kaitun GUI] " .. tostring(err)) end
            end)
            return btn
        end
        local function ToggleCard(page, order, text, default, callback)
            local f = addCard(page, order, 46)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -70, 1, 0); t.Position = UDim2.new(0, 12, 0, 0)
            t.BackgroundTransparency = 1; t.Text = text; t.TextColor3 = Color3.fromRGB(230, 235, 255)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = f
            local sw = Instance.new("TextButton")
            sw.Size = UDim2.new(0, 44, 0, 22); sw.Position = UDim2.new(1, -54, 0.5, -11)
            sw.BackgroundColor3 = default and Color3.fromRGB(60, 200, 110) or Color3.fromRGB(60, 64, 82)
            sw.Text = ""; sw.AutoButtonColor = false; sw.Parent = f
            Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
            local state = default
            sw.MouseButton1Click:Connect(function()
                state = not state
                sw.BackgroundColor3 = state and Color3.fromRGB(60, 200, 110) or Color3.fromRGB(60, 64, 82)
                pcall(callback, state)
            end)
            return f
        end
        local function DropdownCard(page, order, text, options, default, callback)
            local f = addCard(page, order, 46)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -110, 1, 0); t.Position = UDim2.new(0, 12, 0, 0)
            t.BackgroundTransparency = 1; t.Text = text; t.TextColor3 = Color3.fromRGB(230, 235, 255)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = f
            local cur = Instance.new("TextButton")
            cur.Size = UDim2.new(0, 90, 0, 30); cur.Position = UDim2.new(1, -100, 0.5, -15)
            cur.BackgroundColor3 = Color3.fromRGB(30, 34, 50); cur.Text = default
            cur.TextColor3 = Color3.fromRGB(255, 255, 255); cur.Font = Enum.Font.GothamBold; cur.TextSize = 12
            cur.AutoButtonColor = false; cur.Parent = f
            Instance.new("UICorner", cur).CornerRadius = UDim.new(0, 7)
            local idx = 1
            for i, o in ipairs(options) do if o == default then idx = i end end
            cur.MouseButton1Click:Connect(function()
                idx = (idx % #options) + 1
                cur.Text = options[idx]
                pcall(callback, options[idx])
            end)
            return f
        end
        local function TextboxCard(page, order, placeholder, callback)
            local f = addCard(page, order, 46)
            local box = Instance.new("TextBox")
            box.Size = UDim2.new(1, -24, 1, -14); box.Position = UDim2.new(0, 12, 0, 7)
            box.BackgroundColor3 = Color3.fromRGB(14, 16, 24); box.PlaceholderText = placeholder
            box.Text = ""; box.TextColor3 = Color3.fromRGB(255, 255, 255); box.PlaceholderColor3 = Color3.fromRGB(120, 128, 150)
            box.Font = Enum.Font.Gotham; box.TextSize = 13; box.ClearTextOnFocus = false
            box.TextXAlignment = Enum.TextXAlignment.Left; box.Parent = f
            Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
            box:GetPropertyChangedSignal("Text"):Connect(function() pcall(callback, box.Text) end)
            return box
        end

        -- PAGE: MAIN
        local mainPage = CreatePage("Main")
        local StatusValue = StatusCard(mainPage, 1)
        do
            local savedGear = Config.gear
            pcall(function()
                local y = HttpService:JSONDecode(readfile("nawy/kaitunv4.json"))
                if y and y["Choose Gear"] then savedGear = y["Choose Gear"] end
            end)
            getgenv().Config["Gear"] = savedGear; Config.gear = savedGear
            DropdownCard(mainPage, 2, "Choose Gear", { "A-B-B", "A-A-B" }, savedGear, function(v)
                getgenv().Config["Gear"] = v; Config.gear = v
                pcall(function()
                    local m = {}; pcall(function() m = HttpService:JSONDecode(readfile("nawy/kaitunv4.json")) end)
                    if type(m) ~= "table" then m = {} end
                    if not isfolder("nawy") then makefolder("nawy") end
                    m["Choose Gear"] = v; writefile("nawy/kaitunv4.json", HttpService:JSONEncode(m))
                end)
            end)
        end
        ToggleCard(mainPage, 3, "Reset After Trial", Config.resetAfterTrial, function(v)
            getgenv().Config["ResetAfterTrial"] = v; Config.resetAfterTrial = v
        end)
        TextboxCard(mainPage, 4, "Nhập Job ID...", function(text) _G.jobidinput = text end)
        ButtonCard(mainPage, 5, "Join Job Id", function()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", _G.jobidinput)
        end)
        ButtonCard(mainPage, 6, "Change Race (2500F)", function()
            local R = ReplicatedStorage.Remotes.CommF_
            R:InvokeServer("BlackbeardReward", "Reroll", "1")
            R:InvokeServer("BlackbeardReward", "Reroll", "2")
        end)
        local NetDiag = LabelCard(mainPage, 7, "🌐 Net (backend)", "đang kiểm tra…")
        local PlaceCard = LabelCard(mainPage, 8, "🆔 Place / Server", "…")
        local SyncDbg = LabelCard(mainPage, 9, "🔎 Sync Debug", "…")

        -- PAGE: STATUS
        local statusPage = CreatePage("Status")
        local mainStatusLabels = {}
        for i, name in ipairs(Config.mains) do
            mainStatusLabels[name] = LabelCard(statusPage, i, "Main " .. i .. ": " .. name, "loading...")
        end

        -- PAGE: DEBUG
        local debugPage = CreatePage("Debug")
        local function IndicatorRow(order, labelText)
            local f = addCard(debugPage, order, 30)
            local dot = Instance.new("Frame")
            dot.Size = UDim2.new(0, 12, 0, 12); dot.Position = UDim2.new(0, 12, 0.5, -6)
            dot.BackgroundColor3 = Color3.fromRGB(110, 116, 140); dot.BorderSizePixel = 0; dot.Parent = f
            Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -36, 1, 0); t.Position = UDim2.new(0, 32, 0, 0)
            t.BackgroundTransparency = 1; t.Text = labelText; t.TextColor3 = Color3.fromRGB(220, 225, 240)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.Gotham; t.TextSize = 12
            t.TextTruncate = Enum.TextTruncate.AtEnd; t.Parent = f
            return function(ok, txt)
                dot.BackgroundColor3 = ok and Color3.fromRGB(60, 205, 115) or Color3.fromRGB(235, 75, 85)
                if txt then t.Text = txt end
            end
        end
        local setLoop = IndicatorRow(1, "Loop")
        local setNet  = IndicatorRow(2, "Net")
        local setSrv  = IndicatorRow(3, "Server")
        local setDoor = IndicatorRow(4, "Door")
        local setMain = IndicatorRow(5, "Main stt1")

        local logSF
        do
            local box = addCard(debugPage, 6, 286)
            local hl = Instance.new("TextLabel")
            hl.Size = UDim2.new(1, -16, 0, 18); hl.Position = UDim2.new(0, 10, 0, 4)
            hl.BackgroundTransparency = 1; hl.Text = "📜 LOG (200 dòng · cuộn ↕)"
            hl.TextColor3 = Color3.fromRGB(150, 200, 255); hl.TextXAlignment = Enum.TextXAlignment.Left
            hl.Font = Enum.Font.GothamBold; hl.TextSize = 11; hl.Parent = box
            logSF = Instance.new("ScrollingFrame")
            logSF.Size = UDim2.new(1, -12, 1, -28); logSF.Position = UDim2.new(0, 6, 0, 24)
            logSF.BackgroundColor3 = Color3.fromRGB(10, 12, 18); logSF.BackgroundTransparency = 0.3
            logSF.BorderSizePixel = 0; logSF.ScrollBarThickness = 5
            logSF.ScrollBarImageColor3 = Color3.fromRGB(120, 160, 240)
            logSF.CanvasSize = UDim2.new(0, 0, 0, 0); logSF.AutomaticCanvasSize = Enum.AutomaticSize.Y; logSF.Parent = box
            Instance.new("UICorner", logSF).CornerRadius = UDim.new(0, 8)
            local lay = Instance.new("UIListLayout", logSF); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Padding = UDim.new(0, 1)
        end
        local logLabels = {}

        selectTab("Main")
        Panel.Size = UDim2.new(0, 0, 0, 0)
        TS:Create(Panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Size = UDim2.new(0, 320, 0, 460) }):Play()

        -- update loops (mỗi loop pcall riêng, check Runtime.alive)
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.2)
                pcall(function()
                    if _G.statusnow then StatusValue.Text = _G.statusnow .. "\nPlaceId: " .. tostring(game.PlaceId) end
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(1)
                pcall(function() if _G.netDiag then NetDiag:SetDesc(_G.netDiag) end end)
                pcall(function()
                    PlaceCard:SetDesc(("PlaceId: %s | Job: %s"):format(tostring(game.PlaceId), tostring(game.JobId):sub(1, 18)))
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.5)
                pcall(function()
                    local cur = getCurrentMainBeingUpgraded()
                    local c = cur and State.statusCache[cur]
                    local me = State.isMain[State.myName] and ("MAIN" .. tostring(State.myMainIndex)) or "ALLY"
                    SyncDbg:SetDesc(("me=%s cur=%s st=%s ss=%s i=%s d=%s%s"):format(
                        me, tostring(cur):sub(1, 12), tostring(c and c.status or "?"),
                        _G.lastSameSrv and "same" or "diff", tostring(_G.lastRaceI),
                        tostring(_G.lastDoorDist and math.floor(_G.lastDoorDist) or "?"), tostring(_G.lastDoorSrc or "?")))
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(3)
                for i, name in ipairs(Config.mains) do
                    pcall(function()
                        if mainStatusLabels[name] then mainStatusLabels[name]:SetDesc("Status: " .. State.getMainStatus(name)) end
                    end)
                end
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.4)
                pcall(function()
                    local alive = _G.loopLastT and (tick() - _G.loopLastT) < 2
                    setLoop(alive == true, "Loop: " .. (alive and ("alive #" .. tostring(_G.loopTick or 0)) or "STALL!"))
                    local g, p = _G.netGetOk, _G.netPostOk
                    setNet(g and p == true, "Net: GET " .. (g and "OK" or "FAIL")
                        .. " | POST " .. (p == nil and "N/A" or (p and "OK" or "FAIL")))
                    setSrv(_G.lastSameSrv == true, "Server: " .. (_G.lastSameSrv and "SAME" or "DIFF"))
                    local atDoor = _G.lastDoorDist and _G.lastDoorDist < 150
                    setDoor(atDoor == true, "Door: d=" .. tostring(_G.lastDoorDist and math.floor(_G.lastDoorDist) or "?")
                        .. tostring(_G.lastDoorSrc or "?"))
                    local cur = getCurrentMainBeingUpgraded()
                    local c = cur and State.statusCache[cur]
                    setMain(c ~= nil, "Main1: " .. tostring(cur):sub(1, 12) .. " = " .. tostring(c and c.status or "?"))
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.4)
                pcall(function()
                    local present = {}
                    for _, e in ipairs(_G.dbgLog) do
                        present[e.seq] = true
                        if not logLabels[e.seq] then
                            local lb = Instance.new("TextLabel")
                            lb.Size = UDim2.new(1, -4, 0, 0); lb.AutomaticSize = Enum.AutomaticSize.Y
                            lb.BackgroundTransparency = 1; lb.LayoutOrder = e.seq
                            lb.Font = Enum.Font.Code; lb.TextSize = 11; lb.TextWrapped = true
                            lb.TextXAlignment = Enum.TextXAlignment.Left; lb.Text = e.text
                            lb.TextColor3 = (e.level == "ok" and Color3.fromRGB(80, 210, 120))
                                or (e.level == "err" and Color3.fromRGB(235, 80, 90))
                                or Color3.fromRGB(190, 198, 215)
                            lb.Parent = logSF
                            logLabels[e.seq] = lb
                        end
                    end
                    for seq, lb in pairs(logLabels) do
                        if not present[seq] then lb:Destroy(); logLabels[seq] = nil end
                    end
                    local nb = logSF.CanvasPosition.Y >= (logSF.AbsoluteCanvasSize.Y - logSF.AbsoluteWindowSize.Y - 24)
                    if nb then logSF.CanvasPosition = Vector2.new(0, logSF.AbsoluteCanvasSize.Y) end
                end)
            end
        end)
    end)
    if not okUI then
        Logger.warn("UIManager: build GUI fail → chạy text-only (_G.fullStatus / _G.dbgLog).", "ui_fail")
    end
end

--[[ ============================================================================
 [32] STARTUP — init + start mọi module (chống start trùng). (File A: rải toàn file)
============================================================================ ]]
if not Runtime._started then
    Runtime._started = true
    _G[State.myName] = true

    -- Helper: start module an toàn — 1 module lỗi KHÔNG được kéo sập cả startup (root cause "không load").
    local function safeStart(label, fn)
        local ok, err = pcall(fn)
        if not ok then
            pcall(function() Net.log("ERR", "startup '" .. label .. "' lỗi: " .. tostring(err)) end)
            pcall(function() Logger.warn("[BOOT] '" .. label .. "' fail: " .. tostring(err), "boot_fail_" .. label) end)
        end
    end

    -- ========== ƯU TIÊN 1: THỨ NGƯỜI DÙNG THẤY — chạy TRƯỚC, KHÔNG phụ thuộc network ==========
    -- Trước đây ServerSync.init() (HTTP retry 8 lần, block ~8-10s / throw) chạy ĐẦU → nếu chậm/lỗi thì
    -- UI + choose team + main loop phía dưới KHÔNG BAO GIỜ chạy → "không load UI, không chọn team, không load script".
    -- Giờ: UI + TeamManager lên trước, vô điều kiện; init đẩy xuống thread nền.
    safeStart("ui", UIManager.start)                 -- UI hiện ngay (kể cả khi mọi thứ khác fail)
    safeStart("ui_recovery", startUIRecoveryLoop)
    safeStart("team", TeamManager.start)             -- chọn team ngay (có recovery loop riêng)
    safeStart("sea", SeaManager.start)

    -- ========== ƯU TIÊN 2: NETWORK / ROLE — chạy NỀN, không block UI/team ==========
    task.spawn(function()
        safeStart("markVisited", function() TeleportManager.markVisited(game.JobId) end)
        safeStart("serversync_init", ServerSync.init)       -- /init retry 8 lần → nền, không treo startup
        safeStart("warmers", ServerSync.startWarmers)
        safeStart("netprobe", ServerSync.startNetProbe)
        safeStart("noguchi", startNoguchiLoop)
        safeStart("ability_sync", AbilitySync.startLoops)
    end)

    -- ========== ƯU TIÊN 3: WORLD / COMBAT / VÒNG CHÍNH ==========
    safeStart("noclip", function() Movement.enableNoclip("return true") end)
    safeStart("spam_skills", CombatActions.startSpamSkills)
    safeStart("fast_attack", CombatActions.startFastAttack)
    safeStart("haki", CombatActions.startHakiLoop)
    safeStart("ally_train_gate", AllyTrainingGate.start)
    safeStart("ally_fm_watch", AllyFullMoonWatch.start)  -- loop nền Ally1/Ally2 canh hết full moon
    safeStart("main_loop", MainLoop.start)               -- vòng chính — LUÔN chạy dù init nền chưa xong

    Logger.ok("KaitunV4 bản 2 (modular, port từ File A) khởi động xong. role=" .. tostring(State.myRole))
end
