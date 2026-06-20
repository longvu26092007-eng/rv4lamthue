-- Module giờ NHÚNG THẲNG trong script (không tải GitHub nữa) → xoá cache cũ để chắc chắn không
-- dính bản module_bf.lua lỗi (tween leak / noclip loadstring mỗi frame).
pcall(function() if isfile and isfile("kaitun_module_bf.lua") and delfile then delfile("kaitun_module_bf.lua") end end)

-- ĐỢI CLIENT LOAD XONG HẲN trước khi làm gì (quan trọng SAU KHI HOP SERVER: instance mới
-- phải load đủ mới chọn team + chạy script; nếu không sẽ "chọn được team mà script không chạy").
if not game:IsLoaded() then game.Loaded:Wait() end
-- timeout 30s: LoadingScreen kẹt / service thiếu sẽ KHÔNG treo vĩnh viễn (mọi remote sau đã qua safeInvoke)
local _bootT0 = tick()
repeat
    task.wait(0.1)
until (game:GetService("ReplicatedStorage") and game:GetService("ReplicatedStorage"):FindFirstChild("Remotes") and game.Players and game.Players.LocalPlayer and not game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen")) or (tick() - _bootT0) > 30

if workspace:GetAttribute("MAP") and workspace:GetAttribute("MAP") ~= "Sea3" then
    -- bọc thread con: InvokeServer YIELD được → tránh treo lúc load nếu server chậm
    task.spawn(function()
        pcall(function() game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TravelZou") end)
    end)
end
if not isfile("cache_v4.json") then
    writefile("cache_v4.json", "{}")
end
local B, A = pcall(function()
    return game.HttpService:JSONDecode(readfile("cache_v4.json"))
end)
if not B then
    A = {}
end
A[game.JobId] = math.floor(tick())
writefile("cache_v4.json", game.HttpService:JSONEncode(A))

if not getgenv().Config then
    getgenv().Config = {
        ["Allies"] = { game.Players.LocalPlayer.Name },
        ["Method"] = "Kill Players After Trial",
        ["MainAccount"] = { game.Players.LocalPlayer.Name },
        ["ResetAfterTrial"] = true,
        ["Team"] = "Marines",
        ["Gear"] = "A-B-B",
        ["Kick Moon"] = true,
        ["Hop Server FullMoon"] = true,
    }
end
if not getgenv().Config["Gear"] or #getgenv().Config["Gear"] ~= 5 then
    getgenv().Config["Gear"] = "A-B-B"
end

local myName = game.Players.LocalPlayer.Name
-- Mặc định SERVER LOCAL (chạy node index.js ngay trên máy này) → độ trễ ~1ms, hết lag.
-- Muốn dùng remote/LAN thì set ở executor TRƯỚC khi load: getgenv().API_URL = "http://<ip>:20425"
local BASE_URL = getgenv().API_URL or "http://127.0.0.1:20425"

-- ============================================================
-- [NET] Lớp HTTP production — chống mất dữ liệu cho 100+ account.
--   • Chọn hàm request mạnh nhất theo executor (syn/http_request/request/fluxus/krnl), fallback HttpGet cho GET.
--   • POST = hàng đợi worker (bounded concurrency) + RETRY backoff + COALESCE theo key
--     (chỉ giữ dữ liệu MỚI NHẤT mỗi loại → không tràn queue, không spam).
--   • GET = semaphore giới hạn đồng thời + retry + CACHE TTL (cắt bão request lặp).
--   • Log đầy đủ. KHÔNG bao giờ làm kẹt luồng game (POST async, GET có trần đồng thời).
-- ============================================================
local Net = {}
do
    local HS = game:GetService("HttpService")
    local httprequest = (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
        or (fluxus and fluxus.request)
        or (krnl and krnl.request)
    Net.hasReq = httprequest ~= nil

    -- ---- log vòng (giữ 200 dòng gần nhất) ----
    Net.logs = {}
    function Net.log(level, msg)
        local line = ("[NET][%s] %s"):format(level, tostring(msg))
        table.insert(Net.logs, line)
        if #Net.logs > 200 then table.remove(Net.logs, 1) end
        if level == "ERR" or level == "WARN" then warn(line) end
    end

    -- ---- 2 semaphore RIÊNG cho GET và POST ----
    -- GET đông (firesignal/status...) KHÔNG được làm nghẽn POST (heartbeat/donedoor/abilityready).
    local function makeSem(max)
        local cur = 0
        local function acquire()
            local guard = 0
            while cur >= max do
                task.wait(0.03)
                guard = guard + 1
                if guard > 400 then break end -- ~12s thì thôi chờ (đề phòng kẹt slot)
            end
            cur = cur + 1
        end
        local function release() cur = math.max(0, cur - 1) end
        return acquire, release
    end
    local acquireGet, releaseGet = makeSem(4)
    local acquirePost, releasePost = makeSem(4)

    -- ---- request thô: trả ok(bool), status(number), body(string), err ----
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
            if method ~= "GET" then
                return false, 0, nil, "executor không có hàm request cho POST"
            end
            local body
            local ok, err = pcall(function() body = game:HttpGet(url) end)
            if ok and body then return true, 200, body, nil end
            return false, 0, nil, tostring(err)
        end
    end

    -- ---- GET đồng bộ + retry + cache ----
    local cache = {} -- url -> { t, decoded, raw }
    local GET_RETRIES = 3
    function Net.getRaw(url)
        acquireGet()
        local ok, status, body, err
        for attempt = 1, GET_RETRIES do
            ok, status, body, err = rawRequest("GET", url, nil)
            if ok then break end
            Net.log("WARN", ("GET fail %d/%d %s : %s"):format(attempt, GET_RETRIES, url, tostring(err)))
            task.wait(0.2 * attempt)
        end
        releaseGet()
        if not ok then Net.log("ERR", "GET bỏ cuộc: " .. url) end
        return ok, body, status
    end

    function Net.getJSON(url, ttl)
        ttl = ttl or 0
        if ttl > 0 then
            local c = cache[url]
            if c and c.decoded ~= nil and (tick() - c.t) < ttl then return c.decoded end
        end
        local ok, body = Net.getRaw(url)
        if not ok or not body then return nil end
        local good, decoded = pcall(function() return HS:JSONDecode(body) end)
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

    -- ---- POST: hàng đợi + worker + retry + coalesce theo key ----
    local postQ = {}
    local keyed = {} -- key -> job mới nhất
    local MAX_Q = 800
    local POST_RETRIES = 6
    function Net.postJSON(url, tbl, key)
        local bodyStr
        local ok = pcall(function() bodyStr = HS:JSONEncode(tbl or {}) end)
        if not ok then Net.log("ERR", "JSON encode fail: " .. url); return end
        local job = { url = url, body = bodyStr, key = key, attempts = 0 }
        if key then
            local old = keyed[key]
            if old then old.replaced = true end -- bỏ job cũ cùng key (chỉ gửi dữ liệu mới nhất)
            keyed[key] = job
        end
        if #postQ >= MAX_Q then
            table.remove(postQ, 1)
            Net.log("WARN", "postQ tràn, bỏ job cũ nhất")
        end
        table.insert(postQ, job)
    end

    local function worker()
        while true do
            local job = table.remove(postQ, 1)
            if not job or job.replaced then
                task.wait(0.05)
            else
                acquirePost()
                local sok, status, _, err = rawRequest("POST", job.url, job.body)
                releasePost()
                if sok then
                    if job.key and keyed[job.key] == job then keyed[job.key] = nil end
                else
                    job.attempts = job.attempts + 1
                    if (not job.replaced) and job.attempts < POST_RETRIES then
                        Net.log("WARN", ("POST retry %d/%d %s : %s"):format(job.attempts, POST_RETRIES, job.url, tostring(err)))
                        task.wait(0.3 * job.attempts)
                        table.insert(postQ, job)
                    elseif not job.replaced then
                        Net.log("ERR", ("POST bỏ sau %d lần: %s"):format(job.attempts, job.url))
                        if job.key and keyed[job.key] == job then keyed[job.key] = nil end
                    end
                end
            end
        end
    end
    for _ = 1, 4 do task.spawn(worker) end

    -- mở rawRequest ra để net-probe đo GET/POST đồng bộ (single-shot) cho panel chẩn đoán
    Net.raw = rawRequest
    Net.log("INFO", "Net init — hasReq=" .. tostring(Net.hasReq))
end

local isallies = {}
if getgenv().Config and getgenv().Config["Allies"] then
    for i, v in pairs(getgenv().Config["Allies"]) do
        isallies[v] = true
    end
end

local myRole = "unknown"
local myMainIndex = nil
isaccmain = {}
local mainIndexOf = {}
local cleanAllies = {}
for _, v in ipairs(getgenv().Config["Allies"] or {}) do
    if v and v ~= "" then table.insert(cleanAllies, v) end
end
local cleanMains = {}
for _, v in ipairs(getgenv().Config["MainAccount"] or {}) do
    if v and v ~= "" then table.insert(cleanMains, v) end
end
getgenv().Config["Allies"] = cleanAllies
getgenv().Config["MainAccount"] = cleanMains

-- TĂNG TỐC: gộp identify + allmains vào 1 request /init (giảm round-trip).
-- QUAN TRỌNG: retry tới 8 lần — nếu /init lỗi mạng thì account không có role → đứng im.
do
    local allies_str = table.concat(cleanAllies, ",")
    local mains_str = table.concat(cleanMains, ",")
    local url = BASE_URL .. "/init?name=" .. myName .. "&allies=" .. allies_str .. "&mains=" .. mains_str
    local data
    for attempt = 1, 8 do
        data = Net.getJSON(url, 0)
        if data and data.role then break end
        Net.log("WARN", "/init thử lại " .. attempt .. "/8")
        wait(0.3 + 0.2 * attempt)  -- backoff nhẹ hơn → load nhanh hơn khi mạng chập chờn
    end
    if data then
        myRole = data.role or "unknown"
        if myRole == "main" then
            myMainIndex = data.index
            isaccmain[myName] = true
            mainIndexOf[myName] = myMainIndex
        end
        if data.mains then
            for _, v in ipairs(data.mains) do
                if v.name and v.name ~= "" then
                    isaccmain[v.name] = true
                    mainIndexOf[v.name] = v.index
                end
            end
        end
        Net.log("INFO", "/init OK role=" .. tostring(myRole) .. " index=" .. tostring(myMainIndex))
    else
        Net.log("ERR", "/init thất bại hoàn toàn — account sẽ retry status qua các vòng nền")
    end
end

getgenv().Config["Team"] = getgenv().Config["Team"] and (getgenv().Config["Team"] == "Marines" or getgenv().Config["Team"] == "Pirates") and getgenv().Config["Team"] or "Marines"

-- ===== STATUS CACHE: đọc read-through, TTL ngắn → cắt bão getMainStatus mỗi frame =====
statusCache = {} -- name -> { t, status }  (khai báo TRƯỚC setMyMainStatus tránh phụ thuộc thứ tự)
local STATUS_TTL = 3

-- POST mainstatus qua hàng đợi (retry). Cập nhật cache ngay để logic dùng giá trị mới.
function setMyMainStatus(statusStr)
    if not myMainIndex then return end
    statusCache[myName] = { t = tick(), status = statusStr }
    Net.postJSON(BASE_URL .. "/mainstatus?name=" .. myName, { status = statusStr }, "mainstatus")
end

-- Báo status lên server cho BẤT KỲ account nào (kể cả ALLY — không cần myMainIndex) → dashboard/đồng bộ
-- detect được "đang làm trial". Dùng cho IN-TRIAL latch của ally.
function reportStatus(statusStr)
    statusCache[myName] = { t = tick(), status = statusStr }
    Net.postJSON(BASE_URL .. "/mainstatus?name=" .. myName, { status = statusStr }, "mainstatus")
end

local function fetchMainStatusLive(accName)
    -- 1-SHOT qua Net.raw → KHÔNG qua semaphore GET (max 4) và KHÔNG retry-storm của getJSON.
    -- (Trước đây getJSON 3-retry + semaphore → hot-path block làm CẠN slot → warmer bị đói →
    --  statusCache cũ → nhận diện SAI main #1. Đây là gốc của "ally thấy Clifford=waiting".)
    if Net.raw then
        local ok, _, body = Net.raw("GET", BASE_URL .. "/mainstatus?name=" .. accName, nil)
        if ok and body then
            local good, res = pcall(function() return game:GetService("HttpService"):JSONDecode(body) end)
            if good and res and res["data"] and res["data"]["status"] then return res["data"]["status"] end
        end
        return nil
    end
    local res = Net.getJSON(BASE_URL .. "/mainstatus?name=" .. accName, 0)
    if res and res["data"] and res["data"]["status"] then return res["data"]["status"] end
    return nil
end
-- HOT-PATH AN TOÀN: KHÔNG fetch đồng bộ ở đây nữa. game:HttpGet / request YIELD luồng gọi;
-- nếu backend chậm / executor KHÔNG tới được api → vòng chính KẸT NGAY TẠI getMainStatus,
-- TRƯỚC cả status() đầu tiên → panel đứng mãi ở "Đang khởi động...". Giờ chỉ đọc statusCache
-- (đã được warmer nền + setMyMainStatus cập nhật liên tục). Cache rỗng → "waiting".
function getMainStatus(accName)
    local c = statusCache[accName]
    if c then return c.status end
    return "waiting"
end

-- Cờ "còn sống": tắt khi account rời game → mọi vòng nền tự dừng, không gửi nữa.
local ALIVE = true

-- Heartbeat: báo server account còn sống (qua hàng đợi, coalesce).
function sendHeartbeat()
    if not ALIVE then return end
    Net.postJSON(BASE_URL .. "/heartbeat?name=" .. myName, { role = myRole }, "heartbeat")
end

-- Báo server account OUT → server xoá NGAY (không chờ prune 30s).
-- Gửi cả POST (qua queue) lẫn GET đồng bộ (chắc tới được trong lúc teardown,
-- vì queue/worker có thể chưa kịp flush khi instance bị huỷ).
local offlineSent = false
function sendOffline()
    if offlineSent then return end
    offlineSent = true
    ALIVE = false
    pcall(function() Net.postJSON(BASE_URL .. "/offline?name=" .. myName, { role = myRole }, "offline") end)
    pcall(function() Net.getRaw(BASE_URL .. "/offline?name=" .. myName) end)
end

-- Vòng nền gửi heartbeat mỗi 5s (server prune ngưỡng 30s → chịu được vài lần rớt)
spawn(function()
    while ALIVE do
        sendHeartbeat()
        for _ = 1, 5 do
            if not ALIVE then break end
            wait(1)
        end
    end
end)

-- ============================================================
-- [NET PROBE] Chẩn đoán mạng TỪ TRONG EXECUTOR → hiện thẳng lên panel.
--   • req=true/false : executor có hàm request không (POST cần cái này).
--   • GET  OK/FAIL <ms> : gọi GET /timeserver có tới backend không + độ trễ.
--   • POST OK/FAIL <ms> : gọi POST /heartbeat (đúng cái dùng đồng bộ) có tới không.
-- Nếu req=false hoặc POST FAIL → server thấy online:0 = bot KHÔNG đồng bộ được.
-- ============================================================
_G.netDiag = "NET: đang kiểm tra…"
spawn(function()
    local HS = game:GetService("HttpService")
    while true do
        pcall(function()
            if not Net.raw then _G.netDiag = "NET: thiếu Net.raw"; return end
            local g0 = tick()
            local gok = Net.raw("GET", BASE_URL .. "/timeserver", nil)
            local gms = math.floor((tick() - g0) * 1000)
            local pok, pms = nil, 0
            if Net.hasReq then
                local p0 = tick()
                pok = Net.raw("POST", BASE_URL .. "/heartbeat?name=" .. myName, HS:JSONEncode({ role = myRole }))
                pms = math.floor((tick() - p0) * 1000)
            end
            _G.netGetOk = gok and true or false
            _G.netPostOk = Net.hasReq and (pok and true or false) or nil
            _G.netDiag = ("req=%s | GET %s %dms | POST %s"):format(
                tostring(Net.hasReq),
                gok and "OK" or "FAIL", gms,
                Net.hasReq and ((pok and "OK " or "FAIL ") .. pms .. "ms") or "N/A (thiếu request)")
        end)
        wait(5)
    end
end)

-- Phát hiện account RỜI GAME THẬT → báo offline. QUAN TRỌNG: ĐỔI SERVER (hop fullmoon/
-- teleport) KHÔNG tính offline — báo offline lúc hop sẽ xoá account khỏi stt1 làm LỆCH đồng bộ.
-- Hop chỉ teleport rồi join lại, heartbeat tiếp tục ở server mới (<30s); rớt thật thì prune lo.
local teleporting = false
do
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    -- đánh dấu đang teleport (hop server) → chặn offline trong lúc này
    pcall(function()
        LP.OnTeleport:Connect(function(state)
            if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
                teleporting = true
            elseif state == Enum.TeleportState.Failed or state == Enum.TeleportState.Cancelled then
                teleporting = false   -- hop hỏng → cho phép offline nếu sau đó rời thật
            end
        end)
    end)
    -- chính mình rời server (quit thật) — BỎ QUA nếu đang teleport (hop)
    Players.PlayerRemoving:Connect(function(plr)
        if plr == LP and not teleporting then sendOffline() end
    end)
    -- đóng instance (đóng tab/kill) — cũng bỏ qua nếu đang teleport
    pcall(function() game:BindToClose(function()
        if not teleporting then sendOffline() end
    end) end)
end

-- mainJobCache: name -> { jobid, time, t } — jobid của main do warmer đọc nền → isSameServerAsMain
-- đọc CACHE (không gọi mạng, không block vòng chính).
mainJobCache = mainJobCache or {}
local function fetchJobLive(accName)
    if Net.raw then
        local ok, _, body = Net.raw("GET", BASE_URL .. "/noguchi?name=" .. accName, nil)
        if ok and body then
            local good, res = pcall(function() return game:GetService("HttpService"):JSONDecode(body) end)
            if good and res and res["data"] and res["data"]["jobid"] then
                return res["data"]["jobid"], res["data"]["time"] or 0
            end
        end
    end
    return nil
end

-- ===== NGUỒN CHỐT THỨ TỰ MAIN do SERVER trả (web là trọng tài) =====
-- Trả: order (mảng tên main đã xếp), current (tên main stt1). MỌI account đọc cái này → đồng nhất,
-- hết cảnh mỗi con tự tính getMainOrder cục bộ ra stt1 khác nhau ("detect main linh tinh").
local function fetchCurMainLive()
    if Net.raw then
        local ok, _, body = Net.raw("GET", BASE_URL .. "/curmain", nil)
        if ok and body then
            local good, res = pcall(function() return game:GetService("HttpService"):JSONDecode(body) end)
            if good and res and type(res.order) == "table" then
                return res   -- nguyên bảng: order, current, current_jobid, current_time, mains[]
            end
        end
    end
    return nil
end

-- Warmer: CHỈ 1 request /curmain mỗi ~0.7s → lấy order (web chốt) + status MỌI main + jobid main stt1.
-- KHÔNG còn fetch status từng main (trước đây N main = N request/con/vòng → 100 main = bùng request).
-- Giờ tải PHẲNG: 1 request/con/vòng bất kể 2 hay 100 main. getMainStatus/isSameServerAsMain đọc cache.
spawn(function()
    while true do
        pcall(function()
            local data = fetchCurMainLive()
            if data and type(data.order) == "table" then
                _G.srvMainOrder = data.order
                _G.srvCurMain = data.current
                -- nóng statusCache cho TẤT CẢ main từ 1 response (TRỪ chính mình — self do
                -- setMyMainStatus quản lý cục bộ, không để server cũ ghi đè gây nhấp nháy rotation).
                if type(data.mains) == "table" then
                    for _, m in ipairs(data.mains) do
                        if m.name and m.name ~= myName then
                            statusCache[m.name] = { t = tick(), status = m.status or "waiting" }
                        end
                    end
                end
                -- jobid main stt1 (ally cần để biết hop đi đâu) — đã kèm trong /curmain, khỏi gọi riêng
                local curr = data.current
                if curr and curr ~= myName and data.current_jobid and data.current_jobid ~= "" then
                    mainJobCache[curr] = { jobid = data.current_jobid, time = data.current_time or 0, t = tick() }
                end
            end
        end)
        wait(0.7)
    end
end)

-- FIX: Join team bền — retry cả 2 cách (remote + ChooseTeam UI) tới khi có team thật.
-- Trước đây chỉ gọi 1 lần nên "lúc được lúc không" (remote chưa sẵn / UI chưa load kịp).
spawn(function()
    local LP = game:GetService("Players").LocalPlayer
    local team = getgenv().Config["Team"]
    if team ~= "Marines" and team ~= "Pirates" then team = "Marines" end
    local attempts = 0
    while not LP.Team and attempts < 40 do
        attempts = attempts + 1
        -- Cách 1: gọi thẳng remote SetTeam
        pcall(function()
            game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("SetTeam", team)
        end)
        task.wait(0.4)
        if LP.Team then break end
        -- Cách 2: fallback qua ChooseTeam UI (getgc) khi remote không ăn
        pcall(function()
            local chooseGui = LP.PlayerGui:FindFirstChild("ChooseTeam", true)
            local uiCtrl    = LP.PlayerGui:FindFirstChild("UIController", true)
            if chooseGui and chooseGui.Visible and uiCtrl then
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
end)

local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
-- ============================================================
-- [SAFE INVOKE] Gọi RemoteFunction KHÔNG để treo luồng. InvokeServer tới RemoteFunction
-- YIELD luồng gọi tới khi server trả lời — nếu handler server-side treo (account vừa
-- join / đang load, Data chưa sẵn) thì luồng KẸT VĨNH VIỄN. pcall KHÔNG cứu được (chỉ
-- bắt error, không bắt yield). Đây là nguyên nhân treo "Đang khởi động".
-- safeInvoke chạy InvokeServer trong thread con, chờ tối đa `timeout`s → loop luôn đi tiếp.
-- Trả: ok(bool), r1, r2, ...  (hết giờ → ok=false).
-- ============================================================
local function _resolveCommF()
    local rs = game:GetService("ReplicatedStorage")
    local rem = rs:FindFirstChild("Remotes") or rs:WaitForChild("Remotes", 10)
    return rem and (rem:FindFirstChild("CommF_") or rem:WaitForChild("CommF_", 10)) or nil
end
local _CommF = _resolveCommF()
local function safeInvoke(timeout, ...)
    if not _CommF then _CommF = _resolveCommF() end
    if not _CommF then return false end
    local args = table.pack(...)
    local done, packed = false, nil
    task.spawn(function()
        packed = table.pack(pcall(function()
            return _CommF:InvokeServer(table.unpack(args, 1, args.n))
        end))
        done = true
    end)
    local t0 = tick()
    while not done and (tick() - t0) < timeout do task.wait() end
    if not done or not packed then return false end
    return table.unpack(packed, 1, packed.n)
end
-- ============================================================
-- [MODULE] Bản module_bf NHÚNG THẲNG (không tải GitHub) — đã FIX:
--   • topos: HỦY tween cũ trước khi tạo mới (hết chồng tween + memory leak + giật),
--     clamp duration 0.05–4s (không bao giờ tween 300s = kẹt), nil-safe (không WaitForChild vô hạn).
--   • noclip: compile loadstring 1 LẦN (không mỗi frame = hết tốn CPU), single-instance,
--     nil-safe lúc respawn, chỉ set CanCollide part còn true.
--   • eq/haki/getdis: nil-guard Character/Backpack/HRP.
-- ============================================================
local module
do
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local TweenS = game:GetService("TweenService")
    module = {}

    local function getHRP()
        local c = LP.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    function module:eq()
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

    function module:haki()
        local char = LP.Character
        if char and not char:FindFirstChild("HasBuso") then
            pcall(function()
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("Buso")
            end)
        end
    end

    -- topos: hủy tween cũ + clamp + nil-safe
    local _activeTween
    function module:topos(targetCFrame, v36)
        if typeof(targetCFrame) ~= "CFrame" then return end
        local hrp = getHRP()
        if not hrp then return end                                  -- respawn → bỏ qua, KHÔNG hang
        if not v36 then pcall(function() LP.Character.Humanoid.Sit = false end) end
        if _activeTween then pcall(function() _activeTween:Cancel(); _activeTween:Destroy() end); _activeTween = nil end
        local dist = (hrp.Position - targetCFrame.Position).Magnitude
        local dur = math.clamp(dist / 200, 0.05, 600)               -- 200 studs/s LUÔN cố định (cap 600s, gần như KHÔNG BAO GIỜ chạm) → không tăng tốc/giật ngược dù xa bao nhiêu
        local tw = TweenS:Create(hrp,
            TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
            { CFrame = targetCFrame })
        _activeTween = tw
        tw.Completed:Once(function() if _activeTween == tw then _activeTween = nil end; pcall(function() tw:Destroy() end) end)
        tw:Play()
        return tw
    end

    function module:join(v2)
        v2 = (v2 == "Marines" or v2 == "Pirates") and v2 or "Marines"
        for _, v in pairs(LP.PlayerGui:GetChildren()) do
            if v:FindFirstChild("ChooseTeam") then
                local b = v.ChooseTeam.Container:FindFirstChild(v2)
                b = b and b:FindFirstChild("Frame"); b = b and b:FindFirstChild("TextButton")
                if b then pcall(function() firesignal(b.Activated) end) end
            end
        end
    end

    function module:tele(v)
        pcall(function()
            game:GetService("ReplicatedStorage"):WaitForChild("__ServerBrowser"):InvokeServer("teleport", v or game.JobId)
        end)
    end

    -- noclip: compile 1 lần + single-instance + nil-safe
    local _noclipOn = false
    function module:noclip(v)
        if _noclipOn then return end
        _noclipOn = true
        local okC, fn = pcall(loadstring, v)
        local cond = (okC and type(fn) == "function") and fn or function() return true end
        task.spawn(function()
            while true do
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

    function module:getdis(x, y)
        if typeof(x) ~= "CFrame" then return math.huge end
        if not y then
            local hrp = getHRP()
            if not hrp then return math.huge end
            y = hrp.CFrame
        end
        return (x.Position - y.Position).Magnitude
    end

    -- anti-AFK
    pcall(function()
        LP.Idled:Connect(function()
            local vu = game:GetService("VirtualUser")
            vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(1)
            vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        end)
    end)
end
local topofgreattree = CFrame.new(3035.15137, 2281.15918, -7325.19189, 0.0284484141, 2.19495124e-08, 0.999595284,
    -3.29094476e-08, 1, -2.10217994e-08, -0.999595284, -3.22980895e-08, 0.0284484141)

local _doorCache = {}
function getdoor(vv)
    vv = vv or game:GetService("Players").LocalPlayer.Data.Race.Value
    -- CACHE: tìm được Entrance 1 lần thì NHỚ → chống streaming chớp nil (đang đứng ở cửa mà
    -- FindFirstChild lỡ trả nil → "ở cửa vẫn ghi false"). Cache hết hiệu lực khi part bị huỷ.
    local cached = _doorCache[vv]
    if cached and cached.Parent then return cached end
    -- FIX: không dùng WaitForChild (treo vô hạn nếu corridor chưa load) → FindFirstChild an toàn
    local temple = workspace.Map:FindFirstChild("Temple of Time")
    if not temple then return nil end
    local corridor = temple:FindFirstChild(vv .. "Corridor")
    if not corridor then return nil end
    local door = corridor:FindFirstChild("Door")
    if not door then return nil end
    local entrance = door:FindFirstChild("Entrance")
    if entrance then _doorCache[vv] = entrance end
    return entrance
end

function getdis(...)
    return module:getdis(...)
end

local topos = function(v)
    pcall(function()
        if getdis(v) > 2500 and getdis(CFrame.new(28310.0234, 14895.1123, 109.456741, -0.469690144, -2.85620132e-08, -0.882831335, -3.23509219e-08, 1, -1.51411736e-08, 0.882831335, 2.14487486e-08, -0.469690144)) < 1500 then
            game.Players.LocalPlayer.Character.Humanoid.Health = 0
        end
    end)
    return module:topos(v)
end

local TEMPLE_ENTRY = Vector3.new(28310.0234, 14895.1123, 109.456741)
-- Lên đứng ở cửa trial. Tách 2 trường hợp cho hết "đứng im / detect door lỗi":
--   • CHƯA ở temple → requestEntrance NHƯNG throttle 5s (gọi mỗi frame sẽ restart teleport
--     liên tục → đứng im rất lâu mới vào được).
--   • ĐÃ ở temple mà getdoor() chớp nil → CHỜ cửa load (retry 3s), KHÔNG re-teleport
--     (re-teleport khi cửa chưa load chính là "lỗi detect door"), rồi bám sát cửa.
function goToMyDoor()
    -- XA temple (vd vừa chết/reset, respawn ở spawn) → requestEntrance lên Temple of Time NHƯ LÚC
    -- MỚI VÀO GAME. KHÔNG topos bay từ xa (giật giật + lỗi nil lúc char đang respawn). Throttle 4s.
    if getdis(CFrame.new(28310.0234, 14895.1123, 109.456741)) >= 3000 then
        if not _G.lastReqEntrance or (tick() - _G.lastReqEntrance) > 4 then
            _G.lastReqEntrance = tick()
            pcall(function()
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", TEMPLE_ENTRY)
            end)
        end
        return false
    end
    -- ĐÃ ở temple: topos tới cửa MỖI tick (noclip BẬT → đứng yên sẽ rơi xuyên sàn; topos lại mỗi
    -- ~0.35s giữ char trong tầm AT_DOOR_DIST, không rơi xa). KHÔNG hard-set liên tục để không cản
    -- teleport khi ActivateAbility mở trial. Nil-safe (đang respawn → bỏ qua).
    local door = getdoor()
    if not door then return false end
    local char = game.Players.LocalPlayer.Character
    if not (char and char:FindFirstChild("HumanoidRootPart")) then return false end
    pcall(function() topos(door.CFrame) end)
    return getdis(door.CFrame) <= 150
end

-- ============================================================
-- TEMPLE OF TIME — AN TOÀN, CHỐNG ĐƠ/CRASH.
-- Trước đây: reparent CẢ MODEL "Temple of Time" từ MapStash vào Map MỖI 0.35s + đọc thô
-- workspace.Map["Temple of Time"].FFABorder.Forcefield.Transparency. Reparent model lớn
-- client-side lặp liên tục = ĐƠ/CRASH (nặng hơn khi nhiều account 1 máy); đọc thô = ném lỗi
-- nếu game đổi cấu trúc. Sửa: THROTTLE reparent 5s + pcall, đọc forcefield bằng FindFirstChild.
-- Trả: "loading" (chưa vào Map) | "ffup" (forcefield đóng → khúc kill-player) | "ffdown" (mở → vào trial).
-- ============================================================
function templeState()
    local temple = workspace.Map:FindFirstChild("Temple of Time")
    if not temple then
        if not _G.lastTempleReparent or (tick() - _G.lastTempleReparent) > 5 then
            _G.lastTempleReparent = tick()
            pcall(function()
                local stash = game:GetService("ReplicatedStorage"):FindFirstChild("MapStash")
                local m = stash and stash:FindFirstChild("Temple of Time")
                if m then m.Parent = workspace.Map end
            end)
        end
        return "loading"
    end
    local ff
    pcall(function()
        local border = temple:FindFirstChild("FFABorder")
        local field = border and border:FindFirstChild("Forcefield")
        if field then ff = field.Transparency end
    end)
    if ff == 0 then return "ffup" end
    return "ffdown"
end

local pos_plr_trial = {
    CFrame.new(28692.3477, 14887.5605, -53.7669983, 0.707131445, -0, -0.707082093, 0, 1, -0, 0.707082093, 0, 0.707131445),
    CFrame.new(28782.7246, 14898.9902, -59.6069946, 0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, 0.707134247),
    CFrame.new(28700.875, 14888.2598, -154.110992, -1, 0, 0, 0, 1, 0, 0, 0, -1),
    CFrame.new(28795.7715, 14888.2598, -112.917999, -0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, -0.707134247),
    CFrame.new(28658.4551, 14888.2598, -121.372009, -0.515037298, 0, -0.857167721, 0, 1, 0, 0.857167721, 0, -0.515037298),
    CFrame.new(28742.4688, 14887.5596, -18.2120056, 0.92051065, 0, 0.390717506, 0, 1, 0, -0.390717506, 0, 0.92051065)
}

local race_abilities = {
    ["Human"] = "Last Resort",
    ["Mink"] = "Agility",
    ["Fishman"] = "Water Body",
    ["Skypiea"] = "Heavenly Blood",
    ["Ghoul"] = "Heightened Senses",
    ["Cyborg"] = "Energy Core",
    ["Draco"] = "Primordial Reign"
}
-- FIX: KHÔNG dựng sẵn bằng WaitForChild (không timeout → treo VĨNH VIỄN lúc load nếu
-- location chưa stream). Lazy getter + cache, dùng FindFirstChild → trả nil khi chưa load
-- (mọi nơi dùng đã nil-guard sẵn → vòng sau tự lấy lại).
local RACE_TRIAL_NAME = {
    ["Human"] = "Trial of Strength", ["Mink"] = "Trial of Speed", ["Fishman"] = "Trial of Water",
    ["Skypiea"] = "Trial of the King", ["Ghoul"] = "Trial of Carnage",
    ["Cyborg"] = "Trial of the Machine", ["Draco"] = "Trial of Flames",
}
local _raceTrialCache = {}
local function getRaceTrialPlace(race)
    local c = _raceTrialCache[race]
    if c and c.Parent then return c end
    local wo = workspace:FindFirstChild("_WorldOrigin")
    local loc = wo and wo:FindFirstChild("Locations")
    local nm = RACE_TRIAL_NAME[race]
    local p = (loc and nm) and loc:FindFirstChild(nm) or nil
    if p then _raceTrialCache[race] = p end
    return p
end

-- ============================================================
-- [TRIAL] Làm trial theo từng tộc — ƯU TIÊN kkv4 (Ceiling/Floor + loop Enemies/SeaBeasts),
-- sửa bug đối chiếu bản decompiled 1.txt/3.txt (KHÔNG dùng Banana lỗi thời):
--   • Skypiea: bay tới part "snowisland_Cylinder.081" (điểm HOÀN THÀNH), không phải FinishPart.
--   • Human/Ghoul: CẦM MELEE lên → bay tới boss → đánh + kill (Health=0 + SimulationRadius).
--   • Teleport bằng module:topos THÔ (tránh wrapper topos() tự kill khi target xa & gần temple).
-- Dùng chung cho cả nhánh MAIN lẫn ALLY.
function doTrialForMyRace()
    local LP = game.Players.LocalPlayer
    local myrace = LP.Data.Race.Value
    local race_trial_place = getRaceTrialPlace(myrace)
    local function tp(cf) pcall(function() module:topos(cf) end) end  -- teleport thô (không tự kill)
    -- BAY TỪ TỪ tới cf (tween mượt). KaitunV4 KHÔNG có Tween2/BKP → tự dựng bằng TweenService.
    -- module:noclip(return true) đã bật sẵn nên xuyên vật cản khi bay.
    local function flyTo(cf)
        pcall(function()
            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local dist = (cf.Position - hrp.Position).Magnitude
            local dur = math.clamp(dist / 200, 0.05, 600)  -- 200 studs/s LUÔN cố định (cap 600s) → không tăng tốc/giật ngược dù xa bao nhiêu
            local tw = game:GetService("TweenService"):Create(
                hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = cf })
            tw:Play(); wait(dur); pcall(function() tw:Destroy() end)  -- destroy → hết leak
        end)
    end
    local function equipMelee()  -- cầm vũ khí Melee (fallback: Sword/Blox Fruit/Gun)
        pcall(function()
            local char = LP.Character
            if not (char and char:FindFirstChild("Humanoid")) then return end
            local melee, anyw
            for _, t in pairs(LP.Backpack:GetChildren()) do
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

    if myrace == "Mink" then
        -- Rabbit: tele tới "StartPoint" (+10). Delay 2s sau khi vừa vào (game kịp khởi tạo),
        -- rồi GIỮ ở StartPoint LIÊN TỤC ~4s (mọi nguồn tween mỗi frame; tp 1 phát/0.35s sẽ trôi
        -- khỏi điểm → trial KHÔNG hoàn thành).
        if tick() - (_G.minkLastTrial or 0) > 3 then wait(2) end
        _G.minkLastTrial = tick()
        local sp = _G.minkStartPoint
        if not (sp and sp.Parent) then   -- cache: chỉ quét workspace khi chưa có/đã mất part
            sp = nil
            pcall(function()
                for _, obj in pairs(workspace:GetDescendants()) do
                    if obj.Name == "StartPoint" then sp = obj break end
                end
            end)
            _G.minkStartPoint = sp
        end
        if sp then
            -- ĐỨNG NGAY TRÊN điểm (bỏ offset +10 vì trước đó lơ lửng cao quá → không nhận).
            local t0 = tick()
            repeat wait(); pcall(function() module:topos(sp.CFrame * CFrame.new(0, 2, 0)) end)
            until (tick() - t0) > 4
        end
    elseif myrace == "Skypiea" then
        -- tới part "snowisland_Cylinder.081" (8/8 nguồn), fallback FinishPart (kkv4).
        -- Đứng im 10-15s ở trên trời = path workspace.Map.SkyTrial chưa đúng dù part đã load.
        -- → tìm theo path trước (nhanh), KHÔNG thấy thì tìm RỘNG toàn workspace để bắt part ngay.
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
            local c = _G.skyFinish   -- cache: tránh quét toàn workspace mỗi tick
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
        elseif race_trial_place then flyTo(race_trial_place.CFrame) end  -- chưa load → bay vào khu trial cho stream part
    elseif myrace == "Cyborg" then
        pcall(function() tp(workspace.Map.CyborgTrial.Floor.CFrame * CFrame.new(0, 500, 0)) end)
    elseif myrace == "Human" or myrace == "Ghoul" then
        for _, v in pairs(workspace.Enemies:GetChildren()) do
            local hum = v:FindFirstChild("Humanoid")
            local hrp = v:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health > 0 and (not race_trial_place or getdis(hrp.CFrame, race_trial_place.CFrame) < 1500) then
                local t0 = tick()
                repeat wait()
                    equipMelee()                                     -- FIX: cầm melee lên trước
                    module:eq(); module:haki()
                    tp(hrp.CFrame * CFrame.new(0, 30, 0))            -- bay tới boss
                    pcall(function() sethiddenproperty(LP, "SimulationRadius", math.huge) end)
                    pcall(function() hrp.CanCollide = false; hum.Health = 0 end)  -- kill chắc ăn
                until (not v.Parent) or (not v:FindFirstChild("Humanoid")) or v.Humanoid.Health <= 0 or (tick() - t0) > 20  -- timeout chống đứng im
            end
        end
    elseif myrace == "Fishman" then
        for _, v in pairs(workspace.SeaBeasts:GetChildren()) do
            pcall(function()
                if v:FindFirstChild('Health') and v.Health.Value > 0 and v:FindFirstChild("HumanoidRootPart")
                    and (not race_trial_place or getdis(v.HumanoidRootPart.CFrame, race_trial_place) < 1500) then
                    local t0 = tick()
                    repeat wait()
                        if not LP.Backpack:FindFirstChild("Sharkman Karate") then
                            safeInvoke(3, "BuySharkmanKarate")
                        end
                        tp(v.HumanoidRootPart.CFrame * CFrame.new(0, 500, 0))
                        _G.SHOULDSPAMSKILLS = true
                    until (not v.Parent) or (not v:FindFirstChild('Health')) or v.Health.Value <= 0 or (not v:FindFirstChild("HumanoidRootPart")) or (tick() - t0) > 25  -- timeout
                    _G.SHOULDSPAMSKILLS = false
                end
            end)
        end
    end
end

-- Gộp dispatch "đang trong khu trial → làm trial; chưa → lên cửa đợi" dùng chung MAIN & ALLY
-- (trước đây 2 nhánh copy-paste, sửa lệch dễ sinh bug). isMain: set status in_trail cho main.
function runTrialPhase(roleName, isMain)
    local race_trial_place = getRaceTrialPlace(game.Players.LocalPlayer.Data.Race.Value)
    if race_trial_place and getdis(race_trial_place.CFrame) < 1500 then
        if isMain then
            local st = getMainStatus(myName)
            if st ~= "in_trail" and st ~= "training" then setMyMainStatus("in_trail") end
        end
        status(roleName .. " Doing trial")
        doTrialForMyRace()
    else
        status(roleName .. " Ready for trialing (đợi đồng bộ ability)")
        goToMyDoor()  -- file ABILITY SYNC lo ghi check + bấm đúng starttime
    end
end

function isnight()
    local c = game.Lighting.ClockTime
    if c >= 16 or c < 5 then return true end
    return false
end

function isfullmoon()
    return game:GetService("Lighting"):GetAttribute("MoonPhase") == 5
end

if module then module:noclip([[return true]]) end

function getmob1(pos)
    local allmobs = {}
    for i, v in pairs(workspace.Enemies:GetChildren()) do
        if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and getdis(v.HumanoidRootPart.CFrame, pos) < 1000 then
            table.insert(allmobs, v)
        end
    end
    return allmobs
end

function checkmob_(v)
    return v and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0
end

function noideaforname(v)
    if isallies[v.Name] then return false end
    return true
end

function getplayers()
    local plrs = {}
    for i, v in pairs(game.Players:GetPlayers()) do
        if v ~= game.Players.LocalPlayer and v.Character and not isaccmain[v.Name] and noideaforname(v) then
            if v.Character:FindFirstChild("Humanoid") and v.Character:FindFirstChild("HumanoidRootPart") and v.Character.Humanoid.Health > 0 then
                for _, pos in pairs(pos_plr_trial) do
                    if getdis(v.Character.HumanoidRootPart.CFrame, pos) < 10 then
                        plrs[v.Character] = true
                    end
                end
            end
        end
    end
    return plrs
end
function countplayers()
    local c = 0
    for _ in pairs(getplayers()) do c = c + 1 end
    return c
end

-- 1 nhịp đánh player trong trial: topos quanh target. Offset random đổi mỗi 0.3s (không mỗi
-- frame) → hết giật, bám target lâu hơn nên kill nhanh hơn. Nil-safe.
local _atkOff, _atkT = CFrame.new(0, 3, 0), 0
function attackTick(target)
    if tick() - _atkT > 0.3 then
        _atkT = tick()
        local x, z = math.random(1, 4), math.random(1, 4)
        if math.random(1, 2) == 1 then x = -x end
        if math.random(1, 2) == 1 then z = -z end
        _atkOff = CFrame.new(x, 3, z)
    end
    local hrp = target and target:FindFirstChild("HumanoidRootPart")
    if hrp then pcall(function() topos(hrp.CFrame * _atkOff) end) end
end
function checkbackpack(v)
    local LP = game.Players.LocalPlayer
    return (LP.Backpack and LP.Backpack:FindFirstChild(v)) or (LP.Character and LP.Character:FindFirstChild(v))
end

function trialable()
    if not game.Players.LocalPlayer.Character:FindFirstChild("RaceTransformed") then
        -- vẫn hỏi UpgradeRace Check để bắt DONE (i==5) dù chưa transform → tránh con full gear
        -- bị tưởng "tới lượt train/trial".
        local okI, i5 = safeInvoke(3, "UpgradeRace", "Check")
        _G.lastRaceI = okI and i5 or "?"   -- debug: hiện i hiện tại
        if okI and (i5 == 5 or i5 == 8) then return false, "done" end   -- 5/8 = FULL GEAR
        local abcxyz = checkbackpack(race_abilities[game:GetService("Players").LocalPlayer.Data.Race.Value])
        if abcxyz then return true end
        return false
    end
    local ok, i, d, f = safeInvoke(3, "UpgradeRace", "Check")
    if not ok then _G.lastRaceI = "?"; return false end   -- remote treo/timeout → coi như chưa sẵn sàng
    _G.lastRaceI = i   -- debug: hiện i hiện tại
    -- FULL GEAR = i==5 (Full Update) HOẶC i==8 (full gear + còn training sessions) → DONE.
    if i == 5 or i == 8 then
        return false, "done"
    elseif i == 6 then
        return false, d - 2
    elseif i == 1 or i == 3 then
        return false
    elseif i == 2 or i == 4 or i == 7 then
        if f then
            local totalfragments = tonumber(f)
            if game:GetService("Players").LocalPlayer.Data.Fragments.Value >= totalfragments then
                safeInvoke(3, "UpgradeRace", "Buy")
            else
                return false, "raiding"
            end
        end
        return false, f
    elseif i == 0 then
        return true, d   -- Ready For Trial
    else
        return false
    end
end

-- Cache trialable() — bản gốc gọi UpgradeRace Check (+ có thể Buy) qua InvokeServer 3 lần/giây.
-- TTL 1.5s: vẫn đủ nhạy cho chuyển trạng thái, giảm mạnh round-trip server (×100 account).
local _trCache = { t = -1e9, ab = nil, AB = nil }
function cachedTrialable()
    if (tick() - _trCache.t) < 1.5 then return _trCache.ab, _trCache.AB end
    local ab, AB = trialable()
    _trCache.t, _trCache.ab, _trCache.AB = tick(), ab, AB
    return ab, AB
end

-- ============================================================
-- [DEBUG LOG] Ring buffer 200 dòng + CHỐNG SPAM: cùng key trong 15s thì BỎ (không ghi lại).
--   DBG(msg, level, key): level "ok"=xanh / "err"=đỏ / "info"=xám. key gộp spam (mặc định = msg).
--   → status() đổi mỗi 0.35s nhưng mỗi nội dung chỉ vào log 1 lần / 15s.
--   Thứ tần suất cao (loop/net/door/server) KHÔNG vào log — hiện bằng ĐÈN xanh/đỏ ở tab Debug.
-- ============================================================
_G.dbgLog = _G.dbgLog or {}
_G.dbgSeq = _G.dbgSeq or 0
local _dbgLastKey = {}
local DBG_MAX, DBG_SPAM_TTL = 200, 15
function DBG(msg, level, key)
    key = key or tostring(msg)
    local t = tick()
    if _dbgLastKey[key] and (t - _dbgLastKey[key]) < DBG_SPAM_TTL then return end  -- spam <15s → bỏ
    _dbgLastKey[key] = t
    _G.dbgSeq = _G.dbgSeq + 1
    local hm = "--:--:--"
    pcall(function()
        local base = (serverNow and serverNow()) or (os and os.time and os.time()) or t
        local s = math.floor(base + 7 * 3600) % 86400   -- giờ Hà Nội
        hm = string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
    end)
    _G.dbgLog[#_G.dbgLog + 1] = { seq = _G.dbgSeq, text = "[" .. hm .. "] " .. tostring(msg), level = level or "info" }
    while #_G.dbgLog > DBG_MAX do table.remove(_G.dbgLog, 1) end
end

function status(v)
    -- DEBUG: luôn kèm [i=X] (giá trị UpgradeRace Check mới nhất) để xem trạng thái race thực tế
    _G.statusnow = tostring(v)
        .. ((_G.lastRaceI ~= nil) and ("  [i=" .. tostring(_G.lastRaceI) .. "]") or "")
        .. ((_G.lastDoorDist ~= nil) and ("  [d=" .. tostring(math.floor(_G.lastDoorDist)) .. (_G.lastDoorSrc or "?") .. (_G.lastSameSrv and "/same" or "/diff") .. "]") or "")
    -- đẩy vào Debug log (gộp spam theo nội dung gốc v, 15s/lần)
    local sv = tostring(v)
    local lvl = "info"
    if sv:find("Lỗi") or sv:find("⚠") or sv:find("FAIL") or sv:find("Died") then lvl = "err"
    elseif sv:find("Doing trial") or sv:find("DONE") or sv:find("Ready") or sv:find("Kill Players") then lvl = "ok" end
    DBG(sv, lvl, sv)
end

-- ============================================================
-- HÀNG ĐỢI ĐỘNG theo "stt":
--   1) main đang trial (moon/in_trail) → đầu hàng
--   2) main đang chờ (waiting/"")       → theo thứ tự config
--   3) main đã xong (done/training)     → đẩy XUỐNG CUỐI
-- order[1] = main đang ở "stt1" (tới lượt trial). Khi main stt1 chuyển done/training
-- nó tự xuống cuối → main kế lên stt1; main sau lại tụt 1 bậc (Main3 → Main2...).
-- ============================================================
function getMainOrder()
    -- ƯU TIÊN order do SERVER chốt (đồng nhất MỌI account → hết "detect main linh tinh").
    -- Chưa lấy được (mới load, warmer chưa chạy) → tính cục bộ TẠM cho khỏi nil.
    if _G.srvMainOrder and #_G.srvMainOrder > 0 then return _G.srvMainOrder end
    local mains = getgenv().Config["MainAccount"] or {}
    local active, waiting, finished = {}, {}, {}
    for _, name in ipairs(mains) do
        local st = getMainStatus(name)
        if st == "offline" then
            -- main KHÔNG online (server trả "offline") → BỎ QUA, không tính vào hàng đợi.
            -- = "bỏ dữ liệu con main vừa xong": con đã xong/rời sẽ KHÔNG còn bị thấy "waiting" = #1
            --   chặn rotation → Main kế tự lên #1.
        elseif st == "moon" or st == "in_trail" then
            active[#active + 1] = name
        elseif st == "done" or st == "training" then
            finished[#finished + 1] = name
        else -- "waiting" / ""
            waiting[#waiting + 1] = name
        end
    end
    local order = {}
    for _, n in ipairs(active) do order[#order + 1] = n end
    for _, n in ipairs(waiting) do order[#order + 1] = n end
    for _, n in ipairs(finished) do order[#order + 1] = n end
    return order
end

-- stt ĐỘNG (1-based) của 1 main trong hàng đợi; nil nếu không phải main.
function mainSttOf(name)
    for i, v in ipairs(getMainOrder()) do
        if v == name then return i end
    end
    return nil
end

-- Main đang ở "stt1" (tới lượt được trial). Trả (name, 1).
function getCurrentMainBeingUpgraded()
    -- main stt1 do SERVER chốt; chưa có → suy từ getMainOrder (đã ưu tiên server bên trong)
    if _G.srvCurMain then return _G.srvCurMain, 1 end
    local order = getMainOrder()
    if #order == 0 then return nil, nil end
    return order[1], 1
end

-- Đọc jobid của main hiện tại → trả (cùng_server?, jobid_của_main).
-- Dùng cho nhánh ally quyết định: cùng server thì ra cửa, khác server thì hop.
function isSameServerAsMain(mainName)
    if not mainName then return false, nil end
    -- CACHE-ONLY: đọc mainJobCache (warmer nền cập nhật mỗi ~0.7s). KHÔNG gọi mạng → KHÔNG block
    -- vòng chính (trước đây 3×retry + getJSON-retry = block tới ~vài giây → STALL + không hop).
    local c = mainJobCache and mainJobCache[mainName]
    if not c or not c.jobid then return false, nil end
    local fresh = (gettimeserver() - (c.time or 0)) < 60
    local same = fresh and (c.jobid == game.JobId)
    return same, c.jobid
end

function checkgear()
    local _okcg, dt = safeInvoke(3, "TempleClock", "Check")
    if dt then
        if dt.HadPoint then
            local g1, g2, g3 = getgenv().Config["Gear"]:match("^(.-)%-(.-)%-(.-)$")
            local a23 = { [2] = g1, [3] = g2, [4] = g3 }
            local a24 = { ["A"] = "Alpha", ["B"] = "Omega" }
            local lvl = dt.RaceDetails.Completed
            local choosegear = (lvl == 1 or lvl == 5) and "Blank" or a24[a23[lvl]]
            local a = dt.RaceDetails.A
            local b = dt.RaceDetails.B
            if a >= 2 then
                safeInvoke(3, "TempleClock", "SpendPoint", "Gear" .. tostring(dt.Completed), "Omega")
            elseif b >= 2 then
                safeInvoke(3, "TempleClock", "SpendPoint", "Gear" .. tostring(dt.Completed), "Alpha")
            else
                safeInvoke(3, "TempleClock", "SpendPoint", "Gear" .. tostring(dt.RaceDetails.Completed), choosegear)
            end
        end
    end
end

TweenObject = function(Object, Pos, Speed)
    if Speed == nil then Speed = 350 end
    if not (Object and Object.Parent) then return end                 -- nil-guard mob đã despawn
    local Distance = (Pos.Position - Object.Position).Magnitude
    local dur = math.clamp(Distance / Speed, 0.03, 3)                 -- clamp: không tween quá dài
    local tw = game:GetService("TweenService"):Create(
        Object, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = Pos })
    tw.Completed:Once(function() pcall(function() tw:Destroy() end) end) -- destroy → hết leak
    tw:Play()
end
GetMobPosition = function(EnemiesName)
    local pos = Vector3.new(0, 0, 0)
    local count = 0
    for r, v in pairs(workspace.Enemies:GetChildren()) do
        if v.Name == EnemiesName and v:FindFirstChild("HumanoidRootPart") then
            if not pos then
                pos = v.HumanoidRootPart.Position
            else
                pos = pos + v.HumanoidRootPart.Position
            end
            count = count + 1
        end
    end
    if count > 0 then return pos / count end
    return nil
end
BringMob = function()
    local plr = game:GetService("Players").LocalPlayer
    local myHrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    if not myHrp then return end   -- nil-guard: đang respawn → bỏ qua tick này
    local ememe = game.Workspace.Enemies:GetChildren()
    if #ememe > 0 then
        local totalpos = {}
        for i, v in pairs(ememe) do
            if not totalpos[v.Name] then
                totalpos[v.Name] = GetMobPosition(v.Name)
            end
        end
        for i, v in pairs(workspace.Enemies:GetChildren()) do
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
                                sethiddenproperty(plr, "SimulationRadius", math.huge)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- "Đã mở cửa đền" là điều kiện nền tảng & ỔN ĐỊNH theo account → CHECK 1 LẦN rồi GHI FILE
-- riêng theo account (<myName>_kaitunv4.json: {templedoor=true}). Lần sau (kể cả reload/rejoin)
-- ĐỌC FILE, KHÔNG gọi remote nữa → hết phụ thuộc reply game-server cho gate này (hết treo + load nhanh).
local TEMPLE_DOOR_FILE = myName .. "_kaitunv4.json"
local function readTempleDoor()
    if _G.templeDoorOK then return true end                     -- cache RAM (phiên này)
    -- cache FILE: đã từng xác nhận true → dùng luôn, bỏ qua remote
    local fok, fdata = pcall(function() return game.HttpService:JSONDecode(readfile(TEMPLE_DOOR_FILE)) end)
    if fok and type(fdata) == "table" and fdata.templedoor == true then
        _G.templeDoorOK = true
        return true
    end
    -- chưa true → gọi remote 1 LẦN (có timeout, không treo); true thì ghi file + nhớ vĩnh viễn
    local ok, res = safeInvoke(3, "CheckTempleDoor")
    if ok and res then
        _G.templeDoorOK = true
        pcall(function() writefile(TEMPLE_DOOR_FILE, game.HttpService:JSONEncode({ templedoor = true })) end)
        return true
    end
    return res  -- nil/false → vòng sau tự thử lại tới khi true (rồi mới ghi file & dừng hẳn)
end
-- ============================================================
-- GATE SẴN SÀNG: chờ TEAM + NHÂN VẬT + DATA load xong rồi mới chạy logic chính.
-- Cần sau khi HOP SERVER: nếu chạy logic khi nhân vật/Data chưa load → lỗi / "không chạy".
-- Heartbeat + choose-team + /init ở TRÊN đã chạy rồi nên account KHÔNG bị rớt khi chờ.
-- Có timeout 45s (best-effort) để không treo vĩnh viễn; vòng lặp chính đã bọc pcall nên an toàn.
-- ============================================================
-- CHẠY NỀN (task.spawn) → KHÔNG block luồng chính tới đoạn TẠO UI. Trước đây GATE block tới 45s
-- (nhất là khi team/char/data load chậm hoặc backend chậm) làm "UI mãi mới lên". Vòng lặp chính đã
-- nil-guard + pcall nên chạy sớm vài nhịp lúc char/data chưa load cũng AN TOÀN (chỉ phí vài tick).
task.spawn(function()
    local LP = game:GetService("Players").LocalPlayer
    local t0 = tick()
    repeat
        task.wait(0.2)
        local c = LP.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local ready = LP.Team
            and c and c:FindFirstChild("HumanoidRootPart")
            and hum and hum.Health > 0
            and LP:FindFirstChild("Data") and LP.Data:FindFirstChild("Race")
        if ready then break end
    until (tick() - t0) > 45
    _G.gameReady = true
    Net.log("INFO", ("Game ready gate: team=%s char=%s data=%s elapsed=%.1fs"):format(
        tostring(LP.Team ~= nil),
        tostring(LP.Character ~= nil),
        tostring(LP:FindFirstChild("Data") ~= nil),
        tick() - t0))
end)

local checktempledoor = readTempleDoor()
_G.ShouldSendData = false
local issobusy = false
spawn(function()
    -- THROTTLE: trước đây `while wait()` ~mỗi frame → getCurrentMainBeingUpgraded gọi HTTP
    -- nhiều lần/frame → bão request → executor rate-limit → rớt dữ liệu. Giờ chạy 0.35s/vòng,
    -- getMainStatus đọc statusCache (warmer nền) nên gần như không còn request trong vòng này.
    while wait(0.35) do
        -- HEARTBEAT: chứng minh vòng chính SỐNG ngay nhịp đầu → thay chữ "Đang khởi động..." liền.
        -- Trước đây status() đầu tiên nằm SAU các call mạng đồng bộ; nếu mạng kẹt thì panel đứng
        -- mãi ở splash dù coroutine vẫn chạy. Set 1 lần để KHÔNG nhấp nháy với status thật.
        _G.loopTick = (_G.loopTick or 0) + 1
        _G.loopLastT = tick()
        if not _G.firstLoopHit then _G.firstLoopHit = true; status("Vòng chính đã chạy — đang đồng bộ…") end
        -- gate có thể trả nil/false lúc load → đọc lại (đã cache RAM/file: true rồi sẽ thôi gọi remote)
        if not checktempledoor then checktempledoor = readTempleDoor() end
        -- BỌC PCALL: 1 dòng lỗi (vd trialable/InvokeServer khi game update remote) sẽ KHÔNG
        -- giết coroutine nữa → không còn kẹt im "Đang khởi động"; lỗi hiện thẳng ra status.
        local _okLoop, _errLoop = pcall(function()
            if not checktempledoor then
                status("Chờ mở cửa đền (CheckTempleDoor=" .. tostring(checktempledoor) .. ")")
                return
            end
            _G.ShouldSendData = false
            local ab, AB = cachedTrialable()
            local currentmain, currentidx = getCurrentMainBeingUpgraded()
            local myStt = mainSttOf(myName) or myMainIndex   -- stt ĐỘNG để hiển thị
            local myStatus = ""
            if isaccmain[myName] then
                myStatus = getMainStatus(myName)
            end
            if isaccmain[myName] then
                if AB == "done" then
                    -- DONE chỉ khi i==5/8 HIỆN TẠI. KHÔNG nhớ vĩnh viễn (đổi tộc → V3 i=? thì hết done).
                    if myStatus ~= "done" then setMyMainStatus("done"); myStatus = "done" end
                else
                    -- Không còn done (đổi tộc/V3/đang tiến hành) → bỏ status done về waiting để chạy lại
                    if myStatus == "done" then setMyMainStatus("waiting"); myStatus = "waiting" end
                    if (myStatus == "in_trail" or myStatus == "moon") and not ab then
                        status("[MAIN " .. myStt .. "] Trial completed, switching to training!")
                        setMyMainStatus("training")
                        myStatus = "training"
                    end
                end
                if myStatus == "in_trail" and ab then
                    local in_temple = getdis(CFrame.new(28310.0234, 14895.1123, 109.456741)) < 3000
                    if not in_temple then
                        status("[MAIN " .. myStt .. "] Died in trial, retrying...")
                        setMyMainStatus("waiting")
                        myStatus = "waiting"
                    end
                end
            end

            -- ===== IN-TRIAL LATCH =====
            -- Đã VÀO khu trial (ability sync đẩy vào) + bản thân CÒN cần trial (ab) → CHỐT in_trial:
            -- DỪNG mọi điều phối (hop / chờ main / kill-player), CHỈ làm trial. Áp cho CẢ Main lẫn Ally.
            -- → Khi main đổi trạng thái giữa chừng, ally/main KHÔNG rớt về "Waiting" → 3 con cùng làm
            --   trial tới khi xong, KHÔNG đứng im. Tự nhả khi trial xong (ab=false) hoặc rời khu trial.
            local _tplace = getRaceTrialPlace(game.Players.LocalPlayer.Data.Race.Value)
            -- CHỈ latch khi cửa trial ĐANG MỞ (ffdown/loading). Vào khúc KILL-PLAYER (ffup) thì NHẢ latch
            -- → ally thoát ra để TỰ RESET. Trước đây ab còn true + đứng gần trial → latch giữ mãi "doing
            -- trial" suốt ffup, KHÔNG bao giờ tới nhánh auto-reset (đếm 3 phút không reset là do đây).
            local _inTrialNow = (_tplace and ab and getdis(_tplace.CFrame) < 1500 and templeState() ~= "ffup") and true or false
            if _inTrialNow then
                if isaccmain[myName] then
                    if myStatus ~= "in_trail" then setMyMainStatus("in_trail"); myStatus = "in_trail" end
                elseif not _G.inTrial then
                    reportStatus("in_trail")          -- ally: báo 1 lần lúc vừa bước vào trial
                end
                _G.inTrial = true
                status((isaccmain[myName] and ("[MAIN " .. tostring(myStt) .. "]") or "[ALLY]") .. " 🔥 IN-TRIAL → đang làm trial")
                doTrialForMyRace()
                return
            else
                if _G.inTrial and not isaccmain[myName] then reportStatus("ally") end  -- vừa RỜI trial → trả status ally
                _G.inTrial = false
            end

            if isaccmain[myName] and myStatus == "done" then
                status("[MAIN " .. myStt .. "] ✅ DONE YOUR RACE - FULL GEAR (Gear2/3/4)!")
            elseif isaccmain[myName] and myStatus == "training" then
                status("[MAIN " .. myStt .. "] Training (parallel)")
                if not ab then
                    setMyMainStatus("training")   -- CHỐT chắc status training (chống dashboard dính moon/in_trail cũ)
                    if AB == "raiding" then
                        local boss = workspace.Enemies:FindFirstChild("Cake Prince") or workspace.Enemies:FindFirstChild("Dough King")
                        if boss then
                            status("[MAIN " .. myStt .. "] Raiding for fragment")
                            repeat wait()
                                pcall(function() topos(boss.HumanoidRootPart.CFrame * CFrame.new(0, 25, 0)) end)
                                module:eq(); module:haki(); BringMob()
                            until not checkmob_(boss)
                        end
                    else
                        local LP  = game:GetService("Players").LocalPlayer
                        local VIM = game:GetService("VirtualInputManager")
                        local function pressV4()  -- bấm Y biến hình V4 khi RaceEnergy đầy (nil-safe)
                            pcall(function()
                                local c = LP.Character
                                if c and c:FindFirstChild("RaceEnergy") and c.RaceEnergy.Value == 1 then
                                    VIM:SendKeyEvent(true, "Y", false, game)
                                    VIM:SendKeyEvent(false, "Y", false, game)
                                end
                            end)
                        end
                        pressV4()
                        local pos__ = CFrame.new(214.688675, 126.626984, -12600.2236, -0.180400655, -1.09679892e-08, 0.983593225, 1.94620693e-08, 1, 1.47204746e-08, -0.983593225, 2.17983427e-08, -0.180400655)
                        if getdis(pos__) < 1500 then
                            for _, v in ipairs(getmob1(pos__)) do
                                local lastY, lastTf, lastTrainPost = 0, nil, 0
                                repeat
                                    local c  = LP.Character
                                    local tf = (c and c:FindFirstChild("RaceTransformed") and c.RaceTransformed.Value) or false
                                    if tf then
                                        -- ===== ĐANG V4 → CHỈ CHỜ HẾT V4: NGẮT vòng nặng cho đỡ hao tài nguyên =====
                                        -- KHÔNG eq/haki/BringMob/topos mỗi frame; đứng cao 1 lần rồi nghỉ dài.
                                        if lastTf ~= true then
                                            local hrp = v:FindFirstChild("HumanoidRootPart")
                                            if hrp then pcall(function() topos(hrp.CFrame * CFrame.new(0, 150, 0)) end) end
                                            status("[MAIN " .. myStt .. "] Training (Wait for end V4)")
                                            lastTf = true
                                        end
                                        -- re-assert "training" mỗi 4s → dashboard LUÔN là training (không dính moon)
                                        if (tick() - lastTrainPost) > 4 then setMyMainStatus("training"); lastTrainPost = tick() end
                                        wait(0.5)   -- nghỉ dài: chỉ chờ V4 hết, không làm gì nặng
                                    else
                                        -- ===== CHƯA V4 → áp sát + kill nạp energy =====
                                        module:eq(); module:haki(); BringMob()
                                        local hrp = v:FindFirstChild("HumanoidRootPart")
                                        if hrp then pcall(function() topos(hrp.CFrame * CFrame.new(0, 20, 0)) end) end
                                        if lastTf ~= false then
                                            status("[MAIN " .. myStt .. "] Training (Kill Mobs)")
                                            lastTf = false
                                        end
                                        if (tick() - lastY > 0.4) then lastY = tick(); pressV4() end
                                        wait()
                                    end
                                until not checkmob_(v)
                            end
                        else
                            topos(pos__)
                        end
                    end
                else
                    -- TRAINING XONG (sẵn sàng trial) → về WAITING để vào hàng đợi (MỌI main, không chỉ stt1).
                    -- Thứ tự xoay theo INDEX (config) nên con nào xong train trước cũng KHÔNG cắt hàng —
                    -- main đúng lượt vẫn lên stt1. Để "training" lại = kẹt cuối hàng dù ĐÃ sẵn sàng.
                    if myStatus ~= "waiting" then setMyMainStatus("waiting") end
                    status("[MAIN " .. myStt .. "] Training done → waiting (chờ tới lượt)")
                end
            elseif isaccmain[myName] and currentmain == myName then
                status("[MAIN " .. myStt .. "] My turn to upgrade gear!")
                if myStatus == "waiting" or myStatus == "" then
                    setMyMainStatus("moon")
                end
                -- FIX #1: `continue` không tồn tại trong Lua 5.1 → dùng goto + label ::skip_turn::
                local skip = false
                if getgenv().Config["Hop Server FullMoon"] then
                    local isInFullmoonServer = isfullmoon()
                    if not isInFullmoonServer or not isnight() then
                        local hopped = false
                        pcall(function()
                            local cachedJobs = {}
                            local okCache, cacheData = pcall(function() return game.HttpService:JSONDecode(readfile("cache_v4.json")) end)
                            if okCache and cacheData then cachedJobs = cacheData end
                            local thua = Net.getJSON("http://fi11.bot-hosting.net:20758/api/name=fullmoon", 5)
                            if thua and thua["success"] and thua["data"] then
                                for _, v in pairs(thua["data"]) do
                                    local jobid = v["jobid"]
                                    if jobid and jobid ~= game.JobId and v.player <= 8 then
                                        local lastVisit = cachedJobs[jobid]
                                        if not lastVisit or (math.floor(tick()) - lastVisit) > 3600 then
                                            status("[MAIN " .. myStt .. "] Hop fullmoon server")
                                            game:GetService("ReplicatedStorage"):WaitForChild("__ServerBrowser"):InvokeServer("teleport", jobid)
                                            hopped = true
                                            break
                                        end
                                    end
                                end
                            end
                        end)
                        if hopped then
                            wait(10)
                            Net.postJSON(BASE_URL .. "/noguchi?name=" .. myName, { jobid = game.JobId }, "noguchi")
                            skip = true
                        end
                    end
                end
                if not skip then
                    spawn(checkgear)
                    _G.ShouldSendData = true
                    local ts = templeState()
                    if ts == "loading" then
                        status("[MAIN " .. myStt .. "] Đang vào Temple of Time...")
                    elseif ts == "ffup" then
                        -- CHỈ kill player KHI ĐÃ qua in_trial (myStatus=="in_trail") → đúng khúc FFA CỦA MÌNH.
                        -- Chưa in_trial (còn moon/đang chờ ở cửa) → KHÔNG bay ra kill (người khác có thể đang
                        -- trial → mình bay ra kill sẽ bị KICK); chỉ bám cửa chờ ability mở trial.
                        if myStatus == "in_trail" then
                            status("[MAIN " .. myStt .. "] Kill Players After Trial")
                            for plr in pairs(getplayers()) do
                                if plr then
                                    repeat wait() attackTick(plr)
                                    until not plr or not plr.Parent or not plr:FindFirstChild("Humanoid") or not plr:FindFirstChild("HumanoidRootPart") or plr.Humanoid.Health <= 0 or templeState() ~= "ffup"
                                end
                            end
                        else
                            status("[MAIN " .. myStt .. "] Chờ ở cửa (chưa in_trial → KHÔNG kill)")
                            goToMyDoor()
                        end
                    else
                        runTrialPhase("[MAIN " .. myStt .. "]", true)
                    end
                end
            elseif isaccmain[myName] then
                -- MAIN CHƯA TỚI LƯỢT: nếu CÒN TRAIN ĐƯỢC (chưa sẵn sàng trial) → TRAIN SONG SONG luôn
                -- (đỡ phí thời gian chờ; training KHÔNG cần fullmoon). Đã sẵn sàng (ab=true) → WAITING chờ
                -- tới lượt lên stt1 (hop fullmoon + làm trial vẫn CHỈ khi tới lượt stt1).
                _G.allyKillReset = false
                if (not ab) and AB ~= "done" then
                    if myStatus ~= "training" then setMyMainStatus("training") end
                    status("[MAIN " .. myStt .. "] Training song song (chưa tới lượt)")
                else
                    if myStatus == "training" then setMyMainStatus("waiting") end
                    status("[MAIN " .. myStt .. "] Waiting for current main: " .. tostring(currentmain))
                end
            else
                -- CHỈ ALLY THẬT vào đây: liên tục detect jobid của main stt1 → join + help.
                local roleName = "[ALLY]"
                -- set status TRƯỚC các call mạng bên dưới (fetchMainStatusLive / isSameServerAsMain
                -- vẫn YIELD); nếu mạng kẹt thì panel hiện dòng này thay vì đứng "Đang khởi động...".
                status(roleName .. " Đang dò main đang tới lượt…")
                -- "Nhận lệnh lên trial door" = phát hiện main đang up (moon/in_trail). Làm như join
                -- jobid: nếu cache miss/chưa active thì FETCH TƯƠI retry 2 lần → đỡ trễ/đứng chờ oan.
                -- TẤT CẢ đọc CACHE (warmer nền giữ tươi ~0.7s) → KHÔNG gọi mạng, KHÔNG block, hết STALL.
                local mainActive = false
                if currentmain then
                    local st = getMainStatus(currentmain)                  -- cache-only
                    mainActive = (st == "moon" or st == "in_trail")
                    status(roleName .. " main " .. tostring(currentmain) .. " = " .. tostring(st))
                end
                -- Main phụ (main-as-ally) KHÔNG hop theo (giữ như bản gốc); chỉ ally thật mới hop.
                local sameServer, mainJob = true, nil
                if not isaccmain[myName] then
                    sameServer, mainJob = isSameServerAsMain(currentmain)   -- cache-only (mainJobCache)
                end
                if currentmain and mainActive and not sameServer then
                    -- Khác server với main đang up → hop sang server của main (throttle 5s tránh spam)
                    _G.allyKillReset = false  -- rời khúc kill-player → cho reset lại ở trial sau
                    status(roleName .. " Hop sang server main: " .. tostring(currentmain))
                    if mainJob and mainJob ~= "" and mainJob ~= game.JobId then
                        if not _G.lastAllyHop or (tick() - _G.lastAllyHop) > 5 then
                            _G.lastAllyHop = tick()
                            pcall(function()
                                game:GetService("ReplicatedStorage"):WaitForChild("__ServerBrowser"):InvokeServer("teleport", mainJob)
                            end)
                        end
                    end
                -- B: cùng server + main moon/in_trail → RA CỬA NGAY (bỏ chặn fullmoon/Timer). VIP/fullmoon/busy vẫn cho qua.
                elseif (currentmain and mainActive and sameServer) or getgenv().Config["VIPServer"] or (isnight() and isfullmoon()) or issobusy then
                        spawn(checkgear)
                        _G.ShouldSendData = true
                        local ts = templeState()
                        if ts == "loading" then
                            status(roleName .. " Đang vào Temple of Time...")
                        elseif ts == "ffup" then
                            if not isaccmain[myName] then
                                -- ===== ALLY: AUTO RESET NGAY khi vào khúc kill player =====
                                -- Ally KHÔNG cần kill hết người — reset luôn (stagger theo thứ tự ally)
                                -- để đồng bộ + báo /helpreset cho main. _G.allyKillReset chống reset lặp.
                                status(roleName .. " Kill-player → AUTO RESET (ally)")
                                -- reset 1 LẦN cho mỗi khúc kill-player. KHÔNG tự clear theo timer
                                -- (trước đây clear sau 5s → chết lặp = "đứng khá lâu" + chặn hop sang
                                -- server main mới). Flag chỉ clear khi đã rời khúc này (hop/trial/waiting).
                                if not _G.allyKillReset then
                                    _G.allyKillReset = true
                                    spawn(function()
                                        local delay = 2
                                        for i, name in ipairs(getgenv().Config["Allies"] or {}) do
                                            if name == myName then delay = i * 2 break end
                                        end
                                        wait(delay)
                                        pcall(function() game.Players.LocalPlayer.Character.Humanoid.Health = 0 end)
                                        wait(1)
                                        Net.postJSON(BASE_URL .. "/helpreset", { name = myName }, "helpreset")
                                    end)
                                end
                            else
                                status(roleName .. " Kill Players After Trial")
                                for plr in pairs(getplayers()) do
                                    if plr then
                                        repeat wait() attackTick(plr)
                                        until not plr or not plr.Parent or not plr:FindFirstChild("Humanoid") or not plr:FindFirstChild("HumanoidRootPart") or plr.Humanoid.Health <= 0 or templeState() ~= "ffup"
                                    end
                                end
                                if countplayers() <= 0 then
                                    local isCurrentMain = isaccmain[myName] and myName == currentmain
                                    local isOtherMain = isaccmain[myName] and myName ~= currentmain  -- acc main phụ
                                    if isCurrentMain then
                                        local allies_str = table.concat(getgenv().Config["Allies"] or {}, ",")
                                        if allies_str ~= "" then
                                            status("[MAIN " .. myStt .. "] Waiting for help accs to reset first...")
                                            local timeout = 0
                                            repeat
                                                wait(1)
                                                timeout = timeout + 1
                                                local res = Net.getJSON(BASE_URL .. "/helpreset?allies=" .. allies_str, 0)
                                                if res and res.all_done then break end
                                            until timeout >= 25
                                        end
                                        game.Players.LocalPlayer.Character.Humanoid.Health = 0
                                        wait(3)
                                        setMyMainStatus("training")
                                        Net.postJSON(BASE_URL .. "/helpreset/clear", {}, "helpreset_clear")
                                    elseif isOtherMain then
                                        spawn(function()
                                            local delay = (#(getgenv().Config["Allies"] or {}) * 2) + 4 + math.random(0, 3)
                                            wait(delay)
                                            game.Players.LocalPlayer.Character.Humanoid.Health = 0
                                            wait(1)
                                            Net.postJSON(BASE_URL .. "/helpreset", { name = myName }, "helpreset")
                                        end)
                                    end
                                end
                            end
                        else
                            _G.allyKillReset = false  -- Forcefield đã đóng (qua trial mới) → reset lại được
                            runTrialPhase(roleName, false)
                        end
                else
                    _G.allyKillReset = false  -- chờ main → cho reset lại ở trial sau
                    status(roleName .. " Waiting for current main: " .. tostring(currentmain))
                end
            end
        end)
        if not _okLoop then
            status("⚠ Lỗi vòng chính: " .. tostring(_errLoop))
            Net.log("ERR", "main loop crash: " .. tostring(_errLoop))
        end
    end
end)

local fruits = {
    ['Buddha-Buddha'] = true,
    ['T-Rex-T-Rex'] = true,
    ['Dragon-Dragon'] = true,
    ['Yeti-Yeti'] = true,
    ['Leopard-Leopard'] = true,
    ['Venom-Venom'] = true,
    ['Phoenix-Phoenix'] = true,
    ['Kitsune-Kitsune'] = true,
    ['Mammoth-Mammoth'] = true,
    ['Gas-Gas'] = true,
    ["Portal-Portal"] = true,
}
local isvalidtooltip = { ["Melee"] = true, ["Blox Fruit"] = true, ["Sword"] = true, ["Gun"] = true }
local isvalidnameui = { ["Z"] = true, ["X"] = true, ["C"] = true, ["V"] = true, ["F"] = true }

function getallweapon()
    local weapon = {}
    for i, v in pairs(game.Players.LocalPlayer.Backpack:GetChildren()) do
        if v:IsA("Tool") and isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
    end
    for i, v in pairs(game.Players.LocalPlayer.Character:GetChildren()) do
        if v:IsA("Tool") and isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
    end
    return weapon
end

function EquipTool(v)
    local thua = game.Players.LocalPlayer.Backpack:FindFirstChild(v)
    if thua then game.Players.LocalPlayer.Character.Humanoid:EquipTool(thua) end
end

spawn(function()
    while wait() do
        if _G.SHOULDSPAMSKILLS then
            local weapon = getallweapon()
            for i, v in pairs(weapon) do
                if not game:GetService("Players").LocalPlayer.PlayerGui.Main.Skills:FindFirstChild(v.Name) then
                    EquipTool(v.Name)
                end
            end
            for i, v in pairs(weapon) do
                if v.Parent ~= game.Players.LocalPlayer.Character then EquipTool(v.Name) end
                local ui_ = game:GetService("Players").LocalPlayer.PlayerGui.Main.Skills:FindFirstChild(v.Name)
                if ui_ then
                    for _, vl in pairs(ui_:GetChildren()) do
                        if isvalidnameui[vl.Name] then
                            local cooldown_frame = vl:WaitForChild("Cooldown", 3)
                            local title_frame = vl:WaitForChild("Title", 3)
                            if cooldown_frame and title_frame and (title_frame.TextColor3 == Color3.new(1, 1, 1) or title_frame.TextColor3 == Color3.fromRGB(255, 255, 255)) then
                                if cooldown_frame.Size == UDim2.new(0, 0, 1, -1) then
                                    if vl.Name == "V" then
                                        if not fruits[ui_.Name] then
                                            game:service('VirtualInputManager'):SendKeyEvent(true, "V", false, game)
                                            wait(0.1)
                                            game:service('VirtualInputManager'):SendKeyEvent(false, "V", false, game)
                                            wait(1.5)
                                        end
                                    else
                                        game:service('VirtualInputManager'):SendKeyEvent(true, vl.Name, false, game)
                                        wait(0.1)
                                        game:service('VirtualInputManager'):SendKeyEvent(false, vl.Name, false, game)
                                        wait(1.5)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

local Ec = game["Players"]["LocalPlayer"]
local function Bc(x)
    if not x then return false end
    local L = x:FindFirstChild("Humanoid")
    return L and L["Health"] > 0
end
local function Pc(x, L)
    local V = (game:GetService("Players")):GetPlayers()
    local H = {}
    local r = (x:GetPivot())["Position"]
    for x, a in ipairs(V) do
        if a ~= Ec and not isaccmain[a.Name] and a["Character"] and noideaforname(a) then
            local x = a["Character"]:FindFirstChild("HumanoidRootPart")
            if x and Bc(a["Character"]) then
                local V = (x["Position"] - r)["Magnitude"]
                if V <= L then table["insert"](H, a["Character"]) end
            end
        end
    end
    for x, a in ipairs((game:GetService("Workspace"))["Enemies"]:GetChildren()) do
        local x = a:FindFirstChild("HumanoidRootPart")
        if x and Bc(a) then
            local V = (x["Position"] - r)["Magnitude"]
            if V <= L then table["insert"](H, a) end
        end
    end
    return H
end
function AttackNoCoolDown()
    local x = (game:GetService("Players"))["LocalPlayer"]
    local L = x["Character"]
    if not L then return end
    local a = nil
    for x, L in ipairs(L:GetChildren()) do
        if L:IsA("Tool") then
            a = L; break
        end
    end
    if not a then return end
    local V = Pc(L, 60)
    if #V == 0 then return end
    local H = game:GetService("ReplicatedStorage")
    local r = H:FindFirstChild("Modules")
    if not r then return end
    local R = ((H:WaitForChild("Modules")):WaitForChild("Net")):WaitForChild("RE/RegisterAttack")
    local y = ((H:WaitForChild("Modules")):WaitForChild("Net")):WaitForChild("RE/RegisterHit")
    if not R or not y then return end
    local l, M = {}, nil
    for x, L in ipairs(V) do
        if not L:GetAttribute("IsBoat") then
            local x = { "RightLowerArm", "RightUpperArm", "LeftLowerArm", "LeftUpperArm", "RightHand", "LeftHand" }
            local a = L:FindFirstChild(x[math["random"](#x)]) or L["PrimaryPart"]
            if a then
                table["insert"](l, { L, a }); M = a
            end
        end
    end
    if not M then return end
    R:FireServer(0)
    local n = x:FindFirstChild("PlayerScripts")
    if not n then return end
    local b = n:FindFirstChildOfClass("LocalScript")
    while not b do
        n["ChildAdded"]:Wait(); b = n:FindFirstChildOfClass("LocalScript")
    end
    local Z
    if getsenv then
        local x, L = pcall(getsenv, b)
        if x and L then Z = L["_G"]["SendHitsToServer"] end
    end
    local q, I = pcall(function()
        return (require(r["Flags"]))["COMBAT_REMOTE_THREAD"] or false
    end)
    if q and (I and Z) then
        Z(M, l)
    elseif q and not I then
        y:FireServer(M, l)
    end
end

CameraShakerR = require(game["ReplicatedStorage"]["Util"]["CameraShaker"])
CameraShakerR:Stop()
_G.FastAttack = true

if _G.FastAttack then
    local _ENV = (getgenv or getrenv or getfenv)()
    local function SafeWaitForChild(parent, childName)
        local success, result = pcall(function() return parent:WaitForChild(childName) end)
        if not success or not result then warn("noooooo: " .. childName) end
        return result
    end
    local function WaitChilds(path, ...)
        local last = path
        for _, child in { ... } do
            last = last:FindFirstChild(child) or SafeWaitForChild(last, child)
            if not last then break end
        end
        return last
    end
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Players = game:GetService("Players")
    local Player = Players.LocalPlayer
    if not Player then
        warn("Không tìm thấy người chơi cục bộ.")
        return
    end
    local Remotes = SafeWaitForChild(ReplicatedStorage, "Remotes")
    if not Remotes then return end
    local Modules = SafeWaitForChild(ReplicatedStorage, "Modules")
    local Net = SafeWaitForChild(Modules, "Net")
    local sethiddenproperty = sethiddenproperty or function(...) return ... end
    local Settings = { AutoClick = true, ClickDelay = 0 }
    local Module = {}
    Module.FastAttack = (function()
        if _ENV.rz_FastAttack then return _ENV.rz_FastAttack end
        local FastAttack = { Distance = 100, attackMobs = true, attackPlayers = true, Equipped = nil }
        local RegisterAttack = SafeWaitForChild(Net, "RE/RegisterAttack")
        local RegisterHit = SafeWaitForChild(Net, "RE/RegisterHit")
        local function IsAlive(character)
            return character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0
        end
        local function ProcessEnemies(OthersEnemies, Folder)
            local BasePart = nil
            for _, Enemy in Folder:GetChildren() do
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
            local Part1 = ProcessEnemies(OthersEnemies, game:GetService("Workspace").Enemies)
            local Part2 = ProcessEnemies(OthersEnemies, game:GetService("Workspace").Characters)
            local character = Player.Character
            if not character then return end
            local equippedWeapon = character:FindFirstChildOfClass("Tool")
            if equippedWeapon and equippedWeapon:FindFirstChild("LeftClickRemote") then
                for _, enemyData in ipairs(OthersEnemies) do
                    local enemy = enemyData[1]
                    local direction = (enemy.HumanoidRootPart.Position - character:GetPivot().Position).Unit
                    pcall(function() equippedWeapon.LeftClickRemote:FireServer(direction, 1) end)
                end
            elseif #OthersEnemies > 0 then
                self:Attack(Part1 or Part2, OthersEnemies)
            else
                task.wait(0)
            end
        end

        function FastAttack:BladeHits()
            local Equipped = IsAlive(Player.Character) and Player.Character:FindFirstChildOfClass("Tool")
            if Equipped and Equipped.ToolTip ~= "Gun" then
                self:AttackNearest()
            else
                task.wait(0)
            end
        end

        task.spawn(function()
            while task.wait(Settings.ClickDelay) do
                if Settings.AutoClick then FastAttack:BladeHits() end
            end
        end)
        _ENV.rz_FastAttack = FastAttack
        return FastAttack
    end)()
end

local remote, idremote
for _, v in next, ({ game.ReplicatedStorage.Util, game.ReplicatedStorage.Common, game.ReplicatedStorage.Remotes,
    game.ReplicatedStorage.Assets, game.ReplicatedStorage.FX }) do
    for _, n in next, v:GetChildren() do
        if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remote, idremote = n, n:GetAttribute("Id") end
    end
    v.ChildAdded:Connect(function(n)
        if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remote, idremote = n, n:GetAttribute("Id") end
    end)
end
task.spawn(function()
    while task.wait(0.05) do
        local char = game.Players.LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local parts = {}
        for _, x in ipairs({ workspace.Enemies, workspace.Characters }) do
            for _, v in ipairs(x and x:GetChildren() or {}) do
                local hrp = v:FindFirstChild("HumanoidRootPart")
                local hum = v:FindFirstChild("Humanoid")
                if v ~= char and hrp and hum and hum.Health > 0 and (hrp.Position - root.Position).Magnitude <= 60 then
                    for _, _v in ipairs(v:GetChildren()) do
                        if _v:IsA("BasePart") and (hrp.Position - root.Position).Magnitude <= 60 then
                            parts[#parts + 1] = { v, _v }
                        end
                    end
                end
            end
        end
        local tool = char:FindFirstChildOfClass("Tool")
        if #parts > 0 and tool and
            (tool:GetAttribute("WeaponType") == "Melee" or tool:GetAttribute("WeaponType") == "Sword") then
            pcall(function()
                require(game.ReplicatedStorage.Modules.Net):RemoteEvent("RegisterHit", true)
                game.ReplicatedStorage.Modules.Net["RE/RegisterAttack"]:FireServer()
                local head = parts[1][1]:FindFirstChild("Head")
                if not head then return end
                game.ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(head, parts, {}, tostring(
                    game.Players.LocalPlayer.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15))
                cloneref(remote):FireServer(string.gsub("RE/RegisterHit", ".", function(c)
                    return string.char(bit32.bxor(string.byte(c), math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1))
                end), bit32.bxor(idremote + 909090, game.ReplicatedStorage.Modules.Net.seed:InvokeServer() * 2), head,
                    parts)
            end)
        end
    end
end)
spawn(function()
    while wait() do
        if module then module:haki() end
        AttackNoCoolDown()
    end
end)

-- FIX #5 + ĐỒNG BỘ: clock sync KHÔNG chặn luồng chính + luôn trả epoch server nhất quán.
serverClockOffset = nil
function syncClock()
    local t0 = tick()
    local srv = tonumber(Net.text(BASE_URL .. "/timeserver", 0))
    local t1 = tick()
    if srv then
        serverClockOffset = (srv + (t1 - t0) / 2) - t1
        return true
    end
    return false
end
-- serverNow LUÔN trả epoch server (nhất quán mọi account). Không bao giờ trả tick() thô
-- (tránh lệch hàng tỷ giây làm account không bấm được).
function serverNow()
    if serverClockOffset ~= nil then
        return tick() + serverClockOffset
    end
    -- chưa sync xong → lấy thẳng từ server 1 lần (epoch đúng)
    local srv = tonumber(Net.text(BASE_URL .. "/timeserver", 1))
    if srv then return srv end
    return os and os.time and os.time() or 0
end
function gettimeserver()
    return serverNow()
end
-- sync nền, KHÔNG chặn load
spawn(function()
    syncClock()
    while true do wait(20); pcall(syncClock) end
end)

-- ===== ABILITY SYNC (phương pháp FILE workspace): 3 account chung 1 PC bấm cùng lúc =====
-- KHÔNG còn dùng web để hẹn giờ bấm (đã bỏ /firesignal, /donedoor, /abilityready cho việc bấm).
-- Vẫn dùng web CHỈ để đánh số role/index (Main..idx / Ally..i) qua /init.
-- Cơ chế:
--   1) Mỗi account ghi FILE RIÊNG trong folder racev4_vunguyen/: checkalready_<label thường>
--      nội dung "<Label>:doorandability=<true|false>" (vd checkalready_main1 → "Main1:doorandability=true").
--      true khi đủ CẢ 2: đứng ở cửa (<AT_DOOR_DIST) VÀ CÙNG jobid (cùng server) với main đang turn.
--      Mỗi con CHỈ đụng file của mình → HẾT tranh ghi (lost-update) như khi xài chung 1 checkalready.txt.
--   2) Khi CẢ 3 file (Main1 + Ally1 + Ally2...) = true → main ghi starttime.txt = GIỜ THỰC Hà Nội + LEAD.
--   3) Cả 3 account đọc starttime mỗi giây. Tới đúng giờ đó (age ∈ [0, window)) thì bấm ActivateAbility 1 lần.
-- starttime ghi "HH:MM:SS" giờ UTC+7 (Hà Nội/Bangkok); so theo giây-trong-ngày → bấm đồng bộ 1 thời điểm.
local ABILITY_FIRE_WINDOW = 6   -- giây — chỉ bấm trong khoảng [start, start+window)
local AT_DOOR_DIST = 150        -- coi như "đứng ở cửa" khi cách Entrance < ngần này (nới nhẹ từ 120)
local START_LEAD   = 5          -- giây — starttime = bây giờ + 5s
local ABILITY_COOLDOWN = 30     -- giây — sau khi bấm ActivateAbility phải chờ ngần này mới được bấm lại
_G.myFireEpoch = _G.myFireEpoch or 0   -- epoch (server) lần cuối bấm ActivateAbility (0 = chưa bấm → sẵn sàng)
-- ===== FILE SYNC theo ROLE (folder riêng, MỖI ACC 1 FILE → hết tranh ghi) =====
local SYNC_DIR     = "racev4_vunguyen"
local START_FILE   = SYNC_DIR .. "/starttime.txt"
local function ensureSyncDir()
    if isfolder and not isfolder(SYNC_DIR) then pcall(function() makefolder(SYNC_DIR) end) end
end
ensureSyncDir()
-- Dọn file cũ ở thư mục gốc (bản trước dùng chung checkalready.txt / starttime.txt) → tránh đọc nhầm.
pcall(function()
    if isfile and delfile then
        if isfile("checkalready.txt") then delfile("checkalready.txt") end
        if isfile("starttime.txt") then delfile("starttime.txt") end
    end
end)
-- "Main1" → racev4_vunguyen/checkalready_main1 ; "Ally2" → racev4_vunguyen/checkalready_ally2
local function checkFileForLabel(label)
    return SYNC_DIR .. "/checkalready_" .. string.lower(label)
end

-- Toạ độ cửa trial từng tộc (tham khảo Banana "Teleport To Trial Door") — nguồn check door
-- dự phòng khi getdoor() trả nil/sai. Lấy khoảng cách NHỎ NHẤT giữa 2 nguồn cho chuẩn.
local BANANA_DOOR_CFRAME = {
    Human   = CFrame.new(29221.822, 14890.975, -205.991),
    Skypiea = CFrame.new(28960.158, 14919.624, 235.039),
    Fishman = CFrame.new(28231.175, 14890.975, -211.641),
    Cyborg  = CFrame.new(28502.681, 14895.975, -423.727),
    Ghoul   = CFrame.new(28674.244, 14890.676, 445.431),
    Mink    = CFrame.new(29012.341, 14890.975, -380.149),
}

-- Khoảng cách tới cửa corridor của mình (LOCAL, không mạng).
-- "Thuật toán check chuẩn": thử cả getdoor() lẫn toạ độ Banana, lấy cái gần nhất.
-- ƯU TIÊN part THẬT (getdoor, đã cache) → chính xác. KHÔNG min với toạ độ hardcode nữa:
-- min làm "đứng ở temple vẫn ghi true" khi toạ độ Banana lỡ gần chỗ đứng. Banana CHỈ dùng
-- khi getdoor chưa resolve được lần nào (rất hiếm, vd corridor chưa stream).
local function distToMyDoor()
    local door = getdoor()
    if door then
        local d = getdis(door.CFrame)
        -- DEBUG: R = part Door.Entrance THẬT của corridor (chuẩn). Nếu ở Temple of Time mà d≈0
        -- với src=R nghĩa là getdoor() trả part nằm sai chỗ (ngay hub) → cần đổi mốc cửa.
        _G.lastDoorSrc, _G.lastDoorName, _G.lastDoorDist = "R", door.Name, d
        return d
    end
    local cf = BANANA_DOOR_CFRAME[game.Players.LocalPlayer.Data.Race.Value]
    if cf then
        local d = getdis(cf)
        -- B = toạ độ Banana hardcode (dự phòng). d≈0 với src=B = toạ độ Banana trùng chỗ đứng.
        _G.lastDoorSrc, _G.lastDoorName, _G.lastDoorDist = "B", "banana", d
        return d
    end
    _G.lastDoorSrc, _G.lastDoorName, _G.lastDoorDist = "X", "none", 1e9
    return 1e9
end

-- ===== GIỜ THỰC UTC+7 (Hà Nội / Bangkok) =====
local TZ_OFFSET = 7 * 3600   -- UTC+7
-- epoch (UTC) → giây-trong-ngày theo giờ Hà Nội (0..86399)
local function hanoiSecOfDay(epoch)
    return math.floor(epoch + TZ_OFFSET) % 86400
end
-- epoch → chuỗi "HH:MM:SS" giờ Hà Nội (ghi vào starttime.txt cho dễ đọc)
local function fmtHanoi(epoch)
    local s = hanoiSecOfDay(epoch)
    return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
end
-- "HH:MM:SS" → giây-trong-ngày (nil nếu sai định dạng)
local function parseHanoi(str)
    local h, m, s = string.match(str or "", "(%d+):(%d+):(%d+)")
    if not h then return nil end
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
end

-- Cùng server (jobid) với MAIN đang tới turn? (CACHE 3s, tránh spam /noguchi mỗi giây)
-- Bản thân main đang-turn → luôn true. Ally → so jobid qua isSameServerAsMain.
local _ssCache = { t = -1e9, v = false }
local function sameServerAsCurrentMain()
    local curName = getCurrentMainBeingUpgraded()
    if not curName then return false end
    if myName == curName then return true end
    local now = tick()
    if now - _ssCache.t < 3 then return _ssCache.v end
    local same = isSameServerAsMain(curName)
    _ssCache.t = now
    _ssCache.v = same and true or false
    return _ssCache.v
end

-- Vị trí của mình trong danh sách Allies (1-based), nil nếu không phải ally
local function allyIndexOf(nm)
    for i, v in ipairs(getgenv().Config["Allies"] or {}) do
        if v == nm then return i end
    end
    return nil
end

-- Nhãn (label) của CHÍNH account này trong checkalready.txt:
--   - Main đang tới turn  → "Main"..idx_web_của_main_đó
--   - Ally                → "Ally"..vị_trí_trong_Allies
--   - Main KHÔNG tới turn  → nil (không tham gia round này)
local function myAbilityLabel()
    local curName, curIdx = getCurrentMainBeingUpgraded()
    if curName and myName == curName then
        return "Main" .. tostring(curIdx)
    end
    local ai = allyIndexOf(myName)
    if ai then return "Ally" .. ai end
    return nil
end

-- Tập nhãn BẮT BUỘC phải true để chốt giờ: main đang-turn + toàn bộ ally
local function requiredLabels()
    local curName, curIdx = getCurrentMainBeingUpgraded()
    local labels = {}
    if curIdx then table.insert(labels, "Main" .. tostring(curIdx)) end
    for i, _ in ipairs(getgenv().Config["Allies"] or {}) do
        table.insert(labels, "Ally" .. i)
    end
    return labels
end

-- canactiveability của CHÍNH MÌNH: true nếu đã QUA cooldown 30s kể từ lần bấm ActivateAbility cuối.
-- Chưa bấm bao giờ (_G.myFireEpoch<=0) → true (sẵn sàng). Dùng serverNow (epoch server, đồng nhất mọi máy).
local function myCanActive()
    local fe = _G.myFireEpoch or 0
    if fe <= 0 then return true end
    return serverNow() >= (fe + ABILITY_COOLDOWN)
end

-- Đọc trạng thái READY của 1 label từ FILE RIÊNG của nó → bool.
-- READY = doorandability=true VÀ canactiveability=true (ability đã hết cooldown). Thiếu 1 → false.
local function readLabelReady(label)
    local fp = checkFileForLabel(label)
    if not (isfile and isfile(fp)) then return false end
    local ok, data = pcall(readfile, fp)
    if not ok or not data then return false end
    local door = string.match(data, "doorandability=(%w+)") == "true"
    local cana = string.match(data, "canactiveability=(%w+)") == "true"
    return door and cana
end

-- Ghi FILE RIÊNG của chính mình (KHÔNG đụng file account khác → hết tranh ghi).
-- Format: "<Label>:doorandability=<bool>;canactiveability=<bool>;<HH:MM:SS lần bấm ability cuối>"
local function writeMyCheck(label, cond)
    if not label then return end
    ensureSyncDir()
    local fe = _G.myFireEpoch or 0
    local fireStr = (fe > 0) and fmtHanoi(fe) or "00:00:00"
    pcall(function()
        writefile(checkFileForLabel(label),
            label .. ":doorandability=" .. (cond and "true" or "false")
            .. ";canactiveability=" .. (myCanActive() and "true" or "false")
            .. ";" .. fireStr)
    end)
end

-- Đủ tất cả nhãn bắt buộc = true? (đọc từng FILE RIÊNG của main-turn + các ally)
local function allReady()
    local req = requiredLabels()
    if #req == 0 then return false end
    for _, lb in ipairs(req) do
        if not readLabelReady(lb) then return false end
    end
    return true
end

-- Đọc starttime.txt ("HH:MM:SS" giờ Hà Nội) → giây-trong-ngày (0..86399), nil nếu sai
local function readStart()
    if not (isfile and isfile(START_FILE)) then return nil end
    local ok, data = pcall(readfile, START_FILE)
    if not ok or not data then return nil end
    return parseHanoi((string.gsub(data, "%s", "")))
end

-- (Bỏ) Không cần main tạo file chung nữa — mỗi account ghi FILE RIÊNG qua writeMyCheck;
-- folder racev4_vunguyen đã được ensureSyncDir() tạo sẵn ở trên.

-- ===== LOOP GHI: cadence 1s — ghi dòng của mình + (main) chốt starttime khi đủ 3 =====
spawn(function()
    while true do
        pcall(function()
            _G.myDoorReady = false   -- mặc định CHƯA sẵn sàng (chưa ở cửa / chưa cùng server)
            local label = myAbilityLabel()
            if label then
                -- chỉ true khi đủ CẢ 2: gần door VÀ cùng jobid (cùng server) với main đang turn.
                -- Thiếu 1 trong 2 → ghi false. Ghi liên tục mỗi 1s kể từ khi load script.
                local dd = distToMyDoor()
                local ss = sameServerAsCurrentMain()
                _G.lastDoorDist = dd        -- debug: soi detect cửa trên panel
                _G.lastSameSrv = ss
                local cond = (dd < AT_DOOR_DIST) and ss
                _G.myDoorReady = cond and true or false   -- = checkalready của mình → cổng cho loop bấm
                writeMyCheck(label, cond)

                -- Chỉ MAIN đang tới turn mới chốt giờ
                local curName = getCurrentMainBeingUpgraded()
                if curName and myName == curName then
                    -- Dùng EPOCH nội bộ để biết "vừa ghi gần đây" thay vì đọc lại giây-trong-ngày
                    -- của file (file cũ/khác ngày làm needNew kẹt false → không ghi starttime nữa).
                    -- Chốt mới khi: đã quá (lead+window) từ lần chốt trước VÀ đủ 3 con sẵn sàng.
                    local now = serverNow()
                    local last = _G.myStartEpoch or 0
                    if (now - last) > (START_LEAD + ABILITY_FIRE_WINDOW) and allReady() then
                        ensureSyncDir()
                        pcall(function() writefile(START_FILE, fmtHanoi(now + START_LEAD)) end)
                        _G.myStartEpoch = now
                    end
                end
            end
        end)
        wait(1)
    end
end)

-- ===== LOOP ĐỌC starttime: 1s, GIỮ giá-trị-tốt — đọc lỗi (file đang ghi) KHÔNG ghi đè nil =====
spawn(function()
    while true do
        pcall(function()
            local v = readStart()
            if v then _G.syncStart = v end   -- chỉ cập nhật khi đọc được → không clobber bằng nil
        end)
        wait(1)
    end
end)

-- ===== LOOP BẤM: CHỈ check starttime liên tục KHI Ở CỬA + checkalready(_G.myDoorReady)=true.
-- Ở cửa + sẵn sàng → TĂNG CƯỜNG poll 0.1s (không miss window). Chưa ở cửa/chưa sẵn sàng → 0.5s tiết kiệm,
-- KHÔNG đọc/bấm starttime (tránh bấm bậy khi chưa tới cửa). =====
spawn(function()
    while true do
        if _G.myDoorReady == true then
            pcall(function()
                local st = readStart() or _G.syncStart   -- ưu tiên đọc tươi, fallback giá trị cache
                if st then _G.syncStart = st end
                if st and st ~= _G.allyLastFire then
                    local age = hanoiSecOfDay(serverNow()) - st
                    if age < -43200 then age = age + 86400 end   -- wrap qua nửa đêm
                    if age >= ABILITY_FIRE_WINDOW then
                        -- giờ chốt ĐÃ TRÔI QUA cửa sổ → BỎ QUA (không bắn trễ), đánh dấu đã xử lý
                        _G.allyLastFire = st
                    elseif age >= 0 and distToMyDoor() < AT_DOOR_DIST then
                        _G.allyLastFire = st
                        _G.myFireEpoch = serverNow()   -- bắt đầu cooldown 30s → canactiveability=false tới khi hết
                        game.ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
                    end
                    -- age < 0 → giờ chốt ở tương lai → chờ tới đúng giờ
                end
            end)
            wait(0.1)   -- TĂNG CƯỜNG: ở cửa + ready → poll nhanh
        else
            wait(0.5)   -- chưa ở cửa / chưa ready → nghỉ, không check starttime
        end
    end
end)


-- MỌI account (cả ally) POST jobid mỗi 1s → dashboard hiện server từng con để so cùng/khác server.
spawn(function()
    while wait(1) do
        Net.postJSON(BASE_URL .. "/noguchi?name=" .. myName, { jobid = game.JobId }, "noguchi")
    end
end)

_G[myName] = true
-- ============================================================
-- [GUI] Vu Nguyen Kaitun V4 — Premium (self-contained luxury UI)
-- Không phụ thuộc thư viện ngoài. Theme tối + viền RGB + animation.
-- ============================================================
local LocalPlayer  = game:GetService("Players").LocalPlayer
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local StarterGui   = game:GetService("StarterGui")
local TPService    = game:GetService("TeleportService")

-- dọn GUI cũ nếu reload
pcall(function()
    local old = LocalPlayer.PlayerGui:FindFirstChild("VuNguyenKaitunV4")
    if old then old:Destroy() end
end)

-- ---- RGB animator: viền chạy 7 màu ----
local rgbObjects = {} -- { {obj=, offset=, s=, v=, prop=} }
local function RegisterRGB(obj, offset, s, v, prop)
    table.insert(rgbObjects, {
        obj = obj, offset = offset or 0, s = s or 0.85, v = v or 1,
        prop = prop or "Color"
    })
end
spawn(function()
    while true do
        local t = tick()
        for _, o in ipairs(rgbObjects) do
            if o.obj and o.obj.Parent then
                local hue = (t * 0.12 + o.offset) % 1
                pcall(function() o.obj[o.prop] = Color3.fromHSV(hue, o.s, o.v) end)
            end
        end
        RunService.RenderStepped:Wait()
    end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name           = "VuNguyenKaitunV4"
Gui.ResetOnSpawn   = false
Gui.IgnoreGuiInset = false
Gui.DisplayOrder   = 1000
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent         = LocalPlayer:WaitForChild("PlayerGui")

-- ---- Toggle floating button ----
local Toggle = Instance.new("TextButton")
Toggle.Size                   = UDim2.new(0, 54, 0, 54)
Toggle.Position               = UDim2.new(1, -70, 0.30, 0)
Toggle.BackgroundColor3       = Color3.fromRGB(18, 20, 28)
Toggle.BorderSizePixel        = 0
Toggle.Text                   = "👑"
Toggle.TextSize               = 26
Toggle.Font                   = Enum.Font.GothamBold
Toggle.TextColor3             = Color3.fromRGB(255, 255, 255)
Toggle.AutoButtonColor        = false
Toggle.Parent                 = Gui
Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0, 14)
local togGrad = Instance.new("UIGradient", Toggle)
togGrad.Rotation = 90
togGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 38, 55)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 17, 25)),
}
local togStroke = Instance.new("UIStroke", Toggle)
togStroke.Thickness       = 2.5
togStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
RegisterRGB(togStroke, 0)
Toggle.MouseEnter:Connect(function()
    TweenService:Create(Toggle, TweenInfo.new(0.2), {Size = UDim2.new(0, 60, 0, 60)}):Play()
end)
Toggle.MouseLeave:Connect(function()
    TweenService:Create(Toggle, TweenInfo.new(0.2), {Size = UDim2.new(0, 54, 0, 54)}):Play()
end)

-- ---- Main panel ----
local Panel = Instance.new("Frame")
Panel.Size             = UDim2.new(0, 320, 0, 460)
Panel.Position         = UDim2.new(0.5, -160, 0.5, -230)
Panel.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
Panel.BorderSizePixel  = 0
Panel.Active           = true
Panel.Draggable        = true
Panel.Visible          = true
Panel.Parent           = Gui
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 16)
local pGrad = Instance.new("UIGradient", Panel)
pGrad.Rotation = 135
pGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(22, 25, 38)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(14, 16, 24)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(10, 11, 18)),
}
local pStroke = Instance.new("UIStroke", Panel)
pStroke.Thickness       = 2.5
pStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
RegisterRGB(pStroke, 0)
local shadow = Instance.new("Frame")
shadow.Size                   = UDim2.new(1, 18, 1, 18)
shadow.Position               = UDim2.new(0, -9, 0, -9)
shadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
shadow.BackgroundTransparency = 0.6
shadow.BorderSizePixel        = 0
shadow.ZIndex                 = 0
shadow.Parent                 = Panel
Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 22)

-- ---- Header ----
local Header = Instance.new("Frame")
Header.Size             = UDim2.new(1, -20, 0, 52)
Header.Position         = UDim2.new(0, 10, 0, 10)
Header.BackgroundColor3 = Color3.fromRGB(20, 23, 35)
Header.BorderSizePixel  = 0
Header.Parent           = Panel
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)
local hGrad = Instance.new("UIGradient", Header)
hGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 32, 48)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 20, 30)),
}
local Title = Instance.new("TextLabel")
Title.Size                   = UDim2.new(1, -50, 0, 24)
Title.Position               = UDim2.new(0, 14, 0, 6)
Title.BackgroundTransparency = 1
Title.Text                   = "👑 VU NGUYEN KAITUN V4"
Title.TextColor3             = Color3.fromRGB(255, 255, 255)
Title.TextXAlignment         = Enum.TextXAlignment.Left
Title.Font                   = Enum.Font.GothamBold
Title.TextSize               = 15
Title.Parent                 = Header
local SubTitle = Instance.new("TextLabel")
SubTitle.Size                   = UDim2.new(1, -50, 0, 14)
SubTitle.Position               = UDim2.new(0, 14, 0, 30)
SubTitle.BackgroundTransparency = 1
SubTitle.Text                   = "✦ PREMIUM"
SubTitle.TextXAlignment         = Enum.TextXAlignment.Left
SubTitle.Font                   = Enum.Font.GothamBold
SubTitle.TextSize               = 11
SubTitle.Parent                 = Header
RegisterRGB(SubTitle, 0.1, 0.7, 1, "TextColor3")
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size             = UDim2.new(0, 30, 0, 30)
CloseBtn.Position         = UDim2.new(1, -38, 0.5, -15)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
CloseBtn.BorderSizePixel  = 0
CloseBtn.Text             = "✕"
CloseBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
CloseBtn.Font             = Enum.Font.GothamBold
CloseBtn.TextSize         = 15
CloseBtn.AutoButtonColor  = false
CloseBtn.Parent           = Header
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)
CloseBtn.MouseButton1Click:Connect(function() Panel.Visible = false end)
Toggle.MouseButton1Click:Connect(function() Panel.Visible = not Panel.Visible end)

