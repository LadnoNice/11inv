RPInv = RPInv or {}
RPInv.Items = RPInv.Items or {}
RPInv.UseTypes = {
	none   = "Nothing",
	heal   = "Restore health (arg = amount)",
	armor  = "Restore armor (arg = amount)",
	weapon = "Give weapon (arg = weapon class)",
	ammo   = "Give ammo (arg = AmmoType:amount)",
	throw  = "Throw armed (arg = entity class, JMod grenades)",
	place  = "Place in front (arg = entity class)",
	entuse = "Use like pressing E on the entity (arg = entity class)",
	attachment = "Weapon attachment (arg = base:name, e.g. arccw:optic_mrs)",
	flare  = "Airdrop flare gun, single use (arg = preset IDs, e.g. 1,3; empty = any)",
	resource = "JMod resource, stack = units (arg = resource entity class)",
	rounds = "Loose rounds for reserve ammo (arg = ammo type name)",
}

for _, f in ipairs({ "rpinv/sh_grid.lua", "rpinv/sh_equip.lua", "rpinv/sh_protect.lua", "rpinv/sh_attach.lua" }) do
	AddCSLuaFile(f)
	include(f)
end

local client = {
	"rpinv/cl_theme.lua", "rpinv/cl_icons.lua", "rpinv/cl_grid.lua",
	"rpinv/cl_ui.lua", "rpinv/cl_search.lua", "rpinv/cl_select.lua", "rpinv/cl_attach.lua", "rpinv/cl_airdrop.lua", "rpinv/cl_loot.lua", "rpinv/cl_admin.lua", "rpinv/cl_presets.lua",
}

if SERVER then
	for _, f in ipairs(client) do AddCSLuaFile(f) end
	include("rpinv/sv_database.lua")
	include("rpinv/sv_inventory.lua")
	include("rpinv/sv_jmod.lua")
	include("rpinv/sv_equipment.lua")
	include("rpinv/sv_carriers.lua")
	include("rpinv/sv_search.lua")
	include("rpinv/sv_quick.lua")
	include("rpinv/sv_ammo.lua")
	include("rpinv/sv_attach.lua")
	include("rpinv/sv_containers.lua")
	include("rpinv/sv_airdrop.lua")
	include("rpinv/sv_loot.lua")
	include("rpinv/sv_presets.lua")
	include("rpinv/sv_devtools.lua")
else
	for _, f in ipairs(client) do include(f) end
end
