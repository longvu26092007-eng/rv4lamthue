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

 ── REFACTOR (maintainability-only, KHÔNG đổi hành vi) ─────────────────────────
  • D2/D3/D1: AbilitySync loop gọi lại maybeFire()/pollFire()/reportAtDoor()
    (xoá duplicate, giữ y nguyên side-effect — write-loop vẫn reset myDoorReady).
  • State.runtime: gom các _G NỘI BỘ vào 1 chỗ (debug dễ); _G public/UI giữ nguyên.
  • CombatActions tách Targeting/WeaponManager/SkillSpam/MobControl/FastAttackMod,
    giữ facade CombatActions.* để call-site không đổi.
  • StateMachine.tick() tách hàm con (giữ NGUYÊN thứ tự if/elseif, return sớm,
    thời điểm set status). + validateInvariants() chỉ cảnh báo.
  • UIManager dùng safeCreate() bọc TỪNG nhóm (báo fail ở đúng bước), không pcall
    lớn nữa; layout/text/màu/update-loop GIỮ NGUYÊN.
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

local LocalPlayer = Players.LocalPlayer

--[[ ============================================================================
 [01] BOOTSTRAP — chờ client load, KHÔNG treo vô hạn (timeout 30s). (File A 5-12)
============================================================================ ]]
do
    if not game:IsLoaded() then game.Loaded:Wait() end
    local t0 = tick()
    repeat
        task.wait(0.1)
        local rem  = ReplicatedStorage:FindFirstChild("Remotes")
        local lp   = Players.LocalPlayer
        local gui  = lp and lp:FindFirstChild("PlayerGui")
        local loadingScreen = gui and gui:FindFirstChild("LoadingScreen")
        if rem and lp and gui and not loadingScreen then break end
    until (tick() - t0) > 30
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
    Config.FULLMOON_API       = "http://fi11.bot-hosting.net:20758/api/name=fullmoon" -- File A 2159
    Config.DEAD_JOB_TTL       = 1800   -- File A 2175
    Config.MAIN_TURN_TIMEOUT  = 300    -- File A 1752
    Config.TRAIN_WINDOW       = 300    -- File A 1612
    Config.HELPRESET_TIMEOUT  = 25     -- File A 2005
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
      (Đọc _G.lastRaceI/lastDoorDist/lastDoorSrc/lastSameSrv → các biến này GIỮ _G
       vì status() khai báo trước State + UI cũng đọc.)
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
      State.runtime: gom các _G NỘI BỘ (debug dễ). _G public/UI giữ riêng.
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

    -- runtime nội bộ (thay cho các _G nội bộ). Bắt đầu rỗng = mọi field nil
    -- (đúng default cũ của _G chưa gán). Public/debug/UI globals KHÔNG nằm ở đây.
    State.runtime = State.runtime or {}

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
        Net.postJSON(Config.baseUrl .. "/mainstatus?name=" .. State.myName, { status = statusStr }, "mainstatus")
    end
    -- Báo status cho BẤT KỲ account (kể cả ALLY — không cần myMainIndex). (File A 330-333)
    function State.reportStatus(statusStr)
        State.statusCache[State.myName] = { t = tick(), status = statusStr }
        Net.postJSON(Config.baseUrl .. "/mainstatus?name=" .. State.myName, { status = statusStr }, "mainstatus")
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
        local url = B .. "/init?name=" .. Config.myName .. "&allies=" .. allies_str .. "&mains=" .. mains_str
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
        Net.postJSON(B .. "/heartbeat?name=" .. Config.myName, { role = State.myRole, fullmoon = fm }, "heartbeat")
    end

    -- Offline đúng 1 lần, gửi cả POST queue lẫn GET đồng bộ (File A 378-385)
    function ServerSync.sendOffline()
        if Runtime._offlineSent then return end
        Runtime._offlineSent = true
        Runtime.alive = false
        pcall(function() Net.postJSON(B .. "/offline?name=" .. Config.myName, { role = State.myRole }, "offline") end)
        pcall(function() Net.getRaw(B .. "/offline?name=" .. Config.myName) end)
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
                            State.mainJobCache[curr] = { jobid = data.current_jobid, time = data.current_time or 0, t = tick() }
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
                        pok = Net.raw("POST", B .. "/heartbeat?name=" .. Config.myName, HttpService:JSONEncode({ role = State.myRole }))
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
    Players.PlayerRemoving:Connect(function(plr)
        if plr == LocalPlayer and not Runtime.teleporting then ServerSync.sendOffline() end
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
        local entrance = door and door:FindFirstChild("Entrance")
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
      goToMyDoor. (File A 880-942)  (_G nội bộ → State.runtime; _G.lastDoor* giữ _G)
============================================================================ ]]
local TempleManager = {}
do
    local TEMPLE_ENTRY = TEMPLE_ENTRY_POS
    local TEMPLE_ENTRY_CF = CFrame.new(TEMPLE_ENTRY)
    TempleManager.TEMPLE_ENTRY = TEMPLE_ENTRY

    -- templeState: cache 0.5s, reparent MapStash throttle 5s, trả loading/ffup/ffdown (File A 911-942)
    function TempleManager.templeState()
        local t = tick()
        if State.runtime._tsCacheTime and (t - State.runtime._tsCacheTime) < 0.5 then return State.runtime._tsCacheValue end
        State.runtime._tsCacheTime = t
        local temple = WorldProbe.getTemple()
        if not temple then
            if not State.runtime.lastTempleReparent or (tick() - State.runtime.lastTempleReparent) > 5 then
                State.runtime.lastTempleReparent = tick()
                pcall(function()
                    local stash = ReplicatedStorage:FindFirstChild("MapStash")
                    local m = stash and stash:FindFirstChild("Temple of Time")
                    local map = workspace:FindFirstChild("Map")
                    if m and map then m.Parent = map end
                end)
            end
            State.runtime._tsCacheValue = "loading"
            return "loading"
        end
        local ff = WorldProbe.getForcefieldState()
        if ff == 0 then State.runtime._tsCacheValue = "ffup"; return "ffup" end
        State.runtime._tsCacheValue = "ffdown"
        return "ffdown"
    end

    -- goToMyDoor: xa temple >3000 → requestEntrance throttle 4s; gần → topos cửa; trả d<=150 (File A 880-901)
    function TempleManager.goToMyDoor()
        if Movement.getdis(CFrame.new(TEMPLE_ENTRY)) >= 3000 then
            if not State.runtime.lastReqEntrance or (tick() - State.runtime.lastReqEntrance) > 4 then
                State.runtime.lastReqEntrance = tick()
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
local function isfullmoon()
    return Lighting:GetAttribute("MoonPhase") == 5
end
_G.isfullmoon = isfullmoon   -- để heartbeat (khai báo trước) gọi được
local function isSamePlace(serverEntry)
    return serverEntry ~= nil and tonumber(serverEntry.placeid) == game.PlaceId
end