-- ---- Tab bar ----
local TabBar = Instance.new("Frame")
TabBar.Size             = UDim2.new(1, -20, 0, 34)
TabBar.Position         = UDim2.new(0, 10, 0, 70)
TabBar.BackgroundColor3 = Color3.fromRGB(16, 18, 28)
TabBar.BorderSizePixel  = 0
TabBar.Parent           = Panel
Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 9)
local tabLayout = Instance.new("UIListLayout", TabBar)
tabLayout.FillDirection       = Enum.FillDirection.Horizontal
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
tabLayout.Padding             = UDim.new(0, 4)
local tabPad = Instance.new("UIPadding", TabBar)
tabPad.PaddingLeft  = UDim.new(0, 4)
tabPad.PaddingRight = UDim.new(0, 4)

-- ---- Pages container ----
local PageHolder = Instance.new("Frame")
PageHolder.Size                  = UDim2.new(1, -20, 1, -120)
PageHolder.Position              = UDim2.new(0, 10, 0, 112)
PageHolder.BackgroundTransparency = 1
PageHolder.BorderSizePixel       = 0
PageHolder.Parent                = Panel

local pages   = {}
local tabBtns = {}
local function selectTab(name)
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    for n, b in pairs(tabBtns) do
        local on = (n == name)
        TweenService:Create(b, TweenInfo.new(0.18), {
            BackgroundColor3 = on and Color3.fromRGB(40, 45, 68) or Color3.fromRGB(20, 23, 35)
        }):Play()
        b.TextColor3 = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,160,185)
    end
