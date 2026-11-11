TOOL.Category = "Sandbox Inventory+"
TOOL.Name = "#tool.rpinv_airdrop.name"
TOOL.ClientConVar = { preset = "0" }

if CLIENT then
	language.Add("tool.rpinv_airdrop.name", "RP Airdrop")
	language.Add("tool.rpinv_airdrop.desc", "Call airdrops and manage auto-drop points (superadmin)")
	language.Add("tool.rpinv_airdrop.left", "Call the selected airdrop at the crosshair")
	language.Add("tool.rpinv_airdrop.right", "Add an auto-drop point here")
	language.Add("tool.rpinv_airdrop.reload", "Remove the nearest auto-drop point")
	TOOL.Information = { { name = "left" }, { name = "right" }, { name = "reload" } }
end

local function allowed(ply)
	return IsValid(ply) and ply:IsSuperAdmin()
end

function TOOL:LeftClick(tr)
	if CLIENT then return allowed(self:GetOwner()) end
	local ply = self:GetOwner()
	if not allowed(ply) or not RPInv.Airdrop then return false end
	if (ply.RPInvNextDrop or 0) > CurTime() then return false end
	ply.RPInvNextDrop = CurTime() + 1
	local AD = RPInv.Airdrop
	local preset = AD.Presets[self:GetClientNumber("preset", 0)] or AD.PickPreset(false)
	if not preset then
		RPInv.Notify(ply, "Create an airdrop preset first (ADMIN > AIRDROPS).", 2)
		return false
	end
	local ok, err = AD.Call(preset, tr.HitPos, ply)
	RPInv.Notify(ply, ok and ("Airdrop called: " .. preset.name) or err, ok and 1 or 2)
	return ok
end

function TOOL:RightClick(tr)
	if CLIENT then return allowed(self:GetOwner()) end
	local ply = self:GetOwner()
	if not allowed(ply) or not RPInv.Airdrop then return false end
	local AD = RPInv.Airdrop
	local ground, err = AD.DropSite(tr.HitPos)
	if not ground then
		RPInv.Notify(ply, err, 2)
		return false
	end
	if not AD.AddPoint(ground) then
		RPInv.Notify(ply, "Point limit reached (200).", 2)
		return false
	end
	RPInv.Notify(ply, "Auto-drop point added (" .. #AD.Points() .. " on this map).", 1)
	AD.SendList(ply)
	return true
end

function TOOL:Reload(tr)
	if CLIENT then return allowed(self:GetOwner()) end
	local ply = self:GetOwner()
	if not allowed(ply) or not RPInv.Airdrop then return false end
	local AD = RPInv.Airdrop
	if not AD.RemoveNearestPoint(tr.HitPos, 400) then
		RPInv.Notify(ply, "No auto-drop point within 400 units.", 2)
		return false
	end
	RPInv.Notify(ply, "Auto-drop point removed (" .. #AD.Points() .. " left).", 1)
	AD.SendList(ply)
	return true
end

function TOOL.BuildCPanel(panel)
	panel:Help("Superadmin only. Presets and the auto-drop timer are in the inventory: ADMIN > AIRDROPS.")
	local combo = panel:ComboBox("Airdrop preset")
	local function fill()
		if not IsValid(combo) then return end
		combo:Clear()
		local want = GetConVar("rpinv_airdrop_preset"):GetInt()
		combo:AddChoice("Random preset", 0, want == 0)
		local AD = RPInv.Airdrop
		for _, pr in ipairs(AD and AD.Data and AD.Data.presets or {}) do
			combo:AddChoice(pr.name, pr.id, pr.id == want)
		end
	end
	combo.OnSelect = function(_, _, _, data)
		RunConsoleCommand("rpinv_airdrop_preset", tostring(data or 0))
	end
	fill()
	hook.Add("RPInv_AirdropsUpdated", "RPInv_AirdropTool", fill)
	net.Start("rpinv_ad_list")
	net.SendToServer()
end
