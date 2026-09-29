--[[
	StatUpgradeServer (Script > ServerScriptService)

	Мета-прокачка персонажа (Stat Upgrade Tree в стиле Dying Light).

	• За каждый уровень (атрибут PlayerLevel от LevelManager) — +1 очко таланта.
	  Выданные уровни запоминаются (LastLevel), поэтому очки не дублируются
	  и докидываются, если уровень вырос, пока данные ещё грузились.
	• 3 ветки:
	    Живучесть  — +5 MaxHealth за уровень,             кап 20
	    Ловкость   — +3% дальности/скорости рывка
	                 и −3% перезарядки Roll за уровень,    кап 10
	    Стойкость  — +2% снижения входящего урона,         кап 10
	• Перекат по умолчанию в 2 раза короче (BASE_ROLL_SCALE = 0.5),
	  прокачка Ловкости множит уже эту базу.
	• Сохранение в DataStore: вход / выход / BindToClose / автосейв.
	  Если загрузка упала — данные НЕ перезаписываются дефолтами.

	Атрибуты ПЕРСОНАЖА (для боёвки, рывка и скриптов урона):
	    DefenseMultiplier       = 1 − DefenseLvl * 0.02   (итоговый урон = урон * DefenseMultiplier)
	    RollMultiplier          = 0.5 * (1 + RollLvl * 0.03)  (дальность/скорость рывка)
	    RollCooldownMultiplier  = 1 − RollLvl * 0.03       (множитель перезарядки)
	    StatHealthBonus         = HealthLvl * 5 (уже добавлено к Humanoid.MaxHealth)

	Атрибуты ИГРОКА (для UI): StatPoints, StatHealthLvl, StatRollLvl, StatDefenseLvl, StatsLoaded

	API: RemoteFunction ReplicatedStorage.UpgradeStat(statName) -> { ok, reason?, state }
	     _G.ApplyPlayerDefense(character, amount) -> урон после брони
	     _G.DamagePlayer(humanoid, amount)        -> TakeDamage с учётом брони и i-frames переката
	     [DEV] _G.DevGiveStatPoints(player, amount)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local DEBUG = true
local function dbg(...)
	if DEBUG then
		print("[StatUpgrade]", ...)
	end
end

-- ================= НАСТРОЙКИ =================
local STATS = {
	Health  = { Key = "HealthLvl",  Max = 20 },
	Roll    = { Key = "RollLvl",    Max = 10 },
	Defense = { Key = "DefenseLvl", Max = 10 },
}

local HEALTH_PER_LEVEL = 5
local ROLL_PER_LEVEL = 0.03
local DEFENSE_PER_LEVEL = 0.02
local BASE_ROLL_SCALE = 0.5 -- перекат изначально в 2 раза меньше

local AUTOSAVE_INTERVAL = 60
local UPGRADE_DEBOUNCE = 0.1

-- ================= REMOTE =================
local upgradeRemote = ReplicatedStorage:FindFirstChild("UpgradeStat")
if not upgradeRemote then
	upgradeRemote = Instance.new("RemoteFunction")
	upgradeRemote.Name = "UpgradeStat"
	upgradeRemote.Parent = ReplicatedStorage
end

local statStore = nil
do
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore("PlayerStatTree_v1")
	end)
	if ok and store then
		statStore = store
	else
		warn("[StatUpgrade] DataStore недоступен — прокачка не сохранится (в Studio включи API Services)")
	end
end

local playerData = {}
local loadOk = {} -- true только если GetAsync прошёл успешно (иначе не сохраняем)
local dirty = {}
local lastUpgrade = {}

-- ================= ПРИМЕНЕНИЕ СТАТОВ =================
local function publishPlayerAttributes(player, data)
	player:SetAttribute("StatPoints", data.Points)
	player:SetAttribute("StatHealthLvl", data.HealthLvl)
	player:SetAttribute("StatRollLvl", data.RollLvl)
	player:SetAttribute("StatDefenseLvl", data.DefenseLvl)
end

-- Добавляем к MaxHealth только разницу с уже применённым бонусом,
-- чтобы не ломать чужие модификаторы здоровья (карты, баффы и т.д.)
local function applyHealth(character, data, healCurrent)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local target = data.HealthLvl * HEALTH_PER_LEVEL
	local applied = tonumber(character:GetAttribute("StatHealthBonus")) or 0
	local diff = target - applied
	if diff == 0 then return end

	character:SetAttribute("StatHealthBonus", target)
	hum.MaxHealth = math.max(1, hum.MaxHealth + diff)
	if hum.Health > 0 then
		if healCurrent then
			hum.Health = math.min(hum.MaxHealth, hum.Health + math.max(diff, 0))
		else
			hum.Health = math.min(hum.Health, hum.MaxHealth)
		end
	end
end

local function applyCharacter(player, healCurrent)
	local data = playerData[player]
	local character = player.Character
	if not data or not character then return end

	character:SetAttribute("DefenseMultiplier", 1 - data.DefenseLvl * DEFENSE_PER_LEVEL)
	character:SetAttribute("RollMultiplier", BASE_ROLL_SCALE * (1 + data.RollLvl * ROLL_PER_LEVEL))
	character:SetAttribute("RollCooldownMultiplier", 1 - data.RollLvl * ROLL_PER_LEVEL)
	applyHealth(character, data, healCurrent)
end

-- ================= ОЧКИ ЗА УРОВНИ =================
local function syncLevelPoints(player)
	local data = playerData[player]
	if not data then return end
	local lvl = tonumber(player:GetAttribute("PlayerLevel"))
	if not lvl then return end -- LevelManager ещё не загрузил уровень

	if lvl > data.LastLevel then
		local gained = lvl - data.LastLevel
		data.Points += gained
		data.LastLevel = lvl
		dirty[player] = true
		publishPlayerAttributes(player, data)
		dbg(string.format("%s +%d очк. таланта (ур.%d), всего %d", player.Name, gained, lvl, data.Points))
	end
end

-- ================= ЗАГРУЗКА / СОХРАНЕНИЕ =================
local function sanitize(saved)
	local function num(key, lo, hi)
		local v = type(saved) == "table" and tonumber(saved[key]) or nil
		return math.clamp(math.floor(v or lo), lo, hi)
	end
	return {
		Points = num("Points", 0, math.huge),
		HealthLvl = num("HealthLvl", 0, STATS.Health.Max),
		RollLvl = num("RollLvl", 0, STATS.Roll.Max),
		DefenseLvl = num("DefenseLvl", 0, STATS.Defense.Max),
		LastLevel = num("LastLevel", 1, math.huge), -- персонаж начинает с 1 уровня
	}
end

local function savePlayer(player)
	if not statStore or not loadOk[player] then return end
	local data = playerData[player]
	if not data then return end
	dirty[player] = nil

	local ok, err = pcall(function()
		statStore:SetAsync("Player_" .. player.UserId, {
			Points = data.Points,
			HealthLvl = data.HealthLvl,
			RollLvl = data.RollLvl,
			DefenseLvl = data.DefenseLvl,
			LastLevel = data.LastLevel,
		})
	end)
	if not ok then
		dirty[player] = true
		warn("[StatUpgrade] Ошибка сохранения:", err)
	end
end

local function onCharacterAdded(player, character)
	character:WaitForChild("Humanoid", 10)
	if player.Character ~= character then return end
	-- Новый персонаж: бонус HP ещё не применён, лечим до полного
	applyCharacter(player, true)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = hum.MaxHealth
	end
end

local function loadPlayer(player)
	local saved = nil
	local ok = true
	if statStore then
		local success, result = pcall(function()
			return statStore:GetAsync("Player_" .. player.UserId)
		end)
		if success then
			saved = result
		else
			ok = false
			warn("[StatUpgrade] Ошибка загрузки (сохранение для игрока отключено):", result)
		end
	end
	if not player.Parent then return end

	local data = sanitize(saved)
	playerData[player] = data
	loadOk[player] = ok and statStore ~= nil

	publishPlayerAttributes(player, data)
	syncLevelPoints(player)
	player:SetAttribute("StatsLoaded", true)

	player:GetAttributeChangedSignal("PlayerLevel"):Connect(function()
		syncLevelPoints(player)
	end)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	dbg(string.format("%s загружен: очки %d, HP %d, Roll %d, Def %d",
		player.Name, data.Points, data.HealthLvl, data.RollLvl, data.DefenseLvl))
end

Players.PlayerAdded:Connect(loadPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(loadPlayer, p)
end

Players.PlayerRemoving:Connect(function(player)
	savePlayer(player)
	playerData[player] = nil
	loadOk[player] = nil
	dirty[player] = nil
	lastUpgrade[player] = nil
end)

game:BindToClose(function()
	local threads = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(threads, task.spawn(savePlayer, player))
	end
	-- ждём завершения всех сохранений (не дольше ~25 с)
	local deadline = os.clock() + 25
	for _, th in ipairs(threads) do
		while coroutine.status(th) ~= "dead" and os.clock() < deadline do
			task.wait()
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player in pairs(dirty) do
			if player.Parent then
				task.spawn(savePlayer, player)
			else
				dirty[player] = nil
			end
		end
	end
end)

-- ================= ПРОКАЧКА =================
local function snapshot(data)
	return {
		Points = data.Points,
		HealthLvl = data.HealthLvl,
		RollLvl = data.RollLvl,
		DefenseLvl = data.DefenseLvl,
	}
end

upgradeRemote.OnServerInvoke = function(player, statName)
	local data = playerData[player]
	if not data then
		return { ok = false, reason = "NotLoaded" }
	end

	local now = os.clock()
	if lastUpgrade[player] and now - lastUpgrade[player] < UPGRADE_DEBOUNCE then
		return { ok = false, reason = "TooFast", state = snapshot(data) }
	end
	lastUpgrade[player] = now

	local def = type(statName) == "string" and STATS[statName]
	if not def then
		return { ok = false, reason = "BadStat", state = snapshot(data) }
	end
	if data.Points <= 0 then
		return { ok = false, reason = "NoPoints", state = snapshot(data) }
	end
	if data[def.Key] >= def.Max then
		return { ok = false, reason = "MaxLevel", state = snapshot(data) }
	end

	data.Points -= 1
	data[def.Key] += 1
	dirty[player] = true

	publishPlayerAttributes(player, data)
	applyCharacter(player, true)

	dbg(string.format("%s прокачал %s → %d/%d (очков осталось %d)",
		player.Name, statName, data[def.Key], def.Max, data.Points))

	return { ok = true, state = snapshot(data) }
end

-- ================= API ДЛЯ СКРИПТОВ УРОНА =================
-- Итоговый урон = ВходящийУрон * (1 − DefenseLvl * 0.02)
_G.ApplyPlayerDefense = function(character, amount)
	local mult = typeof(character) == "Instance" and tonumber(character:GetAttribute("DefenseMultiplier")) or 1
	return amount * math.clamp(mult, 0, 1)
end

_G.DamagePlayer = function(humanoid, amount)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") then return 0 end
	local character = humanoid.Parent
	if character and character:GetAttribute("IsDodging") then
		return 0 -- i-frames переката (RollServer)
	end
	local final = _G.ApplyPlayerDefense(character, amount)
	humanoid:TakeDamage(final)
	return final
end

-- [DEV] выдать очки талантов
_G.DevGiveStatPoints = function(player, amount)
	local data = playerData[player]
	if not data then return end
	data.Points += math.max(1, math.floor(tonumber(amount) or 1))
	dirty[player] = true
	publishPlayerAttributes(player, data)
end

dbg("Запущен")
