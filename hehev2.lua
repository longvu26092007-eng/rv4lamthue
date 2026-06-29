local MeleeData = {
    ["Black Leg"] = "Dark Step Teacher";
    ["Electro"] = "Mad Scientist";
    ["Fishman Karate"] = "Water Kung-fu Teacher";
    ["Dragon Claw"] = "Sabi";
    ["Superhuman"] = "Martial Arts Master";
    ["Death Step"] = "Phoeyu, the Reformed";
    ["Sharkman Karate"] = "Sharkman Teacher";
    ["Electric Claw"] = "Previous Hero";
    ["Dragon Talon"] = "Uzoth";
    ["Godhuman"] = "Ancient Monk";
    ["Sanguine Art"] = "Shafi";
};
getgenv().Settings = getgenv().Settings or {
    ["API"] = {
        --[[
            Only accept this body format:
            {
                ["timestamp"] = 1700000000;
                ["JobId"] = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
                ["PlaceId"] = 7449423635;
            }
        ]]
        ["URL"] = "";
        ["Method"] = "GET";
        ["Headers"] = {
            ["Content-Type"] = "application/json";
        };
        ["Body"] = {
            ["Player"] = "";
            ["PlayerId"] = "";
        };
    };
    ["Focus Melee"] = "Sharkman Karate";
    -- FOCUS WHEN DO SHARK V3
    ["Races"] = { -- bật race nào thì script sẽ check V3 race đó, đủ hết sẽ ghi Completed-RACES
        ["Human"] = true;
        ["Mink"] = true;      
        ["Fishman"] = true;   
        ["Skypiea"] = true;   
        ["Cyborg"] = false;
        ["Ghoul"] = false;
    };
    ["Max Chests"] = 50;
    -- if you collected 50 chests, hop server
    ["Skip Chest Delay"] = 1;
    -- (0.4 - 2)
    ["Black Screen"] = false;
    ["Reset After Collect Chests"] = 10;
    -- if you collected 10 chests, it will reset for safe (anti kick)
    ["Katakuri Progress"] = 300;
    -- 300 monster left
    ["Fragments"] = 5000;
    -- Auto farm fragments until you have 5000 fragments to buy the chip
    ["Chest Tween Speed"] = 325;
    ["Chest Touch Radius"] = 8;
    ["Flower Tween Speed"] = 325;
    ["Flower Touch Radius"] = 8;
}
-- Đổi folder sau khi Completed-RACES.
getgenv().ChangeFolderOnCompleted = getgenv().ChangeFolderOnCompleted ~= false
getgenv().id1 = getgenv().id1 or "........."
getgenv().id2 = getgenv().id2 or "........."
-- id3 optional, không set default.
-- Nếu không dùng thì để getgenv().id3 = nil ở config ngoài.
local SeaMelee = {
    [2] = {"Dragon Claw", "Superhuman", "Death Step", "Sharkman Karate"};
    [3] = {"Electric Claw", "Dragon Talon", "Godhuman", "Sanguine Art"};
}
local function GetMeleeTargetSea(meleeName)
    if type(meleeName) ~= "string" then return 1 end
    for sea, list in pairs(SeaMelee) do
        for _, n in ipairs(list) do
            if n == meleeName then return sea end
        end
    end
    return 1
end
repeat task.wait(0.5) until game:IsLoaded() and time() >= 10
cloneref = cloneref or clonereference or function(x) return x end
isnetworkowner = isnetworkowner or isNetworkOwner or function() return true end
workspace = cloneref(workspace) or cloneref(Workspace) or (getrenv and (getrenv().workspace or getrenv().Workspace)) or cloneref(game:GetService("Workspace"))
PlaceId, JobId = game.PlaceId, game.JobId
getfenv = getfenv or _G or _ENV or shared or function() return {} end
IsOnMobile = false
Services = setmetatable({}, {__index = function(self, name)
    local s, c = pcall(function() return cloneref(game:GetService(name)) end)
    if s then rawset(self, name, c) return c
    else error("Invalid Roblox Service: " .. tostring(name))
    end
end})
COREGUI = Services.CoreGui
RunService = Services.RunService
VirtualUser = Services.VirtualUser
TweenService = Services.TweenService
HttpService = Services.HttpService
Players = Services.Players
ReplicatedStorage = Services.ReplicatedStorage
Lighting = Services.Lighting
CollectionService = Services.CollectionService
UserInputService = Services.UserInputService
VirtualInputManager = Services.VirtualInputManager
ReplicatedFirst = Services.ReplicatedFirst
StarterGui = Services.StarterGui
GuiService = Services.GuiService
TeleportService = Services.TeleportService
NeedSit = false
COMMF_ = ReplicatedStorage:WaitForChild("Remotes") and ReplicatedStorage.Remotes:WaitForChild("CommF_")
LocalPlayer = Players.LocalPlayer
LocalPlayer.CharacterAdded:Connect(function(v)
    Character = v Humanoid = v:WaitForChild("Humanoid")
    HumanoidRootPart = v:WaitForChild("HumanoidRootPart")
end)
if LocalPlayer.Character then
    Character = LocalPlayer.Character
    Humanoid = Character:FindFirstChildWhichIsA("Humanoid") or Character:WaitForChild("Humanoid")
    HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart") or Character:WaitForChild("HumanoidRootPart")
end

StarterGui:SetCore("SendNotification", {Title = "Executed", Text = "Loading… Please wait", Subtext = "Kaitun Races By Centramil", Duration = 5})
if not game:IsLoaded() or workspace.DistributedGameTime <= 10 then
    local WFGTL = COREGUI:FindFirstChild("WFGTL") or Instance.new("Hint", COREGUI)
    WFGTL.Text = "Just a moment... Waiting while the game loads - This won't take long!"
    task.wait(10 - workspace.DistributedGameTime)
    WFGTL:Destroy()
