AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "RP Container"
ENT.Spawnable = false
ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "CID")
	self:NetworkVar("String", 0, "CName")
end

if SERVER then
	function ENT:Initialize()
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end

	function ENT:Use(activator)
		if IsValid(activator) and activator:IsPlayer() then
			RPInv.OpenContainer(activator, self)
		end
	end

	function ENT:OnRemove()
		if RPInv.OnContainerRemoved then RPInv.OnContainerRemoved(self) end
	end
else
	function ENT:Draw()
		self:DrawModel()
	end
end
