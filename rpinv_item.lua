AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "RP Inventory Item"
ENT.Spawnable = false
ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "ItemID")
	self:NetworkVar("Int", 0, "Amount")
end

if SERVER then
	function ENT:Initialize()
		local def = RPInv.Items[self:GetItemID()]
		if not def then self:Remove() return end

		local fix = RPInv.GetModelFix(def.model)
		self:SetModel(fix and fix.proxy or def.model)
		if not fix then RPInv.ApplyLook(self, def) end
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local phys = self:GetPhysicsObject()
		if not IsValid(phys) then
			local mins, maxs = self:OBBMins(), self:OBBMaxs()
			self:PhysicsInitBox(mins, maxs)
			self:SetCollisionBounds(mins, maxs)
			phys = self:GetPhysicsObject()
		end
		if IsValid(phys) then phys:Wake() end
	end

	function ENT:Use(activator)
		if self.RPInvTaken or not IsValid(activator) or not activator:IsPlayer() then return end
		RPInv.PickupWorldItem(activator, self)
	end
else
	function ENT:RPInvShown()
		local def = RPInv.Items[self:GetItemID()]
		local fix = def and RPInv.GetModelFix(def.model)
		if not fix then return nil end
		local c = self.RPInvShownEnt
		if IsValid(c) and string.lower(c:GetModel() or "") == string.lower(def.model) then return c, fix end
		if IsValid(c) then c:Remove() end
		c = ClientsideModel(def.model, RENDERGROUP_OPAQUE)
		if not IsValid(c) then return nil end
		c:SetNoDraw(true)
		RPInv.ApplyModelFix(c)
		local fb = RPInv.ModelFixBounds(def.model)
		local m = Matrix()
		m:SetTranslation(-fb.center)
		RPInv.ModelFixHook(c, m)
		self.RPInvShownEnt = c
		return c, fix
	end

	function ENT:Draw()
		local c, fix = self:RPInvShown()
		if not c then
			self:DrawModel()
			return
		end
		local pos, ang = LocalToWorld(vector_origin, fix.proxyAng, self:LocalToWorld(self:OBBCenter()), self:GetAngles())
		c:SetPos(pos)
		c:SetAngles(ang)
		c:InvalidateBoneCache()
		c:DrawModel()
	end

	function ENT:OnRemove()
		if IsValid(self.RPInvShownEnt) then self.RPInvShownEnt:Remove() end
	end
end
