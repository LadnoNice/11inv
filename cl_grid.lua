local T = RPInv.Theme
local G = RPInv.Grid
local I = RPInv.Icons

RPInv.Stores = RPInv.Stores or {}
RPInv.Drag = nil
RPInv.Press = nil
RPInv.Hover = nil

local function defs() return RPInv.Items end
local function store(sid) return sid and RPInv.Stores[sid] end

local nameCache = {}
local function shortName(def, width)
	local key = def.name .. "|" .. width
	local s = nameCache[key]
	if s then return s end
	surface.SetFont("RPInv.Tiny")
	s = def.name
	local tw = surface.GetTextSize(s)
	while #s > 1 and tw > width do
		s = string.sub(s, 1, #s - 1)
		tw = surface.GetTextSize(s .. ".")
	end
	if s ~= def.name then s = string.TrimRight(s) .. "." end
	nameCache[key] = s
	return s
end

local function shadowText(text, fontName, x, y, col, ax, ay)
	draw.SimpleText(text, fontName, x + 1, y + 1, color_black, ax, ay)
	draw.SimpleText(text, fontName, x, y, col, ax, ay)
end

function RPInv.TintFor(def)
	if def.jmod_armor and def.jmod_armor ~= "" then return T.Tints.armor end
	return T.Tints[def.use_type] or T.Tints.none
end

function RPInv.Durability(def, inst)
	if not def.jmod_armor or def.jmod_armor == "" then return nil end
	local max = RPInv.JModMaxDur(def.jmod_armor)
	if not max or max <= 0 then return nil end
	local m = inst and inst.meta and inst.meta.jmod
	local dur = (m and tonumber(m.dur)) or (inst and tonumber(inst.dur)) or max
	return math.max(0, dur), max
end

local function fmtDur(v)
	if v >= 10 then return tostring(math.floor(v + 0.5)) end
	return string.format("%.1f", v)
end

function RPInv.DrawItemBox(def, inst, x, y, pw, ph, alpha, fit)
	local tint = RPInv.TintFor(def)
	surface.SetDrawColor(tint.r, tint.g, tint.b, tint.a * (alpha or 255) / 255)
	surface.DrawRect(x, y, pw, ph)
	local icon = def.use_type == "attachment" and RPInv.Att.Icon(def)
	local wicon = not icon and def.use_type == "weapon" and RPInv.Att.WeaponIcon(def)
	if icon then
		local s = math.min(pw, ph) - 4
		surface.SetMaterial(icon)
		surface.SetDrawColor(255, 255, 255, alpha or 255)
		surface.DrawTexturedRect(x + (pw - s) / 2, y + (ph - s) / 2, s, s)
	elseif wicon then
		local s = math.min(pw, ph) - 2
		surface.SetMaterial(wicon)
		surface.SetDrawColor(255, 255, 255, alpha or 255)
		surface.DrawTexturedRect(x + (pw - s) / 2, y + (ph - s) / 2, s, s)
	elseif fit then
		local box = math.min((pw - 6) / def.w, (ph - 6) / def.h)
		local iw, ih = def.w * box, def.h * box
		I.Draw(def, x + (pw - iw) / 2, y + (ph - ih) / 2, iw, ih, 0, alpha)
	else
		I.Draw(def, x + 2, y + 2, pw - 4, ph - 4, inst.rot, alpha)
	end
	if (alpha or 255) > 100 and inst.meta and istable(inst.meta.atts) and #RPInv.Att.DataList(inst.meta.atts) > 0 then
		surface.SetDrawColor(T.Accent.r, T.Accent.g, T.Accent.b, 200)
		surface.DrawRect(x + 3, y + ph - 7, 4, 4)
	end
	if (alpha or 255) > 100 then
		shadowText(shortName(def, pw - 6), "RPInv.Tiny", x + pw - 3, y + 1, T.Green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
		local dur, max = RPInv.Durability(def, inst)
		if dur then
			local frac = math.Clamp(dur / max, 0, 1)
			surface.SetDrawColor(0, 0, 0, 180)
			surface.DrawRect(x + 2, y + ph - 4, pw - 4, 3)
			surface.SetDrawColor(Lerp(frac, 200, 90), Lerp(frac, 60, 180), 50, 230)
			surface.DrawRect(x + 2, y + ph - 4, (pw - 4) * frac, 3)
			shadowText(fmtDur(dur) .. "/" .. fmtDur(max), "RPInv.Tiny", x + pw - 3, y + ph - 4, T.Green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		elseif def.max_stack > 1 or (inst.amount or 1) > 1 then
			shadowText(tostring(inst.amount), "RPInv.Count", x + pw - 3, y + ph, T.White, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		end
	end
end

local PANEL = {}

function PANEL:Init()
	self.IsRPInvGrid = true
	self.Cell = T.CellSize()
	self.Search = ""
	self:SetMouseInputEnabled(true)
end

function PANEL:SetStore(sid)
	self.SID = sid
	self:Resize()
end

function PANEL:SetCell(cs)
	self.Cell = cs
	self:Resize()
end

function PANEL:Resize()
	local st = store(self.SID)
	local w, h = st and st.w or 1, st and st.h or 1
	self:SetSize(w * self.Cell + 1, h * self.Cell + 1)
	local canvas = self:GetParent()
	local scroll = IsValid(canvas) and canvas:GetParent()
	if IsValid(scroll) then scroll:InvalidateLayout() end
end

function PANEL:ItemAtCursor()
	local st = store(self.SID)
	if not st then return end
	local mx, my = self:CursorPos()
	if mx < 0 or my < 0 then return end
	return G.ItemAt(st, defs(), math.floor(mx / self.Cell), math.floor(my / self.Cell)), st
end

function PANEL:Think()
	local st = store(self.SID)
	if st and (self.LastW ~= st.w or self.LastH ~= st.h) then
		self.LastW, self.LastH = st.w, st.h
		self:Resize()
	end
	if self:IsHovered() and not RPInv.Drag then
		local it = self:ItemAtCursor()
		if it then
			if not RPInv.Hover or RPInv.Hover.id ~= it.id or RPInv.Hover.sid ~= self.SID then
				RPInv.Hover = { sid = self.SID, id = it.id, since = RealTime() }
			end
			RPInv.Hover.seen = FrameNumber()
		end
	end
end

function PANEL:Paint(w, h)
	local st = store(self.SID)
	if not st then return end
	local cs = self.Cell
	surface.SetDrawColor(T.CellBg)
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(T.CellLine)
	for x = 0, st.w do surface.DrawRect(x * cs, 0, 1, h) end
	for y = 0, st.h do surface.DrawRect(0, y * cs, w, 1) end

	local d = defs()
	local drag = RPInv.Drag
	local hover = RPInv.Hover
	local query = self.Search
	local searching = query ~= nil and query ~= ""
	for _, it in pairs(st.items) do
		local def = d[it.item]
		if def then
			local iw, ih = G.Size(def, it.rot)
			local x, y, pw, ph = it.x * cs + 1, it.y * cs + 1, iw * cs - 1, ih * cs - 1
			local isDragged = drag and drag.sid == self.SID and drag.id == it.id and drag.n >= it.amount
			RPInv.DrawItemBox(def, it, x, y, pw, ph, isDragged and 50 or 255)
			surface.SetDrawColor(T.Dim)
			surface.DrawOutlinedRect(x, y, pw, ph, 1)
			if searching then
				if G.Matches(def, query) then
					surface.SetDrawColor(T.SearchHit)
					surface.DrawOutlinedRect(x, y, pw, ph, 2)
				else
					surface.SetDrawColor(T.SearchDim)
					surface.DrawRect(x, y, pw, ph)
				end
			end
			if not drag and hover and hover.sid == self.SID and hover.id == it.id and hover.seen == FrameNumber() then
				surface.SetDrawColor(T.ItemHover)
				surface.DrawRect(x, y, pw, ph)
				surface.SetDrawColor(T.White)
				surface.DrawOutlinedRect(x, y, pw, ph, 1)
			end
		end
	end

	local tgt = RPInv.DragTarget
	if drag and tgt and tgt.panel == self then
		local col = tgt.status == "ok" and T.GhostOk or (tgt.status == "bad" and T.GhostBad or T.GhostMerge)
		local gx, gy = tgt.x * cs + 1, tgt.y * cs + 1
		local gw, gh = tgt.w * cs - 1, tgt.h * cs - 1
		self.GhostX = Lerp(math.min(1, FrameTime() * 30), self.GhostX or gx, gx)
		self.GhostY = Lerp(math.min(1, FrameTime() * 30), self.GhostY or gy, gy)
		surface.SetDrawColor(col)
		surface.DrawRect(self.GhostX, self.GhostY, gw, gh)
		surface.SetDrawColor(col.r, col.g, col.b, 230)
		surface.DrawOutlinedRect(self.GhostX, self.GhostY, gw, gh, 2)
	else
		self.GhostX, self.GhostY = nil, nil
	end
end

function PANEL:OnMouseWheeled(delta)
	if self.OnZoom and input.IsControlDown() then
		self:OnZoom(delta)
		return true
	end
end

function PANEL:OnMousePressed(code)
	local it = self:ItemAtCursor()
	if code == MOUSE_LEFT then
		if not it then return end
		if input.IsShiftDown() then
			RPInv.QuickMove(self.SID, it)
			return
		end
		local now = SysTime()
		if self.LastClickId == it.id and now - (self.LastClickT or 0) < 0.3 then
			self.LastClickId = nil
			RPInv.Press = nil
			RPInv.ItemDoubleClick(self.SID, it)
			return
		end
		self.LastClickId, self.LastClickT = it.id, now
		local mx, my = gui.MousePos()
		RPInv.Press = { sid = self.SID, id = it.id, x = mx, y = my, ctrl = input.IsControlDown() }
	elseif code == MOUSE_RIGHT and it then
		RPInv.ItemMenu(self.SID, it)
	end
end

vgui.Register("RPInvGrid", PANEL, "DPanel")

local function targetUnderCursor()
	local hp = vgui.GetHoveredPanel()
	while IsValid(hp) do
		if hp.IsRPInvGrid then return "grid", hp end
		if hp.IsRPInvEquipSlot then return "slot", hp end
		if hp.IsRPInvQuickSlot then return "quick", hp end
		if hp.IsRPInvDropZone then return "zone", hp end
		hp = hp:GetParent()
	end
end

function RPInv.ComputeDrop(grid, d)
	d = d or RPInv.Drag
	if not d or not IsValid(grid) then return end
	local st = store(grid.SID)
	local dd = defs()
	local def = dd[d.item]
	if not st or not def then return end
	local w, h = G.Size(def, d.rot)
	local cs = grid.Cell
	local mx, my = grid:CursorPos()
	local x = math.Clamp(math.floor(mx / cs - w / 2 + 0.5), 0, math.max(0, st.w - w))
	local y = math.Clamp(math.floor(my / cs - h / 2 + 0.5), 0, math.max(0, st.h - h))
	local same = d.sid == grid.SID
	local src = same and st.items[d.id] or nil
	local whole = d.n >= d.amount

	local under = G.ItemAt(st, dd, math.floor(mx / cs), math.floor(my / cs))
	if under and not (same and under.id == d.id) and G.CanStack(dd, { id = -1, item = d.item, meta = d.meta }, under) then
		local uw, uh = G.InstSize(dd, under)
		return { panel = grid, x = under.x, y = under.y, w = uw, h = uh, status = "merge", onto = under.id }
	end
	if G.CanPlace(st, dd, w, h, x, y, whole and src or nil) then
		return { panel = grid, x = x, y = y, w = w, h = h, status = "ok" }
	end
	if whole and d.sid ~= "e" and #G.Overlaps(st, dd, w, h, x, y, src) == 1 then
		return { panel = grid, x = x, y = y, w = w, h = h, status = "swap" }
	end
	return { panel = grid, x = x, y = y, w = w, h = h, status = "bad" }
end

local function startDrag(press)
	if press.equip then
		RPInv.Drag = { sid = "e", id = press.equip.key, item = press.equip.item, amount = 1, n = 1, rot = 0, meta = { jmod = { dur = press.equip.dur } } }
		RPInv.Hover = nil
		surface.PlaySound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav")
		return
	end
	local st = store(press.sid)
	local it = st and st.items[press.id]
	if not it then return end
	RPInv.Drag = {
		sid = press.sid, id = it.id, item = it.item, amount = it.amount, meta = it.meta,
		rot = it.rot, n = (press.ctrl and it.amount > 1) and 1 or it.amount,
	}
	RPInv.Hover = nil
	surface.PlaySound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav")
end

local function finishDrag()
	local d = RPInv.Drag
	RPInv.Drag = nil
	RPInv.DragTarget = nil
	if not d then return end
	local kind, panel = targetUnderCursor()
	local bad = function() surface.PlaySound("buttons/button10.wav") end
	if d.sid == "e" then
		if kind == "grid" then
			local r = RPInv.ComputeDrop(panel, d)
			if r and r.status == "ok" then
				RPInv.Act({ a = "unequip", key = d.id, to = panel.SID, x = r.x, y = r.y, rot = d.rot })
			else
				bad()
			end
		elseif kind == "zone" then
			RPInv.Act({ a = "unequip", key = d.id, drop = true })
		end
		return
	end
	if kind == "grid" then
		local r = RPInv.ComputeDrop(panel, d)
		if r and r.status ~= "bad" then
			RPInv.Act({ a = "move", from = d.sid, id = d.id, to = panel.SID, x = r.x, y = r.y, rot = d.rot, n = d.n, onto = r.onto })
			surface.PlaySound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav")
		else
			bad()
		end
	elseif kind == "quick" then
		RPInv.Act({ a = "quickbind", slot = panel.QuickIndex, item = d.item })
		surface.PlaySound("ui/buttonclick.wav")
	elseif kind == "slot" then
		if RPInv.SlotTakesAttachment(panel.SlotKey, defs()[d.item]) then
			RPInv.Act({ a = "attach", w = panel.SlotKey, item = d.item, from = d.sid, id = d.id })
		elseif RPInv.EquipSlotOf(defs()[d.item]) == panel.SlotKey then
			RPInv.Act({ a = "equip", from = d.sid, id = d.id, slot = panel.SlotKey })
		else
			bad()
		end
	elseif kind == "zone" then
		RPInv.Act({ a = "drop", from = d.sid, id = d.id, n = d.n })
	end
end

local rWasDown = false
hook.Add("Think", "RPInv_DragThink", function()
	local press = RPInv.Press
	if press then
		if not input.IsMouseDown(MOUSE_LEFT) then
			RPInv.Press = nil
		else
			local mx, my = gui.MousePos()
			if math.abs(mx - press.x) + math.abs(my - press.y) > 5 then
				RPInv.Press = nil
				startDrag(press)
			end
		end
	end

	local d = RPInv.Drag
	if not d then rWasDown = false return end
	if not IsValid(RPInv.Screen) or not input.IsMouseDown(MOUSE_LEFT) then
		if IsValid(RPInv.Screen) then finishDrag() else RPInv.Drag = nil RPInv.DragTarget = nil end
		return
	end
	local rDown = input.IsKeyDown(KEY_R)
	if rDown and not rWasDown then
		local def = defs()[d.item]
		if def and def.rotatable and def.w ~= def.h then
			d.rot = 1 - d.rot
			surface.PlaySound("ui/buttonrollover.wav")
		end
	end
	rWasDown = rDown

	local kind, panel = targetUnderCursor()
	RPInv.DragTarget = kind == "grid" and RPInv.ComputeDrop(panel) or nil
	RPInv.DragZone = kind == "zone" and panel or nil
	RPInv.DragSlot = kind == "slot" and panel or nil
end)

local function wrap(text, fontName, maxW)
	surface.SetFont(fontName)
	local lines, line = {}, ""
	for word in string.gmatch(text, "%S+") do
		local test = line == "" and word or (line .. " " .. word)
		if surface.GetTextSize(test) > maxW and line ~= "" then
			lines[#lines + 1] = line
			line = word
		else
			line = test
		end
	end
	if line ~= "" then lines[#lines + 1] = line end
	return lines
end

local tipCache = {}
local function modNames(inst)
	local data = inst.meta and inst.meta.atts
	if not istable(data) then return "" end
	local out = {}
	for _, a in ipairs(RPInv.Att.DataList(data)) do
		if not RPInv.Att.IsFree(data.b, a) then out[#out + 1] = RPInv.Att.AttName(data.b, a) end
	end
	return table.concat(out, ", ")
end

local function tooltipLines(def, inst, equipped)
	local dur, max = RPInv.Durability(def, inst)
	local mods = modNames(inst)
	local key = def.id .. "|" .. (inst.amount or 1) .. "|" .. def.descr .. "|" .. tostring(dur) .. "|" .. tostring(equipped) .. "|" .. mods
	local c = tipCache[key]
	if c then return c end
	local w, h = def.w, def.h
	local slot = RPInv.EquipSlotOf(def)
	local slotName = slot and RPInv.EquipSlotByKey[slot] and RPInv.EquipSlotByKey[slot].name
	local sub = string.upper((def.category ~= "" and def.category or def.use_type)) .. "   " .. w .. "x" .. h
	if def.max_stack > 1 then sub = sub .. "   " .. (inst.amount or 1) .. "/" .. def.max_stack end
	if dur then sub = sub .. "   DUR " .. math.floor(dur + 0.5) .. "/" .. math.floor(max + 0.5) end
	local hint
	if equipped then
		hint = "DBL-CLICK: UNEQUIP   DRAG: MOVE   RMB: MENU"
	elseif slot then
		hint = "DBL-CLICK: EQUIP (" .. slotName .. ")   SHIFT: MOVE"
	else
		hint = (def.use_type ~= "none" and "DBL-CLICK: USE   " or "") .. "SHIFT: MOVE   RMB: MENU"
	end
	local descr = wrap(def.descr or "", "RPInv.Small", T.S(260))
	if mods ~= "" then
		for _, l in ipairs(wrap("MODS: " .. mods, "RPInv.Small", T.S(260))) do descr[#descr + 1] = l end
	end
	c = { title = def.name, sub = sub, descr = descr, hint = hint }
	tipCache[key] = c
	return c
end

local function drawTooltip()
	local h = RPInv.Hover
	if not h or h.seen ~= FrameNumber() or RealTime() - h.since < 0.3 then return end
	local it, def
	if h.sid == "e" then
		it = h.equip and { amount = 1, dur = h.equip.dur, meta = h.equip.meta or {} }
		def = h.equip and defs()[h.equip.item]
	else
		local st = store(h.sid)
		it = st and st.items[h.id]
		def = it and defs()[it.item]
	end
	if not def then return end
	local c = tooltipLines(def, it, h.sid == "e")
	local pad = T.S(10)
	surface.SetFont("RPInv.Text")
	local tw = surface.GetTextSize(c.title)
	surface.SetFont("RPInv.Small")
	local w = math.max(tw, surface.GetTextSize(c.sub), surface.GetTextSize(c.hint), T.S(160))
	for _, l in ipairs(c.descr) do w = math.max(w, surface.GetTextSize(l)) end
	w = w + pad * 2
	local lh = T.S(15)
	local hgt = pad * 2 + T.S(18) + lh + #c.descr * lh + (#c.descr > 0 and T.S(6) or 0) + lh + T.S(4)
	local mx, my = gui.MousePos()
	local x, y = mx + 18, my + 18
	if x + w > ScrW() then x = mx - w - 8 end
	if y + hgt > ScrH() then y = my - hgt - 8 end
	surface.SetDrawColor(10, 11, 10, 245)
	surface.DrawRect(x, y, w, hgt)
	surface.SetDrawColor(T.Dim)
	surface.DrawOutlinedRect(x, y, w, hgt, 1)
	surface.SetDrawColor(T.Accent)
	surface.DrawRect(x, y, 3, hgt)
	local cy = y + pad
	draw.SimpleText(c.title, "RPInv.Text", x + pad, cy, T.White)
	cy = cy + T.S(18)
	draw.SimpleText(c.sub, "RPInv.Small", x + pad, cy, T.Accent)
	cy = cy + lh
	if #c.descr > 0 then
		cy = cy + T.S(6)
		for _, l in ipairs(c.descr) do
			draw.SimpleText(l, "RPInv.Small", x + pad, cy, T.Green)
			cy = cy + lh
		end
	end
	draw.SimpleText(c.hint, "RPInv.Small", x + pad, cy + T.S(4), T.Dim)
end

RPInv.Equipped = RPInv.Equipped or {}

local SLOT = {}

function SLOT:Init()
	self.IsRPInvEquipSlot = true
	self.LabelH = T.S(16)
	self:SetMouseInputEnabled(true)
end

function SLOT:Setup(key, labelH)
	self.SlotKey = key
	self.Info = RPInv.EquipSlotByKey[key]
	if labelH then self.LabelH = labelH end
end

function SLOT:Entry()
	local list = RPInv.Equipped[self.SlotKey]
	return list and list[1], list and #list or 0
end

function SLOT:Think()
	if self:IsHovered() and not RPInv.Drag then
		local e = self:Entry()
		if e then
			if not RPInv.Hover or RPInv.Hover.sid ~= "e" or RPInv.Hover.id ~= e.key then
				RPInv.Hover = { sid = "e", id = e.key, since = RealTime(), equip = e }
			end
			RPInv.Hover.equip = e
			RPInv.Hover.seen = FrameNumber()
		end
	end
end

function SLOT:Paint(w, h)
	local lab = self.LabelH
	local bh = h - lab
	local name = self.Info and self.Info.name or self.SlotKey
	local e, count = self:Entry()
	local drag = RPInv.Drag
	local fits = drag and drag.sid ~= "e" and (RPInv.EquipSlotOf(defs()[drag.item]) == self.SlotKey or RPInv.SlotTakesAttachment(self.SlotKey, defs()[drag.item]))
	draw.SimpleText(name, lab < T.S(14) and "RPInv.Tiny" or "RPInv.Small", 1, lab / 2, fits and T.Accent or T.Mid, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local def = e and defs()[e.item]
	if def then
		surface.SetDrawColor(14, 15, 14, 220)
		surface.DrawRect(0, lab, w, bh)
		local dragged = drag and drag.sid == "e" and drag.id == e.key
		RPInv.DrawItemBox(def, { amount = 1, rot = 0, dur = e.dur, meta = e.meta or {} }, 1, lab + 1, w - 2, bh - 2, dragged and 50 or 255, true)
		if count > 1 then
			draw.SimpleText("+" .. (count - 1), "RPInv.Small", 4, lab + 2, T.Accent)
		end
	else
		surface.SetDrawColor(12, 13, 12, 95)
		surface.DrawRect(0, lab, w, bh)
		surface.SetDrawColor(255, 255, 255, 6)
		for i = -bh, w, T.S(9) do surface.DrawLine(i, h, i + bh, lab) end
	end
	if fits then
		local hot = RPInv.DragSlot == self
		surface.SetDrawColor(T.GhostOk.r, T.GhostOk.g, T.GhostOk.b, hot and 90 or 35)
		surface.DrawRect(0, lab, w, bh)
		surface.SetDrawColor(T.GhostOk.r, T.GhostOk.g, T.GhostOk.b, 230)
		surface.DrawOutlinedRect(0, lab, w, bh, 2)
	elseif not drag and self:IsHovered() and e then
		surface.SetDrawColor(T.ItemHover)
		surface.DrawRect(0, lab, w, bh)
		surface.SetDrawColor(T.White)
		surface.DrawOutlinedRect(0, lab, w, bh, 1)
	else
		surface.SetDrawColor(e and T.Dim or T.Faint)
		surface.DrawOutlinedRect(0, lab, w, bh, 1)
	end
end

function SLOT:OnMousePressed(code)
	local e = self:Entry()
	if not e then return end
	if code == MOUSE_LEFT then
		local now = SysTime()
		if self.LastKey == e.key and now - (self.LastT or 0) < 0.3 then
			self.LastKey = nil
			RPInv.Press = nil
			RPInv.Act({ a = "unequip", key = e.key })
			return
		end
		self.LastKey, self.LastT = e.key, now
		local mx, my = gui.MousePos()
		RPInv.Press = { equip = e, x = mx, y = my }
	elseif code == MOUSE_RIGHT then
		RPInv.EquipMenu(self.SlotKey)
	end
end

vgui.Register("RPInvEquipSlot", SLOT, "DPanel")

function RPInv.SlotWeaponBase(slotKey)
	local list = RPInv.Equipped[slotKey]
	local e = list and list[1]
	local def = e and e.kind == "weapon" and defs()[e.item]
	if not def or def.use_type ~= "weapon" then return nil end
	local base = RPInv.Att.BaseOfClass(def.use_arg)
	if base and RPInv.Att.Editable[base] then return base end
end

function RPInv.SlotTakesAttachment(slotKey, def)
	if not def or def.use_type ~= "attachment" or not (RPInv.Settings and RPInv.Settings.att_items) then return false end
	local b = RPInv.Att.Parse(def.use_arg)
	return b ~= nil and RPInv.SlotWeaponBase(slotKey) == b
end

RPInv.QuickSlots = RPInv.QuickSlots or {}
local QUICK_KEYS = { "6", "7", "8", "9", "0" }
local QUICK_OK = setmetatable({ none = false }, { __index = function() return true end })

function RPInv.CountOwned(id)
	local n = 0
	local function add(st)
		if not st then return end
		for _, it in pairs(st.items) do
			if it.item == id then n = n + it.amount end
		end
	end
	add(RPInv.Stores.p)
	if RPInv.PocketsCid then add(RPInv.Stores["k:" .. RPInv.PocketsCid]) end
	for _, list in pairs(RPInv.Equipped or {}) do
		for _, e in ipairs(list) do
			if e.carrier then add(RPInv.Stores["k:" .. e.key]) end
		end
	end
	return n
end

local QUICK = {}

function QUICK:Init()
	self.IsRPInvQuickSlot = true
	self:SetMouseInputEnabled(true)
end

function QUICK:Setup(i)
	self.QuickIndex = i
end

function QUICK:Paint(w, h)
	local id = RPInv.QuickSlots["s" .. self.QuickIndex]
	local def = id and defs()[id]
	local drag = RPInv.Drag
	local fits = drag and drag.sid ~= "e" and defs()[drag.item] and QUICK_OK[defs()[drag.item].use_type]
	surface.SetDrawColor(14, 15, 14, 200)
	surface.DrawRect(0, 0, w, h)
	if def then
		local count = RPInv.CountOwned(id)
		RPInv.DrawItemBox(def, { amount = count, rot = 0, meta = {} }, 1, 1, w - 2, h - 2, count > 0 and 255 or 90, true)
		if def.max_stack <= 1 then
			shadowText(tostring(count), "RPInv.Count", w - 3, h, count > 0 and T.White or T.Red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		end
	end
	shadowText(QUICK_KEYS[self.QuickIndex], "RPInv.Text", 4, 2, T.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	if fits then
		local hot = vgui.GetHoveredPanel() == self
		surface.SetDrawColor(T.GhostOk.r, T.GhostOk.g, T.GhostOk.b, hot and 90 or 30)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(T.GhostOk.r, T.GhostOk.g, T.GhostOk.b, 230)
		surface.DrawOutlinedRect(0, 0, w, h, 2)
	else
		surface.SetDrawColor(self:IsHovered() and T.Accent or T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
end

function QUICK:OnMousePressed(code)
	if code == MOUSE_RIGHT and RPInv.QuickSlots["s" .. self.QuickIndex] then
		local m = T.Menu()
		T.MenuOption(m, "CLEAR QUICK SLOT", function() RPInv.Act({ a = "quickclear", slot = self.QuickIndex }) end)
		m:Open()
	end
end

vgui.Register("RPInvQuickSlot", QUICK, "DPanel")

hook.Add("DrawOverlay", "RPInv_DragOverlay", function()
	if not IsValid(RPInv.Screen) then return end
	local d = RPInv.Drag
	if d then
		local def = defs()[d.item]
		if not def then return end
		local cs = RPInv.DragTarget and RPInv.DragTarget.panel.Cell or T.CellSize()
		local w, h = G.Size(def, d.rot)
		local pw, ph = w * cs - 1, h * cs - 1
		local mx, my = gui.MousePos()
		local x, y = mx - pw / 2, my - ph / 2
		RPInv.DrawItemBox(def, { amount = d.n, rot = d.rot, meta = d.meta }, x, y, pw, ph, 210)
		surface.SetDrawColor(T.White)
		surface.DrawOutlinedRect(x, y, pw, ph, 1)
		if d.n < d.amount then
			draw.SimpleText(d.n .. " / " .. d.amount, "RPInv.Count", x + pw - 3, y + ph, T.Accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		end
		return
	end
	drawTooltip()
end)
