local T = RPInv.Theme
RPInv.LootData = RPInv.LootData or { presets = {}, points = 0, enabled = true, refill = {} }

local function request()
	net.Start("rpinv_lt_list")
	net.SendToServer()
end

net.Receive("rpinv_lt_list_r", function()
	RPInv.LootData = RPInv.ReadJSON() or RPInv.LootData
	hook.Run("RPInv_LootUpdated")
end)

local editor

local function itemName(id)
	local d = RPInv.Items[id]
	return d and d.name or id
end

function RPInv.BuildLootAdmin(p)
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
	local enabled = toggle(top, "LOOT SPAWNS", RPInv.LootData.enabled ~= false, 200)
	btn(top, "APPLY", 90, function()
		RPInv.SendJSON("rpinv_lt_settings", { enabled = enabled.Value })
	end)
	local pts = T.Label(top, "", "RPInv.Small")
	pts:Dock(LEFT)
	pts:SetWide(T.S(520))
	pts:DockMargin(T.S(12), 0, 0, 0)
	btn(top, "CLEAR POINTS", 140, function()
		net.Start("rpinv_lt_clearpoints")
		net.SendToServer()
	end, true)

	local hint = T.Label(p, "Toolgun > Sandbox Inventory+ > Loot Spawns: LMB spawns the selected preset at the crosshair, RMB adds a spawn point, R removes the nearest one. Without points, containers appear on random navmesh spots. A new container never appears near a player or in sight. Empty ones vanish after EMPTY REMOVE; unopened ones after STAYS UNOPENED. POINT TAGS limit a preset to points with those tool tags. LOOT AIMED PROP MODEL makes every map prop with that model lootable with the selected preset (refills every N min).", "RPInv.Small")
	hint:Dock(TOP)
	hint:SetWrap(true)
	hint:SetTall(T.S(62))
	hint:DockMargin(0, 0, 0, T.S(6))

	local left = vgui.Create("DPanel", p)
	left:Dock(LEFT)
	left:SetWide(T.S(400))
	left:DockMargin(0, 0, T.S(12), 0)
	left.Paint = nil
	local lb = vgui.Create("DPanel", left)
	lb:Dock(BOTTOM)
	lb:SetTall(T.S(30))
	lb:DockMargin(0, T.S(6), 0, 0)
	lb.Paint = nil
	local pb = vgui.Create("DPanel", left)
	pb:Dock(BOTTOM)
	pb:SetTall(T.S(30))
	pb:DockMargin(0, T.S(6), 0, 0)
	pb.Paint = nil
	local propList = T.List(left, { { name = "LOOTABLE MAP PROP MODEL" }, { name = "PRESET", w = T.S(60) }, { name = "MIN", w = T.S(50) } })
	propList:Dock(BOTTOM)
	propList:SetTall(T.S(130))
	propList:DockMargin(0, T.S(6), 0, 0)
	local propMin = T.TextEntry(pb, "min")
	propMin:SetNumeric(true)
	propMin:SetWide(T.S(56))
	propMin:Dock(LEFT)
	propMin:DockMargin(0, 0, T.S(6), 0)
	propMin:SetText("30")
	local list = T.List(left, { { name = "ID", w = T.S(40) }, { name = "NAME" }, { name = "ON MAP", w = T.S(70) }, { name = "LOOT", w = T.S(50) }, { name = "ON", w = T.S(40) } })
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
	f.model = field(r1, "CONTAINER MODEL (any .mdl)", 320)
	local aimCell = vgui.Create("DPanel", r1)
	aimCell:Dock(LEFT)
	aimCell:SetWide(T.S(150))
	aimCell.Paint = nil
	local aimBtn = T.Button(aimCell, "USE AIMED PROP", T.S(150), function()
		local e = LocalPlayer():GetEyeTrace().Entity
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
	f.max = field(r2, "MAX ON MAP", 100, true)
	f.interval = field(r2, "NEW EVERY (SEC)", 120, true)
	f.life = field(r2, "STAYS UNOPENED (MIN)", 150, true)
	local r2b = erow()
	f.empty_time = field(r2b, "EMPTY REMOVE (SEC)", 150, true)
	f.min_dist = field(r2b, "NO PLAYER WITHIN (UNITS)", 180, true)
	f.tags = field(r2b, "POINT TAGS (comma, empty = any)", 260)
	local r3 = erow(T.S(30))
	local onBtn = toggle(r3, "SPAWNS", true, 160)

	local lootHead = right:Add("DLabel")
	lootHead:Dock(TOP)
	lootHead:SetFont("RPInv.Small")
	lootHead:SetTextColor(T.Accent)
	lootHead:SetText("LOOT TABLE  (each row rolls on its own: CHANCE % to appear, amount MIN..MAX)")
	lootHead:SetTall(T.S(20))
	local lootList = T.List(right, { { name = "ITEM" }, { name = "ID", w = T.S(150) }, { name = "CHANCE %", w = T.S(80) }, { name = "MIN", w = T.S(50) }, { name = "MAX", w = T.S(50) } })
	lootList:Dock(TOP)
	lootList:SetTall(T.S(200))
	local r4 = erow()
	f.chance = field(r4, "CHANCE %", 90, true)
	f.min = field(r4, "MIN", 70, true)
	f.mx = field(r4, "MAX", 70, true)
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
		f.mx:SetText(tostring(e.max))
	end
	btn(r4b, "UPDATE ROW", 130, function()
		local i = selectedLoot()
		if not i then return end
		loot[i].chance = math.Clamp(tonumber(f.chance:GetText()) or loot[i].chance, 0.1, 100)
		loot[i].min = math.max(1, math.floor(tonumber(f.min:GetText()) or loot[i].min))
		loot[i].max = math.max(loot[i].min, math.floor(tonumber(f.mx:GetText()) or loot[i].max))
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
	search.OnChange = function() timer.Create("RPInv_LootPick", 0.2, 1, refreshPick) end
	pick.DoDoubleClick = function(_, _, line)
		if #loot >= 60 then return end
		local id = line:GetColumnText(2)
		local d = RPInv.Items[id]
		if not d then return end
		loot[#loot + 1] = { item = id, chance = 50, min = 1, max = 1 }
		refreshLoot()
		surface.PlaySound("ui/buttonclick.wav")
	end

	local r5 = erow(T.S(34))
	btn(r5, "SAVE PRESET", 160, function()
		RPInv.SendJSON("rpinv_lt_save", {
			id = current and current.id, name = f.name:GetText(), model = f.model:GetText(),
			w = tonumber(f.w:GetText()), h = tonumber(f.h:GetText()), max = tonumber(f.max:GetText()),
			interval = tonumber(f.interval:GetText()), life = tonumber(f.life:GetText()),
			empty_time = tonumber(f.empty_time:GetText()), min_dist = tonumber(f.min_dist:GetText()),
			tags = f.tags:GetText(), enabled = onBtn.Value, loot = loot,
		})
	end)

	local function fill(pr)
		current = pr
		pr = pr or { name = "Supply box", model = "models/items/ammocrate_smg1.mdl", w = 6, h = 4, max = 5, interval = 120, life = 15, empty_time = 60, min_dist = 1200, enabled = true, loot = {} }
		f.name:SetText(pr.name or "")
		f.model:SetText(pr.model or "")
		f.w:SetText(tostring(pr.w or 6))
		f.h:SetText(tostring(pr.h or 4))
		f.max:SetText(tostring(pr.max or 5))
		f.interval:SetText(tostring(pr.interval or 120))
		f.life:SetText(tostring(pr.life or 15))
		f.empty_time:SetText(tostring(pr.empty_time or 60))
		f.min_dist:SetText(tostring(pr.min_dist or 1200))
		f.tags:SetText(pr.tags or "")
		onBtn.Value = pr.enabled ~= false
		onBtn:SetText("SPAWNS: " .. (onBtn.Value and "ON" or "OFF"))
		loot = table.Copy(pr.loot or {})
		refreshLoot()
	end

	local function selectedPreset()
		local _, line = list:GetSelectedLine()
		local id = line and tonumber(line:GetColumnText(1))
		for _, pr in ipairs(RPInv.LootData.presets or {}) do
			if pr.id == id then return pr end
		end
	end
	list.OnRowSelected = function() fill(selectedPreset()) end
	btn(lb, "NEW", 70, function()
		list:ClearSelection()
		fill(nil)
	end)
	btn(lb, "SPAWN AT AIM", 140, function()
		local pr = selectedPreset()
		if not pr then return end
		net.Start("rpinv_lt_spawnnow")
		net.WriteUInt(pr.id, 16)
		net.SendToServer()
	end)
	btn(lb, "REFRESH", 100, request)
	btn(pb, "LOOT AIMED PROP MODEL", 200, function()
		local pr = selectedPreset()
		if not pr then
			RPInv.Toast("Select a loot preset first.", 2)
			return
		end
		net.Start("rpinv_lt_propset")
		net.WriteUInt(pr.id, 16)
		net.WriteUInt(math.Clamp(math.floor(tonumber(propMin:GetText()) or 30), 1, 1440), 16)
		net.SendToServer()
	end)
	btn(pb, "REMOVE", 90, function()
		local _, line = propList:GetSelectedLine()
		if not line then return end
		net.Start("rpinv_lt_propdel")
		net.WriteString(line:GetColumnText(1))
		net.SendToServer()
	end, true)
	btn(lb, "DELETE", 80, function()
		local pr = selectedPreset()
		if not pr then return end
		net.Start("rpinv_lt_delete")
		net.WriteUInt(pr.id, 16)
		net.SendToServer()
	end, true)

	local function refresh()
		if not IsValid(list) then return end
		local D = RPInv.LootData
		enabled.Value = D.enabled ~= false
		enabled:SetText("LOOT SPAWNS: " .. (enabled.Value and "ON" or "OFF"))
		local tagText = {}
		for k, n in SortedPairs(D.tags or {}) do tagText[#tagText + 1] = k .. " " .. n end
		pts:SetText("POINTS ON THIS MAP: " .. tostring(D.points or 0) .. (#tagText > 0 and ("  (" .. table.concat(tagText, ", ") .. ")") or ""))
		propList:Clear()
		for _, pr in ipairs(D.props or {}) do T.AddLine(propList, pr.model, pr.p, pr.m) end
		local sel = current and current.id
		list:Clear()
		for _, pr in ipairs(D.presets or {}) do
			local line = T.AddLine(list, pr.id, pr.name, (pr.alive or 0) .. " / " .. (pr.max or 0), #(pr.loot or {}), pr.enabled ~= false and "YES" or "NO")
			if pr.id == sel then
				list:SelectItem(line)
				current = pr
			end
		end
	end
	hook.Add("RPInv_LootUpdated", "RPInv_AdminLoot", refresh)
	refreshPick()
	fill(nil)
	refresh()
	p.OnShow = request
	editor = p
end

hook.Add("RPInv_ItemsUpdated", "RPInv_LootItemNames", function()
	if IsValid(editor) then hook.Run("RPInv_LootUpdated") end
end)
