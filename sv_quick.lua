local DB = RPInv.DB
local K = RPInv.Carriers
local J = RPInv.JM
local Q = RPInv.Quick or {}
RPInv.Quick = Q

util.AddNetworkString("rpinv_quick")

Q.COUNT = 5
local QUICK_TYPES = { heal = true, armor = true, ammo = true, throw = true, place = true, flare = true }
local STORE_CATS = {
	["JMod - EZ Explosives"] = "Explosives", ["JMod - EZ Misc."] = "Misc", ["JMod - EZ Misc"] = "Misc",
	["JMod - EZ Special Ammo"] = "Ammo",
}

local itemsDirty = false
local function itemsChanged()
	if itemsDirty then return end
	itemsDirty = true
	timer.Simple(0, function()
		itemsDirty = false
		RPInv.SendItems()
	end)
end

function Q.ExplosiveClass(cls)
	if not isstring(cls) or string.find(cls, "nuke", 1, true) then return false end
	local full = scripted_ents.Get(cls)
	if not full or not full.JModEZstorable or not STORE_CATS[full.Category] then return false end
	return true, scripted_ents.IsBasedOn(cls, "ent_jack_gmod_ezgrenade"), STORE_CATS[full.Category]
end

function Q.JModWeaponFor(ent)
	if not IsValid(ent) or not ent.JModEZstorable then return nil end
	if istable(ent.Specs) and isstring(ent.Specs.swep) and weapons.GetStored(ent.Specs.swep) then return ent.Specs.swep end
	local cls = ent:GetClass()
	if string.sub(cls, 1, 4) ~= "ent_" then return nil end
	local w = "wep_" .. string.sub(cls, 5)
	if weapons.GetStored(w) then return w end
end

local function storeJModWeapon(ply, ent, cls)
	local def = RPInv.WeaponDefForClass(cls)
	if not def then return false end
	local full = weapons.Get(cls)
	local meta = {}
	local size = full and full.Primary and tonumber(full.Primary.ClipSize) or -1
	if size and size > 0 then
		meta.clip1 = ent.HasSpawnAmmo and size or math.Clamp(tonumber(ent.MagRounds) or 0, 0, size)
	end
	local st = RPInv.PlayerStorage(ply)
	if RPInv.GiveToPlayer(ply, def.id, 1, meta) > 0 then
		RPInv.Notify(ply, "Not enough space for " .. def.name .. ".", 2)
		return true
	end
	ent.RPInvTaken = true
	ent:Remove()
	RPInv.Push(st)
	ply:EmitSound("items/ammo_pickup.wav", 60)
	RPInv.Notify(ply, "Picked up: " .. def.name, 1)
	hook.Run("RPInv_ItemAdded", ply, def.id, 1)
	return true
end

hook.Add("PlayerUse", "RPInv_JModWeaponPickup", function(ply, ent)
	if not IsValid(ent) or ent.RPInvTaken then return end
	local cls = Q.JModWeaponFor(ent)
	if not cls then return end
	local mode = RPInv.Settings.jmod_pickup
	if mode == "off" then return end
	if JMod and isfunction(JMod.IsAltUsing) and JMod.IsAltUsing(ply) then return end
	if not ((mode == "plain") or (mode == "shift" and ply:KeyDown(IN_SPEED))) then return end
	if not ply:KeyPressed(IN_USE) then return false end
	storeJModWeapon(ply, ent, cls)
	return false
end)

local function sizeFor(ent)
	local s = ent:OBBMaxs() - ent:OBBMins()
	local long = math.max(s.x, s.y, s.z)
	if long <= 9 then return 1, 1 end
	if long <= 16 then return 2, 1 end
	if long <= 26 then return 2, 2 end
	return 3, 2
end

