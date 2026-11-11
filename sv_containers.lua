local DB = RPInv.DB
RPInv.Containers = RPInv.Containers or {}

for _, n in ipairs({
	"rpinv_cexit", "rpinv_a_clist", "rpinv_a_clist_r", "rpinv_a_cspawn", "rpinv_a_cdelete",
}) do util.AddNetworkString(n) end

local USE_DIST = 160
local MAX_CONTAINERS = 200
RPInv.MaxContainers = MAX_CONTAINERS

function RPInv.SpawnContainer(c)
	local ent = ents.Create("rpinv_container")
	if not IsValid(ent) then return end
	ent:SetModel(c.model)
	ent:SetPos(c.pos)
	ent:SetAngles(c.ang)
	ent:SetCID(c.id)
	ent:SetCName(c.name)
	ent:Spawn()
	ent:Activate()
	c.ent = ent
	return ent
end

function RPInv.ContainerStorage(c)
	local key = "c:" .. c.id
	local st = RPInv.Storages[key]
	if not st then
		st = RPInv.NewStorage(DB.LOC_CONTAINER, c.id, c.w, c.h, c.name)
		RPInv.LoadStorage(st)
		RPInv.Storages[key] = st
	end
	if st.overflow and IsValid(c.ent) then RPInv.FlushOverflow(st, c.ent:GetPos() + Vector(0, 0, 40)) end
	return st
end

local function closeFor(ply)
	local cid = ply.RPInvOpen
	ply.RPInvOpen = nil
	local c = cid and RPInv.Containers[cid]
	if c and IsValid(c.ent) then
		if c.transient then
			c.ent:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 50, 110)
		else
			c.ent:EmitSound("items/ammocrate_close.wav", 55, 110)
		end
	end
	if cid and not ply:IsBot() then
		net.Start("rpinv_close")
		net.WriteUInt(cid, 32)
		net.Send(ply)
	end
end
RPInv.CloseContainerFor = closeFor

local function inRange(ply, ent)
	local eye = ply:GetShootPos()
	return eye:DistToSqr(ent:NearestPoint(eye)) <= USE_DIST * USE_DIST
end

function RPInv.ContainerAccess(ply, cid)
	if ply.RPInvOpen ~= cid then return nil end
	local c = RPInv.Containers[cid]
	if not c or not IsValid(c.ent) or not ply:Alive() or not inRange(ply, c.ent) then
		closeFor(ply)
		return nil
	end
	return RPInv.ContainerStorage(c)
end

function RPInv.OpenContainerId(ply, cid)
	local c = RPInv.Containers[cid]
	if not c or not ply:Alive() or not IsValid(c.ent) or not inRange(ply, c.ent) then return end
	if ply.RPInvOpen and ply.RPInvOpen ~= c.id then closeFor(ply) end
	ply.RPInvOpen = c.id
	local st = RPInv.ContainerStorage(c)
	c.ent:EmitSound(c.transient and "physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav" or "items/ammocrate_open.wav", 55, c.transient and 100 or 110)
	RPInv.Push(st, ply)
end

function RPInv.OpenContainer(ply, ent)
	RPInv.OpenContainerId(ply, ent:GetCID())
end

local TRANSIENT_BASE = 3000000000
local transientSerial = 0

function RPInv.CreateTransient(name, w, h)
	transientSerial = transientSerial + 1
	local c = { id = TRANSIENT_BASE + transientSerial, name = name, w = w, h = h, transient = true }
	RPInv.Containers[c.id] = c
	return c
end

DB.Query("DELETE FROM rpinv_inst WHERE loc_type = " .. DB.LOC_CONTAINER .. " AND CAST(loc_id AS INTEGER) >= " .. TRANSIENT_BASE)

function RPInv.SaveContainerPlacement(ent)
	local c = RPInv.Containers[ent:GetCID()]
	if not c or c.ent ~= ent then return end
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then
		phys:EnableMotion(false)
		phys:Sleep()
	end
	c.pos, c.ang = ent:GetPos(), ent:GetAngles()
	DB.UpdateContainerPos(c.id, c.pos, c.ang)
end

function RPInv.DeleteContainer(cid)
	local c = RPInv.Containers[cid]
	if not c then return end
	RPInv.Containers[cid] = nil
	for _, p in ipairs(player.GetAll()) do
		if p.RPInvOpen == cid then closeFor(p) end
	end
	DB.DeleteContainer(cid)
	RPInv.Storages["c:" .. cid] = nil
	if IsValid(c.ent) and not c.ent.RPInvRemoving then
		c.ent.RPInvRemoving = true
		c.ent:Remove()
	end
	return c
end

