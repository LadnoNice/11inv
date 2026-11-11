RPInv.DB = RPInv.DB or {}
local DB = RPInv.DB
local Q = sql.SQLStr

DB.LOC_PLAYER = 0
DB.LOC_CONTAINER = 1
DB.LOC_EQUIP = 2
DB.LOC_CARRIER = 3

local function query(q)
	local r = sql.Query(q)
	if r == false then
		ErrorNoHalt("[RPInv] SQL error: " .. tostring(sql.LastError()) .. "\n  " .. q .. "\n")
	end
	return r
end
DB.Query = query

local depth = 0
function DB.Transaction(fn)
	depth = depth + 1
	if depth == 1 then sql.Begin() end
	local ok, err = pcall(fn)
	depth = depth - 1
	if depth == 0 then sql.Commit() end
	if not ok then ErrorNoHalt("[RPInv] " .. tostring(err) .. "\n") end
	return ok
end

local function lastId()
	return tonumber(sql.QueryValue("SELECT last_insert_rowid()"))
end

local function columns(tbl)
	local out = {}
	for _, r in ipairs(query("PRAGMA table_info(" .. tbl .. ")") or {}) do out[r.name] = true end
	return out
end

local function addColumn(tbl, cols, name, decl)
	if not cols[name] then query("ALTER TABLE " .. tbl .. " ADD COLUMN " .. name .. " " .. decl) end
end

local function nullable(v)
	if v == nil or v == "NULL" then return nil end
	return v
end

function DB.GetSetting(key, default)
	local r = sql.QueryValue("SELECT v FROM rpinv_settings WHERE k = " .. Q(key))
	if r == nil or r == false then return default end
	return r
end

function DB.SetSetting(key, value)
	query("REPLACE INTO rpinv_settings (k, v) VALUES (" .. Q(key) .. ", " .. Q(tostring(value)) .. ")")
end

function DB.Log(ply, action, details)
	local sid = IsValid(ply) and (ply:SteamID64() or ply:Nick()) or "console"
	query(string.format("INSERT INTO rpinv_log (ts, steamid, action, details) VALUES (%d, %s, %s, %s)",
		os.time(), Q(sid), Q(action), Q(tostring(details or ""):sub(1, 500))))
end

local ITEM_COLS = {
	"id", "name", "model", "descr", "max_stack", "use_type", "use_arg", "w", "h", "rotatable",
	"equip_slot", "grid_w", "grid_h", "jmod_armor", "world_class", "cam_ang", "cam_fov", "category", "cam_off", "skin", "bodygroups",
}
local ITEM_NUM = { max_stack = true, w = true, h = true, rotatable = true, grid_w = true, grid_h = true, cam_fov = true, skin = true }

function DB.SaveItem(d)
	local vals = {}
	for i, c in ipairs(ITEM_COLS) do
		local v = d[c]
		if c == "rotatable" then v = (v == false or v == 0) and 0 or 1 end
		if ITEM_NUM[c] then
			vals[i] = string.format("%g", tonumber(v) or 0)
		else
			vals[i] = Q(tostring(v or ""))
		end
	end
	query("REPLACE INTO rpinv_items (" .. table.concat(ITEM_COLS, ", ") .. ") VALUES (" .. table.concat(vals, ", ") .. ")")
end

function DB.DeleteItem(id)
	DB.Transaction(function()
		query("DELETE FROM rpinv_items WHERE id = " .. Q(id))
		query("DELETE FROM rpinv_inst WHERE item_id = " .. Q(id))
	end)
end

function DB.LoadItems()
	local out = {}
	for _, r in ipairs(query("SELECT * FROM rpinv_items") or {}) do
		local d = {}
		for _, c in ipairs(ITEM_COLS) do
			local v = nullable(r[c])
			d[c] = ITEM_NUM[c] and (tonumber(v) or 0) or (v or "")
		end
		d.max_stack = math.max(1, d.max_stack)
		d.w = math.Clamp(d.w, 1, 10)
		d.h = math.Clamp(d.h, 1, 10)
		d.rotatable = d.rotatable ~= 0
		out[d.id] = d
	end
	return out
