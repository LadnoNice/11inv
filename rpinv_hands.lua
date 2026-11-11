AddCSLuaFile()

SWEP.PrintName = "Hands"
SWEP.Author = "RP Inventory"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = false
SWEP.DisableDuplicator = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local maxMass = CreateConVar("rpinv_hands_maxmass", "60", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Heaviest physics mass the inventory hands can drag", 1, 100000)
local REACH = 95
local SHOVE_COOLDOWN = 3

function SWEP:SetupDataTables()
	self:NetworkVar("Entity", 0, "DragEnt")
	self:NetworkVar("Vector", 0, "DragLocal")
	self:NetworkVar("Float", 0, "DragDist")
end

function SWEP:Initialize()
	self:SetHoldType("normal")
end

function SWEP:ClearDrag()
	self.Drag = nil
	if SERVER and self.GetDragEnt and IsValid(self:GetDragEnt()) then self:SetDragEnt(NULL) end
end

function SWEP:Deploy()
	local own = self:GetOwner()
	local vm = IsValid(own) and own:GetViewModel()
	if IsValid(vm) then vm:SetNoDraw(true) end
	return true
end

function SWEP:Holster()
	self:ClearDrag()
	local own = self:GetOwner()
	local vm = IsValid(own) and own:GetViewModel()
	if IsValid(vm) then vm:SetNoDraw(false) end
	return true
end

function SWEP:OnRemove()
	self:Holster()
end

function SWEP:ShouldDropOnDie()
	return false
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.1)
end

function SWEP:SecondaryAttack()
	self:SetNextSecondaryFire(CurTime() + SHOVE_COOLDOWN)
	if CLIENT then return end
	local own = self:GetOwner()
	if not IsValid(own) or own:GetNW2Bool("RPInvSurrender", false) then return end
	local eye, aim = own:GetShootPos(), own:GetAimVector()
	own:LagCompensation(true)
	local tr = util.TraceHull({
		start = eye, endpos = eye + aim * 85, filter = own, mask = MASK_SHOT_HULL,
		mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6),
	})
	own:LagCompensation(false)
	own:DoCustomAnimEvent(PLAYERANIMEVENT_CUSTOM_GESTURE, ACT_GMOD_GESTURE_MELEE_SHOVE_2HAND)
	own:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 60, math.random(85, 100), 0.6)
	own:ViewPunch(Angle(2.5, math.Rand(-1, 1), 0))
	local ent = tr.Entity
	if not IsValid(ent) then return end
	local flat = Vector(aim.x, aim.y, 0):GetNormalized()
	if ent:IsPlayer() then
		ent:SetVelocity(flat * 330 + Vector(0, 0, 100))
		ent:ViewPunch(Angle(-8, math.Rand(-6, 6), math.Rand(-4, 4)))
		ent:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 65, math.random(95, 110))
		own:ViewPunch(Angle(4, 0, 0))
		return
	end
	if ent:IsNPC() then
		ent:SetVelocity(flat * 260)
		ent:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 65)
		return
	end
	local phys = ent:GetPhysicsObjectNum(tr.PhysicsBone or 0)
	if not IsValid(phys) then phys = ent:GetPhysicsObject() end
	if IsValid(phys) and phys:IsMoveable() then
		phys:Wake()
		phys:ApplyForceOffset(aim * math.min(phys:GetMass(), 80) * 300, tr.HitPos)
		ent:EmitSound("physics/wood/wood_box_impact_hard" .. math.random(1, 6) .. ".wav", 62)
		own:ViewPunch(Angle(3, 0, 0))
	end
end

function SWEP:Reload()
	if CLIENT then return end
	local own = self:GetOwner()
	if not IsValid(own) or not own:KeyPressed(IN_RELOAD) or own:GetNW2Bool("RPInvSurrender", false) then return end
	if (self.NextToggle or 0) > CurTime() or CurTime() - (own.RPInvFistsAt or 0) < 0.4 then return end
	self.NextToggle = CurTime() + 0.4
	if not own:HasWeapon("weapon_fists") then own:Give("weapon_fists") end
	own.RPInvFistsAt = CurTime()
	own:SelectWeapon("weapon_fists")
