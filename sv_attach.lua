local DB = RPInv.DB
local A = RPInv.Att
local E = RPInv.Equip
local Q = RPInv.Quick

util.AddNetworkString("rpinv_attinfo")
util.AddNetworkString("rpinv_attrefresh")

local function clientRefresh(ply, wep)
	if not IsValid(ply) or ply:IsBot() or not IsValid(wep) then return end
	timer.Simple(0.1, function()
		if not IsValid(ply) or not IsValid(wep) then return end
		net.Start("rpinv_attrefresh")
		net.WriteEntity(wep)
		net.Send(ply)
	end)
end

local FALLBACK_MODEL = "models/items/boxsrounds.mdl"

local itemsDirty = false
local function itemsChanged()
	if itemsDirty then return end
	itemsDirty = true
	timer.Simple(0, function()
		itemsDirty = false
		RPInv.SendItems()
	end)
end

function A.EnsureDef(base, att, quiet)
	if A.IsFree(base, att) or att == "base" then return nil end
	local id = A.ItemId(base, att)
	local def = RPInv.Items[id]
	if def then return def end
	local arg = base .. ":" .. att
	if #arg > 64 then return nil end
	local t = A.AttTable(base, att)
	local model = t.DroppedModel or t.Model
	if not isstring(model) or not util.IsValidModel(model) then model = FALLBACK_MODEL end
	def = {
		id = id, name = string.sub(A.AttName(base, att), 1, 40), model = model,
		descr = ("Weapon attachment (" .. A.BaseNames[base] .. "). Drag it onto an equipped weapon or use it with the weapon in your hands."):sub(1, 200),
		max_stack = 1, use_type = "attachment", use_arg = arg, w = 1, h = 1, rotatable = true,
		equip_slot = "", grid_w = 0, grid_h = 0, jmod_armor = "", world_class = "",
		cam_ang = "0 0 0", cam_fov = 1, category = "Attachments",
	}
	RPInv.Items[id] = def
	DB.SaveItem(def)
	if not quiet then DB.Log(nil, "attachment_item_auto", arg) end
	itemsChanged()
	return def
end

util.AddNetworkString("rpinv_a_attimport")

function A.ImportAll()
	local n = 0
	local function each(base, tbl)
		if not istable(tbl) then return end
		for name, t in pairs(tbl) do
			if isstring(name) and istable(t) and not RPInv.Items[A.ItemId(base, name)] and A.EnsureDef(base, name, true) then n = n + 1 end
		end
	end
	DB.Transaction(function()
		if ArcCW then each("arccw", ArcCW.AttachmentTable) end
		if TacRP then each("tacrp", TacRP.Attachments) end
		if ARC9 then each("arc9", ARC9.Attachments) end
		if TFA and TFA.Attachments then each("tfa", TFA.Attachments.Atts) end
	end)
	return n
end

net.Receive("rpinv_a_attimport", function(_, ply)
	if not RPInv.IsAdmin(ply) then return end
	if (ply.RPInvAttImportNext or 0) > CurTime() then return end
	ply.RPInvAttImportNext = CurTime() + 5
	local n = A.ImportAll()
	DB.Log(ply, "attachment_import", n)
	RPInv.Notify(ply, "Imported " .. n .. " attachment item(s).", 1)
end)

local function runOp(ply, fn)
	local arccwInv = ply.ArcCW_AttInv
	ply.ArcCW_AttInv = setmetatable(table.Copy(arccwInv or {}), { __index = function() return 999 end })
	ply.RPInvAttOp = true
	local ok, err = pcall(fn)
	ply.RPInvAttOp = nil
	ply.ArcCW_AttInv = arccwInv
	if not ok then ErrorNoHalt("[RPInv] attachment error: " .. tostring(err) .. "\n") end
	if ArcCW and isfunction(ArcCW.PlayerSendAttInv) then pcall(ArcCW.PlayerSendAttInv, ArcCW, ply) end
	if TacRP and isfunction(TacRP.PlayerSendAttInv) then pcall(TacRP.PlayerSendAttInv, TacRP, ply) end
	if ARC9 and isfunction(ARC9.PlayerSendAttInv) then pcall(ARC9.PlayerSendAttInv, ARC9, ply) end
	return ok