end

local function CreatePage(name)
    local page = Instance.new("ScrollingFrame")
    page.Size                  = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel       = 0
    page.ScrollBarThickness    = 4
    page.ScrollBarImageColor3  = Color3.fromRGB(120, 160, 240)
    page.CanvasSize            = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    page.Visible               = false
    page.Parent                = PageHolder
    local l = Instance.new("UIListLayout", page)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding   = UDim.new(0, 8)
    local p = Instance.new("UIPadding", page)
    p.PaddingTop = UDim.new(0, 2); p.PaddingBottom = UDim.new(0, 4)
    p.PaddingLeft = UDim.new(0, 2); p.PaddingRight = UDim.new(0, 4)
    pages[name] = page

    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(0, 96, 1, -6)
    btn.BackgroundColor3 = Color3.fromRGB(20, 23, 35)
    btn.BorderSizePixel  = 0
    btn.Text             = name
    btn.Font             = Enum.Font.GothamBold
    btn.TextSize         = 12
    btn.TextColor3       = Color3.fromRGB(150, 160, 185)
    btn.AutoButtonColor  = false
    btn.Parent           = TabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    tabBtns[name] = btn
    return page
end

-- ---- widget builders ----
local function addCard(page, order, height)
    local f = Instance.new("Frame")
    f.LayoutOrder      = order
    f.Size             = UDim2.new(1, 0, 0, height)
    f.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
    f.BorderSizePixel  = 0
    f.Parent           = page
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
    local g = Instance.new("UIGradient", f)
    g.Rotation = 90
    g.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 27, 41)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 16, 24)),
    }
    return f
