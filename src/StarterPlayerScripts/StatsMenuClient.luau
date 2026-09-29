--[[
	StatsMenuClient (LocalScript > StarterPlayerScripts)

	Меню мета-прокачки (Stat Upgrade Tree). Открытие: клавиша U или кнопка в HUD.
	Стиль: тёмный обсидиан, золотая рамка с градиентом, рубиновые акценты.

	Данные берутся из атрибутов игрока (StatPoints / StatHealthLvl / StatRollLvl /
	StatDefenseLvl), которые выставляет StatUpgradeServer. Прокачка — через
	RemoteFunction ReplicatedStorage.UpgradeStat, вся проверка на сервере.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local upgradeRemote = ReplicatedStorage:WaitForChild("UpgradeStat")

---------------------------------------------------------------------
-- НАСТРОЙКИ
---------------------------------------------------------------------
local SOUNDS = {
	StoneClick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.7, Speed = 0.55 }, -- глухой «камень»
	MetalRing  = { Id = "rbxasset://sounds/unsheath.wav",  Volume = 0.6, Speed = 1.1 },  -- звон металла
}

local BRANCHES = {
	{
		Stat = "Health", Attr = "StatHealthLvl", Max = 20,
		Icon = "❤", Title = "ЖИВУЧЕСТЬ", Desc = "+5 HP за уровень",
		Bonus = function(lvl) return string.format("Бонус: +%d HP", lvl * 5) end,
	},
	{
		Stat = "Roll", Attr = "StatRollLvl", Max = 10,
		Icon = "👢", Title = "ЛОВКОСТЬ", Desc = "+3% к мобильности за уровень",
		Bonus = function(lvl) return string.format("Бонус: +%d%% рывок, −%d%% перезарядка", lvl * 3, lvl * 3) end,
	},
	{
		Stat = "Defense", Attr = "StatDefenseLvl", Max = 10,
		Icon = "🛡", Title = "СТОЙКОСТЬ", Desc = "+2% к снижению урона за уровень",
		Bonus = function(lvl) return string.format("Бонус: −%d%% входящего урона", lvl * 2) end,
	},
}

local COLORS = {
	White      = Color3.fromRGB(255, 255, 255),
	Obsidian   = Color3.fromRGB(12, 10, 14),
	ObsidianHi = Color3.fromRGB(34, 29, 37),
	Card       = Color3.fromRGB(20, 17, 23),
	CardHi     = Color3.fromRGB(38, 32, 42),
	TrackBg    = Color3.fromRGB(7, 5, 8),

	GoldLight  = Color3.fromRGB(255, 228, 155),
	Gold       = Color3.fromRGB(212, 165, 70),
	GoldDark   = Color3.fromRGB(115, 78, 28),
	EmbossDark = Color3.fromRGB(38, 20, 6),

	RubyLight  = Color3.fromRGB(240, 70, 78),
	Ruby       = Color3.fromRGB(172, 16, 34),
	RubyDark   = Color3.fromRGB(88, 4, 14),

	TextDim    = Color3.fromRGB(165, 150, 135),
	Disabled   = Color3.fromRGB(70, 64, 70),
}

---------------------------------------------------------------------
-- ХЕЛПЕРЫ
---------------------------------------------------------------------
local function create(className, props, children)
	local inst = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do
		inst[k] = v
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	inst.Parent = parent
	return inst
end

local function corner(r)
	return create("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function goldGradient(rotation)
	return create("UIGradient", {
		Rotation = rotation or 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLORS.GoldLight),
			ColorSequenceKeypoint.new(0.45, COLORS.Gold),
			ColorSequenceKeypoint.new(1, COLORS.GoldDark),
		}),
	})
end

local function goldStroke(thickness, rotation)
	return create("UIStroke", {
		Color = COLORS.White, -- цвет задаёт градиент
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, { goldGradient(rotation) })
end

local function obsidianGradient()
	return create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLORS.ObsidianHi),
			ColorSequenceKeypoint.new(1, COLORS.Obsidian),
		}),
	})
end

local function applyFont(label, weight)
	local ok = pcall(function()
		label.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", weight or Enum.FontWeight.Bold)
	end)
	if not ok then
		label.Font = Enum.Font.GothamBold
	end
