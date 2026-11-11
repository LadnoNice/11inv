local T = RPInv.Theme
local I = RPInv.Icons
RPInv.Presets = RPInv.Presets or {}

local CELL, GAP, HEAD = 76, 6, 26
local GROUPS = {
	{ "heal", "MEDICAL / FOOD" },
	{ "armor", "ARMOR" },
	{ "weapon", "WEAPONS" },
	{ "ammo", "AMMO" },
	{ "attachment", "ATTACHMENTS" },
	{ "throw", "GRENADES" },
	{ "place", "JMOD ITEMS" },
	{ "none", "MISC" },
}

local root

local function requestPresets()
	net.Start("rpinv_a_plist")
	net.SendToServer()
end

local function itemNet(name, id, amount)
	net.Start(name)
	net.WriteString(id)
	net.WriteUInt(amount, 16)
	net.SendToServer()
end

local function spawnPreset(id)
	net.Start("rpinv_a_pspawn")
	net.WriteUInt(id, 32)
	net.SendToServer()
end

local function makeTile(layout, label, tip, paintIcon)
	local b = layout:Add("DButton")
	b:SetSize(CELL, CELL)
	b:SetText("")
	b:SetTooltip(tip)
	b.Paint = function(s, w, h)
		surface.SetDrawColor(T.CellBg)
		surface.DrawRect(0, 0, w, h)
		paintIcon(w, h)
		if s:IsHovered() then
			surface.SetDrawColor(T.ItemHover)
			surface.DrawRect(0, 0, w, h)
		end
		surface.SetDrawColor(0, 0, 0, 170)
		surface.DrawRect(0, h - 16, w, 16)
		draw.SimpleText(string.sub(label, 1, 11), "RPInv.Tiny", w / 2, h - 8, T.Green, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(s:IsHovered() and T.Accent or T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	return b
end

local function itemIcon(def)
	return function(w, h)
		local tint = T.Tints[def.use_type] or T.Tints.none
		surface.SetDrawColor(tint)
		surface.DrawRect(1, 1, w - 2, h - 17)
		local aw, ah = def.w, def.h
		local box = math.min((w - 8) / aw, (h - 24) / ah)
		local pw, ph = aw * box, ah * box
		I.Draw(def, (w - pw) / 2, (h - 16 - ph) / 2, pw, ph, 0)
		draw.SimpleText(aw .. "x" .. ah, "RPInv.Tiny", w - 3, 2, T.Dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	end
end

local function addSection(scroll, title, count, fill)
	local sec = scroll:Add("DPanel")
	sec:Dock(TOP)
	sec:DockMargin(0, 0, 0, 8)
	sec.Paint = function(_, w)
		draw.SimpleText(title, "RPInv.Text", 4, HEAD / 2, T.Green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(T.Dim)
		surface.DrawRect(0, HEAD - 2, w, 1)
		if count == 0 then
			draw.SimpleText("(nothing here yet)", "RPInv.Small", 4, HEAD + 10, T.Dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	local layout = vgui.Create("DIconLayout", sec)
	layout:SetSpaceX(GAP)
	layout:SetSpaceY(GAP)
	fill(layout)
	sec.PerformLayout = function(s, w)
		layout:SetPos(0, HEAD + 2)
		layout:SetWide(w)
		local per = math.max(1, math.floor((w + GAP) / (CELL + GAP)))
		local rows = math.max(1, math.ceil(count / per))
		local lh = count == 0 and 24 or rows * (CELL + GAP)
		if layout:GetTall() ~= lh then layout:SetTall(lh) end
		if s:GetTall() ~= HEAD + 2 + lh then s:SetTall(HEAD + 2 + lh) end
	end
end

local function rebuild()
	if not IsValid(root) then return end
	root.Dirty = false
	local admin = LocalPlayer():IsSuperAdmin()
	root.Admin = admin
	root.Bar:SetVisible(admin)

	if IsValid(root.Scroll) then root.Scroll:Remove() end
	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(8, 4, 8, 8)
	T.StyleScroll(scroll)
	root.Scroll = scroll

	if not admin then
		local l = T.Label(scroll, "SUPERADMIN ACCESS ONLY", "RPInv.Title")
		l:Dock(TOP)
		l:SetTall(30)
		l:DockMargin(10, 10, 0, 0)
		return
	end

	local query = string.lower(string.Trim(root.Query or ""))
	local function matches(d)
		if query == "" then return true end
		local hay = string.lower(d.name .. " " .. d.id .. " " .. (d.category or "") .. " " .. (d.use_arg or ""))
		return string.find(hay, query, 1, true) ~= nil
	end
	local byGroup = {}
	for _, d in pairs(RPInv.Items) do
		if matches(d) then
			local g = "none"
			for _, gg in ipairs(GROUPS) do
				if gg[1] == d.use_type then g = gg[1] end
			end
			byGroup[g] = byGroup[g] or {}
			table.insert(byGroup[g], d)
		end
	end
	for _, g in ipairs(GROUPS) do
		local list = byGroup[g[1]]
		if list then
			table.sort(list, function(a, b) return a.name < b.name end)
			addSection(scroll, "ITEMS :: " .. g[2], #list, function(layout)
				for _, d in ipairs(list) do
					local tip = d.name .. "  (" .. d.w .. "x" .. d.h .. ")\n" .. d.descr .. "\n\nClick: spawn at crosshair\nRight-click: more"
					local b = makeTile(layout, d.name, tip, itemIcon(d))
					b.DoClick = function() itemNet("rpinv_a_spawn", d.id, 1) end
					b.DoRightClick = function()
						local m = T.Menu()
						T.MenuOption(m, "SPAWN ONE", function() itemNet("rpinv_a_spawn", d.id, 1) end)
						if d.max_stack > 1 then
							T.MenuOption(m, "SPAWN FULL STACK (" .. d.max_stack .. ")", function() itemNet("rpinv_a_spawn", d.id, d.max_stack) end)
						end
						T.MenuOption(m, "GIVE ME ONE", function() itemNet("rpinv_a_give", d.id, 1) end)
						if d.max_stack > 1 then
							T.MenuOption(m, "GIVE ME FULL STACK", function() itemNet("rpinv_a_give", d.id, d.max_stack) end)
						end
						T.MenuOption(m, "INSPECT", function() RPInv.Inspect(d) end)
						m:Open()
					end
				end
			end)
		end
	end

	addSection(scroll, "CONTAINER PRESETS", #RPInv.Presets, function(layout)
		for _, p in ipairs(RPInv.Presets) do
			local tip = string.format("%s\nGrid: %d x %d | Stacks: %d\n\nClick: spawn at crosshair\nRight-click: more", p.name, p.w or 0, p.h or 0, p.stacks or 0)
			local mdlDef = { model = p.model, w = 1, h = 1, cam_ang = "", cam_fov = 1, name = p.name }
			local b = makeTile(layout, p.name, tip, function(w, h)
				I.Draw(mdlDef, 6, 4, w - 12, h - 24, 0)
				draw.SimpleText((p.w or 0) .. "x" .. (p.h or 0), "RPInv.Tiny", w - 3, 2, T.Dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
			end)
			b.DoClick = function() spawnPreset(p.id) end
			b.DoRightClick = function()
				local m = T.Menu()
				T.MenuOption(m, "SPAWN", function() spawnPreset(p.id) end)
				T.MenuOption(m, "UPDATE FROM AIMED CONTAINER", function()
					RPInv.SendJSON("rpinv_a_psave", { id = p.id, from_aimed = true })
				end)
				T.MenuOption(m, "DELETE PRESET", function()
					T.Confirm("Delete preset '" .. p.name .. "'?", function()
						net.Start("rpinv_a_pdelete")
						net.WriteUInt(p.id, 32)
						net.SendToServer()
					end)
				end)
				m:Open()
			end
		end
	end)
end

local function buildRoot()
	root = vgui.Create("DPanel")
	root.Paint = function(_, w, h)
		surface.SetDrawColor(T.WinBg)
		surface.DrawRect(0, 0, w, h)
	end

	local bar = vgui.Create("DPanel", root)
	bar:Dock(TOP)
	bar:SetTall(66)
	bar:DockPadding(8, 8, 8, 0)
	bar.Paint = function(_, w, h)
		surface.SetDrawColor(T.HeadBg)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(T.Accent)
		surface.DrawRect(0, h - 1, w, 1)
	end
	root.Bar = bar

	local function column(w, label, text, numeric)
		local p = vgui.Create("DPanel", bar)
		p:Dock(LEFT)
		p:SetWide(w)
		p:DockMargin(0, 0, 8, 0)
		p.Paint = nil
		return T.Field(p, label, text, numeric)
	end
	local name = column(170, "Preset name", "Supply Crate")
	local model = column(300, "Model (.mdl) for empty preset", "models/props_junk/wood_crate001a.mdl")
	local gw = column(50, "W", "8", true)
	local gh = column(50, "H", "6", true)

	local btns = vgui.Create("DPanel", bar)
	btns:Dock(LEFT)
	btns:SetWide(240)
	btns.Paint = nil
	local b1 = T.Button(btns, "CREATE EMPTY PRESET", nil, function()
		RPInv.SendJSON("rpinv_a_psave", { name = name:GetText(), model = model:GetText(), w = tonumber(gw:GetText()) or 8, h = tonumber(gh:GetText()) or 6 })
	end)
	b1:Dock(TOP)
	b1:SetTall(24)
	b1:DockMargin(0, 0, 0, 4)
	local b2 = T.Button(btns, "SAVE AIMED CONTAINER", nil, function()
		RPInv.SendJSON("rpinv_a_psave", { name = name:GetText(), from_aimed = true })
	end)
	b2:Dock(TOP)
	b2:SetTall(24)

	local sp = vgui.Create("DPanel", bar)
	sp:Dock(RIGHT)
	sp:SetWide(260)
	sp.Paint = nil
	local search = T.Field(sp, "Search items", "")
	search.OnChange = function(s)
		root.Query = s:GetText()
		timer.Create("RPInv_QSearch", 0.25, 1, function()
			if IsValid(root) then root.Dirty = true end
		end)
	end

	root.Think = function(s)
		if not IsValid(LocalPlayer()) then return end
		local admin = LocalPlayer():IsSuperAdmin()
		local adminChanged = s.Admin ~= admin
		if s.Dirty or adminChanged or not IsValid(s.Scroll) then
			rebuild()
			if adminChanged and admin then requestPresets() end
		end
		local vis = s:IsVisible()
		if vis and not s.WasVisible and admin and CurTime() > (s.NextReq or 0) then
			s.NextReq = CurTime() + 2
			requestPresets()
		end
		s.WasVisible = vis
	end

	root.Dirty = true
	return root
end

hook.Add("RPInv_PresetsUpdated", "RPInv_SpawnTab", function()
	if IsValid(root) then root.Dirty = true end
end)

hook.Add("RPInv_ItemsUpdated", "RPInv_SpawnTab", function()
	if IsValid(root) then root.Dirty = true end
end)

spawnmenu.AddCreationTab("RP Inventory", buildRoot, "icon16/box.png", 150, "Spawn RP Inventory items and container presets")