end
if not COMMF_ then repeat task.wait(1) until COMMF_ end
task.spawn(function()
    xpcall(function()
        if not LocalPlayer.Team then
            if LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen") then
                repeat task.wait(1) until not LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen")
            end
            xpcall(function() COMMF_:InvokeServer("SetTeam", "Pirates")
            end, function() firesignal(LocalPlayer.PlayerGui["Main (minimal)"].ChooseTeam.Container.Pirates) end)
            task.wait(2)
        end
    end, function(err) warn("????", err) end)
end)
repeat task.wait(2) until Character and Character:FindFirstChild("HumanoidRootPart") and Character:FindFirstChildWhichIsA("Humanoid") and Character:IsDescendantOf(workspace.Characters) 
local API = function(xnorquest, bool) local GBSettings = getgenv().Settings
    local URL = GBSettings.URL_API
    local limitTime = GBSettings.Timestamp
    if URL ~= "" then
        xpcall(function()
            while true do
                local res = request({Url = GBSettings.URL_API, Method = GBSettings.Method, Headers = GBSettings.Headers, Body = GBSettings.Body})
                local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
                if not ok or not data or not data.JobIds or not data.Amount then print("fetch = false") return end
                if type(data.Amount) ~= "number" or data.Amount <= 0 then print("Amount <= 0") return end
                print("fetch = true")
                local now = os.time()
                local valid = {}
                for i = #data.JobIds, 1, -1 do
                    local v = data.JobIds[i]
                    if typeof(v.Players) == "number" and typeof(v.name) == "string" and typeof(v.timestamp) == "number" and v.name == xnorquest and (now - v.timestamp) <= limitTime
                    then table.insert(valid, v)
                    end
                end
                if #valid == 0 then return end
                local pikabo = valid[math.random(1, #valid)]
                print("JobId:", pikabo.jobid)
                print("PlaceId:", pikabo.placeid)
                TeleportService:TeleportToPlaceInstance(pikabo.placeid, pikabo.jobid, LocalPlayer)
                task.wait(5) if bool == "BREAK" then return end
            end
        end, function(err) warn("API ERROR: ", err) end)
    end
end
APIorHOP = function(x, c)
    local URL = getgenv().Settings.URL_API
    if not URL or URL == "" then HopServer(10)
    else API(x, c)
    end
end

local KaitunGuiStatusLabel
local KaitunGuiBlur
local guiVisible = true

do
    local plr = LocalPlayer

    pcall(function()
        if COREGUI:FindFirstChild("KaitunRacesBF") then
            COREGUI.KaitunRacesBF:Destroy()
        end
        if COREGUI:FindFirstChild("Status") then
            COREGUI.Status:Destroy()
        end
        if COREGUI:FindFirstChild("KaitunRacesBtn") then
            COREGUI.KaitunRacesBtn:Destroy()
        end
        local oldBlur = Lighting:FindFirstChild("CameraBlur")
        if oldBlur then
            oldBlur:Destroy()
        end
    end)

    KaitunGuiBlur = Instance.new("BlurEffect")
    KaitunGuiBlur.Name = "CameraBlur"
    KaitunGuiBlur.Size = 24
    KaitunGuiBlur.Parent = Lighting

    local CoinCard_1 = Instance.new("ScreenGui")
    local DropShadowHolder_1 = Instance.new("Frame")
    local Main_1 = Instance.new("Frame")
    local UICorner_1 = Instance.new("UICorner")
    local UIStroke_1 = Instance.new("UIStroke")
    local Divider_1 = Instance.new("Frame")
    local CharacterLabel = Instance.new("TextLabel")
    local LevelLabel_1 = Instance.new("TextLabel")
    local RaceLabel_1 = Instance.new("TextLabel")
    local BeliLabel_1 = Instance.new("TextLabel")
    local FragLabel_1 = Instance.new("TextLabel")
    local Top_1 = Instance.new("TextLabel")
    local UIGradient_1 = Instance.new("UIGradient")
    local UnderStats_1 = Instance.new("TextLabel")
    local UIGradient_2 = Instance.new("UIGradient")
    local UnderRace_1 = Instance.new("TextLabel")
    local UIGradient_3 = Instance.new("UIGradient")
    local RaceContainer = Instance.new("Frame")
    local DropShadow_1 = Instance.new("ImageLabel")

    CoinCard_1.Name = "KaitunRacesBF"
    CoinCard_1.Parent = COREGUI
    CoinCard_1.ResetOnSpawn = false
    CoinCard_1.DisplayOrder = 20

    DropShadowHolder_1.AnchorPoint = Vector2.new(0.5, 0.5)
    DropShadowHolder_1.BackgroundColor3 = Color3.fromRGB(163, 163, 163)
    DropShadowHolder_1.BackgroundTransparency = 1
    DropShadowHolder_1.Name = "DropShadowHolder"
    DropShadowHolder_1.Parent = CoinCard_1
    DropShadowHolder_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    DropShadowHolder_1.Size = UDim2.new(0, 620, 0, 390)
    DropShadowHolder_1.ZIndex = 1

    Main_1.AnchorPoint = Vector2.new(0.5, 0.5)
    Main_1.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Main_1.BackgroundTransparency = 0.5
    Main_1.Name = "Main"
    Main_1.Parent = DropShadowHolder_1
    Main_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    Main_1.Size = UDim2.new(1, -47, 1, -47)

    UICorner_1.CornerRadius = UDim.new(0, 8)
    UICorner_1.Parent = Main_1

    UIStroke_1.Color = Color3.fromRGB(255, 80, 80)
    UIStroke_1.Thickness = 2.5
    UIStroke_1.Parent = Main_1

    Divider_1.BorderSizePixel = 0
    Divider_1.BackgroundColor3 = Color3.fromRGB(210, 210, 210)
    Divider_1.Name = "Divider"
    Divider_1.Parent = Main_1
    Divider_1.Position = UDim2.new(0.05, 0, 0.205, 0)
    Divider_1.Size = UDim2.new(0.90, 0, 0, 2)

    Top_1.BackgroundTransparency = 1
    Top_1.Name = "Top"
    Top_1.Parent = Main_1
    Top_1.AnchorPoint = Vector2.new(0.5, 0)
    Top_1.Position = UDim2.new(0.5, 0, 0.055, 0)
    Top_1.Size = UDim2.new(0.8, 0, 0, 24)
    Top_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    Top_1.Text = "Kaitun Races BF"
    Top_1.TextColor3 = Color3.fromRGB(255, 80, 80)
    Top_1.TextSize = 22
    Top_1.TextXAlignment = Enum.TextXAlignment.Center

    UIGradient_1.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80))
    }
    UIGradient_1.Parent = Top_1

    UnderStats_1.BackgroundTransparency = 1
    UnderStats_1.Name = "UnderStats"
    UnderStats_1.Parent = Main_1
    UnderStats_1.AnchorPoint = Vector2.new(0.5, 0)
    UnderStats_1.Position = UDim2.new(0.5, 0, 0.225, 2)
    UnderStats_1.Size = UDim2.new(0.4, 0, 0, 18)
    UnderStats_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    UnderStats_1.Text = "Account Stats"
    UnderStats_1.TextColor3 = Color3.fromRGB(255, 255, 255)
    UnderStats_1.TextSize = 16
    UnderStats_1.TextXAlignment = Enum.TextXAlignment.Center

    UIGradient_2.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80))
    }
    UIGradient_2.Parent = UnderStats_1

    local function setupCenterStat(lbl, yPos)
        lbl.BackgroundTransparency = 1
        lbl.Parent = Main_1
        lbl.AnchorPoint = Vector2.new(0.5, 0)
        lbl.Position = UDim2.new(0.5, 0, yPos, 0)
        lbl.Size = UDim2.new(0.82, 0, 0, 18)
        lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        lbl.TextSize = 16
        lbl.TextXAlignment = Enum.TextXAlignment.Center
        lbl.RichText = true
    end

    CharacterLabel.Name = "CharacterLabel"
    setupCenterStat(CharacterLabel, 0.285)
    CharacterLabel.Text = "Character: N/A"

    LevelLabel_1.Name = "LevelLabel"
    setupCenterStat(LevelLabel_1, 0.355)
    LevelLabel_1.Text = ""

    RaceLabel_1.Name = "RaceLabel"
    setupCenterStat(RaceLabel_1, 0.425)
    RaceLabel_1.Text = "Race: N/A"

    BeliLabel_1.Name = "BeliLabel"
    setupCenterStat(BeliLabel_1, 0.495)
    BeliLabel_1.Text = "Beli: N/A"

    FragLabel_1.Name = "FragLabel"
    setupCenterStat(FragLabel_1, 0.565)
    FragLabel_1.Text = "Frag: N/A"

    UnderRace_1.BackgroundTransparency = 1
    UnderRace_1.Name = "UnderRace"
    UnderRace_1.Parent = Main_1
    UnderRace_1.AnchorPoint = Vector2.new(0.5, 0)
    UnderRace_1.Position = UDim2.new(0.5, 0, 0.67, 0)
    UnderRace_1.Size = UDim2.new(0.45, 0, 0, 18)
    UnderRace_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    UnderRace_1.Text = "Race Progress (V3)"
    UnderRace_1.TextColor3 = Color3.fromRGB(255, 255, 255)
    UnderRace_1.TextSize = 16
    UnderRace_1.TextXAlignment = Enum.TextXAlignment.Center

    UIGradient_3.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80))
    }
    UIGradient_3.Parent = UnderRace_1

    RaceContainer.Name = "RaceContainer"
    RaceContainer.Parent = Main_1
    RaceContainer.BackgroundTransparency = 1
    RaceContainer.AnchorPoint = Vector2.new(0.5, 0)
    RaceContainer.Position = UDim2.new(0.5, 0, 0.735, 0)
    RaceContainer.Size = UDim2.new(0.88, 0, 0, 90)

    local raceGrid = Instance.new("UIGridLayout")
    raceGrid.Parent = RaceContainer
    raceGrid.CellSize = UDim2.new(0, 150, 0, 24)
    raceGrid.CellPadding = UDim2.new(0, 12, 0, 6)
    raceGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    raceGrid.VerticalAlignment = Enum.VerticalAlignment.Top
    raceGrid.SortOrder = Enum.SortOrder.LayoutOrder

    DropShadow_1.AnchorPoint = Vector2.new(0.5, 0.5)
    DropShadow_1.BackgroundTransparency = 1
    DropShadow_1.Name = "DropShadow"
    DropShadow_1.Parent = DropShadowHolder_1
    DropShadow_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    DropShadow_1.Size = UDim2.new(1, 47, 1, 47)
    DropShadow_1.ZIndex = 0
    DropShadow_1.Image = "rbxassetid://6015897843"
    DropShadow_1.ImageTransparency = 0.25
    DropShadow_1.ImageColor3 = Color3.fromRGB(0, 0, 0)

    local Status = Instance.new("ScreenGui")
    Status.Name = "Status"
    Status.Parent = COREGUI
    Status.ResetOnSpawn = false
    Status.DisplayOrder = 10

    local DropShadow2Holder2_1 = Instance.new("Frame")
    DropShadow2Holder2_1.Name = "DropShadow2Holder2"
    DropShadow2Holder2_1.Parent = Status
    DropShadow2Holder2_1.AnchorPoint = Vector2.new(0.5, 0.5)
    DropShadow2Holder2_1.BackgroundTransparency = 1
    DropShadow2Holder2_1.Position = UDim2.new(0.5, 0, 0.05, 0)
    DropShadow2Holder2_1.Size = UDim2.new(0, 320, 0, 55)

    local DropShadow2_1 = Instance.new("ImageLabel")
    DropShadow2_1.Name = "DropShadow2"
    DropShadow2_1.Parent = DropShadow2Holder2_1
    DropShadow2_1.AnchorPoint = Vector2.new(0.5, 0.5)
    DropShadow2_1.BackgroundTransparency = 1
    DropShadow2_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    DropShadow2_1.Size = UDim2.new(1, 47, 1, 47)
    DropShadow2_1.Image = "rbxassetid://6015897843"
    DropShadow2_1.ImageColor3 = Color3.fromRGB(0, 0, 0)
    DropShadow2_1.ImageTransparency = 0.5

    local MainStatus = Instance.new("Frame")
    MainStatus.Name = "Main"
    MainStatus.Parent = DropShadow2_1
    MainStatus.AnchorPoint = Vector2.new(0.5, 0.5)
    MainStatus.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    MainStatus.BackgroundTransparency = 0.5
    MainStatus.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainStatus.Size = UDim2.new(1, -50, 1, -40)

    local UIStrokeStatus = Instance.new("UIStroke")
    UIStrokeStatus.Parent = MainStatus
    UIStrokeStatus.Color = Color3.fromRGB(233, 80, 80)
    UIStrokeStatus.Thickness = 2.5

    local UICornerStatus = Instance.new("UICorner")
    UICornerStatus.Parent = MainStatus
    UICornerStatus.CornerRadius = UDim.new(0, 6)

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Name = "StatusLabel"
    StatusLabel.Parent = MainStatus
    StatusLabel.AnchorPoint = Vector2.new(0.5, 0)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Position = UDim2.new(0.5, 0, 0.06, 0)
    StatusLabel.Size = UDim2.new(1, -20, 0, 34)
    StatusLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    StatusLabel.Text = "Status: nil"
    StatusLabel.TextColor3 = Color3.fromRGB(233, 80, 80)
    StatusLabel.TextSize = 20
    StatusLabel.TextWrapped = true
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Center

    KaitunGuiStatusLabel = StatusLabel

    local raceTitles = {
        ["Full Power"] = "Human V3",
        ["Godspeed"] = "Rabbit V3",
        ["Warrior of the Sea"] = "Shark V3",
        ["Perfect Being"] = "Angel V3",
        ["Hell Hound"] = "Ghoul V3",
        ["War Machine"] = "Cyborg V3",
    }

    local allV3 = {
        "Human V3",
        "Rabbit V3",
        "Shark V3",
        "Angel V3",
        "Ghoul V3",
        "Cyborg V3"
    }

    local raceColors = {
        ["Angel V3"] = Color3.fromRGB(255, 204, 0),
        ["Human V3"] = Color3.fromRGB(255, 50, 50),
        ["Shark V3"] = Color3.fromRGB(0, 168, 255),
        ["Cyborg V3"] = Color3.fromRGB(204, 0, 255),
        ["Ghoul V3"] = Color3.fromRGB(160, 255, 80),
        ["Rabbit V3"] = Color3.fromRGB(0, 255, 60),
    }

    local raceLabels = {}

    local function GetUnlockedRaces()
        local unlockedV3 = {}
        local added = {}

        local function addRace(raceVer)
            if not raceVer or added[raceVer] or not string.find(raceVer, "V3") then
                return
            end
            added[raceVer] = true
            table.insert(unlockedV3, raceVer)
        end

        local ok, titles = pcall(function()
            return ReplicatedStorage.Remotes.CommF_:InvokeServer("getTitles")
        end)

        if ok and type(titles) == "table" then
            for _, t in pairs(titles) do
                local name = t.Name or t[1]
                local unlockedValue = nil

                if t.Unlocked ~= nil then
                    unlockedValue = t.Unlocked
                elseif t.unlocked ~= nil then
                    unlockedValue = t.unlocked
                else
                    unlockedValue = t[2]
                end

                if name and raceTitles[name] and IsTitleUnlockedValue(unlockedValue) then
                    addRace(raceTitles[name])
                end
            end
        end

        local titlesFolder = plr:FindFirstChild("Titles")
        if titlesFolder then
            for _, inst in ipairs(titlesFolder:GetChildren()) do
                if raceTitles[inst.Name] then
                    if IsTitleUnlockedValue(inst.Value) then
                        addRace(raceTitles[inst.Name])
                    end
                end
            end
        end

        return unlockedV3
    end

    local function createRaceLabel(raceName, order)
        local lbl = Instance.new("TextLabel")
        lbl.Name = raceName:gsub("%s+", "")
        lbl.Parent = RaceContainer
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(0, 150, 0, 24)
        lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        lbl.TextSize = 16
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Center
        lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        lbl.LayoutOrder = order
        lbl.RichText = true
        return lbl
    end

    for i, race in ipairs(allV3) do
        raceLabels[race] = createRaceLabel(race, i)
    end

    task.spawn(function()
        while task.wait(0.4) do
            pcall(function()
                if plr:FindFirstChild("Data") then
                    if plr.Data:FindFirstChild("Beli") then
                        BeliLabel_1.Text = "Beli: " .. tostring(plr.Data.Beli.Value)
                    end
                    if plr.Data:FindFirstChild("Fragments") then
                        FragLabel_1.Text = "Frag: " .. tostring(plr.Data.Fragments.Value)
                    end
                    if plr.Data:FindFirstChild("Race") then
                        RaceLabel_1.Text = "Race: " .. tostring(plr.Data.Race.Value)
                    end
                end

                CharacterLabel.Text = '<font color="#FFFFFF">Character: ' .. tostring(plr.Name) .. '</font>'
                LevelLabel_1.Text = ""

                local unlockedV3 = GetUnlockedRaces()

                for _, race in ipairs(allV3) do
                    local has = table.find(unlockedV3, race) ~= nil
                    local dot = has and "🟢" or "🔴"
                    local color = raceColors[race] or Color3.fromRGB(255, 255, 255)
                    local hex = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
                    raceLabels[race].Text = dot .. ' <font color="' .. hex .. '">' .. race .. '</font>'
                end
            end)
        end
    end)
