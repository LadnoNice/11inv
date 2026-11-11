local function isContainer(ent)
	return IsValid(ent) and ent:GetClass() == "rpinv_container"
end

local function isAdmin(ply)
	return IsValid(ply) and ply:IsSuperAdmin()
end

hook.Add("PhysgunPickup", "RPInv_ProtectContainers", function(ply, ent)
	if isContainer(ent) and not isAdmin(ply) then return false end
end)

hook.Add("CanTool", "RPInv_ProtectContainers", function(ply, tr, mode, _, button)
	local ent = tr.Entity
	if not isContainer(ent) then return end
	if mode ~= "remover" or button == 3 or not isAdmin(ply) then return false end
	if SERVER then ent.RPInvDeleteBy = ply end
end)

hook.Add("CanProperty", "RPInv_ProtectContainers", function(ply, prop, ent)
	if not IsValid(ent) then return end
	local cls = ent:GetClass()
	if cls == "rpinv_container" then
		if prop ~= "remover" or not isAdmin(ply) then return false end
		if SERVER then ent.RPInvDeleteBy = ply end
	elseif cls == "rpinv_item" and prop == "persist" then
		return false
	end
end)

local BLOCKED = bit.bor(IN_ATTACK, IN_ATTACK2, IN_JUMP, IN_DUCK, IN_RELOAD, IN_SPEED)

function RPInv.VehicleLocked(ply)
	return IsValid(ply) and ply:InVehicle() and not ply:GetAllowWeaponsInVehicle()
end

hook.Add("PlayerSwitchWeapon", "RPInv_SurrenderHands", function(ply, old, new)
	if ply:GetNW2Bool("RPInvSurrender", false) and IsValid(new) and new:GetClass() ~= "rpinv_hands" then return true end
	if RPInv.VehicleLocked(ply) then return true end
end)

local SLOW_SPEED = 55

hook.Add("StartCommand", "RPInv_Surrendered", function(ply, cmd)
	if not ply:GetNW2Bool("RPInvSurrender", false) then return end
	cmd:SetUpMove(0)
	cmd:RemoveKey(BLOCKED)
end)

hook.Add("SetupMove", "RPInv_SurrenderSlow", function(ply, mv)
	if not ply:GetNW2Bool("RPInvSurrender", false) then return end
	mv:SetMaxSpeed(SLOW_SPEED)
	mv:SetMaxClientSpeed(SLOW_SPEED)
end)

local PLY = FindMetaTable("Player")
RPInv.OrigGetRagdollEntity = RPInv.OrigGetRagdollEntity or PLY.GetRagdollEntity
local origRagdoll = RPInv.OrigGetRagdollEntity

function PLY:GetRagdollEntity()
	if not self:Alive() then
		local body = self:GetNW2Entity("RPInvBody")
		if IsValid(body) then return body end
	end
	return origRagdoll(self)
end

if SERVER then
	hook.Add("CanPlayerUnfreeze", "RPInv_ProtectContainers", function(_, ent)
		if isContainer(ent) then return false end
	end)

	hook.Add("PhysgunDrop", "RPInv_SaveContainerPos", function(_, ent)
		if isContainer(ent) and RPInv.SaveContainerPlacement then RPInv.SaveContainerPlacement(ent) end
	end)
end