end

local function StatusCard(page, order)
    local f = addCard(page, order, 72)
    local s = Instance.new("UIStroke", f); s.Thickness = 1.8; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    RegisterRGB(s, 0.33)
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -16, 0, 16); t.Position = UDim2.new(0, 12, 0, 8)
    t.BackgroundTransparency = 1; t.Text = "● STATUS"
    t.TextColor3 = Color3.fromRGB(140, 200, 255); t.TextXAlignment = Enum.TextXAlignment.Left
    t.Font = Enum.Font.GothamBold; t.TextSize = 11; t.Parent = f
    local v = Instance.new("TextLabel")
    v.Size = UDim2.new(1, -20, 0, 40); v.Position = UDim2.new(0, 12, 0, 26)
    v.BackgroundTransparency = 1; v.Text = "Đang khởi động..."
    v.TextColor3 = Color3.fromRGB(255, 255, 255); v.TextXAlignment = Enum.TextXAlignment.Left
    v.TextYAlignment = Enum.TextYAlignment.Top; v.Font = Enum.Font.GothamBold
    v.TextSize = 13; v.TextWrapped = true; v.Parent = f
    return v
end

local function LabelCard(page, order, titleText, descText)
    local f = addCard(page, order, 50)
    local s = Instance.new("UIStroke", f); s.Thickness = 1.2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    RegisterRGB(s, (order % 7) / 7)
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -16, 0, 18); t.Position = UDim2.new(0, 12, 0, 7)
    t.BackgroundTransparency = 1; t.Text = titleText
    t.TextColor3 = Color3.fromRGB(230, 235, 255); t.TextXAlignment = Enum.TextXAlignment.Left
    t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = f
    local d = Instance.new("TextLabel")
    d.Size = UDim2.new(1, -16, 0, 16); d.Position = UDim2.new(0, 12, 0, 27)
    d.BackgroundTransparency = 1; d.Text = descText or ""
    d.TextColor3 = Color3.fromRGB(140, 150, 175); d.TextXAlignment = Enum.TextXAlignment.Left
    d.Font = Enum.Font.Gotham; d.TextSize = 11; d.TextTruncate = Enum.TextTruncate.AtEnd; d.Parent = f
    return { SetTitle = function(_, x) t.Text = x end, SetDesc = function(_, x) d.Text = x end }