local function sendList(ply)
	local list = {}
	for id, c in SortedPairs(RPInv.Containers) do
		if not c.transient then
			local r = RPInv.Loot and RPInv.Loot.RefillOf(id)
			list[#list + 1] = { id = id, name = c.name, model = c.model, w = c.w, h = c.h, refill = r and { p = r.p, m = r.m } or nil }
		end
	end
	RPInv.SendJSON("rpinv_a_clist_r", { list = list }, ply)
end
RPInv.SendContainerList = sendList

function RPInv.OnContainerRemoved(ent)
	local by = ent.RPInvDeleteBy
	if not by or ent.RPInvRemoving then return end
	local c = RPInv.Containers[ent:GetCID()]
	if not c or c.ent ~= ent then return end
	ent.RPInvRemoving = true
	RPInv.DeleteContainer(c.id)
	DB.Log(by, "container_delete", c.id .. " " .. c.name)
	if IsValid(by) then
		RPInv.Notify(by, "Container deleted: " .. c.name, 1)
		sendList(by)
	end
end

function RPInv.CreateContainer(name, model, w, h, pos, ang)
	local c = { name = name, model = model, w = w, h = h, pos = pos, ang = ang }
	c.id = DB.CreateContainer(c)
	if not c.id then return end
	RPInv.Containers[c.id] = c
	RPInv.SpawnContainer(c)
	return c
end

function RPInv.PlaceOnGround(c, hitPos)
	if not IsValid(c.ent) then return end
	c.pos = hitPos - Vector(0, 0, c.ent:OBBMins().z)
	c.ent:SetPos(c.pos)
	DB.UpdateContainerPos(c.id, c.pos, c.ang)
end

net.Receive("rpinv_cexit", function(_, ply)
	local cid = net.ReadUInt(32)
	if ply.RPInvOpen == cid then ply.RPInvOpen = nil end
end)

local function loadAll()
	RPInv.Containers = {}
	for _, row in ipairs(DB.LoadContainers(game.GetMap())) do
		RPInv.Containers[row.id] = row
		RPInv.SpawnContainer(row)
	end
end
hook.Add("InitPostEntity", "RPInv_LoadContainers", loadAll)

hook.Add("PostCleanupMap", "RPInv_RespawnContainers", function()
	for id, c in pairs(RPInv.Containers) do
		if c.transient then
			RPInv.DeleteContainer(id)
		else
			RPInv.SpawnContainer(c)
		end
	end
end)

hook.Add("PlayerDeath", "RPInv_CloseOnDeath", function(ply)
	if ply.RPInvOpen then closeFor(ply) end
end)

timer.Create("RPInv_ViewerCheck", 0.5, 0, function()
	for _, p in ipairs(player.GetAll()) do
		if p.RPInvOpen then RPInv.ContainerAccess(p, p.RPInvOpen) end
	end
end)

net.Receive("rpinv_a_clist", function(_, ply)
	if RPInv.IsAdmin(ply) then sendList(ply) end
end)

net.Receive("rpinv_a_cspawn", function(_, ply)
	local t = RPInv.ReadJSON(1024)
	if not RPInv.IsAdmin(ply) or type(t) ~= "table" then return end
	if table.Count(RPInv.Containers) >= MAX_CONTAINERS then RPInv.Notify(ply, "Container limit reached.", 2) return end

	local name = string.Trim(tostring(t.name or "")):sub(1, 40)
	if name == "" then name = "Container" end
	local w = math.Clamp(math.floor(tonumber(t.w) or 10), 1, 20)
	local h = math.Clamp(math.floor(tonumber(t.h) or 4), 1, 20)
	local tr = ply:GetEyeTrace()

	local c
	if t.convert then
		local target = tr.Entity
		if not IsValid(target) or target:GetClass() ~= "prop_physics" then
			RPInv.Notify(ply, "Aim at a prop first.", 2)
			return
		end
		local model, pos, ang = target:GetModel(), target:GetPos(), target:GetAngles()
		target:Remove()
		c = RPInv.CreateContainer(name, model, w, h, pos, ang)
	else
		local model = string.Trim(tostring(t.model or "")):sub(1, 128)
		if not model:lower():match("%.mdl$") or not util.IsValidModel(model) then
			RPInv.Notify(ply, "Model not found on the server.", 2)
			return
		end
		c = RPInv.CreateContainer(name, model, w, h, tr.HitPos + tr.HitNormal * 5, Angle(0, ply:EyeAngles().y + 180, 0))
		if c then RPInv.PlaceOnGround(c, tr.HitPos) end
	end
	if not c then RPInv.Notify(ply, "Database error.", 2) return end

	DB.Log(ply, "container_create", c.id .. " " .. name .. " " .. w .. "x" .. h)
	RPInv.Notify(ply, "Container created: " .. name, 1)
	sendList(ply)
end)

net.Receive("rpinv_a_cdelete", function(_, ply)
	local cid = net.ReadUInt(32)
	if not RPInv.IsAdmin(ply) then return end
	local c = RPInv.DeleteContainer(cid)
	if not c then return end
	DB.Log(ply, "container_delete", cid .. " " .. c.name)
	RPInv.Notify(ply, "Container deleted: " .. c.name, 1)
	sendList(ply)
end)
