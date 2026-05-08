-- ==========================================
-- [ FRAGMENT CHECKER & LOGGER ]
-- Chức năng: Đợi game load -> Mở UI -> Theo dõi Fragment -> Ghi file khi đủ
-- ==========================================

-- [[ 4. THIẾT LẬP SỐ FRAGMENT YÊU CẦU ]]
-- Nếu chưa có biến getgenv().fragmentchange từ trước, mặc định sẽ là 8000
getgenv().fragmentchange = getgenv().fragmentchange or 8000 
local TARGET_FRAG = getgenv().fragmentchange

-- ==========================================
-- [ 5. ĐỢI GAME LOAD ĐẦY ĐỦ ]
-- ==========================================
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Đợi LocalPlayer và các thành phần giao diện, nhân vật
repeat task.wait() until game.Players
repeat task.wait() until game.Players.LocalPlayer
repeat task.wait() until game.Players.LocalPlayer:FindFirstChild("PlayerGui")
repeat task.wait() until game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
task.wait(2)

-- ==========================================
-- [ LẤY DỮ LIỆU NGƯỜI CHƠI ]
-- ==========================================
local Player = game.Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")

local function GetFragments()
    local val = 0
    pcall(function() 
        val = Player.Data.Fragments.Value 
    end)
    return val
end

-- ==========================================
-- [ 1. TẠO UI HIỂN THỊ STATUS ]
-- ==========================================
-- Xóa UI cũ nếu đã từng chạy script
if CoreGui:FindFirstChild("CheckFragUI") then
    CoreGui.CheckFragUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui", CoreGui)
ScreenGui.Name = "CheckFragUI"

-- Khung chính
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size             = UDim2.new(0, 320, 0, 110)
MainFrame.Position         = UDim2.new(0.5, -160, 0.5, -55)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.Active           = true
MainFrame.Draggable        = true
Instance.new("UIStroke", MainFrame).Color        = Color3.fromRGB(0, 255, 255)
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

-- Tiêu đề
local Title = Instance.new("TextLabel", MainFrame)
Title.Size                 = UDim2.new(1, 0, 0, 30)
Title.Text                 = "Theo Dõi Fragment"
Title.TextColor3           = Color3.fromRGB(0, 255, 255)
Title.BackgroundTransparency = 1
Title.Font                 = Enum.Font.GothamBold
Title.TextSize             = 14

local Line = Instance.new("Frame", Title)
Line.Size              = UDim2.new(1, 0, 0, 1)
Line.Position          = UDim2.new(0, 0, 1, 0)
Line.BackgroundColor3  = Color3.fromRGB(0, 255, 255)
Line.BorderSizePixel   = 0

-- Dòng hiển thị trạng thái hiện tại
local ActionStatus = Instance.new("TextLabel", MainFrame)
ActionStatus.Size                 = UDim2.new(1, -20, 0, 22)
ActionStatus.Position             = UDim2.new(0, 10, 0, 40)
ActionStatus.Text                 = "Trạng thái: Đang khởi tạo..."
ActionStatus.TextColor3           = Color3.fromRGB(200, 200, 200)
ActionStatus.Font                 = Enum.Font.Gotham
ActionStatus.BackgroundTransparency = 1
ActionStatus.TextSize             = 12
ActionStatus.TextXAlignment       = Enum.TextXAlignment.Left

-- Dòng hiển thị số lượng Fragment
local FragLabel = Instance.new("TextLabel", MainFrame)
FragLabel.Size                 = UDim2.new(1, -20, 0, 22)
FragLabel.Position             = UDim2.new(0, 10, 0, 65)
FragLabel.Text                 = "🔮 Fragments: ... / " .. tostring(TARGET_FRAG)
FragLabel.TextColor3           = Color3.fromRGB(200, 160, 255)
FragLabel.Font                 = Enum.Font.GothamBold
FragLabel.BackgroundTransparency = 1
FragLabel.TextSize             = 13
FragLabel.TextXAlignment       = Enum.TextXAlignment.Left

-- ==========================================
-- [ 2 & 3. CHECK FRAGMENT VÀ GHI FILE ]
-- ==========================================
-- Chạy vòng lặp kiểm tra song song (không làm đứng game)
task.spawn(function()
    while true do
        local currentFrag = GetFragments()
        FragLabel.Text = "🔮 Fragments: " .. tostring(currentFrag) .. " / " .. tostring(TARGET_FRAG)

        if currentFrag >= TARGET_FRAG then
            -- Khi đã đủ hoặc vượt mức yêu cầu
            FragLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
            ActionStatus.Text = "Trạng thái: Đang ghi log..."
            
            -- Ghi file
            local success, err = pcall(function()
                writefile(Player.Name .. ".txt", "Completed-fragment")
            end)

            if success then
                ActionStatus.Text = "Trạng thái: ✅ HOÀN THÀNH (Đã ghi file)"
                warn("[CheckFrag] Đã ghi thành công file: " .. Player.Name .. ".txt")
            else
                ActionStatus.Text = "Trạng thái: ❌ Lỗi ghi file!"
                warn("[CheckFrag] Lỗi khi tạo file: " .. tostring(err))
            end
            
            -- Dừng vòng lặp sau khi hoàn thành nhiệm vụ
            break
        else
            -- Khi chưa đủ, tiếp tục cập nhật UI và chờ
            FragLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
            ActionStatus.Text = "Trạng thái: Đang đợi farm đủ Fragment..."
        end
        
        -- Dừng 3 giây mỗi lần check để tối ưu hóa, không làm drop FPS
        task.wait(3)
    end
end)