end

local function ButtonCard(page, order, text, callback)
    local btn = Instance.new("TextButton")
    btn.LayoutOrder      = order
    btn.Size             = UDim2.new(1, 0, 0, 42)
    btn.BackgroundColor3 = Color3.fromRGB(22, 25, 38)
    btn.BorderSizePixel  = 0
    btn.Text             = ""
    btn.AutoButtonColor  = false
    btn.Parent           = page
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
    local grad = Instance.new("UIGradient", btn); grad.Rotation = 90
    grad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 42, 60)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 25, 38)),
    }
    local stroke = Instance.new("UIStroke", btn); stroke.Thickness = 1.5; stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    RegisterRGB(stroke, (order % 7) / 7)
    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 30, 1, 0); icon.Position = UDim2.new(0, 8, 0, 0)
    icon.BackgroundTransparency = 1; icon.Text = "🚀"; icon.Font = Enum.Font.GothamBold
    icon.TextSize = 16; icon.TextColor3 = Color3.fromRGB(255,255,255); icon.Parent = btn
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -50, 1, 0); lbl.Position = UDim2.new(0, 42, 0, 0)
    lbl.BackgroundTransparency = 1; lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(245, 250, 255); lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 13; lbl.Parent = btn
    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 24, 1, 0); arrow.Position = UDim2.new(1, -28, 0, 0)
    arrow.BackgroundTransparency = 1; arrow.Text = "›"; arrow.TextColor3 = Color3.fromRGB(180,200,255)
    arrow.TextTransparency = 0.5; arrow.Font = Enum.Font.GothamBold; arrow.TextSize = 22; arrow.Parent = btn
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.18), {Size = UDim2.new(1, 0, 0, 46)}):Play()
        TweenService:Create(arrow, TweenInfo.new(0.18), {TextTransparency = 0}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.18), {Size = UDim2.new(1, 0, 0, 42)}):Play()
        TweenService:Create(arrow, TweenInfo.new(0.18), {TextTransparency = 0.5}):Play()
    end)
    btn.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback)
        if not ok then warn("[Kaitun GUI] " .. tostring(err)) end
    end)
    return btn
