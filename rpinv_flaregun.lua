AddCSLuaFile()

SWEP.PrintName = "Signal Flare Gun"
SWEP.Author = "Sandbox Inventory+"
SWEP.Purpose = "Fire into open sky to call an airdrop. From the spawn menu it calls a random preset."
SWEP.Instructions = "LMB: fire the flare straight up. Single use."
SWEP.Category = "Sandbox Inventory+"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Slot = 4
SWEP.SlotPos = 9
SWEP.Weight = 1
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModelFOV = 65
SWEP.ViewModelFlip = false
SWEP.UseHands = false
SWEP.ViewModel = "models/weapons/v_flaregun.mdl"
SWEP.WorldModel = "models/weapons/w_357.mdl"
SWEP.HoldType = "pistol"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.FireSound = "weapons/flaregun/fire.wav"
SWEP.FlareSpeed = 1900

if CLIENT then
	SWEP.WepSelectIcon = surface.GetTextureID("vgui/entities/rpinv_flaregun")

	function SWEP:RPInvWorldGun()
		if IsValid(self.RPInvWM) then return self.RPInvWM, self.RPInvWMBase end
		local fix = RPInv.GetModelFix(self.ViewModel)
		if not fix then return nil end
		local c = ClientsideModel(self.ViewModel, RENDERGROUP_OPAQUE)
		if not IsValid(c) then return nil end
		c:SetNoDraw(true)
		RPInv.ApplyModelFix(c)
		RPInv.ModelFixHook(c)
		local g = Matrix()
		g:SetTranslation(fix.grip)
		g:SetAngles(fix.gunAng)
		local base = g:GetInverseTR()
		self.RPInvWM, self.RPInvWMBase = c, base
		self:CallOnRemove("RPInvWM", function(w) if IsValid(w.RPInvWM) then w.RPInvWM:Remove() end end)
		return c, base
	end

	function SWEP:DrawWorldModel()
		local ply = self:GetOwner()
		local gun, base = self:RPInvWorldGun()
		local hb = IsValid(ply) and ply:LookupBone("ValveBiped.Bip01_R_Hand")
		local hm = hb and ply:GetBoneMatrix(hb)
		self:SetupBones()
		local ai = self:LookupAttachment("muzzle")
		local att = ai and ai > 0 and self:GetAttachment(ai)
		if not gun or not hm or not att then
			self:DrawModel()
			return
		end
		local t = Matrix()
		t:SetTranslation(hm:GetTranslation())
		t:SetAngles(att.Ang)
		local e = t * base
		gun:SetPos(e:GetTranslation())
		gun:SetAngles(e:GetAngles())
		gun:InvalidateBoneCache()
		gun:DrawModel()
	end
end

function SWEP:SetupDataTables()
	self:NetworkVar("Bool", 0, "Fired")
end

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
	self:SendWeaponAnim(ACT_VM_DRAW)
	self:SetNextPrimaryFire(CurTime() + 0.6)
	return true
end

function SWEP:SecondaryAttack()
end

function SWEP:Reload()
end

function SWEP:PrimaryAttack()
	if self:GetFired() then return end
	local ply = self:GetOwner()
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if ply:GetNW2Bool("RPInvSurrender", false) then return end
	self:SetNextPrimaryFire(CurTime() + 5)
	if IsFirstTimePredicted() then
		self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
		ply:SetAnimation(PLAYER_ATTACK1)
		ply:ViewPunch(Angle(-6, math.Rand(-1, 1), 0))
	end
	if CLIENT then return end
	self:SetFired(true)
	self:EmitSound(self.FireSound, 90, math.random(96, 104))
	local aim = ply:GetAimVector()
	local start = ply:GetShootPos()
	local tr = util.TraceLine({ start = start, endpos = start + aim * 20, filter = ply, mask = MASK_SHOT_HULL })
	local flare = ents.Create("rpinv_flare")
	if IsValid(flare) then
		flare:SetPos(tr.HitPos - aim * 2)
		flare.RPInvVel = aim * self.FlareSpeed + ply:GetVelocity() * 0.5
		flare.RPInvPresets = self.RPInvPresets or ""
		flare.RPInvBy = ply
		flare:SetOwner(ply)
		flare:Spawn()
	end
	if RPInv and RPInv.DB then RPInv.DB.Log(ply, "flare_fire", tostring(self.RPInvItem) .. " " .. tostring(ply:GetPos())) end
	self.RPInvItem = nil
	timer.Simple(1.1, function()
		if not IsValid(self) or not IsValid(ply) then return end
		local hands = RPInv.HandsClass()
		if ply:GetActiveWeapon() == self and hands ~= "" and ply:HasWeapon(hands) then ply:SelectWeapon(hands) end
		timer.Simple(0.2, function()
			if IsValid(ply) and ply:HasWeapon("rpinv_flaregun") then ply:StripWeapon("rpinv_flaregun") end
		end)
	end)
end

if SERVER then
	function SWEP:Equip(ply)
		self.RPInvHolder = ply
	end

	function SWEP:ReturnItem()
		local item = self.RPInvItem
		self.RPInvItem = nil
		local ply = self.RPInvHolder
		if not item or self:GetFired() or not IsValid(ply) or not RPInv or not RPInv.Items[item] then return end
		local left = RPInv.GiveToPlayer(ply, item, 1)
		if left > 0 and RPInv.SpawnWorldItem then
			RPInv.SpawnWorldItem(item, 1, ply:GetPos() + Vector(0, 0, 40))
			RPInv.Notify(ply, "No room for the flare gun. It was dropped.", 2)
		end
		RPInv.Push(RPInv.PlayerStorage(ply))
	end

	function SWEP:Holster()
		if not self:GetFired() and self.RPInvItem then
			self:ReturnItem()
			local ply = self.RPInvHolder
			timer.Simple(0, function()
				if IsValid(ply) and ply:HasWeapon("rpinv_flaregun") then ply:StripWeapon("rpinv_flaregun") end
			end)
		end
		return true
	end

	function SWEP:OnDrop()
		self:ReturnItem()
		self:Remove()
	end

	function SWEP:OnRemove()
		self:ReturnItem()
	end
end
