local DB = RPInv.DB
local K = RPInv.Carriers or {}
RPInv.Carriers = K

local MAXID = 2147483647
local int = RPInv.Int

function K.NewCid()
	local chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
	local out = {}
	for i = 1, 10 do
		local n = math.random(1, #chars)
		out[i] = string.sub(chars, n, n)
	end
	return table.concat(out)
end

function K.GridForStorage(n)
	n = tonumber(n) or 0
	if n <= 0 then return 0, 0 end
	if n <= 5 then return 3, 2 end
	if n <= 10 then return 4, 2 end
	if n <= 20 then return 4, 4 end
	if n <= 30 then return 5, 5 end
	return 6, 6
end

function K.Storage(cid, def)
	local key = "k:" .. cid
	local st = RPInv.Storages[key]
	if not st then
		st = RPInv.NewStorage(DB.LOC_CARRIER, cid, def.grid_w, def.grid_h, def.name)
		RPInv.LoadStorage(st)
		RPInv.Storages[key] = st
	elseif st.w ~= def.grid_w or st.h ~= def.grid_h then
		st.w, st.h = def.grid_w, def.grid_h
		RPInv.Revalidate(st)
	end
	st.name = def.name
	return st
end

local function scan(st, cid)
	if not st then return nil end
	for _, inst in pairs(st.items) do
		if inst.meta.cid == cid then
			local def = RPInv.Items[inst.item]
			if RPInv.IsCarrierDef(def) then return def, inst end
		end
	end
end

function K.PocketsCid(ply)
	return "pk_" .. string.gsub(RPInv.SID(ply), "[^%w_]", "_")
end

function K.PocketsDef()
	local S = RPInv.Settings
	return { grid_w = S.pockets_w or 4, grid_h = S.pockets_h or 1, name = "POCKETS" }
end

function K.WornDef(ply, cid)
	if cid == K.PocketsCid(ply) then
		local pd = K.PocketsDef()
		if pd.grid_w > 0 and pd.grid_h > 0 then return pd end
		return nil
	end
	if not RPInv.JModAvailable() or not istable(ply.EZarmor) or not istable(ply.EZarmor.items) then return nil end
	local it = ply.EZarmor.items[cid]
	if not it or not it.name then return nil end
	local def = RPInv.JM.DefFor(it.name)
	if RPInv.IsCarrierDef(def) then return def end
end

function K.Pockets(ply)
	local pd = K.PocketsDef()
	if pd.grid_w <= 0 or pd.grid_h <= 0 then return nil end
	return K.Storage(K.PocketsCid(ply), pd)
end

function K.Find(ply, cid)
	local def = K.WornDef(ply, cid)
	if def then return def, "worn" end
	def = scan(RPInv.PlayerStorage(ply), cid)
	if def then return def, "held" end
	if ply.RPInvOpen and RPInv.ContainerAccess then
		def = scan(RPInv.ContainerAccess(ply, ply.RPInvOpen), cid)
		if def then return def, "near" end
	end
end

function RPInv.CarrierAccess(ply, cid)
	if not ply:Alive() then return nil end
	local def = K.Find(ply, cid)
	if not def then
		if ply.RPInvKVis then ply.RPInvKVis[cid] = nil end
		return nil
	end
	return K.Storage(cid, def)
end

function K.Watch(ply, cid, def)
	ply.RPInvKVis = ply.RPInvKVis or {}
	ply.RPInvKVis[cid] = true
	RPInv.Push(K.Storage(cid, def), ply)
end

local Actions = RPInv.Actions

Actions.open = function(ply, t, touch)
	local src = RPInv.Access(ply, t.from)
	local inst = src and src.items[int(t.id, 1, MAXID) or -1]
	if not inst then return false end
	local def = RPInv.Items[inst.item]
	if not RPInv.IsCarrierDef(def) then return "This item has no storage." end
	if src.loc == DB.LOC_CARRIER then return false end
	if not inst.meta.cid then
		inst.meta.cid = K.NewCid()
		RPInv.InstSave(src, inst)
		touch(src)
	end
	K.Watch(ply, inst.meta.cid, def)
	return true
end

Actions.kclose = function(ply, t)
	local cid = string.match(tostring(t.cid or ""), "^[%w_]+$")
	if cid and ply.RPInvKVis then ply.RPInvKVis[cid] = nil end
	return true
end

hook.Add("RPInv_EquipPushed", "RPInv_CarrierPush", function(ply, worn)
	local pk = K.Pockets(ply)
	if pk then K.Watch(ply, K.PocketsCid(ply), K.PocketsDef()) end
	for _, w in ipairs(worn) do
		local def = RPInv.Items[w.item]
		if RPInv.IsCarrierDef(def) then K.Watch(ply, w.key, def) end
	end
end)

hook.Add("InitPostEntity", "RPInv_SeedCarrierGrids", function()
	timer.Simple(1, function()
		if not RPInv.JModAvailable() or DB.GetSetting("jmod_carriers_seeded", "0") == "1" then return end
		DB.Transaction(function()
			for _, def in pairs(RPInv.Items) do
				local info = def.jmod_armor ~= "" and JMod.ArmorTable[def.jmod_armor]
				if info and info.storage and (def.grid_w or 0) == 0 then
					def.grid_w, def.grid_h = K.GridForStorage(info.storage)
					DB.SaveItem(def)
				end
			end
		end)
		DB.SetSetting("jmod_carriers_seeded", "1")
		RPInv.SendItems()
	end)
end)
