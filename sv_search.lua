local DB = RPInv.DB
local G = RPInv.Grid
local E = RPInv.Equip
local J = RPInv.JM
local K = RPInv.Carriers

util.AddNetworkString("rpinv_frisk")
util.AddNetworkString("rpinv_frisk_state")

local RANGE = 110

local HOLSTER = { [1] = { time = 1.5, stow = 0.6 }, [2] = { time = 1.0, stow = 0.55 } }

local function gear(ent, vol, pitch)
	if IsValid(ent) then ent:EmitSound("npc/combine_soldier/gear" .. math.random(1, 6) .. ".wav", vol or 55, pitch or math.random(95, 108)) end
end
RPInv.GearSound = gear

local function rustle(state, ent, now)
	if (state.nextSnd or 0) > now then return end
	state.nextSnd = now + math.Rand(0.55, 0.85)
	gear(ent, 52, math.random(92, 112))
end

local function holsterKind(ply, wep)
	if not IsValid(wep) then return 0 end
	local cls = wep:GetClass()
	if cls == "rpinv_hands" or cls == "weapon_fists" then return 0 end
	for slot, inst in pairs(E.State(ply).weapons) do
		local def = RPInv.Items[inst.item]
		if def and def.use_arg == cls then return slot == "primary" and 1 or 2 end
	end
	return (tonumber(wep:GetSlot()) or 2) <= 1 and 2 or 1
end

local function toHands(ply)
	if not ply:Alive() then return end
	if not ply:HasWeapon("rpinv_hands") then ply:Give("rpinv_hands") end
	ply:SelectWeapon("rpinv_hands")
end

local function setSurrender(ply, on, quiet)
	if ply:GetNW2Bool("RPInvSurrender", false) == on then return end
	local tname = "RPInv_Holster" .. ply:EntIndex()
	timer.Remove(tname)
	timer.Remove(tname .. "b")
	timer.Remove(tname .. "h")
	ply:SetNW2Int("RPInvHolster", 0)
	if on then
		ply:SetNW2Bool("RPInvSurrender", true)
		if not ply:Alive() then return end
		local wep = ply:GetActiveWeapon()
		local kind = holsterKind(ply, wep)
		if kind == 0 then
			toHands(ply)
			gear(ply, 55)
			return
		end
		local model = wep:GetModel()
		ply:SetNW2String("RPInvHolsterModel", isstring(model) and model or "")
		ply:SetNW2String("RPInvHolsterClass", wep:GetClass())
		ply:SetNW2Float("RPInvHolsterAt", CurTime())
		ply:SetNW2Int("RPInvHolster", kind)
		local spec = HOLSTER[kind]
		timer.Create(tname .. "h", 0.15, 1, function()
			if IsValid(ply) and ply:GetNW2Bool("RPInvSurrender", false) then toHands(ply) end
		end)
		timer.Create(tname, spec.time * spec.stow, 1, function()
			if not IsValid(ply) or ply:GetNW2Int("RPInvHolster", 0) == 0 then return end
			if ply:GetNW2Bool("RPInvSurrender", false) then toHands(ply) end
			ply:EmitSound("npc/combine_soldier/gear" .. math.random(1, 6) .. ".wav", 60)
			timer.Create(tname .. "b", spec.time * (1 - spec.stow), 1, function()
				if IsValid(ply) then ply:SetNW2Int("RPInvHolster", 0) end
			end)
		end)
		return
	end
	ply:SetNW2Bool("RPInvSurrender", false)
	local hands = RPInv.HandsClass()
	if hands ~= "rpinv_hands" and ply:HasWeapon("rpinv_hands") then
		if hands ~= "" and ply:Alive() then
			if not ply:HasWeapon(hands) then ply:Give(hands) end
			ply:SelectWeapon(hands)
		end
		timer.Simple(0, function()
			if IsValid(ply) and not ply:GetNW2Bool("RPInvSurrender", false) then ply:StripWeapon("rpinv_hands") end
		end)
		if not quiet then gear(ply, 50, 110) end
		return
	end
	if not quiet then
		toHands(ply)
		gear(ply, 50, 110)
	end
end
RPInv.SetSurrender = setSurrender

hook.Add("PlayerSpawn", "RPInv_SurrenderReset", function(ply) setSurrender(ply, false, true) end)
hook.Add("PlayerDeath", "RPInv_SurrenderReset", function(ply) setSurrender(ply, false, true) end)

