local A = RPInv.Att or {}
RPInv.Att = A

A.BaseNames = { arccw = "ArcCW", tacrp = "TacRP", arc9 = "ARC9", tfa = "TFA" }
A.Editable = { arccw = true, tacrp = true, tfa = true, arc9 = true }

function A.BaseOf(w)
	if not w then return nil end
	if w.ArcCW then return "arccw" end
	if w.ArcticTacRP then return "tacrp" end
	if w.ARC9 then return "arc9" end
	if w.IsTFAWeapon then return "tfa" end
end

local classBase = {}
function A.BaseOfClass(cls)
	if not isstring(cls) or cls == "" then return nil end
	local c = classBase[cls]
	if c ~= nil then return c or nil end
	local stored = weapons.Get(cls)
	if not stored then return nil end
	c = A.BaseOf(stored) or false
	classBase[cls] = c
	return c or nil
end

function A.AttTable(base, att)
	if not isstring(att) then return nil end
	if base == "arccw" then
		return ArcCW and ArcCW.AttachmentTable and ArcCW.AttachmentTable[att]
	elseif base == "tacrp" then
		return TacRP and TacRP.Attachments and TacRP.Attachments[att]
	elseif base == "arc9" then
		if not ARC9 then return nil end
		if isfunction(ARC9.GetAttTable) then
			local ok, t = pcall(ARC9.GetAttTable, att)
			if ok and istable(t) then return t end
		end
		return ARC9.Attachments and ARC9.Attachments[att]
	elseif base == "tfa" then
		return TFA and TFA.Attachments and TFA.Attachments.Atts and TFA.Attachments.Atts[att]
	end
end

local function phrase(s)
	if not isstring(s) then return nil end
	if CLIENT and string.sub(s, 1, 1) == "#" then return language.GetPhrase(string.sub(s, 2)) end
	return s
end
A.Phrase = phrase

function A.AttName(base, att)
	local t = A.AttTable(base, att)
	if not t then return att end
	local n
	if base == "tacrp" and isfunction(TacRP.GetAttName) then
		local ok, r = pcall(TacRP.GetAttName, TacRP, att, true)
		if ok and isstring(r) and r ~= "" then n = r end
	elseif base == "arccw" and isfunction(ArcCW.GetTranslation) then
		local ok, r = pcall(ArcCW.GetTranslation, "name." .. att)
		if ok and isstring(r) and r ~= "" then n = r end
	elseif base == "arc9" and isfunction(ARC9.GetPhraseForAtt) then
		local ok, r = pcall(ARC9.GetPhraseForAtt, ARC9, att, "PrintName")
		if ok and isstring(r) and r ~= "" then n = r end
	elseif base == "tfa" then
		n = t.Name
	end
	n = n or t.PrintName or t.FullName or t.Name or t.CompactName or att
	return tostring(phrase(n) or att)
end

function A.IsFree(base, att)
	local t = A.AttTable(base, att)
	return not t or t.Free == true or t.Hidden == true
end

function A.IsDefault(wep, base, att)
	if base ~= "tfa" or not IsValid(wep) or not istable(wep.Attachments) then return false end
	for _, c in pairs(wep.Attachments) do
		if istable(c) and c.default == att then return true end
	end
	return false
end

function A.SlotTable(wep, k)
	if not IsValid(wep) or not istable(wep.Attachments) or k == nil then return nil end
	if wep.ARC9 then
		if not isfunction(wep.LocateSlotFromAddress) then return nil end
		local ok, s = pcall(wep.LocateSlotFromAddress, wep, tonumber(k) or k)
		return ok and istable(s) and s or nil
	end
	local s = wep.Attachments[k]
	return istable(s) and s or nil
end

function A.ItemId(base, att)
	return "att_" .. base .. "_" .. util.CRC(base .. ":" .. att)
end

function A.Parse(arg)
	local b, a = string.match(tostring(arg or ""), "^(%w+):(.+)$")
	if b and A.BaseNames[b] then return b, a end
end

function A.Exists(arg)
	local b, a = A.Parse(arg)
	return b ~= nil and A.AttTable(b, a) ~= nil
end