function Q.EntityDefFor(ent)
	local cls = ent:GetClass()
	for _, d in SortedPairs(RPInv.Items) do
		if d.world_class == cls and (d.jmod_armor or "") == "" then return d end
	end
	local ok, grenade, cat = Q.ExplosiveClass(cls)
	if not ok or Q.JModWeaponFor(ent) then return nil end
	local full = scripted_ents.Get(cls)
	local name = isstring(full.PrintName) and full.PrintName ~= "" and full.PrintName or cls
	local w, h = sizeFor(ent)
	local id = string.sub("jent_" .. string.gsub(string.lower(cls), "[^a-z0-9_]", "_"), 1, 32)
	local def = {
		id = id, name = string.sub(name, 1, 40), model = ent:GetModel(),
		descr = grenade and "JMod grenade. Put it in a quick slot and press the key twice to throw it armed." or "JMod item. Use it to place it in front of you, then use it the JMod way.",
		max_stack = grenade and 3 or 1, use_type = grenade and "throw" or "place", use_arg = cls,
		w = w, h = h, rotatable = true, equip_slot = "", grid_w = 0, grid_h = 0, jmod_armor = "", world_class = cls,
		cam_ang = "0 0 0", cam_fov = 1, category = grenade and "Grenades" or (cat or "Explosives"),
	}
	RPInv.Items[id] = def
	DB.SaveItem(def)
	DB.Log(nil, "explosive_item_auto", id)
	itemsChanged()
	return def
end

local function entClass(def)
	local cls = (def.world_class ~= "" and def.world_class) or def.use_arg
	if cls == "prop_physics" then return cls end
	if isstring(cls) and scripted_ents.GetStored(cls) then return cls end
end

local function setOwner(ent, ply)
	if JMod and isfunction(JMod.SetEZowner) then JMod.SetEZowner(ent, ply) end
end

local function captureState(ent)
	local c = ent:GetColor()
	return {
		hp = ent:Health(), mhp = ent:GetMaxHealth(), col = { c.r, c.g, c.b, c.a },
		mat = ent:GetMaterial(), skin = ent:GetSkin(),
	}
end

local function applyState(ent, s)
	if not istable(s) then return end
	if tonumber(s.mhp) and s.mhp > 0 then ent:SetMaxHealth(s.mhp) end
	if tonumber(s.hp) and s.hp > 0 then ent:SetHealth(s.hp) end
	if istable(s.col) then
		local a = tonumber(s.col[4]) or 255
		ent:SetColor(Color(tonumber(s.col[1]) or 255, tonumber(s.col[2]) or 255, tonumber(s.col[3]) or 255, a))
		if a < 255 then ent:SetRenderMode(RENDERMODE_TRANSCOLOR) end
	end
	if isstring(s.mat) and s.mat ~= "" then ent:SetMaterial(s.mat) end
	if tonumber(s.skin) then ent:SetSkin(s.skin) end
end

local function spawnFresh(cls, pos, ply)
	local stored = scripted_ents.GetStored(cls)
	local t = stored and stored.t
	local ent
	if t and isfunction(t.SpawnFunction) and IsValid(ply) then
		local tr = {
			Hit = true, HitWorld = true, HitPos = pos, HitNormal = Vector(0, 0, 1), Normal = Vector(0, 0, -1),
			StartPos = pos + Vector(0, 0, 64), Fraction = 0.5, Entity = game.GetWorld(),
		}
		local ok, res = pcall(t.SpawnFunction, t, ply, tr, cls)
		if ok and IsValid(res) then ent = res end
	end
	if not IsValid(ent) then
		ent = ents.Create(cls)
		if not IsValid(ent) then return nil end
		ent:SetPos(pos)
		ent:SetAngles(Angle(0, IsValid(ply) and ply:EyeAngles().y + 180 or math.random(0, 359), 0))
		ent:Spawn()
		ent:Activate()
	end
	if IsValid(ply) then
		if isfunction(ent.SetCreator) then ent:SetCreator(ply) end
		if isfunction(ent.CPPISetOwner) then ent:CPPISetOwner(ply) end
		setOwner(ent, ply)
		local name = (t and isstring(t.PrintName) and t.PrintName ~= "") and t.PrintName or cls
		undo.Create("SENT")
		undo.SetPlayer(ply)
		undo.AddEntity(ent)
		undo.SetCustomUndoText("Undone " .. name)
		undo.Finish("Scripted Entity (" .. name .. ")")
		ply:AddCleanup("sents", ent)
	end
	return ent
end