local function sendState(ply, t)
	if not IsValid(ply) or ply:IsBot() then return end
	RPInv.SendJSON("rpinv_frisk_state", t, ply)
end

local function canSearch(searcher, target, opened)
	if not IsValid(target) or not target:IsPlayer() or target == searcher then return false, "Nothing to search." end
	if not searcher:Alive() or not target:Alive() then return false, "Both players must be alive." end
	if searcher:GetPos():DistToSqr(target:GetPos()) > (RANGE + 40) * (RANGE + 40) then return false, "You are too far away." end
	if searcher.RPInvForceSearch == target or opened then return true end
	local mode = RPInv.Settings.search_mode
	if mode == "admin" then return false, "Only admins can search players on this server." end
	if mode == "surrender" and not target:GetNW2Bool("RPInvSurrender", false) then return false, "The player has to hold E to surrender first." end
	return true
end

function RPInv.FriskValid(ply)
	return IsValid(ply.RPInvFrisk) and (canSearch(ply, ply.RPInvFrisk, true))
end

local function aimAt(ply, ent)
	local eye, aim = ply:GetShootPos(), ply:GetAimVector()
	local bestDist, bestDot = math.huge, -1
	local function test(pos)
		local d = pos:DistToSqr(eye)
		if d < bestDist then bestDist = d end
		local dot = aim:Dot((pos - eye):GetNormalized())
		if dot > bestDot then bestDot = dot end
	end
	local n = ent:GetPhysicsObjectCount()
	if ent:IsRagdoll() and n > 0 then
		for i = 0, n - 1 do
			local ph = ent:GetPhysicsObjectNum(i)
			if IsValid(ph) then test(ph:GetPos()) end
		end
	else
		test(ent:WorldSpaceCenter())
		test(ent:EyePos())
		test(ent:GetPos() + Vector(0, 0, 12))
	end
	return math.sqrt(bestDist), bestDot
end

local function lookingAt(ply, target)
	local _, dot = aimAt(ply, target)
	return dot > 0.7 or ply:GetEyeTrace().Entity == target
end

local function holdCheck(ply, ent, holding, range)
	if not IsValid(ent) then return "the target is gone" end
	if not holding then return "you let go of E" end
	local dist, dot = aimAt(ply, ent)
	if dist > range then return "you are too far away" end
	if dot < 0.7 and ply:GetEyeTrace().Entity ~= ent then return "you looked away" end
end

local GRACE = 0.5

local function lookedPlayer(ply)
	local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * RANGE, filter = ply })
	local e = tr.Entity
	if IsValid(e) and e:IsPlayer() then return e end
	if IsValid(e) then return nil, true end
end

local function stopSearch(ply, reason)
	local target = ply.RPInvFrisk or (ply.RPInvFriskPending and ply.RPInvFriskPending.target)
	ply.RPInvFrisk, ply.RPInvFriskPending, ply.RPInvForceSearch = nil, nil, nil
	ply.RPInvNeedRelease = true
	sendState(ply, { phase = "closed", reason = reason })
	if IsValid(target) then
		sendState(target, { phase = "closed_target" })
		if reason then RPInv.Notify(target, "The search was stopped.", 0) end
	end
end

local function sendEquip(searcher, target)
	local slots, worn = E.Slots(target)
	local pd = K.PocketsDef()
	sendState(searcher, {
		phase = "equip", name = target:Nick(), slots = slots, equipment = RPInv.Settings.search_equipment,
		pockets = K.PocketsCid(target), pocketsW = pd.grid_w, pocketsH = pd.grid_h,
	})
	local pk = K.Pockets(target)
	if pk then RPInv.Push(pk, searcher) end
	for _, w in ipairs(worn) do
		local def = RPInv.Items[w.item]
		if RPInv.IsCarrierDef(def) then RPInv.Push(K.Storage(w.key, def), searcher) end
	end
end

local function openSearch(ply, target)
	ply.RPInvFriskPending = nil
	ply.RPInvFrisk = target
	DB.Log(ply, "search", target:SteamID64() or target:Nick())
	sendState(ply, { phase = "open", name = target:Nick() })
	sendState(target, { phase = "closed_target" })
	RPInv.Push(RPInv.PlayerStorage(target), ply)
	sendEquip(ply, target)
	target:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 60)
	gear(target, 58)
	RPInv.Notify(target, ply:Nick() .. " is going through your things.", 2)
end

local function setSearching(ply, on)
	if ply:GetNW2Bool("RPInvSearching", false) ~= on then ply:SetNW2Bool("RPInvSearching", on) end
