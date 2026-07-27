--[[
	NovaUI
	A lightweight, Fluent-inspired UI library for Roblox.

	This is a standalone ModuleScript. Put it in ReplicatedStorage (or anywhere
	a LocalScript can reach it) and `require()` it — see example.lua for usage.

	Layout: icon-only sidebar rail + search/selector bar + two-column grouped
	settings sections (rows with inline toggle/dropdown/slider controls),
	styled after a dark dashboard-style settings panel.

	Icons: optional integration with latte-soft/lucide-roblox
	(https://github.com/latte-soft/lucide-roblox). If a "Lucide" ModuleScript
	is found under ReplicatedStorage (or passed via CreateWindow's
	`IconProvider` option / NovaUI:SetIconProvider), sidebar tab icons and a
	few chrome icons (search, folder, chevron, close) render using it.
	Without it, everything still works — icons just fall back to plain text/
	initials so the library has no hard dependency.

	Components:
		Window, Tab, Section/Row (grouped settings list), Paragraph, Button,
		Toggle, Slider, Dropdown (single/multi), Colorpicker (with optional
		transparency), Keybind, Input, Notify, Dialog

	Theme: dark background with a blue accent (see Themes.Dark below).
	You can swap NovaUI.Theme for your own table with the same keys.
--]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	New("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
	return inst
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

local function Tween(inst, props, time, style, dir)
	local info = TweenInfo.new(time or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(inst, info, props)
	tw:Play()
	return tw
end

local function MakeDraggable(frame, handle)
	handle = handle or frame
	local dragging, dragStart, startPos = false, nil, nil

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
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
NovaUI.Version = "1.1.0"
NovaUI.Options = {}
NovaUI.Unloaded = false
NovaUI.Theme = Themes.Dark
NovaUI.IconProvider = nil

--- Optional: NovaUI:SetIconProvider(require(path.to.Lucide))
-- Hooks up latte-soft/lucide-roblox (or any module exposing the same
-- `ImageLabel(name, size, propsOverrides)` API) so tab/chrome icons render
-- as real Lucide glyphs instead of falling back to text.
function NovaUI:SetIconProvider(module)
	NovaUI.IconProvider = module
end

local function TryFindLucide()
	if NovaUI.IconProvider then
		return NovaUI.IconProvider
	end
	local ok, mod = pcall(function()
		local found = ReplicatedStorage:FindFirstChild("Lucide") or ReplicatedStorage:FindFirstChild("lucide-roblox")
		return found and require(found)
	end)
	if ok and mod then
		NovaUI.IconProvider = mod
		return mod
	end
	return nil
end

-- Returns an ImageLabel for `name` via the icon provider, or nil if
-- unavailable/not found — callers should always have a text fallback.
local function GetIcon(name, size, propsOverrides)
	if not name or name == "" then return nil end
	local provider = TryFindLucide()
	if not provider then return nil end
	local ok, imageLabel = pcall(function()
		return provider.ImageLabel(name, size or 20, propsOverrides)
	end)
	if ok and imageLabel then return imageLabel end
	return nil
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

	local card = New("Frame", {
		BackgroundColor3 = theme.SecondaryBackground,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = -os.clock(),
		Parent = holder,
	})
	Round(card, 8)
	Stroke(card, theme.Border, 1)
	Pad(card, 12)

	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = card,
	})

	New("Frame", {
		BackgroundColor3 = theme.Accent,
		Size = UDim2.new(0, 3, 1, 0),
		Parent = card,
	})

	New("TextLabel", {
		Text = config.Title or "Notification",
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = card,
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
			Parent = card,
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
			Parent = card,
		})
	end

	card.BackgroundTransparency = 1
	card.Position = UDim2.new(1, 40, 0, 0)
	Tween(card, { BackgroundTransparency = 0, Position = UDim2.new(0, 0, 0, 0) }, 0.25)

	if config.Duration then
		task.delay(config.Duration, function()
			if card and card.Parent then
				Tween(card, { Position = UDim2.new(1, 40, 0, 0) }, 0.2)
				task.wait(0.2)
				card:Destroy()
			end
		end)
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
	if config.IconProvider then
		NovaUI.IconProvider = config.IconProvider
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

	local Main = New("Frame", {
		Name = "Main",
		BackgroundColor3 = theme.Background,
		BackgroundTransparency = config.Acrylic and 0.06 or 0,
		Position = UDim2.new(0.5, -size.X.Offset / 2, 0.5, -size.Y.Offset / 2),
		Size = size,
		ClipsDescendants = true,
		Parent = ScreenGui,
	})
	Round(Main, 14)
	Stroke(Main, theme.Border, 1)

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
		Size = UDim2.new(1, 0, 1, -100),
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

	local ExpandBtn = New("TextButton", {
		Text = "\226\140\132", -- chevron-ish fallback glyph
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 24, 0, 24),
		AutoButtonColor = false,
		Parent = SidebarFooter,
	})
	do
		local icon = GetIcon("chevron-down", 14, { TextColor3 = theme.SubText })
		if icon then
			ExpandBtn.Text = ""
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.ImageColor3 = theme.SubText
			icon.Parent = ExpandBtn
		end
	end

	local AvatarBtn = New("TextButton", {
		Text = "",
		BackgroundColor3 = theme.ElementBackground,
		Size = UDim2.new(0, 32, 0, 32),
		AutoButtonColor = false,
		Parent = SidebarFooter,
	})
	Round(AvatarBtn, 16)
	Stroke(AvatarBtn, theme.Border, 1)

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

	-- Search pill
	local SearchPill = New("Frame", {
		BackgroundColor3 = theme.ElementBackground,
		Size = UDim2.new(0, 220, 1, 0),
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
		Parent = SearchPill,
	})

	-- Config selector pill (folder icon + label + chevron)
	local SelectorPill = New("TextButton", {
		Text = "",
		BackgroundColor3 = theme.ElementBackground,
		Size = UDim2.new(0, 176, 1, 0),
		AutoButtonColor = false,
		LayoutOrder = 2,
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
		local icon = GetIcon("folder", 14)
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

	local SelectorList = New("Frame", {
		BackgroundColor3 = theme.ElementBackgroundHover,
		Visible = false,
		ZIndex = 30,
		Size = UDim2.new(0, 176, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = ContentTopBar,
	})
	Round(SelectorList, 8)
	Stroke(SelectorList, theme.Border, 1)
	Pad(SelectorList, 4)
	New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = SelectorList })

	-- Window chrome (minimize/close) — small, top-right corner
	local ChromeRow = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 56, 1, 0),
		LayoutOrder = 3,
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
	local MinimizeBtn = New("TextButton", {
		Text = "\226\128\148",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 24, 0, 24),
		LayoutOrder = 1,
		Parent = ChromeRow,
	})
	local CloseBtn = New("TextButton", {
		Text = "\226\156\149",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 24, 0, 24),
		LayoutOrder = 2,
		Parent = ChromeRow,
	})

	MakeDraggable(Main, LogoBox)
	MakeDraggable(Main, ContentTopBar)

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
	Window._fullSize = size
	Window._activeTabIndex = 1
	Window._searchRows = {} -- { {Instance, TitleLower, TabIndex}, ... }
	Window._searchText = ""

	CloseBtn.MouseButton1Click:Connect(function()
		Window:Destroy()
	end)

	MinimizeBtn.MouseButton1Click:Connect(function()
		Window:ToggleMinimize()
	end)

	function Window:ToggleMinimize()
		self._minimized = not self._minimized
		if self._minimized then
			Tween(Main, { Size = UDim2.new(0, self._fullSize.X.Offset, 0, 56) }, 0.2)
			Sidebar.Visible = false
			ContentArea.Visible = false
		else
			Sidebar.Visible = true
			ContentArea.Visible = true
			Tween(Main, { Size = self._fullSize }, 0.2)
		end
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
		ScreenGui:Destroy()
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
	local ConfigSelector = { Value = SelectorLabel.Text, Changed = Signal.new(), _options = {}, _buttons = {} }
	function ConfigSelector:OnChanged(fn) ConfigSelector.Changed:Connect(fn) end
	function ConfigSelector:SetValue(name)
		ConfigSelector.Value = name
		SelectorLabel.Text = name
		ConfigSelector.Changed:Fire(name)
	end
	function ConfigSelector:SetOptions(list)
		for _, btn in ipairs(ConfigSelector._buttons) do btn:Destroy() end
		ConfigSelector._buttons = {}
		ConfigSelector._options = list
		for i, name in ipairs(list) do
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
				LayoutOrder = i,
				ZIndex = 31,
				Parent = SelectorList,
			})
			Round(btn, 4)
			Pad(btn, 8, 0, 8, 0)
			btn.MouseEnter:Connect(function() btn.BackgroundTransparency = 0.85 end)
			btn.MouseLeave:Connect(function() btn.BackgroundTransparency = 1 end)
			btn.MouseButton1Click:Connect(function()
				ConfigSelector:SetValue(name)
				SelectorList.Visible = false
			end)
			table.insert(ConfigSelector._buttons, btn)
		end
	end
	SelectorPill.MouseButton1Click:Connect(function()
		SelectorList.Visible = not SelectorList.Visible
	end)
	Window.ConfigSelector = ConfigSelector
	Window.Search = { Box = SearchBox }

	function Window:SelectTab(index)
		local tab = self._tabs[index]
		if not tab then return end
		self._activeTabIndex = index
		for i, t in ipairs(self._tabs) do
			t._page.Visible = (i == index)
			t._button.BackgroundTransparency = (i == index) and 0.85 or 1
			if t._icon then
				t._icon.ImageColor3 = (i == index) and theme.Accent or theme.SubText
			end
			if t._fallbackLabel then
				t._fallbackLabel.TextColor3 = (i == index) and theme.Accent or theme.SubText
			end
		end
		ApplySearchFilter()
	end

	--- Window:Dialog({ Title, Content, Buttons = {{Title, Callback}, ...} })
	function Window:Dialog(cfg)
		local overlay = New("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 50,
			Parent = Main,
		})

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
				Size = UDim2.new(0, 90, 1, 0),
				ZIndex = 51,
				Parent = btnRow,
			})
			Round(btn, 6)
			btn.MouseButton1Click:Connect(function()
				overlay:Destroy()
				if btnCfg.Callback then btnCfg.Callback() end
			end)
		end
	end

	--=========================================================================
	-- TAB
	--=========================================================================

	function Window:AddTab(tabConfig)
		tabConfig = tabConfig or {}
		local index = #self._tabs + 1

		local button = New("TextButton", {
			Text = "",
			BackgroundColor3 = theme.Accent,
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 40, 0, 40),
			AutoButtonColor = false,
			LayoutOrder = index,
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

		-- Tooltip (parented to ScreenGui so it isn't clipped by Main)
		local tooltip = New("TextLabel", {
			Text = tabConfig.Title or ("Tab " .. index),
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = theme.Text,
			BackgroundColor3 = theme.ElementBackgroundHover,
			Visible = false,
			ZIndex = 100,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, 24),
			Parent = ScreenGui,
		})
		Round(tooltip, 5)
		Pad(tooltip, 8, 0, 8, 0)

		button.MouseEnter:Connect(function()
			tooltip.Position = UDim2.fromOffset(button.AbsolutePosition.X + button.AbsoluteSize.X + 8, button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2 - 12)
			tooltip.Visible = true
			if index ~= Window._activeTabIndex then
				Tween(button, { BackgroundTransparency = 0.9 }, 0.12)
			end
		end)
		button.MouseLeave:Connect(function()
			tooltip.Visible = false
			if index ~= Window._activeTabIndex then
				Tween(button, { BackgroundTransparency = 1 }, 0.12)
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
			Visible = index == 1,
			Parent = PagesContainer,
		})
		Pad(page, 20, 4, 20, 20)
		New("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
			Parent = page,
		})

		local Tab = { _page = page, _button = button, _icon = iconImage, _fallbackLabel = fallbackLabel, _columns = nil, _columnsFrame = nil }

		button.MouseButton1Click:Connect(function()
			Window:SelectTab(index)
		end)

		if index == 1 then
			button.BackgroundTransparency = 0.85
			if iconImage then iconImage.ImageColor3 = theme.Accent end
			if fallbackLabel then fallbackLabel.TextColor3 = theme.Accent end
		end

		--=====================================================================
		-- CLASSIC ELEMENTS (single-column card style — still available,
		-- handy for a Settings tab, forms, etc.)
		--=====================================================================

		local function BaseCard(height, layoutOrder)
			local card = New("Frame", {
				BackgroundColor3 = theme.ElementBackground,
				Size = UDim2.new(1, 0, 0, height or 46),
				LayoutOrder = layoutOrder or (#page:GetChildren()),
				Parent = page,
			})
			Round(card, 8)
			return card
		end

		local function TitleDesc(parent, title, description, rightInset)
			local box = New("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 12, 0, 0),
				Size = UDim2.new(1, -(24 + (rightInset or 0)), 1, 0),
				Parent = parent,
			})
			New("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Parent = box,
			})
			New("TextLabel", {
				Text = title or "",
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 16),
				Parent = box,
			})
			if description then
				New("TextLabel", {
					Text = description,
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextColor3 = theme.SubText,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 14),
					Parent = box,
				})
			end
			return box
		end

		--- Tab:AddParagraph({ Title, Content })
		function Tab:AddParagraph(cfg)
			local card = New("Frame", {
				BackgroundColor3 = theme.ElementBackground,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = page,
			})
			Round(card, 8)
			Pad(card, 12)
			New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = card })
			New("TextLabel", {
				Text = cfg.Title or "",
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 16),
				Parent = card,
			})
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
				Parent = card,
			})
			return card
		end

		--- Tab:AddButton({ Title, Description, Callback })
		function Tab:AddButton(cfg)
			local card = BaseCard(46)
			TitleDesc(card, cfg.Title, cfg.Description, 90)

			local btn = New("TextButton", {
				Text = "Run",
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = theme.Text,
				BackgroundColor3 = theme.Accent,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.new(0, 70, 0, 26),
				Parent = card,
			})
			Round(btn, 6)
			btn.MouseButton1Click:Connect(function()
				if cfg.Callback then cfg.Callback() end
			end)
			return { Instance = card }
		end

		--- Tab:AddToggle(id, { Title, Description, Default })
		function Tab:AddToggle(id, cfg)
			local card = BaseCard(46)
			TitleDesc(card, cfg.Title, cfg.Description, 60)

			local track = New("Frame", {
				BackgroundColor3 = theme.ElementBackgroundHover,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.new(0, 38, 0, 20),
				Parent = card,
			})
			Round(track, 10)
			local knob = New("Frame", {
				BackgroundColor3 = theme.Text,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 2, 0.5, 0),
				Size = UDim2.new(0, 16, 0, 16),
				Parent = track,
			})
			Round(knob, 8)

			local clickArea = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Parent = track })

			local Toggle = { Value = cfg.Default or false, Changed = Signal.new() }

			local function Render(animate)
				local on = Toggle.Value
				local trackColor = on and theme.Accent or theme.ElementBackgroundHover
				local knobPos = on and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
				if animate then
					Tween(track, { BackgroundColor3 = trackColor }, 0.15)
					Tween(knob, { Position = knobPos }, 0.15)
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
			end

			function Toggle:OnChanged(fn)
				Toggle.Changed:Connect(fn)
			end

			clickArea.MouseButton1Click:Connect(function()
				Toggle:SetValue(not Toggle.Value)
			end)

			NovaUI.Options[id] = Toggle
			return Toggle
		end

		--- Tab:AddSlider(id, { Title, Description, Default, Min, Max, Rounding, Callback })
		function Tab:AddSlider(id, cfg)
			local card = BaseCard(52)
			local min, max = cfg.Min or 0, cfg.Max or 100
			local rounding = cfg.Rounding or 0

			local box = New("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 12, 0, 2),
				Size = UDim2.new(1, -24, 0, 32),
				Parent = card,
			})

			New("TextLabel", {
				Text = cfg.Title or "",
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundTransparency = 1,
				Size = UDim2.new(0.6, 0, 0, 16),
				Parent = box,
			})

			local valueLabel = New("TextLabel", {
				Text = tostring(cfg.Default or min),
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextColor3 = theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Right,
				BackgroundTransparency = 1,
				Position = UDim2.new(0.6, 0, 0, 0),
				Size = UDim2.new(0.4, 0, 0, 16),
				Parent = box,
			})

			local track = New("Frame", {
				BackgroundColor3 = theme.ElementBackgroundHover,
				Position = UDim2.new(0, 0, 0, 22),
				Size = UDim2.new(1, 0, 0, 6),
				Parent = box,
			})
			Round(track, 3)
			local fill = New("Frame", {
				BackgroundColor3 = theme.Accent,
				Size = UDim2.new(0, 0, 1, 0),
				Parent = track,
			})
			Round(fill, 3)
			local knob = New("Frame", {
				BackgroundColor3 = theme.Text,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(0, 12, 0, 12),
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

			local function Render(v)
				v = math.clamp(v, min, max)
				local alpha = (max ~= min) and (v - min) / (max - min) or 0
				fill.Size = UDim2.new(alpha, 0, 1, 0)
				knob.Position = UDim2.new(alpha, 0, 0.5, 0)
				valueLabel.Text = tostring(v)
			end
			Render(Slider.Value)

			function Slider:SetValue(v)
				v = ApplyRounding(v)
				Slider.Value = v
				Render(v)
				Slider.Changed:Fire(v)
				if cfg.Callback then cfg.Callback(v) end
			end

			function Slider:OnChanged(fn)
				Slider.Changed:Connect(fn)
			end

			local dragging = false
			local function UpdateFromInputPos(x)
				local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
				local v = min + rel * (max - min)
				Slider:SetValue(v)
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

			NovaUI.Options[id] = Slider
			return Slider
		end

		--- Tab:AddDropdown(id, { Title, Description, Values, Multi, Default })
		function Tab:AddDropdown(id, cfg)
			local values = cfg.Values or {}
			local multi = cfg.Multi or false

			local card = BaseCard(46)
			TitleDesc(card, cfg.Title, cfg.Description, 130)

			local selectedBtn = New("TextButton", {
				Text = "",
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextColor3 = theme.SubText,
				BackgroundColor3 = theme.ElementBackgroundHover,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.new(0, 120, 0, 28),
				AutoButtonColor = false,
				Parent = card,
			})
			Round(selectedBtn, 6)
			Pad(selectedBtn, 8, 0, 8, 0)
			selectedBtn.TextXAlignment = Enum.TextXAlignment.Left
			selectedBtn.TextTruncate = Enum.TextTruncate.AtEnd

			local listFrame = New("Frame", {
				BackgroundColor3 = theme.ElementBackgroundHover,
				Visible = false,
				ZIndex = 20,
				Size = UDim2.new(0, 180, 0, math.min(#values, 6) * 28 + 8),
				Parent = card,
			})
			Round(listFrame, 6)
			Stroke(listFrame, theme.Border, 1)

			local listScroll = New("ScrollingFrame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				CanvasSize = UDim2.new(0, 0, 0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 2,
				BorderSizePixel = 0,
				ZIndex = 20,
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
					return #names > 0 and table.concat(names, ", ") or "None"
				else
					return tostring(Dropdown.Value or "None")
				end
			end

			local function RefreshButton()
				selectedBtn.Text = LabelForValue()
			end

			local function RefreshHighlights()
				for name, btn in pairs(Dropdown._optionButtons) do
					local active = multi and Dropdown.Value[name] or (Dropdown.Value == name)
					btn.BackgroundTransparency = active and 0.85 or 1
					btn.TextColor3 = active and theme.Accent or theme.Text
				end
			end

			function Dropdown:OnChanged(fn)
				Dropdown.Changed:Connect(fn)
			end

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
					ZIndex = 21,
					Parent = listScroll,
				})
				Round(optBtn, 4)
				Pad(optBtn, 8, 0, 8, 0)
				Dropdown._optionButtons[tostring(name)] = optBtn

				optBtn.MouseButton1Click:Connect(function()
					if multi then
						local key = tostring(name)
						local newMap = {}
						for k, v in pairs(Dropdown.Value) do newMap[k] = v end
						newMap[key] = not newMap[key]
						Dropdown:SetValue(newMap)
					else
						Dropdown:SetValue(tostring(name))
						listFrame.Visible = false
					end
				end)
			end

			selectedBtn.MouseButton1Click:Connect(function()
				listFrame.Visible = not listFrame.Visible
			end)

			if cfg.Default ~= nil then
				Dropdown:SetValue(cfg.Default)
			else
				RefreshButton()
			end

			NovaUI.Options[id] = Dropdown
			return Dropdown
		end

		--- Tab:AddColorpicker(id, { Title, Description, Default, Transparency })
		function Tab:AddColorpicker(id, cfg)
			local card = BaseCard(46)
			TitleDesc(card, cfg.Title, cfg.Description, 50)

			local swatch = New("TextButton", {
				Text = "",
				BackgroundColor3 = cfg.Default or Color3.fromRGB(255, 255, 255),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.new(0, 28, 0, 20),
				Parent = card,
			})
			Round(swatch, 5)
			Stroke(swatch, theme.Border, 1)

			local popup = New("Frame", {
				BackgroundColor3 = theme.ElementBackgroundHover,
				Visible = false,
				ZIndex = 20,
				Size = UDim2.new(0, 200, 0, cfg.Transparency ~= nil and 210 or 180),
				Parent = card,
			})
			Round(popup, 8)
			Stroke(popup, theme.Border, 1)
			Pad(popup, 10)
			New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = popup })

			local svBox = New("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 0, 0),
				Size = UDim2.new(1, 0, 0, 100),
				ZIndex = 21,
				LayoutOrder = 1,
				Parent = popup,
			})
			Round(svBox, 4)
			New("UIGradient", { Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(1,1,1)), Transparency = NumberSequence.new(0, 1), Parent = svBox })
			local blackOverlay = New("Frame", { BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 1, Size = UDim2.new(1,0,1,0), ZIndex = 21, Parent = svBox })
			New("UIGradient", { Color = ColorSequence.new(Color3.new(0,0,0), Color3.new(0,0,0)), Transparency = NumberSequence.new(1, 0), Rotation = 90, Parent = blackOverlay })

			local svCursor = New("Frame", {
				BackgroundColor3 = Color3.new(1,1,1),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.new(0, 8, 0, 8),
				ZIndex = 22,
				Parent = svBox,
			})
			Round(svCursor, 4)
			Stroke(svCursor, Color3.new(0,0,0), 1)

			local hueBar = New("Frame", {
				Size = UDim2.new(1, 0, 0, 14),
				ZIndex = 21,
				LayoutOrder = 2,
				Parent = popup,
			})
			Round(hueBar, 4)
			New("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0.00, Color3.fromHSV(0, 1, 1)),
					ColorSequenceKeypoint.new(0.17, Color3.fromHSV(1/6, 1, 1)),
					ColorSequenceKeypoint.new(0.33, Color3.fromHSV(2/6, 1, 1)),
					ColorSequenceKeypoint.new(0.50, Color3.fromHSV(3/6, 1, 1)),
					ColorSequenceKeypoint.new(0.67, Color3.fromHSV(4/6, 1, 1)),
					ColorSequenceKeypoint.new(0.83, Color3.fromHSV(5/6, 1, 1)),
					ColorSequenceKeypoint.new(1.00, Color3.fromHSV(1, 1, 1)),
				}),
				Parent = hueBar,
			})
			local hueCursor = New("Frame", {
				BackgroundColor3 = Color3.new(1,1,1),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(0, 4, 1, 4),
				ZIndex = 22,
				Parent = hueBar,
			})

			local alphaBar, alphaCursor
			if cfg.Transparency ~= nil then
				alphaBar = New("Frame", {
					BackgroundColor3 = theme.ElementBackground,
					Size = UDim2.new(1, 0, 0, 14),
					ZIndex = 21,
					LayoutOrder = 3,
					Parent = popup,
				})
				Round(alphaBar, 4)
				alphaCursor = New("Frame", {
					BackgroundColor3 = Color3.new(1,1,1),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.new(0, 4, 1, 4),
					ZIndex = 22,
					Parent = alphaBar,
				})
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
				if alphaCursor then
					alphaCursor.Position = UDim2.new(1 - Colorpicker.Transparency, 0, 0.5, 0)
					alphaBar.BackgroundColor3 = Colorpicker.Value
				end
			end
			Render()

			function Colorpicker:OnChanged(fn)
				Colorpicker.Changed:Connect(fn)
			end

			function Colorpicker:SetValueRGB(color)
				Colorpicker.Value = color
				h, s, v = Color3.toHSV(color)
				Render()
				Colorpicker.Changed:Fire()
			end

			local function Commit()
				Colorpicker.Value = Color3.fromHSV(h, s, v)
				Render()
				Colorpicker.Changed:Fire()
			end

			local draggingSV, draggingHue, draggingAlpha = false, false, false

			svBox.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingSV = true end
			end)
			hueBar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingHue = true end
			end)
			if alphaBar then
				alphaBar.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingAlpha = true end
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
					Colorpicker.Changed:Fire()
				end
			end)

			swatch.MouseButton1Click:Connect(function()
				popup.Visible = not popup.Visible
			end)

			NovaUI.Options[id] = Colorpicker
			return Colorpicker
		end

		--- Tab:AddKeybind(id, { Title, Mode, Default, Callback, ChangedCallback })
		function Tab:AddKeybind(id, cfg)
			local card = BaseCard(46)
			TitleDesc(card, cfg.Title, cfg.Description, 100)

			local keyBtn = New("TextButton", {
				Text = tostring(cfg.Default or "None"),
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextColor3 = theme.Text,
				BackgroundColor3 = theme.ElementBackgroundHover,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.new(0, 90, 0, 26),
				Parent = card,
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

			NovaUI.Options[id] = Keybind
			return Keybind
		end

		--- Tab:AddInput(id, { Title, Default, Placeholder, Numeric, Finished, Callback })
		function Tab:AddInput(id, cfg)
			local card = BaseCard(46)
			TitleDesc(card, cfg.Title, cfg.Description, 130)

			local box = New("Frame", {
				BackgroundColor3 = theme.ElementBackgroundHover,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.new(0, 120, 0, 26),
				Parent = card,
			})
			Round(box, 6)
			Pad(box, 8, 0, 8, 0)

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

			NovaUI.Options[id] = Input
			return Input
		end

		--=====================================================================
		-- SECTION / ROW — the grouped, two-column settings-list layout
		--=====================================================================

		--- Tab:AddSection({ Title, Column }) -> Section
		--- Column is 1 or 2 (default 1), placing the section in the left or
		--- right column, mirroring a two-panel settings layout.
		function Tab:AddSection(sectionCfg)
			sectionCfg = sectionCfg or {}
			local columnIndex = sectionCfg.Column or 1

			if not Tab._columnsFrame then
				Tab._columnsFrame = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = 999,
					Parent = page,
				})
				New("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 24),
					Parent = Tab._columnsFrame,
				})
				Tab._columns = {}
			end

			if not Tab._columns[columnIndex] then
				local col = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(0.5, -12, 0, 0),
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

			--- Section:AddRow(id, {
			---   Title, Type = "toggle"|"dropdown"|"slider"|"text",
			---   Elevated = true,       -- renders as a raised card (use for the section's main on/off row)
			---   Bold = true,           -- bold label even when not Elevated
			---   Menu = true,           -- adds a "..." icon before the control (Elevated rows only)
			---   -- toggle: Default
			---   -- dropdown: Values, Multi, Default
			---   -- slider: Default, Min, Max, Rounding, Suffix, Callback
			---   -- text: Value (static, non-interactive)
			--- })
			function Section:AddRow(id, rowCfg)
				rowCfg = rowCfg or {}
				local rowType = rowCfg.Type or "toggle"
				local elevated = rowCfg.Elevated and true or false
				local rowHeight = elevated and 44 or 30

				Section._rowCount = Section._rowCount + 1
				local row = New("Frame", {
					BackgroundColor3 = theme.ElementBackground,
					BackgroundTransparency = elevated and 0 or 1,
					Size = UDim2.new(1, 0, 0, rowHeight),
					LayoutOrder = Section._rowCount,
					Parent = sectionFrame,
				})
				if elevated then
					Round(row, 8)
					Pad(row, 12, 0, 12, 0)
				end

				table.insert(Window._searchRows, { Instance = row, TitleLower = (rowCfg.Title or ""):lower(), TabIndex = index })

				local labelBold = elevated or rowCfg.Bold
				local rightControlWidth = (rowType == "slider") and 150 or (rowType == "dropdown" and 110 or 38)
				if rowCfg.Menu then rightControlWidth = rightControlWidth + 24 end

				New("TextLabel", {
					Text = rowCfg.Title or "",
					Font = labelBold and Enum.Font.GothamMedium or Enum.Font.Gotham,
					TextSize = elevated and 13 or 12.5,
					TextColor3 = labelBold and theme.Text or theme.SubText,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
					Position = UDim2.new(0, elevated and 0 or 0, 0, 0),
					Size = UDim2.new(1, -(rightControlWidth + 10), 1, 0),
					Parent = row,
				})

				local controlHolder = New("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, elevated and 0 or 0, 0.5, 0),
					Size = UDim2.new(0, rightControlWidth, 1, 0),
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
						LayoutOrder = 1,
						Parent = controlHolder,
					})
					if rowCfg.MenuCallback then
						menuBtn.MouseButton1Click:Connect(rowCfg.MenuCallback)
					end
				end

				if rowType == "toggle" then
					local track = New("Frame", {
						BackgroundColor3 = theme.ElementBackgroundHover,
						Size = UDim2.new(0, 36, 0, 18),
						LayoutOrder = 2,
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

					local Toggle = { Value = rowCfg.Default or false, Changed = Signal.new() }
					local function RenderToggle(animate)
						local on = Toggle.Value
						local trackColor = on and theme.Accent or theme.ElementBackgroundHover
						local knobPos = on and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
						if animate then
							Tween(track, { BackgroundColor3 = trackColor }, 0.15)
							Tween(knob, { Position = knobPos }, 0.15)
						else
							track.BackgroundColor3 = trackColor
							knob.Position = knobPos
						end
					end
					RenderToggle(false)
					function Toggle:SetValue(value)
						Toggle.Value = value
						RenderToggle(true)
						Toggle.Changed:Fire(value)
						if rowCfg.Callback then rowCfg.Callback(value) end
					end
					function Toggle:OnChanged(fn) Toggle.Changed:Connect(fn) end
					clickArea.MouseButton1Click:Connect(function() Toggle:SetValue(not Toggle.Value) end)

					if id then NovaUI.Options[id] = Toggle end
					return Toggle

				elseif rowType == "dropdown" then
					local values = rowCfg.Values or {}
					local multi = rowCfg.Multi or false

					local ddBtn = New("TextButton", {
						Text = "",
						Font = Enum.Font.Gotham,
						TextSize = 12,
						TextColor3 = theme.SubText,
						BackgroundColor3 = theme.ElementBackgroundHover,
						AutoButtonColor = false,
						Size = UDim2.new(0, rowCfg.Menu and (rightControlWidth - 24) or rightControlWidth, 0, 26),
						LayoutOrder = 2,
						Parent = controlHolder,
					})
					Round(ddBtn, 6)
					Pad(ddBtn, 8, 0, 22, 0)
					ddBtn.TextXAlignment = Enum.TextXAlignment.Left
					ddBtn.TextTruncate = Enum.TextTruncate.AtEnd

					do
						local icon = GetIcon("chevron-down", 10)
						if icon then
							icon.AnchorPoint = Vector2.new(1, 0.5)
							icon.Position = UDim2.new(1, -6, 0.5, 0)
							icon.ImageColor3 = theme.SubText
							icon.Parent = ddBtn
						else
							New("TextLabel", {
								Text = "\226\150\190",
								Font = Enum.Font.Gotham,
								TextSize = 9,
								TextColor3 = theme.SubText,
								BackgroundTransparency = 1,
								AnchorPoint = Vector2.new(1, 0.5),
								Position = UDim2.new(1, -6, 0.5, 0),
								Size = UDim2.new(0, 10, 1, 0),
								Parent = ddBtn,
							})
						end
					end

					local listFrame = New("Frame", {
						BackgroundColor3 = theme.ElementBackgroundHover,
						Visible = false,
						ZIndex = 20,
						Size = UDim2.new(0, 180, 0, math.min(#values, 6) * 28 + 8),
						Parent = row,
					})
					Round(listFrame, 6)
					Stroke(listFrame, theme.Border, 1)
					local listScroll = New("ScrollingFrame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						CanvasSize = UDim2.new(0, 0, 0, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						ScrollBarThickness = 2,
						BorderSizePixel = 0,
						ZIndex = 20,
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
							ZIndex = 21,
							Parent = listScroll,
						})
						Round(optBtn, 4)
						Pad(optBtn, 8, 0, 8, 0)
						Dropdown._optionButtons[tostring(name)] = optBtn
						optBtn.MouseButton1Click:Connect(function()
							if multi then
								local key = tostring(name)
								local newMap = {}
								for k, v in pairs(Dropdown.Value) do newMap[k] = v end
								newMap[key] = not newMap[key]
								Dropdown:SetValue(newMap)
							else
								Dropdown:SetValue(tostring(name))
								listFrame.Visible = false
							end
						end)
					end
					ddBtn.MouseButton1Click:Connect(function()
						listFrame.Position = UDim2.new(1, 0, 1, 4)
						listFrame.AnchorPoint = Vector2.new(1, 0)
						listFrame.Visible = not listFrame.Visible
					end)
					if rowCfg.Default ~= nil then
						Dropdown:SetValue(rowCfg.Default)
					else
						RefreshButton()
					end

					if id then NovaUI.Options[id] = Dropdown end
					return Dropdown

				elseif rowType == "slider" then
					local min, max = rowCfg.Min or 0, rowCfg.Max or 100
					local rounding = rowCfg.Rounding or 0
					local suffix = rowCfg.Suffix or ""

					local valueLabel = New("TextLabel", {
						Text = tostring(rowCfg.Default or min) .. suffix,
						Font = Enum.Font.Gotham,
						TextSize = 12,
						TextColor3 = theme.SubText,
						TextXAlignment = Enum.TextXAlignment.Right,
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 44, 1, 0),
						LayoutOrder = 2,
						Parent = controlHolder,
					})

					local trackWidth = (rowCfg.Menu and (rightControlWidth - 24) or rightControlWidth) - 52
					local track = New("Frame", {
						BackgroundColor3 = theme.ElementBackgroundHover,
						Size = UDim2.new(0, math.max(trackWidth, 50), 0, 4),
						LayoutOrder = 3,
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

					local Slider = { Value = rowCfg.Default or min, Changed = Signal.new() }
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
						if rowCfg.Callback then rowCfg.Callback(v) end
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

				elseif rowType == "text" then
					New("TextLabel", {
						Text = rowCfg.Value or "",
						Font = Enum.Font.Gotham,
						TextSize = 12,
						TextColor3 = theme.SubText,
						TextXAlignment = Enum.TextXAlignment.Right,
						BackgroundTransparency = 1,
						LayoutOrder = 2,
						Size = UDim2.new(0, rightControlWidth, 1, 0),
						Parent = controlHolder,
					})
					return nil
				end
			end

			return Section
		end

		self._tabs[index] = Tab
		return Tab
	end

	return Window
end

return NovaUI
