local T = RPInv.Theme
local A = RPInv.Att

local win
local FOV = 30
local HAND = "ValveBiped.Bip01_R_Hand"
local ORIGIN = Vector(0, 0, 0)
local LINE = Color(235, 235, 228, 110)

local function readJSON()
	local len = net.ReadUInt(32)
	return util.JSONToTable(util.Decompress(net.ReadData(len)) or "") or {}
end

local function request(slot)
	RPInv.Act({ a = "attinfo", w = slot })
end

local function slotWeapon(slot)
	local list = RPInv.Equipped and RPInv.Equipped[slot]
	local e = list and list[1]
	local def = e and RPInv.Items[e.item]
	if not def or def.use_type ~= "weapon" then return nil end
	local wep = LocalPlayer():GetWeapon(def.use_arg)
	if IsValid(wep) then return wep, def end
end

local function call(wep, fn, ...)
	if not isfunction(fn) then return nil end
	local ok, r = pcall(fn, wep, ...)
	if ok then return r end
end

local function placeArcCW(base, wep)
	local wmo = wep.WorldModelOffset
	if wmo and not wep.MirrorVMWM then
		local o = wmo.pos or ORIGIN
		local ang = Angle(0, 0, 0)
		local a = wmo.ang or Angle(0, 0, 0)
		ang:RotateAroundAxis(ang:Right(), a.p)
		ang:RotateAroundAxis(ang:Up(), a.y)
		ang:RotateAroundAxis(ang:Forward(), a.r)
		base:SetPos(Vector(o.x, -o.y, o.z))
		base:SetAngles(ang)
	else
		base:SetPos(ORIGIN)
		base:SetAngles(Angle(0, 0, 0))
	end
	base:InvalidateBoneCache()
	base:SetupBones()
end

local function arccwMode(wep)
	if wep.MirrorVMWM then return "mirror" end
	if istable(wep.WorldModelOffset) then return "offset" end
	return "merge"
end

local function arccwOffset(wep, k, e)
	local s = k and istable(wep.Attachments) and wep.Attachments[k]
	if not istable(s) then return (e and e.OffsetPos) or ORIGIN end
	local mirror = wep.MirrorVMWM
	if istable(s.SlideAmount) then
		local d = s.SlidePos or 0.5
		if mirror then return LerpVector(d, s.SlideAmount.vmin or ORIGIN, s.SlideAmount.vmax or ORIGIN) end
		return LerpVector(d, s.SlideAmount.wmin or ORIGIN, s.SlideAmount.wmax or ORIGIN)
	end
	local o = istable(s.Offset) and s.Offset or {}
	return (mirror and o.vpos or o.wpos) or ORIGIN
end

local function arccwBoneFrame(wep, base, k, e)
	local mode = arccwMode(wep)
	if mode == "offset" then return Vector(ORIGIN), Angle(0, 0, 0) end
	local s = k and istable(wep.Attachments) and wep.Attachments[k]
	local bname = (e and e.WMBone) or (mode == "mirror" and s and s.Bone) or (s and s.WMBone) or HAND
	local bi = isstring(bname) and base:LookupBone(bname)
	local m = bi and base:GetBoneMatrix(bi)
	if m then return m:GetTranslation(), m:GetAngles() end
	return base:GetPos(), base:GetAngles()
end

local function arccwPlace(wep, base, k, e)
	local bpos, bang = arccwBoneFrame(wep, base, k, e)
	local off = arccwOffset(wep, k, e)
	local apos = bpos + bang:Forward() * off.x + bang:Right() * off.y + bang:Up() * off.z
	local aang = Angle(bang.p, bang.y, bang.r)
	local oa = (e and e.OffsetAng) or Angle(0, 0, 0)
	aang:RotateAroundAxis(aang:Right(), oa.p)
	aang:RotateAroundAxis(aang:Up(), oa.y)
	aang:RotateAroundAxis(aang:Forward(), oa.r)
	local mo = (e and e.ModelOffset) or ORIGIN
	apos = apos + aang:Forward() * mo.x + aang:Right() * mo.y + aang:Up() * mo.z
	return apos, aang
end

local function drawArcCW(wep, base)
	if not istable(wep.WM) then call(wep, wep.SetupModel, true) end
	for _, e in pairs(istable(wep.WM) and wep.WM or {}) do
		if istable(e) and not e.IsBaseWM and not e.BoneMerge and not e.NoDraw and IsValid(e.Model) then
			local pos, ang = arccwPlace(wep, base, e.Slot, e)
			e.Model:SetPos(pos)
			e.Model:SetAngles(ang)
			e.Model:SetRenderOrigin(pos)
			e.Model:SetRenderAngles(ang)
			if e.Bodygroups then e.Model:SetBodyGroups(e.Bodygroups) end
			e.Model:SetupBones()
			e.Model:DrawModel()
		end
	end
end

local function anchorArcCW(wep, base, k)
	if not k or not istable(wep.Attachments) or not istable(wep.Attachments[k]) then return nil end
	for _, e in pairs(istable(wep.WM) and wep.WM or {}) do
		if istable(e) and e.Slot == k and IsValid(e.Model) and not e.NoDraw and not e.BoneMerge then return e.Model:WorldSpaceCenter() end
	end
	local s = wep.Attachments[k]
	local o = istable(s.Offset) and s.Offset
	if not istable(s.SlideAmount) and not (o and ((wep.MirrorVMWM and o.vpos) or (not wep.MirrorVMWM and o.wpos))) then return nil end
	return (arccwPlace(wep, base, k, nil))
end