end

local function metaJSON(meta)
	if not meta or next(meta) == nil then return "" end
	return util.TableToJSON(meta)
end

function DB.LoadInsts(locType, locId)
	local out = {}
	local rows = query(string.format("SELECT * FROM rpinv_inst WHERE loc_type = %d AND loc_id = %s", locType, Q(tostring(locId))))
	for _, r in ipairs(rows or {}) do
		local meta = nullable(r.meta)
		out[#out + 1] = {
			id = tonumber(r.id), item = r.item_id, amount = math.max(1, tonumber(r.amount) or 1),
			meta = (meta and meta ~= "" and util.JSONToTable(meta)) or {},
			x = tonumber(r.x) or 0, y = tonumber(r.y) or 0, rot = tonumber(r.rot) == 1 and 1 or 0,
			slot = nullable(r.slot),
		}
	end
	return out
end

function DB.InsertInst(inst, locType, locId)
	query(string.format(
		"INSERT INTO rpinv_inst (item_id, amount, meta, loc_type, loc_id, x, y, rot, slot) VALUES (%s, %d, %s, %d, %s, %d, %d, %d, %s)",
		Q(inst.item), inst.amount, Q(metaJSON(inst.meta)), locType, Q(tostring(locId)), inst.x, inst.y, inst.rot, inst.slot and Q(inst.slot) or "NULL"
	))
	inst.id = lastId()
	return inst.id
end

function DB.UpdateInst(inst, locType, locId)
	query(string.format(
		"UPDATE rpinv_inst SET amount = %d, meta = %s, loc_type = %d, loc_id = %s, x = %d, y = %d, rot = %d, slot = %s WHERE id = %d",
		inst.amount, Q(metaJSON(inst.meta)), locType, Q(tostring(locId)), inst.x, inst.y, inst.rot, inst.slot and Q(inst.slot) or "NULL", inst.id
	))
end

function DB.DeleteInst(id)
	query("DELETE FROM rpinv_inst WHERE id = " .. math.floor(id))
end

function DB.DeleteInstsAt(locType, locId)
	query(string.format("DELETE FROM rpinv_inst WHERE loc_type = %d AND loc_id = %s", locType, Q(tostring(locId))))
end

local function vecStr(v) return string.format("%.2f %.2f %.2f", v.x, v.y, v.z) end
local function parse3(str)
	local p = string.Explode(" ", str or "")
	return tonumber(p[1]) or 0, tonumber(p[2]) or 0, tonumber(p[3]) or 0
end
DB.Parse3 = parse3

function DB.CreateContainer(c)
	query(string.format(
		"INSERT INTO rpinv_containers (map, name, model, slots, grid_w, grid_h, pos, ang) VALUES (%s, %s, %s, %d, %d, %d, %s, %s)",
		Q(game.GetMap()), Q(c.name), Q(c.model), c.w * c.h, c.w, c.h, Q(vecStr(c.pos)), Q(vecStr(Vector(c.ang.p, c.ang.y, c.ang.r)))
	))
	return lastId()
end

function DB.UpdateContainerPos(id, pos, ang)
	query(string.format("UPDATE rpinv_containers SET pos = %s, ang = %s WHERE id = %d",
		Q(vecStr(pos)), Q(vecStr(Vector(ang.p, ang.y, ang.r))), id))
end

function DB.LoadContainers(map)
	local out = {}
	for _, r in ipairs(query("SELECT * FROM rpinv_containers WHERE map = " .. Q(map)) or {}) do
		local px, py, pz = parse3(r.pos)
		local ap, ay, ar = parse3(r.ang)
		out[#out + 1] = {
			id = tonumber(r.id), name = r.name, model = r.model,
			w = math.Clamp(tonumber(r.grid_w) or 10, 1, 20), h = math.Clamp(tonumber(r.grid_h) or 4, 1, 20),
			pos = Vector(px, py, pz), ang = Angle(ap, ay, ar),
		}
	end
	return out
