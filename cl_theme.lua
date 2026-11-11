RPInv.Theme = RPInv.Theme or {}
local T = RPInv.Theme
T.Tracked = T.Tracked or setmetatable({}, { __mode = "k" })

local palette = {
	Green = Color(206, 202, 184),
	Mid = Color(146, 143, 128),
	Dim = Color(78, 79, 72),
	Faint = Color(52, 53, 49),
	Accent = Color(214, 170, 72),
	White = Color(235, 235, 228),
	Red = Color(196, 62, 48),
	WinBg = Color(14, 15, 14, 245), HeadBg = Color(34, 35, 33, 255), BarBg = Color(8, 9, 8, 240),
	CellBg = Color(22, 23, 22, 235), CellLine = Color(46, 48, 45, 255),
	InputBg = Color(10, 11, 10, 255), ListBg = Color(18, 19, 18, 240),
	BtnBg = Color(40, 41, 38, 255), BtnHover = Color(214, 170, 72, 40), MenuBg = Color(22, 23, 21, 252),
	Sel = Color(214, 170, 72, 60), Hover = Color(255, 255, 255, 18),
	TabOn = Color(196, 194, 180, 255), TabOnText = Color(16, 17, 16),
	Overlay = Color(0, 0, 0, 0), OverlayHover = Color(255, 255, 255, 28),
	ScreenDim = Color(6, 7, 6, 200),
	GhostOk = Color(90, 170, 70, 95), GhostBad = Color(190, 50, 40, 95), GhostMerge = Color(214, 160, 50, 105),
	ItemHover = Color(255, 255, 255, 34), SearchDim = Color(0, 0, 0, 175), SearchHit = Color(214, 170, 72, 255),
	Tints = {
		heal = Color(120, 34, 34, 80), armor = Color(40, 70, 115, 80),
		weapon = Color(66, 66, 54, 90), ammo = Color(130, 92, 30, 80), none = Color(70, 70, 66, 60),
		attachment = Color(54, 78, 70, 85),
	},
	FontName = "Bahnschrift",
}

T.Scale = 1

local function font(name, size, weight)
	surface.CreateFont(name, { font = palette.FontName, size = math.max(9, math.Round(size * T.Scale)), weight = weight or 600, antialias = true, extended = true })
end

local function makeFonts()
	T.Scale = math.Clamp(ScrH() / 1080, 0.7, 1.4)
	font("RPInv.Big", 30, 700)
	font("RPInv.Title", 22, 700)
	font("RPInv.Tab", 19, 700)
	font("RPInv.Text", 16, 600)
	font("RPInv.Small", 13, 600)
	font("RPInv.Tiny", 11, 600)
	font("RPInv.Count", 15, 700)
end

function T.Apply()
	for k, v in pairs(palette) do T[k] = v end
	makeFonts()
	for p, role in pairs(T.Tracked) do
		if IsValid(p) then p:SetTextColor(T[role]) end
	end
	hook.Run("RPInv_ThemeChanged")
end

T.Apply()
hook.Add("OnScreenSizeChanged", "RPInv_Fonts", function() T.Apply() end)

function T.CellSize()
	return math.Clamp(math.Round(ScrH() * 0.0555), 36, 72)
end

function T.S(v)
	return math.Round(v * T.Scale)
end

function T.FormatTitle(title)
	if type(title) == "function" then title = title() end
	local t = title:gsub(" :: ", "  -  ")
	t = t:gsub("_", " ")
	return t
end

function T.Corners(x, y, w, h, len, thick)
	thick = thick or 2
	surface.DrawRect(x, y, len, thick) surface.DrawRect(x, y, thick, len)
	surface.DrawRect(x + w - len, y, len, thick) surface.DrawRect(x + w - thick, y, thick, len)
	surface.DrawRect(x, y + h - thick, len, thick) surface.DrawRect(x, y + h - len, thick, len)
	surface.DrawRect(x + w - len, y + h - thick, len, thick) surface.DrawRect(x + w - thick, y + h - len, thick, len)
end

