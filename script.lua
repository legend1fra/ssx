local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Network = Lib.Network

local SetObjectiveEvent = ReplicatedStorage:WaitForChild("Util"):WaitForChild("Net"):WaitForChild("RE/SetObjective")

-- ==========================================
-- متغيرات لتحسين الأداء
-- ==========================================
local cachedPrompts = {}
local lastCacheTime = 0
local CACHE_DURATION = 2 -- تحديث الكاش كل ثانيتين

-- ==========================================
-- قائمة الأدوية المتاحة في اللعبة
-- ==========================================
local medicalItems = {
    "IV Drops", "Eye Drops", "Medicine", "Herbs", 
    "Antibiotics", "Bandages", "Ointment", "Cough Syrup"
}

-- ==========================================
-- دوال البحث المحسّنة مع التخزين المؤقت
-- ==========================================
local function updatePromptCache()
    local currentTime = tick()
    if currentTime - lastCacheTime < CACHE_DURATION then
        return -- لا تحدث الكاش إذا لم تمض المدة الكافية
    end
    
    cachedPrompts = {}
    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            cachedPrompts[descendant] = {
                ObjectText = descendant.ObjectText:lower(),
                ActionText = descendant.ActionText:lower(),
                Parent = descendant.Parent,
                Instance = descendant
            }
        end
    end
    lastCacheTime = currentTime
end

-- ==========================================
-- دوال البحث الأساسية
-- ==========================================
local function findPatientTarget()
    -- البحث في الـ Tags أولاً (أسرع)
    local patients = CollectionService:GetTagged("Patient") or {}
    if #patients > 0 then return patients[1] end
    
    -- البحث التقليدي كحل بديل
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
    updatePromptCache()
    
    for _, data in pairs(cachedPrompts) do
        if string.find(data.ObjectText, itemName:lower()) or string.find(data.ActionText, itemName:lower()) then
            return data.Parent, data.Instance
        end
    end
    return nil, nil
end

