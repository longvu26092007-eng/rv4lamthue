repeat
    task.wait(0.1)
until game:GetService("ReplicatedStorage") and game:GetService("ReplicatedStorage"):FindFirstChild("Remotes") and game.Players and game.Players.LocalPlayer and not game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen")

if workspace:GetAttribute("MAP") and workspace:GetAttribute("MAP") ~= "Sea3" then
    game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TravelZou")
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
local BASE_URL = "https://api.vunguyensoft.shop"

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
        wait(0.6 * attempt)
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

-- POST mainstatus qua hàng đợi (retry). Cập nhật cache ngay để logic dùng giá trị mới.
function setMyMainStatus(statusStr)
    if not myMainIndex then return end
    statusCache[myName] = { t = tick(), status = statusStr }
    Net.postJSON(BASE_URL .. "/mainstatus?name=" .. myName, { status = statusStr }, "mainstatus")
end

-- ===== STATUS CACHE: đọc read-through, TTL ngắn → cắt bão getMainStatus mỗi frame =====
statusCache = {} -- name -> { t, status }
local STATUS_TTL = 3
local function fetchMainStatusLive(accName)
    local res = Net.getJSON(BASE_URL .. "/mainstatus?name=" .. accName, 0)
    if res and res["data"] and res["data"]["status"] then return res["data"]["status"] end
    return nil
end
function getMainStatus(accName)
    local c = statusCache[accName]
    if c and (tick() - c.t) < STATUS_TTL then return c.status end
    local st = fetchMainStatusLive(accName)
    if st == nil then
        -- FIX: lỗi mạng KHÔNG trả "waiting" (gây logic nhảy lung tung) → giữ giá trị cũ.
        if c then return c.status end
        return "waiting"
    end
    statusCache[accName] = { t = tick(), status = st }
    return st
end

-- Heartbeat: báo server account còn sống (qua hàng đợi, coalesce).
function sendHeartbeat()
    Net.postJSON(BASE_URL .. "/heartbeat?name=" .. myName, { role = myRole }, "heartbeat")
end

-- Vòng nền gửi heartbeat mỗi 5s (server prune ngưỡng 30s → chịu được vài lần rớt)
spawn(function()
    while true do
        sendHeartbeat()
        wait(5)
    end
end)

-- Warmer: làm nóng statusCache nền (rải đều) → getMainStatus trong vòng logic chỉ hit cache.
spawn(function()
    while true do
        local mains = (getgenv().Config and getgenv().Config["MainAccount"]) or {}
        for _, nm in ipairs(mains) do
            local st = fetchMainStatusLive(nm)
            if st ~= nil then statusCache[nm] = { t = tick(), status = st } end
            wait(0.15)
        end
        wait(1.5)
    end
end)

-- ===== ĐỒNG BỘ ABILITY: báo donedoor + abilityready (qua hàng đợi, coalesce, retry) =====
function reportDoneDoor(clear)
    Net.postJSON(BASE_URL .. "/donedoor?name=" .. myName, { clear = clear and true or false }, "donedoor")
end

function reportAbilityReady(need, clear)
    Net.postJSON(BASE_URL .. "/abilityready?name=" .. myName, { need = need, clear = clear and true or false }, "abilityready")
end

function thuaaa()
    if game:GetService("Players").LocalPlayer.Team then return end
    local team = getgenv().Config["Team"]
    if team ~= "Marines" and team ~= "Pirates" then team = "Marines" end
    pcall(function()
        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("SetTeam", team)
    end)
end

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
-- FIX #7 + TĂNG TỐC: cache module_bf.lua vào file local.
-- Lần đầu tải từ GitHub rồi lưu; các lần sau đọc thẳng từ disk (gần như tức thì, không chờ mạng).
local module
do
    local MODULE_CACHE = "kaitun_module_bf.lua"
    local MODULE_URL = "https://github.com/noguchihyuga/idk/blob/main/module_bf.lua?raw=true"
    local src
    -- 1) thử đọc cache local trước
    if isfile and isfile(MODULE_CACHE) then
        local okR, cached = pcall(readfile, MODULE_CACHE)
        if okR and cached and #cached > 50 then src = cached end
    end
    -- 2) chưa có cache → tải từ GitHub + lưu lại
    if not src then
        local okH, fetched = pcall(function() return game:HttpGet(MODULE_URL) end)
        if okH and fetched and #fetched > 50 then
            src = fetched
            pcall(function() writefile(MODULE_CACHE, fetched) end)
        end
    end
    -- 3) loadstring từ source (local hoặc vừa tải)
    if src then
        local okL, result = pcall(function() return loadstring(src)() end)
        if okL and result then
            module = result
        else
            warn("[KaitunV4] loadstring module_bf FAILED, thử tải lại từ GitHub...")
            -- cache hỏng → xóa, tải tươi
            pcall(function() if delfile then delfile(MODULE_CACHE) end end)
            local okH2, fetched2 = pcall(function() return game:HttpGet(MODULE_URL) end)
            if okH2 and fetched2 then
                local okL2, res2 = pcall(function() return loadstring(fetched2)() end)
                if okL2 and res2 then
                    module = res2
                    pcall(function() writefile(MODULE_CACHE, fetched2) end)
                end
            end
        end
    end
    if not module then warn("[KaitunV4] Load module_bf.lua FAILED hoàn toàn") end
