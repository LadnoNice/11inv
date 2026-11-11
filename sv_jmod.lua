local DB = RPInv.DB
local G = RPInv.Grid
local J = {}
RPInv.JM = J

util.AddNetworkString("rpinv_a_jmodimport")

local itemsDirty = false
local function itemsChanged()
	if itemsDirty then return end
	itemsDirty = true
	timer.Simple(0, function()
		itemsDirty = false
		RPInv.SendItems()
	end)
end

function J.Available()
	return RPInv.JModAvailable() and isfunction(JMod.EZ_Equip_Armor) and isfunction(JMod.RemoveArmorByID)
end

function J.IsArmorEnt(ent)
	return IsValid(ent) and isstring(ent.ArmorName) and string.sub(ent:GetClass(), 1, 21) == "ent_jack_gmod_ezarmor"
end

local function defId(name)
	local id = "jmod_" .. string.gsub(string.lower(name), "[^a-z0-9_]", "_")
	return string.sub(id, 1, 32)
end

function J.DefFor(name)
	for id, d in pairs(RPInv.Items) do
		if d.jmod_armor == name then return d end
	end
end

function J.EnsureDef(name)
	if not RPInv.JModAvailable() then return nil end
	local info = JMod.ArmorTable[name]
	if not info then return nil end
	local def = J.DefFor(name)
	if def then return def end
	local slot = RPInv.JModSlotFor(name) or "body"
	local size = RPInv.JModSlotSize[slot] or { 2, 2 }
	local id = defId(name)
	if RPInv.Items[id] then id = string.sub(id, 1, 28) .. "_" .. math.random(100, 999) end
	local slotName = RPInv.EquipSlotByKey[slot] and RPInv.EquipSlotByKey[slot].name or slot
	local gw, gh = 0, 0
	if info.storage and RPInv.Carriers then gw, gh = RPInv.Carriers.GridForStorage(info.storage) end
	def = {
		id = id, name = tostring(info.PrintName or name):sub(1, 40), model = info.entmdl or info.mdl or "models/props_junk/cardboard_box004a.mdl",
		descr = ("JMod armor. Slot: " .. slotName .. ". Durability: " .. tostring(info.dur or "?") .. "."):sub(1, 200),
		max_stack = 1, use_type = "none", use_arg = "", w = size[1], h = size[2], rotatable = true,
		equip_slot = slot, grid_w = gw, grid_h = gh, jmod_armor = name, world_class = info.ent or "",
		cam_ang = "0 0 0", cam_fov = 1, category = "Armor",
	}
	RPInv.Items[id] = def
	DB.SaveItem(def)
	itemsChanged()
	return def
end

function J.ImportAll()
	if not RPInv.JModAvailable() then return 0 end
	local n = 0
	DB.Transaction(function()
		for name, info in pairs(JMod.ArmorTable) do
			if info.ent and not info.noent and not J.DefFor(name) then
				if J.EnsureDef(name) then n = n + 1 end
			end
		end
	end)
	return n
end

local function colTable(c)
	if not c then return nil end
	return { r = c.r or 255, g = c.g or 255, b = c.b or 255 }
end

function J.MetaFromEnt(ent)
	local m = {
		dur = tonumber(ent.Durability),
		col = colTable(ent:GetColor()),
		chrg = istable(ent.ArmorCharges) and table.Copy(ent.ArmorCharges) or nil,
		ammo = (istable(ent.ammoStored) and next(ent.ammoStored)) and table.Copy(ent.ammoStored) or nil,
	}
	local cid = isstring(ent.EZID) and string.match(ent.EZID, "^[%w_]+$") or nil
	return { jmod = m, cid = cid }
end

function J.MetaFromWorn(item, id)
	local cid = isstring(id) and string.match(id, "^[%w_]+$") or nil
	return { jmod = { dur = tonumber(item.dur), col = colTable(item.col), chrg = istable(item.chrg) and table.Copy(item.chrg) or nil }, cid = cid }
end

function J.SpawnArmorEnt(name, meta, pos, ang)
	if not RPInv.JModAvailable() then return nil end
	local info = JMod.ArmorTable[name]
	if not info or not info.ent then return nil end
	local ent = ents.Create(info.ent)
	if not IsValid(ent) then return nil end
	local m = meta and meta.jmod or {}
	ent:SetPos(pos)
	ent:SetAngles(ang or Angle(0, math.random(0, 359), 0))
	if m.dur then ent.Durability = m.dur end
	if m.chrg then ent.ArmorCharges = table.Copy(m.chrg) end
	if m.ammo then ent.ammoStored = table.Copy(m.ammo) end
	if meta and isstring(meta.cid) then ent.EZID = meta.cid end
	ent:Spawn()
	ent:Activate()
	if m.col then ent:SetColor(Color(m.col.r, m.col.g, m.col.b)) end
	return ent
end

local function hasJModStorage(ent)
	local inv = ent.JModInv
	if not istable(inv) then return false end
	if istable(inv.items) and #inv.items > 0 then return true end
	if istable(inv.EZresources) and next(inv.EZresources) ~= nil then return true end
	return false
end

