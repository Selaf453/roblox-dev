local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- RemoteEvent для спавна по кнопке Y
local spawnDebugEvent = ReplicatedStorage:FindFirstChild("SpawnMobsDebugEvent")
if not spawnDebugEvent then
	spawnDebugEvent = Instance.new("RemoteEvent")
	spawnDebugEvent.Name = "SpawnMobsDebugEvent"
	spawnDebugEvent.Parent = ReplicatedStorage
end

-- Урон по игроку с учётом брони «Стойкость» и i-frames переката (StatUpgradeServer)
local function damagePlayer(hum, amount)
	if _G.DamagePlayer then
		_G.DamagePlayer(hum, amount)
	else
		hum:TakeDamage(amount)
	end
end

-- ================= ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ =================
local function weldParts(pA, pB)
	local w = Instance.new("WeldConstraint")
	w.Part0 = pA
	w.Part1 = pB
	w.Parent = pA
end

local function makePart(parent, name, size, color, cf, canCollide, mat)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.Slate
	p.CFrame = cf
	p.CanCollide = canCollide
	p.Parent = parent
	return p
end

local function setupHumanoidClean(humanoid, maxHp)
	humanoid.MaxHealth = maxHp
	humanoid.Health = maxHp
	pcall(function()
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayDistance = 0
	end)
end