end
local topofgreattree = CFrame.new(3035.15137, 2281.15918, -7325.19189, 0.0284484141, 2.19495124e-08, 0.999595284,
    -3.29094476e-08, 1, -2.10217994e-08, -0.999595284, -3.22980895e-08, 0.0284484141)

function getdoor(vv)
    vv = vv or game:GetService("Players").LocalPlayer.Data.Race.Value
    -- FIX: không dùng WaitForChild (treo vô hạn nếu corridor chưa load) → FindFirstChild an toàn
    local temple = workspace.Map:FindFirstChild("Temple of Time")
    if not temple then return nil end
    local corridor = temple:FindFirstChild(vv .. "Corridor")
    if not corridor then return nil end
    local door = corridor:FindFirstChild("Door")
    if not door then return nil end
    return door:FindFirstChild("Entrance")
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

local pos_plr_trial = {
    CFrame.new(28692.3477, 14887.5605, -53.7669983, 0.707131445, -0, -0.707082093, 0, 1, -0, 0.707082093, 0, 0.707131445),
    CFrame.new(28782.7246, 14898.9902, -59.6069946, 0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, 0.707134247),
    CFrame.new(28700.875, 14888.2598, -154.110992, -1, 0, 0, 0, 1, 0, 0, 0, -1),
    CFrame.new(28795.7715, 14888.2598, -112.917999, -0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, -0.707134247),
    CFrame.new(28658.4551, 14888.2598, -121.372009, -0.515037298, 0, -0.857167721, 0, 1, 0, 0.857167721, 0, -0.515037298),
    CFrame.new(28742.4688, 14887.5596, -18.2120056, 0.92051065, 0, 0.390717506, 0, 1, 0, -0.390717506, 0, 0.92051065)
}

function isplrshouldkill(plr)
    if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
        for i, v in pairs(pos_plr_trial) do
            if getdis(plr.Character.HumanoidRootPart.CFrame, v) < 5 then
                return true
            end
        end
    end
    return false
end

