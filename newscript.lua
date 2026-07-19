local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Library = require(ReplicatedStorage:WaitForChild("Lib"))
local LocalPlayer = Players.LocalPlayer

local NPCsFolder = workspace:WaitForChild("NPCs")

-- ==========================================
-- 1. نظام الحماية (Sanity) التلقائي
-- ==========================================
local function keepSanityFull()
    LocalPlayer:SetAttribute("Sanity", 100)
end

keepSanityFull()
Library.Inject("PlayerLostSanity", keepSanityFull)
LocalPlayer:GetAttributeChangedSignal("Sanity"):Connect(keepSanityFull)
RunService.Heartbeat:Connect(keepSanityFull)

-- ==========================================
-- 2. دالة الـ ESP الأساسية (للمجسمات والنصوص)
-- ==========================================
local function applyESP(model, color, topText)
    if model:FindFirstChild("ESPHighlight") then return end
    
    -- إنشاء التحديد (Highlight)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESPHighlight"
    highlight.FillColor = color
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = model
    
    -- إنشاء النص العائم (BillboardGui)
    if topText then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ESPTextGui"
        billboard.Adornee = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model
        billboard.Size = UDim2.new(0, 150, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
        billboard.AlwaysOnTop = true
        
        local textLabel = Instance.new("TextLabel")
        textLabel.Parent = billboard
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = topText
        textLabel.TextColor3 = color
        textLabel.TextStrokeTransparency = 0 -- حدود سوداء للنص ليكون مقروءاً
        textLabel.Font = Enum.Font.SourceSansBold
        textLabel.TextSize = 16
        
        billboard.Parent = model
    end
end

-- ==========================================
-- 3. نظام ESP الخاص بالشخصيات (NPCs)
-- ==========================================
local function checkNPC(obj)
    if not obj:IsA("Model") then return end

    local isPatient = obj:GetAttribute("IsPatient")
    local roomName = obj:GetAttribute("DesignatedRoom")

    if isPatient == true then
        applyESP(obj, Color3.fromRGB(50, 255, 50), "🩺 " .. tostring(roomName or "Patient"))
    else
        applyESP(obj, Color3.fromRGB(120, 140, 255), "👤 NPC")
    end
end

for _, obj in pairs(NPCsFolder:GetChildren()) do checkNPC(obj) end
NPCsFolder.ChildAdded:Connect(function(obj)
    task.wait(0.5)
    checkNPC(obj)
end)

-- ==========================================
-- 4. نظام التحليل والعلاج التلقائي للمريض
-- ==========================================
local trackedPatients = {}
local inventoryOrder = {}
local inventoryItems = {}

local function getTreatmentIcon(treatmentName)
    local icons = {
        Herbs = "🌿",
        Medicine = "💊",
        Bandage = "🩹",
        Antibiotics = "🧪",
        Oxygen = "🫁",
        IV = "🩸",
        Injection = "💉",
        Surgery = "🛠️"
    }

    return icons[treatmentName] or "🧾"
end

local function getRoomTreatments(roomName)
    if not roomName or roomName == "" then return {} end

    local roomsFolder = workspace:FindFirstChild("Rooms")
    local medicalFolder = roomsFolder and roomsFolder:FindFirstChild("Medical")
    local targetRoom = medicalFolder and medicalFolder:FindFirstChild(roomName)
    local minigame = targetRoom and targetRoom:FindFirstChild("Minigame")
    local tv = minigame and minigame:FindFirstChild("TV")
    local screen = tv and tv:FindFirstChild("Screen")
    local ui = screen and screen:FindFirstChild("UI")
    local report = ui and ui:FindFirstChild("Report")
    local inv = report and report:FindFirstChild("inv")

    if not inv then return {} end

    local treatments = {}
    for _, child in ipairs(inv:GetChildren()) do
        if child:IsA("Folder") and child.Name ~= "UIGridLayout" and child.Name ~= "_Properties" then
            table.insert(treatments, child.Name)
        end
    end

    return treatments
end

local function getRequiredTreatments(patientModel)
    local patientName = tostring(patientModel.Name or "")
    local roomName = tostring(patientModel:GetAttribute("DesignatedRoom") or "")
    local lowerName = string.lower(patientName)

    if string.find(lowerName, "shirley") then
        return {"Herbs"}
    elseif string.find(lowerName, "jojo") then
        return {"Medicine"}
    end

    local roomTreatments = getRoomTreatments(roomName)
    if #roomTreatments > 0 then
        return roomTreatments
    end

    if string.find(string.lower(roomName), "room1") then
        return {"Herbs"}
    elseif string.find(string.lower(roomName), "room2") then
        return {"Medicine"}
    end

    return {}
end

local function createTreatmentOverlay(patientModel, treatments)
    if patientModel:FindFirstChild("AutoTreatmentGui") then return end

    local rootPart = patientModel:FindFirstChild("HumanoidRootPart") or patientModel.PrimaryPart or patientModel:FindFirstChild("Head") or patientModel
    if not rootPart then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "AutoTreatmentGui"
    billboard.Adornee = rootPart
    billboard.Size = UDim2.new(0, 220, 0, 70)
    billboard.StudsOffset = Vector3.new(0, 4.2, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = patientModel

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Parent = billboard

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0.45, 0)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Treatment"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextStrokeTransparency = 0.2
    titleLabel.Font = Enum.Font.SourceSansBold
    titleLabel.TextSize = 15
    titleLabel.Parent = frame

    local treatmentLabel = Instance.new("TextLabel")
    treatmentLabel.Size = UDim2.new(1, 0, 0.55, 0)
    treatmentLabel.Position = UDim2.new(0, 0, 0.45, 0)
    treatmentLabel.BackgroundTransparency = 1
    treatmentLabel.Text = table.concat(treatments, " + ")
    treatmentLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    treatmentLabel.TextStrokeTransparency = 0.2
    treatmentLabel.Font = Enum.Font.SourceSansBold
    treatmentLabel.TextSize = 17
    treatmentLabel.Parent = frame

    return treatmentLabel
end

local function ensureInventoryGui()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = playerGui:FindFirstChild("AutoTreatInventory")

    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "AutoTreatInventory"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
    end

    return screenGui
end

local function refreshInventoryLayout()
    for index, treatmentName in ipairs(inventoryOrder) do
        local item = inventoryItems[treatmentName]
        if item then
            item.Position = UDim2.new(0, 10, 0, 36 + ((index - 1) * 38))
        end
    end
end

local function addInventoryItem(treatmentName)
    if inventoryItems[treatmentName] then return end

    local screenGui = ensureInventoryGui()
    local inventoryFrame = screenGui:FindFirstChild("InventoryFrame")

    if not inventoryFrame then
        inventoryFrame = Instance.new("Frame")
        inventoryFrame.Name = "InventoryFrame"
        inventoryFrame.Size = UDim2.new(0, 260, 0, 140)
        inventoryFrame.Position = UDim2.new(0, 20, 0, 20)
        inventoryFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        inventoryFrame.BackgroundTransparency = 0.2
        inventoryFrame.BorderSizePixel = 0
        inventoryFrame.Parent = screenGui

        local header = Instance.new("TextLabel")
        header.Name = "Header"
        header.Size = UDim2.new(1, -10, 0, 24)
        header.Position = UDim2.new(0, 5, 0, 5)
        header.BackgroundTransparency = 1
        header.Text = "Auto Inventory"
        header.TextColor3 = Color3.fromRGB(255, 255, 255)
        header.Font = Enum.Font.SourceSansBold
        header.TextSize = 16
        header.Parent = inventoryFrame
    end

    local itemFrame = Instance.new("Frame")
    itemFrame.Name = treatmentName
    itemFrame.Size = UDim2.new(0, 240, 0, 30)
    itemFrame.Position = UDim2.new(0, 10, 0, 36 + ((#inventoryOrder) * 38))
    itemFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    itemFrame.BorderSizePixel = 0
    itemFrame.Parent = inventoryFrame

    local iconLabel = Instance.new("TextLabel")
    iconLabel.Size = UDim2.new(0, 26, 0, 26)
    iconLabel.Position = UDim2.new(0, 6, 0, 2)
    iconLabel.BackgroundTransparency = 1
    iconLabel.Text = getTreatmentIcon(treatmentName)
    iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    iconLabel.Font = Enum.Font.SourceSansBold
    iconLabel.TextSize = 16
    iconLabel.Parent = itemFrame

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -40, 1, 0)
    nameLabel.Position = UDim2.new(0, 36, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = treatmentName
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.Font = Enum.Font.SourceSansBold
    nameLabel.TextSize = 14
    nameLabel.Parent = itemFrame

    table.insert(inventoryOrder, treatmentName)
    inventoryItems[treatmentName] = itemFrame
end

local function removeInventoryItem(treatmentName)
    local item = inventoryItems[treatmentName]
    if not item then return end

    item:Destroy()
    inventoryItems[treatmentName] = nil

    for index, currentName in ipairs(inventoryOrder) do
        if currentName == treatmentName then
            table.remove(inventoryOrder, index)
            break
        end
    end

    refreshInventoryLayout()
end

local function trackPatient(patientModel)
    if trackedPatients[patientModel] then return end

    local treatments = getRequiredTreatments(patientModel)
    local overlayLabel = createTreatmentOverlay(patientModel, treatments)

    if #treatments > 0 then
        for _, treatmentName in ipairs(treatments) do
            addInventoryItem(treatmentName)
        end
    else
        if overlayLabel then
            overlayLabel.Text = "Awaiting diagnosis"
            overlayLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
        end
    end

    trackedPatients[patientModel] = {
        treatments = treatments,
        delivered = false,
        overlayLabel = overlayLabel
    }
end

local function autoTreatPatient(patientModel, patientData)
    if patientData.delivered then return end

    local patientRoot = patientModel:FindFirstChild("HumanoidRootPart") or patientModel.PrimaryPart or patientModel:FindFirstChild("Head")
    local characterRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

    if not patientRoot or not characterRoot then return end

    local distance = (patientRoot.Position - characterRoot.Position).Magnitude
    if distance > 12 then return end

    for _, treatmentName in ipairs(patientData.treatments) do
        if inventoryItems[treatmentName] then
            removeInventoryItem(treatmentName)
            patientData.delivered = true
            if patientData.overlayLabel then
                patientData.overlayLabel.Text = "Delivered: " .. treatmentName
                patientData.overlayLabel.TextColor3 = Color3.fromRGB(80, 255, 120)
            end
            break
        end
    end
end

RunService.Heartbeat:Connect(function()
    for patientModel, patientData in pairs(trackedPatients) do
        if patientModel and patientModel.Parent then
            autoTreatPatient(patientModel, patientData)
        end
    end
end)

local function handlePatientModel(obj)
    if not obj:IsA("Model") then return end

    local isPatient = obj:GetAttribute("IsPatient")
    if isPatient == true then
        trackPatient(obj)
    end
end

for _, obj in pairs(NPCsFolder:GetChildren()) do
    handlePatientModel(obj)
end

NPCsFolder.ChildAdded:Connect(function(obj)
    task.wait(0.5)
    handlePatientModel(obj)
end)

-- ==========================================
-- 5. نظام ESP الخاص باللاعبين (Players)
-- ==========================================
local function handlePlayer(player)
    -- تجاهل اللاعب المحلي (أنت) حتى لا تتحدد شخصيتك
    if player == LocalPlayer then return end

    -- إذا كانت شخصية اللاعب موجودة بالفعل
    if player.Character then
        applyESP(player.Character, Color3.fromRGB(50, 150, 255), "👤 " .. player.Name) -- أزرق
    end

    -- عندما يموت اللاعب ويترسبن من جديد
    player.CharacterAdded:Connect(function(character)
        task.wait(0.5) -- انتظار قصير حتى يكتمل تحميل مجسم اللاعب
        applyESP(character, Color3.fromRGB(50, 150, 255), "👤 " .. player.Name)
    end)
end

-- تطبيق الـ ESP على اللاعبين الموجودين حالياً في السيرفر
for _, player in pairs(Players:GetPlayers()) do
    handlePlayer(player)
end

-- تطبيق الـ ESP على أي لاعب جديد يدخل السيرفر لاحقاً
Players.PlayerAdded:Connect(handlePlayer)