local function findNearestTarget(pos, maxDist)
	local targetChar = nil
	local minDist = maxDist or 200

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChild("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 then
			local dist = (root.Position - pos).Magnitude
			if dist < minDist then
				minDist = dist
				targetChar = char
			end
		end
	end
	return targetChar
end

-- ================= УМНЫЙ ХП-БАР =================
local function attachSmartHealthBar(mob, adorneePart)
	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid or not adorneePart then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "SmartHealthBar"
	bb.Size = UDim2.new(0, 76, 0, 9)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 65
	bb.Enabled = false
	bb.Adornee = adorneePart
	bb.Parent = mob

	local bg = Instance.new("Frame", bb)
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(26, 12, 13) -- лакированное тёмное дерево
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel = 0
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 4)

	local stroke = Instance.new("UIStroke", bg)
	stroke.Color = Color3.fromRGB(212, 170, 90) -- тонкая золотая рамка
	stroke.Thickness = 1

	local damageTrail = Instance.new("Frame", bg)
	damageTrail.Name = "DamageTrail"
	damageTrail.Size = UDim2.new(1, 0, 1, 0)
	damageTrail.BackgroundColor3 = Color3.fromRGB(255, 214, 150)
	damageTrail.BorderSizePixel = 0
	Instance.new("UICorner", damageTrail).CornerRadius = UDim.new(0, 4)

	local fill = Instance.new("Frame", bg)
	fill.Name = "HealthFill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	fill.BorderSizePixel = 0
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

	-- градиент здоровья: алый > тёмно-бордовый
	local fillGradient = Instance.new("UIGradient", fill)
	fillGradient.Color = ColorSequence.new(Color3.fromRGB(230, 44, 44), Color3.fromRGB(104, 10, 22))

	local hideToken = 0

	humanoid.HealthChanged:Connect(function(health)
		if health <= 0 then
			bb:Destroy()
			return
		end

		local maxH = humanoid.MaxHealth
		if health < maxH then
			bb.Enabled = true
			bg.BackgroundTransparency = 0.2
			stroke.Transparency = 0
			fill.BackgroundTransparency = 0
			damageTrail.BackgroundTransparency = 0

			local ratio = math.clamp(health / maxH, 0, 1)
			fill.Size = UDim2.new(ratio, 0, 1, 0)

			task.delay(0.18, function()
				if mob and mob.Parent then
					TweenService:Create(damageTrail, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Size = UDim2.new(ratio, 0, 1, 0)
					}):Play()
				end
			end)

			hideToken = hideToken + 1
			local currentToken = hideToken

			task.delay(3.0, function()
				if currentToken == hideToken and bb and bb.Parent then
					local fadeTween = TweenService:Create(bg, TweenInfo.new(0.4), {BackgroundTransparency = 1})
					TweenService:Create(stroke, TweenInfo.new(0.4), {Transparency = 1}):Play()
					TweenService:Create(fill, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
					TweenService:Create(damageTrail, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
					fadeTween:Play()
					fadeTween.Completed:Connect(function()
						if currentToken == hideToken then
							bb.Enabled = false
						end
					end)
				end
			end)
		else
			bb.Enabled = false
		end
	end)
end

-- =====================================================================
-- LOW-POLY КОНСТРУКТОР ВИЗУАЛА (японская стилистика)
-- Все декоративные детали: CanCollide/CanTouch/CanQuery = false, Massless = true,
-- намертво приварены WeldConstraint к своей «кости» (корень/голова/руки/ноги).
-- Поэтому хитбоксы, масса и физика мобов остаются прежними.
-- Лицо моба смотрит в ?Z (LookVector) — туда, куда Humanoid поворачивает корень при ходьбе.
-- =====================================================================
local MAT = Enum.Material

local COL = {
	lacquerBlack = Color3.fromRGB(26, 20, 22),
	lacquerRed   = Color3.fromRGB(138, 24, 28),
	lacquerWood  = Color3.fromRGB(58, 30, 24),
	gold         = Color3.fromRGB(212, 170, 90),
	iron         = Color3.fromRGB(52, 52, 58),
	steel        = Color3.fromRGB(206, 212, 222),
	lacing       = Color3.fromRGB(176, 30, 36),
	ivory        = Color3.fromRGB(232, 218, 184),
	cord         = Color3.fromRGB(60, 36, 84),
	voidDark     = Color3.fromRGB(14, 10, 12),
	paper        = Color3.fromRGB(242, 238, 226),
}

-- базовая декоративная деталь, приваренная к кости; localCF — в пространстве кости
local function deco(mob, bone, name, size, color, localCF, mat, shape)
	local p
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Cyl" then
			p.Shape = Enum.PartType.Cylinder
		end
	end
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or MAT.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CFrame = bone.CFrame * localCF
	p.Parent = mob

	local w = Instance.new("WeldConstraint")
	w.Part0 = bone
	w.Part1 = p
	w.Parent = p
	return p
end

-- лакированная пластина (лёгкий блик)
local function lacq(p)
	p.Reflectance = 0.08
	return p
end

-- low-poly шип из клиньев, растущий вдоль +Y от baseCF.
-- fin = true > плоский клык (2 клина, треугольник виден спереди), иначе крестовой шип (4 клина)
local function spike(mob, bone, name, baseCF, w, h, color, mat, fin)
	for k = (fin and 1 or 0), 1 do
		local r = baseCF * CFrame.Angles(0, k * math.pi / 2, 0)
		deco(mob, bone, name, Vector3.new(w, h, w / 2), color, r * CFrame.new(0, h / 2, -w / 4), mat, "Wedge")
		deco(mob, bone, name, Vector3.new(w, h, w / 2), color, r * CFrame.new(0, h / 2, w / 4) * CFrame.Angles(0, math.pi, 0), mat, "Wedge")
	end
end

-- гранёная заклёпка-ромб
local function stud(mob, bone, name, cf, s, color)
	return deco(mob, bone, name, Vector3.new(s, s, s), color, cf * CFrame.Angles(math.rad(45), math.rad(45), 0), MAT.Metal)
end

-- цилиндр-сегмент между двумя точками (в пространстве кости)
local function decoSeg(mob, bone, name, a, b, d, color, mat, extra)
	local dir = b - a
	local up = (math.abs(dir.Unit.Y) > 0.98) and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	return deco(mob, bone, name, Vector3.new(dir.Magnitude + (extra or 0), d, d), color, cf, mat, "Cyl"), cf
end

-- светящаяся трещина-линия между двумя точками
local function decoLine(mob, bone, name, a, b, t, color, normal)
	local cf = CFrame.lookAt((a + b) / 2, b, normal or Vector3.new(0, 1, 0))
	return deco(mob, bone, name, Vector3.new(t, t * 0.6, (b - a).Magnitude + t), color, cf, MAT.Neon)
end

-- ---------- КАТАНА с цубой ----------
-- пространство меча: клинок растёт вдоль +Y, лезвие смотрит в ?Z, (0,0,0) — центр хвата
local function buildKatana(mob, bone, gripCF, s, bladeLen, edgeColor)
	local function at(x, y, z) return gripCF * CFrame.new(x * s, y * s, z * s) end
	local function sz(x, y, z) return Vector3.new(x * s, y * s, z * s) end

	deco(mob, bone, "KatanaTsuka", sz(0.16, 0.95, 0.2), Color3.fromRGB(22, 18, 20), at(0, 0.12, 0), MAT.Fabric)
	for i = 0, 3 do
		deco(mob, bone, "KatanaIto", sz(0.18, 0.05, 0.22), Color3.fromRGB(214, 202, 176), at(0, -0.21 + i * 0.21, 0) * CFrame.Angles(0, 0, 0.5), MAT.Fabric)
	end
	deco(mob, bone, "KatanaKashira", sz(0.2, 0.08, 0.24), COL.gold, at(0, -0.39, 0), MAT.Metal)
	-- цуба: железный диск с золотым ободом
	deco(mob, bone, "KatanaTsubaRim", sz(0.03, 0.7, 0.7), COL.gold, at(0, 0.63, 0) * CFrame.Angles(0, 0, math.pi / 2), MAT.Metal, "Cyl")
	deco(mob, bone, "KatanaTsuba", sz(0.07, 0.62, 0.62), COL.iron, at(0, 0.63, 0) * CFrame.Angles(0, 0, math.pi / 2), MAT.Metal, "Cyl")
	deco(mob, bone, "KatanaHabaki", sz(0.12, 0.14, 0.26), COL.gold, at(0, 0.74, 0), MAT.Metal)

	-- клинок из 3 сегментов с изгибом (сори) и светящейся линией хамона
	local segLen = bladeLen * s / 3
	local cur = gripCF * CFrame.new(0, 0.8 * s, 0)
	local firstBlade, firstEdge
	for i = 1, 3 do
		cur = cur * CFrame.Angles(0.05, 0, 0)
		local blade = deco(mob, bone, "KatanaBlade", Vector3.new(0.07 * s, segLen + 0.02, 0.2 * s), COL.steel, cur * CFrame.new(0, segLen / 2, 0), MAT.Metal)
		blade.Reflectance = 0.25
		local edge = deco(mob, bone, "KatanaHamon", Vector3.new(0.075 * s, segLen, 0.045 * s), edgeColor, cur * CFrame.new(0, segLen / 2, -0.09 * s), MAT.Neon)
		if i == 1 then
			firstBlade, firstEdge = blade, edge
		end
		cur = cur * CFrame.new(0, segLen, 0)
	end
	deco(mob, bone, "KatanaKissaki", Vector3.new(0.07 * s, 0.32 * s, 0.2 * s), COL.steel, cur * CFrame.new(0, 0.16 * s, 0), MAT.Metal, "Wedge")
	return firstBlade, firstEdge
end

-- ---------- КАНАБО (шипастая дубина они) ----------
-- ось = +Y, (0,0,0) — навершие рукояти
local function buildKanabo(mob, bone, baseCF, s)
	local function at(x, y, z) return baseCF * CFrame.new(x * s, y * s, z * s) end
	local function sz(x, y, z) return Vector3.new(x * s, y * s, z * s) end
	local WOOD = Color3.fromRGB(40, 28, 24)

	deco(mob, bone, "KanaboGrip", sz(0.9, 0.2, 0.2), COL.lacquerWood, at(0, 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2), MAT.Wood, "Cyl")
	for i = 0, 2 do
		deco(mob, bone, "KanaboWrap", sz(0.1, 0.24, 0.24), COL.lacing, at(0, 0.18 + i * 0.25, 0) * CFrame.Angles(0, 0, math.pi / 2), MAT.Fabric, "Cyl")
	end
	deco(mob, bone, "KanaboPommel", sz(0.26, 0.26, 0.26), COL.iron, at(0, -0.02, 0), MAT.Metal, "Ball")
	-- восьмигранная голова
	deco(mob, bone, "KanaboHead", sz(0.5, 1.6, 0.5), WOOD, at(0, 1.75, 0), MAT.Wood)
	deco(mob, bone, "KanaboHead", sz(0.5, 1.6, 0.5), WOOD, at(0, 1.75, 0) * CFrame.Angles(0, math.pi / 4, 0), MAT.Wood)
	deco(mob, bone, "KanaboBand", sz(0.6, 0.1, 0.6), COL.iron, at(0, 1.0, 0), MAT.Metal)
	deco(mob, bone, "KanaboBand", sz(0.6, 0.1, 0.6), COL.iron, at(0, 2.5, 0) * CFrame.Angles(0, math.pi / 4, 0), MAT.Metal)
	deco(mob, bone, "KanaboCap", sz(0.4, 0.14, 0.4), COL.iron, at(0, 2.6, 0), MAT.Metal)
	-- железные шипы в шахматном порядке
	for row = 0, 3 do
		for k = 0, 3 do
			local a = k * math.pi / 2 + (row % 2) * math.pi / 4
			stud(mob, bone, "KanaboStud", at(0, 1.2 + row * 0.37, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.3 * s), 0.16 * s, COL.iron)
		end
	end
end

-- ---------- МАСКА ОНИ / ХАННЯ ----------
-- maskCF: центр задней плоскости маски, маска выступает в ?Z
-- o: skin, dark, eye, brow, fang, horn, hornLen, hornSweep, tusk, mouthGlow, noMouthFill
local function buildOniMask(mob, bone, maskCF, s, o)
	local function at(x, y, z) return maskCF * CFrame.new(x * s, y * s, z * s) end
	local function sz(x, y, z) return Vector3.new(x * s, y * s, z * s) end

	lacq(deco(mob, bone, "MaskFace", sz(1.2, 0.73, 0.14), o.skin, at(0, 0.185, -0.07)))
	lacq(deco(mob, bone, "MaskChin", sz(1.0, 0.17, 0.14), o.skin, at(0, -0.465, -0.07)))
	lacq(deco(mob, bone, "MaskNose", sz(0.24, 0.26, 0.14), o.skin, at(0, 0, -0.21), nil, "Wedge"))

	if not o.noMouthFill then
		deco(mob, bone, "MaskMouth", sz(0.64, 0.24, 0.04), o.mouthGlow or o.dark, at(0, -0.29, -0.03), o.mouthGlow and MAT.Neon or MAT.SmoothPlastic)
	end

	for _, sgn in ipairs({ -1, 1 }) do
		lacq(deco(mob, bone, "MaskCheek", sz(0.3, 0.22, 0.14), o.skin, at(sgn * 0.45, -0.29, -0.07)))
		deco(mob, bone, "MaskSocket", sz(0.34, 0.17, 0.03), o.dark, at(sgn * 0.26, 0.14, -0.155) * CFrame.Angles(0, 0, sgn * 0.28))
		deco(mob, bone, "MaskEye", sz(0.24, 0.07, 0.04), o.eye, at(sgn * 0.26, 0.14, -0.17) * CFrame.Angles(0, 0, sgn * 0.28), MAT.Neon)
		deco(mob, bone, "MaskBrow", sz(0.4, 0.11, 0.12), o.brow, at(sgn * 0.28, 0.31, -0.16) * CFrame.Angles(0, 0, sgn * 0.42))
		-- клыки сверху и бивни снизу
		spike(mob, bone, "MaskFang", at(sgn * 0.17, -0.19, -0.11) * CFrame.Angles(math.pi, 0, 0), 0.08 * s, 0.12 * s, o.fang, MAT.SmoothPlastic, true)
		spike(mob, bone, "MaskTusk", at(sgn * 0.25, -0.4, -0.12), 0.1 * s, (o.tusk or 0.24) * s, o.fang, MAT.SmoothPlastic, true)
		-- рога
		if (o.hornLen or 0) > 0 then
			local sweep = o.hornSweep or 0
			local baseCF = at(sgn * 0.36, 0.66, 0.02) * CFrame.Angles(sweep, 0, -sgn * 0.32)
			deco(mob, bone, "MaskHornBase", sz(0.22, 0.42, 0.22), o.horn, baseCF)
			spike(mob, bone, "MaskHorn", baseCF * CFrame.new(0, 0.2 * s, 0) * CFrame.Angles(sweep, 0, -sgn * 0.35), 0.2 * s, o.hornLen * s, o.horn, MAT.SmoothPlastic)
		end
	end
end

-- ---------- мистическая пульсация Neon-деталей (сервер, ~8 Гц) ----------
local function startRunePulse(mob, humanoid, parts, light, colHi, colLo, period)
	task.spawn(function()
		local t0 = os.clock()
		while mob.Parent and humanoid.Health > 0 do
			local a = 0.5 + 0.5 * math.sin((os.clock() - t0) * 2 * math.pi / period)
			local c = colLo:Lerp(colHi, a)
			for _, p in ipairs(parts) do
				if p.Parent then
					p.Color = c
				end
			end
			if light then
				light.Brightness = 1 + 2.4 * a
			end
			task.wait(0.12)
		end
	end)
end

local function addLight(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
	return l
end

-- ================= 1. КАМЕННЫЙ ПРЫГУН (15 HP | 8 XP) =================
-- Визуал: «Ао-они» — каменный валун в лакированных доспехах, синяя маска они, канабо за спиной,
-- раскалённое ядро (Head) светится сквозь железную решётку на спине.
local function createRockSlime(spawnCFrame)
	local mob = Instance.new("Model")
	mob.Name = "RockSlime"
	mob:SetAttribute("ExpReward", 8)
	mob:SetAttribute("LootTable", "Slime")

	local humanoid = Instance.new("Humanoid", mob)
	humanoid.WalkSpeed = 18
	humanoid.JumpPower = 38
	setupHumanoidClean(humanoid, 15)

	local root = makePart(mob, "HumanoidRootPart", Vector3.new(1.6, 1.2, 1.6), Color3.fromRGB(62, 64, 70), spawnCFrame * CFrame.new(0, 1.2, 0), true, Enum.Material.Slate)
	local head = makePart(mob, "Head", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(255, 140, 30), root.CFrame * CFrame.new(0, 0.2, 0.5), false, Enum.Material.Neon)
	-- наплечники из красного лака (размеры/позиции прежние)
	local crustL = makePart(mob, "CrustL", Vector3.new(0.5, 0.7, 1.1), COL.lacquerRed, root.CFrame * CFrame.new(-0.8, 0.1, 0) * CFrame.Angles(0, 0, 0.2), false, Enum.Material.SmoothPlastic)
	local crustR = makePart(mob, "CrustR", Vector3.new(0.5, 0.7, 1.1), COL.lacquerRed, root.CFrame * CFrame.new(0.8, 0.1, 0) * CFrame.Angles(0, 0, -0.2), false, Enum.Material.SmoothPlastic)
	lacq(crustL)
	lacq(crustR)

	weldParts(root, head)
	weldParts(root, crustL)
	weldParts(root, crustR)

	-- ---------- ВИЗУАЛ ----------
	-- каменная юбка из граней (делает тело валуном, а не кубом)
	for k = 0, 5 do
		local yaw = k * math.pi / 3 + math.pi / 6
		deco(mob, root, "RockFacet", Vector3.new(0.9, 0.45, 0.3), (k % 2 == 0) and Color3.fromRGB(54, 56, 62) or Color3.fromRGB(72, 74, 78),
			CFrame.Angles(0, yaw, 0) * CFrame.new(0, -0.4, -0.74) * CFrame.Angles(0.28, 0, 0), MAT.Basalt)
	end

	-- спинная пластина из тёмного лакированного дерева с металлом
	deco(mob, root, "BackPlate", Vector3.new(1.34, 0.12, 1.2), COL.lacquerWood, CFrame.new(0, 0.66, 0.05), MAT.Wood)
	lacq(deco(mob, root, "PlateRidge", Vector3.new(0.14, 0.1, 1.1), COL.lacquerRed, CFrame.new(0, 0.75, 0.05)))
	deco(mob, root, "PlateTrim", Vector3.new(1.38, 0.06, 0.08), COL.gold, CFrame.new(0, 0.66, -0.58), MAT.Metal)
	for _, x in ipairs({ -0.48, 0.48 }) do
		for _, z in ipairs({ -0.37, 0.47 }) do
			stud(mob, root, "PlateStud", CFrame.new(x, 0.74, z), 0.12, COL.iron)
		end
	end

	-- ламели под наплечниками, золотой кант, мон и маленький рог
	for _, pair in ipairs({ { crustL, -1 }, { crustR, 1 } }) do
		local crust, sgn = pair[1], pair[2]
		deco(mob, crust, "CrustTrim", Vector3.new(0.54, 0.06, 1.14), COL.gold, CFrame.new(0, 0.37, 0), MAT.Metal)
		for k = 1, 2 do
			lacq(deco(mob, crust, "CrustLame", Vector3.new(0.14, 0.22, 1.12), (k == 1) and COL.lacquerBlack or COL.lacquerRed,
				CFrame.new(sgn * (0.2 + k * 0.04), -0.26 - k * 0.19, 0) * CFrame.Angles(0, 0, sgn * 0.15)))
		end
		deco(mob, crust, "CrustMon", Vector3.new(0.04, 0.3, 0.3), COL.gold, CFrame.new(sgn * 0.26, 0.05, 0), MAT.Metal, "Cyl")
		spike(mob, crust, "CrustHorn", CFrame.new(0, 0.37, 0.2) * CFrame.Angles(0, 0, -sgn * 0.3), 0.14, 0.3, COL.ivory, MAT.SmoothPlastic)
	end

	-- синяя маска они спереди
	buildOniMask(mob, root, CFrame.new(0, 0.14, -0.8), 0.6, {
		skin = Color3.fromRGB(44, 62, 128),
		dark = COL.voidDark,
		eye = Color3.fromRGB(255, 160, 40),
		brow = Color3.fromRGB(26, 34, 78),
		fang = COL.ivory,
		horn = COL.ivory,
		hornLen = 0.55,
		mouthGlow = Color3.fromRGB(255, 120, 30),
	})

	-- железная решётка над раскалённым ядром на спине
	for _, x in ipairs({ -0.22, 0.22 }) do
		deco(mob, root, "CoreCage", Vector3.new(0.07, 0.9, 0.07), COL.iron, CFrame.new(x, 0.2, 0.93), MAT.Metal)
	end
	deco(mob, root, "CoreCage", Vector3.new(0.9, 0.07, 0.07), COL.iron, CFrame.new(0, 0.2, 0.93), MAT.Metal)
	deco(mob, root, "CoreFrame", Vector3.new(1.0, 0.1, 0.1), COL.iron, CFrame.new(0, -0.24, 0.88), MAT.Metal)
	for _, x in ipairs({ -0.46, 0.46 }) do
		deco(mob, root, "CoreFrame", Vector3.new(0.1, 0.9, 0.1), COL.iron, CFrame.new(x, 0.2, 0.88), MAT.Metal)
		stud(mob, root, "CoreBolt", CFrame.new(x, -0.24, 0.94), 0.1, COL.gold)
	end

	-- канабо, пристёгнутый за спиной
	buildKanabo(mob, root, CFrame.new(0.62, -0.32, 0.92) * CFrame.Angles(0.5, 0, -0.35), 0.55)
	deco(mob, root, "KanaboStrap", Vector3.new(0.1, 0.1, 0.5), COL.cord, CFrame.new(0.66, 0.05, 0.92) * CFrame.Angles(0, 0, -0.35), MAT.Fabric)

	-- короткие каменные лапки
	for _, x in ipairs({ -0.48, 0.48 }) do
		for _, z in ipairs({ -0.45, 0.45 }) do
			deco(mob, root, "StoneFoot", Vector3.new(0.42, 0.26, 0.5), Color3.fromRGB(46, 48, 54), CFrame.new(x, -0.5, z) * CFrame.Angles(0, x * 0.4, 0), MAT.Basalt)
		end
	end

	addLight(head, Color3.fromRGB(255, 140, 40), 7, 1.4)

	mob.PrimaryPart = root
	mob.Parent = workspace

	attachSmartHealthBar(mob, head)

	local lastJump = os.clock()
	local attackCooldown = false

	task.spawn(function()
		while mob and mob.Parent and humanoid.Health > 0 do
			local targetChar = findNearestTarget(root.Position, 160)
			if targetChar then
				local targetRoot = targetChar.HumanoidRootPart
				local dist = (targetRoot.Position - root.Position).Magnitude

				humanoid:MoveTo(targetRoot.Position)

				if os.clock() - lastJump > 1.6 and dist > 5 then
					lastJump = os.clock()
					humanoid.Jump = true
					root.AssemblyLinearVelocity = (targetRoot.Position - root.Position).Unit * 25 + Vector3.new(0, 20, 0)
				end

				if dist <= 3.2 and not attackCooldown then
					attackCooldown = true
					local targetHum = targetChar:FindFirstChild("Humanoid")
					if targetHum then
						damagePlayer(targetHum, 5)
					end
					task.delay(0.6, function() attackCooldown = false end)
				end
			end
			task.wait(0.12)
		end
	end)

	return mob
end

-- ================= 2. ПАРЯЩИЙ КРИСТАЛЛ (ВЫСОКИЙ С МОТОРОМ) =================
-- Визуал: «Ханнья-торо» — кристалл-душа в лакированном фонаре-святилище,
-- маска ханнья с горящими глазами, парящие наплечники и три летающие катаны на орбите.
local function createCrystalSentry(spawnCFrame)
	local mob = Instance.new("Model")
	mob.Name = "CrystalSentry"
	mob:SetAttribute("ExpReward", 22)
	mob:SetAttribute("LootTable", "Sentry")

	local humanoid = Instance.new("Humanoid", mob)
	humanoid.WalkSpeed = 9
	humanoid.HipHeight = 7.5
	setupHumanoidClean(humanoid, 35)

	local root = makePart(mob, "HumanoidRootPart", Vector3.new(1.3, 3.2, 1.3), Color3.fromRGB(120, 230, 255), spawnCFrame * CFrame.new(0, 7.5, 0), true, Enum.Material.Glass)
	root.Transparency = 0.25

	local head = makePart(mob, "Head", Vector3.new(0.8, 2.2, 0.8), Color3.fromRGB(0, 210, 255), root.CFrame, false, Enum.Material.Neon)
	weldParts(root, head)

	local centerAtt = Instance.new("Attachment", root)
	centerAtt.Name = "CenterAtt"
	centerAtt.Axis = Vector3.new(0, 1, 0)

	local rotor = Instance.new("Part")
	rotor.Name = "OrbitRotor"
	rotor.Size = Vector3.new(0.2, 0.2, 0.2)
	rotor.Transparency = 1
	rotor.CanCollide = false
	rotor.Massless = true
	rotor.CFrame = root.CFrame
	rotor.Parent = mob

	local rotorAtt = Instance.new("Attachment", rotor)
	rotorAtt.Name = "RotorAtt"
	rotorAtt.Axis = Vector3.new(0, 1, 0)

	local motor = Instance.new("HingeConstraint")
	motor.Attachment0 = centerAtt
	motor.Attachment1 = rotorAtt
	motor.ActuatorType = Enum.ActuatorType.Motor
	motor.MotorMaxTorque = 1e6
	motor.AngularVelocity = 2.8
	motor.Parent = root

	-- три летающие катаны на орбите (приварены к ротору; первый сегмент клинка = OrbitShard_i, хамон = RuneGlow_i)
	local ORBIT_RADIUS = 1.35
	for i = 1, 3 do
		local angle = (i - 1) * (math.pi * 2 / 3)
		local gripCF = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.85, ORBIT_RADIUS) * CFrame.Angles(math.pi, 0, 0)
		local shard, rune = buildKatana(mob, rotor, gripCF, 0.62, 2.6, Color3.fromRGB(0, 240, 255))
		shard.Name = "OrbitShard_" .. i
		rune.Name = "RuneGlow_" .. i
	end

	-- ---------- ВИЗУАЛ ----------
	-- каркас фонаря: стойки и золотой пояс
	for _, x in ipairs({ -0.7, 0.7 }) do
		for _, z in ipairs({ -0.7, 0.7 }) do
			lacq(deco(mob, root, "LanternStrut", Vector3.new(0.1, 3.1, 0.1), COL.lacquerBlack, CFrame.new(x, 0, z), MAT.Wood))
		end
	end
	for _, z in ipairs({ -0.72, 0.72 }) do
		deco(mob, root, "LanternBand", Vector3.new(1.5, 0.1, 0.1), COL.gold, CFrame.new(0, -0.95, z), MAT.Metal)
	end
	for _, x in ipairs({ -0.72, 0.72 }) do
		deco(mob, root, "LanternBand", Vector3.new(0.1, 0.1, 1.5), COL.gold, CFrame.new(x, -0.95, 0), MAT.Metal)
	end

	-- крыша-пагода с загнутыми золотыми карнизами
	lacq(deco(mob, root, "LanternCollar", Vector3.new(1.62, 0.2, 1.62), COL.lacquerBlack, CFrame.new(0, 1.7, 0)))
	deco(mob, root, "LanternCollarTrim", Vector3.new(1.68, 0.07, 1.68), COL.gold, CFrame.new(0, 1.6, 0), MAT.Metal)
	for k = 0, 3 do
		lacq(deco(mob, root, "LanternRoof", Vector3.new(2.2, 0.5, 1.1), Color3.fromRGB(96, 20, 26), CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 2.05, -0.55), nil, "Wedge"))
		spike(mob, root, "RoofEave", CFrame.Angles(0, k * math.pi / 2 + math.pi / 4, 0) * CFrame.new(0, 1.84, -1.42) * CFrame.Angles(-1.0, 0, 0), 0.14, 0.35, COL.gold, MAT.Metal, true)
	end
	deco(mob, root, "RoofFinial", Vector3.new(0.12, 0.3, 0.12), COL.gold, CFrame.new(0, 2.42, 0), MAT.Metal)
	deco(mob, root, "RoofHoju", Vector3.new(0.32, 0.32, 0.32), COL.gold, CFrame.new(0, 2.66, 0), MAT.Metal, "Ball")

	-- ступенчатое днище и светящаяся капля
	lacq(deco(mob, root, "LanternBase", Vector3.new(1.62, 0.2, 1.62), COL.lacquerBlack, CFrame.new(0, -1.7, 0)))
	deco(mob, root, "LanternBaseTrim", Vector3.new(1.68, 0.07, 1.68), COL.gold, CFrame.new(0, -1.6, 0), MAT.Metal)
	lacq(deco(mob, root, "LanternStep", Vector3.new(1.1, 0.22, 1.1), COL.lacquerRed, CFrame.new(0, -1.91, 0)))
	lacq(deco(mob, root, "LanternStep", Vector3.new(0.7, 0.22, 0.7), COL.lacquerBlack, CFrame.new(0, -2.13, 0) * CFrame.Angles(0, math.pi / 4, 0)))
	deco(mob, root, "LanternStep", Vector3.new(0.34, 0.3, 0.34), COL.gold, CFrame.new(0, -2.39, 0), MAT.Metal)
	deco(mob, root, "SpiritDrop", Vector3.new(0.26, 0.26, 0.26), Color3.fromRGB(0, 230, 255), CFrame.new(0, -2.68, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), MAT.Neon)

	-- маска ханнья: костяной лак, золотые рога и клыки, неоновые глаза
	local maskCF = CFrame.new(0, 0.3, -0.74)
	buildOniMask(mob, root, maskCF, 0.72, {
		skin = Color3.fromRGB(236, 228, 210),
		dark = COL.voidDark,
		eye = Color3.fromRGB(0, 235, 255),
		brow = Color3.fromRGB(34, 28, 34),
		fang = COL.gold,
		horn = COL.gold,
		hornLen = 0.6,
		hornSweep = 0.25,
		tusk = 0.3,
		mouthGlow = Color3.fromRGB(0, 190, 255),
	})
	-- чёрные пряди на лбу ханнья
	for _, sgn in ipairs({ -1, 1 }) do
		deco(mob, root, "HannyaHair", Vector3.new(0.07, 0.3, 0.03), COL.voidDark, maskCF * CFrame.new(sgn * 0.1, 0.4, -0.12) * CFrame.Angles(0, 0, sgn * 0.35))
	end

	-- парящие ламельные наплечники
	for _, sgn in ipairs({ -1, 1 }) do
		for k = 0, 2 do
			lacq(deco(mob, root, "FloatSode", Vector3.new(0.12, 0.36, 0.74), (k % 2 == 0) and COL.lacquerRed or COL.lacquerBlack,
				CFrame.new(sgn * (0.9 + k * 0.05), 0.62 - k * 0.33, 0) * CFrame.Angles(0, 0, sgn * 0.18)))
		end
		deco(mob, root, "FloatSodeTrim", Vector3.new(0.16, 0.06, 0.78), COL.gold, CFrame.new(sgn * 0.87, 0.82, 0) * CFrame.Angles(0, 0, sgn * 0.18), MAT.Metal)
		deco(mob, root, "FloatSodeMon", Vector3.new(0.04, 0.26, 0.26), COL.gold, CFrame.new(sgn * 1.0, 0.29, 0) * CFrame.Angles(0, 0, sgn * 0.18), MAT.Metal, "Cyl")
	end

	addLight(head, Color3.fromRGB(0, 210, 255), 10, 1.6)

	mob.PrimaryPart = root
	mob.Parent = workspace

	attachSmartHealthBar(mob, head)

	local shootCooldown = false

	task.spawn(function()
		while mob and mob.Parent and humanoid.Health > 0 do
			local targetChar = findNearestTarget(root.Position, 200)
			if targetChar then
				local targetRoot = targetChar.HumanoidRootPart
				local dist = (targetRoot.Position - root.Position).Magnitude

				if dist > 24 then
					humanoid:MoveTo(targetRoot.Position)
				elseif dist < 12 then
					local runAwayPos = root.Position + (root.Position - targetRoot.Position).Unit * 12
					humanoid:MoveTo(runAwayPos)
				end

				if not shootCooldown and dist <= 42 then
					shootCooldown = true

					local startPos = root.Position + Vector3.new(0, -0.4, 0)
					local aimDir = (targetRoot.Position + Vector3.new(0, 0.5, 0) - startPos).Unit

					local bolt = Instance.new("Part")
					bolt.Name = "SentryBolt"
					bolt.Shape = Enum.PartType.Ball
					bolt.Size = Vector3.new(0.85, 0.85, 0.85)
					bolt.Color = Color3.fromRGB(0, 230, 255)
					bolt.Material = Enum.Material.Neon
					bolt.CanCollide = false
					bolt.CFrame = CFrame.new(startPos)
					bolt.Parent = workspace

					local bv = Instance.new("LinearVelocity")
					local att = Instance.new("Attachment", bolt)
					bv.Attachment0 = att
					bv.MaxForce = 1e7
					bv.VectorVelocity = aimDir * 65
					bv.Parent = bolt

					bolt.Touched:Connect(function(hit)
						if hit:IsDescendantOf(mob) then return end
						local hitModel = hit:FindFirstAncestorOfClass("Model")
						local playerHum = hitModel and hitModel:FindFirstChild("Humanoid")
						if playerHum and Players:GetPlayerFromCharacter(hitModel) then
							damagePlayer(playerHum, 5)
						end
						bolt:Destroy()
					end)

					Debris:AddItem(bolt, 3)
					task.delay(2.2, function() shootCooldown = false end)
				end
			end
			task.wait(0.2)
		end
	end)

	return mob