local function numSlots(wep)
	local out = {}
	for k, s in pairs(wep.Attachments or {}) do
		if isnumber(k) and istable(s) then out[#out + 1] = k end
	end
	table.sort(out)
	return out
end
A.NumSlots = numSlots

local function arc9Tree(slots, depth)
	if depth > 6 or not istable(slots) then return nil end
	local out, any = {}, false
	for k, s in pairs(slots) do
		if isnumber(k) and istable(s) and isstring(s.Installed) then
			out[tostring(k)] = { i = s.Installed, t = tonumber(s.ToggleNum), s = arc9Tree(s.SubAttachments, depth + 1) }
			any = true
		end
	end
	return any and out or nil
end

local function arc9Flatten(tree, list, depth)
	if not istable(tree) or depth > 6 then return list end
	for _, n in pairs(tree) do
		if istable(n) and isstring(n.i) then
			list[#list + 1] = n.i
			arc9Flatten(n.s, list, depth + 1)
		end
	end
	return list
end

function A.Installed(wep)
	local base = A.BaseOf(wep)
	local out = {}
	if not base or not istable(wep.Attachments) then return out, base end
	if base == "arc9" then
		for _, a in ipairs(arc9Flatten(arc9Tree(wep.Attachments, 0), {}, 0)) do out[#out + 1] = { a = a } end
	elseif base == "tfa" then
		for cat, t in pairs(wep.Attachments) do
			local sel = istable(t) and tonumber(t.sel) or 0
			if sel > 0 and istable(t.atts) and isstring(t.atts[sel]) then out[#out + 1] = { k = cat, a = t.atts[sel] } end
		end
	else
		for _, k in ipairs(numSlots(wep)) do
			local s = wep.Attachments[k]
			if isstring(s.Installed) and not s.Internal then out[#out + 1] = { k = k, a = s.Installed } end
		end
	end
	return out, base
end

function A.Capture(wep)
	if not IsValid(wep) then return nil end
	local base = A.BaseOf(wep)
	if not base or not istable(wep.Attachments) then return nil end
	if base == "arc9" then return { b = base, t = arc9Tree(wep.Attachments, 0) or {} } end
	local s = {}
	for _, e in ipairs((A.Installed(wep))) do s[tostring(e.k)] = e.a end
	return { b = base, s = s }
end

function A.DataList(data)
	local out = {}
	if not istable(data) or not A.BaseNames[data.b] then return out end
	if data.b == "arc9" then return arc9Flatten(data.t, out, 0) end
	for _, a in pairs(istable(data.s) and data.s or {}) do
		if isstring(a) then out[#out + 1] = a end
	end
	table.sort(out)
	return out
end

local function locked()
	return RPInv.Settings and RPInv.Settings.att_items == true
end

local function bypass(ply)
	return IsValid(ply) and ply.RPInvAttOp == true
end

local function guarded(wep)
	if not IsValid(wep) or not wep.RPInvAttLock then return false end
	local t = math.max(wep.RPInvDeployedAt or 0, wep.RPInvAttLockAt or 0)
	return CurTime() < t + 3
end

hook.Add("ArcCW_PlayerCanAttach", "RPInv_Attachments", function(ply, wep)
	if bypass(ply) then return true end
	if locked() or guarded(wep) then return false end
end)

hook.Add("TacRP_CanCustomize", "RPInv_Attachments", function(ply, wep)
	if bypass(ply) then return true end
	if locked() then return false, "Change attachments in the inventory." end
	if guarded(wep) then return false end
end)

hook.Add("TacRP_PlayerAttCount", "RPInv_Attachments", function(ply)
	if bypass(ply) then return 9999 end
end)

hook.Add("TacRP_PlayerGiveAtt", "RPInv_Attachments", function(ply)
	if bypass(ply) then return true end
end)

hook.Add("TacRP_PlayerTakeAtt", "RPInv_Attachments", function(ply)
	if bypass(ply) then return true end
end)

local function tfaGate(wep)
	local ply = IsValid(wep) and wep:GetOwner()
	if bypass(ply) then return true end
	if locked() or guarded(wep) then return false end
end

hook.Add("TFA_PreCanAttach", "RPInv_Attachments", tfaGate)
hook.Add("TFA_PreCanDetach", "RPInv_Attachments", tfaGate)

hook.Add("ARC9_PlayerGetAtts", "RPInv_Attachments", function(ply)
	if bypass(ply) then return 999 end
	if locked() then return 0 end
end)

hook.Add("ARC9_PlayerGiveAtt", "RPInv_Attachments", function(ply)
	if bypass(ply) or locked() then return true end
end)

hook.Add("ARC9_PlayerTakeAtt", "RPInv_Attachments", function(ply)
	if bypass(ply) then return true end
end)

function A.Locked() return locked() end
function A.Guarded(wep) return guarded(wep) end

if CLIENT then
	local hinted = false
	timer.Create("RPInv_AttLockHint", 1, 0, function()
		local lp = LocalPlayer()
		if not IsValid(lp) or not locked() then return end
		local w = lp:GetActiveWeapon()
		local open = false
		if IsValid(w) then
			if isfunction(w.GetCustomize) then
				local ok, v = pcall(w.GetCustomize, w)
				open = ok and v == true
			end
			if not open and ArcCW and w.ArcCW and isfunction(w.GetState) and ArcCW.STATE_CUSTOMIZE then
				open = w:GetState() == ArcCW.STATE_CUSTOMIZE
			end
		end
		if open and not hinted and RPInv.Toast then
			RPInv.Toast("This server keeps attachments as inventory items: open the inventory, right-click the weapon in its slot and choose ATTACHMENTS.", 0)
		end
		hinted = open
	end)
end

if CLIENT then
	local function eig3(a)
		local v = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
		for _ = 1, 32 do
			if a[1][2] ^ 2 + a[1][3] ^ 2 + a[2][3] ^ 2 < 1e-10 then break end
			for p = 1, 2 do
				for q = p + 1, 3 do
					if math.abs(a[p][q]) > 1e-12 then
						local theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
						local t = (theta >= 0 and 1 or -1) / (math.abs(theta) + math.sqrt(theta * theta + 1))
						local c = 1 / math.sqrt(t * t + 1)
						local s = t * c
						for k = 1, 3 do
							local x, y = a[k][p], a[k][q]
							a[k][p], a[k][q] = c * x - s * y, s * x + c * y
						end
						for k = 1, 3 do
							local x, y = a[p][k], a[q][k]
							a[p][k], a[q][k] = c * x - s * y, s * x + c * y
						end
						for k = 1, 3 do
							local x, y = v[k][p], v[k][q]
							v[k][p], v[k][q] = c * x - s * y, s * x + c * y
						end
					end
				end
			end
		end
		local out = {}
		for i = 1, 3 do out[i] = { val = a[i][i], vec = Vector(v[1][i], v[2][i], v[3][i]):GetNormalized() } end
		table.sort(out, function(x, y) return x.val > y.val end)
		return out
	end

	local frames = {}
	function A.MeshFrame(path)
		local c = frames[path]
		if c ~= nil then return c or nil end
		frames[path] = false
		if not isstring(path) or path == "" or not RPInv.ModelExists(path) then return nil end
		local meshes = util.GetModelMeshes(path)
		if not istable(meshes) then return nil end
		local pts = {}
		for _, m in ipairs(meshes) do
			for _, vtx in ipairs(m.triangles or {}) do
				if isvector(vtx.pos) then pts[#pts + 1] = vtx.pos end
			end
		end
		local step = math.max(1, math.floor(#pts / 20000))
		local sample = {}
		for i = 1, #pts, step do sample[#sample + 1] = pts[i] end
		if #sample < 12 then return nil end
		local mean = Vector(0, 0, 0)
		for _, p in ipairs(sample) do mean:Add(p) end
		mean:Div(#sample)
		local a = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
		for _, p in ipairs(sample) do
			local d = { p.x - mean.x, p.y - mean.y, p.z - mean.z }
			for i = 1, 3 do
				for j = 1, 3 do a[i][j] = a[i][j] + d[i] * d[j] end
			end
		end
		local e = eig3(a)
		local L, U = e[1].vec, e[2].vec
		local lmin, lmax = math.huge, -math.huge
		for _, p in ipairs(sample) do
			local l = (p - mean):Dot(L)
			lmin, lmax = math.min(lmin, l), math.max(lmax, l)
		end
		local len = lmax - lmin
		if len <= 0 then return nil end
		local function slice(fromMax)
			local lo, hi, sum, n = math.huge, -math.huge, 0, 0
			for _, p in ipairs(sample) do
				local d = p - mean
				local l = d:Dot(L)
				if (fromMax and l > lmax - len * 0.12) or (not fromMax and l < lmin + len * 0.12) then
					local u = d:Dot(U)
					lo, hi, sum, n = math.min(lo, u), math.max(hi, u), sum + u, n + 1
				end
			end
			return n > 0 and (hi - lo) or math.huge, n > 0 and sum / n or 0
		end
		local hFront, mFront = slice(true)
		local hBack, mBack = slice(false)
		local muzzleMean = mFront
		if hBack < hFront then
			L = -L
			muzzleMean = mBack
		end
		local ulo, uhi = math.huge, -math.huge
		for _, p in ipairs(sample) do
			local u = (p - mean):Dot(U)
			ulo, uhi = math.min(ulo, u), math.max(uhi, u)
		end
		if muzzleMean < (ulo + uhi) / 2 then U = -U end
		local V = L:Cross(U):GetNormalized()
		c = { L = L, U = U, V = V, center = mean }
		frames[path] = c
		return c
	end

	function A.OrientFor(frame, dl, du)
		local dv = dl:Cross(du):GetNormalized()
		local L, U, V = frame.L, frame.U, frame.V
		local fx = dl * L.x + du * U.x + dv * V.x
		local fy = dl * L.y + du * U.y + dv * V.y
		local fz = dl * L.z + du * U.z + dv * V.z
		local m = Matrix()
		m:SetForward(fx)
		m:SetRight(-fy)
		m:SetUp(fz)
		return m:GetAngles()
	end

	local wicons = {}
	function A.WeaponIcon(def)
		local cls = def.use_arg
		local c = wicons[cls]
		if c ~= nil then return c or nil end
		local full = weapons.Get(cls)
		if not full then return nil end
		if not (full.ARC9 and full.MirrorVMWM) then
			wicons[cls] = false
			return nil
		end
		local m = Material("entities/" .. cls .. ".png", "smooth mips")
		if m and not m:IsError() then
			wicons[cls] = m
			return m
		end
		wicons[cls] = false
	end

	local icons = {}
	function A.Icon(def)
		local key = def.use_arg
		local c = icons[key]
		if c then return c end
		local b, a = A.Parse(key)
		local t = b and A.AttTable(b, a)
		local ic = t and (t.Icon or t.IconOverride)
		if isstring(ic) and ic ~= "" then ic = Material(ic, "smooth mips") end
		if type(ic) == "IMaterial" and not ic:IsError() then
			icons[key] = ic
			return ic
		end
	end
end
