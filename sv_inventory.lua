local DB = RPInv.DB
local G = RPInv.Grid
DB.Init()

RPInv.Items = DB.LoadItems()
RPInv.Storages = RPInv.Storages or {}
local function gridSize(w, h)
	w, h = math.floor(tonumber(w) or 10), math.floor(tonumber(h) or 6)
	if w <= 0 or h <= 0 then return 0, 0 end
	return math.Clamp(w, 4, 20), math.Clamp(h, 2, 20)
end
RPInv.GridSize = gridSize

local gw0, gh0 = gridSize(DB.GetSetting("player_grid_w", "10"), DB.GetSetting("player_grid_h", "6"))

RPInv.Settings = {
	player_grid_w = gw0,
	player_grid_h = gh0,
	death_mode = ({ keep = "keep", drop = "drop", corpse = "corpse" })[DB.GetSetting("death_mode", "corpse")] or "corpse",
	corpse_time = math.Clamp(tonumber(DB.GetSetting("corpse_time", "5")) or 5, 1, 60),
	restore_armor = DB.GetSetting("restore_armor", "1") ~= "0",
	jmod_pickup = ({ shift = "shift", plain = "plain", off = "off" })[DB.GetSetting("jmod_pickup", "shift")] or "shift",
	search_mode = ({ surrender = "surrender", anyone = "anyone", admin = "admin" })[DB.GetSetting("search_mode", "surrender")] or "surrender",
	search_time = math.Clamp(tonumber(DB.GetSetting("search_time", "4")) or 4, 1, 30),
	search_equipment = DB.GetSetting("search_equipment", "1") ~= "0",
	loot_time = math.Clamp(tonumber(DB.GetSetting("loot_time", "2")) or 2, 0, 15),
	weapon_touch_pickup = DB.GetSetting("weapon_touch_pickup", "0") == "1",
	pockets_w = math.Clamp(tonumber(DB.GetSetting("pockets_w", "4")) or 4, 0, 8),
	pockets_h = math.Clamp(tonumber(DB.GetSetting("pockets_h", "1")) or 1, 0, 4),
	att_items = DB.GetSetting("att_items", "0") == "1",
	selector_mode = DB.GetSetting("selector_mode", "inventory") == "vanilla" and "vanilla" or "inventory",
	qmenu_weapons = DB.GetSetting("qmenu_weapons", "1") ~= "0",
	entity_pickup = ({ shift = "shift", plain = "plain", off = "off" })[DB.GetSetting("entity_pickup", "shift")] or "shift",
	entity_fresh = DB.GetSetting("entity_fresh", "1") ~= "0",
	hands_class = DB.GetSetting("hands_class", "rpinv_hands"),
	consumable_weapons = DB.GetSetting("consumable_weapons", ""),
	weapon_blacklist = DB.GetSetting("weapon_blacklist", ""),
}

for _, n in ipairs({
	"rpinv_ready", "rpinv_items", "rpinv_store", "rpinv_close", "rpinv_toast", "rpinv_act", "rpinv_settings",
	"rpinv_a_save", "rpinv_a_delete", "rpinv_a_give", "rpinv_a_spawn", "rpinv_a_settings",
}) do util.AddNetworkString(n) end

local function sid(ply) return ply:SteamID64() or ("BOT_" .. ply:EntIndex()) end