end

function SetStatus(text)
    pcall(function()
        if KaitunGuiStatusLabel then
            KaitunGuiStatusLabel.Text = "Status: " .. tostring(text)
        end
    end)
end

pcall(function() LocalPlayer.PlayerGui:FindFirstChild("Blank"):Destroy() end)
local BlankScreen = LocalPlayer.PlayerGui:FindFirstChild("Blank") or Instance.new("ScreenGui", LocalPlayer.PlayerGui)
BlankScreen.Name = "Blank" BlankScreen.ResetOnSpawn = false BlankScreen.DisplayOrder = -math.huge BlankScreen.IgnoreGuiInset = true

local Black = BlankScreen:FindFirstChild("Black Screen") or Instance.new("Frame", BlankScreen)
Black.Name = "Black Screen"
Black.Size = UDim2.new(1, 0, 1, 0)
Black.BackgroundColor3 = Color3.new(0, 0, 0)
Black.ZIndex = -math.huge
Black.Visible = getgenv().Settings["Black Screen"]

RunService:Set3dRenderingEnabled(not Black.Visible)

local label = Instance.new("TextLabel", BlankScreen)
label.Name = "CenteredLabel"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.new(0.5, 0, 0.5, 0)
label.Size = UDim2.new(0.6, 0, 0.15, 0)
label.Text = ""
label.Visible = false
label.TextScaled = true;
label.TextWrapped = true;
label.TextXAlignment = Enum.TextXAlignment.Center;
label.TextYAlignment = Enum.TextYAlignment.Center;
label.BackgroundTransparency = 1;
label.Font = Enum.Font.GothamSemibold;
label.TextSize = 48;
label.TextColor3 = Color3.fromRGB(255, 255, 255)

local leftButton = Instance.new("TextButton", BlankScreen)
leftButton.Name = "LeftButton"
leftButton.AnchorPoint = Vector2.new(0, 0)
leftButton.Position = UDim2.new(0, 20, 0, 90)
leftButton.Size = UDim2.new(0, 90, 0, 38)
leftButton.Text = "ON"
leftButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
leftButton.TextColor3 = Color3.fromRGB(255, 80, 80)
leftButton.TextSize = 22
leftButton.Font = Enum.Font.GothamBlack
leftButton.TextStrokeTransparency = 0.1
leftButton.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
leftButton.AutoButtonColor = true
leftButton.Active = true
leftButton.Draggable = true

local leftButtonCorner = Instance.new("UICorner")
leftButtonCorner.CornerRadius = UDim.new(0, 8)
leftButtonCorner.Parent = leftButton

local leftButtonStroke = Instance.new("UIStroke")
leftButtonStroke.Color = Color3.fromRGB(255, 80, 80)
leftButtonStroke.Thickness = 2
leftButtonStroke.Parent = leftButton

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.F4 then
        Black.Visible = not Black.Visible
        RunService:Set3dRenderingEnabled(not Black.Visible)
        
        StarterGui:SetCore("SendNotification", {
            Title = "Black Screen",
            Text = Black.Visible and "Đã BẬT màn hình đen (Tắt Render 3D)" or "Đã TẮT màn hình đen (Bật Render 3D)",
            Duration = 2
        })
    end
end)

leftButton.MouseButton1Click:Connect(function()
    guiVisible = not guiVisible
    leftButton.Text = guiVisible and "ON" or "OFF"
    leftButton.TextColor3 = guiVisible and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 80, 80)
    leftButtonStroke.Color = guiVisible and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 80, 80)

    local kaitunGui = COREGUI:FindFirstChild("KaitunRacesBF")
    if kaitunGui then
        kaitunGui.Enabled = guiVisible
    end

    local statusGui = COREGUI:FindFirstChild("Status")
    if statusGui then
        statusGui.Enabled = guiVisible
    end

    if KaitunGuiBlur then
        KaitunGuiBlur.Size = guiVisible and 24 or 0
    end
end)

local function SetText(newText)
    local text = tostring(newText)
    SetStatus(text)
end
-- Đã bỏ lưu tiến độ race bằng file.
-- Tiến độ V3 sẽ check trực tiếp bằng title/getTitles.
function CheckSea(v: number) return v == tonumber(workspace:GetAttribute("MAP"):match("%d+")) end
local remoteAttack, idremote
local seed = ReplicatedStorage.Modules.Net.seed:InvokeServer()
task.spawn((function() for _, v in next, ({ReplicatedStorage.Util, ReplicatedStorage.Common, ReplicatedStorage.Remotes, ReplicatedStorage.Assets, ReplicatedStorage.FX}) do
    for _, n in next, v:GetChildren() do if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remoteAttack, idremote = n, n:GetAttribute("Id") end
    end v.ChildAdded:Connect(function(n) if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remoteAttack, idremote = n, n:GetAttribute("Id")
    end end) end
end))
CheckLocation = (function(v)return LocalPlayer:GetAttribute("CurrentLocation") == v end)
CheckMap = (function(v) return workspace.Map:FindFirstChild(v) or false end)
CheckTool = (function(v)
    for _, x in next, {LocalPlayer.Backpack, Character} do
    for _, v2 in next, x:GetChildren() do if v2:IsA("Tool") and (v2.Name == v or v2.Name:find(v)) then return true end
    end end return false
end)
CheckMaterial = (function(x)
    for _, v in pairs(COMMF_:InvokeServer("getInventory")) do if v.Type == "Material" then if v.Name == x then return v.Count end end
    end return 0
end)
CheckInventory = (function(...)
    for _, v in pairs(COMMF_:InvokeServer("getInventory")) do
    for _, n in next, {...} do if v.Name == n then return true end end
    end return false
end)

