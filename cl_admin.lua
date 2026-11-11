local T = RPInv.Theme

RPInv.Presets = RPInv.Presets or {}
RPInv.ContainerList = RPInv.ContainerList or {}

local function send(name, tbl) RPInv.SendJSON(name, tbl) end

local function request(name)
	net.Start(name)
	net.SendToServer()
end

local function bar(parent, h)
	local b = vgui.Create("DPanel", parent)
	b:Dock(TOP)
	b:SetTall(h or T.S(30))
	b:DockMargin(0, 0, 0, T.S(6))
	b.Paint = nil
	return b
end

local function barButton(b, text, w, fn, confirm)
	local btn = (confirm and T.ConfirmButton or T.Button)(b, text, T.S(w), fn)
	btn:Dock(LEFT)
	btn:DockMargin(0, 0, T.S(6), 0)
	return btn
end

local function fieldRow(parent, specs)
	local row = vgui.Create("DPanel", parent)
	row:Dock(TOP)
	row:SetTall(48)
	row.Paint = nil
	local out = {}
	for _, s in ipairs(specs) do
		local cell = vgui.Create("DPanel", row)
		cell:Dock(LEFT)
		cell:SetWide(T.S(s.w))
		cell:DockMargin(0, 0, T.S(8), 0)
		cell.Paint = nil
		out[#out + 1] = T.Field(cell, s.label, s.value, s.numeric)
	end
	return unpack(out)
end

local function section(parent, title)
	local p = vgui.Create("DPanel", parent)
	p:Dock(FILL)
	p:DockPadding(T.S(16), T.S(44), T.S(16), T.S(16))
	p.Paint = function(_, w, h)
		surface.SetDrawColor(T.WinBg)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		draw.SimpleText(title, "RPInv.Tab", T.S(16), T.S(20), T.Green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(T.Accent)
		surface.DrawRect(T.S(16), T.S(34), T.S(40), 2)
	end
	p:SetVisible(false)
	return p
end

local function toggleButton(parent, label, value)
	local b
	b = T.Button(parent, "", nil, function()
		b.Value = not b.Value
		b:SetText(label .. ": " .. (b.Value and "YES" or "NO"))
	end)
	b.Value = value
	b:SetText(label .. ": " .. (value and "YES" or "NO"))
	return b
end

local function cycleButton(parent, label, keys, names, value)
	local b
	local idx = table.KeyFromValue(keys, value) or 1
	b = T.Button(parent, "", nil, function()
		idx = idx % #keys + 1
		b.Value = keys[idx]
		b:SetText(label .. ": " .. names[keys[idx]])
	end)
	b.Value = keys[idx]
	b:SetText(label .. ": " .. names[keys[idx]])
	return b
end

local itemList

local function buildItems(p)
	local left = vgui.Create("DPanel", p)
	left:Dock(LEFT)
	left:SetWide(T.S(520))
	left:DockMargin(0, 0, T.S(16), 0)
	left.Paint = nil

	local editor = vgui.Create("DScrollPanel", p)
	editor:Dock(FILL)
	T.StyleScroll(editor)

	local search = T.TextEntry(left, "Search by name, id, category or argument...")
	search:Dock(TOP)
	search:SetTall(T.S(26))
	search:DockMargin(0, 0, 0, T.S(6))
	itemList = T.List(left, {
		{ name = "ID", w = T.S(120) }, { name = "NAME" }, { name = "SIZE", w = T.S(50) }, { name = "TYPE", w = T.S(70) }, { name = "STACK", w = T.S(50) },
	})
	itemList:Dock(FILL)
	itemList.Search = search

	local ents2 = vgui.Create("DPanel", left)
	ents2:Dock(BOTTOM)
	ents2:SetTall(T.S(30))
	ents2:DockMargin(0, T.S(6), 0, 0)
	ents2.Paint = nil
	barButton(ents2, "ADD AIMED ENTITY AS ITEM", 260, function()
		net.Start("rpinv_a_entitem")
		net.SendToServer()
	end)

	local io = vgui.Create("DPanel", left)
	io:Dock(BOTTOM)
	io:SetTall(T.S(30))
	io:DockMargin(0, T.S(6), 0, 0)
	io.Paint = nil
	barButton(io, "EXPORT ALL (CLIPBOARD)", 230, function()
		local list = {}
		for _, d in SortedPairs(RPInv.Items) do list[#list + 1] = d end
		SetClipboardText(util.TableToJSON({ items = list }, true))
		RPInv.Toast("Copied " .. #list .. " item definitions to the clipboard.", 1)
	end)
	barButton(io, "IMPORT JSON", 150, function()
		local f = T.Frame("IMPORT ITEMS (PASTE JSON)", T.S(700), T.S(480))
		f:Center()
		f:DoModal()
		local te = vgui.Create("DTextEntry", f)
		te:SetMultiline(true)
		te:SetFont("RPInv.Small")
		te:SetPos(T.S(12), T.S(44))
		te:SetSize(f:GetWide() - T.S(24), f:GetTall() - T.S(100))
		local go = T.Button(f, "IMPORT", T.S(140), function()
			local t = util.JSONToTable(te:GetValue() or "")
			if type(t) ~= "table" then
				RPInv.Toast("That is not valid JSON.", 2)
				return
			end
			RPInv.SendJSON("rpinv_a_import", t)
			f:Close()
		end)
		go:SetPos(T.S(12), f:GetTall() - T.S(46))
		go:SetTall(T.S(32))
		local note = T.Label(f, "Existing items with the same ID are overwritten. Models must exist on the server.", "RPInv.Small")
		note:SetPos(T.S(166), f:GetTall() - T.S(38))
		note:SetWide(f:GetWide() - T.S(180))
	end)

	local fields = {}
	local current
	local preview

	local function value(k)
		local f = fields[k]
		if not f then return nil end
		if f.Value ~= nil then return f.Value end
		return f:GetText()
	end

	local function readDef()
		return {
			id = value("id"), name = value("name"), model = value("model"), descr = value("descr"),
			category = value("category"), max_stack = tonumber(value("max_stack")) or 1,
			w = math.Clamp(tonumber(value("w")) or 1, 1, 10), h = math.Clamp(tonumber(value("h")) or 1, 1, 10),
			rotatable = value("rotatable"), use_type = value("use_type"), use_arg = value("use_arg"),
			cam_ang = string.format("%d %d %d", tonumber(value("cam_p")) or 0, tonumber(value("cam_y")) or 0, tonumber(value("cam_r")) or 0),
			cam_fov = tonumber(value("cam_fov")) or 1,
			cam_off = string.format("%.2f %.2f", math.Clamp(tonumber(value("cam_ox")) or 0, -1, 1), math.Clamp(tonumber(value("cam_oy")) or 0, -1, 1)),
			skin = math.Clamp(math.floor(tonumber(value("skin")) or 0), 0, 63),
			bodygroups = string.sub(string.gsub(string.lower(tostring(value("bodygroups") or "")), "[^0-9a-z]", ""), 1, 32),
			equip_slot = value("equip_slot") or (current and current.equip_slot) or "",
			grid_w = math.Clamp(tonumber(value("grid_w")) or 0, 0, 12), grid_h = math.Clamp(tonumber(value("grid_h")) or 0, 0, 12),
			jmod_armor = current and current.jmod_armor or "",
		}
	end

	local function fill(def)
		current = def
		editor:Clear()
		fields = {}
		def = def or { id = "", name = "", model = "models/props_junk/PopCan01a.mdl", descr = "", max_stack = 1, use_type = "none", use_arg = "", w = 1, h = 1, rotatable = true, category = "", cam_ang = "0 0 0", cam_fov = 1 }
		local p0, y0, r0 = RPInv.DB_Parse3(def.cam_ang)

		local top = vgui.Create("DPanel", editor)
		top:Dock(TOP)
		top:SetTall(T.S(220))
		top:DockMargin(0, 0, 0, T.S(10))
		top.Paint = nil

		local mdl = vgui.Create("DModelPanel", top)
		mdl:Dock(LEFT)
		mdl:SetWide(T.S(260))
		mdl:SetFOV(32)
		mdl:SetAmbientLight(Color(220, 220, 220))
		mdl:SetDirectionalLight(BOX_TOP, Color(255, 255, 255))
		mdl:SetDirectionalLight(BOX_FRONT, Color(200, 200, 200))
		local paintModel = mdl.Paint
		mdl.Paint = function(s, w, h)
			surface.SetDrawColor(T.CellBg)
			surface.DrawRect(0, 0, w, h)
			paintModel(s, w, h)
			surface.SetDrawColor(T.Dim)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
			draw.SimpleText("3D PREVIEW", "RPInv.Tiny", T.S(6), T.S(4), T.Dim)
		end
		mdl.LayoutEntity = function(s, e)
			local a = RealTime() * 0.6
			s:SetCamPos(Vector(math.cos(a), math.sin(a), 0.45) * (s.R or 20) * 3)
			if IsValid(e) and fields.skin then
				local look = { skin = tonumber(fields.skin:GetText()) or 0, bodygroups = fields.bodygroups:GetText() }
				local sig = look.skin .. "|" .. look.bodygroups
				if s.LookSig ~= sig then
					s.LookSig = sig
					RPInv.ApplyLook(e, look)
				end
			end
		end
		local function setModel(path)
			if not RPInv.ModelExists(path) then return end
			mdl:SetModel(path)
			mdl.LookSig = nil
			local e = mdl:GetEntity()
			if not IsValid(e) then return end
			local mn, mx = e:GetRenderBounds()
			e:SetPos(-(mn + mx) / 2)
			mdl.R = math.max(mn:Distance(mx) / 2, 2)
			mdl:SetLookAt(vector_origin)
		end
		setModel(def.model)

		preview = vgui.Create("DPanel", top)
		preview:Dock(FILL)
		preview:DockMargin(T.S(10), 0, 0, 0)
		preview.Def = table.Copy(def)
		preview.Def.RPInvPreview = true
		preview.Paint = function(s, w, h)
			surface.SetDrawColor(T.WinBg)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(T.Dim)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
			draw.SimpleText("INVENTORY ICON", "RPInv.Tiny", T.S(6), T.S(4), T.Dim)
			local d = s.Def
			if not d or not RPInv.ModelExists(d.model or "") then
				draw.SimpleText("INVALID MODEL", "RPInv.Small", w / 2, h / 2, T.Red, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				return
			end
			local cs = math.min(T.CellSize(), math.floor((w - T.S(20)) / d.w), math.floor((h - T.S(40)) / d.h))
			local pw, ph = d.w * cs, d.h * cs
			local x, y = (w - pw) / 2, (h - ph) / 2 + T.S(6)
			surface.SetDrawColor(T.CellBg)
			surface.DrawRect(x, y, pw, ph)
			RPInv.DrawItemBox(d, { amount = math.max(1, d.max_stack), rot = 0 }, x + 1, y + 1, pw - 1, ph - 1, 255)
			surface.SetDrawColor(T.CellLine)
			for i = 0, d.w do surface.DrawRect(x + i * cs, y, 1, ph) end
			for i = 0, d.h do surface.DrawRect(x, y + i * cs, pw, 1) end
		end

		local idf
		idf, fields.name = fieldRow(editor, {
			{ label = "ID (a-z, 0-9, _)", value = def.id, w = 180 }, { label = "NAME", value = def.name, w = 260 },
		})
		fields.id = idf
		idf:SetEnabled(def.id == "")
		fields.model = fieldRow(editor, { { label = "MODEL (.mdl)", value = def.model, w = 448 } })
		fields.descr = fieldRow(editor, { { label = "DESCRIPTION", value = def.descr, w = 448 } })
		fields.category, fields.max_stack, fields.w, fields.h = fieldRow(editor, {
			{ label = "CATEGORY", value = def.category, w = 180 }, { label = "MAX STACK", value = tostring(def.max_stack), w = 84, numeric = true },
			{ label = "WIDTH", value = tostring(def.w), w = 76, numeric = true }, { label = "HEIGHT", value = tostring(def.h), w = 76, numeric = true },
		})

		local b1 = bar(editor, T.S(28))
		fields.rotatable = toggleButton(b1, "ROTATABLE", def.rotatable ~= false)
		fields.rotatable:Dock(LEFT)
		fields.rotatable:SetWide(T.S(180))
		fields.rotatable:DockMargin(0, 0, T.S(8), 0)
		local keys = table.GetKeys(RPInv.UseTypes)
		table.sort(keys)
		fields.use_type = cycleButton(b1, "ON USE", keys, RPInv.UseTypes, def.use_type)
		fields.use_type:Dock(FILL)

		fields.use_arg = fieldRow(editor, { { label = "USE ARGUMENT (amount / weapon class / AmmoType:amount)", value = def.use_arg, w = 448 } })

		fields.grid_w, fields.grid_h = fieldRow(editor, {
			{ label = "STORAGE GRID W (0 = none)", value = tostring(def.grid_w or 0), w = 210, numeric = true },
			{ label = "STORAGE GRID H (0 = none)", value = tostring(def.grid_h or 0), w = 210, numeric = true },
		})

		if def.jmod_armor and def.jmod_armor ~= "" then
			local slot = RPInv.EquipSlotOf(def)
			local info = T.Label(editor, "JMOD ARMOR: " .. def.jmod_armor .. "   SLOT: " .. (slot and RPInv.EquipSlotByKey[slot].name or "?"), "RPInv.Small")
			info:SetTextColor(T.Accent)
			info:Dock(TOP)
			info:DockMargin(0, 0, 0, T.S(8))
		else
			local keys, names = { "" }, { [""] = "NONE" }
			for _, k in ipairs(RPInv.WeaponSlotKeys) do
				keys[#keys + 1] = k
				names[k] = RPInv.EquipSlotByKey[k].name
			end
			local b4 = bar(editor, T.S(28))
			fields.equip_slot = cycleButton(b4, "WEAPON SLOT (on use = weapon)", keys, names, def.equip_slot or "")
			fields.equip_slot:Dock(FILL)
		end
		fields.cam_p, fields.cam_y, fields.cam_r, fields.cam_fov = fieldRow(editor, {
			{ label = "ICON PITCH", value = tostring(p0), w = 100 }, { label = "ICON YAW", value = tostring(y0), w = 100 },
			{ label = "ICON ROLL", value = tostring(r0), w = 100 }, { label = "ICON ZOOM", value = tostring(def.cam_fov ~= 0 and def.cam_fov or 1), w = 100 },
		})
		local ox0, oy0 = string.match(def.cam_off or "", "^(%-?[%d%.]+) (%-?[%d%.]+)$")
		fields.cam_ox, fields.cam_oy = fieldRow(editor, {
			{ label = "ICON OFFSET X (-1..1)", value = tostring(tonumber(ox0) or 0), w = 160 },
			{ label = "ICON OFFSET Y (-1..1)", value = tostring(tonumber(oy0) or 0), w = 160 },
		})
		fields.skin, fields.bodygroups = fieldRow(editor, {
			{ label = "SKIN", value = tostring(def.skin or 0), w = 90, numeric = true },
			{ label = "BODYGROUPS (one digit per group, e.g. 0120)", value = def.bodygroups or "", w = 330 },
		})
		local lookInfo = T.Label(editor, "", "RPInv.Tiny")
		lookInfo:Dock(TOP)
		lookInfo:DockMargin(0, 0, 0, T.S(6))
		lookInfo.Think = function(s)
			if (s.Next or 0) > RealTime() then return end
			s.Next = RealTime() + 0.5
			local e = mdl:GetEntity()
			if not IsValid(e) then s:SetText("") return end
			local parts = {}
			for i = 0, e:GetNumBodyGroups() - 1 do
				local n = e:GetBodygroupCount(i)
				if n > 1 then parts[#parts + 1] = "#" .. (i + 1) .. " " .. (e:GetBodygroupName(i) or "?") .. " 0-" .. (n - 1) end
			end
			s:SetText("THIS MODEL: SKINS 0-" .. math.max(0, e:SkinCount() - 1) .. (#parts > 0 and ("   BODYGROUPS: " .. table.concat(parts, ", ")) or "   NO BODYGROUPS"))
		end
		local function num(f, d) return tonumber(f:GetText()) or d end
		local function setNum(f, v, fmt) f:SetText(string.format(fmt or "%d", v)) end
		preview:SetCursor("sizeall")
		preview.OnMousePressed = function(s, code)
			if code == MOUSE_MIDDLE then
				setNum(fields.cam_p, 0)
				setNum(fields.cam_y, 0)
				setNum(fields.cam_r, 0)
				setNum(fields.cam_fov, 1, "%.2f")
				setNum(fields.cam_ox, 0, "%.2f")
				setNum(fields.cam_oy, 0, "%.2f")
				return
			end
			s.Drag = { code = code, x = gui.MouseX(), y = gui.MouseY() }
			s:MouseCapture(true)
		end
		preview.OnMouseReleased = function(s)
			s.Drag = nil
			s:MouseCapture(false)
		end
		preview.OnMouseWheeled = function(_, d)
			local z = math.Clamp(num(fields.cam_fov, 1) * (d > 0 and 1.1 or 1 / 1.1), 0.3, 20)
			setNum(fields.cam_fov, z, "%.2f")
			return true
		end
		preview.Think = function(s)
			local dr = s.Drag
			if not dr then return end
			if not input.IsMouseDown(dr.code) then
				s.Drag = nil
				s:MouseCapture(false)
				return
			end
			local mx, my = gui.MouseX(), gui.MouseY()
			local dx, dy = mx - dr.x, my - dr.y
			if dx == 0 and dy == 0 then return end
			dr.x, dr.y = mx, my
			if dr.code == MOUSE_LEFT then
				local yaw = num(fields.cam_y, 0) + dx * 0.6
				yaw = (yaw + 180) % 360 - 180
				setNum(fields.cam_y, math.Round(yaw))
				setNum(fields.cam_p, math.Round(math.Clamp(num(fields.cam_p, 0) + dy * 0.6, -180, 180)))
			elseif dr.code == MOUSE_RIGHT then
				setNum(fields.cam_ox, math.Clamp(num(fields.cam_ox, 0) + dx / math.max(s:GetWide(), 1) * 2, -1, 1), "%.2f")
				setNum(fields.cam_oy, math.Clamp(num(fields.cam_oy, 0) - dy / math.max(s:GetTall(), 1) * 2, -1, 1), "%.2f")
			end
		end
		local note = T.Label(editor, "Pitch/yaw/roll 0 0 0 = automatic orientation. Zoom 1 = fit to cells. Offset moves the model inside the icon (1 = half the icon; X right, Y up). In the icon preview: left-drag rotates, right-drag moves, wheel zooms, middle click resets.", "RPInv.Tiny")
		note:Dock(TOP)
		note:DockMargin(0, 0, 0, T.S(10))

		local b2 = bar(editor)
		barButton(b2, "SAVE", 110, function()
			send("rpinv_a_save", readDef())
		end)
		barButton(b2, "NEW", 90, function() fill(nil) end)
		if def.id ~= "" then
			barButton(b2, "DELETE", 110, function()
				net.Start("rpinv_a_delete")
				net.WriteString(def.id)
				net.SendToServer()
				fill(nil)
			end, true)
		end

		local b3 = bar(editor)
		local amt = T.TextEntry(b3)
		amt:Dock(LEFT)
		amt:SetWide(T.S(56))
		amt:DockMargin(0, 0, T.S(6), 0)
		amt:SetNumeric(true)
		amt:SetText("1")
		local function amount() return math.Clamp(tonumber(amt:GetText()) or 1, 1, 999) end
		local function itemNet(name)
			if def.id == "" then return end
			net.Start(name)
			net.WriteString(def.id)
			net.WriteUInt(amount(), 16)
			net.SendToServer()
		end
		barButton(b3, "GIVE ME", 110, function() itemNet("rpinv_a_give") end)
		barButton(b3, "SPAWN AT AIM", 150, function() itemNet("rpinv_a_spawn") end)

		local lastSig, changedAt
		top.Think = function()
			local d = readDef()
			d.RPInvPreview = true
			local sig = util.TableToJSON(d)
			if sig ~= lastSig then
				lastSig, changedAt = sig, SysTime()
				if preview.Def and preview.Def.model == d.model then preview.Def = d end
			elseif changedAt and SysTime() - changedAt > 0.6 then
				changedAt = nil
				if RPInv.ModelExists(d.model or "") and (not preview.Def or preview.Def.model ~= d.model) then setModel(d.model) end
				preview.Def = d
			end
		end
	end

	local function refresh()
		if not IsValid(itemList) then return end
		itemList:Clear()
		local q = IsValid(itemList.Search) and string.lower(string.Trim(itemList.Search:GetText())) or ""
		for id, d in SortedPairs(RPInv.Items) do
			local hay = string.lower(d.name .. " " .. id .. " " .. (d.category or "") .. " " .. (d.use_arg or ""))
			if q == "" or string.find(hay, q, 1, true) then
				T.AddLine(itemList, id, d.name, d.w .. "x" .. d.h, d.use_type, d.max_stack)
			end
		end
	end
	if IsValid(itemList.Search) then
		itemList.Search.OnChange = function()
			timer.Create("RPInv_AdminSearch", 0.2, 1, refresh)
		end
	end
	itemList.OnRowSelected = function(_, _, line)
		local d = RPInv.Items[line:GetColumnText(1)]
		if d then fill(d) end
	end
	hook.Add("RPInv_ItemsUpdated", "RPInv_AdminItems", function()
		refresh()
		if current and RPInv.Items[current.id] then
			current = RPInv.Items[current.id]
		end
	end)
	refresh()
	fill(nil)
end

local contList

local function buildContainers(p)
	local name, model, w, h = fieldRow(p, {
		{ label = "CONTAINER NAME", value = "Storage Crate", w = 220 },
		{ label = "MODEL (.mdl) - for SPAWN AT AIM", value = "models/props_junk/wood_crate001a.mdl", w = 340 },
		{ label = "WIDTH", value = "8", w = 70, numeric = true }, { label = "HEIGHT", value = "6", w = 70, numeric = true },
	})
	local function create(convert)
		send("rpinv_a_cspawn", { name = name:GetText(), model = model:GetText(), w = tonumber(w:GetText()) or 8, h = tonumber(h:GetText()) or 6, convert = convert })
	end
	local b = bar(p)
	barButton(b, "SPAWN AT AIM", 150, function() create(false) end)
	barButton(b, "CONVERT AIMED PROP", 200, function() create(true) end)
	barButton(b, "REFRESH", 110, function() request("rpinv_a_clist") end)
	barButton(b, "DELETE SELECTED", 170, function()
		local _, line = contList:GetSelectedLine()
		if not line then return end
		net.Start("rpinv_a_cdelete")
		net.WriteUInt(tonumber(line:GetColumnText(1)), 32)
		net.SendToServer()
	end, true)
	local rp, rm = fieldRow(p, {
		{ label = "REFILL FROM LOOT PRESET ID (0 = OFF)", value = "0", w = 260, numeric = true },
		{ label = "EVERY (MINUTES)", value = "30", w = 140, numeric = true },
	})
	local rb = bar(p)
	barButton(rb, "SET REFILL FOR SELECTED", 240, function()
		local _, line = contList:GetSelectedLine()
		if not line then return end
		net.Start("rpinv_lt_refill")
		net.WriteUInt(tonumber(line:GetColumnText(1)), 32)
		net.WriteUInt(math.Clamp(math.floor(tonumber(rp:GetText()) or 0), 0, 65535), 16)
		net.WriteUInt(math.Clamp(math.floor(tonumber(rm:GetText()) or 30), 1, 1440), 16)
		net.SendToServer()
	end)
	local hint = T.Label(p, "Superadmins can also move containers with the physgun and delete them with the remover tool or C-menu. A refill wipes the container and rolls fresh loot from the preset (only while nobody has it open). Preset IDs are in the LOOT tab.", "RPInv.Small")
	hint:Dock(TOP)
	hint:SetWrap(true)
	hint:SetTall(T.S(32))
	hint:DockMargin(0, 0, 0, T.S(6))
	contList = T.List(p, { { name = "ID", w = T.S(60) }, { name = "NAME" }, { name = "SIZE", w = T.S(70) }, { name = "REFILL", w = T.S(120) }, { name = "MODEL" } })
	contList:Dock(FILL)
	p.OnShow = function() request("rpinv_a_clist") end
end

local presetList

local function buildPresets(p)
	local name, model, w, h = fieldRow(p, {
		{ label = "PRESET NAME", value = "Supply Crate", w = 220 },
		{ label = "MODEL (.mdl) - for empty presets", value = "models/props_junk/wood_crate001a.mdl", w = 340 },
		{ label = "WIDTH", value = "8", w = 70, numeric = true }, { label = "HEIGHT", value = "6", w = 70, numeric = true },
	})
	local function selected()
		local _, line = presetList:GetSelectedLine()
		return line and tonumber(line:GetColumnText(1))
	end
	local b = bar(p)
	barButton(b, "CREATE EMPTY", 150, function()
		send("rpinv_a_psave", { name = name:GetText(), model = model:GetText(), w = tonumber(w:GetText()) or 8, h = tonumber(h:GetText()) or 6 })
	end)
	barButton(b, "SAVE AIMED CONTAINER", 220, function()
		send("rpinv_a_psave", { name = name:GetText(), from_aimed = true })
	end)
	local b2 = bar(p)
	barButton(b2, "SPAWN SELECTED", 170, function()
		local id = selected()
		if not id then return end
		net.Start("rpinv_a_pspawn")
		net.WriteUInt(id, 32)
		net.SendToServer()
	end)
	barButton(b2, "UPDATE FROM AIMED", 190, function()
		local id = selected()
		if id then send("rpinv_a_psave", { id = id, from_aimed = true }) end
	end)
	barButton(b2, "DELETE SELECTED", 170, function()
		local id = selected()
		if not id then return end
		net.Start("rpinv_a_pdelete")
		net.WriteUInt(id, 32)
		net.SendToServer()
	end, true)
	presetList = T.List(p, { { name = "ID", w = T.S(60) }, { name = "NAME" }, { name = "SIZE", w = T.S(70) }, { name = "STACKS", w = T.S(70) }, { name = "MODEL" } })
	presetList:Dock(FILL)
	local function refresh()
		if not IsValid(presetList) then return end
		presetList:Clear()
		for _, pr in ipairs(RPInv.Presets) do
			T.AddLine(presetList, pr.id, pr.name, pr.w .. "x" .. pr.h, pr.stacks or 0, pr.model)
		end
	end
	hook.Add("RPInv_PresetsUpdated", "RPInv_AdminPresets", refresh)
	refresh()
	p.OnShow = function() request("rpinv_a_plist") end
end

local function buildSettings(p)
	local s = RPInv.Settings
	local w, h = fieldRow(p, {
		{ label = "PLAYER GRID WIDTH (4-20, 0 = NONE)", value = tostring(s.player_grid_w or 10), w = 240, numeric = true },
		{ label = "PLAYER GRID HEIGHT (2-20, 0 = NONE)", value = tostring(s.player_grid_h or 6), w = 240, numeric = true },
	})
	local note = T.Label(p, "Items that no longer fit after shrinking are re-packed; anything left over is dropped at the player's feet. 0 = no main inventory: players only have pockets, rigs and backpacks.", "RPInv.Small")
	note:Dock(TOP)
	note:DockMargin(0, 0, 0, T.S(10))

	local function row()
		local r = bar(p, T.S(28))
		return r
	end
	local death = cycleButton(row(), "ON DEATH", { "keep", "corpse", "drop" }, {
		keep = "KEEP INVENTORY AND RE-EQUIP ARMOR", corpse = "LEAVE A LOOTABLE BODY", drop = "DROP EVERYTHING ON THE GROUND",
	}, s.death_mode or "keep")
	death:Dock(FILL)
	local ctime, ltime = fieldRow(p, {
		{ label = "BODY STAYS FOR (MINUTES, 1-60)", value = tostring(s.corpse_time or 5), w = 260, numeric = true },
		{ label = "SEARCHING A BODY TAKES (SECONDS, 0-15)", value = tostring(s.loot_time or 2), w = 300, numeric = true },
	})
	local restore = toggleButton(row(), "RE-EQUIP SAVED JMOD ARMOR AFTER REJOIN", s.restore_armor ~= false)
	restore:Dock(FILL)
	local pickup = cycleButton(row(), "STORE JMOD ARMOR FROM THE GROUND", { "shift", "plain", "off" }, {
		shift = "SHIFT + E", plain = "E (JMod carry disabled)", off = "OFF",
	}, s.jmod_pickup or "shift")
	pickup:Dock(FILL)
	local smode = cycleButton(row(), "SEARCHING PLAYERS", { "surrender", "anyone", "admin" }, {
		surrender = "ONLY IF THE TARGET HOLDS E (HANDS UP)", anyone = "ANYONE CAN BE SEARCHED", admin = "ADMINS ONLY (rpinv_search)",
	}, s.search_mode or "surrender")
	smode:Dock(FILL)
	local sequip = toggleButton(row(), "SEARCHER CAN TAKE WORN EQUIPMENT", s.search_equipment ~= false)
	sequip:Dock(FILL)
	local touch = toggleButton(row(), "PICK UP WEAPONS ON THE GROUND BY WALKING OVER THEM", s.weapon_touch_pickup == true)
	touch:Dock(FILL)
	local atts = toggleButton(row(), "WEAPON ATTACHMENTS ARE INVENTORY ITEMS (BASE MENUS LOCKED)", s.att_items == true)
	atts:Dock(FILL)
	local selector = cycleButton(row(), "WEAPON SELECTION", { "inventory", "vanilla" }, {
		inventory = "INVENTORY SLOTS (1-5, NO SCROLL WHEEL)", vanilla = "VANILLA HUD AND SCROLL WHEEL",
	}, s.selector_mode or "inventory")
	selector:Dock(FILL)
	local qweap = toggleButton(row(), "WEAPONS GIVEN FROM THE Q MENU BECOME INVENTORY ITEMS", s.qmenu_weapons ~= false)
	qweap:Dock(FILL)
	local epick = cycleButton(row(), "STORE ENTITIES ADDED AS ITEMS", { "shift", "plain", "off" }, {
		shift = "SHIFT + E", plain = "E", off = "OFF",
	}, s.entity_pickup or "shift")
	epick:Dock(FILL)
	local efresh = toggleButton(row(), "ENTITIES COME BACK AS A FRESH Q MENU SPAWN (OFF = KEEP HEALTH, COLOUR, SKIN)", s.entity_fresh ~= false)
	efresh:Dock(FILL)
	local ammoItems = toggleButton(row(), "RESERVE AMMO LIVES IN THE INVENTORY AS ROUNDS (TAKES SPACE, RELOADS FROM IT)", s.ammo_items == true)
	ammoItems:Dock(FILL)
	local ammoStack, ammoIgnore = fieldRow(p, {
		{ label = "ROUNDS PER INVENTORY CELL (1-999)", value = tostring(s.ammo_stack or 60), w = 260, numeric = true },
		{ label = "AMMO TYPES LEFT TO THE WEAPON BASE (comma separated names)", value = s.ammo_ignore or "", w = 480 },
	})
	local stime, pw, ph = fieldRow(p, {
		{ label = "SEARCH TIME (SECONDS, 1-30)", value = tostring(s.search_time or 4), w = 260, numeric = true },
		{ label = "POCKETS WIDTH (0-8)", value = tostring(s.pockets_w or 4), w = 180, numeric = true },
		{ label = "POCKETS HEIGHT (0-4)", value = tostring(s.pockets_h or 1), w = 180, numeric = true },
	})

	local handsF = fieldRow(p, {
		{ label = "HANDS WEAPON CLASS (key 4; rpinv_hands = ours, empty = none, or any SWEP class)", value = s.hands_class == nil and "rpinv_hands" or s.hands_class, w = 520 },
	})
	local consF = fieldRow(p, {
		{ label = "USED-UP WEAPONS (classes, comma separated): removed with their item once clip and reserve ammo are 0", value = s.consumable_weapons or "", w = 720 },
	})
	local blackF = fieldRow(p, {
		{ label = "WEAPON BLACKLIST (classes, comma separated): never turned into items or dropped with G, like the physgun", value = s.weapon_blacklist or "", w = 720 },
	})
	local consNote = T.Label(p, "Slot weapons that the weapon base removes itself when they run out (grenades and similar) are cleared automatically; list the ones that stay in the hands empty.", "RPInv.Small")
	consNote:Dock(TOP)
	consNote:DockMargin(0, 0, 0, T.S(8))

	local b = bar(p)
	barButton(b, "APPLY", 120, function()
		send("rpinv_a_settings", {
			player_grid_w = tonumber(w:GetText()), player_grid_h = tonumber(h:GetText()),
			death_mode = death.Value, restore_armor = restore.Value, jmod_pickup = pickup.Value,
			corpse_time = tonumber(ctime:GetText()), loot_time = tonumber(ltime:GetText()),
			search_mode = smode.Value, search_time = tonumber(stime:GetText()), search_equipment = sequip.Value,
			weapon_touch_pickup = touch.Value, att_items = atts.Value,
			selector_mode = selector.Value, qmenu_weapons = qweap.Value, entity_pickup = epick.Value, entity_fresh = efresh.Value,
			hands_class = handsF:GetText(), consumable_weapons = consF:GetText(), weapon_blacklist = blackF:GetText(),
			ammo_items = ammoItems.Value, ammo_stack = tonumber(ammoStack:GetText()), ammo_ignore = ammoIgnore:GetText(),
			pockets_w = tonumber(pw:GetText()), pockets_h = tonumber(ph:GetText()),
		})
	end)
	barButton(b, "IMPORT JMOD ARMOR", 220, function()
		net.Start("rpinv_a_jmodimport")
		net.SendToServer()
	end)
	barButton(b, "IMPORT ATTACHMENTS", 220, function()
		net.Start("rpinv_a_attimport")
		net.SendToServer()
	end)
	local b2 = bar(p)
	barButton(b2, "CLEAR ATTACHMENT ITEMS", 240, function()
		net.Start("rpinv_a_purge")
		net.WriteString("attachments")
		net.SendToServer()
	end, true)
	barButton(b2, "CLEAR JMOD ARMOR ITEMS", 240, function()
		net.Start("rpinv_a_purge")
		net.WriteString("armor")
		net.SendToServer()
	end, true)
	local function wipe(kind, title, text)
		Derma_Query(text, title, "YES, DELETE", function()
			net.Start("rpinv_a_wipe")
			net.WriteString(kind)
			net.SendToServer()
		end, "CANCEL")
	end
	local b3 = bar(p)
	barButton(b3, "DELETE ALL ITEMS ON THE GROUND", 300, function()
		wipe("ground", "Delete ground items", "Delete every inventory item lying on the ground on this map? This cannot be undone.")
	end)
	barButton(b3, "WIPE ALL INVENTORY DATA", 260, function()
		wipe("all", "Wipe all inventory data", "Wipe the inventories, pockets, backpacks, equipped weapons and armor, quick slots and container contents of EVERY player, online and offline?\n\nItem definitions, placed containers, presets and settings are kept.\n\nThis cannot be undone.")
	end)
	local jm = T.Label(p, RPInv.JModAvailable() and "JMod detected: IMPORT creates an inventory item for every JMod armor piece (sizes are editable in ITEMS)."
		or "JMod is not installed: equipment slots accept weapons only.", "RPInv.Small")
	jm:Dock(TOP)
	local dev = T.Label(p, "Dev console commands: rpinv_dev_fill, rpinv_dev_bot, rpinv_dev_race, rpinv_dev_bot_open/put/take/inv/kill/remove", "RPInv.Small")
	dev:Dock(TOP)
	dev:DockMargin(0, T.S(12), 0, 0)
end

local logList

local function buildLog(p)
	local b = bar(p)
	barButton(b, "REFRESH", 120, function() request("rpinv_a_log") end)
	logList = T.List(p, { { name = "TIME", w = T.S(150) }, { name = "PLAYER", w = T.S(170) }, { name = "ACTION", w = T.S(140) }, { name = "DETAILS" } })
	logList:Dock(FILL)
	p.OnShow = function() request("rpinv_a_log") end
end

net.Receive("rpinv_a_log_r", function()
	if not IsValid(logList) then return end
	logList:Clear()
	for _, r in ipairs(RPInv.ReadJSON().rows or {}) do
		T.AddLine(logList, os.date("%Y-%m-%d %H:%M:%S", tonumber(r.ts) or 0), r.steamid or "", r.action or "", r.details or "")
	end
end)

function RPInv.BuildAdmin(page, W, H)
	local pad = T.S(18)
	local nav = vgui.Create("DPanel", page)
	nav:SetPos(pad, pad)
	nav:SetSize(T.S(200), H - pad * 2)
	nav.Paint = function(_, w, h)
		surface.SetDrawColor(T.WinBg)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	nav:DockPadding(T.S(8), T.S(8), T.S(8), T.S(8))

	local body = vgui.Create("DPanel", page)
	body:SetPos(pad * 2 + nav:GetWide(), pad)
	body:SetSize(W - nav:GetWide() - pad * 3, H - pad * 2)
	body.Paint = nil

	local sections = {}
	local function show(key)
		for k, s in pairs(sections) do s:SetVisible(k == key) end
		if sections[key].OnShow then sections[key].OnShow() end
		nav.Active = key
	end
	local list = {
		{ "items", "ITEMS", buildItems }, { "containers", "CONTAINERS", buildContainers },
		{ "presets", "PRESETS", buildPresets }, { "airdrops", "AIRDROPS", function(sec) RPInv.BuildAirdropAdmin(sec) end },
		{ "loot", "LOOT", function(sec) RPInv.BuildLootAdmin(sec) end },
		{ "settings", "SETTINGS", function(sec)
			local sc = vgui.Create("DScrollPanel", sec)
			sc:Dock(FILL)
			T.StyleScroll(sc)
			buildSettings(sc:GetCanvas())
		end }, { "log", "LOG", buildLog },
	}
	for _, e in ipairs(list) do
		local sec = section(body, e[2])
		e[3](sec)
		sections[e[1]] = sec
		local btn = vgui.Create("DButton", nav)
		btn:Dock(TOP)
		btn:SetTall(T.S(34))
		btn:DockMargin(0, 0, 0, T.S(4))
		btn:SetText("")
		btn.Paint = function(s, w, h)
			local on = nav.Active == e[1]
			surface.SetDrawColor(on and T.TabOn or (s:IsHovered() and Color(255, 255, 255, 14) or Color(0, 0, 0, 0)))
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(e[2], "RPInv.Text", T.S(12), h / 2, on and T.TabOnText or T.Green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		btn.DoClick = function()
			surface.PlaySound("ui/buttonclick.wav")
			show(e[1])
		end
	end
	show("items")
end

function RPInv.DB_Parse3(s)
	local p = string.Explode(" ", s or "")
	return tonumber(p[1]) or 0, tonumber(p[2]) or 0, tonumber(p[3]) or 0
end

net.Receive("rpinv_a_clist_r", function()
	RPInv.ContainerList = RPInv.ReadJSON().list or {}
	if not IsValid(contList) then return end
	contList:Clear()
	for _, c in ipairs(RPInv.ContainerList) do
		local r = c.refill
		T.AddLine(contList, c.id, c.name, (c.w or "?") .. "x" .. (c.h or "?"), r and ("#" .. r.p .. " / " .. r.m .. " MIN") or "-", c.model)
	end
end)

net.Receive("rpinv_a_plist_r", function()
	local list = RPInv.ReadJSON().list or {}
	local changed = util.TableToJSON(list) ~= util.TableToJSON(RPInv.Presets)
	RPInv.Presets = list
	if changed then hook.Run("RPInv_PresetsUpdated") end
end)
