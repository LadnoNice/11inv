RPInv = RPInv or {}
local G = {}
RPInv.Grid = G

function G.Size(def, rot)
	local w, h = 1, 1
	if def then w, h = def.w or 1, def.h or 1 end
	if rot == 1 then return h, w end
	return w, h
end

function G.InstSize(defs, inst, rot)
	return G.Size(defs[inst.item], rot == nil and inst.rot or rot)
end

function G.Occupancy(st, defs, ignoreA, ignoreB)
	local occ = {}
	for _, it in pairs(st.items) do
		if it ~= ignoreA and it ~= ignoreB then
			local w, h = G.InstSize(defs, it)
			for dy = 0, h - 1 do
				for dx = 0, w - 1 do
					occ[(it.y + dy) * st.w + it.x + dx] = it
				end
			end
		end
	end
	return occ
end

function G.InBounds(st, w, h, x, y)
	return x >= 0 and y >= 0 and x + w <= st.w and y + h <= st.h
end

function G.Fits(st, occ, w, h, x, y)
	if not G.InBounds(st, w, h, x, y) then return false end
	for dy = 0, h - 1 do
		local row = (y + dy) * st.w + x
		for dx = 0, w - 1 do
			if occ[row + dx] then return false end
		end
	end
	return true
end

function G.CanPlace(st, defs, w, h, x, y, ignoreA, ignoreB)
	return G.Fits(st, G.Occupancy(st, defs, ignoreA, ignoreB), w, h, x, y)
end

function G.Overlaps(st, defs, w, h, x, y, ignore)
	local found, list = {}, {}
	for _, it in pairs(st.items) do
		if it ~= ignore and not found[it] then
			local iw, ih = G.InstSize(defs, it)
			if x < it.x + iw and it.x < x + w and y < it.y + ih and it.y < y + h then
				found[it] = true
				list[#list + 1] = it
			end
		end
	end
	return list
end

function G.ItemAt(st, defs, cx, cy)
	for _, it in pairs(st.items) do
		local w, h = G.InstSize(defs, it)
		if cx >= it.x and cx < it.x + w and cy >= it.y and cy < it.y + h then return it end
	end
end

function G.FindSpot(st, occ, def)
	local rots = { 0 }
	local w, h = G.Size(def, 0)
	if def and def.rotatable ~= false and def.rotatable ~= 0 and w ~= h then rots[2] = 1 end
	for _, rot in ipairs(rots) do
		local rw, rh = G.Size(def, rot)
		for y = 0, st.h - rh do
			for x = 0, st.w - rw do
				if G.Fits(st, occ, rw, rh, x, y) then return x, y, rot end
			end
		end
	end
end

function G.AutoPlace(st, defs, def, ignore)
	return G.FindSpot(st, G.Occupancy(st, defs, ignore), def)
end

function G.Mark(st, occ, inst, w, h, x, y)
	for dy = 0, h - 1 do
		for dx = 0, w - 1 do
			occ[(y + dy) * st.w + x + dx] = inst
		end
	end
end

function G.SortKey(def)
	return def and (def.category ~= "" and def.category or def.use_type) or "zzz"
end

function G.Sort(st, defs)
	local list = {}
	for _, it in pairs(st.items) do list[#list + 1] = it end
	table.sort(list, function(a, b)
		local da, db = defs[a.item], defs[b.item]
		local wa, ha = G.Size(da, 0)
		local wb, hb = G.Size(db, 0)
		if wa * ha ~= wb * hb then return wa * ha > wb * hb end
		local ka, kb = G.SortKey(da), G.SortKey(db)
		if ka ~= kb then return ka < kb end
		local na, nb = da and da.name or a.item, db and db.name or b.item
		if na ~= nb then return na < nb end
		if a.amount ~= b.amount then return a.amount > b.amount end
		return a.id < b.id
	end)
	local occ, out = {}, {}
	for _, it in ipairs(list) do
		local def = defs[it.item]
		local x, y, rot = G.FindSpot(st, occ, def)
		if not x then return nil end
		local w, h = G.Size(def, rot)
		G.Mark(st, occ, it, w, h, x, y)
		out[it.id] = { x = x, y = y, rot = rot }
	end
	return out
end

function G.MetaEmpty(meta)
	return meta == nil or next(meta) == nil
end

function G.CanStack(defs, a, b)
	if a == b or a.item ~= b.item then return false end
	local def = defs[a.item]
	if not def or (def.max_stack or 1) <= 1 then return false end
	return G.MetaEmpty(a.meta) and G.MetaEmpty(b.meta) and b.amount < def.max_stack
end

function G.Matches(def, query)
	if query == nil or query == "" then return true end
	if not def then return false end
	local q = string.lower(query)
	return string.find(string.lower(def.name or ""), q, 1, true) ~= nil
		or string.find(string.lower(def.use_type or ""), q, 1, true) ~= nil
		or string.find(string.lower(def.category or ""), q, 1, true) ~= nil
end
