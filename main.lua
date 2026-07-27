--[[
	NovaUI
	A lightweight, dashboard-style UI library for Roblox.

	This is a standalone ModuleScript. Put it in ReplicatedStorage (or anywhere
	a LocalScript can reach it) and `require()` it — see example.lua for usage.

	Different from Fluent on purpose: there is no "add elements straight to a
	tab" API. A Tab only ever holds Sections (Tab:AddSection), and every
	element (toggle/slider/dropdown/colorpicker/keybind/input/button/
	paragraph) is added to a Section as a row:

		local Section = Tab:AddSection({ Title = "Display", Column = 1 })
		Section:AddToggle("MyToggle", { Title = "Enable overlay", Default = true })
		Section:AddSlider("Scale", { Title = "Scale", Min = 50, Max = 200, Suffix = "%" })

	Icons: no external module dependency — give NovaUI a plain asset-id table
	instead, via `NovaUI:SetIcons(table)` or CreateWindow's `Icons = table`
	option (or drop a ModuleScript named "NovaIcons"/"Icons" under
	ReplicatedStorage returning the same shape and it's found automatically):

		{
			["48px"]  = { rewind = {16898613699, {48, 48}, {563, 967}}, ... },
			["256px"] = { rewind = {16898613699, {256, 256}, {0, 0}}, ... },
		}

	i.e. size-bucket key -> icon name -> {assetId, {pxWidth, pxHeight}, {offsetX, offsetY}}.
	assetId is one shared sprite-sheet image per bucket; {pxWidth, pxHeight}
	is this icon's size within that sheet, and {offsetX, offsetY} is where
	it sits inside the sheet (rendered via ImageRectOffset/ImageRectSize).
	The offset is optional — omit it (or use {0,0}) if assetId is instead a
	one-icon-per-decal id rather than a packed sheet. Any number of size
	buckets works; GetIcon picks the smallest bucket that's still big enough
	for the requested render size and scales it down
	(preserving aspect ratio), so keep at least one reasonably large bucket
	per icon. Tab icons, chrome icons (search, folder, chevron, minimize,
	fullscreen, close, notification close), and the bottom-of-sidebar
	buttons (`config.SidebarButtons` / `Window:AddSidebarButton`) all pull
	from this same table via the icon name string. Without a table set,
	everything still works — icons just fall back to plain text glyphs.

	Popups (dropdown lists, colorpickers, the top config selector) render in
	a dedicated top-level overlay layer, so they're never occluded by other
	rows/sections and close automatically on an outside click.

	Motion is intentionally restrained/modern: short fades + small (4-8px)
	slides, no overshoot/bounce easing.

	Theme: dark background with a blue accent (see Themes.Dark below).
--]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

--=============================================================================
-- THEME
--=============================================================================

local Themes = {
	Dark = {
		Accent = Color3.fromRGB(70, 130, 255),
		AccentHover = Color3.fromRGB(95, 150, 255),
		Background = Color3.fromRGB(15, 15, 19),
		SecondaryBackground = Color3.fromRGB(19, 19, 24),
		ElementBackground = Color3.fromRGB(26, 26, 32),
		ElementBackgroundHover = Color3.fromRGB(34, 34, 41),
		PopupBackground = Color3.fromRGB(30, 30, 37),
		Text = Color3.fromRGB(235, 236, 240),
		SubText = Color3.fromRGB(140, 142, 155),
		Border = Color3.fromRGB(40, 40, 48),
		Divider = Color3.fromRGB(36, 36, 43),
	},
}

--=============================================================================
-- UTILITIES
--=============================================================================

local function New(className, props, children)
	local inst = Instance.new(className)
	for prop, value in pairs(props or {}) do
		if prop ~= "Parent" then
			inst[prop] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function Round(inst, radius)
	New("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = inst })
	return inst
end

local function Stroke(inst, color, thickness, transparency)
	local stroke = New("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
	return stroke
end

local function Pad(inst, l, t, r, b)
	New("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0),
		PaddingTop = UDim.new(0, t or l or 0),
		PaddingRight = UDim.new(0, r or l or 0),
		PaddingBottom = UDim.new(0, b or t or l or 0),
		Parent = inst,
	})
	return inst
end

-- Modern, restrained easing everywhere: short duration, no overshoot/bounce.
local EASE = Enum.EasingStyle.Quad
local EASE_SOFT = Enum.EasingStyle.Quint

local function Tween(inst, props, time, style, dir)
	local info = TweenInfo.new(time or 0.15, style or EASE, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(inst, info, props)
	tw:Play()
	return tw
end

-- IMPORTANT: the movement/end tracking below is on the GLOBAL
-- UserInputService, not on `handle`. A GuiObject's own InputChanged only
-- fires while the cursor is still over that object's bounds — during an
-- actual drag the cursor leaves the (usually small) handle almost
-- immediately, which silently stops the drag. Only InputBegan (to detect
-- the press starting on the handle) needs to be scoped to `handle`.
local function MakeDraggable(frame, handle)
	handle = handle or frame
	local dragging = false
	local dragStart, startPos

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- Roblox's native UIShadow instance (a UI modifier, like UICorner/UIStroke —
-- it doesn't participate in UIListLayout and isn't clipped by its own
-- parent's ClipsDescendants), so it can be added directly to any Frame.
local function AddShadow(parent, opts)
	opts = opts or {}
	return New("UIShadow", {
		Color = opts.Color or Color3.new(0, 0, 0),
		Transparency = opts.Transparency or 0.6,
		Offset = UDim2.fromOffset(opts.OffsetX or 0, opts.OffsetY or 6),
		Spread = opts.Spread or UDim2.fromScale(0, 0),
		BlurRadius = UDim.new(0, opts.Blur or 24),
		ZIndex = opts.ZIndex or 0,
		Enabled = opts.Enabled ~= false,
		Parent = parent,
	})
end

-- Small, snappy hover feedback (no bounce) — used on icon buttons.
local function AddHoverScale(button, scaleUp)
	scaleUp = scaleUp or 1.04
	local uiScale = New("UIScale", { Scale = 1, Parent = button })
	button.MouseEnter:Connect(function()
		Tween(uiScale, { Scale = scaleUp }, 0.1)
	end)
	button.MouseLeave:Connect(function()
		Tween(uiScale, { Scale = 1 }, 0.1)
	end)
	button.MouseButton1Down:Connect(function()
		Tween(uiScale, { Scale = scaleUp * 0.95 }, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		Tween(uiScale, { Scale = scaleUp }, 0.06)
	end)
	return uiScale
end

-- Quick fade + tiny scale for popups/dropdown lists when they open. No bounce.
local function PopIn(frame)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = New("UIScale", { Scale = 1, Parent = frame })
	end
	scale.Scale = 0.96
	Tween(scale, { Scale = 1 }, 0.12, EASE)
end

-- Subtle fade + small rise-in for newly created rows/cards. No bounce.
local function FadeSlideIn(inst, delayTime)
	local originalPosition = inst.Position
	local originalTransparency = inst.BackgroundTransparency
	inst.Position = originalPosition + UDim2.new(0, 0, 0, 4)
	inst.BackgroundTransparency = 1
	task.delay(delayTime or 0, function()
		if inst and inst.Parent then
			Tween(inst, { Position = originalPosition, BackgroundTransparency = originalTransparency }, 0.18, EASE_SOFT)
		end
	end)
end

-- Minimal signal/event implementation used by every element (:OnChanged, :OnClick, ...)
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _listeners = {} }, Signal)
end

function Signal:Connect(fn)
	table.insert(self._listeners, fn)
end

function Signal:Fire(...)
	for _, fn in ipairs(self._listeners) do
		task.spawn(fn, ...)
	end
end

local function ScreenParent()
	local ok, playerGui = pcall(function()
		return LocalPlayer:WaitForChild("PlayerGui")
	end)
	return ok and playerGui or nil
end

--=============================================================================
-- LIBRARY ROOT
--=============================================================================

local NovaUI = {}
NovaUI.Version = "2.0.0"
NovaUI.Options = {}
NovaUI.Unloaded = false
NovaUI.Theme = Themes.Dark
NovaUI.Icons = nil

--=============================================================================
-- CONFIG SERIALIZATION (JSON) — Color3 values are stored as a tagged
-- {__type="Color3", R=, G=, B=} table since raw Color3 isn't JSON-safe.
--=============================================================================

local function SerializeValue(value)
	if typeof(value) == "Color3" then
		return { __type = "Color3", R = value.R, G = value.G, B = value.B }
	end
	return value
end

local function DeserializeValue(value)
	if typeof(value) == "table" and value.__type == "Color3" then
		return Color3.new(value.R or 0, value.G or 0, value.B or 0)
	end
	return value
end

--- NovaUI:ExportConfig() -> table mapping every registered option id to its
--- current (JSON-safe) value. Colorpicker values come back as
--- {__type="Color3", R,G,B} rather than a raw Color3.
function NovaUI:ExportConfig()
	local data = {}
	for id, opt in pairs(NovaUI.Options) do
		data[id] = SerializeValue(opt.Value)
	end
	return data
end

--- NovaUI:ExportConfigJSON() -> JSON string of NovaUI:ExportConfig().
function NovaUI:ExportConfigJSON()
	return HttpService:JSONEncode(NovaUI:ExportConfig())
end

--- NovaUI:ApplyConfig(data) — data may be a Lua table (id -> value, as
--- produced by ExportConfig) or a JSON string. Pushes each value into the
--- matching live option via its :SetValue/:SetValueRGB method, so every
--- toggle/slider/dropdown/colorpicker/keybind/input on screen updates.
function NovaUI:ApplyConfig(data)
	if type(data) == "string" then
		local ok, decoded = pcall(function() return HttpService:JSONDecode(data) end)
		if not ok or type(decoded) ~= "table" then return false end
		data = decoded
	end
	if type(data) ~= "table" then return false end

	for id, rawValue in pairs(data) do
		local opt = NovaUI.Options[id]
		if opt then
			local value = DeserializeValue(rawValue)
			if typeof(value) == "Color3" and opt.SetValueRGB then
				opt:SetValueRGB(value)
			elseif opt.SetValue then
				opt:SetValue(value)
			end
		end
	end
	return true
end

--- Provide your own icon asset table (no external module dependency).
--- Each bucket's assetId is one sprite-sheet image shared by every icon in
--- that bucket; {w,h} is the icon's size within the sheet and the optional
--- {x,y} is its top-left offset inside the sheet (ImageRectSize/Offset).
--- Omit {x,y} (or use {0,0}) if assetId is instead a dedicated per-icon
--- decal rather than a sheet.
--- Shape: { ["48px"] = { iconname = {assetId, {pxWidth, pxHeight}, {offsetX, offsetY}}, ... },
---          ["256px"] = { iconname = {assetId, {pxWidth, pxHeight}, {offsetX, offsetY}}, ... } }
--- Any number of size buckets is fine — keys just need a number in them
--- (e.g. "48px", "256", "64x64"). GetIcon picks the smallest bucket that's
--- still >= the requested render size (falling back to the largest bucket
--- available if none is big enough), then scales to fit while preserving
--- each icon's native aspect ratio.
function NovaUI:SetIcons(iconTable)
	NovaUI.Icons = iconTable
end

local function TryFindIcons()
	if NovaUI.Icons then
		return NovaUI.Icons
	end
	local ok, mod = pcall(function()
		local found = ReplicatedStorage:FindFirstChild("NovaIcons") or ReplicatedStorage:FindFirstChild("Icons")
		return found and require(found)
	end)
	if ok and mod then
		NovaUI.Icons = mod
		return mod
	end
	return nil
end

local function PickIconSizeKey(sheet, targetSize)
	local bestKey, bestNum -- smallest bucket that's still >= targetSize
	local largestKey, largestNum -- fallback: largest bucket available
	for key in pairs(sheet) do
		local num = tonumber(tostring(key):match("%d+"))
		if num then
			if num >= targetSize and (not bestNum or num < bestNum) then
				bestNum, bestKey = num, key
			end
			if not largestNum or num > largestNum then
				largestNum, largestKey = num, key
			end
		end
	end
	return bestKey or largestKey
end

-- Returns an ImageLabel for `name` from the icon table, or nil if
-- unavailable/not found — callers should always have a text fallback.
local function GetIcon(name, size, propsOverrides)
	if not name or name == "" then return nil end
	local sheet = TryFindIcons()
	if not sheet then return nil end

	local sizeKey = PickIconSizeKey(sheet, size or 20)
	local bucket = sizeKey and sheet[sizeKey]
	local entry = bucket and bucket[name]
	if not entry then return nil end

	local assetId, dims, offset = entry[1], entry[2], entry[3]
	if not assetId then return nil end
	local nativeW = (dims and dims[1]) or size or 20
	local nativeH = (dims and dims[2]) or size or 20
	local target = size or math.max(nativeW, nativeH)
	local scale = target / math.max(nativeW, nativeH)

	local ok, label = pcall(function()
		local props = {
			Image = "rbxassetid://" .. tostring(assetId),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(math.floor(nativeW * scale + 0.5), math.floor(nativeH * scale + 0.5)),
		}
		-- If the table gives an {x,y} sheet offset, assetId is a shared
		-- sprite sheet — carve out just this icon's sub-rectangle instead of
		-- rendering the whole sheet image.
		if offset then
			props.ImageRectOffset = Vector2.new(offset[1] or 0, offset[2] or 0)
			props.ImageRectSize = Vector2.new(nativeW, nativeH)
		end
		return New("ImageLabel", props)
	end)
	if not ok or not label then return nil end

	if propsOverrides then
		for prop, value in pairs(propsOverrides) do
			label[prop] = value
		end
	end
	return label
end

-- Sets a button's visible content to an icon (from the icon table) when
-- back to a text glyph otherwise. Returns a handle with :SetColor(color).
local function SetButtonIcon(button, iconName, fallbackText, size, color)
	local existing = button:FindFirstChild("__Icon")
	if existing then existing:Destroy() end

	local icon = iconName and GetIcon(iconName, size or 14)
	if icon then
		icon.Name = "__Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.ImageColor3 = color or Color3.new(1, 1, 1)
		icon.Parent = button
		button.Text = ""
	else
		button.Text = fallbackText or ""
		button.TextColor3 = color or Color3.new(1, 1, 1)
	end

	return {
		SetColor = function(c)
			if icon then
				icon.ImageColor3 = c
			else
				button.TextColor3 = c
			end
		end,
	}
end

local NotifHolder -- created lazily, one per Library instance

local function EnsureNotifHolder()
	if NotifHolder and NotifHolder.Parent then
		return NotifHolder
	end

	local gui = New("ScreenGui", {
		Name = "NovaUI_Notifications",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
		Parent = ScreenParent(),
	})

	NotifHolder = New("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.new(0, 300, 1, -32),
		Parent = gui,
	})

	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
		Parent = NotifHolder,
	})

	return NotifHolder