local function interactWithComputer()
    updatePromptCache()
    
    -- البحث الأول: ابحث عن "inspect" بالضبط
    for _, data in pairs(cachedPrompts) do
        local objText = data.ObjectText
        local actText = data.ActionText
        local parentName = data.Parent.Name:lower()
        
        if (string.find(objText, "inspect") and #objText < 50) or 
           (string.find(actText, "inspect") and #actText < 50) or
           (string.find(parentName, "computer") or string.find(parentName, "console")) then
            print(" وجدت الكمبيوتر: " .. data.Parent.Name)
            return data.Parent, data.Instance
        end
    end
    
    -- البحث الثاني: ابحث عن أي شيء يتعلق بـ "examine" أو "look"
    for _, data in pairs(cachedPrompts) do
        if string.find(data.ObjectText, "examine") or string.find(data.ActionText, "examine") or
           string.find(data.ObjectText, "look") or string.find(data.ActionText, "look") then
            print(" وجدت جهاز فحص: " .. data.Parent.Name)
            return data.Parent, data.Instance
        end
    end
    
    return nil, nil
end


-- ==========================================
-- دالة قراءة التشخيص من الشاشة (محسّنة جداً)
--==========================================
local function getDiagnosisFromMonitor()
    print(" جاري قراءة نتيجة الفحص...")
    
    -- البحث 1: ابحث في TextLabels الكبيرة (عادة ما تكون فيها النتائج)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            if obj.Text and obj.Text ~= "" and obj.TextSize and obj.TextSize >= 14 then
                local screenText = obj.Text:lower()
                local screenLength = string.len(screenText)
                
                -- ابحث عن الأدوية
                for _, medicine in ipairs(medicalItems) do
                    local medicineLower = medicine:lower()
                    if string.find(screenText, medicineLower) then
                        -- تأكد أن النص ليس طويل جداً (كي لا يكون معلومات غير ذات صلة)
                        if screenLength < 200 then
                            print(" تم العثور على التشخيص: " .. medicine)
                            return medicine
                        end
                    end
                end
            end
        end
    end
    
    -- البحث 2: ابحث في أي TextLabel بدون قيود الحجم
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            if obj.Text and obj.Text ~= "" and string.len(obj.Text) < 300 then
                local screenText = obj.Text:lower()
                
                for _, medicine in ipairs(medicalItems) do
                    if string.find(screenText, medicine:lower()) then
                        print(" تم العثور على التشخيص: " .. medicine)
                        return medicine
                    end
                end
            end
        end
    end
    
    print(" لم أتمكن من قراءة التشخيص بعد")
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
-- دالة تفعيل ProximityPrompt بطرق متعددة
-- ==========================================
local function activatePrompt(prompt, duration)
    if not prompt then 
        warn(" Prompt غير موجود")
        return false 
    end
    
    duration = duration or 1
    local activated = false
    
    -- المحاولة 1: استخدام fireproximityprompt (الأسرع والأكثر موثوقية)
    if fireproximityprompt then
        pcall(function()
            print(" محاولة: fireproximityprompt")
            fireproximityprompt(prompt)
            task.wait(duration)
            activated = true
        end)
        if activated then return true end
    end
    
    -- المحاولة 2: محاكاة الضغط المطول عبر UserInputService
    local UserInputService = game:GetService("UserInputService")
    if UserInputService then
        pcall(function()print(" محاولة: UserInputService بضغط مطول")
            -- محاكاة الضغط على Enter (الزر الافتراضي)
            UserInputService:SendKeyEvent(true, Enum.KeyCode.E, false)
            task.wait(duration)
            UserInputService:SendKeyEvent(false, Enum.KeyCode.E, false)
            activated = true
        end)
        if activated then return true end
    end
    
    -- المحاولة 3: تفعيل الحدث PromptTriggered مباشرة
    if prompt.Triggered then
        pcall(function()
            print(" محاولة: Triggered event")
            prompt:Fire()
            task.wait(duration)
            activated = true
        end)
        if activated then return true end
    end
    
    -- المحاولة 4: محاكاة InputBegan و InputEnded مع Touch
    if prompt.PromptButtonHoldBegan then
        pcall(function()
            print(" محاولة: PromptButtonHoldBegan")
            prompt.PromptButtonHoldBegan:Fire()
            task.wait(duration)
            if prompt.PromptButtonHoldEnded then
                prompt.PromptButtonHoldEnded:Fire()
            end
            activated = true
        end)
        if activated then return true end
    end
    
    -- المحاولة 5: التعديل المباشر على خصائص Prompt
    if prompt.ActionText then
        pcall(function()
            print(" محاولة: تعديل الخصائص والتفعيل")
            local oldActionText = prompt.ActionText
            prompt.ActionText = oldActionText
            task.wait(0.1)
            
            if prompt.Triggered then
                prompt.Triggered:Connect(function()
                    print(" تم التفعيل بنجاح!")
                end)
                prompt:Fire()
            end
            task.wait(duration)
            activated = true
        end)
        if activated then return true end
    end
    
    if not activated then
        warn(" فشلت جميع محاولات التفعيل للـ Prompt")
    end
    
    return activated
end

-- ==========================================
-- الاستماع للمهمات وإدارة الدورة الكاملة (محسّنة)
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
                local success = false
                local maxRetries = 2
                local attempt = 0
                
                while attempt < maxRetries and not success do
                    attempt = attempt + 1
                    print(" محاولة " .. attempt .. " من " .. maxRetries)
                    
                    -- 1. التوجه للمريض
                    local patient = findPatientTarget()
                    if not patient then
                        warn(" لم أجد المريض")
                        task.wait(1)
                        continue
                    end
                    
                    print(" التوجه للمريض...")
                    walkToTarget(patient)
                    task.wait(0.8)
                    
                    -- 2. التوجه للكمبيوتر والتحليل
                    local compPart, compPrompt = interactWithComputer()
                    if not compPart or not compPrompt then
                        warn(" لم أجد الكمبيوتر")
                        task.wait(1)
                        continue
                    end
                    
                    print(" التوجه للكمبيوتر...")
                    walkToTarget(compPart)
                    task.wait(0.5) -- زيادة الانتظار قليلاً
                    
                    -- تفعيل الكمبيوتر مع محاولات متعددة
                    print(" جاري تفعيل جهاز الفحص...")
                    local computerActivated = false
                    for tryCount = 1, 3 do
                        print("  محاولة تفعيل " ..
         tryCount .. " من 3")
                        computerActivated = activatePrompt(compPrompt, 1.5)
                        if computerActivated then
                            print(" تم تفعيل جهاز الفحص بنجاح!")
                            break
                        end
                        task.wait(0.5)
                    end
                    
                    if not computerActivated then
                        warn(" فشل تفعيل جهاز الفحص بعد 3 محاولات")
                        task.wait(1)
                        continue
                    end
                    
                    -- 3. انتظار ظهور النتيجة وقراءتها
                    print(" جاري انتظار نتيجة الفحص...")
                    local diagnosis = nil
                    for i = 1, 8 do -- 8 محاولات × 0.5 ثانية = 4 ثواني
                        task.wait(0.5)
                        diagnosis = getDiagnosisFromMonitor()
                        if diagnosis then
                            print(" تم الحصول على النتيجة!")
                            break
                        end
                        if i % 2 == 0 then print("  ...جاري البحث " .. i .. "/8") end
                    end
                    
                    if not diagnosis then
                        warn(" فشل قراءة التشخيص بعد الانتظار")
                        task.wait(1)
                        continue
                    end
                    
                    print(" الدواء المطلوب: " .. diagnosis)
                    
                    -- 4. البحث عن الدواء والذهاب إليه
                    local medicineObject, medicinePrompt = findItemAndPrompt(diagnosis)
                    if not medicineObject or not medicinePrompt then
                        warn(" لم أجد الدواء: " .. diagnosis)
                        task.wait(1)
                        continue
                    end
                    
                    print(" التوجه لأخذ الدواء: " .. diagnosis)
                    walkToTarget(medicineObject)
                    task.wait(0.5)
                    
                    -- تفعيل أخذ الدواء مع محاولات متعددة
                    print(" جاري أخذ الدواء بضغط مطول...")
                    local medicineActivated = false
                    for tryCount = 1, 3 do
                        print("  محاولة أخذ الدواء " .. tryCount .. " من 3")
                        medicineActivated = activatePrompt(medicinePrompt, 1.5)
                        if medicineActivated then
                            print(" تم سحب الدواء بنجاح!")
                            break
                        end
                        task.wait(0.5)
                    end
                    
                    if not medicineActivated then
                        warn(" فشل أخذ الدواء بعد 3 محاولات")
                        task.wait(1)
                        continue
                    end
                    
                    task.wait(0.8)
                    
                    -- 5. العودة للمريض وإعطاء الدواء
                    print(" العودة للمريض...")
                    walkToTarget(patient)
                    task.wait(0.5)
                    
                    -- البحث عن زر الإعطاء
                    local givePrompt = patient:FindFirstChildOfClass("ProximityPrompt") or patient:FindFirstChild("ProximityPrompt", true)
                    if not givePrompt then
                        warn(" لم أجد زر إعطاء الدواء")
                        task.wait(1)
                        continue
                    end
                    
                    -- إعطاء الدواء
                    print(" جاري إعطاء الدواء للمريض...")
                    local giveActivated = false
                    for tryCount = 1, 3 do
                        print("  محاولة إعطاء الدواء " .. tryCount .. " من 3")
                        giveActivated = activatePrompt(givePrompt, 1.5)
                        if giveActivated then
                            print(" تم إعطاء الدواء بنجاح!")
                            break
         end
                        task.wait(0.5)
                    end
                    
                    if giveActivated then
                        print("🎉 تمت معالجة المريض بنجاح!")
                        success = true
                    else
                        warn("⚠️ فشل إعطاء الدواء بعد 3 محاولات")
                        task.wait(1)
                    end
                end
                
                if not success then
                    warn("❌ فشلت المهمة بعد " .. maxRetries .. " محاولات")
                end
            end)
        end
    end
end)

print("🚀 تم تشغيل السكربت المحسّن بنجاح!")
print("📍 معلومات السكربت:")
print("  ✓ محاكاة ضغط مطول محسّنة")
print("  ✓ بحث ذكي عن العناصر")
print("  ✓ إعادة محاولة تلقائية عند الفشل")
print("  ✓ رسائل تشخيصية مفصلة")
print("⏳ في انتظار المهام...")