end

function RPInv.StartLoot(ply, rag)
	if not ply:Alive() or ply.RPInvLoot or ply.RPInvFriskPending or ply.RPInvFrisk then return end
	if ply.RPInvOpen == rag.RPInvCorpseId then return end
	local time = RPInv.Settings.loot_time or 2
	ply.RPInvLoot = { rag = rag, done = CurTime() + time }
	setSearching(ply, true)
	sendState(ply, { phase = "progress", name = "BODY OF " .. rag:GetNW2String("RPInvCorpse", ""), time = time })
end

local function stopLoot(ply, opened, why)
	ply.RPInvLoot = nil
	setSearching(ply, false)
	sendState(ply, { phase = "progress_end" })
	if not opened then
		RPInv.Notify(ply, "Search cancelled: " .. (why or "interrupted") .. ".", 2)
		ply:EmitSound("buttons/button10.wav", 45, 110)
	end
end

local function startSearch(ply, target, force)
	if ply.RPInvFrisk or ply.RPInvFriskPending then stopSearch(ply) end
	ply.RPInvForceSearch = force and target or nil
	local ok, err = canSearch(ply, target)
	if not ok then
		ply.RPInvForceSearch = nil
		if force then RPInv.Notify(ply, err, 2) end
		return
	end
	local time = RPInv.Settings.search_time
	ply.RPInvFriskPending = { target = target, done = CurTime() + time, force = force }
	sendState(ply, { phase = "progress", name = target:Nick(), time = time })
	sendState(target, { phase = "progress_target", name = ply:Nick(), time = time })
end

net.Receive("rpinv_frisk", function(_, ply)
	if net.ReadUInt(2) == 2 and (ply.RPInvFrisk or ply.RPInvFriskPending) then stopSearch(ply) end
end)

concommand.Add("rpinv_search", function(ply)
	if not IsValid(ply) or not ply:IsSuperAdmin() then return end
	local target = ply:GetEyeTrace().Entity
	if not IsValid(target) or not target:IsPlayer() then RPInv.Notify(ply, "Aim at a player.", 2) return end
	startSearch(ply, target, true)
end)

local TOOL_WEAPONS = { weapon_physgun = true, gmod_tool = true, gmod_camera = true }

local function toolBusy(p)
	local w = p:GetActiveWeapon()
	if IsValid(w) and TOOL_WEAPONS[w:GetClass()] then return true end
	return p:KeyDown(IN_ATTACK) or p:KeyDown(IN_ATTACK2)
end

timer.Create("RPInv_FriskCheck", 0.1, 0, function()
	local now = CurTime()
	for _, p in ipairs(player.GetAll()) do
		local holding = p:Alive() and not p:InVehicle() and (p.RPInvHoldCmd or (p:KeyDown(IN_USE) and p:GetInfoNum("rpinv_hold_e", 1) ~= 0))
		if not holding then p.RPInvNeedRelease = nil end
		local loot = p.RPInvLoot
		if loot then
			local rag = loot.rag
			local why = (not IsValid(rag) or not rag.RPInvCorpseId) and "the body is gone" or holdCheck(p, rag, holding, 140)
			if why then
				loot.bad = loot.bad or now
				if now - loot.bad >= GRACE or not IsValid(rag) then stopLoot(p, false, why) end
			else
				loot.bad = nil
				rustle(loot, rag, now)
				if now >= loot.done then
					local id = rag.RPInvCorpseId
					stopLoot(p, true)
					p.RPInvNeedRelease = true
					RPInv.OpenContainerId(p, id)
				end
			end
		end
		setSearching(p, (p.RPInvLoot ~= nil) or (p.RPInvFriskPending ~= nil))
		local pend = p.RPInvFriskPending
		if pend then
			local okSearch, err = canSearch(p, pend.target)
			local why = (not okSearch) and string.lower(string.TrimRight(err or "not allowed", ".")) or (not pend.force and holdCheck(p, pend.target, holding, RANGE + 20))
			if why then
				pend.bad = pend.bad or now
				if now - pend.bad >= GRACE or not IsValid(pend.target) then
					stopSearch(p, "cancelled")
					RPInv.Notify(p, "Search cancelled: " .. why .. ".", 2)
					p:EmitSound("buttons/button10.wav", 45, 110)
				end
			else
				pend.bad = nil
				rustle(pend, pend.target, now)
				if now >= pend.done then openSearch(p, pend.target) end
			end
		elseif p.RPInvFrisk then
			if not RPInv.FriskValid(p) then
				stopSearch(p, "ended")
				RPInv.Notify(p, "The search ended.", 0)
			end
		end

		local surrendered = p:GetNW2Bool("RPInvSurrender", false)
		if not holding then
			p.RPInvHoldSince = nil
			if surrendered and not p.RPInvForceSurrender then setSurrender(p, false) end
		elseif not surrendered and not p.RPInvFriskPending and not p.RPInvFrisk and not p.RPInvLoot and (p.RPInvHoldCmd or not toolBusy(p)) then
			local target, blocked = lookedPlayer(p)
			if target then
				p.RPInvHoldSince = nil
				if not p.RPInvNeedRelease then startSearch(p, target, false) end
			elseif blocked then
				p.RPInvHoldSince = nil
			else
				p.RPInvHoldSince = p.RPInvHoldSince or now
				if now - p.RPInvHoldSince >= 0.5 then setSurrender(p, true) end
			end
		elseif not surrendered then
			p.RPInvHoldSince = nil
			p.RPInvNeedRelease = true
		end
	end
end)

