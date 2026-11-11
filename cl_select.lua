local T = RPInv.Theme

local TOOLS = { "weapon_physgun", "gmod_tool", "gmod_camera" }
local SLOT_KEYS = { [1] = "primary", [2] = "secondary", [3] = "utility" }
local QUICK_LABELS = { "6", "7", "8", "9", "0" }
local DOUBLE_TIME = 0.45

local hint, hintT = nil, 0
local misc, miscT = nil, 0
local quickPress = { i = nil, t = 0 }

local function showHint(text)
	hint, hintT = text, RealTime()
	misc = nil
end

local function slotWeapon(slot)
	local list = RPInv.Equipped and RPInv.Equipped[slot]
	local e = list and list[1]
	local def = e and RPInv.Items[e.item]
	if def and def.use_type == "weapon" then return def end
end

local function pick(cls)
	local lp = LocalPlayer()
	local w = lp:GetWeapon(cls)
	if IsValid(w) then
		input.SelectWeapon(w)
		return w
	end
end

local function weaponName(w)
	local n = w:GetPrintName()
	if not isstring(n) or n == "" then n = w:GetClass() end
	return string.upper(language.GetPhrase(n))
end

local function selectHands()
	local cls = RPInv.HandsClass()
	if cls ~= "" and pick(cls) then showHint("HANDS") end
end

local function selectSlot(slot)
	local name = RPInv.EquipSlotByKey[slot].name
	local def = slotWeapon(slot)
	if not def then
		showHint(name .. ": EMPTY")
		return
	end
	local active = LocalPlayer():GetActiveWeapon()
	if IsValid(active) and active:GetClass() == def.use_arg then
		selectHands()
		return
	end
	if pick(def.use_arg) then
		showHint(name .. ": " .. string.upper(def.name))
	else
		RPInv.Act({ a = "slotready", slot = slot })
		showHint(name .. ": " .. string.upper(def.name))
	end
end

local function slotClasses()
	local out = {}
	for _, key in ipairs(RPInv.WeaponSlotKeys) do
		local def = slotWeapon(key)
		if def then out[def.use_arg] = true end
	end
	return out
end