local race_abilities = {
    ["Human"] = "Last Resort",
    ["Mink"] = "Agility",
    ["Fishman"] = "Water Body",
    ["Skypiea"] = "Heavenly Blood",
    ["Ghoul"] = "Heightened Senses",
    ["Cyborg"] = "Energy Core",
    ["Draco"] = "Primordial Reign"
}
local races_trial_place = {
    ["Human"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of Strength"),
    ["Mink"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of Speed"),
    ["Fishman"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of Water"),
    ["Skypiea"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of the King"),
    ["Ghoul"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of Carnage"),
    ["Cyborg"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of the Machine"),
    ["Draco"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of Flames")
}

_G.playersinserver = {}
function updateplayers()
    if not _G.playersinserver then _G.playersinserver = {} end
    local players = {}
    for i, v in pairs(game.Players:GetChildren()) do
        players[v] = {
            ["Race"] = v.Data.Race.Value,
            ["Door"] = (function()
                local x, y = pcall(function()
                    return workspace.Map["Temple of Time"]:WaitForChild(v.Data.Race.Value .. "Corridor"):WaitForChild(
                    "Door"):WaitForChild("Entrance")
                end)
                if x then return y end
                return nil
            end)()
        }
    end
    _G.playersinserver = players
end

function isshouldturnonability()
    local Players = game.Players
    local c = 0
    local temple = workspace.Map:FindFirstChild("Temple of Time")
    if not temple then return false, 0 end
    for _, v in next, Players:GetPlayers() do
        local char = v.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local data = v:FindFirstChild("Data")
        local race = data and data:FindFirstChild("Race")
        if hrp and race and (isallies[v.Name] or isaccmain[v.Name]) then
            local corridor = temple:FindFirstChild(race.Value .. "Corridor")
            local door = corridor and corridor:FindFirstChild("Door")
            local entrance = door and door:FindFirstChild("Entrance")
            if entrance then
                if (entrance.Position - hrp.Position).Magnitude <= 50 then
                    c = c + 1
                end
            end
        end
    end
    return c >= 3, c
end

function checkfullgear() end

function talktoonggianaodo()
    local thua = game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("RaceV4Progress", "Check")
    if thua == 1 then
        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("RaceV4Progress", "Check")
        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("RaceV4Progress", "Begin")
    elseif thua == 2 then
        repeat
            wait()
            game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("RaceV4Progress", "Teleport")
            topos(CFrame.new(3028, 2281, -7325))
        until module:getdis(CFrame.new(28286.35546875, 14896.5078125, 102.62469482422)) <= 15
    else
        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("RaceV4Progress", "Check")
        wait(1)
        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("RaceV4Progress", "Continue")
    end
end

function getBlueGear()
    if not game.workspace.Map:FindFirstChild("MysticIsland") then return nil end
    for o, c in pairs(game.workspace.Map.MysticIsland:GetChildren()) do
        if c:IsA("MeshPart") and c.MeshId == "rbxassetid://10153114969" then
            return c
        end
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
function checkbackpack(v)
    return game.Players.LocalPlayer.Backpack:FindFirstChild(v) or game.Players.LocalPlayer.Character:FindFirstChild(v)
end

function getdialogoftemple()
    if not game.Players.LocalPlayer.Character:FindFirstChild("RaceTransformed") then return
        "You have yet to achieve greatness" end
    local i, d, f = game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("UpgradeRace", "Check")
    return i == 5 and "You Are Done Your Race"
        or i == 6 and "Upgrades completed: " .. d - 2 .. "/3, Need Trains More"
        or (i == 1 or i == 3) and "Please Train More"
        or (i == 2 or i == 4 or i == 7) and "You Can Buy Gear With " .. f .. " Fragments"
        or i == 0 and ("You Are Ready For Trial [Gear: " .. d .. "]")
        or i ~= 8 and "You have yet to achieve greatness"
        or "Remaining " .. 10 - d .. " training sessions."
end

function trialable()
    if not game.Players.LocalPlayer.Character:FindFirstChild("RaceTransformed") then
        local abcxyz = checkbackpack(race_abilities[game:GetService("Players").LocalPlayer.Data.Race.Value])
        if abcxyz then return true end
        return false
    end
    local i, d, f = game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("UpgradeRace", "Check")
    if i == 5 then
        return false
    else
        if i == 6 then
            return false, d - 2
        elseif i == 1 or i == 3 then
            return false
        elseif i == 2 or i == 4 or i == 7 then
            if f then
                local totalfragments = tonumber(f)
                if game:GetService("Players").LocalPlayer.Data.Fragments.Value >= totalfragments then
                    game:GetService("ReplicatedStorage")["Remotes"]["CommF_"]:InvokeServer("UpgradeRace", "Buy")
                else
                    return false, "raiding"
                end
            end
            return false, f
        elseif i == 0 then
            return true, d
        elseif i ~= 8 then
            return false
        else
            return true, 10 - d
        end
    end
end

local Gears = { "Alpha", "Omega" }
function getnameofgear()
    for i, v in pairs(workspace.Map["Temple of Time"].InnerClock:GetChildren()) do
        if v:IsA("MeshPart") and v:FindFirstChild("Highlight") and v.Highlight.FillTransparency == 1 then
            return v.Name
        end
    end
end

function status(v)
    _G.statusnow = v
end

function getCurrentMainBeingUpgraded()
    local mains = getgenv().Config["MainAccount"]
    if not mains or #mains == 0 then
        return nil, nil
    end
    for i, name in ipairs(mains) do
        local st = getMainStatus(name)
        if st == "moon" or st == "in_trail" then
            return name, i
        end
    end
    for i, name in ipairs(mains) do
        local st = getMainStatus(name)
        if st == "waiting" or st == "" then
            if i == 1 then
                return name, i
            else
                local prevSt = getMainStatus(mains[i - 1])
                if prevSt == "training" or prevSt == "waiting" or prevSt == "" then
                    return name, i
                end
            end
        end
    end
    return mains[1], 1
end

function getResetDelay(currentmain)
    local allyList = getgenv().Config["Allies"] or {}
    for i, name in ipairs(allyList) do
        if name == myName then
            return i * 2  -- ally 1 = 2s, ally 2 = 4s
        end
    end
    if isaccmain[myName] and myName ~= currentmain then
        local baseDelay = (#(getgenv().Config["Allies"] or {}) * 2) + 8
        return baseDelay + math.random(0, 3)
    end
    return nil
end

function followMainAccount()
    if isaccmain[myName] then return true end
    local sameServer = false
    pcall(function()
        local targetMain, _ = getCurrentMainBeingUpgraded()
        if not targetMain then
            status("[ALLY] Waiting for any main to register...")
            return
        end
        local ok, dataplr = pcall(function()
            return Net.getJSON(BASE_URL .. "/noguchi?name=" .. targetMain, 1)
        end)
        if ok and dataplr and dataplr["data"] and dataplr["data"]["jobid"] then
            local jobid = dataplr["data"]["jobid"]
            local time_ = dataplr["data"]["time"]
            local tick_ = gettimeserver()
            if tick_ - time_ < 30 then
                if jobid == game.JobId then
                    sameServer = true
                else
                    status("Follow main: " .. targetMain .. " (hop in 5s...)")
                    wait(5)
                    local ok2, dataplr2 = pcall(function()
                        return Net.getJSON(BASE_URL .. "/noguchi?name=" .. targetMain, 1)
                    end)
                    if ok2 and dataplr2 and dataplr2["data"] and dataplr2["data"]["jobid"] then
                        local jobid2 = dataplr2["data"]["jobid"]
                        if jobid2 == game.JobId then
                            sameServer = true
                        elseif jobid2 == jobid then
                            game:GetService("ReplicatedStorage"):WaitForChild("__ServerBrowser"):InvokeServer("teleport", jobid2)
                        end
                    end
                end
            else
                status("[ALLY] Main jobid too old, waiting...")
                sameServer = false
            end
        end
    end)
    return sameServer
end

function followPreviousMain()
    if not myMainIndex or myMainIndex <= 1 then return true end
    local prevMain = getgenv().Config["MainAccount"][myMainIndex - 1]
    if not prevMain then return true end
    local sameServer = false
    pcall(function()
        local ok, dataplr = pcall(function()
            return Net.getJSON(BASE_URL .. "/noguchi?name=" .. prevMain, 1)
        end)
        if ok and dataplr and dataplr["data"] then
            local jobid = dataplr["data"]["jobid"]
            local time_ = dataplr["data"]["time"]
            local tick_ = gettimeserver()
            if tick_ - time_ < 60 then
                if jobid == game.JobId then
                    sameServer = true
                else
                    status("Follow prev main: " .. prevMain)
                    game:GetService("ReplicatedStorage"):WaitForChild("__ServerBrowser"):InvokeServer("teleport", jobid)
                end
            end
        end
    end)
    return sameServer
end

-- Đọc jobid của main hiện tại → trả (cùng_server?, jobid_của_main).
-- Dùng cho nhánh ally quyết định: cùng server thì ra cửa, khác server thì hop.
function isSameServerAsMain(mainName)
    if not mainName then return false, nil end
    local same, job = false, nil
    local data = Net.getJSON(BASE_URL .. "/noguchi?name=" .. mainName, 1)
    if data and data["data"] and data["data"]["jobid"] then
        job = data["data"]["jobid"]
        local time_ = data["data"]["time"] or 0
        if (gettimeserver() - time_) < 60 and job == game.JobId then same = true end
    end
    return same, job
end

function checkgear()
    local dt = game.ReplicatedStorage.Remotes.CommF_:InvokeServer("TempleClock", "Check")
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
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TempleClock", "SpendPoint","Gear" .. tostring(dt.Completed), "Omega")
            elseif b >= 2 then
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TempleClock", "SpendPoint","Gear" .. tostring(dt.Completed), "Alpha")
            else
                game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("TempleClock", "SpendPoint","Gear" .. tostring(dt.RaceDetails.Completed), choosegear)
            end
        end
    end
end

CheckAlive = function(x)
    return x and x.Parent and x:FindFirstChild("Humanoid") and x:FindFirstChild("HumanoidRootPart") and
        x:FindFirstChild("Humanoid").Health > 0
end
TweenObject = function(Object, Pos, Speed)
    if Speed == nil then Speed = 350 end
    local Distance = (Pos.Position - Object.Position).Magnitude
    local tweenService = game:GetService("TweenService")
    local info = TweenInfo.new(Distance / Speed, Enum.EasingStyle.Linear)
    tween1 = tweenService:Create(Object, info, { CFrame = Pos })
    tween1:Play()
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
            -- FIX #4: bỏ điều kiện thừa `v.Name == v.Name` (luôn true)
            if hum and hum.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
                if (v.HumanoidRootPart.Position - plr.Character.HumanoidRootPart.Position).Magnitude <= 350 then
                    for k, f in pairs(totalpos) do
                        if k and v.Name == k and f then
                            Gay = CFrame.new(f.X, f.Y, f.Z)
                            Cac = (v.HumanoidRootPart.Position - Gay.Position).Magnitude
                            if Cac > 3 and Cac <= 280 then
                                TweenObject(v.HumanoidRootPart, Gay, 300)
                                v.HumanoidRootPart.CanCollide = false
                                v.Humanoid.WalkSpeed = 0
                                v.Humanoid.JumpPower = 0
                                v.Humanoid:ChangeState(14)
                                sethiddenproperty(game.Players.LocalPlayer, "SimulationRadius", math.huge)
                            end
                        end
                    end
                end
            end
        end
    end
end

local checktempledoor = game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("CheckTempleDoor")
_G.ShouldSendData = false
local issobusy = false
spawn(function()
    -- THROTTLE: trước đây `while wait()` ~mỗi frame → getCurrentMainBeingUpgraded gọi HTTP
    -- nhiều lần/frame → bão request → executor rate-limit → rớt dữ liệu. Giờ chạy 0.35s/vòng,
    -- getMainStatus đọc statusCache (warmer nền) nên gần như không còn request trong vòng này.
    while wait(0.35) do
        if not checktempledoor then
        else
            _G.ShouldSendData = false
            local ab, AB = trialable()
            local currentmain, currentidx = getCurrentMainBeingUpgraded()
            local myStatus = ""
            if isaccmain[myName] then
                myStatus = getMainStatus(myName)
            end
            if isaccmain[myName] then
                if (myStatus == "in_trail" or myStatus == "moon") and not ab then
                    status("[MAIN " .. myMainIndex .. "] Trial completed, switching to training!")
                    setMyMainStatus("training")
                    myStatus = "training"
                end
                if myStatus == "in_trail" and ab then
                    local in_temple = getdis(CFrame.new(28310.0234, 14895.1123, 109.456741)) < 3000
                    if not in_temple then
                        status("[MAIN " .. myMainIndex .. "] Died in trial, retrying...")
                        setMyMainStatus("waiting")
                        myStatus = "waiting"
                    end
                end
            end
            if isaccmain[myName] and myStatus == "training" then
                status("[MAIN " .. myMainIndex .. "] Training (parallel)")
                if not ab then
                    if AB == "raiding" then
                        local boss = workspace.Enemies:FindFirstChild("Cake Prince") or workspace.Enemies:FindFirstChild("Dough King")
                        if boss then
                            repeat wait()
                                pcall(function() topos(boss.HumanoidRootPart.CFrame * CFrame.new(0, 25, 0)) end)
                                module:eq()
                                module:haki()
                                BringMob()
                            until not checkmob_(boss)
                        end
                        status("[MAIN " .. myMainIndex .. "] Raiding for fragment")
                    else
                        pcall(function()
                            if game.Players.LocalPlayer.Character.RaceEnergy.Value == 1 then
                                game:GetService("VirtualInputManager"):SendKeyEvent(true, "Y", false, game)
                                game:GetService("VirtualInputManager"):SendKeyEvent(false, "Y", false, game)
                            end
                        end)
                        local pos__ = CFrame.new(214.688675, 126.626984, -12600.2236, -0.180400655, -1.09679892e-08, 0.983593225, 1.94620693e-08, 1, 1.47204746e-08, -0.983593225, 2.17983427e-08, -0.180400655)
                        if getdis(pos__) < 1500 then
                            local mobs = getmob1(pos__)
                            for i, v in pairs(mobs) do
                                repeat wait()
                                    module:eq()
                                    module:haki()
                                    BringMob()
                                    pcall(function()
                                        if game.Players.LocalPlayer.Character.RaceTransformed.Value then
                                            status("[MAIN " .. myMainIndex .. "] Training (Wait for end V4)")
                                            topos(v.HumanoidRootPart.CFrame * CFrame.new(0, 150, 0))
                                        else
                                            status("[MAIN " .. myMainIndex .. "] Training (Kill Mobs)")
                                            topos(v.HumanoidRootPart.CFrame * CFrame.new(0, 20, 0))
                                        end
                                    end)
                                    spawn(function()
                                        pcall(function()
                                            if game.Players.LocalPlayer.Character.RaceEnergy.Value == 1 then
                                                game:GetService("VirtualInputManager"):SendKeyEvent(true, "Y", false,game)
                                                game:GetService("VirtualInputManager"):SendKeyEvent(false, "Y", false,game)
                                            end
                                        end)
                                    end)
                                until not checkmob_(v)
                            end
                        else
                            topos(pos__)
                        end
                    end
                else
                    status("[MAIN " .. myMainIndex .. "] Training done, back to waiting")
                    setMyMainStatus("waiting")
                end
            elseif isaccmain[myName] and currentmain == myName then
                status("[MAIN " .. myMainIndex .. "] My turn to upgrade gear!")
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
                                            status("[MAIN " .. myMainIndex .. "] Hop fullmoon server")
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
                    if not workspace.Map:FindFirstChild("Temple of Time") then
                        if game:GetService("ReplicatedStorage").MapStash:FindFirstChild("Temple of Time") then
                            game:GetService("ReplicatedStorage").MapStash["Temple of Time"].Parent = workspace.Map
                        end
                    elseif workspace.Map["Temple of Time"].FFABorder.Forcefield.Transparency == 0 then
                        status("[MAIN " .. myMainIndex .. "] Kill Players After Trial")
                        for plr, i in pairs(getplayers()) do
                            if plr then
                                repeat wait()
                                    pcall(function()
                                        topos(plr.HumanoidRootPart.CFrame * CFrame.new((function()
                                            local x, y, z = 0, 3, 0
                                            x = math.random(1, 4); z = math.random(1, 4)
                                            if math.random(1, 2) == 1 then x = x * -1 end
                                            if math.random(1, 2) == 1 then z = z * -1 end
                                            return x, y, z
                                        end)()))
                                    end)
                                until not plr or not plr.Parent or not plr:FindFirstChild("Humanoid") or not plr:FindFirstChild("HumanoidRootPart") or plr.Humanoid.Health <= 0 or workspace.Map["Temple of Time"].FFABorder.Forcefield.Transparency == 1
                            end
                        end
                    else
                        local race_trial_place
                        if races_trial_place[game:GetService("Players").LocalPlayer.Data.Race.Value] then
                            race_trial_place = races_trial_place[game:GetService("Players").LocalPlayer.Data.Race.Value]
                        end
                        if race_trial_place and getdis(race_trial_place.CFrame) < 1500 then
                            if myStatus ~= "in_trail" and myStatus ~= "training" then
                                setMyMainStatus("in_trail")
                            end
                            status("[MAIN " .. myMainIndex .. "] Doing trial")
                            local myrace = game.Players.LocalPlayer.Data.Race.Value
                            if myrace == "Mink" then
                                pcall(function() topos(workspace.Map.MinkTrial.Ceiling.CFrame * CFrame.new(0,-20,0)) end)
                            elseif myrace == "Skypiea" then
                                pcall(function() topos(workspace.Map.SkyTrial.Model.FinishPart.CFrame) end)
                            elseif myrace == "Cyborg" then
                                pcall(function() topos(workspace.Map.CyborgTrial.Floor.CFrame * CFrame.new(0, 500, 0)) end)
                            elseif myrace == "Human" or myrace == "Ghoul" then
                                for i, v in pairs(game.Workspace.Enemies:GetChildren()) do
                                    if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                                        if getdis(v.HumanoidRootPart.CFrame, race_trial_place.CFrame) < 1500 then
                                            repeat wait()
                                                module:eq()
                                                module:haki()
                                                pcall(function() topos(v:FindFirstChild("HumanoidRootPart").CFrame * CFrame.new(0, 30, 0)) end)
                                            until not v or not v:FindFirstChild("HumanoidRootPart") or not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0
                                        end
                                    end
                                end
                            elseif myrace == "Fishman" then
                                for i, v in pairs(workspace.SeaBeasts:GetChildren()) do
                                    pcall(function()
                                        -- Khớp kkv4: Fishman truyền race_trial_place (object), KHÔNG .CFrame
                                        if v:FindFirstChild('Health') and v.Health.Value > 0 and v:FindFirstChild("HumanoidRootPart") and getdis(v.HumanoidRootPart.CFrame, race_trial_place) < 1500 then
                                            repeat wait()
                                                if not game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Sharkman Karate") then
                                                    game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuySharkmanKarate")
                                                end
                                                topos(v.HumanoidRootPart.CFrame * CFrame.new(0, 500, 0))
                                                _G.SHOULDSPAMSKILLS = true
                                            until not v or not v:FindFirstChild('Health') or v.Health.Value <= 0 or not v:FindFirstChild("HumanoidRootPart")
                                            _G.SHOULDSPAMSKILLS = false
                                        end
                                    end)
                                end
                            end
                        else
                            if game:GetService("Players").LocalPlayer.PlayerGui.Main.Timer.Visible == false then
                                local khang
                                repeat wait()
                                    khang = pcall(function()
                                        return getdoor()
                                    end) and getdoor()
                                until khang ~= nil
                                local isNearTemple = getdis(CFrame.new(28310.0234, 14895.1123, 109.456741)) < 3000
                                if isNearTemple then
                                    topos(khang.CFrame)
                                    status("[MAIN " .. myMainIndex .. "] Ready for trialing (đợi đồng bộ ability)")
                                    -- Đứng ở cửa. Ghi checkalready.txt=true + bấm ability đúng starttime do vòng ABILITY SYNC (file) lo.
                                else
                                    -- FIX #3: requestEntrance chỉ nhận Vector3 (bỏ rotation data)
                                    game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(28310.0234, 14895.1123, 109.456741))
                                end
                            end
                        end
                    end
                end
            else
                local roleName = isaccmain[myName] and ("[MAIN " .. myMainIndex .. " as ALLY]") or "[ALLY]"
                local currentMainStatus = currentmain and getMainStatus(currentmain) or ""
                local mainActive = (currentMainStatus == "moon" or currentMainStatus == "in_trail")
                -- Main phụ (main-as-ally) KHÔNG hop theo (giữ như bản gốc); chỉ ally thật mới hop.
                local sameServer, mainJob = true, nil
                if not isaccmain[myName] then
                    sameServer, mainJob = isSameServerAsMain(currentmain)
                end
                if currentmain and mainActive and not sameServer then
                    -- Khác server với main đang up → hop sang server của main (throttle 8s tránh spam)
                    status(roleName .. " Hop sang server main: " .. tostring(currentmain))
                    if mainJob and mainJob ~= "" and mainJob ~= game.JobId then
                        if not _G.lastAllyHop or (tick() - _G.lastAllyHop) > 8 then
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
                        if not workspace.Map:FindFirstChild("Temple of Time") then
                            if game:GetService("ReplicatedStorage").MapStash:FindFirstChild("Temple of Time") then
                                game:GetService("ReplicatedStorage").MapStash["Temple of Time"].Parent = workspace.Map
                            end
                        elseif workspace.Map["Temple of Time"].FFABorder.Forcefield.Transparency == 0 then
                            if not isaccmain[myName] then
                                -- ===== ALLY: AUTO RESET NGAY khi vào khúc kill player =====
                                -- Ally KHÔNG cần kill hết người — reset luôn (stagger theo thứ tự ally)
                                -- để đồng bộ + báo /helpreset cho main. _G.allyKillReset chống reset lặp.
                                status(roleName .. " Kill-player → AUTO RESET (ally)")
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
                                        wait(5)  -- chờ respawn xong mới cho reset lại lần sau
                                        _G.allyKillReset = false
                                    end)
                                end
                            else
                                status(roleName .. " Kill Players After Trial")
                                for plr, i in pairs(getplayers()) do
                                    if plr then
                                        repeat wait()
                                            pcall(function()
                                                topos(plr.HumanoidRootPart.CFrame * CFrame.new((function()
                                                    local x, y, z = 0, 3, 0
                                                    x = math.random(1, 4); z = math.random(1, 4)
                                                    if math.random(1, 2) == 1 then x = x * -1 end
                                                    if math.random(1, 2) == 1 then z = z * -1 end
                                                    return x, y, z
                                                end)()))
                                            end)
                                        until not plr or not plr.Parent or not plr:FindFirstChild("Humanoid") or not plr:FindFirstChild("HumanoidRootPart") or plr.Humanoid.Health <= 0 or workspace.Map["Temple of Time"].FFABorder.Forcefield.Transparency == 1
                                    end
                                end
                                if countplayers() <= 0 then
                                    local isCurrentMain = isaccmain[myName] and myName == currentmain
                                    local isOtherMain = isaccmain[myName] and myName ~= currentmain  -- acc main phụ
                                    if isCurrentMain then
                                        local allies_str = table.concat(getgenv().Config["Allies"] or {}, ",")
                                        if allies_str ~= "" then
                                            status("[MAIN " .. myMainIndex .. "] Waiting for help accs to reset first...")
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
                            local race_trial_place
                            if races_trial_place[game:GetService("Players").LocalPlayer.Data.Race.Value] then
                                race_trial_place = races_trial_place[game:GetService("Players").LocalPlayer.Data.Race.Value]
                            end
                            if race_trial_place and getdis(race_trial_place.CFrame) < 1500 then
                                status(roleName .. " Doing trial")
                                local myrace = game.Players.LocalPlayer.Data.Race.Value
                                if myrace == "Mink" then
                                    pcall(function() topos(workspace.Map.MinkTrial.Ceiling.CFrame * CFrame.new(0,-20,0)) end)
                                elseif myrace == "Skypiea" then
                                    pcall(function() topos(workspace.Map.SkyTrial.Model.FinishPart.CFrame) end)
                                elseif myrace == "Cyborg" then
                                    pcall(function() topos(workspace.Map.CyborgTrial.Floor.CFrame * CFrame.new(0, 500, 0)) end)
                                elseif myrace == "Human" or myrace == "Ghoul" then
                                    for i, v in pairs(game.Workspace.Enemies:GetChildren()) do
                                        if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                                            if getdis(v.HumanoidRootPart.CFrame, race_trial_place.CFrame) < 1500 then
                                                repeat wait()
                                                    module:eq()
                                                    module:haki()
                                                    pcall(function()
                                                        topos(v:FindFirstChild("HumanoidRootPart").CFrame * CFrame.new(0, 30, 0))
                                                    end)
                                                until not v or not v:FindFirstChild("HumanoidRootPart") or not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0
                                            end
                                        end
                                    end
                                elseif myrace == "Fishman" then
                                    for i, v in pairs(workspace.SeaBeasts:GetChildren()) do
                                        pcall(function()
                                            -- Khớp kkv4: Fishman truyền race_trial_place (object), KHÔNG .CFrame
                                            if v:FindFirstChild('Health') and v.Health.Value > 0 and v:FindFirstChild("HumanoidRootPart") and getdis(v.HumanoidRootPart.CFrame, race_trial_place) < 1500 then
                                                repeat wait()
                                                    if not game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("Sharkman Karate") then
                                                        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("BuySharkmanKarate")
                                                    end
                                                    topos(v.HumanoidRootPart.CFrame * CFrame.new(0, 500, 0))
                                                    _G.SHOULDSPAMSKILLS = true
                                                until not v or not v:FindFirstChild('Health') or v.Health.Value <= 0 or not v:FindFirstChild("HumanoidRootPart")
                                                _G.SHOULDSPAMSKILLS = false
                                            end
                                        end)
                                    end
                                end
                            else
                                -- B: bỏ chặn Timer.Visible → ally luôn ra cửa. Giới hạn vòng tìm cửa tránh treo.
                                local khang, tries = nil, 0
                                repeat wait(); khang = getdoor(); tries = tries + 1 until khang ~= nil or tries > 50
                                if khang then
                                    if getdis(khang.CFrame) < 1500 then
                                        topos(khang.CFrame)
                                        status("Ready for trialing (đợi đồng bộ ability)")
                                        -- Đứng giữ vị trí ở cửa (ally đã chọn team → lên cửa làm v4 + đợi lệnh).
                                        -- Ghi checkalready.txt=true + bấm ability đúng starttime do vòng ABILITY SYNC (file) lo.
                                    else
                                        -- FIX #3: requestEntrance chỉ nhận Vector3
                                        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(28310.0234, 14895.1123, 109.456741))
                                    end
                                end
                            end
                        end
                else
                    status(roleName .. " Waiting for current main: " .. tostring(currentmain))
                end
            end
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
                            local cooldown_frame, title_frame = vl:WaitForChild("Cooldown"), vl:WaitForChild("Title")
                            if title_frame.TextColor3 == Color3.new(1, 1, 1) or title_frame.TextColor3 == Color3.fromRGB(255, 255, 255) then
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
--   1) checkalready.txt: mỗi account ghi đúng DÒNG của mình "<Label>:doorandability=<true|false>".
--      true khi đủ CẢ 2: đứng ở cửa (<AT_DOOR_DIST) VÀ CÙNG jobid (cùng server) với main đang turn.
--      Thiếu 1 → ghi false. Main đang-tới-turn tự tạo file nếu chưa có (bỏ qua nếu đã tồn tại).
--   2) Khi CẢ 3 dòng (Main..idx, Ally1, Ally2...) = true → main tạo starttime.txt = GIỜ THỰC Hà Nội + 10s.
--   3) Cả 3 account đọc starttime.txt mỗi 3s. Tới đúng giờ đó (age ∈ [0, window)) thì bấm ActivateAbility 1 lần.
-- starttime ghi "HH:MM:SS" giờ UTC+7 (Hà Nội/Bangkok); so theo giây-trong-ngày → bấm đồng bộ 1 thời điểm.
local ABILITY_FIRE_WINDOW = 6   -- giây — chỉ bấm trong khoảng [start, start+window)
local AT_DOOR_DIST = 150        -- coi như "đứng ở cửa" khi cách Entrance < ngần này (nới nhẹ từ 120)
local START_LEAD   = 10         -- giây — starttime = bây giờ + 10s
local CHECK_FILE   = "checkalready.txt"
local START_FILE   = "starttime.txt"

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
local function distToMyDoor()
    local best = 1e9
    pcall(function()
        local door = getdoor()
        if door then best = math.min(best, getdis(door.CFrame)) end
    end)
    pcall(function()
        local race = game.Players.LocalPlayer.Data.Race.Value
        local cf = BANANA_DOOR_CFRAME[race]
        if cf then best = math.min(best, getdis(cf)) end
    end)
    return best
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

-- Đọc & phân tích checkalready.txt → bảng { Label = true/false }
local function parseCheck()
    local t = {}
    if not (isfile and isfile(CHECK_FILE)) then return t end
    local ok, data = pcall(readfile, CHECK_FILE)
    if not ok or not data then return t end
    for label, val in string.gmatch(data, "(%w+):doorandability=(%w+)") do
        t[label] = (val == "true")
    end
    return t
end

-- Ghi lại toàn bộ bảng ra file (mỗi dòng 1 nhãn, sort cho ổn định)
local function serializeCheck(t)
    local keys = {}
    for k, _ in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    local lines = {}
    for _, k in ipairs(keys) do
        table.insert(lines, k .. ":doorandability=" .. (t[k] and "true" or "false"))
    end
    return table.concat(lines, "\n")
end

-- Read-modify-write: chỉ đụng DÒNG của chính mình, giữ nguyên dòng account khác
local function writeMyCheck(label, cond)
    if not label then return end
    local t = parseCheck()
    t[label] = cond and true or false
    pcall(function() writefile(CHECK_FILE, serializeCheck(t)) end)
end

-- Đủ tất cả nhãn bắt buộc = true?
local function allReady()
    local t = parseCheck()
    local req = requiredLabels()
    if #req == 0 then return false end
    for _, lb in ipairs(req) do
        if t[lb] ~= true then return false end
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

-- Main đang-tới-turn tự tạo checkalready.txt nếu chưa có (bỏ qua nếu đã tồn tại)
if isaccmain[myName] then
    spawn(function()
        if not (isfile and isfile(CHECK_FILE)) then
            pcall(function() writefile(CHECK_FILE, "") end)
        end
    end)
end

-- ===== LOOP GHI: cadence 1s — ghi dòng của mình + (main) chốt starttime khi đủ 3 =====
spawn(function()
    while true do
        pcall(function()
            local label = myAbilityLabel()
            if label then
                -- chỉ true khi đủ CẢ 2: gần door VÀ cùng jobid (cùng server) với main đang turn.
                -- Thiếu 1 trong 2 → ghi false. Ghi liên tục mỗi 1s kể từ khi load script.
                local cond = (distToMyDoor() < AT_DOOR_DIST) and sameServerAsCurrentMain()
                writeMyCheck(label, cond)

                -- Chỉ MAIN đang tới turn mới chốt giờ
                local curName = getCurrentMainBeingUpgraded()
                if curName and myName == curName then
                    local existing = readStart()           -- giây-trong-ngày (Hà Nội) hoặc nil
                    local nowSec = hanoiSecOfDay(serverNow())
                    -- "đã qua cửa sổ" → cho đặt giờ mới. Xử lý wrap qua nửa đêm.
                    local needNew = true
                    if existing then
                        local age = nowSec - existing
                        if age < -43200 then age = age + 86400 end
                        if age <= ABILITY_FIRE_WINDOW then needNew = false end  -- còn pending/đang trong window
                    end
                    if needNew and allReady() then
                        pcall(function()
                            -- starttime = giờ thực Hà Nội hiện tại + 10s, dạng HH:MM:SS
                            writefile(START_FILE, fmtHanoi(serverNow() + START_LEAD))
                        end)
                    end
                end
            end
        end)
        wait(1)
    end
end)

-- ===== LOOP ĐỌC starttime: 3s — mọi account đọc giờ chốt =====
spawn(function()
    while true do
        pcall(function()
            _G.syncStart = readStart()
        end)
        wait(3)
    end
end)

-- ===== LOOP BẤM: 0.25s — tới đúng starttime thì bấm ActivateAbility 1 lần =====
spawn(function()
    while true do
        pcall(function()
            local st = _G.syncStart   -- giây-trong-ngày (Hà Nội) của giờ chốt
            if st and st ~= _G.allyLastFire then
                if distToMyDoor() < AT_DOOR_DIST then
                    local age = hanoiSecOfDay(serverNow()) - st
                    if age < -43200 then age = age + 86400 end   -- wrap qua nửa đêm
                    if age >= 0 and age < ABILITY_FIRE_WINDOW then
                        _G.allyLastFire = st
                        game.ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
                    end
                end
            end
        end)
        wait(0.25)
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
        TPService:TeleportToPlaceInstance(game.PlaceId, _G.jobidinput, LocalPlayer)
    end)
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
        TPService:TeleportToPlaceInstance(game.PlaceId, jobidnow, LocalPlayer)
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

selectTab("Main")

-- intro animation
Panel.Size = UDim2.new(0, 0, 0, 0)
TweenService:Create(Panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = UDim2.new(0, 320, 0, 460)
}):Play()
