--[[
	MobTelegraphAttacksServer (Script, ServerScriptService)

	Серверная логика телеграф-атак — БЕЗ ИЗМЕНЕНИЙ:
	  • тайминги (наведение 1.3 с, окно уворота 0.5 с, волна шипов шаг 0.14 с);
	  • радиусы поражения (8.5 у копья, 5.6 у шипов), урон (36 / 28), отбрасывание;
	  • уворот через атрибут IsDodging и множитель DungeonDamageMultiplier;
	  • ИИ-выбор цели и кулдауны.

	Вся визуализация (руны, лазер, копьё, шипы, ударная волна, пыль, звук)
	теперь рисуется на клиенте скриптом MobAttackVFXClient по сигналам
	нового RemoteEvent ReplicatedStorage.MobAttackVFXEvent.
	Существующие RemoteEvent не переименовывались.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ================= КАНАЛ ВИЗУАЛЬНЫХ ЭФФЕКТОВ =================
local vfxEvent = ReplicatedStorage:FindFirstChild("MobAttackVFXEvent")
if not vfxEvent then
	vfxEvent = Instance.new("RemoteEvent")
	vfxEvent.Name = "MobAttackVFXEvent"
	vfxEvent.Parent = ReplicatedStorage
end

print("[MobTelegraph] Скрипт атак запущен, канал эффектов MobAttackVFXEvent создан")

local function fireVFX(kind, ...)
	vfxEvent:FireAllClients(kind, ...)
end

local function tryDamagePlayer(char, damage, knockbackDir)
	if not char or not char.Parent then return end
	if char:GetAttribute("IsDodging") == true then return end -- Уворот на Shift

	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if hum and hum.Health > 0 and root then
		-- МНОЖИТЕЛЬ УРОНА В ПАТИ (1.3x)
		local dmgMult = char:GetAttribute("DungeonDamageMultiplier") or 1.0
		-- БРОНЯ «Стойкость»: урон * (1 − DefenseLvl * 0.02)
		local defMult = math.clamp(tonumber(char:GetAttribute("DefenseMultiplier")) or 1, 0, 1)
		hum:TakeDamage(damage * dmgMult * defMult)

		if knockbackDir then
			root.AssemblyLinearVelocity = knockbackDir
		end
	end
end

-- ================= 1. КРИСТАЛЬНОЕ КОПЬЁ (ЛЕТАЮЩИЙ КРИСТАЛЛ) =================
local function executeCrystalStrike(crystalModel, targetChar)
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	local crystalRoot = crystalModel:FindFirstChild("HumanoidRootPart") or crystalModel.PrimaryPart or crystalModel:FindFirstChildWhichIsA("BasePart")
	if not targetRoot or not crystalRoot then return end

	-- Фаза наведения (1.3 сек преследует цель) — клиент рисует заряжающийся луч и рунный прицел
	local trackTime = 1.3
	fireVFX("CrystalCharge", crystalRoot, targetRoot, trackTime)

	local lockedPos = Vector3.new(targetRoot.Position.X, targetRoot.Position.Y - 2.85, targetRoot.Position.Z)
	local startT = os.clock()
	while os.clock() - startT < trackTime do
		if targetRoot and targetRoot.Parent and crystalRoot and crystalRoot.Parent then
			lockedPos = Vector3.new(targetRoot.Position.X, targetRoot.Position.Y - 2.85, targetRoot.Position.Z)
		end
		task.wait(0.03)
	end

	-- ФАЗА ЗАХВАТА (LOCK-ON): окно для рывка на Shift
	fireVFX("CrystalLock", crystalRoot, lockedPos, 0.5)
	task.wait(0.5)

	-- ВЗРЫВ: КОПЬЁ ИЗ-ПОД ЗЕМЛИ
	fireVFX("CrystalSpear", lockedPos)

	-- Проверка урона в радиусе поражения
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r then
			local flatDist = (Vector3.new(r.Position.X, 0, r.Position.Z) - Vector3.new(lockedPos.X, 0, lockedPos.Z)).Magnitude
			if flatDist <= 8.5 then
				tryDamagePlayer(c, 36, Vector3.new(0, 44, 0))
			end
		end
	end

	task.wait(0.7)
end

-- ================= 2. СЕЙСМИЧЕСКИЙ УДАР ГОЛЕМА =================
local function executeGolemSlam(golemModel, targetChar)
	local golemRoot = golemModel:FindFirstChild("HumanoidRootPart") or golemModel.PrimaryPart
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if not golemRoot or not targetRoot then return end

	-- Замах Голема (движение модели — серверное, как раньше)
	local originalC0 = golemRoot.CFrame
	local jumpCF = originalC0 * CFrame.new(0, 3.4, 0) * CFrame.Angles(math.rad(-22), 0, 0)
	TweenService:Create(golemRoot, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {CFrame = jumpCF}):Play()

	-- Телеграф: зарядка кулаков и растрескивающийся рунный круг под големом
	fireVFX("GolemWindup", golemRoot, 0.55, originalC0.Position.Y - 2.5)

	task.wait(0.55)

	-- Удар в пол
	TweenService:Create(golemRoot, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame = originalC0}):Play()

	-- Направление считается после замаха — как в исходной логике
	local dir = (targetRoot.Position - golemRoot.Position).Unit
	dir = Vector3.new(dir.X, 0, dir.Z).Unit

	fireVFX("GolemSlam", originalC0.Position, originalC0.Position.Y - 2.5, dir)

	local startPos = golemRoot.Position + (dir * 5)
	local spikeCount = 5
	local stepDistance = 7.5

	task.spawn(function()
		for i = 1, spikeCount do
			local currentPos = startPos + (dir * (i * stepDistance))
			local floorY = golemRoot.Position.Y - 2.5
			local spikePos = Vector3.new(currentPos.X, floorY, currentPos.Z)

			-- Раскалённая трещина-предвестник
			fireVFX("SlamWarn", spikePos, 0.55)

			task.wait(0.14) -- Волна катится вперед

			-- Скальный шип
			local h = math.random(8, 12)
			fireVFX("SlamSpike", spikePos, dir, h)

			-- Проверка попадания
			for _, p in ipairs(Players:GetPlayers()) do
				local c = p.Character
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if r then
					local dist = (Vector3.new(r.Position.X, 0, r.Position.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude
					if dist <= 5.6 then
						local knock = (dir * 42) + Vector3.new(0, 36, 0)
						tryDamagePlayer(c, 28, knock)
					end
				end
			end
		end
	end)
end

-- ================= 3. ИИ СЛЕЖЕНИЕ И ЗАПУСК =================
local function getClosestPlayer(pos, maxDist)
	local closestPlr = nil
	local minDist = maxDist or 70

	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 then
			local d = (root.Position - pos).Magnitude
			if d < minDist then
				minDist = d
				closestPlr = c
			end
		end
	end
	return closestPlr
end

local trackedMobs = {}

task.spawn(function()
	while true do
		task.wait(0.4)

		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("Model") and not trackedMobs[obj] then
				local name = obj.Name:lower()
				local isCrystal = name:find("crystal")
				local isGolem = name:find("golem") or name:find("colossus")

				if isCrystal or isGolem then
					local hum = obj:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						trackedMobs[obj] = os.clock() + math.random(2, 4)

						task.spawn(function()
							while obj.Parent and hum.Health > 0 do
								task.wait(0.5)
								local now = os.clock()
								if now >= (trackedMobs[obj] or 0) then
									local root = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
									if root then
										local targetChar = getClosestPlayer(root.Position, 75)
										if targetChar then
											print(string.format("[MobTelegraph] %s атакует %s", obj.Name, targetChar.Name))
											if isCrystal then
												executeCrystalStrike(obj, targetChar)
												trackedMobs[obj] = os.clock() + math.random(5, 7)
											elseif isGolem then
												executeGolemSlam(obj, targetChar)
												trackedMobs[obj] = os.clock() + math.random(6, 8)
											end
										end
									end
								end
							end
							trackedMobs[obj] = nil
						end)
					end
				end
			end
		end
	end
end)