local function genericEntity(cls)
	return not Q.ExplosiveClass(cls)
end

local function spawnProp(def, pos, ply, meta)
	if not util.IsValidModel(def.model or "") then return nil end
	local ent = ents.Create("prop_physics")
	if not IsValid(ent) then return nil end
	ent:SetModel(def.model)
	ent:SetPos(pos)
	ent:SetAngles(Angle(0, IsValid(ply) and ply:EyeAngles().y + 180 or math.random(0, 359), 0))
	ent:Spawn()
	ent:Activate()
	ent:SetPos(pos - Vector(0, 0, ent:OBBMins().z))
	if IsValid(ply) then
		if isfunction(ent.SetCreator) then ent:SetCreator(ply) end
		if isfunction(ent.CPPISetOwner) then ent:CPPISetOwner(ply) end
		undo.Create("Prop")
		undo.SetPlayer(ply)
		undo.AddEntity(ent)
		undo.Finish("Prop (" .. def.model .. ")")
		ply:AddCleanup("props", ent)
	end
	if not RPInv.Settings.entity_fresh and meta then applyState(ent, meta.ent) end
	return ent
end

function RPInv.SpawnWorldEntity(def, pos, ply, meta)
	local cls = entClass(def)
	if not cls then return nil end
	if cls == "prop_physics" then return spawnProp(def, pos, ply, meta) end
	if genericEntity(cls) and RPInv.Settings.entity_fresh then return spawnFresh(cls, pos, ply) end
	local ent = ents.Create(cls)
	if not IsValid(ent) then return nil end
	ent:SetPos(pos)
	ent:SetAngles(Angle(0, math.random(0, 359), 0))
	if IsValid(ply) then
		setOwner(ent, ply)
		if isfunction(ent.CPPISetOwner) then ent:CPPISetOwner(ply) end
	end
	ent:Spawn()
	ent:Activate()
	if genericEntity(cls) and meta then applyState(ent, meta.ent) end
	return ent
end

function RPInv.ThrowEntity(ply, def)
	if ply:GetNW2Bool("RPInvSurrender", false) then return false, "You cannot do that with your hands up." end
	local cls = entClass(def)
	if not cls then return false, "This item cannot be thrown." end
	local eye, aim = ply:GetShootPos(), ply:GetAimVector()
	local tr = util.TraceLine({ start = eye, endpos = eye + aim * 24, filter = ply })
	local ent = ents.Create(cls)
	if not IsValid(ent) then return false, "This item cannot be thrown." end
	ent:SetPos(tr.HitPos - aim * 6)
	ent:SetAngles(aim:Angle())
	setOwner(ent, ply)
	ent:Spawn()
	ent:Activate()
	if isfunction(ent.Prime) then ent:Prime() end
	if isfunction(ent.Arm) then ent:Arm() end
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then
		phys:Wake()
		phys:SetVelocity(ply:GetVelocity() + aim * (tonumber(ent.HardThrowStr) or 600))
		phys:AddAngleVelocity(VectorRand() * 400)
	end
	ply:DoCustomAnimEvent(PLAYERANIMEVENT_CUSTOM_GESTURE, ACT_GMOD_GESTURE_ITEM_THROW)
	return true
end

function RPInv.PlaceEntity(ply, def, inst)
	if ply:GetNW2Bool("RPInvSurrender", false) then return false, "You cannot do that with your hands up." end
	local ent = RPInv.SpawnWorldEntity(def, RPInv.DropPos(ply), ply, inst and inst.meta)
	if not IsValid(ent) then return false, "This item cannot be placed." end
	ply:DoCustomAnimEvent(PLAYERANIMEVENT_CUSTOM_GESTURE, ACT_GMOD_GESTURE_ITEM_PLACE)
	return true
end

