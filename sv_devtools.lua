local function say(ply, msg)
	if IsValid(ply) then ply:ChatPrint("[RPInv dev] " .. msg) else print("[RPInv dev] " .. msg) end
end

local function getBot()
	for _, p in ipairs(player.GetBots()) do
		if p.RPInvDevBot then return p end
	end
end

local function countIn(st, id)
	local n = 0
	for _, it in pairs(st.items) do
		if it.item == id then n = n + it.amount end
	end
	return n
end

local function aimed(ply, cls)
	local ent = ply:GetEyeTrace().Entity
	if IsValid(ent) and ent:GetClass() == cls then return ent end
end

local function dev(name, fn)
	concommand.Add(name, function(ply, _, args)
		if not IsValid(ply) or not ply:IsSuperAdmin() then return end
		fn(ply, args)
	end)
end

local function needBot(ply)
	local bot = getBot()
	if not IsValid(bot) then say(ply, "No test bot. Run rpinv_dev_bot first.") end
	return bot
end

local function botContainer(bot)
	return bot.RPInvOpen and RPInv.Access(bot, "c:" .. bot.RPInvOpen)
end

dev("rpinv_dev_bot", function(ply)
	local bot = getBot()
	if not IsValid(bot) then
		if player.GetCount() >= game.MaxPlayers() then
			say(ply, "No free player slot. Start the game with 2+ max players (not singleplayer).")
			return
		end
		bot = player.CreateNextBot("RPInv Tester")
		if not IsValid(bot) then say(ply, "Could not create a bot.") return end
		bot.RPInvDevBot = true
	end
	if not bot:Alive() then bot:Spawn() end
	bot:SetPos(ply:GetPos() + ply:GetRight() * 48)
	say(ply, "Bot ready next to you: " .. bot:Nick())
end)

dev("rpinv_dev_bot_remove", function(ply)
	local bot = needBot(ply)
	if bot then bot:Kick("RPInv test finished") say(ply, "Bot removed.") end
end)

dev("rpinv_dev_race", function(ply)
	local bot = needBot(ply)
	if not bot then return end
	local ent = aimed(ply, "rpinv_item")
	if not ent then say(ply, "Aim at a world item.") return end
	local id, total = ent:GetItemID(), ent:GetAmount()
	local stA, stB = RPInv.PlayerStorage(ply), RPInv.PlayerStorage(bot)
	local before = countIn(stA, id) + countIn(stB, id)
	ent:Use(bot, bot)
	if IsValid(ent) then ent:Use(ply, ply) end
	timer.Simple(0.2, function()
		if not IsValid(ply) or not IsValid(bot) then return end
		local gained = countIn(stA, id) + countIn(stB, id) - before
		local onGround = IsValid(ent) and not ent.RPInvTaken and ent:GetAmount() or 0
		local ok = gained + onGround == total
		say(ply, string.format("Item stack %d: players gained %d, left in world %d -> %s", total, gained, onGround, ok and "PASS (no dupe)" or "FAIL (DUPE!)"))
	end)
end)

dev("rpinv_dev_bot_open", function(ply)
	local bot = needBot(ply)
	if not bot then return end
	local ent = aimed(ply, "rpinv_container")
	if not ent then say(ply, "Aim at a container.") return end
	if not bot:Alive() then bot:Spawn() end
	bot:SetPos(ply:GetPos() + ply:GetRight() * 48)
	RPInv.OpenContainer(bot, ent)
	say(ply, "Bot opened " .. ent:GetCName() .. ". Open it yourself too, then use rpinv_dev_bot_put / rpinv_dev_bot_take.")
end)

dev("rpinv_dev_bot_put", function(ply, args)
	local bot = needBot(ply)
	if not bot then return end
	local id, amount = args[1], math.max(1, math.floor(tonumber(args[2]) or 1))
	if not id or not RPInv.Items[id] then say(ply, "Usage: rpinv_dev_bot_put <item id> [amount]") return end
	if not botContainer(bot) then say(ply, "The bot has no container open (rpinv_dev_bot_open).") return end
	RPInv.AddItem(bot, id, amount)
	local moved = 0
	for _, it in SortedPairs(RPInv.PlayerStorage(bot).items) do
		if it.item == id and RPInv.DoAction(bot, { a = "quick", from = "p", id = it.id }) then moved = moved + 1 end
	end
	say(ply, "Bot moved " .. moved .. " stack(s) of " .. id .. " into the container.")
end)

dev("rpinv_dev_bot_take", function(ply, args)
	local bot = needBot(ply)
	if not bot then return end
	local st = botContainer(bot)
	if not st then say(ply, "The bot has no container open (rpinv_dev_bot_open).") return end
	local k = math.max(1, math.floor(tonumber(args[1]) or 1))
	local i = 0
	for _, it in SortedPairsByMemberValue(st.items, "y") do
		i = i + 1
		if i == k then
			local name = it.item
			local ok = RPInv.DoAction(bot, { a = "quick", from = "c:" .. bot.RPInvOpen, id = it.id })
			say(ply, "Bot took item #" .. k .. " (" .. name .. "): " .. (ok and "ok" or "failed"))
			return
		end
	end
	say(ply, "The container has fewer than " .. k .. " items.")
end)

dev("rpinv_dev_bot_inv", function(ply)
	local bot = needBot(ply)
	if not bot then return end
	local parts = {}
	for _, it in SortedPairs(RPInv.PlayerStorage(bot).items) do
		parts[#parts + 1] = it.item .. " x" .. it.amount .. " @" .. it.x .. "," .. it.y
	end
	say(ply, "Bot inventory: " .. (#parts > 0 and table.concat(parts, ", ") or "empty") .. " | open container: " .. tostring(bot.RPInvOpen))
end)

dev("rpinv_dev_bot_kill", function(ply)
	local bot = needBot(ply)
	if bot then bot:Kill() say(ply, "Bot killed. Its container access is closed (check with rpinv_dev_bot_inv).") end
end)

dev("rpinv_dev_bot_surrender", function(ply)
	local bot = needBot(ply)
	if not bot then return end
	bot.RPInvForceSurrender = not bot.RPInvForceSurrender
	RPInv.SetSurrender(bot, bot.RPInvForceSurrender)
	if bot.RPInvForceSurrender then bot:SetPos(ply:GetPos() + ply:GetForward() * 60) end
	say(ply, "Bot hands up: " .. tostring(bot.RPInvForceSurrender) .. ". Look at it and hold E to search.")
end)

dev("rpinv_dev_bot_gear", function(ply)
	local bot = needBot(ply)
	if not bot then return end
	local n = 0
	for id in SortedPairs(RPInv.Items) do
		if n < 6 and RPInv.GiveToStorage(RPInv.PlayerStorage(bot), id, 1) == 0 then n = n + 1 end
	end
	if RPInv.JM.Available() then
		for _, name in ipairs({ "Backpack", "Medium-Vest" }) do
			if JMod.ArmorTable[name] then RPInv.JM.Equip(bot, name) end
		end
	end
	RPInv.Push(RPInv.PlayerStorage(bot))
	RPInv.Equip.QueuePush(bot)
	say(ply, "Gave the bot " .. n .. " items and some JMod armor.")
end)

dev("rpinv_dev_fill", function(ply)
	local st = RPInv.PlayerStorage(ply)
	local n = 0
	for id in SortedPairs(RPInv.Items) do
		if RPInv.GiveToStorage(st, id, 1) == 0 then n = n + 1 end
	end
	RPInv.Push(st)
	say(ply, "Added one of each item type (" .. n .. " placed).")
end)