concommand.Add("+rpinv_hold", function(ply)
	if not IsValid(ply) then return end
	ply.RPInvHoldCmd = true
	local e = ply:GetEyeTrace().Entity
	if IsValid(e) and e.RPInvCorpseId and RPInv.StartLoot and ply:GetShootPos():DistToSqr(ply:GetEyeTrace().HitPos) < 140 * 140 then
		RPInv.StartLoot(ply, e)
	end
end)

concommand.Add("-rpinv_hold", function(ply)
	if IsValid(ply) then ply.RPInvHoldCmd = nil end
end)

hook.Add("PlayerDisconnected", "RPInv_FriskLeave", function(ply)
	for _, p in ipairs(player.GetAll()) do
		if p ~= ply and (p.RPInvFrisk == ply or (p.RPInvFriskPending and p.RPInvFriskPending.target == ply)) then
			stopSearch(p, "left")
		end
	end
end)

hook.Add("RPInv_EquipPushed", "RPInv_FriskEquip", function(ply)
	for _, p in ipairs(player.GetAll()) do
		if p.RPInvFrisk == ply and RPInv.FriskValid(p) then sendEquip(p, ply) end
	end
end)

function RPInv.FriskAccess(ply, sub)
	if not RPInv.FriskValid(ply) then return nil end
	local target = ply.RPInvFrisk
	if sub == "p" then return RPInv.PlayerStorage(target) end
	local cid = string.match(sub, "^k:([%w_]+)$")
	if cid then
		local def = K.WornDef(target, cid)
		if def then return K.Storage(cid, def) end
	end
end

RPInv.Actions.frisk_take = function(ply, t, touch)
	if not RPInv.FriskValid(ply) then return "You are not searching anyone." end
	if not RPInv.Settings.search_equipment then return "Taking worn equipment is disabled on this server." end
	local target = ply.RPInvFrisk
	local key = string.sub(tostring(t.key or ""), 1, 64)
	local s = E.State(target)
	local mine = RPInv.PlayerStorage(ply)
	touch(mine)

	for slot, inst in pairs(s.weapons) do
		if tostring(inst.id) == key then
			local def = RPInv.Items[inst.item]
			local x, y, rot = G.AutoPlace(mine, RPInv.Items, def)
			if not x then return "Not enough space in your inventory." end
			E.StripWeapon(target, inst)
			s.weapons[slot] = nil
			inst.slot, inst.x, inst.y, inst.rot = nil, x, y, rot
			mine.items[inst.id] = inst
			DB.UpdateInst(inst, mine.loc, mine.locId)
			E.QueuePush(target)
			DB.Log(ply, "search_take", (target:SteamID64() or "?") .. " " .. inst.item)
			gear(target, 60)
			return true
		end
	end

	if not J.Available() or not (target.EZarmor and istable(target.EZarmor.items)) then return false end
	local armorId
	for id in pairs(target.EZarmor.items) do
		if tostring(id) == key then armorId = id end
	end
	if not armorId then return false end
	target.RPInvCapture = { to = ply }
	local ok, err = pcall(JMod.RemoveArmorByID, target, armorId, false)
	target.RPInvCapture = nil
	if not ok then ErrorNoHalt("[RPInv] " .. tostring(err) .. "\n") end
	E.QueuePush(target)
	DB.Log(ply, "search_take", (target:SteamID64() or "?") .. " armor")
	gear(target, 60)
	return true
end