end

-- ================= 3. ВОКСЕЛЬНЫЙ ГОЛЕМ (60 HP | 45 XP) =================
-- Визуал: «Ака-они-муся» — красный демон-самурай: доспех до из лакированных ламелей со шнуровкой,
-- рельефные содэ, кабуто с рогами, маска они с огненной пастью, катана с цубой, пустые ножны, сасимоно.
local function createVoxelGolem(spawnCFrame)
	local mob = Instance.new("Model")
	mob.Name = "VoxelGolem"
	mob:SetAttribute("ExpReward", 45)
	mob:SetAttribute("LootTable", "Golem")

	local humanoid = Instance.new("Humanoid", mob)
	humanoid.WalkSpeed = 13
	setupHumanoidClean(humanoid, 60)

	local SKIN = Color3.fromRGB(150, 38, 34)
	local HAKAMA = Color3.fromRGB(36, 32, 52)

	local torso = makePart(mob, "HumanoidRootPart", Vector3.new(2, 2.2, 1.4), COL.lacquerBlack, spawnCFrame * CFrame.new(0, 2.5, 0), true, Enum.Material.SmoothPlastic)
	local head = makePart(mob, "Head", Vector3.new(1.3, 1.2, 1.3), SKIN, torso.CFrame * CFrame.new(0, 1.7, 0), false, Enum.Material.Slate)
	-- огненная пасть под маской (деталь EyeVisor сохранена)
	local eyeVisor = makePart(mob, "EyeVisor", Vector3.new(0.62, 0.2, 0.08), Color3.fromRGB(255, 110, 30), head.CFrame * CFrame.new(0, -0.29, -0.67), false, Enum.Material.Neon)

	local leftArm = makePart(mob, "LeftArm", Vector3.new(0.9, 2.1, 0.9), SKIN, torso.CFrame * CFrame.new(-1.6, 0.1, 0), false, Enum.Material.Slate)
	local rightArm = makePart(mob, "RightArm", Vector3.new(0.9, 2.1, 0.9), SKIN, torso.CFrame * CFrame.new(1.6, 0.1, 0), false, Enum.Material.Slate)
	local padL = makePart(mob, "PadL", Vector3.new(1.2, 0.6, 1.2), COL.lacquerBlack, leftArm.CFrame * CFrame.new(0, 0.9, 0), false, Enum.Material.Wood)
	local padR = makePart(mob, "PadR", Vector3.new(1.2, 0.6, 1.2), COL.lacquerBlack, rightArm.CFrame * CFrame.new(0, 0.9, 0), false, Enum.Material.Wood)

	local leftLeg = makePart(mob, "LeftLeg", Vector3.new(0.9, 2, 0.9), HAKAMA, torso.CFrame * CFrame.new(-0.6, -2.1, 0), true, Enum.Material.Fabric)
	local rightLeg = makePart(mob, "RightLeg", Vector3.new(0.9, 2, 0.9), HAKAMA, torso.CFrame * CFrame.new(0.6, -2.1, 0), true, Enum.Material.Fabric)

	weldParts(torso, head)
	weldParts(head, eyeVisor)
	weldParts(torso, leftArm)
	weldParts(torso, rightArm)
	weldParts(leftArm, padL)
	weldParts(rightArm, padR)
	weldParts(torso, leftLeg)
	weldParts(torso, rightLeg)

	-- ---------- ВИЗУАЛ: ТОРС (до) ----------
	for i = 0, 3 do
		local y = 0.72 - i * 0.42
		lacq(deco(mob, torso, "DoLame", Vector3.new(2.14, 0.4, 0.12), (i % 2 == 0) and COL.lacquerBlack or COL.lacquerWood, CFrame.new(0, y, -0.77) * CFrame.Angles(0.07, 0, 0)))
		for _, x in ipairs({ -0.7, 0, 0.7 }) do
			deco(mob, torso, "DoLacing", Vector3.new(0.07, 0.36, 0.03), COL.lacing, CFrame.new(x, y, -0.85) * CFrame.Angles(0.07, 0, 0), MAT.Fabric)
		end
	end
	lacq(deco(mob, torso, "DoMunaita", Vector3.new(1.5, 0.3, 0.14), COL.lacquerBlack, CFrame.new(0, 1.02, -0.76)))
	deco(mob, torso, "DoMunaitaTrim", Vector3.new(1.54, 0.06, 0.16), COL.gold, CFrame.new(0, 1.18, -0.76), MAT.Metal)
	deco(mob, torso, "DoMon", Vector3.new(0.05, 0.5, 0.5), COL.gold, CFrame.new(0, 0.3, -0.87) * CFrame.Angles(0, math.pi / 2, 0), MAT.Metal, "Cyl")
	deco(mob, torso, "DoMonInner", Vector3.new(0.06, 0.3, 0.3), COL.lacing, CFrame.new(0, 0.3, -0.88) * CFrame.Angles(0, math.pi / 2, 0), MAT.SmoothPlastic, "Cyl")

	-- спина и бока
	lacq(deco(mob, torso, "DoBack", Vector3.new(2.1, 2.1, 0.14), COL.lacquerBlack, CFrame.new(0, 0, 0.77)))
	for _, y in ipairs({ 0.5, 0, -0.5 }) do
		deco(mob, torso, "DoBackLace", Vector3.new(2.12, 0.05, 0.03), COL.lacing, CFrame.new(0, y, 0.85), MAT.Fabric)
	end
	deco(mob, torso, "AgemakiKnot", Vector3.new(0.3, 0.3, 0.3), COL.lacing, CFrame.new(0, 0.35, 0.9), MAT.Fabric, "Ball")
	for _, sgn in ipairs({ -1, 1 }) do
		deco(mob, torso, "AgemakiTail", Vector3.new(0.1, 0.5, 0.05), COL.lacing, CFrame.new(sgn * 0.12, 0.02, 0.9) * CFrame.Angles(0, 0, sgn * 0.3), MAT.Fabric)
		lacq(deco(mob, torso, "DoSide", Vector3.new(0.12, 2.0, 1.45), COL.lacquerBlack, CFrame.new(sgn * 1.05, 0, 0)))
	end

	-- пояс-оби с узлом
	deco(mob, torso, "Obi", Vector3.new(2.22, 0.24, 1.6), COL.cord, CFrame.new(0, -1.0, 0), MAT.Fabric)
	deco(mob, torso, "ObiKnot", Vector3.new(0.3, 0.3, 0.16), COL.cord, CFrame.new(0.55, -1.0, -0.86), MAT.Fabric)
	deco(mob, torso, "ObiEnd", Vector3.new(0.12, 0.42, 0.05), COL.cord, CFrame.new(0.48, -1.3, -0.86) * CFrame.Angles(0, 0, 0.25), MAT.Fabric)
	deco(mob, torso, "ObiEnd", Vector3.new(0.12, 0.42, 0.05), COL.cord, CFrame.new(0.64, -1.3, -0.86) * CFrame.Angles(0, 0, -0.2), MAT.Fabric)

	-- кусадзури: 5 набедренных панелей из трёх ламелей
	local panels = {
		{ 0, 0.8, -0.47 }, { 0, 0.8, 0.47 },
		{ math.pi / 2, 1.08, 0 }, { -math.pi / 2, 1.08, 0 },
		{ math.pi, 0.8, 0 },
	}
	for _, pnl in ipairs(panels) do
		for k = 0, 2 do
			local cf = CFrame.Angles(0, pnl[1], 0) * CFrame.new(pnl[3], -1.26 - k * 0.26, -(pnl[2] + k * 0.045)) * CFrame.Angles(0.14, 0, 0)
			lacq(deco(mob, torso, "Kusazuri", Vector3.new(0.9, 0.28, 0.1), (k == 2) and COL.lacquerRed or COL.lacquerBlack, cf))
		end
		deco(mob, torso, "KusazuriLace", Vector3.new(0.06, 0.76, 0.03), COL.lacing,
			CFrame.Angles(0, pnl[1], 0) * CFrame.new(pnl[3], -1.52, -(pnl[2] + 0.1)) * CFrame.Angles(0.14, 0, 0), MAT.Fabric)
	end

	-- ---------- РУКИ: содэ, котэ, кулаки ----------
	local function dressArm(arm, sgn)
		lacq(deco(mob, arm, "SodeKanmuri", Vector3.new(1.3, 0.14, 1.36), COL.lacquerBlack, CFrame.new(sgn * 0.05, 1.27, 0) * CFrame.Angles(0, 0, -sgn * 0.12)))
		deco(mob, arm, "SodeKanmuriTrim", Vector3.new(1.34, 0.05, 1.4), COL.gold, CFrame.new(sgn * 0.05, 1.2, 0) * CFrame.Angles(0, 0, -sgn * 0.12), MAT.Metal)
		for k = 0, 3 do
			lacq(deco(mob, arm, "SodeLame", Vector3.new(0.14, 0.34, 1.36), (k % 2 == 0) and COL.lacquerRed or COL.lacquerBlack,
				CFrame.new(sgn * (0.68 + k * 0.05), 0.78 - k * 0.3, 0) * CFrame.Angles(0, 0, sgn * 0.2)))
		end
		for _, z in ipairs({ -0.42, 0.42 }) do
			deco(mob, arm, "SodeLace", Vector3.new(0.04, 1.2, 0.07), COL.gold, CFrame.new(sgn * 0.87, 0.33, z) * CFrame.Angles(0, 0, sgn * 0.2), MAT.Fabric)
		end
		deco(mob, arm, "SodeMon", Vector3.new(0.05, 0.34, 0.34), COL.gold, CFrame.new(sgn * 0.83, 0.48, 0) * CFrame.Angles(0, 0, sgn * 0.2), MAT.Metal, "Cyl")
		spike(mob, arm, "ShoulderHorn", CFrame.new(sgn * 0.35, 1.34, 0) * CFrame.Angles(0, 0, -sgn * 0.5), 0.22, 0.5, COL.ivory, MAT.SmoothPlastic)

		-- котэ (наручи): железо и золотые кольца
		deco(mob, arm, "Kote", Vector3.new(0.96, 0.8, 0.96), COL.iron, CFrame.new(0, -0.55, 0), MAT.Metal)
		for _, y in ipairs({ -0.17, -0.93 }) do
			deco(mob, arm, "KoteRing", Vector3.new(1.0, 0.07, 1.0), COL.gold, CFrame.new(0, y, 0), MAT.Metal)
		end
		for _, x in ipairs({ -0.2, 0.2 }) do
			deco(mob, arm, "KoteSplint", Vector3.new(0.08, 0.66, 0.03), Color3.fromRGB(34, 34, 40), CFrame.new(x, -0.55, -0.495), MAT.Metal)
		end
		-- кулак с тэкко
		deco(mob, arm, "Fist", Vector3.new(0.8, 0.62, 0.86), SKIN, CFrame.new(0, -1.36, 0), MAT.Slate)
		deco(mob, arm, "Tekko", Vector3.new(0.06, 0.45, 0.7), COL.iron, CFrame.new(sgn * 0.42, -1.3, 0), MAT.Metal)
	end
	dressArm(leftArm, -1)
	dressArm(rightArm, 1)

	-- катана в правой руке (низкая стойка гэдан), лезвие вниз
	buildKatana(mob, rightArm, CFrame.new(0, -1.36, -0.05) * CFrame.Angles(math.rad(-115), 0, 0), 1.0, 2.7, Color3.fromRGB(255, 90, 60))

	-- пустые ножны-сая за поясом слева
	local sayaCF = CFrame.new(-1.16, -1.0, 0.35) * CFrame.Angles(0.3, 0, 0)
	lacq(deco(mob, torso, "Saya", Vector3.new(0.14, 0.2, 2.2), COL.lacquerBlack, sayaCF))
	deco(mob, torso, "SayaKoiguchi", Vector3.new(0.18, 0.24, 0.1), COL.gold, sayaCF * CFrame.new(0, 0, -1.05), MAT.Metal)
	deco(mob, torso, "SayaKojiri", Vector3.new(0.18, 0.24, 0.12), COL.gold, sayaCF * CFrame.new(0, 0, 1.07), MAT.Metal)
	deco(mob, torso, "SayaSageo", Vector3.new(0.06, 0.34, 0.06), COL.cord, sayaCF * CFrame.new(0, -0.24, -0.6), MAT.Fabric)

	-- флажок сасимоно за спиной
	lacq(deco(mob, torso, "SashimonoPole", Vector3.new(0.1, 3.4, 0.1), COL.lacquerBlack, CFrame.new(0.55, 1.7, 0.92)))
	deco(mob, torso, "SashimonoBar", Vector3.new(0.08, 0.08, 1.0), COL.lacquerBlack, CFrame.new(0.55, 3.35, 1.42))
	deco(mob, torso, "SashimonoFlag", Vector3.new(0.04, 1.8, 0.95), COL.lacquerRed, CFrame.new(0.55, 2.45, 1.42), MAT.Fabric)
	deco(mob, torso, "SashimonoMon", Vector3.new(0.05, 0.6, 0.6), COL.paper, CFrame.new(0.55, 2.6, 1.42), MAT.SmoothPlastic, "Cyl")
	deco(mob, torso, "SashimonoMonInner", Vector3.new(0.06, 0.3, 0.3), COL.voidDark, CFrame.new(0.55, 2.6, 1.42), MAT.SmoothPlastic, "Cyl")
	deco(mob, torso, "SashimonoTop", Vector3.new(0.18, 0.18, 0.18), COL.gold, CFrame.new(0.55, 3.47, 0.92), MAT.Metal, "Ball")

	-- ---------- ГОЛОВА: кабуто + маска они ----------
	lacq(deco(mob, head, "KabutoBowl", Vector3.new(1.42, 0.42, 1.42), COL.lacquerBlack, CFrame.new(0, 0.72, 0)))
	for k = 0, 3 do
		lacq(deco(mob, head, "KabutoRoof", Vector3.new(1.42, 0.3, 0.36), COL.lacquerBlack, CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 1.08, -0.53), nil, "Wedge"))
	end
	lacq(deco(mob, head, "KabutoTop", Vector3.new(0.72, 0.3, 0.72), COL.lacquerBlack, CFrame.new(0, 1.08, 0)))
	deco(mob, head, "KabutoTehen", Vector3.new(0.1, 0.3, 0.3), COL.gold, CFrame.new(0, 1.24, 0) * CFrame.Angles(0, 0, math.pi / 2), MAT.Metal, "Cyl")
	local visorCF = CFrame.new(0, 0.62, -0.8) * CFrame.Angles(-0.25, 0, 0)
	lacq(deco(mob, head, "KabutoVisor", Vector3.new(1.46, 0.1, 0.34), COL.lacquerBlack, visorCF))
	deco(mob, head, "KabutoVisorTrim", Vector3.new(1.48, 0.05, 0.06), COL.gold, visorCF * CFrame.new(0, 0, -0.16), MAT.Metal)
	deco(mob, head, "Maedate", Vector3.new(0.3, 0.3, 0.06), COL.gold, CFrame.new(0, 0.84, -0.74) * CFrame.Angles(-0.2, 0, math.pi / 4), MAT.Metal)
	for _, sgn in ipairs({ -1, 1 }) do
		lacq(deco(mob, head, "Fukigaeshi", Vector3.new(0.1, 0.42, 0.4), COL.lacquerRed, CFrame.new(sgn * 0.78, 0.6, -0.5) * CFrame.Angles(0, sgn * 0.6, 0)))
		-- рога они сквозь шлем
		local hornCF = CFrame.new(sgn * 0.42, 1.1, -0.15) * CFrame.Angles(0, 0, -sgn * 0.3)
		deco(mob, head, "OniHornBase", Vector3.new(0.24, 0.5, 0.24), COL.ivory, hornCF)
		spike(mob, head, "OniHorn", hornCF * CFrame.new(0, 0.25, 0) * CFrame.Angles(0.15, 0, -sgn * 0.35), 0.2, 0.65, COL.ivory, MAT.SmoothPlastic)
	end
	-- сикоро: расходящиеся назатыльные ламели
	for k = 0, 2 do
		local colK = (k % 2 == 0) and COL.lacquerBlack or COL.lacquerRed
		lacq(deco(mob, head, "Shikoro", Vector3.new(1.6, 0.24, 0.1), colK, CFrame.new(0, 0.42 - k * 0.2, 0.78 + k * 0.07) * CFrame.Angles(-0.3, 0, 0)))
		for _, sgn in ipairs({ -1, 1 }) do
			lacq(deco(mob, head, "Shikoro", Vector3.new(0.1, 0.24, 1.1), colK, CFrame.new(sgn * (0.78 + k * 0.07), 0.42 - k * 0.2, 0.2) * CFrame.Angles(0, 0, sgn * 0.3)))
		end
	end
	buildOniMask(mob, head, CFrame.new(0, 0, -0.65), 1.0, {
		skin = Color3.fromRGB(168, 32, 30),
		dark = COL.voidDark,
		eye = Color3.fromRGB(255, 200, 60),
		brow = Color3.fromRGB(90, 16, 18),
		fang = COL.ivory,
		horn = COL.ivory,
		hornLen = 0,
		noMouthFill = true, -- пасть светится деталью EyeVisor
	})

	-- ---------- НОГИ: сунэатэ, таби, варадзи ----------
	for _, leg in ipairs({ leftLeg, rightLeg }) do
		deco(mob, leg, "Suneate", Vector3.new(0.72, 0.9, 0.08), COL.iron, CFrame.new(0, -0.4, -0.49), MAT.Metal)
		for _, x in ipairs({ -0.2, 0.2 }) do
			deco(mob, leg, "SuneateSplint", Vector3.new(0.07, 0.84, 0.03), COL.gold, CFrame.new(x, -0.4, -0.545), MAT.Metal)
		end
		deco(mob, leg, "Kyahan", Vector3.new(0.96, 0.08, 0.96), Color3.fromRGB(225, 215, 195), CFrame.new(0, 0.1, 0), MAT.Fabric)
		deco(mob, leg, "Tabi", Vector3.new(0.96, 0.26, 1.2), Color3.fromRGB(228, 222, 210), CFrame.new(0, -0.83, -0.15), MAT.Fabric)
		deco(mob, leg, "Waraji", Vector3.new(1.0, 0.07, 1.3), Color3.fromRGB(190, 160, 100), CFrame.new(0, -0.965, -0.15), MAT.Fabric)
	end

	addLight(eyeVisor, Color3.fromRGB(255, 120, 40), 6, 1.2)

	mob.PrimaryPart = torso
	mob.Parent = workspace

	attachSmartHealthBar(mob, head)

	local attackCooldown = false
	task.spawn(function()
		while mob and mob.Parent and humanoid.Health > 0 do
			local targetChar = findNearestTarget(torso.Position, 220)
			if targetChar then
				local targetRoot = targetChar.HumanoidRootPart
				local distance = (targetRoot.Position - torso.Position).Magnitude

				if distance > 4.5 then
					humanoid:MoveTo(targetRoot.Position)
				else
					humanoid:MoveTo(torso.Position)
					if not attackCooldown then
						attackCooldown = true
						local targetHum = targetChar:FindFirstChild("Humanoid")
						if targetHum then
							damagePlayer(targetHum, 12)
							targetRoot.AssemblyLinearVelocity = (targetRoot.Position - torso.Position).Unit * 20 + Vector3.new(0, 8, 0)
						end
						task.delay(1.0, function() attackCooldown = false end)
					end
				end
			end
			task.wait(0.15)
		end
	end)

	return mob
