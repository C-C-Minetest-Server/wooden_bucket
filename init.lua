-- Minetest 0.4 mod: bucket
-- See README.txt for licensing and other information.


-- New recipes added for the right bowl.
local eth = minetest.get_modpath("ethereal")
local farm = minetest.get_modpath("farming") and farming and farming.mod -- as in mobs_animal, cow.lua

-- ethereal uses recipe for farming:bowl if registered, see extra.lua.
if farm and minetest.registered_items["farming:bowl"] then

	minetest.clear_craft({ output = "farming:bowl" })

	minetest.register_craft({
		output = 'farming:bowl 4',
		recipe = {'bucket_wooden:bucket_empty'},
		type = 'shapeless',
	})

elseif eth and minetest.registered_items["ethereal:bowl"] then

	minetest.clear_craft({ output = "ethereal:bowl" })

	minetest.register_craft({
		output = 'ethereal:bowl 4',
		recipe = {'bucket_wooden:bucket_empty'},
		type = 'shapeless',
	})
end
-- End change

minetest.register_craft({
	output = 'bucket_wooden:bucket_empty 1',
	recipe = {
		{'group:wood', '', 'group:wood'},
		{'', 'group:wood', ''},
	}
})

minetest.register_craft({
	type = "fuel",
	recipe = "bucket_wooden:bucket_empty",
	burntime = 22,
})


bucket_wooden = {}

-- intllib
--------------------------------------------------------------------------------
-- Copied from TenPlus1 mod mobs:
local path = minetest.get_modpath(minetest.get_current_modname()) .. "/"

-- Check for translation method.
local S
if minetest.get_translator ~= nil then
	S = minetest.get_translator("bucket_wooden") -- 5.x translation function
else
	if minetest.get_modpath("intllib") then
		dofile(minetest.get_modpath("intllib") .. "/init.lua")
		if intllib.make_gettext_pair then
			gettext, ngettext = intllib.make_gettext_pair() -- new gettext method
		else
			gettext = intllib.Getter() -- old text file method
		end
		S = gettext
	else -- boilerplate function
		S = function(str, ...)
			local args = {...}
			return str:gsub("@%d+", function(match)
				return args[tonumber(match:sub(2))]
			end)
		end
	end
end
--------------------------------------------------------------------------------
bucket_wooden.intllib = S
--End change
bucket_wooden.liquids = {}

local function check_protection(pos, name, text)
	if minetest.is_protected(pos, name) then
		minetest.log("action", (name ~= "" and name or "A mod")
			.. " tried to " .. text
			.. " at protected position "
			.. minetest.pos_to_string(pos)
			.. " with a wooden bucket")
		minetest.record_protection_violation(pos, name)
		return true
	end
	return false
end

local function log_action(pos, name, action)
	minetest.log("action", (name ~= "" and name or "A mod")
		.. " " .. action .. " at " .. minetest.pos_to_string(pos) .. " with a wooden bucket")
end

-- Register a new liquid
--    source = name of the source node
--    flowing = name of the flowing node
--    itemname = name of the new bucket item (or nil if liquid is not takeable)
--    inventory_image = texture of the new bucket item (ignored if itemname == nil)
--    name = text description of the bucket item
--    groups = (optional) groups of the bucket item, for example {water_bucket = 1}
--    force_renew = (optional) bool. Force the liquid source to renew if it has a
--                  source neighbour, even if defined as 'liquid_renewable = false'.
--                  Needed to avoid creating holes in sloping rivers.
-- This function can be called from any mod (that depends on bucket).
function bucket_wooden.register_liquid(source, flowing, itemname, inventory_image, name,
		groups, force_renew)
	bucket_wooden.liquids[source] = {
		source = source,
		flowing = flowing,
		itemname = itemname,
		force_renew = force_renew,
	}
	bucket_wooden.liquids[flowing] = bucket_wooden.liquids[source]

	if itemname ~= nil then
		minetest.register_craftitem(itemname, {
			description = name,
			inventory_image = inventory_image,
			stack_max = 1,
			liquids_pointable = true,
			groups = groups,

			on_place = function(itemstack, user, pointed_thing)
				-- Must be pointing to node
				if pointed_thing.type ~= "node" then
					return
				end

				local node = minetest.get_node_or_nil(pointed_thing.under)
				local ndef = node and minetest.registered_nodes[node.name]

				-- Call on_rightclick if the pointed node defines it
				if ndef and ndef.on_rightclick and
						not (user and user:is_player() and
						user:get_player_control().sneak) then
					return ndef.on_rightclick(
						pointed_thing.under,
						node, user,
						itemstack)
				end

				local lpos

				-- Check if pointing to a buildable node
				if ndef and ndef.buildable_to then
					-- buildable; replace the node
					lpos = pointed_thing.under
				else
					-- not buildable to; place the liquid above
					-- check if the node above can be replaced

					lpos = pointed_thing.above
					node = minetest.get_node_or_nil(lpos)
					local above_ndef = node and minetest.registered_nodes[node.name]

					if not above_ndef or not above_ndef.buildable_to then
						-- do not remove the bucket with the liquid
						return itemstack
					end
				end

				local pname = user and user:get_player_name() or ""
				if check_protection(lpos, pname, "place "..source) then
					return
				end

				minetest.set_node(lpos, {name = source})
				log_action(lpos, pname, "placed " .. source)
				return ItemStack("bucket_wooden:bucket_empty")
			end
		})
	end
