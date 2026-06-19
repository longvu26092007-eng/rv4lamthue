-- ============================================================
-- checktemple.lua — DIAGNOSTIC
-- Mục đích: sau khi NHÂN VẬT load xong mới gọi remote temple-door,
-- in ra giá trị thực tế để biết tại sao bot kẹt "Đang khởi động".
-- Cách dùng: chạy file này trong executor trên 1 account đang kẹt,
-- rồi gửi lại toàn bộ phần in trong Console (F9) / output executor.
-- ============================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

-- ---- log helper: in cả ra console lẫn warn (cho dễ thấy) ----
local function L(...)
    local parts = {}
    for _, v in ipairs({ ... }) do parts[#parts + 1] = tostring(v) end
    local line = "[CHECKTEMPLE] " .. table.concat(parts, " ")
    print(line)
    warn(line)
end

-- ============================================================
-- 1) ĐỢI NHÂN VẬT LOAD XONG (đúng yêu cầu: load xong mới check)
-- ============================================================
local function waitCharacterReady(timeout)
    local t0 = tick()
    local LP = Players.LocalPlayer
    repeat
        local ok = LP
            and LP.Character
            and LP.Character:FindFirstChild("HumanoidRootPart")
            and LP.Character:FindFirstChildOfClass("Humanoid")
            and LP.Character:FindFirstChildOfClass("Humanoid").Health > 0
        -- chờ luôn LoadingScreen tắt (giống điều kiện khởi động của bot chính)
        local stillLoading = LP and LP:FindFirstChild("PlayerGui")
            and LP.PlayerGui:FindFirstChild("LoadingScreen")
        if ok and not stillLoading then return true end
        task.wait(0.2)
    until (tick() - t0) > (timeout or 60)
    return false
end

L("Đang đợi nhân vật load xong...")
local ready = waitCharacterReady(60)
L("Nhân vật ready =", ready)
-- chờ thêm 1 nhịp cho Data/remote ổn định
task.wait(1)

-- ============================================================
-- 2) GỌI REMOTE: thử nhiều biến thể tên, in kết quả + kiểu + lỗi
-- ============================================================
local CommF = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("CommF_")
L("Tìm thấy Remotes.CommF_ =", CommF ~= nil)

local function tryInvoke(arg)
    if not CommF then return end
    local ok, res = pcall(function() return CommF:InvokeServer(arg) end)
    if ok then
        L(("InvokeServer(%q) => OK | type=%s | value=%s"):format(arg, typeof(res), tostring(res)))
        -- nếu là table → liệt kê field cho dễ đọc
        if typeof(res) == "table" then
            for k, v in pairs(res) do
                L(("    .%s = %s (%s)"):format(tostring(k), tostring(v), typeof(v)))
            end
        end
    else
        L(("InvokeServer(%q) => LỖI | %s"):format(arg, tostring(res)))
    end
end

L("================= KẾT QUẢ REMOTE =================")
tryInvoke("CheckTempleDoor")
tryInvoke("templedoorcheck")
tryInvoke("TempleDoorCheck")
tryInvoke("CheckTempleDoorStatus")

-- ============================================================
-- 3) DÒ mọi remote/khoá có chữ "temple" để lộ tên đúng (nếu game đã đổi tên)
-- ============================================================
L("============ DÒ remote chứa 'temple' ============")
local remotesFolder = RS:FindFirstChild("Remotes")
if remotesFolder then
    for _, inst in ipairs(remotesFolder:GetDescendants()) do
        if string.find(string.lower(inst.Name), "temple") then
            L("  Remote:", inst.ClassName, inst.Name)
        end
    end
else
    L("  Không thấy folder ReplicatedStorage.Remotes")
end

-- ============================================================
-- 4) Thông tin phụ: vị trí, world, có đang ở Temple of Time không
-- ============================================================
local LP = Players.LocalPlayer
local hrp = LP and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
if hrp then
    L("Vị trí nhân vật:", math.floor(hrp.Position.X), math.floor(hrp.Position.Y), math.floor(hrp.Position.Z))
end
local templeInMap = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Temple of Time") ~= nil
L("Có 'Temple of Time' trong workspace.Map =", templeInMap)

L("================= XONG — copy toàn bộ dòng [CHECKTEMPLE] gửi lại =================")