end

function DB.DeleteContainer(id)
	DB.Transaction(function()
		query("DELETE FROM rpinv_containers WHERE id = " .. math.floor(id))
		DB.DeleteInstsAt(DB.LOC_CONTAINER, id)
	end)
end

function DB.SavePreset(p)
	local json = util.TableToJSON(p.contents or {})
	if p.id then
		query(string.format("UPDATE rpinv_presets SET name = %s, model = %s, slots = %d, grid_w = %d, grid_h = %d, contents = %s WHERE id = %d",
			Q(p.name), Q(p.model), p.w * p.h, p.w, p.h, Q(json), p.id))
		return p.id
	end
	query(string.format("INSERT INTO rpinv_presets (name, model, slots, grid_w, grid_h, contents) VALUES (%s, %s, %d, %d, %d, %s)",
		Q(p.name), Q(p.model), p.w * p.h, p.w, p.h, Q(json)))
	return lastId()
end

function DB.LoadPresets()
	local out = {}
	for _, r in ipairs(query("SELECT * FROM rpinv_presets") or {}) do
		local contents = {}
		for _, e in ipairs(util.JSONToTable(r.contents or "") or {}) do
			if type(e) == "table" and e.item_id and tonumber(e.amount) then
				contents[#contents + 1] = {
					item_id = tostring(e.item_id), amount = tonumber(e.amount),
					x = tonumber(e.x) or 0, y = tonumber(e.y) or 0, rot = tonumber(e.rot) == 1 and 1 or 0,
					meta = type(e.meta) == "table" and e.meta or nil,
				}
			end
		end
		local id = tonumber(r.id)
		out[id] = {
			id = id, name = r.name, model = r.model, contents = contents,
			w = math.Clamp(tonumber(r.grid_w) or 10, 1, 20), h = math.Clamp(tonumber(r.grid_h) or 4, 1, 20),
		}
	end
	return out
end

function DB.DeletePreset(id)
	query("DELETE FROM rpinv_presets WHERE id = " .. math.floor(id))
end

local STARTER_SIZES = {
	hotdog = { 1, 1, "Food" }, soda = { 1, 1, "Food" }, medkit = { 2, 1, "Medical" }, battery = { 1, 1, "Armor" },
	pistol = { 2, 1, "Weapons" }, crowbar = { 3, 1, "Weapons" },
	ammo_pistol = { 1, 1, "Ammo" }, ammo_smg = { 1, 1, "Ammo" }, ammo_ar2 = { 1, 1, "Ammo" },
	ammo_shotgun = { 1, 1, "Ammo" }, ammo_357 = { 1, 1, "Ammo" },
}

local function applyStarterSizes()
	for id, s in pairs(STARTER_SIZES) do
		query(string.format("UPDATE rpinv_items SET w = %d, h = %d, category = %s WHERE id = %s AND w = 1 AND h = 1 AND category = ''",
			s[1], s[2], Q(s[3]), Q(id)))
	end
end

