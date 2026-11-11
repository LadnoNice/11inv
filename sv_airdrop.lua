local DB = RPInv.DB
local AD = RPInv.Airdrop or {}
RPInv.Airdrop = AD

for _, n in ipairs({
	"rpinv_ad_list", "rpinv_ad_list_r", "rpinv_ad_save", "rpinv_ad_delete", "rpinv_ad_call",
	"rpinv_ad_settings", "rpinv_ad_clearpoints", "rpinv_ad_plane", "rpinv_ad_flareitem",
}) do util.AddNetworkString(n) end

AD.DEFAULT_MODEL = "models/items/ammocrate_smg1.mdl"
AD.MAX_PRESETS = 50
AD.MAX_LOOT = 60
AD.MAX_ALIVE = 6
AD.FALL_SPEED = 57
AD.CALL_DELAY = 20
AD.Pending = AD.Pending or 0
AD.PLANE_LEAD = 8.5
AD.PLANE_SPEED = 750
AD.PLANE_RANGE = 32768

for _, m in ipairs({ "models/wc_3dregenerator_ac130.mdl", "models/parachute/chute.mdl", "models/weapons/v_flaregun.mdl" }) do
	util.PrecacheModel(m)
end
util.PrecacheSound("rpinv/airdrop_plane.wav")

local S = RPInv.Settings
S.airdrop_auto = DB.GetSetting("airdrop_auto", "1") ~= "0"
S.airdrop_interval = math.Clamp(tonumber(DB.GetSetting("airdrop_interval", "30")) or 30, 5, 240)
S.airdrop_announce = DB.GetSetting("airdrop_announce", "1") ~= "0"

local function loadPresets()
	local t = util.JSONToTable(DB.GetSetting("airdrop_presets", "") or "") or {}
	local out = {}
	for _, p in pairs(t) do
		if istable(p) and tonumber(p.id) then out[tonumber(p.id)] = p end
	end
	return out
end

AD.Presets = loadPresets()

