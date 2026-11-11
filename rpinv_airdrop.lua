AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "RP Airdrop"
ENT.Spawnable = false
ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "Landed")
	self:NetworkVar("Float", 0, "SmokeUntil")
	self:NetworkVar("Vector", 0, "SmokeColor")
end

if SERVER then
	function ENT:UpdateTransmitState()
		return TRANSMIT_ALWAYS
	end

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
		self.RPInvSway = math.Rand(0, 6.28)
		self:NextThink(CurTime())
	end

	function ENT:Think()
		if self:GetLanded() then return end
		local ground = self.RPInvGround
		if not ground then
			self:Remove()
			return
		end
		local dt = FrameTime()
		local pos = self:GetPos()
		local bottom = pos.z + self:OBBMins().z
		local step = RPInv.Airdrop.FALL_SPEED * dt
		if bottom - step <= ground.z then
			self:SetPos(Vector(ground.x, ground.y, ground.z - self:OBBMins().z))
			local ang = self:GetAngles()
			self:SetAngles(Angle(0, ang.y, 0))
			RPInv.Airdrop.Land(self)
			return
		end
		local t = CurTime() + self.RPInvSway
		local drift = Vector(math.sin(t * 0.7), math.cos(t * 0.5), 0) * 12 * dt
		self:SetPos(Vector(pos.x + drift.x, pos.y + drift.y, pos.z - step))
		self:SetAngles(Angle(math.sin(t * 1.1) * 4, self:GetAngles().y + dt * 3, math.cos(t * 0.9) * 4))
		self:NextThink(CurTime())
		return true
	end

	function ENT:Use(activator)
		if not IsValid(activator) or not activator:IsPlayer() or not self:GetLanded() then return end
		if self.RPInvAirdropCid then RPInv.OpenContainerId(activator, self.RPInvAirdropCid) end
	end

	function ENT:OnRemove()
		timer.Remove("RPInv_Airdrop" .. self:EntIndex())
		local cid = self.RPInvAirdropCid
		if cid and RPInv.Containers[cid] then RPInv.DeleteContainer(cid) end
	end
else
	local SMOKE = {}
	for i = 1, 9 do SMOKE[i] = "particle/smokesprites_000" .. i end

	function ENT:Initialize()
		local s = util.SharedRandom("rpinv_ad" .. self:EntIndex(), 0, 360)
		self.Wind = Angle(0, s, 0):Forward() * 26
		self.NextPuff = 0
		local mn, mx = self:OBBMins(), self:OBBMaxs()
		self:SetRenderBounds(mn - Vector(250, 250, 0), mx + Vector(250, 250, 700))
	end

	function ENT:SmokeOn()
		return self:GetLanded() and self:GetSmokeUntil() > CurTime()
	end

	function ENT:Think()
		if self:GetLanded() and not self.RPInvLandedAt then
			self.RPInvLandedAt = CurTime()
			self.RPInvChuteOn = IsValid(self.RPInvChute)
		end
		local on = self:SmokeOn()
		if on and not self.Hiss then
			self.Hiss = CreateSound(self, "weapons/flaregun/burn.wav")
			if self.Hiss then
				self.Hiss:SetSoundLevel(65)
				self.Hiss:PlayEx(0.35, 100)
			end
		elseif not on and self.Hiss then
			self.Hiss:Stop()
			self.Hiss = nil
		end
		if not on then return end
		local top = self:WorldSpaceCenter() + Vector(0, 0, self:OBBMaxs().z - self:OBBCenter().z)
		local dl = DynamicLight(self:EntIndex())
		if dl then
			local c = self:GetSmokeColor()
			dl.pos = top + Vector(0, 0, 45)
			dl.r, dl.g, dl.b = c.x * 255, c.y * 255, c.z * 255
			dl.brightness = 2 + math.Rand(0, 0.6)
			dl.decay = 1000
			dl.size = 220
			dl.dietime = CurTime() + 0.2
		end
		local now = RealTime()
		if now < self.NextPuff then return end
		if EyePos():DistToSqr(top) > 9000 * 9000 then return end
		self.NextPuff = now + 0.07
		if not self.Emitter then self.Emitter = ParticleEmitter(top, false) end
		local em = self.Emitter
		if not em then return end
		em:SetPos(top)
		local c = self:GetSmokeColor()
		local p = em:Add(SMOKE[math.random(#SMOKE)], top + VectorRand() * 3)
		if p then
			p:SetVelocity(Vector(math.Rand(-12, 12), math.Rand(-12, 12), math.Rand(70, 120)) + self.Wind * 0.4)
			p:SetGravity(Vector(self.Wind.x, self.Wind.y, 6))
			p:SetAirResistance(28)
			p:SetDieTime(math.Rand(7, 11))
			p:SetStartAlpha(math.random(150, 200))
			p:SetEndAlpha(0)
			p:SetStartSize(math.Rand(6, 12))
			p:SetEndSize(math.Rand(110, 170))
			p:SetRoll(math.Rand(0, 360))
			p:SetRollDelta(math.Rand(-0.35, 0.35))
			local shade = math.Rand(0.75, 1)
			p:SetColor(c.x * 255 * shade, c.y * 255 * shade, c.z * 255 * shade)
			p:SetLighting(false)
		end
	end

	function ENT:OnRemove()
		if self.Hiss then self.Hiss:Stop() end
		if self.Emitter then self.Emitter:Finish() end
	end

	function ENT:Draw()
		self:DrawModel()
		if (not self:GetLanded() or self.RPInvChuteOn) and RPInv.Airdrop and RPInv.Airdrop.DrawParachute then
			RPInv.Airdrop.DrawParachute(self)
		end
	end
end