local function migrate(from)
	if from >= 2 then return end
	local ic = columns("rpinv_items")
	addColumn("rpinv_items", ic, "w", "INTEGER NOT NULL DEFAULT 1")
	addColumn("rpinv_items", ic, "h", "INTEGER NOT NULL DEFAULT 1")
	addColumn("rpinv_items", ic, "rotatable", "INTEGER NOT NULL DEFAULT 1")
	addColumn("rpinv_items", ic, "equip_slot", "TEXT NOT NULL DEFAULT ''")
	addColumn("rpinv_items", ic, "grid_w", "INTEGER NOT NULL DEFAULT 0")
	addColumn("rpinv_items", ic, "grid_h", "INTEGER NOT NULL DEFAULT 0")
	addColumn("rpinv_items", ic, "jmod_armor", "TEXT NOT NULL DEFAULT ''")
	addColumn("rpinv_items", ic, "world_class", "TEXT NOT NULL DEFAULT ''")
	addColumn("rpinv_items", ic, "cam_ang", "TEXT NOT NULL DEFAULT ''")
	addColumn("rpinv_items", ic, "cam_fov", "REAL NOT NULL DEFAULT 0")
	addColumn("rpinv_items", ic, "category", "TEXT NOT NULL DEFAULT ''")

	local cc = columns("rpinv_containers")
	addColumn("rpinv_containers", cc, "grid_w", "INTEGER NOT NULL DEFAULT 10")
	addColumn("rpinv_containers", cc, "grid_h", "INTEGER NOT NULL DEFAULT 4")
	for _, r in ipairs(query("SELECT id, slots FROM rpinv_containers") or {}) do
		local slots = math.max(1, tonumber(r.slots) or 20)
		query(string.format("UPDATE rpinv_containers SET grid_w = %d, grid_h = %d WHERE id = %d",
			math.min(slots, 10), math.max(2, math.ceil(slots / 10)), tonumber(r.id)))
	end

	local pc = columns("rpinv_presets")
	addColumn("rpinv_presets", pc, "grid_w", "INTEGER NOT NULL DEFAULT 10")
	addColumn("rpinv_presets", pc, "grid_h", "INTEGER NOT NULL DEFAULT 4")
	for _, r in ipairs(query("SELECT id, slots FROM rpinv_presets") or {}) do
		local slots = math.max(1, tonumber(r.slots) or 20)
		query(string.format("UPDATE rpinv_presets SET grid_w = %d, grid_h = %d, contents = '[]' WHERE id = %d",
			math.min(slots, 10), math.max(2, math.ceil(slots / 10)), tonumber(r.id)))
	end

	query("DROP TABLE IF EXISTS rpinv_slots")
	query("DROP TABLE IF EXISTS rpinv_cslots")
	applyStarterSizes()
end

