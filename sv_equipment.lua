local DB = RPInv.DB
local G = RPInv.Grid
local J = RPInv.JM
local E = RPInv.Equip or {}
RPInv.Equip = E
E.Cache = E.Cache or {}

util.AddNetworkString("rpinv_equip")
util.AddNetworkString("rpinv_dropwep")
util.AddNetworkString("rpinv_vmreset")

local BASE_NO_DROP = { rpinv_hands = true, weapon_fists = true, weapon_physgun = true, gmod_tool = true, gmod_camera = true, rpinv_flaregun = true }
local blacklistSrc, blacklistSet = nil, {}

local function blacklisted(cls)
	local src = RPInv.Settings.weapon_blacklist or ""
	if src ~= blacklistSrc then
		blacklistSrc, blacklistSet = src, {}
		for c in string.gmatch(src, "[^,%s]+") do blacklistSet[c] = true end
	end
	return blacklistSet[cls] == true
end
RPInv.WeaponBlacklisted = blacklisted

local NO_DROP = setmetatable({}, { __index = function(_, cls) return BASE_NO_DROP[cls] or blacklisted(cls) or nil end })

hook.Add("AllowPlayerPickup", "RPInv_NoUsePickup", function(_, ent)
	if IsValid(ent) and (ent:IsNPC() or string.sub(ent:GetClass(), 1, 4) == "npc_") then return end
	if not RPInv.Settings.use_pickup then return false end
end)

function E.GiveHands(ply, select)
	local cls = RPInv.HandsClass()
	if cls == "" or not IsValid(ply) or not ply:Alive() then return end
	if not ply:HasWeapon(cls) then ply:Give(cls) end
	if select and ply:HasWeapon(cls) and not ply:GetNW2Bool("RPInvSurrender", false) then ply:SelectWeapon(cls) end
end

hook.Add("PlayerLoadout", "RPInv_Hands", function(ply)
	E.GiveHands(ply, false)
end)

hook.Add("KeyPress", "RPInv_FistsToHands", function(ply, key)
	if key ~= IN_RELOAD then return end
	if CurTime() - (ply.RPInvFistsAt or 0) < 0.4 then return end
	local w = ply:GetActiveWeapon()
	if not IsValid(w) or w:GetClass() ~= "weapon_fists" or not ply:HasWeapon("rpinv_hands") then return end
	ply.RPInvFistsAt = CurTime()
	ply:SelectWeapon("rpinv_hands")
	timer.Simple(0.2, function()
		if not IsValid(ply) or not ply:HasWeapon("weapon_fists") then return end
		local a = ply:GetActiveWeapon()
		if not (IsValid(a) and a:GetClass() == "weapon_fists") then ply:StripWeapon("weapon_fists") end
	end)
end)

net.Receive("rpinv_dropwep", function(_, ply)
	if not ply:Alive() or ply:GetNW2Bool("RPInvSurrender", false) or ply:InVehicle() then return end
	if (ply.RPInvDropNext or 0) > CurTime() then return end
	ply.RPInvDropNext = CurTime() + 0.5
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or NO_DROP[wep:GetClass()] then return end
	if hook.Run("RPInv_CanDropWeapon", ply, wep) == false then return end
	E.ThrowWeapon(ply, wep)
end)

function E.ThrowWeapon(ply, wep)
	ply:DropWeapon(wep)
	if not IsValid(wep) then return end
	local aim = ply:GetAimVector()
	local start = ply:GetShootPos() - Vector(0, 0, 6)
	local tr = util.TraceHull({ start = start, endpos = start + aim * 30, mins = Vector(-5, -5, -5), maxs = Vector(5, 5, 5), filter = { ply, wep } })
	wep:SetPos(tr.HitPos - aim * 4)
	wep:SetAngles(Angle(0, ply:EyeAngles().y + 90, 0))
	local phys = wep:GetPhysicsObject()
	if IsValid(phys) then
		phys:Wake()
		phys:SetVelocity(ply:GetVelocity() + aim * 230 + Vector(0, 0, 50))
		phys:AddAngleVelocity(-phys:GetAngleVelocity() + Vector(0, 0, math.random(-90, 90)))
	end
	ply:EmitSound("physics/metal/weapon_impact_soft" .. math.random(1, 3) .. ".wav", 55)
end

local SLOT_SIZE = { [0] = { 3, 1, "utility" }, [1] = { 2, 1, "secondary" }, [2] = { 3, 2, "primary" }, [3] = { 4, 2, "primary" }, [4] = { 5, 2, "primary" }, [5] = { 2, 2, "utility" } }

local HL2_WEAPONS = {
	weapon_crowbar = { PrintName = "Crowbar", Slot = 0, WorldModel = "models/weapons/w_crowbar.mdl" },
	weapon_stunstick = { PrintName = "Stunstick", Slot = 0, WorldModel = "models/weapons/w_stunbaton.mdl" },
	weapon_physcannon = { PrintName = "Gravity Gun", Slot = 0, WorldModel = "models/weapons/w_physics.mdl" },
	weapon_pistol = { PrintName = "9mm Pistol", Slot = 1, WorldModel = "models/weapons/w_pistol.mdl" },
	weapon_357 = { PrintName = ".357 Magnum", Slot = 1, WorldModel = "models/weapons/w_357.mdl" },
	weapon_smg1 = { PrintName = "SMG", Slot = 2, WorldModel = "models/weapons/w_smg1.mdl" },
	weapon_ar2 = { PrintName = "Pulse Rifle", Slot = 2, WorldModel = "models/weapons/w_irifle.mdl" },
	weapon_shotgun = { PrintName = "Shotgun", Slot = 3, WorldModel = "models/weapons/w_shotgun.mdl" },
	weapon_crossbow = { PrintName = "Crossbow", Slot = 3, WorldModel = "models/weapons/w_crossbow.mdl" },
	weapon_rpg = { PrintName = "RPG", Slot = 4, WorldModel = "models/weapons/w_rocket_launcher.mdl" },
	weapon_frag = { PrintName = "Frag Grenade", Slot = 4, WorldModel = "models/weapons/w_grenade.mdl" },
	weapon_slam = { PrintName = "S.L.A.M.", Slot = 4, WorldModel = "models/weapons/w_slam.mdl" },
	weapon_bugbait = { PrintName = "Bugbait", Slot = 5, WorldModel = "models/weapons/w_bugbait.mdl" },
}
RPInv.HL2Weapons = HL2_WEAPONS

