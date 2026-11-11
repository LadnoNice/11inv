AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Loot Container"
ENT.Spawnable = false
ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "CName")
end

if SERVER then
	function ENT:Initialize()
		self:PhysicsInit(SOLID_VPHYSICS)
		if not IsValid(self:GetPhysicsObject()) then
			self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs())
		end
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end

	function ENT:Use(activator)
		if not IsValid(activator) or not activator:IsPlayer() or not self.RPInvLootCid then return end
		if RPInv.Loot then RPInv.Loot.Opened(self) end
		RPInv.OpenContainerId(activator, self.RPInvLootCid)
	end

	function ENT:OnRemove()
		local cid = self.RPInvLootCid
		if cid and RPInv.Containers[cid] then RPInv.DeleteContainer(cid) end
	end
end