--[[ ============================================================================
 [16] TELEPORTMANAGER — hop fullmoon (cache 1h/placeid/player/blacklist 771) +
      hop server ít người (GetServers/HopServer) + cờ teleport riêng.
      (File A 604-708, 1146-1210)  (_G cờ hop → State.runtime)
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
        State.runtime.trainHopArmedT = tick()
        DBG(("[HOP] %s → teleport %s (Players=%d)"):format(tostring(Reason), tostring(ServerData.JobId), ServerData.Players), "ok")
        local ok = pcall(function()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", ServerData.JobId)
        end)
        return ok
    end

    -- ===== HOP FULLMOON (File A 1153-1210) =====
    function TeleportManager.hopFullmoon(reason)
        local hopped = false
        pcall(function()
            local cachedJobs = FileStore.readJson(CACHE_FILE, {})
            local thua = Net.getJSON(Config.FULLMOON_API, Config.FULLMOON_TTL)
            if not (thua and thua["success"] and type(thua["data"]) == "table") then
                DBG("[FM] API fullmoon lỗi/rỗng (success=" .. tostring(thua and thua["success"]) .. ")", "err", "fm_api")
                return
            end
            local now = math.floor(tick())
            local fresh, any = {}, {}
            local total, badPlace, tooMany, deadSkip = 0, 0, 0, 0
            for _, v in pairs(thua["data"]) do
                total = total + 1
                local jobid = v["jobid"]
                if jobid and jobid ~= game.JobId then
                    local dead = TeleportManager.deadJobs[jobid]
                    if dead and (tick() - dead) < Config.DEAD_JOB_TTL then
                        deadSkip = deadSkip + 1
                    elseif not isSamePlace(v) then
                        badPlace = badPlace + 1
                    elseif (v.player or 0) > 8 then
                        tooMany = tooMany + 1
                    else
                        local entry = { jobid = jobid, player = v.player or 0 }
                        table.insert(any, entry)
                        local lastVisit = cachedJobs[jobid]
                        if not lastVisit or (now - lastVisit) > Config.JOB_REVISIT_TTL then
                            table.insert(fresh, entry)
                        end
                    end
                end
            end
            local pool = (#fresh > 0) and fresh or any
            if #pool == 0 then
                DBG(("[FM] Không có server fullmoon hợp lệ (API=%d, khác placeid=%d, >8người=%d, chết=%d)")
                    :format(total, badPlace, tooMany, deadSkip), "err", "fm_nopool")
                return
            end
            table.sort(pool, function(a, b) return a.player < b.player end)
            local pick = pool[1]
            status(tostring(reason) .. " Hop fullmoon server (" .. tostring(pick.player) .. " người)")
            DBG(("[FM] %s → teleport %s (%d người, pool=%d/%d, chết=%d)")
                :format(tostring(reason), tostring(pick.jobid), pick.player, #pool, #any, deadSkip), "ok", "fm_hop")
            State.runtime.lastFullmoonJob = pick.jobid
            State.runtime.fmHopArmedT = tick()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", pick.jobid)
            hopped = true
        end)
        return hopped
    end

    -- ===== TeleportInitFailed: blacklist 771 + retry đúng cờ (File A 683-708) =====
    pcall(function()
        TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, message)
            if player ~= LocalPlayer then return end
            Runtime.teleporting = false   -- chống kẹt teleporting=true khi fail
            -- (1) FULLMOON HOP fail (771 server chết) → blacklist + thử fullmoon khác
            if State.runtime.fmHopArmedT and (tick() - State.runtime.fmHopArmedT) < 15 then
                State.runtime.fmHopArmedT = nil
                if State.runtime.lastFullmoonJob then
                    TeleportManager.deadJobs[State.runtime.lastFullmoonJob] = tick()
                    DBG("[FM] Teleport fail (" .. tostring(teleportResult) .. ") jobid chết → blacklist + thử server khác", "err", "fm_dead")
                end
                task.delay(2, function() TeleportManager.hopFullmoon("[FM-Retry]") end)
                return
            end
            -- (2) HOP ÍT NGƯỜI fail
            if State.runtime.trainHopArmedT and (tick() - State.runtime.trainHopArmedT) < 15 then
                State.runtime.trainHopArmedT = nil
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
            if State.runtime.allyHopArmedT and (tick() - State.runtime.allyHopArmedT) < 15 then
                State.runtime.allyHopArmedT = nil
                DBG("[ALLY] Teleport fail (" .. tostring(teleportResult) .. ") → vòng sau hop lại", "err", "ally_tpfail")
            end
        end)
    end)
end
-- alias File A
local function HopServer(reason, maxp) return TeleportManager.hopLowPlayer(reason, maxp) end
local function hopFullmoonServer(reason) return TeleportManager.hopFullmoon(reason) end

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
 [18] COMBAT — tách module con theo trách nhiệm; CombatActions = FACADE giữ call-site.
   • Targeting     : getmob1/checkmob_/getplayers/countplayers/pos_plr_trial
   • WeaponManager : getallweapon/EquipTool/isvalidtooltip
   • MobControl    : TweenObject/GetMobPosition/BringMob
   • SkillSpam     : start()/setSpam()/shouldSpam()  (cờ = State.runtime.SHOULDSPAMSKILLS)
   • FastAttackMod : start()  (RE/RegisterAttack, RE/RegisterHit, LeftClickRemote)
   • CombatActions : attackTick + facade (getmob1/getplayers/.../startSpamSkills/...)
   (File A 1214-1517, 2039-2395) — logic GIỮ NGUYÊN.
============================================================================ ]]
-- ---- Targeting ----
local Targeting = {}
do
    local LP = LocalPlayer
    -- vị trí 6 ô player trong trial (File A 944-951)
    Targeting.pos_plr_trial = {
        CFrame.new(28692.3477, 14887.5605, -53.7669983, 0.707131445, -0, -0.707082093, 0, 1, -0, 0.707082093, 0, 0.707131445),
        CFrame.new(28782.7246, 14898.9902, -59.6069946, 0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, 0.707134247),
        CFrame.new(28700.875, 14888.2598, -154.110992, -1, 0, 0, 0, 1, 0, 0, 0, -1),
        CFrame.new(28795.7715, 14888.2598, -112.917999, -0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, -0.707134247),
        CFrame.new(28658.4551, 14888.2598, -121.372009, -0.515037298, 0, -0.857167721, 0, 1, 0, 0.857167721, 0, -0.515037298),
        CFrame.new(28742.4688, 14887.5596, -18.2120056, 0.92051065, 0, 0.390717506, 0, 1, 0, -0.390717506, 0, 0.92051065),
    }

    function Targeting.getmob1(pos)
        local allmobs = {}
        for _, v in pairs(workspace.Enemies:GetChildren()) do
            if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid")
                and v.Humanoid.Health > 0 and Movement.getdis(v.HumanoidRootPart.CFrame, pos) < 1000 then
                table.insert(allmobs, v)
            end
        end
        return allmobs
    end
    function Targeting.checkmob_(v)
        return v and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0
    end

    local function noideaforname(v)
        if State.isAlly[v.Name] then return false end
        return true
    end
    function Targeting.getplayers()
        local plrs = {}
        for _, v in pairs(Players:GetPlayers()) do
            if v ~= LP and v.Character and not State.isMain[v.Name] and noideaforname(v) then
                local hum = v.Character:FindFirstChild("Humanoid")
                local hrp = v.Character:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0 then
                    for _, pos in pairs(Targeting.pos_plr_trial) do
                        if Movement.getdis(hrp.CFrame, pos) < 10 then
                            plrs[v.Character] = true
                        end
                    end
                end
            end
        end
        return plrs
    end
    function Targeting.countplayers()
        local c = 0
        for _ in pairs(Targeting.getplayers()) do c = c + 1 end
        return c
    end
end

-- ---- WeaponManager ----
local WeaponManager = {}
do
    local LP = LocalPlayer
    WeaponManager.isvalidtooltip = { ["Melee"] = true, ["Blox Fruit"] = true, ["Sword"] = true, ["Gun"] = true }
    function WeaponManager.getallweapon()
        local weapon = {}
        local bp = LP:FindFirstChild("Backpack")
        if bp then
            for _, v in pairs(bp:GetChildren()) do
                if v:IsA("Tool") and WeaponManager.isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
            end
        end
        if LP.Character then
            for _, v in pairs(LP.Character:GetChildren()) do
                if v:IsA("Tool") and WeaponManager.isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
            end
        end
        return weapon
    end
    function WeaponManager.EquipTool(v)
        local bp = LP:FindFirstChild("Backpack")
        local thua = bp and bp:FindFirstChild(v)
        if thua and LP.Character and LP.Character:FindFirstChild("Humanoid") then
            LP.Character.Humanoid:EquipTool(thua)
        end
    end
end

-- ---- MobControl ----
local MobControl = {}
do
    local LP = LocalPlayer
    function MobControl.TweenObject(Object, Pos, Speed)
        if Speed == nil then Speed = 350 end
        if not (Object and Object.Parent) then return end
        local Distance = (Pos.Position - Object.Position).Magnitude
        local dur = math.clamp(Distance / Speed, 0.03, 3)
        local tw = TweenService:Create(Object, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = Pos })
        tw.Completed:Once(function() pcall(function() tw:Destroy() end) end)
        tw:Play()
    end
    function MobControl.GetMobPosition(EnemiesName)
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
    function MobControl.BringMob()
        local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myHrp then return end
        local ememe = workspace.Enemies:GetChildren()
        if #ememe > 0 then
            local totalpos = {}
            for _, v in pairs(ememe) do
                if not totalpos[v.Name] then totalpos[v.Name] = MobControl.GetMobPosition(v.Name) end
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
                                    MobControl.TweenObject(v.HumanoidRootPart, dest, 300)
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
end

