-- In-game tests for Open NPC (only on a test copy of the game; runs only when Data Files\MWSE\opennpc_test.run exists).
-- Starts a new game, skips making a character, checks each thing she should do, writes the results next to the run file
-- and quits the game.

local RUN_FLAG = "Data Files\\MWSE\\opennpc_test.run"
local RESULTS = "Data Files\\MWSE\\opennpc_test_results.txt"

local function exists(p) local f = io.open(p, "r") if f then f:close() return true end return false end
if not exists(RUN_FLAG) then return end

-- (with Data Files\MWSE\opennpc_test.save holding a save's file name, the run starts from that save instead of a new game)
local FROM_SAVE = nil
do
	local f = io.open("Data Files\\MWSE\\opennpc_test.save", "r")
	if f then FROM_SAVE = (f:read("*l") or ""):gsub("%s+$", "") f:close() if FROM_SAVE == "" then FROM_SAVE = nil end end
end

local companion = require("opennpc.companion")
local results, lines = {}, {}

local function say(fmt, ...)
	local s = string.format(fmt, ...)
	mwse.log("[Open NPC test] %s", s)
	table.insert(lines, s)
end

local function check(name, ok, detail)
	table.insert(results, { name = name, ok = ok })
	say("%s %s: %s", ok and "PASS" or "FAIL", name, detail or "")
end

local function finish()
	local passed = 0
	for _, r in ipairs(results) do if r.ok then passed = passed + 1 end end
	say("DONE %d of %d passed", passed, #results)
	local f = io.open(RESULTS, "w")
	f:write(table.concat(lines, "\n") .. "\n")
	f:close()
	timer.start({ type = timer.real, duration = 1, callback = function() os.exit(0) end })
end

-- ------------------------------------------------------------------ helpers

local function her() return companion.her() end
local function dist(r) return r.position:distance(tes3.player.position) end
local function sameCell(r) return r.cell == tes3.player.cell or (not r.cell.isInterior and not tes3.player.cell.isInterior) end

--- Calls `test()` every half second until it returns true or `seconds` pass, then `after(ok)`.
local function waitFor(seconds, test, after)
	local left = seconds * 2
	timer.start({ type = timer.simulate, duration = 0.5, iterations = left, persist = false, callback = function(e)
		local ok, value = pcall(test)
		if ok and value then e.timer:cancel() after(true) return end
		left = left - 1
		if left <= 0 then after(false) end
	end })
end

local function later(seconds, fn) timer.start({ type = timer.simulate, duration = seconds, persist = false, callback = fn }) end

-- Places to move him to (door spots from Morrowind.esm). Moving him straight there, not with the console's coc: coc purges
-- textures and redraws the map, which crashed the renderer in a background window.
local PLACES = {
	["Balmora"] = { cell = { -3, -2 }, position = { -21774.1, -12078.0, 619.6 }, orientation = { 0, 0, 4.7 } },
	["Balmora, Eight Plates"] = { cell = "Balmora, Eight Plates", position = { -91.8, -289.7, -128.0 }, orientation = { 0, 0, 1.6 } },
	["Ald'ruhn"] = { cell = { -2, 6 }, position = { -14372.0, 55861.4, 2445.9 }, orientation = { 0, 0, 2.7 } },
	-- (the Razor Hole's street door: 820 units from the Eight Plates door, same street, same height)
	["Balmora, by the Razor Hole"] = { cell = { -3, -2 }, position = { -22592.7, -12122.1, 643.5 }, orientation = { 0, 0, 1.57 } },
	-- (45% of the way from the Eight Plates door to the Razor Hole door: about 370 units down the same street)
	["Balmora, down the street"] = { cell = { -3, -2 }, position = { -22142.4, -12097.8, 630.4 }, orientation = { 0, 0, 1.57 } },
}

--- Moves him (not her: that's her job) to one of PLACES. Within the outdoor cell he's already in, the move is forced as
--- a cell change (setting his position, or a plain same-cell positionCell, didn't stick: the game put him back).
local function coc(name)
	local p = PLACES[name]
	local target = tes3vector3.new(p.position[1], p.position[2], p.position[3])
	local here = tes3.player.cell
	local sameOutdoor = type(p.cell) == "table" and not here.isInterior and here.gridX == p.cell[1] and here.gridY == p.cell[2]
	tes3.positionCell({ reference = tes3.mobilePlayer, cell = p.cell, position = p.position, orientation = p.orientation,
		teleportCompanions = false, forceCellChange = sameOutdoor })
	later(1, function()
		say("moved him to %s%s: he is %.0f units from that spot", name, sameOutdoor and " (same cell, forced)" or "", tes3.player.position:distance(target))
	end)
end

--- A spot `d` units from the player where she can stand, along the first clear direction.
local function awaySpot(d) return companion.spotNear(tes3.player, d, { tes3.player, her() }) end

--- A clear spot at least `min` units from him (16 directions, farthest first), or nil if there's no room for it here.
local function farSpot(min)
	local ignore = { tes3.player, her() }
	for _, d in ipairs({ 900, 750, 600, min }) do
		for k = 0, 15 do
			local a = math.rad(k * 22.5)
			local dir = tes3vector3.new(math.sin(a), math.cos(a), 0)
			local s = companion.clearSpot(tes3.player.position, dir, d, ignore)
			if s and s:distance(tes3.player.position) >= min then return s end
		end
	end
	return nil
end

--- Puts her somewhere in his cell (the way the game moves people, so her AI keeps working).
local function moveHer(r, spot) tes3.positionCell({ reference = r, cell = tes3.player.cell, position = spot, forceCellChange = true }) end

local function realLater(seconds, fn) timer.start({ type = timer.real, duration = seconds, callback = fn }) end

--- Like waitFor, on the real clock (it keeps running while menus are open).
local function waitReal(seconds, test, after)
	local left = seconds * 2
	timer.start({ type = timer.real, duration = 0.5, iterations = left, callback = function(e)
		local ok, value = pcall(test)
		if ok and value then e.timer:cancel() after(true) return end
		left = left - 1
		if left <= 0 then after(false) end
	end })
end

--- The height of the first thing under (x, y), looking down from `fromZ` (high up if not given), or nil.
local function groundAt(x, y, fromZ)
	local hit = tes3.rayTest({ position = tes3vector3.new(x, y, fromZ or 20000), direction = tes3vector3.new(0, 0, -1), maxDistance = 40000, ignore = { tes3.player, her() } })
	return hit and hit.intersection and hit.intersection.z or nil
end

local function across(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

--- Moves him anywhere outdoors, as a cell change, without taking her along (getting there is her job). The game drops
--- him onto whatever is under the spot; with `exact` he's then set to its height (up in the air, under water).
local function putHim(pos, rot, exact)
	tes3.positionCell({ reference = tes3.mobilePlayer, position = pos, orientation = rot and tes3vector3.new(0, 0, rot) or tes3.player.orientation,
		teleportCompanions = false, forceCellChange = true })
	if exact then companion.liftTo(tes3.player, pos) end
end

--- A spell effect on him (levitation, water breathing) for `seconds`.
local function effectOn(id, seconds)
	tes3.applyMagicSource({ reference = tes3.player, name = "Open NPC test", bypassResistances = true, effects = { { id = id, min = 20, max = 20, duration = seconds } } })
end

--- A flat place at least `rise` higher than `base` (a roof, a ledge) within `range` of it, closest first, or nil.
local function highPlace(base, rise, range)
	for rad = 300, range, 200 do
		for k = 0, 15 do
			local a = math.rad(k * 22.5)
			local x, y = base.x + rad * math.sin(a), base.y + rad * math.cos(a)
			local g = groundAt(x, y)
			if g and g - base.z > rise and g - base.z < 1500 then
				local flat = true
				for _, o in ipairs({ { 70, 0 }, { -70, 0 }, { 0, 70 }, { 0, -70 } }) do
					local h = groundAt(x + o[1], y + o[2])
					if not h or math.abs(h - g) > 25 then flat = false break end
				end
				if flat then return tes3vector3.new(x, y, g + 4) end
			end
		end
	end
	return nil
end

--- A spot over open water at least `depth` deep, `min` to `range` from him, closest first, or nil.
local function deepWater(depth, min, range)
	local p = tes3.player.position
	for rad = min, range, 150 do
		for k = 0, 15 do
			local a = math.rad(k * 22.5)
			local x, y = p.x + rad * math.sin(a), p.y + rad * math.cos(a)
			local g = groundAt(x, y, 3000)
			if g and g < -depth then
				local open = true
				for _, o in ipairs({ { 150, 0 }, { -150, 0 }, { 0, 150 }, { 0, -150 } }) do
					local h = groundAt(x + o[1], y + o[2], 3000)
					if not h or h > -depth + 100 then open = false break end
				end
				if open then return tes3vector3.new(x, y, g) end
			end
		end
	end
	return nil
end

-- ------------------------------------------------------------------ travel (silt striders and boats, through the game's own menus)

-- (the people who take you, and where they stand, from Morrowind.esm)
local TRAVEL = {
	["Ald'ruhn"] = { id = "navam veran", position = { -17654.6, 54770.1, 2774.7 }, rot = 2.20 },
	["Balmora"] = { id = "selvil sareloth", position = { -21226.6, -18292.2, 1097.3 }, rot = 0.00 },
	["Vivec, Foreign Quarter"] = { id = "ano andaram", position = { 35692.9, -74335.9, 101.2 }, rot = 3.14 },
}

--- A spot 130 units in front of a TRAVEL person, facing them.
local function besideTravel(t)
	local x = t.position[1] + 130 * math.sin(t.rot)
	local y = t.position[2] + 130 * math.cos(t.rot)
	local g = groundAt(x, y, t.position[3] + 150)
	return tes3vector3.new(x, y, (g or t.position[3]) + 4), t.rot + math.pi
end

local travelWith = nil   -- (who the game said would go along, at the last travel price list)
event.register(tes3.event.calcTravelPrice, function(e)
	local names = {}
	for _, m in ipairs(e.companions or {}) do table.insert(names, m.reference.object.name) end
	travelWith = #names > 0 and table.concat(names, ", ") or "nobody"
end)

local function dumpMenu(el, depth, out)
	depth, out = depth or 0, out or {}
	if #out < 50 then
		table.insert(out, string.rep(".", depth) .. tostring(el.name) .. ((el.text and el.text ~= "") and (" '" .. el.text .. "'") or ""))
		for _, c in ipairs(el.children or {}) do dumpMenu(c, depth + 1, out) end
	end
	return out
end

local function findText(el, text, out)
	out = out or {}
	if el.text and el.text:find(text, 1, true) then table.insert(out, el) end
	for _, c in ipairs(el.children or {}) do findText(c, text, out) end
	return out
end

local function closeMenus()
	local dlg = tes3ui.findMenu("MenuDialog")
	local bye = dlg and dlg:findChild("MenuDialog_button_bye")
	if bye then bye:triggerEvent("mouseClick") end
	tes3ui.leaveMenuMode()
end

--- Talks to the TRAVEL person at `from`, opens their travel list, picks the first of `places` on it, and calls
--- after(ok, detail) once he has arrived somewhere else. before() runs just before the talk opens.
local function travel(from, places, before, after)
	local t = TRAVEL[from]
	local who = tes3.getReference(t.id)
	if not who then after(false, "can't find " .. t.id) return end
	tes3.addItem({ reference = tes3.player, item = "gold_001", count = 1000 })
	travelWith = nil
	if before then before() end
	local cellBefore = tes3.player.cell
	if not tes3.showDialogueMenu({ reference = who }) then after(false, "the talk with " .. t.id .. " didn't open") return end
	realLater(1.5, function()
		local dlg = tes3ui.findMenu("MenuDialog")
		local button = dlg and dlg:findChild("MenuDialog_service_travel")
		if not button or not button.visible then
			say("the talk: %s", dlg and table.concat(dumpMenu(dlg), " / ") or "none")
			closeMenus()
			after(false, "no travel in the talk with " .. t.id)
			return
		end
		button:triggerEvent("mouseClick")
		realLater(1.5, function()
			local menu = tes3ui.findMenu("MenuServiceTravel")
			if not menu then closeMenus() after(false, "the travel list didn't open") return end
			say("the travel list: %s", table.concat(dumpMenu(menu), " / "))
			local pick
			for _, place in ipairs(places) do pick = pick or findText(menu, place)[1] end
			if not pick then closeMenus() after(false, "none of " .. table.concat(places, ", ") .. " on the list") return end
			say("picking '%s' (the game takes along: %s)", pick.text, tostring(travelWith))
			pick:triggerEvent("mouseClick")
			waitReal(40, function() return not tes3.menuMode() and tes3.player.cell ~= cellBefore end, function(ok)
				after(ok, ok and ("he's in " .. tes3.player.cell.id) or ("he's still in " .. tes3.player.cell.id))
			end)
		end)
	end)
end

local function copies()
	local n = 0
	for _, cell in ipairs(tes3.getActiveCells()) do
		for ref in cell:iterateReferences(tes3.objectType.npc) do
			if require("opennpc.look").isHerRecord(ref.baseObject.id) and not ref.deleted and not ref.disabled then n = n + 1 end
		end
	end
	return n
end

-- ------------------------------------------------------------------ the stand-in AI (tools/standin_ai.js on port 41799)

local STANDIN = "http://127.0.0.1:41799"
local socketHttp = require("socket.http")

--- Tells the stand-in what happens next (a call, his words, her name in the app, its next reply). Local and instant.
local function control(q)
	local body = socketHttp.request(STANDIN .. "/control?" .. q)
	return body and json.decode(body)
end

--- The last question she sent, decoded, and how many she has sent.
local function lastQuestion()
	local body = socketHttp.request(STANDIN .. "/last")
	local j = body and json.decode(body) or {}
	return j.last or {}, j.asks or 0
end

local function asks() local _, n = lastQuestion() return n end

local function questionText(q)
	local t = {}
	for _, m in ipairs(q.messages or {}) do table.insert(t, tostring(m.content)) end
	return table.concat(t, " | ")
end

-- ------------------------------------------------------------------ when she gets hurt (logged, with what did it and where)

local hurts = {}
event.register(tes3.event.damaged, function(e)
	local r = her()
	if not r or e.reference ~= r or (e.damage or 0) <= 0 then return end   -- (under water the game sends a 0 every frame)
	local how = tostring(e.source)
	for k, v in pairs(tes3.damageSource) do if v == e.source then how = k end end
	local who = e.attackerReference and (" from " .. e.attackerReference.object.name) or ""
	local s = string.format("%.1f by %s%s in %s at (%.0f, %.0f, %.0f)", e.damage or 0, how, who, r.cell.id, r.position.x, r.position.y, r.position.z)
	table.insert(hurts, { how = how, text = s })
	say("she was hurt: %s", s)
end)

--- Her health (base), strength and long blade, for comparing.
local function stats(r)
	local m = r.mobile
	return string.format("health %.0f, strength %.0f, long blade %.0f", m.health.base, m.strength.base, m.longBlade.base)
end
local leveled   -- (her stats right after she leveled up)

-- ------------------------------------------------------------------ the steps

local steps = {}
local function nextStep()
	local s = table.remove(steps, 1)
	if s then s() else finish() end
end

table.insert(steps, function()
	waitFor(10, function() local r = her() return r and sameCell(r) and dist(r) < 400 end, function(ok)
		local r = her()
		check("shows up", ok, r and string.format("%s, %.0f units from him in %s", r.object.name, dist(r), r.cell.id) or "not in the world")
		check("her name", r and r.object.name == companion.shownName(), r and r.object.name or "")
		nextStep()
	end)
end)

table.insert(steps, function()
	-- (the stand-in app gives her the name Yui at its wait door)
	waitFor(10, function() local r = her() return r and r.object.name == "Yui" end, function(ok)
		local r = her()
		check("the app names her", ok, r and r.object.name or "missing")
		nextStep()
	end)
end)

table.insert(steps, function()
	local before = asks()
	control("reply=nothing&call=1")
	waitFor(10, function() return asks() > before end, function(ok)
		local q = lastQuestion()
		check("a call starts and she's asked", ok and questionText(q):find("is with you now", 1, true) ~= nil, string.format("%d new question(s)", asks() - before))
		nextStep()
	end)
end)

table.insert(steps, function()
	local r = her()
	control("reply=wait&words=%2B1")
	waitFor(10, function() return companion.state(r).mode == "wait" end, function(ok)
		check("his words make her wait", ok, "mode " .. companion.state(r).mode)
		nextStep()
	end)
end)

table.insert(steps, function()
	local r = her()
	control("reply=follow&words=%2B1")
	waitFor(10, function() return companion.state(r).mode == "follow" end, function(ok)
		check("his words make her follow", ok, "mode " .. companion.state(r).mode)
		local q = lastQuestion()
		local text = questionText(q)
		local sys = q.messages and q.messages[1] and tostring(q.messages[1].content) or ""
		local enum = q.tools and q.tools[1] and q.tools[1]["function"] and q.tools[1]["function"].parameters.properties.action.enum or {}
		check("the AI hears who, where and what she can do",
			sys:find("You control Yui", 1, true) and sys:find("Morrowind", 1, true) and text:find(tes3.player.cell.displayName, 1, true)
				and (text:find("following", 1, true) or text:find("waiting", 1, true)) and #enum >= 5,
			string.format("system says Yui+Morrowind: %s; where: %s; actions: %s", tostring(sys:find("You control Yui", 1, true) ~= nil and sys:find("Morrowind", 1, true) ~= nil),
				tostring(text:find(tes3.player.cell.displayName, 1, true) ~= nil), table.concat(enum, ",")))
		nextStep()
	end)
end)

table.insert(steps, function()
	tes3.runLegacyScript({ command = "tgm" })
	local crab = tes3.createReference({ object = "mudcrab", position = companion.spotNear(tes3.player, 300, { tes3.player, her() }), orientation = tes3.player.orientation, cell = tes3.player.cell })
	local r = her()
	later(1, function()
		control("reply=fight&words=%2B1")
		waitFor(15, function() return crab.mobile == nil or crab.mobile.isDead or (r.mobile.actionData.target == crab.mobile) end, function(ok)
			check("his words make her fight", ok, ok and "she went for the mudcrab" or "she didn't")
			waitFor(40, function() return crab.mobile == nil or crab.mobile.isDead end, function()
				tes3.runLegacyScript({ command = "tgm" })
				control("reply=nothing&call=0")
				nextStep()
			end)
		end)
	end)
end)

local function parked()
	local body = socketHttp.request(STANDIN .. "/parked")
	local j = body and json.decode(body) or {}
	return (j.parked or 0) > 0
end

table.insert(steps, function()
	-- (the new pick while her door question is waiting, as when a person picks in the app; set in the moment between two
	-- questions, the next one would only see it when its wait ran out)
	waitFor(10, parked, function()
	control("name=Mila")
	waitFor(6, function() local r = her() return r and r.object.name == "Mila" end, function(ok)
		local r = her()
		check("a new pick in the app renames her", ok, r and r.object.name or "missing")
		nextStep()
	end)
	end)
end)

table.insert(steps, function()
	-- (a short gap, as when he walks ahead: she has to close it on foot, no coming over)
	local r = her()
	local cameBefore = companion.cameOver or 0
	coc("Balmora, down the street")
	later(1, function()
		local start = dist(r)
		waitFor(25, function() return dist(r) < 200 end, function(ok)
			local came = (companion.cameOver or 0) - cameBefore
			check("walks after him", ok and came == 0 and start >= 250, string.format("started %.0f away, now %.0f, came over %d times", start, dist(r), came))
			coc("Balmora")   -- (back to the Eight Plates door for the next check)
			later(4, nextStep)
		end)
	end)
end)

table.insert(steps, function()
	-- (he walks off down the street, the way a player does; she has to walk after him: 820 units to within 250)
	local r = her()
	coc("Balmora, by the Razor Hole")
	later(1, function()
		local start = dist(r)
		local cameBefore = companion.cameOver or 0
		local walkedTo = start
		waitFor(30, function()
			if (companion.cameOver or 0) == cameBefore then walkedTo = math.min(walkedTo, dist(r)) end
			return dist(r) < 250
		end, function(ok)
			local came = (companion.cameOver or 0) - cameBefore
			check("follows (a long gap)", ok and start >= 600, string.format("started %.0f away, now %.0f; she walked to %.0f%s", start, dist(r), walkedTo,
				came > 0 and ", then came over when stuck" or ", all the way on foot"))
			nextStep()
		end)
	end)
end)

table.insert(steps, function()
	local r = her()
	companion.wait(r)
	coc("Balmora")   -- (back to the Eight Plates door, 820 units off)
	local spot = r.position:copy()
	later(8, function()
		local moved = r.position:distance(spot)
		local waitedAt = dist(r)
		check("waits when told", moved < 80 and waitedAt > 250, string.format("moved %.0f, %.0f from him", moved, waitedAt))
		companion.follow(r)
		waitFor(30, function() return dist(r) < 250 end, function(ok)
			check("follows again", ok, string.format("from %.0f away to %.0f; %s", waitedAt, dist(r), companion.describeAI(r)))
			nextStep()
		end)
	end)
end)

table.insert(steps, function()
	coc("Balmora, Eight Plates")
	waitFor(6, function() local r = her() return r and r.cell == tes3.player.cell and dist(r) < 600 end, function(ok)
		local r = her()
		check("comes through a door", ok, r and string.format("she's in %s, %.0f away", r.cell.id, dist(r)) or "missing")
		nextStep()
	end)
end)

table.insert(steps, function()
	-- (following him back out, then in again for the next check)
	coc("Balmora")
	waitFor(6, function() local r = her() return r and not r.cell.isInterior and dist(r) < 600 end, function(ok)
		local r = her()
		check("comes back out a door with him", ok, r and string.format("she's in %s, %.0f away", r.cell.id, dist(r)) or "missing")
		coc("Balmora, Eight Plates")
		waitFor(6, function() local r2 = her() return r2 and r2.cell == tes3.player.cell and dist(r2) < 600 end, function() nextStep() end)
	end)
end)

table.insert(steps, function()
	local r = her()
	companion.wait(r)
	local waitedIn = r.cell.id
	coc("Balmora")
	later(4, function()
		local r2 = her()
		check("stays behind when waiting", r2 and r2.cell.id == waitedIn, r2 and ("she's in " .. r2.cell.id) or "missing")
		companion.follow(r2)
		waitFor(6, function() local r3 = her() return r3 and sameCell(r3) and dist(r3) < 600 end, function(ok)
			local r3 = her()
			check("comes when called from another place", ok, r3 and string.format("she's in %s, %.0f away", r3.cell.id, dist(r3)) or "missing")
			nextStep()
		end)
	end)
end)

table.insert(steps, function()
	coc("Ald'ruhn")
	waitFor(6, function() local r = her() return r and sameCell(r) and dist(r) < 600 end, function(ok)
		local r = her()
		check("comes along on a long jump (like Recall)", ok, r and string.format("she's in %s, %.0f away", r.cell.id, dist(r)) or "missing")
		nextStep()
	end)
end)

table.insert(steps, function()
	tes3.runLegacyScript({ command = "tgm" })   -- (he can't die; the test checks that she does the fighting)
	local crab = tes3.createReference({ object = "mudcrab", position = companion.spotNear(tes3.player, 260, { tes3.player, her() }), orientation = tes3.player.orientation, cell = tes3.player.cell })
	later(0.5, function()
		crab.mobile:startCombat(tes3.mobilePlayer)
		waitFor(45, function() return crab.mobile == nil or crab.mobile.isDead end, function(ok)
			check("fights what attacks him", ok, ok and "the mudcrab is dead (he never swung)" or "the mudcrab is still alive")
			tes3.runLegacyScript({ command = "tgm" })
			nextStep()
		end)
	end)
end)

table.insert(steps, function()
	local r = her()
	local hp = r.mobile.health.base
	local before = companion.state(r).level
	local newLevel = tes3.player.object.level + 1
	tes3.runLegacyScript({ command = string.format("player->SetLevel %d", newLevel) })   -- (the level can't be set from Lua directly)
	event.trigger(tes3.event.levelUp, { level = newLevel })
	later(1, function()
		local st = companion.state(r)
		leveled = stats(r)
		check("levels up with him", st.level == tes3.player.object.level and r.mobile.health.base > hp,
			string.format("her level %d to %d, health %.0f to %.0f", before, st.level, hp, r.mobile.health.base))
		nextStep()
	end)
end)

-- (levitating: he goes up where she can't; she must stay on the ground, not be put up in the air and fall)
table.insert(steps, function()
	local r = her()
	tes3.runLegacyScript({ command = "tgm" })   -- (he can't get hurt in the next checks: flying, dropping, swimming; off again before the save)
	effectOn(tes3.effect.levitate, 300)
	waitFor(10, function() return dist(r) < 300 end, function()
		local start, hp, came = r.position:copy(), r.mobile.health.current, companion.cameOver or 0
		local p = tes3.player.position
		putHim(tes3vector3.new(p.x, p.y, p.z + 1500), nil, true)
		later(9, function()
			local up = tes3.player.position.z - start.z
			local moved = math.abs(r.position.z - start.z)
			check("stays on the ground when he levitates up", up > 1000 and moved < 150 and not r.mobile.isFalling and r.mobile.health.current >= hp - 1,
				string.format("he is %.0f up (levitating: %s); her height changed %.0f; health %.0f to %.0f; came over %d times",
					up, tostring(tes3.mobilePlayer.levitate > 0), moved, hp, r.mobile.health.current, (companion.cameOver or 0) - came))
			nextStep()
		end)
	end)
end)

table.insert(steps, function()
	-- (he flies off, 3200 units, 800 over the ground: she comes along on the ground under him)
	local r = her()
	local hp, came = r.mobile.health.current, companion.cameOver or 0
	local p, target = tes3.player.position, nil
	for k = 0, 7 do
		local a = math.rad(k * 45)
		local x, y = p.x + 3200 * math.sin(a), p.y + 3200 * math.cos(a)
		local g = groundAt(x, y)
		if g and g > 50 then target = tes3vector3.new(x, y, g + 800) break end
	end
	if not target then check("comes along under him when he flies off", false, "no land 3200 away from here") nextStep() return end
	putHim(target, nil, true)
	waitFor(10, function() return across(r.position, tes3.player.position) < 900 end, function(ok)
		local z1 = r.position.z
		later(3, function()
			local fell = z1 - r.position.z
			local g = groundAt(r.position.x, r.position.y, r.position.z + 60)
			local onGround = g ~= nil and math.abs(r.position.z - g) < 60
			check("comes along under him when he flies off", ok and fell < 50 and onGround and r.mobile.health.current >= hp - 1,
				string.format("%.0f across from him, %.0f under him; on the ground: %s; dropped %.0f in 3 s; health %.0f to %.0f; came over %d times",
					across(r.position, tes3.player.position), tes3.player.position.z - r.position.z, tostring(onGround), fell, hp, r.mobile.health.current,
					(companion.cameOver or 0) - came))
			nextStep()
		end)
	end)
end)

table.insert(steps, function()
	-- (he lands up high where she can't walk, as on a roof or a tower floor he levitated to: she gets up there with him)
	local r = her()
	local base = r.position:copy()
	local spot = highPlace(base, 350, 2500)
	if not spot then
		tes3.removeEffects({ reference = tes3.player, effect = tes3.effect.levitate })
		check("gets up to him on a high place he flew to", false, "no high flat place near here")
		nextStep()
		return
	end
	local came = companion.cameOver or 0
	putHim(spot)
	tes3.removeEffects({ reference = tes3.player, effect = tes3.effect.levitate })
	later(1, function()
		local start = dist(r)
		waitFor(20, function() return dist(r) < 350 and math.abs(r.position.z - tes3.player.position.z) < 120 end, function(ok)
			check("gets up to him on a high place he flew to", ok,
				string.format("he is %.0f above where she was; she started %.0f away, now %.0f (%.0f apart in height); health %.0f; came over %d times",
					tes3.player.position.z - base.z, start, dist(r), math.abs(r.position.z - tes3.player.position.z), r.mobile.health.current, (companion.cameOver or 0) - came))
			nextStep()
		end)
	end)
end)

-- (silt striders and boats: through the game's own talk and travel menus)
table.insert(steps, function()
	local pos, rot = besideTravel(TRAVEL["Ald'ruhn"])
	putHim(pos, rot)
	waitFor(20, function() local r = her() return r and sameCell(r) and dist(r) < 300 end, function(near)
		local came = companion.cameOver or 0
		travel("Ald'ruhn", { "Balmora" }, nil, function(ok, detail)
			if not ok then check("comes along on a silt strider", false, detail) nextStep() return end
			waitFor(10, function() local r = her() return r and sameCell(r) and dist(r) < 600 end, function(ok2)
				local r = her()
				check("comes along on a silt strider", ok2 and near, string.format("%s; she's in %s, %.0f away, health %.0f; the game took along: %s; came over %d times",
					detail, r.cell.id, dist(r), r.mobile.health.current, tostring(travelWith), (companion.cameOver or 0) - came))
				nextStep()
			end)
		end)
	end)
end)

table.insert(steps, function()
	-- (she's indoors when the silt strider leaves, where the game can't take her along: she must still turn up)
	local came = companion.cameOver or 0
	local p = PLACES["Balmora, Eight Plates"]
	local before = stats(her())
	travel("Balmora", { "Vivec" }, function()
		tes3.positionCell({ reference = her(), cell = p.cell, position = p.position, forceCellChange = true })
	end, function(ok, detail)
		if not ok then check("isn't left behind when the silt strider goes without her", false, detail) nextStep() return end
		waitFor(10, function() local r = her() return r and sameCell(r) and dist(r) < 600 end, function(ok2)
			local r = her()
			check("isn't left behind when the silt strider goes without her", ok2, string.format("%s; she's in %s, %.0f away, health %.0f; the game took along: %s; came over %d times",
				detail, r.cell.id, dist(r), r.mobile.health.current, tostring(travelWith), (companion.cameOver or 0) - came))
			check("keeps her level-ups after time apart", stats(r) == leveled, string.format("after leveling: %s; before the trip: %s; now: %s", tostring(leveled), before, stats(r)))
			nextStep()
		end)
	end)
end)

table.insert(steps, function()
	local pos, rot = besideTravel(TRAVEL["Vivec, Foreign Quarter"])
	putHim(pos, rot)
	waitFor(20, function() local r = her() return r and sameCell(r) and dist(r) < 300 end, function(near)
		local came = companion.cameOver or 0
		travel("Vivec, Foreign Quarter", { "Ebonheart", "Hla Oad", "Molag Mar", "Tel Branora", "Sadrith Mora" }, nil, function(ok, detail)
			if not ok then check("comes along on a boat", false, detail) nextStep() return end
			waitFor(10, function() local r = her() return r and sameCell(r) and dist(r) < 600 end, function(ok2)
				local r = her()
				check("comes along on a boat", ok2 and near, string.format("%s; she's in %s, %.0f away, health %.0f; the game took along: %s; came over %d times",
					detail, r.cell.id, dist(r), r.mobile.health.current, tostring(travelWith), (companion.cameOver or 0) - came))
				nextStep()
			end)
		end)
	end)
end)

-- (swimming, at the boat's harbour)
local backOnLand
table.insert(steps, function()
	-- (no fish: these checks are about the water, not a fight)
	for _, a in ipairs(tes3.findActorsInProximity({ reference = tes3.player, range = 6000 })) do
		if a.actorType == tes3.actorType.creature then a.reference:disable() end
	end
	backOnLand = tes3.player.position:copy()
	local deep = deepWater(450, 800, 3500)
	if not deep then check("comes to him in the water at the top, not the bottom", false, "no deep water near " .. tes3.player.cell.id) nextStep() return end
	effectOn(tes3.effect.waterBreathing, 300)
	putHim(tes3vector3.new(deep.x, deep.y, -250), nil, true)
	later(2, function()
		local came, hp = companion.cameOver or 0, her().mobile.health.current
		companion.command("come", {}, true)
		later(2, function()
			local r = her()
			local bottom = groundAt(r.position.x, r.position.y, 0) or deep.z
			check("comes to him in the water at the top, not the bottom",
				(companion.cameOver or 0) > came and r.position.z > -170 and r.position.z > bottom + 150 and across(r.position, tes3.player.position) < 400,
				string.format("he is %.0f under the surface (swimming: %s); she's at %.0f (swimming: %s), the bottom there %.0f; %.0f across from him; health %.0f to %.0f; came over %d times",
					-tes3.player.position.z, tostring(tes3.mobilePlayer.isSwimming), r.position.z, tostring(r.mobile.isSwimming), bottom,
					across(r.position, tes3.player.position), hp, r.mobile.health.current, (companion.cameOver or 0) - came))
			nextStep()
		end)
	end)
end)

table.insert(steps, function()
	-- (under water with him, out of breath: she must not drown)
	local r = her()
	local h = tes3.player.position
	moveHer(r, tes3vector3.new(h.x + 100, h.y, -300))
	later(0.5, function()
		local hp = r.mobile.health.current
		-- (as if she'd been under nearly all her breath: just over one of her half-second checks left)
		r.mobile.holdBreathTime = 0.6
		local under, samples, lowest = 0, 0, hp
		waitFor(6, function()
			samples = samples + 1
			if r.mobile.underwater then under = under + 1 end
			lowest = math.min(lowest, r.mobile.health.current)
			return false
		end, function()
			check("doesn't drown under water with him", samples > 0 and under >= samples * 0.6 and hp - lowest < 3 and r.mobile.holdBreathTime > 1,
				string.format("under water %d of %d half-seconds; health %.0f, lowest %.0f; breath left %.1f s", under, samples, hp, lowest, r.mobile.holdBreathTime))
			nextStep()
		end)
	end)
end)

table.insert(steps, function()
	-- (back on the dock, everything as it was, for the save)
	tes3.removeEffects({ reference = tes3.player, effect = tes3.effect.waterBreathing })
	if backOnLand then putHim(backOnLand) end
	later(1, function()
		companion.command("come", {}, true)
		tes3.runLegacyScript({ command = "tgm" })
		waitFor(10, function() local r = her() return r and sameCell(r) and dist(r) < 400 end, function() nextStep() end)
	end)
end)

-- ------------------------------------------------------------------ her look, through the look menu's own page

local look = require("opennpc.look")
local menu = require("opennpc.menu")

--- Does she look like `lk`: race, face, hair, and wearing every piece of the outfit? Also the pieces she isn't wearing.
local function looksLike(r, lk)
	local npc = r.baseObject
	local outfit = look.OUTFITS[1]
	for _, o in ipairs(look.OUTFITS) do if o.id == lk.outfit then outfit = o end end
	local missing = {}
	for _, it in ipairs(outfit.items) do
		local obj = tes3.getObject(it)
		if not (obj and r.object:hasItemEquipped(obj)) then table.insert(missing, it) end
	end
	local same = npc.race.id:lower() == lk.race:lower() and npc.head ~= nil and npc.head.id:lower() == lk.head:lower()
		and npc.hair ~= nil and npc.hair.id:lower() == lk.hair:lower()
	return same and #missing == 0, missing
end

local function notWearing(missing) return #missing > 0 and ("; not wearing " .. table.concat(missing, ", ")) or "" end

--- A photo of her, standing where the camera looks, facing it (in first or third person: the third-person camera doesn't
--- turn when he's turned by a move, so she goes where it looks, not where he faces). The runner (run_tests.ps1) takes it
--- from outside the game when Data Files\MWSE\opennpc_photo.txt names it (MGE's own screenshot saves nothing with DXVK's
--- d3d9.dll: the photo probe); she stands still 4 seconds for it.
local function photo(name, after)
	local r = her()
	companion.wait(r)
	local eye, look = tes3.getCameraPosition(), tes3.getCameraVector()
	local flat = math.sqrt(look.x * look.x + look.y * look.y)
	local dir = flat > 0.01 and tes3vector3.new(look.x / flat, look.y / flat, 0) or tes3vector3.new(0, 1, 0)
	local side = tes3vector3.new(dir.y, -dir.x, 0)
	-- (a spot ahead of the camera with ground under it and nothing between: past him in third person, a little to the side)
	local spot
	for _, d in ipairs({ 340, 280, 220 }) do
		for _, o in ipairs({ 70, -70, 0 }) do
			local p = eye + dir * d + side * o
			local ground = tes3.rayTest({ position = p + tes3vector3.new(0, 0, 50), direction = tes3vector3.new(0, 0, -1), maxDistance = 600, ignore = { tes3.player, r } })
			if ground and ground.intersection and math.abs(ground.intersection.z - tes3.player.position.z) < 120 then
				local chest = ground.intersection + tes3vector3.new(0, 0, 90)
				local toward = chest - eye
				local len = toward:length()
				local hit = tes3.rayTest({ position = eye, direction = toward:normalized(), maxDistance = len, ignore = { tes3.player, r } })
				if not (hit and hit.distance and hit.distance < len - 30) then spot = ground.intersection + tes3vector3.new(0, 0, 4) break end
			end
		end
		if spot then break end
	end
	moveHer(r, spot or (tes3.player.position + dir * 200))
	later(0.5, function()
		local toCam = eye - r.position
		r.orientation = tes3vector3.new(0, 0, math.atan2(toCam.x, toCam.y))
		later(1.5, function()
			local file = io.open("Data Files\\MWSE\\opennpc_photo.txt", "w")
			file:write(name)
			file:close()
			say("photo now: %s (%.0f from the camera, a clear spot: %s, third person: %s)", name, r.position:distance(eye), tostring(spot ~= nil), tostring(tes3.is3rdPerson()))
			later(4, function()
				companion.follow(r)
				later(1, after)
			end)
		end)
	end)
end

--- Opens the look menu's page in a window of its own, clicks its buttons (id, times), reads what it shows, closes it.
local function useMenu(clicks)
	local m = tes3ui.createMenu({ id = "OpenNPC:TestMenu", fixedFrame = true })
	menu.build(m)
	for _, c in ipairs(clicks) do
		for _ = 1, c[2] do m:findChild(c[1]):triggerEvent("mouseClick") end
	end
	local shown = {}
	for _, key in ipairs({ "Companion", "Race", "Face", "Hair", "Outfit" }) do table.insert(shown, key .. " " .. m:findChild("OpenNPC:" .. key .. "_value").text) end
	m:destroy()
	return table.concat(shown, ", ")
end

local lookSteps = {}   -- (also run alone by the "look" probe)

table.insert(lookSteps, function()
	-- (him facing straight ahead, for the photos, at midday)
	putHim(tes3.player.position:copy(), tes3.player.orientation.z)
	tes3.worldController.hour.value = 13
	later(1.5, function()
		local r = her()
		local name = companion.shownName()
		local lk = look.lookFor(name)
		local ok, missing = looksLike(r, lk)
		check("starts with the default look", ok and lk.race == look.DEFAULT.race and lk.outfit == look.DEFAULT.outfit,
			string.format("%s: %s%s", name, look.describe(r), notWearing(missing)))
		photo("1_default", nextStep)
	end)
end)

table.insert(lookSteps, function()
	local r = her()
	local name = companion.shownName()
	local shown = useMenu({ { "OpenNPC:Face_next", 2 }, { "OpenNPC:Hair_next", 3 }, { "OpenNPC:Outfit_next", 1 } })
	later(1.5, function()
		local r2 = her()
		local lk = look.lookFor(name)
		local ok, missing = looksLike(r2, lk)
		check("the look menu changes her face, hair and outfit", ok and r2 == r and lk.outfit == "warrior" and lk.head ~= look.DEFAULT.head and lk.hair ~= look.DEFAULT.hair,
			string.format("the menu shows %s; she's %s; the same person: %s%s", shown, look.describe(r2), tostring(r2 == r), notWearing(missing)))
		photo("2_changed", nextStep)
	end)
end)

table.insert(lookSteps, function()
	local r = her()
	local name = companion.shownName()
	local before = { level = companion.state(r).level, stats = stats(r), mode = companion.state(r).mode }
	-- (Imperial, back two: High Elf, then Dark Elf; two swaps in a row)
	local shown = useMenu({ { "OpenNPC:Race_prev", 2 } })
	later(2, function()
		local r2 = her()
		local lk = look.lookFor(name)
		local ok, missing = looksLike(r2, lk)
		local st = companion.state(r2)
		check("a new race in the menu swaps her, keeping what's hers",
			ok and r2.baseObject.race.id == "Dark Elf" and copies() == 1 and r2.object.name == name and st.level == before.level
				and stats(r2) == before.stats and st.mode == before.mode and sameCell(r2) and dist(r2) < 400,
			string.format("the menu shows %s; she's %s, called %s, %d of her, %.0f away; level %d (was %d), %s (was %s), %s%s", shown, look.describe(r2),
				r2.object.name, copies(), dist(r2), st.level, before.level, stats(r2), before.stats, st.mode, notWearing(missing)))
		photo("3_dark_elf", nextStep)
	end)
end)

table.insert(lookSteps, function()
	-- (the app picks Yui again, then Mila: each turns up in her own look; Yui never got one, so hers is the default)
	waitFor(10, parked, function()
		control("name=Yui")
		waitFor(8, function() local r = her() return r and r.object.name == "Yui" and r.baseObject.race.id == "Imperial" end, function(ok)
			local okYui = ok and looksLike(her(), look.lookFor("Yui"))
			local yui = look.describe(her())
			waitFor(10, parked, function()
				control("name=Mila")
				waitFor(8, function() local r = her() return r and r.object.name == "Mila" and r.baseObject.race.id == "Dark Elf" end, function(ok2)
					local r = her()
					check("each companion keeps her own look", okYui and ok2 and looksLike(r, look.lookFor("Mila")) and copies() == 1,
						string.format("Yui: %s; Mila: %s; %d of her", yui, look.describe(r), copies()))
					nextStep()
				end)
			end)
		end)
	end)
end)


for _, s in ipairs(lookSteps) do table.insert(steps, s) end
table.insert(steps, function()
	-- (over the whole run: fights may hurt her, the ways of getting around must not)
	local bad = {}
	for _, h in ipairs(hurts) do if h.how == "fall" or h.how == "suffocation" then table.insert(bad, h.text) end end
	check("never hurt by a fall or by drowning", #bad == 0, #bad == 0 and string.format("hurt %d times in all, none by falling or drowning", #hurts) or table.concat(bad, "; "))
	nextStep()
end)

table.insert(steps, function()
	tes3.saveGame({ file = "opennpc_test", name = "Open NPC test" })
	later(1, function()
		event.register(tes3.event.loaded, function()
			waitFor(6, function() local r = her() return r and sameCell(r) and dist(r) < 600 end, function(ok)
				local r = her()
				check("after saving and loading", ok and copies() == 1 and companion.state(r).mode == "follow" and stats(r) == leveled
						and looksLike(r, look.lookFor(companion.shownName())),
					r and string.format("%d of her, mode %s, %.0f away; %s (after leveling: %s); %s", copies(), companion.state(r).mode, dist(r), stats(r),
						tostring(leveled), look.describe(r)) or "missing")
				nextStep()
			end)
		end, { doOnce = true })
		tes3.loadGame("opennpc_test.ess")
	end)
end)

-- ------------------------------------------------------------------ a probe (with Data Files\MWSE\opennpc_test.probe: only this, no checks)
-- (what the game does with someone put up in the air or deep in the water: does it drop them to the ground?)

local function watchZ(label, ref, after)
	for _, t in ipairs({ 0.2, 1, 3 }) do
		later(t, function()
			local m = ref.mobile
			say("probe %s, at %.1f s: z %.0f (levitate %s, flying %s, swimming %s, under water %s, falling %s)", label, t, ref.position.z,
				tostring(m.levitate), tostring(m.isFlying), tostring(m.isSwimming), tostring(m.underwater), tostring(m.isFalling))
			if t == 3 then after() end
		end)
	end
end

local function probe()
	local r = her()
	companion.wait(r)   -- (so her own moves don't get in the way)
	tes3.runLegacyScript({ command = "tgm" })
	effectOn(tes3.effect.levitate, 300)
	later(1, function()
		local p = tes3.player.position:copy()
		local up = tes3vector3.new(p.x, p.y, p.z + 1500)
		say("probe: he is at z %.0f; levitate %s, flying %s", p.z, tostring(tes3.mobilePlayer.levitate), tostring(tes3.mobilePlayer.isFlying))
		putHim(up)
		watchZ("A him, positionCell forced, 1500 up", tes3.player, function()
			tes3.player.position = up
			watchZ("B him, position set, 1500 up", tes3.player, function()
				tes3.positionCell({ reference = tes3.mobilePlayer, position = up, teleportCompanions = false })
				watchZ("C him, positionCell not forced, 1500 up", tes3.player, function()
					tes3.removeEffects({ reference = tes3.player, effect = tes3.effect.levitate })
					effectOn(tes3.effect.waterBreathing, 300)
					putHim((besideTravel(TRAVEL["Vivec, Foreign Quarter"])))
					later(4, function()
						local deep = deepWater(450, 300, 3500)
						if not deep then say("probe: no deep water near %s", tes3.player.cell.id) finish() return end
						say("probe: deep water at %.0f, %.0f, bottom %.0f", deep.x, deep.y, deep.z)
						local under = tes3vector3.new(deep.x, deep.y, -250)
						putHim(under)
						watchZ("D him, positionCell forced, 250 under water", tes3.player, function()
							tes3.player.position = under
							watchZ("E him, position set, 250 under water", tes3.player, function()
								local top = tes3vector3.new(deep.x + 100, deep.y, -90)
								tes3.positionCell({ reference = r, cell = tes3.player.cell, position = top, forceCellChange = true })
								watchZ("F her, positionCell forced, 90 under the surface", r, function()
									r.position = top
									watchZ("G her, position set, 90 under the surface", r, function()
										local mid = tes3vector3.new(deep.x + 100, deep.y, -250)
										r.position = mid
										watchZ("H her, position set, 250 under water", r, function() finish() end)
									end)
								end)
							end)
						end)
					end)
				end)
			end)
		end)
	end)
end

-- (with "photo" in the probe file: which way of taking a photo saves a file here)
local function photoProbe()
	local lfs = require("lfs")
	say("probe photo: MGE on: %s", tostring(mge.enabled()))
	local tries = {
		{ "A, forward slashes, png", function() return mge.saveScreenshot({ path = "Data Files/MWSE/opennpc_probe_A.png" }) end, "Data Files/MWSE/opennpc_probe_A.png" },
		{ "B, the game folder, png", function() return mge.saveScreenshot({ path = "opennpc_probe_B.png" }) end, "opennpc_probe_B.png" },
		{ "C, back slashes, bmp", function() return mge.saveScreenshot({ path = "Data Files\\MWSE\\opennpc_probe_C.bmp" }) end, "Data Files\\MWSE\\opennpc_probe_C.bmp" },
		{ "D, with the menus, png", function() return mge.saveScreenshot({ path = "opennpc_probe_D.png", captureWithUI = true }) end, "opennpc_probe_D.png" },
		{ "E, MGE's own screenshot key", function() return mge.macros.takeScreenshot() end, nil },
	}
	local i = 0
	local function nextTry()
		i = i + 1
		local t = tries[i]
		if not t then finish() return end
		local ok, res = pcall(t[2])
		later(2, function()
			say("probe photo %s: the call %s (%s); a file there 2 s later: %s", t[1], ok and "ran" or "failed", tostring(res),
				t[3] and tostring(lfs.attributes(t[3]) ~= nil) or "see the game folder")
			nextTry()
		end)
	end
	later(2, nextTry)
end

if exists("Data Files\\MWSE\\opennpc_test.probe") then
	local f = io.open("Data Files\\MWSE\\opennpc_test.probe", "r")
	local kind = f and (f:read("*l") or "") or ""
	if f then f:close() end
	for k in pairs(steps) do steps[k] = nil end
	if kind:find("look") then
		table.insert(steps, function() waitFor(10, function() return her() ~= nil end, function() later(2, nextStep) end) end)
		for _, st in ipairs(lookSteps) do table.insert(steps, st) end
	else
		table.insert(steps, function() waitFor(10, function() return her() ~= nil end, kind:find("photo") and photoProbe or probe) end)
	end
end

-- ------------------------------------------------------------------ starting

local started = false

--- The nearest door in his cell that leads somewhere.
local function nearestDoor()
	local best, bestD
	for ref in tes3.player.cell:iterateReferences(tes3.objectType.door) do
		if ref.destination and not ref.disabled then
			local d = ref.position:distance(tes3.player.position)
			if not bestD or d < bestD then best, bestD = ref, d end
		end
	end
	return best, bestD
end

event.register(tes3.event.loaded, function(e)
	if started or not FROM_SAVE or e.newGame then return end
	started = true
	say("save %s loaded in %s; letting it settle", FROM_SAVE, tes3.player.cell.id)
	later(4, function()
		local door, d = nearestDoor()
		if door then
			say("walking through the nearest door, %s (%.0f away), to %s", door.id, d, door.destination.cell.id)
			tes3.player:activate(door)
		else
			say("no door in %s", tes3.player.cell.id)
		end
		later(8, function()
			say("through: now in %s; going to Balmora", tes3.player.cell.id)
			coc("Balmora")
			later(10, function() say("in %s; starting checks", tes3.player.cell.id) nextStep() end)
		end)
	end)
end)

event.register(tes3.event.loaded, function(e)
	if started or FROM_SAVE or not e.newGame then return end
	started = true
	say("new game loaded; letting it settle")
	later(3, function()
		say("skipping character creation")
		tes3.findGlobal("CharGenState").value = -1
		-- (as at the end of the game's own character creation: menus, map and controls back on)
		for _, c in ipairs({ "EnablePlayerControls", "EnableInventoryMenu", "EnableMagicMenu", "EnableMapMenu", "EnableStatsMenu", "EnableRest", "EnablePlayerJumping", "EnablePlayerViewSwitch", "EnableVanityMode" }) do
			tes3.runLegacyScript({ command = c })
		end
		later(1, function()
			-- (off the ship through its own door first, the way the game itself leaves character creation; teleporting
			-- straight off the ship crashed the renderer every time)
			for ref in tes3.player.cell:iterateReferences(tes3.objectType.door) do
				if ref.destination then
					say("leaving the ship through %s to %s", ref.id, ref.destination.cell.id)
					tes3.player:activate(ref)
					break
				end
			end
			later(5, function()
				say("now in %s; going to Balmora", tes3.player.cell.id)
				coc("Balmora")
			end)
		end)
		later(10, function() say("in %s; starting checks", tes3.player.cell.id) nextStep() end)
	end)
end)

event.register(tes3.event.initialized, function()
	say("test run starting; waiting for the main menu")
	-- (a new game only once the main menu is on screen, as a player would click it: started while the opening movies still
	-- played, the next loading screen crashed the renderer)
	event.register(tes3.event.uiActivated, function()
		say("main menu is up")
		timer.start({ type = timer.real, duration = 3, callback = function()
			if FROM_SAVE then say("loading save %s", FROM_SAVE) tes3.loadGame(FROM_SAVE)
			else say("starting a new game") tes3.newGame() end
		end })
	end, { filter = "MenuOptions", doOnce = true })
end)

-- (a hard stop, so a stuck step never leaves the game running)
event.register(tes3.event.initialized, function()
	timer.start({ type = timer.real, duration = 600, callback = function()
		say("TIMEOUT: the run took too long")
		finish()
	end })
end)
