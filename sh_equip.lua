RPInv = RPInv or {}

RPInv.EquipSlots = {
	{ key = "head", name = "HEADWEAR" },
	{ key = "ears", name = "EARPIECE" },
	{ key = "face", name = "FACE COVER" },
	{ key = "eyes", name = "EYEWEAR" },
	{ key = "body", name = "BODY ARMOR" },
	{ key = "belt", name = "BELT" },
	{ key = "back", name = "BACKPACK" },
	{ key = "lshoulder", name = "L SHOULDER" },
	{ key = "rshoulder", name = "R SHOULDER" },
	{ key = "lforearm", name = "L FOREARM" },
	{ key = "rforearm", name = "R FOREARM" },
	{ key = "lthigh", name = "L THIGH" },
	{ key = "rthigh", name = "R THIGH" },
	{ key = "lcalf", name = "L CALF" },
	{ key = "rcalf", name = "R CALF" },
	{ key = "primary", name = "PRIMARY", weapon = true },
	{ key = "secondary", name = "SECONDARY", weapon = true },
	{ key = "utility", name = "UTILITY", weapon = true },
}

RPInv.EquipSlotByKey = {}
for _, s in ipairs(RPInv.EquipSlots) do RPInv.EquipSlotByKey[s.key] = s end

RPInv.WeaponSlotKeys = { "primary", "secondary", "utility" }
RPInv.OldWeaponSlots = { sling = "primary", onback = "primary", holster = "secondary", sheath = "utility" }

RPInv.JModSlotOrder = {
	"head", "mouthnose", "eyes", "ears", "chest", "abdomen", "back", "pelvis", "waist",
	"leftshoulder", "rightshoulder", "leftforearm", "rightforearm",
	"leftthigh", "rightthigh", "leftcalf", "rightcalf",
}

RPInv.JModSlotMap = {
	head = "head", mouthnose = "face", eyes = "eyes", ears = "ears",
	chest = "body", abdomen = "body", back = "back", pelvis = "belt", waist = "belt",
	leftshoulder = "lshoulder", rightshoulder = "rshoulder", leftforearm = "lforearm", rightforearm = "rforearm",
	leftthigh = "lthigh", rightthigh = "rthigh", leftcalf = "lcalf", rightcalf = "rcalf",
}

RPInv.JModSlotSize = {
	head = { 2, 2 }, face = { 2, 2 }, eyes = { 2, 1 }, ears = { 2, 1 }, body = { 3, 3 }, back = { 4, 5 }, belt = { 2, 2 },
	lshoulder = { 2, 2 }, rshoulder = { 2, 2 }, lforearm = { 2, 1 }, rforearm = { 2, 1 },
	lthigh = { 2, 2 }, rthigh = { 2, 2 }, lcalf = { 2, 2 }, rcalf = { 2, 2 },
}

function RPInv.IsCarrierDef(def)
	return def ~= nil and (tonumber(def.grid_w) or 0) > 0 and (tonumber(def.grid_h) or 0) > 0
end

function RPInv.JModAvailable()
	return JMod ~= nil and istable(JMod.ArmorTable)
end

function RPInv.JModSlotFor(armorName)
	if not RPInv.JModAvailable() then return nil end
	local info = JMod.ArmorTable[armorName]
	if not info or not istable(info.slots) then return nil end
	if info.plymdl then return "body" end
	for _, js in ipairs(RPInv.JModSlotOrder) do
		if info.slots[js] ~= nil then return RPInv.JModSlotMap[js] end
	end
	for js in pairs(info.slots) do
		if RPInv.JModSlotMap[js] then return RPInv.JModSlotMap[js] end
	end
	return "body"
end

function RPInv.JModMaxDur(armorName)
	if not RPInv.JModAvailable() then return nil end
	local info = JMod.ArmorTable[armorName]
	return info and tonumber(info.dur) or nil
end

function RPInv.EquipSlotOf(def)
	if not def then return nil end
	if def.jmod_armor and def.jmod_armor ~= "" then
		return RPInv.JModSlotFor(def.jmod_armor) or (def.equip_slot ~= "" and def.equip_slot or nil)
	end
	local s = RPInv.EquipSlotByKey[def.equip_slot or ""]
	if s and s.weapon and def.use_type == "weapon" then return s.key end
	return nil