end

local function ToggleCard(page, order, text, descText, default, callback)
    local f = addCard(page, order, 46)
    local s = Instance.new("UIStroke", f); s.Thickness = 1.2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    RegisterRGB(s, (order % 7) / 7)
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -70, 0, 18); t.Position = UDim2.new(0, 12, 0, 6)
    t.BackgroundTransparency = 1; t.Text = text; t.TextColor3 = Color3.fromRGB(230,235,255)
    t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = f
    local d = Instance.new("TextLabel")
    d.Size = UDim2.new(1, -70, 0, 14); d.Position = UDim2.new(0, 12, 0, 25)
    d.BackgroundTransparency = 1; d.Text = descText or ""; d.TextColor3 = Color3.fromRGB(140,150,175)
    d.TextXAlignment = Enum.TextXAlignment.Left; d.Font = Enum.Font.Gotham; d.TextSize = 10; d.Parent = f
    local sw = Instance.new("TextButton")
    sw.Size = UDim2.new(0, 44, 0, 22); sw.Position = UDim2.new(1, -54, 0.5, -11)
    sw.BackgroundColor3 = default and Color3.fromRGB(60,200,110) or Color3.fromRGB(60,64,82)
    sw.Text = ""; sw.AutoButtonColor = false; sw.Parent = f
    Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18); knob.Position = default and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255); knob.BorderSizePixel = 0; knob.Parent = sw
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local state = default
    sw.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(sw, TweenInfo.new(0.18), {
            BackgroundColor3 = state and Color3.fromRGB(60,200,110) or Color3.fromRGB(60,64,82)
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.18), {
            Position = state and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
        }):Play()
        pcall(callback, state)
    end)
    return f
