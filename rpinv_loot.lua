TOOL.Category = "Sandbox Inventory+"
TOOL.Name = "#tool.rpinv_loot.name"
TOOL.ClientConVar = { preset = "0", tag = "", rot = "0", height = "0", exact = "1" }

if CLIENT then
	language.Add("tool.rpinv_loot.name", "Loot Spawns")
	language.Add("tool.rpinv_loot.desc", "Place loot container spawn points (superadmin)")
	language.Add("tool.rpinv_loot.left", "Spawn the selected loot preset at the crosshair")
	language.Add("tool.rpinv_loot.right", "Add a loot spawn point where the ghost is")
	language.Add("tool.rpinv_loot.reload", "Remove the nearest loot spawn point")
	TOOL.Information = { { name = "left" }, { name = "right" }, { name = "reload" } }
end

local DEFAULT_MODEL = "models/items/ammocrate_smg1.mdl"

local function allowed(ply)
	return IsValid(ply) and ply:IsSuperAdmin()
end

function TOOL:PointPlacement(tr)
	local ply = self:GetOwner()
	local yaw = math.NormalizeAngle(ply:EyeAngles().y + 180 + self:GetClientNumber("rot", 0))
	local pos = tr.HitPos + Vector(0, 0, self:GetClientNumber("height", 0))
	return pos, yaw
end

function TOOL:LeftClick()
	if CLIENT then return allowed(self:GetOwner()) end
	local ply = self:GetOwner()
	local L = RPInv.Loot
	if not allowed(ply) or not L then return false end
	if (ply.RPInvNextLoot or 0) > CurTime() then return false end
	ply.RPInvNextLoot = CurTime() + 0.5
	local preset = L.Presets[self:GetClientNumber("preset", 0)]
	if not preset then
		for _, p in RandomPairs(L.Presets) do preset = p break end
	end
	if not preset then
		RPInv.Notify(ply, "Create a loot preset first (ADMIN > LOOT).", 2)
		return false
	end
	local ok, err = L.SpawnAtAim(ply, preset)
	RPInv.Notify(ply, ok and ("Loot container spawned: " .. preset.name) or err, ok and 1 or 2)
	return ok
end

function TOOL:RightClick(tr)
	if CLIENT then return allowed(self:GetOwner()) end
	local ply = self:GetOwner()
	local L = RPInv.Loot
	if not allowed(ply) or not L then return false end
	if not tr.Hit or tr.HitSky then return false end
	local tag = L.CleanTag(self:GetClientInfo("tag"))
	local pos, yaw = self:PointPlacement(tr)
	if self:GetClientNumber("exact", 1) == 0 then yaw = nil end
	if not L.AddPoint(pos, tag, yaw) then
		RPInv.Notify(ply, "Point limit reached (" .. L.MAX_POINTS .. ").", 2)
		return false
	end
	RPInv.Notify(ply, "Loot spawn point added" .. (tag ~= "" and (" [" .. tag .. "]") or "") .. " (" .. #L.Points() .. " on this map).", 1)
	L.SendList(ply)
	return true
end

function TOOL:Reload(tr)
	if CLIENT then return allowed(self:GetOwner()) end
	local ply = self:GetOwner()
	local L = RPInv.Loot
	if not allowed(ply) or not L then return false end
	if not L.RemoveNearestPoint(tr.HitPos, 400) then
		RPInv.Notify(ply, "No loot spawn point within 400 units.", 2)
		return false
	end
	RPInv.Notify(ply, "Loot spawn point removed (" .. #L.Points() .. " left).", 1)
	L.SendList(ply)
	return true
end

local function ghostModel(self)
	local id = self:GetClientNumber("preset", 0)
	local list = {}
	if SERVER then
		for _, pr in SortedPairs(RPInv.Loot and RPInv.Loot.Presets or {}) do list[#list + 1] = pr end
	else
		list = RPInv.LootData and RPInv.LootData.presets or {}
	end
	for _, pr in ipairs(list) do
		if pr.id == id then return pr.model end
	end
	return list[1] and list[1].model or DEFAULT_MODEL
end

function TOOL:Think()
	if not allowed(self:GetOwner()) then return end
	local model = ghostModel(self)
	if not IsValid(self.GhostEntity) or self.GhostEntity:GetModel() ~= model then
		self:MakeGhostEntity(model, vector_origin, angle_zero)
	end
	local g = self.GhostEntity
	if not IsValid(g) then return end
	local tr = self:GetOwner():GetEyeTrace()
	if not tr.Hit or tr.HitSky then
		g:SetNoDraw(true)
		return
	end
	local pos, yaw = self:PointPlacement(tr)
	g:SetAngles(Angle(0, yaw, 0))
	g:SetPos(pos - Vector(0, 0, g:OBBMins().z))
	g:SetNoDraw(false)
end

if CLIENT then
	function TOOL:DrawHUD()
		local pts = RPInv.LootData and RPInv.LootData.pointList
		if not pts then return end
		local eye = EyePos()
		for _, v in ipairs(pts) do
			local pos = Vector(v[1], v[2], v[3])
			if pos:DistToSqr(eye) < 3000 * 3000 then
				local sc = pos:ToScreen()
				if sc.visible then
					surface.SetDrawColor(214, 170, 72, 230)
					surface.DrawOutlinedRect(sc.x - 5, sc.y - 5, 10, 10, 2)
					local label = (v[4] and v[4] ~= "") and v[4] or "untagged"
					if v[5] then label = label .. "  " .. v[5] .. "°" end
					draw.SimpleText(label, "DermaDefault", sc.x, sc.y - 8, Color(235, 240, 246), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
				end
			end
		end
	end
end

function TOOL.BuildCPanel(panel)
	panel:Help("Superadmin only. Presets, limits and timers are in the inventory: ADMIN > LOOT. The ghost shows exactly where a container from this point will stand; existing points are shown as squares.")
	panel:TextEntry("Tag for new points (e.g. table, warehouse)", "rpinv_loot_tag")
	panel:Help("A preset with POINT TAGS only spawns on points with one of those tags. Empty tag = untagged point.")
	panel:NumSlider("Rotation", "rpinv_loot_rot", -180, 180, 0)
	panel:NumSlider("Height offset", "rpinv_loot_height", -64, 64, 0)
	panel:CheckBox("Exact point (keep this position and rotation, no ground snap)", "rpinv_loot_exact")
	local combo = panel:ComboBox("Loot preset for LMB and the ghost")
	local function fill()
		if not IsValid(combo) then return end
		combo:Clear()
		local want = GetConVar("rpinv_loot_preset"):GetInt()
		combo:AddChoice("Random preset", 0, want == 0)
		for _, pr in ipairs(RPInv.LootData and RPInv.LootData.presets or {}) do
			combo:AddChoice(pr.name, pr.id, pr.id == want)
		end
	end
	combo.OnSelect = function(_, _, _, data)
		RunConsoleCommand("rpinv_loot_preset", tostring(data or 0))
	end
	fill()
	hook.Add("RPInv_LootUpdated", "RPInv_LootTool", fill)
	net.Start("rpinv_lt_list")
	net.SendToServer()
end