function RPInv.UseEntity(ply, def, inst)
	if ply:GetNW2Bool("RPInvSurrender", false) then return false, "You cannot do that with your hands up." end
	local cls = entClass(def)
	if not cls or cls == "prop_physics" then return false, "This item has no entity to use." end
	local ent = ents.Create(cls)
	if not IsValid(ent) then return false, "This item cannot be used." end
	ent:SetPos(RPInv.DropPos(ply))
	ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	setOwner(ent, ply)
	ent:Spawn()
	ent:Activate()
	if IsValid(ent) then
		ent:SetNoDraw(true)
		ent:SetCollisionGroup(COLLISION_GROUP_WORLD)
		if inst and inst.meta then applyState(ent, inst.meta.ent) end
	end
	if not IsValid(ent) or ent:IsMarkedForDeletion() then return true end
	local ok, err = pcall(ent.Use, ent, ply, ply, USE_ON, 1)
	if not ok then
		ErrorNoHalt("[RPInv] entity use failed for " .. cls .. ": " .. tostring(err) .. "\n")
		SafeRemoveEntity(ent)
		return false, "This item cannot be used."
	end
	if not IsValid(ent) or ent:IsMarkedForDeletion() then return true end
	SafeRemoveEntity(ent)
	return false, "Nothing happened."
end