end

--- Fluent:Notify({ Title, Content, SubContent, Duration })
function NovaUI:Notify(config)
	local theme = NovaUI.Theme
	local holder = EnsureNotifHolder()

	-- IMPORTANT: `card` uses AutomaticSize.Y. Never give a direct child of
	-- an AutomaticSize.Y frame a Scale-based Y size (e.g. UDim2.new(0,3,1,0))
	-- — that's a circular size dependency and is what made notifications
	-- balloon to a huge height before. The accent strip's height is instead
	-- driven explicitly from `content`'s resolved AbsoluteSize below.
	local card = New("Frame", {
		BackgroundColor3 = theme.SecondaryBackground,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ClipsDescendants = true,
		LayoutOrder = -os.clock(),
		Parent = holder,
	})
	Round(card, 8)
	Stroke(card, theme.Border, 1)
	local shadow = AddShadow(card, { Transparency = 1, OffsetY = 6, Blur = 18 })

	local content = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	Pad(content, 14, 12, 12, 14)
	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = content,
	})

	local accentBar = New("Frame", {
		BackgroundColor3 = theme.Accent,
		Size = UDim2.new(0, 3, 0, 0),
		Parent = card,
	})
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		accentBar.Size = UDim2.new(0, 3, 0, content.AbsoluteSize.Y)
	end)

	local closeBtn = New("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 18, 0, 18),
		AutoButtonColor = false,
		ZIndex = 2,
		Parent = card,
	})
	SetButtonIcon(closeBtn, "x", "\226\156\149", 11, theme.SubText)

	New("TextLabel", {
		Text = config.Title or "Notification",
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -22, 0, 18),
		LayoutOrder = 1,
		Parent = content,
	})

	if config.Content then
		New("TextLabel", {
			Text = config.Content,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = content,
		})
	end

	if config.SubContent then
		New("TextLabel", {
			Text = config.SubContent,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = theme.SubText,
			TextTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3,
			Parent = content,
		})
	end

	local progressFill
	if config.Duration then
		local progressTrack = New("Frame", {
			BackgroundColor3 = theme.ElementBackgroundHover,
			Size = UDim2.new(1, 0, 0, 3),
			LayoutOrder = 99,
			Parent = content,
		})
		Round(progressTrack, 2)
		progressFill = New("Frame", {
			BackgroundColor3 = theme.Accent,
			Size = UDim2.new(1, 0, 1, 0),
			Parent = progressTrack,
		})
		Round(progressFill, 2)
	end

	local function Dismiss()
		if not (card and card.Parent) then return end
		Tween(card, { Position = UDim2.new(1, 24, 0, 0), BackgroundTransparency = 1 }, 0.16, EASE_SOFT)
		Tween(shadow, { Transparency = 1 }, 0.16)
		task.delay(0.16, function()
			if card then card:Destroy() end
		end)
	end
	closeBtn.MouseButton1Click:Connect(Dismiss)

	card.BackgroundTransparency = 1
	card.Position = UDim2.new(1, 24, 0, 0)
	Tween(card, { Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0 }, 0.2, EASE_SOFT)
	Tween(shadow, { Transparency = 0.55 }, 0.25)

	if config.Duration then
		if progressFill then
			Tween(progressFill, { Size = UDim2.new(0, 0, 1, 0) }, config.Duration, Enum.EasingStyle.Linear)
		end
		task.delay(config.Duration, Dismiss)
	end

	return card
end

--=============================================================================
-- WINDOW
--=============================================================================