end

local function DropdownCard(page, order, text, options, default, callback)
    local f = addCard(page, order, 46)
    local s = Instance.new("UIStroke", f); s.Thickness = 1.2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    RegisterRGB(s, (order % 7) / 7)
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -110, 1, 0); t.Position = UDim2.new(0, 12, 0, 0)
    t.BackgroundTransparency = 1; t.Text = text; t.TextColor3 = Color3.fromRGB(230,235,255)
    t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = f
    local cur = Instance.new("TextButton")
    cur.Size = UDim2.new(0, 90, 0, 30); cur.Position = UDim2.new(1, -100, 0.5, -15)
    cur.BackgroundColor3 = Color3.fromRGB(30,34,50); cur.Text = default
    cur.TextColor3 = Color3.fromRGB(255,255,255); cur.Font = Enum.Font.GothamBold; cur.TextSize = 12
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
    local s = Instance.new("UIStroke", f); s.Thickness = 1.2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    RegisterRGB(s, (order % 7) / 7)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -24, 1, -14); box.Position = UDim2.new(0, 12, 0, 7)
    box.BackgroundColor3 = Color3.fromRGB(14,16,24); box.PlaceholderText = placeholder
    box.Text = ""; box.TextColor3 = Color3.fromRGB(255,255,255); box.PlaceholderColor3 = Color3.fromRGB(120,128,150)
    box.Font = Enum.Font.Gotham; box.TextSize = 13; box.ClearTextOnFocus = false
    box.TextXAlignment = Enum.TextXAlignment.Left; box.Parent = f
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
    local pad = Instance.new("UIPadding", box); pad.PaddingLeft = UDim.new(0, 8)
    box:GetPropertyChangedSignal("Text"):Connect(function() pcall(callback, box.Text) end)
    return box