local function miscList()
	local lp = LocalPlayer()
	local bound = slotClasses()
	local list = {}
	for _, cls in ipairs(TOOLS) do
		local w = lp:GetWeapon(cls)
		if IsValid(w) then list[#list + 1] = w end
	end
	local others = {}
	for _, w in ipairs(lp:GetWeapons()) do
		local cls = w:GetClass()
		if cls ~= "rpinv_hands" and cls ~= "weapon_fists" and cls ~= RPInv.HandsClass() and not bound[cls] and not table.HasValue(TOOLS, cls) then
			others[#others + 1] = w
		end
	end
	table.sort(others, function(a, b) return a:GetSlot() < b:GetSlot() or (a:GetSlot() == b:GetSlot() and a:GetClass() < b:GetClass()) end)
	for _, w in ipairs(others) do list[#list + 1] = w end
	return list
end

local function cycleMisc()
	local list = miscList()
	if #list == 0 then
		showHint("MISC: EMPTY")
		return
	end
	local active = LocalPlayer():GetActiveWeapon()
	local idx = 0
	for i, w in ipairs(list) do
		if w == active then idx = i end
	end
	local nextW = list[idx % #list + 1]
	input.SelectWeapon(nextW)
	hint = nil
	misc, miscT = { list = list, sel = nextW }, RealTime()
end

local function quickKey(i)
	local id = RPInv.QuickSlots and RPInv.QuickSlots["s" .. i]
	local def = id and RPInv.Items[id]
	local label = "QUICK " .. QUICK_LABELS[i]
	if not def then
		quickPress.i = nil
		showHint(label .. ": EMPTY")
		surface.PlaySound("buttons/button10.wav")
		return
	end
	local now = RealTime()
	if quickPress.i == i and now - quickPress.t <= DOUBLE_TIME then
		quickPress.i = nil
		RPInv.Act({ a = "quickuse", slot = i })
		showHint(label .. ": " .. string.upper(def.name))
		return
	end
	quickPress.i, quickPress.t = i, now
	surface.PlaySound("buttons/lightswitch2.wav")
	local n = RPInv.CountOwned and RPInv.CountOwned(id) or 0
	showHint(label .. ": " .. string.upper(def.name) .. " x" .. n .. "   PRESS AGAIN")
end

local numKeys = CreateClientConVar("rpinv_numkeys", "1", true, false, "1 = number keys 1-0 run the inventory selector and quick slots, 0 = use rpinv_slot / rpinv_quick binds only")

local function vanilla()
	return RPInv.Settings and RPInv.Settings.selector_mode == "vanilla"
end

local function canAct(ply)
	return IsValid(ply) and ply:Alive() and not ply:GetNW2Bool("RPInvSurrender", false) and not IsValid(RPInv.Screen) and not RPInv.VehicleLocked(ply)
end

local function slotAction(n)
	if SLOT_KEYS[n] then
		selectSlot(SLOT_KEYS[n])
	elseif n == 4 then
		selectHands()
	elseif n == 5 then
		cycleMisc()
	end
end

hook.Add("HUDShouldDraw", "RPInv_NoWeaponSelection", function(name)
	if name == "CHudWeaponSelection" and not vanilla() then return false end
end)

hook.Add("PlayerBindPress", "RPInv_WeaponKeys", function(ply, bind, pressed)
	if RPInv.VehicleLocked(ply) then return end
	local b = string.lower(bind)
	local n = tonumber(string.match(b, "^slot(%d+)$"))
	if vanilla() then
		if not n or n < 7 or n > 10 or not numKeys:GetBool() then return end
		if ply:InVehicle() then return true end
		if pressed and canAct(ply) then quickKey(n - 5) end
		return true
	end
	if string.find(b, "invnext", 1, true) or string.find(b, "invprev", 1, true) then
		local w = ply:GetActiveWeapon()
		if IsValid(w) and w:GetClass() == "weapon_physgun" and input.IsMouseDown(MOUSE_LEFT) then return end
		return true
	end
	if b == "lastinv" then return true end
	if not n then return end
	if not numKeys:GetBool() then return true end
	if ply:InVehicle() and n >= 6 then return true end
	if pressed and canAct(ply) then
		if n >= 6 and n <= 10 then
			quickKey(n - 5)
		else
			slotAction(n)
		end
	end
	return true
end)

concommand.Add("rpinv_slot", function(ply, _, args)
	local n = tonumber(args[1])
	if not n or n < 1 or n > 5 or vanilla() or not canAct(ply) then return end
	slotAction(math.floor(n))
end, nil, "Select a weapon slot: 1 primary, 2 secondary, 3 utility, 4 hands, 5 misc (press again to cycle)")

concommand.Add("rpinv_quick", function(ply, _, args)
	local n = tonumber(args[1])
	if not n or n < 1 or n > 5 or not canAct(ply) or ply:InVehicle() then return end
	n = math.floor(n)
	local id = RPInv.QuickSlots and RPInv.QuickSlots["s" .. n]
	local def = id and RPInv.Items[id]
	if not def then
		showHint("QUICK " .. QUICK_LABELS[n] .. ": EMPTY")
		surface.PlaySound("buttons/button10.wav")
		return
	end
	RPInv.Act({ a = "quickuse", slot = n })
	showHint("QUICK " .. QUICK_LABELS[n] .. ": " .. string.upper(def.name))
end, nil, "Use quick slot 1-5 right away")

local function fade(age, hold, out)
	if age > hold + out then return nil end
	return age > hold and (1 - (age - hold) / out) or 1
end

local function footer(x, y, a)
	local text = (RPInv.Settings and RPInv.Settings.selector_mode == "vanilla") and "7-0 QUICK SLOTS 2-5 (PRESS TWICE)   rpinv_quick 1-5 TO BIND"
		or "1 PRIMARY   2 SECONDARY   3 UTILITY   4 HANDS   5 MISC   6-0 QUICK (PRESS TWICE)"
	draw.SimpleText(text, "RPInv.Tiny", x, y, Color(T.Mid.r, T.Mid.g, T.Mid.b, 200 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function drawMisc()
	local a = fade(RealTime() - miscT, 1.6, 0.4)
	if not a then
		misc = nil
		return
	end
	local list = misc.list
	local rowH = T.S(24)
	local w = T.S(260)
	for _, wp in ipairs(list) do
		if IsValid(wp) then
			surface.SetFont("RPInv.Small")
			w = math.max(w, surface.GetTextSize(weaponName(wp)) + T.S(40))
		end
	end
	local h = T.S(26) + #list * rowH + T.S(6)
	local x, y = ScrW() / 2 - w / 2, ScrH() - T.S(190) - h
	surface.SetDrawColor(10, 11, 10, 215 * a)
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(T.Accent.r, T.Accent.g, T.Accent.b, 255 * a)
	surface.DrawRect(x, y, T.S(3), h)
	draw.SimpleText("MISC", "RPInv.Text", x + T.S(12), y + T.S(13), Color(T.Accent.r, T.Accent.g, T.Accent.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local cy = y + T.S(26)
	for _, wp in ipairs(list) do
		if IsValid(wp) then
			local on = wp == misc.sel
			if on then
				surface.SetDrawColor(T.Accent.r, T.Accent.g, T.Accent.b, 40 * a)
				surface.DrawRect(x + T.S(6), cy, w - T.S(12), rowH - T.S(2))
			end
			local col = on and T.White or T.Mid
			draw.SimpleText((on and "> " or "  ") .. weaponName(wp), "RPInv.Small", x + T.S(14), cy + rowH / 2 - 1, Color(col.r, col.g, col.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cy = cy + rowH
		end
	end
	footer(ScrW() / 2, ScrH() - T.S(170) + T.S(40), a)
end

hook.Add("HUDPaint", "RPInv_UseCooldown", function()
	local lp = LocalPlayer()
	if not IsValid(lp) or not lp:Alive() then return end
	local left = lp:GetNW2Float("RPInvThrowAt", 0) - CurTime()
	if left <= 0 then return end
	local frac = math.Clamp(1 - left / 2, 0, 1)
	local w, h = T.S(160), T.S(6)
	local x, y = ScrW() / 2 - w / 2, ScrH() / 2 + T.S(42)
	surface.SetDrawColor(10, 11, 10, 200)
	surface.DrawRect(x - 1, y - 1, w + 2, h + 2)
	surface.SetDrawColor(T.Accent.r, T.Accent.g, T.Accent.b, 230)
	surface.DrawRect(x, y, w * frac, h)
	draw.SimpleText("THROWING  " .. string.format("%.1f", left) .. "s", "RPInv.Tiny", ScrW() / 2, y - T.S(4), T.Mid, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end)

hook.Add("HUDPaint", "RPInv_SelectHint", function()
	if misc then
		drawMisc()
		return
	end
	if not hint then return end
	local a = fade(RealTime() - hintT, 1.2, 0.4)
	if not a then
		hint = nil
		return
	end
	local x, y = ScrW() / 2, ScrH() - T.S(170)
	surface.SetFont("RPInv.Text")
	local tw = surface.GetTextSize(hint)
	local w, h = tw + T.S(30), T.S(30)
	surface.SetDrawColor(10, 11, 10, 210 * a)
	surface.DrawRect(x - w / 2, y, w, h)
	surface.SetDrawColor(T.Accent.r, T.Accent.g, T.Accent.b, 255 * a)
	surface.DrawRect(x - w / 2, y, T.S(3), h)
	draw.SimpleText(hint, "RPInv.Text", x, y + h / 2, Color(T.White.r, T.White.g, T.White.b, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	footer(x, y + h + T.S(10), a)
end)
