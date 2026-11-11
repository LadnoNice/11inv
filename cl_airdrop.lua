local T = RPInv.Theme
local AD = RPInv.Airdrop or {}
RPInv.Airdrop = AD

AD.PLANE_MODEL = "models/wc_3dregenerator_ac130.mdl"
AD.PLANE_SCALE = 1.6
AD.PLANE_SOUND = "rpinv/airdrop_plane.wav"
AD.PARACHUTE_MODEL = "models/parachute/chute.mdl"
AD.CHUTE_BOTTOM = 66
AD.CHUTE_RADIUS = 75
AD.Data = AD.Data or { presets = {}, points = 0, auto = true, interval = 30, announce = true }

local planes = {}

AD.PLANE_FADE_TIME = 5

net.Receive("rpinv_ad_plane", function()
	local over, yaw, speed = net.ReadVector(), net.ReadFloat(), net.ReadFloat()
	local back, fwd, lead, scale = net.ReadFloat(), net.ReadFloat(), net.ReadFloat(), net.ReadFloat()
	local dir = Angle(0, yaw, 0):Forward()
	speed = math.max(speed, 50)
	local pl = { over = over, dir = dir, speed = speed, back = back, fwd = fwd, lead = lead, start = CurTime(), alpha = 0 }
	pl.t0 = math.max(0, lead - back / speed)
	pl.t1 = lead + fwd / speed
	pl.fadeT = math.min(AD.PLANE_FADE_TIME, (pl.t1 - pl.t0) / 2)
	pl.ent = ClientsideModel(AD.PLANE_MODEL, RENDERGROUP_OPAQUE)
	if IsValid(pl.ent) then
		pl.ent:SetAngles(Angle(0, yaw, 0))
		pl.ent:SetModelScale(scale > 0 and scale or AD.PLANE_SCALE)
		pl.ent:SetNoDraw(true)
		pl.ent:SetPos(over - dir * math.min(back, lead * speed))
		pl.ent:SetRenderBounds(Vector(-1200, -1200, -300), Vector(1200, 1200, 600))
		pl.ent:EmitSound(AD.PLANE_SOUND, 140, math.random(96, 103), 1)
	else
		sound.Play(AD.PLANE_SOUND, over, 140, 100, 1)
	end
	planes[#planes + 1] = pl
end)

local function smooth(f)
	f = math.Clamp(f, 0, 1)
	return f * f * (3 - 2 * f)
end

hook.Add("Think", "RPInv_AirdropPlanes", function()
	local now = CurTime()
	for i = #planes, 1, -1 do
		local pl = planes[i]
		local t = now - pl.start
		local e = pl.ent
		if not IsValid(e) or t > math.max(pl.t1, 20) + 1 then
			if IsValid(e) then
				e:StopSound(AD.PLANE_SOUND)
				e:Remove()
			end
			table.remove(planes, i)
		else
			local s = (t - pl.lead) * pl.speed
			e:SetPos(pl.over + pl.dir * math.Clamp(s, -pl.back, pl.fwd))
			local ft = math.max(pl.fadeT, 0.1)
			pl.alpha = (t < pl.t0 or t > pl.t1) and 0 or smooth((t - pl.t0) / ft) * smooth((pl.t1 - t) / ft)
		end
	end
end)

hook.Add("PostDrawTranslucentRenderables", "RPInv_AirdropPlanesDraw", function(_, sky)
	if sky or #planes == 0 then return end
	for _, pl in ipairs(planes) do
		if pl.alpha > 0.01 and IsValid(pl.ent) then
			render.SetBlend(pl.alpha)
			pl.ent:DrawModel()
		end
	end
	render.SetBlend(1)
end)

local function chuteFor(ent)
	if IsValid(ent.RPInvChute) then return ent.RPInvChute end
	if ent.RPInvChuteFailed then return nil end
	local c = ClientsideModel(AD.PARACHUTE_MODEL, RENDERGROUP_OPAQUE)
	if not IsValid(c) then ent.RPInvChuteFailed = true end
	if not IsValid(c) then return nil end
	c:SetNoDraw(true)
	local mn, mx = ent:OBBMins(), ent:OBBMaxs()
	local r = math.max(mx.x - mn.x, mx.y - mn.y) / 2
	local scale = math.Clamp(r / 30, 0.8, 3)
	c:SetModelScale(scale)
	c.Scale = scale
	c.Born = CurTime()
	ent.RPInvChute = c
	ent:CallOnRemove("RPInvChute", function(e) if IsValid(e.RPInvChute) then e.RPInvChute:Remove() end end)
	return c
end

local function playSeq(c, name, t, loop)
	local seq = c:LookupSequence(name)
	if not seq or seq < 0 then return false end
	local d = math.max(c:SequenceDuration(seq), 0.05)
	if c:GetSequence() ~= seq then c:SetSequence(seq) end
	local cyc = loop and ((t / d) % 1) or math.Clamp(t / d, 0, 1)
	c:SetCycle(cyc)
	c:InvalidateBoneCache()
	return t < d or loop
end

function AD.DrawParachute(ent)
	local c = chuteFor(ent)
	if not c then return end
	local landedAt = ent.RPInvLandedAt
	if landedAt and not ent.RPInvChuteOn then return end
	local s = c.Scale
	local base = ent:GetPos() + Vector(0, 0, ent:OBBMaxs().z - AD.CHUTE_BOTTOM * s + 6)
	if landedAt then
		local t = CurTime() - landedAt
		if not playSeq(c, "collapse", t, false) then
			ent.RPInvChuteOn = false
			return
		end
		c:SetPos(base - Vector(0, 0, math.min(t, 2) * 30 * s))
	else
		local t = CurTime() - c.Born
		if not playSeq(c, "open", t, false) then playSeq(c, "idle", t, true) end
		c:SetPos(base)
	end
	local a = ent:GetAngles()
	c:SetAngles(Angle(a.p * 0.5, a.y, a.r * 0.5))
	c:DrawModel()
end

local function request()
	net.Start("rpinv_ad_list")
	net.SendToServer()
end

local editor

net.Receive("rpinv_ad_list_r", function()
	AD.Data = RPInv.ReadJSON() or AD.Data
	hook.Run("RPInv_AirdropsUpdated")
end)

local function itemName(id)
	local d = RPInv.Items[id]
	return d and d.name or id
end

function RPInv.BuildAirdropAdmin(p)
	local function row(h)
		local r = vgui.Create("DPanel", p)
		r:Dock(TOP)
		r:SetTall(h or T.S(30))
		r:DockMargin(0, 0, 0, T.S(6))
		r.Paint = nil
		return r
	end
	local function btn(parent, text, w, fn, confirm)
		local b = (confirm and T.ConfirmButton or T.Button)(parent, text, T.S(w), fn)
		b:Dock(LEFT)
		b:DockMargin(0, 0, T.S(6), 0)
		return b
	end
	local function toggle(parent, label, value, w)
		local b
		b = T.Button(parent, "", T.S(w), function()
			b.Value = not b.Value
			b:SetText(label .. ": " .. (b.Value and "ON" or "OFF"))
		end)
		b.Value = value
		b:SetText(label .. ": " .. (value and "ON" or "OFF"))
		b:Dock(LEFT)
		b:DockMargin(0, 0, T.S(6), 0)
		return b
	end

	local top = row()
	local auto = toggle(top, "AUTO AIRDROPS", AD.Data.auto, 210)
	local ann = toggle(top, "ANNOUNCE", AD.Data.announce, 160)
	local ival = T.TextEntry(top, "minutes")
	ival:SetNumeric(true)
	ival:SetWide(T.S(70))
	ival:Dock(LEFT)
	ival:DockMargin(0, 0, T.S(6), 0)
	ival:SetText(tostring(AD.Data.interval or 30))
	local il = T.Label(top, "MIN BETWEEN DROPS", "RPInv.Small")
	il:Dock(LEFT)
	il:SetWide(T.S(130))
	btn(top, "APPLY", 90, function()
		RPInv.SendJSON("rpinv_ad_settings", { auto = auto.Value, announce = ann.Value, interval = tonumber(ival:GetText()) })
	end)
	local pts = T.Label(top, "", "RPInv.Small")
	pts:Dock(LEFT)
	pts:SetWide(T.S(220))
	pts:DockMargin(T.S(12), 0, 0, 0)
	btn(top, "CLEAR POINTS", 140, function()
		net.Start("rpinv_ad_clearpoints")
		net.SendToServer()
	end, true)

	local hint = T.Label(p, "Toolgun > Sandbox Inventory+ > RP Airdrop: LMB calls the selected preset at the crosshair, RMB adds an auto-drop point, R removes the nearest point. Auto drops use the presets marked AUTO.", "RPInv.Small")
	hint:Dock(TOP)
	hint:SetWrap(true)
	hint:SetTall(T.S(32))
	hint:DockMargin(0, 0, 0, T.S(6))

	local left = vgui.Create("DPanel", p)
	left:Dock(LEFT)
	left:SetWide(T.S(380))
	left:DockMargin(0, 0, T.S(12), 0)
	left.Paint = nil
	local lb = vgui.Create("DPanel", left)
	lb:Dock(BOTTOM)
	lb:SetTall(T.S(30))
	lb:DockMargin(0, T.S(6), 0, 0)
	lb.Paint = nil
	local lb2 = vgui.Create("DPanel", left)
	lb2:Dock(BOTTOM)
	lb2:SetTall(T.S(30))
	lb2:DockMargin(0, T.S(6), 0, 0)
	lb2.Paint = nil
	local list = T.List(left, { { name = "ID", w = T.S(40) }, { name = "NAME" }, { name = "LOOT", w = T.S(50) }, { name = "AUTO", w = T.S(50) } })
	list:Dock(FILL)

	local right = vgui.Create("DScrollPanel", p)
	right:Dock(FILL)
	T.StyleScroll(right)

	local current
	local loot = {}
	local f = {}
	local function field(parent, label, w, numeric)
		local cell = vgui.Create("DPanel", parent)
		cell:Dock(LEFT)
		cell:SetWide(T.S(w))
		cell:DockMargin(0, 0, T.S(8), 0)
		cell.Paint = nil
		return T.Field(cell, label, "", numeric)
	end
	local function erow(h)
		local r = right:Add("DPanel")
		r:Dock(TOP)
		r:SetTall(h or 48)
		r:DockMargin(0, 0, 0, T.S(4))
		r.Paint = nil
		return r
	end
	local r1 = erow()
	f.name = field(r1, "NAME", 200)
	f.model = field(r1, "CRATE MODEL (any .mdl)", 330)
	local aimCell = vgui.Create("DPanel", r1)
	aimCell:Dock(LEFT)
	aimCell:SetWide(T.S(150))
	aimCell.Paint = nil
	local aimBtn = T.Button(aimCell, "USE AIMED PROP", T.S(150), function()
		local tr = LocalPlayer():GetEyeTrace()
		local e = tr.Entity
		if IsValid(e) and not e:IsPlayer() and isstring(e:GetModel()) and e:GetModel():lower():match("%.mdl$") then
			f.model:SetText(e:GetModel())
			surface.PlaySound("ui/buttonclick.wav")
		else
			surface.PlaySound("buttons/button10.wav")
		end
	end)
	aimBtn:Dock(BOTTOM)
	aimBtn:SetTall(T.S(26))
	local r2 = erow()
	f.w = field(r2, "GRID W", 70, true)
	f.h = field(r2, "GRID H", 70, true)
	f.life = field(r2, "STAYS (MIN)", 90, true)
	f.smoke_time = field(r2, "SMOKE (MIN)", 90, true)
	f.r = field(r2, "SMOKE R", 70, true)
	f.g = field(r2, "SMOKE G", 70, true)
	f.b = field(r2, "SMOKE B", 70, true)
	f.weight = field(r2, "AUTO WEIGHT", 100, true)
	local r3 = erow(T.S(30))
	local autoBtn = toggle(r3, "USED BY AUTO DROPS", false, 230)

	local lootHead = right:Add("DLabel")
	lootHead:Dock(TOP)
	lootHead:SetFont("RPInv.Small")
	lootHead:SetTextColor(T.Accent)
	lootHead:SetText("LOOT TABLE  (each row rolls on its own: CHANCE % to drop, amount MIN..MAX)")
	lootHead:SetTall(T.S(20))
	local lootList = T.List(right, { { name = "ITEM" }, { name = "ID", w = T.S(150) }, { name = "CHANCE %", w = T.S(80) }, { name = "MIN", w = T.S(50) }, { name = "MAX", w = T.S(50) } })
	lootList:Dock(TOP)
	lootList:SetTall(T.S(200))
	local r4 = erow()
	f.chance = field(r4, "CHANCE %", 90, true)
	f.min = field(r4, "MIN", 70, true)
	f.max = field(r4, "MAX", 70, true)
	local r4b = erow(T.S(30))

	local function refreshLoot()
		lootList:Clear()
		for i, e in ipairs(loot) do
			local line = T.AddLine(lootList, itemName(e.item), e.item, tostring(e.chance), tostring(e.min), tostring(e.max))
			line.LootIndex = i
		end
	end
	local function selectedLoot()
		local _, line = lootList:GetSelectedLine()
		return line and line.LootIndex
	end
	lootList.OnRowSelected = function(_, _, line)
		local e = loot[line.LootIndex]
		if not e then return end
		f.chance:SetText(tostring(e.chance))
		f.min:SetText(tostring(e.min))
		f.max:SetText(tostring(e.max))
	end
	btn(r4b, "UPDATE ROW", 130, function()
		local i = selectedLoot()
		if not i then return end
		loot[i].chance = math.Clamp(tonumber(f.chance:GetText()) or loot[i].chance, 0.1, 100)
		loot[i].min = math.max(1, math.floor(tonumber(f.min:GetText()) or loot[i].min))
		loot[i].max = math.max(loot[i].min, math.floor(tonumber(f.max:GetText()) or loot[i].max))
		refreshLoot()
	end)
	btn(r4b, "REMOVE ROW", 130, function()
		local i = selectedLoot()
		if not i then return end
		table.remove(loot, i)
		refreshLoot()
	end)

	local addHead = right:Add("DLabel")
	addHead:Dock(TOP)
	addHead:SetFont("RPInv.Small")
	addHead:SetTextColor(T.Accent)
	addHead:SetText("ADD ITEMS  (search, then double-click an item)")
	addHead:SetTall(T.S(20))
	local search = right:Add("DTextEntry")
	search:Dock(TOP)
	search:SetTall(T.S(26))
	search:DockMargin(0, 0, 0, T.S(4))
	search:SetFont("RPInv.Text")
	search.Paint = function(s, w, h)
		surface.SetDrawColor(T.InputBg)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(s:HasFocus() and T.Accent or T.Dim)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		if s:GetText() == "" and not s:HasFocus() then
			draw.SimpleText("Search items...", "RPInv.Small", 6, h / 2, T.Dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		s:DrawTextEntryText(T.Green, T.Sel, T.Accent)
	end
	local pick = T.List(right, { { name = "ITEM" }, { name = "ID", w = T.S(160) }, { name = "CATEGORY", w = T.S(110) } })
	pick:Dock(TOP)
	pick:SetTall(T.S(200))
	local function refreshPick()
		pick:Clear()
		local q = string.lower(string.Trim(search:GetText()))
		local n = 0
		for id, d in SortedPairsByMemberValue(RPInv.Items, "name") do
			local hay = string.lower(d.name .. " " .. id .. " " .. (d.category or ""))
			if q == "" or string.find(hay, q, 1, true) then
				T.AddLine(pick, d.name, id, d.category or "")
				n = n + 1
				if n >= 300 then break end
			end
		end
	end
	search.OnChange = function() timer.Create("RPInv_ADPick", 0.2, 1, refreshPick) end
	pick.DoDoubleClick = function(_, _, line)
		if #loot >= 60 then return end
		local id = line:GetColumnText(2)
		local d = RPInv.Items[id]
		if not d then return end
		loot[#loot + 1] = { item = id, chance = 50, min = 1, max = math.min(d.max_stack, 1) }
		refreshLoot()
		surface.PlaySound("ui/buttonclick.wav")
	end

	local r5 = erow(T.S(34))
	btn(r5, "SAVE PRESET", 160, function()
		RPInv.SendJSON("rpinv_ad_save", {
			id = current and current.id, name = f.name:GetText(), model = f.model:GetText(),
			w = tonumber(f.w:GetText()), h = tonumber(f.h:GetText()), life = tonumber(f.life:GetText()),
			smoke_time = tonumber(f.smoke_time:GetText()),
			smoke = { tonumber(f.r:GetText()), tonumber(f.g:GetText()), tonumber(f.b:GetText()) },
			weight = tonumber(f.weight:GetText()), auto = autoBtn.Value, loot = loot,
		})
	end)
	btn(r5, "MAKE FLARE GUN ITEM", 220, function()
		if not current or not current.id then
			RPInv.Toast("Save the preset first.", 2)
			return
		end
		net.Start("rpinv_ad_flareitem")
		net.WriteUInt(current.id, 16)
		net.SendToServer()
	end)
	local fh = T.Label(r5, "Flare gun items call the preset IDs in their use argument (e.g. 1,3). Use type: flare.", "RPInv.Small")
	fh:Dock(FILL)
	fh:DockMargin(T.S(6), 0, 0, 0)

	local function fill(pr)
		current = pr
		pr = pr or { name = "New airdrop", model = "models/items/ammocrate_smg1.mdl", w = 8, h = 6, life = 10, smoke_time = 3, smoke = { 230, 30, 20 }, weight = 1, auto = true, loot = {} }
		f.name:SetText(pr.name or "")
		f.model:SetText(pr.model or "")
		f.w:SetText(tostring(pr.w or 8))
		f.h:SetText(tostring(pr.h or 6))
		f.life:SetText(tostring(pr.life or 10))
		f.smoke_time:SetText(tostring(pr.smoke_time or 3))
		local c = pr.smoke or { 230, 30, 20 }
		f.r:SetText(tostring(c[1]))
		f.g:SetText(tostring(c[2]))
		f.b:SetText(tostring(c[3]))
		f.weight:SetText(tostring(pr.weight or 1))
		autoBtn.Value = pr.auto == true
		autoBtn:SetText("USED BY AUTO DROPS: " .. (autoBtn.Value and "ON" or "OFF"))
		loot = table.Copy(pr.loot or {})
		refreshLoot()
	end

	local function selectedPreset()
		local _, line = list:GetSelectedLine()
		local id = line and tonumber(line:GetColumnText(1))
		for _, pr in ipairs(AD.Data.presets or {}) do
			if pr.id == id then return pr end
		end
	end
	list.OnRowSelected = function() fill(selectedPreset()) end
	btn(lb, "NEW", 70, function()
		list:ClearSelection()
		fill(nil)
	end)
	btn(lb2, "CALL AT AIM", 150, function()
		local pr = selectedPreset()
		if not pr then return end
		net.Start("rpinv_ad_call")
		net.WriteUInt(pr.id, 16)
		net.WriteBool(false)
		net.SendToServer()
	end)
	btn(lb2, "CALL RANDOM", 150, function()
		local pr = selectedPreset()
		if not pr then return end
		net.Start("rpinv_ad_call")
		net.WriteUInt(pr.id, 16)
		net.WriteBool(true)
		net.SendToServer()
	end)
	btn(lb, "DELETE", 100, function()
		local pr = selectedPreset()
		if not pr then return end
		net.Start("rpinv_ad_delete")
		net.WriteUInt(pr.id, 16)
		net.SendToServer()
	end, true)

	local function refresh()
		if not IsValid(list) then return end
		auto.Value = AD.Data.auto == true
		auto:SetText("AUTO AIRDROPS: " .. (auto.Value and "ON" or "OFF"))
		ann.Value = AD.Data.announce == true
		ann:SetText("ANNOUNCE: " .. (ann.Value and "ON" or "OFF"))
		ival:SetText(tostring(AD.Data.interval or 30))
		pts:SetText("AUTO-DROP POINTS ON THIS MAP: " .. tostring(AD.Data.points or 0))
		local sel = current and current.id
		list:Clear()
		for _, pr in ipairs(AD.Data.presets or {}) do
			local line = T.AddLine(list, pr.id, pr.name, #(pr.loot or {}), pr.auto and "YES" or "NO")
			if pr.id == sel then
				list:SelectItem(line)
				current = pr
			end
		end
	end
	hook.Add("RPInv_AirdropsUpdated", "RPInv_AdminAirdrops", refresh)
	refreshPick()
	fill(nil)
	refresh()
	p.OnShow = request
	editor = p
end

hook.Add("RPInv_ItemsUpdated", "RPInv_AirdropItemNames", function()
	if IsValid(editor) then hook.Run("RPInv_AirdropsUpdated") end
end)
