local T = RPInv.Theme

RPInv.Frisk = RPInv.Frisk or {}
local F = RPInv.Frisk
local win

local function sendClose()
	net.Start("rpinv_frisk")
	net.WriteUInt(2, 2)
	net.SendToServer()
end

local function closeWindow(notify)
	if IsValid(win) then
		win.Silent = not notify
		win:Remove()
	end
	win = nil
end

local function slotName(key)
	local s = RPInv.EquipSlotByKey[key]
	return s and s.name or string.upper(key)
end

local function buildBody()
	if not IsValid(win) then return end
	local body = win.Body
	body:Clear()
	local pad = T.S(8)
	local leftW = T.S(250)
	local availW = body:GetWide() - leftW - pad - T.S(22)
	local zoom = F.Zoom or 1
	local function cellFor(cols)
		local fit = math.floor(availW / math.max(1, cols))
		local base = math.Clamp(fit, 26, math.floor(T.CellSize() * 1.2))
		return math.Clamp(math.floor(base * zoom), 16, math.max(math.min(fit, 110), 26))
	end

	local left = vgui.Create("DScrollPanel", body)
	left:Dock(LEFT)
	left:SetWide(leftW)
	left:DockMargin(0, 0, pad, 0)
	T.StyleScroll(left)

	local any = false
	for _, s in ipairs(RPInv.EquipSlots) do
		for _, e in ipairs((F.Slots or {})[s.key] or {}) do
			local def = RPInv.Items[e.item]
			if def then
				any = true
				local row = left:Add("DPanel")
				row:Dock(TOP)
				row:SetTall(T.S(54))
				row:DockMargin(0, 0, T.S(6), T.S(4))
				row.Paint = function(_, w, h)
					surface.SetDrawColor(T.CellBg)
					surface.DrawRect(0, 0, w, h)
					RPInv.DrawItemBox(def, { amount = 1, rot = 0, dur = e.dur, meta = e.meta or {} }, 1, 1, h - 2, h - 2, 255, true)
					draw.SimpleText(slotName(s.key), "RPInv.Tiny", h + T.S(6), T.S(12), T.Mid)
					draw.SimpleText(def.name, "RPInv.Small", h + T.S(6), T.S(28), T.White)
					surface.SetDrawColor(T.Dim)
					surface.DrawOutlinedRect(0, 0, w, h, 1)
				end
				if F.AllowEquipment then
					local take = T.Button(row, "TAKE", T.S(56), function() RPInv.Act({ a = "frisk_take", key = e.key }) end)
					take:SetFont("RPInv.Small")
					take:Dock(RIGHT)
					take:DockMargin(0, T.S(14), T.S(6), T.S(14))
				end
			end
		end
	end
	if not any then
		local l = T.Label(left, "NO EQUIPMENT", "RPInv.Small")
		l:Dock(TOP)
	end

	local right = vgui.Create("DScrollPanel", body)
	right:Dock(FILL)
	T.StyleScroll(right)
	local st = RPInv.Stores["t:p"]
	local mainCell = cellFor(math.max(st and st.w or 10, 4))
	local function section(title, sid, gw, gh)
		local sec = right:Add("DPanel")
		sec:Dock(TOP)
		sec:DockMargin(0, 0, T.S(8), T.S(10))
		local c2 = math.min(mainCell, cellFor(gw))
		sec:SetTall(T.S(20) + gh * c2 + 1)
		sec:SetWide(gw * c2 + 2)
		sec.Paint = function() draw.SimpleText(title, "RPInv.Small", 0, T.S(9), T.Mid, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		local g = vgui.Create("RPInvGrid", sec)
		g:SetCell(c2)
		g:SetStore(sid)
		g:SetPos(0, T.S(20))
		g.OnZoom = function(_, delta) RPInv.FriskZoom(delta > 0 and 0.1 or -0.1) end
	end
	if not st or (st.w > 0 and st.h > 0) then section("INVENTORY", "t:p", st and st.w or 10, st and st.h or 6) end
	if F.Pockets and (F.PocketsW or 0) > 0 and (F.PocketsH or 0) > 0 then
		section("POCKETS", "t:k:" .. F.Pockets, F.PocketsW, F.PocketsH)
	end
	for _, s in ipairs(RPInv.EquipSlots) do
		for _, e in ipairs((F.Slots or {})[s.key] or {}) do
			local def = RPInv.Items[e.item]
			if e.carrier and def and (def.grid_w or 0) > 0 then
				section(slotName(s.key) .. "  -  " .. string.upper(def.name), "t:k:" .. e.key, def.grid_w, def.grid_h)
			end
		end
	end
end

function RPInv.FriskZoom(step)
	F.Zoom = math.Clamp((F.Zoom or 1) + step, 0.5, 2)
	buildBody()
end

local function openWindow(name)
	local scr = RPInv.OpenScreen()
	if not IsValid(scr) then return end
	closeWindow(false)
	local w, h = math.min(ScrW() - T.S(60), T.S(1500)), math.min(ScrH() - T.S(90), T.S(980))
	win = vgui.Create("DPanel", scr)
	win:SetSize(w, h)
	win:SetPos((ScrW() - w) / 2, (ScrH() - h) / 2 + T.S(20))
	win:SetAlpha(0)
	win:AlphaTo(255, 0.12)
	local headH = T.S(34)
	win.Paint = function(_, pw, ph)
		surface.SetDrawColor(T.WinBg)
		surface.DrawRect(0, 0, pw, ph)
		surface.SetDrawColor(T.HeadBg)
		surface.DrawRect(0, 0, pw, headH)
		surface.SetDrawColor(T.Red)
		surface.DrawRect(0, headH - 1, pw, 1)
		draw.SimpleText("SEARCH: " .. string.upper(name), "RPInv.Tab", T.S(12), headH / 2, T.White, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("DRAG ITEMS INTO YOUR INVENTORY   SHIFT+CLICK: TAKE   CTRL+WHEEL: ZOOM", "RPInv.Tiny", pw - T.S(140), headH / 2, T.Dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		draw.SimpleText(math.Round((F.Zoom or 1) * 100) .. "%", "RPInv.Small", pw - T.S(84), headH / 2, T.Mid, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(T.Dim)
		surface.DrawOutlinedRect(0, 0, pw, ph, 1)
		surface.SetDrawColor(T.Red)
		T.Corners(0, 0, pw, ph, T.S(10), 2)
	end
	local close = T.CloseButton(win, function() closeWindow(true) end)
	close:SetSize(T.S(22), T.S(22))
	close:SetPos(w - close:GetWide() - T.S(6), (headH - close:GetTall()) / 2)
	local zin = T.Button(win, "+", T.S(22), function() RPInv.FriskZoom(0.1) end)
	zin:SetTall(T.S(22))
	zin:SetPos(w - T.S(60), (headH - T.S(22)) / 2)
	local zout = T.Button(win, "-", T.S(22), function() RPInv.FriskZoom(-0.1) end)
	zout:SetTall(T.S(22))
	zout:SetPos(w - T.S(130), (headH - T.S(22)) / 2)
	win.Body = vgui.Create("DPanel", win)
	win.Body:SetPos(T.S(8), headH + T.S(8))
	win.Body:SetSize(w - T.S(16), h - headH - T.S(16))
	win.Body.Paint = nil
	win.OnMousePressed = function(s, code)
		if code ~= MOUSE_LEFT then return end
		local mx, my = gui.MousePos()
		local x, y = s:GetPos()
		s.Grab = { mx - x, my - y }
	end
	win.Think = function(s)
		local down = input.IsMouseDown(MOUSE_LEFT)
		if down and not s.WasDown and (s:IsHovered() or s:IsChildHovered()) then s:MoveToFront() end
		s.WasDown = down
		if s.Grab then
			if not down then s.Grab = nil return end
			local mx, my = gui.MousePos()
			s:SetPos(math.Clamp(mx - s.Grab[1], 0, ScrW() - s:GetWide()), math.Clamp(my - s.Grab[2], 0, ScrH() - T.S(40)))
		end
	end
	win.OnRemove = function(s)
		if not s.Silent then sendClose() end
		RPInv.Stores["t:p"] = nil
		for sid in pairs(RPInv.Stores) do
			if string.sub(sid, 1, 4) == "t:k:" then RPInv.Stores[sid] = nil end
		end
	end
	surface.PlaySound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav")
	buildBody()
end

net.Receive("rpinv_frisk_state", function()
	local t = RPInv.ReadJSON()
	local phase = t.phase
	if phase == "progress" then
		F.Progress = { text = "SEARCHING " .. string.upper(t.name or ""), start = RealTime(), time = tonumber(t.time) or 4 }
	elseif phase == "progress_target" then
		F.Progress = { text = string.upper(t.name or "") .. " IS SEARCHING YOU", start = RealTime(), time = tonumber(t.time) or 4, target = true }
	elseif phase == "open" then
		F.Progress = nil
		F.Name = t.name
		openWindow(t.name or "")
	elseif phase == "equip" then
		F.Slots = istable(t.slots) and t.slots or {}
		F.AllowEquipment = t.equipment == true
		F.Pockets = isstring(t.pockets) and t.pockets or nil
		F.PocketsW, F.PocketsH = tonumber(t.pocketsW) or 0, tonumber(t.pocketsH) or 0
		local sig = util.TableToJSON(F.Slots) .. tostring(F.Pockets) .. F.PocketsW .. "x" .. F.PocketsH
		if sig ~= F.Sig then
			F.Sig = sig
			buildBody()
		end
	elseif phase == "progress_end" then
		F.Progress = nil
	elseif phase == "closed" or phase == "closed_target" then
		F.Progress = nil
		if phase == "closed" then
			closeWindow(false)
			F.Slots, F.Sig = nil, nil
		end
	end
end)

hook.Add("RPInv_StoreUpdated", "RPInv_FriskStore", function(sid)
	if sid == "t:p" and IsValid(win) and not win.HasGrid then
		win.HasGrid = true
		buildBody()
	end
end)

hook.Add("HUDPaint", "RPInv_FriskHUD", function()
	local lp = LocalPlayer()
	if not IsValid(lp) then return end
	local cx = ScrW() / 2
	local p = F.Progress
	if p then
		local frac = math.Clamp((RealTime() - p.start) / p.time, 0, 1)
		local w, h = T.S(360), T.S(10)
		local y = ScrH() * 0.62
		draw.SimpleText(p.text, "RPInv.Text", cx, y - T.S(14), p.target and T.Red or T.White, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(10, 11, 10, 220)
		surface.DrawRect(cx - w / 2, y, w, h)
		surface.SetDrawColor(p.target and T.Red or T.Accent)
		surface.DrawRect(cx - w / 2, y, w * frac, h)
		surface.SetDrawColor(T.Dim)
		surface.DrawOutlinedRect(cx - w / 2, y, w, h, 1)
		if not p.target then
			draw.SimpleText("KEEP HOLDING E", "RPInv.Tiny", cx, y + h + T.S(10), T.Mid, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	if lp:GetNW2Bool("RPInvSurrender", false) then
		draw.SimpleText("HANDS UP", "RPInv.Title", cx, ScrH() - T.S(120), T.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText("RELEASE E TO STOP SURRENDERING", "RPInv.Small", cx, ScrH() - T.S(96), T.Mid, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	if IsValid(RPInv.Screen) or p then return end
	local tr = lp:GetEyeTrace()
	local e = tr.Entity
	if IsValid(e) and e:IsPlayer() and e:Alive() and tr.HitPos:DistToSqr(lp:GetShootPos()) < 110 * 110 then
		local up = e:GetNW2Bool("RPInvSurrender", false)
		local mode = RPInv.Settings.search_mode
		if up or mode == "anyone" then
			local y = ScrH() / 2 + T.S(44)
			draw.SimpleText(string.upper(e:Nick()), "RPInv.Text", cx, y, T.White, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText("[HOLD E] SEARCH", "RPInv.Small", cx, y + T.S(20), T.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end)

local POSE = {
	["ValveBiped.Bip01_L_Forearm"] = Angle(25, -65, 25),
	["ValveBiped.Bip01_R_Forearm"] = Angle(-25, -65, -25),
	["ValveBiped.Bip01_L_UpperArm"] = Angle(-70, -180, 70),
	["ValveBiped.Bip01_R_UpperArm"] = Angle(70, -180, -70),
}
local zero = Angle(0, 0, 0)

local HAND = "ValveBiped.Bip01_R_Hand"
local HOLSTER = {
	[1] = {
		time = 1.5, stow = 0.6, slerp = 0.85,
		pose = {
			["ValveBiped.Bip01_R_UpperArm"] = Angle(50, -210, -80),
			["ValveBiped.Bip01_R_Forearm"] = Angle(-32, -115, -15),
		},
	},
	[2] = {
		time = 1.0, stow = 0.55,
		pose = {
			["ValveBiped.Bip01_R_UpperArm"] = Angle(30, 25, 15),
			["ValveBiped.Bip01_R_Forearm"] = Angle(-25, -45, 0),
			["ValveBiped.Bip01_R_Hand"] = Angle(0, -20, 0),
		},
	},
}

local function smooth(x)
	x = math.Clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local axisCache = {}
local function axisAngle(ang)
	local key = tostring(ang)
	local c = axisCache[key]
	if c then return c[1], c[2] end
	local f, l, u = ang:Forward(), -ang:Right(), ang:Up()
	local m11, m21, m31 = f.x, f.y, f.z
	local m12, m22, m32 = l.x, l.y, l.z
	local m13, m23, m33 = u.x, u.y, u.z
	local th = math.acos(math.Clamp((m11 + m22 + m33 - 1) / 2, -1, 1))
	local axis
	if th < 1e-4 then
		axis = Vector(0, 0, 1)
	elseif math.sin(th) > 1e-3 then
		local s = 2 * math.sin(th)
		axis = Vector((m32 - m23) / s, (m13 - m31) / s, (m21 - m12) / s)
	else
		local x = math.sqrt(math.max(0, (m11 + 1) / 2))
		local y = math.sqrt(math.max(0, (m22 + 1) / 2))
		local z = math.sqrt(math.max(0, (m33 + 1) / 2))
		if m12 + m21 < 0 then y = -y end
		if m13 + m31 < 0 then z = -z end
		axis = Vector(x, y, z)
	end
	axis:Normalize()
	local deg = math.deg(th)
	axisCache[key] = { axis, deg }
	return axis, deg
end

local function partial(ang, w)
	local axis, deg = axisAngle(ang)
	local a = Angle(0, 0, 0)
	a:RotateAroundAxis(axis, deg * w)
	return a
end

local function removeProp(ply)
	if IsValid(ply.RPInvHolsterProp) then ply.RPInvHolsterProp:Remove() end
	ply.RPInvHolsterProp = nil
end

local function holsterProp(ply, mdl)
	local p = ply.RPInvHolsterProp
	if IsValid(p) and p:GetModel() == mdl then return p end
	removeProp(ply)
	if not isstring(mdl) or mdl == "" or not RPInv.ModelExists(mdl) then return nil end
	p = ClientsideModel(mdl)
	if not IsValid(p) then return nil end
	p:SetPos(Vector(0, 0, 0))
	p:SetAngles(Angle(0, 0, 0))
	p:SetupBones()
	local bi = p:LookupBone(HAND)
	local b = bi and p:GetBoneMatrix(bi)
	if b then
		p.RPInvGrip = b:GetTranslation()
		p.RPInvHeld = b:GetInverseTR()
	else
		p.RPInvGrip = p:OBBCenter()
	end
	ply.RPInvHolsterProp = p
	return p
end

local bindCache = {}
local function bind0(mdl)
	local c = bindCache[mdl]
	if c ~= nil then return c or nil end
	bindCache[mdl] = false
	local e = ClientsideModel(mdl)
	if not IsValid(e) then return nil end
	e:SetNoDraw(true)
	e:SetPos(Vector(0, 0, 0))
	e:SetAngles(Angle(0, 0, 0))
	e:SetupBones()
	local m = e:GetBoneMatrix(0)
	e:Remove()
	if m then bindCache[mdl] = m end
	return m
end

local function captureHeld(ply, wep)
	local id = ply:LookupBone(HAND)
	local hm = id and ply:GetBoneMatrix(id)
	if not hm then return end
	local ent, merged = wep, true
	if wep.ArcCW and IsValid(wep.WMModel) then
		ent, merged = wep.WMModel, false
	elseif wep.ARC9 and istable(wep.WModel) and IsValid(wep.WModel[1]) then
		ent, merged = wep.WModel[1], false
	end
	local mdl = ent:GetModel()
	if not isstring(mdl) or mdl == "" then return end
	local m
	if merged then
		local b0 = ent:GetBoneMatrix(0)
		local bind = bind0(mdl)
		if not b0 or not bind then return end
		m = b0 * bind:GetInverseTR()
	else
		m = Matrix()
		m:SetTranslation(ent:GetPos())
		m:SetAngles(ent:GetAngles())
	end
	ply.RPInvHeldRel = hm:GetInverseTR() * m
	ply.RPInvHeldModel = mdl
end

local function placeProp(ply, p, kind, w)
	local id = ply:LookupBone(HAND)
	local hm = id and ply:GetBoneMatrix(id)
	if not hm then return end
	local rel = ply.RPInvHeldRel
	local held = rel and (hm * rel) or (p.RPInvHeld and (hm * p.RPInvHeld) or hm)
	local ang = held:GetAngles()
	local frame = RPInv.Att.MeshFrame(p:GetModel())
	if frame then
		local pa = Angle(0, ply:EyeAngles().y, 0)
		local fwd, right, up = pa:Forward(), pa:Right(), pa:Up()
		local dl, du
		if kind == 1 then
			dl = (up * 0.85 + right * 0.3 - fwd * 0.1):GetNormalized()
			du = dl:Cross(fwd):GetNormalized()
		else
			dl = (up * -0.95 + fwd * 0.2):GetNormalized()
			du = (fwd - dl * fwd:Dot(dl)):GetNormalized()
		end
		ang = LerpAngle(w, ang, RPInv.Att.OrientFor(frame, dl, du))
	end
	local grip = rel and rel:GetInverseTR():GetTranslation() or p.RPInvGrip or Vector(0, 0, 0)
	local pos = hm:GetTranslation() - LocalToWorld(grip, Angle(0, 0, 0), Vector(0, 0, 0), ang)
	p:SetPos(pos)
	p:SetAngles(ang)
end

local function resetHolsterBones(ply)
	for _, spec in pairs(HOLSTER) do
		for bone in pairs(spec.pose) do
			local id = ply:LookupBone(bone)
			if id then ply:ManipulateBoneAngles(id, Angle(0, 0, 0)) end
		end
	end
end

hook.Add("EntityRemoved", "RPInv_HolsterProp", function(ent)
	if ent.RPInvHolsterProp then removeProp(ent) end
end)

hook.Add("Think", "RPInv_HolsterAnim", function()
	local lp = LocalPlayer()
	for _, ply in ipairs(player.GetAll()) do
		local kind = ply:Alive() and ply:GetNW2Int("RPInvHolster", 0) or 0
		local spec = HOLSTER[kind]
		if spec then
			local at = ply:GetNW2Float("RPInvHolsterAt", 0)
			if ply.RPInvHolsterSeen ~= at then
				ply.RPInvHolsterSeen = at
				ply.RPInvHeldRel, ply.RPInvHeldModel = nil, nil
				removeProp(ply)
			end
			local t = math.Clamp((CurTime() - at) / spec.time, 0, 1)
			local aw = ply:GetActiveWeapon()
			local stillHeld = IsValid(aw) and aw:GetClass() == ply:GetNW2String("RPInvHolsterClass", "")
			local w = t < spec.stow and smooth(t / spec.stow) or smooth(1 - (t - spec.stow) / (1 - spec.stow))
			if stillHeld then w = 0 end
			for bone, ang in pairs(spec.pose) do
				local id = ply:LookupBone(bone)
				if id then ply:ManipulateBoneAngles(id, spec.slerp and partial(ang, w * spec.slerp) or ang * w) end
			end
			ply.RPInvHolsterBones = true
			if stillHeld then
				captureHeld(ply, aw)
				removeProp(ply)
			elseif t < spec.stow then
				local p = holsterProp(ply, ply.RPInvHeldModel or ply:GetNW2String("RPInvHolsterModel", ""))
				if IsValid(p) then
					p:SetNoDraw(ply == lp and not lp:ShouldDrawLocalPlayer())
					placeProp(ply, p, kind, smooth(t / spec.stow))
				end
			else
				removeProp(ply)
			end
		elseif ply.RPInvHolsterBones then
			ply.RPInvHolsterBones = nil
			resetHolsterBones(ply)
			removeProp(ply)
		end
	end
end)

hook.Add("Think", "RPInv_HandsUpPose", function()
	local dt = FrameTime()
	for _, ply in ipairs(player.GetAll()) do
		local want = (ply:Alive() and ply:GetNW2Bool("RPInvSurrender", false) and ply:GetNW2Int("RPInvHolster", 0) == 0) and 1 or 0
		local cur = ply.RPInvPose or 0
		if cur > 0 or want > 0 then
			cur = math.Approach(cur, want, dt * 4)
			ply.RPInvPose = cur
			local ease = cur * cur * (3 - 2 * cur)
			for bone, ang in pairs(POSE) do
				local id = ply:LookupBone(bone)
				if id then ply:ManipulateBoneAngles(id, cur > 0 and ang * ease or zero) end
			end
		end
	end
end)

hook.Add("Think", "RPInv_SearchGesture", function()
	local now = RealTime()
	for _, ply in ipairs(player.GetAll()) do
		local on = ply:Alive() and ply:GetNW2Bool("RPInvSearching", false)
		if on then
			if (ply.RPInvGestureNext or 0) <= now then
				ply.RPInvGestureNext = now + 1.3
				ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_PLACE, true)
			end
			ply.RPInvGestureOn = true
		elseif ply.RPInvGestureOn then
			ply.RPInvGestureOn = nil
			ply.RPInvGestureNext = nil
			ply:AnimResetGestureSlot(GESTURE_SLOT_CUSTOM)
		end
	end
end)

local function clearCorpseModels(rag)
	if istable(rag.EZarmorModels) then
		for _, m in pairs(rag.EZarmorModels) do
			if IsValid(m) then m:Remove() end
		end
	end
	rag.EZarmorModels = nil
end

local function drawCorpse(self, flags)
	self:DrawModel(flags)
	if self.EZarmor and RPInv.JModAvailable() and isfunction(JMod.ArmorPlayerModelDraw) then
		pcall(JMod.ArmorPlayerModelDraw, self, true)
	end
end

local nextScan = 0
hook.Add("Think", "RPInv_CorpseArmor", function()
	local now = RealTime()
	if now < nextScan then return end
	nextScan = now + 0.25
	for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
		local s = rag:GetNW2String("RPInvCorpseArmor", "")
		if s ~= (rag.RPInvArmorSig or "") then
			rag.RPInvArmorSig = s
			clearCorpseModels(rag)
			local list = util.JSONToTable(s) or {}
			if #list > 0 then
				local items = {}
				for i, a in ipairs(list) do
					local c = a.c or { 255, 255, 255 }
					items["rpinv" .. i] = { name = a.n, col = { r = c[1] or 255, g = c[2] or 255, b = c[3] or 255 }, tgl = false }
				end
				rag.EZarmor = { items = items }
				rag.RenderOverride = drawCorpse
				if not rag.RPInvCleanup then
					rag.RPInvCleanup = true
					rag:CallOnRemove("RPInvCorpseArmor", clearCorpseModels)
				end
			else
				rag.EZarmor = nil
				rag.RenderOverride = nil
			end
		end
	end
end)

local CAM_MIN, CAM_MAX = Vector(-4, -4, -4), Vector(4, 4, 4)

hook.Add("CalcView", "RPInv_DeathCam", function(ply, pos, ang, fov)
	if ply:Alive() then return end
	local body = ply:GetNW2Entity("RPInvBody")
	if not IsValid(body) then return end
	local bone = body:LookupBone("ValveBiped.Bip01_Spine2") or body:LookupBone("ValveBiped.Bip01_Head1")
	local center = bone and body:GetBonePosition(bone) or body:WorldSpaceCenter()
	local tr = util.TraceHull({
		start = center, endpos = center - ang:Forward() * 110 + Vector(0, 0, 12),
		mins = CAM_MIN, maxs = CAM_MAX, filter = { body, ply }, mask = MASK_SOLID_BRUSHONLY,
	})
	return { origin = tr.HitPos, angles = ang, fov = fov, drawviewer = false }
end)

net.Receive("rpinv_vmreset", function()
	RPInv.ResetViewModel(LocalPlayer())
end)

local dropCvar = CreateClientConVar("rpinv_dropkey", "g", true, false, "Hold this key to drop the weapon in your hands (none = off, bind +rpinv_drop instead)")
CreateClientConVar("rpinv_hold_e", "1", true, true, "1 = holding E raises the hands / searches / loots bodies, 0 = only the +rpinv_hold bind does")
local dropSince, dropSent = nil, false
local dropCmd = false

concommand.Add("+rpinv_drop", function() dropCmd = true end, nil, "Hold to drop the weapon in your hands")
concommand.Add("-rpinv_drop", function() dropCmd = false end)

hook.Add("Think", "RPInv_DropKey", function()
	local code = input.GetKeyCode(dropCvar:GetString())
	local keyDown = code and code > 0 and input.IsKeyDown(code)
	local lp = LocalPlayer()
	local focus = vgui.GetKeyboardFocus()
	local blocked = not IsValid(lp) or lp:IsTyping() or gui.IsGameUIVisible() or gui.IsConsoleVisible()
		or IsValid(RPInv.Screen) or (IsValid(focus) and focus:GetClassName() == "TextEntry")
	if blocked or not (keyDown or dropCmd) then
		dropSince, dropSent = nil, false
		return
	end
	dropSince = dropSince or RealTime()
	if not dropSent and RealTime() - dropSince >= 0.3 then
		dropSent = true
		net.Start("rpinv_dropwep")
		net.SendToServer()
	end
end)
