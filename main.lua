--!nocheck
--[[
	Ren
	A compact, dark dashboard UI library for Roblox.

	Same API as NovaUI — CreateWindow -> AddTab -> AddSection -> AddToggle /
	AddSlider / AddDropdown / AddColorpicker / AddKeybind / AddInput /
	AddButton / AddParagraph — so a NovaUI script runs on Ren by swapping the
	require. Only the look differs: a header (brand, search, config chip,
	window controls), a horizontal tab bar underneath it, and two columns of
	section cards per tab.

		local Ren = loadstring(game:HttpGet("<raw url>/ren.luau"))()
		local Window = Ren:CreateWindow({ Title = "Ren", SubTitle = "v1.0" })
		local Combat = Window:AddTab({ Title = "Combat", Icon = "swords" })
		local Rotation = Combat:AddSection({ Title = "Rotation settings", Column = 1 })
		Rotation:AddToggle("Look", { Title = "Look", Default = true })
		Window:StartAutoLoad()

	Settings tab: every window gets one, always the last tab in the bar
	(after every tab the script adds). It carries the whole config store that lives on NovaUI's top ribbon —
	pick (= load), create, save, delete, refresh, set/clear autoload — plus
	the menu keybind and a couple of interface switches. `SettingsTab = false`
	turns it off; `Window.SettingsTab:AddSection(...)` adds your own sections.
	The header's config chip is a quick switcher onto the same store.

	Configs persist under <Folder>/Games/<GameId>/<name>.json through the
	executor's file globals. Without them (Studio) the store keeps configs in
	memory for the session, so every button still works; Configs.Persistent
	tells the two apart.

	Icons are Lucide (lucide.dev), by name: "swords", "eye", "settings"...
	The full set is the same sprite table NovaUI loads — fetched with
	game:HttpGet when the executor has it, or required from a ModuleScript
	named "RenIcons"/"LucideIcons" in ReplicatedStorage. A built-in subset
	covers everything the library draws itself plus common tab icons, so
	nothing goes blank offline. Raw asset ids / rbxassetid:// strings work
	anywhere an icon name does.

	Additions over NovaUI (all optional):
	  Section:AddRangeSlider(id, { Min, Max, Default = { lo, hi } })
	  Any element with `Menu = true` gets `.Menu`, a section that opens as a
	  settings popup from the row's "..." button (MenuTitle/MenuDescription).
	  Elements have :SetTitle / :SetDescription / :SetVisible.
	  CreateWindow({ Accent = Color3 }) recolors the accent.
	  Ren.GuiParent = <Instance> mounts windows and notifications there
	  instead of searching gethui() -> CoreGui -> PlayerGui.

	Minimizing shrinks the window into a small round logo button in the
	middle of the screen (MinimizePosition = UDim2 anchor point, default
	the screen center; MinimizedSize = px, default 40). Tap it to restore;
	drag it to move it out of the way.

	The window (or the minimized button) turns semi-transparent while it's
	dragged: DragTransparency = 0..1, default 0.5; false turns it off.

	Floating frames are separate draggable panels that stay up while the menu
	is hidden. Create them after the window so they pick up its Accent; the X
	only hides one (:SetVisible(true) brings it back, :OnClose(fn) tells you),
	and closing the window destroys them. A frame fits its content up to
	MaxHeight (default 380, the window's height), then scrolls.

		local Status = Ren:CreateStatus({ Status = "Running" })
		Status:SetStatus("Paused")          -- "Running", "Paused" or "Error"
		Status:Log("Waiting for coins")     -- Status:Log(text, "Error") tints it

		local Stats = Ren:CreateStatistics({ Title = "Overflow statistics" })
		local Hatches = Stats:AddStat({ Title = "Hatches", Icon = "egg", Value = 0 })
		local Rate = Stats:AddGraph({ Title = "Coins / min", Icon = "chart-line" })
		local Pets = Stats:AddImageHolder({ Title = "Pets", Icon = "paw-print" })
		local Notes = Stats:AddText({ Title = "Session", Content = "Started." })
		Hatches:Increment(3)
		Rate:Push(1200)
		Pets:AddImage({ Image = "rbxassetid://123", Title = "Dog", Count = 3 })
		Notes:SetContent("Hatching.")
--]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")

local LocalPlayer = Players.LocalPlayer

local Ren = {}
Ren.Version = "1.0.0"
Ren.Options = {}
Ren.Unloaded = false
Ren.ReducedEffects = false

--=============================================================================
-- THEME
--=============================================================================

local Themes = {
	Dark = {
		-- The logo's average blue (its gradient runs #71C2FE -> #003FD5).
		Accent = Color3.fromRGB(64, 148, 244),
		Header = Color3.fromRGB(18, 18, 24),
		Background = Color3.fromRGB(14, 14, 19),
		SectionBackground = Color3.fromRGB(21, 21, 28),
		ElementBackground = Color3.fromRGB(29, 29, 38),
		ElementBackgroundHover = Color3.fromRGB(38, 38, 49),
		PopupBackground = Color3.fromRGB(20, 20, 27),
		Text = Color3.fromRGB(236, 236, 244),
		SubText = Color3.fromRGB(142, 142, 160),
		DimText = Color3.fromRGB(92, 92, 110),
		Border = Color3.fromRGB(33, 33, 43),
		Divider = Color3.fromRGB(27, 27, 35),
		Knob = Color3.fromRGB(62, 62, 78),
		Danger = Color3.fromRGB(255, 92, 102),
		Warning = Color3.fromRGB(245, 190, 80),
		Success = Color3.fromRGB(110, 220, 120),
	},
}

-- Everything accent-derived is computed rather than stored, so a custom
-- Accent (CreateWindow's `Accent`) carries through every tint at once.
local function DeriveTheme(base, accent)
	local theme = table.clone(base)
	theme.Accent = accent or base.Accent
	theme.AccentHover = theme.Accent:Lerp(Color3.new(1, 1, 1), 0.18)
	theme.AccentTrack = theme.ElementBackground:Lerp(theme.Accent, 0.22)
	theme.AccentSoft = theme.PopupBackground:Lerp(theme.Accent, 0.16)
	return theme
end

Ren.Themes = Themes
Ren.Theme = DeriveTheme(Themes.Dark)
-- Default brand mark (header + minimized button); CreateWindow's `Logo`
-- overrides it per window with an image or a Lucide icon name.
Ren.Logo = "rbxassetid://122702287858040"

local Fonts
do
	local family = "rbxasset://fonts/families/GothamSSm.json"
	Fonts = {
		Regular = Font.new(family, Enum.FontWeight.Regular),
		Medium = Font.new(family, Enum.FontWeight.Medium),
		Bold = Font.new(family, Enum.FontWeight.Bold),
	}
end

--=============================================================================
-- UTILITIES
--=============================================================================

local function New(className, props, children)
	local inst = Instance.new(className)
	-- New GuiObjects come with a 1px border in (27, 42, 53); on any opaque,
	-- square-cornered frame (the tab bar) it shows as a bluish line. Off by
	-- default; a props table can still turn it back on.
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
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

-- `corners` squares off individual corners, e.g. { BottomLeft = 0 }.
local function Round(inst, radius, corners)
	local corner = New("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = inst })
	if corners then
		for key, value in pairs(corners) do
			pcall(function()
				corner[key .. "Radius"] = UDim.new(0, value)
			end)
		end
	end
	return corner
end

local function Pill(inst)
	New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = inst })
	return inst
end

local function Stroke(inst, color, thickness, transparency)
	return New("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
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

local function List(parent, props)
	local layout = New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder })
	for prop, value in pairs(props or {}) do
		layout[prop] = value
	end
	layout.Parent = parent
	return layout
end

local function Row(parent, padding, align)
	return List(parent, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, padding or 0),
	})
end

local function Label(props)
	local merged = {
		BackgroundTransparency = 1,
		FontFace = Fonts.Regular,
		TextSize = 12,
		TextColor3 = Ren.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for prop, value in pairs(props) do
		merged[prop] = value
	end
	return New("TextLabel", merged)
end

local EASE = Enum.EasingStyle.Quad
local EASE_SOFT = Enum.EasingStyle.Quint

local function Tween(inst, props, time, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(time or 0.15, style or EASE, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Fades a whole subtree out (text, images, fills, strokes) so a closing card
-- dissolves instead of popping when it's destroyed a moment later.
local function FadeOutTree(root, duration)
	duration = duration or 0.12
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("GuiObject") and inst.BackgroundTransparency < 1 then
			Tween(inst, { BackgroundTransparency = 1 }, duration)
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			Tween(inst, { TextTransparency = 1 }, duration)
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			Tween(inst, { ImageTransparency = 1 }, duration)
		elseif inst:IsA("UIStroke") then
			Tween(inst, { Transparency = 1 }, duration)
		end
	end
end

-- Movement/end are tracked on the global UserInputService rather than the
-- handle: the cursor leaves a small handle almost immediately during a drag,
-- and the handle's own InputChanged stops firing the moment it does.
-- onDrag(true) fires once the pointer has actually moved a few pixels (a
-- plain click or tap never triggers it), onDrag(false) when that drag ends.
local function MakeDraggable(frame, handle, track, canDrag, onDrag)
	local dragging, moved, dragStart, startPos = false, false, nil, nil
	track(handle.InputBegan:Connect(function(input)
		if canDrag and not canDrag() then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = input.Position
			startPos = frame.Position
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			if not moved and delta.Magnitude >= 3 then
				moved = true
				if onDrag then onDrag(true) end
			end
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragging and moved and onDrag then onDrag(false) end
			dragging = false
			moved = false
		end
	end))
end

-- See-through while dragged, so what's behind the frame stays visible
-- (`transparency` defaults to 0.5; false turns it off). The frame is lifted
-- into a screen-sized CanvasGroup for the drag only, so it fades as one flat
-- layer, stroke and shadow included; living in a CanvasGroup all the time
-- would render it through a texture. Returns MakeDraggable's onDrag.
local function DragFade(frame, gui, transparency)
	if transparency == nil then transparency = 0.5 end
	if not transparency then return nil end
	local ok, group = pcall(New, "CanvasGroup", {
		Name = "DragFade",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = gui,
	})
	if not ok then return nil end
	local token = 0
	return function(dragging)
		token = token + 1
		local current = token
		if dragging then
			group.ZIndex = frame.ZIndex
			group.Visible = true
			frame.Parent = group
			Tween(group, { GroupTransparency = transparency }, 0.12)
		else
			Tween(group, { GroupTransparency = 0 }, 0.12)
			task.delay(0.12, function()
				if current ~= token or not gui.Parent then return end
				frame.Parent = gui
				group.Visible = false
			end)
		end
	end
end

-- Every shadow is remembered (weakly) so SetReducedEffects can switch the
-- ones that already exist, not just the ones created afterwards.
local Shadows = setmetatable({}, { __mode = "k" })
local function AddShadow(parent, opts)
	opts = opts or {}
	local ok, shadow = pcall(function()
		return New("UIShadow", {
			Color = opts.Color or Color3.new(0, 0, 0),
			Transparency = opts.Transparency or 0.5,
			Offset = UDim2.fromOffset(0, opts.OffsetY or 0),
			BlurRadius = UDim.new(0, opts.Blur or 16),
			Enabled = not Ren.ReducedEffects,
			Parent = parent,
		})
	end)
	if ok and shadow then
		Shadows[shadow] = true
		return shadow
	end
	return nil
end

function Ren:SetReducedEffects(enabled)
	Ren.ReducedEffects = enabled and true or false
	for shadow in pairs(Shadows) do
		if shadow.Parent then
			shadow.Enabled = not Ren.ReducedEffects
		end
	end
end

-- Soft round glow behind a logo. UIShadow takes its element's shape, and an
-- ImageLabel's shape is its square box (a square glow), so the shadow goes
-- on a transparent round frame underneath instead — which also leaves a
-- non-round logo uncropped.
local function AddGlow(parent, size, color)
	local glow = New("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = parent.ZIndex,
		Parent = parent,
	})
	Pill(glow)
	AddShadow(glow, { Color = color, Transparency = 0.78, Blur = 8 })
	return glow
end

local function PopIn(frame)
	local scale = frame:FindFirstChildOfClass("UIScale") or New("UIScale", { Parent = frame })
	scale.Scale = 0.96
	Tween(scale, { Scale = 1 }, 0.12, EASE)
end

local function TextWidth(text, size)
	local ok, width = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.GothamMedium, Vector2.new(2000, 100)).X
	end)
	return ok and width or #text * size * 0.6
end

-- Callbacks run on their own thread: one that yields forever (a farm loop)
-- or errors can't strand the UI code that called it.
local function SafeCall(fn, ...)
	if type(fn) == "function" then
		task.spawn(fn, ...)
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _listeners = {} }, Signal)
end

function Signal:Connect(fn)
	table.insert(self._listeners, fn)
	local listeners = self._listeners
	return {
		Disconnect = function()
			local index = table.find(listeners, fn)
			if index then table.remove(listeners, index) end
		end,
	}
end

function Signal:Fire(...)
	for _, fn in ipairs(table.clone(self._listeners)) do
		task.spawn(fn, ...)
	end
end

-- gethui() on executors that have it, then CoreGui, then PlayerGui — each
-- tried for real, since a LocalScript can *see* CoreGui but not parent to it.
-- Ren.GuiParent (or CreateWindow's Parent) skips the search.
local function MountGui(gui, preferred)
	preferred = preferred or Ren.GuiParent
	if preferred then
		gui.Parent = preferred
		return
	end
	local candidates = {}
	local okHui, hui = pcall(function() return gethui and gethui() end)
	if okHui and typeof(hui) == "Instance" then table.insert(candidates, hui) end
	table.insert(candidates, game:GetService("CoreGui"))
	if LocalPlayer then
		local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
		if playerGui then table.insert(candidates, playerGui) end
	end
	for _, parent in ipairs(candidates) do
		if pcall(function() gui.Parent = parent end) then
			return
		end
	end
end

--=============================================================================
-- ICONS (Lucide)
--=============================================================================

local LUCIDE_URL = "https://raw.githubusercontent.com/zzmmr/icons/refs/heads/main/main"

-- Built-in subset of the same 48px Lucide sheets: name = {sheet, x, y}.
local LUCIDE_SHEETS = { 16898613699, 16898613353, 16898612819, 16898613869, 16898613613, 16898613777, 16898613044, 16898612629, 16898613509 }
local LUCIDE_FALLBACK = {
	search={1,918,857}, folder={2,404,967}, ["folder-open"]={2,820,759}, ["chevron-down"]={3,196,918}, ["chevron-up"]={3,710,918}, ["chevron-right"]={3,869,759},
	["chevron-left"]={3,404,967}, x={4,869,906}, minus={5,771,196}, ["maximize-2"]={5,820,514}, ["minimize-2"]={5,967,0}, check={3,710,869},
	ellipsis={2,771,49}, settings={6,771,257}, ["settings-2"]={6,0,771}, save={1,918,453}, ["file-plus"]={2,918,49}, ["trash-2"]={4,257,918},
	["refresh-cw"]={1,404,869}, zap={4,918,906}, download={7,820,906}, upload={4,612,869}, ["arrow-right"]={8,453,820}, ["grip-vertical"]={9,0,869},
	bell={3,820,257}, info={9,612,869}, ["circle-alert"]={3,918,808}, ["triangle-alert"]={4,967,0}, ["circle-check"]={3,869,955}, user={4,661,869},
	keyboard={9,453,820}, palette={5,453,918}, ["sliders-horizontal"]={6,820,355}, ["layout-grid"]={9,918,404}, copy={7,918,612}, swords={6,967,759},
	sword={6,710,967}, footprints={2,918,710}, eye={2,771,563}, ["eye-off"]={2,820,514}, monitor={5,404,820}, layers={9,98,967},
	menu={5,49,820}, ["shopping-cart"]={6,869,257}, crosshair={7,453,869}, target={4,514,771}, shield={6,869,0}, wrench={4,820,906},
	home={9,820,147}, ["gamepad-2"]={2,710,967}, star={6,967,147}, sparkles={6,918,49}, bolt={3,306,820}, wifi={4,869,808},
	gauge={2,771,955}, clock={7,771,661}, ["map-pin"]={5,820,257}, list={9,869,808}, ["mouse-pointer-click"]={5,771,710}, power={1,820,147},
	pencil={1,820,257}, plus={1,257,918}, pin={1,918,0}, box={3,771,196}, ["move-diagonal-2"]={5,967,49}, ["log-out"]={9,820,955},
	globe={9,771,563}, music={5,967,563}, rocket={1,918,147}, bot={3,869,98}, users={4,967,98}, key={9,869,404},
	lock={9,918,857}, cpu={7,196,869}, terminal={4,820,257}, code={7,355,869}, ghost={2,869,906}, ["wand-sparkles"]={4,453,918},
	flame={2,967,306}, heart={9,661,771}, skull={6,49,869}, radar={1,820,404}, ["scan-eye"]={1,869,759}, ["person-standing"]={1,563,771},
	package={5,918,196}, hammer={9,306,820}, car={3,918,147}, plane={1,98,820}, timer={4,918,0}, compass={7,514,967},
	bug={3,257,967}, paintbrush={5,918,453}, image={9,306,918}, ["volume-2"]={4,771,808}, activity={8,514,771},
	egg={2,514,771}, coins={7,869,612}, ["paw-print"]={1,771,257}, ["line-chart"]={9,196,918}, ["trending-up"]={4,514,918}, gem={2,918,857},
	trophy={4,820,147}, ["scroll-text"]={1,967,759}, hourglass={9,49,918}, wallet={4,147,967},
}
local ICON_ALIASES = { house = "home", cog = "settings", close = "x", ["more-horizontal"] = "ellipsis", gear = "settings", ["chart-line"] = "line-chart" }

local FallbackIcons
do
	local bucket = {}
	for name, entry in pairs(LUCIDE_FALLBACK) do
		bucket[name] = { LUCIDE_SHEETS[entry[1]], { 48, 48 }, { entry[2], entry[3] } }
	end
	FallbackIcons = { ["48px"] = bucket }
end

-- The sprite table is a plain Lua table literal, so where loadstring is
-- missing it's read with patterns instead of executed.
local function ParseIconSource(source)
	if type(loadstring) == "function" then
		local okLoad, chunk = pcall(loadstring, source)
		if okLoad and type(chunk) == "function" then
			local okRun, result = pcall(chunk)
			if okRun and type(result) == "table" then return result end
		end
	end
	local buckets = {}
	for position, key in source:gmatch('()%["(%d+px)"%]%s*=%s*{') do
		table.insert(buckets, { position, key })
	end
	local result = {}
	for i, bucketInfo in ipairs(buckets) do
		local chunkEnd = buckets[i + 1] and (buckets[i + 1][1] - 1) or #source
		local chunk = source:sub(bucketInfo[1] + #bucketInfo[2] + 4, chunkEnd)
		local bucket = {}
		for key, id, w, h, x, y in chunk:gmatch('([%w_%-%[%]"]+)%s*=%s*{%s*(%d+)%s*,%s*{%s*(%d+)%s*,%s*(%d+)%s*}%s*,%s*{%s*(%d+)%s*,%s*(%d+)%s*}%s*}') do
			key = key:gsub('^%["', ""):gsub('"%]$', "")
			bucket[key] = { tonumber(id), { tonumber(w), tonumber(h) }, { tonumber(x), tonumber(y) } }
		end
		result[bucketInfo[2]] = bucket
	end
	return next(result) and result or nil
end

local function LoadLucide()
	for _, name in ipairs({ "RenIcons", "LucideIcons" }) do
		local module = ReplicatedStorage:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then return result end
		end
	end
	local ok, source = pcall(function() return game:HttpGet(LUCIDE_URL) end)
	if ok and type(source) == "string" and #source > 1000 then
		return ParseIconSource(source)
	end
	return nil
end

Ren.Icons = LoadLucide()

--- Ren:SetIcons(table) — swap in your own icon table, same shape as NovaUI's:
--- { ["48px"] = { name = { assetId, { w, h }, { x, y } } }, ... }
function Ren:SetIcons(iconTable)
	Ren.Icons = iconTable
end

local function PickIconSizeKey(sheet, targetSize)
	local bestKey, bestNum, largestKey, largestNum
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

local function LookupIcon(sheet, name, size)
	if type(sheet) ~= "table" then return nil end
	local key = PickIconSizeKey(sheet, size)
	local bucket = key and sheet[key]
	if type(bucket) == "table" and bucket[name] then
		return bucket[name]
	end
	for _, other in pairs(sheet) do
		if type(other) == "table" and other[name] then
			return other[name]
		end
	end
	return nil
end

-- ImageLabel for `name` (Lucide name, raw asset id, or rbxassetid:// /
-- http(s):// string), or nil when it can't be found anywhere.
local function GetIcon(name, size)
	if name == nil or name == "" then return nil end
	size = size or 16

	local direct
	if type(name) == "number" then
		direct = "rbxassetid://" .. tostring(name)
	elseif type(name) == "string" and (name:match("^rbxassetid://") or name:match("^rbxasset://") or name:match("^rbxthumb://") or name:match("^https?://")) then
		direct = name
	end
	if direct then
		return New("ImageLabel", {
			Image = direct,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
		})
	end

	name = ICON_ALIASES[name] or name
	local entry = LookupIcon(Ren.Icons, name, size) or LookupIcon(FallbackIcons, name, size)
	if not entry or not entry[1] then return nil end

	local nativeW = (entry[2] and entry[2][1]) or size
	local nativeH = (entry[2] and entry[2][2]) or size
	local scale = size / math.max(nativeW, nativeH)
	local label = New("ImageLabel", {
		Image = "rbxassetid://" .. tostring(entry[1]),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(math.floor(nativeW * scale + 0.5), math.floor(nativeH * scale + 0.5)),
	})
	if entry[3] then
		label.ImageRectOffset = Vector2.new(entry[3][1] or 0, entry[3][2] or 0)
		label.ImageRectSize = Vector2.new(nativeW, nativeH)
	end
	return label
end

local function Icon(name, size, color, props)
	local image = GetIcon(name, size)
	if not image then return nil end
	if color then image.ImageColor3 = color end
	for prop, value in pairs(props or {}) do
		image[prop] = value
	end
	return image
end

--=============================================================================
-- FILESYSTEM
--=============================================================================

-- Executor globals; under Studio they read as nil and the config store falls
-- back to keeping configs in memory.
local FS = {
	IsFolder = isfolder,
	MakeFolder = makefolder,
	ListFiles = listfiles,
	IsFile = isfile,
	ReadFile = readfile,
	WriteFile = writefile,
	DeleteFile = delfile,
}
FS.Ready = type(FS.IsFolder) == "function"
	and type(FS.MakeFolder) == "function"
	and type(FS.ListFiles) == "function"
	and type(FS.IsFile) == "function"
	and type(FS.ReadFile) == "function"
	and type(FS.WriteFile) == "function"

-- makefolder isn't recursive everywhere, so build the path one level at a time.
local function EnsureFolder(path)
	if not FS.Ready then return false end
	local built
	for segment in path:gmatch("[^/]+") do
		built = built and (built .. "/" .. segment) or segment
		if not FS.IsFolder(built) then
			if not pcall(FS.MakeFolder, built) then return false end
		end
	end
	return FS.IsFolder(path) and true or false
end

--=============================================================================
-- OPTIONS / CONFIG SERIALIZATION
--=============================================================================

local function RegisterOption(id, opt)
	if id == nil then return end
	if Ren.Options[id] ~= nil then
		warn(string.format("[Ren] duplicate option id %q — only the last element registered under it will save/load", tostring(id)))
	end
	Ren.Options[id] = opt
end

local function SerializeValue(value)
	if typeof(value) == "Color3" then
		return { __type = "Color3", R = value.R, G = value.G, B = value.B }
	elseif typeof(value) == "EnumItem" then
		return { __type = "EnumItem", EnumType = (tostring(value.EnumType):gsub("^Enum%.", "")), Name = value.Name }
	elseif typeof(value) == "table" then
		-- Multi-select map -> sorted list of option names; SetValue resolves
		-- the names back to live entries on the way in.
		local names = {}
		for option, on in pairs(value) do
			if on then table.insert(names, tostring(option)) end
		end
		table.sort(names)
		return names
	elseif value ~= nil and typeof(value) ~= "string" and typeof(value) ~= "number" and typeof(value) ~= "boolean" then
		return tostring(value)
	end
	return value
end

local function DeserializeValue(value)
	if typeof(value) == "table" and value.__type == "Color3" then
		return Color3.new(value.R or 0, value.G or 0, value.B or 0)
	elseif typeof(value) == "table" and value.__type == "EnumItem" then
		local enumType = Enum[value.EnumType]
		return enumType and enumType[value.Name]
	elseif typeof(value) == "table" and value.__type == "Range" then
		return { Min = value.Min, Max = value.Max }
	end
	return value
end

--- Ren:ExportConfig() -> id -> JSON-safe value for every registered option.
function Ren:ExportConfig()
	local data = {}
	for id, opt in pairs(Ren.Options) do
		if opt.Serialize then
			data[id] = opt:Serialize()
		else
			data[id] = SerializeValue(opt.Value)
		end
	end
	return data
end

function Ren:ExportConfigJSON()
	return HttpService:JSONEncode(Ren:ExportConfig())
end

--- Ren:ApplyConfig(data) — a table from ExportConfig or its JSON string.
--- Each option is pushed on its own thread (sorted id order), so a callback
--- that yields or errors can't strand the options after it.
function Ren:ApplyConfig(data)
	if type(data) == "string" then
		local ok, decoded = pcall(function() return HttpService:JSONDecode(data) end)
		if not ok or type(decoded) ~= "table" then return false end
		data = decoded
	end
	if type(data) ~= "table" then return false end

	local ids = {}
	for id in pairs(data) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)

	for _, id in ipairs(ids) do
		local opt = Ren.Options[id]
		if opt then
			local value = DeserializeValue(data[id])
			task.spawn(function()
				if typeof(value) == "Color3" and opt.SetValueRGB then
					opt:SetValueRGB(value)
				elseif opt.SetValue then
					opt:SetValue(value)
				end
			end)
		end
	end
	return true
end

--=============================================================================
-- KEYBIND HELPERS
--=============================================================================

local MOUSE_BUTTON_LABELS = {
	[Enum.UserInputType.MouseButton1] = "Mouse1",
	[Enum.UserInputType.MouseButton2] = "Mouse2",
	[Enum.UserInputType.MouseButton3] = "Mouse3",
}

local KEY_SHORT = {
	LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
	LeftAlt = "LAlt", RightAlt = "RAlt", LeftSuper = "LWin", RightSuper = "RWin", Return = "Enter",
	Backspace = "Bksp", PageUp = "PgUp", PageDown = "PgDn", Insert = "Ins", Delete = "Del",
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	Backquote = "`", Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]", Semicolon = ";",
	Quote = "'", Comma = ",", Period = ".", Slash = "/", BackSlash = "\\",
}

local function KeybindDisplayName(value)
	if value == nil then return "None" end
	if typeof(value) == "EnumItem" then
		if value.EnumType == Enum.KeyCode then return KEY_SHORT[value.Name] or value.Name end
		if value.EnumType == Enum.UserInputType then return MOUSE_BUTTON_LABELS[value] or value.Name end
	end
	return tostring(value)
end

local function KeybindMatches(value, input)
	if typeof(value) ~= "EnumItem" then return false end
	if value.EnumType == Enum.KeyCode then
		return input.KeyCode == value
	elseif value.EnumType == Enum.UserInputType then
		return input.UserInputType == value
	end
	return false
end

local KEYBIND_MODES = { toggle = "Toggle", hold = "Hold", always = "Always" }
local function NormalizeKeybindMode(mode, id)
	if mode == nil then return "Toggle" end
	local resolved = KEYBIND_MODES[(tostring(mode):gsub("^%s+", ""):gsub("%s+$", ""):lower())]
	if resolved then return resolved end
	warn(string.format("[Ren] Keybind %q: unknown Mode %q — using \"Toggle\".", tostring(id), tostring(mode)))
	return "Toggle"
end

-- Set while any keybind is capturing (and for a beat after), so the window's
-- own hotkeys don't fire on the very key press that's being bound.
local KeybindCapture = { Active = 0, LastEnded = 0 }
local function CapturingKeybind()
	return KeybindCapture.Active > 0 or (os.clock() - KeybindCapture.LastEnded) < 0.15
end

-- The default chat box lives in CoreGui, out of GetFocusedTextBox's sight.
local function ChatInputFocused()
	local ok, focused = pcall(function()
		return TextChatService.ChatInputBarConfiguration.IsFocused
	end)
	return ok and focused == true
end

--=============================================================================
-- NOTIFICATIONS
--=============================================================================

local NotifHolder
local NotifCounter = 0

local function EnsureNotifHolder()
	if NotifHolder and NotifHolder.Parent and NotifHolder.Parent.Parent then
		return NotifHolder
	end
	local gui = New("ScreenGui", {
		Name = "Ren_Notifications",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
	})
	MountGui(gui)
	NotifHolder = New("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.new(0, 290, 1, -32),
		Parent = gui,
	})
	List(NotifHolder, {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
	})
	return NotifHolder
