local DB = RPInv.DB
local AM = RPInv.Ammo or {}
RPInv.Ammo = AM

local S = RPInv.Settings
S.ammo_items = DB.GetSetting("ammo_items", "0") == "1"
S.ammo_stack = math.Clamp(tonumber(DB.GetSetting("ammo_stack", "60")) or 60, 1, 999)
S.ammo_ignore = DB.GetSetting("ammo_ignore", "")

AM.SYNC = 0.25

local MODELS = {
	{ "buckshot", "models/items/boxbuckshot.mdl" },
	{ "shotgun", "models/items/boxbuckshot.mdl" },
	{ "gauge", "models/items/boxbuckshot.mdl" },
	{ "357", "models/items/357ammo.mdl" },
	{ "magnum", "models/items/357ammo.mdl" },
	{ "pistol", "models/items/boxsrounds.mdl" },
	{ "9mm", "models/items/boxsrounds.mdl" },
	{ "45", "models/items/boxsrounds.mdl" },
	{ "ar2", "models/items/combine_rifle_cartridge01.mdl" },
	{ "rpg", "models/weapons/w_missile_closed.mdl" },
	{ "rocket", "models/weapons/w_missile_closed.mdl" },
	{ "grenade", "models/items/grenadeammo.mdl" },
	{ "xbowbolt", "models/items/crossbowrounds.mdl" },
}

local function modelFor(name)
	local l = string.lower(name)
	for _, m in ipairs(MODELS) do
		if string.find(l, m[1], 1, true) then return m[2] end
	end
	return "models/items/boxmrounds.mdl"
end

local dirty = false
local function itemsChanged()
	if dirty then return end
	dirty = true
	timer.Simple(0, function()
		dirty = false
		RPInv.SendItems()
	end)
end

local byType = {}

function AM.DefFor(ammoId)
	local name = game.GetAmmoName(ammoId)
	if not name then return nil end
	local cached = byType[name]
	if cached and RPInv.Items[cached.id] == cached then return cached end
	for _, d in pairs(RPInv.Items) do
		if d.use_type == "rounds" and d.use_arg == name then
			byType[name] = d
			return d
		end
	end
	local id = string.sub("rounds_" .. string.gsub(string.lower(name), "[^a-z0-9_]", "_"), 1, 32)
	if RPInv.Items[id] then id = string.sub(id, 1, 28) .. "_" .. ammoId end
	local def = {
		id = id, name = string.sub(name .. " rounds", 1, 40), model = modelFor(name),
		descr = "Loose " .. name .. " ammunition. Your weapons reload from the rounds you carry.",
		max_stack = S.ammo_stack, use_type = "rounds", use_arg = name, w = 1, h = 1, rotatable = true,
		equip_slot = "", grid_w = 0, grid_h = 0, jmod_armor = "", world_class = "",
		cam_ang = "0 0 0", cam_fov = 1, cam_off = "", category = "Ammo",
	}
	RPInv.Items[id] = def
	DB.SaveItem(def)
	itemsChanged()
	byType[name] = def
	return def
end

local function inventoryRounds(ply)
	local out = {}
	for _, st in ipairs(RPInv.PlayerStorages(ply)) do
		for _, inst in pairs(st.items) do
			local def = RPInv.Items[inst.item]
			if def and def.use_type == "rounds" then
				local aid = game.GetAmmoID(def.use_arg)
				if aid and aid >= 0 then out[aid] = (out[aid] or 0) + inst.amount end
			end
		end
	end
	return out
end

local function takeRounds(ply, aid, n)
	local name = game.GetAmmoName(aid)
	if not name then return 0 end
	local taken = 0
	local list = RPInv.PlayerStorages(ply)
	for i = #list, 1, -1 do
		local st = list[i]
		local touched = false
		for id, inst in SortedPairs(st.items) do
			if taken >= n then break end
			local def = RPInv.Items[inst.item]
			if def and def.use_type == "rounds" and def.use_arg == name then
				local k = math.min(inst.amount, n - taken)
				taken = taken + k
				if k >= inst.amount then
					RPInv.InstRemove(st, inst)
				else
					inst.amount = inst.amount - k
					RPInv.InstSave(st, inst)
				end
				touched = true
			end
		end
		if touched then RPInv.Push(st) end
		if taken >= n then break end
	end
	return taken
end

local function giveRounds(ply, aid, n)
	local def = AM.DefFor(aid)
	if not def then return n end
	local left = RPInv.GiveToPlayer(ply, def.id, n)
	if left > 0 then
		RPInv.SpawnWorldItem(def.id, left, ply:GetPos() + Vector(0, 0, 24))
		RPInv.Notify(ply, "No room for " .. left .. " " .. def.name .. ": dropped at your feet.", 2)
	end
	return left
end

local function ignored(aid)
	local name = game.GetAmmoName(aid)
	if not name then return true end
	local l = string.lower(name)
	for t in string.gmatch(string.lower(S.ammo_ignore or ""), "[^,]+") do
		if string.Trim(t) == l then return true end
	end
	return false
end
AM.Ignored = ignored