end

minetest.register_craftitem("bucket_wooden:bucket_empty", {
	description = S("Empty Wooden Bucket"),
	inventory_image = "bucket_wooden.png",
	stack_max = 99,
	liquids_pointable = true,
	on_use = function(itemstack, user, pointed_thing)
		if pointed_thing.type == "object" then
			pointed_thing.ref:punch(user, 1.0, { full_punch_interval=1.0 }, nil)
			return user:get_wielded_item()
		elseif pointed_thing.type ~= "node" then
			-- do nothing if it's neither object nor node
			return
		end
		-- Check if pointing to a liquid source
		local pos = pointed_thing.under
		local node = minetest.get_node(pointed_thing.under)
		local liquiddef = bucket_wooden.liquids[node.name]
		local item_count = user:get_wielded_item():get_count()

		if liquiddef ~= nil
		and liquiddef.itemname ~= nil
		and node.name == liquiddef.source then
			local pname = user:get_player_name()
			if check_protection(pos, pname, "take ".. node.name) then
				return
			end

			-- default set to return filled bucket
			local giving_back = liquiddef.itemname

			-- check if holding more than 1 empty bucket
			if item_count > 1 then

				-- if space in inventory add filled bucked, otherwise drop as item
				local inv = user:get_inventory()
				if inv:room_for_item("main", {name=liquiddef.itemname}) then
					inv:add_item("main", liquiddef.itemname)
				else
					local upos = user:get_pos()
					upos.y = math.floor(upos.y + 0.5)
					minetest.add_item(upos, liquiddef.itemname)
				end

				-- set to return empty buckets minus 1
				giving_back = "bucket_wooden:bucket_empty "..tostring(item_count-1)

			end

			-- force_renew requires a source neighbour
			local source_neighbor = false
			if liquiddef.force_renew then
				source_neighbor = minetest.find_node_near(pos, 1, liquiddef.source)
			end
			if source_neighbor and liquiddef.force_renew then
				log_action(pos, pname, "picked up " .. liquiddef.source .. " (force renewed)")
			else
				minetest.add_node(pos, {name = "air"})
				log_action(pos, pname, "picked up " .. liquiddef.source)
			end

			return ItemStack(giving_back)
		else
			-- non-liquid nodes will have their on_punch triggered
			local node_def = minetest.registered_nodes[node.name]
			if node_def then
				node_def.on_punch(pos, node, user, pointed_thing)
			end
			return user:get_wielded_item()
		end
	end,
})

bucket_wooden.register_liquid(
	"default:water_source",
	"default:water_flowing",
	"bucket_wooden:bucket_water",
	"bucket_wooden_water.png",
	S("Wooden Water Bucket"), -- Change: added Wooden
	{water_bucket_wooden = 1}
)

-- River water source is 'liquid_renewable = false' to avoid horizontal spread
-- of water sources in sloping rivers that can cause water to overflow
-- riverbanks and cause floods.
-- River water source is instead made renewable by the 'force renew' option
-- used here.

bucket_wooden.register_liquid(
	"default:river_water_source",
	"default:river_water_flowing",
	"bucket_wooden:bucket_river_water",
	"bucket_wooden_river_water.png",
	S("Wooden River Water Bucket"), -- Change: added Wooden
	{water_bucket_wooden = 1},
	true
)

