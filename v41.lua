repeat
    wait(1)
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

pcall(function()
    local allies_str = table.concat(cleanAllies, ",")
    local mains_str = table.concat(cleanMains, ",")
    local url = BASE_URL .. "/identify?name=" .. myName .. "&allies=" .. allies_str .. "&mains=" .. mains_str
    local data = game.HttpService:JSONDecode(game:HttpGet(url))
    myRole = data.role or "unknown"
    if myRole == "main" then
        myMainIndex = data.index
        isaccmain[myName] = true
        mainIndexOf[myName] = myMainIndex
    end
end)

pcall(function()
    local mainList = game.HttpService:JSONDecode(game:HttpGet(BASE_URL .. "/allmains"))
    for _, v in ipairs(mainList) do
        if v.name and v.name ~= "" then
            isaccmain[v.name] = true
            mainIndexOf[v.name] = v.index
        end
    end
end)

getgenv().Config["Team"] = getgenv().Config["Team"] and (getgenv().Config["Team"] == "Marines" or getgenv().Config["Team"] == "Pirates") and getgenv().Config["Team"] or "Marines"

function setMyMainStatus(statusStr)
    if not myMainIndex then return end
    pcall(function()
        local response = (http_request or http and http.request or request)({
            ["Url"] = BASE_URL .. "/mainstatus?name=" .. myName,
            ["Method"] = "POST",
            ["Headers"] = { ["Content-Type"] = "application/json" },
            ["Body"] = game.HttpService:JSONEncode({ status = statusStr })
        })
    end)
end

function getMainStatus(accName)
    local ok, res = pcall(function()
        return game.HttpService:JSONDecode(game:HttpGet(BASE_URL .. "/mainstatus?name=" .. accName))
    end)
    if ok and res and res["data"] then
        return res["data"]["status"] or "waiting"
    end
    return "waiting"
end

function thuaaa()
    if game:GetService("Players").LocalPlayer.Team then return end
    if getgenv().Config["Team"] == "Marines" or not getgenv().Config["Team"] then
        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("SetTeam", "Marines")
    elseif getgenv().Config["Team"] == "Pirates" then
        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("SetTeam", "Pirates")
    end
end

thuaaa()

local L_207_ = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("ChooseTeam", true)
local L_208_ = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("UIController", true)
if L_207_ and L_207_.Visible then
    repeat
        task.wait(1)
        if L_207_ and L_207_.Visible and L_208_ then
            for L_209_forvar0, L_210_forvar1 in pairs(getgc(true)) do
                if type(L_210_forvar1) == "function" and getfenv(L_210_forvar1).script == L_208_ then
                    local L_211_ = getconstants(L_210_forvar1)
                    pcall(function()
                        if (L_211_[1] == "Pirates" or L_211_[1] == "Marines") and #L_211_ == 1 then
                            if L_211_[1] == getgenv().Config["Team"] then
                                L_210_forvar1(getgenv().Config["Team"])
                            end
                        end
                    end)
                end
            end
        end
    until game:GetService("Players").LocalPlayer.Team
end

local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
-- FIX #7: bọc pcall quanh loadstring module
local module
do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://github.com/noguchihyuga/idk/blob/main/module_bf.lua?raw=true"))()
    end)
    if ok and result then
        module = result
    else
        warn("[KaitunV4] Load module_bf.lua FAILED: " .. tostring(result))
    end
end
local topofgreattree = CFrame.new(3035.15137, 2281.15918, -7325.19189, 0.0284484141, 2.19495124e-08, 0.999595284,
    -3.29094476e-08, 1, -2.10217994e-08, -0.999595284, -3.22980895e-08, 0.0284484141)