local function savePresets()
	local list = {}
	for _, p in SortedPairs(AD.Presets) do list[#list + 1] = p end
	DB.SetSetting("airdrop_presets", util.TableToJSON(list))
end

local function pointsKey() return "airdrop_points_" .. game.GetMap() end

function AD.Points()
	if not AD.PointList then
		local raw = util.JSONToTable(DB.GetSetting(pointsKey(), "") or "") or {}
		AD.PointList = {}
		for _, v in ipairs(raw) do
			if istable(v) and tonumber(v[1]) then AD.PointList[#AD.PointList + 1] = Vector(v[1], v[2], v[3]) end
		end
	end
	return AD.PointList
end

local function savePoints()
	local raw = {}
	for _, v in ipairs(AD.Points()) do raw[#raw + 1] = { math.Round(v.x), math.Round(v.y), math.Round(v.z) } end
	DB.SetSetting(pointsKey(), util.TableToJSON(raw))
end

function AD.AddPoint(pos)
	local list = AD.Points()
	if #list >= 200 then return false end
	list[#list + 1] = pos
	savePoints()
	return true
end

function AD.RemoveNearestPoint(pos, maxDist)
	local list = AD.Points()
	local best, bd = nil, (maxDist or 300) ^ 2
	for i, v in ipairs(list) do
		local d = v:DistToSqr(pos)
		if d < bd then best, bd = i, d end
	end
	if not best then return false end
	table.remove(list, best)
	savePoints()
	return true
end

local function sanitize(t, old)
	if type(t) ~= "table" then return nil, "Invalid data." end
	local p = { id = old and old.id }
	p.name = string.Trim(tostring(t.name or "")):sub(1, 40)
	if p.name == "" then return nil, "Name cannot be empty." end
	local model = string.Trim(tostring(t.model or "")):sub(1, 128)
	if model == "" then model = AD.DEFAULT_MODEL end
	if not model:lower():match("%.mdl$") or not util.IsValidModel(model) then return nil, "Model not found on the server." end
	p.model = model
	p.w = math.Clamp(math.floor(tonumber(t.w) or 8), 1, 20)
	p.h = math.Clamp(math.floor(tonumber(t.h) or 6), 1, 20)
	p.life = math.Clamp(math.floor(tonumber(t.life) or 10), 1, 120)
	p.smoke_time = math.Clamp(math.floor(tonumber(t.smoke_time) or 3), 0, 60)
	local c = istable(t.smoke) and t.smoke or {}
	p.smoke = { math.Clamp(math.floor(tonumber(c[1]) or 230), 0, 255), math.Clamp(math.floor(tonumber(c[2]) or 30), 0, 255), math.Clamp(math.floor(tonumber(c[3]) or 20), 0, 255) }
	p.auto = t.auto == true
	p.weight = math.Clamp(math.floor(tonumber(t.weight) or 1), 1, 100)
	p.loot = {}
	for _, e in ipairs(istable(t.loot) and t.loot or {}) do
		if #p.loot >= AD.MAX_LOOT then break end
		local def = istable(e) and RPInv.Items[tostring(e.item or "")]
		if def then
			local mn = math.Clamp(math.floor(tonumber(e.min) or 1), 1, 999)
			local mx = math.Clamp(math.floor(tonumber(e.max) or mn), mn, 999)
			p.loot[#p.loot + 1] = { item = def.id, chance = math.Clamp(tonumber(e.chance) or 50, 0.1, 100), min = mn, max = mx }
		end
	end
	return p
end

local function listPayload()
	local list = {}
	for _, p in SortedPairs(AD.Presets) do list[#list + 1] = p end
	return {
		presets = list, points = #AD.Points(),
		auto = S.airdrop_auto, interval = S.airdrop_interval, announce = S.airdrop_announce,
	}
end

local function sendList(ply)
	RPInv.SendJSON("rpinv_ad_list_r", listPayload(), ply)
end
AD.SendList = sendList

local function broadcastAdmins()
	for _, p in ipairs(player.GetAll()) do
		if RPInv.IsAdmin(p) then sendList(p) end
	end
end

function AD.RollLoot(preset, st)
	local defs = RPInv.Items
	DB.Transaction(function()
		for _, e in ipairs(preset.loot or {}) do
			if defs[e.item] and math.Rand(0, 100) < e.chance then
				RPInv.GiveToStorage(st, e.item, math.random(e.min, e.max))
			end
		end
	end)
end

local function groundBelow(pos)
	local tr = util.TraceLine({ start = pos + Vector(0, 0, 64), endpos = pos - Vector(0, 0, 16384), mask = MASK_SOLID_BRUSHONLY })
	if not tr.Hit then return nil end
	return tr.HitPos
end

local function skyAbove(pos)
	local tr = util.TraceLine({ start = pos + Vector(0, 0, 16), endpos = pos + Vector(0, 0, 16384), mask = MASK_SOLID_BRUSHONLY })
	if tr.HitSky or not tr.Hit then return tr.HitPos end
	if tr.HitTexture and string.find(string.lower(tr.HitTexture), "skybox", 1, true) then return tr.HitPos end
	return nil
end

function AD.DropSite(pos)
	local ground = groundBelow(pos)
	if not ground then return nil, "No ground under that point." end
	local sky = skyAbove(ground)
	if not sky then return nil, "There is no open sky above that point." end
	local room = sky.z - ground.z
	if room < 300 then return nil, "The sky is too low there." end
	local plane = math.max(math.min(sky.z - 450, ground.z + 4400), ground.z + 260)
	local top = math.Clamp(plane - 160, ground.z + 150, sky.z - 80)
	return ground, top, plane, sky.z
end

function AD.Alive()
	local n = 0
	for _, e in ipairs(ents.FindByClass("rpinv_airdrop")) do
		if IsValid(e) then n = n + 1 end
	end
	return n
end

local function announce(preset, ground)
	if not S.airdrop_announce then return end
	for _, p in ipairs(player.GetAll()) do
		RPInv.Notify(p, "AIRDROP INCOMING: " .. string.upper(preset.name) .. ". Look for the smoke.", 0)
	end
end

function AD.Call(preset, pos, by)
	if not preset then return false, "Unknown airdrop preset." end
	if AD.Alive() + AD.Pending >= AD.MAX_ALIVE then return false, "Too many airdrops are active." end
	local ground, top, planeZ, skyZ = AD.DropSite(pos)
	if not ground then return false, top end
	local scale = math.Clamp((skyZ - planeZ - 40) / 256, 0.5, 1.6)
	local over = Vector(ground.x, ground.y, planeZ)
	local function reach(d)
		local last, gap = 0, 0
		for dist = 256, AD.PLANE_RANGE, 256 do
			if util.IsInWorld(over + d * dist) then
				last, gap = dist, 0
			else
				gap = gap + 256
				if gap > 4096 then break end
			end
		end
		return math.max(0, last - 300)
	end
	local bestYaw, bestBack, bestFwd, bestLen = 0, 0, 0, -1
	local base = math.random(0, 359)
	for i = 0, 11 do
		local yaw = (base + i * 30) % 360
		local d = Angle(0, yaw, 0):Forward()
		local back, fwd = reach(-d), reach(d)
		local len = back + fwd + math.min(back, fwd) * 0.5
		if len > bestLen then bestYaw, bestBack, bestFwd, bestLen = yaw, back, fwd, len end
	end
	announce(preset, ground)
	DB.Log(by, "airdrop_call", preset.id .. " " .. preset.name .. " " .. tostring(ground))
	local copy = table.Copy(preset)
	AD.Pending = AD.Pending + 1
	timer.Simple(AD.CALL_DELAY, function()
		net.Start("rpinv_ad_plane")
		net.WriteVector(over)
		net.WriteFloat(bestYaw)
		net.WriteFloat(math.max(AD.PLANE_SPEED, bestBack / AD.PLANE_LEAD))
		net.WriteFloat(bestBack)
		net.WriteFloat(bestFwd)
		net.WriteFloat(AD.PLANE_LEAD)
		net.WriteFloat(scale)
		net.Broadcast()
		timer.Simple(AD.PLANE_LEAD, function()
			AD.Pending = math.max(0, AD.Pending - 1)
			local ent = ents.Create("rpinv_airdrop")
			if not IsValid(ent) then return end
			ent:SetModel(copy.model)
			ent:SetPos(Vector(ground.x, ground.y, top))
			ent:SetAngles(Angle(0, math.random(0, 359), 0))
			ent.RPInvPreset = copy
			ent.RPInvGround = ground
			ent:SetSmokeColor(Vector(copy.smoke[1] / 255, copy.smoke[2] / 255, copy.smoke[3] / 255))
			ent:Spawn()
			ent:Activate()
		end)
	end)
	return true
end

function AD.Land(ent)
	local preset = ent.RPInvPreset
	if not preset then ent:Remove() return end
	local c = RPInv.CreateTransient("AIRDROP: " .. string.upper(preset.name), preset.w, preset.h)
	c.ent = ent
	c.airdrop = true
	ent.RPInvAirdropCid = c.id
	AD.RollLoot(preset, RPInv.ContainerStorage(c))
	ent:SetSmokeUntil(CurTime() + preset.smoke_time * 60)
	ent:SetLanded(true)
	ent:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 85, 90)
	local fx = EffectData()
	fx:SetOrigin(ent:GetPos())
	fx:SetScale(0.6)
	util.Effect("ThumperDust", fx, true, true)
	timer.Create("RPInv_Airdrop" .. ent:EntIndex(), preset.life * 60, 1, function()
		if IsValid(ent) then ent:Remove() end
	end)
end

local function pickPreset(onlyAuto)
	local pool, total = {}, 0
	for _, p in pairs(AD.Presets) do
		if not onlyAuto or p.auto then
			pool[#pool + 1] = p
			total = total + (p.weight or 1)
		end
	end
	if total <= 0 then return nil end
	local r = math.Rand(0, total)
	for _, p in ipairs(pool) do
		r = r - (p.weight or 1)
		if r <= 0 then return p end
	end
	return pool[#pool]
end
AD.PickPreset = pickPreset

function AD.RandomSite()
	local pts = AD.Points()
	for _ = 1, 12 do
		local pos
		if #pts > 0 then
			pos = pts[math.random(#pts)]
		elseif navmesh and navmesh.IsLoaded and navmesh.IsLoaded() then
			local areas = navmesh.GetAllNavAreas()
			local a = areas[math.random(#areas)]
			pos = a and a:GetCenter()
		else
			local plys = player.GetAll()
			local p = plys[math.random(#plys)]
			if IsValid(p) then pos = p:GetPos() + Angle(0, math.random(0, 359), 0):Forward() * math.random(800, 2500) end
		end
		if pos and AD.DropSite(pos) then return pos end
	end
end

function AD.CallRandom(preset, by)
	local pos = AD.RandomSite()
	if not pos then return false, "No open spot for an airdrop was found. Add drop points with the RP Airdrop tool." end
	return AD.Call(preset, pos, by)
end

AD.FLARE_MIN_HEIGHT = 600
AD.FLARE_CLASS = "rpinv_flaregun"
AD.FLARE_MODEL = "models/weapons/v_flaregun.mdl"

timer.Simple(0, function()
	local changed = false
	for _, d in pairs(RPInv.Items) do
		if d.use_type == "flare" and d.model == "models/weapons/w_357.mdl" then
			d.model = AD.FLARE_MODEL
			DB.SaveItem(d)
			changed = true
		end
	end
	if changed then RPInv.SendItems() end
end)

function AD.FlarePresets(arg)
	local out = {}
	for n in tostring(arg or ""):gmatch("%d+") do
		local p = AD.Presets[tonumber(n)]
		if p then out[#out + 1] = p end
	end
	return out
end

function AD.FlareCall(arg, under, by)
	local pool = AD.FlarePresets(arg)
	local preset
	if string.find(tostring(arg or ""), "%d") then
		if #pool == 0 then return false, "This flare gun has no valid airdrop presets." end
		local total = 0
		for _, p in ipairs(pool) do total = total + (p.weight or 1) end
		local r = math.Rand(0, total)
		for _, p in ipairs(pool) do
			r = r - (p.weight or 1)
			if r <= 0 then preset = p break end
		end
		preset = preset or pool[#pool]
	else
		preset = pickPreset(false)
	end
	if not preset then return false, "There are no airdrop presets." end
	return AD.Call(preset, under + Vector(0, 0, 8), by)
end

function AD.GiveFlareGun(ply, def)
	if ply:GetNW2Bool("RPInvSurrender", false) then return false, "You cannot do that with your hands up." end
	if ply:HasWeapon(AD.FLARE_CLASS) then return false, "You are already holding a flare gun." end
	local wep = ply:Give(AD.FLARE_CLASS)
	if not IsValid(wep) then return false, "The flare gun is not available." end
	wep.RPInvItem = def.id
	wep.RPInvPresets = def.use_arg or ""
	wep.RPInvHolder = ply
	ply:SelectWeapon(AD.FLARE_CLASS)
	return true
end

net.Receive("rpinv_ad_flareitem", function(_, ply)
	local id = net.ReadUInt(16)
	local p = AD.Presets[id]
	if not RPInv.IsAdmin(ply) or not p then return end
	local itemId = "flare_" .. id
	local def = {
		id = itemId, name = string.sub("Flare Gun: " .. p.name, 1, 40), model = AD.FLARE_MODEL,
		descr = "Fire it straight up into open sky to call the airdrop \"" .. p.name .. "\".",
		max_stack = 1, use_type = "flare", use_arg = tostring(id), w = 2, h = 1, rotatable = true,
		category = "Airdrop", cam_ang = "0 0 0", cam_fov = 1, equip_slot = "", grid_w = 0, grid_h = 0,
		jmod_armor = "", world_class = "",
	}
	RPInv.Items[itemId] = def
	DB.SaveItem(def)
	DB.Log(ply, "airdrop_flare_item", itemId)
	RPInv.SendItems()
	RPInv.Notify(ply, "Item created: " .. def.name .. " (ID " .. itemId .. "). Edit it in the ITEMS tab.", 1)
end)

AD.NextAuto = AD.NextAuto or (CurTime() + S.airdrop_interval * 60)

timer.Create("RPInv_AirdropAuto", 10, 0, function()
	if not S.airdrop_auto or #player.GetAll() == 0 then return end
	if CurTime() < AD.NextAuto then return end
	AD.NextAuto = CurTime() + S.airdrop_interval * 60
	local preset = pickPreset(true)
	if preset then AD.CallRandom(preset, nil) end
end)

net.Receive("rpinv_ad_list", function(_, ply)
	if RPInv.IsAdmin(ply) then sendList(ply) end
end)

net.Receive("rpinv_ad_save", function(_, ply)
	local t = RPInv.ReadJSON(32000)
	if not RPInv.IsAdmin(ply) or type(t) ~= "table" then return end
	local old = t.id and AD.Presets[tonumber(t.id) or -1]
	if not old and table.Count(AD.Presets) >= AD.MAX_PRESETS then RPInv.Notify(ply, "Airdrop preset limit reached.", 2) return end
	local p, err = sanitize(t, old)
	if not p then RPInv.Notify(ply, err, 2) return end
	if not p.id then
		local max = 0
		for id in pairs(AD.Presets) do max = math.max(max, id) end
		p.id = max + 1
	end
	AD.Presets[p.id] = p
	savePresets()
	DB.Log(ply, "airdrop_save", p.id .. " " .. p.name)
	RPInv.Notify(ply, "Airdrop preset saved: " .. p.name, 1)
	broadcastAdmins()
end)

net.Receive("rpinv_ad_delete", function(_, ply)
	local id = net.ReadUInt(16)
	local p = AD.Presets[id]
	if not RPInv.IsAdmin(ply) or not p then return end
	AD.Presets[id] = nil
	savePresets()
	DB.Log(ply, "airdrop_delete", id .. " " .. p.name)
	RPInv.Notify(ply, "Airdrop preset deleted: " .. p.name, 1)
	broadcastAdmins()
end)

net.Receive("rpinv_ad_call", function(_, ply)
	local id = net.ReadUInt(16)
	local random = net.ReadBool()
	if not RPInv.IsAdmin(ply) then return end
	if (ply.RPInvNextDrop or 0) > CurTime() then return end
	ply.RPInvNextDrop = CurTime() + 1
	local preset = AD.Presets[id]
	local ok, err
	if random then
		ok, err = AD.CallRandom(preset, ply)
	else
		ok, err = AD.Call(preset, ply:GetEyeTrace().HitPos, ply)
	end
	RPInv.Notify(ply, ok and "Airdrop called." or (err or "Could not call an airdrop."), ok and 1 or 2)
end)

net.Receive("rpinv_ad_settings", function(_, ply)
	local t = RPInv.ReadJSON(1024)
	if not RPInv.IsAdmin(ply) or type(t) ~= "table" then return end
	if t.auto ~= nil then S.airdrop_auto = t.auto == true end
	if t.announce ~= nil then S.airdrop_announce = t.announce == true end
	if tonumber(t.interval) then
		S.airdrop_interval = math.Clamp(math.floor(tonumber(t.interval)), 5, 240)
		AD.NextAuto = math.min(AD.NextAuto, CurTime() + S.airdrop_interval * 60)
	end
	DB.SetSetting("airdrop_auto", S.airdrop_auto and "1" or "0")
	DB.SetSetting("airdrop_announce", S.airdrop_announce and "1" or "0")
	DB.SetSetting("airdrop_interval", S.airdrop_interval)
	DB.Log(ply, "airdrop_settings", "auto=" .. tostring(S.airdrop_auto) .. " every " .. S.airdrop_interval .. " min")
	RPInv.Notify(ply, "Airdrop settings saved.", 1)
	broadcastAdmins()
end)

net.Receive("rpinv_ad_clearpoints", function(_, ply)
	if not RPInv.IsAdmin(ply) then return end
	AD.PointList = {}
	savePoints()
	DB.Log(ply, "airdrop_points_clear", game.GetMap())
	RPInv.Notify(ply, "All airdrop points on this map were removed.", 1)
	broadcastAdmins()
end)