end

local function playSound(def)
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.Volume = def.Volume
	s.PlaybackSpeed = def.Speed
	s.Parent = SoundService
	s.Ended:Once(function() s:Destroy() end)
	s:Play()
	task.delay(4, function()
		if s.Parent then s:Destroy() end
	end)
end

---------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------
local old = playerGui:FindFirstChild("StatTreeGui")
if old then old:Destroy() end

local screenGui = create("ScreenGui", {
	Name = "StatTreeGui",
	ResetOnSpawn = false,
	DisplayOrder = 46,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- ---------- Кнопка в HUD (рядом с [C] и [H] из StatsUIController) ----------
local hudBtn = create("TextButton", {
	Name = "TalentsButton",
	Size = UDim2.fromOffset(56, 56),
	Position = UDim2.new(1, -208, 1, -85),
	BackgroundColor3 = COLORS.White,
	AutoButtonColor = false,
	Text = "",
	Parent = screenGui,
}, { corner(12), obsidianGradient(), goldStroke(1.6, 45) })

create("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "✦",
	TextColor3 = COLORS.GoldLight,
	TextSize = 26,
	Font = Enum.Font.GothamBlack,
	Parent = hudBtn,
})

create("TextLabel", {
	Size = UDim2.fromOffset(18, 15),
	Position = UDim2.new(1, -15, 1, -13),
	BackgroundColor3 = COLORS.RubyDark,
	Text = "U",
	TextColor3 = COLORS.White,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	Parent = hudBtn,
}, { corner(4) })

-- Рубиновый бейдж «есть очки»
local hudDot = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(20, 20),
	Position = UDim2.new(1, -4, 0, 4),
	BackgroundColor3 = COLORS.Ruby,
	Text = "0",
	TextColor3 = COLORS.White,
	Font = Enum.Font.GothamBlack,
	TextSize = 11,
	Visible = false,
	ZIndex = 3,
	Parent = hudBtn,
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), create("UIStroke", { Color = COLORS.GoldLight, Thickness = 1.2 }) })

-- ---------- Затемнение и панель ----------
local dim = create("Frame", {
	Name = "Dim",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = screenGui,
})

local panel = create("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(560, 500),
	BackgroundColor3 = COLORS.White,
	Visible = false,
	Parent = screenGui,
}, { corner(14), obsidianGradient() })

local uiScale = create("UIScale", { Scale = 1, Parent = panel })

local frameStroke = goldStroke(2.5, 0)
frameStroke.Parent = panel
local frameGradient = frameStroke:FindFirstChildOfClass("UIGradient")

-- Внутренняя рубиновая кайма
create("Frame", {
	Position = UDim2.fromOffset(6, 6),
	Size = UDim2.new(1, -12, 1, -12),
	BackgroundTransparency = 1,
	Parent = panel,
}, { corner(10), create("UIStroke", { Color = COLORS.RubyDark, Thickness = 1, Transparency = 0.25 }) })

-- ---------- Шапка ----------
local title = create("TextLabel", {
	Position = UDim2.fromOffset(28, 18),
	Size = UDim2.new(1, -90, 0, 28),
	BackgroundTransparency = 1,
	Text = "ДРЕВО ТАЛАНТОВ",
	TextColor3 = COLORS.White,
	TextSize = 24,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
}, { goldGradient(), create("UIStroke", { Color = COLORS.EmbossDark, Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }) })
applyFont(title, Enum.FontWeight.Heavy)

local closeBtn = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, 18),
	Size = UDim2.fromOffset(32, 32),
	BackgroundColor3 = COLORS.RubyDark,
	AutoButtonColor = true,
	Text = "✕",
	TextColor3 = COLORS.GoldLight,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	Parent = panel,
}, { corner(8), create("UIStroke", { Color = COLORS.Gold, Thickness = 1.2 }) })