local FIGHT_WINDOW = 2
local FIGHT_LIMIT = 3

local function apply(ply, set, aid, n)
	if ply:GetAmmoCount(aid) ~= n then
		if n < ply:GetAmmoCount(aid) then
			ply.RPInvAmmoCut = ply.RPInvAmmoCut or {}
			ply.RPInvAmmoCut[aid] = CurTime()
		end
		ply:SetAmmo(n, aid)
	end
	set[aid] = ply:GetAmmoCount(aid)
end

function AM.Sync(ply)
	if not ply:Alive() or ply:IsBot() then return end
	local set = ply.RPInvAmmoSet
	local pool = ply:GetAmmo()
	local skip = ply.RPInvAmmoSkip or {}
	ply.RPInvAmmoSkip = skip
	if not set then
		set = {}
		ply.RPInvAmmoSet = set
		local inv = inventoryRounds(ply)
		for aid in pairs(pool) do
			if not skip[aid] and not ignored(aid) then apply(ply, set, aid, inv[aid] or 0) end
		end
		for aid, n in pairs(inv) do
			if not skip[aid] and not ignored(aid) then apply(ply, set, aid, n) end
		end
		return
	end
	local now = CurTime()
	local seen = {}
	for aid, cur in pairs(pool) do
		seen[aid] = true
		if not skip[aid] and not ignored(aid) then
			local last = set[aid] or 0
			if cur < last then
				takeRounds(ply, aid, last - cur)
			elseif cur > last then
				local cut = ply.RPInvAmmoCut and ply.RPInvAmmoCut[aid]
				if cut and now - cut < FIGHT_WINDOW then
					ply.RPInvAmmoFights = ply.RPInvAmmoFights or {}
					local f = ply.RPInvAmmoFights[aid]
					if not f or now - f.t > 20 then f = { n = 0, t = now } end
					f.n = f.n + 1
					ply.RPInvAmmoFights[aid] = f
					if f.n >= FIGHT_LIMIT then
						skip[aid] = true
						set[aid] = nil
						RPInv.Notify(ply, (game.GetAmmoName(aid) or "This ammo") .. " is managed by your weapon base here, so it stays out of the inventory.", 0)
					end
				else
					giveRounds(ply, aid, cur - last)
				end
			end
		end
	end
	for aid, last in pairs(set) do
		if not seen[aid] and last > 0 and not skip[aid] then takeRounds(ply, aid, last) end
	end
	local inv = inventoryRounds(ply)
	for aid in pairs(set) do
		if not inv[aid] and not skip[aid] then
			apply(ply, set, aid, 0)
			set[aid] = nil
		end
	end
	for aid, n in pairs(inv) do
		if not skip[aid] and not ignored(aid) then apply(ply, set, aid, n) end
	end
end

timer.Create("RPInv_AmmoSync", AM.SYNC, 0, function()
	if not S.ammo_items then return end
	for _, ply in ipairs(player.GetAll()) do
		if ply.RPInvReady then AM.Sync(ply) end
	end
end)

hook.Add("PlayerSpawn", "RPInv_AmmoReset", function(ply)
	ply.RPInvAmmoSet = nil
end)

hook.Add("PlayerDeath", "RPInv_AmmoReset", function(ply)
	ply.RPInvAmmoSet = nil
end)

function AM.Reprice()
	for _, d in pairs(RPInv.Items) do
		if d.use_type == "rounds" and d.max_stack ~= S.ammo_stack then
			d.max_stack = S.ammo_stack
			DB.SaveItem(d)
		end
	end
	itemsChanged()
end

local BATTERY = { id = "suit_battery", name = "Suit Battery", model = "models/items/battery.mdl", descr = "Suit charge taken out of your armor. Use it to put 15 armor back.",
	max_stack = 5, use_type = "armor", use_arg = "15", w = 1, h = 1, rotatable = true, equip_slot = "", grid_w = 0, grid_h = 0,
	jmod_armor = "", world_class = "", cam_ang = "0 0 0", cam_fov = 1, cam_off = "", category = "Medical" }

concommand.Add("rpinv_suit_battery", function(ply)
	if not IsValid(ply) or not ply:Alive() then return end
	if (ply.RPInvNextBattery or 0) > CurTime() then return end
	ply.RPInvNextBattery = CurTime() + 0.5
	if ply:Armor() < 15 then RPInv.Notify(ply, "You need at least 15 suit armor.", 2) return end
	if not RPInv.Items[BATTERY.id] then
		RPInv.Items[BATTERY.id] = table.Copy(BATTERY)
		DB.SaveItem(RPInv.Items[BATTERY.id])
		itemsChanged()
	end
	if RPInv.GiveToPlayer(ply, BATTERY.id, 1) > 0 then RPInv.Notify(ply, "No room for a battery.", 2) return end
	ply:SetArmor(ply:Armor() - 15)
	ply:EmitSound("items/battery_pickup.wav", 60, 90)
	RPInv.Notify(ply, "Took 15 armor out as a Suit Battery.", 1)
end, nil, "Turn 15 suit armor into a Suit Battery item")