IsDied = function(v)
    local ok, r = xpcall(function()
        if not v then return true end
        local h = v:FindFirstChild("Humanoid") or v:FindFirstChildWhichIsA("Humanoid")
        local hrp = v:FindFirstChild("HumanoidRootPart")
        if not h or not hrp then return true end
        if h:IsA("Humanoid") then return h.Health <= 0 end
        if h:IsA("ValueBase") and type(h.Value) == "number" then return h.Value <= 0 end
        return false
    end, function() return false end)
    return ok and r or false
end

KillAura = (function(vName)
    pcall(function() setscriptable(LocalPlayer, "SimulationRadius", true) end)
    pcall(function() sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge) end)
    for _, v in next, workspace.Enemies:GetChildren() do
        pcall(function()
            local hrp = v:FindFirstChild("HumanoidRootPart") or false
            if hrp and HumanoidRootPart and (hrp.Position - HumanoidRootPart.Position).Magnitude <= 1250 then
                local cond = (vName and v.Name == vName) or not vName
                if cond then
                    v:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Dead)
                end
            end
        end)
    end
end)
CheckMoon = (function()
    local tex =
        (CheckSea(1) or CheckSea(3)) and ((Lighting:FindFirstChild("Sky") and Lighting.Sky.MoonTextureId)
        or (Lighting:FindFirstChild("Space_Skybox") and Lighting.Space_Skybox.MoonTextureId))
        or (CheckSea(2) and Lighting:FindFirstChild("FantasySky") and Lighting.FantasySky.MoonTextureId)
        or ""
    tex = tex:gsub("rbxassetid://", "http://www.roblox.com/asset/?id=")
    return ({
        ["http://www.roblox.com/asset/?id=15493317929"] = "Blue Moon";
        ["http://www.roblox.com/asset/?id=9709149431"] = "8/8";
        ["http://www.roblox.com/asset/?id=9709149052"] = "7/8";
        ["http://www.roblox.com/asset/?id=9709143733"] = "6/8";
        ["http://www.roblox.com/asset/?id=9709150401"] = "5/8";
        ["http://www.roblox.com/asset/?id=9709135895"] = "4/8";
        ["http://www.roblox.com/asset/?id=9709150086"] = "2/8";
        ["http://www.roblox.com/asset/?id=9709139597"] = "1/8";
        ["http://www.roblox.com/asset/?id=9709149680"] = "0/8";
})[tex] or "nil"
end)
CheckMonster = (function(...) local args = {...}
    local v2 = {workspace.Enemies, ReplicatedStorage}
    for i = 1, #args do local n = args[i]
        local m = workspace.Enemies:FindFirstChild(n) or ReplicatedStorage:FindFirstChild(n)
        if m and m:IsA("Model") and m.Name ~= "Blank Buddy" then
            local h = m:FindFirstChildWhichIsA("Humanoid") local r = m:FindFirstChild("HumanoidRootPart")
            if h and r and not IsDied(m) then return m end
        end
    end
    for c = 1, #v2 do local container = v2[c] local ms = container:GetChildren()
        for m = 1, #ms do local m = ms[m] local h = m:FindFirstChildWhichIsA("Humanoid")
            local r = m:FindFirstChild("HumanoidRootPart")
            if m:IsA("Model") and h and r and not IsDied(m) and m.Name ~= "Blank Buddy" then
                for i = 1, #args do local n = args[i]
                    if m.Name == n or m.Name:lower():find(n:lower()) then
                        return m
                    end
                end
            end
        end
    end
    return false
end)
local lastEquip = tick()
EquipWeapon = (function(v)
    if tick() - lastEquip <= 0.2 then return end
    lastEquip = tick()
    if not Character then return end
    local tool = Character:FindFirstChildWhichIsA("Tool")
    if tool and (tool.ToolTip and tool.ToolTip == v) then return end
    for _, x in next, LocalPlayer.Backpack:GetChildren() do
        if x:IsA("Tool") and x.ToolTip == v then
            Humanoid:EquipTool(x)
            return
        end
    end
end)
function GetPosition(v)
    if not v then return nil
    elseif typeof(v) == "Vector3" then return v
    elseif typeof(v) == "CFrame" then return v.Position
    elseif v:IsA("BasePart") then return v.Position
    elseif v:IsA("Player") then
        local c = v.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        return hrp and hrp.Position
    elseif typeof(v) == "Instance" then
        local hrp = v:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp.Position end
        local bp = v:FindFirstChildWhichIsA("BasePart")
        if bp then return bp.Position end
        if v.WorldPivot then return v.WorldPivot.Position end
    end
    return nil
end
local function getCFrame(v)
    if not v then return nil end
    if typeof(v) == "CFrame" then return v end
    if typeof(v) == "Vector3" then return CFrame.new(v) end
    if typeof(v) ~= "Instance" then return end
    if v:IsA("BasePart") then return v.CFrame end
    if v:IsA("Model") then
        if v.GetPivot then return v:GetPivot() end
        local root = v.PrimaryPart or v:FindFirstChild("HumanoidRootPart")
        if root then return root.CFrame end
    end
    if v:IsA("CFrameValue") then return v.Value end
    if v:IsA("Vector3Value") then return CFrame.new(v.Value) end
end
GetCFrameByNPC = function(x)
    local npc = workspace.NPCs:FindFirstChild(x) or ReplicatedStorage.NPCs:FindFirstChild(x)
    if npc and npc:IsA("Model") then
        return GetPosition(npc), CheckDistance(npc)
    end
    return nil, math.huge
end
GetNPCMelee = function(xn)
    return (type(xn)=="string" and MeleeData[xn] and (function(n)
        return (function(p) return p and {Name = n, Position = p} end)(GetCFrameByNPC(n))
    end)(MeleeData[xn])) or nil