local itemsDirty = false
local function itemsChanged()
	if itemsDirty then return end
	itemsDirty = true
	timer.Simple(0, function()
		itemsDirty = false
		RPInv.SendItems()
	end)
end

local function bestWeaponModel(cls, fallback)
	local full = weapons.Get(cls) or HL2_WEAPONS[cls]
	local candidates = {}
	if full and full.MirrorVMWM then
		candidates[#candidates + 1] = full.WorldModelMirror
		candidates[#candidates + 1] = full.ViewModel
	end
	candidates[#candidates + 1] = fallback
	candidates[#candidates + 1] = full and full.WorldModel
	for _, m in ipairs(candidates) do
		if isstring(m) and m ~= "" and util.IsValidModel(m) then return m end
	end
	return "models/weapons/w_pistol.mdl"
end

function RPInv.WeaponDefFor(wep)
	return RPInv.WeaponDefForClass(wep:GetClass(), wep:GetModel(), wep:GetSlot())
end

function RPInv.WeaponDefForClass(cls, entModel, wslot)
	if NO_DROP[cls] then return nil end
	for _, d in SortedPairs(RPInv.Items) do
		if d.use_type == "weapon" and d.use_arg == cls then
			if d.descr == ("Weapon: " .. cls):sub(1, 200) then
				local better = bestWeaponModel(cls, entModel)
				if better ~= d.model then
					d.model = better
					DB.SaveItem(d)
					itemsChanged()
				end
			end
			return d
		end
	end
	local stored = weapons.Get(cls) or HL2_WEAPONS[cls]
	if not stored then return nil end
	local listed = list.Get("Weapon")[cls]
	local name = (stored and stored.PrintName) or (listed and listed.PrintName) or cls
	if not isstring(name) or name == "" or string.sub(name, 1, 1) == "#" then name = cls end
	local model = bestWeaponModel(cls, entModel)
	local slot = math.Clamp(tonumber(wslot or stored.Slot) or 2, 0, 5)
	local size = SLOT_SIZE[slot] or SLOT_SIZE[2]
	local id = string.sub("wep_" .. string.gsub(string.lower(cls), "[^a-z0-9_]", "_"), 1, 32)
	local def = {
		id = id, name = string.sub(name, 1, 40), model = model, descr = ("Weapon: " .. cls):sub(1, 200),
		max_stack = 1, use_type = "weapon", use_arg = cls, w = size[1], h = size[2], rotatable = true,
		equip_slot = size[3], grid_w = 0, grid_h = 0, jmod_armor = "", world_class = "",
		cam_ang = "0 0 0", cam_fov = 1, category = "Weapons",
	}
	RPInv.Items[id] = def
	DB.SaveItem(def)
	DB.Log(nil, "weapon_item_auto", id)
	itemsChanged()
	return def
end

hook.Add("PlayerDroppedWeapon", "RPInv_MarkDropped", function(ply, wep)
	if IsValid(wep) then
		wep.RPInvDropped = true
		wep.RPInvSlotOwner = nil
	end
	if not IsValid(ply) or not ply:IsPlayer() then return end
	timer.Simple(0.05, function()
		if not IsValid(ply) then return end
		RPInv.ResetViewModel(ply)
		if ply:IsBot() then return end
		net.Start("rpinv_vmreset")
		net.Send(ply)
	end)
end)

hook.Add("PlayerCanPickupWeapon", "RPInv_NoTouchPickup", function(ply, wep)
	if RPInv.Settings.weapon_touch_pickup then return end
	if not IsValid(wep) or NO_DROP[wep:GetClass()] then return end
	if wep.RPInvDropped or CurTime() - wep:GetCreationTime() > 0.3 then return false end
end)

hook.Add("PlayerUse", "RPInv_WeaponPickup", function(ply, ent)
	if not IsValid(ent) or not ent:IsWeapon() or IsValid(ent:GetOwner()) or ent.RPInvTaken then return end
	if NO_DROP[ent:GetClass()] or RPInv.Settings.weapon_pickup == false then return end
	if not ply:KeyPressed(IN_USE) then return false end
	local def = RPInv.WeaponDefFor(ent)
	if not def then return end
	local clip = ent:Clip1()
	local meta = istable(ent.RPInvMeta) and table.Copy(ent.RPInvMeta) or {}
	if clip and clip >= 0 then meta.clip1 = clip end
	meta.atts = ent.RPInvAttPending or RPInv.Att.Capture(ent)
	local st = RPInv.PlayerStorage(ply)
	if RPInv.GiveToPlayer(ply, def.id, 1, meta) > 0 then
		RPInv.Notify(ply, "Not enough space for " .. def.name .. ".", 2)
		return false
	end
	ent.RPInvTaken = true
	ent:Remove()
	RPInv.Push(st)
	ply:EmitSound("items/ammo_pickup.wav", 60)
	RPInv.Notify(ply, "Picked up: " .. def.name, 1)
	hook.Run("RPInv_ItemAdded", ply, def.id, 1)
	return false
end)

local sid = RPInv.SID
local int = RPInv.Int
local MAXID = 2147483647

if DB.GetSetting("weapon_slots_v2", "0") ~= "1" then
	DB.Transaction(function()
		for old, new in pairs(RPInv.OldWeaponSlots) do
			DB.Query(string.format("UPDATE rpinv_items SET equip_slot = %s WHERE equip_slot = %s", sql.SQLStr(new), sql.SQLStr(old)))
			DB.Query(string.format("UPDATE rpinv_inst SET slot = %s WHERE loc_type = %d AND slot = %s", sql.SQLStr(new), DB.LOC_EQUIP, sql.SQLStr(old)))
		end
	end)
	for _, d in pairs(RPInv.Items) do
		d.equip_slot = RPInv.OldWeaponSlots[d.equip_slot] or d.equip_slot
	end
	DB.SetSetting("weapon_slots_v2", "1")
end

local function state(ply)
	local key = sid(ply)
	local s = E.Cache[key]
	if s then return s end
	s = { weapons = {}, armor = {} }
	local orphans = {}
	for _, inst in ipairs(DB.LoadInsts(DB.LOC_EQUIP, key)) do
		local def = RPInv.Items[inst.item]
		local slot = RPInv.EquipSlotByKey[inst.slot or ""]
		if inst.slot == "armor" then
			s.armor[#s.armor + 1] = inst
		elseif not def then
			DB.DeleteInst(inst.id)
		elseif slot and slot.weapon and not s.weapons[inst.slot] then
			s.weapons[inst.slot] = inst
		else
			orphans[#orphans + 1] = inst
		end
	end
	E.Cache[key] = s
	if #orphans > 0 then
		local st = RPInv.PlayerStorage(ply)
		DB.Transaction(function()
			for _, inst in ipairs(orphans) do
				DB.DeleteInst(inst.id)
				RPInv.GiveToStorage(st, inst.item, inst.amount, inst.meta)
			end
		end)
	end
	return s
end
E.State = state

function E.Slots(ply)
	local s = state(ply)
	local slots = {}
	local worn = J.WornList(ply)
	for _, w in ipairs(worn) do
		local def = RPInv.Items[w.item]
		slots[w.slot] = slots[w.slot] or {}
		table.insert(slots[w.slot], {
			kind = "armor", key = w.key, item = w.item, dur = w.dur, max = w.max,
			carrier = RPInv.IsCarrierDef(def) or nil,
		})
	end
	for slot, inst in pairs(s.weapons) do
		slots[slot] = { { kind = "weapon", key = tostring(inst.id), item = inst.item, meta = next(inst.meta) ~= nil and inst.meta or nil } }
	end
	return slots, worn
end

function E.Push(ply)
	if not IsValid(ply) then return end
	if ply:IsBot() then
		hook.Run("RPInv_EquipPushed", ply, J.WornList(ply))
		return
	end
	local s = state(ply)
	local slots = {}
	local worn = J.WornList(ply)
	for _, w in ipairs(worn) do
		local def = RPInv.Items[w.item]
		slots[w.slot] = slots[w.slot] or {}
		table.insert(slots[w.slot], {
			kind = "armor", key = w.key, item = w.item, dur = w.dur, max = w.max,
			carrier = RPInv.IsCarrierDef(def) or nil,
		})
	end
	for slot, inst in pairs(s.weapons) do
		slots[slot] = { { kind = "weapon", key = tostring(inst.id), item = inst.item, meta = next(inst.meta) ~= nil and inst.meta or nil } }
	end
	local pd = RPInv.Carriers.PocketsDef()
	RPInv.SendJSON("rpinv_equip", {
		slots = slots, jmod = J.Available(), pockets = RPInv.Carriers.PocketsCid(ply), pocketsW = pd.grid_w, pocketsH = pd.grid_h,
	}, ply)
	hook.Run("RPInv_EquipPushed", ply, worn)
end

local function queuePush(ply)
	if not IsValid(ply) then return end
	timer.Create("RPInv_EqPush" .. ply:EntIndex(), 0, 1, function()
		if IsValid(ply) then E.Push(ply) end
	end)
end
E.QueuePush = queuePush

function E.SaveArmor(ply)
	if not IsValid(ply) or not J.Available() or ply.RPInvArmorPending then return end
	local s = state(ply)
	local key = sid(ply)
	DB.Transaction(function()
		for _, inst in ipairs(s.armor) do DB.DeleteInst(inst.id) end
		s.armor = {}
		for id, it in pairs((ply.EZarmor and ply.EZarmor.items) or {}) do
			local def = it.name and J.EnsureDef(it.name)
			if def then
				local inst = { item = def.id, amount = 1, meta = J.MetaFromWorn(it, id), x = 0, y = 0, rot = 0, slot = "armor" }
				DB.InsertInst(inst, DB.LOC_EQUIP, key)
				s.armor[#s.armor + 1] = inst
			end
		end
	end)
end

function E.ClearArmorRows(ply)
	local s = state(ply)
	DB.Transaction(function()
		for _, inst in ipairs(s.armor) do DB.DeleteInst(inst.id) end
	end)
	s.armor = {}
end

function E.RestoreArmor(ply)
	ply.RPInvArmorPending = nil
	if not J.Available() then return end
	local s = state(ply)
	local worn = ply.EZarmor and istable(ply.EZarmor.items) and next(ply.EZarmor.items) ~= nil
	if #s.armor == 0 or worn then
		E.SaveArmor(ply)
		return
	end
	ply.RPInvArmorPending = true
	for _, inst in ipairs(s.armor) do
		local def = RPInv.Items[inst.item]
		if def and def.jmod_armor ~= "" then J.Equip(ply, def.jmod_armor, inst.meta) end
	end
	ply.RPInvArmorPending = nil
	E.SaveArmor(ply)
	queuePush(ply)
end

local function weaponDef(inst)
	local def = RPInv.Items[inst.item]
	if def and def.use_type == "weapon" and def.use_arg ~= "" then return def end
end

function E.GiveWeapon(ply, inst)
	local def = weaponDef(inst)
	if not def or ply:HasWeapon(def.use_arg) then return end
	local clip = tonumber(inst.meta.clip1)
	local wep = ply:Give(def.use_arg, clip ~= nil or RPInv.Settings.ammo_items == true)
	if IsValid(wep) and clip and clip >= 0 then wep:SetClip1(clip) end
	if IsValid(wep) then wep.RPInvSlotOwner = ply end
	E.RestoreAttachments(ply, wep, inst.meta.atts, clip)
end

local function emptyWeapon(ply, wep)
	if not IsValid(wep) or not IsValid(ply) then return false end
	local at = wep:GetPrimaryAmmoType()
	local reserve = (at and at >= 0) and ply:GetAmmoCount(at) or 0
	local clip = wep:Clip1()
	return (clip == nil or clip <= 0) and reserve <= 0
end

local function consumeSlot(ply, cls)
	local s = E.Cache[sid(ply)]
	if not s then return end
	for slot, inst in pairs(s.weapons) do
		local def = weaponDef(inst)
		if def and def.use_arg == cls then
			s.weapons[slot] = nil
			DB.DeleteInst(inst.id)
			queuePush(ply)
			hook.Run("RPInv_ItemRemoved", ply, def.id, 1)
			RPInv.Notify(ply, "Used up: " .. def.name, 0)
			return
		end
	end
end

local function consumableList()
	local out = {}
	for c in string.gmatch(RPInv.Settings.consumable_weapons or "", "[^,%s]+") do out[c] = true end
	return out
end

hook.Add("EntityRemoved", "RPInv_SlotWeaponUsedUp", function(ent)
	if not IsValid(ent) or not ent:IsWeapon() or ent.RPInvNoDrop then return end
	local ply = ent.RPInvSlotOwner
	if not IsValid(ply) or not ply:Alive() then return end
	if not emptyWeapon(ply, ent) then return end
	local cls = ent:GetClass()
	timer.Simple(0, function()
		if IsValid(ply) and ply:Alive() and not ply:HasWeapon(cls) then consumeSlot(ply, cls) end
	end)
end)

timer.Create("RPInv_ConsumableWeapons", 1, 0, function()
	local list = consumableList()
	if next(list) == nil then return end
	for _, ply in ipairs(player.GetAll()) do
		local s = ply:Alive() and E.Cache[sid(ply)]
		if s then
			for _, inst in pairs(s.weapons) do
				local def = weaponDef(inst)
				local w = def and list[def.use_arg] and ply:GetWeapon(def.use_arg)
				if IsValid(w) and emptyWeapon(ply, w) then
					E.NoDropSpawn(w)
					ply:StripWeapon(def.use_arg)
					consumeSlot(ply, def.use_arg)
				end
			end
		end
	end
end)

function E.RestoreAttachments(ply, wep, atts, clip)
	if not IsValid(wep) or not istable(atts) or not RPInv.Att.Restore then return end
	wep.RPInvAttPending = atts
	timer.Simple(0.15, function()
		if not IsValid(wep) or not IsValid(ply) or wep:GetOwner() ~= ply then return end
		wep.RPInvAttPending = nil
		RPInv.Att.Restore(ply, wep, atts)
		if not clip or clip < 0 then return end
		wep:SetClip1(clip)
		timer.Simple(0.1, function()
			if IsValid(wep) and wep:GetOwner() == ply then wep:SetClip1(clip) end
		end)
	end)
end

function E.StripWeapon(ply, inst)
	local def = weaponDef(inst)
	if not def then return end
	local wep = ply:GetWeapon(def.use_arg)
	if IsValid(wep) then
		local clip = wep:Clip1()
		if clip and clip >= 0 then inst.meta.clip1 = clip end
		inst.meta.atts = wep.RPInvAttPending or RPInv.Att.Capture(wep)
		E.NoDropSpawn(wep)
		ply:StripWeapon(def.use_arg)
	end
end

local function noop() end

function E.NoDropSpawn(wep)
	if IsValid(wep) then
		wep.OnDrop = noop
		wep.RPInvNoDrop = true
	end
end

local function ammoKey(ply) return "ammo_" .. sid(ply) end

function E.SaveAmmo(ply)
	if not IsValid(ply) or ply:IsBot() or ply.RPInvRestore or RPInv.Settings.ammo_items then return end
	local out = {}
	for id, n in pairs(ply:GetAmmo()) do
		local name = game.GetAmmoName(id)
		if name and n > 0 then out[name] = n end
	end
	DB.SetSetting(ammoKey(ply), util.TableToJSON(out))
end

function E.RestoreAmmo(ply)
	if ply:IsBot() or RPInv.Settings.ammo_items then return end
	local raw = DB.GetSetting(ammoKey(ply), "") or ""
	local t = raw ~= "" and util.JSONToTable(raw)
	if not istable(t) then return end
	ply:RemoveAllAmmo()
	for name, n in pairs(t) do
		if isstring(name) and game.GetAmmoID(name) ~= -1 then
			ply:SetAmmo(math.Clamp(math.floor(tonumber(n) or 0), 0, 9999), name)
		end
	end
end

function E.SyncWeaponMeta(ply)
	local s = E.Cache[sid(ply)]
	if not s then return end
	DB.Transaction(function()
		for _, inst in pairs(s.weapons) do
			local def = weaponDef(inst)
			local wep = def and ply:GetWeapon(def.use_arg)
			if IsValid(wep) and not wep.RPInvAttPending then
				local clip = wep:Clip1()
				if clip and clip >= 0 then inst.meta.clip1 = clip end
				inst.meta.atts = RPInv.Att.Capture(wep)
				DB.UpdateInst(inst, DB.LOC_EQUIP, sid(ply))
			end
		end
	end)
end

function E.GiveWeapons(ply)
	for _, inst in pairs(state(ply).weapons) do E.GiveWeapon(ply, inst) end
end

function RPInv.SpawnInstInWorld(inst, pos, amount, ply)
	local def = RPInv.Items[inst.item]
	if def and def.use_type == "resource" and RPInv.SpawnResource and RPInv.SpawnResource(def, pos, amount or inst.amount, ply) then return true end
	if def and def.jmod_armor ~= "" and J.SpawnArmorEnt(def.jmod_armor, inst.meta, pos) then return true end
	if def and def.jmod_armor == "" and def.world_class ~= "" and RPInv.SpawnWorldEntity and (def.world_class == "prop_physics" or scripted_ents.GetStored(def.world_class)) then
		local n = math.max(1, amount or inst.amount)
		local spawned = 0
		for i = 1, n do
			if IsValid(RPInv.SpawnWorldEntity(def, pos + Vector(math.random(-6, 6), math.random(-6, 6), i * 3), ply, inst.meta)) then spawned = spawned + 1 end
		end
		if spawned > 0 then return true end
	end
	return IsValid(RPInv.SpawnWorldItem(inst.item, amount or inst.amount, pos, nil, inst.meta))
end

local function placeBack(ply, inst, preferSt, x, y, rot)
	local defs = RPInv.Items
	local def = defs[inst.item]
	if preferSt and x and y then
		local r = (def.rotatable and rot == 1) and 1 or 0
		local w, h = G.Size(def, r)
		if G.CanPlace(preferSt, defs, w, h, x, y) then return preferSt, x, y, r end
	end
	local st = RPInv.PlayerStorage(ply)
	local ax, ay, ar = G.AutoPlace(st, defs, def)
	if ax then return st, ax, ay, ar end
end

local Actions = RPInv.Actions

Actions.equip = function(ply, t, touch)
	local src = RPInv.Access(ply, t.from)
	local inst = src and src.items[int(t.id, 1, MAXID) or -1]
	if not inst then return false end
	local def = RPInv.Items[inst.item]
	local slot = RPInv.EquipSlotOf(def)
	if not slot then return "This item cannot be equipped." end
	if t.slot ~= nil and t.slot ~= slot then return "This item does not fit that slot." end
	touch(src)

	if def.jmod_armor ~= "" then
		if not J.Available() then return "JMod is not installed." end
		src.items[inst.id] = nil
		ply.RPInvCapture = {}
		local ok, err = J.Equip(ply, def.jmod_armor, inst.meta)
		ply.RPInvCapture = nil
		if not ok then
			src.items[inst.id] = inst
			return err
		end
		DB.DeleteInst(inst.id)
		hook.Run("RPInv_ItemRemoved", ply, def.id, 1)
		E.SaveArmor(ply)
		queuePush(ply)
		return true
	end

	local s = state(ply)
	local old = s.weapons[slot]
	src.items[inst.id] = nil
	if old then
		local st, x, y, rot = placeBack(ply, old, src, inst.x, inst.y, old.rot)
		if not st then
			src.items[inst.id] = inst
			return "No space for the weapon that is already in that slot."
		end
		E.StripWeapon(ply, old)
		s.weapons[slot] = nil
		old.slot, old.x, old.y, old.rot = nil, x, y, rot
		st.items[old.id] = old
		DB.UpdateInst(old, st.loc, st.locId)
		touch(st)
	end
	inst.slot, inst.x, inst.y, inst.rot = slot, 0, 0, 0
	s.weapons[slot] = inst
	DB.UpdateInst(inst, DB.LOC_EQUIP, sid(ply))
	E.GiveWeapon(ply, inst)
	ply:EmitSound("items/ammo_pickup.wav", 55, 120)
	queuePush(ply)
	return true
end

Actions.slotready = function(ply, t)
	local inst = state(ply).weapons[tostring(t.slot or "")]
	local def = inst and weaponDef(inst)
	if not def then return false end
	if ply:HasWeapon(def.use_arg) then return true end
	if ply:InVehicle() or ply:GetNW2Bool("RPInvSurrender", false) then return false end
	E.GiveWeapon(ply, inst)
	if not ply:HasWeapon(def.use_arg) then return "This weapon is not installed on the server (" .. def.use_arg .. ")." end
	ply:SelectWeapon(def.use_arg)
	return true
end

Actions.unequip = function(ply, t, touch)
	local key = string.sub(tostring(t.key or ""), 1, 64)
	if key == "" then return false end
	local s = state(ply)
	local tx, ty, trot = int(t.x, 0, 63), int(t.y, 0, 63), int(t.rot, 0, 1)
	local target = t.to and RPInv.Access(ply, t.to) or nil

	for slot, inst in pairs(s.weapons) do
		if tostring(inst.id) == key then
			E.StripWeapon(ply, inst)
			if t.drop then
				s.weapons[slot] = nil
				RPInv.SpawnWorldItem(inst.item, 1, RPInv.DropPos(ply), nil, inst.meta)
				DB.DeleteInst(inst.id)
				queuePush(ply)
				return true
			end
			local st, x, y, rot = placeBack(ply, inst, target, tx, ty, trot)
			s.weapons[slot] = nil
			inst.slot = nil
			if not st then
				RPInv.SpawnWorldItem(inst.item, 1, RPInv.DropPos(ply), nil, inst.meta)
				DB.DeleteInst(inst.id)
				queuePush(ply)
				return "No space in your inventory. The item was dropped."
			end
			inst.x, inst.y, inst.rot = x, y, rot
			st.items[inst.id] = inst
			DB.UpdateInst(inst, st.loc, st.locId)
			touch(st)
			queuePush(ply)
			return true
		end
	end

	if not J.Available() or not (ply.EZarmor and istable(ply.EZarmor.items)) then return false end
	local armorId
	for id in pairs(ply.EZarmor.items) do
		if tostring(id) == key then armorId = id end
	end
	if not armorId then
		queuePush(ply)
		return false
	end
	if not t.drop then
		ply.RPInvCapture = { target = t.to and { sid = t.to, x = tx, y = ty, rot = trot } or nil }
	end
	local ok, err = pcall(JMod.RemoveArmorByID, ply, armorId, false)
	ply.RPInvCapture = nil
	if not ok then ErrorNoHalt("[RPInv] " .. tostring(err) .. "\n") end
	queuePush(ply)
	return true
end

function E.DropAll(ply)
	local base = ply:GetPos() + Vector(0, 0, 24)
	local st = RPInv.PlayerStorage(ply)
	local s = state(ply)
	local i = 0
	local function spot()
		i = i + 1
		return base + Vector(math.random(-28, 28), math.random(-28, 28), (i % 6) * 6)
	end
	for _, inst in pairs(s.weapons) do E.StripWeapon(ply, inst) end
	local pk = RPInv.Carriers.Pockets(ply)
	DB.Transaction(function()
		for id, inst in pairs(st.items) do
			RPInv.SpawnInstInWorld(inst, spot())
			DB.DeleteInst(id)
		end
		if pk then
			for id, inst in pairs(pk.items) do
				RPInv.SpawnInstInWorld(inst, spot())
				DB.DeleteInst(id)
			end
			pk.items = {}
		end
		st.items = {}
		for _, inst in pairs(s.weapons) do
			RPInv.SpawnInstInWorld(inst, spot())
			DB.DeleteInst(inst.id)
		end
		s.weapons = {}
	end)
	RPInv.Push(st)
	E.ClearArmorRows(ply)
	if J.Available() and ply.EZarmor and istable(ply.EZarmor.items) then
		local corpse = JMod.Config and JMod.Config.QoL and (tonumber(JMod.Config.QoL.JModCorpseStayTime) or 0) > 0
		if not corpse then
			for id in pairs(table.Copy(ply.EZarmor.items)) do pcall(JMod.RemoveArmorByID, ply, id, false) end
		end
	end
end

function E.ApplySuitColor(ply)
	if not J.Available() or not istable(ply.EZarmor) or not istable(ply.EZarmor.items) then return end
	for _, it in pairs(ply.EZarmor.items) do
		local info = it.name and JMod.ArmorTable[it.name]
		local c = it.col
		if info and info.plymdl and istable(c) and c.r and c.g and c.b then
			local cur = ply:GetColor()
			if cur.r ~= c.r or cur.g ~= c.g or cur.b ~= c.b then ply:SetColor(Color(c.r, c.g, c.b, cur.a)) end
			return
		end
	end
end

function E.GiveArmorWeapons(ply)
	if not IsValid(ply) or not ply:Alive() or not ply.EZarmor or not istable(ply.EZarmor.items) or not JMod or not JMod.ArmorTable then return end
	for id, item in pairs(ply.EZarmor.items) do
		local info = item.name and JMod.ArmorTable[item.name]
		local cls = info and info.eff and info.eff.weapon
		if isstring(cls) and not ply:HasWeapon(cls) and weapons.GetStored(cls) then
			local wep = ply:Give(cls)
			if IsValid(wep) then wep.EZarmorID = id end
		end
	end
end

hook.Add("JMod_EZarmorSync", "RPInv_ArmorSync", function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	timer.Create("RPInv_ArmorWeps" .. ply:EntIndex(), 0.5, 1, function() E.GiveArmorWeapons(ply) end)
	E.ApplySuitColor(ply)
	queuePush(ply)
	if ply.RPInvArmorPending or not ply:Alive() then return end
	timer.Create("RPInv_EqSave" .. ply:EntIndex(), 0.3, 1, function()
		if IsValid(ply) and ply:Alive() then E.SaveArmor(ply) end
	end)
end)

hook.Add("PlayerInitialSpawn", "RPInv_EquipJoin", function(ply)
	ply.RPInvArmorPending = true
	ply.RPInvRestore = "join"
end)

function E.SpawnBody(ply)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return nil end
	rag:SetModel(ply:GetModel())
	rag:SetSkin(ply:GetSkin())
	for i = 0, ply:GetNumBodyGroups() - 1 do rag:SetBodygroup(i, ply:GetBodygroup(i)) end
	rag:SetPos(ply:GetPos())
	rag:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	rag:SetColor(ply:GetColor())
	rag:Spawn()
	rag:Activate()
	rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	local vel = ply:GetVelocity()
	if vel:Length() > 90 then vel = vel:GetNormalized() * 90 end
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		local pos, ang = ply:GetBonePosition(rag:TranslatePhysBoneToBone(i))
		if IsValid(phys) then
			if pos then
				phys:SetPos(pos)
				phys:SetAngles(ang)
			end
			phys:SetVelocity(vel)
			phys:AddAngleVelocity(-phys:GetAngleVelocity())
			phys:SetDamping(0.6, 4)
		end
	end
	timer.Simple(1.5, function()
		if not IsValid(rag) then return end
		for i = 0, rag:GetPhysicsObjectCount() - 1 do
			local phys = rag:GetPhysicsObjectNum(i)
			if IsValid(phys) then phys:SetDamping(0.05, 0.3) end
		end
	end)
	return rag
end

function E.MakeCorpse(ply)
	local st = RPInv.PlayerStorage(ply)
	local s = state(ply)
	local c = RPInv.CreateTransient("BODY: " .. string.upper(ply:Nick()), math.max(st.w, 10), st.h + 8)
	local cst = RPInv.ContainerStorage(c)
	local defs = RPInv.Items
	local spill = {}
	local function put(inst)
		local def = defs[inst.item]
		local x, y, rot = G.AutoPlace(cst, defs, def)
		if not x then spill[#spill + 1] = inst return end
		inst.slot, inst.x, inst.y, inst.rot = nil, x, y, rot
		cst.items[inst.id] = inst
		DB.UpdateInst(inst, cst.loc, cst.locId)
	end
	for _, inst in pairs(s.weapons) do E.StripWeapon(ply, inst) end
	DB.Transaction(function()
		for id, inst in pairs(st.items) do
			cst.items[id] = inst
			DB.UpdateInst(inst, cst.loc, cst.locId)
		end
		st.items = {}
		local pk = RPInv.Carriers.Pockets(ply)
		if pk then
			for _, inst in SortedPairs(pk.items) do put(inst) end
			pk.items = {}
			RPInv.Push(pk)
		end
		for _, inst in pairs(s.weapons) do put(inst) end
		s.weapons = {}
		if J.Available() and ply.EZarmor and istable(ply.EZarmor.items) then
			for id, it in pairs(ply.EZarmor.items) do
				local def = it.name and J.EnsureDef(it.name)
				if def then
					local inst = { item = def.id, amount = 1, meta = J.MetaFromWorn(it, id), x = 0, y = 0, rot = 0 }
					DB.InsertInst(inst, cst.loc, cst.locId)
					if inst.id then
						put(inst)
						c.wornIds = c.wornIds or {}
						c.wornIds[inst.id] = true
					end
				end
			end
		end
	end)
	for _, inst in ipairs(spill) do
		RPInv.SpawnInstInWorld(inst, ply:GetPos() + Vector(math.random(-20, 20), math.random(-20, 20), 20))
		DB.DeleteInst(inst.id)
	end
	E.ClearArmorRows(ply)
	RPInv.Push(st)
	ply.RPInvCorpse = c
end

local function dumpCorpse(c, pos)
	local cst = RPInv.ContainerStorage(c)
	for _, inst in pairs(cst.items) do
		RPInv.SpawnInstInWorld(inst, pos + Vector(math.random(-24, 24), math.random(-24, 24), 20))
	end
	RPInv.DeleteContainer(c.id)
end

hook.Add("PlayerDeath", "RPInv_CorpseBody", function(ply)
	local c = ply.RPInvCorpse
	if not c then return end
	ply.RPInvCorpse = nil
	local pos = ply:GetPos()
	local nick = ply:Nick()
	timer.Simple(0, function()
		if not RPInv.Containers[c.id] then return end
		local rag
		for _, jc in ipairs(ents.FindByClass("ent_jack_gmod_ezcorpse")) do
			if jc.DeadPlayer == ply and IsValid(jc.EZragdoll) then rag = jc.EZragdoll end
		end
		if not IsValid(rag) and IsValid(ply) then
			local old = ply:GetRagdollEntity()
			rag = E.SpawnBody(ply)
			if IsValid(rag) and IsValid(old) then old:Remove() end
		end
		if not IsValid(rag) then
			dumpCorpse(c, pos)
			return
		end
		c.ent = rag
		if IsValid(ply) and not ply:Alive() then ply:SetNW2Entity("RPInvBody", rag) end
		rag.RPInvCorpseId = c.id
		rag:SetNW2String("RPInvCorpse", nick)
		E.UpdateCorpseVisual(c)
		rag:CallOnRemove("RPInvCorpse", function()
			if RPInv.Containers[c.id] then RPInv.DeleteContainer(c.id) end
		end)
		timer.Create("RPInv_Corpse" .. c.id, (RPInv.Settings.corpse_time or 5) * 60, 1, function()
			if IsValid(rag) then rag:Remove() elseif RPInv.Containers[c.id] then RPInv.DeleteContainer(c.id) end
		end)
	end)
end)

function E.UpdateCorpseVisual(c)
	if not c or not IsValid(c.ent) or not c.wornIds then return end
	local cst = RPInv.Storages["c:" .. c.id]
	if not cst then return end
	local list = {}
	for id in pairs(c.wornIds) do
		local inst = cst.items[id]
		local def = inst and RPInv.Items[inst.item]
		if def and def.jmod_armor ~= "" then
			local col = inst.meta.jmod and inst.meta.jmod.col
			list[#list + 1] = { n = def.jmod_armor, c = col and { col.r, col.g, col.b } or nil }
		else
			c.wornIds[id] = nil
		end
	end
	local s = util.TableToJSON(list)
	if c.LastVisual ~= s then
		c.LastVisual = s
		c.ent:SetNW2String("RPInvCorpseArmor", s)
	end
end

hook.Add("RPInv_StoragePushed", "RPInv_CorpseVisual", function(st)
	if st.loc ~= DB.LOC_CONTAINER then return end
	local c = RPInv.Containers[tonumber(st.locId)]
	if c and c.transient then E.UpdateCorpseVisual(c) end
end)

hook.Add("PlayerUse", "RPInv_CorpseUse", function(ply, ent)
	if not ent.RPInvCorpseId then return end
	if ply:KeyPressed(IN_USE) and RPInv.StartLoot and ply:GetInfoNum("rpinv_hold_e", 1) ~= 0 then RPInv.StartLoot(ply, ent) end
	return false
end)

hook.Add("DoPlayerDeath", "RPInv_EquipDeath", function(ply)
	timer.Remove("RPInv_EqSave" .. ply:EntIndex())
	ply.RPInvDeathWeapons = {}
	for _, inst in pairs(state(ply).weapons) do
		local def = weaponDef(inst)
		if def then
			ply.RPInvDeathWeapons[def.use_arg] = true
			E.NoDropSpawn(ply:GetWeapon(def.use_arg))
		end
	end
	if RPInv.Settings.death_mode == "corpse" then
		E.MakeCorpse(ply)
		ply.RPInvArmorPending = nil
		ply.RPInvRestore = nil
	elseif RPInv.Settings.death_mode == "drop" then
		E.DropAll(ply)
		ply.RPInvArmorPending = nil
		ply.RPInvRestore = nil
	else
		E.SaveArmor(ply)
		E.SaveAmmo(ply)
		ply.RPInvArmorPending = true
		ply.RPInvRestore = "death"
	end
end)

hook.Add("PostPlayerDeath", "RPInv_KeepArmor", function(ply)
	if RPInv.Settings.death_mode == "drop" or not J.Available() then return end
	timer.Simple(0, function()
		for _, c in ipairs(ents.FindByClass("ent_jack_gmod_ezcorpse")) do
			local rag = c.EZragdoll
			if c.DeadPlayer == ply and IsValid(rag) and istable(rag.EZarmorP) then
				for k, piece in pairs(rag.EZarmorP) do
					if IsValid(piece) then piece:Remove() end
					rag.EZarmorP[k] = nil
				end
			end
		end
	end)
end)

hook.Add("PlayerSpawn", "RPInv_EquipSpawn", function(ply)
	ply:SetNW2Entity("RPInvBody", NULL)
	timer.Simple(0.6, function()
		if not IsValid(ply) or not ply:Alive() then return end
		local reason = ply.RPInvRestore
		ply.RPInvRestore = nil
		if reason == "death" or (reason == "join" and RPInv.Settings.restore_armor) then
			E.RestoreArmor(ply)
		elseif reason == "join" then
			ply.RPInvArmorPending = nil
			E.SaveArmor(ply)
		end
		E.GiveWeapons(ply)
		if reason == "join" or reason == "death" then E.RestoreAmmo(ply) end
		E.GiveHands(ply, true)
		queuePush(ply)
	end)
end)

hook.Add("PlayerDroppedWeapon", "RPInv_EquippedDrop", function(ply, wep)
	if not IsValid(ply) or not ply:IsPlayer() or not IsValid(wep) then return end
	local cls = wep:GetClass()
	if not ply:Alive() and ply.RPInvDeathWeapons and ply.RPInvDeathWeapons[cls] then
		timer.Simple(0, function() if IsValid(wep) then wep:Remove() end end)
		return
	end
	local s = E.Cache[sid(ply)]
	if not s then return end
	for slot, inst in pairs(s.weapons) do
		local def = weaponDef(inst)
		if def and def.use_arg == cls then
			if ply:Alive() and s.weapons[slot] == inst then
				inst.meta.atts = wep.RPInvAttPending or RPInv.Att.Capture(wep)
				local meta = table.Copy(inst.meta)
				meta.clip1 = nil
				wep.RPInvMeta = meta
				s.weapons[slot] = nil
				DB.DeleteInst(inst.id)
				queuePush(ply)
			else
				timer.Simple(0, function() if IsValid(wep) then wep:Remove() end end)
			end
			return
		end
	end
end)

hook.Add("PlayerDisconnected", "RPInv_EquipLeave", function(ply)
	if ply:Alive() and not ply.RPInvSavedOnShutdown then
		E.SaveArmor(ply)
		E.SyncWeaponMeta(ply)
		E.SaveAmmo(ply)
	end
	E.Cache[sid(ply)] = nil
end)

hook.Add("RPInv_PlayerReady", "RPInv_EquipReady", function(ply)
	state(ply)
	queuePush(ply)
end)

hook.Add("RPInv_ItemDeleted", "RPInv_EquipPurge", function(id)
	for key, s in pairs(E.Cache) do
		for slot, inst in pairs(s.weapons) do
			if inst.item == id then s.weapons[slot] = nil end
		end
		for i = #s.armor, 1, -1 do
			if s.armor[i].item == id then table.remove(s.armor, i) end
		end
	end
	for _, p in ipairs(player.GetAll()) do queuePush(p) end
end)

timer.Create("RPInv_ArmorAutosave", 60, 0, function()
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and not p.RPInvArmorPending then E.SaveArmor(p) end
		if p:Alive() then
			E.SyncWeaponMeta(p)
			E.SaveAmmo(p)
		end
	end
end)

function E.QMenuToItem(ply, wep)
	if not IsValid(ply) or not IsValid(wep) or wep:GetOwner() ~= ply or not ply:Alive() then return end
	local cls = wep:GetClass()
	if NO_DROP[cls] then return end
	local s = state(ply)
	for _, inst in pairs(s.weapons) do
		local d = weaponDef(inst)
		if d and d.use_arg == cls then return end
	end
	local def = RPInv.WeaponDefFor(wep)
	if not def then return end
	local meta = {}
	local clip = wep:Clip1()
	if clip and clip >= 0 then meta.clip1 = clip end
	local slot = RPInv.EquipSlotOf(def)
	if slot and not s.weapons[slot] then
		local inst = { item = def.id, amount = 1, meta = meta, x = 0, y = 0, rot = 0, slot = slot }
		DB.InsertInst(inst, DB.LOC_EQUIP, sid(ply))
		if not inst.id then return end
		s.weapons[slot] = inst
		queuePush(ply)
		RPInv.Notify(ply, "Equipped: " .. def.name, 1)
		hook.Run("RPInv_ItemAdded", ply, def.id, 1)
		return
	end
	local st = RPInv.PlayerStorage(ply)
	if RPInv.GiveToPlayer(ply, def.id, 1, meta) > 0 then
		RPInv.Notify(ply, "No room for " .. def.name .. ": it stays in MISC.", 2)
		return
	end
	E.NoDropSpawn(wep)
	ply:StripWeapon(cls)
	RPInv.Push(st)
	RPInv.Notify(ply, "Added to the inventory: " .. def.name, 1)
	hook.Run("RPInv_ItemAdded", ply, def.id, 1)
end

hook.Add("PlayerGiveSWEP", "RPInv_QMenuMark", function(ply, cls)
	if RPInv.Settings.qmenu_weapons and IsValid(ply) then ply.RPInvQGive = { cls = cls, t = CurTime() } end
end)

hook.Add("WeaponEquip", "RPInv_QMenuToItem", function(wep, ply)
	local q = IsValid(ply) and ply.RPInvQGive
	if not q or not IsValid(wep) or q.cls ~= wep:GetClass() or CurTime() - q.t > 1 then return end
	ply.RPInvQGive = nil
	timer.Simple(0, function() E.QMenuToItem(ply, wep) end)
end)

hook.Add("ShutDown", "RPInv_EquipShutdown", function()
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and not p.RPInvArmorPending then
			E.SaveArmor(p)
			E.SyncWeaponMeta(p)
			E.SaveAmmo(p)
			p.RPInvSavedOnShutdown = true
		end
	end
end)