end

if SERVER then
	function SWEP:TryGrab(own)
		local eye, aim = own:GetShootPos(), own:GetAimVector()
		local tr = util.TraceLine({ start = eye, endpos = eye + aim * REACH, filter = own, mask = MASK_SHOT })
		local ent = tr.Entity
		if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsRagdoll() then return end
		if ent:IsWeapon() and IsValid(ent:GetOwner()) then return end
		if ent:GetClass() == "rpinv_container" then return end
		local phys = ent:GetPhysicsObject()
		if not IsValid(phys) or not phys:IsMoveable() or phys:GetMass() > maxMass:GetFloat() then return end
		if hook.Run("GravGunPickupAllowed", own, ent) == false then return end
		if hook.Run("RPInv_CanDrag", own, ent) == false then return end
		local dist = math.Clamp(eye:Distance(tr.HitPos), 40, 85)
		self.Drag = { ent = ent, phys = phys, lpos = phys:WorldToLocal(tr.HitPos), dist = dist }
		self:SetDragEnt(ent)
		self:SetDragLocal(ent:WorldToLocal(tr.HitPos))
		self:SetDragDist(dist)
	end

	function SWEP:UpdateDrag(own)
		local d = self.Drag
		if not IsValid(d.ent) or not IsValid(d.phys) or not d.phys:IsMoveable() then
			self:ClearDrag()
			return
		end
		local target = own:GetShootPos() + own:GetAimVector() * d.dist
		local grab = d.phys:LocalToWorld(d.lpos)
		if grab:DistToSqr(target) > 130 * 130 then
			self:ClearDrag()
			return
		end
		local vel = (target - grab) * 10
		if vel:Length() > 450 then vel = vel:GetNormalized() * 450 end
		d.phys:Wake()
		d.phys:ApplyForceOffset((vel - d.phys:GetVelocity()) * d.phys:GetMass() * 0.35, grab)
		d.phys:AddAngleVelocity(-d.phys:GetAngleVelocity() * 0.08)
	end

	function SWEP:Think()
		local own = self:GetOwner()
		if not IsValid(own) then return end
		if own:KeyDown(IN_ATTACK) and not own:GetNW2Bool("RPInvSurrender", false) then
			if not self.Drag and own:KeyPressed(IN_ATTACK) then self:TryGrab(own) end
			if self.Drag then self:UpdateDrag(own) end
		elseif self.Drag then
			self:ClearDrag()
		end
		self:NextThink(CurTime())
		return true
	end
end

if CLIENT then
	function SWEP:DrawWorldModel() end
	function SWEP:PreDrawViewModel() return true end

	local white = Color(255, 255, 255)
	local bmin, bmax = Vector(-0.6, -0.6, -0.6), Vector(0.6, 0.6, 0.6)

	hook.Add("PostDrawTranslucentRenderables", "RPInv_HandsDrag", function(depth, sky)
		if depth or sky then return end
		local lp = LocalPlayer()
		local drawn = false
		for _, ply in ipairs(player.GetAll()) do
			local w = ply:GetActiveWeapon()
			if IsValid(w) and w:GetClass() == "rpinv_hands" and w.GetDragEnt then
				local ent = w:GetDragEnt()
				if IsValid(ent) then
					if not drawn then
						render.SetColorMaterial()
						drawn = true
					end
					local grab = ent:LocalToWorld(w:GetDragLocal())
					local eye, aim
					if ply == lp then
						eye, aim = EyePos(), EyeAngles():Forward()
					else
						eye, aim = ply:EyePos(), ply:EyeAngles():Forward()
					end
					render.DrawLine(grab, eye + aim * w:GetDragDist(), white, true)
					render.DrawBox(grab, ent:GetAngles(), bmin, bmax, white)
				end
			end
		end
	end)
end
