local DB = RPInv.DB
local L = RPInv.Loot or {}
RPInv.Loot = L

for _, n in ipairs({
	"rpinv_lt_list", "rpinv_lt_list_r", "rpinv_lt_save", "rpinv_lt_delete", "rpinv_lt_settings",
	"rpinv_lt_clearpoints", "rpinv_lt_spawnnow", "rpinv_lt_refill", "rpinv_lt_propset", "rpinv_lt_propdel",
}) do util.AddNetworkString(n) end

L.DEFAULT_MODEL = "models/items/ammocrate_smg1.mdl"
L.MAX_PRESETS = 50
L.MAX_LOOT = 60
L.MAX_POINTS = 500
L.TICK = 5

local S = RPInv.Settings
S.loot_enabled = DB.GetSetting("loot_enabled", "1") ~= "0"

local function loadPresets()
	local out = {}
	for _, p in pairs(util.JSONToTable(DB.GetSetting("loot_presets", "") or "") or {}) do
		if istable(p) and tonumber(p.id) then out[tonumber(p.id)] = p end
	end
	return out
end

L.Presets = loadPresets()

local function savePresets()
	local list = {}
	for _, p in SortedPairs(L.Presets) do list[#list + 1] = p end
	DB.SetSetting("loot_presets", util.TableToJSON(list))
end

local function pointsKey() return "loot_points_" .. game.GetMap() end

local function cleanTag(s)
	return string.sub(string.lower(string.gsub(tostring(s or ""), "[^%w_%-]", "")), 1, 24)
end
L.CleanTag = cleanTag

function L.Points()
	if not L.PointList then
		L.PointList = {}
		for _, v in ipairs(util.JSONToTable(DB.GetSetting(pointsKey(), "") or "") or {}) do
			if istable(v) and tonumber(v[1]) then
				L.PointList[#L.PointList + 1] = { pos = Vector(v[1], v[2], v[3]), tag = cleanTag(v[4]), yaw = tonumber(v[5]), exact = tonumber(v[5]) ~= nil }
			end
		end
	end
	return L.PointList
end

local function savePoints()
	local raw = {}
	for _, v in ipairs(L.Points()) do
		raw[#raw + 1] = { math.Round(v.pos.x, 1), math.Round(v.pos.y, 1), math.Round(v.pos.z, 1), v.tag, v.exact and math.Round(v.yaw or 0) or nil }
	end
	DB.SetSetting(pointsKey(), util.TableToJSON(raw))
end

function L.AddPoint(pos, tag, yaw)
	local list = L.Points()
	if #list >= L.MAX_POINTS then return false end
	list[#list + 1] = { pos = pos, tag = cleanTag(tag), yaw = yaw, exact = yaw ~= nil }
	savePoints()
	return true
end

function L.TagCounts()
	local out = {}
	for _, v in ipairs(L.Points()) do
		local k = v.tag ~= "" and v.tag or "untagged"
		out[k] = (out[k] or 0) + 1
	end
	return out
end

function L.RemoveNearestPoint(pos, maxDist)
	local list = L.Points()
	local best, bd = nil, (maxDist or 300) ^ 2
	for i, v in ipairs(list) do
		local d = v.pos:DistToSqr(pos)
		if d < bd then best, bd = i, d end
	end
	if not best then return false end
	table.remove(list, best)
	savePoints()
	return true
end

local function loadRefill()
	local out = {}
	for k, v in pairs(util.JSONToTable(DB.GetSetting("loot_refill", "") or "") or {}) do
		local cid, p, m = tonumber(k), tonumber(v.p), tonumber(v.m)
		if cid and p and m then out[cid] = { p = p, m = m } end
	end
	return out
end

L.Refill = loadRefill()

local function saveRefill()
	local raw = {}
	for cid, r in pairs(L.Refill) do raw[tostring(cid)] = { p = r.p, m = r.m } end
	DB.SetSetting("loot_refill", util.TableToJSON(raw))
end

function L.RefillOf(cid)
	return L.Refill[cid]
end

local function num(v, def, lo, hi)
	return math.Clamp(math.floor(tonumber(v) or def), lo, hi)
end

local function sanitize(t, old)
	if type(t) ~= "table" then return nil, "Invalid data." end
	local p = { id = old and old.id }
	p.name = string.Trim(tostring(t.name or "")):sub(1, 40)
	if p.name == "" then return nil, "Name cannot be empty." end
	local model = string.Trim(tostring(t.model or "")):sub(1, 128)
	if model == "" then model = L.DEFAULT_MODEL end
	if not model:lower():match("%.mdl$") or not util.IsValidModel(model) then return nil, "Model not found on the server." end
	p.model = model
	p.w = num(t.w, 6, 1, 20)
	p.h = num(t.h, 4, 1, 20)
	p.max = num(t.max, 5, 1, 50)
	p.interval = num(t.interval, 120, 10, 7200)
	p.life = num(t.life, 15, 1, 240)
	p.empty_time = num(t.empty_time, 60, 5, 1800)
	p.min_dist = num(t.min_dist, 1200, 0, 20000)
	p.enabled = t.enabled ~= false
	local tags = {}
	for tg in string.gmatch(tostring(t.tags or ""), "[^,%s]+") do
		local c = cleanTag(tg)
		if c ~= "" and #tags < 10 then tags[#tags + 1] = c end
	end
	p.tags = table.concat(tags, ",")
	p.loot = {}
	for _, e in ipairs(istable(t.loot) and t.loot or {}) do
		if #p.loot >= L.MAX_LOOT then break end
		local def = istable(e) and RPInv.Items[tostring(e.item or "")]
		if def then
			local mn = num(e.min, 1, 1, 999)
			local mx = math.Clamp(math.floor(tonumber(e.max) or mn), mn, 999)
			p.loot[#p.loot + 1] = { item = def.id, chance = math.Clamp(tonumber(e.chance) or 50, 0.1, 100), min = mn, max = mx }
		end
	end
	return p
end

function L.RollLoot(preset, st)
	DB.Transaction(function()
		for _, e in ipairs(preset.loot or {}) do
			if RPInv.Items[e.item] and math.Rand(0, 100) < e.chance then
				RPInv.GiveToStorage(st, e.item, math.random(e.min, e.max))
			end
		end
	end)
end

local function alive(presetId)
	local n = 0
	for _, e in ipairs(ents.FindByClass("rpinv_lootbox")) do
		if IsValid(e) and (presetId == nil or e.RPInvLootPreset == presetId) then n = n + 1 end
	end
	return n
end
L.Alive = alive

local function groundAt(pos)
	local tr = util.TraceLine({ start = pos + Vector(0, 0, 48), endpos = pos - Vector(0, 0, 400), mask = MASK_SOLID_BRUSHONLY })
	if not tr.Hit or tr.StartSolid then return nil end
	return tr.HitPos, tr.HitNormal
end

local function occupied(pos)
	for _, e in ipairs(ents.FindInSphere(pos, 72)) do
		if IsValid(e) and (e:GetClass() == "rpinv_lootbox" or e:GetClass() == "rpinv_airdrop" or e:GetClass() == "rpinv_container") then return true end
	end
	return false
end

local function seenOrNear(pos, minDist)
	local target = pos + Vector(0, 0, 24)
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() then
			local eye = p:EyePos()
			local d = eye:Distance(target)
			if d < minDist then return true end
			if d < 7000 then
				local dir = (target - eye):GetNormalized()
				if p:GetAimVector():Dot(dir) > 0.4 then
					local tr = util.TraceLine({ start = eye, endpos = target, mask = MASK_OPAQUE, filter = p })
					if not tr.Hit or tr.HitPos:DistToSqr(target) < 48 * 48 then return true end
				end
			end
		end
	end
	return false
end

local function tagSet(preset)
	local set, any = {}, false
	for t in string.gmatch(preset.tags or "", "[^,%s]+") do
		set[cleanTag(t)] = true
		any = true
	end
	return any and set or nil
end

local function candidate(preset)
	local pts = L.Points()
	if #pts > 0 then
		local set = tagSet(preset)
		if not set then return pts[math.random(#pts)] end
		local pool = {}
		for _, v in ipairs(pts) do
			if set[v.tag ~= "" and v.tag or "untagged"] then pool[#pool + 1] = v end
		end
		if #pool == 0 then return nil end
		return pool[math.random(#pool)]
	end
	if navmesh and navmesh.IsLoaded and navmesh.IsLoaded() then
		local areas = navmesh.GetAllNavAreas()
		local a = areas[math.random(math.max(#areas, 1))]
		if a and not a:IsUnderwater() then return { pos = a:GetRandomPoint() } end
	end
end

function L.FindSite(preset)
	for _ = 1, 16 do
		local pt = candidate(preset)
		if pt then
			local ground = pt.exact and pt.pos or groundAt(pt.pos)
			if ground and not occupied(ground) and not seenOrNear(ground, preset.min_dist or 1200) then return ground, pt.exact and pt.yaw or nil end
		end
	end
end

function L.Spawn(preset, ground, by, yaw)
	local ent = ents.Create("rpinv_lootbox")
	if not IsValid(ent) then return nil end
	ent:SetModel(preset.model)
	ent:SetPos(ground)
	ent:SetAngles(Angle(0, yaw or math.random(0, 359), 0))
	ent:SetCName(string.upper(preset.name))
	ent:Spawn()
	ent:Activate()
	ent:SetPos(ground - Vector(0, 0, ent:OBBMins().z))
	local c = RPInv.CreateTransient(string.upper(preset.name), preset.w, preset.h)
	c.ent = ent
	c.loot = true
	ent.RPInvLootCid = c.id
	ent.RPInvLootPreset = preset.id
	ent.RPInvLootDie = CurTime() + preset.life * 60
	ent.RPInvLootLife = preset.life * 60
	ent.RPInvLootEmptyTime = preset.empty_time
	L.RollLoot(preset, RPInv.ContainerStorage(c))
	if IsValid(by) then DB.Log(by, "loot_spawn", preset.id .. " " .. preset.name .. " " .. tostring(ground)) end
	return ent
end

function L.Opened(ent)
	if ent.RPInvLootOpened then return end
	ent.RPInvLootOpened = true
	ent.RPInvLootDie = math.max(ent.RPInvLootDie or 0, CurTime() + (ent.RPInvLootLife or 900))
end

hook.Add("RPInv_StoragePushed", "RPInv_LootEmpty", function(st)
	if st.loc ~= DB.LOC_CONTAINER then return end
	local c = RPInv.Containers[tonumber(st.locId)]
	if not c or not c.loot or not IsValid(c.ent) then return end
	if next(st.items) == nil then
		c.ent.RPInvLootEmptyAt = c.ent.RPInvLootEmptyAt or (CurTime() + (c.ent.RPInvLootEmptyTime or 60))
	else
		c.ent.RPInvLootEmptyAt = nil
	end
end)

local function wipe(st)
	DB.Transaction(function()
		for id in pairs(st.items) do DB.DeleteInst(id) end
	end)
	st.items = {}
end

local function openBy(cid)
	for _, p in ipairs(player.GetAll()) do
		if p.RPInvOpen == cid then return true end
	end
	return false
end

local PROP_CLASSES = { prop_physics = true, prop_physics_multiplayer = true, prop_physics_override = true, prop_dynamic = true, prop_dynamic_override = true }

local function loadPropLoot()
	local out = {}
	for k, v in pairs(util.JSONToTable(DB.GetSetting("loot_props", "") or "") or {}) do
		if isstring(k) and istable(v) and tonumber(v.p) and tonumber(v.m) then out[string.lower(k)] = { p = tonumber(v.p), m = tonumber(v.m) } end
	end
	return out
end

L.PropLoot = loadPropLoot()
L.PropBoxes = L.PropBoxes or {}

local function syncPropModels()
	local models = {}
	for m in pairs(L.PropLoot) do models[m] = true end
	S.loot_prop_models = models
end
syncPropModels()

local function savePropLoot()
	DB.SetSetting("loot_props", util.TableToJSON(L.PropLoot))
	syncPropModels()
	if RPInv.SendSettings then RPInv.SendSettings() end
end

local function propBox(ent)
	local cfg = L.PropLoot[string.lower(ent:GetModel() or "")]
	local preset = cfg and L.Presets[cfg.p]
	if not preset then return nil end
	local cid = ent.RPInvPropCid
	if cid and RPInv.Containers[cid] then return cid end
	local c = RPInv.CreateTransient(string.upper(preset.name), preset.w, preset.h)
	c.ent = ent
	c.propLoot = true
	ent.RPInvPropCid = c.id
	ent.RPInvPropNext = CurTime() + cfg.m * 60
	ent:CallOnRemove("RPInvPropLoot", function(e)
		if e.RPInvPropCid and RPInv.Containers[e.RPInvPropCid] then RPInv.DeleteContainer(e.RPInvPropCid) end
	end)
	L.PropBoxes[ent] = true
	L.RollLoot(preset, RPInv.ContainerStorage(c))
	return c.id
end

hook.Add("PlayerUse", "RPInv_PropLoot", function(ply, ent)
	if not IsValid(ent) or not PROP_CLASSES[ent:GetClass()] or not L.PropLoot[string.lower(ent:GetModel() or "")] then return end
	if not ply:KeyPressed(IN_USE) then return false end
	local cid = propBox(ent)
	if not cid then return end
	RPInv.OpenContainerId(ply, cid)
	return false
end)

L.NextSpawn = L.NextSpawn or {}
L.NextRefill = L.NextRefill or {}

timer.Create("RPInv_LootTick", L.TICK, 0, function()
	local now = CurTime()
	for _, e in ipairs(ents.FindByClass("rpinv_lootbox")) do
		if IsValid(e) then
			local cid = e.RPInvLootCid
			local gone = (e.RPInvLootEmptyAt and now >= e.RPInvLootEmptyAt) or (e.RPInvLootDie and now >= e.RPInvLootDie)
			if gone and not (cid and openBy(cid)) then e:Remove() end
		end
	end
	for cid, r in pairs(L.Refill) do
		local c = RPInv.Containers[cid]
		local preset = L.Presets[r.p]
		if c and not c.transient and preset then
			L.NextRefill[cid] = L.NextRefill[cid] or (now + r.m * 60)
			if now >= L.NextRefill[cid] and not openBy(cid) then
				L.NextRefill[cid] = now + r.m * 60
				local st = RPInv.ContainerStorage(c)
				wipe(st)
				L.RollLoot(preset, st)
				RPInv.Push(st)
			end
		end
	end
	for e in pairs(L.PropBoxes) do
		if not IsValid(e) or not e.RPInvPropCid or not RPInv.Containers[e.RPInvPropCid] then
			L.PropBoxes[e] = nil
		else
			local cfg = L.PropLoot[string.lower(e:GetModel() or "")]
			local preset = cfg and L.Presets[cfg.p]
			if preset and now >= (e.RPInvPropNext or 0) and not openBy(e.RPInvPropCid) then
				e.RPInvPropNext = now + cfg.m * 60
				local st = RPInv.ContainerStorage(RPInv.Containers[e.RPInvPropCid])
				wipe(st)
				L.RollLoot(preset, st)
				RPInv.Push(st)
			end
		end
	end
	if not S.loot_enabled or #player.GetAll() == 0 then return end
	for id, preset in pairs(L.Presets) do
		if preset.enabled and now >= (L.NextSpawn[id] or 0) then
			if alive(id) >= preset.max then
				L.NextSpawn[id] = now + L.TICK
			else
				local site, yaw = L.FindSite(preset)
				if site and L.Spawn(preset, site, nil, yaw) then
					L.NextSpawn[id] = now + preset.interval
				else
					L.NextSpawn[id] = now + 15
				end
			end
		end
	end
end)

local function listPayload()
	local list = {}
	for _, p in SortedPairs(L.Presets) do
		local c = table.Copy(p)
		c.alive = alive(p.id)
		list[#list + 1] = c
	end
	local refill = {}
	for cid, r in pairs(L.Refill) do refill[tostring(cid)] = r end
	local props = {}
	for m, r in SortedPairs(L.PropLoot) do props[#props + 1] = { model = m, p = r.p, m = r.m } end
	local pl = {}
	for _, v in ipairs(L.Points()) do pl[#pl + 1] = { math.Round(v.pos.x), math.Round(v.pos.y), math.Round(v.pos.z), v.tag, v.exact and math.Round(v.yaw or 0) or nil } end
	return { presets = list, points = #L.Points(), pointList = pl, tags = L.TagCounts(), enabled = S.loot_enabled, refill = refill, props = props }
end

local function sendList(ply)
	RPInv.SendJSON("rpinv_lt_list_r", listPayload(), ply)
end
L.SendList = sendList

local function broadcastAdmins()
	for _, p in ipairs(player.GetAll()) do
		if RPInv.IsAdmin(p) then sendList(p) end
	end
end

net.Receive("rpinv_lt_list", function(_, ply)
	if RPInv.IsAdmin(ply) then sendList(ply) end
end)

net.Receive("rpinv_lt_save", function(_, ply)
	local t = RPInv.ReadJSON(32000)
	if not RPInv.IsAdmin(ply) or type(t) ~= "table" then return end
	local old = t.id and L.Presets[tonumber(t.id) or -1]
	if not old and table.Count(L.Presets) >= L.MAX_PRESETS then RPInv.Notify(ply, "Loot preset limit reached.", 2) return end
	local p, err = sanitize(t, old)
	if not p then RPInv.Notify(ply, err, 2) return end
	if not p.id then
		local max = 0
		for id in pairs(L.Presets) do max = math.max(max, id) end
		p.id = max + 1
	end
	L.Presets[p.id] = p
	savePresets()
	DB.Log(ply, "loot_save", p.id .. " " .. p.name)
	RPInv.Notify(ply, "Loot preset saved: " .. p.name, 1)
	broadcastAdmins()
end)

net.Receive("rpinv_lt_delete", function(_, ply)
	local id = net.ReadUInt(16)
	local p = L.Presets[id]
	if not RPInv.IsAdmin(ply) or not p then return end
	L.Presets[id] = nil
	savePresets()
	for _, e in ipairs(ents.FindByClass("rpinv_lootbox")) do
		if IsValid(e) and e.RPInvLootPreset == id then e:Remove() end
	end
	DB.Log(ply, "loot_delete", id .. " " .. p.name)
	RPInv.Notify(ply, "Loot preset deleted: " .. p.name, 1)
	broadcastAdmins()
end)

net.Receive("rpinv_lt_settings", function(_, ply)
	local t = RPInv.ReadJSON(256)
	if not RPInv.IsAdmin(ply) or type(t) ~= "table" then return end
	if t.enabled ~= nil then S.loot_enabled = t.enabled == true end
	DB.SetSetting("loot_enabled", S.loot_enabled and "1" or "0")
	DB.Log(ply, "loot_settings", "enabled=" .. tostring(S.loot_enabled))
	RPInv.Notify(ply, "Loot spawns " .. (S.loot_enabled and "enabled." or "disabled."), 1)
	broadcastAdmins()
end)

net.Receive("rpinv_lt_clearpoints", function(_, ply)
	if not RPInv.IsAdmin(ply) then return end
	L.PointList = {}
	savePoints()
	DB.Log(ply, "loot_points_clear", game.GetMap())
	RPInv.Notify(ply, "All loot spawn points on this map were removed.", 1)
	broadcastAdmins()
end)

function L.SpawnAtAim(ply, preset)
	if not preset then return false, "Unknown loot preset." end
	local tr = ply:GetEyeTrace()
	local ground = groundAt(tr.HitPos + tr.HitNormal * 4)
	if not ground then return false, "No ground there." end
	if not L.Spawn(preset, ground, ply, ply:EyeAngles().y + 180) then return false, "Could not spawn the container." end
	return true
end

net.Receive("rpinv_lt_spawnnow", function(_, ply)
	local id = net.ReadUInt(16)
	if not RPInv.IsAdmin(ply) then return end
	if (ply.RPInvNextLoot or 0) > CurTime() then return end
	ply.RPInvNextLoot = CurTime() + 0.5
	local ok, err = L.SpawnAtAim(ply, L.Presets[id])
	RPInv.Notify(ply, ok and "Loot container spawned." or err, ok and 1 or 2)
	if ok then broadcastAdmins() end
end)

net.Receive("rpinv_lt_refill", function(_, ply)
	local cid = net.ReadUInt(32)
	local pid = net.ReadUInt(16)
	local minutes = net.ReadUInt(16)
	if not RPInv.IsAdmin(ply) then return end
	local c = RPInv.Containers[cid]
	if not c or c.transient then return end
	if pid == 0 or not L.Presets[pid] then
		L.Refill[cid] = nil
		L.NextRefill[cid] = nil
		RPInv.Notify(ply, "Refill turned off for " .. c.name .. ".", 1)
	else
		minutes = math.Clamp(minutes, 1, 1440)
		L.Refill[cid] = { p = pid, m = minutes }
		L.NextRefill[cid] = CurTime()
		RPInv.Notify(ply, c.name .. " refills from " .. L.Presets[pid].name .. " every " .. minutes .. " min (first refill now).", 1)
	end
	saveRefill()
	DB.Log(ply, "loot_refill", cid .. " preset=" .. pid .. " min=" .. minutes)
	broadcastAdmins()
	if RPInv.SendContainerList then RPInv.SendContainerList(ply) end
end)

net.Receive("rpinv_lt_propset", function(_, ply)
	local pid = net.ReadUInt(16)
	local minutes = math.Clamp(net.ReadUInt(16), 1, 1440)
	if not RPInv.IsAdmin(ply) then return end
	local ent = ply:GetEyeTrace().Entity
	if not IsValid(ent) or not PROP_CLASSES[ent:GetClass()] then
		RPInv.Notify(ply, "Aim at a map prop (prop_physics or prop_dynamic).", 2)
		return
	end
	local preset = L.Presets[pid]
	if not preset then RPInv.Notify(ply, "Select a loot preset first.", 2) return end
	local model = string.lower(ent:GetModel() or "")
	if model == "" then return end
	if table.Count(L.PropLoot) >= 100 and not L.PropLoot[model] then RPInv.Notify(ply, "Limit of 100 prop models reached.", 2) return end
	L.PropLoot[model] = { p = pid, m = minutes }
	savePropLoot()
	DB.Log(ply, "loot_prop_set", model .. " preset=" .. pid .. " min=" .. minutes)
	RPInv.Notify(ply, "Every " .. string.GetFileFromFilename(model) .. " is now lootable (" .. preset.name .. ", refills every " .. minutes .. " min).", 1)
	broadcastAdmins()
end)

net.Receive("rpinv_lt_propdel", function(_, ply)
	local model = string.lower(net.ReadString())
	if not RPInv.IsAdmin(ply) or not L.PropLoot[model] then return end
	L.PropLoot[model] = nil
	savePropLoot()
	for e in pairs(L.PropBoxes) do
		if IsValid(e) and string.lower(e:GetModel() or "") == model then
			if e.RPInvPropCid and RPInv.Containers[e.RPInvPropCid] then RPInv.DeleteContainer(e.RPInvPropCid) end
			e.RPInvPropCid = nil
			L.PropBoxes[e] = nil
		end
	end
	DB.Log(ply, "loot_prop_del", model)
	RPInv.Notify(ply, "Prop model is no longer lootable.", 1)
	broadcastAdmins()
end)

hook.Add("RPInv_ItemDeleted", "RPInv_LootItemDeleted", function()
	local changed = false
	for _, p in pairs(L.Presets) do
		for i = #p.loot, 1, -1 do
			if not RPInv.Items[p.loot[i].item] then
				table.remove(p.loot, i)
				changed = true
			end
		end
	end
	if changed then savePresets() end
end)