-- Разделитель
create("Frame", {
	Position = UDim2.fromOffset(28, 56),
	Size = UDim2.new(1, -56, 0, 2),
	BackgroundColor3 = COLORS.White,
	BorderSizePixel = 0,
	Parent = panel,
}, {
	create("UIGradient", {
		Color = ColorSequence.new(COLORS.Gold),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})

-- Счётчик очков
local pointsGlow = create("UIStroke", {
	Color = COLORS.GoldLight,
	Thickness = 0,
	Transparency = 1,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
})
local pointsLabel = create("TextLabel", {
	Position = UDim2.fromOffset(0, 66),
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Text = "ОЧКИ ТАЛАНТОВ: 0",
	TextColor3 = COLORS.GoldLight,
	TextSize = 30,
	Parent = panel,
}, { pointsGlow })
applyFont(pointsLabel, Enum.FontWeight.Heavy)

-- ---------- Карточки ----------
local list = create("Frame", {
	Position = UDim2.fromOffset(22, 118),
	Size = UDim2.new(1, -44, 1, -136),
	BackgroundTransparency = 1,
	Parent = panel,
}, {
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
	}),
})

local cards = {}

local function makeCard(def, order)
	local card = create("Frame", {
		Name = def.Stat .. "Card",
		Size = UDim2.new(1, 0, 0, 112),
		BackgroundColor3 = COLORS.Card,
		LayoutOrder = order,
		Parent = list,
	}, { corner(10) })
	local cardStroke = create("UIStroke", { Color = COLORS.GoldDark, Thickness = 1.4, Transparency = 0.2, Parent = card })

	-- Иконка в рубиновом медальоне
	local iconBox = create("Frame", {
		Position = UDim2.fromOffset(14, 16),
		Size = UDim2.fromOffset(80, 80),
		BackgroundColor3 = COLORS.White,
		Parent = card,
	}, {
		corner(10),
		create("UIGradient", {
			Rotation = 135,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, COLORS.RubyLight),
				ColorSequenceKeypoint.new(0.5, COLORS.Ruby),
				ColorSequenceKeypoint.new(1, COLORS.RubyDark),
			}),
		}),
		goldStroke(2, 45),
	})
	create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = def.Icon,
		TextColor3 = COLORS.White,
		TextSize = 40,
		Font = Enum.Font.GothamBold,
		Parent = iconBox,
	})

	-- Название / описание
	local nameLbl = create("TextLabel", {
		Position = UDim2.fromOffset(110, 12),
		Size = UDim2.new(1, -230, 0, 24),
		BackgroundTransparency = 1,
		Text = def.Title,
		TextColor3 = COLORS.White,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	}, { goldGradient() })
	applyFont(nameLbl, Enum.FontWeight.Heavy)

	create("TextLabel", {
		Position = UDim2.fromOffset(110, 36),
		Size = UDim2.new(1, -230, 0, 18),
		BackgroundTransparency = 1,
		Text = def.Desc,
		TextColor3 = COLORS.TextDim,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	local bonusLbl = create("TextLabel", {
		Position = UDim2.fromOffset(110, 54),
		Size = UDim2.new(1, -230, 0, 18),
		BackgroundTransparency = 1,
		Text = def.Bonus(0),
		TextColor3 = COLORS.RubyLight,
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})

	-- Прогресс-бар
	local track = create("Frame", {
		Position = UDim2.fromOffset(110, 80),
		Size = UDim2.new(1, -230, 0, 16),
		BackgroundColor3 = COLORS.TrackBg,
		ClipsDescendants = true,
		Parent = card,
	}, { corner(4), create("UIStroke", { Color = COLORS.GoldDark, Thickness = 1 }) })

	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.White,
		BorderSizePixel = 0,
		Parent = track,
	}, {
		corner(4),
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, COLORS.RubyLight),
				ColorSequenceKeypoint.new(0.5, COLORS.Ruby),
				ColorSequenceKeypoint.new(1, COLORS.RubyDark),
			}),
		}),
	})

	-- Деления по уровням
	for i = 1, def.Max - 1 do
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(i / def.Max, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = track,
		})
	end

	local progressLbl = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "0 / " .. def.Max,
		TextColor3 = COLORS.White,
		TextSize = 12,
		Font = Enum.Font.GothamBlack,
		ZIndex = 3,
		Parent = track,
	}, { create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.2 }) })

	-- Кнопка «+»
	local btn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(96, 64),
		BackgroundColor3 = COLORS.White,
		AutoButtonColor = false,
		Text = "+",
		TextColor3 = COLORS.GoldLight,
		TextSize = 36,
		Font = Enum.Font.GothamBlack,
		Parent = card,
	}, { corner(10) })
	local btnGradient = create("UIGradient", { Rotation = 90, Parent = btn })
	local btnStroke = create("UIStroke", {
		Color = COLORS.Gold,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = btn,
	})

	local c = {
		Def = def,
		Card = card,
		CardStroke = cardStroke,
		Fill = fill,
		Progress = progressLbl,
		Bonus = bonusLbl,
		Button = btn,
		ButtonGradient = btnGradient,
		ButtonStroke = btnStroke,
		Enabled = false,
		Level = 0,
	}
	cards[def.Stat] = c
	return c