function NovaUI:CreateWindow(config)
	config = config or {}
	local theme = NovaUI.Theme
	if config.Theme and Themes[config.Theme] then
		theme = Themes[config.Theme]
		NovaUI.Theme = theme
	end
	if config.Icons then
		NovaUI.Icons = config.Icons
	end

	local size = config.Size or UDim2.fromOffset(600, 480)
	local railWidth = config.TabWidth or 64
	local topBarHeight = 64

	local ScreenGui = New("ScreenGui", {
		Name = "NovaUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
		Parent = ScreenParent(),
	})

	-- Tooltip helper (needs ScreenGui + theme, so it's scoped per-window).
	local function AttachTooltip(button, text)
		local tooltip = New("TextLabel", {
			Text = text,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = theme.Text,
			BackgroundColor3 = theme.ElementBackgroundHover,
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 500,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, 24),
			Parent = ScreenGui,
		})
		Round(tooltip, 5)
		Pad(tooltip, 8, 0, 8, 0)
		button.MouseEnter:Connect(function()
			tooltip.Position = UDim2.fromOffset(button.AbsolutePosition.X + button.AbsoluteSize.X + 8, button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2 - 12)
			tooltip.Visible = true
			tooltip.BackgroundTransparency = 1
			Tween(tooltip, { BackgroundTransparency = 0 }, 0.08)
		end)
		button.MouseLeave:Connect(function()
			tooltip.Visible = false
		end)
		return tooltip
	end

	-- Small reusable icon-button constructor (icon w/ text fallback,
	-- hover tint, hover-scale pop). Used for chrome + sidebar buttons.
	local function MakeIconButton(parent, sizePx, iconName, fallbackText, iconSize)
		local btn = New("TextButton", {
			Text = "",
			BackgroundColor3 = theme.ElementBackground,
			BackgroundTransparency = 1,
			Size = UDim2.new(0, sizePx, 0, sizePx),
			AutoButtonColor = false,
			Parent = parent,
		})
		Round(btn, math.floor(sizePx / 2) - 3)
		local state = { handle = SetButtonIcon(btn, iconName, fallbackText, iconSize or 14, theme.SubText) }
		AddHoverScale(btn, 1.08)
		btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.85 }, 0.1)
			state.handle.SetColor(theme.Text)
		end)
		btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.1)
			state.handle.SetColor(theme.SubText)
		end)
		return {
			Instance = btn,
			SetIcon = function(name, fb)
				state.handle = SetButtonIcon(btn, name, fb, iconSize or 14, theme.SubText)
			end,
			SetColor = function(c)
				state.handle.SetColor(c)
			end,
		}
	end

	-- Main is the frame that gets positioned/dragged/resized directly.
	-- UIShadow is a UI modifier (like UICorner/UIStroke, both also attached
	-- directly below) — it isn't clipped by Main's own ClipsDescendants and
	-- doesn't need a separate un-clipped wrapper frame.
	local Main = New("Frame", {
		Name = "Main",
		BackgroundColor3 = theme.Background,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = size,
		ClipsDescendants = true,
		Parent = ScreenGui,
	})
	Round(Main, 14)
	Stroke(Main, theme.Border, 1)
	local Shadow = AddShadow(Main, { Transparency = 1, OffsetY = 10, Blur = 30 })
	local mainScale = New("UIScale", { Scale = 0.97, Parent = Main })

	-- Opening animation: a restrained fade + tiny scale-up (no bounce).
	do
		local targetAcrylicTransparency = config.Acrylic and 0.06 or 0
		Tween(mainScale, { Scale = 1 }, 0.18, EASE_SOFT)
		Tween(Main, { BackgroundTransparency = targetAcrylicTransparency }, 0.2)
		Tween(Shadow, { Transparency = 0.5 }, 0.25)
	end

	-- Bottom-right resize grip. High ZIndex so it's always grabbable above
	-- whatever's scrolled underneath it; the actual drag wiring happens
	-- further below (it needs the Window table's minimized/fullscreen state).
	local ResizeHandle = New("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -3, 1, -3),
		Size = UDim2.new(0, 18, 0, 18),
		ZIndex = 50,
		Parent = Main,
	})
	do
		local icon = GetIcon("arrow-down-right", 14)
		if icon then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.ImageColor3 = theme.SubText
			icon.ZIndex = 50
			icon.Parent = ResizeHandle
		else
			New("TextLabel", {
				Text = "\226\134\152", -- "↘"
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = theme.SubText,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 50,
				Parent = ResizeHandle,
			})
		end
	end
	AddHoverScale(ResizeHandle, 1.2)

	--=========================================================================
	-- OVERLAY (dropdown lists / colorpickers / config selector render here,
	-- as a ScreenGui-level sibling of Main, so they're always on top and
	-- never occluded by other rows — and they auto-close on outside click)
	--=========================================================================

	local Overlay = New("Frame", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 900,
		Parent = ScreenGui,
	})
	local PopupCatcher = New("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 899,
		Parent = Overlay,
	})

	local currentPopup = nil
	local currentPopupOnClose = nil
	local function ClosePopup()
		if currentPopup then
			currentPopup.Visible = false
			currentPopup = nil
		end
		PopupCatcher.Visible = false
		if currentPopupOnClose then
			local onClose = currentPopupOnClose
			currentPopupOnClose = nil
			onClose()
		end
	end
	PopupCatcher.MouseButton1Click:Connect(ClosePopup)

	--- Opens `popup` (reparented into Overlay) anchored just below
	--- `anchorButton`. opts.Align = "left" (default) or "right" is only a
	--- *preference* — if the preferred side would overflow/underflow the
	--- screen (e.g. a swatch near the left edge with Align="right"), this
	--- automatically falls back to whichever side actually fits, instead of
	--- hard-clamping to the screen edge and stranding the popup far from
	--- the button that opened it.
	--- opts.Gap = pixel gap below the anchor (default 6).
	--- opts.OnClose = fn() called once, when this popup is closed (either
	--- by clicking an option, or by clicking outside it).
	local function OpenPopup(popup, anchorButton, opts)
		opts = opts or {}
		if currentPopup == popup then
			ClosePopup()
			return
		end
		ClosePopup()
		popup.Parent = Overlay
		popup.ZIndex = 901

		local anchorPos = anchorButton.AbsolutePosition
		local anchorSize = anchorButton.AbsoluteSize
		local popupWidth = popup.Size.X.Offset
		local screenSize = Overlay.AbsoluteSize

		local leftAlignedX = anchorPos.X
		local rightAlignedX = anchorPos.X + anchorSize.X - popupWidth
		local leftFits = (leftAlignedX + popupWidth) <= screenSize.X
		local rightFits = rightAlignedX >= 0
		local preferRight = opts.Align == "right"

		local x
		if preferRight and rightFits then
			x = rightAlignedX
		elseif (not preferRight) and leftFits then
			x = leftAlignedX
		elseif rightFits then
			x = rightAlignedX
		elseif leftFits then
			x = leftAlignedX
		else
			x = preferRight and rightAlignedX or leftAlignedX
		end
		x = math.clamp(x, 4, math.max(4, screenSize.X - popupWidth - 4))

		popup.Position = UDim2.fromOffset(x, anchorPos.Y + anchorSize.Y + (opts.Gap or 6))
		popup.Visible = true
		PopIn(popup)
		PopupCatcher.Visible = true

		currentPopup = popup
		currentPopupOnClose = opts.OnClose
	end

	--=========================================================================
	-- SIDEBAR (icon rail, full height)
	--=========================================================================

	local Sidebar = New("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = theme.SecondaryBackground,
		Size = UDim2.new(0, railWidth, 1, 0),
		Parent = Main,
	})
	-- Rounds all 4 corners for simplicity (Roblox has no per-corner radius);
	-- the right two corners are covered by ContentArea sitting flush beside it.
	Round(Sidebar, 14)

	local LogoBox = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		Parent = Sidebar,
	})
	local logoMark = New("Frame", {
		BackgroundColor3 = theme.Accent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 32, 0, 32),
		Parent = LogoBox,
	})
	Round(logoMark, 9)
	New("TextLabel", {
		Text = (config.Title or "N"):sub(1, 1):upper(),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = logoMark,
	})

	local TabRailScroll = New("ScrollingFrame", {
		Name = "TabRail",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 56),
		Size = UDim2.new(1, 0, 1, -132),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 0,
		BorderSizePixel = 0,
		Parent = Sidebar,
	})
	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = TabRailScroll,
	})

	-- Populated below, after Window:AddSidebarButton exists — either with
	-- config.SidebarButtons (fully customizable icon buttons) or a
	-- sensible default (collapse + profile).
	local SidebarFooter = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 76),
		Parent = Sidebar,
	})
	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = SidebarFooter,
	})

	--=========================================================================
	-- CONTENT AREA (search/selector bar + tab pages)
	--=========================================================================

	local ContentArea = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, railWidth, 0, 0),
		Size = UDim2.new(1, -railWidth, 1, 0),
		Parent = Main,
	})

	local ContentTopBar = New("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, topBarHeight),
		Parent = ContentArea,
	})
	Pad(ContentTopBar, 20, 14, 20, 14)

	-- Only the sidebar logo is a drag handle. Deliberately NOT any part of
	-- the content top bar — Roblox's InputBegan/InputChanged fire on every
	-- GuiObject under the cursor regardless of Z-order, so an invisible
	-- "drag background" behind the search box/selector/chrome buttons would
	-- still fight with their clicks (this is why minimize/fullscreen/search
	-- could misbehave before).
	local TopBarRow = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = ContentTopBar,
	})
	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = TopBarRow,
	})

	-- Search pill (narrower than before — the save-config button added
	-- next to the selector needs the room in the top bar).
	local SearchPill = New("Frame", {
		BackgroundColor3 = theme.ElementBackground,
		Size = UDim2.new(0, 170, 1, 0),
		LayoutOrder = 1,
		Parent = TopBarRow,
	})
	Round(SearchPill, 8)
	Pad(SearchPill, 10, 0, 10, 0)
	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = SearchPill,
	})
	do
		local icon = GetIcon("search", 14)
		if icon then
			icon.LayoutOrder = 1
			icon.ImageColor3 = theme.SubText
			icon.Parent = SearchPill
		else
			New("TextLabel", {
				Text = "\226\140\149",
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = theme.SubText,
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 14, 1, 0),
				LayoutOrder = 1,
				Parent = SearchPill,
			})
		end
	end
	local SearchBox = New("TextBox", {
		Text = "",
		PlaceholderText = "Search",
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = theme.Text,
		PlaceholderColor3 = theme.SubText,
		ClearTextOnFocus = false,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -20, 1, 0),
		LayoutOrder = 2,
		ZIndex = 2,
		Parent = SearchPill,
	})

	-- Config selector pill (folder icon + label + chevron)
	local SelectorPill = New("TextButton", {
		Text = "",
		BackgroundColor3 = theme.ElementBackground,
		Size = UDim2.new(0, 176, 1, 0),
		AutoButtonColor = false,
		LayoutOrder = 2,
		ZIndex = 2,
		Parent = TopBarRow,
	})
	Round(SelectorPill, 8)
	Pad(SelectorPill, 10, 0, 10, 0)
	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = SelectorPill,
	})
	do
		local icon = GetIcon("file-cog", 14)
		if icon then
			icon.LayoutOrder = 1
			icon.ImageColor3 = theme.SubText
			icon.Parent = SelectorPill
		else
			New("TextLabel", {
				Text = "\226\150\161",
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextColor3 = theme.SubText,
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 14, 1, 0),
				LayoutOrder = 1,
				Parent = SelectorPill,
			})
		end
	end
	local SelectorLabel = New("TextLabel", {
		Text = config.SubTitle or "New Config 1",
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 1, 0),
		LayoutOrder = 2,
		Parent = SelectorPill,
	})
	do
		local icon = GetIcon("chevron-down", 12)
		if icon then
			icon.LayoutOrder = 3
			icon.ImageColor3 = theme.SubText
			icon.Parent = SelectorPill
		else
			New("TextLabel", {
				Text = "\226\150\190",
				Font = Enum.Font.Gotham,
				TextSize = 10,
				TextColor3 = theme.SubText,
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 12, 1, 0),
				LayoutOrder = 3,
				Parent = SelectorPill,
			})
		end
	end

	-- Fixed-width, opaque popup list (rendered in Overlay, never occluded).
	local SelectorList = New("Frame", {
		BackgroundColor3 = theme.PopupBackground,
		BackgroundTransparency = 0,
		Visible = false,
		Size = UDim2.new(0, 176, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = Overlay,
	})
	Round(SelectorList, 8)
	Stroke(SelectorList, theme.Border, 1)
	AddShadow(SelectorList, { Transparency = 0.45, OffsetY = 6, Blur = 16 })
	Pad(SelectorList, 4)
	New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = SelectorList })

	-- Save-config button, right next to the selector pill. Fires
	-- Window.ConfigSelector:OnSave(fn) — hook up your own SaveManager-style
	-- persistence logic there.
	local SaveConfigBtn = New("TextButton", {
		Text = "",
		BackgroundColor3 = theme.ElementBackground,
		Size = UDim2.new(0, 36, 1, 0),
		AutoButtonColor = false,
		LayoutOrder = 3,
		ZIndex = 2,
		Parent = TopBarRow,
	})
	Round(SaveConfigBtn, 8)
	local saveIconHandle = SetButtonIcon(SaveConfigBtn, "save", "\226\134\147", 14, theme.SubText)
	AddHoverScale(SaveConfigBtn, 1.06)
	SaveConfigBtn.MouseEnter:Connect(function()
		Tween(SaveConfigBtn, { BackgroundColor3 = theme.ElementBackgroundHover }, 0.1)
		saveIconHandle.SetColor(theme.Text)
	end)
	SaveConfigBtn.MouseLeave:Connect(function()
		Tween(SaveConfigBtn, { BackgroundColor3 = theme.ElementBackground }, 0.1)
		saveIconHandle.SetColor(theme.SubText)
	end)
	AttachTooltip(SaveConfigBtn, "Save Config")

	-- Flexible spacer — eats whatever room is left in the top bar so
	-- ChromeRow below always ends up flush against the right edge instead
	-- of just trailing whatever's to its left. It's also a second drag
	-- handle (besides the sidebar logo): a plain background area with
	-- nothing interactive on it, so dragging from anywhere in that gap
	-- doesn't fight any button/textbox clicks, while giving a much bigger
	-- grab area than the small logo alone.
	local TopBarSpacer = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 4,
		Parent = TopBarRow,
	})
	New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = TopBarSpacer })

	-- Window chrome (minimize/fullscreen/close) — small, flush to the right
	-- edge of the top bar (TopBarSpacer above pushes it there).
	-- All three render as real icons via MakeIconButton, falling back
	-- to text glyphs automatically if no icon provider is hooked up.
	local ChromeRow = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 82, 1, 0),
		LayoutOrder = 5,
		ZIndex = 2,
		Parent = TopBarRow,
	})
	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		Parent = ChromeRow,
	})

	local MinimizeBtn = MakeIconButton(ChromeRow, 24, "minimize-2", "\226\128\148", 13)
	MinimizeBtn.Instance.LayoutOrder = 1
	AttachTooltip(MinimizeBtn.Instance, "Minimize")

	local FullscreenBtn = MakeIconButton(ChromeRow, 24, "expand", "\226\150\162", 13)
	FullscreenBtn.Instance.LayoutOrder = 2
	AttachTooltip(FullscreenBtn.Instance, "Fullscreen")

	local CloseBtn = MakeIconButton(ChromeRow, 24, "x", "\226\156\149", 13)
	CloseBtn.Instance.LayoutOrder = 3
	AttachTooltip(CloseBtn.Instance, "Close")
	CloseBtn.Instance.MouseEnter:Connect(function()
		CloseBtn.SetColor(Color3.fromRGB(255, 100, 100))
	end)

	MakeDraggable(Main, LogoBox)
	MakeDraggable(Main, TopBarSpacer)

	local PagesContainer = New("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, topBarHeight),
		Size = UDim2.new(1, 0, 1, -topBarHeight),
		Parent = ContentArea,
	})

	--=========================================================================
	-- WINDOW OBJECT
	--=========================================================================

	local Window = {}
	Window._tabs = {}
	Window._gui = ScreenGui
	Window._main = Main
	Window._minimized = false
	Window._fullscreen = false
	Window._fullSize = size
	Window._viewportConn = nil
	Window._cameraConn = nil
	Window._activeTabIndex = 1
	Window._searchRows = {} -- { {Instance, TitleLower, TabIndex}, ... }
	Window._searchText = ""

	CloseBtn.Instance.MouseButton1Click:Connect(function()
		Window:Destroy()
	end)

	MinimizeBtn.Instance.MouseButton1Click:Connect(function()
		Window:ToggleMinimize()
	end)

	FullscreenBtn.Instance.MouseButton1Click:Connect(function()
		Window:ToggleFullscreen()
	end)

	-- Resizes Main to `newSize` while keeping its current ON-SCREEN top-left
	-- corner fixed, instead of its center (which is what plain AnchorPoint
	-- (0.5,0.5) resizing does by default). Minimize only changes Height —
	-- anchoring by center means restoring after you'd dragged the minimized
	-- bar up near the top of the screen grows the window mostly upward,
	-- pushing it (and its only drag handles) off the top of the screen
	-- entirely. Anchoring by top-left instead means it only ever grows
	-- downward/rightward from wherever it currently is, so it can't strand
	-- itself off-screen like that.
	local function ResizeKeepingTopLeft(newSize, duration, style)
		local screenSize = ScreenGui.AbsoluteSize
		local topLeft = Main.AbsolutePosition
		local newWidth = newSize.X.Scale * screenSize.X + newSize.X.Offset
		local newHeight = newSize.Y.Scale * screenSize.Y + newSize.Y.Offset
		local newCenterX = topLeft.X + newWidth / 2
		local newCenterY = topLeft.Y + newHeight / 2
		local newPosition = UDim2.new(0.5, newCenterX - screenSize.X * 0.5, 0.5, newCenterY - screenSize.Y * 0.5)
		if duration then
			Tween(Main, { Size = newSize, Position = newPosition }, duration, style)
		else
			Main.Size = newSize
			Main.Position = newPosition
		end
	end

	--- Minimizing only collapses the sidebar + page content — the top bar
	--- (search, config selector, save button, minimize/fullscreen/close) stays
	--- visible and usable the whole time, it just fills the collapsed window.
	function Window:ToggleMinimize()
		self._minimized = not self._minimized
		if self._minimized then
			self._preMinimizeSize = Main.Size
			ResizeKeepingTopLeft(UDim2.new(0, self._fullSize.X.Offset, 0, topBarHeight), 0.18, EASE_SOFT)
			Sidebar.Visible = false
			PagesContainer.Visible = false
			ResizeHandle.Visible = false
			Tween(ContentArea, { Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 1, 0) }, 0.18, EASE_SOFT)
		else
			Sidebar.Visible = true
			PagesContainer.Visible = true
			ResizeHandle.Visible = true
			Tween(ContentArea, { Position = UDim2.new(0, railWidth, 0, 0), Size = UDim2.new(1, -railWidth, 1, 0) }, 0.18, EASE_SOFT)
			ResizeKeepingTopLeft(self._preMinimizeSize or self._fullSize, 0.18, EASE_SOFT)
		end
	end

	-- Applies the current camera viewport to Main while fullscreen is on.
	-- Also re-centers Main every time (Position keeps its dragged offset
	-- otherwise, from AnchorPoint(0.5,0.5) + that offset — so if you'd
	-- dragged the window off-center before going fullscreen, it would grow
	-- around that off-center point instead of actually covering the screen).
	-- `animate` tweens the very first application; live updates afterward
	-- (screen/resolution changes while already fullscreen) snap instantly so
	-- they can't fight an in-flight tween.
	local function ApplyViewportSize(window, animate)
		local camera = Workspace.CurrentCamera
		local viewport = (camera and camera.ViewportSize) or Vector2.new(1280, 720)
		local targetSize = UDim2.fromOffset(viewport.X - 32, viewport.Y - 32)
		local targetPosition = UDim2.new(0.5, 0, 0.5, 0)
		if animate then
			Tween(Main, { Size = targetSize, Position = targetPosition }, 0.2, EASE_SOFT)
		else
			Main.Size = targetSize
			Main.Position = targetPosition
		end
	end

	local function DisconnectFullscreenTracking(window)
		if window._viewportConn then
			window._viewportConn:Disconnect()
			window._viewportConn = nil
		end
		if window._cameraConn then
			window._cameraConn:Disconnect()
			window._cameraConn = nil
		end
	end

	--- Toggles the window to fill (most of) the screen and back, tracking the
	--- camera's ViewportSize live so Main is resized whenever the game
	--- window/resolution changes while fullscreen is active. Swaps the chrome
	--- icon between "expand" and "shrink".
	function Window:ToggleFullscreen()
		self._fullscreen = not self._fullscreen
		if self._fullscreen then
			self._savedSize = Main.Size
			self._savedPosition = Main.Position
			ResizeHandle.Visible = false
			ApplyViewportSize(self, true)

			local function HookCamera(camera)
				if not camera then return end
				self._viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					ApplyViewportSize(self, false)
				end)
			end
			HookCamera(Workspace.CurrentCamera)
			self._cameraConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
				if self._viewportConn then
					self._viewportConn:Disconnect()
					self._viewportConn = nil
				end
				HookCamera(Workspace.CurrentCamera)
				ApplyViewportSize(self, false)
			end)

			FullscreenBtn.SetIcon("shrink", "\226\150\163")
		else
			DisconnectFullscreenTracking(self)
			ResizeHandle.Visible = not self._minimized
			Tween(Main, {
				Size = self._savedSize or self._fullSize,
				Position = self._savedPosition or UDim2.new(0.5, 0, 0.5, 0),
			}, 0.2, EASE_SOFT)
			FullscreenBtn.SetIcon("expand", "\226\150\162")
		end
	end

	-- Drag-to-resize from the bottom-right corner grip. Disabled while
	-- minimized/fullscreen since Main's size is programmatically driven
	-- then; resizing updates Window._fullSize so minimize/restore and
	-- exiting fullscreen both snap back to whatever size you last set by
	-- hand rather than the original CreateWindow size.
	do
		local MIN_WIDTH = math.max(360, railWidth + 220)
		local MIN_HEIGHT = math.max(280, topBarHeight + 160)
		local resizing = false
		local resizeStart, startSize

		ResizeHandle.InputBegan:Connect(function(input)
			if Window._minimized or Window._fullscreen then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				resizing = true
				resizeStart = input.Position
				startSize = Main.Size
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - resizeStart
				local newWidth = math.max(MIN_WIDTH, startSize.X.Offset + delta.X)
				local newHeight = math.max(MIN_HEIGHT, startSize.Y.Offset + delta.Y)
				local newSize = UDim2.new(startSize.X.Scale, newWidth, startSize.Y.Scale, newHeight)
				Main.Size = newSize
				Window._fullSize = newSize
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				resizing = false
			end
		end)
	end

	if config.MinimizeKey then
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.KeyCode == config.MinimizeKey then
				Window:ToggleMinimize()
			end
		end)
	end

	function Window:Destroy()
		ClosePopup()
		DisconnectFullscreenTracking(self)
		ScreenGui:Destroy()
	end

	--- Window:AddSidebarButton({ Icon, FallbackText, Tooltip, Callback, Order })
	--- Appends a fully customizable icon button to the bottom of the
	--- sidebar rail. Pass `config.SidebarButtons` (an array of these same
	--- tables) to CreateWindow to replace the default set entirely.
	function Window:AddSidebarButton(cfg)
		cfg = cfg or {}
		local btnHandle = MakeIconButton(SidebarFooter, 32, cfg.Icon, cfg.FallbackText or "\226\128\162", 15)
		btnHandle.Instance.LayoutOrder = cfg.Order or (#SidebarFooter:GetChildren())
		if cfg.Tooltip then
			AttachTooltip(btnHandle.Instance, cfg.Tooltip)
		end
		if cfg.Callback then
			btnHandle.Instance.MouseButton1Click:Connect(cfg.Callback)
		end
		return btnHandle
	end

	if config.SidebarButtons then
		for _, btnCfg in ipairs(config.SidebarButtons) do
			Window:AddSidebarButton(btnCfg)
		end
	else
		Window:AddSidebarButton({
			Icon = "chevron-down",
			FallbackText = "\226\140\132",
			Tooltip = "Collapse",
			Callback = function() Window:ToggleMinimize() end,
		})
		Window:AddSidebarButton({
			Icon = "user",
			FallbackText = "\226\128\162",
			Tooltip = "Profile",
		})
	end

	local function ApplySearchFilter()
		local query = Window._searchText:lower()
		for _, entry in ipairs(Window._searchRows) do
			if entry.TabIndex == Window._activeTabIndex then
				entry.Instance.Visible = (query == "") or entry.TitleLower:find(query, 1, true) ~= nil
			end
		end
	end

	SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
		Window._searchText = SearchBox.Text
		ApplySearchFilter()
	end)

	--- Window:AddConfig(name) — registers a name in the top config selector.
	--- Window.ConfigSelector:OnChanged(fn) fires with the selected name.
	--- Window.ConfigSelector:OnSave(fn) fires with (name, jsonString) when the
	--- save-config button is clicked — jsonString is every registered
	--- option's current value, JSON-encoded (Colorpicker values included).
	--- Hook up your own persistence (e.g. writeFile) inside that callback.
	local ConfigSelector = { Value = SelectorLabel.Text, Changed = Signal.new(), Save = Signal.new(), _options = {}, _buttons = {} }
	function ConfigSelector:OnChanged(fn) ConfigSelector.Changed:Connect(fn) end
	function ConfigSelector:OnSave(fn) ConfigSelector.Save:Connect(fn) end
	function ConfigSelector:SetValue(name)
		ConfigSelector.Value = name
		SelectorLabel.Text = name
		ConfigSelector.Changed:Fire(name)
	end

	local function CreateOptionButton(name, layoutOrder)
		local btn = New("TextButton", {
			Text = name,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = theme.Accent,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = layoutOrder,
			Parent = SelectorList,
		})
		Round(btn, 4)
		Pad(btn, 8, 0, 8, 0)
		btn.MouseEnter:Connect(function() Tween(btn, { BackgroundTransparency = 0.85 }, 0.08) end)
		btn.MouseLeave:Connect(function() Tween(btn, { BackgroundTransparency = 1 }, 0.08) end)
		btn.MouseButton1Click:Connect(function()
			ConfigSelector:SetValue(name)
			ClosePopup()
		end)
		return btn
	end

	function ConfigSelector:SetOptions(list)
		for _, btn in pairs(ConfigSelector._buttons) do btn:Destroy() end
		ConfigSelector._buttons = {}
		ConfigSelector._options = {}
		for i, name in ipairs(list) do
			table.insert(ConfigSelector._options, name)
			ConfigSelector._buttons[name] = CreateOptionButton(name, i)
		end
	end

	--- ConfigSelector:AddOption(name) — appends one entry to the dropdown
	--- without rebuilding the whole list (keeps existing entries/order).
	function ConfigSelector:AddOption(name)
		if ConfigSelector._buttons[name] then return end
		table.insert(ConfigSelector._options, name)
		ConfigSelector._buttons[name] = CreateOptionButton(name, #ConfigSelector._options)
	end

	--- ConfigSelector:RemoveOption(name) — removes one entry from the dropdown.
	function ConfigSelector:RemoveOption(name)
		local btn = ConfigSelector._buttons[name]
		if not btn then return end
		btn:Destroy()
		ConfigSelector._buttons[name] = nil
		for i, n in ipairs(ConfigSelector._options) do
			if n == name then
				table.remove(ConfigSelector._options, i)
				break
			end
		end
	end

	SelectorPill.MouseButton1Click:Connect(function()
		OpenPopup(SelectorList, SelectorPill, { Align = "left" })
	end)
	SaveConfigBtn.MouseButton1Click:Connect(function()
		ConfigSelector.Save:Fire(ConfigSelector.Value, NovaUI:ExportConfigJSON())
	end)
	Window.ConfigSelector = ConfigSelector
	Window.Search = { Box = SearchBox }

	--- Window:LoadConfig(data) — data is a JSON string (or plain table) of
	--- id -> value pairs, as produced by NovaUI:ExportConfigJSON()/ExportConfig().
	--- Applies each value to the matching live section item. Your own script
	--- decides how the JSON gets here (read from file, DataStore, etc.) — the
	--- library only handles turning it back into on-screen state.
	function Window:LoadConfig(data)
		return NovaUI:ApplyConfig(data)
	end

	function Window:SelectTab(index)
		local tab = self._tabs[index]
		if not tab then return end
		ClosePopup()
		local previousIndex = self._activeTabIndex
		self._activeTabIndex = index
		for i, t in ipairs(self._tabs) do
			local active = (i == index)
			if active then
				t._page.Visible = true
				t._page.Position = UDim2.new(0, (i > previousIndex) and 8 or -8, 0, 0)
				Tween(t._page, { Position = UDim2.new(0, 0, 0, 0) }, 0.14, EASE)
			elseif i ~= index then
				t._page.Visible = false
			end
			Tween(t._button, { BackgroundTransparency = active and 0.85 or 1 }, 0.1)
			if t._icon then
				Tween(t._icon, { ImageColor3 = active and theme.Accent or theme.SubText }, 0.1)
			end
			if t._fallbackLabel then
				t._fallbackLabel.TextColor3 = active and theme.Accent or theme.SubText
			end
		end
		ApplySearchFilter()
	end

	--- Window:Dialog({ Title, Content, Buttons = {{Title, Callback}, ...} })
	function Window:Dialog(cfg)
		local overlay = New("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 50,
			Parent = Main,
		})
		Tween(overlay, { BackgroundTransparency = 0.4 }, 0.15)

		local box = New("Frame", {
			BackgroundColor3 = theme.SecondaryBackground,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 300, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 51,
			Parent = overlay,
		})
		Round(box, 8)
		Stroke(box, theme.Border, 1)
		Pad(box, 16)
		local boxScale = New("UIScale", { Scale = 0.96, Parent = box })
		Tween(boxScale, { Scale = 1 }, 0.15, EASE_SOFT)

		New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = box })

		New("TextLabel", {
			Text = cfg.Title or "Dialog",
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			TextColor3 = theme.Text,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 20),
			ZIndex = 51,
			LayoutOrder = 1,
			Parent = box,
		})

		if cfg.Content then
			New("TextLabel", {
				Text = cfg.Content,
				Font = Enum.Font.Gotham,
				TextSize = 13,
				TextColor3 = theme.SubText,
				TextWrapped = true,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				ZIndex = 51,
				LayoutOrder = 2,
				Parent = box,
			})
		end

		local btnRow = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 32),
			ZIndex = 51,
			LayoutOrder = 3,
			Parent = box,
		})
		New("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
			Parent = btnRow,
		})

		for _, btnCfg in ipairs(cfg.Buttons or {}) do
			local btn = New("TextButton", {
				Text = btnCfg.Title,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = theme.Text,
				BackgroundColor3 = theme.ElementBackground,
				AutoButtonColor = false,
				Size = UDim2.new(0, 90, 1, 0),
				ZIndex = 51,
				Parent = btnRow,
			})
			Round(btn, 6)
			AddHoverScale(btn, 1.05)
			btn.MouseEnter:Connect(function()
				Tween(btn, { BackgroundColor3 = theme.ElementBackgroundHover }, 0.1)
			end)
			btn.MouseLeave:Connect(function()
				Tween(btn, { BackgroundColor3 = theme.ElementBackground }, 0.1)
			end)
			btn.MouseButton1Click:Connect(function()
				Tween(overlay, { BackgroundTransparency = 1 }, 0.12)
				Tween(boxScale, { Scale = 0.96 }, 0.12)
				Tween(box, { BackgroundTransparency = 1 }, 0.1)
				task.delay(0.12, function()
					overlay:Destroy()
				end)
				if btnCfg.Callback then btnCfg.Callback() end
			end)
		end
	end

	--=========================================================================
	-- TAB (only holds Sections — see Tab:AddSection below)
	--=========================================================================

	function Window:AddTab(tabConfig)
		tabConfig = tabConfig or {}
		local tabIndex = #self._tabs + 1

		local button = New("TextButton", {
			Text = "",
			BackgroundColor3 = theme.Accent,
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 40, 0, 40),
			AutoButtonColor = false,
			LayoutOrder = tabIndex,
			Parent = TabRailScroll,
		})
		Round(button, 10)

		local iconImage = tabConfig.Icon and GetIcon(tabConfig.Icon, 20) or nil
		local fallbackLabel
		if iconImage then
			iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
			iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
			iconImage.ImageColor3 = theme.SubText
			iconImage.Parent = button
		else
			fallbackLabel = New("TextLabel", {
				Text = (tabConfig.Title or "T"):sub(1, 1):upper(),
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextColor3 = theme.SubText,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Parent = button,
			})
		end

		AttachTooltip(button, tabConfig.Title or ("Tab " .. tabIndex))
		AddHoverScale(button, 1.08)

		button.MouseEnter:Connect(function()
			if tabIndex ~= Window._activeTabIndex then
				Tween(button, { BackgroundTransparency = 0.9 }, 0.1)
			end
		end)
		button.MouseLeave:Connect(function()
			if tabIndex ~= Window._activeTabIndex then
				Tween(button, { BackgroundTransparency = 1 }, 0.1)
			end
		end)

		local page = New("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = theme.Border,
			BorderSizePixel = 0,
			Visible = tabIndex == 1,
			Parent = PagesContainer,
		})
		-- Deliberately no UIPadding on `page` itself: the two-column split
		-- below needs pixel-exact control over the padded content width, and
		-- mixing that with however UIPadding remaps Scale for its children
		-- was the suspected source of column 2 still overflowing a little
		-- even after the math was exact — padding is applied by hand instead,
		-- computed straight from page.AbsoluteSize with no ambiguity.
		local PAGE_PAD_LEFT, PAGE_PAD_TOP, PAGE_PAD_RIGHT, PAGE_PAD_BOTTOM = 20, 4, 20, 20

		local Tab = { _page = page, _button = button, _icon = iconImage, _fallbackLabel = fallbackLabel, _columns = nil, _columnsFrame = nil }

		button.MouseButton1Click:Connect(function()
			Window:SelectTab(tabIndex)
		end)

		if tabIndex == 1 then
			button.BackgroundTransparency = 0.85
			if iconImage then iconImage.ImageColor3 = theme.Accent end
			if fallbackLabel then fallbackLabel.TextColor3 = theme.Accent end
		end

		--=====================================================================
		-- SECTION — the only way to add content to a tab. Sections lay out
		-- in one of two side-by-side columns; each row inside is a labeled
		-- control (toggle/slider/dropdown/colorpicker/keybind/input/button)
		-- or a plain paragraph.
		--=====================================================================

		--- Tab:AddSection({ Title, Column }) -> Section
		--- Column is 1 or 2 (default 1), placing the section in the left or
		--- right column, mirroring a two-panel settings layout.
		function Tab:AddSection(sectionCfg)
			sectionCfg = sectionCfg or {}
			local columnIndex = sectionCfg.Column or 1

			local COLUMN_GAP = 24

			if not Tab._columnsFrame then
				-- Pure offset Position/Size, computed directly from page's
				-- raw (unpadded) AbsoluteSize — no Scale, no UIPadding
				-- involved at all for this frame, so there's no ambiguity
				-- left to cause column 2 to overflow. RIGHT_SAFETY reserves
				-- a small extra gutter on top of PAGE_PAD_RIGHT so column 2
				-- never sits flush against page's true right edge (where its
				-- scrollbar rides).
				local RIGHT_SAFETY = 6
				Tab._columnsFrame = New("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, PAGE_PAD_LEFT, 0, PAGE_PAD_TOP),
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Parent = page,
				})
				Tab._columns = {}

				local bottomSpacer = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 1, 0, PAGE_PAD_BOTTOM),
					Parent = page,
				})
				local function RepositionBottomSpacer()
					bottomSpacer.Position = UDim2.new(0, 0, 0, PAGE_PAD_TOP + Tab._columnsFrame.AbsoluteSize.Y)
				end
				Tab._columnsFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(RepositionBottomSpacer)

				local function RelayoutColumns()
					local totalWidth = page.AbsoluteSize.X - PAGE_PAD_LEFT - PAGE_PAD_RIGHT - RIGHT_SAFETY
					if totalWidth <= 0 then return end
					Tab._columnsFrame.Size = UDim2.new(0, totalWidth, 0, 0)
					local col1, col2 = Tab._columns[1], Tab._columns[2]
					if col1 and col2 then
						local leftWidth = math.floor((totalWidth - COLUMN_GAP) / 2)
						local rightWidth = totalWidth - COLUMN_GAP - leftWidth
						col1.Position = UDim2.new(0, 0, 0, 0)
						col1.Size = UDim2.new(0, leftWidth, 0, 0)
						col2.Position = UDim2.new(0, leftWidth + COLUMN_GAP, 0, 0)
						col2.Size = UDim2.new(0, rightWidth, 0, 0)
					elseif col1 then
						col1.Position = UDim2.new(0, 0, 0, 0)
						col1.Size = UDim2.new(0, totalWidth, 0, 0)
					elseif col2 then
						col2.Position = UDim2.new(0, 0, 0, 0)
						col2.Size = UDim2.new(0, totalWidth, 0, 0)
					end
				end
				Tab._relayoutColumns = RelayoutColumns
				page:GetPropertyChangedSignal("AbsoluteSize"):Connect(RelayoutColumns)
				RelayoutColumns()
				RepositionBottomSpacer()
			end

			if not Tab._columns[columnIndex] then
				local col = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = columnIndex,
					Parent = Tab._columnsFrame,
				})
				New("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 18),
					Parent = col,
				})
				Tab._columns[columnIndex] = col
				Tab._relayoutColumns()
			end

			local column = Tab._columns[columnIndex]

			local sectionFrame = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = column,
			})
			New("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 3),
				Parent = sectionFrame,
			})

			if sectionCfg.Title then
				New("TextLabel", {
					Text = string.upper(sectionCfg.Title),
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextColor3 = theme.SubText,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = 0,
					Parent = sectionFrame,
				})
			end

			local Section = { _rowCount = 0 }

			-- Shared row shell used by every Section:AddX method below.
			-- `controlWidth` is how much horizontal space to reserve on the
			-- right for that row's control.
			local function CreateRow(rowCfg, controlWidth)
				rowCfg = rowCfg or {}
				local elevated = rowCfg.Elevated and true or false
				local hasDescription = rowCfg.Description ~= nil and rowCfg.Description ~= ""
				local rowHeight = elevated and 44 or (hasDescription and 40 or 32)

				Section._rowCount = Section._rowCount + 1
				local row = New("Frame", {
					BackgroundColor3 = elevated and theme.ElementBackground or theme.ElementBackground,
					BackgroundTransparency = elevated and 0 or 1,
					Size = UDim2.new(1, 0, 0, rowHeight),
					LayoutOrder = Section._rowCount,
					Parent = sectionFrame,
				})
				Round(row, 8)
				Pad(row, elevated and 12 or 4, 0, elevated and 12 or 4, 0)

				-- Every row gets a restrained fade+rise on creation, and a
				-- subtle hover highlight — modern, not bouncy.
				FadeSlideIn(row, math.min(Section._rowCount * 0.012, 0.1))
				local hoverOnTransparency = elevated and 0 or 0.92
				local hoverOffTransparency = elevated and 0 or 1
				local baseColor = row.BackgroundColor3
				row.MouseEnter:Connect(function()
					if elevated then
						Tween(row, { BackgroundColor3 = theme.ElementBackgroundHover }, 0.1)
					else
						Tween(row, { BackgroundTransparency = hoverOnTransparency }, 0.1)
					end
				end)
				row.MouseLeave:Connect(function()
					if elevated then
						Tween(row, { BackgroundColor3 = baseColor }, 0.1)
					else
						Tween(row, { BackgroundTransparency = hoverOffTransparency }, 0.1)
					end
				end)

				table.insert(Window._searchRows, { Instance = row, TitleLower = (rowCfg.Title or ""):lower(), TabIndex = tabIndex })

				local labelBox = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -(controlWidth + 10), 1, 0),
					Parent = row,
				})
				New("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Parent = labelBox,
				})
				New("TextLabel", {
					Text = rowCfg.Title or "",
					Font = elevated and Enum.Font.GothamMedium or Enum.Font.Gotham,
					TextSize = elevated and 13 or 12.5,
					TextColor3 = elevated and theme.Text or theme.SubText,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 16),
					Parent = labelBox,
				})
				if hasDescription then
					New("TextLabel", {
						Text = rowCfg.Description,
						Font = Enum.Font.Gotham,
						TextSize = 11,
						TextColor3 = theme.SubText,
						TextTransparency = 0.2,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextWrapped = true,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 14),
						Parent = labelBox,
					})
				end

				local controlHolder = New("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.new(0, controlWidth, 1, 0),
					Parent = row,
				})
				New("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
					Parent = controlHolder,
				})

				if rowCfg.Menu then
					local menuBtn = New("TextButton", {
						Text = "\226\139\175",
						Font = Enum.Font.GothamBold,
						TextSize = 14,
						TextColor3 = theme.SubText,
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 20, 0, 20),
						LayoutOrder = -1,
						Parent = controlHolder,
					})
					if rowCfg.MenuCallback then
						menuBtn.MouseButton1Click:Connect(rowCfg.MenuCallback)
					end
				end

				return row, controlHolder
			end

			--- Section:AddToggle(id, { Title, Description, Default, Elevated, Menu, Callback })
			function Section:AddToggle(id, cfg)
				cfg = cfg or {}
				local _, controlHolder = CreateRow(cfg, cfg.Menu and 60 or 36)

				local track = New("Frame", {
					BackgroundColor3 = theme.ElementBackgroundHover,
					Size = UDim2.new(0, 36, 0, 18),
					Parent = controlHolder,
				})
				Round(track, 9)
				local knob = New("Frame", {
					BackgroundColor3 = theme.Text,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 2, 0.5, 0),
					Size = UDim2.new(0, 14, 0, 14),
					Parent = track,
				})
				Round(knob, 7)
				local clickArea = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Parent = track })

				local Toggle = { Value = cfg.Default or false, Changed = Signal.new() }
				local function Render(animate)
					local on = Toggle.Value
					local trackColor = on and theme.Accent or theme.ElementBackgroundHover
					local knobPos = on and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
					if animate then
						Tween(track, { BackgroundColor3 = trackColor }, 0.12)
						Tween(knob, { Position = knobPos }, 0.12)
					else
						track.BackgroundColor3 = trackColor
						knob.Position = knobPos
					end
				end
				Render(false)
				function Toggle:SetValue(value)
					Toggle.Value = value
					Render(true)
					Toggle.Changed:Fire(value)
					if cfg.Callback then cfg.Callback(value) end
				end
				function Toggle:OnChanged(fn) Toggle.Changed:Connect(fn) end
				clickArea.MouseButton1Click:Connect(function() Toggle:SetValue(not Toggle.Value) end)

				if id then NovaUI.Options[id] = Toggle end
				return Toggle
			end

			--- Section:AddSlider(id, { Title, Description, Default, Min, Max, Rounding, Suffix, Elevated, Callback })
			function Section:AddSlider(id, cfg)
				cfg = cfg or {}
				local min, max = cfg.Min or 0, cfg.Max or 100
				local rounding = cfg.Rounding or 0
				local suffix = cfg.Suffix or ""
				local controlWidth = 160

				local _, controlHolder = CreateRow(cfg, controlWidth)

				local valueLabel = New("TextLabel", {
					Text = tostring(cfg.Default or min) .. suffix,
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = theme.SubText,
					TextXAlignment = Enum.TextXAlignment.Right,
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 44, 1, 0),
					LayoutOrder = 1,
					Parent = controlHolder,
				})

				local track = New("Frame", {
					BackgroundColor3 = theme.ElementBackgroundHover,
					Size = UDim2.new(0, controlWidth - 52, 0, 4),
					LayoutOrder = 2,
					Parent = controlHolder,
				})
				Round(track, 2)
				local fill = New("Frame", { BackgroundColor3 = theme.Accent, Size = UDim2.new(0, 0, 1, 0), Parent = track })
				Round(fill, 2)
				local knob = New("Frame", {
					BackgroundColor3 = theme.Text,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.new(0, 11, 0, 11),
					ZIndex = 2,
					Parent = track,
				})
				Round(knob, 6)

				local Slider = { Value = cfg.Default or min, Changed = Signal.new() }
				local function ApplyRounding(v)
					if rounding <= 0 then return math.floor(v + 0.5) end
					local mult = 10 ^ rounding
					return math.floor(v * mult + 0.5) / mult
				end
				local function RenderSlider(v)
					v = math.clamp(v, min, max)
					local alpha = (max ~= min) and (v - min) / (max - min) or 0
					fill.Size = UDim2.new(alpha, 0, 1, 0)
					knob.Position = UDim2.new(alpha, 0, 0.5, 0)
					valueLabel.Text = tostring(v) .. suffix
				end
				RenderSlider(Slider.Value)
				function Slider:SetValue(v)
					v = ApplyRounding(v)
					Slider.Value = v
					RenderSlider(v)
					Slider.Changed:Fire(v)
					if cfg.Callback then cfg.Callback(v) end
				end
				function Slider:OnChanged(fn) Slider.Changed:Connect(fn) end

				local dragging = false
				local function UpdateFromInputPos(x)
					local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
					Slider:SetValue(min + rel * (max - min))
				end
				track.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = true
						UpdateFromInputPos(input.Position.X)
					end
				end)
				UserInputService.InputChanged:Connect(function(input)
					if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						UpdateFromInputPos(input.Position.X)
					end
				end)
				UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = false
					end
				end)

				if id then NovaUI.Options[id] = Slider end
				return Slider
			end

			--- Section:AddDropdown(id, { Title, Description, Values, Multi, Default, Elevated, Callback })
			function Section:AddDropdown(id, cfg)
				cfg = cfg or {}
				local values = cfg.Values or {}
				local multi = cfg.Multi or false
				local controlWidth = 130

				local _, controlHolder = CreateRow(cfg, controlWidth)

				local ddBtn = New("TextButton", {
					Text = "",
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = theme.SubText,
					BackgroundColor3 = theme.ElementBackgroundHover,
					BackgroundTransparency = 0,
					AutoButtonColor = false,
					Size = UDim2.new(0, controlWidth, 0, 26),
					LayoutOrder = 1,
					Parent = controlHolder,
				})
				Round(ddBtn, 6)
				Pad(ddBtn, 8, 0, 22, 0)
				ddBtn.TextXAlignment = Enum.TextXAlignment.Left
				ddBtn.TextTruncate = Enum.TextTruncate.AtEnd

				-- Kept as a variable so it can be flipped 180° open/closed.
				local chevron
				do
					local icon = GetIcon("chevron-down", 10)
					if icon then
						chevron = icon
						icon.AnchorPoint = Vector2.new(1, 0.5)
						icon.Position = UDim2.new(1, -8, 0.5, 0)
						icon.ImageColor3 = theme.SubText
						icon.Parent = ddBtn
					else
						chevron = New("TextLabel", {
							Text = "\226\150\190",
							Font = Enum.Font.Gotham,
							TextSize = 9,
							TextColor3 = theme.SubText,
							BackgroundTransparency = 1,
							AnchorPoint = Vector2.new(1, 0.5),
							Position = UDim2.new(1, -8, 0.5, 0),
							Size = UDim2.new(0, 10, 1, 0),
							Parent = ddBtn,
						})
					end
				end

				-- Fixed-width, fully opaque popup — rendered in Overlay so it's
				-- never occluded by (or bleeding through) later sections/rows.
				local listFrame = New("Frame", {
					BackgroundColor3 = theme.PopupBackground,
					BackgroundTransparency = 0,
					Visible = false,
					Size = UDim2.new(0, math.max(controlWidth, 160), 0, math.min(#values, 6) * 28 + 8),
					Parent = Overlay,
				})
				Round(listFrame, 6)
				Stroke(listFrame, theme.Border, 1)
				AddShadow(listFrame, { Transparency = 0.45, OffsetY = 6, Blur = 16 })

				local listScroll = New("ScrollingFrame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					CanvasSize = UDim2.new(0, 0, 0, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollBarThickness = 2,
					BorderSizePixel = 0,
					Parent = listFrame,
				})
				Pad(listScroll, 4)
				New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = listScroll })

				local Dropdown = { Value = multi and {} or nil, Changed = Signal.new(), _optionButtons = {} }
				local function LabelForValue()
					if multi then
						local names = {}
						for name, on in pairs(Dropdown.Value or {}) do
							if on then table.insert(names, name) end
						end
						return #names > 0 and table.concat(names, ", ") or "..."
					else
						return tostring(Dropdown.Value or "...")
					end
				end
				local function RefreshButton() ddBtn.Text = LabelForValue() end
				local function RefreshHighlights()
					for name, btn in pairs(Dropdown._optionButtons) do
						local active = multi and Dropdown.Value[name] or (Dropdown.Value == name)
						btn.BackgroundTransparency = active and 0.85 or 1
						btn.TextColor3 = active and theme.Accent or theme.Text
					end
				end
				function Dropdown:OnChanged(fn) Dropdown.Changed:Connect(fn) end
				function Dropdown:SetValue(value)
					if multi then
						local map = {}
						if typeof(value) == "table" then
							if value[1] ~= nil then
								for _, name in ipairs(value) do map[name] = true end
							else
								for name, on in pairs(value) do map[name] = on end
							end
						end
						Dropdown.Value = map
					else
						Dropdown.Value = value
					end
					RefreshButton()
					RefreshHighlights()
					Dropdown.Changed:Fire(Dropdown.Value)
					if cfg.Callback then cfg.Callback(Dropdown.Value) end
				end
				for i, name in ipairs(values) do
					local optBtn = New("TextButton", {
						Text = tostring(name),
						Font = Enum.Font.Gotham,
						TextSize = 12,
						TextColor3 = theme.Text,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundColor3 = theme.Accent,
						BackgroundTransparency = 1,
						AutoButtonColor = false,
						Size = UDim2.new(1, 0, 0, 26),
						LayoutOrder = i,
						Parent = listScroll,
					})
					Round(optBtn, 4)
					Pad(optBtn, 8, 0, 8, 0)
					Dropdown._optionButtons[tostring(name)] = optBtn
					optBtn.MouseEnter:Connect(function()
						if not (multi and Dropdown.Value[tostring(name)]) and Dropdown.Value ~= tostring(name) then
							Tween(optBtn, { BackgroundTransparency = 0.92 }, 0.08)
						end
					end)
					optBtn.MouseLeave:Connect(function() RefreshHighlights() end)
					optBtn.MouseButton1Click:Connect(function()
						if multi then
							local key = tostring(name)
							local newMap = {}
							for k, v in pairs(Dropdown.Value) do newMap[k] = v end
							newMap[key] = not newMap[key]
							Dropdown:SetValue(newMap)
						else
							Dropdown:SetValue(tostring(name))
							ClosePopup()
						end
					end)
				end
				ddBtn.MouseButton1Click:Connect(function()
					OpenPopup(listFrame, ddBtn, {
						Align = "right",
						OnClose = function()
							Tween(chevron, { Rotation = 0 }, 0.12)
						end,
					})
					-- OpenPopup toggles closed (and Visible=false) if this
					-- dropdown was already open; only flip to 180° when it
					-- actually just opened.
					if listFrame.Visible then
						Tween(chevron, { Rotation = 180 }, 0.12)
					end
				end)
				if cfg.Default ~= nil then
					Dropdown:SetValue(cfg.Default)
				else
					RefreshButton()
				end

				if id then NovaUI.Options[id] = Dropdown end
				return Dropdown
			end

			--- Section:AddColorpicker(id, { Title, Description, Default, Transparency, Elevated, Callback })
			--- Callback/Changed fire once, with the final Color3, when you click
			--- off the popup to close it (not while dragging inside it).
			function Section:AddColorpicker(id, cfg)
				cfg = cfg or {}
				local controlWidth = 34

				local _, controlHolder = CreateRow(cfg, controlWidth)

				local swatch = New("TextButton", {
					Text = "",
					BackgroundColor3 = cfg.Default or Color3.fromRGB(255, 255, 255),
					AutoButtonColor = false,
					Size = UDim2.new(0, 30, 0, 20),
					Parent = controlHolder,
				})
				Round(swatch, 5)
				Stroke(swatch, theme.Border, 1)

				-- Fixed-size, fully opaque popup rendered in Overlay so it's
				-- always readable and never sits under other UI.
				local popup = New("Frame", {
					BackgroundColor3 = theme.PopupBackground,
					BackgroundTransparency = 0,
					Visible = false,
					Size = UDim2.new(0, 200, 0, cfg.Transparency ~= nil and 210 or 180),
					Parent = Overlay,
				})
				Round(popup, 8)
				Stroke(popup, theme.Border, 1)
				AddShadow(popup, { Transparency = 0.45, OffsetY = 6, Blur = 16 })
				Pad(popup, 10)
				New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = popup })

				-- Live preview swatch inside the popup, so the current color
				-- is always visible right next to the pickers themselves.
				local previewRow = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = 0,
					Parent = popup,
				})
				local previewSwatch = New("Frame", {
					BackgroundColor3 = cfg.Default or Color3.fromRGB(255, 255, 255),
					Size = UDim2.new(0, 20, 0, 20),
					Parent = previewRow,
				})
				Round(previewSwatch, 5)
				Stroke(previewSwatch, theme.Border, 1)
				local previewLabel = New("TextLabel", {
					Text = "",
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = theme.SubText,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 28, 0, 0),
					Size = UDim2.new(1, -28, 1, 0),
					Parent = previewRow,
				})

				-- SV box is 3 stacked layers, NOT a gradient applied to the base
				-- frame itself: a UIGradient's Color sequence completely
				-- overrides whatever the frame's own BackgroundColor3 is
				-- wherever the gradient is opaque, so putting a white gradient
				-- directly on svBox would hide the hue color underneath it
				-- (that mismatch between the logical s/v mapping and what
				-- actually rendered was the "left=hue, right=black" bug).
				-- Base: solid, full-saturation/value hue — always visible
				-- wherever both overlays above are transparent.
				local svBox = New("Frame", {
					BackgroundColor3 = Color3.fromRGB(255, 0, 0),
					Size = UDim2.new(1, 0, 0, 100),
					LayoutOrder = 1,
					Parent = popup,
				})
				Round(svBox, 4)
				-- White overlay: opaque white at the left edge (s=0), fading to
				-- fully transparent at the right edge (s=1) where the hue below
				-- shows through unobstructed.
				local whiteOverlay = New("Frame", {
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 0,
					Size = UDim2.new(1, 0, 1, 0),
					Parent = svBox,
				})
				New("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = whiteOverlay })
				-- Black overlay: fully transparent at the top edge (v=1, bright)
				-- fading to opaque black at the bottom edge (v=0, dark).
				local blackOverlay = New("Frame", {
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = 0,
					Size = UDim2.new(1, 0, 1, 0),
					Parent = svBox,
				})
				New("UIGradient", { Transparency = NumberSequence.new(1, 0), Rotation = 90, Parent = blackOverlay })

				local svCursor = New("Frame", {
					BackgroundColor3 = Color3.new(1, 1, 1),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.new(0, 10, 0, 10),
					ZIndex = 2,
					Parent = svBox,
				})
				Round(svCursor, 5)
				Stroke(svCursor, Color3.new(0, 0, 0), 2)

				local hueBar = New("Frame", {
					Size = UDim2.new(1, 0, 0, 14),
					LayoutOrder = 2,
					Parent = popup,
				})
				Round(hueBar, 4)
				New("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0.00, Color3.fromHSV(0, 1, 1)),
						ColorSequenceKeypoint.new(0.17, Color3.fromHSV(1 / 6, 1, 1)),
						ColorSequenceKeypoint.new(0.33, Color3.fromHSV(2 / 6, 1, 1)),
						ColorSequenceKeypoint.new(0.50, Color3.fromHSV(3 / 6, 1, 1)),
						ColorSequenceKeypoint.new(0.67, Color3.fromHSV(4 / 6, 1, 1)),
						ColorSequenceKeypoint.new(0.83, Color3.fromHSV(5 / 6, 1, 1)),
						ColorSequenceKeypoint.new(1.00, Color3.fromHSV(1, 1, 1)),
					}),
					Parent = hueBar,
				})
				local hueCursor = New("Frame", {
					BackgroundColor3 = Color3.new(1, 1, 1),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.new(0, 4, 1, 4),
					ZIndex = 2,
					Parent = hueBar,
				})
				Stroke(hueCursor, Color3.new(0, 0, 0), 1)

				local alphaBar, alphaCursor
				if cfg.Transparency ~= nil then
					alphaBar = New("Frame", {
						BackgroundColor3 = theme.ElementBackground,
						Size = UDim2.new(1, 0, 0, 14),
						LayoutOrder = 3,
						Parent = popup,
					})
					Round(alphaBar, 4)
					alphaCursor = New("Frame", {
						BackgroundColor3 = Color3.new(1, 1, 1),
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0, 0, 0.5, 0),
						Size = UDim2.new(0, 4, 1, 4),
						ZIndex = 2,
						Parent = alphaBar,
					})
					Stroke(alphaCursor, Color3.new(0, 0, 0), 1)
				end

				local Colorpicker = {
					Value = cfg.Default or Color3.fromRGB(255, 255, 255),
					Transparency = cfg.Transparency or 0,
					Changed = Signal.new(),
				}
				local h, s, v = Color3.toHSV(Colorpicker.Value)

				local function Render()
					svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
					svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
					hueCursor.Position = UDim2.new(h, 0, 0.5, 0)
					swatch.BackgroundColor3 = Colorpicker.Value
					previewSwatch.BackgroundColor3 = Colorpicker.Value
					previewLabel.Text = string.format("%d, %d, %d", math.round(Colorpicker.Value.R * 255), math.round(Colorpicker.Value.G * 255), math.round(Colorpicker.Value.B * 255))
					if alphaCursor then
						alphaCursor.Position = UDim2.new(1 - Colorpicker.Transparency, 0, 0.5, 0)
						alphaBar.BackgroundColor3 = Colorpicker.Value
					end
				end
				Render()

				function Colorpicker:OnChanged(fn) Colorpicker.Changed:Connect(fn) end
				function Colorpicker:SetValueRGB(color)
					Colorpicker.Value = color
					h, s, v = Color3.toHSV(color)
					Render()
					Colorpicker.Changed:Fire()
				end

				-- Live preview only — does NOT fire Changed/Callback. The value
				-- only "finalizes" (fires) when the popup is closed, so you can
				-- drag around freely and only the final color gets committed.
				local function Commit()
					Colorpicker.Value = Color3.fromHSV(h, s, v)
					Render()
				end

				local draggingSV, draggingHue, draggingAlpha = false, false, false
				svBox.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						draggingSV = true
						s = math.clamp((input.Position.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
						v = 1 - math.clamp((input.Position.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
						Commit()
					end
				end)
				hueBar.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						draggingHue = true
						h = math.clamp((input.Position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 1)
						Commit()
					end
				end)
				if alphaBar then
					alphaBar.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 then
							draggingAlpha = true
							Colorpicker.Transparency = 1 - math.clamp((input.Position.X - alphaBar.AbsolutePosition.X) / alphaBar.AbsoluteSize.X, 0, 1)
							Render()
						end
					end)
				end
				UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						draggingSV, draggingHue, draggingAlpha = false, false, false
					end
				end)
				UserInputService.InputChanged:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
					if draggingSV then
						s = math.clamp((input.Position.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
						v = 1 - math.clamp((input.Position.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
						Commit()
					elseif draggingHue then
						h = math.clamp((input.Position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 1)
						Commit()
					elseif draggingAlpha and alphaBar then
						Colorpicker.Transparency = 1 - math.clamp((input.Position.X - alphaBar.AbsolutePosition.X) / alphaBar.AbsoluteSize.X, 0, 1)
						Render()
					end
				end)

				swatch.MouseButton1Click:Connect(function()
					-- Re-sync h/s/v from the *current* Value every time the
					-- popup opens (in case SetValueRGB changed it while
					-- closed) so the cursors always match the real color.
					h, s, v = Color3.toHSV(Colorpicker.Value)
					Render()
					OpenPopup(popup, swatch, {
						Align = "right",
						OnClose = function()
							-- The color only finalizes when you click off the
							-- popup — this is where Changed/Callback actually fire.
							Colorpicker.Changed:Fire(Colorpicker.Value)
							if cfg.Callback then cfg.Callback(Colorpicker.Value) end
						end,
					})
				end)

				if id then NovaUI.Options[id] = Colorpicker end
				return Colorpicker
			end

			--- Section:AddKeybind(id, { Title, Description, Mode, Default, Elevated, Callback, ChangedCallback })
			function Section:AddKeybind(id, cfg)
				cfg = cfg or {}
				local controlWidth = 90

				local _, controlHolder = CreateRow(cfg, controlWidth)

				local keyBtn = New("TextButton", {
					Text = tostring(cfg.Default or "None"),
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = theme.Text,
					BackgroundColor3 = theme.ElementBackgroundHover,
					Size = UDim2.new(0, controlWidth, 0, 26),
					Parent = controlHolder,
				})
				Round(keyBtn, 6)

				local Keybind = {
					Value = cfg.Default,
					Mode = cfg.Mode or "Toggle",
					Changed = Signal.new(),
					Click = Signal.new(),
					_state = false,
					_listening = false,
				}

				function Keybind:OnChanged(fn) Keybind.Changed:Connect(fn) end
				function Keybind:OnClick(fn) Keybind.Click:Connect(fn) end
				function Keybind:GetState() return Keybind._state end
				function Keybind:SetValue(key, mode)
					Keybind.Value = key
					if mode then Keybind.Mode = mode end
					keyBtn.Text = tostring(key or "None")
					Keybind.Changed:Fire(key)
					if cfg.ChangedCallback then cfg.ChangedCallback(key) end
				end

				keyBtn.MouseButton1Click:Connect(function()
					Keybind._listening = true
					keyBtn.Text = "..."
				end)

				UserInputService.InputBegan:Connect(function(input, processed)
					if Keybind._listening then
						local keyName
						if input.UserInputType == Enum.UserInputType.MouseButton1 then keyName = "MB1"
						elseif input.UserInputType == Enum.UserInputType.MouseButton2 then keyName = "MB2"
						elseif input.KeyCode ~= Enum.KeyCode.Unknown then keyName = input.KeyCode.Name end
						if keyName then
							Keybind._listening = false
							Keybind:SetValue(keyName)
						end
						return
					end

					if processed then return end
					local matches = (input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode.Name == Keybind.Value)
						or (input.UserInputType == Enum.UserInputType.MouseButton1 and Keybind.Value == "MB1")
						or (input.UserInputType == Enum.UserInputType.MouseButton2 and Keybind.Value == "MB2")

					if matches then
						if Keybind.Mode == "Toggle" then
							Keybind._state = not Keybind._state
							if Keybind._state then
								Keybind.Click:Fire()
								if cfg.Callback then cfg.Callback(true) end
							else
								if cfg.Callback then cfg.Callback(false) end
							end
						elseif Keybind.Mode == "Hold" then
							Keybind._state = true
							if cfg.Callback then cfg.Callback(true) end
						elseif Keybind.Mode == "Always" then
							if cfg.Callback then cfg.Callback(true) end
						end
					end
				end)

				UserInputService.InputEnded:Connect(function(input)
					if Keybind.Mode ~= "Hold" then return end
					local keyName
					if input.UserInputType == Enum.UserInputType.MouseButton1 then keyName = "MB1"
					elseif input.UserInputType == Enum.UserInputType.MouseButton2 then keyName = "MB2"
					elseif input.KeyCode ~= Enum.KeyCode.Unknown then keyName = input.KeyCode.Name end
					if keyName == Keybind.Value then
						Keybind._state = false
						if cfg.Callback then cfg.Callback(false) end
					end
				end)

				if id then NovaUI.Options[id] = Keybind end
				return Keybind
			end

			--- Section:AddInput(id, { Title, Description, Default, Placeholder, Numeric, Finished, Elevated, Callback })
			function Section:AddInput(id, cfg)
				cfg = cfg or {}
				local controlWidth = 120

				local _, controlHolder = CreateRow(cfg, controlWidth)

				local box = New("Frame", {
					BackgroundColor3 = theme.ElementBackgroundHover,
					Size = UDim2.new(0, controlWidth, 0, 26),
					Parent = controlHolder,
				})
				Round(box, 6)
				Pad(box, 8, 0, 8, 0)
				-- Starts invisible; brightens into an accent-colored focus
				-- ring and fades back out, so typing/clicking the field gives
				-- the same kind of feedback every other control has.
				local boxFocusRing = Stroke(box, theme.Accent, 1.5, 1)

				local textbox = New("TextBox", {
					Text = cfg.Default or "",
					PlaceholderText = cfg.Placeholder or "",
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = theme.Text,
					PlaceholderColor3 = theme.SubText,
					ClearTextOnFocus = false,
					BackgroundTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, 0, 1, 0),
					Parent = box,
				})

				box.MouseEnter:Connect(function()
					if not textbox:IsFocused() then
						Tween(box, { BackgroundColor3 = theme.ElementBackground }, 0.1)
					end
				end)
				box.MouseLeave:Connect(function()
					if not textbox:IsFocused() then
						Tween(box, { BackgroundColor3 = theme.ElementBackgroundHover }, 0.1)
					end
				end)
				textbox.Focused:Connect(function()
					Tween(boxFocusRing, { Transparency = 0 }, 0.12)
					Tween(box, { BackgroundColor3 = theme.ElementBackground }, 0.12)
				end)
				textbox.FocusLost:Connect(function()
					Tween(boxFocusRing, { Transparency = 1 }, 0.15)
					Tween(box, { BackgroundColor3 = theme.ElementBackgroundHover }, 0.15)
				end)

				local Input = { Value = cfg.Default or "", Changed = Signal.new() }
				function Input:OnChanged(fn) Input.Changed:Connect(fn) end
				function Input:SetValue(text)
					Input.Value = text
					textbox.Text = text
					Input.Changed:Fire(text)
				end

				if cfg.Numeric then
					textbox:GetPropertyChangedSignal("Text"):Connect(function()
						local filtered = textbox.Text:gsub("[^%d%.%-]", "")
						if filtered ~= textbox.Text then
							textbox.Text = filtered
						end
					end)
				end

				local function Fire()
					Input.Value = textbox.Text
					Input.Changed:Fire(textbox.Text)
					if cfg.Callback then cfg.Callback(textbox.Text) end
				end

				if cfg.Finished then
					textbox.FocusLost:Connect(function(enterPressed)
						if enterPressed then Fire() end
					end)
				else
					textbox:GetPropertyChangedSignal("Text"):Connect(Fire)
				end

				if id then NovaUI.Options[id] = Input end
				return Input
			end

			--- Section:AddButton({ Title, Description, ButtonText, Elevated, Callback })
			function Section:AddButton(cfg)
				cfg = cfg or {}
				local controlWidth = 74

				local _, controlHolder = CreateRow(cfg, controlWidth)

				local btn = New("TextButton", {
					Text = cfg.ButtonText or "Run",
					Font = Enum.Font.GothamMedium,
					TextSize = 12,
					TextColor3 = Color3.new(1, 1, 1),
					BackgroundColor3 = theme.Accent,
					AutoButtonColor = false,
					Size = UDim2.new(0, controlWidth, 0, 26),
					Parent = controlHolder,
				})
				Round(btn, 6)
				AddHoverScale(btn, 1.04)
				btn.MouseButton1Click:Connect(function()
					if cfg.Callback then cfg.Callback() end
				end)
				return { Instance = btn }
			end

			--- Section:AddParagraph({ Title, Content })
			function Section:AddParagraph(cfg)
				cfg = cfg or {}
				Section._rowCount = Section._rowCount + 1
				local card = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = Section._rowCount,
					Parent = sectionFrame,
				})
				Pad(card, 4, 6, 4, 6)
				FadeSlideIn(card, math.min(Section._rowCount * 0.012, 0.1))
				New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3), Parent = card })
				if cfg.Title then
					New("TextLabel", {
						Text = cfg.Title,
						Font = Enum.Font.GothamMedium,
						TextSize = 13,
						TextColor3 = theme.Text,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 16),
						LayoutOrder = 1,
						Parent = card,
					})
				end
				New("TextLabel", {
					Text = cfg.Content or "",
					Font = Enum.Font.Gotham,
					TextSize = 12,
					TextColor3 = theme.SubText,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = 2,
					Parent = card,
				})
				return { Instance = card }
			end

			return Section
		end

		self._tabs[tabIndex] = Tab
		return Tab
	end

	return Window
end

return NovaUI
