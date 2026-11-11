AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Signal Flare"
ENT.Spawnable = false
ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

ENT.IgniteDelay = 3
ENT.BurnTime = 30
ENT.DescendSpeed = 9
ENT.Gravity = 600
ENT.HitDamage = 30
ENT.BurstDamage = 25
ENT.BurstRadius = 110
ENT.FireRadius = 80

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "LitAt")
	self:NetworkVar("Float", 1, "DieAt")
end

if SERVER then
	function ENT:UpdateTransmitState()
		return TRANSMIT_ALWAYS
	end

	function ENT:Initialize()
		self:SetModel("models/props_junk/flare.mdl")
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_NONE)
		self:DrawShadow(false)
		self.RPInvVel = self.RPInvVel or Vector(0, 0, 1900)
		self.RPInvBorn = CurTime()
		self.RPInvSway = math.Rand(0, 6.28)
		self:SetLitAt(CurTime() + self.IgniteDelay)
		self:SetDieAt(CurTime() + self.IgniteDelay + self.BurnTime)
		self:NextThink(CurTime())
	end

	function ENT:RPInvFly(dt)
		if self.RPInvGrounded then return end
		local pos = self:GetPos()
		local vel = self.RPInvVel
		local lit = CurTime() >= self:GetLitAt()
		if lit then
			local t = CurTime() + self.RPInvSway
			local target = Vector(math.sin(t * 0.21) * 1.2, math.cos(t * 0.17) * 1.2, -self.DescendSpeed)
			vel = LerpVector(math.min(1, dt * 3), vel, target)
		elseif self.RPInvStuck then
			vel = Vector(0, 0, 0)
		else
			vel = vel * (1 - math.min(0.5, dt * 0.08))
			vel.z = vel.z - self.Gravity * dt
		end
		self.RPInvVel = vel
		local to = pos + vel * dt
		self.RPInvFilter = self.RPInvFilter or { self, self.RPInvBy }
		local tr = util.TraceLine({ start = pos, endpos = to, mask = MASK_SHOT, filter = self.RPInvFilter })
		if tr.Hit and IsValid(tr.Entity) and not tr.Entity:IsWorld() then
			self:RPInvHit(tr.Entity, tr.HitPos, vel)
			self.RPInvFilter[#self.RPInvFilter + 1] = tr.Entity
			self.RPInvVel = vel * 0.15
			self:SetPos(tr.HitPos)
			return
		end
		if tr.Hit then
			if tr.HitSky then
				self.RPInvVel = Vector(0, 0, 0)
				self.RPInvStuck = true
				self.RPInvHitSky = true
				self:SetPos(tr.HitPos - tr.Normal * 24)
			else
				self.RPInvBlocked = true
				self.RPInvVel = Vector(0, 0, 0)
				self.RPInvStuck = true
				if tr.HitNormal.z > 0.5 then
					self.RPInvGrounded = true
					self:SetPos(tr.HitPos + tr.HitNormal * 2)
				else
					self:SetPos(tr.HitPos + tr.HitNormal * 4)
				end
			end
			return
		end
		self:SetPos(to)
	end

	local function burnable(e)
		return IsValid(e) and ((e:IsPlayer() and e:Alive()) or (e:IsNPC() and e:Health() > 0))
	end

	function ENT:RPInvDamage(target, amount, pos)
		local by = self.RPInvBy
		local d = DamageInfo()
		d:SetDamage(amount)
		d:SetDamageType(DMG_BURN)
		d:SetAttacker(IsValid(by) and by or self)
		d:SetInflictor(self)
		d:SetDamagePosition(pos or self:GetPos())
		target:TakeDamageInfo(d)
	end

	function ENT:RPInvHit(target, pos, vel)
		self:RPInvDamage(target, self.HitDamage, pos)
		local phys = target:GetPhysicsObject()
		if IsValid(phys) and not target:IsPlayer() and not target:IsNPC() then phys:ApplyForceOffset(vel * 2, pos) end
		if burnable(target) then target:Ignite(4) end
		self:EmitSound("physics/flesh/flesh_impact_bullet" .. math.random(1, 5) .. ".wav", 70)
	end

	function ENT:RPInvBurstDamage()
		local pos = self:GetPos()
		for _, e in ipairs(ents.FindInSphere(pos, self.BurstRadius)) do
			if IsValid(e) and e ~= self and (burnable(e) or IsValid(e:GetPhysicsObject())) and not e:IsWeapon() then
				local k = 1 - math.min(1, e:NearestPoint(pos):Distance(pos) / self.BurstRadius)
				if k > 0 then self:RPInvDamage(e, self.BurstDamage * k, pos) end
			end
		end
	end

	function ENT:RPInvFire()
		self.RPInvBurning = self.RPInvBurning or {}
		local near = {}
		if CurTime() >= self:GetLitAt() then
			local pos = self:GetPos()
			for _, e in ipairs(ents.FindInSphere(pos, self.FireRadius)) do
				if burnable(e) and e:NearestPoint(pos):DistToSqr(pos) <= self.FireRadius * self.FireRadius then
					near[e] = true
					e:Ignite(1.5)
					self.RPInvBurning[e] = true
				end
			end
		end
		for e in pairs(self.RPInvBurning) do
			if not near[e] then
				if IsValid(e) then e:Extinguish() end
				self.RPInvBurning[e] = nil
			end
		end
	end

	function ENT:OnRemove()
		for e in pairs(self.RPInvBurning or {}) do
			if IsValid(e) then e:Extinguish() end
		end
	end

	function ENT:RPInvBurst()
		self.RPInvIgnited = true
		self:EmitSound("weapons/flaregun/fire.wav", 110, 70)
		self:RPInvBurstDamage()
		local AD = RPInv and RPInv.Airdrop
		if not AD or not AD.FlareCall then return end
		local by = self.RPInvBy
		local pos = self:GetPos()
		local tr = util.TraceLine({ start = pos, endpos = pos - Vector(0, 0, 16384), mask = MASK_SOLID_BRUSHONLY })
		local height = pos.z - tr.HitPos.z
		if self.RPInvBlocked or (height < AD.FLARE_MIN_HEIGHT and not self.RPInvHitSky) then return end
		local ok = AD.FlareCall(self.RPInvPresets, tr.HitPos, by)
		if ok and IsValid(by) then RPInv.Notify(by, "Flare spotted. The airdrop is on its way.", 1) end
	end

	function ENT:Think()
		local now = CurTime()
		if now >= self:GetDieAt() then
			self:Remove()
			return
		end
		self:RPInvFly(FrameTime())
		if not self.RPInvIgnited and now >= self:GetLitAt() then self:RPInvBurst() end
		if now >= (self.RPInvNextFire or 0) then
			self.RPInvNextFire = now + 0.4
			self:RPInvFire()
		end
		self:NextThink(now)
		return true
	end
else
	local RAYMAT = Material("rpinv/flare_ray.png", "smooth")
	local GLOWMAT = Material("rpinv/flare_glow.png", "smooth")
	local SMOKE = {}
	local all = {}
	for i = 1, 9 do SMOKE[i] = "particle/smokesprites_000" .. i end
	local LIGHTS = 2

	local em
	local function emitter(pos)
		if not em or not em:IsValid() then em = ParticleEmitter(pos, false) end
		if em then em:SetPos(pos) end
		return em
	end

	local lit = {}
	local rankAt = 0
	hook.Add("Think", "RPInv_FlareLights", function()
		local now = RealTime()
		if now < rankAt then return end
		rankAt = now + 0.25
		local eye = EyePos()
		local list = {}
		for e in pairs(lit) do
			if IsValid(e) then
				e.RPInvLight = false
				list[#list + 1] = { e = e, d = e:GetPos():DistToSqr(eye) }
			else
				lit[e] = nil
			end
		end
		table.sort(list, function(a, b) return a.d < b.d end)
		for i = 1, math.min(LIGHTS, #list) do list[i].e.RPInvLight = true end
	end)

	function ENT:Initialize()
		self:SetRenderBounds(Vector(-3000, -3000, -3000), Vector(3000, 3000, 3000))
		self.NextPuff = 0
		self.Seed = math.Rand(0, 100)
		self.PixVis = util.GetPixelVisibleHandle()
		all[self] = true
	end

	function ENT:RPInvFade()
		return math.Clamp((self:GetDieAt() - CurTime()) / 3, 0, 1)
	end

	function ENT:RPInvPuff(pos, burning, dist, fade)
		local e = emitter(pos)
		if not e then return end
		local s = math.Clamp(dist / 1500, 1, 4)
		local p = e:Add(SMOKE[math.random(#SMOKE)], pos + VectorRand() * s)
		if not p then return end
		if burning then
			local t = CurTime() + self.Seed
			p:SetVelocity(Vector(math.sin(t * 0.8) * 1.5, math.cos(t * 0.6) * 1.5, math.Rand(10, 16)))
			p:SetAirResistance(20)
			p:SetDieTime(math.Rand(3.5, 5))
			p:SetStartAlpha(120 * fade)
			p:SetEndAlpha(0)
			p:SetStartSize(2.5 * s)
			p:SetEndSize(math.Rand(16, 26) * s)
			local g = math.random(150, 185)
			p:SetColor(235, g, g + 5)
		else
			p:SetVelocity(VectorRand() * 3)
			p:SetDieTime(math.Rand(1.2, 2))
			p:SetStartAlpha(90)
			p:SetEndAlpha(0)
			p:SetStartSize(2 * s)
			p:SetEndSize(math.Rand(10, 16) * s)
			p:SetColor(200, 190, 185)
		end
		p:SetRoll(math.Rand(0, 360))
		p:SetRollDelta(math.Rand(-0.3, 0.3))
		p:SetLighting(false)
	end

	function ENT:Think()
		local now = CurTime()
		local burning = now >= self:GetLitAt()
		local pos = self:GetPos()
		if burning and not self.Burn then
			self.Burn = CreateSound(self, "weapons/flaregun/burn.wav")
			if self.Burn then
				self.Burn:SetSoundLevel(85)
				self.Burn:PlayEx(0.8, 90)
			end
			self.LitFlash = now
			lit[self] = true
		end
		local fade = self:RPInvFade()
		if self.Burn and fade < 1 then self.Burn:ChangeVolume(0.8 * fade, 0) end
		if burning and self.RPInvLight then
			local dl = DynamicLight(self:EntIndex())
			if dl then
				dl.pos = pos
				dl.r, dl.g, dl.b = 255, 40, 40
				dl.brightness = (1.6 + math.Rand(0, 0.4)) * fade
				dl.size = 1200
				dl.decay = 0
				dl.dietime = now + 0.3
			end
		end
		local rt = RealTime()
		if rt < self.NextPuff then return end
		local dist = EyePos():Distance(pos)
		if dist > 14000 then
			self.NextPuff = rt + 0.5
			return
		end
		local step = burning and (dist < 3000 and 0.06 or dist < 8000 and 0.12 or 0.25) or 0.05
		self.NextPuff = rt + step
		self:RPInvPuff(pos, burning, dist, fade)
	end

	function ENT:OnRemove()
		if self.Burn then self.Burn:Stop() end
		lit[self] = nil
		all[self] = nil
	end

	function ENT:Draw()
	end

	function ENT:DrawTranslucent()
		if not self.PixVis then return end
		self.RPInvVis = util.PixelVisible(self:GetPos(), 6, self.PixVis)
		self.RPInvVisAt = RealTime()
	end

	local function quad(x, y, w, h, ang, r, g, b, a)
		if a < 1 then return end
		surface.SetDrawColor(r, g, b, math.min(a, 255))
		surface.DrawTexturedRectRotated(x, y, w, h, ang)
	end

	local function drawLens(e, x, y, dist, vis, now)
		local S = math.Clamp(70 + dist * 0.012, 70, 340) * ScrH() / 1080
		surface.SetMaterial(GLOWMAT)
		if now < e:GetLitAt() then
			quad(x, y, S * 0.5, S * 0.5, 0, 255, 150, 70, 200 * vis)
			quad(x, y, S * 0.16, S * 0.16, 0, 255, 235, 210, 255 * vis)
			return
		end
		local a = vis * e:RPInvFade()
		local flash = math.Clamp(1 - (now - (e.LitFlash or now)) / 1.0, 0, 1)
		local t = now + e.Seed
		local fl = 0.92 + 0.05 * math.sin(t * 7.3) + 0.03 * math.sin(t * 19.1)
		local big = S * (1 + flash * 2)
		quad(x, y, big * 3.2, big * 3.2, 0, 255, 30, 20, 70 * a)
		quad(x, y, big * 1.3 * fl, big * 1.3 * fl, 0, 255, 60, 40, 170 * a)
		quad(x, y, S * 0.34 * fl, S * 0.34 * fl, 0, 255, 240, 225, 255 * a)
		quad(x, y, S * 0.16, S * 0.16, 0, 255, 255, 255, 255 * a)
		surface.SetMaterial(RAYMAT)
		quad(x, y, big * 5 * fl, S * 0.1, 0, 255, 90, 60, 160 * a)
		for i = 1, 5 do
			local len = big * (1.6 + 0.5 * math.sin(t * 1.3 + i * 1.7)) * fl
			quad(x, y, len, S * 0.05, i * 30 + t * 3, 255, 150, 120, 90 * a)
		end
	end

	hook.Add("RenderScreenspaceEffects", "RPInv_FlareLens", function()
		if next(all) == nil then return end
		local now, rt = CurTime(), RealTime()
		local eye = EyePos()
		cam.Start2D()
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		for e in pairs(all) do
			if IsValid(e) then
				local vis = (rt - (e.RPInvVisAt or 0) < 0.25) and (e.RPInvVis or 0) or 0
				if vis > 0.01 then
					local pos = e:GetPos()
					local sc = pos:ToScreen()
					if sc.visible then drawLens(e, sc.x, sc.y, pos:Distance(eye), vis, now) end
				end
			else
				all[e] = nil
			end
		end
		render.OverrideBlend(false)
		cam.End2D()
	end)
end