function getdoor(vv)
    vv = vv or game:GetService("Players").LocalPlayer.Data.Race.Value
    return workspace.Map["Temple of Time"]:WaitForChild(vv .. "Corridor"):WaitForChild("Door").Entrance
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
            return game.HttpService:JSONDecode(game:HttpGet(BASE_URL .. "/noguchi?name=" .. targetMain))
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
                        return game.HttpService:JSONDecode(game:HttpGet(BASE_URL .. "/noguchi?name=" .. targetMain))
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
            return game.HttpService:JSONDecode(game:HttpGet(BASE_URL .. "/noguchi?name=" .. prevMain))
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
    while wait() do
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
                            local thua = game.HttpService:JSONDecode(game:HttpGet("http://fi11.bot-hosting.net:20758/api/name=fullmoon"))
                            if thua and thua["success"] and thua["data"] then
                                for _, v in pairs(thua["data"]) do
                                    local jobid = v["jobid"]
                                    if jobid and jobid ~= game.JobId and v.player >= 8 then
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
                            pcall(function()
                                (http_request or http and http.request or request)({
                                    ["Url"] = BASE_URL .. "/noguchi?name=" .. myName,
                                    ["Method"] = "POST",
                                    ["Headers"] = { ["Content-Type"] = "application/json" },
                                    ["Body"] = game.HttpService:JSONEncode({ jobid = game.JobId })
                                })
                            end)
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
                                        -- FIX #2: race_trial_place.CFrame (trước truyền object)
                                        if v:FindFirstChild('Health') and v.Health.Value > 0 and v:FindFirstChild("HumanoidRootPart") and getdis(v.HumanoidRootPart.CFrame, race_trial_place.CFrame) < 1500 then
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
                                    status("[MAIN " .. myMainIndex .. "] Ready for trialing")
                                    if myName == currentmain then
                                        if isshouldturnonability() then
                                            local fire_at = gettimeserver() + 0.5
                                            pcall(function()
                                                (http_request or http and http.request or request)({
                                                    ["Url"] = BASE_URL .. "/firesignal",
                                                    ["Method"] = "POST",
                                                    ["Headers"] = { ["Content-Type"] = "application/json" },
                                                    ["Body"] = game.HttpService:JSONEncode({ fire_at = fire_at })
                                                })
                                            end)
                                            wait(0.5)
                                            game.ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
                                        end
                                    end
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
                if not followMainAccount() then
                    status(roleName .. " Waiting for current main: " .. tostring(currentmain))
                else
                    local currentMainStatus = currentmain and getMainStatus(currentmain) or ""
                    if getgenv().Config["VIPServer"] or (isnight() and isfullmoon()) or issobusy or currentMainStatus == "moon" or currentMainStatus == "in_trail" then
                        spawn(checkgear)
                        _G.ShouldSendData = true
                        if not workspace.Map:FindFirstChild("Temple of Time") then
                            if game:GetService("ReplicatedStorage").MapStash:FindFirstChild("Temple of Time") then
                                game:GetService("ReplicatedStorage").MapStash["Temple of Time"].Parent = workspace.Map
                            end
                        elseif workspace.Map["Temple of Time"].FFABorder.Forcefield.Transparency == 0 then
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
                                local isHelpAcc = not isaccmain[myName]  -- acc help thuần
                                local isOtherMain = isaccmain[myName] and myName ~= currentmain  -- acc main phụ

                                if isCurrentMain then
                                    local allies_str = table.concat(getgenv().Config["Allies"] or {}, ",")
                                    if allies_str ~= "" then
                                        status("[MAIN " .. myMainIndex .. "] Waiting for help accs to reset first...")
                                        local timeout = 0
                                        repeat
                                            wait(1)
                                            timeout = timeout + 1
                                            local ok, res = pcall(function()
                                                return game.HttpService:JSONDecode(
                                                    game:HttpGet(BASE_URL .. "/helpreset?allies=" .. allies_str)
                                                )
                                            end)
                                            if ok and res and res.all_done then break end
                                        until timeout >= 25
                                    end
                                    game.Players.LocalPlayer.Character.Humanoid.Health = 0
                                    wait(3)
                                    setMyMainStatus("training")
                                    pcall(function()
                                        (http_request or http and http.request or request)({
                                            ["Url"] = BASE_URL .. "/helpreset/clear",
                                            ["Method"] = "POST",
                                            ["Headers"] = { ["Content-Type"] = "application/json" },
                                            ["Body"] = "{}"
                                        })
                                    end)

                                elseif isHelpAcc or isOtherMain then
                                    spawn(function()
                                        local delay = 2
                                        if isHelpAcc then
                                            for i, name in ipairs(getgenv().Config["Allies"] or {}) do
                                                if name == myName then delay = i * 2 break end
                                            end
                                        else
                                            delay = (#(getgenv().Config["Allies"] or {}) * 2) + 4 + math.random(0, 3)
                                        end
                                        wait(delay)
                                        game.Players.LocalPlayer.Character.Humanoid.Health = 0
                                        wait(1)
                                        pcall(function()
                                            (http_request or http and http.request or request)({
                                                ["Url"] = BASE_URL .. "/helpreset",
                                                ["Method"] = "POST",
                                                ["Headers"] = { ["Content-Type"] = "application/json" },
                                                ["Body"] = game.HttpService:JSONEncode({ name = myName })
                                            })
                                        end)
                                    end)
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
                                            -- FIX #2: race_trial_place.CFrame
                                            if v:FindFirstChild('Health') and v.Health.Value > 0 and v:FindFirstChild("HumanoidRootPart") and getdis(v.HumanoidRootPart.CFrame, race_trial_place.CFrame) < 1500 then
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
                                        khang = getdoor()
                                    until khang ~= nil
                                    if getdis(khang.CFrame) < 1500 then
                                        topos(khang.CFrame)
                                        status("Ready for trialing")
                                        local ok, sig = pcall(function()
                                            return game.HttpService:JSONDecode(game:HttpGet(BASE_URL .. "/firesignal"))
                                        end)
                                        if ok and sig and sig.fire_at then
                                            local now = gettimeserver()
                                            local fire_at = tonumber(sig.fire_at) or 0
                                            if fire_at > 0 and now >= fire_at and (now - fire_at) < 10 then
                                                game.ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
                                            end
                                        end
                                    else
                                        -- FIX #3: requestEntrance chỉ nhận Vector3
                                        game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(28310.0234, 14895.1123, 109.456741))
                                    end
                                end
                            end
                        end
                    else
                        status(roleName .. " Waiting for full moon / leader...")
                    end
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