end
local lastCallFA = tick()
FastAttack = (function(x)
    if not HumanoidRootPart or not Character:FindFirstChildWhichIsA("Humanoid") or Character.Humanoid.Health <= 0 or not Character:FindFirstChildWhichIsA("Tool") then return end
    local FAD = 0.01 -- throttle
    if FAD ~= 0 and tick() - lastCallFA <= FAD then return end
    local t = {}
    for _, u in next, {workspace.Characters, workspace.Enemies} do
        for _, e in next, u:GetChildren() do
            local h = e:FindFirstChildWhichIsA("Humanoid") local hrp = e:FindFirstChild("HumanoidRootPart")
            if e ~= Character and (x and e.Name == x or not x) and h and hrp and not IsDied(e) and (hrp.Position - HumanoidRootPart.Position).Magnitude <= 65 then t[#t + 1] = e end
        end
    end
    local n = ReplicatedStorage.Modules.Net
    local h = {[2] = {}}
    local last
    for i = 1, #t do local v = t[i]
        local part = v:FindFirstChild("Head") or v:FindFirstChild("HumanoidRootPart")
        if not h[1] then h[1] = part end
        h[2][#h[2] + 1] = {v, part} last = v
    end
    n:FindFirstChild("RE/RegisterAttack"):FireServer()
    n:FindFirstChild("RE/RegisterHit"):FireServer(unpack(h))
    cloneref(remoteAttack):FireServer(string.gsub("RE/RegisterHit", ".",function(c)
        return string.char(bit32.bxor(string.byte(c), math.floor(workspace:GetServerTimeNow()/10%10)+1))
    end), bit32.bxor(idremote+909090, seed*2), unpack(h))
    lastCallFA = tick()
end)

local lastHop, inHopPP = tick(), false
function IfTableHaveIndex(j)
    for _ in j do
        return true
    end
end
local LastServersDataPulled, CachedServers
function GetServers()
    if LastServersDataPulled then
        if os.time() - LastServersDataPulled < 60 then
            return CachedServers
        end
    end

    for i = 1, 100, 1 do
        local data = game:GetService("ReplicatedStorage"):WaitForChild("__ServerBrowser"):InvokeServer(i)
        if IfTableHaveIndex(data) then
            LastServersDataPulled = os.time()
            CachedServers = data
            return data
        end
    end
end
HopServer = function(Reason, MaxPlayers, ForcedRegion)
    local Servers = GetServers()
    local ArrayServers = {}
    MaxPlayers = MaxPlayers or 5
    for i, v in Servers do
        if v.Count <= MaxPlayers then
            table.insert(ArrayServers, {
                JobId = i,
                Players = v.Count,
                LastUpdate = v.__LastUpdate,
                Region = v.Region
            })
        end
    end
    print(#ArrayServers, 'servers received')
    local ServerData
    for i = 1, #ArrayServers do
        while task.wait() do
            local Index = math.random(1, #ArrayServers)
            ServerData = ArrayServers[Index]
            if ServerData then
                if not ForcedRegion or ServerData.Regoin == ForcedRegion then
                    print("Found Server:", ServerData.JobId, 'Player Count:', ServerData.Players, "Region:",
                        ServerData.Region)
                    break
                end
            end
        end
        print('Teleporting to', ServerData.JobId, '...')
        ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer('teleport', ServerData.JobId)
    end
end
CheckLocation = (function(v) return LocalPlayer:GetAttribute("CurrentLocation") == v end)
CheckDistance = function(a, b) b = b or Character
    local pa, pb = GetPosition(a), GetPosition(b)
    if pa and pb then return (pa - pb).Magnitude end
    return math.huge
end
local function ExitTheChar()
    local Humanoid = game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")

    if Humanoid and Humanoid.Sit then
        repeat task.wait()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            task.wait()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        until not game.Players.LocalPlayer.Character:FindFirstChild("Humanoid").Sit
    end
end
local connection, tween, pathPart, isTweening = nil, nil, nil, false
function Tween(targetCFrame: CFrame | boolean, target: CFrame)
    if not Character.Humanoid or Character.Humanoid.Health <= 0 then
        pcall(function() workspace.TweenGhost:Destroy() end)
        connection, tween, pathPart, isTweening = nil, nil, nil, false
        return
    end
    if targetCFrame == false then
        if tween then pcall(function() tween:Cancel() end) tween = nil end
        if connection then connection:Disconnect() connection = nil end
        if pathPart then pathPart:Destroy() pathPart = nil end
        isTweening = false
        return
    end
    
    if typeof(targetCFrame) ~= "CFrame" then
        targetCFrame = CFrame.new(targetCFrame)
    end
    if game.Players.LocalPlayer.Character.Humanoid.Sit and not NeedSit then
        ExitTheChar()
    end
    if isTweening or not targetCFrame then return end
    isTweening = true
    if not Character then isTweening = false return end
    local root = Character:FindFirstChild("HumanoidRootPart")
    local humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then isTweening = false return end
    target = target or root
    local dist = (targetCFrame.Position - target.Position).Magnitude
    local offset = (target ~= root) and CFrame.new(0, 30, 0) or CFrame.new(0, 5, 0)
    if dist <= 200 then
        if connection then connection:Disconnect() connection = nil end
        if tween then pcall(function() tween:Cancel() end) tween = nil end
        if pathPart then pathPart:Destroy() pathPart = nil end
        target.CFrame = targetCFrame * offset
        isTweening = false
        return
    end
    pathPart = Instance.new("Part", workspace)
    pathPart.Name = "TweenGhost"
    pathPart.Transparency = 1
    pathPart.Anchored = true
    pathPart.CanCollide = false
    pathPart.CFrame = target.CFrame
    pathPart.Size = Vector3.new(50, 50, 50)
    tween = TweenService:Create(pathPart, TweenInfo.new(dist / 250, Enum.EasingStyle.Linear), {CFrame = targetCFrame * offset})
    connection = RunService.Heartbeat:Connect(function()
        if target and pathPart then
            target.CFrame = pathPart.CFrame * offset
        end
    end)

    tween.Completed:Connect(function()
        if connection then connection:Disconnect() connection = nil end
        if pathPart then pathPart:Destroy() pathPart = nil end
        tween = nil
        isTweening = false
    end)

    tween:Play()
end

local function TweenTouchPart(part, text, speedSetting, radiusSetting, stopCondition)
    if not part or not part:IsA("BasePart") or not part.Parent then
        return false
    end
    if not Character or IsDied(Character) or not HumanoidRootPart then
        return false
    end

    Tween(false)

    local root = Character:FindFirstChild("HumanoidRootPart")
    local humanoid = Character:FindFirstChildWhichIsA("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        return false
    end

    humanoid.Sit = false
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    local speed = tonumber(getgenv().Settings[speedSetting or "Chest Tween Speed"]) or 325
    local touchRadius = tonumber(getgenv().Settings[radiusSetting or "Chest Touch Radius"]) or 8
    local distance = (root.Position - part.Position).Magnitude
    local travelTime = math.max(distance / speed, 0.05)
    local timeout = travelTime + 3
    local startTick = tick()

    local ghost = Instance.new("Part")
    ghost.Name = "TouchTweenGhost"
    ghost.Transparency = 1
    ghost.Anchored = true
    ghost.CanCollide = false
    ghost.Size = Vector3.new(4, 4, 4)
    ghost.CFrame = root.CFrame
    ghost.Parent = workspace

    local touchTween = TweenService:Create(
        ghost,
        TweenInfo.new(travelTime, Enum.EasingStyle.Linear),
        {CFrame = part.CFrame * CFrame.new(0, 2, 0)}
    )

    local heartbeat
    heartbeat = RunService.Heartbeat:Connect(function()
        if not Character or IsDied(Character) or not root or not ghost or not ghost.Parent then
            return
        end
        humanoid.Sit = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = ghost.CFrame
    end)

    touchTween:Play()

    local touched = false
    repeat
        task.wait()
        if text then
            if type(text) == "function" then
                pcall(function() SetText(text()) end)
            else
                SetText(text)
            end
        end
        if not part or not part.Parent then
            break
        end
        if stopCondition and stopCondition() then
            break
        end
        if IsDied(Character) then
            break
        end
        if (root.Position - part.Position).Magnitude <= touchRadius then
            touched = true
            pcall(function()
                firetouchinterest(root, part, 0)
                task.wait(0.08)
                firetouchinterest(root, part, 1)
            end)
            task.wait(0.15)
        end
    until touched or tick() - startTick > timeout

    pcall(function() touchTween:Cancel() end)
    if heartbeat then heartbeat:Disconnect() end
    if ghost then ghost:Destroy() end

    return touched
end

local function TweenChest(chest, stopCondition)
    if not chest or not chest:IsA("BasePart") or not chest.Parent or not chest.CanTouch then
        return false
    end

    return TweenTouchPart(
        chest,
        nil,
        "Chest Tween Speed",
        "Chest Touch Radius",
        function()
            return not chest.Parent or not chest.CanTouch or (stopCondition and stopCondition())
        end
    )
end


local function TweenFlower(flower, flowerName)
    return TweenTouchPart(
        flower,
        "Upgrade Race V2 | Tweening " .. tostring(flowerName),
        "Flower Tween Speed",
        "Flower Touch Radius",
        function()
            return CheckTool(flowerName) or (flower and flower:IsA("BasePart") and flower.Transparency ~= 0)
        end
    )
end


local lastGhost = tick()
BringMonster = (function(name, count) count = count or 3
    if count < 2 then return end
    pcall(function() setscriptable(LocalPlayer, "SimulationRadius", true) end)
    pcall(function() sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge) end)
    xpcall((function()
        local mob, t = {}, nil
        for _, v in next, workspace.Enemies:GetChildren() do
            local h = v:FindFirstChildWhichIsA("Humanoid")
            local hrp = v:FindFirstChild("HumanoidRootPart")
            if h and hrp and h.Health > 0 and (not name or v.Name == name)
                and (HumanoidRootPart.Position - hrp.Position).Magnitude <= ((count or 3) * 250) then
                if not table.find(mob, function(chosen)
                    local chrp = chosen:FindFirstChild("HumanoidRootPart")
                    return chrp and (hrp.Position - chrp.Position).Magnitude <= 5
                end) then mob[#mob+1], t = v, t or hrp.CFrame
                end
                if #mob >= (count or 3) then break end
            end
        end
        if not t then return end
        for i = 1, #mob do
            local hrp = mob[i]:FindFirstChild("HumanoidRootPart")
            local h = mob[i]:FindFirstChildWhichIsA("Humanoid")
            if hrp and (not isnetworkowner or isnetworkowner(hrp)) then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = t * CFrame.new((i-1) * 2, 0, 0)
            end
        end
    end), (function(r) warn("Modules Error [BM]: ".. r) end))
end)

KillMonster=(function(x)
    xpcall(function()
        if workspace.Enemies:FindFirstChild(x) then
            for _,v in next,workspace.Enemies:GetChildren() do
                local vh=v:FindFirstChildWhichIsA("Humanoid") local vhrp=v:FindFirstChild("HumanoidRootPart")
                if vh and vhrp and v.Name==x and not IsDied(v) then
                    local dx,dy,dz=HumanoidRootPart.Position.X-vhrp.Position.X, HumanoidRootPart.Position.Y-vhrp.Position.Y, HumanoidRootPart.Position.Z-vhrp.Position.Z
                    local sqrMag=dx*dx+dy*dy+dz*dz
                    if sqrMag<=4900 then
                        BringMonster(x, 3)
                        FastAttack(x)
                        Tween(CFrame.new(vhrp.Position + (vhrp.CFrame.LookVector * 20) + Vector3.new(0, vhrp.Position.Y > 60 and -20 or 20, 0)))
                        EquipWeapon("Melee")
                        return
                    end
                    Tween(vhrp.CFrame) return
                end
            end
        end
        for _,v in next,ReplicatedStorage:GetChildren() do
            local vhrp=v:FindFirstChild("HumanoidRootPart")
            if v:IsA("Model") and vhrp and v.Name==x and not IsDied(v) then Tween(vhrp.CFrame) return end
        end
    end,function(e) warn("Modules ERROR:",e) end)
end)
local lastCheckSkill, MSkills = tick(), LocalPlayer.PlayerGui:WaitForChild("Main"):WaitForChild("Skills")
CheckCooldownSkill = function (key, n) if tick() - lastCheckSkill <= 0.2 then return false end lastCheckSkill = tick()
    n = n or (function(t) return t and t.Name end)(Character:FindFirstChildOfClass("Tool"))
    local keyfr = n and MSkills:FindFirstChild(n) and MSkills[n]:FindFirstChild(key) and MSkills[n][key]
    local cd = keyfr and keyfr:FindFirstChild("Cooldown")
    local txl = keyfr and keyfr:FindFirstChildWhichIsA("TextLabel")
    return cd and txl and cd.Size.X.Scale <= 0 and table.find({1, 255}, txl.TextColor3.R)
end
TableQuests = setmetatable({}, {__index = function(_, k)
    local p, d, m, raw = HumanoidRootPart.Position
    for _, x in next, require(ReplicatedStorage.GuideModule).Data.NPCList do
        if x.InternalQuestName == k then
            local pos = x.Position
            if typeof(pos) == "Vector3" then
                local dist = (pos - p).Magnitude
                if not d or dist < d then d = dist m = pos raw = x.NPCName end
            elseif typeof(pos) == "table" then
                for _, v in next, pos do
                    if typeof(v) == "Vector3" then
                        local dist = (v - p).Magnitude
                        if not d or dist < d then d = dist m = v raw = x.NPCName end
                    end
                end
            end
        end
    end
    return m and {Position = m, Meters = d, RawNPCName = raw} or nil
end})

getgenv().AimbotTarget = false
SetAimbotTarget = function(a) getgenv().AimbotTarget = not a and nil or GetPosition(a) end
local mt = getrawmetatable(game)
local oldNamecall = mt.__namecall
setreadonly(mt, false)
mt.__namecall = newcclosure(function(self, ...)
    if not checkcaller() then
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local args = {...}
            local t = getgenv().AimbotTarget
            if t and t ~= "" then
                if typeof(args[1]) ~= "boolean" then
                    local p = GetPosition(t)
                    if typeof(p) == "Vector3" then
                        for i = 1, #args do
                            if typeof(args[i]) == "Vector3" then
                                args[i] = p break
                            end
                        end
                    end
                end
                return oldNamecall(self, unpack(args))
            end
        end
    end
    return oldNamecall(self, ...)
end)
CheckOwnerBoat = function() if workspace.Boats:GetChildren() == 0 then return false end
    for _, v in next, workspace.Boats:GetChildren() do
        if v:IsA("Model") and v:FindFirstChild("Owner") and tostring(v.Owner.Value) == LocalPlayer.Name and v.Humanoid.Value > 0 and CheckDistance(v) <= 6000 then
            return v
        end
    end
    return false
end
local canPress = true
PressKeyEvent = (function(k, d)
    if not canPress then return end
    canPress = false
    task.spawn(function()
        VirtualInputManager:SendKeyEvent(true, k, false, game) task.wait(d or 0)
        VirtualInputManager:SendKeyEvent(false, k, false, game)
        canPress = true
    end)
end)

function CheckSafeZone(x)
	for _, v in workspace._WorldOrigin.SafeZones:GetChildren() do
		if (v.CFrame.Position - x).Magnitude < (v.Mesh.Scale.Magnitude / 2) then
			return true
		end
	end
	return false
end

local all = 0;
FarmBeli = (function(stopConditionFunc, ignoreY, ignoreFistStop)
    if type(stopConditionFunc) ~= "function" then stopConditionFunc = function() return false end end

    local chests, c = {}, 0
    local hasFist = CheckTool("Fist of Darkness")

    if not Character or IsDied(Character) then return end
    Tween(false)

    if all < getgenv().Settings["Max Chests"] and (ignoreFistStop or not hasFist) then
        for _, v in next, CollectionService:GetTagged("_ChestTagged") do
            if v and v.CanTouch then
                local dist = (v.Position - HumanoidRootPart.Position).Magnitude
                table.insert(chests, {obj = v, dist = dist})
            end
        end

        table.sort(chests, function(a, b) return a.dist < b.dist end)

        if ignoreFistStop or not CheckTool("Fist of Darkness") then
            for i, t in next, chests do
                local v = t.obj
                if v:IsA("BasePart") and v.Name:find("Chest") then
                    if v.CanTouch then
                        repeat task.wait()
                            SetText("Collect Chests | Collected: " .. c .. "/" .. all .. "/" .. getgenv().Settings["Max Chests"] .. " Chests")
                            local touched = TweenChest(v, function()
                                return (not ignoreFistStop and CheckTool("Fist of Darkness")) or IsDied(Character) or stopConditionFunc()
                            end)

                            if v and v.Parent and v.CanTouch then
                                task.wait(tonumber(getgenv().Settings["Skip Chest Delay"]) or 1)
                                if v and v.Parent and v.CanTouch then
                                    v.CanTouch = false
                                end
                            end
                        until not v.CanTouch or (not ignoreFistStop and CheckTool("Fist of Darkness")) or IsDied(Character) or stopConditionFunc()

                        if all >= getgenv().Settings["Max Chests"] then
                            SetText("Stopped: Max Chests reached")
                            HopServer(8)
                            break
                        elseif not ignoreFistStop and CheckTool("Fist of Darkness") then
                            SetText("Stopped: Fist of Darkness detected")
                            break
                        elseif not ignoreFistStop and CheckMonster("Darkbeard") then
                            break
                        elseif stopConditionFunc() then
                            break
                        end

                        if not IsDied(Character) then
                            c += 1
                            all += 1

                            if c >= getgenv().Settings["Reset After Collect Chests"] and (ignoreFistStop or not CheckTool("Fist of Darkness")) then
                                if Character and Character:FindFirstChildWhichIsA("Humanoid") then
                                    Character:FindFirstChildWhichIsA("Humanoid"):ChangeState(Enum.HumanoidStateType.Dead)
                                    SetText("Collect Chests | Reset: Collected: " .. tostring(getgenv().Settings["Reset After Collect Chests"]) .. " Chests")
                                end
                                c = 0
                                task.wait(1)
                            end
                        else
                            break
                        end
                    end
                    if i % 250 == 0 then task.wait(0.1) end
                end
            end
        else
            Tween(false)
            SetText("Stopped: Found Special Item")
        end

        if (ignoreFistStop or not CheckTool("Fist of Darkness")) and not CheckMonster("Darkbeard") and not stopConditionFunc() then
            HopServer(10)
        end
    end
end)

local raceTitlesV3 = {
    ["Full Power"] = "Human V3",
    ["Godspeed"] = "Rabbit V3",
    ["Warrior of the Sea"] = "Shark V3",
    ["Perfect Being"] = "Angel V3",
    ["Hell Hound"] = "Ghoul V3",
    ["War Machine"] = "Cyborg V3",
    ["Ancient Flame"] = "Draco V3",
}

local raceNameToV3 = {
    Human = "Human V3",
    Mink = "Rabbit V3",
    Rabbit = "Rabbit V3",
    Fishman = "Shark V3",
    Shark = "Shark V3",
    Skypiea = "Angel V3",
    Angel = "Angel V3",
    Ghoul = "Ghoul V3",
    Cyborg = "Cyborg V3",
    Draco = "Draco V3",
}

local raceAlias = {
    human = "Human",
    mink = "Mink",
    rabbit = "Mink",
    fishman = "Fishman",
    shark = "Fishman",
    skypiea = "Skypiea",
    angel = "Skypiea",
    ghoul = "Ghoul",
    cyborg = "Cyborg",
    draco = "Draco",
}

local function NormalizeRaceName(name)
    local s = tostring(name or ""):lower():gsub("%s+", "")
    return raceAlias[s] or tostring(name or "")
end

local function IsTitleUnlockedValue(value)
    if value == true or value == 1 then
        return true
    end

    if value == false or value == 0 or value == nil then
        return false
    end

    local s = tostring(value):lower()
    s = s:gsub("^%s+", ""):gsub("%s+$", "")

    return s == "true"
        or s == "1"
        or s == "yes"
        or s == "owned"
        or s == "unlocked"
end

local function GetUnlockedV3Map()
    local unlocked = {}

    local function mark(titleName, unlockedValue)
        local raceV3 = titleName and raceTitlesV3[titleName]
        if raceV3 and IsTitleUnlockedValue(unlockedValue) then
            unlocked[raceV3] = true
        end
    end

    local ok, titles = pcall(function()
        return COMMF_:InvokeServer("getTitles")
    end)

    if ok and type(titles) == "table" then
        for _, t in pairs(titles) do
            local titleName = t.Name or t.Title or t[1]
            local unlockedValue = nil

            if t.Unlocked ~= nil then
                unlockedValue = t.Unlocked
            elseif t.unlocked ~= nil then
                unlockedValue = t.unlocked
            else
                unlockedValue = t[2]
            end

            mark(titleName, unlockedValue)
        end
    end

    local titlesFolder = LocalPlayer:FindFirstChild("Titles")
    if titlesFolder then
        for _, inst in ipairs(titlesFolder:GetChildren()) do
            mark(inst.Name, inst.Value)
        end
    end

    return unlocked
end

local function CountUnlockedV3(unlocked)
    local count = 0
    for _, has in pairs(unlocked) do
        if has then count += 1 end
    end
    return count
end

local function HasRaceV3(raceName, unlocked)
    raceName = NormalizeRaceName(raceName)
    local raceV3 = raceNameToV3[raceName]
    return raceV3 and unlocked[raceV3] == true
end

local function HasCurrentRaceV3()
    local current = LocalPlayer.Data and LocalPlayer.Data:FindFirstChild("Race") and LocalPlayer.Data.Race.Value or ""
    return HasRaceV3(current, GetUnlockedV3Map())
end

local CompletedFolderLock = false

local function NormalizeFolderId(value, allowNil)
    if value == nil then
        return nil, allowNil
    end

    local s = tostring(value)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")

    if s == "" or s == "........." or s:match("^%.+$") or s:lower() == "nil" then
        return nil, allowNil
    end

    return s, true
end

local function ChangeFolderAfterCompleted(reason)
    if CompletedFolderLock then
        return false
    end

    if getgenv().ChangeFolderOnCompleted == false then
        warn("[Completed-RACES] ChangeFolderOnCompleted = false - bỏ qua đổi folder")
        return false
    end

    if not getgenv().client then
        warn("[Completed-RACES] getgenv().client chưa được set - bỏ qua đổi folder")
        return false
    end

    if typeof(getgenv().client.ChangeToFolder) ~= "function" then
        warn("[Completed-RACES] getgenv().client.ChangeToFolder không tồn tại - bỏ qua đổi folder")
        return false
    end

    local id1, ok1 = NormalizeFolderId(getgenv().id1, false)
    local id2, ok2 = NormalizeFolderId(getgenv().id2, false)
    local id3, ok3 = NormalizeFolderId(getgenv().id3, true)

    if not ok1 or not ok2 then
        warn("[Completed-RACES] id1/id2 bắt buộc nhưng đang rỗng - bỏ qua đổi folder")
        return false
    end

    CompletedFolderLock = true

    warn(("[Completed-RACES] %s -> ChangeToFolder args: id1=%s id2=%s id3=%s"):format(
        tostring(reason or "Completed-RACES"),
        tostring(id1),
        tostring(id2),
        id3 == nil and "nil" or tostring(id3)
    ))

    local ok, changed = pcall(function()
        return getgenv().client:ChangeToFolder(id1, id2, true, id3)
    end)

    if not ok then
        warn("[Completed-RACES] Lỗi khi gọi ChangeToFolder: " .. tostring(changed))
        CompletedFolderLock = false
        return false
    end

    if changed then
        warn("[Client] Successfully changed folder after Completed-RACES, disconnecting to apply changes...")
        pcall(function()
            getgenv().client:Disconnect()
        end)
        task.wait(5)
        pcall(function()
            game:Shutdown()
        end)
        return true
    else
        warn("[Client] Failed to change folder after Completed-RACES")
        task.wait(10)
        CompletedFolderLock = false
        return false
    end
end

local didWriteCompletedRaces = false
local function WriteCompletedRaces(reason)
    if didWriteCompletedRaces then return end

    SetText(reason or "Completed configured races")

    local okWrite, errWrite = pcall(function()
        writefile(LocalPlayer.Name .. ".txt", "Completed-RACES")
    end)

    if not okWrite then
        warn("[Completed-RACES] Lỗi ghi file: " .. tostring(errWrite))
        return
    end

    didWriteCompletedRaces = true
    warn("[Completed-RACES] Đã ghi: " .. LocalPlayer.Name .. ".txt -> Completed-RACES")

    ChangeFolderAfterCompleted("Completed-RACES")
end

local function GetWantedRaces()
    local cfg = getgenv().Settings["Races"] or {}
    local wanted = {}
    local order = {"Human", "Mink", "Fishman", "Skypiea", "Cyborg", "Ghoul"}

    for _, raceName in ipairs(order) do
        if cfg[raceName] == true then
            table.insert(wanted, raceName)
        end
    end

    return wanted
end

local function CheckWantedRacesCompleted(unlocked)
    local wanted = GetWantedRaces()
    local missing = {}

    for _, raceName in ipairs(wanted) do
        if not HasRaceV3(raceName, unlocked) then
            table.insert(missing, raceName)
        end
    end

    return (#wanted > 0 and #missing == 0), wanted, missing
end

local function IsRaceEnabled(raceName)
    raceName = NormalizeRaceName(raceName)
    local cfg = getgenv().Settings["Races"] or {}
    return cfg[raceName] == true
end

CompletedRace = setmetatable({}, {
    __index = function(_, raceName)
        return HasRaceV3(raceName, GetUnlockedV3Map())
    end
})

SaveCompletedRace = function(x)
    SetText("Detected " .. tostring(x) .. " V3 completed by title check")
end

task.spawn(function() wait(1)
    while task.wait(0.5) do
        xpcall(function()
            local CurrentRace = NormalizeRaceName(LocalPlayer.Data.Race.Value)
            local UnlockedV3 = GetUnlockedV3Map()
            local AllWantedDone, WantedRaces, MissingRaces = CheckWantedRacesCompleted(UnlockedV3)
            local CurrentRaceDone = HasRaceV3(CurrentRace, UnlockedV3)
            local CurrentRaceEnabled = IsRaceEnabled(CurrentRace)

            if AllWantedDone then
                WriteCompletedRaces("Upgrade Race V3 | Completed configured races")
                return
            end

            if CurrentRaceDone or not CurrentRaceEnabled then
                if LocalPlayer.Data.Fragments.Value >= 3000 then
                    SetText("Reroll Race")
                    COMMF_:InvokeServer("BlackbeardReward", "Reroll", "2")
                    wait(1)
                else
                    if CheckSea(3) then
                        if CheckMonster("Dough King") or CheckMonster("rip_indra") or CheckMonster("Cake Prince") then
                            for _, v2 in next, {workspace.Enemies, ReplicatedStorage} do
                                for _, v in next, v2:GetChildren() do
                                    if v.Name == "Dough King" or v.Name == "Cake Prince" or v.Name:find("rip_indra") then
                                        if v.Name ~= "rip_indra" and not CheckLocation("Dimensional Shift") then
                                            xpcall(function()
                                                firetouchinterest(LocalPlayer.Character.HumanoidRootPart, workspace.Map.CakeLoaf.BigMirror.Main, 0)
                                                task.wait(3)
                                            end, function(e) warn(e) end)
                                        end
                                        if v:FindFirstChildWhichIsA("Humanoid") and v.Humanoid.Health > 0 and v.HumanoidRootPart then
                                            repeat task.wait()
                                                SetText("Killing ".. v.Name.. " | Health: ".. math.floor(v.Humanoid.Health / v.Humanoid.MaxHealth * 100).. "%")
                                                KillMonster(v.Name)
                                            until not v or not v:FindFirstChildWhichIsA("Humanoid") or v.Humanoid.Health <= 0 or not v.HumanoidRootPart
                                        end
                                    end
                                end
                            end
                        else
                            local currentProgress = tonumber(COMMF_:InvokeServer("CakePrinceSpawner"):match("%d+") or 500)
                            if currentProgress <= getgenv().Settings["Katakuri Progress"] then
                                for _, v in next, workspace.Enemies:GetChildren() do
                                    if table.find({"Cookie Crafter", "Cake Guard", "Baking Staff", "Head Baker"}, v.Name) then
                                        if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChildWhichIsA("Humanoid") and v.Humanoid.Health > 0 then
                                            repeat task.wait()
                                                SetText("Killing 500 monsters | Progress: ".. currentProgress.. "/500")
                                                KillMonster(v.Name)
                                            until not v or not v:FindFirstChildWhichIsA("Humanoid") or v.Humanoid.Health <= 0
                                        end
                                    end
                                end
                            else
                                if not CheckMonster("Dough King") and not CheckMonster("Cake Prince") then
                                    SetText("Hop for Katakuri") task.wait(5) HopServer()
                                end
                            end
                        end
                    else
                        SetText("Travel To Sea 3")
                        COMMF_:InvokeServer("TravelZou") wait(2)
                    end
                end
            else
                if CheckSea(2) or (not CheckTool(getgenv().Settings["Focus Melee"]) and CurrentRace == "Fishman") then
                    local SetRaceStatus = function(x) SetText(string.format("Upgrade Race V%s | Current: %s", x, CurrentRace)) end
                    if not LocalPlayer.Data.Race:FindFirstChild("Evolved") then
                        SetRaceStatus(2)
                        if LocalPlayer.Data.Beli.Value >= 500000 then
                            local alch = COMMF_:InvokeServer("Alchemist", "2")
                            if alch == "Come back when you find them." then
                                if not CheckTool("Flower 2") and workspace.Flower2.Transparency == 0 then
                                    Tween(false)
                                    SetText("Collecting Flower 2")
                                    repeat
                                        task.wait(0.1)
                                        if workspace:FindFirstChild("Flower2") then
                                            TweenFlower(workspace.Flower2, "Flower 2")
                                        end
                                    until (CheckTool("Flower 2") or workspace.Flower2.Transparency ~= 0 or IsDied(Character))
                                elseif not CheckTool("Flower 3") then
                                    for _, v in next, workspace.Enemies:GetChildren() do
                                        if v.Name == "Swan Pirate" and v:FindFirstChildWhichIsA("Humanoid") and v.Humanoid.Health > 0 then
                                            repeat task.wait() KillMonster(v.Name) SetText("Collecting Flower 3")
                                            until not v or v.Humanoid.Health <= 0 or CheckTool("Flower 3")
                                        else
                                            Tween(CFrame.new(980, 120, 1290))
                                        end
                                    end
                                elseif not CheckTool("Flower 1") then
                                    if workspace.Flower1.Transparency == 0 then
                                        Tween(false)
                                        SetText("Collecting Flower 1")
                                        repeat
                                            task.wait(0.1)
                                            if workspace:FindFirstChild("Flower1") then
                                                TweenFlower(workspace.Flower1, "Flower 1")
                                            end
                                        until (CheckTool("Flower 1") or workspace.Flower1.Transparency ~= 0 or IsDied(Character))
                                    else
                                        xpcall(function() Tween(workspace._WorldOrigin.SafeZones:GetChildren()[1].CFrame) end, function() end)
                                    end
                                else
                                    if CheckTool("Flower 1") and CheckTool("Flower 2") and CheckTool("Flower 3") then
                                        COMMF_:InvokeServer("Alchemist", "3")
                                    end
                                end
                            end
                        else
                            FarmBeli(function() return LocalPlayer.Data.Beli.Value >= 500000 end)
                        end
                    elseif COMMF_:InvokeServer("Wenlocktoad") == nil then
                        SetRaceStatus(3)
                        if LocalPlayer.Data.Beli.Value >= 2000000 then
                            local ven1 = COMMF_:InvokeServer("Wenlocktoad", "1")
                            if ven1 == 0 then COMMF_:InvokeServer("Wenlocktoad", "2")
                            elseif ven1 == 2 then COMMF_:InvokeServer("Wenlocktoad", "3")
                            -- elseif ven1 == -1 then SetText("Not Enough Beli")
                            else
                                if CurrentRace == "Human" then
                                    for _, v2 in next, {workspace.Enemies, ReplicatedStorage} do
                                        for _, v in next, v2:GetChildren() do
                                            if table.find({"Jeremy", "Orbitus", "Diamond"}, v.Name) then
                                                repeat task.wait() KillMonster(v.Name)
                                                until not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0
                                            end
                                        end
                                    end
                                elseif CurrentRace == "Mink" then
                                    FarmBeli(function() return not HasCurrentRaceV3() end, nil, true)
                                elseif CurrentRace == "Fishman" then
                                    local TargetMelee = getgenv().Settings["Focus Melee"]
                                    if CheckTool(TargetMelee) then
                                        local function CE(x) return workspace.Enemies:FindFirstChild(x) or workspace.SeaBeasts:FindFirstChild(x) end
                                        local e = CE("Piranha") or CE("Shark") or CE("Fish Crew Member")
                                        local v = CE("SeaBeast1")
                                        if e then Character.Humanoid.Sit = false
                                            repeat task.wait() KillMonster(e.Name)
                                            until not e or e.Humanoid.Health <= 0 or not Character:FindFirstChild("Humanoid") or Character.Humanoid.Health <= 0
                                        elseif v then Character.Humanoid.Sit = false
                                            repeat task.wait()
                                                FastAttack()
                                                SetAimbotTarget(v.HumanoidRootPart)
                                                Tween(v.HumanoidRootPart.CFrame * CFrame.new(0, (v.HumanoidRootPart.Position.Y > -300 and 500 or 1000), 0))
                                                EquipWeapon(({"Melee", "Sword", "Gun", "Blox Fruit"})[math.random(4)])
                                                local k = ({"Z", "X", "C", "V", "F"})[math.random(5)]
                                                if not Character:FindFirstChild("Portal-Portal") then
                                                    if CheckCooldownSkill(k) then
                                                        PressKeyEvent(k, 0.5)
                                                    end
                                                end
                                            until not v or not v:FindFirstChild("Health") or v.Health.Value <= 0 or not Character:FindFirstChild("Humanoid") or Character.Humanoid.Health <= 0
                                        else
                                            local BOAT = CheckOwnerBoat()
                                            if BOAT then
                                                if not Character.Humanoid.Sit then Tween(BOAT.VehicleSeat.CFrame)
                                                    NeedSit = true
                                                else Tween(CFrame.new(-1000000, 49, 1000000), BOAT:FindFirstChild("Engine"))
                                                task.delay(5, function() Tween(false) end)
                                                end
                                            else
                                                local PlaceNPC = Vector3.new(-1, 10, 2960)
                                                if (HumanoidRootPart.Position - PlaceNPC).Magnitude < 50 then
                                                    COMMF_:InvokeServer("BuyBoat", LocalPlayer.Team.Name == "Marine" and "PirateSloop" or "PirateBrigade")
                                                else
                                                    Character.Humanoid.Sit = false
                                                    Tween(CFrame.new(PlaceNPC))
                                                end
                                            end
                                        end
                                    else Character.Humanoid.Sit = false
                                        local npcName = MeleeData[TargetMelee] or TargetMelee
                                        local x, d = GetCFrameByNPC(npcName)
                                        if x then
                                            if d < 50 then
                                                if TargetMelee == "Dragon Claw" then
                                                    COMMF_:InvokeServer("BlackbeardReward", "DragonClaw", "2")
                                                elseif TargetMelee == "Sharkman Karate" then
                                                    local hasSharkman = CheckTool("Sharkman Karate") or CheckInventory("Sharkman Karate")
                                                    if not hasSharkman and COMMF_:InvokeServer("BuySharkmanKarate", true) == 1 then
                                                        local pos = CFrame.new(-2599.621826171875, 238.19833374023438, -10315.998046875)
                                                        repeat
                                                            task.wait()
                                                            Tween(pos)
                                                        until CheckDistance(pos) <= 30
                                                        COMMF_:InvokeServer("BuySharkmanKarate")
                                                    end
                                                else
                                                    COMMF_:InvokeServer("Buy"..TargetMelee:gsub("%s+", ""))
                                                end
                                            else
                                                SetText("Travel To ".. npcName.. " NPC")
                                                Tween(x)
                                            end
                                        else
                                            SetText("Can't find ".. npcName.. " NPC")
                                            Character.Humanoid:ChangeState(Enum.HumanoidStateType.Dead)
                                            LocalPlayer.CharacterAdded:Wait()
                                            local needSea = GetMeleeTargetSea(TargetMelee)
                                            if needSea == 2 then
                                                COMMF_:InvokeServer("TravelDressrosa")
                                            elseif needSea == 3 then
                                                COMMF_:InvokeServer("TravelZou")
                                            end
                                        end
                                     end
                                elseif CurrentRace == "Skypiea" then
                                    local x = nil
                                    for _, v in next, Players:GetPlayers() do
                                        if v.Name ~= LocalPlayer.Name and v:FindFirstChild("Data") and v.Data.Race.Value == "Skypiea" then
                                            if not CheckSafeZone(v.Character.HumanoidRootPart.Position) and v:GetAttribute("DangerLevel") == 0 then
                                                x = v.Character break
                                            end
                                        end
                                    end
                                    
                                    local lastPvpEnable = 0
                                     
                                    if x then
                                        repeat task.wait()
                                            SetText("Killing Skypiea Player | Health: ".. math.floor(x.Humanoid.Health / x.Humanoid.MaxHealth * 100).. "%")
                                            
                                            if LocalPlayer.PlayerGui.Main.PvpDisabled.Visible and (tick() - lastPvpEnable > 3) then
                                                lastPvpEnable = tick()
                                                pcall(function()
                                                    local args = {
                                                        [1] = "EnablePvp"
                                                    }
                                                    COMMF_:InvokeServer(unpack(args))
                                                end)
                                            end
                                            
                                            Tween(x.HumanoidRootPart.CFrame * CFrame.new(0, 20, 0))
                                            if (x.HumanoidRootPart.Position - HumanoidRootPart.Position).Magnitude < 100 then
                                                FastAttack() SetAimbotTarget(x.HumanoidRootPart)
                                                EquipWeapon(({"Melee", "Sword", "Gun", "Blox Fruit"})[math.random(4)])
                                            end
                                        until not x or x.Humanoid.Health <= 0
                                    else
                                        SetText("Finding Skypiea Player") HopServer(10)
                                    end
                                elseif CurrentRace == "Cyborg" then
                                    local venlock = COMMF_:InvokeServer("Wenlocktoad", "2")
                                    if typeof(venlock) == "string" then SetText("Upgrade Race V3")
                                        if venlock:find("haven't completed") ~= nil or venlock:find("Talk to me again") ~= nil then
                                            for _, v in pairs(workspace:GetChildren()) do
                                                pcall(function()
                                                    if v:IsA("Model") and v.Name:find("Fruit") and v:FindFirstChild("Handle") and v.Handle:FindFirstChildWhichIsA("TouchTransmitter", true) then
                                                        print(v.Name)
                                                        firetouchinterest(v.Handle, Character:FindFirstChild("HumanoidRootPart"), 0) task.wait(1)
                                                        firetouchinterest(v.Handle, Character:FindFirstChild("HumanoidRootPart"), 1)
                                                    end
                                                end)
                                            end
                                            if CheckTool("Fruit") then
                                                local t = math.huge
                                                local n;
                                                for _, v in next, COMMF_:InvokeServer("getInventory") do
                                                    if v.Type == "Blox Fruit" then
                                                        if v.Value < t then
                                                            t = v.Value
                                                            n = v.Name
                                                        end
                                                    end
                                                end
                                                COMMF_:InvokeServer("LoadFruit", n)
                                            end
                                            if CheckTool("Fruit") then
                                                COMMF_:InvokeServer("Wenlocktoad", "3")
                                            else
                                                SetText("Not Found Fruit, Hop Server") wait(3)
                                                HopServer(10)
                                            end
                                        end
                                    end
                                end
                            end
                        else
                            FarmBeli(function() return LocalPlayer.Data.Beli.Value >= 2000000 end)
                        end
                    else
                        SaveCompletedRace(CurrentRace)
                    end
                else
                    SetText("Travel To Sea 2 for Upgrade Race V2")
                    COMMF_:InvokeServer("TravelDressrosa") wait(1)
                end
            end
        end, function(err) warn(err) end)
    end
end)

task.spawn(function()
    while task.wait(4) do PressKeyEvent("T") PressKeyEvent("Y") PressKeyEvent("Q")
        xpcall(function() ReplicatedStorage.Remotes.CommE:FireServer("Ken", true)
            if not Character.Humanoid or Character.Humanoid.Health <= 0 then pcall(function() workspace.TweenGhost:Destroy() end) connection, tween, pathPart, isTweening = nil, nil, nil, false return end
            if not Character:FindFirstChild("HasBuso") then COMMF_:InvokeServer("Buso") end
            for _, v in next, {"Buso", "Geppo", "Soru"} do
                if not CollectionService:HasTag(Character, v) then
                    if LocalPlayer.Data.Beli.Value >= ((function(t)
                        return t == "Geppo" and 1e4 or t == "Buso" and 2.5e4 or t == "Soru" and 1e5 or 0
                    end)(v)) then SetText("Buy Abilies: ".. v) COMMF_:InvokeServer("BuyHaki", v)
                    end
                end
            end
        end, function(err) warn("LL: ".. err) end)
    end
end)

GuiService.ErrorMessageChanged:Connect(newcclosure(function()
    if GuiService:GetErrorType() == Enum.ConnectionError.DisconnectErrors then
        while true do ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer('teleport', JobId) task.wait(5) end
    end
end))
