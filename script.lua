local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Library = require(ReplicatedStorage:WaitForChild("Lib"))
local LocalPlayer = Players.LocalPlayer

-- متغير للتحكم بحالة التفعيل (مغلق افتراضياً)
local sanityEnabled = false

-- الدالة المعدلة: تعمل فقط إذا كان الزر مفعل (true)
local function keepSanityFull()
 if sanityEnabled then
  LocalPlayer:SetAttribute("Sanity", 100)
 end
end

-- ربط السكربت بنظام اللعبة
Library.Inject("PlayerLostSanity", keepSanityFull)
LocalPlayer:GetAttributeChangedSignal("Sanity"):Connect(keepSanityFull)
RunService.Heartbeat:Connect(keepSanityFull)

-- ==========================================
-- إنشاء واجهة الزر (UI Creation)
-- ==========================================

local ScreenGui = Instance.new("ScreenGui")
local ToggleButton = Instance.new("TextButton")
local UICorner = Instance.new("UICorner")

-- تحديد مكان وضع الزر (في الـ CoreGui لضمان ثباته)
local ParentUI = game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")
ScreenGui.Parent = ParentUI
ScreenGui.ResetOnSpawn = false

-- تصميم الزر
ToggleButton.Name = "SanityToggleBtn"
ToggleButton.Parent = ScreenGui
ToggleButton.Size = UDim2.new(0, 130, 0, 45)
ToggleButton.Position = UDim2.new(0.05, 0, 0.4, 0) -- يظهر في يسار الشاشة بالمنتصف
ToggleButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50) -- أحمر (إيقاف)
ToggleButton.Text = "Sanity: OFF"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Font = Enum.Font.SourceSansBold
ToggleButton.TextSize = 18
ToggleButton.BorderSizePixel = 0

-- جعل حواف الزر دائرية وجميلة
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = ToggleButton

-- برمجة ميزة سحب وتحريك الزر على الشاشة
local UserInputService = game:GetService("UserInputService")
local dragging, dragInput, dragStart, startPos

local function update(input)
 local delta = input.Position - dragStart
 ToggleButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

ToggleButton.InputBegan:Connect(function(input)
 if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
  dragging = true
  dragStart = input.Position
  startPos = ToggleButton.Position
  
  input.Changed:Connect(function()
   if input.UserInputState == Enum.UserInputState.End then
    dragging = false
   end
  end)
 end
end)

ToggleButton.InputChanged:Connect(function(input)
 if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
  dragInput = input
 end
end)

UserInputService.InputChanged:Connect(function(input)
 if input == dragInput and dragging then
  update(input)
 end
end)

-- برمجة ضغطة الزر للتفعيل والإيقاف
ToggleButton.MouseButton1Click:Connect(function()
 sanityEnabled = not sanityEnabled
 if sanityEnabled then
  -- تغيير اللون للأخضر وتفعيل الحماية
  ToggleButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
  ToggleButton.Text = "Sanity: ON"
  keepSanityFull() -- تشغيل فوري عند الضغط
 else
  -- تغيير اللون للأحمر وإيقاف الحماية
  ToggleButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
  ToggleButton.Text = "Sanity: OFF"
 end
end)