end

--- Ren:Notify({ Title, Content, SubContent, Duration, Icon })
function Ren:Notify(config)
	config = config or {}
	local theme = Ren.Theme
	local holder = EnsureNotifHolder()
	NotifCounter = NotifCounter + 1

	-- The slot sits in the list layout; the card inside it slides, since the
	-- layout owns the slot's Position and would cancel any tween on it.
	local slot = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = NotifCounter,
		Parent = holder,
	})
	local card = New("Frame", {
		BackgroundColor3 = theme.PopupBackground,
		Position = UDim2.fromOffset(320, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = slot,
	})
	Round(card, 10)
	Stroke(card, theme.Border, 1)
	local shadow = AddShadow(card, { Transparency = 1, OffsetY = 6, Blur = 18 })

	local iconBox = New("Frame", {
		BackgroundColor3 = theme.AccentSoft,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(32, 32),
		Parent = card,
	})
	Round(iconBox, 8)
	Icon(config.Icon or "bell", 16, theme.Accent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = iconBox,
	})

	local column = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(56, 0),
		Size = UDim2.new(1, -84, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	Pad(column, 0, 12, 0, 12)
	List(column, { Padding = UDim.new(0, 3) })
	Label({
		Text = config.Title or "Notification",
		FontFace = Fonts.Medium,
		TextSize = 13,
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
		Parent = column,
	})
	if config.Content then
		Label({
			Text = config.Content,
			TextSize = 12,
			TextColor3 = theme.SubText,
			TextWrapped = true,
			RichText = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = column,
		})
	end
	if config.SubContent then
		Label({
			Text = config.SubContent,
			TextSize = 11,
			TextColor3 = theme.DimText,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3,
			Parent = column,
		})
	end

	local closeBtn = New("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(20, 20),
		Parent = card,
	})
	Icon("x", 12, theme.DimText, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = closeBtn,
	})

	-- Inside the laid-out column rather than pinned to the card's bottom
	-- edge: a Scale-Y position inside an AutomaticSize.Y card is a circular
	-- size dependency.
	local progress
	if config.Duration then
		local track = New("Frame", {
			BackgroundColor3 = theme.ElementBackground,
			Size = UDim2.new(1, 0, 0, 2),
			LayoutOrder = 99,
			Parent = column,
		})
		Pill(track)
		progress = New("Frame", {
			BackgroundColor3 = theme.Accent,
			Size = UDim2.fromScale(1, 1),
			Parent = track,
		})
		Pill(progress)
		New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 4), LayoutOrder = 98, Parent = column })
	end

	local dismissed = false
	local function Dismiss()
		if dismissed or not card.Parent then return end
		dismissed = true
		Tween(card, { Position = UDim2.fromOffset(320, 0) }, 0.2, EASE_SOFT, Enum.EasingDirection.In)
		if shadow then Tween(shadow, { Transparency = 1 }, 0.15) end
		FadeOutTree(card, 0.18)
		Tween(card, { BackgroundTransparency = 1 }, 0.18)
		task.delay(0.22, function()
			slot:Destroy()
		end)
	end
	closeBtn.MouseButton1Click:Connect(Dismiss)

	Tween(card, { Position = UDim2.fromOffset(0, 0) }, 0.32, EASE_SOFT)
	if shadow then Tween(shadow, { Transparency = 0.5 }, 0.3) end
	if config.Duration then
		Tween(progress, { Size = UDim2.fromScale(0, 1) }, config.Duration, Enum.EasingStyle.Linear)
		task.delay(config.Duration, Dismiss)
	end

	return { Dismiss = Dismiss, Instance = slot }
end

--=============================================================================
-- SHARED CHROME
--=============================================================================

local function IconButton(parent, iconName, sizePx, iconSize, hoverColor)
	local theme = Ren.Theme
	local btn = New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = theme.ElementBackground,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(sizePx, sizePx),
		Parent = parent,
	})
	Round(btn, 6)
	local image = Icon(iconName, iconSize or 14, theme.SubText, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = btn,
	})
	btn.MouseEnter:Connect(function()
		Tween(btn, { BackgroundTransparency = 0 }, 0.1)
		if image then Tween(image, { ImageColor3 = hoverColor or theme.Text }, 0.1) end
	end)
	btn.MouseLeave:Connect(function()
		Tween(btn, { BackgroundTransparency = 1 }, 0.1)
		if image then Tween(image, { ImageColor3 = theme.SubText }, 0.1) end
	end)
	local handle = { Instance = btn }
	function handle.SetIcon(name)
		if image then image:Destroy() end
		image = Icon(name, iconSize or 14, theme.SubText, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Parent = btn,
		})
	end
	return handle
end

-- A Lucide name gets the accent tint; a real image keeps its colors.
local function AddLogo(parent, image, layoutOrder)
	local isGlyph = type(image) == "string" and not image:find("://")
	local size = isGlyph and 18 or 22
	local holder = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	local logo = Icon(image, size, isGlyph and Ren.Theme.Accent or nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
		Parent = holder,
	})
	if logo then
		AddGlow(holder, size, Ren.Theme.Accent)
	end
	return holder
end

--=============================================================================
-- FLOATING FRAMES: draggable panels outside the window, so they stay up while
-- the menu is hidden. Ren:CreateStatus and Ren:CreateStatistics.
--=============================================================================

local FRAME_HEADER = 40
local FRAME_PADDING = 10
-- The window's starting height, and how tall a frame gets before it scrolls.
local WINDOW_HEIGHT = 380

-- Closing the window unloads the library, and takes these along.
local FloatingFrames = {}

-- A vertical scroller and the frame its content goes in. Inset by position
-- and size: a ScrollingFrame's Scale-sized children ignore a UIPadding.
local function Scroller(parent, insetX, insetY)
	local scroll = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Ren.Theme.ElementBackgroundHover,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Parent = parent,
	})
	local inner = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(insetX, insetY),
		Size = UDim2.new(1, -insetX * 2, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = scroll,
	})
	Pad(inner, 0, 0, 0, insetY)
	return scroll, inner
end

-- The panel both frames share: header (logo, title, close) over a body that
-- hugs its content up to MaxHeight, then scrolls.
local function CreateFloatingFrame(config, defaults)
	local theme = Ren.Theme
	local width = config.Width or defaults.Width

	-- Connections on global services outlive the ScreenGui; dropped in Destroy.
	local connections = {}
	local function Track(conn)
		table.insert(connections, conn)
		return conn
	end

	local gui = New("ScreenGui", {
		Name = defaults.Name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Under the window (100), so its popups stay above a frame.
		DisplayOrder = 90,
	})
	MountGui(gui, config.Parent)

	local main = New("Frame", {
		Name = "Main",
		-- Active so a click on the frame doesn't fall through to the game.
		Active = true,
		BackgroundColor3 = theme.Header,
		Position = config.Position or defaults.Position(width),
		Size = UDim2.fromOffset(width, FRAME_HEADER),
		ClipsDescendants = true,
		Parent = gui,
	})
	Round(main, 10)
	Stroke(main, theme.Border, 1)
	AddShadow(main, { Transparency = 0.25, OffsetY = 8, Blur = 22 })
	local scale = New("UIScale", { Parent = main })

	local header = New("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, FRAME_HEADER),
		Parent = main,
	})
	Pad(header, 14, 0, 8, 0)
	Row(header, 8)
	local logo = config.Logo
	if logo == nil then logo = defaults.Logo end
	if logo then
		AddLogo(header, logo, 1)
	end
	local title = Label({
		Text = config.Title or defaults.Title,
		FontFace = Fonts.Bold,
		TextSize = 13.5,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = header,
	})
	New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = title })

	local body = New("Frame", {
		Name = "Body",
		BackgroundColor3 = theme.Background,
		Position = UDim2.fromOffset(0, FRAME_HEADER),
		Size = UDim2.new(1, 0, 1, -FRAME_HEADER),
		Parent = main,
	})
	Round(body, 10, { TopLeft = 0, TopRight = 0 })
	New("Frame", {
		Name = "Line",
		BackgroundColor3 = theme.Divider,
		Size = UDim2.new(1, 0, 0, 1),
		Parent = body,
	})
	local _, content = Scroller(body, FRAME_PADDING, FRAME_PADDING)
	List(content, { Padding = UDim.new(0, 10) })

	local function FitHeight()
		local wanted = content.AbsoluteSize.Y / scale.Scale + FRAME_PADDING
		local limit = math.max(math.min(config.MaxHeight or WINDOW_HEIGHT, gui.AbsoluteSize.Y - 32) - FRAME_HEADER, 80)
		main.Size = UDim2.fromOffset(width, FRAME_HEADER + math.min(wanted, limit))
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(FitHeight)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(FitHeight)
	task.defer(FitHeight)

	local Frame = {
		Instance = main,
		Content = content,
		Visible = true,
		Destroyed = false,
		Closed = Signal.new(),
	}

	function Frame:SetVisible(visible)
		if Frame.Destroyed then return end
		Frame.Visible = visible and true or false
		gui.Enabled = Frame.Visible
		if Frame.Visible then PopIn(main) end
	end
	function Frame:SetTitle(text)
		title.Text = tostring(text)
	end
	--- Fires when the X closes it (the frame only hides; :SetVisible(true) brings it back).
	function Frame:OnClose(fn)
		return Frame.Closed:Connect(fn)
	end
	function Frame:Destroy()
		if Frame.Destroyed then return end
		Frame.Destroyed = true
		for _, conn in ipairs(connections) do
			if conn.Connected then conn:Disconnect() end
		end
		table.clear(connections)
		gui:Destroy()
		local index = table.find(FloatingFrames, Frame)
		if index then table.remove(FloatingFrames, index) end
	end

	if config.Closable ~= false then
		local close = IconButton(header, "x", 24, 13, theme.Danger)
		close.Instance.LayoutOrder = 3
		close.Instance.MouseButton1Click:Connect(function()
			Frame:SetVisible(false)
			Frame.Closed:Fire()
		end)
	end

	MakeDraggable(main, header, Track, nil, DragFade(main, gui, config.DragTransparency))
	table.insert(FloatingFrames, Frame)
	if config.Visible == false then
		Frame:SetVisible(false)
	else
		PopIn(main)
	end
	return Frame
end

