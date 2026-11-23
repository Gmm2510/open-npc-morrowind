--- Her look: race, face, hair and outfit, all from the game's own parts. Each companion (each name she goes by, as the
--- voice app picks) keeps her own look, in her settings. Morrowind can't change a person's race while the game runs, so
--- OpenNPC.esp has a copy of her for each race; picking another race swaps her for that copy, with everything that's hers.

local this = {}
local companion   -- (opennpc.companion, given at init)

local function log(fmt, ...) mwse.log("[Open NPC] " .. fmt, ...) end

this.RACES = { "Argonian", "Breton", "Dark Elf", "High Elf", "Imperial", "Khajiit", "Nord", "Orc", "Redguard", "Wood Elf" }

--- Her record for a race (the Imperial one is her first record, from before she had other races).
function this.recordFor(race)
	if race == "Imperial" then return "opennpc_companion" end
	return "opennpc_companion_" .. (race:lower():gsub("[^a-z]", ""))
end

--- Is this one of her records?
function this.isHerRecord(id)
	id = id and id:lower() or ""
	return id == "opennpc_companion" or id:sub(1, 18) == "opennpc_companion_"
end

--- The race of one of her records.
function this.raceOf(id)
	for _, race in ipairs(this.RACES) do
		if this.recordFor(race) == id:lower() then return race end
	end
	return "Imperial"
end

-- (each outfit from the game's own clothes and armor; no helmets, so her face shows)
this.OUTFITS = {
	{ id = "traveler", name = "Traveler", items = { "common_shirt_04_b", "common_pants_01", "netch_leather_boots", "netch_leather_cuirass" } },
	{ id = "scout", name = "Scout", items = { "common_shirt_02", "common_pants_02", "netch_leather_boiled_cuirass", "netch_leather_greaves",
		"netch_leather_boots", "netch_leather_pauldron_left", "netch_leather_pauldron_right", "netch_leather_gauntlet_left", "netch_leather_gauntlet_right" } },
	{ id = "warrior", name = "Warrior", items = { "common_shirt_01", "common_pants_01", "chitin cuirass", "chitin greaves", "chitin boots",
		"chitin pauldron - left", "chitin pauldron - right", "chitin guantlet - left", "chitin guantlet - right" } },
	{ id = "fine", name = "Fine clothes", items = { "expensive_shirt_02", "expensive_skirt_01", "expensive_shoes_01", "expensive_belt_01" } },
	{ id = "robe", name = "Robe", items = { "common_shirt_01", "common_pants_01", "expensive_robe_02", "common_shoes_02" } },
}

local function outfitById(id)
	for _, o in ipairs(this.OUTFITS) do if o.id == id then return o end end
	return this.OUTFITS[1]
end

local lookItems = {}
for _, o in ipairs(this.OUTFITS) do for _, it in ipairs(o.items) do lookItems[it:lower()] = true end end

-- (what each of her records carries from OpenNPC.esp besides the Traveler outfit; not carried over on a race swap)
local RECORD_ITEMS = { ["imperial shortsword"] = true }

this.DEFAULT = { race = "Imperial", head = "b_n_imperial_f_head_02", hair = "b_n_imperial_f_hair_01", outfit = "scout" }

-- ------------------------------------------------------------------ faces and hair

local parts = {}   -- (race -> { faces = {ids}, hair = {ids} }, the game's women's heads and hair that a player can pick)

--- The faces (or hair, with which = "hair") a woman of `race` can have, by id.
function this.partsFor(race, which)
	if not parts[race] then
		local faces, hair = {}, {}
		for bp in tes3.iterateObjects(tes3.objectType.bodyPart) do
			if bp.partType == tes3.activeBodyPartLayer.base and bp.female and bp.playable and not bp.vampiric and bp.raceName == race then
				if bp.part == tes3.partIndex.head then table.insert(faces, bp.id)
				elseif bp.part == tes3.partIndex.hair then table.insert(hair, bp.id) end
			end
		end
		table.sort(faces, function(a, b) return a:lower() < b:lower() end)
		table.sort(hair, function(a, b) return a:lower() < b:lower() end)
		parts[race] = { faces = faces, hair = hair }
	end
	return which == "hair" and parts[race].hair or parts[race].faces
end

local function has(list, id)
	for i, v in ipairs(list) do if v:lower() == (id or ""):lower() then return i end end
	return nil
end

-- ------------------------------------------------------------------ looks in her settings

--- The look for the companion called `name`: the saved one, made whole (an unknown race, face, hair or outfit falls back).
function this.lookFor(name)
	local saved = companion.config.looks and companion.config.looks[name] or {}
	local look = {}
	for k, v in pairs(this.DEFAULT) do look[k] = saved[k] or v end
	if not has(this.RACES, look.race) then look.race = this.DEFAULT.race end
	local faces, hair = this.partsFor(look.race), this.partsFor(look.race, "hair")
	if not has(faces, look.head) then look.head = faces[1] end
	if not has(hair, look.hair) then look.hair = hair[1] end
	look.outfit = outfitById(look.outfit).id
	return look
end

--- Saves the look for `name` (nil: back to the default).
function this.setLook(name, look)
	companion.config.looks = companion.config.looks or {}
	companion.config.looks[name] = look
	mwse.saveConfig("Open NPC", companion.config)
end

--- Every companion name with a look of her own, plus the one she goes by now, sorted.
function this.names()
	local seen, out = {}, {}
	local now = companion.shownName()
	for name in pairs(companion.config.looks or {}) do if not seen[name] then seen[name] = true table.insert(out, name) end end
	if not seen[now] then table.insert(out, now) end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end

-- ------------------------------------------------------------------ putting it on her

--- Puts the outfit on her: its pieces added and worn, other outfits' pieces taken away. (Beast races can't wear boots;
--- the game leaves those in her pack.)
function this.dress(r, id)
	local outfit = outfitById(id)
	local wanted = {}
	for _, it in ipairs(outfit.items) do wanted[it:lower()] = true end
	for it in pairs(lookItems) do
		if not wanted[it] then
			local n = tes3.getItemCount({ reference = r, item = it })
			if n > 0 then tes3.removeItem({ reference = r, item = it, count = n, playSound = false }) end
		end
	end
	for _, it in ipairs(outfit.items) do
		if tes3.getItemCount({ reference = r, item = it }) < 1 then tes3.addItem({ reference = r, item = it, count = 1, playSound = false }) end
		if r.mobile then r.mobile:equip({ item = it }) end
	end