-- FIX #5: gettimeserver bọc pcall + fallback nếu network fail
function gettimeserver()
    local ok, res = pcall(function()
        return tonumber(game:HttpGet(BASE_URL .. "/timeserver"))
    end)
    if ok and res then return res end
    return math.floor(tick())
end

spawn(function()
    while wait(1) do
        if isaccmain[myName] then
            pcall(function()
                local response = (http_request or http and http.request or request)({
                    ["Url"] = BASE_URL .. "/noguchi?name=" .. myName,
                    ["Method"] = "POST",
                    ["Headers"] = { ["Content-Type"] = "application/json" },
                    ["Body"] = game.HttpService:JSONEncode({ ["jobid"] = game.JobId })
                })
            end)
        end
    end
end)

_G[myName] = true
getgenv().UseSeaUi = true
local Library = loadstring(game:HttpGet("https://github.com/noguchihyuga/idk/blob/main/alchemyui.lua?raw=true"))()
local Window = Library:Window({
    Title = "Kaitun V4",
    Desc = "free",
    Icon = "rbxassetid://88776023850919",
    Config = { Keybind = Enum.KeyCode.RightControl },
    CloseUIButton = { Enabled = true, Text = "On/Off" },
    Theme = "Dark"
})

function toggle(a, b)
    local x, y = pcall(function() return game.HttpService:JSONDecode(readfile("nawy/kaitunv4.json")) end)
    if not x then
        y = {}; if not isfolder("nawy") then makefolder("nawy") end; writefile("nawy/kaitunv4.json", "{}")
    end
    if y[b["Title"]] then b["Value"] = y[b["Title"]] and true or false end
    local oldcallback = b["Callback"]
    local callback = function(v)
        oldcallback(v)
        local m, n = pcall(function() return game.HttpService:JSONDecode(readfile("nawy/kaitunv4.json")) end)
        if not m then
            n = {}; if not isfolder("nawy") then makefolder("nawy") end; writefile("nawy/kaitunv4.json", "{}")
        end
        n[b["Title"]] = v
        writefile("nawy/kaitunv4.json", game.HttpService:JSONEncode(n))
    end
    b["Callback"] = callback
    return a:Toggle(b)
end