end

-- =================== PAGE: MAIN ===================
local mainPage = CreatePage("Main")
local StatusValue = StatusCard(mainPage, 1)
local Status = { -- giữ tương thích API cũ status loop
    SetTitle = function() end,
    SetDesc  = function(_, v) StatusValue.Text = v end,
}
-- Choose Gear (load value đã lưu)
do
    local savedGear = "A-B-B"
    pcall(function()
        local y = game.HttpService:JSONDecode(readfile("nawy/kaitunv4.json"))
        if y and y["Choose Gear"] then savedGear = y["Choose Gear"] end
    end)
    getgenv().Config["Gear"] = savedGear
    DropdownCard(mainPage, 2, "Choose Gear", { "A-B-B", "A-A-B" }, savedGear, function(v)
        getgenv().Config["Gear"] = v
        pcall(function()
            local m = {}; pcall(function() m = game.HttpService:JSONDecode(readfile("nawy/kaitunv4.json")) end)
            if type(m) ~= "table" then m = {} end
            if not isfolder("nawy") then makefolder("nawy") end
            m["Choose Gear"] = v
            writefile("nawy/kaitunv4.json", game.HttpService:JSONEncode(m))
        end)
    end)
end
-- Reset After Trial
do
    local savedReset = false
    pcall(function()
        local y = game.HttpService:JSONDecode(readfile("nawy/kaitunv4.json"))
        if y and y["Reset After Trial"] ~= nil then savedReset = y["Reset After Trial"] and true or false end
    end)
    getgenv().Config["ResetAfterTrial"] = savedReset
    ToggleCard(mainPage, 3, "Reset After Trial", "Allies", savedReset, function(v)
        getgenv().Config["ResetAfterTrial"] = v
        pcall(function()
            local m = {}; pcall(function() m = game.HttpService:JSONDecode(readfile("nawy/kaitunv4.json")) end)
            if type(m) ~= "table" then m = {} end
            if not isfolder("nawy") then makefolder("nawy") end
            m["Reset After Trial"] = v
            writefile("nawy/kaitunv4.json", game.HttpService:JSONEncode(m))
        end)
    end)
end
-- Job id input + join
TextboxCard(mainPage, 4, "Nhập Job ID...", function(text) _G.jobidinput = text end)
ButtonCard(mainPage, 5, "Join Job Id", function()
    pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("__ServerBrowser"):InvokeServer("teleport", _G.jobidinput)
    end)
end)

-- Change Race (đổi tộc 2500 Fragments) — bản Banana: BlackbeardReward "Reroll" 1+2
ButtonCard(mainPage, 6, "Change Race (2500F)", function()
    pcall(function()
        local R = game:GetService("ReplicatedStorage").Remotes.CommF_
        R:InvokeServer("BlackbeardReward", "Reroll", "1")
        R:InvokeServer("BlackbeardReward", "Reroll", "2")
    end)
end)

-- 🌐 Net diagnostic card — hiện hasReq + GET/POST tới backend đo TỪ TRONG executor
local NetDiag = LabelCard(mainPage, 7, "🌐 Net (backend)", "đang kiểm tra…")
spawn(function()
    while wait(1) do
        if _G.netDiag then pcall(function() NetDiag:SetDesc(_G.netDiag) end) end
    end
end)

-- 🔎 Sync Debug card — dump trạng thái đồng bộ Main/Ally (chỉ đọc cache, KHÔNG gọi mạng)
local SyncDbg = LabelCard(mainPage, 8, "🔎 Sync Debug", "…")
spawn(function()
    while wait(0.5) do
        pcall(function()
            local cur = getCurrentMainBeingUpgraded()        -- cache-only, không block
            local c = cur and statusCache[cur]
            local me = isaccmain[myName] and ("MAIN" .. tostring(myMainIndex)) or "ALLY"
            -- me=vai trò | cur=main stt1 | st=status main(tuổi cache) | ss=cùng/khác server
            -- | i=UpgradeRace Check | d=khoảng cách cửa + nguồn(R/B/X)
            SyncDbg:SetDesc(("me=%s cur=%s st=%s(%ss) ss=%s i=%s d=%s%s dn=%s"):format(
                me, tostring(cur):sub(1, 12),
                tostring(c and c.status or "?"),
                c and string.format("%.0f", tick() - c.t) or "?",
                _G.lastSameSrv and "same" or "diff",
                tostring(_G.lastRaceI),
                tostring(_G.lastDoorDist and math.floor(_G.lastDoorDist) or "?"),
                tostring(_G.lastDoorSrc or "?"),
                tostring(_G.lastDoorName or "?")))
        end)
    end
end)

-- live status loop
spawn(function()
    while wait() do
        if _G.statusnow then StatusValue.Text = _G.statusnow end
    end
end)

-- =================== PAGE: MAIN STATUS ===================
local statusPage = CreatePage("Status")
local mainStatusLabels = {}
for i, name in ipairs(getgenv().Config["MainAccount"]) do
    mainStatusLabels[name] = LabelCard(statusPage, i, "Main " .. i .. ": " .. name, "loading...")
end
spawn(function()
    while wait(3) do
        for i, name in ipairs(getgenv().Config["MainAccount"]) do
            pcall(function()
                local st = getMainStatus(name)
                if mainStatusLabels[name] then mainStatusLabels[name]:SetDesc("Status: " .. st) end
            end)
        end
    end
end)

-- =================== PAGE: ACCOUNTS ===================
local accPage = CreatePage("Accounts")
function get_data_safe(target_name)
    local data = Net.getJSON(BASE_URL .. "/noguchi?name=" .. target_name, 3)
    if data and data.data and data.data.jobid then return data.data.jobid end
    return "N/A"
end
local accOrder = 0
for idx, vl in pairs(getgenv().Config["Allies"]) do
    accOrder = accOrder + 1
    local label = LabelCard(accPage, accOrder, "Account: " .. vl, "No Update")
    local jobidnow = "no update"
    accOrder = accOrder + 1
    ButtonCard(accPage, accOrder, "Join to " .. vl, function()
        game:GetService("ReplicatedStorage"):WaitForChild("__ServerBrowser"):InvokeServer("teleport", jobidnow)
    end)
    spawn(function()
        while wait(5) do
            pcall(function()
                local dataplr = Net.getJSON(BASE_URL .. "/noguchi?name=" .. vl, 3)
                if dataplr and dataplr["data"] and dataplr["data"]["jobid"] then
                    local jobid, time = dataplr["data"]["jobid"], dataplr["data"]["time"]
                    local t = gettimeserver()
                    label:SetDesc(tostring(jobid):sub(1,18) .. " | " .. tostring(t - time) .. "s ago")
                    jobidnow = jobid
                    _G.current_target_jobid = jobid
                end
            end)
        end
    end)
end

-- =================== PAGE: DEBUG (đèn xanh/đỏ + LOG cuộn 200 dòng) ===================
local debugPage = CreatePage("Debug")

-- đèn chỉ báo: cập nhật TẠI CHỖ (xanh=ok / đỏ=lỗi) → KHÔNG spam log
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

spawn(function()
    while wait(0.4) do
        pcall(function()
            local alive = _G.loopLastT and (tick() - _G.loopLastT) < 2
            setLoop(alive == true, "Loop: " .. (alive and ("alive #" .. tostring(_G.loopTick or 0)) or "STALL!"))
            local g, p = _G.netGetOk, _G.netPostOk
            setNet(g and p == true, "Net: GET " .. (g and "OK" or "FAIL")
                .. " | POST " .. (p == nil and "N/A(no req)" or (p and "OK" or "FAIL")))
            setSrv(_G.lastSameSrv == true, "Server: " .. (_G.lastSameSrv and "SAME (cùng main)" or "DIFF (khác)"))
            local atDoor = _G.lastDoorDist and _G.lastDoorDist < 150
            setDoor(atDoor == true, "Door: d=" .. tostring(_G.lastDoorDist and math.floor(_G.lastDoorDist) or "?")
                .. tostring(_G.lastDoorSrc or "?") .. " " .. tostring(_G.lastDoorName or "?"))
            local cur = getCurrentMainBeingUpgraded()
            local c = cur and statusCache[cur]
            setMain(c ~= nil, "Main1: " .. tostring(cur):sub(1, 12) .. " = " .. tostring(c and c.status or "?"))
        end)
    end
end)

-- LOG box: ScrollingFrame lồng cao 286px, cuộn riêng 200 dòng, tô màu theo level
local logSF
do
    local box = addCard(debugPage, 6, 286)
    local hl = Instance.new("TextLabel")
    hl.Size = UDim2.new(1, -16, 0, 18); hl.Position = UDim2.new(0, 10, 0, 4)
    hl.BackgroundTransparency = 1; hl.Text = "📜 LOG (tối đa 200 dòng · cuộn ↕)"
    hl.TextColor3 = Color3.fromRGB(150, 200, 255); hl.TextXAlignment = Enum.TextXAlignment.Left
    hl.Font = Enum.Font.GothamBold; hl.TextSize = 11; hl.Parent = box
    logSF = Instance.new("ScrollingFrame")
    logSF.Size = UDim2.new(1, -12, 1, -28); logSF.Position = UDim2.new(0, 6, 0, 24)
    logSF.BackgroundColor3 = Color3.fromRGB(10, 12, 18); logSF.BackgroundTransparency = 0.3
    logSF.BorderSizePixel = 0; logSF.ScrollBarThickness = 5
    logSF.ScrollBarImageColor3 = Color3.fromRGB(120, 160, 240)
    logSF.CanvasSize = UDim2.new(0, 0, 0, 0); logSF.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logSF.Parent = box
    Instance.new("UICorner", logSF).CornerRadius = UDim.new(0, 8)
    local lay = Instance.new("UIListLayout", logSF)
    lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Padding = UDim.new(0, 1)
    local pad = Instance.new("UIPadding", logSF)
    pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
    pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
end
local logLabels = {}   -- seq -> TextLabel
spawn(function()
    while wait(0.4) do
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
            -- auto-cuộn xuống đáy NẾU đang ở gần đáy; nếu user cuộn lên đọc thì GIỮ nguyên
            local nb = logSF.CanvasPosition.Y >= (logSF.AbsoluteCanvasSize.Y - logSF.AbsoluteWindowSize.Y - 24)
            if nb then logSF.CanvasPosition = Vector2.new(0, logSF.AbsoluteCanvasSize.Y) end
        end)
    end
end)

selectTab("Main")

-- intro animation
Panel.Size = UDim2.new(0, 0, 0, 0)
TweenService:Create(Panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = UDim2.new(0, 320, 0, 460)
}):Play()