function DB.Init()
	query([[CREATE TABLE IF NOT EXISTS rpinv_settings (k TEXT PRIMARY KEY, v TEXT)]])
	query([[CREATE TABLE IF NOT EXISTS rpinv_items (
		id TEXT PRIMARY KEY, name TEXT NOT NULL, model TEXT NOT NULL,
		descr TEXT NOT NULL DEFAULT '', max_stack INTEGER NOT NULL DEFAULT 1,
		use_type TEXT NOT NULL DEFAULT 'none', use_arg TEXT NOT NULL DEFAULT '')]])
	query([[CREATE TABLE IF NOT EXISTS rpinv_containers (
		id INTEGER PRIMARY KEY AUTOINCREMENT, map TEXT NOT NULL, name TEXT NOT NULL, model TEXT NOT NULL,
		slots INTEGER NOT NULL DEFAULT 0, pos TEXT NOT NULL, ang TEXT NOT NULL)]])
	query([[CREATE TABLE IF NOT EXISTS rpinv_presets (
		id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, model TEXT NOT NULL,
		slots INTEGER NOT NULL DEFAULT 0, contents TEXT NOT NULL DEFAULT '[]')]])
	query([[CREATE TABLE IF NOT EXISTS rpinv_inst (
		id INTEGER PRIMARY KEY AUTOINCREMENT, item_id TEXT NOT NULL, amount INTEGER NOT NULL,
		meta TEXT NOT NULL DEFAULT '', loc_type INTEGER NOT NULL, loc_id TEXT NOT NULL,
		x INTEGER NOT NULL DEFAULT 0, y INTEGER NOT NULL DEFAULT 0, rot INTEGER NOT NULL DEFAULT 0, slot TEXT)]])
	query([[CREATE INDEX IF NOT EXISTS rpinv_inst_loc ON rpinv_inst (loc_type, loc_id)]])
	query([[CREATE TABLE IF NOT EXISTS rpinv_log (
		id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, steamid TEXT NOT NULL,
		action TEXT NOT NULL, details TEXT NOT NULL DEFAULT '')]])

	local version = tonumber(DB.GetSetting("schema_version", "1")) or 1
	if version < 2 then
		DB.Transaction(function() migrate(version) end)
		DB.SetSetting("schema_version", 2)
		version = 2
	end
	if version < 3 then
		addColumn("rpinv_items", columns("rpinv_items"), "cam_off", "TEXT NOT NULL DEFAULT ''")
		DB.SetSetting("schema_version", 3)
		version = 3
	end
	if version < 4 then
		local ic = columns("rpinv_items")
		addColumn("rpinv_items", ic, "skin", "INTEGER NOT NULL DEFAULT 0")
		addColumn("rpinv_items", ic, "bodygroups", "TEXT NOT NULL DEFAULT ''")
		DB.SetSetting("schema_version", 4)
	end

	if DB.GetSetting("seeded", "0") ~= "1" then
		local seed = {
			{ id = "hotdog", name = "Hotdog", model = "models/food/hotdog.mdl", descr = "Tastes better than it looks.", max_stack = 5, use_type = "heal", use_arg = "10" },
			{ id = "soda", name = "Soda Can", model = "models/props_junk/PopCan01a.mdl", descr = "Cold and fizzy.", max_stack = 5, use_type = "heal", use_arg = "5" },
			{ id = "medkit", name = "Medkit", model = "models/items/healthkit.mdl", descr = "Patches you up.", max_stack = 3, use_type = "heal", use_arg = "25" },
			{ id = "battery", name = "Armor Battery", model = "models/items/battery.mdl", descr = "Restores some armor.", max_stack = 3, use_type = "armor", use_arg = "15" },
			{ id = "pistol", name = "Pistol", model = "models/weapons/w_pistol.mdl", descr = "A standard sidearm.", max_stack = 1, use_type = "weapon", use_arg = "weapon_pistol" },
			{ id = "crowbar", name = "Crowbar", model = "models/weapons/w_crowbar.mdl", descr = "Handy tool.", max_stack = 1, use_type = "weapon", use_arg = "weapon_crowbar" },
		}
		for _, d in ipairs(seed) do d.w, d.h = 1, 1 DB.SaveItem(d) end
		DB.SetSetting("seeded", "1")
	end

	if DB.GetSetting("seeded_ammo", "0") ~= "1" then
		local ammo = {
			{ id = "ammo_pistol", name = "Pistol Ammo", model = "models/items/boxsrounds.mdl", descr = "20 rounds of 9mm.", max_stack = 10, use_type = "ammo", use_arg = "Pistol:20" },
			{ id = "ammo_smg", name = "SMG Ammo", model = "models/items/boxmrounds.mdl", descr = "45 rounds for SMGs.", max_stack = 10, use_type = "ammo", use_arg = "SMG1:45" },
			{ id = "ammo_ar2", name = "Rifle Ammo", model = "models/items/combine_rifle_cartridge01.mdl", descr = "30 rounds of rifle ammo.", max_stack = 10, use_type = "ammo", use_arg = "AR2:30" },
			{ id = "ammo_shotgun", name = "Shotgun Shells", model = "models/items/boxbuckshot.mdl", descr = "12 shells.", max_stack = 10, use_type = "ammo", use_arg = "Buckshot:12" },
			{ id = "ammo_357", name = "Magnum Ammo", model = "models/items/357ammo.mdl", descr = "6 magnum rounds.", max_stack = 10, use_type = "ammo", use_arg = "357:6" },
		}
		for _, d in ipairs(ammo) do d.w, d.h = 1, 1 DB.SaveItem(d) end
		DB.SetSetting("seeded_ammo", "1")
	end

	if DB.GetSetting("seeded_sizes", "0") ~= "1" then
		applyStarterSizes()
		DB.SetSetting("seeded_sizes", "1")
	end
end