end

local V1, V0, A0 = Vector(1, 1, 1), Vector(0, 0, 0), Angle(0, 0, 0)

local function clearBones(ent)
	if not IsValid(ent) then return end
	for i = 0, ent:GetBoneCount() - 1 do
		ent:ManipulateBoneScale(i, V1)
		ent:ManipulateBoneAngles(i, A0)
		ent:ManipulateBonePosition(i, V0)
	end
end

function RPInv.ResetViewModel(ply)
	if not IsValid(ply) then return end
	local vm = ply:GetViewModel(0)
	if IsValid(vm) then
		clearBones(vm)
		vm:SetSubMaterial()
		vm:SetMaterial("")
		vm:ClearPoseParameters()
	end
	clearBones(ply:GetHands())
end

function RPInv.ApplyLook(ent, def)
	if not IsValid(ent) then return end
	ent:SetSkin(def and tonumber(def.skin) or 0)
	for i = 0, (ent:GetNumBodyGroups() or 1) - 1 do ent:SetBodygroup(i, 0) end
	local bg = def and def.bodygroups or ""
	if isstring(bg) and bg ~= "" then ent:SetBodyGroups(bg) end
end

function RPInv.ModelExists(path)
	if not isstring(path) or path == "" or not string.lower(path):match("%.mdl$") then return false end
	if SERVER then return util.IsValidModel(path) end
	return util.IsValidModel(path) or file.Exists(path, "GAME")
end

function RPInv.HandsClass()
	local c = RPInv.Settings and RPInv.Settings.hands_class
	if c == nil then return "rpinv_hands" end
	return c
end

RPInv.ModelFix = {
	["models/weapons/v_flaregun.mdl"] = {
		hide = { "v_hand_sheet" },
		bones = {
			Hand = { Vector(-5.748, -22.017, 59.119), Angle(0, 0, 90) },
			Cylinder_release = false,
		},
		mins = Vector(-6.44, -29.76, 57.12), maxs = Vector(-4.77, -20.64, 64.22),
		grip = Vector(-5.748, -22.017, 59.119), gunAng = Angle(0, -90, 0),
		proxy = "models/weapons/w_357.mdl", proxyAng = Angle(0, 90, 0),
	},
}

function RPInv.ModelFixBounds(model)
	local fix = RPInv.GetModelFix(model)
	if not fix then return nil end
	return { mins = fix.mins, maxs = fix.maxs, center = (fix.mins + fix.maxs) / 2 }
end

local ZERO = Vector(0, 0, 0)

local function fixBones(e)
	local fix = RPInv.GetModelFix(e:GetModel())
	if not fix then return end
	local w = e:GetWorldTransformMatrix()
	if e.RPInvFixOffset then w = w * e.RPInvFixOffset end
	for name, b in pairs(fix.bones) do
		local i = e:LookupBone(name)
		if i then
			local m = Matrix()
			if b then
				m:SetTranslation(b[1])
				m:SetAngles(b[2])
				m = w * m
			else
				m:SetTranslation(w:GetTranslation())
				m:Scale(ZERO)
			end
			e:SetBoneMatrix(i, m)
		end
	end
end

function RPInv.ModelFixHook(ent, offset)
	if not IsValid(ent) then return end
	ent.RPInvFixOffset = offset
	if ent.RPInvFixCB then return end
	ent.RPInvFixCB = ent:AddCallback("BuildBonePositions", fixBones)
end

function RPInv.GetModelFix(model)
	return isstring(model) and RPInv.ModelFix[string.lower(model)] or nil
end

function RPInv.ApplyModelFix(ent)
	if not IsValid(ent) then return nil end
	local fix = RPInv.GetModelFix(ent:GetModel())
	if not fix then return nil end
	for i, m in ipairs(ent:GetMaterials() or {}) do
		for _, h in ipairs(fix.hide) do
			if string.find(string.lower(m), h, 1, true) then ent:SetSubMaterial(i - 1, "rpinv/nodraw") end
		end
	end
	return fix
end