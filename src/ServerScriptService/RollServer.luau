local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- ================= НАСТРОЙКИ ПЕРЕКАТА =================
-- Скорость = BASE_ROLL_SPEED * RollMultiplier (атрибут от StatUpgradeServer).
-- RollMultiplier = 0.5 на 0 уровне «Ловкости» → перекат изначально в 2 раза меньше,
-- каждый уровень Ловкости даёт +3% к этой скорости.
local BASE_ROLL_SPEED = 50       -- студ/с при множителе 1.0 (подкрути под свой старый перекат)
local ROLL_DURATION = 0.38       -- длительность рывка и i-frames
local DEFAULT_ROLL_MULT = 0.5    -- если StatUpgradeServer ещё не выставил атрибут

-- Создаем RemoteEvent для синхронизации кувырка между всеми игроками
local rollEvent = ReplicatedStorage:FindFirstChild("RollReplicationEvent")
if not rollEvent then
	rollEvent = Instance.new("RemoteEvent")
	rollEvent.Name = "RollReplicationEvent"
	rollEvent.Parent = ReplicatedStorage
end

local rollToken = setmetatable({}, { __mode = "k" })

-- Горизонтальное направление рывка (клиентское rollDir проверяем, иначе — взгляд персонажа)
local function getRollDirection(root, rollDir)
	if typeof(rollDir) == "Vector3" then
		local flat = Vector3.new(rollDir.X, 0, rollDir.Z)
		if flat.Magnitude > 1e-3 and flat.Magnitude == flat.Magnitude then
			return flat.Unit
		end
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
end

rollEvent.OnServerEvent:Connect(function(player, rollDir)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then return end

	local token = (rollToken[char] or 0) + 1
	rollToken[char] = token

	-- Серверная неуязвимость от урона мобов на время переката
	char:SetAttribute("IsDodging", true)

	-- Звук рывка (слышат все игроки рядом)
	local whoosh = Instance.new("Sound")
	whoosh.SoundId = "rbxassetid://9114223175"
	whoosh.Volume = 0.8
	whoosh.PlaybackSpeed = 1.15
	whoosh.RollOffMaxDistance = 60
	whoosh.Parent = root
	whoosh:Play()
	Debris:AddItem(whoosh, 1.2)

	-- ================= ДВИЖЕНИЕ ПЕРЕКАТА =================
	-- Горизонтальная скорость задаётся ограничителем; по вертикали (гравитация) не трогаем.
	local rollMult = tonumber(char:GetAttribute("RollMultiplier")) or DEFAULT_ROLL_MULT
	local dir = getRollDirection(root, rollDir)
	local speed = BASE_ROLL_SPEED * rollMult

	local oldVel = root:FindFirstChild("RollVelocity")
	if oldVel then oldVel:Destroy() end
	local oldAtt = root:FindFirstChild("RollAttachment")
	if oldAtt then oldAtt:Destroy() end

	local att = Instance.new("Attachment")
	att.Name = "RollAttachment"
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "RollVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * speed
	lv.MaxForce = 1e6
	lv.Parent = root

	Debris:AddItem(lv, ROLL_DURATION)
	Debris:AddItem(att, ROLL_DURATION)

	-- Оповещаем других игроков (анимация); 3-й аргумент — множитель рывка
	rollEvent:FireAllClients(player, rollDir, rollMult)

	task.delay(ROLL_DURATION, function()
		if char and char.Parent and rollToken[char] == token then
			char:SetAttribute("IsDodging", false)
		end
	end)
end)