function dropdown(a, b)
    local x, y = pcall(function() return game.HttpService:JSONDecode(readfile("nawy/kaitunv4.json")) end)
    if not x then
        y = {}; if not isfolder("nawy") then makefolder("nawy") end; writefile("nawy/kaitunv4.json", "{}")
    end
    if y[b["Title"]] then b["Value"] = y[b["Title"]] or "" end
    local oldcallback = b["Callback"]
    local callback = function(v)
        oldcallback(v)
        local m, n = pcall(function() return game.HttpService:JSONDecode(readfile("nawy/kaitunv4.json")) end)
        if not m then
            n = {}; if not isfolder("nawy") then makefolder("nawy") end; writefile("nawy/kaitunv4.json", "{}")
        end
        n[b["Title"]] = v
        writefile("nawy/kaitunv4.json", game.HttpService:JSONEncode(n))
    end
    b["Callback"] = callback
    return a:Dropdown(b)
end

local main = Window:Tab({ Title = "Main", Icon = "rbxassetid://10620349455" })
local Status = main:Label({ Title = "Status: nothing", Desc = "nothing" })
local DropdownWithOptions = dropdown(main, {
    Title = "Choose Gear",
    Desc = "Main",
    List = { "A-B-B", "A-A-B" },
    Value = "A-B-B",
    Multi = false,
    Callback = function(value) getgenv().Config["Gear"] = value end
})
toggle(main, {
    Title = "Reset After Trial",
    Desc = "Allies",
    Value = false,
    Callback = function(value) getgenv().Config["ResetAfterTrial"] = value end
})
main:Textbox({
    Title = "Input Job id",
    Desc = "",
    Placeholder = "jobid",
    ClearTextOnFocus = true,
    Callback = function(text) _G.jobidinput = text end
})
main:Button({
    Title = "Join Job Id",
    Desc = "",
    Callback = function()
        pcall(function()
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, _G.jobidinput,
                game.Players.LocalPlayer)
        end)
    end
})

local statusTab = Window:Tab({ Title = "Main Status", Icon = "rbxassetid://10620349455" })
local mainStatusLabels = {}
for i, name in ipairs(getgenv().Config["MainAccount"]) do
    mainStatusLabels[name] = statusTab:Label({
        Title = "Main " .. i .. ": " .. name,
        Desc = "loading..."
    })
end
spawn(function()
    while wait(3) do
        for i, name in ipairs(getgenv().Config["MainAccount"]) do
            pcall(function()
                local st = getMainStatus(name)
                if mainStatusLabels[name] then
                    mainStatusLabels[name]:SetDesc("Status: " .. st)
                end
            end)
        end
    end
end)

local acc = Window:Tab({ Title = "Accounts", Icon = "rbxassetid://10620349455" })
spawn(function()
    while wait() do
        if _G.statusnow then
            Status:SetTitle("Status: " .. _G.statusnow)
            Status:SetDesc(_G.statusnow)
        end
    end
end)

function get_data_safe(target_name)
    local success, response = pcall(function()
        return game:HttpGet(BASE_URL .. "/noguchi?name=" .. target_name)
    end)
    if success and response and response ~= "" then
        local data = game.HttpService:JSONDecode(response)
        if data and data.data and data.data.jobid then
            return data.data.jobid
        end
    end
    return "N/A"
end

for idx, vl in pairs(getgenv().Config["Allies"]) do
    local label = acc:Label({ Title = "Account: " .. vl, Desc = "No Update" })
    local jobidnow = "no update"
    local button = acc:Button({
        ["Title"] = "Join to " .. vl,
        Desc = "",
        ["Callback"] = function()
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, jobidnow, game.Players.LocalPlayer)
        end
    })
    spawn(function()
        while wait(5) do
            pcall(function()
                local dataplr = game.HttpService:JSONDecode(game:HttpGet(BASE_URL .. "/noguchi?name=" .. vl))
                local jobid, time = dataplr["data"]["jobid"], dataplr["data"]["time"]
                local t = gettimeserver()
                label:SetDesc(jobid .. " | " .. tostring(t - time) .. "s ago")
                jobidnow = jobid
                local gg = get_data_safe(vl)
                if gg ~= "N/A" then _G.current_target_jobid = gg end
            end)
        end
    end)
end