end

-- ================= 4. БРОНИРОВАННЫЙ КОЛОСС (350 HP | ТАНК) =================
-- Визуал: древний замшелый каменный страж святилища. Плиты тела разделены пульсирующими
-- мистическими швами, грудь опоясывает толстая симэнава с сидэ, на спине — обломки тории
-- и каменные наросты, лицо — монолитная плита-маска с руническими щелями глаз,
-- руки — гранёные каменные кулаки-молоты с шипами.
local function createArmoredColossus(spawnCFrame)
	local mob = Instance.new("Model")
	mob.Name = "ArmoredColossus"
	mob:SetAttribute("ExpReward", 140)
	mob:SetAttribute("LootTable", "Colossus")

	local humanoid = Instance.new("Humanoid", mob)
	humanoid.WalkSpeed = 8.5
	setupHumanoidClean(humanoid, 350)

	local STONE_A = Color3.fromRGB(58, 62, 62)
	local STONE_B = Color3.fromRGB(48, 51, 53)
	local STONE_C = Color3.fromRGB(70, 72, 70)
	local STONE_D = Color3.fromRGB(42, 44, 47)
	local MOSS_A = Color3.fromRGB(66, 94, 50)
	local MOSS_B = Color3.fromRGB(52, 78, 42)
	local RUNE_HI = Color3.fromRGB(90, 255, 215)
	local RUNE_LO = Color3.fromRGB(10, 110, 115)
	local runes = {}
	local function rune(p)
		table.insert(runes, p)
		return p
	end

	local torso = makePart(mob, "HumanoidRootPart", Vector3.new(3.5, 3.8, 2.2), Color3.fromRGB(44, 47, 50), spawnCFrame * CFrame.new(0, 3.8, 0), true, Enum.Material.Slate)
	-- ядро-печать на груди (ромб в каменной раме)
	local chestCore = makePart(mob, "ChestCore", Vector3.new(0.95, 0.95, 0.22), RUNE_HI, torso.CFrame * CFrame.new(0, 0.1, -1.64) * CFrame.Angles(0, 0, math.rad(45)), false, Enum.Material.Neon)

	local head = makePart(mob, "Head", Vector3.new(1.8, 1.6, 1.8), Color3.fromRGB(54, 57, 60), torso.CFrame * CFrame.new(0, 2.7, 0), false, Enum.Material.Slate)
	local crownHornL = makePart(mob, "HornL", Vector3.new(0.5, 1.2, 0.5), Color3.fromRGB(38, 40, 44), head.CFrame * CFrame.new(-0.8, 1.0, 0) * CFrame.Angles(0, 0, -0.3), false, Enum.Material.Basalt)
	local crownHornR = makePart(mob, "HornR", Vector3.new(0.5, 1.2, 0.5), Color3.fromRGB(38, 40, 44), head.CFrame * CFrame.new(0.8, 1.0, 0) * CFrame.Angles(0, 0, 0.3), false, Enum.Material.Basalt)

	local leftArm = makePart(mob, "LeftArm", Vector3.new(1.6, 3.4, 1.6), Color3.fromRGB(54, 57, 60), torso.CFrame * CFrame.new(-2.8, 0.2, 0), false, Enum.Material.Slate)
	local rightArm = makePart(mob, "RightArm", Vector3.new(1.6, 3.4, 1.6), Color3.fromRGB(54, 57, 60), torso.CFrame * CFrame.new(2.8, 0.2, 0), false, Enum.Material.Slate)
	local leftLeg = makePart(mob, "LeftLeg", Vector3.new(1.4, 3.0, 1.4), Color3.fromRGB(40, 42, 46), torso.CFrame * CFrame.new(-1.1, -3.2, 0), true, Enum.Material.Basalt)
	local rightLeg = makePart(mob, "RightLeg", Vector3.new(1.4, 3.0, 1.4), Color3.fromRGB(40, 42, 46), torso.CFrame * CFrame.new(1.1, -3.2, 0), true, Enum.Material.Basalt)

	weldParts(torso, chestCore)
	weldParts(torso, head)
	weldParts(head, crownHornL)
	weldParts(head, crownHornR)
	weldParts(torso, leftArm)
	weldParts(torso, rightArm)
	weldParts(torso, leftLeg)
	weldParts(torso, rightLeg)

	-- ---------- ТОРС: каменные плиты над светящимися швами ----------
	rune(deco(mob, torso, "RuneSeam", Vector3.new(3.2, 3.5, 0.08), RUNE_HI, CFrame.new(0, 0, -1.14), MAT.Neon))
	rune(deco(mob, torso, "RuneSeam", Vector3.new(3.2, 3.5, 0.08), RUNE_HI, CFrame.new(0, 0, 1.14), MAT.Neon))

	local stoneTones = { STONE_A, STONE_B, STONE_C }
	local FRONT = {
		{ Vector3.new(1.55, 1.25, 0.42), Vector3.new(-0.84, 1.2, -1.39), Vector3.new(-0.06, 0.1, 0.04) },
		{ Vector3.new(1.55, 1.25, 0.42), Vector3.new(0.84, 1.2, -1.39), Vector3.new(-0.06, -0.1, -0.04) },
		{ Vector3.new(1.5, 0.75, 0.38), Vector3.new(-0.82, 0.1, -1.37), Vector3.new(0.03, 0.06, -0.03) },
		{ Vector3.new(1.5, 0.75, 0.38), Vector3.new(0.82, 0.1, -1.37), Vector3.new(0.03, -0.05, 0.04) },
		{ Vector3.new(1.5, 0.75, 0.38), Vector3.new(-0.82, -0.8, -1.37), Vector3.new(-0.02, 0.05, 0.03) },
		{ Vector3.new(1.5, 0.75, 0.38), Vector3.new(0.82, -0.8, -1.37), Vector3.new(0.04, -0.06, -0.02) },
		{ Vector3.new(3.2, 0.6, 0.38), Vector3.new(0, -1.55, -1.37), Vector3.new(0.05, 0, 0) },
	}
	for i, s in ipairs(FRONT) do
		local cf = CFrame.new(s[2]) * CFrame.Angles(s[3].X, s[3].Y, s[3].Z)
		deco(mob, torso, "ChestSlab", s[1], stoneTones[(i - 1) % 3 + 1], cf, MAT.Slate)
		if i <= 2 then
			-- мох на грудных плитах и свисающие пряди
			deco(mob, torso, "Moss", Vector3.new(1.35, 0.14, 0.34), MOSS_A, cf * CFrame.new(0, 0.66, 0.05), MAT.Grass)
			for _, x in ipairs({ -0.35, 0.25 }) do
				deco(mob, torso, "MossStrand", Vector3.new(0.12, 0.5, 0.05), MOSS_B, cf * CFrame.new(x, 0.38, -0.23), MAT.Grass)
			end
		end
	end
	-- каменная рама вокруг ядра
	for k = 0, 3 do
		deco(mob, torso, "CoreFrame", Vector3.new(1.3, 0.22, 0.3), STONE_D, CFrame.new(0, 0.1, -1.6) * CFrame.Angles(0, 0, math.pi / 4 + k * math.pi / 2) * CFrame.new(0, 0.6, 0), MAT.Slate)
	end

	-- спинные плиты
	local i = 0
	for _, y in ipairs({ 1.2, 0, -1.2 }) do
		for _, x in ipairs({ -0.82, 0.82 }) do
			i = i + 1
			local cf = CFrame.new(x, y, 1.38) * CFrame.Angles(math.sin(i * 1.7) * 0.06, math.cos(i * 2.3) * 0.08, math.sin(i * 3.1) * 0.05)
			deco(mob, torso, "BackSlab", Vector3.new(1.55, 1.1, 0.4), stoneTones[i % 3 + 1], cf, MAT.Slate)
			if y > 1 then
				deco(mob, torso, "Moss", Vector3.new(1.3, 0.14, 0.34), MOSS_B, cf * CFrame.new(0, 0.6, 0), MAT.Grass)
			end
		end
	end

	-- трещины на боках торса
	for _, sgn in ipairs({ -1, 1 }) do
		local pts = {
			Vector3.new(sgn * 1.77, 1.3, -0.6), Vector3.new(sgn * 1.77, 0.4, -0.15),
			Vector3.new(sgn * 1.77, -0.4, -0.5), Vector3.new(sgn * 1.77, -1.4, 0.1),
		}
		for k = 1, #pts - 1 do
			rune(decoLine(mob, torso, "RuneCrack", pts[k], pts[k + 1], 0.1, RUNE_HI, Vector3.new(1, 0, 0)))
		end
	end

	-- ---------- СИМЭНАВА вокруг груди ----------
	local RY, A, B = 1.02, 1.9, 1.78
	local N = 24
	local ropePts = {}
	for k = 0, N - 1 do
		local t = k / N * math.pi * 2
		local c, s = math.cos(t), math.sin(t)
		local x = A * ((c >= 0) and 1 or -1) * math.abs(c) ^ 0.5
		local z = B * ((s >= 0) and 1 or -1) * math.abs(s) ^ 0.5
		ropePts[k + 1] = Vector3.new(x, RY + 0.1 * math.cos(t * 2), z)
	end
	local ROPE = Color3.fromRGB(198, 176, 120)
	local ROPE_D = Color3.fromRGB(160, 138, 90)
	for k = 1, N do
		local a, b = ropePts[k], ropePts[k % N + 1]
		local _, segCF = decoSeg(mob, torso, "Shimenawa", a, b, 0.5, ROPE, MAT.Fabric, 0.14)
		deco(mob, torso, "ShimenawaTwist", Vector3.new(0.12, 0.58, 0.58), ROPE_D, segCF * CFrame.Angles(0, 0.55, 0), MAT.Fabric, "Cyl")
	end
	-- бумажные молнии сидэ
	for _, x in ipairs({ -1.5, -0.9, 0.9, 1.5 }) do
		local u = math.abs(x) / A
		local zr = B * (1 - u ^ 4) ^ 0.25 + 0.3
		for k = 1, 4 do
			local off = (k % 2 == 0) and 0.13 or -0.13
			deco(mob, torso, "Shide", Vector3.new(0.34, 0.3, 0.03), COL.paper, CFrame.new(x + off, RY - 0.25 - k * 0.27, -zr) * CFrame.Angles(0, 0, off * 0.9), MAT.SmoothPlastic)
		end
	end

	-- ---------- СПИНА: обломки тории и каменные наросты ----------
	local TORII = Color3.fromRGB(128, 44, 34)
	local TORII_BLACK = Color3.fromRGB(28, 24, 24)
	for _, sgn in ipairs({ -1, 1 }) do
		local pCF = CFrame.new(sgn * 1.0, 2.1, 1.75) * CFrame.Angles(0.42, 0, -sgn * 0.18)
		deco(mob, torso, "ToriiPillar", Vector3.new(2.0, 0.62, 0.62), TORII, pCF * CFrame.Angles(0, 0, math.pi / 2), MAT.Wood, "Cyl")
		deco(mob, torso, "ToriiPillarBand", Vector3.new(0.3, 0.68, 0.68), TORII_BLACK, pCF * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, 0, math.pi / 2), MAT.Wood, "Cyl")
		spike(mob, torso, "ToriiSplinter", pCF * CFrame.new(0.12, 0.95, 0) * CFrame.Angles(0, 0.4, 0.25), 0.3, 0.5, TORII, MAT.Wood, true)
		spike(mob, torso, "ToriiSplinter", pCF * CFrame.new(-0.14, 0.95, 0.05) * CFrame.Angles(0, -0.3, -0.3), 0.26, 0.35, TORII, MAT.Wood, true)
	end
	local kasagiCF = CFrame.new(0.1, 3.2, 2.2) * CFrame.Angles(0.42, 0, 0.14)
	deco(mob, torso, "ToriiShimaki", Vector3.new(3.6, 0.4, 0.5), TORII, kasagiCF, MAT.Wood)
	deco(mob, torso, "ToriiKasagi", Vector3.new(3.9, 0.24, 0.66), TORII_BLACK, kasagiCF * CFrame.new(0, 0.3, 0), MAT.Wood)
	deco(mob, torso, "ToriiKasagiEnd", Vector3.new(0.7, 0.24, 0.66), TORII_BLACK, kasagiCF * CFrame.new(2.1, 0.42, 0) * CFrame.Angles(0, 0, 0.3), MAT.Wood)
	spike(mob, torso, "ToriiBreak", kasagiCF * CFrame.new(-1.8, 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2), 0.35, 0.45, TORII, MAT.Wood, true)
	spike(mob, torso, "ToriiBreak", kasagiCF * CFrame.new(-1.95, 0.3, 0) * CFrame.Angles(0.3, 0, math.pi / 2 + 0.3), 0.24, 0.35, TORII_BLACK, MAT.Wood, true)
	deco(mob, torso, "Ofuda", Vector3.new(0.34, 0.7, 0.03), COL.paper, kasagiCF * CFrame.new(0.6, -0.6, -0.28), MAT.SmoothPlastic)
	deco(mob, torso, "OfudaInk", Vector3.new(0.1, 0.55, 0.02), Color3.fromRGB(150, 24, 24), kasagiCF * CFrame.new(0.6, -0.6, -0.3), MAT.SmoothPlastic)

	local GROWTHS = {
		{ Vector3.new(-1.35, 1.5, 1.55), Vector3.new(0.7, 0, 0.35), 0.6, 1.3 },
		{ Vector3.new(1.3, 0.2, 1.55), Vector3.new(0.9, 0, -0.3), 0.55, 1.1 },
		{ Vector3.new(-0.5, -0.9, 1.55), Vector3.new(1.1, 0, 0.2), 0.5, 0.9 },
		{ Vector3.new(0.6, 1.0, 1.55), Vector3.new(0.8, 0, -0.1), 0.45, 0.8 },
	}
	for _, g in ipairs(GROWTHS) do
		spike(mob, torso, "StoneGrowth", CFrame.new(g[1]) * CFrame.Angles(g[2].X, g[2].Y, g[2].Z), g[3], g[4], STONE_C, MAT.Slate)
	end

	-- ---------- РУКИ: наросты на плечах, гранёные кулаки-молоты ----------
	local function dressArm(arm, sgn)
		local cfA = CFrame.new(sgn * 0.12, 1.8, 0) * CFrame.Angles(0.1, 0.3, -sgn * 0.15)
		local cfB = CFrame.new(sgn * 0.5, 2.35, 0.2) * CFrame.Angles(-0.2, 0.6, -sgn * 0.35)
		deco(mob, arm, "ShoulderRock", Vector3.new(2.2, 1.05, 2.1), STONE_A, cfA, MAT.Slate)
		deco(mob, arm, "ShoulderRock", Vector3.new(1.4, 0.8, 1.3), STONE_B, cfB, MAT.Slate)
		deco(mob, arm, "Moss", Vector3.new(1.8, 0.14, 1.6), MOSS_A, cfA * CFrame.new(-sgn * 0.15, 0.55, -0.1), MAT.Grass)
		deco(mob, arm, "Moss", Vector3.new(1.0, 0.12, 0.9), MOSS_B, cfB * CFrame.new(0, 0.44, 0), MAT.Grass)
		for k = 1, 3 do
			deco(mob, arm, "MossStrand", Vector3.new(0.14, 0.55, 0.05), MOSS_B, cfA * CFrame.new(-0.8 + k * 0.4, 0.2, -1.07), MAT.Grass)
		end
		spike(mob, arm, "ShoulderSpire", cfB * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, -sgn * 0.35), 0.6, 1.5, STONE_C, MAT.Slate)
		spike(mob, arm, "ShoulderSpire", cfA * CFrame.new(sgn * 0.55, 0.4, -0.5) * CFrame.Angles(-0.3, 0, -sgn * 0.6), 0.45, 0.95, STONE_C, MAT.Slate)
		spike(mob, arm, "ShoulderSpire", cfA * CFrame.new(-sgn * 0.4, 0.45, 0.6) * CFrame.Angles(0.4, 0, -sgn * 0.2), 0.4, 0.8, STONE_C, MAT.Slate)
		rune(deco(mob, arm, "RuneCrack", Vector3.new(0.9, 0.09, 0.06), RUNE_HI, cfA * CFrame.new(-0.3, 0.1, -1.07) * CFrame.Angles(0, 0, 0.5), MAT.Neon))
		rune(deco(mob, arm, "RuneCrack", Vector3.new(0.7, 0.09, 0.06), RUNE_HI, cfA * CFrame.new(0.3, -0.12, -1.07) * CFrame.Angles(0, 0, -0.4), MAT.Neon))

		-- предплечье из глыб и светящийся «локоть»
		deco(mob, arm, "ArmRock", Vector3.new(1.85, 1.3, 1.85), STONE_B, CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0.25, 0.03 * sgn), MAT.Slate)
		rune(deco(mob, arm, "ElbowRune", Vector3.new(1.72, 0.16, 1.72), RUNE_HI, CFrame.new(0, -0.28, 0), MAT.Neon))
		deco(mob, arm, "ForearmRock", Vector3.new(1.95, 1.15, 1.95), STONE_A, CFrame.new(0, -1.0, 0) * CFrame.Angles(0, -0.3, 0), MAT.Slate)

		-- гранёный кулак-молот
		deco(mob, arm, "FistCore", Vector3.new(2.3, 1.8, 2.3), STONE_D, CFrame.new(0, -2.55, 0), MAT.Slate)
		deco(mob, arm, "FistFacet", Vector3.new(2.0, 1.6, 2.0), STONE_B, CFrame.new(0, -2.55, 0) * CFrame.Angles(0, math.pi / 4, 0), MAT.Slate)
		deco(mob, arm, "FistBase", Vector3.new(1.7, 0.3, 1.7), STONE_B, CFrame.new(0, -3.5, 0) * CFrame.Angles(0, math.pi / 4, 0), MAT.Slate)
		for _, x in ipairs({ -0.75, -0.25, 0.25, 0.75 }) do
			deco(mob, arm, "Knuckle", Vector3.new(0.48, 0.5, 0.35), STONE_A, CFrame.new(x, -2.05, -1.22), MAT.Slate)
			spike(mob, arm, "KnuckleSpike", CFrame.new(x, -2.05, -1.38) * CFrame.Angles(-math.pi / 2, 0, 0), 0.32, 0.55, STONE_C, MAT.Basalt)
		end
		for _, dy in ipairs({ 0.35, -0.35 }) do
			spike(mob, arm, "FistSpike", CFrame.new(sgn * 1.3, -2.55 + dy, 0) * CFrame.Angles(0, 0, -sgn * math.pi / 2), 0.4, 0.7, STONE_C, MAT.Basalt)
		end
		for _, x in ipairs({ -0.68, 0.68 }) do
			rune(deco(mob, arm, "FistRune", Vector3.new(0.6, 0.09, 0.06), RUNE_HI, CFrame.new(x, -2.75, -1.18) * CFrame.Angles(0, 0, x * 0.45), MAT.Neon))
		end
	end
	dressArm(leftArm, -1)
	dressArm(rightArm, 1)

	-- ---------- НОГИ: глыбы, светящиеся колени, массивные ступни ----------
	for _, pair in ipairs({ { leftLeg, -1 }, { rightLeg, 1 } }) do
		local leg, sgn = pair[1], pair[2]
		deco(mob, leg, "ThighRock", Vector3.new(1.75, 1.1, 1.75), STONE_B, CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0.3 * sgn, 0), MAT.Slate)
		rune(deco(mob, leg, "KneeRune", Vector3.new(1.6, 0.14, 1.6), RUNE_HI, CFrame.new(0, 0.14, 0), MAT.Neon))
		deco(mob, leg, "ShinRock", Vector3.new(1.65, 1.0, 1.65), STONE_A, CFrame.new(0, -0.52, 0) * CFrame.Angles(0, -0.25 * sgn, 0), MAT.Slate)
		deco(mob, leg, "Foot", Vector3.new(2.0, 0.45, 2.3), STONE_D, CFrame.new(0, -1.27, -0.2), MAT.Slate)
		deco(mob, leg, "FootToe", Vector3.new(2.0, 0.45, 0.55), STONE_D, CFrame.new(0, -1.27, -1.625), MAT.Slate, "Wedge")
		deco(mob, leg, "Moss", Vector3.new(1.1, 0.1, 0.7), MOSS_A, CFrame.new(sgn * 0.3, -1.0, -1.0), MAT.Grass)
	end

	-- ---------- ГОЛОВА: монолитная плита-маска ----------
	local MASKSTONE = Color3.fromRGB(74, 76, 74)
	deco(mob, head, "MonolithMask", Vector3.new(2.1, 2.3, 0.45), MASKSTONE, CFrame.new(0, 0.05, -1.12), MAT.Slate)
	deco(mob, head, "MonolithCap", Vector3.new(2.35, 0.34, 0.72), STONE_B, CFrame.new(0, 1.33, -1.02), MAT.Slate)
	deco(mob, head, "Moss", Vector3.new(2.1, 0.12, 0.62), MOSS_A, CFrame.new(0, 1.55, -1.02), MAT.Grass)
	deco(mob, head, "Moss", Vector3.new(1.6, 0.12, 1.4), MOSS_B, CFrame.new(0.1, 0.96, 0.1), MAT.Grass)
	for _, x in ipairs({ -0.85, -0.6, 0.75 }) do
		deco(mob, head, "MossStrand", Vector3.new(0.13, 0.5, 0.05), MOSS_B, CFrame.new(x, 0.95, -1.37), MAT.Grass)
	end
	for _, sgn in ipairs({ -1, 1 }) do
		deco(mob, head, "BrowRidge", Vector3.new(0.85, 0.2, 0.18), STONE_C, CFrame.new(sgn * 0.48, 0.56, -1.43) * CFrame.Angles(0, 0, sgn * 0.18), MAT.Slate)
		deco(mob, head, "EyeSocket", Vector3.new(0.74, 0.3, 0.04), COL.voidDark, CFrame.new(sgn * 0.48, 0.32, -1.36) * CFrame.Angles(0, 0, sgn * 0.14))
		rune(deco(mob, head, "RuneEye", Vector3.new(0.62, 0.1, 0.05), RUNE_HI, CFrame.new(sgn * 0.48, 0.32, -1.39) * CFrame.Angles(0, 0, sgn * 0.14), MAT.Neon))
		rune(deco(mob, head, "RuneTear", Vector3.new(0.07, 0.45, 0.05), RUNE_HI, CFrame.new(sgn * 0.52, -0.12, -1.37), MAT.Neon))
	end
	rune(deco(mob, head, "RuneBrand", Vector3.new(0.09, 0.6, 0.05), RUNE_HI, CFrame.new(0, 0.9, -1.37), MAT.Neon))
	for _, y in ipairs({ 1.05, 0.8 }) do
		rune(deco(mob, head, "RuneBrand", Vector3.new(0.34, 0.07, 0.05), RUNE_HI, CFrame.new(0, y, -1.37), MAT.Neon))
	end
	deco(mob, head, "MouthGroove", Vector3.new(1.2, 0.14, 0.04), COL.voidDark, CFrame.new(0, -0.62, -1.36))
	rune(deco(mob, head, "RuneMouth", Vector3.new(1.0, 0.05, 0.05), RUNE_HI, CFrame.new(0, -0.62, -1.385), MAT.Neon))
	for k = -1.5, 1.5 do
		deco(mob, head, "MouthTooth", Vector3.new(0.09, 0.18, 0.05), MASKSTONE, CFrame.new(k * 0.3, -0.62, -1.395), MAT.Slate)
	end
	-- каменные рога с загнутыми остриями
	spike(mob, crownHornL, "HornTip", CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, 0.6), 0.44, 1.0, Color3.fromRGB(34, 36, 40), MAT.Basalt)
	spike(mob, crownHornR, "HornTip", CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, -0.6), 0.44, 1.0, Color3.fromRGB(34, 36, 40), MAT.Basalt)

	-- свет, духовные искры и пульсация швов
	local coreLight = addLight(chestCore, RUNE_HI, 14, 2)
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "SpiritMotes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(RUNE_HI, RUNE_LO)
	motes.LightEmission = 1
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(1.2, 2)
	motes.Rate = 8
	motes.Speed = NumberRange.new(1, 2.5)
	motes.SpreadAngle = Vector2.new(50, 50)
	motes.Acceleration = Vector3.new(0, 2, 0)
	motes.RotSpeed = NumberRange.new(-60, 60)
	motes.Parent = chestCore
	table.insert(runes, chestCore)

	mob.PrimaryPart = torso
	mob.Parent = workspace

	attachSmartHealthBar(mob, head)
	startRunePulse(mob, humanoid, runes, coreLight, RUNE_HI, RUNE_LO, 1.8)

	local slamCooldown = false

	task.spawn(function()
		while mob and mob.Parent and humanoid.Health > 0 do
			local targetChar = findNearestTarget(torso.Position, 250)
			if targetChar then
				local targetRoot = targetChar.HumanoidRootPart
				local dist = (targetRoot.Position - torso.Position).Magnitude

				if dist > 6.5 then
					humanoid:MoveTo(targetRoot.Position)
				else
					humanoid:MoveTo(torso.Position)
					if not slamCooldown then
						slamCooldown = true

						torso.AssemblyLinearVelocity = Vector3.new(0, 15, 0)
						task.wait(0.45)

						if mob.Parent and humanoid.Health > 0 then
							local shock = Instance.new("Part")
							shock.Shape = Enum.PartType.Cylinder
							shock.Size = Vector3.new(0.4, 2, 2)
							shock.CFrame = torso.CFrame * CFrame.new(0, -3.4, 0) * CFrame.Angles(0, 0, math.rad(90))
							shock.Color = Color3.fromRGB(255, 75, 40)
							shock.Material = Enum.Material.Neon
							shock.CanCollide = false
							shock.Anchored = true
							shock.Parent = workspace

							TweenService:Create(shock, TweenInfo.new(0.35), {
								Size = Vector3.new(0.4, 24, 24),
								Transparency = 1
							}):Play()
							Debris:AddItem(shock, 0.4)

							for _, plr in ipairs(Players:GetPlayers()) do
								local c = plr.Character
								local r = c and c:FindFirstChild("HumanoidRootPart")
								local h = c and c:FindFirstChild("Humanoid")
								if r and h and (r.Position - torso.Position).Magnitude <= 12 then
									damagePlayer(h, 20)
									r.AssemblyLinearVelocity = (r.Position - torso.Position).Unit * 35 + Vector3.new(0, 16, 0)
								end
							end
						end

						task.delay(2.2, function() slamCooldown = false end)
					end
				end
			end
			task.wait(0.15)
		end
	end)

	return mob