hook.Add("PlayerUse", "RPInv_ExplosivePickup", function(ply, ent)
	if not IsValid(ent) or ent.RPInvTaken or not Q.ExplosiveClass(ent:GetClass()) or Q.JModWeaponFor(ent) then return end
	local mode = RPInv.Settings.jmod_pickup
	if mode == "off" then return end
	if JMod and isfunction(JMod.IsAltUsing) and JMod.IsAltUsing(ply) then return end
	if not ((mode == "plain") or (mode == "shift" and ply:KeyDown(IN_SPEED))) then return end
	if not ply:KeyPressed(IN_USE) then return false end
	if isfunction(ent.GetState) and JMod and ent:GetState() ~= (JMod.EZ_STATE_OFF or 0) then
		RPInv.Notify(ply, "Turn it off or disarm it first.", 2)
		return false
	end
	if isfunction(ent.IsPlayerHolding) and ent:IsPlayerHolding() then return false end
	local def = Q.EntityDefFor(ent)
	if not def then return end
	local st = RPInv.PlayerStorage(ply)
	if RPInv.GiveToPlayer(ply, def.id, 1) > 0 then
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

local function resourceMax(ent)
	local mult = JMod and JMod.Config and JMod.Config.ResourceEconomy and tonumber(JMod.Config.ResourceEconomy.MaxResourceMult) or 1
	return math.Clamp(math.floor(tonumber(IsValid(ent) and ent.MaxResource) or 100 * mult), 1, 999)
end

function Q.ResourceDefFor(ent)
	if not IsValid(ent) or not ent.IsJackyEZresource then return nil end
	local cls = ent:GetClass()
	for _, d in SortedPairs(RPInv.Items) do
		if d.use_type == "resource" and d.world_class == cls then return d end
	end
	local full = scripted_ents.Get(cls) or {}
	local name = isstring(full.PrintName) and full.PrintName ~= "" and full.PrintName or cls
	local model = ent:GetModel()
	if not isstring(model) or not util.IsValidModel(model) then return nil end
	local w, h = sizeFor(ent)
	local id = string.sub("jres_" .. string.gsub(string.lower(string.gsub(cls, "^ent_jack_gmod_ez", "")), "[^a-z0-9_]", "_"), 1, 32)
	local max = resourceMax(ent)
	local def = {
		id = id, name = string.sub(name, 1, 40), model = model,
		descr = "JMod resource. The stack is the number of units. Use it to place a box (up to " .. max .. " units).",
		max_stack = max, use_type = "resource", use_arg = cls, w = w, h = h, rotatable = true,
		equip_slot = "", grid_w = 0, grid_h = 0, jmod_armor = "", world_class = cls,
		cam_ang = "0 0 0", cam_fov = 1, cam_off = "", category = "Resources",
	}
	RPInv.Items[id] = def
	DB.SaveItem(def)
	DB.Log(nil, "resource_item_auto", id)
	itemsChanged()
	return def
end

local function spawnResource(def, pos, units, ply)
	local cls = def.world_class ~= "" and def.world_class or def.use_arg
	if not scripted_ents.GetStored(cls) then return nil end
	local ent = ents.Create(cls)
	if not IsValid(ent) then return nil end
	ent:SetPos(pos)
	ent:SetAngles(Angle(0, IsValid(ply) and ply:EyeAngles().y or math.random(0, 359), 0))
	if IsValid(ply) then setOwner(ent, ply) end
	ent:Spawn()
	ent:Activate()
	local n = math.min(units, resourceMax(ent))
	if isfunction(ent.SetEZsupplies) and ent.EZsupplies then ent:SetEZsupplies(ent.EZsupplies, n) end
	return ent, n
end

function RPInv.SpawnResource(def, pos, units, ply)
	local left = units
	local i = 0
	while left > 0 and i < 20 do
		i = i + 1
		local ent, n = spawnResource(def, pos + Vector(math.random(-8, 8), math.random(-8, 8), i * 6), left, ply)
		if not IsValid(ent) then break end
		left = left - n
	end
	return left < units
end

function RPInv.PlaceResource(ply, def, inst)
	if ply:GetNW2Bool("RPInvSurrender", false) then return false, "You cannot do that with your hands up." end
	local ent, n = spawnResource(def, RPInv.DropPos(ply), inst.amount, ply)
	if not IsValid(ent) then return false, "This resource cannot be placed." end
	inst.amount = inst.amount - n + 1
	ply:DoCustomAnimEvent(PLAYERANIMEVENT_CUSTOM_GESTURE, ACT_GMOD_GESTURE_ITEM_PLACE)
	return true
end

hook.Add("PlayerUse", "RPInv_ResourcePickup", function(ply, ent)
	if not IsValid(ent) or ent.RPInvTaken or not ent.IsJackyEZresource then return end
	local mode = RPInv.Settings.jmod_pickup
	if mode == "off" then return end
	if JMod and isfunction(JMod.IsAltUsing) and JMod.IsAltUsing(ply) then return end
	if not ((mode == "plain") or (mode == "shift" and ply:KeyDown(IN_SPEED))) then return end
	if not ply:KeyPressed(IN_USE) then return false end
	if ply:InVehicle() then return false end
	local units = isfunction(ent.GetResource) and math.floor(ent:GetResource()) or 0
	if units < 1 then return false end
	local def = Q.ResourceDefFor(ent)
	if not def then return end
	local st = RPInv.PlayerStorage(ply)
	local left = RPInv.GiveToPlayer(ply, def.id, units)
	local taken = units - left
	if taken <= 0 then
		RPInv.Notify(ply, "Not enough space for " .. def.name .. ".", 2)
		return false
	end
	if left > 0 then
		ent:SetEZsupplies(ent.EZsupplies, left)
	else
		ent.RPInvTaken = true
		ent:Remove()
	end
	RPInv.Push(st)
	ply:EmitSound("items/ammo_pickup.wav", 60)
	RPInv.Notify(ply, "Picked up: " .. def.name .. " x" .. taken .. (left > 0 and (" (" .. left .. " left in the box)") or ""), 1)
	hook.Run("RPInv_ItemAdded", ply, def.id, taken)
	return false
end)

util.AddNetworkString("rpinv_a_entitem")

local entDefs, entDefsAt = {}, 0

local function entKey(cls, model)
	if cls == "prop_physics" then return "prop:" .. string.lower(model or "") end
	return cls
end
Q.EntKey = entKey

local function entDefFor(key)
	if CurTime() - entDefsAt > 3 then
		entDefs, entDefsAt = {}, CurTime()
		for _, d in SortedPairs(RPInv.Items) do
			if (d.world_class or "") ~= "" and (d.jmod_armor or "") == "" and d.use_type ~= "resource" then
				local k = entKey(d.world_class, d.model)
				if not entDefs[k] then entDefs[k] = d end
			end
		end
	end
	return entDefs[key]
end

local function storableEntity(ent)
	if not IsValid(ent) or ent:IsPlayer() or ent:IsWeapon() or ent:IsVehicle() or ent:IsNPC() or ent:IsRagdoll() then return false end
	local cls = ent:GetClass()
	if cls == "prop_physics" then return true end
	if string.sub(cls, 1, 6) == "rpinv_" or not scripted_ents.GetStored(cls) then return false end
	if Q.ExplosiveClass(cls) or Q.JModWeaponFor(ent) or isstring(ent.ArmorName) or ent.IsJackyEZresource then return false end
	return true
end
Q.StorableEntity = storableEntity

hook.Add("PlayerUse", "RPInv_EntityPickup", function(ply, ent)
	if not IsValid(ent) or ent.RPInvTaken then return end
	local mode = RPInv.Settings.entity_pickup
	if mode == "off" or not storableEntity(ent) then return end
	local def = entDefFor(entKey(ent:GetClass(), ent:GetModel()))
	if not def then return end
	if not ((mode == "plain") or (mode == "shift" and ply:KeyDown(IN_SPEED))) then return end
	if not ply:KeyPressed(IN_USE) then return false end
	if ply:InVehicle() then return false end
	local owner = isfunction(ent.CPPIGetOwner) and ent:CPPIGetOwner() or nil
	if IsValid(owner) and owner ~= ply and not RPInv.IsAdmin(ply) then
		RPInv.Notify(ply, "This belongs to someone else.", 2)
		return false
	end
	local meta = (not RPInv.Settings.entity_fresh) and { ent = captureState(ent) } or nil
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

local function freeId(base)
	base = string.sub(base, 1, 32)
	if not RPInv.Items[base] then return base end
	for i = 2, 99 do
		local id = string.sub(base, 1, 32 - #tostring(i) - 1) .. "_" .. i
		if not RPInv.Items[id] then return id end
	end
end

function Q.MakeItemFrom(ply, ent)
	if not IsValid(ent) then return false, "Aim at an entity or a prop first." end
	if not storableEntity(ent) then
		return false, "This can't become an item. Players, NPCs, vehicles, weapons, ragdolls and JMod items are handled elsewhere."
	end
	local cls = ent:GetClass()
	local model = ent:GetModel()
	if not isstring(model) or not model:lower():match("%.mdl$") or not util.IsValidModel(model) then
		return false, "This entity has no usable model for an icon."
	end
	local old = entDefFor(entKey(cls, model))
	if old then return false, "This already is the item " .. old.id .. "." end
	local name, id, descr, cat
	if cls == "prop_physics" then
		local base = string.GetFileFromFilename(model):gsub("%.mdl$", "")
		name = base:gsub("_", " ")
		id = freeId("prop_" .. string.gsub(string.lower(base), "[^a-z0-9_]", "_"))
		descr = "Prop: " .. model .. ". Use it to place it in front of you."
		cat = "Props"
	else
		local full = scripted_ents.Get(cls) or {}
		name = isstring(full.PrintName) and full.PrintName ~= "" and string.sub(full.PrintName, 1, 1) ~= "#" and full.PrintName or cls
		id = freeId("ent_" .. string.gsub(string.lower(cls), "[^a-z0-9_]", "_"))
		descr = "Entity: " .. cls .. ". Use it to place it in front of you."
		cat = "Entities"
	end
	if not id then return false, "No free item ID." end
	local w, h = sizeFor(ent)
	local def = {
		id = id, name = string.sub(name, 1, 40), model = model, descr = descr:sub(1, 200),
		max_stack = 1, use_type = "place", use_arg = cls, w = w, h = h, rotatable = true, equip_slot = "", grid_w = 0, grid_h = 0,
		jmod_armor = "", world_class = cls, cam_ang = "0 0 0", cam_fov = 1, cam_off = "", category = cat,
	}
	RPInv.Items[id] = def
	DB.SaveItem(def)
	DB.Log(ply, "entity_item_add", id)
	entDefsAt = 0
	RPInv.SendItems()
	return true, def
end

net.Receive("rpinv_a_entitem", function(_, ply)
	if not RPInv.IsAdmin(ply) then return end
	local tr = ply:GetEyeTrace()
	if tr.HitPos:DistToSqr(ply:GetShootPos()) > 600 * 600 then RPInv.Notify(ply, "Aim at an entity first.", 2) return end
	local ok, res = Q.MakeItemFrom(ply, tr.Entity)
	if not ok then RPInv.Notify(ply, res, 2) return end
	RPInv.Notify(ply, "Item created: " .. res.name .. " (" .. res.id .. "). Players can now store it with " .. (RPInv.Settings.entity_pickup == "plain" and "E" or "SHIFT+E") .. ".", 1)
end)

local function settingKey(ply) return "quick_" .. RPInv.SID(ply) end

function Q.Get(ply)
	if not ply.RPInvQuick then
		ply.RPInvQuick = util.JSONToTable(DB.GetSetting(settingKey(ply), "") or "") or {}
	end
	return ply.RPInvQuick
end

function Q.Push(ply)
	RPInv.SendJSON("rpinv_quick", { slots = Q.Get(ply) }, ply)
end

local function setSlot(ply, n, id)
	local q = Q.Get(ply)
	q["s" .. n] = id
	DB.SetSetting(settingKey(ply), util.TableToJSON(q))
	Q.Push(ply)
end

function Q.Storages(ply)
	local list = {}
	local pk = K.Pockets(ply)
	if pk then list[#list + 1] = pk end
	for _, w in ipairs(J.WornList(ply)) do
		local def = RPInv.Items[w.item]
		if RPInv.IsCarrierDef(def) then list[#list + 1] = K.Storage(w.key, def) end
	end
	list[#list + 1] = RPInv.PlayerStorage(ply)
	return list
end

local Actions = RPInv.Actions

function RPInv.HandleOf(st)
	if not st then return nil end
	if st.loc == DB.LOC_PLAYER then return "p" end
	if st.loc == DB.LOC_CARRIER then return "k:" .. tostring(st.locId) end
	if st.loc == DB.LOC_CONTAINER then return "c:" .. tostring(st.locId) end
end

Actions.quickbind = function(ply, t)
	local n = RPInv.Int(t.slot, 1, Q.COUNT)
	local def = n and RPInv.Items[tostring(t.item or "")]
	if not def then return false end
	if def.use_type == "none" and not QUICK_TYPES[def.use_type] then return "This item does nothing when used, so it cannot go into a quick slot." end
	setSlot(ply, n, def.id)
	return true
end

Actions.quickclear = function(ply, t)
	local n = RPInv.Int(t.slot, 1, Q.COUNT)
	if n then setSlot(ply, n, nil) end
	return true
end

Actions.quickuse = function(ply, t, touch)
	local n = RPInv.Int(t.slot, 1, Q.COUNT)
	local id = n and Q.Get(ply)["s" .. n]
	local def = id and RPInv.Items[id]
	if not def then return "This quick slot is empty." end
	if ply:GetNW2Bool("RPInvSurrender", false) then return false end
	if def.use_type == "weapon" and def.use_arg ~= "" then
		if ply:InVehicle() then return RPInv.VEHICLE_MSG end
		if ply:HasWeapon(def.use_arg) then
			ply:SelectWeapon(def.use_arg)
			return true
		end
	end
	for _, st in ipairs(Q.Storages(ply)) do
		for _, inst in SortedPairs(st.items) do
			if inst.item == id then
				touch(st)
				local slotKey = def.use_type == "weapon" and RPInv.EquipSlotOf(def)
				local free = slotKey and RPInv.Equip and not RPInv.Equip.State(ply).weapons[slotKey]
				if free and RPInv.Actions.equip then
					local res = RPInv.Actions.equip(ply, { from = RPInv.HandleOf(st) or "p", id = inst.id }, touch)
					if res == true then
						timer.Simple(0.1, function() if IsValid(ply) and ply:HasWeapon(def.use_arg) then ply:SelectWeapon(def.use_arg) end end)
						return true
					end
				end
				local res = RPInv.UseInst(ply, st, inst, true)
				if res == true and def.use_type == "weapon" then
					timer.Simple(0.1, function() if IsValid(ply) and ply:HasWeapon(def.use_arg) then ply:SelectWeapon(def.use_arg) end end)
				end
				return res
			end
		end
	end
	return "No " .. def.name .. " left."
end

hook.Add("RPInv_PlayerReady", "RPInv_QuickReady", function(ply)
	Q.Push(ply)
end)

hook.Add("PlayerDisconnected", "RPInv_QuickLeave", function(ply)
	ply.RPInvQuick = nil
end)
