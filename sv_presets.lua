local DB = RPInv.DB
local G = RPInv.Grid
RPInv.Presets = DB.LoadPresets()

for _, n in ipairs({
	"rpinv_a_plist", "rpinv_a_plist_r", "rpinv_a_psave", "rpinv_a_pdelete", "rpinv_a_pspawn",
}) do util.AddNetworkString(n) end

local MAX_PRESETS = 100

local function sendList(ply)
	local list = {}
	for id, p in SortedPairs(RPInv.Presets) do
		list[#list + 1] = { id = id, name = p.name, model = p.model, w = p.w, h = p.h, stacks = #p.contents }
	end
	RPInv.SendJSON("rpinv_a_plist_r", { list = list }, ply)
end

local function broadcast()
	for _, p in ipairs(player.GetAll()) do
		if RPInv.IsAdmin(p) then sendList(p) end
	end
end

local function snapshot(st)
	local out = {}
	for _, it in SortedPairs(st.items) do
		local meta = table.Copy(it.meta)
		meta.cid = nil
		out[#out + 1] = {
			item_id = it.item, amount = it.amount, x = it.x, y = it.y, rot = it.rot,
			meta = next(meta) ~= nil and meta or nil,
		}
	end
	return out
end

local function fill(st, contents)
	local defs = RPInv.Items
	DB.Transaction(function()
		for _, e in ipairs(contents) do
			local def = defs[e.item_id]
			if def then
				local amount = math.Clamp(math.floor(e.amount), 1, def.max_stack)
				local rot = def.rotatable and e.rot or 0
				local w, h = G.Size(def, rot)
				local x, y = e.x, e.y
				if not G.CanPlace(st, defs, w, h, x, y) then
					x, y, rot = G.AutoPlace(st, defs, def)
				end
				if x then RPInv.InstCreate(st, def.id, amount, table.Copy(e.meta or {}), x, y, rot) end
			end
		end
	end)
end

local function placeContainer(ply, preset)
	local tr = ply:GetEyeTrace()
	local c = RPInv.CreateContainer(preset.name, preset.model, preset.w, preset.h, tr.HitPos + tr.HitNormal * 5, Angle(0, ply:EyeAngles().y + 180, 0))
	if not c then return end
	RPInv.PlaceOnGround(c, tr.HitPos)
	fill(RPInv.ContainerStorage(c), preset.contents)
	return c
end

net.Receive("rpinv_a_plist", function(_, ply)
	if RPInv.IsAdmin(ply) then sendList(ply) end
end)

net.Receive("rpinv_a_psave", function(_, ply)
	local t = RPInv.ReadJSON(1024)
	if not RPInv.IsAdmin(ply) or type(t) ~= "table" then return end

	local existing
	if t.id then
		existing = RPInv.Presets[tonumber(t.id) or -1]
		if not existing then return end
	elseif table.Count(RPInv.Presets) >= MAX_PRESETS then
		RPInv.Notify(ply, "Preset limit reached.", 2)
		return
	end

	local preset = { id = existing and existing.id, name = existing and existing.name }
	if not preset.name then
		preset.name = string.Trim(tostring(t.name or "")):sub(1, 40)
		if preset.name == "" then preset.name = "Preset" end
	end

	if t.from_aimed then
		local ent = ply:GetEyeTrace().Entity
		local c = IsValid(ent) and ent:GetClass() == "rpinv_container" and RPInv.Containers[ent:GetCID()]
		if not c then RPInv.Notify(ply, "Aim at a container first.", 2) return end
		preset.model, preset.w, preset.h = c.model, c.w, c.h
		preset.contents = snapshot(RPInv.ContainerStorage(c))
	else
		local model = string.Trim(tostring(t.model or "")):sub(1, 128)
		if not model:lower():match("%.mdl$") or not util.IsValidModel(model) then
			RPInv.Notify(ply, "Model not found on the server.", 2)
			return
		end
		preset.model = model
		preset.w = math.Clamp(math.floor(tonumber(t.w) or 10), 1, 20)
		preset.h = math.Clamp(math.floor(tonumber(t.h) or 4), 1, 20)
		preset.contents = {}
	end

	preset.id = DB.SavePreset(preset)
	if not preset.id then RPInv.Notify(ply, "Database error.", 2) return end
	RPInv.Presets[preset.id] = preset
	DB.Log(ply, "preset_save", preset.id .. " " .. preset.name)
	RPInv.Notify(ply, "Preset saved: " .. preset.name, 1)
	broadcast()
end)

net.Receive("rpinv_a_pdelete", function(_, ply)
	local id = net.ReadUInt(32)
	local p = RPInv.Presets[id]
	if not RPInv.IsAdmin(ply) or not p then return end
	DB.DeletePreset(id)
	RPInv.Presets[id] = nil
	DB.Log(ply, "preset_delete", id .. " " .. p.name)
	RPInv.Notify(ply, "Preset deleted: " .. p.name, 1)
	broadcast()
end)

net.Receive("rpinv_a_pspawn", function(_, ply)
	local id = net.ReadUInt(32)
	local p = RPInv.Presets[id]
	if not RPInv.IsAdmin(ply) or not p then return end
	if (ply.RPInvNextSpawn or 0) > CurTime() then return end
	ply.RPInvNextSpawn = CurTime() + 0.3
	if table.Count(RPInv.Containers) >= RPInv.MaxContainers then RPInv.Notify(ply, "Container limit reached.", 2) return end
	if not placeContainer(ply, p) then RPInv.Notify(ply, "Database error.", 2) return end
	DB.Log(ply, "preset_spawn", id .. " " .. p.name)
	RPInv.SendContainerList(ply)
end)