end

-- ================= ГЛОБАЛЬНЫЙ МЕТОД СПАВНА =================
_G.SpawnMob = function(mobType, cframe)
	local mob = nil
	local ok, err = pcall(function()
		if mobType == "RockSlime" then
			mob = createRockSlime(cframe)
		elseif mobType == "CrystalSentry" then
			mob = createCrystalSentry(cframe)
		elseif mobType == "ArmoredColossus" then
			mob = createArmoredColossus(cframe)
		else
			mob = createVoxelGolem(cframe)
		end
	end)
	if not ok then
		warn("[MobSpawner Error]:", err)
	end
	return mob
end

-- ================= СПАВН ВОЛНЫ ПЕРЕД ИГРОКОМ ПО НАЖАТИЮ [Y] =================
local activeWaveMobs = {}

local function findSafeFloor(pos)
	local rayOrigin = Vector3.new(pos.X, pos.Y + 25, pos.Z)
	local rayDirection = Vector3.new(0, -65, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hit = workspace:Raycast(rayOrigin, rayDirection, params)
	return hit and hit.Position or nil
end

local function spawnWave(referenceCF)
	for _, m in ipairs(activeWaveMobs) do
		if m and m.Parent then m:Destroy() end
	end
	activeWaveMobs = {}

	local forward = referenceCF.LookVector
	local right = referenceCF.RightVector
	local basePos = referenceCF.Position + (forward * 30)

	local offsets = { -18, -6, 6, 18 }
	local mobList = { "RockSlime", "VoxelGolem", "CrystalSentry", "ArmoredColossus" }

	for i, offsetStuds in ipairs(offsets) do
		local testPos = basePos + (right * offsetStuds)
		local floorPos = findSafeFloor(testPos)

		if not floorPos then
			testPos = referenceCF.Position + (forward * 16) + (right * (offsetStuds * 0.6))
			floorPos = findSafeFloor(testPos)
		end

		if not floorPos then
			floorPos = Vector3.new(testPos.X, referenceCF.Position.Y, testPos.Z)
		end

		local groundCF = CFrame.new(floorPos + Vector3.new(0, 1.2, 0))
		local lookTarget = Vector3.new(referenceCF.Position.X, groundCF.Position.Y, referenceCF.Position.Z)
		local finalCF = CFrame.lookAt(groundCF.Position, lookTarget)

		local mob = _G.SpawnMob(mobList[i], finalCF)
		if mob then
			table.insert(activeWaveMobs, mob)
		end
	end
	print(">>> [MobSpawner] 4 моба заспавнены по нажатию [Y]!")
end

-- Принимаем сигнал от игрока по кнопке [Y]
spawnDebugEvent.OnServerEvent:Connect(function(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		spawnWave(root.CFrame)
	end
end)