end

--- Swaps her for her copy of another race, where she stands, with her name, level-ups, what she was told to do and
--- what she carries.
function this.swap(old, race)
	local id = this.recordFor(race)
	if not tes3.getObject(id) then log("no record %s in OpenNPC.esp", id) return old end
	local carry = {}
	for _, stack in pairs(old.object.inventory) do
		local item = stack.object.id:lower()
		if not lookItems[item] and not RECORD_ITEMS[item] then table.insert(carry, { item = stack.object, count = stack.count }) end
	end
	local data = json.decode(json.encode(old.data.opennpc or {}))
	local new = tes3.createReference({ object = id, position = old.position:copy(), orientation = old.orientation:copy(), cell = old.cell })
	new.data.opennpc = data
	for _, c in ipairs(carry) do tes3.addItem({ reference = new, item = c.item, count = c.count, playSound = false }) end
	log("now a %s (was %s)", race, this.raceOf(old.baseObject.id))
	old:disable()
	old:delete()
	companion.adopt(new)
	return new
end

--- Puts the look of the companion she is now on her: race, face, hair and outfit.
function this.apply(r)
	r = r or companion.her()
	if not r then return nil end
	local look = this.lookFor(companion.shownName())
	local swapped = false
	if r.baseObject.id:lower() ~= this.recordFor(look.race) then r, swapped = this.swap(r, look.race), true end
	local head, hair = tes3.getObject(look.head), tes3.getObject(look.hair)
	if head then r.baseObject.head = head end
	if hair then r.baseObject.hair = hair end
	this.dress(r, look.outfit)
	r:updateEquipment()
	-- (a new copy, or one not built yet, can't put things on until the game has built her: dressed again then. While a
	-- menu is open that's when it closes.)
	if swapped or not r.mobile then
		companion.later(r, function(x)
			if x.mobile then
				this.dress(x, look.outfit)
				x:updateEquipment()
			end
		end)
	end
	return r
end

--- In words, for the log and the tests.
function this.describe(r)
	r = r or companion.her()
	if not r then return "she isn't here" end
	local npc = r.baseObject
	local worn = {}
	for _, stack in pairs(r.object.inventory) do
		if lookItems[stack.object.id:lower()] and r.object:hasItemEquipped(stack.object) then table.insert(worn, stack.object.id) end
	end
	table.sort(worn)
	return string.format("%s, face %s, hair %s, wearing %s", npc.race.name, npc.head and npc.head.id or "none", npc.hair and npc.hair.id or "none", table.concat(worn, ", "))
end

function this.init(c) companion = c end

return this