end

for i, def in ipairs(BRANCHES) do
	makeCard(def, i)
end

---------------------------------------------------------------------
-- СОСТОЯНИЕ / ОБНОВЛЕНИЕ
---------------------------------------------------------------------
local isOpen = false
local pending = false
local pulseTweens = {}

local function setButtonStyle(c, mode)
	local b = c.Button
	if mode == "active" then
		b.Text = "+"
		b.TextSize = 36
		b.TextColor3 = COLORS.GoldLight
		c.ButtonGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLORS.RubyLight),
			ColorSequenceKeypoint.new(0.5, COLORS.Ruby),
			ColorSequenceKeypoint.new(1, COLORS.RubyDark),
		})
		c.ButtonStroke.Color = COLORS.Gold
		c.ButtonStroke.Transparency = 0
	elseif mode == "max" then
		b.Text = "МАКСИМУМ"
		b.TextSize = 13
		b.TextColor3 = COLORS.GoldLight
		c.ButtonGradient.Color = ColorSequence.new(COLORS.GoldDark, COLORS.EmbossDark)
		c.ButtonStroke.Color = COLORS.GoldLight
		c.ButtonStroke.Transparency = 0.2
	else -- нет очков
		b.Text = "+"
		b.TextSize = 36
		b.TextColor3 = COLORS.Disabled
		c.ButtonGradient.Color = ColorSequence.new(COLORS.CardHi, COLORS.Obsidian)
		c.ButtonStroke.Color = COLORS.Disabled
		c.ButtonStroke.Transparency = 0.3
	end
end

local function stopPulse()
	for _, tw in ipairs(pulseTweens) do
		tw:Cancel()
	end
	table.clear(pulseTweens)
	pointsGlow.Thickness = 0
	pointsGlow.Transparency = 1
	pointsLabel.TextColor3 = COLORS.GoldLight
end

local function startPulse()
	if #pulseTweens > 0 then return end
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	pointsGlow.Thickness = 0.5
	pointsGlow.Transparency = 0.9
	table.insert(pulseTweens, TweenService:Create(pointsGlow, info, { Thickness = 3, Transparency = 0.35 }))
	table.insert(pulseTweens, TweenService:Create(pointsLabel, info, { TextColor3 = Color3.fromRGB(255, 245, 210) }))
	for _, tw in ipairs(pulseTweens) do
		tw:Play()
	end
end

local function refresh(animate)
	local points = tonumber(player:GetAttribute("StatPoints")) or 0
	pointsLabel.Text = "ОЧКИ ТАЛАНТОВ: " .. points

	hudDot.Visible = points > 0
	hudDot.Text = points > 99 and "99+" or tostring(points)

	if points > 0 and isOpen then
		startPulse()
	else
		stopPulse()
	end

	for _, c in pairs(cards) do
		local def = c.Def
		local lvl = math.clamp(tonumber(player:GetAttribute(def.Attr)) or 0, 0, def.Max)
		local frac = lvl / def.Max
		c.Level = lvl

		c.Progress.Text = string.format("%d / %d", lvl, def.Max)
		c.Bonus.Text = def.Bonus(lvl)
		if animate then
			TweenService:Create(c.Fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(frac, 1),
			}):Play()
		else
			c.Fill.Size = UDim2.fromScale(frac, 1)
		end

		if lvl >= def.Max then
			c.Enabled = false
			setButtonStyle(c, "max")
			c.CardStroke.Color = COLORS.Gold
		elseif points > 0 then
			c.Enabled = true
			setButtonStyle(c, "active")
			c.CardStroke.Color = COLORS.GoldDark
		else
			c.Enabled = false
			setButtonStyle(c, "off")
			c.CardStroke.Color = COLORS.GoldDark
		end
	end