-- ---- SkillSpam (cờ = State.runtime.SHOULDSPAMSKILLS) ----
local SkillSpam = {}
do
    local LP = LocalPlayer
    local fruits = {
        ['Buddha-Buddha'] = true, ['T-Rex-T-Rex'] = true, ['Dragon-Dragon'] = true, ['Yeti-Yeti'] = true,
        ['Leopard-Leopard'] = true, ['Venom-Venom'] = true, ['Phoenix-Phoenix'] = true, ['Kitsune-Kitsune'] = true,
        ['Mammoth-Mammoth'] = true, ['Gas-Gas'] = true, ["Portal-Portal"] = true,
    }
    local isvalidnameui = { ["Z"] = true, ["X"] = true, ["C"] = true, ["V"] = true, ["F"] = true }

    function SkillSpam.setSpam(v) State.runtime.SHOULDSPAMSKILLS = v end
    function SkillSpam.shouldSpam() return State.runtime.SHOULDSPAMSKILLS end

    -- spam-skills loop: BẬT theo State.runtime.SHOULDSPAMSKILLS, 1 instance, check Runtime.alive (File A 2071-2123)
    function SkillSpam.start()
        task.spawn(function()
            while Runtime.alive do
                task.wait()
                if State.runtime.SHOULDSPAMSKILLS then
                    pcall(function()
                        local char = LP.Character
                        local skillsUI = LP.PlayerGui:FindFirstChild("Main")
                        skillsUI = skillsUI and skillsUI:FindFirstChild("Skills")
                        if not (char and skillsUI) then return end
                        local weapon = WeaponManager.getallweapon()
                        for _, v in pairs(weapon) do
                            if not skillsUI:FindFirstChild(v.Name) then WeaponManager.EquipTool(v.Name) end
                        end
                        for _, v in pairs(weapon) do
                            if v.Parent ~= char then WeaponManager.EquipTool(v.Name) end
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
end

-- ---- FastAttackMod (File A 2228-2323) ----
local FastAttackMod = {}
do
    function FastAttackMod.start()
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
        local Player = LocalPlayer
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
end

-- ---- CombatActions FACADE (giữ call-site cũ) ----
local CombatActions = {}
do
    -- facade Targeting
    CombatActions.pos_plr_trial = Targeting.pos_plr_trial
    CombatActions.getmob1       = Targeting.getmob1
    CombatActions.checkmob_     = Targeting.checkmob_
    CombatActions.getplayers    = Targeting.getplayers
    CombatActions.countplayers  = Targeting.countplayers
    -- facade MobControl
    CombatActions.BringMob      = MobControl.BringMob

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
        State.runtime.SHOULDSPAMSKILLS = true
        if tick() - _atkEqT > 0.4 then
            _atkEqT = tick()
            pcall(function() Movement.equip() end)
            pcall(function() Movement.haki() end)
        end
        local hrp = target and target:FindFirstChild("HumanoidRootPart")
        if hrp then pcall(function() topos(hrp.CFrame * _atkOff) end) end
    end

    -- facade khởi động loop nền
    CombatActions.startSpamSkills = SkillSpam.start
    CombatActions.startFastAttack = FastAttackMod.start
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
    function GearManager.checkGear()
        local _okcg, dt = SafeRemote.invoke(3, "TempleClock", "Check")
        if not (dt and type(dt) == "table") then return end
        if not dt.HadPoint then return end
        local rd = dt.RaceDetails
        if not (rd and rd.Completed ~= nil) then return end
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
      (_G.mink*/skyFinish/SHOULDSPAMSKILLS → State.runtime)
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
            if tick() - (State.runtime.minkLastTrial or 0) > 3 then task.wait(2) end
            State.runtime.minkLastTrial = tick()
            local sp = State.runtime.minkStartPoint
            if not (sp and sp.Parent) then
                sp = nil
                pcall(function()
                    for _, obj in pairs(workspace:GetDescendants()) do
                        if obj.Name == "StartPoint" then sp = obj break end
                    end
                end)
                State.runtime.minkStartPoint = sp
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
                local c = State.runtime.skyFinish
                if c and c.Parent then finish = c
                else
                    pcall(function()
                        for _, obj in pairs(workspace:GetDescendants()) do
                            if obj.Name == "snowisland_Cylinder.081" then finish = obj break end
                        end
                    end)
                    State.runtime.skyFinish = finish
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
                            State.runtime.SHOULDSPAMSKILLS = true
                        until (not v.Parent) or (not v:FindFirstChild('Health')) or v.Health.Value <= 0
                            or (not v:FindFirstChild("HumanoidRootPart")) or (tick() - t0) > 25
                        State.runtime.SHOULDSPAMSKILLS = false
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
      (File A 953-961, 1283-1329, 1583-1672)  (_G.train* → State.runtime; _G.lastRaceI giữ _G)
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

    -- trialable (File A 1283-1319)
    function Training.checkTrialable()
        local char = LP.Character
        if not (char and char:FindFirstChild("RaceTransformed")) then
            local okI, i5 = SafeRemote.invoke(3, "UpgradeRace", "Check")
            _G.lastRaceI = okI and i5 or "?"
            if okI and (i5 == 5 or i5 == 8) then return false, "done" end
            local race = WorldProbe.getRace()
            local abcxyz = race and checkbackpack(race_abilities[race])
            if abcxyz then return true end
            return false
        end
        local ok, i, d, f = SafeRemote.invoke(3, "UpgradeRace", "Check")
        if not ok then _G.lastRaceI = "?"; return false end
        _G.lastRaceI = i
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

    -- cache TTL 1.5s (File A 1321-1329)
    local _trCache = { t = -1e9, ab = nil, AB = nil }
    function Training.cachedTrialable()
        if (tick() - _trCache.t) < 1.5 then return _trCache.ab, _trCache.AB end
        local ab, AB = Training.checkTrialable()
        _trCache.t, _trCache.ab, _trCache.AB = tick(), ab, AB
        return ab, AB
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
        if not State.runtime.trainWinStart then return false end
        if (tick() - State.runtime.trainWinStart) < Config.TRAIN_WINDOW then return false end
        if (State.runtime.trainKills or 0) > 10 then
            State.runtime.trainWinStart = tick(); State.runtime.trainKills = 0
            return false
        end
        status(tag .. " ⏱ Timeout train (kill " .. tostring(State.runtime.trainKills or 0) .. "/5' <=10) → hop server")
        HopServer(("Timeout train kill %d/5phut <=10"):format(State.runtime.trainKills or 0))
        State.runtime.trainWinStart = tick(); State.runtime.trainKills = 0
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
            if not State.runtime.trainGrindLastT or (tick() - State.runtime.trainGrindLastT) > 5 then
                State.runtime.trainWinStart = tick(); State.runtime.trainKills = 0
            end
            State.runtime.trainGrindLastT = tick()
            if not State.runtime.trainWinStart then State.runtime.trainWinStart = tick() end
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
                if State.isMain[State.myName] then State.runtime.trainKills = (State.runtime.trainKills or 0) + 1 end
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
      (_G nội bộ ability → State.runtime; _G.lastDoor*/lastSameSrv giữ _G cho UI)
      Loop nền GỌI LẠI reportAtDoor()/maybeFire()/pollFire() (D1/D2/D3 — hết duplicate).
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

    State.runtime.myFireEpoch = State.runtime.myFireEpoch or 0

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

    -- toạ độ cửa dự phòng (File A 2466-2473)
    local BANANA_DOOR_CFRAME = {
        Human   = CFrame.new(29221.822, 14890.975, -205.991),
        Skypiea = CFrame.new(28960.158, 14919.624, 235.039),
        Fishman = CFrame.new(28231.175, 14890.975, -211.641),
        Cyborg  = CFrame.new(28502.681, 14895.975, -423.727),
        Ghoul   = CFrame.new(28674.244, 14890.676, 445.431),
        Mink    = CFrame.new(29012.341, 14890.975, -380.149),
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

    -- cùng server với main đang turn (cache 3s) (File A 2520-2531)
    local _ssCache = { t = -1e9, v = false }
    function AbilitySync.sameServerAsCurrentMain()
        local curName = getCurrentMainBeingUpgraded()
        if not curName then return false end
        if State.myName == curName then return true end
        local now = tick()
        if now - _ssCache.t < 3 then return _ssCache.v end
        local same = isSameServerAsMain(curName)
        _ssCache.t = now
        _ssCache.v = same and true or false
        return _ssCache.v
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
        local fe = State.runtime.myFireEpoch or 0
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
        local fe = State.runtime.myFireEpoch or 0
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

    -- reportAtDoor: ghi check của mình (File A 2627-2637 — phần dd/ss/cond/myDoorReady/writeMyCheck)
    function AbilitySync.reportAtDoor()
        local label = AbilitySync.myAbilityLabel()
        if not label then return end
        local dd = AbilitySync.distToMyDoor()
        local ss = AbilitySync.sameServerAsCurrentMain()
        _G.lastDoorDist = dd; _G.lastSameSrv = ss
        local cond = (dd < AT_DOOR_DIST) and ss
        State.runtime.myDoorReady = cond and true or false
        AbilitySync.writeMyCheck(label, cond)
    end
    -- maybeFire: main turn chốt starttime khi đủ ready (File A 2641-2651)
    function AbilitySync.maybeFire()
        local curName = getCurrentMainBeingUpgraded()
        if not (curName and State.myName == curName) then return end
        local now = serverNow()
        local last = State.runtime.myStartEpoch or 0
        if (now - last) > (START_LEAD + ABILITY_FIRE_WINDOW) and AbilitySync.allReady() then
            AbilitySync.writeStart(now + START_LEAD)
            State.runtime.myStartEpoch = now
        end
    end
    -- pressAbility: CommE ActivateAbility (File A 2688)
    function AbilitySync.pressAbility()
        State.runtime.myFireEpoch = serverNow()
        pcall(function()
            ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
        end)
    end
    -- pollFire: đọc starttime, bấm trong cửa sổ hợp lệ, latch chống lặp (File A 2673-2698)
    function AbilitySync.pollFire()
        local st = AbilitySync.readStart() or State.runtime.syncStart
        if st then State.runtime.syncStart = st end
        if st and st ~= State.runtime.allyLastFire then
            local age = hanoiSecOfDay(serverNow()) - st
            if age < -43200 then age = age + 86400 end
            if age >= ABILITY_FIRE_WINDOW then
                State.runtime.allyLastFire = st
            elseif age >= 0 and AbilitySync.distToMyDoor() < AT_DOOR_DIST then
                State.runtime.allyLastFire = st
                AbilitySync.pressAbility()
            end
        end
    end

    -- ===== 3 LOOP NỀN (File A 2623-2698) — gọi lại hàm nguồn (D1/D2/D3), check Runtime.alive =====
    function AbilitySync.startLoops()
        -- write loop 1s (File A 2623-2657)
        task.spawn(function()
            while Runtime.alive do
                pcall(function()
                    -- D1: GIỮ NGUYÊN side-effect — reset myDoorReady đầu mỗi vòng (kể cả khi label nil)
                    State.runtime.myDoorReady = false
                    local label = AbilitySync.myAbilityLabel()
                    if label then
                        AbilitySync.reportAtDoor()   -- dd/ss/cond/myDoorReady/writeMyCheck
                        AbilitySync.maybeFire()      -- D2: main turn chốt starttime
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
                    if v then State.runtime.syncStart = v end
                end)
                task.wait(1)
            end
        end)
        -- press loop: ở cửa+ready → 0.1s, chưa → 0.5s (File A 2673-2698)
        task.spawn(function()
            while Runtime.alive do
                if State.runtime.myDoorReady == true then
                    pcall(AbilitySync.pollFire)   -- D3: bấm ability đúng cửa sổ + latch
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
      (_G.allyKillReset/SHOULDSPAMSKILLS → State.runtime)
============================================================================ ]]
local PostTrial = {}
do
    local B = Config.baseUrl

    -- Ally auto-reset 1 lần (File A 1966-1982)
    function PostTrial.resetAllyOnce(roleName)
        if State.runtime.allyKillReset then return "ally_reset" end
        State.runtime.allyKillReset = true
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
        State.runtime.SHOULDSPAMSKILLS = false
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
 [24] TEAMMANAGER — join team bền (remote SetTeam + ChooseTeam UI getgc). (File A 528-559)
============================================================================ ]]
local TeamManager = {}
function TeamManager.start()
    task.spawn(function()
        local team = Config.team
        local attempts = 0
        while Runtime.alive and not LocalPlayer.Team and attempts < 40 do
            attempts = attempts + 1
            SafeRemote.invoke(3, "SetTeam", team)
            task.wait(0.4)
            if LocalPlayer.Team then break end
            pcall(function()
                local chooseGui = LocalPlayer.PlayerGui:FindFirstChild("ChooseTeam", true)
                local uiCtrl    = LocalPlayer.PlayerGui:FindFirstChild("UIController", true)
                if chooseGui and chooseGui.Visible and uiCtrl and getgc then
                    for _, fn in pairs(getgc(true)) do
                        if type(fn) == "function" and getfenv(fn).script == uiCtrl then
                            local consts = getconstants(fn)
                            if consts and #consts == 1 and (consts[1] == "Pirates" or consts[1] == "Marines") then
                                if consts[1] == team then pcall(fn, team) end
                            end
                        end
                    end
                end
            end)
            task.wait(0.8)
        end
        if LocalPlayer.Team then
            Logger.ok("Join team OK (" .. tostring(team) .. ") sau " .. attempts .. " lần")
        else
            Logger.warn("Join team chưa xong sau " .. attempts .. " lần", "team_fail")
        end
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
      (_G.templeDoorOK → State.runtime.templeDoorOK)
============================================================================ ]]
local TempleDoorGate = {}
do
    local FILE = Config.myName .. "_kaitunv4.json"
    function TempleDoorGate.ready()
        if State.runtime.templeDoorOK then return true end
        local fdata = FileStore.readJson(FILE, {})
        if fdata.templedoor == true then State.runtime.templeDoorOK = true; return true end
        local ok, res = SafeRemote.invoke(3, "CheckTempleDoor")
        if ok and res then
            State.runtime.templeDoorOK = true
            FileStore.writeJson(FILE, { templedoor = true })
            return true
        end
        return res
    end
