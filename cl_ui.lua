local T = RPInv.Theme
local G = RPInv.Grid

RPInv.Items = RPInv.Items or {}
RPInv.Stores = RPInv.Stores or {}
RPInv.Settings = RPInv.Settings or { player_grid_w = 10, player_grid_h = 6 }

local function readJSON()
	local len = net.ReadUInt(32)
	return util.JSONToTable(util.Decompress(net.ReadData(len)) or "") or {}
end

local function sendJSON(name, tbl)
	local data = util.Compress(util.TableToJSON(tbl))
	net.Start(name)
	net.WriteUInt(#data, 32)
	net.WriteData(data, #data)
	net.SendToServer()
end

RPInv.ReadJSON, RPInv.SendJSON = readJSON, sendJSON

function RPInv.Act(t)
	sendJSON("rpinv_act", t)
end

local toasts = {}
local TOAST_TIME = 4

function RPInv.Toast(text, kind)
	table.insert(toasts, 1, { text = text, kind = kind or 0, t = RealTime() })
	if #toasts > 6 then toasts[7] = nil end
	if kind == 2 then surface.PlaySound("buttons/button10.wav") end
end

hook.Add("DrawOverlay", "RPInv_Toasts", function()
	if #toasts == 0 then return end
	local now = RealTime()
	local x, y = T.S(24), ScrH() - T.S(150)
	local h = T.S(30)
	for i = #toasts, 1, -1 do
		local t = toasts[i]
		if now - t.t > TOAST_TIME + 0.4 then table.remove(toasts, i) end
	end
	for i, t in ipairs(toasts) do
		local age = now - t.t
		local a = age < 0.15 and age / 0.15 or (age > TOAST_TIME and math.max(0, 1 - (age - TOAST_TIME) / 0.4) or 1)
		surface.SetFont("RPInv.Text")
		local tw = surface.GetTextSize(t.text)
		local yy = y - (i - 1) * (h + T.S(4))
		local slide = (1 - math.min(1, age / 0.15)) * T.S(20)
		surface.SetDrawColor(10, 11, 10, 230 * a)
		surface.DrawRect(x - slide, yy, tw + T.S(28), h)
		local col = t.kind == 2 and T.Red or (t.kind == 1 and Color(120, 170, 80) or T.Accent)
		surface.SetDrawColor(col.r, col.g, col.b, 255 * a)
		surface.DrawRect(x - slide, yy, T.S(4), h)
		draw.SimpleText(t.text, "RPInv.Text", x - slide + T.S(16), yy + h / 2, Color(T.Green.r, T.Green.g, T.Green.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end)

local scr
local contWin
local kWin

local function isContainerSid(sid)
	return type(sid) == "string" and string.sub(sid, 1, 2) == "c:"
end

local function isCarrierSid(sid)
	return type(sid) == "string" and string.sub(sid, 1, 2) == "k:"
end

local function isWornCarrier(cid)
	for _, list in pairs(RPInv.Equipped or {}) do
		for _, e in ipairs(list) do
			if e.carrier and e.key == cid then return true end
		end
	end
	return false
end

local function closeCarrierWindow(notify)
	if IsValid(kWin) then
		kWin.Silent = not notify
		kWin:Remove()
	end
	kWin = nil
end

local function closeContainerWindow(notify)
	if IsValid(contWin) then
		local sid = contWin.SID
		contWin.Silent = not notify
		contWin:Remove()
		RPInv.Stores[sid] = nil
	end
	contWin = nil
end

local recentlyClosed = {}

local function sendExit(sid)
	local kid = string.match(sid or "", "^k:([%w_]+)$")
	if kid then
		recentlyClosed[sid] = RealTime()
		if not isWornCarrier(kid) then RPInv.Act({ a = "kclose", cid = kid }) end
		return
	end
	local cid = tonumber(string.match(sid or "", "^c:(%d+)$"))
	if not cid then return end
	recentlyClosed[sid] = RealTime()
	net.Start("rpinv_cexit")
	net.WriteUInt(cid, 32)
	net.SendToServer()
end

local function header(pnl, title, w)
	draw.SimpleText(title, "RPInv.Tab", 0, T.S(14), T.Green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	surface.SetDrawColor(T.Dim)
	surface.DrawRect(0, T.S(30), w, 1)
end

local function makeSearchSort(parent, sid, grid, right, y)
	local sort = T.Button(parent, "SORT", T.S(64), function() RPInv.Act({ a = "sort", sid = sid }) end)
	sort:SetFont("RPInv.Small")
	sort:SetTall(T.S(22))
	sort:SetPos(right - sort:GetWide(), y)
	local search = T.TextEntry(parent, "SEARCH")
	search:SetFont("RPInv.Small")
	search:SetSize(T.S(140), T.S(22))
	search:SetPos(right - sort:GetWide() - T.S(6) - search:GetWide(), y)
	search:SetUpdateOnType(true)
	search.OnValueChange = function(s) grid.Search = s:GetText() end
	return search, sort
end

local function usedCells(st)
	local n = 0
	for _, it in pairs(st.items) do
		local w, h = G.InstSize(RPInv.Items, it)
		n = n + w * h
	end
	return n
end

local function buildContainerWindow(sid)
	if not IsValid(scr) then return end
	local carrier = isCarrierSid(sid)
	if carrier then
		closeCarrierWindow(false)
	else
		if IsValid(contWin) then
			contWin.Silent = true
			contWin:Remove()
		end
		contWin = nil
	end
	local st = RPInv.Stores[sid]
	if not st then return end
	local cs = math.max(20, math.min(T.CellSize(), math.floor(ScrW() * 0.5 / st.w)))
	local gridW, gridH = st.w * cs + 1, st.h * cs + 1
	local maxGridH = math.floor(ScrH() * 0.62)
	local scrollH = math.min(gridH, maxGridH)
	local pad = T.S(8)
	local headH = T.S(34)
	local w = math.max(gridW + pad * 2 + (gridH > maxGridH and 8 or 0), T.S(330))
	local h = headH + scrollH + pad * 2 + T.S(18)

	local win = vgui.Create("DPanel", scr)
	win.SID = sid
	win:SetSize(w, h)
	local ax = scr.CarrierX or ScrW() / 3
	local wy = scr.BodyY + T.S(18) + T.S(40) + T.S(16) + cs * 2 + T.S(24)
	if carrier then wy = wy + T.S(60) end
	if wy + h > ScrH() then wy = math.max(scr.BodyY + T.S(10), ScrH() - h - T.S(10)) end
	win:SetPos(ax + T.S(carrier and 70 or 10), wy)
	win:SetAlpha(0)
	win:AlphaTo(255, 0.12)
	win.Paint = function(s, pw, ph)
		surface.SetDrawColor(T.WinBg)
		surface.DrawRect(0, 0, pw, ph)
		surface.SetDrawColor(T.HeadBg)
		surface.DrawRect(0, 0, pw, headH)
		surface.SetDrawColor(T.Accent)
		surface.DrawRect(0, headH - 1, pw, 1)
		local cur = RPInv.Stores[sid]
		draw.SimpleText(string.upper(cur and cur.name or "CONTAINER"), "RPInv.Tab", pad + T.S(4), headH / 2, T.White, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if cur then
			draw.SimpleText(string.format("%d x %d   %d / %d", cur.w, cur.h, usedCells(cur), cur.w * cur.h), "RPInv.Tiny", pad, ph - T.S(10), T.Dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		surface.SetDrawColor(T.Dim)
		surface.DrawOutlinedRect(0, 0, pw, ph, 1)
		surface.SetDrawColor(T.Accent)
		T.Corners(0, 0, pw, ph, T.S(10), 2)
	end

	local scroll = vgui.Create("DScrollPanel", win)
	scroll:SetPos(pad, headH + pad)
	scroll:SetSize(w - pad * 2, scrollH)
	T.StyleScroll(scroll)
	local grid = scroll:Add("RPInvGrid")
	grid:SetCell(cs)
	grid:SetStore(sid)
	grid:SetPos(0, 0)

	local close = T.CloseButton(win, function()
		sendExit(sid)
		if carrier then closeCarrierWindow(false) else closeContainerWindow(false) end
	end)
	close:SetSize(T.S(22), T.S(22))
	close:SetPos(w - close:GetWide() - T.S(6), (headH - close:GetTall()) / 2)
	makeSearchSort(win, sid, grid, w - close:GetWide() - T.S(12), (headH - T.S(22)) / 2)

	win.OnMousePressed = function(s, code)
		if code ~= MOUSE_LEFT then return end
		local mx, my = gui.MousePos()
		local x, y = s:GetPos()
		s.Grab = { mx - x, my - y }
	end
	win.Think = function(s)
		local down = input.IsMouseDown(MOUSE_LEFT)
		if down and not s.WasDown and (s:IsHovered() or s:IsChildHovered()) then s:MoveToFront() end
		s.WasDown = down
		if s.Grab then
			if not down then s.Grab = nil return end
			local mx, my = gui.MousePos()
			s:SetPos(math.Clamp(mx - s.Grab[1], 0, ScrW() - s:GetWide()), math.Clamp(my - s.Grab[2], 0, ScrH() - T.S(40)))
		end
	end
	win.OnRemove = function(s)
		if not s.Silent then sendExit(sid) end
		if RPInv.Drag and RPInv.Drag.sid == sid then RPInv.Drag = nil end
	end
	if carrier then
		kWin = win
		surface.PlaySound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav")
	else
		contWin = win
		surface.PlaySound("items/ammocrate_open.wav")
	end
end

local MAIN_SLOTS = {
	{ "ears", 0, 0, 1 }, { "head", 1, 0, 1 }, { "face", 2, 0, 1 },
	{ "belt", 0, 1, 1 }, { "body", 1, 1, 1 }, { "eyes", 2, 1, 1 },
	{ "primary", 0, 2, 2 }, { "secondary", 2, 2, 1 },
	{ "utility", 0, 3, 2 },
}

local LIMB_SLOTS = {
	{ "lshoulder", "rshoulder", "lforearm", "rforearm" },
	{ "lthigh", "rthigh", "lcalf", "rcalf" },
}

local function buildDoll(parent, w, h)
	local lp = LocalPlayer()
	local doll = vgui.Create("DModelPanel", parent)
	doll:SetSize(w, h)
	doll:SetModel(IsValid(lp) and lp:GetModel() or "models/player/kleiner.mdl")
	local fov = 30
	doll:SetFOV(fov)
	doll:SetAmbientLight(Color(150, 150, 145))
	doll:SetDirectionalLight(BOX_FRONT, Color(235, 235, 225))
	doll:SetDirectionalLight(BOX_TOP, Color(200, 200, 190))
	doll:SetDirectionalLight(BOX_LEFT, Color(120, 120, 115))
	doll:SetDirectionalLight(BOX_RIGHT, Color(120, 120, 115))
	doll:SetMouseInputEnabled(false)
	local ent = doll:GetEntity()
	if IsValid(ent) and IsValid(lp) then
		ent:SetSkin(lp:GetSkin())
		for i = 0, lp:GetNumBodyGroups() - 1 do ent:SetBodygroup(i, lp:GetBodygroup(i)) end
		local col = lp:GetPlayerColor()
		ent.GetPlayerColor = function() return col end
		local seq = ent:LookupSequence("idle_all_01")
		if seq and seq > 0 then ent:ResetSequence(seq) end
		local mn, mx = ent:GetRenderBounds()
		local height = math.Clamp(mx.z - mn.z, 40, 120)
		local center = Vector(0, 0, mn.z + height / 2)
		local halfV = math.tan(math.rad(fov / 2)) * h / w
		local dist = (height * 0.5 / 0.96) / halfV
		doll:SetLookAt(center)
		doll:SetCamPos(center + Vector(dist, 0, 0))
	end
	doll.LayoutEntity = function(s, e)
		s:RunAnimation()
		e:SetAngles(Angle(0, 12 * math.sin(RealTime() * 0.4), 0))
	end
	doll.PostDrawModel = function(_, e)
		local p = LocalPlayer()
		if not RPInv.JModAvailable() or not isfunction(JMod.ArmorPlayerModelDraw) or not IsValid(p) or not p.EZarmor then return end
		e.EZarmor = p.EZarmor
		pcall(JMod.ArmorPlayerModelDraw, e, true)
	end
	doll.OnRemove = function(s)
		local e = s:GetEntity()
		if IsValid(e) and istable(e.EZarmorModels) then
			for _, m in pairs(e.EZarmorModels) do
				if IsValid(m) then m:Remove() end
			end
		end
	end
	return doll
end

local function slotPanel(parent, key, x, y, w, h, lab)
	local p = vgui.Create("RPInvEquipSlot", parent)
	p:Setup(key, lab)
	p:SetPos(x, y)
	p:SetSize(w, h)
	return p
end

local function buildEquipment(col, w, hgt)
	col.Paint = function(_, pw) header(col, "EQUIPMENT", pw) end
	local cs = T.CellSize()
	local gap = T.S(10)
	local lab = T.S(16)
	local box = cs * 2
	local top = T.S(40)
	local area = 4 * (lab + box + gap) - gap
	buildDoll(col, w, math.min(area, hgt - top)):SetPos(0, top)
	for _, s in ipairs(MAIN_SLOTS) do
		local key, cx, cy, span = s[1], s[2], s[3], s[4]
		slotPanel(col, key, cx * (box + gap), top + cy * (lab + box + gap), box * span + gap * (span - 1), lab + box, lab)
	end
	local small = math.floor((w - gap * 3) / 4)
	local slab = T.S(13)
	local y = top + area + gap * 2
	for r, row in ipairs(LIMB_SLOTS) do
		for i, key in ipairs(row) do
			if y + slab + small <= hgt then
				slotPanel(col, key, (i - 1) * (small + gap), y, small, slab + small, slab)
			end
		end
		y = y + slab + small + gap
	end
end

local function buildCarriers(col, w)
	col.IsRPInvDropZone = true
	local cs = T.CellSize()
	local lab = T.S(16)
	local top = T.S(40)
	local box = cs * 2
	slotPanel(col, "back", 0, top, box, lab + box, lab)
	local zoneY = top + lab + box + T.S(20)

	local px = box + T.S(16)
	local pockets = vgui.Create("DPanel", col)
	pockets:SetPos(px, top)
	pockets:SetSize(w - px, lab + cs + 2)
	pockets.Paint = function()
		draw.SimpleText("POCKETS", "RPInv.Small", 1, lab / 2, T.Mid, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local pgrid = vgui.Create("RPInvGrid", pockets)
	pgrid:SetPos(0, lab)
	pockets.Think = function()
		local cid = RPInv.PocketsCid
		if not cid then return end
		local pw = math.max(1, RPInv.PocketsW or 4)
		local c2 = math.max(20, math.min(cs, math.floor((w - px - T.S(8)) / pw)))
		if pgrid.SID ~= "k:" .. cid or pgrid.Cell ~= c2 then
			pgrid:SetCell(c2)
			pgrid:SetStore("k:" .. cid)
		end
		pockets:SetVisible((RPInv.PocketsW or 0) > 0 and (RPInv.PocketsH or 0) > 0)
		pockets:SetTall(lab + c2 * math.max(1, RPInv.PocketsH or 1) + 2)
	end

	local qs = math.min(cs, math.floor((w - T.S(8) * 4) / 5))
	local qh = T.S(18) + qs
	local qbar = vgui.Create("DPanel", col)
	qbar:SetSize(w, qh)
	qbar:SetPos(0, col:GetTall() - qh)
	qbar.Paint = function()
		draw.SimpleText("QUICK SLOTS  (PRESS THE KEY TWICE)", "RPInv.Small", 1, T.S(8), T.Mid, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	for i = 1, 5 do
		local q = vgui.Create("RPInvQuickSlot", qbar)
		q:Setup(i)
		q:SetPos((i - 1) * (qs + T.S(8)), T.S(18))
		q:SetSize(qs, qs)
	end

	local list = vgui.Create("DScrollPanel", col)
	list:SetPos(0, zoneY)
	list:SetSize(w, col:GetTall() - zoneY - qh - T.S(12))
	T.StyleScroll(list)
	list.Empty = true
	local order = { "back", "body", "belt" }
	for _, s in ipairs(RPInv.EquipSlots) do
		if s.key ~= "back" and s.key ~= "body" and s.key ~= "belt" then order[#order + 1] = s.key end
	end
	local function rebuild()
		if not IsValid(list) then return end
		local entries, sig = {}, ""
		for _, key in ipairs(order) do
			for _, e in ipairs(RPInv.Equipped[key] or {}) do
				local def = e.carrier and RPInv.Items[e.item]
				if def and (def.grid_w or 0) > 0 then
					entries[#entries + 1] = { key = key, e = e, def = def }
					sig = sig .. e.key .. ":" .. def.grid_w .. "x" .. def.grid_h .. ";"
				end
			end
		end
		if sig == list.Sig then return end
		list.Sig = sig
		list:Clear()
		list.Empty = #entries == 0
		for _, en in ipairs(entries) do
			local def = en.def
			local cs2 = math.max(20, math.min(cs, math.floor((w - T.S(16)) / def.grid_w)))
			local headH = T.S(22)
			local sec = list:Add("DPanel")
			sec:Dock(TOP)
			sec:DockMargin(0, 0, T.S(8), T.S(12))
			sec:SetTall(headH + def.grid_h * cs2 + 1)
			local slotName = RPInv.EquipSlotByKey[en.key] and RPInv.EquipSlotByKey[en.key].name or ""
			sec.Paint = function(_, pw)
				draw.SimpleText(slotName, "RPInv.Small", 0, headH / 2, T.Mid, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText(string.upper(def.name) .. "  " .. def.grid_w .. "x" .. def.grid_h, "RPInv.Tiny", pw, headH / 2, T.Dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
			local g = vgui.Create("RPInvGrid", sec)
			g:SetCell(cs2)
			g:SetStore("k:" .. en.e.key)
			g:SetPos(0, headH)
		end
	end
	list.Think = function(s)
		if (s.NextCheck or 0) > RealTime() then return end
		s.NextCheck = RealTime() + 0.2
		rebuild()
	end
	rebuild()
	col.Paint = function(_, pw)
		header(col, "CARRIERS", pw)
		if list.Empty then
			draw.SimpleText("TACTICAL RIG / BACKPACK / POUCH", "RPInv.Small", 0, zoneY + T.S(8), T.Dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText("NO STORAGE EQUIPPED", "RPInv.Tiny", 0, zoneY + T.S(26), T.Faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
end

local function buildInventory(col, w, hgt, cs)
	cs = cs or T.CellSize()
	if (RPInv.Settings.player_grid_w or 10) <= 0 then
		col.Paint = function(_, pw)
			header(col, "INVENTORY", pw)
			draw.SimpleText("NO MAIN INVENTORY", "RPInv.Small", 0, T.S(52), T.Dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText("USE POCKETS, RIGS AND BACKPACKS", "RPInv.Tiny", 0, T.S(70), T.Faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		return
	end
	local top = T.S(40)
	local scroll = vgui.Create("DScrollPanel", col)
	scroll:SetPos(0, top)
	scroll:SetSize(w, hgt - top - T.S(22))
	T.StyleScroll(scroll)
	local grid = scroll:Add("RPInvGrid")
	grid:SetStore("p")
	grid:SetCell(cs)
	makeSearchSort(col, "p", grid, w - T.S(8), T.S(3))
	col.Paint = function(_, pw, ph)
		header(col, "INVENTORY", pw)
		local st = RPInv.Stores.p
		if st then
			draw.SimpleText(string.format("%d x %d   %d / %d CELLS", st.w, st.h, usedCells(st), st.w * st.h), "RPInv.Small", 0, ph - T.S(10), T.Dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText("R: ROTATE   CTRL+DRAG: ONE   SHIFT+CLICK: QUICK MOVE", "RPInv.Tiny", pw - T.S(8), ph - T.S(10), T.Dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	col.Grid = grid
end

local function buildGear(page, W, H)
	local cs = T.CellSize()
	local pad = T.S(18)
	local eqW = cs * 6 + T.S(10) * 2
	local cols = RPInv.Settings.player_grid_w or 10
	local maxInvW = math.min(math.floor(W * 0.42), W - pad * 4 - eqW - cs * 6)
	local icell = math.max(20, math.min(cs, math.floor((maxInvW - 1 - T.S(14)) / math.max(cols, 1))))
	local gw = cols > 0 and (cols * icell + 1 + T.S(14)) or cs * 5
	local inv = vgui.Create("DPanel", page)
	inv:SetPos(W - gw - pad, pad)
	inv:SetSize(gw, H - pad * 2)
	buildInventory(inv, gw, H - pad * 2, icell)

	local eq = vgui.Create("DPanel", page)
	eq:SetPos(pad, pad)
	eq:SetSize(eqW, H - pad * 2)
	buildEquipment(eq, eqW, H - pad * 2)

	local cx = pad * 2 + eqW
	local cw = W - gw - pad * 4 - eqW
	local car = vgui.Create("DPanel", page)
	car:SetPos(cx, pad)
	car:SetSize(math.max(cw, cs * 3), H - pad * 2)
	buildCarriers(car, math.max(cw, cs * 3))
	return cx
end

local function tabButton(bar, text, onClick)
	local b = vgui.Create("DButton", bar)
	b:SetText("")
	surface.SetFont("RPInv.Tab")
	local tw = surface.GetTextSize(text)
	b:SetSize(tw + T.S(40), bar:GetTall() - T.S(10))
	b.Paint = function(s, w, h)
		local on = bar.Active == s
		if on then
			surface.SetDrawColor(T.TabOn)
			surface.DrawRect(0, 0, w, h)
		elseif s:IsHovered() then
			surface.SetDrawColor(255, 255, 255, 14)
			surface.DrawRect(0, 0, w, h)
		end
		draw.SimpleText(text, "RPInv.Tab", w / 2, h / 2, on and T.TabOnText or (s:IsHovered() and T.White or T.Mid), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	b.OnCursorEntered = function() surface.PlaySound("ui/buttonrollover.wav") end
	b.DoClick = function(s)
		surface.PlaySound("ui/buttonclick.wav")
		bar.Active = s
		onClick()
	end
	return b
end

local function openScreen()
	if IsValid(scr) then return scr end
	RPInv.Hover, RPInv.Drag, RPInv.Press = nil, nil, nil
	scr = vgui.Create("EditablePanel")
	RPInv.Screen = scr
	scr:SetSize(ScrW(), ScrH())
	scr:SetPos(0, 0)
	scr:MakePopup()
	scr.Start = SysTime()
	scr:SetAlpha(0)
	scr:AlphaTo(255, 0.12)
	surface.PlaySound("npc/combine_soldier/gear" .. math.random(1, 6) .. ".wav")
	scr.Paint = function(s, w, h)
		Derma_DrawBackgroundBlur(s, s.Start)
		surface.SetDrawColor(T.ScreenDim)
		surface.DrawRect(0, 0, w, h)
	end

	local barH = T.S(44)
	local bar = vgui.Create("DPanel", scr)
	bar:SetPos(0, 0)
	bar:SetSize(ScrW(), barH)
	bar.Paint = function(_, w, h)
		surface.SetDrawColor(T.BarBg)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(T.Dim)
		surface.DrawRect(0, h - 1, w, 1)
	end

	local bodyY = barH
	local bodyH = ScrH() - barH
	scr.BodyY = bodyY

	local pages = {}
	local function show(key)
		for k, p in pairs(pages) do p:SetVisible(k == key) end
		if IsValid(contWin) then contWin:SetVisible(key == "gear") end
		if IsValid(kWin) then kWin:SetVisible(key == "gear") end
	end

	local gear = vgui.Create("DPanel", scr)
	gear:SetPos(0, bodyY)
	gear:SetSize(ScrW(), bodyH)
	gear.Paint = nil
	pages.gear = gear
	scr.CarrierX = buildGear(gear, ScrW(), bodyH)

	local x = T.S(14)
	local gb = tabButton(bar, "GEAR", function() show("gear") end)
	gb:SetPos(x, T.S(5))
	bar.Active = gb
	x = x + gb:GetWide() + T.S(4)

	if LocalPlayer():IsSuperAdmin() and RPInv.BuildAdmin then
		local ab = tabButton(bar, "ADMIN", function()
			if not pages.admin then
				local admin = vgui.Create("DPanel", scr)
				admin:SetPos(0, bodyY)
				admin:SetSize(ScrW(), bodyH)
				admin.Paint = nil
				RPInv.BuildAdmin(admin, ScrW(), bodyH)
				pages.admin = admin
			end
			show("admin")
		end)
		ab:SetPos(x, T.S(5))
		scr.OpenAdmin = function()
			ab:DoClick()
			bar.Active = ab
		end
	end

	local back = vgui.Create("DButton", bar)
	back:SetText("")
	back:SetSize(T.S(120), barH - T.S(10))
	back:SetPos(ScrW() - back:GetWide() - T.S(14), T.S(5))
	back.Paint = function(s, w, h)
		draw.SimpleText("BACK", "RPInv.Big", w - T.S(4), h / 2, s:IsHovered() and T.White or T.Green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	back.DoClick = function()
		surface.PlaySound("ui/buttonclick.wav")
		RPInv.CloseScreen()
	end

	scr.Think = function(s)
		if gui.IsGameUIVisible() then
			gui.HideGameUI()
			RPInv.CloseScreen()
		end
	end
	scr.OnRemove = function()
		if IsValid(contWin) then
			local sid = contWin.SID
			sendExit(sid)
			contWin.Silent = true
			RPInv.Stores[sid] = nil
		end
		contWin = nil
		if IsValid(kWin) then
			sendExit(kWin.SID)
			kWin.Silent = true
		end
		kWin = nil
		RPInv.Drag, RPInv.Press, RPInv.Hover, RPInv.DragTarget = nil, nil, nil, nil
		RPInv.Screen = nil
	end
	surface.PlaySound("ui/buttonclickrelease.wav")

	for sid in pairs(RPInv.Stores) do
		if isContainerSid(sid) then buildContainerWindow(sid) break end
	end
	return scr
end

RPInv.OpenScreen = function() return openScreen() end

function RPInv.CloseScreen()
	if IsValid(scr) then scr:Remove() end
	scr = nil
end

function RPInv.ToggleScreen()
	if IsValid(scr) then RPInv.CloseScreen() else openScreen() end
end

local function afterGameUI(fn)
	if gui.IsGameUIVisible() then
		gui.HideGameUI()
		local tries = 0
		timer.Create("RPInv_AfterGameUI", 0.05, 40, function()
			tries = tries + 1
			if not gui.IsGameUIVisible() then
				timer.Remove("RPInv_AfterGameUI")
				fn()
			elseif tries % 5 == 0 then
				gui.HideGameUI()
			end
		end)
		return
	end
	fn()
end

concommand.Add("rpinv_admin", function()
	local lp = LocalPlayer()
	if not IsValid(lp) or not lp:IsSuperAdmin() then
		RPInv.Toast("The admin panel is for superadmins only.", 2)
		return
	end
	afterGameUI(function()
		if not IsValid(scr) then openScreen() end
		if IsValid(scr) and scr.OpenAdmin then scr.OpenAdmin() end
	end)
end, nil, "Open the inventory admin panel (superadmin)")

RPInv.AfterGameUI = afterGameUI

function RPInv.RebuildScreen()
	if not IsValid(scr) then return end
	if IsValid(contWin) then contWin.Silent = true end
	if IsValid(kWin) then kWin.Silent = true end
	scr.OnRemove = function() RPInv.Screen = nil end
	scr:Remove()
	scr = nil
	contWin = nil
	kWin = nil
	openScreen()
end

local function containerSid()
	for sid in pairs(RPInv.Stores) do
		if isContainerSid(sid) then return sid end
	end
end

local function useText(def)
	local a = def.use_arg or ""
	if def.use_type == "heal" then return "Restores " .. a .. " health"
	elseif def.use_type == "armor" then return "Restores " .. a .. " armor"
	elseif def.use_type == "weapon" then return "Gives weapon: " .. a
	elseif def.use_type == "resource" then
		return "Places a JMod resource box (the stack is the number of units)"
	elseif def.use_type == "entuse" then
		return "Used like pressing E on it"
	elseif def.use_type == "rounds" then
		return "Reserve ammo (" .. a .. "): weapons reload from it"
	elseif def.use_type == "flare" then
		return "Calls an airdrop. Fire it straight up into open sky. Single use."
	elseif def.use_type == "attachment" then
		local b = RPInv.Att.Parse(a)
		return "Weapon attachment" .. (b and (" (" .. RPInv.Att.BaseNames[b] .. ")") or "")
	elseif def.use_type == "ammo" then
		local at, n = string.match(a, "^(.+):(%d+)$")
		return "Gives " .. (n or "?") .. " " .. (at or "?") .. " ammo"
	end
	return "No use effect"
end
RPInv.UseText = useText

function RPInv.Inspect(def, inst, slotKey)
	local f = T.Frame("INSPECT :: " .. string.upper(def.name), T.S(820), T.S(500))
	f:Center()
	f:DoModal()
	f:SetAlpha(0)
	f:AlphaTo(255, 0.12)
	local mw = T.S(500)
	local mods = {}
	local data = inst and inst.meta and inst.meta.atts
	if istable(data) then
		for _, a in ipairs(RPInv.Att.DataList(data)) do
			if not RPInv.Att.IsFree(data.b, a) then mods[#mods + 1] = { n = RPInv.Att.AttName(data.b, a), arg = data.b .. ":" .. a } end
		end
	end
	if slotKey and def.use_type == "weapon" and RPInv.SlotWeaponBase(slotKey) then
		local view = vgui.Create("RPInvModView", f)
		view:SetPos(T.S(10), T.S(42))
		view:SetSize(mw, f:GetTall() - T.S(52))
		view.Slot = slotKey
		view.Data = { slots = {} }
		RPInv.InspectInfo(f, def, inst, mw, mods)
		return
	end
	local mdl = vgui.Create("DModelPanel", f)
	mdl:SetPos(T.S(10), T.S(42))
	mdl:SetSize(mw, f:GetTall() - T.S(52))
	mdl:SetModel(def.model)
	RPInv.ApplyLook(mdl:GetEntity(), def)
	mdl:SetAmbientLight(Color(255, 255, 255))
	for _, side in ipairs({ BOX_TOP, BOX_BOTTOM, BOX_FRONT, BOX_BACK, BOX_LEFT, BOX_RIGHT }) do
		mdl:SetDirectionalLight(side, Color(200, 200, 200))
	end
	mdl:SetFOV(30)
	local ent = mdl:GetEntity()
	local center, radius = vector_origin, 20
	local fb = RPInv.ModelFixBounds(def.model)
	if IsValid(ent) and fb then
		RPInv.ApplyModelFix(ent)
		RPInv.ModelFixHook(ent)
		center = fb.center
		radius = math.max(fb.mins:Distance(fb.maxs) / 2, 2)
	elseif IsValid(ent) then
		local mn, mx = ent:GetRenderBounds()
		center = (mn + mx) / 2
		radius = math.max(mn:Distance(mx) / 2, 2)
	end
	mdl.Dist = radius * 3.6
	mdl.Ang = Angle(15, 35, 0)
	mdl:SetLookAt(vector_origin)
	mdl.LayoutEntity = function(s, e)
		if s.Grab then
			local mx, my = gui.MousePos()
			s.Ang.y = s.Ang.y + (mx - s.Grab[1]) * 0.5
			s.Ang.p = math.Clamp(s.Ang.p + (my - s.Grab[2]) * 0.5, -89, 89)
			s.Grab = { mx, my }
			if not input.IsMouseDown(MOUSE_LEFT) then s.Grab = nil end
		end
		e:SetAngles(Angle(0, 0, 0))
		e:SetPos(-center)
		local dir = s.Ang:Forward()
		s:SetCamPos(-dir * s.Dist)
		s:SetLookAng(s.Ang)
	end
	mdl.OnMousePressed = function(s, code)
		if code == MOUSE_LEFT then s.Grab = { gui.MousePos() } end
	end
	mdl.OnMouseWheeled = function(s, delta)
		s.Dist = math.Clamp(s.Dist * (delta > 0 and 0.88 or 1.12), radius * 1.2, radius * 10)
		return true
	end
	local paintModel = mdl.Paint
	mdl.Paint = function(s, w, h)
		surface.SetDrawColor(T.CellBg)
		surface.DrawRect(0, 0, w, h)
		paintModel(s, w, h)
		surface.SetDrawColor(T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		draw.SimpleText("DRAG: ROTATE   WHEEL: ZOOM", "RPInv.Tiny", T.S(8), h - T.S(10), T.Dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	RPInv.InspectInfo(f, def, inst, mw, mods)
end

function RPInv.InspectInfo(f, def, inst, mw, mods)
	local info = vgui.Create("DPanel", f)
	info:SetPos(mw + T.S(22), T.S(48))
	info:SetSize(f:GetWide() - mw - T.S(34), f:GetTall() - T.S(60))
	local rows = {
		{ "TYPE", string.upper(def.category ~= "" and def.category or def.use_type) },
		{ "SIZE", def.w .. " x " .. def.h .. (def.rotatable and "" or "  (fixed)") },
		{ "STACK", tostring(def.max_stack) },
		{ "EFFECT", useText(def) },
	}
	local slot = RPInv.EquipSlotOf(def)
	if slot and RPInv.EquipSlotByKey[slot] then
		rows[#rows + 1] = { "SLOT", RPInv.EquipSlotByKey[slot].name }
	end
	local dur, max = RPInv.Durability(def, inst)
	if dur then
		rows[#rows + 1] = { "DURABILITY", math.floor(dur + 0.5) .. " / " .. math.floor(max + 0.5) }
	end
	if def.jmod_armor ~= "" then
		rows[#rows + 1] = { "JMOD", def.jmod_armor }
	end
	info.Paint = function(_, w)
		draw.SimpleText(def.name, "RPInv.Title", 0, 0, T.White)
		local y = T.S(36)
		for _, r in ipairs(rows) do
			draw.SimpleText(r[1], "RPInv.Small", 0, y, T.Dim)
			draw.SimpleText(r[2], "RPInv.Text", T.S(70), y - 1, T.Green)
			y = y + T.S(22)
		end
		surface.SetDrawColor(T.Dim)
		surface.DrawRect(0, y + T.S(4), w, 1)
	end
	local d = vgui.Create("DLabel", info)
	d:SetPos(0, T.S(36) + #rows * T.S(22) + T.S(14))
	d:SetWide(info:GetWide())
	d:SetFont("RPInv.Text")
	d:SetTextColor(T.Mid)
	d:SetWrap(true)
	d:SetAutoStretchVertical(true)
	d:SetText(def.descr ~= "" and def.descr or "No description.")
	if not mods or #mods == 0 then return end
	local tile = T.S(64)
	local gap = T.S(6)
	local perRow = math.max(1, math.floor((info:GetWide() + gap) / (tile + gap)))
	local rows = math.ceil(#mods / perRow)
	local strip = vgui.Create("DPanel", info)
	local sh = T.S(20) + rows * (tile + T.S(16) + gap)
	strip:SetSize(info:GetWide(), sh)
	strip:SetPos(0, info:GetTall() - sh)
	strip.Paint = function()
		draw.SimpleText("ATTACHMENTS (" .. #mods .. ")", "RPInv.Small", 0, 0, T.Accent)
		for i, m in ipairs(mods) do
			local col = (i - 1) % perRow
			local row = math.floor((i - 1) / perRow)
			local x, y = col * (tile + gap), T.S(20) + row * (tile + T.S(16) + gap)
			surface.SetDrawColor(T.CellBg)
			surface.DrawRect(x, y, tile, tile)
			local adef = RPInv.Items[RPInv.Att.ItemId(RPInv.Att.Parse(m.arg))] or { use_arg = m.arg, use_type = "attachment", name = m.n, w = 1, h = 1, max_stack = 1, model = "models/items/boxsrounds.mdl", cam_ang = "", cam_fov = 1, category = "" }
			local icon = RPInv.Att.Icon(adef)
			if icon then
				surface.SetMaterial(icon)
				surface.SetDrawColor(255, 255, 255)
				surface.DrawTexturedRect(x + 2, y + 2, tile - 4, tile - 4)
			elseif RPInv.Items[adef.id or ""] then
				RPInv.DrawItemBox(adef, { amount = 1, rot = 0, meta = {} }, x, y, tile, tile, 255, true)
			end
			surface.SetDrawColor(T.Dim)
			surface.DrawOutlinedRect(x, y, tile, tile, 1)
			surface.SetFont("RPInv.Tiny")
			local name = m.n
			while #name > 1 and surface.GetTextSize(name) > tile do name = string.sub(name, 1, #name - 1) end
			draw.SimpleText(name, "RPInv.Tiny", x, y + tile + T.S(2), T.Green)
		end
	end
end

function RPInv.SplitDialog(sid, it)
	local def = RPInv.Items[it.item]
	if not def or it.amount < 2 then return end
	local f = T.Frame("SPLIT :: " .. string.upper(def.name), T.S(360), T.S(170))
	f:Center()
	f:DoModal()
	local value = math.floor(it.amount / 2)
	local entry = T.TextEntry(f)
	entry:SetNumeric(true)
	entry:SetSize(T.S(70), T.S(26))
	entry:SetPos(f:GetWide() - T.S(86), T.S(54))
	entry:SetText(tostring(value))
	local slider = vgui.Create("DPanel", f)
	slider:SetPos(T.S(16), T.S(58))
	slider:SetSize(f:GetWide() - T.S(118), T.S(18))
	local function setValue(v, fromEntry)
		value = math.Clamp(math.floor(v), 1, it.amount - 1)
		if not fromEntry then entry:SetText(tostring(value)) end
	end
	slider.Paint = function(s, w, h)
		if s.Down then
			if not input.IsMouseDown(MOUSE_LEFT) then s.Down = false end
			local mx = s:CursorPos()
			setValue(1 + (it.amount - 2) * math.Clamp(mx / w, 0, 1) + 0.5)
		end
		surface.SetDrawColor(T.InputBg)
		surface.DrawRect(0, h / 2 - 2, w, 4)
		local frac = it.amount > 2 and (value - 1) / (it.amount - 2) or 0.5
		surface.SetDrawColor(T.Accent)
		surface.DrawRect(0, h / 2 - 2, w * frac, 4)
		surface.DrawRect(w * frac - 4, 0, 8, h)
	end
	slider.OnMousePressed = function(s) s.Down = true end
	entry.OnChange = function(s) setValue(tonumber(s:GetText()) or 1, true) end
	local ok = T.Button(f, "SPLIT", T.S(110), function()
		RPInv.Act({ a = "split", from = sid, id = it.id, n = value })
		f:Close()
	end)
	ok:SetPos(T.S(16), f:GetTall() - T.S(46))
	ok:SetTall(T.S(30))
	local cancel = T.Button(f, "CANCEL", T.S(110), function() f:Close() end)
	cancel:SetPos(T.S(134), f:GetTall() - T.S(46))
	cancel:SetTall(T.S(30))
end

function RPInv.QuickMove(sid, it)
	if sid == "p" and not containerSid() then
		RPInv.Toast("Open a container to quick-move items.", 0)
		return
	end
	RPInv.Act({ a = "quick", from = sid, id = it.id })
end

local function canEquip(def)
	local slot = RPInv.EquipSlotOf(def)
	if not slot then return nil end
	if def.jmod_armor ~= "" and not RPInv.HasJMod then return nil end
	return slot
end

function RPInv.ItemDoubleClick(sid, it)
	local def = RPInv.Items[it.item]
	if not def then return end
	if canEquip(def) then
		RPInv.Act({ a = "equip", from = sid, id = it.id })
	elseif def.use_type ~= "none" then
		RPInv.Act({ a = "use", from = sid, id = it.id })
	else
		RPInv.Inspect(def, it)
	end
end

function RPInv.EquipMenu(slotKey)
	local list = RPInv.Equipped[slotKey]
	if not list or #list == 0 then return end
	local m = T.Menu()
	for _, e in ipairs(list) do
		local def = RPInv.Items[e.item]
		local name = def and def.name or e.item
		local prefix = #list > 1 and (string.upper(name) .. ": ") or ""
		if e.kind == "weapon" and RPInv.SlotWeaponBase(slotKey) and RPInv.Settings.att_items then
			T.MenuOption(m, prefix .. "ATTACHMENTS...", function() RPInv.OpenAttachments(slotKey) end)
		end
		T.MenuOption(m, prefix .. "UNEQUIP", function() RPInv.Act({ a = "unequip", key = e.key }) end)
		T.MenuOption(m, prefix .. "DROP", function() RPInv.Act({ a = "unequip", key = e.key, drop = true }) end)
		if def then
			T.MenuOption(m, prefix .. "INSPECT", function() RPInv.Inspect(def, { amount = 1, dur = e.dur, meta = e.meta or {} }, e.kind == "weapon" and slotKey or nil) end)
		end
	end
	m:Open()
end

function RPInv.ItemMenu(sid, it)
	local def = RPInv.Items[it.item]
	if not def then return end
	local m = T.Menu()
	T.MenuOption(m, "INSPECT", function() RPInv.Inspect(def, it) end)
	local slot = canEquip(def)
	if slot then
		T.MenuOption(m, "EQUIP (" .. RPInv.EquipSlotByKey[slot].name .. ")", function() RPInv.Act({ a = "equip", from = sid, id = it.id }) end)
	end
	if RPInv.IsCarrierDef(def) and not isCarrierSid(sid) then
		T.MenuOption(m, "OPEN", function()
			RPInv.WantCarrier = it.meta.cid or "*"
			RPInv.Act({ a = "open", from = sid, id = it.id })
		end)
	end
	if def.use_type ~= "none" and not slot then
		T.MenuOption(m, "USE", function() RPInv.Act({ a = "use", from = sid, id = it.id }) end)
	end
	local other = containerSid()
	if sid == "p" and other then
		T.MenuOption(m, "STORE", function() RPInv.Act({ a = "quick", from = sid, id = it.id }) end)
	elseif sid ~= "p" then
		T.MenuOption(m, "TAKE", function() RPInv.Act({ a = "quick", from = sid, id = it.id }) end)
	end
	if def.rotatable and def.w ~= def.h then
		T.MenuOption(m, "ROTATE", function() RPInv.Act({ a = "rotate", from = sid, id = it.id }) end)
	end
	if it.amount > 1 then
		T.MenuOption(m, "SPLIT...", function() RPInv.SplitDialog(sid, it) end)
		T.MenuOption(m, "DROP ONE", function() RPInv.Act({ a = "drop", from = sid, id = it.id, n = 1 }) end)
	end
	T.MenuOption(m, it.amount > 1 and "DROP ALL" or "DROP", function() RPInv.Act({ a = "drop", from = sid, id = it.id }) end)
	m:Open()
end

local incoming
net.Receive("rpinv_items", function()
	local t = readJSON()
	if t.first ~= false or not incoming then incoming = {} end
	for _, d in ipairs(t.items or {}) do
		d.rotatable = d.rotatable ~= false and d.rotatable ~= 0
		incoming[d.id] = d
	end
	if t.last == false then return end
	RPInv.Items = incoming
	incoming = nil
	hook.Run("RPInv_ItemsUpdated")
end)

net.Receive("rpinv_settings", function()
	local t = readJSON()
	local changed = t.player_grid_w ~= RPInv.Settings.player_grid_w or t.player_grid_h ~= RPInv.Settings.player_grid_h
	RPInv.Settings = t
	if changed then RPInv.RebuildScreen() end
end)

net.Receive("rpinv_store", function()
	local t = readJSON()
	if type(t.sid) ~= "string" then return end
	local kid = string.match(t.sid, "^k:([%w_]+)$")
	local guarded = isContainerSid(t.sid) or (kid and not isWornCarrier(kid))
	if guarded and recentlyClosed[t.sid] and RealTime() - recentlyClosed[t.sid] < 0.6 then return end
	recentlyClosed[t.sid] = nil
	local st = { sid = t.sid, name = t.name or "", w = t.w or 1, h = t.h or 1, items = {} }
	for _, it in ipairs(t.items or {}) do
		it.meta = it.meta or {}
		it.rot = it.rot == 1 and 1 or 0
		st.items[it.id] = it
	end
	RPInv.Stores[t.sid] = st
	local d = RPInv.Drag
	if d and d.sid == t.sid then
		local cur = st.items[d.id]
		if not cur then
			RPInv.Drag = nil
		else
			d.amount = cur.amount
			d.n = math.min(d.n, cur.amount)
		end
	end
	if isContainerSid(t.sid) then
		for sid in pairs(RPInv.Stores) do
			if sid ~= t.sid and isContainerSid(sid) then RPInv.Stores[sid] = nil end
		end
		openScreen()
		if not IsValid(contWin) or contWin.SID ~= t.sid then buildContainerWindow(t.sid) end
	elseif kid and IsValid(scr) and not isWornCarrier(kid) and (not IsValid(kWin) or kWin.SID ~= t.sid) and (RPInv.WantCarrier == kid or RPInv.WantCarrier == "*") then
		RPInv.WantCarrier = nil
		buildContainerWindow(t.sid)
	end
	hook.Run("RPInv_StoreUpdated", t.sid)
end)

net.Receive("rpinv_close", function()
	local sid = "c:" .. net.ReadUInt(32)
	if IsValid(contWin) and contWin.SID == sid then closeContainerWindow(false) end
	RPInv.Stores[sid] = nil
end)

net.Receive("rpinv_quick", function()
	local t = readJSON()
	RPInv.QuickSlots = istable(t) and istable(t.slots) and t.slots or {}
end)

net.Receive("rpinv_equip", function()
	local t = readJSON()
	RPInv.Equipped = istable(t.slots) and t.slots or {}
	RPInv.PocketsCid = isstring(t.pockets) and t.pockets or nil
	RPInv.PocketsW, RPInv.PocketsH = tonumber(t.pocketsW) or 0, tonumber(t.pocketsH) or 0
	RPInv.HasJMod = t.jmod == true
	local d = RPInv.Drag
	if d and d.sid == "e" then
		local found = false
		for _, list in pairs(RPInv.Equipped) do
			for _, e in ipairs(list) do
				if e.key == d.id then found = true end
			end
		end
		if not found then RPInv.Drag = nil end
	end
	hook.Run("RPInv_EquipUpdated")
end)

net.Receive("rpinv_toast", function()
	local text, kind = net.ReadString(), net.ReadUInt(2)
	RPInv.Toast(text, kind)
end)

local function synced()
	return RPInv.Stores and RPInv.Stores.p ~= nil and next(RPInv.Items or {}) ~= nil
end

local function sendReady()
	net.Start("rpinv_ready")
	net.SendToServer()
	timer.Create("RPInv_ReadyRetry", 2.5, 15, function()
		if synced() then
			timer.Remove("RPInv_ReadyRetry")
			return
		end
		net.Start("rpinv_ready")
		net.SendToServer()
	end)
end

hook.Add("InitPostEntity", "RPInv_Ready", sendReady)

if IsValid(LocalPlayer()) then
	timer.Simple(0.5, sendReady)
end

concommand.Add("rpinv_open", function() RPInv.AfterGameUI(RPInv.ToggleScreen) end)

local keyCvar = CreateClientConVar("rpinv_key", "i", true, false, "Key that toggles the inventory (key name, e.g. i, tab, f4; none = off, bind rpinv_open instead)")
local keyWasDown = false

hook.Add("Think", "RPInv_OpenKey", function()
	local code = input.GetKeyCode(keyCvar:GetString())
	if not code or code <= 0 then return end
	local down = input.IsKeyDown(code)
	if down and not keyWasDown then
		local lp = LocalPlayer()
		local focus = vgui.GetKeyboardFocus()
		local typing = IsValid(focus) and focus:GetClassName() == "TextEntry"
		if IsValid(lp) and not lp:IsTyping() and not typing and not gui.IsGameUIVisible() and not gui.IsConsoleVisible() then
			RPInv.ToggleScreen()
		end
	end
	keyWasDown = down
end)

local entDefs, entDefsAt = {}, 0

local function entKey(cls, model)
	if cls == "prop_physics" then return "prop:" .. string.lower(model or "") end
	return cls
end

local function entDefFor(cls, model)
	if RealTime() - entDefsAt > 2 then
		entDefs, entDefsAt = {}, RealTime()
		for _, d in pairs(RPInv.Items) do
			local pre = string.sub(d.id, 1, 4)
			if (d.world_class or "") ~= "" and (pre == "ent_" or string.sub(d.id, 1, 5) == "prop_") then entDefs[entKey(d.world_class, d.model)] = d end
		end
	end
	return entDefs[entKey(cls, model)]
end

local JMOD_CATS = { ["JMod - EZ Explosives"] = true, ["JMod - EZ Misc."] = true, ["JMod - EZ Misc"] = true, ["JMod - EZ Special Ammo"] = true }

local function jmodStorable(e, c)
	if not e.JModEZstorable or string.find(c, "nuke", 1, true) then return false end
	local full = scripted_ents.Get(c)
	return full ~= nil and JMOD_CATS[full.Category] == true
end

local function lookedAt()
	local lp = LocalPlayer()
	if not IsValid(lp) or IsValid(scr) then return end
	local tr = lp:GetEyeTrace()
	local e = tr.Entity
	if not IsValid(e) or tr.HitPos:DistToSqr(lp:GetShootPos()) > 160 * 160 then return end
	local c = e:GetClass()
	if c == "rpinv_item" or c == "rpinv_container" then return e, c end
	if c == "rpinv_lootbox" then return e, "rpinv_container" end
	if isstring(e.ArmorName) and string.sub(c, 1, 21) == "ent_jack_gmod_ezarmor" and RPInv.Settings.jmod_pickup ~= "off" then
		return e, "jmod"
	end
	if c == "prop_ragdoll" and e:GetNW2String("RPInvCorpse", "") ~= "" then return e, "corpse" end
	if e:IsWeapon() and not IsValid(e:GetOwner()) and c ~= "weapon_physgun" and c ~= "gmod_tool" and c ~= "gmod_camera" and c ~= "rpinv_hands" then
		return e, "weapon"
	end
	if RPInv.Settings.entity_pickup ~= "off" and not e:IsPlayer() and not e:IsNPC() and not e:IsVehicle() and entDefFor(c, e:GetModel()) then
		return e, "entity"
	end
	if e.IsJackyEZresource and RPInv.Settings.jmod_pickup ~= "off" then return e, "resource" end
	if RPInv.Settings.jmod_pickup ~= "off" and jmodStorable(e, c) then return e, "jmoditem" end
	local lm = RPInv.Settings.loot_prop_models
	if lm and string.sub(c, 1, 5) == "prop_" and lm[string.lower(e:GetModel() or "")] then return e, "proploot" end
end

hook.Add("PreDrawHalos", "RPInv_Halo", function()
	local e = lookedAt()
	if e then halo.Add({ e }, T.Accent, 2, 2, 2, true, false) end
end)

hook.Add("HUDPaint", "RPInv_WorldHint", function()
	local e, c = lookedAt()
	if not e then return end
	local x, y = ScrW() / 2, ScrH() / 2 + T.S(44)
	local title, action
	if c == "rpinv_item" then
		local def = RPInv.Items[e:GetItemID()]
		if not def then return end
		title = string.upper(def.name) .. (e:GetAmount() > 1 and ("  x" .. e:GetAmount()) or "")
		action = "[E] PICK UP"
	elseif c == "weapon" then
		local name = e:GetPrintName()
		if not isstring(name) or name == "" then name = e:GetClass() end
		title = string.upper(language.GetPhrase(name))
		action = "[E] TAKE"
	elseif c == "corpse" then
		title = "BODY: " .. string.upper(e:GetNW2String("RPInvCorpse", ""))
		action = "[HOLD E] SEARCH"
	elseif c == "jmoditem" then
		title = string.upper(language.GetPhrase(e.PrintName or e:GetClass()))
		action = RPInv.Settings.jmod_pickup == "plain" and "[E] TAKE" or "[SHIFT+E] TAKE"
	elseif c == "proploot" then
		title = string.upper(string.gsub(string.GetFileFromFilename(e:GetModel() or ""), "%.mdl$", ""):gsub("_", " "))
		action = "[E] SEARCH"
	elseif c == "resource" then
		local n = isfunction(e.GetResource) and e:GetResource() or 0
		title = string.upper(language.GetPhrase(e.PrintName or c)) .. "  x" .. n
		action = RPInv.Settings.jmod_pickup == "plain" and "[E] TAKE" or "[SHIFT+E] TAKE"
	elseif c == "entity" then
		title = string.upper(entDefFor(e:GetClass(), e:GetModel()).name)
		action = RPInv.Settings.entity_pickup == "plain" and "[E] TAKE" or "[SHIFT+E] TAKE"
	elseif c == "jmod" then
		local info = JMod and JMod.ArmorTable and JMod.ArmorTable[e.ArmorName]
		title = string.upper(info and info.PrintName or e.ArmorName)
		action = (RPInv.Settings.jmod_pickup == "plain" and "[E] TAKE" or "[SHIFT+E] TAKE") .. "    [ALT+E] WEAR"
	else
		title = string.upper(e:GetCName())
		action = "[E] SEARCH"
	end
	surface.SetFont("RPInv.Text")
	local tw = surface.GetTextSize(title)
	local bw = math.max(tw, T.S(120)) + T.S(24)
	local bh = T.S(48)
	surface.SetDrawColor(10, 11, 10, 210)
	surface.DrawRect(x - bw / 2, y, bw, bh)
	surface.SetDrawColor(T.Accent)
	surface.DrawRect(x - bw / 2, y, T.S(3), bh)
	draw.SimpleText(title, "RPInv.Text", x, y + T.S(14), T.White, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(action, "RPInv.Small", x, y + T.S(34), T.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
