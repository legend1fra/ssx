local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Library = require(ReplicatedStorage:WaitForChild("Lib"))
local LocalPlayer = Players.LocalPlayer

local NPCsFolder = workspace:WaitForChild("NPCs")

-- Centralized heartbeat tasks to avoid multiple Heartbeat connections
local HeartbeatTasks = {}
local function registerHeartbeatTask(fn)
    table.insert(HeartbeatTasks, fn)
end

RunService.Heartbeat:Connect(function(dt)
    for _, taskFn in ipairs(HeartbeatTasks) do
        pcall(taskFn, dt)
    end
end)

-- ==========================================
-- 1) Automatic Sanity (keep full)
-- ==========================================
local function keepSanityFull()
    if LocalPlayer and LocalPlayer:GetAttribute("Sanity") ~= 100 then
        LocalPlayer:SetAttribute("Sanity", 100)
    end
end

-- Run immediately and keep it registered to events + heartbeat
keepSanityFull()
Library.Inject("PlayerLostSanity", keepSanityFull)
LocalPlayer:GetAttributeChangedSignal("Sanity"):Connect(keepSanityFull)
registerHeartbeatTask(keepSanityFull)


-- ==========================================
-- 2) Basic ESP helper (models and labels)
-- ==========================================
local function applyESP(model, color, topText)
    if not model or model:FindFirstChild("ESPHighlight") then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "ESPHighlight"
    highlight.FillColor = color
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = model

    if topText then
        local adornee = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ESPTextGui"
        billboard.Adornee = adornee
        billboard.Size = UDim2.new(0, 150, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
        billboard.AlwaysOnTop = true

        local textLabel = Instance.new("TextLabel")
        textLabel.Parent = billboard
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = topText
        textLabel.TextColor3 = color
        textLabel.TextStrokeTransparency = 0
        textLabel.Font = Enum.Font.SourceSansBold
        textLabel.TextSize = 16
        billboard.Parent = model
    end
end


-- ==========================================
-- 3) NPC ESP and patient tracking
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

local function findRoomByName(root, name)
    for _, child in ipairs(root:GetChildren()) do
        if child.Name == name then
            return child
        end
        local found = findRoomByName(child, name)
        if found then
            return found
        end
    end
    return nil
end

local function findDescendantByName(root, name)
    for _, d in ipairs(root:GetDescendants()) do
        if d.Name == name then return d end
    end
    return nil
end

local function getRoomTreatments(roomName)
    if not roomName or roomName == "" then return {} end

    -- Try to locate the room anywhere under workspace (handles different project layouts)
    local targetRoom = findRoomByName(workspace, roomName)

    -- Fallback: try case-insensitive partial match on descendant names
    if not targetRoom then
        local lowerNeed = string.lower(roomName)
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Folder") or d:IsA("Model") then
                if string.find(string.lower(d.Name), lowerNeed) then
                    targetRoom = d
                    break
                end
            end
        end
    end

    if not targetRoom then return {} end

    -- Look for an "inv" container anywhere under the found room
    local inv = findDescendantByName(targetRoom, "inv")
    if not inv then
        -- Also try common report/ui path inside the room
        local report = findDescendantByName(targetRoom, "Report")
        inv = report and findDescendantByName(report, "inv") or nil
    end

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
    if #roomTreatments > 0 then return roomTreatments end

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
    -- Also give the player a usable tool for this treatment so they don't have to fetch it
    giveTreatmentToPlayer(treatmentName)
end

local function giveTreatmentToPlayer(treatmentName)
    if not LocalPlayer then return end
    local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer:WaitForChild("Backpack")
    if not backpack then return end

    -- Avoid duplicating tools
    if backpack:FindFirstChild(treatmentName) or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild(treatmentName)) then
        return
    end

    local success, err = pcall(function()
        local tool = Instance.new("Tool")
        tool.Name = treatmentName
        tool.RequiresHandle = true

        local handle = Instance.new("Part")
        handle.Name = "Handle"
        handle.Size = Vector3.new(0.4, 0.4, 0.4)
        handle.Transparency = 1
        handle.CanCollide = false
        handle.Parent = tool

        tool.Parent = backpack
    end)
    if not success then
        warn("Failed to give treatment tool:", err)
    end
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
    -- Remove tool from Backpack/Character when consumed
    if LocalPlayer then
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
            local t = backpack:FindFirstChild(treatmentName)
            if t then t:Destroy() end
        end
        if LocalPlayer.Character then
            local ct = LocalPlayer.Character:FindFirstChild(treatmentName)
            if ct then ct:Destroy() end
        end
    end
end

local function trackPatient(patientModel)
    if trackedPatients[patientModel] then return end
    local treatments = getRequiredTreatments(patientModel)
    local overlayLabel = createTreatmentOverlay(patientModel, treatments)
    if #treatments > 0 then
        for _, treatmentName in ipairs(treatments) do addInventoryItem(treatmentName) end
    else
        if overlayLabel then
            overlayLabel.Text = "Awaiting diagnosis"
            overlayLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
        end
    end
    trackedPatients[patientModel] = { treatments = treatments, delivered = false, overlayLabel = overlayLabel }
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

-- Register patient auto-treat logic on heartbeat
registerHeartbeatTask(function()
    for patientModel, patientData in pairs(trackedPatients) do
        if patientModel and patientModel.Parent then
            autoTreatPatient(patientModel, patientData)
        end
    end
end)

local function isPatientModel(obj)
    if not obj or not obj:IsA("Model") then return false end

    local value = obj:GetAttribute("IsPatient")
    if value == true then
        return true
    end

    if type(value) == "string" then
        local normalized = string.lower(value)
        return normalized == "true" or normalized == "1" or normalized == "yes"
    end

    return false
end

local function handlePatientModel(obj)
    if not isPatientModel(obj) then return end

    applyESP(obj, Color3.fromRGB(0, 200, 120), "🧑‍⚕️ Patient")
    trackPatient(obj)
end

for _, obj in pairs(NPCsFolder:GetChildren()) do handlePatientModel(obj) end
NPCsFolder.ChildAdded:Connect(function(obj)
    task.wait(0.5)
    handlePatientModel(obj)
end)


-- ==========================================
-- 4) Players ESP
-- ==========================================
local function handlePlayer(player)
    if player == LocalPlayer then return end
    if player.Character then
        applyESP(player.Character, Color3.fromRGB(50, 150, 255), "👤 " .. player.Name)
    end
    player.CharacterAdded:Connect(function(character)
        task.wait(0.5)
        applyESP(character, Color3.fromRGB(50, 150, 255), "👤 " .. player.Name)
    end)
end

for _, player in pairs(Players:GetPlayers()) do handlePlayer(player) end
Players.PlayerAdded:Connect(handlePlayer)