end

--[[ ============================================================================
 [27] GAME READY GATE — chờ team/char/data (timeout 45s), KHÔNG block. (File A 1549-1568)
============================================================================ ]]
local function startGameReadyGate()
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
            if ready then break end
        until (tick() - t0) > 45
        _G.gameReady = true
        Logger.ok(("Game ready gate: elapsed=%.1fs"):format(tick() - t0))
    end)
end

--[[ ============================================================================
 [28] STATEMACHINE — flow chính y chang File A main loop (1689-2030).
      tick() = build ctx → validateInvariants → normalize → timeout → latch →
               main/ally branch. GIỮ NGUYÊN thứ tự if/elseif + return sớm +
               thời điểm set status. (_G nội bộ → State.runtime; _G.ShouldSendData giữ _G)
============================================================================ ]]
local StateMachine = {}
do
    StateMachine.state = "BOOTING"
    StateMachine._lastStatus = nil

    local S = {
        BOOTING = "BOOTING", WAITING_ROLE = "WAITING_ROLE", WAITING_MAIN = "WAITING_MAIN",
        FOLLOWING_MAIN = "FOLLOWING_MAIN", WAITING_MOON = "WAITING_MOON", GOING_DOOR = "GOING_DOOR",
        IN_TRIAL = "IN_TRIAL", POST_TRIAL = "POST_TRIAL", TRAINING = "TRAINING",
        DONE = "DONE", ERROR_RECOVER = "ERROR_RECOVER",
    }
    StateMachine.S = S
    function StateMachine.transition(newState, reason)
        if StateMachine.state == newState then return end
        Logger.info(("FSM %s → %s (%s)"):format(StateMachine.state, newState, tostring(reason)), "fsm_" .. newState)
        StateMachine.state = newState
    end

    -- ---------- ctx ----------
    -- Chỉ snapshot giá trị code gốc cũng đọc 1 lần ở đầu tick; myStatus là MUTABLE
    -- (mang qua các block như biến local cũ). templeState/race/trialPlace giữ LIVE-READ
    -- trong hàm con (đúng như code gốc gọi nhiều lần).
    function StateMachine.buildTickContext()
        local me = State.myName
        local isMain = State.isMain[me] == true
        local ab, AB = cachedTrialable()
        local currentmain = getCurrentMainBeingUpgraded()
        local myStt = mainSttOf(me) or State.myMainIndex
        local myStatus = ""
        if isMain then myStatus = State.getMainStatus(me) end
        return {
            me = me, isMain = isMain, ab = ab, AB = AB,
            currentMain = currentmain, myStt = myStt, myStatus = myStatus,
        }
    end

    -- ---------- invariant warnings (CHỈ log, không mutate, throttle theo key) ----------
    local _lastTeleFalseT = tick()
    function StateMachine.validateInvariants(ctx)
        pcall(function()
            -- #6 teleporting kẹt >30s
            if not Runtime.teleporting then
                _lastTeleFalseT = tick()
            elseif (tick() - _lastTeleFalseT) > 30 then
                Logger.warn("INV: Runtime.teleporting=true quá 30s (kẹt teleport?)", "inv_tele_stuck")
            end
            -- #7 role unknown >60s sau khi script chạy
            if State.myRole == "unknown" and (tick() - Runtime.startedAt) > 60 then
                Logger.warn("INV: role vẫn 'unknown' quá 60s sau init", "inv_role_unknown")
            end
            -- #2 currentMain nil >15s sau khi /curmain từng OK
            if not ctx.currentMain and State._lastCurMainOK > 0 and (tick() - State._lastCurMainOK) > 15 then
                Logger.warn("INV: currentMain=nil quá 15s sau /curmain OK", "inv_curmain_nil")
            end
            -- #1 status done nhưng đang ở trial zone (cửa mở)
            if ctx.isMain and ctx.myStatus == "done" then
                local tp = getRaceTrialPlace(WorldProbe.getRace())
                if tp and getdis(tp.CFrame) < 1500 and templeState() ~= "ffup" then
                    Logger.warn("INV: status=done nhưng đang ở trial zone", "inv_done_in_trial")
                end
            end
            -- #3 khác server current main nhưng myDoorReady=true
            if State.runtime.myDoorReady == true and _G.lastSameSrv == false then
                Logger.warn("INV: myDoorReady=true nhưng khác server current main", "inv_ready_diffsrv")
            end
            -- #5 role không phải main nhưng có myMainIndex (mâu thuẫn role)
            if not ctx.isMain and State.myMainIndex ~= nil then
                Logger.warn("INV: không phải main nhưng myMainIndex ~= nil", "inv_ally_hasindex")
            end
        end)
    end

    -- ---------- block1: chuẩn hoá status main (File A 1702-1742). KHÔNG return. ----------
    function StateMachine.normalizeMainStatus(ctx)
        if not ctx.isMain then return end
        if ctx.AB == "done" then
            if ctx.myStatus ~= "done" then State.setMyMainStatus("done"); ctx.myStatus = "done" end
            if getgenv().change and not State.runtime.changeFileWritten then
                local _okw = pcall(function()
                    local race = LocalPlayer.Data.Race.Value
                    writefile(LocalPlayer.Name .. ".txt", "Completed-" .. tostring(race))
                end)
                if _okw then State.runtime.changeFileWritten = true end
            end
        else
            if ctx.myStatus == "done" then State.setMyMainStatus("waiting"); ctx.myStatus = "waiting" end
            State.runtime.changeFileWritten = false
            if (ctx.myStatus == "in_trail" or ctx.myStatus == "moon") and not ctx.ab then
                local inOwnFFA = (ctx.myStatus == "in_trail") and (templeState() == "ffup")
                    and (getdis(CFrame.new(TEMPLE_ENTRY_POS)) < 2000)
                if not inOwnFFA then
                    status("[MAIN " .. ctx.myStt .. "] Trial completed, switching to training!")
                    State.setMyMainStatus("training"); ctx.myStatus = "training"
                else
                    status("[MAIN " .. ctx.myStt .. "] Trial done → ở lại kill player (FFA)")
                end
            end
        end
        if ctx.myStatus == "in_trail" and ctx.ab then
            local in_temple = getdis(CFrame.new(TEMPLE_ENTRY_POS)) < 3000
            if not in_temple then
                status("[MAIN " .. ctx.myStt .. "] Died in trial, retrying...")
                State.setMyMainStatus("waiting"); ctx.myStatus = "waiting"
            end
        end
    end

    -- ---------- block2: MAIN STT1 quá 5' (File A 1746-1768). return true → thoát tick. ----------
    function StateMachine.checkMainTurnTimeout(ctx)
        if not ctx.isMain then return false end
        if ctx.currentMain == ctx.me and ctx.myStatus ~= "training" and ctx.myStatus ~= "done" then
            if not State.runtime.myTurnStart then State.runtime.myTurnStart = tick() end
            if (tick() - State.runtime.myTurnStart) > Config.MAIN_TURN_TIMEOUT then
                status("[MAIN " .. ctx.myStt .. "] ⏱ Quá 5 phút chưa xong lượt → tụt cuối (waiting)")
                State.setMyMainStatus("waiting"); ctx.myStatus = "waiting"
                State.runtime.inTrial = false
                State.runtime.myTurnStart = nil
                return true
            end
        else
            State.runtime.myTurnStart = nil
        end
        return false
    end

    -- ---------- block3: IN-TRIAL latch (File A 1770-1809). return true → thoát tick. ----------
    function StateMachine.handleInTrialLatch(ctx)
        local _tplace = getRaceTrialPlace(WorldProbe.getRace())
        local _inTrialNow = (_tplace and ctx.ab and getdis(_tplace.CFrame) < 1500 and templeState() ~= "ffup") and true or false
        if _inTrialNow then
            if ctx.isMain then
                if ctx.myStatus ~= "in_trail" then State.setMyMainStatus("in_trail"); ctx.myStatus = "in_trail" end
            elseif not State.runtime.inTrial then
                State.reportStatus("in_trail")
            end
            State.runtime.inTrial = true
            StateMachine.transition(S.IN_TRIAL, "in trial zone")
            status((ctx.isMain and ("[MAIN " .. tostring(ctx.myStt) .. "]") or "[ALLY]") .. " 🔥 IN-TRIAL → đang làm trial")
            doTrialForMyRace()
            return true
        else
            if State.runtime.inTrial then
                if not ctx.isMain then
                    State.reportStatus("ally")
                else
                    local fresh_ab, fresh_AB = trialable()
                    if not fresh_ab then
                        if fresh_AB == "done" then State.setMyMainStatus("done")
                        else State.setMyMainStatus("training") end
                    end
                end
            end
            State.runtime.inTrial = false
        end
        return false
    end

    -- ---------- MAIN branch (File A 1811-1909) ----------
    function StateMachine.mainDone(ctx)
        StateMachine.transition(S.DONE, "full gear")
        status("[MAIN " .. ctx.myStt .. "] ✅ DONE YOUR RACE - FULL GEAR (Gear2/3/4)!")
    end

    function StateMachine.mainTraining(ctx)
        StateMachine.transition(S.TRAINING, "training")
        status("[MAIN " .. ctx.myStt .. "] Training (parallel)")
        if not ctx.ab then
            State.setMyMainStatus("training")
            Training.handleTraining("[MAIN " .. ctx.myStt .. "]", ctx.AB, function() State.setMyMainStatus("training") end)
        else
            if ctx.myStatus ~= "waiting" then State.setMyMainStatus("waiting") end
            status("[MAIN " .. ctx.myStt .. "] Training done → waiting (chờ tới lượt)")
        end
    end

    -- ffup nhánh my-turn (File A 1854-1870)
    function StateMachine.mainPostTrial(ctx)
        if ctx.myStatus == "in_trail" then
            PostTrial.mainKillThenReset(ctx.myStt, ctx.currentMain)
        else
            status("[MAIN " .. ctx.myStt .. "] Chờ ở cửa (chưa in_trail → KHÔNG kill)")
            goToMyDoor()
        end
    end
    -- ffdown nhánh my-turn (File A 1871-1873 + reportAtDoor/maybeFire)
    function StateMachine.mainDoorAndAbility(ctx)
        runTrialPhase("[MAIN " .. ctx.myStt .. "]", true)
        AbilitySync.reportAtDoor()
        AbilitySync.maybeFire()
    end

    function StateMachine.mainMyTurn(ctx)
        StateMachine.transition(S.GOING_DOOR, "my turn")
        status("[MAIN " .. ctx.myStt .. "] My turn to upgrade gear!")
        if ctx.myStatus == "waiting" or ctx.myStatus == "" then State.setMyMainStatus("moon") end
        local skip = false
        if Config.hopFullMoon then
            local isInFullmoonServer = isfullmoon()
            if (not isInFullmoonServer or not isnight()) and ctx.myStatus ~= "in_trail" then
                StateMachine.transition(S.WAITING_MOON, "hop fullmoon")
                if hopFullmoonServer("[MAIN " .. ctx.myStt .. "]") then
                    task.wait(10)
                    Net.postJSON(Config.baseUrl .. "/noguchi?name=" .. ctx.me, { jobid = game.JobId }, "noguchi")
                    skip = true
                end
            end
        end
        if not skip then
            task.spawn(checkgear)
            _G.ShouldSendData = true
            local ts = templeState()
            if ts == "loading" then
                status("[MAIN " .. ctx.myStt .. "] Đang vào Temple of Time...")
            elseif ts == "ffup" then
                StateMachine.transition(S.POST_TRIAL, "ffup")
                StateMachine.mainPostTrial(ctx)
            else
                StateMachine.mainDoorAndAbility(ctx)
            end
        end
    end

    function StateMachine.mainWaitingTurn(ctx)
        State.runtime.allyKillReset = false
        if (not ctx.ab) and ctx.AB ~= "done" then
            if ctx.myStatus ~= "training" then State.setMyMainStatus("training") end
            StateMachine.transition(S.TRAINING, "train parallel")
            status("[MAIN " .. ctx.myStt .. "] Training song song (chưa tới lượt)")
            Training.handleTraining("[MAIN " .. ctx.myStt .. "]", ctx.AB, function() State.setMyMainStatus("training") end)
        else
            if ctx.myStatus == "training" then State.setMyMainStatus("waiting") end
            StateMachine.transition(S.WAITING_MAIN, "waiting turn")
            local isWaitFmStt = (type(ctx.myStt) == "number") and ctx.myStt >= 2 and ctx.myStt <= 4
            if isWaitFmStt and Config.hopFullMoon then
                local lastTry = State.runtime.waitFmHopT or 0
                if (not isfullmoon()) and (tick() - lastTry) > 30 then
                    State.runtime.waitFmHopT = tick()
                    status("[MAIN " .. ctx.myStt .. "] Waiting + Hop Full Moon (chờ: " .. tostring(ctx.currentMain) .. ")")
                    if hopFullmoonServer("[MAIN " .. ctx.myStt .. "] Waiting →") then
                        task.wait(10)
                        Net.postJSON(Config.baseUrl .. "/noguchi?name=" .. ctx.me, { jobid = game.JobId }, "noguchi")
                    end
                else
                    status("[MAIN " .. ctx.myStt .. "] Waiting + Full Moon (chờ: " .. tostring(ctx.currentMain) .. ")")
                end
            else
                status("[MAIN " .. ctx.myStt .. "] Waiting for current main: " .. tostring(ctx.currentMain))
            end
        end
    end

    -- elseif chain main (giữ NGUYÊN thứ tự: done → training → currentmain==me → waiting)
    function StateMachine.handleMainBranch(ctx)
        if ctx.myStatus == "done" then
            StateMachine.mainDone(ctx)
        elseif ctx.myStatus == "training" then
            StateMachine.mainTraining(ctx)
        elseif ctx.currentMain == ctx.me then
            StateMachine.mainMyTurn(ctx)
        else
            StateMachine.mainWaitingTurn(ctx)
        end
    end

    -- ---------- ALLY branch (File A 1910-2029) ----------
    function StateMachine.allyTraining(ctx, roleName)
        State.runtime.allyKillReset = false
        State.reportStatus("training")
        StateMachine.transition(S.TRAINING, "ally train")
        status(roleName .. " Train race (chưa sẵn sàng trial) → tạm dừng phụ main")
        Training.handleTraining(roleName, ctx.AB, function() State.reportStatus("training") end)
    end

    function StateMachine.allyFollowMain(ctx, roleName, mainJob)
        State.runtime.allyKillReset = false
        StateMachine.transition(S.FOLLOWING_MAIN, "hop to main")
        status(roleName .. " Hop sang server main: " .. tostring(ctx.currentMain))
        if mainJob and mainJob ~= "" and mainJob ~= game.JobId then
            if not State.runtime.lastAllyHop or (tick() - State.runtime.lastAllyHop) > 5 then
                State.runtime.lastAllyHop = tick()
                State.runtime.allyHopArmedT = tick()
                pcall(function()
                    ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", mainJob)
                end)
            end
        end
    end

    -- cùng server / VIP / (night&fullmoon) → loading | ffup(post-trial) | ffdown(door+ability)
    function StateMachine.allyServerPhase(ctx, roleName)
        task.spawn(checkgear)
        _G.ShouldSendData = true
        local ts = templeState()
        if ts == "loading" then
            status(roleName .. " Đang vào Temple of Time...")
        elseif ts == "ffup" then
            StateMachine.transition(S.POST_TRIAL, "ally ffup")
            PostTrial.resetAllyOnce(roleName)
        else
            State.runtime.allyKillReset = false
            StateMachine.transition(S.GOING_DOOR, "ally to door")
            runTrialPhase(roleName, false)
            AbilitySync.reportAtDoor()
        end
    end

    function StateMachine.handleAllyBranch(ctx)
        local roleName = "[ALLY]"
        if (not ctx.ab) and ctx.AB ~= "done" then
            StateMachine.allyTraining(ctx, roleName)
            return
        end
        status(roleName .. " Đang dò main đang tới lượt…")
        local mainActive = false
        if ctx.currentMain then
            local st = State.getMainStatus(ctx.currentMain)
            mainActive = (st == "moon" or st == "in_trail")
            status(roleName .. " main " .. tostring(ctx.currentMain) .. " = " .. tostring(st))
        end
        local sameServer, mainJob = isSameServerAsMain(ctx.currentMain)
        if ctx.currentMain and mainActive and not sameServer then
            StateMachine.allyFollowMain(ctx, roleName, mainJob)
        elseif (ctx.currentMain and mainActive and sameServer) or Config.vipServer or (isnight() and isfullmoon()) then
            StateMachine.allyServerPhase(ctx, roleName)
        else
            State.runtime.allyKillReset = false
            StateMachine.transition(S.WAITING_MAIN, "ally wait main")
            status(roleName .. " Waiting for current main: " .. tostring(ctx.currentMain))
        end
    end

    -- ---------- tick: GIỮ NGUYÊN thứ tự + return sớm ----------
    function StateMachine.tick()
        _G.ShouldSendData = false
        local ctx = StateMachine.buildTickContext()
        StateMachine.validateInvariants(ctx)
        StateMachine.normalizeMainStatus(ctx)                 -- block1 (no return)
        if StateMachine.checkMainTurnTimeout(ctx) then return end  -- block2
        if StateMachine.handleInTrialLatch(ctx) then return end    -- block3
        if ctx.isMain then
            StateMachine.handleMainBranch(ctx)
        else
            StateMachine.handleAllyBranch(ctx)
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
            Net.postJSON(Config.baseUrl .. "/noguchi?name=" .. State.myName, { jobid = game.JobId }, "noguchi")
            task.wait(1)
        end
    end)
