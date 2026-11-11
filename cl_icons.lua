local I = RPInv.Icons or {}
RPInv.Icons = I

local RES = 96
local PER_FRAME = 2

I.Cache = I.Cache or {}
I.Queue = {}
I.Serial = I.Serial or 0

local function parseAng(s)
	local p = string.Explode(" ", s or "")
	return tonumber(p[1]) or 0, tonumber(p[2]) or 0, tonumber(p[3]) or 0
end

local function keyFor(def, w, h)
	return string.format("%s|%d|%d|%s|%s|%s|%s|%s", def.model, w, h, def.cam_ang or "", tostring(def.cam_fov or 1), def.cam_off or "", tostring(def.skin or 0), def.bodygroups or "")
end

function I.Get(def, w, h)
	if not def then return end
	w, h = w or def.w or 1, h or def.h or 1
	local key = keyFor(def, w, h)
	local e = I.Cache[key]
	if not e then
		I.Serial = I.Serial + 1
		local pw, ph = w * RES, h * RES
		local name = string.format("rpinv_ic_%d_%dx%d", I.Serial, pw, ph)
		local rt = GetRenderTargetEx(name, pw, ph, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SHARED, bit.bor(4, 8, 256, 512), 0, IMAGE_FORMAT_RGBA8888)
		local mat = CreateMaterial(name .. "_m", "UnlitGeneric", {
			["$basetexture"] = rt:GetName(),
			["$translucent"] = "1",
			["$vertexcolor"] = "1",
			["$vertexalpha"] = "1",
		})
		e = { key = key, rt = rt, mat = mat, pw = pw, ph = ph, def = table.Copy(def), ready = false }
		I.Cache[key] = e
		I.Queue[#I.Queue + 1] = e
	end
	return e.ready and e.mat or nil
end

I.Previews = I.Previews or {}

function I.GetPreview(def, w, h)
	if not def then return end
	w, h = w or def.w or 1, h or def.h or 1
	local slot = w .. "x" .. h
	local e = I.Previews[slot]
	if not e then
		local pw, ph = w * RES, h * RES
		local name = "rpinv_icprev_" .. slot
		local rt = GetRenderTargetEx(name, pw, ph, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SHARED, bit.bor(4, 8, 256, 512), 0, IMAGE_FORMAT_RGBA8888)
		local mat = CreateMaterial(name .. "_m", "UnlitGeneric", {
			["$basetexture"] = rt:GetName(),
			["$translucent"] = "1",
			["$vertexcolor"] = "1",
			["$vertexalpha"] = "1",
		})
		e = { rt = rt, mat = mat, pw = pw, ph = ph, ready = false }
		I.Previews[slot] = e
	end
	local sig = keyFor(def, w, h)
	if e.sig ~= sig then
		e.sig = sig
		e.def = table.Copy(def)
		if not e.queued then
			e.queued = true
			I.Queue[#I.Queue + 1] = e
		end
	end
	return e.ready and e.mat or nil
end

function I.Invalidate()
	for _, e in pairs(I.Cache) do
		if not e.queued then
			e.queued = true
			I.Queue[#I.Queue + 1] = e
		end
	end
end

local csent

local function extents(ent, mins, maxs, right, up, fwd)
	local minU, maxU, minV, maxV, minD, maxD = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for i = 0, 7 do
		local c = Vector(bit.band(i, 1) > 0 and maxs.x or mins.x, bit.band(i, 2) > 0 and maxs.y or mins.y, bit.band(i, 4) > 0 and maxs.z or mins.z)
		local wpos = ent:LocalToWorld(c)
		local u, v, d = wpos:Dot(right), wpos:Dot(up), wpos:Dot(fwd)
		minU, maxU = math.min(minU, u), math.max(maxU, u)
		minV, maxV = math.min(minV, v), math.max(maxV, v)
		minD, maxD = math.min(minD, d), math.max(maxD, d)
	end
	return minU, maxU, minV, maxV, minD, maxD
end

local camAng = Angle(0, 90, 0)

local function renderIcon(e)
	local def = e.def
	if not IsValid(csent) then
		csent = ClientsideModel("models/props_junk/PopCan01a.mdl", RENDERGROUP_OTHER)
		if not IsValid(csent) then return false end
		csent:SetNoDraw(true)
	end
	csent:SetModel(def.model)
	csent:SetPos(vector_origin)
	csent:SetSubMaterial()
	RPInv.ApplyLook(csent, def)
	if RPInv.ApplyModelFix(csent) then RPInv.ModelFixHook(csent) end
	csent:InvalidateBoneCache()

	local right, up, fwd = camAng:Right(), camAng:Up(), camAng:Forward()
	local p, y, r = parseAng(def.cam_ang)
	local mins, maxs = csent:GetModelRenderBounds()
	if not mins or mins == maxs then mins, maxs = csent:GetModelBounds() end
	local fb = RPInv.ModelFixBounds(def.model)
	if fb then mins, maxs = fb.mins, fb.maxs end
	if not mins then return false end
	local aspect = e.pw / e.ph

	local ang = Angle(p, y, r)
	if p == 0 and y == 0 and r == 0 then
		local best, bestErr
		for _, cand in ipairs({ Angle(0, 0, 0), Angle(0, 90, 0), Angle(90, 0, 0), Angle(0, 0, 90) }) do
			csent:SetAngles(cand)
			local u0, u1, v0, v1 = extents(csent, mins, maxs, right, up, fwd)
			local a = math.max(u1 - u0, 0.01) / math.max(v1 - v0, 0.01)
			local err = math.abs(math.log(a / aspect))
			if not bestErr or err < bestErr - 0.05 then best, bestErr = cand, err end
		end
		ang = best
	end
	csent:SetAngles(ang)
	csent:SetupBones()

	local u0, u1, v0, v1, d0, d1 = extents(csent, mins, maxs, right, up, fwd)
	local hw, hh = (u1 - u0) / 2, (v1 - v0) / 2
	if hw / math.max(hh, 0.01) < aspect then hw = hh * aspect else hh = hw / aspect end
	local zoom = tonumber(def.cam_fov) or 1
	if zoom <= 0 then zoom = 1 end
	local pad = 1.1 / zoom
	hw, hh = hw * pad, hh * pad
	local cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
	local ox, oy = string.match(def.cam_off or "", "^(%-?[%d%.]+) (%-?[%d%.]+)$")
	cu = cu - (tonumber(ox) or 0) * hw
	cv = cv - (tonumber(oy) or 0) * hh
	local origin = right * cu + up * cv + fwd * (d0 - 64)

	render.PushRenderTarget(e.rt)
	render.OverrideAlphaWriteEnable(true, true)
	render.Clear(0, 0, 0, 0, true, true)

	render.SetStencilEnable(true)
	render.SetStencilWriteMask(255)
	render.SetStencilTestMask(255)
	render.SetStencilReferenceValue(1)
	render.ClearStencil()
	render.SetStencilCompareFunction(STENCIL_ALWAYS)
	render.SetStencilPassOperation(STENCIL_REPLACE)
	render.SetStencilFailOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_KEEP)

	cam.Start({
		type = "3D", x = 0, y = 0, w = e.pw, h = e.ph, origin = origin, angles = camAng,
		ortho = { left = -hw, right = hw, top = -hh, bottom = hh }, znear = 1, zfar = (d1 - d0) + 256,
	})
		render.SuppressEngineLighting(true)
		render.ResetModelLighting(1.05, 1.05, 1.02)
		render.SetModelLighting(BOX_TOP, 1.7, 1.7, 1.65)
		render.SetModelLighting(BOX_LEFT, 1.35, 1.35, 1.3)
		render.SetModelLighting(BOX_BOTTOM, 0.55, 0.55, 0.53)
		render.SetColorModulation(1, 1, 1)
		render.SetBlend(1)
		csent:DrawModel()
		render.SuppressEngineLighting(false)
	cam.End()

	render.OverrideColorWriteEnable(true, false)
	render.SetStencilCompareFunction(STENCIL_EQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)
	render.ClearBuffersObeyStencil(0, 0, 0, 255, false)
	render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
	render.ClearBuffersObeyStencil(0, 0, 0, 0, false)
	render.OverrideColorWriteEnable(false)
	render.SetStencilEnable(false)

	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()
	return true
end

hook.Add("PostRender", "RPInv_IconCache", function()
	local n = 0
	while n < PER_FRAME and #I.Queue > 0 do
		local e = table.remove(I.Queue, 1)
		e.queued = nil
		local ok, res = pcall(renderIcon, e)
		e.ready = true
		if not ok then ErrorNoHalt("[RPInv] icon render failed for " .. tostring(e.def.model) .. ": " .. tostring(res) .. "\n") end
		n = n + 1
	end
end)

function I.Draw(def, x, y, w, h, rot, alpha)
	local cw, ch = def.w or 1, def.h or 1
	local mat = def.RPInvPreview and I.GetPreview(def, cw, ch) or (not def.RPInvPreview and I.Get(def, cw, ch))
	if not mat then return false end
	surface.SetMaterial(mat)
	surface.SetDrawColor(255, 255, 255, alpha or 255)
	if rot == 1 then
		surface.DrawTexturedRectRotated(x + w / 2, y + h / 2, h, w, 90)
	else
		surface.DrawTexturedRect(x, y, w, h)
	end
	return true
end