end

local function flashCard(c)
	c.Card.BackgroundColor3 = COLORS.RubyDark
	TweenService:Create(c.Card, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = COLORS.Card,
	}):Play()
	c.CardStroke.Color = COLORS.GoldLight
	c.CardStroke.Thickness = 3
	TweenService:Create(c.CardStroke, TweenInfo.new(0.5), { Thickness = 1.4 }):Play()
end

local function tryUpgrade(c)
	playSound(SOUNDS.StoneClick)
	if pending or not c.Enabled then return end
	pending = true

	-- лёгкое «нажатие»
	local b = c.Button
	TweenService:Create(b, TweenInfo.new(0.06), { Size = UDim2.fromOffset(90, 58) }):Play()
	task.delay(0.06, function()
		TweenService:Create(b, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(96, 64),
		}):Play()
	end)

	task.spawn(function()
		local ok, result = pcall(function()
			return upgradeRemote:InvokeServer(c.Def.Stat)
		end)
		pending = false
		if ok and type(result) == "table" and result.ok then
			playSound(SOUNDS.MetalRing)
			flashCard(c)
		elseif not ok then
			warn("[StatsMenu] Ошибка прокачки:", result)
		end
		refresh(true)
	end)
end

for _, c in pairs(cards) do
	c.Button.MouseButton1Click:Connect(function()
		tryUpgrade(c)
	end)
	c.Button.MouseEnter:Connect(function()
		if c.Enabled then
			TweenService:Create(c.ButtonStroke, TweenInfo.new(0.12), { Thickness = 3 }):Play()
		end
	end)
	c.Button.MouseLeave:Connect(function()
		TweenService:Create(c.ButtonStroke, TweenInfo.new(0.12), { Thickness = 2 }):Play()
	end)
end

---------------------------------------------------------------------
-- ОТКРЫТИЕ / ЗАКРЫТИЕ
---------------------------------------------------------------------
local shimmerTween
local function setShimmer(on)
	if shimmerTween then
		shimmerTween:Cancel()
		shimmerTween = nil
	end
	if on and frameGradient then
		frameGradient.Rotation = 0
		shimmerTween = TweenService:Create(frameGradient, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
			Rotation = 360,
		})
		shimmerTween:Play()
	end
end

local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	uiScale.Scale = math.clamp(math.min(vp.X / 660, vp.Y / 580), 0.55, 1.25)
end

local function toggleMenu(state)
	if state == nil then state = not isOpen end
	if state == isOpen then return end
	isOpen = state
	_G.IsTalentsOpen = state

	if state then
		updateScale()
		refresh(false)
		dim.Visible = true
		panel.Visible = true
		dim.BackgroundTransparency = 1
		panel.Position = UDim2.fromScale(0.5, 0.53)
		TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.5),
		}):Play()
		setShimmer(true)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		panel.Visible = false
		dim.Visible = false
		setShimmer(false)
		stopPulse()
		if not _G.IsInventoryOpen and not _G.IsSettingsOpen and not _G.IsSkinMenuOpen and not _G.IsCardChoosing
			and not _G.IsShopOpen and not _G.IsHatShopOpen and not _G.IsStatsOpen then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
	end
end
_G.ToggleTalents = toggleMenu

hudBtn.MouseButton1Click:Connect(function()
	playSound(SOUNDS.StoneClick)
	toggleMenu()
end)
closeBtn.MouseButton1Click:Connect(function()
	playSound(SOUNDS.StoneClick)
	toggleMenu(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.U then
		toggleMenu()
	elseif input.KeyCode == Enum.KeyCode.Escape and isOpen then
		toggleMenu(false)
	end
end)

-- Пока меню открыто — держим курсор свободным (другие скрипты могут его залочить)
game:GetService("RunService").RenderStepped:Connect(function()
	if isOpen and UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end)

player.AttributeChanged:Connect(function(name)
	if name == "StatPoints" or name == "StatHealthLvl" or name == "StatRollLvl" or name == "StatDefenseLvl" then
		refresh(isOpen)
	end
end)

refresh(false)