function J.StoreEntity(ply, ent, target)
	if not IsValid(ply) or not J.IsArmorEnt(ent) or ent.RPInvTaken then return false end
	ent.RPInvReserved = nil
	if hasJModStorage(ent) then
		RPInv.Notify(ply, "This item still holds JMod storage contents. Empty it first.", 2)
		return false
	end
	local def = J.EnsureDef(ent.ArmorName)
	if not def then
		RPInv.Notify(ply, "Unknown JMod armor.", 2)
		return false
	end
	local meta = J.MetaFromEnt(ent)
	local placed = false
	if target then
		local st = RPInv.Access(ply, target.sid)
		local rot = (def.rotatable and target.rot == 1) and 1 or 0
		local w, h = G.Size(def, rot)
		if st and RPInv.AllowedIn(st, def) and isnumber(target.x) and isnumber(target.y) and G.CanPlace(st, RPInv.Items, w, h, target.x, target.y) then
			placed = RPInv.InstCreate(st, def.id, 1, meta, target.x, target.y, rot) ~= nil
			if placed then RPInv.Push(st) end
		end
	end
	if not placed then
		local st = RPInv.PlayerStorage(ply)
		placed = RPInv.GiveToPlayer(ply, def.id, 1, meta) == 0
		if placed then RPInv.Push(st) end
	end
	if not placed then
		RPInv.Notify(ply, "Not enough space for " .. def.name .. ". It was left on the ground.", 2)
		return false
	end
	ent.RPInvTaken = true
	ent:Remove()
	ply:EmitSound("items/ammo_pickup.wav", 60)
	hook.Run("RPInv_ItemAdded", ply, def.id, 1)
	return true
end

function J.WornList(ply)
	local out = {}
	if not RPInv.JModAvailable() or not istable(ply.EZarmor) or not istable(ply.EZarmor.items) then return out end
	for id, it in pairs(ply.EZarmor.items) do
		if it.name and JMod.ArmorTable[it.name] then
			local def = J.EnsureDef(it.name)
			if def then
				out[#out + 1] = {
					key = tostring(id), name = it.name, slot = RPInv.JModSlotFor(it.name) or "body", item = def.id,
					dur = tonumber(it.dur) or 0, max = tonumber(JMod.ArmorTable[it.name].dur) or 1, tgl = it.tgl and true or nil,
				}
			end
		end
	end
	table.SortByMember(out, "key", true)
	return out
end

function J.Equip(ply, name, meta)
	if not J.Available() then return false, "JMod is not installed." end
	if not JMod.ArmorTable[name] then return false, "Unknown JMod armor." end
	ply.EZarmor = ply.EZarmor or table.FullCopy(JMod.DEFAULT_ARMOR)
	local before = {}
	for k in pairs(ply.EZarmor.items) do before[k] = true end
	local ok, err = pcall(JMod.EZ_Equip_Armor, ply, name)
	if not ok then return false, "JMod error: " .. tostring(err) end
	local newId
	for k in pairs(ply.EZarmor.items) do
		if not before[k] then newId = k end
	end
	if not newId then return false, "JMod refused to equip this item." end
	local item = ply.EZarmor.items[newId]
	local cid = meta and isstring(meta.cid) and meta.cid or nil
	if cid and cid ~= newId and not ply.EZarmor.items[cid] then
		ply.EZarmor.items[newId] = nil
		item.id = cid
		ply.EZarmor.items[cid] = item
		newId = cid
		JMod.EZarmorSync(ply)
	end
	local m = meta and meta.jmod
	if m then
		if m.dur then item.dur = m.dur end
		if m.col then
			item.col = Color(m.col.r, m.col.g, m.col.b)
			if JMod.ArmorTable[name].plymdl then ply:SetColor(item.col) end
		end
		if m.chrg then item.chrg = table.Copy(m.chrg) end
		if m.ammo then
			for k, v in pairs(m.ammo) do ply:GiveAmmo(v, k, true) end
		end
		JMod.EZarmorSync(ply)
	end
	return true, newId
end

hook.Add("JMod_ArmorRemoved", "RPInv_Capture", function(ply, info, specs, ent, broken)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if not IsValid(ent) or broken then return end
	if not ply:Alive() and RPInv.Settings.death_mode ~= "drop" then
		timer.Simple(0, function() if IsValid(ent) then ent:Remove() end end)
		return
	end
	local cap = ply.RPInvCapture
	if not cap then return end
	ent.RPInvReserved = true
	ent:SetNoDraw(true)
	ent:SetNotSolid(true)
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end
	local owner = IsValid(cap.to) and cap.to or ply
	local function finish()
		if not IsValid(ent) then return end
		if IsValid(owner) and J.StoreEntity(owner, ent, cap.target) then return end
		ent.RPInvReserved = nil
		ent:SetNoDraw(false)
		ent:SetNotSolid(false)
		local p = ent:GetPhysicsObject()
		if IsValid(p) then
			p:EnableMotion(true)
			p:Wake()
		end
	end
	if specs and specs.storage then
		timer.Simple(0.1, finish)
	else
		finish()
	end
end)

hook.Add("PlayerUse", "RPInv_JModPickup", function(ply, ent)
	if not J.IsArmorEnt(ent) then return end
	if ent.RPInvReserved or ent.RPInvTaken then return false end
	if not ply:KeyPressed(IN_USE) then return end
	local mode = RPInv.Settings.jmod_pickup
	local alt = isfunction(JMod.IsAltUsing) and JMod.IsAltUsing(ply)
	if alt then return end
	local wants = (mode == "plain") or (mode == "shift" and ply:KeyDown(IN_SPEED))
	if not wants then return end
	J.StoreEntity(ply, ent)
	return false
end)

net.Receive("rpinv_a_jmodimport", function(_, ply)
	if not RPInv.IsAdmin(ply) then return end
	if not RPInv.JModAvailable() then RPInv.Notify(ply, "JMod is not installed.", 2) return end
	local n = J.ImportAll()
	DB.Log(ply, "jmod_import", n)
	RPInv.Notify(ply, "Imported " .. n .. " JMod armor item(s).", 1)
end)