local function sendJSON(name, tbl, ply)
	if ply ~= nil and (not IsValid(ply) or not ply:IsPlayer() or ply:IsBot()) then return end
	local data = util.Compress(util.TableToJSON(tbl))
	if not data then return end
	net.Start(name)
	net.WriteUInt(#data, 32)
	net.WriteData(data, #data)
	if ply then net.Send(ply) else net.Broadcast() end
end

local function readJSON(maxLen)
	local len = net.ReadUInt(32)
	if len < 1 or len > maxLen then return nil end
	local raw = util.Decompress(net.ReadData(len), maxLen * 8)
	return raw and util.JSONToTable(raw)
end

local function isAdmin(ply) return IsValid(ply) and ply:IsSuperAdmin() end

local function int(v, lo, hi)
	v = tonumber(v)
	if not v or v ~= v then return nil end
	v = math.floor(v)
	if v < lo or v > hi then return nil end
	return v
end

RPInv.SendJSON, RPInv.ReadJSON, RPInv.IsAdmin, RPInv.Int, RPInv.SID = sendJSON, readJSON, isAdmin, int, sid

function RPInv.Notify(ply, text, kind)
	if not IsValid(ply) or ply:IsBot() then return end
	net.Start("rpinv_toast")
	net.WriteString(text)
	net.WriteUInt(kind or 0, 2)
	net.Send(ply)
end

local ITEMS_PER_MESSAGE = 120

local function sendItems(ply)
	local list = {}
	for _, d in SortedPairs(RPInv.Items) do list[#list + 1] = d end
	local total = math.max(1, math.ceil(#list / ITEMS_PER_MESSAGE))
	for part = 1, total do
		local chunk = {}
		for i = (part - 1) * ITEMS_PER_MESSAGE + 1, math.min(#list, part * ITEMS_PER_MESSAGE) do chunk[#chunk + 1] = list[i] end
		sendJSON("rpinv_items", { items = chunk, first = part == 1, last = part == total }, ply)
	end
end
RPInv.SendItems = sendItems

local sendSettings
function RPInv.SendSettings(ply) return sendSettings(ply) end

function sendSettings(ply)
	sendJSON("rpinv_settings", RPInv.Settings, ply)
end

function RPInv.NewStorage(loc, locId, w, h, name)
	return { loc = loc, locId = tostring(locId), w = w, h = h, items = {}, name = name }
end

local function save(st, inst) DB.UpdateInst(inst, st.loc, st.locId) end

local function create(st, item, amount, meta, x, y, rot)
	local inst = { item = item, amount = amount, meta = meta or {}, x = x, y = y, rot = rot or 0 }
	DB.InsertInst(inst, st.loc, st.locId)
	if not inst.id then return end
	st.items[inst.id] = inst
	return inst
end

local function remove(st, inst)
	st.items[inst.id] = nil
	DB.DeleteInst(inst.id)
end

local function relocate(inst, from, to, x, y, rot)
	from.items[inst.id] = nil
	inst.x, inst.y, inst.rot = x, y, rot
	to.items[inst.id] = inst
	save(to, inst)
end

RPInv.InstCreate, RPInv.InstRemove, RPInv.InstSave = create, remove, save

function RPInv.Revalidate(st)
	local defs = RPInv.Items
	local list, bad = {}, {}
	for _, it in SortedPairs(st.items) do list[#list + 1] = it end
	st.items = {}
	DB.Transaction(function()
		for _, it in ipairs(list) do
			local def = defs[it.item]
			if not def then
				DB.DeleteInst(it.id)
			else
				if not def.rotatable then it.rot = 0 end
				local w, h = G.InstSize(defs, it)
				if G.CanPlace(st, defs, w, h, it.x, it.y) then
					st.items[it.id] = it
				else
					bad[#bad + 1] = it
				end
			end
		end
		for _, it in ipairs(bad) do
			local x, y, rot = G.AutoPlace(st, defs, defs[it.item])
			if x then
				it.x, it.y, it.rot = x, y, rot
				st.items[it.id] = it
				save(st, it)
			else
				st.overflow = st.overflow or {}
				st.overflow[#st.overflow + 1] = it
			end
		end
	end)
	return #bad
end

function RPInv.LoadStorage(st)
	for _, inst in ipairs(DB.LoadInsts(st.loc, st.locId)) do st.items[inst.id] = inst end
	RPInv.Revalidate(st)
end

function RPInv.FlushOverflow(st, pos)
	if not st.overflow or #st.overflow == 0 then return 0 end
	local n = #st.overflow
	DB.Transaction(function()
		for i, it in ipairs(st.overflow) do
			RPInv.SpawnWorldItem(it.item, it.amount, pos + Vector(math.random(-12, 12), math.random(-12, 12), 8 + i * 4), nil, it.meta)
			DB.DeleteInst(it.id)
		end
	end)
	st.overflow = nil
	return n
end

function RPInv.PlayerStorage(ply)
	local key = "p:" .. sid(ply)
	local st = RPInv.Storages[key]
	if not st then
		st = RPInv.NewStorage(DB.LOC_PLAYER, sid(ply), RPInv.Settings.player_grid_w, RPInv.Settings.player_grid_h, "INVENTORY")
		st.owner = ply
		RPInv.LoadStorage(st)
		RPInv.Storages[key] = st
	end
	st.owner = ply
	return st
end

local function payload(st, handle)
	local list = {}
	for _, it in pairs(st.items) do
		list[#list + 1] = {
			id = it.id, item = it.item, amount = it.amount, x = it.x, y = it.y, rot = it.rot,
			meta = next(it.meta) ~= nil and it.meta or nil,
		}
	end
	return { sid = handle, name = st.name, w = st.w, h = st.h, items = list }
end

local function isCarrierDef(def)
	return def ~= nil and (tonumber(def.grid_w) or 0) > 0 and (tonumber(def.grid_h) or 0) > 0
end
RPInv.IsCarrierDef = isCarrierDef

local function allowedIn(st, def)
	return not (st.loc == DB.LOC_CARRIER and isCarrierDef(def))
end
RPInv.AllowedIn = allowedIn

function RPInv.ViewersOf(st)
	local out = {}
	if st.loc == DB.LOC_PLAYER then
		if IsValid(st.owner) then
			out[#out + 1] = { st.owner, "p" }
			for _, p in ipairs(player.GetAll()) do
				if p.RPInvFrisk == st.owner and RPInv.FriskValid and RPInv.FriskValid(p) then out[#out + 1] = { p, "t:p" } end
			end
		end
	elseif st.loc == DB.LOC_CONTAINER then
		local cid = tonumber(st.locId)
		for _, p in ipairs(player.GetAll()) do
			if p.RPInvOpen == cid then out[#out + 1] = { p, "c:" .. st.locId } end
		end
	elseif st.loc == DB.LOC_CARRIER then
		for _, p in ipairs(player.GetAll()) do
			if p.RPInvKVis and p.RPInvKVis[st.locId] then out[#out + 1] = { p, "k:" .. st.locId } end
			if IsValid(p.RPInvFrisk) and RPInv.FriskValid and RPInv.FriskValid(p) and RPInv.Carriers.WornDef(p.RPInvFrisk, st.locId) then
				out[#out + 1] = { p, "t:k:" .. st.locId }
			end
		end
	end
	return out
end

function RPInv.Push(st, only)
	for _, v in ipairs(RPInv.ViewersOf(st)) do
		if not only or only == v[1] then sendJSON("rpinv_store", payload(st, v[2]), v[1]) end
	end
	hook.Run("RPInv_StoragePushed", st)
end

function RPInv.GiveToStorage(st, item, amount, meta)
	local defs = RPInv.Items
	local def = defs[item]
	if not def or amount < 1 or not allowedIn(st, def) then return amount end
	local left = amount
	DB.Transaction(function()
		if G.MetaEmpty(meta) and def.max_stack > 1 then
			for _, it in SortedPairs(st.items) do
				if left <= 0 then break end
				if it.item == item and G.MetaEmpty(it.meta) and it.amount < def.max_stack then
					local add = math.min(left, def.max_stack - it.amount)
					it.amount = it.amount + add
					left = left - add
					save(st, it)
				end
			end
		end
		while left > 0 do
			local x, y, rot = G.AutoPlace(st, defs, def)
			if not x then break end
			local n = math.min(left, def.max_stack)
			if not create(st, item, n, table.Copy(meta or {}), x, y, rot) then break end
			left = left - n
		end
	end)
	return left
end

local function quickMove(inst, from, to)
	local defs = RPInv.Items
	local def = defs[inst.item]
	local moved = false
	if not allowedIn(to, def) then return false end
	if G.MetaEmpty(inst.meta) and def.max_stack > 1 then
		for _, it in SortedPairs(to.items) do
			if inst.amount <= 0 then break end
			if G.CanStack(defs, inst, it) then
				local add = math.min(inst.amount, def.max_stack - it.amount)
				it.amount = it.amount + add
				inst.amount = inst.amount - add
				save(to, it)
				moved = true
			end
		end
		if inst.amount <= 0 then
			remove(from, inst)
			return true
		end
	end
	local x, y, rot = G.AutoPlace(to, defs, def, from == to and inst or nil)
	if not x then
		if moved then save(from, inst) end
		return moved
	end
	relocate(inst, from, to, x, y, rot)
	return true
end

function RPInv.PlayerStorages(ply)
	local main = RPInv.PlayerStorage(ply)
	local list = { main }
	local extra = RPInv.Quick and RPInv.Quick.Storages and RPInv.Quick.Storages(ply) or {}
	for i = #extra, 1, -1 do
		if extra[i] ~= main then list[#list + 1] = extra[i] end
	end
	return list
end

function RPInv.GiveToPlayer(ply, item, amount, meta)
	local left = amount
	for _, st in ipairs(RPInv.PlayerStorages(ply)) do
		if left <= 0 then break end
		if st.w > 0 and st.h > 0 then
			local before = left
			left = RPInv.GiveToStorage(st, item, left, meta)
			if left < before then RPInv.Push(st) end
		end
	end
	return left
end

function RPInv.AddItem(ply, item, amount, meta)
	local left = RPInv.GiveToPlayer(ply, item, amount, meta)
	if left < amount then hook.Run("RPInv_ItemAdded", ply, item, amount - left) end
	return left
end

function RPInv.CountItem(ply, item)
	local n = 0
	for _, it in pairs(RPInv.PlayerStorage(ply).items) do
		if it.item == item then n = n + it.amount end
	end
	return n
end

function RPInv.RemoveItem(ply, item, amount)
	local st = RPInv.PlayerStorage(ply)
	local left = amount
	DB.Transaction(function()
		for _, it in SortedPairs(st.items) do
			if left <= 0 then break end
			if it.item == item then
				local take = math.min(left, it.amount)
				it.amount = it.amount - take
				left = left - take
				if it.amount <= 0 then remove(st, it) else save(st, it) end
			end
		end
	end)
	local removed = amount - left
	if removed > 0 then
		RPInv.Push(st)
		hook.Run("RPInv_ItemRemoved", ply, item, removed)
	end
	return removed
end

function RPInv.ListItems(ply)
	local out = {}
	for _, it in pairs(RPInv.PlayerStorage(ply).items) do
		out[#out + 1] = { id = it.id, item = it.item, amount = it.amount, meta = table.Copy(it.meta) }
	end
	return out
end

function RPInv.ClearInventory(ply)
	local st = RPInv.PlayerStorage(ply)
	DB.Transaction(function() DB.DeleteInstsAt(st.loc, st.locId) end)
	st.items = {}
	RPInv.Push(st)
end

function RPInv.SpawnWorldItem(id, amount, pos, ang, meta)
	local ent = ents.Create("rpinv_item")
	if not IsValid(ent) then return end
	ent:SetItemID(id)
	ent:SetAmount(amount)
	ent.RPInvMeta = table.Copy(meta or {})
	ent:SetPos(pos)
	ent:SetAngles(ang or Angle(0, math.random(0, 359), 0))
	ent:Spawn()
	ent:Activate()
	return ent
end

local function dropPos(ply)
	local start = ply:GetShootPos()
	local dir = ply:GetAimVector()
	dir.z = math.min(dir.z, 0.2)
	local tr = util.TraceLine({ start = start, endpos = start + dir * 50, filter = ply })
	return tr.HitPos - dir * 12 + Vector(0, 0, 4)
end
RPInv.DropPos = dropPos

function RPInv.PickupWorldItem(ply, ent)
	if not ply:Alive() or ent.RPInvTaken then return end
	local item, total = ent:GetItemID(), ent:GetAmount()
	local def = RPInv.Items[item]
	if not def then ent:Remove() return end
	local left = RPInv.GiveToPlayer(ply, item, total, ent.RPInvMeta)
	if left < total then
		ply:EmitSound("items/ammo_pickup.wav", 60)
		hook.Run("RPInv_ItemAdded", ply, item, total - left)
	end
	if left <= 0 then
		ent.RPInvTaken = true
		ent:Remove()
		RPInv.Notify(ply, "Picked up: " .. def.name .. (total > 1 and (" x" .. total) or ""), 1)
	elseif left < total then
		ent:SetAmount(left)
		RPInv.Notify(ply, "Not enough space: picked up " .. (total - left) .. " of " .. total .. ".", 2)
	else
		RPInv.Notify(ply, "Not enough space for " .. def.name .. ".", 2)
	end
end

local UseHandlers = {
	none = function() return false, "This item cannot be used." end,
	heal = function(ply, def)
		if ply:Health() >= ply:GetMaxHealth() then return false, "You are already at full health." end
		ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + (tonumber(def.use_arg) or 0)))
		return true
	end,
	armor = function(ply, def)
		if ply:Armor() >= ply:GetMaxArmor() then return false, "You already have full armor." end
		ply:SetArmor(math.min(ply:GetMaxArmor(), ply:Armor() + (tonumber(def.use_arg) or 0)))
		return true
	end,
	ammo = function(ply, def)
		local atype, amt = string.match(def.use_arg or "", "^(.+):(%d+)$")
		amt = tonumber(amt)
		if not atype or not amt or game.GetAmmoID(atype) == -1 then return false, "This ammo item is misconfigured." end
		ply:GiveAmmo(math.Clamp(amt, 1, 9999), atype)
		return true
	end,
	weapon = function(ply, def, inst)
		if ply:HasWeapon(def.use_arg) then return false, "You already have this weapon." end
		local clip = inst and inst.meta and tonumber(inst.meta.clip1)
		local wep = ply:Give(def.use_arg, clip ~= nil)
		if not IsValid(wep) then return false, "This weapon is not available." end
		if clip and clip >= 0 then wep:SetClip1(clip) end
		if RPInv.Equip and inst and inst.meta then RPInv.Equip.RestoreAttachments(ply, wep, inst.meta.atts, clip) end
		return true
	end,
}

local function access(ply, handle)
	if type(handle) ~= "string" or #handle > 24 then return nil end
	if handle == "p" then return RPInv.PlayerStorage(ply) end
	local cid = tonumber(string.match(handle, "^c:(%d+)$"))
	if cid and RPInv.ContainerAccess then return RPInv.ContainerAccess(ply, cid) end
	local kid = string.match(handle, "^k:([%w_]+)$")
	if kid and RPInv.CarrierAccess then return RPInv.CarrierAccess(ply, kid) end
	if string.sub(handle, 1, 2) == "t:" and RPInv.FriskAccess then return RPInv.FriskAccess(ply, string.sub(handle, 3)) end
end
RPInv.Access = access

local MAXID = 2147483647

local function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh)
	return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local Actions = {}

Actions.move = function(ply, t, touch)
	local defs = RPInv.Items
	local src, dst = access(ply, t.from), access(ply, t.to)
	if not src or not dst then return "That storage is not available." end
	local inst = src.items[int(t.id, 1, MAXID) or -1]
	if not inst then return false end
	local def = defs[inst.item]
	touch(src)
	touch(dst)
	local rot = int(t.rot, 0, 1) or inst.rot
	if not def.rotatable then rot = 0 end
	local n = int(t.n, 1, inst.amount) or inst.amount
	local same = src == dst
	if not allowedIn(dst, def) then return "Carriers cannot be stored inside other carriers." end
	if inst.meta.cid and dst.loc == DB.LOC_CARRIER and dst.locId == inst.meta.cid then return false end

	local onto = int(t.onto, 1, MAXID)
	if onto then
		local target = dst.items[onto]
		if target and G.CanStack(defs, inst, target) then
			local add = math.min(n, def.max_stack - target.amount)
			DB.Transaction(function()
				target.amount = target.amount + add
				inst.amount = inst.amount - add
				save(dst, target)
				if inst.amount <= 0 then remove(src, inst) else save(src, inst) end
			end)
			return true
		end
	end

	local x, y = int(t.x, 0, 63), int(t.y, 0, 63)
	if not x or not y then return false end
	local w, h = G.Size(def, rot)
	local whole = n == inst.amount
	if G.CanPlace(dst, defs, w, h, x, y, (same and whole) and inst or nil) then
		DB.Transaction(function()
			if not whole then
				inst.amount = inst.amount - n
				save(src, inst)
				create(dst, inst.item, n, table.Copy(inst.meta), x, y, rot)
			else
				relocate(inst, src, dst, x, y, rot)
			end
		end)
		return true
	end

	if whole then
		local ov = G.Overlaps(dst, defs, w, h, x, y, same and inst or nil)
		if #ov == 1 then
			local other = ov[1]
			local odef = defs[other.item]
			if allowedIn(src, odef) and G.CanPlace(dst, defs, w, h, x, y, other, same and inst or nil) then
				for _, r in ipairs({ other.rot, 1 - other.rot }) do
					if r == other.rot or odef.rotatable then
						local rw, rh = G.Size(odef, r)
						local clash = same and rectsOverlap(x, y, w, h, inst.x, inst.y, rw, rh)
						if not clash and G.CanPlace(src, defs, rw, rh, inst.x, inst.y, inst, same and other or nil) then
							DB.Transaction(function()
								local ox, oy = inst.x, inst.y
								relocate(inst, src, dst, x, y, rot)
								relocate(other, dst, src, ox, oy, r)
							end)
							return true
						end
					end
				end
			end
		end
	end
	return "No space there."
end

Actions.quick = function(ply, t, touch)
	local src = access(ply, t.from)
	local inst = src and src.items[int(t.id, 1, MAXID) or -1]
	if not inst then return false end
	local dst
	if t.from == "p" then
		if not ply.RPInvOpen then return "Open a container first." end
		dst = access(ply, "c:" .. ply.RPInvOpen)
	else
		dst = access(ply, "p")
	end
	if not dst then return false end
	touch(src)
	touch(dst)
	if not allowedIn(dst, RPInv.Items[inst.item]) then return "Carriers cannot be stored inside other carriers." end
	local moved = false
	DB.Transaction(function() moved = quickMove(inst, src, dst) end)
	if not moved then return "Not enough space." end
	return true
end

Actions.split = function(ply, t, touch)
	local st = access(ply, t.from)
	local inst = st and st.items[int(t.id, 1, MAXID) or -1]
	if not inst or inst.amount < 2 then return false end
	local n = int(t.n, 1, inst.amount - 1)
	if not n then return false end
	touch(st)
	local def = RPInv.Items[inst.item]
	local x, y, rot = G.AutoPlace(st, RPInv.Items, def)
	if not x then return "No space for the new stack." end
	DB.Transaction(function()
		inst.amount = inst.amount - n
		save(st, inst)
		create(st, inst.item, n, table.Copy(inst.meta), x, y, rot)
	end)
	return true
end

Actions.rotate = function(ply, t, touch)
	local st = access(ply, t.from)
	local inst = st and st.items[int(t.id, 1, MAXID) or -1]
	if not inst then return false end
	local def = RPInv.Items[inst.item]
	touch(st)
	if not def.rotatable then return "This item cannot be rotated." end
	local rot = 1 - inst.rot
	local w, h = G.Size(def, rot)
	if not G.CanPlace(st, RPInv.Items, w, h, inst.x, inst.y, inst) then return "No space to rotate here." end
	inst.rot = rot
	save(st, inst)
	return true
end

UseHandlers.throw = function(ply, def)
	if not RPInv.ThrowEntity then return false, "Cannot throw this." end
	return RPInv.ThrowEntity(ply, def)
end

UseHandlers.place = function(ply, def, inst)
	if not RPInv.PlaceEntity then return false, "Cannot place this." end
	return RPInv.PlaceEntity(ply, def, inst)
end

UseHandlers.attachment = function(ply, def)
	if not RPInv.UseAttachment then return false, "Cannot use this." end
	return RPInv.UseAttachment(ply, def)
end

UseHandlers.entuse = function(ply, def, inst)
	if not RPInv.UseEntity then return false, "Cannot use this." end
	return RPInv.UseEntity(ply, def, inst)
end

UseHandlers.rounds = function()
	return false, "Rounds are loaded automatically when you reload."
end

UseHandlers.resource = function(ply, def, inst)
	if not RPInv.PlaceResource then return false, "Cannot place this." end
	return RPInv.PlaceResource(ply, def, inst)
end

UseHandlers.flare = function(ply, def)
	if not RPInv.Airdrop or not RPInv.Airdrop.GiveFlareGun then return false, "Cannot use this." end
	return RPInv.Airdrop.GiveFlareGun(ply, def)
end

RPInv.USE_COOLDOWN = 1
RPInv.THROW_DELAY = 2

local function startThrow(ply, st, inst)
	if ply.RPInvThrowPending then return false end
	if ply:GetNW2Bool("RPInvSurrender", false) then return "You cannot do that with your hands up." end
	ply.RPInvThrowPending = { st = st, id = inst.id, item = inst.item }
	ply:SetNW2Float("RPInvThrowAt", CurTime() + RPInv.THROW_DELAY)
	ply:SetNW2Float("RPInvUseReady", CurTime() + RPInv.THROW_DELAY)
	ply:EmitSound("weapons/slam/mine_mode.wav", 65, 105)
	if RPInv.GearSound then RPInv.GearSound(ply, 52) end
	timer.Create("RPInv_Throw" .. ply:EntIndex(), RPInv.THROW_DELAY, 1, function()
		if not IsValid(ply) then return end
		local p = ply.RPInvThrowPending
		ply.RPInvThrowPending = nil
		ply:SetNW2Float("RPInvThrowAt", 0)
		if not p or not ply:Alive() or ply:GetNW2Bool("RPInvSurrender", false) then return end
		if ply:InVehicle() then
			ply:SetNW2Float("RPInvUseReady", 0)
			RPInv.Notify(ply, RPInv.VEHICLE_MSG, 2)
			return
		end
		local cur = p.st.items[p.id]
		if not cur or cur.item ~= p.item then
			RPInv.Notify(ply, "The grenade is no longer in your inventory.", 2)
			return
		end
		ply:SetNW2Float("RPInvUseReady", 0)
		ply.RPInvThrowNow = true
		local res = RPInv.UseInst(ply, p.st, cur, true)
		ply.RPInvThrowNow = nil
		RPInv.Push(p.st)
		if isstring(res) then RPInv.Notify(ply, res, 2) end
	end)
	return true
end

hook.Add("PlayerDeath", "RPInv_ThrowCancel", function(ply)
	timer.Remove("RPInv_Throw" .. ply:EntIndex())
	ply.RPInvThrowPending = nil
	ply:SetNW2Float("RPInvThrowAt", 0)
end)

local VEHICLE_NO_USE = { throw = true, place = true, weapon = true, flare = true, attachment = true, resource = true }
RPInv.VEHICLE_MSG = "You can't do that in a vehicle."

function RPInv.UseInst(ply, st, inst, quiet)
	local def = RPInv.Items[inst.item]
	if not def then return false end
	if ply:InVehicle() and VEHICLE_NO_USE[def.use_type] then return RPInv.VEHICLE_MSG end
	local now = CurTime()
	if ply:GetNW2Float("RPInvUseReady", 0) > now then return false end
	if def.use_type == "throw" and not ply.RPInvThrowNow then return startThrow(ply, st, inst) end
	local ok, err = (UseHandlers[def.use_type] or UseHandlers.none)(ply, def, inst)
	if not ok then return err or "Cannot use this." end
	ply:SetNW2Float("RPInvUseReady", now + RPInv.USE_COOLDOWN)
	inst.amount = inst.amount - 1
	if inst.amount <= 0 then remove(st, inst) else save(st, inst) end
	hook.Run("RPInv_ItemRemoved", ply, def.id, 1)
	if not quiet then RPInv.Notify(ply, "Used: " .. def.name, 1) end
	return true
end

Actions.use = function(ply, t, touch)
	local st = access(ply, t.from)
	local inst = st and st.items[int(t.id, 1, MAXID) or -1]
	if not inst then return false end
	touch(st)
	local def = RPInv.Items[inst.item]
	return RPInv.UseInst(ply, st, inst, def and (def.use_type == "throw" or def.use_type == "place"))
end

Actions.drop = function(ply, t, touch)
	local st = access(ply, t.from)
	local inst = st and st.items[int(t.id, 1, MAXID) or -1]
	if not inst then return false end
	local n = int(t.n, 1, inst.amount) or inst.amount
	touch(st)
	if not RPInv.SpawnInstInWorld(inst, dropPos(ply), n, ply) then return "Could not drop this item." end
	ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 60)
	DB.Transaction(function()
		inst.amount = inst.amount - n
		if inst.amount <= 0 then remove(st, inst) else save(st, inst) end
	end)
	if st.loc == DB.LOC_PLAYER then hook.Run("RPInv_ItemRemoved", ply, inst.item, n) end
	return true
end

Actions.sort = function(ply, t, touch)
	local st = access(ply, t.sid)
	if not st then return false end
	touch(st)
	local res = G.Sort(st, RPInv.Items)
	if not res then return "Not enough space to sort." end
	DB.Transaction(function()
		for id, pos in pairs(res) do
			local it = st.items[id]
			it.x, it.y, it.rot = pos.x, pos.y, pos.rot
			save(st, it)
		end
	end)
	return true
end

RPInv.Actions = Actions

function RPInv.DoAction(ply, t)
	local fn = type(t) == "table" and Actions[t.a]
	if not fn or not ply:Alive() then return false end
	if ply:InVehicle() and (t.a == "drop" or (t.a == "unequip" and t.drop)) then
		RPInv.Notify(ply, RPInv.VEHICLE_MSG, 2)
		return false
	end
	local touched = {}
	local res = fn(ply, t, function(st) touched[st] = true end)
	if type(res) == "string" then RPInv.Notify(ply, res, 2) end
	if next(touched) == nil then touched[RPInv.PlayerStorage(ply)] = true end
	for st in pairs(touched) do RPInv.Push(st) end
	return res == true
end

local function takeToken(ply)
	local now = CurTime()
	local tokens = math.min(12, (ply.RPInvTokens or 12) + (now - (ply.RPInvTokenTime or now)) * 12)
	ply.RPInvTokenTime = now
	if tokens < 1 then ply.RPInvTokens = tokens return false end
	ply.RPInvTokens = tokens - 1
	return true
end

net.Receive("rpinv_act", function(_, ply)
	local t = readJSON(1024)
	if type(t) ~= "table" or not takeToken(ply) then return end
	RPInv.DoAction(ply, t)
end)

net.Receive("rpinv_ready", function(_, ply)
	if ply.RPInvReady and CurTime() - ply.RPInvReady < 2 then return end
	ply.RPInvReady = CurTime()
	sendItems(ply)
	sendSettings(ply)
	local st = RPInv.PlayerStorage(ply)
	if st.overflow and ply:Alive() and RPInv.FlushOverflow(st, ply:GetPos()) > 0 then
		RPInv.Notify(ply, "Some items did not fit in your inventory and were dropped.", 2)
	end
	RPInv.Push(st, ply)
	hook.Run("RPInv_PlayerReady", ply)
end)

hook.Add("PlayerSpawn", "RPInv_Overflow", function(ply)
	timer.Simple(0.5, function()
		if not IsValid(ply) then return end
		local st = RPInv.Storages["p:" .. sid(ply)]
		if st and st.overflow and RPInv.FlushOverflow(st, ply:GetPos()) > 0 then
			RPInv.Notify(ply, "Some items did not fit in your inventory and were dropped.", 2)
		end
	end)
end)

hook.Add("PlayerDisconnected", "RPInv_Cleanup", function(ply)
	RPInv.Storages["p:" .. sid(ply)] = nil
end)

local function revalidateAll()
	for _, st in pairs(RPInv.Storages) do
		RPInv.Revalidate(st)
		if st.overflow then
			if st.loc == DB.LOC_PLAYER and IsValid(st.owner) and st.owner:Alive() then
				RPInv.FlushOverflow(st, st.owner:GetPos())
				RPInv.Notify(st.owner, "Some items did not fit in your inventory and were dropped.", 2)
			elseif st.loc == DB.LOC_CONTAINER and RPInv.Containers then
				local c = RPInv.Containers[tonumber(st.locId)]
				if c and IsValid(c.ent) then RPInv.FlushOverflow(st, c.ent:GetPos() + Vector(0, 0, 40)) end
			end
		end
		RPInv.Push(st)
	end
end
RPInv.RevalidateAll = revalidateAll

local function sanitizeDef(t)
	if type(t) ~= "table" then return nil, "Invalid data." end
	local id = string.lower(string.Trim(tostring(t.id or "")))
	if #id < 1 or #id > 32 or not id:match("^[a-z0-9_]+$") then return nil, "ID must be 1-32 characters: a-z, 0-9, _" end
	local name = string.Trim(tostring(t.name or "")):sub(1, 40)
	if name == "" then return nil, "Name cannot be empty." end
	local model = string.Trim(tostring(t.model or "")):sub(1, 128)
	if not model:lower():match("%.mdl$") or not util.IsValidModel(model) then return nil, "Model not found on the server." end
	local useType = tostring(t.use_type or "none")
	if not RPInv.UseTypes[useType] then return nil, "Invalid use type." end
	local useArg = string.Trim(tostring(t.use_arg or "")):sub(1, 64)
	if useType == "ammo" then
		local at, amt = useArg:match("^(.+):(%d+)$")
		if not at or game.GetAmmoID(at) == -1 or tonumber(amt) < 1 or tonumber(amt) > 9999 then
			return nil, "Ammo argument must be AmmoType:amount (e.g. Pistol:20). Unknown ammo type or bad amount."
		end
	end
	if (useType == "throw" or useType == "place" or useType == "resource" or useType == "entuse") and not scripted_ents.GetStored(useArg) and not (useType == "place" and useArg == "prop_physics") then
		return nil, "Use argument must be an existing entity class (e.g. ent_jack_gmod_ezfragnade)."
	end
	if useType == "flare" then
		if not useArg:match("^[%d,%s]*$") then return nil, "Flare gun argument must be airdrop preset IDs, e.g. 1,3 (empty = any preset)." end
		local ids = {}
		for n in useArg:gmatch("%d+") do
			if #ids < 16 and not table.HasValue(ids, n) then ids[#ids + 1] = n end
		end
		useArg = table.concat(ids, ",")
	end
	if useType == "attachment" and not RPInv.Att.Exists(useArg) then
		return nil, "Use argument must be base:attachment of an installed weapon base (arccw, tacrp, arc9, tfa)."
	end
	local p, y, r = RPInv.DB.Parse3(tostring(t.cam_ang or ""))
	local old = RPInv.Items[id] or {}
	return {
		id = id, name = name, model = model,
		descr = string.Trim(tostring(t.descr or "")):sub(1, 200),
		max_stack = math.Clamp(math.floor(tonumber(t.max_stack) or 1), 1, 999),
		use_type = useType, use_arg = useArg,
		w = math.Clamp(math.floor(tonumber(t.w) or 1), 1, 10),
		h = math.Clamp(math.floor(tonumber(t.h) or 1), 1, 10),
		rotatable = t.rotatable ~= false and t.rotatable ~= 0,
		category = string.Trim(tostring(t.category or "")):sub(1, 24),
		cam_ang = string.format("%d %d %d", math.Clamp(p, -180, 180), math.Clamp(y, -180, 180), math.Clamp(r, -180, 180)),
		cam_fov = math.Clamp(tonumber(t.cam_fov) or 1, 0.3, 20),
		skin = math.Clamp(math.floor(tonumber(t.skin) or 0), 0, 63),
		bodygroups = string.sub(string.gsub(string.lower(tostring(t.bodygroups or "")), "[^0-9a-z]", ""), 1, 32),
		cam_off = (function()
			local ox, oy = string.match(tostring(t.cam_off or ""), "^%s*(%-?[%d%.]+)%s+(%-?[%d%.]+)%s*$")
			ox, oy = math.Clamp(tonumber(ox) or 0, -1, 1), math.Clamp(tonumber(oy) or 0, -1, 1)
			if ox == 0 and oy == 0 then return "" end
			return string.format("%.2f %.2f", ox, oy)
		end)(),
		equip_slot = (old.jmod_armor and old.jmod_armor ~= "") and (old.equip_slot or "")
			or ((RPInv.EquipSlotByKey[tostring(t.equip_slot or "")] and RPInv.EquipSlotByKey[t.equip_slot].weapon and useType == "weapon") and t.equip_slot or ""),
		grid_w = math.Clamp(math.floor(tonumber(t.grid_w) or old.grid_w or 0), 0, 12),
		grid_h = math.Clamp(math.floor(tonumber(t.grid_h) or old.grid_h or 0), 0, 12),
		jmod_armor = old.jmod_armor or "", world_class = old.world_class or "",
	}
end

net.Receive("rpinv_a_save", function(_, ply)
	local data = readJSON(4096)
	if not isAdmin(ply) then return end
	local def, err = sanitizeDef(data)
	if not def then RPInv.Notify(ply, err, 2) return end
	local old = RPInv.Items[def.id]
	local resized = old and (old.w ~= def.w or old.h ~= def.h or old.rotatable ~= def.rotatable or old.max_stack > def.max_stack)
	RPInv.Items[def.id] = def
	DB.SaveItem(def)
	DB.Log(ply, "item_save", def.id)
	sendItems()
	if resized then revalidateAll() end
	RPInv.Notify(ply, "Item saved: " .. def.name, 1)
end)

util.AddNetworkString("rpinv_a_import")
util.AddNetworkString("rpinv_a_log")
util.AddNetworkString("rpinv_a_log_r")

net.Receive("rpinv_a_import", function(_, ply)
	local data = readJSON(60000)
	if not isAdmin(ply) then return end
	local list = type(data) == "table" and (data.items or data) or nil
	if type(list) ~= "table" then RPInv.Notify(ply, "Import failed: not a JSON item list.", 2) return end
	local saved, failed = 0, 0
	DB.Transaction(function()
		for _, t in ipairs(list) do
			local def = sanitizeDef(t)
			if def then
				local jm = tostring(t.jmod_armor or "")
				if jm ~= "" and RPInv.JModAvailable() and JMod.ArmorTable[jm] then
					def.jmod_armor = jm
					def.world_class = JMod.ArmorTable[jm].ent or ""
					def.equip_slot = RPInv.JModSlotFor(jm) or ""
				end
				RPInv.Items[def.id] = def
				DB.SaveItem(def)
				saved = saved + 1
			else
				failed = failed + 1
			end
		end
	end)
	DB.Log(ply, "item_import", saved .. " saved, " .. failed .. " failed")
	sendItems()
	revalidateAll()
	RPInv.Notify(ply, "Imported " .. saved .. " item(s)" .. (failed > 0 and (", " .. failed .. " skipped (invalid or missing model)") or "") .. ".", failed > 0 and 2 or 1)
end)

net.Receive("rpinv_a_log", function(_, ply)
	if not isAdmin(ply) then return end
	if (ply.RPInvLogNext or 0) > CurTime() then return end
	ply.RPInvLogNext = CurTime() + 1
	local rows = DB.Query("SELECT ts, steamid, action, details FROM rpinv_log ORDER BY id DESC LIMIT 200") or {}
	sendJSON("rpinv_a_log_r", { rows = rows }, ply)
end)

function RPInv.DeleteItemDefs(ids)
	local set = {}
	for _, id in ipairs(ids) do
		if RPInv.Items[id] then set[id] = true end
	end
	if next(set) == nil then return 0 end
	local n = 0
	DB.Transaction(function()
		for id in pairs(set) do
			RPInv.Items[id] = nil
			DB.DeleteItem(id)
			n = n + 1
		end
	end)
	for _, st in pairs(RPInv.Storages) do
		local changed = false
		for iid, it in pairs(st.items) do
			if set[it.item] then st.items[iid] = nil changed = true end
		end
		if changed then RPInv.Push(st) end
	end
	for _, e in ipairs(ents.FindByClass("rpinv_item")) do
		if set[e:GetItemID()] then e:Remove() end
	end
	for id in pairs(set) do hook.Run("RPInv_ItemDeleted", id) end
	sendItems()
	return n
end

net.Receive("rpinv_a_delete", function(_, ply)
	local id = net.ReadString()
	if not isAdmin(ply) or not RPInv.Items[id] then return end
	RPInv.DeleteItemDefs({ id })
	DB.Log(ply, "item_delete", id)
	RPInv.Notify(ply, "Item deleted: " .. id, 1)
end)

util.AddNetworkString("rpinv_a_purge")

net.Receive("rpinv_a_purge", function(_, ply)
	local kind = net.ReadString()
	if not isAdmin(ply) then return end
	if (ply.RPInvPurgeNext or 0) > CurTime() then return end
	ply.RPInvPurgeNext = CurTime() + 3
	local ids = {}
	for id, d in pairs(RPInv.Items) do
		if (kind == "attachments" and d.use_type == "attachment") or (kind == "armor" and (d.jmod_armor or "") ~= "") then
			ids[#ids + 1] = id
		end
	end
	if kind ~= "attachments" and kind ~= "armor" then return end
	local n = RPInv.DeleteItemDefs(ids)
	DB.Log(ply, "item_purge", kind .. " " .. n)
	RPInv.Notify(ply, "Removed " .. n .. (kind == "armor" and " JMod armor" or " attachment") .. " item(s) and every copy of them.", 1)
end)

net.Receive("rpinv_a_give", function(_, ply)
	local id, amount = net.ReadString(), net.ReadUInt(16)
	if not isAdmin(ply) or not RPInv.Items[id] then return end
	local left = RPInv.AddItem(ply, id, math.max(1, amount))
	if left > 0 then RPInv.Notify(ply, "Inventory full, " .. left .. " not added.", 2) end
end)

net.Receive("rpinv_a_spawn", function(_, ply)
	local id, amount = net.ReadString(), net.ReadUInt(16)
	if not isAdmin(ply) or not RPInv.Items[id] then return end
	local tr = ply:GetEyeTrace()
	RPInv.SpawnInstInWorld({ item = id, amount = math.max(1, amount), meta = {} }, tr.HitPos + tr.HitNormal * 12)
end)

util.AddNetworkString("rpinv_a_wipe")

function RPInv.WipeGround()
	local n = 0
	for _, e in ipairs(ents.FindByClass("rpinv_item")) do
		if IsValid(e) then
			e.RPInvTaken = true
			e:Remove()
			n = n + 1
		end
	end
	return n
end

function RPInv.WipeAllData()
	for _, p in ipairs(player.GetAll()) do
		if p.RPInvOpen and RPInv.CloseContainerFor then RPInv.CloseContainerFor(p) end
		local E = RPInv.Equip
		if E and E.State then
			local s = E.State(p)
			for _, inst in pairs(s.weapons or {}) do E.StripWeapon(p, inst) end
			s.weapons = {}
			s.armor = {}
		end
		if istable(p.EZarmor) and istable(p.EZarmor.items) then
			p.EZarmor.items = {}
			if JMod and isfunction(JMod.EZarmorSync) then JMod.EZarmorSync(p) end
		end
		p.RPInvQuick = {}
	end
	DB.Transaction(function()
		DB.Query("DELETE FROM rpinv_inst")
		DB.Query("DELETE FROM rpinv_settings WHERE k LIKE 'quick_%' OR k LIKE 'ammo_%'")
	end)
	for _, st in pairs(RPInv.Storages) do
		st.items = {}
		st.overflow = nil
		RPInv.Push(st)
	end
	for _, p in ipairs(player.GetAll()) do
		if RPInv.Quick and RPInv.Quick.Push then RPInv.Quick.Push(p) end
		if RPInv.Equip and RPInv.Equip.QueuePush then RPInv.Equip.QueuePush(p) end
	end
end

net.Receive("rpinv_a_wipe", function(_, ply)
	local kind = net.ReadString()
	if not isAdmin(ply) then return end
	if kind == "ground" then
		local n = RPInv.WipeGround()
		DB.Log(ply, "wipe_ground", n .. " items")
		RPInv.Notify(ply, "Removed " .. n .. " items from the ground.", 1)
	elseif kind == "all" then
		RPInv.WipeAllData()
		DB.Log(ply, "wipe_all", "all inventory data")
		RPInv.Notify(ply, "All inventory data was wiped.", 1)
	end
end)

net.Receive("rpinv_a_settings", function(_, ply)
	local t = readJSON(8192)
	if not isAdmin(ply) or type(t) ~= "table" then return end
	local S = RPInv.Settings
	local w, h = gridSize(t.player_grid_w or S.player_grid_w, t.player_grid_h or S.player_grid_h)
	S.player_grid_w, S.player_grid_h = w, h
	if t.death_mode == "keep" or t.death_mode == "drop" or t.death_mode == "corpse" then S.death_mode = t.death_mode end
	if tonumber(t.corpse_time) then S.corpse_time = math.Clamp(math.floor(tonumber(t.corpse_time)), 1, 60) end
	DB.SetSetting("corpse_time", S.corpse_time)
	if t.restore_armor ~= nil then S.restore_armor = t.restore_armor == true end
	if t.jmod_pickup == "shift" or t.jmod_pickup == "plain" or t.jmod_pickup == "off" then S.jmod_pickup = t.jmod_pickup end
	if t.search_mode == "surrender" or t.search_mode == "anyone" or t.search_mode == "admin" then S.search_mode = t.search_mode end
	if tonumber(t.search_time) then S.search_time = math.Clamp(math.floor(tonumber(t.search_time)), 1, 30) end
	if t.search_equipment ~= nil then S.search_equipment = t.search_equipment == true end
	DB.SetSetting("search_mode", S.search_mode)
	DB.SetSetting("search_time", S.search_time)
	DB.SetSetting("search_equipment", S.search_equipment and "1" or "0")
	if tonumber(t.loot_time) then S.loot_time = math.Clamp(math.floor(tonumber(t.loot_time)), 0, 15) end
	DB.SetSetting("loot_time", S.loot_time)
	if t.weapon_touch_pickup ~= nil then S.weapon_touch_pickup = t.weapon_touch_pickup == true end
	DB.SetSetting("weapon_touch_pickup", S.weapon_touch_pickup and "1" or "0")
	if tonumber(t.pockets_w) then S.pockets_w = math.Clamp(math.floor(tonumber(t.pockets_w)), 0, 8) end
	if tonumber(t.pockets_h) then S.pockets_h = math.Clamp(math.floor(tonumber(t.pockets_h)), 0, 4) end
	DB.SetSetting("pockets_w", S.pockets_w)
	DB.SetSetting("pockets_h", S.pockets_h)
	if t.att_items ~= nil then S.att_items = t.att_items == true end
	DB.SetSetting("att_items", S.att_items and "1" or "0")
	if t.selector_mode == "inventory" or t.selector_mode == "vanilla" then S.selector_mode = t.selector_mode end
	DB.SetSetting("selector_mode", S.selector_mode)
	if t.qmenu_weapons ~= nil then S.qmenu_weapons = t.qmenu_weapons == true end
	DB.SetSetting("qmenu_weapons", S.qmenu_weapons and "1" or "0")
	if t.entity_pickup == "shift" or t.entity_pickup == "plain" or t.entity_pickup == "off" then S.entity_pickup = t.entity_pickup end
	DB.SetSetting("entity_pickup", S.entity_pickup)
	if t.entity_fresh ~= nil then S.entity_fresh = t.entity_fresh == true end
	DB.SetSetting("entity_fresh", S.entity_fresh and "1" or "0")
	if t.hands_class ~= nil then
		local hc = string.Trim(tostring(t.hands_class)):sub(1, 64)
		if hc == "" or weapons.GetStored(hc) or (RPInv.HL2Weapons and RPInv.HL2Weapons[hc]) then
			S.hands_class = hc
		else
			RPInv.Notify(ply, "Unknown hands weapon class: " .. hc .. " (kept " .. (S.hands_class == "" and "none" or S.hands_class) .. ").", 2)
		end
	end
	DB.SetSetting("hands_class", S.hands_class)
	if t.consumable_weapons ~= nil then
		local list = {}
		for c in string.gmatch(tostring(t.consumable_weapons), "[^,%s]+") do
			if #list < 64 then list[#list + 1] = string.sub(c, 1, 64) end
		end
		S.consumable_weapons = table.concat(list, ",")
	end
	DB.SetSetting("consumable_weapons", S.consumable_weapons)
	if t.weapon_blacklist ~= nil then
		local list = {}
		for c in string.gmatch(tostring(t.weapon_blacklist), "[^,%s]+") do
			if #list < 128 then list[#list + 1] = string.sub(c, 1, 64) end
		end
		S.weapon_blacklist = table.concat(list, ",")
	end
	DB.SetSetting("weapon_blacklist", S.weapon_blacklist or "")
	if t.ammo_items ~= nil and S.ammo_items ~= (t.ammo_items == true) then
		S.ammo_items = t.ammo_items == true
		for _, p in ipairs(player.GetAll()) do p.RPInvAmmoSet = nil end
	end
	DB.SetSetting("ammo_items", S.ammo_items and "1" or "0")
	if tonumber(t.ammo_stack) then
		local n = math.Clamp(math.floor(tonumber(t.ammo_stack)), 1, 999)
		if n ~= S.ammo_stack then
			S.ammo_stack = n
			if RPInv.Ammo and RPInv.Ammo.Reprice then RPInv.Ammo.Reprice() end
		end
	end
	DB.SetSetting("ammo_stack", S.ammo_stack or 60)
	if t.ammo_ignore ~= nil then
		local list = {}
		for c in string.gmatch(tostring(t.ammo_ignore), "[^,]+") do
			c = string.Trim(c)
			if c ~= "" and #list < 64 then list[#list + 1] = string.sub(c, 1, 48) end
		end
		S.ammo_ignore = table.concat(list, ",")
		for _, p in ipairs(player.GetAll()) do p.RPInvAmmoSet = nil end
	end
	DB.SetSetting("ammo_ignore", S.ammo_ignore or "")
	for _, p in ipairs(player.GetAll()) do
		if RPInv.Equip then RPInv.Equip.QueuePush(p) end
	end
	DB.SetSetting("player_grid_w", w)
	DB.SetSetting("player_grid_h", h)
	DB.SetSetting("death_mode", S.death_mode)
	DB.SetSetting("restore_armor", S.restore_armor and "1" or "0")
	DB.SetSetting("jmod_pickup", S.jmod_pickup)
	DB.Log(ply, "settings", w .. "x" .. h .. " death=" .. S.death_mode .. " restore=" .. tostring(S.restore_armor) .. " pickup=" .. S.jmod_pickup)
	for _, st in pairs(RPInv.Storages) do
		if st.loc == DB.LOC_PLAYER then st.w, st.h = w, h end
	end
	revalidateAll()
	sendSettings()
	RPInv.Notify(ply, "Settings saved.", 1)
end)
