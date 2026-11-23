--- Her look menu, in Esc > Mod Config > Open NPC: race, face, hair and outfit, for each companion she goes by.
--- Changes are saved at once and put on her right away when she's in the game you're playing.

local look = require("opennpc.look")
local companion = require("opennpc.companion")

local this = {}
local editing   -- (the companion whose look is on the page)
local values = {}   -- (key -> the label showing that line's value)
local page

--- The next (step 1) or previous (step -1) of `list` after `current`, and its place in the list (step 0: where it is).
local function cycle(list, current, step)
	if #list == 0 then return nil, 0 end
	local i = 1
	for k, v in ipairs(list) do if v:lower() == (current or ""):lower() then i = k end end
	i = ((i - 1 + step) % #list) + 1
	return list[i], i
end

local function playing() return not tes3.onMainMenu() and companion.her() ~= nil end

local function outfitName(id)
	for _, o in ipairs(look.OUTFITS) do if o.id == id then return o.name end end
	return id
end

local function outfitIds()
	local ids = {}
	for _, o in ipairs(look.OUTFITS) do table.insert(ids, o.id) end
	return ids
end

--- Shows the look of the companion on the page.
local function refresh()
	local cur = look.lookFor(editing)
	local faces, hair = look.partsFor(cur.race), look.partsFor(cur.race, "hair")
	local _, fi = cycle(faces, cur.head, 0)
	local _, hi = cycle(hair, cur.hair, 0)
	values.Companion.text = editing
	values.Race.text = cur.race
	values.Face.text = string.format("%d of %d", fi, #faces)
	values.Hair.text = string.format("%d of %d", hi, #hair)
	values.Outfit.text = outfitName(cur.outfit)
	if page then page:getTopLevelMenu():updateLayout() end
end

--- Saves a change to the companion on the page, puts it on her if that's who she is now, and shows it.
local function change(fn)
	local cur = look.lookFor(editing)
	fn(cur)
	look.setLook(editing, cur)
	if playing() and editing == companion.shownName() then look.apply() end
	refresh()
end

--- One line: a name, a "<" button, the value, a ">" button. The buttons get ids (OpenNPC:<key>_prev / _next).
local function row(box, key, onStep)
	local line = box:createBlock({})
	line.flowDirection = "left_to_right"
	line.autoHeight = true
	line.widthProportional = 1.0
	line.borderTop = 8
	local name = line:createLabel({ text = key })
	name.minWidth = 120
	name.borderTop = 4
	local prev = line:createButton({ id = "OpenNPC:" .. key .. "_prev", text = "<" })
	prev:register("mouseClick", function() onStep(-1) end)
	local shown = line:createLabel({ id = "OpenNPC:" .. key .. "_value", text = "" })
	shown.minWidth = 240
	shown.borderTop = 4
	shown.borderLeft = 10
	values[key] = shown
	local nxt = line:createButton({ id = "OpenNPC:" .. key .. "_next", text = ">" })
	nxt:register("mouseClick", function() onStep(1) end)
end

--- Builds the page in `parent` (the Mod Config menu's panel, or any element).
function this.build(parent)
	page = parent
	editing = companion.shownName()   -- (it opens on the companion she is now)
	local box = parent:createThinBorder({})
	box.flowDirection = "top_to_bottom"
	box.widthProportional = 1.0
	box.heightProportional = 1.0
	box.paddingAllSides = 12

	local header = box:createLabel({ text = "Her look" })
	header.color = tes3ui.getPalette("header_color")
	local about = box:createLabel({ text = "Each companion from your voice app keeps her own look. She's " .. editing .. " right now." })
	about.wrapText = true
	about.widthProportional = 1.0
	about.borderTop = 6

	row(box, "Companion", function(step) editing = cycle(look.names(), editing, step) refresh() end)
	row(box, "Race", function(step) change(function(cur)
		cur.race = cycle(look.RACES, cur.race, step)
		cur.head, cur.hair = nil, nil   -- (that race's first face and hair)
	end) end)
	row(box, "Face", function(step) change(function(cur) cur.head = cycle(look.partsFor(cur.race), cur.head, step) end) end)
	row(box, "Hair", function(step) change(function(cur) cur.hair = cycle(look.partsFor(cur.race, "hair"), cur.hair, step) end) end)
	row(box, "Outfit", function(step) change(function(cur) cur.outfit = cycle(outfitIds(), cur.outfit, step) end) end)

	local reset = box:createButton({ id = "OpenNPC:Default", text = "Back to the default look" })
	reset.borderTop = 14
	reset:register("mouseClick", function()
		look.setLook(editing, nil)
		if playing() and editing == companion.shownName() then look.apply() end
		refresh()
	end)

	local note = box:createLabel({ text = playing() and "She changes as you pick. Close the menu to see her."
		or "She changes the next time you load a game." })
	note.wrapText = true
	note.widthProportional = 1.0
	note.borderTop = 10

	refresh()
end

function this.register()
	mwse.registerModConfig("Open NPC", { onCreate = function(parent) this.build(parent) end })
end

return this