--- Ren:CreateStatus({ Title, Status, MaxLines, LogHeight, Timestamps, Width, Position, Logo, Closable, Visible, DragTransparency, Parent })
--- Status:SetStatus("Running" | "Paused" | "Error") — any case; .Value holds it, :OnChanged(fn) follows it.
--- Status:Log(text, tint) — tint is a status name or a Color3. Status:Clear().
function Ren:CreateStatus(config)
	config = config or {}
	local theme = Ren.Theme
	local Status = CreateFloatingFrame(config, {
		Name = "Ren_Status",
		Title = "Status",
		Width = 300,
		-- Mid-left: the top-left corner is under Roblox's chat window, which
		-- swallows clicks meant for the frame's close button.
		Position = function()
			return UDim2.new(0, 16, 0.5, -114)
		end,
	})
	Status.Changed = Signal.new()

	local STATUS_NAMES = { running = "Running", paused = "Paused", error = "Error" }
	local STATUS_COLORS = { Running = theme.Success, Paused = theme.Warning, Error = theme.Danger }

	local stateRow = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = Status.Content,
	})
	Pad(stateRow, 2, 0, 2, 0)
	Row(stateRow, 8)
	local dot = New("Frame", { Size = UDim2.fromOffset(8, 8), LayoutOrder = 1, Parent = stateRow })
	Pill(dot)
	local dotGlow = AddShadow(dot, { Transparency = 0.4, Blur = 8 })
	local stateLabel = Label({
		FontFace = Fonts.Medium,
		TextSize = 13,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = stateRow,
	})

	local logCard = New("Frame", {
		BackgroundColor3 = theme.SectionBackground,
		Size = UDim2.new(1, 0, 0, config.LogHeight or 140),
		LayoutOrder = 2,
		Parent = Status.Content,
	})
	Round(logCard, 8)
	Stroke(logCard, theme.Border, 1)
	local logScroll, logList = Scroller(logCard, 10, 8)
	List(logList, { Padding = UDim.new(0, 3) })
	local emptyLabel = Label({
		Text = "No updates yet",
		TextSize = 11.5,
		TextColor3 = theme.DimText,
		Size = UDim2.new(1, 0, 0, 14),
		Parent = logList,
	})

	-- Follows new lines unless the user has scrolled up to read older ones.
	local followLog = true
	logScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		followLog = logScroll.CanvasPosition.Y >= logScroll.AbsoluteCanvasSize.Y - logScroll.AbsoluteSize.Y - 4
	end)
	logScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		if followLog then
			logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
		end
	end)

	function Status:OnChanged(fn)
		return Status.Changed:Connect(fn)
	end

	function Status:SetStatus(name)
		local resolved = STATUS_NAMES[tostring(name):lower()]
		if not resolved then
			warn(string.format("[Ren] Status: unknown status %q. Expected \"Running\", \"Paused\" or \"Error\".", tostring(name)))
			return
		end
		local changed = Status.Value ~= resolved
		-- The first one is instant, so a new frame doesn't fade in from white.
		local fade = Status.Value and 0.15 or 0
		Status.Value = resolved
		local color = STATUS_COLORS[resolved]
		stateLabel.Text = resolved
		Tween(stateLabel, { TextColor3 = color }, fade)
		Tween(dot, { BackgroundColor3 = color }, fade)
		if dotGlow then dotGlow.Color = color end
		if changed then Status.Changed:Fire(resolved) end
	end

	local lines = {}
	local lineOrder = 0
	local maxLines = config.MaxLines or 200
	local TIME_WIDTH = config.Timestamps ~= false and 54 or 0

	function Status:Log(text, tint)
		if Status.Destroyed then return end
		lineOrder = lineOrder + 1
		emptyLabel.Visible = false
		local line = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = lineOrder,
			Parent = logList,
		})
		if TIME_WIDTH > 0 then
			Label({
				Text = os.date("%H:%M:%S"),
				TextSize = 11,
				TextColor3 = theme.DimText,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.fromOffset(TIME_WIDTH, 14),
				Parent = line,
			})
		end
		local color = typeof(tint) == "Color3" and tint or STATUS_COLORS[STATUS_NAMES[tostring(tint):lower()]]
		Label({
			Text = tostring(text),
			TextSize = 11.5,
			TextColor3 = color or theme.SubText,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(TIME_WIDTH, 0),
			Size = UDim2.new(1, -TIME_WIDTH, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = line,
		})
		table.insert(lines, line)
		if #lines > maxLines then
			table.remove(lines, 1):Destroy()
		end
	end

	function Status:Clear()
		if Status.Destroyed then return end
		for _, line in ipairs(lines) do
			line:Destroy()
		end
		table.clear(lines)
		emptyLabel.Visible = true
	end

	Status:SetStatus(config.Status or "Running")
	return Status
end

-- 1000000 -> "1,000,000"; anything that isn't a number is shown as it is.
local function FormatNumber(value)
	if type(value) ~= "number" then return tostring(value) end
	local text = string.format("%.2f", value):gsub("%.?0+$", "")
	local sign, whole, fraction = text:match("^(-?)(%d+)(.*)$")
	if not whole then return text end
	whole = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. whole .. fraction
end

-- cfg.Format (a function) wins over thousands separators + cfg.Suffix.
local function FormatStat(value, cfg)
	if cfg.Format then return tostring(cfg.Format(value)) end
	return FormatNumber(value) .. (cfg.Suffix or "")
end

local GRAPH_INSET = 8
local GRAPH_FILL_STEP = 4
local STAT_HEIGHT = 58

--- Ren:CreateStatistics({ Title, Logo, Columns, Width, MaxHeight, Position, Closable, Visible, DragTransparency, Parent })
--- Subframes appear in the order they're added; consecutive stats share rows of `Columns` (default 2):
---   Stats:AddStat({ Title, Icon, Value, Color, Format, Suffix }) -> :SetValue(v) / :Increment(n) / :SetIcon(name)
---   Stats:AddGraph({ Title, Icon, Height, MaxPoints, Min, Max, Color, Data, Format, Suffix }) -> :Push(v) / :SetData(list) / :Clear()
---   Stats:AddImageHolder({ Title, Icon, Columns, TileHeight, Images }) -> :AddImage(item) / :SetImages(list) / :Clear()
---     item = { Image, Title, Count, Color } -> tile:SetImage / :SetTitle / :SetCount / :SetColor / :SetVisible / :Destroy
---   Stats:AddText({ Title, Icon, Content }) -> :SetContent(text)
--- Every subframe also has :SetTitle(text) / :SetVisible(bool) / :Destroy().
function Ren:CreateStatistics(config)
	config = config or {}
	local theme = Ren.Theme
	local Stats = CreateFloatingFrame(config, {
		Name = "Ren_Statistics",
		Title = "Statistics",
		Logo = Ren.Logo,
		Width = 340,
		Position = function(width)
			return UDim2.new(1, -(width + 16), 0, 72)
		end,
	})
	local content = Stats.Content
	local statColumns = config.Columns or 2

	local order = 0
	local function NextOrder()
		order = order + 1
		return order
	end

	local statRow, statRowCount = nil, 0

	-- The look of a tab's section: a small title over a card. Returns the
	-- subframe's handle, the card to fill and the title row.
	local function TitledCard(cfg)
		statRow = nil
		local holder = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = NextOrder(),
			Parent = content,
		})
		List(holder, { Padding = UDim.new(0, 6) })
		local head = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = 1,
			Visible = cfg.Title ~= nil,
			Parent = holder,
		})
		Pad(head, 2, 0, 2, 0)
		Row(head, 6)
		if cfg.Icon then
			Icon(cfg.Icon, 13, theme.SubText, { LayoutOrder = 1, Parent = head })
		end
		local headTitle = Label({
			Text = cfg.Title or "",
			FontFace = Fonts.Medium,
			TextSize = 12.5,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = 2,
			Parent = head,
		})
		local card = New("Frame", {
			BackgroundColor3 = theme.SectionBackground,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = holder,
		})
		Round(card, 8)
		Stroke(card, theme.Border, 1)

		local handle = { Instance = holder }
		function handle:SetTitle(text)
			headTitle.Text = tostring(text)
			head.Visible = true
		end
		function handle:SetVisible(visible)
			holder.Visible = visible and true or false
		end
		function handle:Destroy()
			holder:Destroy()
		end
		return handle, card, head
	end

	function Stats:AddStat(cfg)
		cfg = cfg or {}
		if not statRow or statRowCount >= statColumns then
			statRow = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, STAT_HEIGHT),
				LayoutOrder = NextOrder(),
				Parent = content,
			})
			Row(statRow, 8)
			statRowCount = 0
		end
		statRowCount = statRowCount + 1
		local row = statRow
		local color = cfg.Color or theme.Accent

		local card = New("Frame", {
			BackgroundColor3 = theme.SectionBackground,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = statRowCount,
			Parent = row,
		})
		New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = card })
		Round(card, 8)
		Stroke(card, theme.Border, 1)

		local head = New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 9),
			Size = UDim2.new(1, -20, 0, 14),
			Parent = card,
		})
		Row(head, 6)
		local iconSlot = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 14), LayoutOrder = 1, Visible = cfg.Icon ~= nil, Parent = head })
		local statIcon = Icon(cfg.Icon, 14, color, { Parent = iconSlot })
		local statTitle = Label({
			Text = cfg.Title or "",
			TextSize = 11.5,
			TextColor3 = theme.SubText,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = 2,
			Parent = head,
		})
		New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = statTitle })
		local valueLabel = Label({
			FontFace = Fonts.Bold,
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(10, 28),
			Size = UDim2.new(1, -20, 0, 20),
			Parent = card,
		})

		local Stat = { Instance = card }
		function Stat:SetValue(value)
			Stat.Value = value
			valueLabel.Text = FormatStat(value, cfg)
		end
		function Stat:Increment(amount)
			Stat:SetValue((tonumber(Stat.Value) or 0) + (amount or 1))
		end
		function Stat:SetTitle(text)
			statTitle.Text = tostring(text)
		end
		function Stat:SetIcon(name)
			if statIcon then statIcon:Destroy() end
			statIcon = Icon(name, 14, color, { Parent = iconSlot })
			iconSlot.Visible = statIcon ~= nil
		end
		-- A row whose stats are all hidden shouldn't leave its gap behind.
		local function RefreshRow()
			local anyVisible = false
			for _, child in ipairs(row:GetChildren()) do
				if child:IsA("Frame") and child.Visible then anyVisible = true end
			end
			row.Visible = anyVisible
		end
		function Stat:SetVisible(visible)
			card.Visible = visible and true or false
			RefreshRow()
		end
		function Stat:Destroy()
			card:Destroy()
			RefreshRow()
		end
		Stat:SetValue(cfg.Value == nil and 0 or cfg.Value)
		return Stat
	end

	function Stats:AddGraph(cfg)
		cfg = cfg or {}
		local Graph, card, head = TitledCard(cfg)
		head.Visible = true
		Pad(card, 10)
		local color = cfg.Color or theme.Accent
		local maxPoints = cfg.MaxPoints or 30
		local data = {}

		New("UIFlexItem", {
			FlexMode = Enum.UIFlexMode.Fill,
			Parent = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(), LayoutOrder = 3, Parent = head }),
		})
		local valueLabel = Label({
			FontFace = Fonts.Bold,
			TextSize = 12,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = 4,
			Parent = head,
		})

		local plot = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, cfg.Height or 80),
			Parent = card,
		})
		for _, y in ipairs({ 0, 0.5, 1 }) do
			New("Frame", {
				BackgroundColor3 = theme.Divider,
				AnchorPoint = Vector2.new(0, y),
				Position = UDim2.fromScale(0, y),
				Size = UDim2.new(1, 0, 0, 1),
				Parent = plot,
			})
		end
		local function RangeLabel(y, offset)
			return Label({
				TextSize = 10,
				TextColor3 = theme.DimText,
				AnchorPoint = Vector2.new(0, y),
				Position = UDim2.new(0, 2, y, offset),
				Size = UDim2.new(1, -4, 0, 12),
				ZIndex = 4,
				Parent = plot,
			})
		end
		local highLabel, lowLabel = RangeLabel(0, 3), RangeLabel(1, -3)
		local endDot = New("Frame", {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(6, 6),
			Visible = false,
			ZIndex = 3,
			Parent = plot,
		})
		Pill(endDot)
		AddShadow(endDot, { Color = color, Transparency = 0.4, Blur = 8 })

		-- Pools, grown as needed: a push moves these instead of rebuilding them.
		local segments, columns = {}, {}

		local function Redraw()
			if Stats.Destroyed then return end
			local w, h = plot.AbsoluteSize.X, plot.AbsoluteSize.Y
			local count = #data

			local low, high = cfg.Min or math.huge, cfg.Max or -math.huge
			for _, value in ipairs(data) do
				if not cfg.Min then low = math.min(low, value) end
				if not cfg.Max then high = math.max(high, value) end
			end
			highLabel.Text = count > 0 and FormatStat(high, cfg) or ""
			lowLabel.Text = count > 0 and FormatStat(low, cfg) or ""

			local span = high - low
			local function X(i)
				return count > 1 and (i - 1) / (count - 1) * w or w
			end
			local function Y(i)
				local t = span > 0 and math.clamp((data[i] - low) / span, 0, 1) or 0.5
				return GRAPH_INSET + (1 - t) * (h - GRAPH_INSET * 2)
			end

			-- The line: thin rotated frames between neighbouring points.
			for i = 1, count - 1 do
				local x1, y1, x2, y2 = X(i), Y(i), X(i + 1), Y(i + 1)
				local segment = segments[i]
				if not segment then
					segment = New("Frame", {
						BackgroundColor3 = color,
						AnchorPoint = Vector2.new(0.5, 0.5),
						ZIndex = 2,
						Parent = plot,
					})
					segments[i] = segment
				end
				segment.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
				segment.Size = UDim2.fromOffset(math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) + 1, 2)
				segment.Rotation = math.deg(math.atan2(y2 - y1, x2 - x1))
				segment.Visible = true
			end
			for i = math.max(count, 1), #segments do
				segments[i].Visible = false
			end

			-- The fill: narrow fading columns that follow the line's height.
			local columnCount = count > 1 and math.ceil(w / GRAPH_FILL_STEP) or 0
			for c = 1, columnCount do
				local left = (c - 1) * GRAPH_FILL_STEP
				local columnWidth = math.min(GRAPH_FILL_STEP, w - left)
				local position = math.min((left + columnWidth / 2) / w * (count - 1) + 1, count)
				local i = math.min(math.floor(position), count - 1)
				local y1, y2 = Y(i), Y(i + 1)
				local top = y1 + (y2 - y1) * (position - i)
				local column = columns[c]
				if not column then
					column = New("Frame", { BackgroundColor3 = color, Parent = plot })
					New("UIGradient", {
						Rotation = 90,
						Transparency = NumberSequence.new(0.75, 1),
						Parent = column,
					})
					columns[c] = column
				end
				column.Position = UDim2.fromOffset(left, top)
				column.Size = UDim2.fromOffset(columnWidth, h - top)
				column.Visible = true
			end
			for c = columnCount + 1, #columns do
				columns[c].Visible = false
			end

			endDot.Visible = count > 0
			if count > 0 then
				endDot.Position = UDim2.fromOffset(X(count), Y(count))
			end
		end

		-- Several pushes in one frame only draw once.
		local queued = false
		local function QueueRedraw()
			if queued then return end
			queued = true
			task.defer(function()
				queued = false
				Redraw()
			end)
		end
		plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(QueueRedraw)

		local function ShowLatest()
			Graph.Value = data[#data]
			valueLabel.Text = Graph.Value and FormatStat(Graph.Value, cfg) or ""
			QueueRedraw()
		end

		function Graph:Push(value)
			value = tonumber(value)
			if not value then return end
			table.insert(data, value)
			while #data > maxPoints do
				table.remove(data, 1)
			end
			ShowLatest()
		end
		function Graph:SetData(points)
			table.clear(data)
			for _, value in ipairs(points or {}) do
				local number = tonumber(value)
				if number then table.insert(data, number) end
			end
			while #data > maxPoints do
				table.remove(data, 1)
			end
			ShowLatest()
		end
		function Graph:Clear()
			Graph:SetData({})
		end

		Graph:SetData(cfg.Data)
		return Graph
	end

	function Stats:AddImageHolder(cfg)
		cfg = cfg or {}
		local Holder, card = TitledCard(cfg)
		Pad(card, 8)
		List(card)
		local columns = cfg.Columns or 4
		local GAP = 6

		local emptyLabel = Label({
			Text = "Nothing here yet",
			TextSize = 11.5,
			TextColor3 = theme.DimText,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = card,
		})
		local grid = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = card,
		})
		-- Cells are a pixel narrower than an exact share: rounding can otherwise
		-- make a full row a pixel too wide, which wraps its last tile.
		New("UIGridLayout", {
			CellPadding = UDim2.fromOffset(GAP, GAP),
			CellSize = UDim2.new(1 / columns, -math.floor(GAP * (columns - 1) / columns) - 1, 0, cfg.TileHeight or 68),
			FillDirectionMaxCells = columns,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})

		local tiles = {}
		local tileOrder = 0

		function Holder:AddImage(item)
			item = item or {}
			tileOrder = tileOrder + 1
			emptyLabel.Visible = false
			-- Left unparented once the frame is destroyed, so a script's refresh
			-- loop keeps running instead of erroring on a locked parent.
			local tile = New("Frame", {
				BackgroundColor3 = theme.ElementBackground,
				LayoutOrder = tileOrder,
				Parent = not Stats.Destroyed and grid or nil,
			})
			Round(tile, 6)
			local ring = Stroke(tile, item.Color or theme.Border, 1)
			local caption = Label({
				Text = item.Title or "",
				TextSize = 10,
				TextColor3 = theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 4, 1, -4),
				Size = UDim2.new(1, -8, 0, 12),
				Visible = item.Title ~= nil,
				Parent = tile,
			})
			local badge = Label({
				FontFace = Fonts.Bold,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundColor3 = theme.Header,
				BackgroundTransparency = 0.15,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -3, 0, 3),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 14),
				Visible = false,
				ZIndex = 3,
				Parent = tile,
			})
			Pill(badge)
			Pad(badge, 4, 0, 4, 0)

			local image
			local Tile = { Instance = tile }
			local function PlaceImage()
				if image then
					image.Size = UDim2.new(1, -12, 1, caption.Visible and -24 or -12)
				end
			end
			function Tile:SetImage(source)
				if image then image:Destroy() end
				image = Icon(source, 40, nil, {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 6),
					ScaleType = Enum.ScaleType.Fit,
					Parent = tile,
				})
				PlaceImage()
			end
			function Tile:SetTitle(text)
				caption.Text = text and tostring(text) or ""
				caption.Visible = text ~= nil
				PlaceImage()
			end
			function Tile:SetCount(count)
				badge.Text = count and ("x" .. FormatNumber(count)) or ""
				badge.Visible = count ~= nil
			end
			function Tile:SetColor(ringColor)
				ring.Color = ringColor or theme.Border
			end
			function Tile:SetVisible(visible)
				tile.Visible = visible and true or false
			end
			function Tile:Destroy()
				tile:Destroy()
				local index = table.find(tiles, Tile)
				if index then table.remove(tiles, index) end
				emptyLabel.Visible = #tiles == 0
			end

			Tile:SetImage(item.Image)
			Tile:SetCount(item.Count)
			table.insert(tiles, Tile)
			return Tile
		end

		function Holder:Clear()
			for i = #tiles, 1, -1 do
				tiles[i]:Destroy()
			end
		end
		--- Replaces every tile; meant for re-showing an inventory that changed.
		function Holder:SetImages(items)
			Holder:Clear()
			for _, item in ipairs(items or {}) do
				Holder:AddImage(item)
			end
		end

		Holder:SetImages(cfg.Images)
		return Holder
	end

	function Stats:AddText(cfg)
		cfg = cfg or {}
		local Text, card = TitledCard(cfg)
		Pad(card, 10, 8, 10, 8)
		local body = Label({
			Text = cfg.Content or "",
			TextSize = 12,
			TextColor3 = theme.SubText,
			TextWrapped = true,
			RichText = true,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = card,
		})
		function Text:SetContent(text)
			body.Text = tostring(text)
		end
		return Text
	end

	return Stats
end

--=============================================================================
-- WINDOW
--=============================================================================