function T.Hatch(w, h, step, col)
	surface.SetDrawColor(col or T.Faint)
	for i = -h, w, step do
		surface.DrawLine(i, h, i + h, 0)
	end
end

function T.Frame(title, w, h)
	local f = vgui.Create("DFrame")
	f:SetSize(w, h)
	f:SetTitle("")
	f:ShowCloseButton(false)
	f:SetDraggable(true)
	f:MakePopup()
	f.Title = title
	f.Info = ""

	f.Paint = function(s, pw, ph)
		surface.SetDrawColor(T.WinBg)
		surface.DrawRect(0, 0, pw, ph)
		surface.SetDrawColor(T.HeadBg)
		surface.DrawRect(0, 0, pw, 32)
		surface.SetDrawColor(T.Accent)
		surface.DrawRect(0, 31, pw, 1)
		surface.DrawRect(0, 0, 4, 32)
		draw.SimpleText(T.FormatTitle(s.Title), "RPInv.Title", 16, 16, T.Green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if s.Info and s.Info ~= "" then
			draw.SimpleText(s.Info, "RPInv.Small", 10, ph - 14, T.Mid, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		surface.SetDrawColor(T.Dim)
		surface.DrawOutlinedRect(0, 0, pw, ph, 1)
	end

	local close = T.CloseButton(f, function() f:Close() end)
	close:SetPos(w - 30, 4)
	return f
end

function T.CloseButton(parent, fn)
	local close = vgui.Create("DButton", parent)
	close:SetText("")
	close:SetSize(24, 24)
	close.Paint = function(s, bw, bh)
		surface.SetDrawColor(s:IsHovered() and T.Red or Color(120, 40, 32))
		surface.DrawRect(0, 0, bw, bh)
		draw.SimpleText("X", "RPInv.Text", bw / 2, bh / 2, T.White, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	close.DoClick = function()
		surface.PlaySound("ui/buttonclick.wav")
		fn()
	end
	return close
end

function T.DrawCell(w, h, hover, tintKey)
	surface.SetDrawColor(T.CellBg)
	surface.DrawRect(0, 0, w, h)
	local tint = tintKey and T.Tints[tintKey]
	if tint then
		surface.SetDrawColor(tint)
		surface.DrawRect(1, 1, w - 2, h - 2)
	end
	surface.SetDrawColor(hover and T.Accent or T.Dim)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
end

function T.StyleButton(b)
	b:SetFont("RPInv.Text")
	b:SetTextColor(T.Green)
	T.Tracked[b] = "Green"
	b.Paint = function(s, w, h)
		surface.SetDrawColor(T.BtnBg)
		surface.DrawRect(0, 0, w, h)
		if s:IsHovered() then
			surface.SetDrawColor(T.BtnHover)
			surface.DrawRect(0, 0, w, h)
		end
		surface.SetDrawColor(s:IsHovered() and T.Accent or T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
end

function T.Button(parent, text, w, fn)
	local b = vgui.Create("DButton", parent)
	b:SetText(text)
	if w then b:SetWide(w) end
	T.StyleButton(b)
	b.DoClick = function(...)
		surface.PlaySound("ui/buttonclick.wav")
		if fn then fn(...) end
	end
	return b
end

function T.ConfirmButton(parent, text, w, fn)
	local b
	b = T.Button(parent, text, w, function()
		if b.Armed then
			b.Armed = false
			b:SetText(text)
			fn()
		else
			b.Armed = true
			b:SetText("CONFIRM?")
			timer.Simple(3, function()
				if IsValid(b) then b.Armed = false b:SetText(text) end
			end)
		end
	end)
	return b
end

function T.Label(parent, text, font)
	local l = vgui.Create("DLabel", parent)
	l:SetText(text)
	l:SetFont(font or "RPInv.Text")
	l:SetTextColor(T.Mid)
	T.Tracked[l] = "Mid"
	l:SetTall(16)
	return l
end

function T.TextEntry(parent, placeholder)
	local te = vgui.Create("DTextEntry", parent)
	te:SetFont("RPInv.Text")
	te.Placeholder = placeholder
	te.Paint = function(s, w, h)
		surface.SetDrawColor(T.InputBg)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(s:HasFocus() and T.Accent or T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		if s.Placeholder and s:GetText() == "" and not s:HasFocus() then
			draw.SimpleText(s.Placeholder, "RPInv.Small", 6, h / 2, T.Dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		s:DrawTextEntryText(T.Green, T.Sel, T.Accent)
	end
	return te
end

function T.Field(parent, label, text, numeric)
	local l = T.Label(parent, label, "RPInv.Small")
	l:Dock(TOP)
	local te = T.TextEntry(parent)
	te:Dock(TOP)
	te:SetTall(24)
	te:DockMargin(0, 0, 0, 6)
	te:SetText(text or "")
	if numeric then te:SetNumeric(true) end
	return te
end

function T.StyleScroll(panel)
	local vbar = (panel.GetVBar and panel:GetVBar()) or panel.VBar
	if not IsValid(vbar) then return end
	vbar:SetWide(6)
	vbar:SetHideButtons(true)
	vbar.Paint = function(_, w, h)
		surface.SetDrawColor(T.ListBg)
		surface.DrawRect(0, 0, w, h)
	end
	vbar.btnGrip.Paint = function(s, w, h)
		surface.SetDrawColor(s:IsHovered() and T.Mid or T.Dim)
		surface.DrawRect(0, 0, w, h)
	end
end

function T.List(parent, cols)
	local l = vgui.Create("DListView", parent)
	l:SetMultiSelect(false)
	l:SetHeaderHeight(22)
	l:SetDataHeight(20)
	l.Paint = function(_, w, h)
		surface.SetDrawColor(T.ListBg)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	for _, c in ipairs(cols) do
		local col = l:AddColumn(c.name)
		if c.w then col:SetFixedWidth(c.w) end
		col.Header:SetFont("RPInv.Small")
		col.Header:SetTextColor(T.Green)
		T.Tracked[col.Header] = "Green"
		col.Header.Paint = function(_, w, h)
			surface.SetDrawColor(T.HeadBg)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(T.Dim)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end
	end
	T.StyleScroll(l)
	return l
end

function T.AddLine(list, ...)
	local line = list:AddLine(...)
	line.Paint = function(s, w, h)
		if s:IsSelected() then
			surface.SetDrawColor(T.Sel)
			surface.DrawRect(0, 0, w, h)
		elseif s:IsHovered() then
			surface.SetDrawColor(T.Hover)
			surface.DrawRect(0, 0, w, h)
		end
	end
	line.ApplySchemeSettings = function(s)
		for _, c in ipairs(s.Columns) do
			c:SetFont("RPInv.Small")
			c:SetTextColor(T.Green)
		end
	end
	line:ApplySchemeSettings()
	return line
end

function T.Menu()
	local m = DermaMenu()
	m.Paint = function(_, w, h)
		surface.SetDrawColor(T.MenuBg)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	return m
end

function T.MenuOption(m, text, fn)
	local o = m:AddOption(text, function()
		surface.PlaySound("ui/buttonclick.wav")
		fn()
	end)
	o:SetFont("RPInv.Text")
	o:SetTextColor(T.Green)
	o:SetTextInset(12, 0)
	o.Paint = function(s, w, h)
		if s:IsHovered() then
			surface.SetDrawColor(T.Sel)
			surface.DrawRect(0, 0, w, h)
		end
	end
	return o
end

function T.Confirm(text, onYes)
	local f = T.Frame("CONFIRM", 380, 140)
	f:Center()
	local l = T.Label(f, text, "RPInv.Text")
	l:SetPos(16, 52)
	l:SetSize(348, 20)
	local yes = T.Button(f, "YES", 110, function() f:Close() onYes() end)
	yes:SetPos(16, 96)
	yes:SetTall(30)
	local no = T.Button(f, "NO", 110, function() f:Close() end)
	no:SetPos(140, 96)
	no:SetTall(30)
end