end

local function invoke(wep, name, ...)
	local fn = wep[name]
	if not isfunction(fn) then return nil end
	local ok, r = pcall(fn, wep, ...)
	if not ok then ErrorNoHalt("[RPInv] " .. name .. ": " .. tostring(r) .. "\n") end
	return r
end

local function toArc9(nodes, slots, limit)
	local out = {}
	local n = 0
	for k in pairs(istable(nodes) and nodes or {}) do n = math.max(n, tonumber(k) or 0) end
	if istable(slots) then n = math.max(n, #slots) end
	if limit then n = math.min(n, limit) end
	for i = 1, n do
		local node = istable(nodes) and nodes[tostring(i)]
		if istable(node) and isstring(node.i) and A.AttTable("arc9", node.i) then
			local t = A.AttTable("arc9", node.i)
			out[i] = { Installed = node.i, ToggleNum = tonumber(node.t) or 1, SubAttachments = toArc9(node.s, t.Attachments) }
		else
			out[i] = {}
		end
	end
	return out
end

local function arc9Apply(wep, nodes)
	local tbl = toArc9(nodes, wep.Attachments, #wep.Attachments)
	invoke(wep, "BuildSubAttachments", tbl)
	invoke(wep, "DoInvalidateCache")
	invoke(wep, "PruneAttachments")
	invoke(wep, "FillIntegralSlots")
	invoke(wep, "SendWeapon")
	invoke(wep, "PostModify")
end

local function arc9Set(wep, k, att)
	local s = A.SlotTable(wep, k)
	if not s then return end
	s.Installed = att
	s.ToggleNum = 1
	s.SubAttachments = {}
	local cap = A.Capture(wep)
	arc9Apply(wep, cap and cap.t or {})
end

hook.Add("PlayerSwitchWeapon", "RPInv_AttachmentDeploy", function(_, _, new)
	if IsValid(new) and new.RPInvAttLock then new.RPInvDeployedAt = CurTime() end
end)

local slotTable = A.SlotTable

local function finish(ply, wep, base)
	if base == "arccw" then
		if isfunction(wep.AdjustAtts) then wep:AdjustAtts() end
		if isfunction(wep.NetworkWeapon) then wep:NetworkWeapon() end
		if isfunction(wep.SetupModel) then
			wep:SetupModel(false)
			wep:SetupModel(true)
		end
		if isfunction(wep.RefreshBGs) then wep:RefreshBGs() end
	elseif base == "tacrp" then
		if isfunction(wep.InvalidateCache) then wep:InvalidateCache() end
		if isfunction(wep.SetBaseSettings) then wep:SetBaseSettings() end
		if isfunction(wep.NetworkWeapon) then wep:NetworkWeapon() end
	end
end

local function rawAttach(base, wep, k, att)
	if base == "arccw" then
		wep:Attach(k, att, true, false)
	elseif base == "tacrp" then
		wep:Attach(k, att, true, true)
	elseif base == "tfa" then
		local t = slotTable(wep, k)
		local idx = istable(t) and istable(t.atts) and table.KeyFromValue(t.atts, att)
		if idx and isfunction(wep.SetTFAAttachment) then wep:SetTFAAttachment(k, idx, true, true) end
	elseif base == "arc9" then
		arc9Set(wep, k, att)
	end
end

local function rawDetach(base, wep, k)
	if base == "arccw" then
		wep:Detach(k, true, false, true)
	elseif base == "tacrp" then
		wep:Detach(k, true, true)
	elseif base == "tfa" and isfunction(wep.SetTFAAttachment) then
		wep:SetTFAAttachment(k, 0, true, true)
	elseif base == "arc9" then
		arc9Set(wep, k, nil)
	end
end

local function wantMap(data)
	local want = {}
	for k, v in pairs(istable(data.s) and data.s or {}) do
		if isstring(v) then want[tonumber(k) or k] = v end
	end
	return want
end

function A.Restore(ply, wep, data)
	if not IsValid(wep) or not istable(data) or data.b ~= A.BaseOf(wep) or not istable(wep.Attachments) then return end
	local base = data.b
	wep.RPInvAttLock = true
	wep.RPInvAttLockAt = CurTime()
	if base == "arccw" then
		wep:SetNWBool("ArcCW_DisableAutosave", true)
		ply.ArcCW_DisableAutosave = true
		timer.Create("RPInv_ArcCWAuto" .. ply:EntIndex(), 2, 1, function()
			if IsValid(ply) then ply.ArcCW_DisableAutosave = nil end
		end)
	end
	runOp(ply, function()
		if base == "arc9" then
			arc9Apply(wep, data.t)
		elseif base == "tfa" then
			local want = wantMap(data)
			for cat, t in pairs(wep.Attachments) do
				if istable(t) and istable(t.atts) then
					local cur = (tonumber(t.sel) or 0) > 0 and t.atts[t.sel] or nil
					if cur ~= want[cat] then
						if want[cat] then rawAttach(base, wep, cat, want[cat]) else rawDetach(base, wep, cat) end
					end
				end
			end
		else
			local want = wantMap(data)
			for _, k in ipairs(A.NumSlots(wep)) do
				local s = wep.Attachments[k]
				if isstring(s.Installed) and not s.Internal and s.Installed ~= want[k] then rawDetach(base, wep, k) end
			end
			for _ = 1, 3 do
				for _, k in ipairs(A.NumSlots(wep)) do
					local s = wep.Attachments[k]
					if want[k] and s and s.Installed ~= want[k] then rawAttach(base, wep, k, want[k]) end
				end
			end
		end
		finish(ply, wep, base)
	end)
	clientRefresh(ply, wep)
end

local function counts(list)
	local c = {}
	for _, e in ipairs(list) do
		local a = isstring(e) and e or e.a
		c[a] = (c[a] or 0) + 1
	end
	return c
end

local function slotWeapon(ply, wslot)
	local inst = E.State(ply).weapons[tostring(wslot or "")]
	local def = inst and RPInv.Items[inst.item]
	if not def or def.use_type ~= "weapon" then return nil, "No weapon in that slot." end
	local wep = ply:GetWeapon(def.use_arg)
	if not IsValid(wep) then return nil, "This weapon is not ready." end
	local base = A.BaseOf(wep)
	if not base or not A.Editable[base] then return nil, "This weapon does not support attachments here." end
	return wep, inst, base, def
end

local TFA_WORDS = {
	{ "si_", "SIGHT" }, { "sight", "SIGHT" }, { "scope", "SIGHT" }, { "optic", "SIGHT" }, { "reflex", "SIGHT" },
	{ "am_", "AMMO" }, { "ammo", "AMMO" }, { "round", "AMMO" },
	{ "supp", "MUZZLE" }, { "muzz", "MUZZLE" }, { "silenc", "MUZZLE" }, { "brake", "MUZZLE" },
	{ "fg_", "FOREGRIP" }, { "grip", "FOREGRIP" }, { "bipod", "FOREGRIP" },
	{ "laser", "TACTICAL" }, { "flash", "TACTICAL" }, { "light", "TACTICAL" }, { "ub_", "UNDERBARREL" },
	{ "mag", "MAGAZINE" }, { "drum", "MAGAZINE" },
	{ "stock", "STOCK" }, { "st_", "STOCK" },
	{ "skin", "SKIN" }, { "sk_", "SKIN" }, { "camo", "SKIN" },
	{ "br_", "BARREL" }, { "barrel", "BARREL" },
}

local function tfaCatName(s, k)
	for _, att in ipairs(istable(s.atts) and s.atts or {}) do
		local t = A.AttTable("tfa", att)
		local text = string.lower(att .. " " .. tostring(t and t.Name or ""))
		for _, wd in ipairs(TFA_WORDS) do
			if string.find(text, wd[1], 1, true) then return wd[2] end
		end
	end
	return "SLOT " .. tostring(k)
end

local function slotName(base, wep, k)
	local s = slotTable(wep, k)
	if not istable(s) then return tostring(k) end
	local n = s.PrintName or s.header or s.Header or s.Name
	if base == "arccw" and isstring(n) and ArcCW and isfunction(ArcCW.TryTranslation) then
		local ok, r = pcall(ArcCW.TryTranslation, n)
		if ok and isstring(r) then n = r end
	elseif base == "arc9" and isstring(n) and ARC9 and isfunction(ARC9.GetPhrase) then
		local ok, r = pcall(ARC9.GetPhrase, ARC9, n)
		if ok and isstring(r) and r ~= "" then n = r end
	elseif base == "tfa" and not isstring(n) then
		n = tfaCatName(s, k)
	end
	return isstring(n) and n or tostring(k)
end

local function slotKeys(base, wep)
	if base == "tfa" then
		local out = {}
		for cat, t in pairs(wep.Attachments) do
			if istable(t) and istable(t.atts) and #t.atts > 0 then out[#out + 1] = cat end
		end
		table.sort(out, function(a, b)
			local oa, ob = wep.Attachments[a].order, wep.Attachments[b].order
			if oa or ob then return (oa or 999) < (ob or 999) end
			return tostring(a) < tostring(b)
		end)
		return out
	end
	if base == "arc9" then
		local out = {}
		local list = invoke(wep, "GetSubSlotList") or {}
		for i, s in ipairs(list) do
			if istable(s) and not s.Hidden and s.Category then out[#out + 1] = s.Address or i end
		end
		return out
	end
	local out = {}
	for _, k in ipairs(A.NumSlots(wep)) do
		local s = wep.Attachments[k]
		if not s.Internal and not s.Hidden and (s.Slot or s.Category) then out[#out + 1] = k end
	end
	return out
end

local function installedAt(base, wep, k)
	local s = slotTable(wep, k)
	if not istable(s) then return nil end
	if base == "tfa" then
		local sel = tonumber(s.sel) or 0
		return sel > 0 and istable(s.atts) and s.atts[sel] or nil
	end
	return isstring(s.Installed) and s.Installed or nil
end

local function accepts(ply, base, wep, k, att)
	local s = slotTable(wep, k)
	if not istable(s) then return false end
	if base == "tfa" then return istable(s.atts) and table.HasValue(s.atts, att) end
	local ok = false
	runOp(ply, function()
		if base == "arccw" then
			local t = ArcCW.AttachmentTable[att]
			ok = t ~= nil and ArcCW:SlotAcceptsAtt(s.Slot, wep, att) and (not isfunction(wep.CheckFlags) or wep:CheckFlags(t.ExcludeFlags, t.RequireFlags))
		elseif base == "tacrp" then
			ok = isfunction(wep.CanAttach) and wep:CanAttach(k, att) == true
		elseif base == "arc9" then
			ok = isfunction(wep.CanAttach) and wep:CanAttach(k, att, s, true) == true
		end
	end)
	return ok and true or false
end

local function fixed(base, wep, k)
	local s = slotTable(wep, k)
	if not istable(s) then return true end
	if base == "tacrp" then return s.Integral == true end
	if base == "arccw" then return s.Installed ~= nil and s.Installed == s.EmptyFallback end
	return false
end

local function noRemove(base, wep, k)
	local s = slotTable(wep, k)
	if not istable(s) then return true end
	if base == "arc9" then return s.Integral ~= nil and s.Integral ~= false end
	if base == "tfa" then
		local sel = tonumber(s.sel) or 0
		local cur = sel > 0 and istable(s.atts) and s.atts[sel] or nil
		return cur ~= nil and cur == s.default
	end
	return false
end

local function ownedAttachments(ply, base)
	local out = {}
	for _, st in ipairs(Q.Storages(ply)) do
		for _, inst in SortedPairs(st.items) do
			local def = RPInv.Items[inst.item]
			if def and def.use_type == "attachment" then
				local b, a = A.Parse(def.use_arg)
				if b == base and not out[def.id] then out[def.id] = { def = def, att = a, st = st, inst = inst } end
			end
		end
	end
	return out
end

local function findOwned(ply, item)
	for _, st in ipairs(Q.Storages(ply)) do
		for _, inst in SortedPairs(st.items) do
			if inst.item == item then return st, inst end
		end
	end
end

local function giveAtt(ply, base, att)
	local def = A.EnsureDef(base, att)
	if not def then return end
	local st = RPInv.PlayerStorage(ply)
	if RPInv.GiveToPlayer(ply, def.id, 1) > 0 then
		RPInv.SpawnWorldItem(def.id, 1, RPInv.DropPos(ply))
		RPInv.Notify(ply, "No space for " .. def.name .. ". It was dropped.", 2)
	else
		RPInv.Push(st)
	end
	hook.Run("RPInv_ItemAdded", ply, def.id, 1)
end

local function saveWeapon(ply, wep, inst)
	inst.meta.atts = A.Capture(wep)
	DB.UpdateInst(inst, DB.LOC_EQUIP, RPInv.SID(ply))
	E.QueuePush(ply)
	clientRefresh(ply, wep)
end

local function refund(ply, base, record, before, after, wep)
	local rec = counts(record)
	local b, a = counts(before), counts(after)
	for att, n in pairs(b) do
		local gone = n - (a[att] or 0)
		for _ = 1, gone do
			if (rec[att] or 0) > 0 and not A.IsDefault(wep, base, att) then
				rec[att] = rec[att] - 1
				giveAtt(ply, base, att)
			end
		end
	end
end

function A.SendInfo(ply, wslot)
	local wep, inst, base, def = slotWeapon(ply, wslot)
	if not wep then
		RPInv.SendJSON("rpinv_attinfo", { w = wslot, err = inst }, ply)
		return
	end
	local owned = ownedAttachments(ply, base)
	local slots = {}
	for _, k in ipairs(slotKeys(base, wep)) do
		local cur = installedAt(base, wep, k)
		local opts = {}
		for id, o in SortedPairs(owned) do
			if o.att ~= cur and accepts(ply, base, wep, k, o.att) then opts[#opts + 1] = { item = id, n = o.def.name } end
		end
		slots[#slots + 1] = {
			k = tostring(k), n = slotName(base, wep, k), i = cur, inm = cur and A.AttName(base, cur) or nil,
			free = cur and (A.IsFree(base, cur) or noRemove(base, wep, k)) or nil, fixed = fixed(base, wep, k) or nil, opts = opts,
		}
	end
	RPInv.SendJSON("rpinv_attinfo", { w = wslot, name = def.name, base = A.BaseNames[base], slots = slots }, ply)
end

local function keyOf(base, wep, k)
	if k == nil then return nil end
	local n = tonumber(k)
	if base ~= "tfa" then return n end
	if n and slotTable(wep, n) then return n end
	return slotTable(wep, k) and k or nil
end

function A.AttachTo(ply, wslot, k, att)
	if not RPInv.Settings.att_items then return false, "Attachments are managed by the weapon base on this server." end
	if ply:GetNW2Bool("RPInvSurrender", false) then return false, "You cannot do that with your hands up." end
	local wep, inst, base = slotWeapon(ply, wslot)
	if not wep then return false, inst end
	local ab, an = A.Parse(att)
	if ab ~= base then return false, "This attachment does not fit this weapon." end
	local key = keyOf(base, wep, k)
	if key == nil then
		local free, any
		for _, sk in ipairs(slotKeys(base, wep)) do
			if accepts(ply, base, wep, sk, an) and not fixed(base, wep, sk) then
				any = any or sk
				if not installedAt(base, wep, sk) and not free then free = sk end
			end
		end
		key = free or any
		if key == nil then return false, "This attachment does not fit this weapon." end
	elseif not accepts(ply, base, wep, key, an) then
		return false, "This attachment does not fit that slot."
	end
	if fixed(base, wep, key) then return false, "That slot cannot be changed." end
	local record = A.DataList(inst.meta.atts or A.Capture(wep))
	local before = A.Installed(wep)
	runOp(ply, function()
		if (base == "arccw" or base == "tacrp") and installedAt(base, wep, key) then rawDetach(base, wep, key) end
		rawAttach(base, wep, key, an)
		finish(ply, wep, base)
	end)
	local after = A.Installed(wep)
	local b, a = counts(before), counts(after)
	if (a[an] or 0) <= (b[an] or 0) then
		refund(ply, base, record, before, after, wep)
		saveWeapon(ply, wep, inst)
		return false, "This attachment cannot be installed right now."
	end
	record[#record + 1] = an
	refund(ply, base, record, before, after, wep)
	saveWeapon(ply, wep, inst)
	ply:EmitSound("items/ammo_pickup.wav", 60, 135)
	return true
end

function A.DetachFrom(ply, wslot, k)
	if not RPInv.Settings.att_items then return false, "Attachments are managed by the weapon base on this server." end
	if ply:GetNW2Bool("RPInvSurrender", false) then return false, "You cannot do that with your hands up." end
	local wep, inst, base = slotWeapon(ply, wslot)
	if not wep then return false, inst end
	local key = keyOf(base, wep, k)
	if key == nil or not installedAt(base, wep, key) then return false, "Nothing to remove." end
	if fixed(base, wep, key) or noRemove(base, wep, key) then return false, "This attachment cannot be removed." end
	local record = A.DataList(inst.meta.atts or A.Capture(wep))
	local before = A.Installed(wep)
	runOp(ply, function()
		rawDetach(base, wep, key)
		finish(ply, wep, base)
	end)
	local after = A.Installed(wep)
	refund(ply, base, record, before, after, wep)
	saveWeapon(ply, wep, inst)
	local b, a = counts(before), counts(after)
	local changed = false
	for att, n in pairs(b) do
		if (a[att] or 0) < n then changed = true end
	end
	if not changed then return false, "This attachment cannot be removed." end
	ply:EmitSound("items/ammo_pickup.wav", 60, 90)
	return true
end

local Actions = RPInv.Actions

Actions.attinfo = function(ply, t)
	A.SendInfo(ply, tostring(t.w or ""))
	return true
end

Actions.attach = function(ply, t, touch)
	local def = RPInv.Items[tostring(t.item or "")]
	if not def or def.use_type ~= "attachment" then return false end
	local st, inst
	if t.from and t.id then
		st = RPInv.Access(ply, t.from)
		inst = st and st.items[RPInv.Int(t.id, 1, 2147483647) or -1]
		if inst and inst.item ~= def.id then inst = nil end
	end
	if not inst then st, inst = findOwned(ply, def.id) end
	if not inst then return "You do not have this attachment." end
	local wslot = tostring(t.w or "")
	touch(st)
	local x, y, rot, meta = inst.x, inst.y, inst.rot, table.Copy(inst.meta)
	local removed = inst.amount <= 1
	inst.amount = inst.amount - 1
	if removed then RPInv.InstRemove(st, inst) else RPInv.InstSave(st, inst) end
	local ok, err = A.AttachTo(ply, wslot, t.k, def.use_arg)
	if ok then
		hook.Run("RPInv_ItemRemoved", ply, def.id, 1)
	elseif removed then
		local w, h = RPInv.Grid.Size(def, rot)
		local placed = RPInv.Grid.CanPlace(st, RPInv.Items, w, h, x, y) and RPInv.InstCreate(st, def.id, 1, meta, x, y, rot)
		if not placed and RPInv.GiveToStorage(st, def.id, 1, meta) > 0 then
			RPInv.SpawnWorldItem(def.id, 1, RPInv.DropPos(ply), nil, meta)
		end
	else
		inst.amount = inst.amount + 1
		RPInv.InstSave(st, inst)
	end
	A.SendInfo(ply, wslot)
	return ok or err
end

Actions.detach = function(ply, t)
	local wslot = tostring(t.w or "")
	local ok, err = A.DetachFrom(ply, wslot, t.k)
	A.SendInfo(ply, wslot)
	return ok or err
end

function RPInv.UseAttachment(ply, def)
	local active = ply:GetActiveWeapon()
	if not IsValid(active) then return false, "Hold the weapon you want to modify." end
	for wslot, inst in pairs(E.State(ply).weapons) do
		local wdef = RPInv.Items[inst.item]
		if wdef and wdef.use_arg == active:GetClass() then
			return A.AttachTo(ply, wslot, nil, def.use_arg)
		end
	end
	return false, "Hold a weapon from your weapon slots to modify it."
end

hook.Add("PlayerUse", "RPInv_AttachmentPickup", function(ply, ent)
	if not RPInv.Settings.att_items or not IsValid(ent) or ent.RPInvTaken then return end
	local list
	local cls = ent:GetClass()
	local giveBase = (string.sub(cls, 1, 10) == "arccw_att_" and "arccw") or (string.sub(cls, 1, 9) == "arc9_att_" and "arc9") or nil
	if istable(ent.GiveAttachments) and giveBase then
		list = {}
		for att, n in pairs(ent.GiveAttachments) do
			if att ~= "BaseClass" then
				for _ = 1, math.Clamp(tonumber(n) or 1, 1, 20) do list[#list + 1] = { giveBase, att } end
			end
		end
	elseif isstring(ent.AttToGive) and string.sub(ent:GetClass(), 1, 10) == "tacrp_att_" then
		list = { { "tacrp", ent.AttToGive } }
	end
	if not list then return end
	if not ply:KeyPressed(IN_USE) then return false end
	local st = RPInv.PlayerStorage(ply)
	local need = {}
	for _, e in ipairs(list) do
		local def = A.EnsureDef(e[1], e[2])
		if def then need[#need + 1] = def end
	end
	if #need == 0 then return false end
	local placed, rest = 0, {}
	for _, def in ipairs(need) do
		if RPInv.GiveToStorage(st, def.id, 1) == 0 then
			placed = placed + 1
			hook.Run("RPInv_ItemAdded", ply, def.id, 1)
		else
			rest[#rest + 1] = def
		end
	end
	if placed == 0 then
		RPInv.Notify(ply, "Not enough space.", 2)
		return false
	end
	RPInv.Push(st)
	local pos = ent:GetPos() + Vector(0, 0, 8)
	ent.RPInvTaken = true
	ent:Remove()
	for i, def in ipairs(rest) do RPInv.SpawnWorldItem(def.id, 1, pos + Vector(0, 0, i * 4)) end
	ply:EmitSound("items/ammo_pickup.wav", 60)
	if #rest > 0 then
		RPInv.Notify(ply, "Picked up " .. placed .. " of " .. #need .. " attachments. The rest did not fit.", 2)
	else
		RPInv.Notify(ply, "Picked up: " .. need[1].name .. (#need > 1 and (" +" .. (#need - 1)) or ""), 1)
	end
	return false
end)

local function wrapArc9Net()
	local key = "arc9_networkweapon"
	local orig = net.Receivers[key]
	if not isfunction(orig) or orig == A.Arc9NetWrapped then return end
	local wrapped = function(len, ply)
		local wpn = net.ReadEntity()
		if not IsValid(wpn) or not wpn.ARC9 then return end
		if wpn:GetOwner() ~= ply then return end
		local nocust = GetConVar("arc9_atts_nocustomize")
		if nocust and nocust:GetBool() then return end
		if A.Locked() or A.Guarded(wpn) then
			if isfunction(wpn.SendWeapon) then wpn:SendWeapon(ply) end
			return
		end
		wpn:ReceiveWeapon()
	end
	net.Receivers[key] = wrapped
	A.Arc9NetWrapped = wrapped
	local rkey = "arc9_randomizeatts"
	local rorig = net.Receivers[rkey]
	if isfunction(rorig) and rorig ~= A.Arc9RandWrapped then
		local rwrapped = function(len, ply)
			local wpn = IsValid(ply) and ply:GetActiveWeapon()
			if IsValid(wpn) and wpn.ARC9 and (A.Locked() or A.Guarded(wpn)) then
				if isfunction(wpn.SendWeapon) then wpn:SendWeapon(ply) end
				return
			end
			rorig(len, ply)
		end
		net.Receivers[rkey] = rwrapped
		A.Arc9RandWrapped = rwrapped
	end
end

hook.Add("InitPostEntity", "RPInv_Arc9Net", wrapArc9Net)
timer.Simple(0, wrapArc9Net)