end

--[[ ============================================================================
 [31] UIMANAGER — GUI Premium (port File A 2709-3373) + fallback text-only.
      safeCreate() bọc TỪNG nhóm → fail ở bước nào biết bước đó (không pcall lớn).
      Layout/text/màu/update-loop GIỮ NGUYÊN. UI lỗi KHÔNG làm chết main loop.
============================================================================ ]]
local UIManager = {}
function UIManager.start()
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

    -- safeCreate: xpcall TỪNG nhóm; fail → log đúng nhãn, trả nil (không ném ra ngoài)
    local function safeCreate(label, fn)
        local ok, result = xpcall(fn, debug.traceback)
        if not ok then
            Logger.err("UI fail @ " .. tostring(label) .. ": " .. tostring(result), "ui_fail_" .. tostring(label))
            return nil
        end
        return result
    end

    -- ===== shared upvalues (đối tượng + builder dùng chung giữa các nhóm) =====
    local Gui, Toggle, togStroke, Panel, pStroke, Header, Title, SubTitle, CloseBtn
    local TabBar, tabLayout, PageHolder
    local pages, tabBtns = {}, {}
    local StatusValue, NetDiag, PlaceCard, SyncDbg
    local mainStatusLabels = {}
    local setLoop, setNet, setSrv, setDoor, setMain
    local logSF
    local logLabels = {}

    -- ===== builder helpers (định nghĩa không thể fail; chỉ chạy khi được gọi) =====
    local function RegisterRGB(obj, offset, s, v, prop)
        local hue = (0.65 + (offset or 0)) % 1
        pcall(function() obj[prop or "Color"] = Color3.fromHSV(hue, s or 0.85, v or 1) end)
    end
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
    local function IndicatorRow(debugPage, order, labelText)
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

    -- ===== nhóm dựng UI (mỗi nhóm xpcall riêng) =====
    safeCreate("ScreenGui setup", function()
        pcall(function()
            local old = LocalPlayer.PlayerGui:FindFirstChild("VuNguyenKaitunV4")
            if old then old:Destroy() end
        end)
        Gui = Instance.new("ScreenGui")
        Gui.Name = "VuNguyenKaitunV4"; Gui.ResetOnSpawn = false; Gui.IgnoreGuiInset = false
        Gui.DisplayOrder = 1000; Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end)

    safeCreate("Toggle setup", function()
        Toggle = Instance.new("TextButton")
        Toggle.Size = UDim2.new(0, 54, 0, 54); Toggle.Position = UDim2.new(1, -70, 0.30, 0)
        Toggle.BackgroundColor3 = Color3.fromRGB(18, 20, 28); Toggle.BorderSizePixel = 0
        Toggle.Text = "👑"; Toggle.TextSize = 26; Toggle.Font = Enum.Font.GothamBold
        Toggle.TextColor3 = Color3.fromRGB(255, 255, 255); Toggle.AutoButtonColor = false; Toggle.Parent = Gui
        Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0, 14)
        togStroke = Instance.new("UIStroke", Toggle)
        togStroke.Thickness = 2.5; togStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        RegisterRGB(togStroke, 0)
    end)

    safeCreate("Panel setup", function()
        Panel = Instance.new("Frame")
        Panel.Size = UDim2.new(0, 320, 0, 460); Panel.Position = UDim2.new(0.5, -160, 0.5, -230)
        Panel.BackgroundColor3 = Color3.fromRGB(12, 14, 22); Panel.BorderSizePixel = 0
        Panel.Active = true; Panel.Draggable = true; Panel.Visible = true; Panel.Parent = Gui
        Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 16)
        pStroke = Instance.new("UIStroke", Panel)
        pStroke.Thickness = 2.5; pStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        RegisterRGB(pStroke, 0)
    end)

    safeCreate("Header setup", function()
        Header = Instance.new("Frame")
        Header.Size = UDim2.new(1, -20, 0, 52); Header.Position = UDim2.new(0, 10, 0, 10)
        Header.BackgroundColor3 = Color3.fromRGB(20, 23, 35); Header.BorderSizePixel = 0; Header.Parent = Panel
        Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)
        Title = Instance.new("TextLabel")
        Title.Size = UDim2.new(1, -50, 0, 24); Title.Position = UDim2.new(0, 14, 0, 6)
        Title.BackgroundTransparency = 1; Title.Text = "👑 VU NGUYEN KAITUN V4"
        Title.TextColor3 = Color3.fromRGB(255, 255, 255); Title.TextXAlignment = Enum.TextXAlignment.Left
        Title.Font = Enum.Font.GothamBold; Title.TextSize = 15; Title.Parent = Header
        SubTitle = Instance.new("TextLabel")
        SubTitle.Size = UDim2.new(1, -50, 0, 14); SubTitle.Position = UDim2.new(0, 14, 0, 30)
        SubTitle.BackgroundTransparency = 1; SubTitle.Text = "✦ PREMIUM"
        SubTitle.TextXAlignment = Enum.TextXAlignment.Left; SubTitle.Font = Enum.Font.GothamBold
        SubTitle.TextSize = 11; SubTitle.Parent = Header
        RegisterRGB(SubTitle, 0.1, 0.7, 1, "TextColor3")
        CloseBtn = Instance.new("TextButton")
        CloseBtn.Size = UDim2.new(0, 30, 0, 30); CloseBtn.Position = UDim2.new(1, -38, 0.5, -15)
        CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50); CloseBtn.BorderSizePixel = 0
        CloseBtn.Text = "✕"; CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        CloseBtn.Font = Enum.Font.GothamBold; CloseBtn.TextSize = 15; CloseBtn.AutoButtonColor = false; CloseBtn.Parent = Header
        Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)
        CloseBtn.MouseButton1Click:Connect(function() Panel.Visible = false end)
        Toggle.MouseButton1Click:Connect(function() Panel.Visible = not Panel.Visible end)
    end)

    safeCreate("TabBar setup", function()
        TabBar = Instance.new("Frame")
        TabBar.Size = UDim2.new(1, -20, 0, 34); TabBar.Position = UDim2.new(0, 10, 0, 70)
        TabBar.BackgroundColor3 = Color3.fromRGB(16, 18, 28); TabBar.BorderSizePixel = 0; TabBar.Parent = Panel
        Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 9)
        tabLayout = Instance.new("UIListLayout", TabBar)
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center; tabLayout.Padding = UDim.new(0, 4)
        PageHolder = Instance.new("Frame")
        PageHolder.Size = UDim2.new(1, -20, 1, -120); PageHolder.Position = UDim2.new(0, 10, 0, 112)
        PageHolder.BackgroundTransparency = 1; PageHolder.BorderSizePixel = 0; PageHolder.Parent = Panel
    end)

    -- Main page (gồm cả Net/Sync labels — UI gốc đặt chúng trên trang Main)
    safeCreate("Main page setup", function()
        local mainPage = CreatePage("Main")
        StatusValue = StatusCard(mainPage, 1)
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
        NetDiag   = LabelCard(mainPage, 7, "🌐 Net (backend)", "đang kiểm tra…")
        PlaceCard = LabelCard(mainPage, 8, "🆔 Place / Server", "…")
        SyncDbg   = LabelCard(mainPage, 9, "🔎 Sync Debug", "…")
    end)

    safeCreate("Status page setup", function()
        local statusPage = CreatePage("Status")
        for i, name in ipairs(Config.mains) do
            mainStatusLabels[name] = LabelCard(statusPage, i, "Main " .. i .. ": " .. name, "loading...")
        end
    end)

    safeCreate("Debug page setup", function()
        local debugPage = CreatePage("Debug")
        setLoop = IndicatorRow(debugPage, 1, "Loop")
        setNet  = IndicatorRow(debugPage, 2, "Net")
        setSrv  = IndicatorRow(debugPage, 3, "Server")
        setDoor = IndicatorRow(debugPage, 4, "Door")
        setMain = IndicatorRow(debugPage, 5, "Main stt1")
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
    end)

    safeCreate("Intro animation", function()
        selectTab("Main")
        Panel.Size = UDim2.new(0, 0, 0, 0)
        TweenService:Create(Panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Size = UDim2.new(0, 320, 0, 460) }):Play()
    end)

    -- update loops (mỗi loop pcall riêng + check Runtime.alive — y nguyên cadence/nội dung)
    safeCreate("UI update loop setup", function()
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.2)
                pcall(function()
                    if _G.statusnow and StatusValue then StatusValue.Text = _G.statusnow .. "\nPlaceId: " .. tostring(game.PlaceId) end
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(1)
                pcall(function() if _G.netDiag and NetDiag then NetDiag:SetDesc(_G.netDiag) end end)
                pcall(function()
                    if PlaceCard then
                        PlaceCard:SetDesc(("PlaceId: %s | Job: %s"):format(tostring(game.PlaceId), tostring(game.JobId):sub(1, 18)))
                    end
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.5)
                pcall(function()
                    if not SyncDbg then return end
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
                    if not (setLoop and setNet and setSrv and setDoor and setMain) then return end
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
                    if not logSF then return end
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
end

--[[ ============================================================================
 [32] STARTUP — init + start mọi module (chống start trùng). (File A: rải toàn file)
============================================================================ ]]
if not Runtime._started then
    Runtime._started = true
    _G[State.myName] = true

    -- cache_v4.json: ghi mốc thời gian jobid hiện tại (File A 34-44)
    TeleportManager.markVisited(game.JobId)

    -- network/role/warmer
    ServerSync.init()
    ServerSync.startWarmers()
    ServerSync.startNetProbe()

    -- world/move
    Movement.enableNoclip("return true")
    CombatActions.startSpamSkills()
    CombatActions.startFastAttack()
    CombatActions.startHakiLoop()

    -- team/sea/gates
    TeamManager.start()
    SeaManager.start()
    startGameReadyGate()

    -- ability sync (3 loop file-based) + noguchi
    AbilitySync.startLoops()
    startNoguchiLoop()

    -- UI + main loop
    UIManager.start()
    MainLoop.start()

    Logger.ok("KaitunV4 bản 2 (modular, port từ File A) khởi động xong. role=" .. tostring(State.myRole))
end
