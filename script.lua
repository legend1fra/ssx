local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local SetObjectiveEvent = ReplicatedStorage:WaitForChild("Util"):WaitForChild("Net"):WaitForChild("RE/SetObjective")

-- ==========================================
-- قائمة الأدوية المتاحة في اللعبة
-- ==========================================
local medicalItems = {
    "IV Drops", "Eye Drops", "Medicine", "Herbs", 
    "Antibiotics", "Bandages", "Ointment", "Cough Syrup"
}

-- ==========================================
-- دوال البحث الأساسية
-- ==========================================
local function findPatientTarget()
    local folders = {workspace:FindFirstChild("Patients"), workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Misc"), workspace}
    for _, folder in ipairs(folders) do
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Model") and (child:FindFirstChild("Humanoid") or string.find(child.Name:lower(), "patient")) then
                    return child
                end
            end
        end
    end
    return nil
end

local function findItemAndPrompt(itemName)
    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            if string.find(descendant.ObjectText:lower(), itemName:lower()) or string.find(descendant.ActionText:lower(), itemName:lower()) then
                return descendant.Parent, descendant
            end
        end
    end
    return nil, nil
end

local function interactWithComputer()
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and (string.find(desc.ObjectText:lower(), "inspect") or string.find(desc.ActionText:lower(), "inspect") or string.find(desc.Parent.Name:lower(), "computer")) then
            return desc.Parent, desc
        end
    end
    return nil, nil
end

-- ==========================================
-- دالة قراءة الشاشات المعلقة على الحائط (Workspace) لمعرفة الدواء
-- ==========================================
local function getDiagnosisFromMonitor()
    print(" جاري فحص الشاشات المعلقة في العيادة...")
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            if obj.Text and obj.Text ~= "" then
                local onScreenText = obj.Text:lower()
                for _, med in ipairs(medicalItems) do
                    if string.find(onScreenText, med:lower()) then
                        return med
                    end
                end
            end
        end
    end
    return nil
end

-- ==========================================
-- دالة المشي ورسم المسار الذكي
-- ==========================================
local function walkToTarget(targetInstance)
    if not targetInstance then return end
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart or humanoid.Health <= 0 then return end
    
    local targetPosition = targetInstance:IsA("BasePart") and targetInstance.Position or (targetInstance:IsA("Model") and targetInstance.PrimaryPart and targetInstance.PrimaryPart.Position) or targetInstance:GetModelCFrame().Position
    
    local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4})
    pcall(function() path:ComputeAsync(rootPart.Position, targetPosition) end)
    
    if path.Status == Enum.PathStatus.Success then
        for _, waypoint in ipairs(path:GetWaypoints()) do
            if humanoid.Health <= 0 then break end
            humanoid:MoveTo(waypoint.Position)
            if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
            humanoid.MoveToFinished:Wait()
        end
    else
        humanoid:MoveTo(targetPosition)
    end
end

-- ==========================================
-- دالة تفعيل ProximityPrompt بضغط مطول
-- ==========================================
local function holdProximityPrompt(prompt, duration)
    if not prompt then return false end
    duration = duration or 1
    
    if fireproximityprompt then
        -- محاولة 1: استخدام fireproximityprompt المباشر
        fireproximityprompt(prompt)
        task.wait(duration)
        return true
    elseif prompt.PromptButtonHoldBegan and prompt.PromptButtonHoldEnded then
        -- محاولة 2: محاكاة ضغط مطول عبر الأحداث
        prompt:InputBegan(Enum.UserInputType.Touch)
        task.wait(duration)
        prompt:InputEnded(Enum.UserInputType.Touch)
        return true
    elseif prompt.Triggered then
        -- محاولة 3: تفعيل الحدث مباشرة
        prompt:Fire()
        task.wait(duration)
        return true
    end
    
    return false
end

-- ==========================================
-- الاستماع للمهمات وإدارة الدورة الكاملة
-- ==========================================
SetObjectiveEvent.OnClientEvent:Connect(function(objectiveText, unusedVar, targetInstance)
    if targetInstance and typeof(targetInstance) == "Instance" then
        task.spawn(function() walkToTarget(targetInstance) end)
        return
    end
    
    if typeof(objectiveText) == "string" then
        local lowerText = objectiveText:lower()
        
        if string.find(lowerText, "treat") and string.find(lowerText, "patient") then
            task.spawn(function()
                -- 1. التوجه للمريض
                local patient = findPatientTarget()
                if patient then
                    print(" التوجه للمريض لعمل الفحص المبدئي...")
                    walkToTarget(patient)
                    task.wait(1)
                end
                
                -- 2. التوجه للكمبيوتر للتحليل
                local compPart, compPrompt = interactWithComputer()
                if compPart and compPrompt then
                    print(" التوجه للكمبيوتر للتحليل...")
                    walkToTarget(compPart)
                    task.wait(0.3)
                    -- استخدام ضغط مطول للكمبيوتر (مثل نظام الفحص)
                    holdProximityPrompt(compPrompt, 1.5)
                    
                    -- 3. انتظار الشاشة لتتحدث وقراءة التشخيص
                    task.wait(2.5) -- انتظار كافٍ لظهور النص على الشاشة المعلقة
                    local requiredMedicine = getDiagnosisFromMonitor()
                    
                    if requiredMedicine then
                        print(" التحليل مكتمل! الدواء المطلوب هو: " .. requiredMedicine)
                        
                        -- 4. الذهاب للدواء الصحيح
                        local itemObject, prompt = findItemAndPrompt(requiredMedicine)
                        if itemObject and prompt then
                            walkToTarget(itemObject)
                            task.wait(0.5)
                            -- استخدام ضغط مطول لأخذ الدواء (مثل الكمبيوتر تماماً)
                            print(" جاري أخذ الدواء بضغط مطول...")
                            holdProximityPrompt(prompt, 1.5)
                            print(" تم سحب الدواء!")
                            
                            task.wait(1)
                            
                            -- 5. العودة للمريض وإعطائه الدواء
                            if patient then
                                print(" العودة للمريض لإعطائه العلاج...")
                                walkToTarget(patient)
                                task.wait(0.5)
                                
                                -- البحث عن زر الإعطاء الخاص بالمريض
                                local givePrompt = patient:FindFirstChildOfClass("ProximityPrompt") or patient:FindFirstChild("ProximityPrompt", true)
                                if givePrompt then
                                    print(" جاري إعطاء الدواء للمريض بضغط مطول...")
                                    holdProximityPrompt(givePrompt, 1.5)
                                            print("🎉 تمت معالجة المريض بنجاح!")
                                else
                                    warn("⚠️ وصلت للمريض ولكن لم أجد زر إعطاء الدواء.")
                                end
                            end
                        else
                            warn("❌ لم أتمكن من إيجاد مكان الدواء: " .. requiredMedicine)
                        end
                    else
                        warn("❌ لم أتمكن من قراءة الشاشة، أو الدواء غير موجود في القائمة!")
                    end
                end
            end)
        end
    end
end)

print("🚀 تم تشغيل السكربت المحدث بنجاح! جاهز لمعالجة المرضى.")