local function anchorTacRP(wep, base, k)
	local s = istable(wep.Attachments) and wep.Attachments[k]
	if not istable(s) then return nil end
	if IsValid(s.WModel) then return s.WModel:WorldSpaceCenter() end
	if not s.Pos_WM then return nil end
	local bi = base:LookupBone(s.WMBone or HAND)
	local m = bi and base:GetBoneMatrix(bi)
	if not m then return nil end
	local bp, ba = m:GetTranslation(), m:GetAngles()
	local o = s.Pos_WM or ORIGIN
	return bp + ba:Forward() * o.x + ba:Right() * o.y + ba:Up() * o.z
end

local function statRows(wep, base)
	local rows = {}
	local function add(label, v, unit, digits)
		v = tonumber(v)
		if not v or v ~= v then return end
		rows[#rows + 1] = { label, (digits and string.format("%." .. digits .. "f", v) or tostring(math.Round(v))) .. (unit or "") }
	end
	local ammo = game.GetAmmoName(wep:GetPrimaryAmmoType() or -1)
	if ammo then rows[#rows + 1] = { "CALIBER", string.upper(language.GetPhrase(ammo .. "_ammo") ~= ammo .. "_ammo" and language.GetPhrase(ammo .. "_ammo") or ammo) } end
	add("MAGAZINE", wep:GetMaxClip1())
	if base == "arccw" then
		local d = tonumber(call(wep, wep.GetFiringDelay))
		if d and d > 0 then add("FIRE RATE", 60 / d, " rpm") end
		add("DAMAGE", call(wep, wep.GetBuff, "Damage"))
		add("RANGE", call(wep, wep.GetBuff, "Range"), " m")
		add("PRECISION", call(wep, wep.GetBuff, "AccuracyMOA"), " MOA", 1)
		add("RECOIL", call(wep, wep.GetBuff, "Recoil"), nil, 2)
	elseif base == "tacrp" then
		add("FIRE RATE", call(wep, wep.GetValue, "RPM"), " rpm")
		add("DAMAGE", call(wep, wep.GetValue, "Damage_Max"))
		local r = tonumber(call(wep, wep.GetValue, "Range_Max"))
		if r then add("RANGE", r * 0.0254, " m") end
		add("SPREAD", call(wep, wep.GetValue, "Spread"), nil, 3)
		add("RECOIL", call(wep, wep.GetValue, "RecoilKick"), nil, 2)
	elseif base == "arc9" then
		add("FIRE RATE", call(wep, wep.GetProcessedValue, "RPM"), " rpm")
		add("DAMAGE", call(wep, wep.GetProcessedValue, "DamageMax"))
		local r = tonumber(call(wep, wep.GetProcessedValue, "RangeMax"))
		if r then add("RANGE", r * 0.0254, " m") end
		add("SPREAD", call(wep, wep.GetProcessedValue, "Spread"), nil, 3)
		add("RECOIL", call(wep, wep.GetProcessedValue, "Recoil"), nil, 2)
	elseif base == "tfa" then
		add("FIRE RATE", call(wep, wep.GetStatL, "Primary.RPM"), " rpm")
		add("DAMAGE", call(wep, wep.GetStatL, "Primary.Damage"))
		local r = tonumber(call(wep, wep.GetStatL, "Primary.Range"))
		if r and r > 0 then add("RANGE", r * 0.0254, " m") end
		add("SPREAD", call(wep, wep.GetStatL, "Primary.Spread"), nil, 3)
		add("RECOIL", call(wep, wep.GetStatL, "Primary.KickUp"), nil, 2)
	end
	return rows
end

local function shortText(text, font, width)
	surface.SetFont(font)
	if surface.GetTextSize(text) <= width then return text end
	local s = text
	while #s > 1 and surface.GetTextSize(s .. ".") > width do s = string.sub(s, 1, #s - 1) end
	return string.TrimRight(s) .. "."
end

local function slotMenu(info, slot)
	local m = T.Menu()
	local any = false
	for _, o in ipairs(info.opts or {}) do
		any = true
		T.MenuOption(m, "INSTALL: " .. o.n, function() RPInv.Act({ a = "attach", w = slot, k = info.k, item = o.item }) end)
	end
	if info.i and not info.free and not info.fixed then
		any = true
		T.MenuOption(m, "REMOVE: " .. (A.Phrase(info.inm) or info.i), function() RPInv.Act({ a = "detach", w = slot, k = info.k }) end)
	end
	if not any then
		m:Remove()
		RPInv.Toast(info.fixed and "This slot cannot be changed." or "You have no attachments for this slot.", 0)
		return
	end
	m:Open()
end

local BOX = {}

function BOX:Init()
	self:SetMouseInputEnabled(true)
	self:SetCursor("hand")
end

function BOX:Setup(info, base)
	self.Info = info
	self.Base = base
	self.IconDef = info.i and { use_arg = base .. ":" .. info.i } or nil
end

function BOX:Paint(w, h)
	local info = self.Info
	local hot = self:IsHovered()
	surface.SetDrawColor(10, 11, 10, 230)
	surface.DrawRect(0, 0, w, h)
	local head = T.S(16)
	surface.SetDrawColor(T.HeadBg)
	surface.DrawRect(0, 0, w, head)
	draw.SimpleText(shortText(string.upper(A.Phrase(info.n) or info.n), "RPInv.Tiny", w - T.S(8)), "RPInv.Tiny", T.S(4), head / 2, T.Mid, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local icon = self.IconDef and A.Icon(self.IconDef)
	if icon then
		local s = h - head - T.S(22)
		surface.SetMaterial(icon)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRect((w - s) / 2, head + T.S(3), s, s)
	elseif not info.i then
		T.Hatch(w, h, T.S(9), Color(255, 255, 255, 5))
	end
	local name = info.i and (A.Phrase(info.inm) or info.i) or "NONE"
	draw.SimpleText(shortText(name, "RPInv.Small", w - T.S(8)), "RPInv.Small", T.S(4), h - T.S(4), info.i and T.White or T.Dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	if info.fixed then
		draw.SimpleText("FIXED", "RPInv.Tiny", w - T.S(4), head + T.S(3), T.Dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	elseif #(info.opts or {}) > 0 then
		local b = T.S(14)
		surface.SetDrawColor(T.GhostOk.r, T.GhostOk.g, T.GhostOk.b, 230)
		surface.DrawRect(w - b - 2, h - b - 2, b, b)
		draw.SimpleText(tostring(#info.opts), "RPInv.Tiny", w - b / 2 - 2, h - b / 2 - 2, T.White, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	surface.SetDrawColor(hot and T.White or (info.i and T.Accent or T.Dim))
	surface.DrawOutlinedRect(0, 0, w, h, 1)
end

function BOX:OnMousePressed(code)
	if code == MOUSE_LEFT or code == MOUSE_RIGHT then
		surface.PlaySound("ui/buttonclick.wav")
		slotMenu(self.Info, win and win.Slot)
	end
end

vgui.Register("RPInvModSlot", BOX, "DPanel")

local VIEW = {}

local openViews = setmetatable({}, { __mode = "k" })

function VIEW:Init()
	openViews[self] = true
	self.Yaw, self.Pitch, self.Zoom = 0, 0, 1
	self.Boxes = {}
	self.Anchors = {}
	self.FitFrames = 0
	self:SetMouseInputEnabled(true)
end

function VIEW:SetData(t)
	for _, b in pairs(self.Boxes) do b:Remove() end
	self.Boxes = {}
	self.Data = t
	self.Rebuild = true
	if not istable(t.slots) then return end
	local base = A.BaseOfClass(self.Class) or ""
	for _, info in ipairs(t.slots) do
		local b = vgui.Create("RPInvModSlot", self)
		b:Setup(info, base)
		b:SetSize(T.S(108), T.S(88))
		b:SetVisible(false)
		self.Boxes[info.k] = b
	end
end

function VIEW:BaseModel(path)
	if not isstring(path) or path == "" or not RPInv.ModelExists(path) then return nil end
	if IsValid(self.Model) and self.Model:GetModel() == path then return self.Model end
	if IsValid(self.Model) then self.Model:Remove() end
	local m = ClientsideModel(path)
	if not IsValid(m) then return nil end
	m:SetNoDraw(true)
	self.Model = m
	self.Cam = nil
	return m
end

function VIEW:OnRemove()
	if IsValid(self.Model) then self.Model:Remove() end
	if IsValid(self.Proxy) then self.Proxy:Remove() end
	local wep = self.LastWeapon
	if IsValid(wep) and wep.ARC9 then call(wep, wep.KillModel, true) end
end

function VIEW:OnMousePressed(code)
	if code == MOUSE_LEFT then self.Grab = { gui.MousePos() } end
end

function VIEW:OnMouseWheeled(delta)
	self.Zoom = math.Clamp(self.Zoom * (delta > 0 and 0.9 or 1.1), 0.4, 2.5)
	return true
end

function VIEW:Think()
	if self.Grab then
		if not input.IsMouseDown(MOUSE_LEFT) then
			self.Grab = nil
		else
			local mx, my = gui.MousePos()
			self.Yaw = self.Yaw + (mx - self.Grab[1]) * 0.4
			self.Pitch = math.Clamp(self.Pitch + (my - self.Grab[2]) * 0.4, -80, 80)
			self.Grab = { mx, my }
		end
	end
end

local SIDE_HINTS = { up = { "optic", "sight", "scope", "top", "tac_top", "rail_top" }, front = { "muzzle", "barrel", "suppressor", "silencer" } }

local function hinted(name, list)
	name = string.lower(tostring(name or ""))
	for _, w in ipairs(list) do
		if string.find(name, w, 1, true) then return true end
	end
	return false
end

local function corners(mn, mx)
	return {
		Vector(mn.x, mn.y, mn.z), Vector(mx.x, mx.y, mx.z), Vector(mn.x, mn.y, mx.z), Vector(mn.x, mx.y, mn.z),
		Vector(mx.x, mn.y, mn.z), Vector(mx.x, mx.y, mn.z), Vector(mx.x, mn.y, mx.z), Vector(mn.x, mx.y, mx.z),
	}
end

function VIEW:FitCamera(fr, points, w, h)
	local size = fr.mx - fr.mn
	local o = fr.pos
	local ax = LocalToWorld(Vector(1, 0, 0), Angle(0, 0, 0), o, fr.ang) - o
	local ay = LocalToWorld(Vector(0, 1, 0), Angle(0, 0, 0), o, fr.ang) - o
	local az = LocalToWorld(Vector(0, 0, 1), Angle(0, 0, 0), o, fr.ang) - o
	local list = { { ax, size.x }, { ay, size.y }, { az, size.z } }
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local L, U, V = list[1][1], list[2][1], list[3][1]
	local center = LocalToWorld((fr.mn + fr.mx) / 2, Angle(0, 0, 0), o, fr.ang)
	local mf = fr.model and A.MeshFrame(fr.model)
	if mf then
		local function dir(v) return LocalToWorld(v, Angle(0, 0, 0), Vector(0, 0, 0), fr.ang) end
		L, U = dir(mf.L), dir(mf.U)
		local f = L:Cross(U):GetNormalized()
		if f:Cross(U):Dot(-L) < 0 then f = -f end
		center = LocalToWorld(mf.center, Angle(0, 0, 0), o, fr.ang)
		self:FinishCamera(fr, points, w, h, L, U, f, center)
		return
	end
	local function score(dir, which)
		local s, n = 0, 0
		for k, p in pairs(points) do
			local slot = self.SlotNames[k]
			if slot and hinted(slot, SIDE_HINTS[which]) then
				s = s + (p - center):Dot(dir)
				n = n + 1
			end
		end
		return n > 0 and s or nil
	end
	local su = score(U, "up")
	if su and su < 0 then U = -U elseif not su and U.z < 0 then U = -U end
	local sf = score(L, "front")
	if sf and sf < 0 then L = -L end
	local f = V
	if f:Cross(U):Dot(-L) < 0 then f = -f end
	self:FinishCamera(fr, points, w, h, L, U, f, center)
end

function VIEW:FinishCamera(fr, points, w, h, L, U, f, center)
	local o = fr.pos
	local lo, hi = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
	local function push(p)
		local q = Vector((p - center):Dot(L), (p - center):Dot(U), (p - center):Dot(f))
		lo.x, lo.y, lo.z = math.min(lo.x, q.x), math.min(lo.y, q.y), math.min(lo.z, q.z)
		hi.x, hi.y, hi.z = math.max(hi.x, q.x), math.max(hi.y, q.y), math.max(hi.z, q.z)
	end
	for _, c in ipairs(corners(fr.mn, fr.mx)) do push(LocalToWorld(c, Angle(0, 0, 0), o, fr.ang)) end
	for _, p in pairs(points) do push(p) end
	local mid = center + L * ((lo.x + hi.x) / 2) + U * ((lo.y + hi.y) / 2)
	local tanH = math.tan(math.rad(FOV / 2))
	local tanV = tanH * h / w
	local dist = math.max((hi.x - lo.x) / 2 / tanH, (hi.y - lo.y) / 2 / tanV) * 1.25 + (hi.z - lo.z) / 2
	self.Cam = { center = mid, ang = f:AngleEx(U), up = U, dist = math.max(dist, 20), offset = mid - fr.pos, ref = fr.pos }
	self.FitFrames = 3
end

local function entFrame(ent)
	local mn, mx = ent:GetModelBounds()
	return { mn = mn, mx = mx, pos = ent:GetPos(), ang = ent:GetAngles(), model = ent:GetModel() }
end

local function handAtOrigin(ent)
	ent:SetPos(ORIGIN)
	ent:SetAngles(Angle(0, 0, 0))
	ent:InvalidateBoneCache()
	ent:SetupBones()
	local bi = ent:LookupBone(HAND)
	local b = bi and ent:GetBoneMatrix(bi)
	if not b then return false end
	local w = Matrix()
	w:SetTranslation(ORIGIN)
	local m = w * b:GetInverseTR() * w
	ent:SetPos(m:GetTranslation())
	ent:SetAngles(m:GetAngles())
	ent:InvalidateBoneCache()
	ent:SetupBones()
	return true
end

local function tfaProxy(view)
	local mdl = LocalPlayer():GetModel()
	if not IsValid(view.Proxy) or view.Proxy:GetModel() ~= mdl then
		if IsValid(view.Proxy) then view.Proxy:Remove() end
		view.Proxy = ClientsideModel(mdl)
		if not IsValid(view.Proxy) then return nil end
		view.Proxy:SetNoDraw(true)
	end
	handAtOrigin(view.Proxy)
	return view.Proxy
end

local function tfaPlace(view, wep, base)
	local wmo = call(wep, wep.GetStatRawL, "WorldModelOffset") or wep.WorldModelOffset
	if istable(wmo) and istable(wmo.Pos) and istable(wmo.Ang) then
		local ang = Angle(0, 0, 0)
		local op, oa = wmo.Pos, wmo.Ang
		local pos = ang:Forward() * (op.Forward or 0) + ang:Right() * (op.Right or 0) + ang:Up() * (op.Up or 0)
		ang:RotateAroundAxis(ang:Up(), oa.Up or 0)
		ang:RotateAroundAxis(ang:Right(), oa.Right or 0)
		ang:RotateAroundAxis(ang:Forward(), oa.Forward or 0)
		base:SetPos(pos)
		base:SetAngles(ang)
		base:SetModelScale(tonumber(wmo.Scale) or 1, 0)
		base:InvalidateBoneCache()
		base:SetupBones()
		view.TFABones = tfaProxy(view) or base
		return
	end
	if not handAtOrigin(base) then
		base:SetPos(ORIGIN)
		base:SetAngles(Angle(0, 0, 0))
		base:SetupBones()
	end
	view.TFABones = base
end

local function tfaElements(wep)
	local raw = call(wep, wep.GetStatRaw, "WorldModelElements", TFA and TFA.LatestDataVersion or 1)
	return istable(raw) and raw or (istable(wep.WElements) and wep.WElements) or {}
end

local function tfaAnchor(wep, k)
	local s = A.SlotTable(wep, tonumber(k) or k)
	if not s then return nil end
	local sel = tonumber(s.sel) or 0
	local att = sel > 0 and istable(s.atts) and s.atts[sel]
	local t = att and A.AttTable("tfa", att)
	local wt = t and t.WeaponTable
	if not istable(wt) then return nil end
	local elems = tfaElements(wep)
	for _, list in ipairs({ wt.WorldModelElements, wt.WElements, wt.ViewModelElements, wt.VElements }) do
		if istable(list) then
			for name in pairs(list) do
				local e = elems[name]
				if istable(e) and IsValid(e.curmodel) then return e.curmodel:WorldSpaceCenter() end
			end
		end
	end
end

local SCENES = {}

SCENES.arccw = {
	prepare = function(view, wep)
		local path = (IsValid(wep.WMModel) and wep.WMModel:GetModel()) or (wep.MirrorVMWM and (wep.MirrorWorldModel or wep.ViewModel)) or wep.WorldModel
		local base = view:BaseModel(path)
		if not base then return nil end
		placeArcCW(base, wep)
		if IsValid(wep.WMModel) then
			base:SetSkin(wep.WMModel:GetSkin())
			for i = 0, base:GetNumBodyGroups() - 1 do base:SetBodygroup(i, wep.WMModel:GetBodygroup(i)) end
		end
		return base, entFrame(base)
	end,
	draw = function(view, wep, base)
		base:DrawModel()
		drawArcCW(wep, base)
	end,
	anchor = function(view, wep, base, k) return anchorArcCW(wep, base, tonumber(k)) end,
}

SCENES.tacrp = {
	prepare = function(view, wep)
		local base = view:BaseModel(wep.WorldModel)
		if not base then return nil end
		base:SetPos(ORIGIN)
		base:SetAngles(Angle(0, 0, 0))
		base:InvalidateBoneCache()
		base:SetupBones()
		call(wep, wep.DoBodygroups, true, base)
		return base, entFrame(base)
	end,
	draw = function(view, wep, base)
		base:DrawModel()
		call(wep, wep.DrawCustomModel, true, base)
	end,
	anchor = function(view, wep, base, k)
		local n = tonumber(k)
		return n and anchorTacRP(wep, base, n) or nil
	end,
}

SCENES.arc9 = {
	prepare = function(view, wep)
		if not wep.MirrorVMWM then
			local base = view:BaseModel(wep.WorldModel)
			if not base then return nil end
			base:SetPos(ORIGIN)
			base:SetAngles(Angle(0, 0, 0))
			return base, entFrame(base)
		end
		if view.Rebuild or not istable(wep.CModel) or not IsValid(wep.CModel[1]) then
			view.Rebuild = nil
			call(wep, wep.KillModel, true)
			call(wep, wep.SetupModel, true, 0, true)
		end
		local base = istable(wep.CModel) and wep.CModel[1]
		if not IsValid(base) then return nil end
		base:SetPos(ORIGIN)
		base:SetAngles(Angle(0, 0, 0))
		return base, entFrame(base)
	end,
	draw = function(view, wep, base)
		if not wep.MirrorVMWM then
			base:DrawModel()
			return
		end
		local old = ARC9.PresetCam
		ARC9.PresetCam = true
		call(wep, wep.DrawCustomModel, true, Vector(ORIGIN), Angle(0, 0, 0))
		ARC9.PresetCam = old
	end,
	anchor = function(view, wep, base, k)
		if not wep.MirrorVMWM then return nil end
		local s = A.SlotTable(wep, tonumber(k))
		if not s or (not s.Pos and not s.Installed) then return nil end
		local p = call(wep, wep.GetAttachmentPos, s, true, false, false, Vector(ORIGIN), Angle(0, 0, 0))
		return isvector(p) and p or nil
	end,
}

local function drawTFA(view, wep, base)
	base:DrawModel()
	local elems = tfaElements(wep)
	if not istable(wep.wRenderOrder) then call(wep, wep.RebuildModsRenderOrder) end
	local bones = IsValid(view.TFABones) and view.TFABones or base
	for _, name in ipairs(istable(wep.wRenderOrder) and wep.wRenderOrder or {}) do
		local e = elems[name]
		if istable(e) and e.type == "Model" and not e.hide and not e.bonemerge then
			if call(wep, wep.GetStatL, "WorldModelElements." .. name .. ".active") ~= false then
				call(wep, wep.PrecacheElement, e, true)
				local model = e.curmodel
				if IsValid(model) and isfunction(wep.GetBoneOrientation) then
					local ent = bones:LookupBone(e.bone or HAND) and bones or base
					local ok, pos, ang = pcall(wep.GetBoneOrientation, wep, elems, e, ent, (not e.bone) and HAND or nil)
					if ok and isvector(pos) and isangle(ang) then
						local ep = e.pos or ORIGIN
						local ea = e.angle or Angle(0, 0, 0)
						model:SetPos(pos + ang:Forward() * ep.x + ang:Right() * ep.y + ang:Up() * ep.z)
						ang:RotateAroundAxis(ang:Up(), ea.y)
						ang:RotateAroundAxis(ang:Right(), ea.p)
						ang:RotateAroundAxis(ang:Forward(), ea.r)
						model:SetAngles(ang)
						local c = e.color or color_white
						render.SetColorModulation((c.r or 255) / 255, (c.g or 255) / 255, (c.b or 255) / 255)
						render.SetBlend((c.a or 255) / 255)
						model:DrawModel()
						render.SetBlend(1)
						render.SetColorModulation(1, 1, 1)
					end
				end
			end
		end
	end
end

SCENES.tfa = {
	prepare = function(view, wep)
		local base = view:BaseModel(wep.WorldModel)
		if not base then return nil end
		tfaPlace(view, wep, base)
		call(wep, wep.IterateBodygroups, base, "WorldModelBodygroups", TFA and TFA.LatestDataVersion or 1)
		return base, entFrame(base)
	end,
	draw = function(view, wep, base) drawTFA(view, wep, base) end,
	anchor = function(view, wep, base, k) return tfaAnchor(wep, k) end,
}

SCENES.plain = {
	prepare = function(view, wep)
		local base = view:BaseModel(wep.WorldModel)
		if not base then return nil end
		base:SetPos(ORIGIN)
		base:SetAngles(Angle(0, 0, 0))
		return base, entFrame(base)
	end,
	draw = function(view, wep, base) base:DrawModel() end,
	anchor = function() return nil end,
}

local function clampTo(base, p)
	local mn, mx = base:GetModelBounds()
	local pad = (mx - mn) * 0.08
	local l = base:WorldToLocal(p)
	l.x = math.Clamp(l.x, mn.x - pad.x, mx.x + pad.x)
	l.y = math.Clamp(l.y, mn.y - pad.y, mx.y + pad.y)
	l.z = math.Clamp(l.z, mn.z - pad.z, mx.z + pad.z)
	return base:LocalToWorld(l)
end

function VIEW:CollectAnchors(scene, wep, base)
	local pts = {}
	if not self.Data or not istable(self.Data.slots) then return pts end
	for _, info in ipairs(self.Data.slots) do
		local p = scene.anchor(self, wep, base, info.k)
		if isvector(p) then pts[info.k] = clampTo(base, p) end
	end
	return pts
end

local function lighting(center)
	render.SuppressEngineLighting(true)
	render.SetLightingOrigin(center)
	render.ResetModelLighting(0.32, 0.33, 0.35)
	render.SetColorModulation(1, 1, 1)
	render.SetBlend(1)
	render.SetModelLighting(BOX_TOP, 0.95, 0.95, 0.92)
	render.SetModelLighting(BOX_FRONT, 0.55, 0.56, 0.58)
	render.SetModelLighting(BOX_BACK, 0.45, 0.46, 0.5)
	render.SetModelLighting(BOX_LEFT, 0.6, 0.6, 0.62)
	render.SetModelLighting(BOX_RIGHT, 0.6, 0.6, 0.62)
	render.SetModelLighting(BOX_BOTTOM, 0.18, 0.18, 0.2)
end

local function placeRow(list, y, w, bw, gap)
	table.sort(list, function(a, b) return a.ax < b.ax end)
	local n = #list
	if n == 0 then return end
	local total = n * bw + (n - 1) * gap
	local xs = {}
	for i, e in ipairs(list) do xs[i] = math.Clamp(e.ax - bw / 2, 0, w - bw) end
	for i = 2, n do xs[i] = math.max(xs[i], xs[i - 1] + bw + gap) end
	if xs[n] + bw > w then
		xs[n] = w - bw
		for i = n - 1, 1, -1 do xs[i] = math.min(xs[i], xs[i + 1] - bw - gap) end
	end
	if total > w then
		for i = 1, n do xs[i] = (i - 1) * (w - bw) / math.max(1, n - 1) end
	end
	for i, e in ipairs(list) do e.box:SetPos(math.floor(xs[i]), y) end
end

function VIEW:Layout(w, h, centerY)
	local bw, bh = T.S(108), T.S(88)
	local gap = T.S(10)
	local cap = math.max(1, math.floor((w + gap) / (bw + gap)))
	local top, bottom, loose = {}, {}, {}
	for _, info in ipairs(self.Data and self.Data.slots or {}) do
		local box = self.Boxes[info.k]
		if IsValid(box) then
			box:SetVisible(true)
			local a = self.Anchors[info.k]
			if a then
				local e = { box = box, ax = a.x, ay = a.y }
				if a.y < centerY then top[#top + 1] = e else bottom[#bottom + 1] = e end
			else
				loose[#loose + 1] = { box = box, ax = w + #loose }
			end
		end
	end
	for _, e in ipairs(loose) do
		if #top <= #bottom then top[#top + 1] = e else bottom[#bottom + 1] = e end
	end
	local function rows(list, ys)
		table.sort(list, function(a, b) return a.ax < b.ax end)
		local chunks = {}
		for i, e in ipairs(list) do
			local r = math.floor((i - 1) / cap) + 1
			chunks[r] = chunks[r] or {}
			table.insert(chunks[r], e)
		end
		for r, c in ipairs(chunks) do placeRow(c, ys(r), w, bw, gap) end
	end
	rows(top, function(r) return T.S(8) + (r - 1) * (bh + gap) end)
	rows(bottom, function(r) return h - T.S(8) - bh - (r - 1) * (bh + gap) end)
end

function VIEW:Paint(w, h)
	surface.SetDrawColor(8, 10, 12, 255)
	surface.DrawRect(0, 0, w, h)
	for i = 0, 4 do
		surface.SetDrawColor(30, 44, 56, 18 - i * 3)
		surface.DrawRect(w * (0.15 + i * 0.05), 0, w * (0.7 - i * 0.1), h)
	end
	local wep = slotWeapon(self.Slot)
	if not IsValid(wep) then
		draw.SimpleText("EQUIP THE WEAPON TO MODIFY IT", "RPInv.Text", w / 2, h / 2, T.Mid, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return
	end
	if self.LastWeapon ~= wep then
		self.LastWeapon = wep
		self.Cam = nil
	end
	self.Class = wep:GetClass()
	local kind = A.BaseOf(wep)
	local scene = SCENES[kind] or SCENES.plain
	local base, fr = scene.prepare(self, wep)
	if not IsValid(base) or not fr then
		scene = SCENES.plain
		base, fr = scene.prepare(self, wep)
		if not IsValid(base) or not fr then return end
	end
	self.SlotNames = {}
	for _, info in ipairs(self.Data and self.Data.slots or {}) do self.SlotNames[info.k] = info.n end
	local x, y = self:LocalToScreen(0, 0)
	if not self.Cam then
		cam.Start3D(fr.pos + Vector(-100, 0, 0), Angle(0, 0, 0), FOV, x, y, w, h, 1, 4096)
		render.OverrideColorWriteEnable(true, false)
		scene.draw(self, wep, base)
		render.OverrideColorWriteEnable(false, false)
		local pts = self:CollectAnchors(scene, wep, base)
		cam.End3D()
		self:FitCamera(fr, pts, w, h)
	end
	local cf = self.Cam
	local center = fr.pos + cf.offset
	local ang = Angle(cf.ang.p, cf.ang.y, cf.ang.r)
	ang:RotateAroundAxis(cf.up, self.Yaw)
	ang:RotateAroundAxis(ang:Right(), -self.Pitch)
	local camPos = center - ang:Forward() * (cf.dist * self.Zoom)
	cam.Start3D(camPos, ang, FOV, x, y, w, h, 1, 8192)
	render.ClearDepth()
	lighting(center)
	scene.draw(self, wep, base)
	local pts = self:CollectAnchors(scene, wep, base)
	self.Anchors = {}
	for k, p in pairs(pts) do
		local s = p:ToScreen()
		if s.visible then self.Anchors[k] = { x = s.x - x, y = s.y - y } end
	end
	local c = center:ToScreen()
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, cv in ipairs(corners(fr.mn, fr.mx)) do
		local s = LocalToWorld(cv, Angle(0, 0, 0), fr.pos, fr.ang):ToScreen()
		minx, miny, maxx, maxy = math.min(minx, s.x), math.min(miny, s.y), math.max(maxx, s.x), math.max(maxy, s.y)
	end
	render.SuppressEngineLighting(false)
	cam.End3D()
	if self.FitFrames > 0 and maxx > minx then
		self.FitFrames = self.FitFrames - 1
		local ratio = math.max((maxx - minx) / (w * 0.62), (maxy - miny) / (h * 0.42))
		if ratio > 0.05 then cf.dist = cf.dist * math.Clamp(ratio, 0.5, 2) end
	end
	self:Layout(w, h, c.y - y)
	local hover = vgui.GetHoveredPanel()
	for k, a in pairs(self.Anchors) do
		local box = self.Boxes[k]
		if IsValid(box) and box:IsVisible() then
			local bx, by = box:GetPos()
			local bw, bh = box:GetSize()
			local sx = bx + bw / 2
			local sy = (by + bh / 2 < a.y) and (by + bh) or by
			local hot = hover == box
			surface.SetDrawColor(hot and T.Accent or LINE)
			surface.DrawLine(sx, sy, a.x, a.y)
			surface.DrawCircle(a.x, a.y, T.S(5), hot and T.Accent or LINE)
			surface.SetDrawColor(hot and T.Accent or T.White)
			surface.DrawRect(a.x - 1, a.y - 1, 3, 3)
		end
	end
end

vgui.Register("RPInvModView", VIEW, "DPanel")

local function buildSide(t)
	if not IsValid(win) then return end
	local left, right = win.Left, win.Right
	left:Clear()
	local seen, list = {}, {}
	for _, info in ipairs(t.slots or {}) do
		for _, o in ipairs(info.opts or {}) do
			local e = seen[o.item]
			if not e then
				e = { item = o.item, n = o.n, slots = {} }
				seen[o.item] = e
				list[#list + 1] = e
			end
			table.insert(e.slots, info)
		end
	end
	table.sort(list, function(a, b) return a.n < b.n end)
	if #list == 0 then
		local l = T.Label(left, "No fitting attachments in your inventory, pockets or carriers.", "RPInv.Small")
		l:Dock(TOP)
		l:SetWrap(true)
		l:SetTall(T.S(40))
	end
	for _, e in ipairs(list) do
		local def = RPInv.Items[e.item]
		local row = left:Add("DButton")
		row:SetText("")
		row:Dock(TOP)
		row:DockMargin(0, 0, T.S(4), T.S(4))
		row:SetTall(T.S(46))
		row.Paint = function(s, w, h)
			surface.SetDrawColor(T.CellBg)
			surface.DrawRect(0, 0, w, h)
			if def then RPInv.DrawItemBox(def, { amount = 1, rot = 0, meta = {} }, 1, 1, h - 2, h - 2, 255, true) end
			draw.SimpleText(shortText(e.n, "RPInv.Small", w - h - T.S(10)), "RPInv.Small", h + T.S(6), T.S(8), T.White)
			local names = {}
			for _, info in ipairs(e.slots) do names[#names + 1] = string.upper(A.Phrase(info.n) or info.n) end
			draw.SimpleText(shortText(table.concat(names, ", "), "RPInv.Tiny", w - h - T.S(10)), "RPInv.Tiny", h + T.S(6), h - T.S(8), T.Mid, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			surface.SetDrawColor(s:IsHovered() and T.Accent or T.Dim)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end
		row.DoClick = function()
			surface.PlaySound("ui/buttonclick.wav")
			if #e.slots == 1 then
				RPInv.Act({ a = "attach", w = win.Slot, k = e.slots[1].k, item = e.item })
				return
			end
			local m = T.Menu()
			for _, info in ipairs(e.slots) do
				T.MenuOption(m, "INTO " .. string.upper(A.Phrase(info.n) or info.n), function() RPInv.Act({ a = "attach", w = win.Slot, k = info.k, item = e.item }) end)
			end
			m:Open()
		end
	end
	right.Rows = nil
	right.NextStats = 0
end

local function fill(t)
	if not IsValid(win) then return end
	win.Data = t
	if t.err then
		win.Title = "WEAPON MODDING"
		win.Error = t.err
		return
	end
	win.Error = nil
	win.Title = "WEAPON MODDING :: " .. string.upper(t.name or "")
	local wep = slotWeapon(win.Slot)
	win.View.Class = IsValid(wep) and wep:GetClass() or nil
	win.View:SetData(t)
	win.View.FitFrames = 3
	buildSide(t)
end

function RPInv.OpenAttachments(slot)
	if IsValid(win) then win:Close() end
	local W, H = ScrW() - T.S(60), ScrH() - T.S(60)
	win = T.Frame("WEAPON MODDING", W, H)
	win:SetDraggable(false)
	win:Center()
	win.Slot = slot
	win.Think = function(s)
		if not IsValid(RPInv.Screen) then s:Close() end
	end
	local pad = T.S(12)
	local top = T.S(42)
	local leftW, rightW = T.S(250), T.S(300)

	local lhead = vgui.Create("DPanel", win)
	lhead:SetPos(pad, top)
	lhead:SetSize(leftW, T.S(22))
	lhead.Paint = function() draw.SimpleText("YOUR ATTACHMENTS", "RPInv.Small", 0, T.S(11), T.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	local left = vgui.Create("DScrollPanel", win)
	left:SetPos(pad, top + T.S(24))
	left:SetSize(leftW, H - top - T.S(24) - pad)
	T.StyleScroll(left)
	win.Left = left

	local view = vgui.Create("RPInvModView", win)
	view:SetPos(pad * 2 + leftW, top)
	view:SetSize(W - leftW - rightW - pad * 4, H - top - pad)
	view.Slot = slot
	win.View = view

	local right = vgui.Create("DPanel", win)
	right:SetPos(W - rightW - pad, top)
	right:SetSize(rightW, H - top - pad)
	right.NextStats = 0
	right.Paint = function(s, w, h)
		local wep = slotWeapon(slot)
		if RealTime() >= (s.NextStats or 0) then
			s.NextStats = RealTime() + 0.5
			s.Rows = IsValid(wep) and statRows(wep, A.BaseOf(wep)) or {}
		end
		local data = win.Data or {}
		local y = 0
		local rowH = T.S(26)
		local info = {
			{ "WEAPON", data.name or "" },
			{ "BASE", data.base or "" },
		}
		local used, total = 0, 0
		for _, sl in ipairs(data.slots or {}) do
			total = total + 1
			if sl.i and not sl.free then used = used + 1 end
		end
		info[#info + 1] = { "ATTACHMENTS", used .. " / " .. total }
		local all = {}
		for _, r in ipairs(info) do all[#all + 1] = r end
		for _, r in ipairs(s.Rows or {}) do all[#all + 1] = r end
		for _, r in ipairs(all) do
			surface.SetDrawColor(18, 20, 20, 235)
			surface.DrawRect(0, y, w, rowH - 2)
			surface.SetDrawColor(T.Accent.r, T.Accent.g, T.Accent.b, 160)
			surface.DrawRect(0, y, 2, rowH - 2)
			draw.SimpleText(r[1], "RPInv.Small", T.S(10), y + (rowH - 2) / 2, T.Mid, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(shortText(tostring(r[2]), "RPInv.Small", w * 0.55), "RPInv.Small", w - T.S(8), y + (rowH - 2) / 2, T.White, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			y = y + rowH
		end
		if win.Error then
			draw.SimpleText(win.Error, "RPInv.Small", 0, y + T.S(10), T.Red)
		end
		local hy = h - T.S(70)
		for _, l in ipairs({ "DRAG THE WEAPON: ROTATE", "MOUSE WHEEL: ZOOM", "CLICK A SLOT: INSTALL OR REMOVE", "GREEN CORNER: YOU HAVE PARTS FOR IT" }) do
			draw.SimpleText(l, "RPInv.Tiny", 0, hy, T.Dim)
			hy = hy + T.S(16)
		end
	end
	win.Right = right
	request(slot)
end

net.Receive("rpinv_attinfo", function()
	local t = readJSON()
	if IsValid(win) and t.w == win.Slot then fill(t) end
end)

local nextRefresh = 0
hook.Add("RPInv_StoreUpdated", "RPInv_AttachRefresh", function()
	if not IsValid(win) or RealTime() < nextRefresh then return end
	nextRefresh = RealTime() + 0.5
	timer.Simple(0.1, function()
		if IsValid(win) then request(win.Slot) end
	end)
end)

local function refreshModels(wep)
	if not IsValid(wep) then return end
	local own = wep:GetOwner() == LocalPlayer()
	local b = A.BaseOf(wep)
	if b == "arccw" then
		call(wep, wep.RecalcAllBuffs)
		call(wep, wep.SetupModel, true)
		if own then call(wep, wep.SetupModel, false) end
		call(wep, wep.RefreshBGs)
	elseif b == "tacrp" then
		call(wep, wep.InvalidateCache)
		call(wep, wep.SetupModel, true)
		if own then call(wep, wep.SetupModel, false) end
	elseif b == "arc9" then
		call(wep, wep.DoInvalidateCache)
		call(wep, wep.KillModel)
		call(wep, wep.SetupModel, true)
		if own then call(wep, wep.SetupModel, false) end
	elseif b == "tfa" then
		call(wep, wep.BuildAttachmentCache)
		call(wep, wep.ClearStatCache)
		call(wep, wep.RebuildModsRenderOrder)
	end
end

net.Receive("rpinv_attrefresh", function()
	local wep = net.ReadEntity()
	if not IsValid(wep) then return end
	refreshModels(wep)
	timer.Simple(0.3, function() refreshModels(wep) end)
end)

local lastActive
hook.Add("Think", "RPInv_AttachDeployRefresh", function()
	local lp = LocalPlayer()
	if not IsValid(lp) then return end
	local w = lp:GetActiveWeapon()
	if w == lastActive then return end
	lastActive = w
	if IsValid(w) and A.BaseOf(w) then
		timer.Simple(0.15, function()
			if IsValid(w) and IsValid(lp) and lp:GetActiveWeapon() == w then refreshModels(w) end
		end)
	end
end)

hook.Add("PreDrawViewModel", "RPInv_ModHideVM", function()
	for p in pairs(openViews) do
		if not IsValid(p) then
			openViews[p] = nil
		elseif IsValid(p.LastWeapon) and p.LastWeapon.ArcticTacRP then
			return true
		end
	end
end)