function Ren:CreateWindow(config)
	config = config or {}
	Ren.Unloaded = false
	-- Migration: NovaUI scripts pass SubTitle = "My Config" as the starting
	-- label of its config selector; as a Ren subtitle it's noise, so drop it.
	local subTitle = config.SubTitle
	if subTitle == "My Config" then subTitle = nil end
	if config.Theme and Themes[config.Theme] then
		Ren.Theme = DeriveTheme(Themes[config.Theme], config.Accent)
	elseif config.Accent then
		Ren.Theme = DeriveTheme(Themes.Dark, config.Accent)
	end
	local theme = Ren.Theme
	if config.Icons then
		Ren.Icons = config.Icons
	end
	if config.ReducedEffects ~= nil then
		Ren:SetReducedEffects(config.ReducedEffects)
	end

	-- Fixed starting size: config.Size is deliberately ignored (NovaUI scripts
	-- pass sizes tuned for its sidebar layout). The corner grip still resizes.
	local size = UDim2.fromOffset(600, WINDOW_HEIGHT)
	local HEADER_HEIGHT = 50
	local TABBAR_HEIGHT = 40
	local CORNER = 10
	local COLUMN_GAP = 12

	-- Connections on global services outlive the ScreenGui; every one is
	-- tracked here and dropped in Window:Destroy().
	local AllConnections = {}
	local function Track(conn)
		table.insert(AllConnections, conn)
		return conn
	end

	local ScreenGui = New("ScreenGui", {
		Name = "Ren",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
	})
	MountGui(ScreenGui, config.Parent)

	-- AbsolutePosition and a child's Position live in different spaces once
	-- IgnoreGuiInset is on; this frame's origin is the conversion.
	local GuiOrigin = New("Frame", {
		Name = "GuiOrigin",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = ScreenGui,
	})
	local function ToGuiSpace(absolutePosition)
		return absolutePosition - GuiOrigin.AbsolutePosition
	end

	--=========================================================================
	-- FRAME: Main = header color (so a minimized window is just the header);
	-- Body under it holds the tab bar and pages on the darker background.
	--=========================================================================

	local width, height = size.X.Offset, size.Y.Offset
	local Main = New("Frame", {
		Name = "Main",
		BackgroundColor3 = theme.Header,
		Position = UDim2.new(0.5, -math.floor(width / 2), 0.5, -math.floor(height / 2)),
		Size = size,
		ClipsDescendants = true,
		Parent = ScreenGui,
	})
	local MainCorner = Round(Main, CORNER)
	local MainStroke = Stroke(Main, theme.Border, 1)
	local MainShadow = AddShadow(Main, { Transparency = 1, OffsetY = 12, Blur = 28 })
	local MainScale = New("UIScale", { Scale = 0.96, Parent = Main })

	local Header = New("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		Parent = Main,
	})
	local HeaderRow = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = Header,
	})
	Pad(HeaderRow, 16, 0, 10, 0)
	Row(HeaderRow, 8)

	local Body = New("Frame", {
		Name = "Body",
		BackgroundColor3 = theme.Background,
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT),
		Parent = Main,
	})
	Round(Body, CORNER, { TopLeft = 0, TopRight = 0 })

	local TabBar = New("Frame", {
		Name = "TabBar",
		BackgroundColor3 = theme.Header,
		Size = UDim2.new(1, 0, 0, TABBAR_HEIGHT),
		ClipsDescendants = true,
		Parent = Body,
	})
	New("Frame", {
		Name = "Line",
		BackgroundColor3 = theme.Divider,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = TabBar,
	})
	New("Frame", {
		Name = "TopLine",
		BackgroundColor3 = theme.Divider,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		Parent = TabBar,
	})

	local TabScroll = New("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = TabBar,
	})
	local TabList = New("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = TabScroll,
	})
	Row(TabList, 4)

	local Indicator = New("Frame", {
		Name = "Indicator",
		BackgroundColor3 = theme.Accent,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.fromOffset(0, 2),
		Visible = false,
		ZIndex = 3,
		Parent = TabBar,
	})
	Pill(Indicator)
	AddShadow(Indicator, { Color = theme.Accent, Transparency = 0.35, Blur = 10 })

	local PagesContainer = New("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, TABBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TABBAR_HEIGHT),
		ClipsDescendants = true,
		Parent = Body,
	})

	local ResizeHandle = New("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -2, 1, -2),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = 50,
		Parent = Body,
	})
	local resizeIcon = Icon("move-diagonal-2", 12, theme.DimText, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ImageTransparency = 0.4,
		ZIndex = 50,
		Parent = ResizeHandle,
	})
	if resizeIcon then
		ResizeHandle.MouseEnter:Connect(function()
			Tween(resizeIcon, { ImageTransparency = 0, ImageColor3 = theme.SubText }, 0.1)
		end)
		ResizeHandle.MouseLeave:Connect(function()
			Tween(resizeIcon, { ImageTransparency = 0.4, ImageColor3 = theme.DimText }, 0.1)
		end)
	end

	--=========================================================================
	-- OVERLAY + POPUP STACK
	-- Dropdown lists, colorpickers, menus and the config switcher render in
	-- Overlay so nothing occludes them. Popups stack: one opened from inside
	-- another (a dropdown inside a menu) stays nested above it. Each level
	-- has its own full-screen catcher; a click outside closes the top popup
	-- and every one below it that the click is also outside of.
	--=========================================================================

	local Overlay = New("Frame", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 900,
		Parent = ScreenGui,
	})

	local PopupStack = {}

	local function ClosePopupAt(level)
		for i = #PopupStack, level, -1 do
			local entry = table.remove(PopupStack, i)
			entry.Popup.Visible = false
			entry.Catcher:Destroy()
			SafeCall(entry.OnClose)
		end
	end
	local function ClosePopup()
		if #PopupStack > 0 then ClosePopupAt(#PopupStack) end
	end
	local function CloseAllPopups()
		if #PopupStack > 0 then ClosePopupAt(1) end
	end
	local function ClosePopupFor(popup)
		for i, entry in ipairs(PopupStack) do
			if entry.Popup == popup then
				ClosePopupAt(i)
				return
			end
		end
	end
	local function PointIn(gui, point)
		local p, s = gui.AbsolutePosition, gui.AbsoluteSize
		return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
	end

	-- Whether a processed press was meant for a UI rather than the game: the
	-- Roblox menu, chat, a text box, or a click on this window, an open popup
	-- or a floating frame.
	local function IsUiPress(input)
		if GuiService.MenuIsOpen or ChatInputFocused() then return true end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.MouseButton3 then
			if ScreenGui.Enabled and (#PopupStack > 0 or PointIn(Main, input.Position)) then return true end
			for _, frame in ipairs(FloatingFrames) do
				if frame.Visible and PointIn(frame.Instance, input.Position) then return true end
			end
			return false
		end
		return UserInputService:GetFocusedTextBox() ~= nil
	end

	local function PlacePopup(popup, anchor, opts)
		local screen = Overlay.AbsoluteSize
		local scale = popup:FindFirstChildOfClass("UIScale")
		local factor = scale and scale.Scale or 1
		local popupW = popup.AbsoluteSize.X / factor
		local popupH = popup.AbsoluteSize.Y / factor
		if popupW <= 0 then popupW = popup.Size.X.Offset end
		if popupH <= 0 then popupH = popup.Size.Y.Offset end

		local anchorPos = ToGuiSpace(anchor.AbsolutePosition)
		local anchorSize = anchor.AbsoluteSize
		local gap = opts.Gap or 6

		local leftX = anchorPos.X
		local rightX = anchorPos.X + anchorSize.X - popupW
		local x
		if opts.Align == "right" then
			x = rightX >= 4 and rightX or leftX
		else
			x = (leftX + popupW <= screen.X - 4) and leftX or rightX
		end
		x = math.clamp(x, 4, math.max(4, screen.X - popupW - 4))

		local y = anchorPos.Y + anchorSize.Y + gap
		if y + popupH > screen.Y - 4 and anchorPos.Y - popupH - gap >= 4 then
			y = anchorPos.Y - popupH - gap
		end
		y = math.clamp(y, 4, math.max(4, screen.Y - popupH - 4))
		popup.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	end

	--- Opens `popup` under `anchor` (Align "left"/"right", Gap, OnClose).
	--- Opening a popup that's already open closes it instead. Returns true
	--- when it ended up open.
	local function OpenPopup(popup, anchor, opts)
		opts = opts or {}
		for i, entry in ipairs(PopupStack) do
			if entry.Popup == popup then
				ClosePopupAt(i)
				return false
			end
		end
		local parentLevel = 0
		for i = #PopupStack, 1, -1 do
			if anchor and anchor:IsDescendantOf(PopupStack[i].Popup) then
				parentLevel = i
				break
			end
		end
		if parentLevel < #PopupStack then
			ClosePopupAt(parentLevel + 1)
		end

		local level = #PopupStack + 1
		local catcher = New("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 900 + level * 2,
			Parent = Overlay,
		})
		catcher.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.MouseButton2 and kind ~= Enum.UserInputType.Touch then
				return
			end
			local point = Vector2.new(input.Position.X, input.Position.Y)
			ClosePopup()
			while #PopupStack > 0 and not PointIn(PopupStack[#PopupStack].Popup, point) do
				ClosePopup()
			end
		end)

		popup.Parent = Overlay
		popup.ZIndex = 901 + level * 2
		table.insert(PopupStack, { Popup = popup, Catcher = catcher, OnClose = opts.OnClose })
		PlacePopup(popup, anchor, opts)
		popup.Visible = true
		PopIn(popup)
		-- AutomaticSize popups only know their real height after a layout
		-- pass; place again once they have it.
		task.defer(function()
			if popup.Visible then PlacePopup(popup, anchor, opts) end
		end)
		return true
	end

	--=========================================================================
	-- SMALL WIDGET HELPERS
	--=========================================================================

	-- Remembered so they can be hidden when their button vanishes under the
	-- cursor (minimizing), which never fires the MouseLeave that would.
	local Tooltips = {}
	local function HideTooltips()
		for _, tip in ipairs(Tooltips) do
			tip.Visible = false
		end
	end

	local function AttachTooltip(target, text)
		local tip = Label({
			Text = text,
			FontFace = Fonts.Medium,
			TextSize = 11,
			TextColor3 = theme.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundColor3 = theme.ElementBackgroundHover,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			Visible = false,
			ZIndex = 1000,
			Parent = ScreenGui,
		})
		Round(tip, 5)
		Pad(tip, 8, 0, 8, 0)
		table.insert(Tooltips, tip)
		target.MouseEnter:Connect(function()
			local anchor = ToGuiSpace(target.AbsolutePosition)
			tip.Position = UDim2.fromOffset(anchor.X + target.AbsoluteSize.X / 2, anchor.Y + target.AbsoluteSize.Y + 6)
			tip.Visible = true
		end)
		target.MouseLeave:Connect(function()
			tip.Visible = false
		end)
		return tip
	end

	-- Square icon-only button: transparent at rest, tinted on hover.
	local function Separator(parent, layoutOrder)
		return New("Frame", {
			BackgroundColor3 = theme.Border,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(1, 18),
			LayoutOrder = layoutOrder,
			Parent = parent,
		})
	end

	--=========================================================================
	-- HEADER: brand | search ... config chip, avatar, extra buttons | chrome
	--=========================================================================

	local Brand = New("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = HeaderRow,
	})
	Row(Brand, 8)
	local logoImage = config.Logo or Ren.Logo
	local logoIsGlyph = type(logoImage) == "string" and not logoImage:find("://")
	do
		AddLogo(Brand, logoImage, 1)
		Label({
			Text = config.Title or "Ren",
			FontFace = Fonts.Bold,
			TextSize = 15,
			TextColor3 = theme.Text,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = 2,
			Parent = Brand,
		})
		if subTitle then
			Label({
				Text = subTitle,
				TextSize = 11,
				TextColor3 = theme.DimText,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				LayoutOrder = 3,
				Parent = Brand,
			})
		end
	end

	Separator(HeaderRow, 2)

	local SearchPill = New("Frame", {
		BackgroundColor3 = theme.ElementBackground,
		-- 150 leaves the 600px header room for a long config name in the
		-- chip; at 180 the chrome buttons could be pushed off the edge.
		Size = UDim2.fromOffset(config.SearchWidth or 150, 30),
		LayoutOrder = 3,
		Parent = HeaderRow,
	})
	Round(SearchPill, 7)
	local searchRing = Stroke(SearchPill, theme.Accent, 1, 1)
	Icon("search", 14, theme.DimText, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Parent = SearchPill,
	})
	local SearchBox = New("TextBox", {
		Text = "",
		PlaceholderText = config.SearchPlaceholder or "Search element",
		FontFace = Fonts.Regular,
		TextSize = 12,
		TextColor3 = theme.Text,
		PlaceholderColor3 = theme.DimText,
		ClearTextOnFocus = false,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Parent = SearchPill,
	})
	SearchBox.Focused:Connect(function()
		Tween(searchRing, { Transparency = 0.3 }, 0.12)
	end)
	SearchBox.FocusLost:Connect(function()
		Tween(searchRing, { Transparency = 1 }, 0.15)
	end)

	-- Flexible gap: pushes everything after it to the right edge and doubles
	-- as the main drag area (nothing interactive on it to fight with).
	local HeaderSpacer = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 4,
		Parent = HeaderRow,
	})
	New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = HeaderSpacer })

	local ConfigChip = New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = theme.ElementBackground,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 5,
		Parent = HeaderRow,
	})
	Round(ConfigChip, 7)
	Pad(ConfigChip, 10, 0, 10, 0)
	Row(ConfigChip, 8)
	local ChipLabel = Label({
		Text = "No config",
		FontFace = Fonts.Medium,
		TextSize = 12,
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = ConfigChip,
	})
	New("UISizeConstraint", { MaxSize = Vector2.new(90, math.huge), Parent = ChipLabel })
	local chipIcon = Icon("folder", 15, theme.SubText, { LayoutOrder = 2, Parent = ConfigChip })
	ConfigChip.MouseEnter:Connect(function()
		Tween(ConfigChip, { BackgroundTransparency = 0 }, 0.1)
		if chipIcon then Tween(chipIcon, { ImageColor3 = theme.Accent }, 0.1) end
	end)
	ConfigChip.MouseLeave:Connect(function()
		Tween(ConfigChip, { BackgroundTransparency = 1 }, 0.1)
		if chipIcon then Tween(chipIcon, { ImageColor3 = theme.SubText }, 0.1) end
	end)

	local Avatar = New("ImageButton", {
		AutoButtonColor = false,
		BackgroundColor3 = theme.ElementBackground,
		Image = LocalPlayer and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", LocalPlayer.UserId) or "",
		Size = UDim2.fromOffset(26, 26),
		LayoutOrder = 6,
		Visible = config.ShowAvatar ~= false,
		Parent = HeaderRow,
	})
	Pill(Avatar)
	Stroke(Avatar, theme.Border, 1)
	if not LocalPlayer then
		Icon("user", 14, theme.SubText, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Parent = Avatar,
		})
	end
	AttachTooltip(Avatar, LocalPlayer and (LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")") or "Studio")

	local ExtraButtons = New("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 7,
		Parent = HeaderRow,
	})
	Row(ExtraButtons, 2)

	Separator(HeaderRow, 8)

	local Chrome = New("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 9,
		Parent = HeaderRow,
	})
	Row(Chrome, 2)
	local MinimizeBtn = IconButton(Chrome, "minus", 28, 14)
	MinimizeBtn.Instance.LayoutOrder = 1
	AttachTooltip(MinimizeBtn.Instance, "Minimize")
	local FullscreenBtn = IconButton(Chrome, "maximize-2", 28, 13)
	FullscreenBtn.Instance.LayoutOrder = 2
	local FullscreenTip = AttachTooltip(FullscreenBtn.Instance, "Fullscreen")
	local CloseBtn = IconButton(Chrome, "x", 28, 15, theme.Danger)
	CloseBtn.Instance.LayoutOrder = 3
	AttachTooltip(CloseBtn.Instance, "Close")

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
	Window._activeTab = nil
	Window._activeTabIndex = 0
	Window._searchText = ""
	Window.Search = { Box = SearchBox }

	local SetDragFade = DragFade(Main, ScreenGui, config.DragTransparency)

	local function CanDrag()
		return not Window._fullscreen
	end
	MakeDraggable(Main, Brand, Track, CanDrag, SetDragFade)
	MakeDraggable(Main, HeaderSpacer, Track, CanDrag, SetDragFade)

	--=========================================================================
	-- MINIMIZE: Main itself shrinks into a small round button (the logo)
	-- parked at MinimizePosition — the middle of the screen by default.
	-- Tapping it grows the full window back to where it was; it can be
	-- dragged aside first without that counting as a tap.
	--=========================================================================

	local MINI_SIZE = config.MinimizedSize or 40
	local currentDialog = nil -- owned by Window:Dialog below

	local MiniButton = New("TextButton", {
		Name = "Mini",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 80,
		Parent = Main,
	})
	local miniIconSize = math.floor(MINI_SIZE * (logoIsGlyph and 0.45 or 0.6))
	local miniIcon = Icon(logoImage, miniIconSize, logoIsGlyph and theme.Accent or nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 81,
		Parent = MiniButton,
	})
	if miniIcon then
		AddGlow(MiniButton, miniIconSize, theme.Accent)
	end
	MiniButton.MouseEnter:Connect(function()
		Tween(MainStroke, { Transparency = 0.05 }, 0.12)
	end)
	MiniButton.MouseLeave:Connect(function()
		if Window._minimized then Tween(MainStroke, { Transparency = 0.5 }, 0.12) end
	end)

	local function MiniPosition()
		local anchor = config.MinimizePosition or UDim2.fromScale(0.5, 0.5)
		return UDim2.new(anchor.X.Scale, anchor.X.Offset - MINI_SIZE / 2, anchor.Y.Scale, anchor.Y.Offset - MINI_SIZE / 2)
	end

	local function PixelSize(udim2)
		local screen = ScreenGui.AbsoluteSize
		return Vector2.new(udim2.X.Scale * screen.X + udim2.X.Offset, udim2.Y.Scale * screen.Y + udim2.Y.Offset)
	end

	-- While Main shrinks or grows, Header/Body are held at the full window's
	-- pixel size so they're clipped/revealed by it instead of reflowing
	-- through every in-between size.
	local function PinContent(pixels)
		if pixels then
			Header.Size = UDim2.fromOffset(pixels.X, HEADER_HEIGHT)
			Body.Size = UDim2.fromOffset(pixels.X, pixels.Y - HEADER_HEIGHT)
		else
			Header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
			Body.Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT)
		end
	end

	local function Animate(inst, props, duration)
		if duration > 0 then
			Tween(inst, props, duration, EASE_SOFT)
		else
			for prop, value in pairs(props) do inst[prop] = value end
		end
	end

	-- Bumped on every minimize/restore so a delayed step from an earlier,
	-- interrupted animation can tell it's stale.
	local minimizeToken = 0

	--- Window:ToggleMinimize(instant) — collapses to the round button / back.
	function Window:ToggleMinimize(instant)
		minimizeToken = minimizeToken + 1
		local token = minimizeToken
		local duration = instant and 0 or 0.3
		CloseAllPopups()
		HideTooltips()
		self._minimized = not self._minimized

		if self._minimized then
			if currentDialog then
				currentDialog:Destroy()
				currentDialog = nil
			end
			if self._fullscreen then
				-- Drop fullscreen without its own animation, so restoring
				-- lands on the windowed size rather than the full screen.
				self._fullscreen = false
				Main.Size = self._savedSize or self._fullSize
				Main.Position = self._savedPosition or Main.Position
				ResizeHandle.Visible = true
				FullscreenBtn.SetIcon("maximize-2")
				FullscreenTip.Text = "Fullscreen"
			end
			self._preMinimizeSize = Main.Size
			self._preMinimizePosition = Main.Position
			PinContent(PixelSize(Main.Size))

			Animate(Main, { Size = UDim2.fromOffset(MINI_SIZE, MINI_SIZE), Position = MiniPosition() }, duration)
			Animate(MainCorner, { CornerRadius = UDim.new(0, MINI_SIZE / 2) }, duration)
			Animate(MainStroke, { Color = theme.Accent, Transparency = 0.5 }, duration)

			local function ShowMini()
				if token ~= minimizeToken then return end
				Header.Visible = false
				Body.Visible = false
				MiniButton.Visible = true
				if miniIcon then
					miniIcon.ImageTransparency = 1
					Animate(miniIcon, { ImageTransparency = 0 }, duration * 0.6)
				end
			end
			if duration > 0 then
				task.delay(duration * 0.4, ShowMini)
			else
				ShowMini()
			end
		else
			local target = self._preMinimizeSize or self._fullSize
			PinContent(PixelSize(target))
			MiniButton.Visible = false
			Header.Visible = true
			Body.Visible = true

			Animate(Main, { Size = target, Position = self._preMinimizePosition or Main.Position }, duration)
			Animate(MainCorner, { CornerRadius = UDim.new(0, CORNER) }, duration)
			Animate(MainStroke, { Color = theme.Border, Transparency = 0 }, duration)

			local function Unpin()
				if token == minimizeToken then PinContent(nil) end
			end
			if duration > 0 then
				task.delay(duration, Unpin)
			else
				Unpin()
			end
		end
	end

	-- Drag the button anywhere; only a press that didn't move it restores.
	-- Activated rather than MouseButton1Click so a tap on touch counts too.
	do
		local pressedAt
		MakeDraggable(Main, MiniButton, Track, nil, SetDragFade)
		MiniButton.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				pressedAt = Main.AbsolutePosition
			end
		end)
		MiniButton.Activated:Connect(function()
			if pressedAt and (Main.AbsolutePosition - pressedAt).Magnitude > 4 then return end
			if Window._minimized then Window:ToggleMinimize() end
		end)
	end

	--- Fills the screen (16px margin) and back. Scale-based, so it follows
	--- resolution changes on its own.
	function Window:ToggleFullscreen()
		if self._minimized then
			self:ToggleMinimize(true)
		end
		self._fullscreen = not self._fullscreen
		if self._fullscreen then
			self._savedSize = Main.Size
			self._savedPosition = Main.Position
			ResizeHandle.Visible = false
			Tween(Main, { Size = UDim2.new(1, -32, 1, -32), Position = UDim2.fromOffset(16, 16) }, 0.22, EASE_SOFT)
			FullscreenBtn.SetIcon("minimize-2")
			FullscreenTip.Text = "Exit fullscreen"
		else
			ResizeHandle.Visible = true
			Tween(Main, { Size = self._savedSize or self._fullSize, Position = self._savedPosition or Main.Position }, 0.22, EASE_SOFT)
			FullscreenBtn.SetIcon("maximize-2")
			FullscreenTip.Text = "Fullscreen"
		end
	end

	MinimizeBtn.Instance.MouseButton1Click:Connect(function()
		Window:ToggleMinimize()
	end)
	FullscreenBtn.Instance.MouseButton1Click:Connect(function()
		Window:ToggleFullscreen()
	end)

	-- Corner resize. Main is anchored top-left, so only the corner moves.
	do
		local MIN_WIDTH, MIN_HEIGHT = 560, 340
		local resizing, resizeStart, startSize = false, nil, nil
		Track(ResizeHandle.InputBegan:Connect(function(input)
			if Window._minimized or Window._fullscreen then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				resizing = true
				resizeStart = input.Position
				startSize = Main.AbsoluteSize
			end
		end))
		Track(UserInputService.InputChanged:Connect(function(input)
			if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - resizeStart
				local screen = ScreenGui.AbsoluteSize
				local topLeft = ToGuiSpace(Main.AbsolutePosition)
				local newWidth = math.clamp(startSize.X + delta.X, MIN_WIDTH, math.max(MIN_WIDTH, screen.X - topLeft.X))
				local newHeight = math.clamp(startSize.Y + delta.Y, MIN_HEIGHT, math.max(MIN_HEIGHT, screen.Y - topLeft.Y))
				Main.Size = UDim2.fromOffset(newWidth, newHeight)
				Window._fullSize = Main.Size
			end
		end))
		Track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				resizing = false
			end
		end))
	end

	-- Live, reassignable hotkeys (KeyCode or MouseButton UserInputType).
	-- ToggleKey defaults to RightShift so a hidden window can always come
	-- back; pass ToggleKey = false for none.
	Window.MinimizeKey = config.MinimizeKey
	if config.ToggleKey == false then
		Window.ToggleKey = nil
	else
		Window.ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	end

	function Window:SetVisible(visible)
		if not visible then CloseAllPopups() end
		ScreenGui.Enabled = visible
	end
	function Window:ToggleVisible()
		Window:SetVisible(not ScreenGui.Enabled)
	end

	Track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or CapturingKeybind() then return end
		if KeybindMatches(Window.ToggleKey, input) then
			Window:ToggleVisible()
		elseif KeybindMatches(Window.MinimizeKey, input) then
			Window:ToggleMinimize()
		end
	end))

	function Window:Destroy()
		CloseAllPopups()
		for _, conn in ipairs(AllConnections) do
			if conn.Connected then conn:Disconnect() end
		end
		table.clear(AllConnections)
		for i = #FloatingFrames, 1, -1 do
			FloatingFrames[i]:Destroy()
		end
		ScreenGui:Destroy()
		Ren.Unloaded = true
	end

	function Window:Notify(cfg)
		return Ren:Notify(cfg)
	end

	--- Window:AddSidebarButton({ Icon, Tooltip, Callback, Order }) — NovaUI
	--- name kept; Ren has no sidebar, so these land in the header next to
	--- the window controls. Window:AddHeaderButton is the same function.
	--- Migration: a "chevron-down" button is NovaUI's collapse button, which
	--- Ren's header minimize already covers, so it's skipped. The caller
	--- still gets a working (unparented) handle back, so code that wires up
	--- the returned button doesn't error.
	function Window:AddSidebarButton(cfg)
		cfg = cfg or {}
		if cfg.Icon == "chevron-down" then
			return { Instance = New("TextButton", { Text = "" }), SetIcon = function() end }
		end
		local handle = IconButton(ExtraButtons, cfg.Icon or "star", 28, 15)
		handle.Instance.LayoutOrder = cfg.Order or #ExtraButtons:GetChildren()
		if cfg.Tooltip then AttachTooltip(handle.Instance, cfg.Tooltip) end
		if cfg.Callback then
			handle.Instance.MouseButton1Click:Connect(function() SafeCall(cfg.Callback) end)
		end
		return handle
	end
	Window.AddHeaderButton = Window.AddSidebarButton
	for _, btnCfg in ipairs(config.SidebarButtons or config.HeaderButtons or {}) do
		Window:AddSidebarButton(btnCfg)
	end

	--=========================================================================
	-- DIALOG
	--=========================================================================

	--- Window:Dialog({ Title, Content, Input = { Placeholder, Default },
	---   Buttons = {{ Title, Callback, Main }, ...} })
	--- With Input, each button's Callback gets the input's text. Main = true
	--- is the solid accent action. A lone button spans the full width.
	function Window:Dialog(cfg)
		cfg = cfg or {}
		if currentDialog then
			currentDialog:Destroy()
			currentDialog = nil
		end
		if Window._minimized then
			Window:ToggleMinimize()
		end
		CloseAllPopups()

		local overlay = New("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 60,
			Parent = Main,
		})
		Round(overlay, CORNER)
		currentDialog = overlay
		Tween(overlay, { BackgroundTransparency = 0.45 }, 0.15)

		local box = New("Frame", {
			BackgroundColor3 = theme.PopupBackground,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(cfg.Width or 340, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 61,
			Parent = overlay,
		})
		Round(box, 10)
		Stroke(box, theme.Border, 1)
		Pad(box, 16, 16, 16, 16)
		local boxShadow = AddShadow(box, { Transparency = 0.3, OffsetY = 10, Blur = 20 })
		local boxScale = New("UIScale", { Scale = 0.96, Parent = box })
		Tween(boxScale, { Scale = 1 }, 0.16, EASE_SOFT)
		List(box, { Padding = UDim.new(0, 14) })

		-- head has no layout of its own so the close button can sit pinned in
		-- its top-right corner; the text stack is a laid-out child.
		local head = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = box,
		})
		local headText = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -28, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = head,
		})
		List(headText, { Padding = UDim.new(0, 4) })
		Label({
			Text = cfg.Title or "Dialog",
			FontFace = Fonts.Medium,
			TextSize = 14,
			TextColor3 = theme.Text,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 1,
			Parent = headText,
		})
		if cfg.Content then
			Label({
				Text = cfg.Content,
				TextSize = 12,
				TextColor3 = theme.SubText,
				TextWrapped = true,
				RichText = true,
				LineHeight = 1.15,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
				Parent = headText,
			})
		end

		local function CloseDialog()
			if currentDialog == overlay then currentDialog = nil end
			Tween(overlay, { BackgroundTransparency = 1 }, 0.12)
			Tween(boxScale, { Scale = 0.96 }, 0.12)
			Tween(box, { BackgroundTransparency = 1 }, 0.12)
			if boxShadow then Tween(boxShadow, { Transparency = 1 }, 0.12) end
			FadeOutTree(box, 0.12)
			task.delay(0.13, function()
				overlay:Destroy()
			end)
		end

		local closeX = IconButton(head, "x", 24, 13)
		closeX.Instance.AnchorPoint = Vector2.new(1, 0)
		closeX.Instance.Position = UDim2.new(1, 6, 0, -5)
		closeX.Instance.MouseButton1Click:Connect(CloseDialog)

		local inputBox
		if cfg.Input then
			local inputHolder = New("Frame", {
				BackgroundColor3 = theme.ElementBackground,
				Size = UDim2.new(1, 0, 0, 32),
				LayoutOrder = 3,
				Parent = box,
			})
			Round(inputHolder, 7)
			local ring = Stroke(inputHolder, theme.Accent, 1, 1)
			inputBox = New("TextBox", {
				Text = cfg.Input.Default or "",
				PlaceholderText = cfg.Input.Placeholder or "",
				FontFace = Fonts.Regular,
				TextSize = 12,
				TextColor3 = theme.Text,
				PlaceholderColor3 = theme.DimText,
				ClearTextOnFocus = false,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -20, 1, 0),
				Parent = inputHolder,
			})
			inputBox.Focused:Connect(function() Tween(ring, { Transparency = 0.2 }, 0.12) end)
			inputBox.FocusLost:Connect(function() Tween(ring, { Transparency = 1 }, 0.15) end)
			task.defer(function()
				if inputBox.Parent then inputBox:CaptureFocus() end
			end)
		end

		local buttons = cfg.Buttons or {}
		local btnRow = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 32),
			LayoutOrder = 4,
			Parent = box,
		})
		Row(btnRow, 8, Enum.HorizontalAlignment.Right)
		for index, btnCfg in ipairs(buttons) do
			local isMain = btnCfg.Main == true
			local btn = New("TextButton", {
				Text = btnCfg.Title or "OK",
				FontFace = Fonts.Medium,
				TextSize = 12,
				TextColor3 = isMain and Color3.new(1, 1, 1) or theme.Text,
				BackgroundColor3 = isMain and theme.Accent or theme.ElementBackground,
				AutoButtonColor = false,
				Size = #buttons == 1 and UDim2.fromScale(1, 1) or UDim2.fromOffset(math.max(84, TextWidth(btnCfg.Title or "OK", 12) + 32), 32),
				LayoutOrder = index,
				Parent = btnRow,
			})
			Round(btn, 7)
			if not isMain then Stroke(btn, theme.Border, 1) end
			btn.MouseEnter:Connect(function()
				Tween(btn, { BackgroundColor3 = isMain and theme.AccentHover or theme.ElementBackgroundHover }, 0.1)
			end)
			btn.MouseLeave:Connect(function()
				Tween(btn, { BackgroundColor3 = isMain and theme.Accent or theme.ElementBackground }, 0.1)
			end)
			btn.MouseButton1Click:Connect(function()
				CloseDialog()
				SafeCall(btnCfg.Callback, inputBox and inputBox.Text or nil)
			end)
		end
		if inputBox then
			-- Enter submits through the Main button (or the last one).
			inputBox.FocusLost:Connect(function(enterPressed)
				if not enterPressed or currentDialog ~= overlay then return end
				local primary
				for _, btnCfg in ipairs(buttons) do
					if btnCfg.Main then primary = btnCfg end
				end
				primary = primary or buttons[#buttons]
				if primary then
					CloseDialog()
					SafeCall(primary.Callback, inputBox.Text)
				end
			end)
		end
	end

	CloseBtn.Instance.MouseButton1Click:Connect(function()
		if config.ConfirmClose == false then
			Window:Destroy()
			return
		end
		Window:Dialog({
			Title = "Close window?",
			Content = "This will unload " .. (config.Title or "the interface") .. ".",
			Buttons = {
				{ Title = "Cancel" },
				{ Title = "Close", Main = true, Callback = function()
					task.delay(0.14, function() Window:Destroy() end)
				end },
			},
		})
	end)

	--=========================================================================
	-- SECTION BUILDER — shared by tab sections and "..." menu popups
	--=========================================================================

	local ROW_HEIGHT, ROW_HEIGHT_DESC = 34, 44

	-- `container` is a frame with a vertical UIListLayout that rows land in.
	-- ctx.NoSearch keeps a menu popup's rows out of the header search;
	-- ctx.Compact shortens slider tracks to fit a popup's narrower rows.
	local function BuildSection(container, ctx)
		ctx = ctx or {}
		local Section = { _rowCount = 0, _searchRows = {}, Instance = container }

		local function NormalizeArgs(id, cfg)
			if type(id) == "table" and cfg == nil then
				return nil, id
			end
			return id, cfg or {}
		end

		local function NextOrder()
			Section._rowCount = Section._rowCount + 1
			return Section._rowCount
		end

		-- Shared row shell: title (+ description) on the left, a control
		-- strip `controlWidth` wide on the right, optional "..." menu.
		local function CreateRow(rowCfg, controlWidth)
			rowCfg = rowCfg or {}
			local elevated = rowCfg.Elevated and true or false
			local menuWidth = rowCfg.Menu and 28 or 0
			local hasDesc = rowCfg.Description ~= nil and rowCfg.Description ~= ""

			local row = New("Frame", {
				BackgroundColor3 = theme.ElementBackground,
				BackgroundTransparency = elevated and 0 or 1,
				Size = UDim2.new(1, 0, 0, hasDesc and ROW_HEIGHT_DESC or ROW_HEIGHT),
				LayoutOrder = NextOrder(),
				Parent = container,
			})
			Round(row, 6)

			local labelBox = New("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -(controlWidth + menuWidth + 30), 1, 0),
				Parent = row,
			})
			List(labelBox, { VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 2) })
			local title = Label({
				Text = rowCfg.Title or "",
				FontFace = Fonts.Medium,
				TextSize = 12,
				TextColor3 = theme.SubText,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, 0, 0, 15),
				LayoutOrder = 1,
				Parent = labelBox,
			})
			local desc = Label({
				Text = rowCfg.Description or "",
				TextSize = 11,
				TextColor3 = theme.DimText,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, 0, 0, 13),
				LayoutOrder = 2,
				Visible = hasDesc,
				Parent = labelBox,
			})

			local control = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.new(0, controlWidth + menuWidth, 1, 0),
				Parent = row,
			})
			Row(control, 8, Enum.HorizontalAlignment.Right)

			local handle = { Row = row, Control = control, TitleLabel = title, _active = false, _hover = false }
			local searchEntry
			if not ctx.NoSearch then
				searchEntry = { Instance = row, TitleLower = (rowCfg.Title or ""):lower() }
				table.insert(Section._searchRows, searchEntry)
			end

			local function PaintTitle()
				Tween(title, { TextColor3 = (handle._hover or handle._active) and theme.Text or theme.SubText }, 0.12)
			end
			--- Rows read white while "on" (toggles), grey otherwise.
			function handle.SetActive(on)
				handle._active = on and true or false
				PaintTitle()
			end
			row.MouseEnter:Connect(function()
				handle._hover = true
				if elevated then
					Tween(row, { BackgroundColor3 = theme.ElementBackgroundHover }, 0.1)
				else
					Tween(row, { BackgroundTransparency = 0.6 }, 0.1)
				end
				PaintTitle()
			end)
			row.MouseLeave:Connect(function()
				handle._hover = false
				if elevated then
					Tween(row, { BackgroundColor3 = theme.ElementBackground }, 0.1)
				else
					Tween(row, { BackgroundTransparency = 1 }, 0.1)
				end
				PaintTitle()
			end)

			-- Whole-row click target, under the labels and controls.
			local clickArea
			function handle.SetClick(fn)
				if not clickArea then
					clickArea = New("TextButton", {
						Text = "",
						AutoButtonColor = false,
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						ZIndex = 0,
						Parent = row,
					})
					clickArea.MouseButton1Click:Connect(function()
						if handle._onClick then handle._onClick() end
					end)
				end
				handle._onClick = fn
			end

			if rowCfg.Menu then
				local menuBtn = New("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = theme.ElementBackgroundHover,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(20, 20),
					LayoutOrder = -1,
					Parent = control,
				})
				Round(menuBtn, 5)
				local dots = Icon("ellipsis", 14, theme.SubText, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Parent = menuBtn,
				})
				menuBtn.MouseEnter:Connect(function()
					Tween(menuBtn, { BackgroundTransparency = 0 }, 0.1)
					if dots then Tween(dots, { ImageColor3 = theme.Text }, 0.1) end
				end)
				menuBtn.MouseLeave:Connect(function()
					Tween(menuBtn, { BackgroundTransparency = 1 }, 0.1)
					if dots then Tween(dots, { ImageColor3 = theme.SubText }, 0.1) end
				end)

				local popup = New("Frame", {
					BackgroundColor3 = theme.PopupBackground,
					Size = UDim2.fromOffset(rowCfg.MenuWidth or 260, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Visible = false,
					Parent = Overlay,
				})
				Round(popup, 10)
				Stroke(popup, theme.Border, 1)
				AddShadow(popup, { Transparency = 0.35, OffsetY = 8, Blur = 20 })
				Pad(popup, 12, 12, 12, 8)
				List(popup, { Padding = UDim.new(0, 8) })

				local menuHead = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 32),
					LayoutOrder = 1,
					Parent = popup,
				})
				Label({
					Text = rowCfg.MenuTitle or ((rowCfg.Title or "Element") .. " settings"),
					FontFace = Fonts.Medium,
					TextSize = 13,
					TextColor3 = theme.Text,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Size = UDim2.new(1, -26, 0, 16),
					Parent = menuHead,
				})
				Label({
					Text = rowCfg.MenuDescription or "Additional settings for this element.",
					TextSize = 11,
					TextColor3 = theme.DimText,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.fromOffset(0, 18),
					Size = UDim2.new(1, -26, 0, 13),
					Parent = menuHead,
				})
				local menuClose = IconButton(menuHead, "x", 22, 12)
				menuClose.Instance.AnchorPoint = Vector2.new(1, 0)
				menuClose.Instance.Position = UDim2.new(1, 4, 0, -4)
				menuClose.Instance.MouseButton1Click:Connect(function()
					ClosePopupFor(popup)
				end)

				New("Frame", {
					BackgroundColor3 = theme.Divider,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 1),
					LayoutOrder = 2,
					Parent = popup,
				})

				local menuBody = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = 3,
					Parent = popup,
				})
				List(menuBody, { Padding = UDim.new(0, 2) })
				handle.Menu = BuildSection(menuBody, { NoSearch = true, Compact = true })

				menuBtn.MouseButton1Click:Connect(function()
					SafeCall(rowCfg.MenuCallback)
					if handle.Menu._rowCount > 0 then
						OpenPopup(popup, menuBtn, { Align = "right" })
					end
				end)
			end

			--- Gives an element object the shared row methods.
			function handle.Attach(obj)
				obj.Instance = obj.Instance or row
				obj.Menu = handle.Menu
				function obj:SetTitle(text)
					title.Text = text or ""
					if searchEntry then searchEntry.TitleLower = (text or ""):lower() end
				end
				function obj:SetDescription(text)
					local has = text ~= nil and text ~= ""
					desc.Text = text or ""
					desc.Visible = has
					row.Size = UDim2.new(1, 0, 0, has and ROW_HEIGHT_DESC or ROW_HEIGHT)
				end
				function obj:SetVisible(visible)
					if searchEntry then searchEntry.Hidden = not visible end
					row.Visible = visible and true or false
				end
				return obj
			end

			return handle
		end

		--- Section:AddToggle(id, { Title, Description, Default, Elevated, Menu, Callback })
		function Section:AddToggle(id, cfg)
			id, cfg = NormalizeArgs(id, cfg)
			local row = CreateRow(cfg, 32)

			local track = New("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = theme.ElementBackground,
				Size = UDim2.fromOffset(32, 18),
				LayoutOrder = 1,
				Parent = row.Control,
			})
			Pill(track)
			local trackStroke = Stroke(track, theme.Border, 1)
			local knob = New("Frame", {
				BackgroundColor3 = theme.Knob,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 3, 0.5, 0),
				Size = UDim2.fromOffset(12, 12),
				Parent = track,
			})
			Pill(knob)

			local Toggle = { Value = cfg.Default and true or false, Changed = Signal.new(), Type = "Toggle" }
			local function Render(animate)
				local on = Toggle.Value
				local knobProps = {
					BackgroundColor3 = on and theme.Accent or theme.Knob,
					Position = on and UDim2.new(1, -15, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
				}
				local trackProps = { BackgroundColor3 = on and theme.AccentTrack or theme.ElementBackground }
				local strokeProps = { Color = on and theme.AccentTrack or theme.Border }
				if animate then
					Tween(knob, knobProps, 0.16, EASE_SOFT)
					Tween(track, trackProps, 0.16)
					Tween(trackStroke, strokeProps, 0.16)
				else
					for prop, value in pairs(knobProps) do knob[prop] = value end
					track.BackgroundColor3 = trackProps.BackgroundColor3
					trackStroke.Color = strokeProps.Color
				end
				row.SetActive(on)
			end
			Render(false)

			function Toggle:SetValue(value)
				Toggle.Value = value and true or false
				Render(true)
				Toggle.Changed:Fire(Toggle.Value)
				SafeCall(cfg.Callback, Toggle.Value)
			end
			function Toggle:OnChanged(fn) return Toggle.Changed:Connect(fn) end

			-- Announce the starting value too, same as NovaUI.
			Toggle.Changed:Fire(Toggle.Value)
			SafeCall(cfg.Callback, Toggle.Value)

			local function Flip() Toggle:SetValue(not Toggle.Value) end
			track.MouseButton1Click:Connect(Flip)
			row.SetClick(Flip)

			RegisterOption(id, Toggle)
			return row.Attach(Toggle)
		end

		-- Shared slider track: hit area + 4px rail + fill + knob(s).
		local function SliderTrack(parent, trackWidth, layoutOrder)
			local hit = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(trackWidth, 18),
				LayoutOrder = layoutOrder,
				Parent = parent,
			})
			local rail = New("Frame", {
				BackgroundColor3 = theme.ElementBackgroundHover,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, 0, 0, 4),
				Parent = hit,
			})
			Pill(rail)
			local fill = New("Frame", {
				BackgroundColor3 = theme.Accent,
				Size = UDim2.fromScale(0, 1),
				Parent = rail,
			})
			Pill(fill)
			local function MakeKnob()
				local knob = New("Frame", {
					BackgroundColor3 = Color3.new(1, 1, 1),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.fromOffset(12, 12),
					ZIndex = 2,
					Parent = rail,
				})
				Pill(knob)
				Stroke(knob, theme.Accent, 2)
				return knob
			end
			return hit, rail, fill, MakeKnob
		end

		local function Formatter(rounding, suffix)
			return function(v)
				return string.format("%." .. rounding .. "f", v) .. suffix
			end
		end

		-- string.format rather than floor/mult: the division doesn't always
		-- land on a clean decimal (83.49999...), the formatted string does.
		local function Rounder(rounding)
			return function(v)
				if rounding <= 0 then return math.floor(v + 0.5) end
				return tonumber(string.format("%." .. rounding .. "f", v))
			end
		end

		--- Section:AddSlider(id, { Title, Description, Default, Min, Max, Rounding, Suffix, Elevated, Callback })
		function Section:AddSlider(id, cfg)
			id, cfg = NormalizeArgs(id, cfg)
			local min, max = cfg.Min or 0, cfg.Max or 100
			local rounding = math.clamp(cfg.Rounding or 1, 0, 3)
			local format = Formatter(rounding, cfg.Suffix or "")
			local round = Rounder(rounding)
			local TRACK_W = cfg.TrackWidth or (ctx.Compact and 80 or 104)
			local LABEL_W = ctx.Compact and 38 or 48
			local row = CreateRow(cfg, LABEL_W + 8 + TRACK_W)

			local valueLabel = Label({
				Text = "",
				FontFace = Fonts.Medium,
				TextSize = 11.5,
				TextColor3 = theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(0, LABEL_W, 1, 0),
				LayoutOrder = 1,
				Parent = row.Control,
			})
			local hit, rail, fill, MakeKnob = SliderTrack(row.Control, TRACK_W, 2)
			local knob = MakeKnob()

			local Slider = { Value = math.clamp(cfg.Default or min, min, max), Changed = Signal.new(), Type = "Slider" }
			local function Render(v)
				local alpha = (max ~= min) and (v - min) / (max - min) or 0
				fill.Size = UDim2.fromScale(alpha, 1)
				knob.Position = UDim2.fromScale(alpha, 0.5)
				valueLabel.Text = format(v)
			end
			Render(Slider.Value)

			function Slider:SetValue(v)
				v = round(math.clamp(tonumber(v) or min, min, max))
				Slider.Value = v
				Render(v)
				Slider.Changed:Fire(v)
				SafeCall(cfg.Callback, v)
			end
			function Slider:OnChanged(fn) return Slider.Changed:Connect(fn) end

			local dragging = false
			local function FromX(x)
				local alpha = math.clamp((x - rail.AbsolutePosition.X) / rail.AbsoluteSize.X, 0, 1)
				local v = round(min + alpha * (max - min))
				if v ~= Slider.Value then Slider:SetValue(v) end
			end
			hit.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					Tween(knob, { Size = UDim2.fromOffset(14, 14) }, 0.1)
					FromX(input.Position.X)
				end
			end)
			Track(UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					FromX(input.Position.X)
				end
			end))
			Track(UserInputService.InputEnded:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
					dragging = false
					Tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.1)
				end
			end))

			RegisterOption(id, Slider)
			return row.Attach(Slider)
		end

		--- Section:AddRangeSlider(id, { Title, Description, Default = { lo, hi }, Min, Max, Rounding, Suffix, Callback })
		--- Value is { Min = lo, Max = hi }; SetValue takes that or { lo, hi }.
		function Section:AddRangeSlider(id, cfg)
			id, cfg = NormalizeArgs(id, cfg)
			local min, max = cfg.Min or 0, cfg.Max or 100
			local rounding = math.clamp(cfg.Rounding or 1, 0, 3)
			local format = Formatter(rounding, cfg.Suffix or "")
			local round = Rounder(rounding)
			local TRACK_W = cfg.TrackWidth or (ctx.Compact and 70 or 92)
			local row = CreateRow(cfg, 78 + 8 + TRACK_W)

			local valueLabel = Label({
				Text = "",
				FontFace = Fonts.Medium,
				TextSize = 11.5,
				TextColor3 = theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(0, 78, 1, 0),
				LayoutOrder = 1,
				Parent = row.Control,
			})
			local hit, rail, fill, MakeKnob = SliderTrack(row.Control, TRACK_W, 2)
			local lowKnob, highKnob = MakeKnob(), MakeKnob()

			local function Normalize(value)
				local lo, hi
				if type(value) == "table" then
					lo = value.Min or value[1]
					hi = value.Max or value[2]
				end
				lo = round(math.clamp(tonumber(lo) or min, min, max))
				hi = round(math.clamp(tonumber(hi) or max, min, max))
				if lo > hi then lo, hi = hi, lo end
				return { Min = lo, Max = hi }
			end

			local Range = { Value = Normalize(cfg.Default), Changed = Signal.new(), Type = "RangeSlider" }
			local function Alpha(v) return (max ~= min) and (v - min) / (max - min) or 0 end
			local function Render()
				local a, b = Alpha(Range.Value.Min), Alpha(Range.Value.Max)
				fill.Position = UDim2.fromScale(a, 0)
				fill.Size = UDim2.fromScale(b - a, 1)
				lowKnob.Position = UDim2.fromScale(a, 0.5)
				highKnob.Position = UDim2.fromScale(b, 0.5)
				valueLabel.Text = format(Range.Value.Min) .. "  –  " .. format(Range.Value.Max)
			end
			Render()

			function Range:SetValue(value)
				Range.Value = Normalize(value)
				Render()
				Range.Changed:Fire(Range.Value)
				SafeCall(cfg.Callback, Range.Value)
			end
			function Range:OnChanged(fn) return Range.Changed:Connect(fn) end
			function Range:Serialize()
				return { __type = "Range", Min = Range.Value.Min, Max = Range.Value.Max }
			end

			local dragging -- "Min" / "Max" / nil
			local function ValueAt(x)
				local alpha = math.clamp((x - rail.AbsolutePosition.X) / rail.AbsoluteSize.X, 0, 1)
				return round(min + alpha * (max - min))
			end
			local function Drag(x)
				local v = ValueAt(x)
				local nextValue = { Min = Range.Value.Min, Max = Range.Value.Max }
				if dragging == "Min" then
					nextValue.Min = math.min(v, Range.Value.Max)
				else
					nextValue.Max = math.max(v, Range.Value.Min)
				end
				if nextValue.Min ~= Range.Value.Min or nextValue.Max ~= Range.Value.Max then
					Range:SetValue(nextValue)
				end
			end
			hit.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					local v = ValueAt(input.Position.X)
					-- Grab whichever knob is closer; ties go to the side
					-- the press is on, so stacked knobs can still separate.
					local dLow, dHigh = math.abs(v - Range.Value.Min), math.abs(v - Range.Value.Max)
					if dLow == dHigh then
						dragging = v < Range.Value.Min and "Min" or "Max"
					else
						dragging = dLow < dHigh and "Min" or "Max"
					end
					Drag(input.Position.X)
				end
			end)
			Track(UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					Drag(input.Position.X)
				end
			end))
			Track(UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = nil
				end
			end))

			RegisterOption(id, Range)
			return row.Attach(Range)
		end

		--- Section:AddDropdown(id, { Title, Description, Values, Multi, Default, Searchable, Width, Callback })
		--- Compact inline button; the list opens as a popup (with a search
		--- box once there are more than 7 options, and All/None for Multi).
		--- Values may be Instances — Value/Callback hand those back.
		function Section:AddDropdown(id, cfg)
			id, cfg = NormalizeArgs(id, cfg)
			local values = cfg.Values or {}
			local multi = cfg.Multi or false
			local BTN_W = cfg.Width or 118
			local OPTION_H, MAX_ROWS, POPUP_PAD = 26, 7, 5
			local row = CreateRow(cfg, BTN_W)

			local ddBtn = New("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = theme.ElementBackground,
				Size = UDim2.fromOffset(BTN_W, 24),
				LayoutOrder = 1,
				Parent = row.Control,
			})
			Round(ddBtn, 6)
			Stroke(ddBtn, theme.Border, 1)
			local ddLabel = Label({
				Text = "",
				FontFace = Fonts.Medium,
				TextSize = 11.5,
				TextColor3 = theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(9, 0),
				Size = UDim2.new(1, -30, 1, 0),
				Parent = ddBtn,
			})
			local chevron = Icon("chevron-down", 12, theme.SubText, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Parent = ddBtn,
			})
			ddBtn.MouseEnter:Connect(function() Tween(ddBtn, { BackgroundColor3 = theme.ElementBackgroundHover }, 0.1) end)
			ddBtn.MouseLeave:Connect(function() Tween(ddBtn, { BackgroundColor3 = theme.ElementBackground }, 0.1) end)

			local popup = New("Frame", {
				BackgroundColor3 = theme.PopupBackground,
				ClipsDescendants = true,
				Size = UDim2.fromOffset(160, 100),
				Visible = false,
				Parent = Overlay,
			})
			Round(popup, 8)
			Stroke(popup, theme.Border, 1)
			AddShadow(popup, { Transparency = 0.4, OffsetY = 6, Blur = 16 })
			Pad(popup, POPUP_PAD)
			List(popup, { Padding = UDim.new(0, 4) })

			local searchPill = New("Frame", {
				BackgroundColor3 = theme.ElementBackground,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = 1,
				Visible = false,
				Parent = popup,
			})
			Round(searchPill, 5)
			Icon("search", 12, theme.DimText, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, 0.5, 0),
				Parent = searchPill,
			})
			local searchInput = New("TextBox", {
				Text = "",
				PlaceholderText = "Search...",
				FontFace = Fonts.Regular,
				TextSize = 12,
				TextColor3 = theme.Text,
				PlaceholderColor3 = theme.DimText,
				ClearTextOnFocus = false,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(26, 0),
				Size = UDim2.new(1, -32, 1, 0),
				Parent = searchPill,
			})

			local actionRow
			local selectAllBtn, noneBtn
			if multi then
				actionRow = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 22),
					LayoutOrder = 2,
					Parent = popup,
				})
				Row(actionRow, 4)
				local function ActionButton(text, order)
					local btn = New("TextButton", {
						Text = text,
						FontFace = Fonts.Medium,
						TextSize = 11,
						TextColor3 = theme.SubText,
						BackgroundColor3 = theme.ElementBackground,
						AutoButtonColor = false,
						Size = UDim2.new(0.5, -2, 1, 0),
						LayoutOrder = order,
						Parent = actionRow,
					})
					Round(btn, 5)
					btn.MouseEnter:Connect(function() Tween(btn, { BackgroundColor3 = theme.ElementBackgroundHover, TextColor3 = theme.Text }, 0.1) end)
					btn.MouseLeave:Connect(function() Tween(btn, { BackgroundColor3 = theme.ElementBackground, TextColor3 = theme.SubText }, 0.1) end)
					return btn
				end
				selectAllBtn = ActionButton("Select all", 1)
				noneBtn = ActionButton("None", 2)
			end

			local listScroll = New("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, OPTION_H),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 2,
				ScrollBarImageColor3 = theme.ElementBackgroundHover,
				LayoutOrder = 3,
				Parent = popup,
			})
			List(listScroll, { Padding = UDim.new(0, 2) })
			local emptyLabel = Label({
				Text = "No options",
				TextSize = 12,
				TextColor3 = theme.DimText,
				Size = UDim2.new(1, 0, 0, OPTION_H),
				LayoutOrder = 1000000,
				Visible = false,
				Parent = listScroll,
			})
			Pad(emptyLabel, 8, 0, 8, 0)

			local Dropdown = { Value = multi and {} or nil, Changed = Signal.new(), Multi = multi, Type = "Dropdown", _optionButtons = {} }
			local optionByKey = {}
			local searchQuery = ""

			local function Searchable()
				if cfg.Searchable ~= nil then return cfg.Searchable end
				return #values > MAX_ROWS
			end
			local function ResolveOption(value)
				if value == nil then return nil end
				local option = optionByKey[tostring(value)]
				if option ~= nil then return option end
				return value
			end
			local function IsSelected(key)
				local option = optionByKey[key]
				if option == nil then return false end
				if multi then return (Dropdown.Value or {})[option] and true or false end
				return Dropdown.Value ~= nil and tostring(Dropdown.Value) == key
			end
			local function LabelForValue()
				if multi then
					local picked = {}
					for _, option in ipairs(values) do
						if (Dropdown.Value or {})[option] then table.insert(picked, tostring(option)) end
					end
					if #picked == 0 then return "None" end
					if #picked == 1 then return picked[1] end
					return picked[1] .. ", +" .. (#picked - 1)
				end
				return Dropdown.Value ~= nil and tostring(Dropdown.Value) or "None"
			end
			local function Matches(key)
				return searchQuery == "" or string.find(key:lower(), searchQuery, 1, true) ~= nil
			end
			local function RefreshHighlights()
				for key, entry in pairs(Dropdown._optionButtons) do
					local active = IsSelected(key)
					entry.Label.TextColor3 = active and theme.Text or theme.SubText
					entry.Check.Visible = active
					entry.Button.BackgroundTransparency = active and 0.5 or 1
				end
			end
			local function Resize()
				local shown = 0
				for key, entry in pairs(Dropdown._optionButtons) do
					local visible = Matches(key)
					entry.Button.Visible = visible
					if visible then shown = shown + 1 end
				end
				emptyLabel.Text = searchQuery ~= "" and "No matches" or "No options"
				emptyLabel.Visible = shown == 0
				local rows = math.clamp(shown, 1, MAX_ROWS)
				local listHeight = rows * OPTION_H + (rows - 1) * 2
				listScroll.Size = UDim2.new(1, 0, 0, listHeight)
				local searchable = Searchable()
				searchPill.Visible = searchable
				local headerHeight = (searchable and 30 or 0) + (multi and 26 or 0)
				popup.Size = UDim2.fromOffset(math.max(ddBtn.AbsoluteSize.X, 150), POPUP_PAD * 2 + headerHeight + listHeight)
			end
			local function RefreshButton()
				ddLabel.Text = LabelForValue()
			end

			function Dropdown:OnChanged(fn) return Dropdown.Changed:Connect(fn) end
			--- Dropdown:SetValue(value) — an entry or its name; Multi takes a
			--- list or an entry -> bool map.
			function Dropdown:SetValue(value)
				if multi then
					local map = {}
					if typeof(value) == "table" then
						if value[1] ~= nil and typeof(value[1]) ~= "boolean" then
							for _, name in ipairs(value) do map[ResolveOption(name)] = true end
						else
							for name, on in pairs(value) do
								if on then map[ResolveOption(name)] = true end
							end
						end
					end
					Dropdown.Value = map
				else
					Dropdown.Value = ResolveOption(value)
				end
				RefreshButton()
				RefreshHighlights()
				Dropdown.Changed:Fire(Dropdown.Value)
				SafeCall(cfg.Callback, Dropdown.Value)
			end

			local function CreateOption(option, index)
				local key = tostring(option)
				local btn = New("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = theme.ElementBackground,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, OPTION_H),
					LayoutOrder = index,
					Parent = listScroll,
				})
				Round(btn, 5)
				local label = Label({
					Text = key,
					FontFace = Fonts.Medium,
					TextSize = 12,
					TextColor3 = theme.SubText,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.fromOffset(9, 0),
					Size = UDim2.new(1, -34, 1, 0),
					Parent = btn,
				})
				local check = Icon("check", 12, theme.Accent, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -9, 0.5, 0),
					Visible = false,
					Parent = btn,
				}) or New("Frame", { Visible = false, Parent = btn })
				Dropdown._optionButtons[key] = { Button = btn, Label = label, Check = check }
				optionByKey[key] = option
				btn.MouseEnter:Connect(function()
					if not IsSelected(key) then Tween(btn, { BackgroundTransparency = 0.3 }, 0.08) end
					label.TextColor3 = theme.Text
				end)
				btn.MouseLeave:Connect(function()
					RefreshHighlights()
				end)
				btn.MouseButton1Click:Connect(function()
					if multi then
						local nextMap = {}
						for k, v in pairs(Dropdown.Value or {}) do nextMap[k] = v end
						nextMap[option] = not IsSelected(key) or nil
						Dropdown:SetValue(nextMap)
					else
						Dropdown:SetValue(option)
						ClosePopupFor(popup)
					end
				end)
			end

			--- Dropdown:SetOptions(list) — rebuilds the list; selections whose
			--- names survive carry over (re-pointed at the new entries).
			function Dropdown:SetOptions(list)
				values = list or {}
				Dropdown.Values = values
				for _, entry in pairs(Dropdown._optionButtons) do entry.Button:Destroy() end
				Dropdown._optionButtons = {}
				optionByKey = {}
				for index, option in ipairs(values) do
					if not Dropdown._optionButtons[tostring(option)] then CreateOption(option, index) end
				end
				if multi then
					local survivors = {}
					for option, on in pairs(Dropdown.Value or {}) do
						local live = optionByKey[tostring(option)]
						if on and live ~= nil then survivors[live] = true end
					end
					Dropdown.Value = survivors
				elseif Dropdown.Value ~= nil then
					Dropdown.Value = optionByKey[tostring(Dropdown.Value)]
				end
				RefreshButton()
				RefreshHighlights()
				Resize()
			end
			Dropdown.Values = values
			for index, option in ipairs(values) do
				if not Dropdown._optionButtons[tostring(option)] then CreateOption(option, index) end
			end

			searchInput:GetPropertyChangedSignal("Text"):Connect(function()
				searchQuery = searchInput.Text:lower()
				Resize()
			end)
			if selectAllBtn then
				selectAllBtn.MouseButton1Click:Connect(function()
					local nextMap = {}
					for option, on in pairs(Dropdown.Value or {}) do
						if on then nextMap[option] = true end
					end
					for key, option in pairs(optionByKey) do
						if Matches(key) then nextMap[option] = true end
					end
					Dropdown:SetValue(nextMap)
				end)
				noneBtn.MouseButton1Click:Connect(function()
					Dropdown:SetValue({})
				end)
			end

			local function Open()
				Resize()
				local opened = OpenPopup(popup, ddBtn, {
					Align = "right",
					OnClose = function()
						if chevron then Tween(chevron, { Rotation = 0 }, 0.12) end
						searchInput:ReleaseFocus()
						searchInput.Text = ""
					end,
				})
				if opened then
					if chevron then Tween(chevron, { Rotation = 180 }, 0.12) end
					if searchPill.Visible and not UserInputService.TouchEnabled then
						searchInput:CaptureFocus()
					end
				end
			end
			ddBtn.MouseButton1Click:Connect(Open)
			row.SetClick(Open)

			if cfg.Default ~= nil then
				Dropdown:SetValue(cfg.Default)
			else
				RefreshButton()
			end
			Resize()

			RegisterOption(id, Dropdown)
			return row.Attach(Dropdown)
		end

		--- Section:AddColorpicker(id, { Title, Description, Default, Transparency, Elevated, Callback })
		--- Like NovaUI, Changed/Callback fire once with the final color when
		--- the picker closes, not on every drag step.
		function Section:AddColorpicker(id, cfg)
			id, cfg = NormalizeArgs(id, cfg)
			local row = CreateRow(cfg, 30)
			local hasAlpha = cfg.Transparency ~= nil

			local swatch = New("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = cfg.Default or Color3.new(1, 1, 1),
				Size = UDim2.fromOffset(28, 16),
				LayoutOrder = 1,
				Parent = row.Control,
			})
			Round(swatch, 4)
			Stroke(swatch, theme.Border, 1)

			local popup = New("Frame", {
				BackgroundColor3 = theme.PopupBackground,
				Size = UDim2.fromOffset(220, hasAlpha and 210 or 192),
				Visible = false,
				Parent = Overlay,
			})
			Round(popup, 10)
			Stroke(popup, theme.Border, 1)
			AddShadow(popup, { Transparency = 0.4, OffsetY = 6, Blur = 16 })
			Pad(popup, 10)
			List(popup, { Padding = UDim.new(0, 8) })

			-- SV square: hue base + white→clear (left→right) + clear→black
			-- (top→bottom) layers. A gradient on the base itself would
			-- override its hue color, so they're separate frames.
			local svBox = New("Frame", {
				BackgroundColor3 = Color3.fromHSV(0, 1, 1),
				Size = UDim2.new(1, 0, 0, 118),
				LayoutOrder = 1,
				Parent = popup,
			})
			Round(svBox, 6)
			local white = New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = svBox })
			Round(white, 6)
			New("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
			local black = New("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), Parent = svBox })
			Round(black, 6)
			New("UIGradient", { Transparency = NumberSequence.new(1, 0), Rotation = 90, Parent = black })
			local svCursor = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(10, 10),
				ZIndex = 3,
				Parent = svBox,
			})
			Pill(svCursor)
			Stroke(svCursor, Color3.new(1, 1, 1), 2)

			local function Bar(order)
				local bar = New("Frame", {
					BackgroundColor3 = Color3.new(1, 1, 1),
					Size = UDim2.new(1, 0, 0, 10),
					LayoutOrder = order,
					Parent = popup,
				})
				Pill(bar)
				local cursor = New("Frame", {
					BackgroundColor3 = Color3.new(1, 1, 1),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.fromOffset(12, 12),
					ZIndex = 3,
					Parent = bar,
				})
				Pill(cursor)
				Stroke(cursor, theme.PopupBackground, 2)
				return bar, cursor
			end
			local hueBar, hueCursor = Bar(2)
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
			local alphaBar, alphaCursor, alphaGradient
			if hasAlpha then
				alphaBar, alphaCursor = Bar(3)
				alphaGradient = New("UIGradient", { Transparency = NumberSequence.new(0, 0.85), Parent = alphaBar })
			end

			local bottom = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 4,
				Parent = popup,
			})
			Row(bottom, 6)
			local preview = New("Frame", {
				BackgroundColor3 = cfg.Default or Color3.new(1, 1, 1),
				Size = UDim2.fromOffset(24, 24),
				LayoutOrder = 1,
				Parent = bottom,
			})
			Round(preview, 6)
			Stroke(preview, theme.Border, 1)
			local hexHolder = New("Frame", {
				BackgroundColor3 = theme.ElementBackground,
				Size = UDim2.fromOffset(78, 24),
				LayoutOrder = 2,
				Parent = bottom,
			})
			Round(hexHolder, 6)
			local hexBox = New("TextBox", {
				Text = "",
				FontFace = Fonts.Medium,
				TextSize = 11.5,
				TextColor3 = theme.Text,
				ClearTextOnFocus = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Parent = hexHolder,
			})
			local rgbLabel = Label({
				Text = "",
				TextSize = 11,
				TextColor3 = theme.DimText,
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(0, 84, 1, 0),
				LayoutOrder = 3,
				Parent = bottom,
			})

			local Colorpicker = {
				Value = cfg.Default or Color3.new(1, 1, 1),
				Transparency = cfg.Transparency or 0,
				Changed = Signal.new(),
				Type = "Colorpicker",
			}
			local h, s, v = Colorpicker.Value:ToHSV()

			local function Render()
				svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
				svCursor.Position = UDim2.fromScale(s, 1 - v)
				hueCursor.Position = UDim2.fromScale(h, 0.5)
				hueCursor.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
				swatch.BackgroundColor3 = Colorpicker.Value
				preview.BackgroundColor3 = Colorpicker.Value
				if not hexBox:IsFocused() then
					hexBox.Text = "#" .. Colorpicker.Value:ToHex():upper()
				end
				rgbLabel.Text = string.format("%d, %d, %d", math.round(Colorpicker.Value.R * 255), math.round(Colorpicker.Value.G * 255), math.round(Colorpicker.Value.B * 255))
				if alphaBar then
					alphaBar.BackgroundColor3 = Colorpicker.Value
					alphaCursor.Position = UDim2.fromScale(1 - Colorpicker.Transparency, 0.5)
					swatch.BackgroundTransparency = Colorpicker.Transparency * 0.8
				end
			end
			Render()

			function Colorpicker:OnChanged(fn) return Colorpicker.Changed:Connect(fn) end
			function Colorpicker:SetValueRGB(color, transparency)
				Colorpicker.Value = color
				if transparency ~= nil then Colorpicker.Transparency = transparency end
				h, s, v = color:ToHSV()
				Render()
				Colorpicker.Changed:Fire(Colorpicker.Value)
				SafeCall(cfg.Callback, Colorpicker.Value)
			end
			function Colorpicker:SetValue(hsvOrColor, transparency)
				if typeof(hsvOrColor) == "Color3" then
					Colorpicker:SetValueRGB(hsvOrColor, transparency)
				elseif type(hsvOrColor) == "table" then
					Colorpicker:SetValueRGB(Color3.fromHSV(hsvOrColor[1] or 0, hsvOrColor[2] or 0, hsvOrColor[3] or 1), transparency)
				end
			end

			local function Commit()
				Colorpicker.Value = Color3.fromHSV(h, s, v)
				Render()
			end

			local dragTarget -- "SV" / "Hue" / "Alpha"
			local function UpdateDrag(position)
				if dragTarget == "SV" then
					s = math.clamp((position.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
					v = 1 - math.clamp((position.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
					Commit()
				elseif dragTarget == "Hue" then
					h = math.clamp((position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 0.999)
					Commit()
				elseif dragTarget == "Alpha" and alphaBar then
					Colorpicker.Transparency = 1 - math.clamp((position.X - alphaBar.AbsolutePosition.X) / alphaBar.AbsoluteSize.X, 0, 1)
					Render()
				end
			end
			local function BeginDrag(target)
				return function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragTarget = target
						UpdateDrag(input.Position)
					end
				end
			end
			svBox.InputBegan:Connect(BeginDrag("SV"))
			hueBar.InputBegan:Connect(BeginDrag("Hue"))
			if alphaBar then alphaBar.InputBegan:Connect(BeginDrag("Alpha")) end
			Track(UserInputService.InputChanged:Connect(function(input)
				if dragTarget and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					UpdateDrag(input.Position)
				end
			end))
			Track(UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragTarget = nil
				end
			end))

			hexBox.FocusLost:Connect(function()
				local hex = hexBox.Text:gsub("#", ""):gsub("%s", "")
				if #hex == 6 and hex:match("^%x+$") then
					local ok, color = pcall(Color3.fromHex, hex)
					if ok then
						h, s, v = color:ToHSV()
						Commit()
					end
				end
				Render()
			end)

			local function Open()
				h, s, v = Colorpicker.Value:ToHSV()
				Render()
				OpenPopup(popup, swatch, {
					Align = "right",
					OnClose = function()
						Colorpicker.Changed:Fire(Colorpicker.Value)
						SafeCall(cfg.Callback, Colorpicker.Value)
					end,
				})
			end
			swatch.MouseButton1Click:Connect(Open)
			row.SetClick(Open)

			RegisterOption(id, Colorpicker)
			return row.Attach(Colorpicker)
		end
		Section.AddColorPicker = Section.AddColorpicker

		--- Section:AddKeybind(id, { Title, Description, Mode, Default, Elevated, Callback, ChangedCallback })
		--- Callback / :OnChanged get the live pressed state; ChangedCallback /
		--- :OnKeybindChanged get the newly bound key. Values are Enum.KeyCode
		--- or Enum.UserInputType.MouseButton1/2/3 items. While binding, Escape
		--- cancels and Backspace clears.
		function Section:AddKeybind(id, cfg)
			id, cfg = NormalizeArgs(id, cfg)
			local row = CreateRow(cfg, 84)

			local keyBtn = New("TextButton", {
				Text = KeybindDisplayName(cfg.Default),
				FontFace = Fonts.Medium,
				TextSize = 11.5,
				TextColor3 = theme.Text,
				BackgroundColor3 = theme.ElementBackground,
				AutoButtonColor = false,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 24),
				LayoutOrder = 1,
				Parent = row.Control,
			})
			Round(keyBtn, 6)
			Pad(keyBtn, 10, 0, 10, 0)
			New("UISizeConstraint", { MinSize = Vector2.new(48, 0), Parent = keyBtn })
			local keyStroke = Stroke(keyBtn, theme.Border, 1)
			keyBtn.MouseEnter:Connect(function() Tween(keyBtn, { BackgroundColor3 = theme.ElementBackgroundHover }, 0.1) end)
			keyBtn.MouseLeave:Connect(function() Tween(keyBtn, { BackgroundColor3 = theme.ElementBackground }, 0.1) end)

			local Keybind = {
				Value = cfg.Default,
				Mode = NormalizeKeybindMode(cfg.Mode, id),
				Changed = Signal.new(),
				KeybindChanged = Signal.new(),
				Click = Signal.new(),
				Type = "Keybind",
				_state = false,
				_listening = false,
			}
			Keybind.KeybindChanged:Fire(Keybind.Value)
			SafeCall(cfg.ChangedCallback, Keybind.Value)

			function Keybind:OnChanged(fn) return Keybind.Changed:Connect(fn) end
			function Keybind:OnKeybindChanged(fn) return Keybind.KeybindChanged:Connect(fn) end
			function Keybind:OnClick(fn) return Keybind.Click:Connect(fn) end
			function Keybind:GetState()
				if Keybind.Mode == "Always" then return true end
				return Keybind._state
			end
			function Keybind:SetValue(key, mode)
				Keybind.Value = key
				if mode then Keybind.Mode = NormalizeKeybindMode(mode, id) end
				keyBtn.Text = KeybindDisplayName(key)
				Keybind.KeybindChanged:Fire(key)
				SafeCall(cfg.ChangedCallback, key)
			end

			local pulse
			local function StopListening()
				if not Keybind._listening then return end
				Keybind._listening = false
				KeybindCapture.Active = math.max(0, KeybindCapture.Active - 1)
				KeybindCapture.LastEnded = os.clock()
				if pulse then pulse:Cancel() pulse = nil end
				Tween(keyStroke, { Color = theme.Border, Transparency = 0 }, 0.12)
				keyBtn.TextColor3 = theme.Text
			end
			local function StartListening()
				if Keybind._listening then return end
				Keybind._listening = true
				KeybindCapture.Active = KeybindCapture.Active + 1
				keyBtn.Text = "..."
				keyBtn.TextColor3 = theme.Accent
				keyStroke.Color = theme.Accent
				keyStroke.Transparency = 0
				pulse = TweenService:Create(keyStroke, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.7 })
				pulse:Play()
			end
			keyBtn.MouseButton1Click:Connect(StartListening)
			row.SetClick(StartListening)

			Track(UserInputService.InputBegan:Connect(function(input, processed)
				if Keybind._listening then
					local newValue
					if input.KeyCode == Enum.KeyCode.Escape then
						StopListening()
						keyBtn.Text = KeybindDisplayName(Keybind.Value)
						return
					elseif input.KeyCode == Enum.KeyCode.Backspace then
						StopListening()
						Keybind:SetValue(nil)
						return
					elseif input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.MouseButton2
						or input.UserInputType == Enum.UserInputType.MouseButton3 then
						newValue = input.UserInputType
					elseif input.KeyCode ~= Enum.KeyCode.Unknown then
						newValue = input.KeyCode
					end
					if newValue then
						-- The click that started listening also arrives here
						-- as MouseButton1; ignore it.
						if newValue == Enum.UserInputType.MouseButton1 and processed then return end
						StopListening()
						Keybind:SetValue(newValue)
					end
					return
				end

				if not KeybindMatches(Keybind.Value, input) then return end
				-- A hold follows the physical key, so a press the game consumed
				-- (a sunk ContextAction, a click on its GUI) still starts it.
				local ignored = processed
				if Keybind.Mode == "Hold" then
					ignored = processed and IsUiPress(input)
				end
				if ignored then return end
				if Keybind.Mode == "Toggle" then
					Keybind._state = not Keybind._state
					if Keybind._state then Keybind.Click:Fire() end
					Keybind.Changed:Fire(Keybind._state)
					SafeCall(cfg.Callback, Keybind._state)
				else
					Keybind._state = true
					Keybind.Click:Fire()
					Keybind.Changed:Fire(true)
					SafeCall(cfg.Callback, true)
				end
			end))
			Track(UserInputService.InputEnded:Connect(function(input)
				if Keybind.Mode ~= "Hold" or not KeybindMatches(Keybind.Value, input) then return end
				-- Releases always arrive, including for presses ignored above.
				if not Keybind._state then return end
				Keybind._state = false
				Keybind.Changed:Fire(false)
				SafeCall(cfg.Callback, false)
			end))

			RegisterOption(id, Keybind)
			return row.Attach(Keybind)
		end

		--- Section:AddInput(id, { Title, Description, Default, Placeholder, Numeric, Finished, Width, Elevated, Callback })
		function Section:AddInput(id, cfg)
			id, cfg = NormalizeArgs(id, cfg)
			local W = cfg.Width or 130
			local row = CreateRow(cfg, W)

			local box = New("Frame", {
				BackgroundColor3 = theme.ElementBackground,
				Size = UDim2.fromOffset(W, 24),
				LayoutOrder = 1,
				Parent = row.Control,
			})
			Round(box, 6)
			local ring = Stroke(box, theme.Border, 1)
			local textbox = New("TextBox", {
				Text = cfg.Default or "",
				PlaceholderText = cfg.Placeholder or "",
				FontFace = Fonts.Regular,
				TextSize = 12,
				TextColor3 = theme.Text,
				PlaceholderColor3 = theme.DimText,
				ClearTextOnFocus = false,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(1, -16, 1, 0),
				Parent = box,
			})
			textbox.Focused:Connect(function()
				Tween(ring, { Color = theme.Accent }, 0.12)
				Tween(box, { BackgroundColor3 = theme.ElementBackgroundHover }, 0.12)
			end)
			textbox.FocusLost:Connect(function()
				Tween(ring, { Color = theme.Border }, 0.15)
				Tween(box, { BackgroundColor3 = theme.ElementBackground }, 0.15)
			end)

			local Input = { Value = cfg.Default or "", Changed = Signal.new(), Type = "Input", Box = textbox }
			local function Fire()
				Input.Value = textbox.Text
				Input.Changed:Fire(textbox.Text)
				SafeCall(cfg.Callback, textbox.Text)
			end
			function Input:OnChanged(fn) return Input.Changed:Connect(fn) end
			-- Fires Changed/Callback either way: a loaded config has to reach
			-- the callback whether or not the text actually differs.
			function Input:SetValue(text)
				text = text ~= nil and tostring(text) or ""
				if not cfg.Finished and textbox.Text ~= text then
					textbox.Text = text -- the Text listener below fires
					return
				end
				textbox.Text = text
				Fire()
			end

			if cfg.Numeric then
				textbox:GetPropertyChangedSignal("Text"):Connect(function()
					local filtered = textbox.Text:gsub("[^%d%.%-]", "")
					if filtered ~= textbox.Text then textbox.Text = filtered end
				end)
			end
			if cfg.Finished then
				textbox.FocusLost:Connect(function(enterPressed)
					if enterPressed then Fire() end
				end)
			else
				textbox:GetPropertyChangedSignal("Text"):Connect(Fire)
			end
			row.SetClick(function() textbox:CaptureFocus() end)

			RegisterOption(id, Input)
			return row.Attach(Input)
		end

		--- Section:AddButton({ Title, Description, ButtonText, Main, Elevated, Callback })
		function Section:AddButton(cfg)
			cfg = cfg or {}
			local text = cfg.ButtonText or "Run"
			local primary = cfg.Main or cfg.Primary
			local W = math.max(60, math.ceil(TextWidth(text, 12)) + 26)
			local row = CreateRow(cfg, W)

			local btn = New("TextButton", {
				Text = text,
				FontFace = Fonts.Medium,
				TextSize = 12,
				TextColor3 = primary and Color3.new(1, 1, 1) or theme.Text,
				BackgroundColor3 = primary and theme.Accent or theme.ElementBackground,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(W, 24),
				LayoutOrder = 1,
				Parent = row.Control,
			})
			Round(btn, 6)
			local stroke = Stroke(btn, primary and theme.Accent or theme.Border, 1)
			local restColor = primary and theme.Accent or theme.ElementBackground
			btn.MouseEnter:Connect(function()
				Tween(btn, { BackgroundColor3 = primary and theme.AccentHover or theme.ElementBackgroundHover }, 0.1)
			end)
			btn.MouseLeave:Connect(function()
				Tween(btn, { BackgroundColor3 = restColor }, 0.1)
			end)
			local function Click()
				stroke.Color = theme.Accent
				Tween(stroke, { Color = primary and theme.Accent or theme.Border }, 0.35)
				SafeCall(cfg.Callback)
			end
			btn.MouseButton1Click:Connect(Click)
			row.SetClick(Click)

			local Button = { Instance = btn, Type = "Button" }
			function Button:SetText(newText)
				btn.Text = newText
			end
			return row.Attach(Button)
		end

		--- Section:AddParagraph({ Title, Content }) -> { SetTitle, SetContent }
		function Section:AddParagraph(cfg)
			cfg = cfg or {}
			local card = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = NextOrder(),
				Parent = container,
			})
			Pad(card, 10, 8, 10, 8)
			List(card, { Padding = UDim.new(0, 3) })
			local titleLabel
			if cfg.Title then
				titleLabel = Label({
					Text = cfg.Title,
					FontFace = Fonts.Medium,
					TextSize = 12,
					TextColor3 = theme.Text,
					Size = UDim2.new(1, 0, 0, 15),
					LayoutOrder = 1,
					Parent = card,
				})
			end
			local contentLabel = Label({
				Text = cfg.Content or "",
				TextSize = 11.5,
				TextColor3 = theme.SubText,
				TextWrapped = true,
				RichText = true,
				LineHeight = 1.1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
				Parent = card,
			})
			local Paragraph = { Instance = card, Type = "Paragraph" }
			function Paragraph:SetTitle(text)
				if titleLabel then titleLabel.Text = text end
			end
			function Paragraph:SetContent(text)
				contentLabel.Text = text
			end
			function Paragraph:SetVisible(visible)
				card.Visible = visible and true or false
			end
			return Paragraph
		end

		return Section
	end

	--=========================================================================
	-- TABS
	--=========================================================================

	local function UpdateIndicator(animate)
		local tab = Window._activeTab
		if not tab or not tab._button.Parent then
			Indicator.Visible = false
			return
		end
		local btn = tab._button
		local x = btn.AbsolutePosition.X - TabBar.AbsolutePosition.X + 12
		local w = math.max(btn.AbsoluteSize.X - 24, 8)
		local props = { Position = UDim2.new(0, x, 1, 0), Size = UDim2.fromOffset(w, 2) }
		Indicator.Visible = true
		if animate then
			Tween(Indicator, props, 0.25, EASE_SOFT)
		else
			Indicator.Position = props.Position
			Indicator.Size = props.Size
		end
	end
	TabScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function() UpdateIndicator(false) end)
	TabList:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() UpdateIndicator(false) end)
	TabBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() UpdateIndicator(false) end)

	local function ApplySearchFilter()
		local query = Window._searchText:lower()
		local tab = Window._activeTab
		if not tab then return end
		for _, section in ipairs(tab._sections) do
			local titleMatch = query ~= "" and section.TitleLower:find(query, 1, true) ~= nil
			local anyVisible = false
			for _, entry in ipairs(section.Section._searchRows) do
				local visible = not entry.Hidden and (query == "" or titleMatch or entry.TitleLower:find(query, 1, true) ~= nil)
				entry.Instance.Visible = visible
				if visible then anyVisible = true end
			end
			section.Frame.Visible = query == "" or titleMatch or anyVisible
		end
	end
	SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
		Window._searchText = SearchBox.Text
		ApplySearchFilter()
	end)

	local function PaintTab(tab, active, animate)
		local t = animate and 0.15 or 0
		Tween(tab._button, { BackgroundTransparency = active and 0 or 1 }, t)
		Tween(tab._label, { TextColor3 = active and theme.Text or theme.SubText }, t)
		if tab._icon then
			Tween(tab._icon, { ImageColor3 = active and theme.Accent or theme.SubText }, t)
		end
	end

	-- Scrolls the tab bar just far enough to show the tab's button; Settings
	-- sits at the far end, so the header's "Manage configs" can land on it
	-- while it's scrolled out of view.
	local function ScrollTabIntoView(tab)
		local btn = tab._button
		local x = TabScroll.CanvasPosition.X
		local left = btn.AbsolutePosition.X - TabScroll.AbsolutePosition.X + x
		local right = left + btn.AbsoluteSize.X
		local view = TabScroll.AbsoluteSize.X
		if left < x then
			x = left
		elseif right > x + view then
			x = right - view
		end
		if x ~= TabScroll.CanvasPosition.X then
			TabScroll.CanvasPosition = Vector2.new(math.max(x, 0), 0)
		end
	end

	--- Window:SelectTab(indexOrTab) — 1-based over the tabs you added (the
	--- built-in settings tab isn't counted; pass Window.SettingsTab for it).
	function Window:SelectTab(target, instant)
		local tab = type(target) == "number" and self._tabs[target] or target
		if type(tab) ~= "table" or not tab._page then return end
		CloseAllPopups()
		local previous = self._activeTab
		self._activeTab = tab
		self._activeTabIndex = tab._index or 0
		for _, other in ipairs(self._tabs) do
			if other ~= tab then
				other._page.Visible = false
				PaintTab(other, false, not instant)
			end
		end
		if self.SettingsTab and self.SettingsTab ~= tab then
			self.SettingsTab._page.Visible = false
			PaintTab(self.SettingsTab, false, not instant)
		end
		tab._page.Visible = true
		PaintTab(tab, true, not instant)
		if previous ~= tab and not instant then
			local fromRight = tab._button.LayoutOrder > (previous and previous._button.LayoutOrder or 0)
			tab._page.Position = UDim2.fromOffset(fromRight and 10 or -10, 0)
			Tween(tab._page, { Position = UDim2.fromOffset(0, 0) }, 0.2, EASE_SOFT)
		else
			tab._page.Position = UDim2.fromOffset(0, 0)
		end
		ScrollTabIntoView(tab)
		UpdateIndicator(not instant and previous ~= nil)
		ApplySearchFilter()
	end

	local function CreateTab(tabConfig)
		local button = New("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = theme.ElementBackground,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 28),
			Parent = TabList,
		})
		Round(button, 7)
		Pad(button, 10, 0, 12, 0)
		Row(button, 7)
		local icon = Icon(tabConfig.Icon, 15, theme.SubText, { LayoutOrder = 1, Parent = button })
		local label = Label({
			Text = tabConfig.Title or "Tab",
			FontFace = Fonts.Medium,
			TextSize = 12,
			TextColor3 = theme.SubText,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = 2,
			Parent = button,
		})

		local page = New("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = theme.ElementBackgroundHover,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			Visible = false,
			Parent = PagesContainer,
		})
		-- Inset by position/size rather than a UIPadding on the page: inside a
		-- ScrollingFrame, Scale sizes resolve against the full canvas width and
		-- ignore the padding, which pushed the right column past the edge.
		local columnsFrame = New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.new(1, -28, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = page,
		})
		Pad(columnsFrame, 0, 0, 0, 14)

		local Tab = {
			Title = tabConfig.Title,
			_page = page,
			_button = button,
			_icon = icon,
			_label = label,
			_columns = {},
			_sectionCounts = {},
			_sections = {},
		}

		button.MouseEnter:Connect(function()
			if Window._activeTab ~= Tab then Tween(label, { TextColor3 = theme.Text }, 0.1) end
		end)
		button.MouseLeave:Connect(function()
			if Window._activeTab ~= Tab then Tween(label, { TextColor3 = theme.SubText }, 0.1) end
		end)
		button.MouseButton1Click:Connect(function()
			Window:SelectTab(Tab)
		end)

		local function RelayoutColumns()
			local c1, c2 = Tab._columns[1], Tab._columns[2]
			if c1 and c2 then
				c1.Position = UDim2.fromOffset(0, 0)
				c1.Size = UDim2.new(0.5, -COLUMN_GAP / 2, 0, 0)
				c2.Position = UDim2.new(0.5, COLUMN_GAP / 2, 0, 0)
				c2.Size = UDim2.new(0.5, -COLUMN_GAP / 2, 0, 0)
			elseif c1 or c2 then
				local only = c1 or c2
				only.Position = UDim2.fromOffset(0, 0)
				only.Size = UDim2.fromScale(1, 0)
			end
		end

		--- Tab:AddSection({ Title, Column = 1|2, Order }) -> Section
		function Tab:AddSection(sectionCfg)
			sectionCfg = sectionCfg or {}
			local columnIndex = math.clamp(math.floor(tonumber(sectionCfg.Column) or 1), 1, 2)
			if not Tab._columns[columnIndex] then
				local column = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Parent = columnsFrame,
				})
				List(column, { Padding = UDim.new(0, 14) })
				Tab._columns[columnIndex] = column
				RelayoutColumns()
			end
			Tab._sectionCounts[columnIndex] = (Tab._sectionCounts[columnIndex] or 0) + 1

			local sectionFrame = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = sectionCfg.Order or Tab._sectionCounts[columnIndex],
				Parent = Tab._columns[columnIndex],
			})
			List(sectionFrame, { Padding = UDim.new(0, 7) })
			if sectionCfg.Title then
				local head = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 16),
					LayoutOrder = 1,
					Parent = sectionFrame,
				})
				Pad(head, 2, 0, 2, 0)
				Row(head, 6)
				if sectionCfg.Icon then
					Icon(sectionCfg.Icon, 13, theme.SubText, { LayoutOrder = 1, Parent = head })
				end
				Label({
					Text = sectionCfg.Title,
					FontFace = Fonts.Medium,
					TextSize = 12.5,
					TextColor3 = theme.Text,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromScale(0, 1),
					LayoutOrder = 2,
					Parent = head,
				})
			end
			local card = New("Frame", {
				BackgroundColor3 = theme.SectionBackground,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
				Parent = sectionFrame,
			})
			Round(card, 8)
			Stroke(card, theme.Border, 1)
			Pad(card, 4, 4, 4, 4)
			List(card, { Padding = UDim.new(0, 2) })

			local Section = BuildSection(card, {})
			Section.Frame = sectionFrame
			table.insert(Tab._sections, {
				Frame = sectionFrame,
				Section = Section,
				TitleLower = (sectionCfg.Title or ""):lower(),
			})
			return Section
		end

		function Tab:Select()
			Window:SelectTab(Tab)
		end

		return Tab
	end

	--- Window:AddTab({ Title, Icon }) -> Tab. The first tab added is selected.
	function Window:AddTab(tabConfig)
		local tab = CreateTab(tabConfig or {})
		table.insert(self._tabs, tab)
		tab._index = #self._tabs
		tab._button.LayoutOrder = tab._index
		if #self._tabs == 1 then
			Window:SelectTab(tab, true)
			task.defer(UpdateIndicator, false)
		end
		return tab
	end

	--=========================================================================
	-- CONFIG STORE (same API as NovaUI's ribbon: Window.ConfigSelector and
	-- Window.Configs), driven from the header chip and the Settings tab.
	--=========================================================================

	local configFolder = config.ConfigFolder or ((config.Folder or "Ren") .. "/Games/" .. tostring(game.GameId))
	local configExtension = config.ConfigExtension or ".json"
	local AUTOLOAD_NAME = "_autoload"
	local notifyConfigs = config.ConfigNotifications ~= false

	local function ConfigPath(name)
		return configFolder .. "/" .. name .. configExtension
	end

	-- Backend: real files when the executor has them, else a session table.
	local Store = {}
	if FS.Ready then
		function Store.List()
			local names = {}
			if not FS.IsFolder(configFolder) then return names end
			local ok, files = pcall(FS.ListFiles, configFolder)
			if not ok or type(files) ~= "table" then return names end
			for _, path in ipairs(files) do
				local file = path:match("[^/\\]+$")
				if file and file:sub(-#configExtension) == configExtension then
					local name = file:sub(1, -#configExtension - 1)
					if name ~= AUTOLOAD_NAME then table.insert(names, name) end
				end
			end
			table.sort(names)
			return names
		end
		function Store.Exists(name)
			return FS.IsFile(ConfigPath(name)) and true or false
		end
		function Store.Read(name)
			if not FS.IsFile(ConfigPath(name)) then return nil end
			local ok, contents = pcall(FS.ReadFile, ConfigPath(name))
			return ok and type(contents) == "string" and contents or nil
		end
		function Store.Write(name, data)
			if not EnsureFolder(configFolder) then return false end
			return (pcall(FS.WriteFile, ConfigPath(name), data))
		end
		function Store.Delete(name)
			if not FS.IsFile(ConfigPath(name)) then return true end
			if type(FS.DeleteFile) ~= "function" then return false end
			return (pcall(FS.DeleteFile, ConfigPath(name)))
		end
	else
		Ren._memoryConfigs = Ren._memoryConfigs or {}
		local memory = Ren._memoryConfigs
		function Store.List()
			local names = {}
			for name in pairs(memory) do
				if name ~= AUTOLOAD_NAME then table.insert(names, name) end
			end
			table.sort(names)
			return names
		end
		function Store.Exists(name) return memory[name] ~= nil end
		function Store.Read(name) return memory[name] end
		function Store.Write(name, data)
			memory[name] = data
			return true
		end
		function Store.Delete(name)
			memory[name] = nil
			return true
		end
	end

	local function ConfigNotify(text, icon)
		if not notifyConfigs then return end
		Ren:Notify({ Title = config.Title or "Ren", Content = text, Icon = icon or "folder", Duration = 4 })
	end

	local configUIListeners = {}
	local RefreshConfigUI -- defined with the chip popup below

	local ConfigSelector = {
		Value = nil,
		AutoLoad = nil,
		Changed = Signal.new(),
		Save = Signal.new(),
		Created = Signal.new(),
		AutoLoadChanged = Signal.new(),
		_options = {},
	}
	function ConfigSelector:OnChanged(fn) return ConfigSelector.Changed:Connect(fn) end
	function ConfigSelector:OnSave(fn) return ConfigSelector.Save:Connect(fn) end
	function ConfigSelector:OnCreate(fn) return ConfigSelector.Created:Connect(fn) end
	function ConfigSelector:OnAutoLoad(fn) return ConfigSelector.AutoLoadChanged:Connect(fn) end
	function ConfigSelector:GetAutoLoad() return ConfigSelector.AutoLoad end

	function ConfigSelector:SetValue(name)
		ConfigSelector.Value = name
		RefreshConfigUI()
		ConfigSelector.Changed:Fire(name)
	end
	function ConfigSelector:SetAutoLoad(name, silent)
		if name == "" then name = nil end
		ConfigSelector.AutoLoad = name
		RefreshConfigUI()
		if not silent then ConfigSelector.AutoLoadChanged:Fire(name) end
	end
	local function PruneAutoLoad()
		if ConfigSelector.AutoLoad ~= nil and not table.find(ConfigSelector._options, ConfigSelector.AutoLoad) then
			ConfigSelector:SetAutoLoad(nil)
		end
	end
	function ConfigSelector:SetOptions(list)
		ConfigSelector._options = table.clone(list or {})
		if ConfigSelector.Value ~= nil and not table.find(ConfigSelector._options, ConfigSelector.Value) then
			ConfigSelector.Value = nil
		end
		RefreshConfigUI()
		PruneAutoLoad()
	end
	function ConfigSelector:AddOption(name)
		if table.find(ConfigSelector._options, name) then return end
		table.insert(ConfigSelector._options, name)
		table.sort(ConfigSelector._options)
		RefreshConfigUI()
	end
	function ConfigSelector:RemoveOption(name)
		local index = table.find(ConfigSelector._options, name)
		if not index then return end
		table.remove(ConfigSelector._options, index)
		if ConfigSelector.Value == name then ConfigSelector.Value = nil end
		RefreshConfigUI()
		PruneAutoLoad()
	end

	--- Window.Configs — the store behind the chip and the Settings tab.
	--- Persistent is false when there's no filesystem (configs then live in
	--- memory for the session).
	local Configs = {
		Folder = configFolder,
		Extension = configExtension,
		Ready = true,
		Persistent = FS.Ready,
		_autoLoaded = false,
	}
	function Configs:List() return Store.List() end
	function Configs:Path(name) return ConfigPath(name) end
	function Configs:Exists(name)
		if name == nil or name == "" then return false end
		return Store.Exists(name)
	end
	function Configs:Refresh()
		local names = Store.List()
		ConfigSelector:SetOptions(names)
		return names
	end
	--- Reads `name` and pushes it into every registered option.
	function Configs:Load(name)
		name = name or ConfigSelector.Value
		if name == nil or name == "" then return false end
		local data = Store.Read(name)
		if type(data) ~= "string" or data == "" then return false end
		if not Ren:ApplyConfig(data) then
			ConfigNotify("Couldn't read " .. name .. ".", "circle-alert")
			return false
		end
		ConfigNotify("Loaded <b>" .. name .. "</b>.", "download")
		return true
	end
	--- Writes the current state over `name` (default: the selected config).
	function Configs:Save(name)
		name = name or ConfigSelector.Value
		if name == nil or name == "" then return false end
		ConfigSelector.Save:Fire(name, Ren:ExportConfigJSON())
		return true
	end
	--- Same as the Create button: writes current state under a new name and
	--- selects it.
	function Configs:Create(name)
		if name == nil or name == "" then return false end
		local json = Ren:ExportConfigJSON()
		-- Written before it's selected, so the Changed -> Load that selecting
		-- triggers finds the file instead of a missing one.
		Store.Write(name, json)
		ConfigSelector:AddOption(name)
		ConfigSelector.Value = name
		RefreshConfigUI()
		ConfigSelector.Created:Fire(name, json)
		return true
	end
	function Configs:Delete(name)
		name = name or ConfigSelector.Value
		if name == nil or name == "" then return false end
		if not Store.Delete(name) then return false end
		ConfigSelector:RemoveOption(name)
		ConfigNotify("Deleted <b>" .. name .. "</b>.", "trash-2")
		return true
	end
	function Configs:AutoLoad()
		if Configs._autoLoaded then return false end
		local name = Store.Read(AUTOLOAD_NAME)
		if type(name) == "string" then
			name = name:gsub("^%s+", ""):gsub("%s+$", "")
		end
		if name == nil or name == "" then return false end
		if not Store.Exists(name) then
			ConfigSelector:SetAutoLoad(nil)
			return false
		end
		Configs._autoLoaded = true
		ConfigSelector:SetAutoLoad(name, true)
		ConfigSelector:SetValue(name)
		return true
	end

	-- The store listens on the same signals a consumer can hook, so extra
	-- OnSave/OnCreate/OnChanged handlers keep working on top of it.
	ConfigSelector:OnChanged(function(name)
		Configs:Load(name)
	end)
	ConfigSelector:OnSave(function(name, json)
		if Store.Write(name, json) then
			ConfigSelector:AddOption(name)
			ConfigNotify("Saved <b>" .. name .. "</b>.", "save")
		else
			ConfigNotify("Couldn't save " .. name .. ".", "circle-alert")
		end
	end)
	ConfigSelector:OnCreate(function(name)
		ConfigNotify("Created <b>" .. name .. "</b>.", "file-plus")
	end)
	ConfigSelector:OnAutoLoad(function(name)
		if name == nil then
			Store.Delete(AUTOLOAD_NAME)
		else
			Store.Write(AUTOLOAD_NAME, name)
		end
	end)

	Window.ConfigSelector = ConfigSelector
	Window.Configs = Configs

	function Window:LoadConfig(data)
		return Ren:ApplyConfig(data)
	end
	--- Call once, after every tab/section/element exists: selects and
	--- applies the config marked for autoload, if any.
	function Window:StartAutoLoad()
		return Configs:AutoLoad()
	end

	-- Header chip: quick switcher onto the store.
	local ConfigPopup = New("Frame", {
		BackgroundColor3 = theme.PopupBackground,
		Size = UDim2.fromOffset(210, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = Overlay,
	})
	Round(ConfigPopup, 8)
	Stroke(ConfigPopup, theme.Border, 1)
	AddShadow(ConfigPopup, { Transparency = 0.4, OffsetY = 6, Blur = 16 })
	Pad(ConfigPopup, 5)
	List(ConfigPopup, { Padding = UDim.new(0, 2) })
	Label({
		Text = "CONFIGS",
		FontFace = Fonts.Bold,
		TextSize = 10,
		TextColor3 = theme.DimText,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1,
		Parent = Pad(New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Parent = ConfigPopup }), 8, 0, 8, 0),
	})
	local ConfigList = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 26),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = theme.ElementBackgroundHover,
		LayoutOrder = 2,
		Parent = ConfigPopup,
	})
	List(ConfigList, { Padding = UDim.new(0, 2) })
	local ConfigEmpty = Label({
		Text = "No configs yet",
		TextSize = 12,
		TextColor3 = theme.DimText,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 3,
		Parent = Pad(New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 3, Parent = ConfigPopup }), 8, 0, 8, 0),
	})
	New("Frame", {
		BackgroundColor3 = theme.Divider,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = 4,
		Parent = ConfigPopup,
	})

	local function PopupAction(text, iconName, order, callback)
		local btn = New("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = theme.ElementBackground,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = order,
			Parent = ConfigPopup,
		})
		Round(btn, 5)
		Pad(btn, 8, 0, 8, 0)
		Row(btn, 8)
		local image = Icon(iconName, 13, theme.SubText, { LayoutOrder = 1, Parent = btn })
		local label = Label({
			Text = text,
			FontFace = Fonts.Medium,
			TextSize = 12,
			TextColor3 = theme.SubText,
			Size = UDim2.new(1, -24, 1, 0),
			LayoutOrder = 2,
			Parent = btn,
		})
		btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0 }, 0.08)
			label.TextColor3 = theme.Text
			if image then image.ImageColor3 = theme.Text end
		end)
		btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.08)
			label.TextColor3 = theme.SubText
			if image then image.ImageColor3 = theme.SubText end
		end)
		btn.MouseButton1Click:Connect(callback)
		return btn
	end
	local chipSaveAction = PopupAction("Save current", "save", 5, function()
		ClosePopupFor(ConfigPopup)
		if ConfigSelector.Value then
			Configs:Save()
		else
			Window:SelectTab(Window.SettingsTab or 1)
		end
	end)
	PopupAction("Manage configs", "settings", 6, function()
		ClosePopupFor(ConfigPopup)
		if Window.SettingsTab then Window:SelectTab(Window.SettingsTab) end
	end)

	RefreshConfigUI = function()
		ChipLabel.Text = ConfigSelector.Value or "No config"
		chipSaveAction.Visible = ConfigSelector.Value ~= nil
		for _, child in ipairs(ConfigList:GetChildren()) do
			if child:IsA("GuiButton") then child:Destroy() end
		end
		for index, name in ipairs(ConfigSelector._options) do
			local selected = ConfigSelector.Value == name
			local btn = New("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = theme.ElementBackground,
				BackgroundTransparency = selected and 0.4 or 1,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = index,
				Parent = ConfigList,
			})
			Round(btn, 5)
			Label({
				Text = name,
				FontFace = Fonts.Medium,
				TextSize = 12,
				TextColor3 = selected and theme.Text or theme.SubText,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(9, 0),
				Size = UDim2.new(1, -60, 1, 0),
				Parent = btn,
			})
			if ConfigSelector.AutoLoad == name then
				Label({
					Text = "AUTO",
					FontFace = Fonts.Bold,
					TextSize = 9,
					TextColor3 = theme.Accent,
					TextXAlignment = Enum.TextXAlignment.Right,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, selected and -26 or -9, 0.5, 0),
					Size = UDim2.fromOffset(30, 12),
					Parent = btn,
				})
			end
			if selected then
				Icon("check", 12, theme.Accent, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -9, 0.5, 0),
					Parent = btn,
				})
			end
			btn.MouseEnter:Connect(function() Tween(btn, { BackgroundTransparency = 0 }, 0.08) end)
			btn.MouseLeave:Connect(function() Tween(btn, { BackgroundTransparency = selected and 0.4 or 1 }, 0.08) end)
			btn.MouseButton1Click:Connect(function()
				ClosePopupFor(ConfigPopup)
				ConfigSelector:SetValue(name)
			end)
		end
		local count = #ConfigSelector._options
		ConfigList.Visible = count > 0
		ConfigEmpty.Parent.Visible = count == 0
		ConfigList.Size = UDim2.new(1, 0, 0, math.min(count, 6) * 28 - 2)
		for _, listener in ipairs(configUIListeners) do
			listener()
		end
	end

	ConfigChip.MouseButton1Click:Connect(function()
		OpenPopup(ConfigPopup, ConfigChip, { Align = "right" })
	end)

	--=========================================================================
	-- SETTINGS TAB
	--=========================================================================

	if config.SettingsTab ~= false then
		local settings = CreateTab({ Title = config.SettingsTitle or "Settings", Icon = config.SettingsIcon or "settings" })
		-- Created before any of the script's tabs, but ordered after all of
		-- them so it always ends the list.
		settings._button.LayoutOrder = 2 ^ 30
		Window.SettingsTab = settings

		local syncing = false
		local function Trim(text)
			return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
		end
		local function RequireSelection()
			if ConfigSelector.Value then return ConfigSelector.Value end
			Ren:Notify({ Title = "Configs", Content = "Select or create a config first.", Icon = "info", Duration = 3 })
			return nil
		end

		local configsSection = settings:AddSection({ Title = "Configs", Column = 1 })
		local storage = configsSection:AddParagraph({
			Title = "Storage",
			Content = FS.Ready
				and ("Saved to <font color=\"#" .. theme.Text:ToHex() .. "\">" .. configFolder .. "</font>")
				or "No file access here — configs are kept for this session only.",
		})
		local selector = configsSection:AddDropdown(nil, {
			Title = "Config",
			Description = "Selecting one loads it",
			Values = {},
			Width = 130,
			Callback = function(name)
				if syncing then return end
				if name ~= nil and name ~= ConfigSelector.Value then
					ConfigSelector:SetValue(name)
				end
			end,
		})
		local CreateFromInput
		local nameInput = configsSection:AddInput(nil, {
			Title = "New config",
			Placeholder = "Config name",
			Width = 130,
			Finished = true,
			-- Enter in the field creates, same as the button below.
			Callback = function(text)
				if Trim(text) ~= "" and CreateFromInput then CreateFromInput() end
			end,
		})
		function CreateFromInput()
			local name = Trim(nameInput.Box.Text)
			if name == "" or name == AUTOLOAD_NAME or name:find("[/\\:*?\"<>|]") then
				Ren:Notify({ Title = "Configs", Content = "Enter a valid config name first.", Icon = "info", Duration = 3 })
				return
			end
			if Configs:Exists(name) then
				Window:Dialog({
					Title = "Overwrite " .. name .. "?",
					Content = "A config with this name already exists.",
					Buttons = {
						{ Title = "Cancel" },
						{ Title = "Overwrite", Main = true, Callback = function()
							ConfigSelector.Value = name
							Configs:Save(name)
							RefreshConfigUI()
						end },
					},
				})
				return
			end
			Configs:Create(name)
			nameInput:SetValue("")
		end
		configsSection:AddButton({ Title = "Create config", Description = "Saves current settings under the new name", ButtonText = "Create", Main = true, Callback = CreateFromInput })
		configsSection:AddButton({ Title = "Save config", Description = "Overwrites the selected config", ButtonText = "Save", Callback = function()
			if RequireSelection() then Configs:Save() end
		end })
		configsSection:AddButton({ Title = "Load config", Description = "Re-applies the selected config", ButtonText = "Load", Callback = function()
			local name = RequireSelection()
			if name then Configs:Load(name) end
		end })
		local autoloadButton = configsSection:AddButton({ Title = "Autoload", Description = "None", ButtonText = "Set selected", Callback = function()
			local name = RequireSelection()
			if not name then return end
			if ConfigSelector.AutoLoad == name then
				ConfigSelector:SetAutoLoad(nil)
				ConfigNotify("Autoload cleared.", "zap")
			else
				ConfigSelector:SetAutoLoad(name)
				ConfigNotify("<b>" .. name .. "</b> will load on startup.", "zap")
			end
		end })
		configsSection:AddButton({ Title = "Delete config", Description = "Removes the selected config", ButtonText = "Delete", Callback = function()
			local name = RequireSelection()
			if not name then return end
			Window:Dialog({
				Title = "Delete " .. name .. "?",
				Content = "This can't be undone.",
				Buttons = {
					{ Title = "Cancel" },
					{ Title = "Delete", Main = true, Callback = function() Configs:Delete(name) end },
				},
			})
		end })
		configsSection:AddButton({ Title = "Refresh list", ButtonText = "Refresh", Callback = function()
			Configs:Refresh()
		end })

		table.insert(configUIListeners, function()
			syncing = true
			selector:SetOptions(ConfigSelector._options)
			selector:SetValue(ConfigSelector.Value)
			syncing = false
			local marked = ConfigSelector.AutoLoad
			autoloadButton:SetDescription(marked and ("Loads " .. marked .. " on startup") or "Nothing loads on startup")
			autoloadButton:SetText((marked ~= nil and marked == ConfigSelector.Value) and "Clear" or "Set selected")
		end)

		local interface = settings:AddSection({ Title = "Interface", Column = 2 })
		interface:AddKeybind(nil, {
			Title = "Menu keybind",
			Description = "Shows / hides the window",
			Default = Window.ToggleKey,
			ChangedCallback = function(key)
				Window.ToggleKey = key
			end,
		})
		interface:AddToggle(nil, {
			Title = "Config notifications",
			Default = notifyConfigs,
			Callback = function(on)
				notifyConfigs = on
			end,
		})
		interface:AddToggle(nil, {
			Title = "Reduced effects",
			Description = "Turns off shadows and glows",
			Default = Ren.ReducedEffects,
			Callback = function(on)
				Ren:SetReducedEffects(on)
			end,
		})
		interface:AddButton({ Title = "Unload interface", ButtonText = "Unload", Callback = function()
			Window:Dialog({
				Title = "Unload " .. (config.Title or "the interface") .. "?",
				Content = "The window closes and its keybinds stop working.",
				Buttons = {
					{ Title = "Cancel" },
					{ Title = "Unload", Main = true, Callback = function()
						task.delay(0.14, function() Window:Destroy() end)
					end },
				},
			})
		end })

		local about = settings:AddSection({ Title = "About", Column = 2 })
		about:AddParagraph({
			Title = (config.Title or "Ren") .. (subTitle and ("  ·  " .. subTitle) or ""),
			Content = (LocalPlayer and ("Signed in as " .. LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")\n") or "")
				.. "Built on Ren " .. Ren.Version .. ".",
		})
		Window._storageParagraph = storage
	end

	-- Read the autoload mark before filling the list: SetOptions prunes a
	-- mark it can't find a config for.
	do
		local marked = Store.Read(AUTOLOAD_NAME)
		Configs:Refresh()
		if type(marked) == "string" and marked ~= "" and table.find(ConfigSelector._options, marked) then
			ConfigSelector:SetAutoLoad(marked, true)
		end
	end

	-- Nothing selected until a tab is added; show Settings meanwhile.
	if Window.SettingsTab then
		Window:SelectTab(Window.SettingsTab, true)
		task.defer(UpdateIndicator, false)
	end

	-- Opening animation: a short rise + scale-in, no bounce.
	do
		local target = Main.Position
		Main.Position = target + UDim2.fromOffset(0, 8)
		Tween(Main, { Position = target }, 0.25, EASE_SOFT)
		Tween(MainScale, { Scale = 1 }, 0.22, EASE_SOFT)
		if MainShadow then Tween(MainShadow, { Transparency = 0.25 }, 0.3) end
	end

	return Window
end

return Ren
