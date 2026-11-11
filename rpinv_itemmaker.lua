TOOL.Category = "Sandbox Inventory+"
TOOL.Name = "#tool.rpinv_itemmaker.name"
TOOL.ClientConVar = { name = "Container", w = "8", h = "6" }

if CLIENT then
	language.Add("tool.rpinv_itemmaker.name", "Item Maker")
	language.Add("tool.rpinv_itemmaker.desc", "Make inventory items or containers from entities and props (superadmin)")
	language.Add("tool.rpinv_itemmaker.left", "Make an inventory item from the aimed entity or prop")
	language.Add("tool.rpinv_itemmaker.right", "Turn the aimed entity or prop into a container")
	TOOL.Information = { { name = "left" }, { name = "right" } }
end

local function allowed(ply)
	return IsValid(ply) and ply:IsSuperAdmin()
end

local function blocked(ent)
	return not IsValid(ent) or ent:IsWorld() or ent:IsPlayer() or ent:IsNPC() or ent:IsVehicle() or ent:IsWeapon() or ent:IsRagdoll()
		or string.sub(ent:GetClass(), 1, 6) == "rpinv_"
end

function TOOL:LeftClick(tr)
	if CLIENT then return allowed(self:GetOwner()) and IsValid(tr.Entity) end
	local ply = self:GetOwner()
	if not allowed(ply) or not RPInv.Quick or not RPInv.Quick.MakeItemFrom then return false end
	local ok, res = RPInv.Quick.MakeItemFrom(ply, tr.Entity)
	if not ok then
		RPInv.Notify(ply, res, 2)
		return false
	end
	RPInv.Notify(ply, "Item created: " .. res.name .. " (" .. res.id .. "). Edit it in ADMIN > ITEMS.", 1)
	return true
end

function TOOL:RightClick(tr)
	local ent = tr.Entity
	if CLIENT then return allowed(self:GetOwner()) and not blocked(ent) end
	local ply = self:GetOwner()
	if not allowed(ply) then return false end
	if blocked(ent) then
		RPInv.Notify(ply, "Aim at a prop or an entity.", 2)
		return false
	end
	local model = ent:GetModel()
	if not isstring(model) or not model:lower():match("%.mdl$") or not util.IsValidModel(model) then
		RPInv.Notify(ply, "This entity has no usable model.", 2)
		return false
	end
	if table.Count(RPInv.Containers) >= (RPInv.MaxContainers or 200) then
		RPInv.Notify(ply, "Container limit reached.", 2)
		return false
	end
	local name = string.Trim(self:GetClientInfo("name")):sub(1, 40)
	if name == "" then name = "Container" end
	local w = math.Clamp(math.floor(self:GetClientNumber("w", 8)), 1, 20)
	local h = math.Clamp(math.floor(self:GetClientNumber("h", 6)), 1, 20)
	local pos, ang = ent:GetPos(), ent:GetAngles()
	ent:Remove()
	local c = RPInv.CreateContainer(name, model, w, h, pos, ang)
	if not c then
		RPInv.Notify(ply, "Database error.", 2)
		return false
	end
	RPInv.DB.Log(ply, "container_create", c.id .. " " .. name .. " " .. w .. "x" .. h .. " from " .. model)
	RPInv.Notify(ply, "Container created: " .. name .. " (" .. w .. "x" .. h .. ").", 1)
	if RPInv.SendContainerList then RPInv.SendContainerList(ply) end
	return true
end

function TOOL.BuildCPanel(panel)
	panel:Help("Superadmin only. LMB makes the aimed entity or prop an inventory item (players store it with SHIFT+E, it is placed again from the inventory). RMB turns it into a permanent container with the name and grid below.")
	panel:TextEntry("Container name", "rpinv_itemmaker_name")
	panel:NumSlider("Grid width", "rpinv_itemmaker_w", 1, 20, 0)
	panel:NumSlider("Grid height", "rpinv_itemmaker_h", 1, 20, 0)
end
