--- Open NPC for Morrowind: a companion who plays the whole game with you.
--- She shows up once the character is made, follows you, waits when told, fights beside you, catches up after doors,
--- Recall, Intervention, silt striders and boats, stays on the ground under you while you levitate and on the water over
--- you while you swim, never drowns, can be revived at her body when she dies, and levels up with you. Her person comes from OpenNPC.esp (Morrowind can't make a new
--- person while the game runs); everything she does is here.

local brain = require("opennpc.brain")
local look = require("opennpc.look")

local this = {}

this.NPC_ID = "opennpc_companion"
-- (url: the AI she asks, any OpenAI-style "chat completions with tools" address; a voice app on this PC can also open the
-- wait door there. useAppName: that app may name her, the companion picked in it.)
-- (looks: each companion's look, by the name she goes by; see opennpc.look)
this.config = mwse.loadConfig("Open NPC", { name = "Ana", url = "http://127.0.0.1:41751/v1", key = "", model = "", useAppName = true, looks = {} })

local function log(fmt, ...)
	mwse.log("[Open NPC] " .. fmt, ...)
end

-- ------------------------------------------------------------------ finding her

local handle

--- Her reference in the world, or nil if she isn't there (not made yet, or removed). She can be any race's record.
function this.her()
	if handle and handle:valid() then
		local r = handle:getObject()
		if r and not r.deleted and not r.disabled then return r end
	end
	handle = nil
	local ids = {}
	local saved = tes3.player and tes3.player.data.opennpcId
	if saved then table.insert(ids, saved) end
	for _, race in ipairs(look.RACES) do table.insert(ids, look.recordFor(race)) end
	for _, id in ipairs(ids) do
		local r = tes3.getReference(id)
		if r and not r.deleted and not r.disabled then
			handle = tes3.makeSafeObjectHandle(r)
			return r
		end
	end
	return nil
end

--- What she's doing and how far she has leveled, kept in the save with her.
function this.state(r)
	r.data.opennpc = r.data.opennpc or { mode = "follow", level = tes3.player.object.level }
	return r.data.opennpc
end

local function chargenDone()
	local g = tes3.findGlobal("CharGenState")
	return g == nil or g.value == -1
end

-- ------------------------------------------------------------------ places to stand

local UP = tes3vector3.new(0, 0, 1)

local function flat(v)
	local l = math.sqrt(v.x * v.x + v.y * v.y)
	if l < 0.001 then return tes3vector3.new(0, 1, 0) end
	return tes3vector3.new(v.x / l, v.y / l, 0)
end

local function turn(v, degrees)
	local a = math.rad(degrees)
	return tes3vector3.new(v.x * math.cos(a) - v.y * math.sin(a), v.x * math.sin(a) + v.y * math.cos(a), 0)
end

local function facing(ref)
	local z = ref.orientation.z
	return tes3vector3.new(math.sin(z), math.cos(z), 0)
end

--- `dist` units from `from` along `dir`, if nothing is in the way at chest height and there's ground under it.
local function clearSpot(from, dir, dist, ignore)
	local chest = from + UP * 70
	local hit = tes3.rayTest({ position = chest, direction = dir, maxDistance = dist + 48, ignore = ignore })
	if hit and hit.distance and hit.distance < dist + 48 then return nil end
	local above = chest + dir * dist
	local ground = tes3.rayTest({ position = above, direction = UP * -1, maxDistance = 400, ignore = ignore })
	if not ground or not ground.intersection then return nil end
	-- (not a drop: the ground there is within a step or two of his feet)
	if math.abs(ground.intersection.z - from.z) > 160 then return nil end
	return ground.intersection + UP * 4
end

this.clearSpot = clearSpot

local SWIM_DEPTH = 125   -- (how far under the surface a swimmer's feet are; the game settled her at 120)

--- `dist` units from `from` (a point on the water's surface) along `dir`, if nothing is in the way: her feet as deep
--- under the surface as a swimmer's, or on the bottom where it's too shallow to swim.
local function waterSpot(from, dir, dist, ignore)
	local hit = tes3.rayTest({ position = from, direction = dir, maxDistance = dist + 48, ignore = ignore })
	if hit and hit.distance and hit.distance < dist + 48 then return nil end
	local s = from + dir * dist
	local z = from.z - SWIM_DEPTH
	local bottom = tes3.rayTest({ position = s, direction = UP * -1, maxDistance = 400, ignore = ignore })
	if bottom and bottom.intersection and bottom.intersection.z > z then z = bottom.intersection.z + 4 end
	return tes3vector3.new(s.x, s.y, z)
end

--- A place near the point `at` (behind `face` if it can, then the sides, then in front) where she can stand, or swim
--- when `kind` is "water".
function this.spotAt(at, face, dist, ignore, kind)
	local dirs = { face * -1, turn(face, 120), turn(face, -120), turn(face, 60), turn(face, -60), face }
	local find = kind == "water" and waterSpot or clearSpot
	for _, d in ipairs(dirs) do
		for _, k in ipairs({ dist, dist * 0.6, dist * 0.35 }) do
			local s = find(at, d, k, ignore)
			if s then return s end
		end
	end
	return kind == "water" and (at - UP * SWIM_DEPTH) or (at + UP * 8)
end

--- A place near `ref` where she can stand.
function this.spotNear(ref, dist, ignore) return this.spotAt(ref.position, facing(ref), dist, ignore, "ground") end

--- Where she should be heading for: his feet; while he's in the water, the surface over him; while he's off the ground
--- (levitating, jumping, falling), the ground under him, or the water's surface if the ground under him is under water.
--- (Put where he is while he levitated, she fell from there and got hurt.) Returns the point and "ground" or "water".
function this.standPoint(r)
	local m, p, cell = tes3.mobilePlayer, tes3.player.position, tes3.player.cell
	local water = (not cell.isInterior or cell.hasWater) and cell.waterLevel or nil
	if water and (m.isSwimming or m.underwater) then return tes3vector3.new(p.x, p.y, water), "water" end
	if not (m.levitate > 0 or m.isFlying or m.isFalling or m.isJumping) then return p:copy(), "ground" end
	local hit = tes3.rayTest({ position = p + UP * 20, direction = UP * -1, maxDistance = 20000, ignore = { tes3.player, r } })
	local g = hit and hit.intersection
	if water and (not g or g.z < water) then return tes3vector3.new(p.x, p.y, water), "water" end
	if not g then return p:copy(), "ground" end
	return tes3vector3.new(g.x, g.y, g.z), "ground"
end

local function isFar(r, at)
	local pc, hc = tes3.player.cell, r.cell
	if pc.isInterior or hc.isInterior then
		if pc ~= hc then return true end
	end
	return r.position:distance(at or this.standPoint(r)) > 2500
end

-- ------------------------------------------------------------------ what she does

--- The game's own follow order, the way companion mods give it: follow him, no end point, for good. (MWSE's setAIFollow
--- without a destination left her standing far off or walking away.)
local function setFollow(r)
	tes3.runLegacyScript({ reference = r, command = "AIFollow player 0 0 0 0" })
end

--- What her AI is doing right now, for the log.
function this.describeAI(r)
	r = r or this.her()
	local planner = r and r.mobile and r.mobile.aiPlanner
	local p = planner and planner:getActivePackage()
	if not p then return "no AI package" end
	local d = p.destination and string.format("(%.0f,%.0f,%.0f)", p.destination.x, p.destination.y, p.destination.z) or "none"
	return string.format("package %s, target %s, destination %s, followDistance %s, duration %s, done %s, moving %s",
		tostring(p.type), p.targetActor == tes3.mobilePlayer and "him" or tostring(p.targetActor and p.targetActor.reference),
		d, tostring(p.followDistance), tostring(p.duration), tostring(p.isDone), tostring(p.isMoving))
end

-- (stuck while following: where she was when the last 6 seconds began, and the closest she's been to him lately, each
-- with how many ticks it has held)
local stuck = {}
local function resetStuck(r, d) stuck = { pos = r and r.position:copy(), moveTicks = 0, best = d or math.huge, closerTicks = 0 } end
resetStuck()

--- Runs fn(ref) a frame later (or after `seconds`), only if `ref` is still there: by then it can be gone (a race swap
--- deletes her old copy), and touching a gone one is an error.
function this.later(ref, fn, seconds)
	local h = tes3.makeSafeObjectHandle(ref)
	local function run()
		if not h:valid() then return end
		local r = h:getObject()
		if r and not r.deleted then fn(r) end
	end
	if seconds then timer.start({ type = timer.simulate, duration = seconds, persist = false, callback = run })
	else timer.delayOneFrame(run) end
end

--- Sets `ref` to the height of `spot` once the game has finished moving it (it drops a moved person onto what's under
--- them; setting the position afterwards sticks).
function this.liftTo(ref, spot)
	local function lift(r)
		if r.position.z < spot.z - 40 then
			log("lifted %s from %.0f back up to %.0f", r == tes3.player and "him" or "her", r.position.z, spot.z)
			r.position = spot:copy()
		end
	end
	this.later(ref, lift)
	this.later(ref, lift, 0.3)
end

--- Puts her near him: behind him if she can, out of his way.
function this.bringToPlayer(r)
	r = r or this.her()
	if not r then return end
	local at, kind = this.standPoint(r)
	local how = kind == "water" and ", in the water" or (at:distance(tes3.player.position) > 60 and ", up in the air" or "")
	local why = string.format("she was in %s at %.0f, he is in %s%s", r.cell.id, r.position:distance(at), tes3.player.cell.id, how)
	local spot = this.spotAt(at, facing(tes3.player), 140, { tes3.player, r }, kind)
	-- (forced as a cell change: a move inside the cell she's already in didn't stick, and left her standing, unable to walk)
	-- (the game drops anyone it moves who isn't swimming yet onto whatever is under the spot, and from the surface to the
	-- bottom of deep water that drop hurt her: in the water she's put on the bottom, then lifted up to swim with him)
	local land = spot
	if kind == "water" then
		local bottom = tes3.rayTest({ position = spot, direction = UP * -1, maxDistance = 20000, ignore = { tes3.player, r } })
		if bottom and bottom.intersection then land = bottom.intersection + UP * 4 end
	end
	tes3.positionCell({ reference = r, cell = tes3.player.cell, position = land, orientation = tes3.player.orientation, forceCellChange = true })
	-- (a move isn't a fall: the height she last stood at becomes where she's put. The game kept her old one, and took the
	-- way from the dock to the bottom of the harbour as a fall: 11 health.)
	if r.mobile then r.mobile.lastGroundZ = land.z end
	if kind == "water" then this.liftTo(r, spot) end
	log("(%s)", why)
	if this.state(r).mode == "follow" then setFollow(r) end
	this.cameOver = (this.cameOver or 0) + 1
	resetStuck()
	log("came over to %s", tes3.player.cell.id)
end

function this.follow(r)
	r = r or this.her()
	if not r then return end
	this.state(r).mode = "follow"
	if isFar(r) then this.bringToPlayer(r) end
	setFollow(r)
	log("following (%s)", this.describeAI(r))
end

function this.wait(r)
	r = r or this.her()
	if not r then return end
	this.state(r).mode = "wait"
	if r.mobile and r.mobile.forceRun ~= nil then r.mobile.forceRun = false end
	tes3.setAIWander({ reference = r, idles = { 0, 0, 0, 0, 0, 0, 0, 0 }, range = 0 })
	log("waiting in %s", r.cell.id)
end

--- The name she goes by: the voice app's (the companion picked there), when it gives one and that's allowed, else her
--- settings' name.
function this.shownName()
	local app = brain.appName()
	if this.config.useAppName ~= false and app and app ~= "" then return app end
	return (this.config.name and this.config.name ~= "") and this.config.name or "Ana"
end

function this.applyName(r)
	r = r or this.her()
	-- (on her base record: the name on her own copy in the world doesn't take, and that's the one the game shows)
	if r then r.baseObject.name = this.shownName() end
end

local SKILLS = { "shortBlade", "longBlade", "block", "mediumArmor", "athletics" }
local ATTRIBUTES = { "strength", "agility", "endurance" }

--- One level for her: more health, a little stronger, better with her blade and armor.
local function gainLevel(r)
	tes3.modStatistic({ reference = r, name = "health", value = 8 })
	for _, a in ipairs(ATTRIBUTES) do tes3.modStatistic({ reference = r, attribute = tes3.attribute[a], value = 1, limit = true }) end
	for _, s in ipairs(SKILLS) do tes3.modStatistic({ reference = r, skill = tes3.skill[s], value = 2, limit = true }) end
end

--- Her trained stats go into the save with her. (The game works out a person's stats afresh from their record each
--- time it builds them again, after she's been somewhere it had let go of: her level-ups were gone, health 92 back to 84.)
local function saveStats(r)
	local m = r.mobile
	if not m then return end
	local t = { health = m.health.base, attributes = {}, skills = {} }
	for _, a in ipairs(ATTRIBUTES) do t.attributes[a] = m[a].base end
	for _, s in ipairs(SKILLS) do t.skills[s] = m[s].base end
	this.state(r).stats = t
end

--- Puts her saved stats back if the game built her again from her record.
function this.restoreStats(r)
	r = r or this.her()
	local t = r and this.state(r).stats
	local m = r and r.mobile
	if not t or not m then return end
	local fixed = 0
	if math.abs(m.health.base - t.health) > 0.5 then tes3.setStatistic({ reference = r, name = "health", value = t.health }) fixed = fixed + 1 end
	for a, v in pairs(t.attributes) do
		if math.abs(m[a].base - v) > 0.5 then tes3.setStatistic({ reference = r, attribute = tes3.attribute[a], value = v }) fixed = fixed + 1 end
	end
	for k, v in pairs(t.skills) do
		if math.abs(m[k].base - v) > 0.5 then tes3.setStatistic({ reference = r, skill = tes3.skill[k], value = v }) fixed = fixed + 1 end
	end
	if fixed > 0 then log("put back %d of her stats (the game had built her again from her record)", fixed) end
end

--- Levels her up to wherever he is now.
function this.catchUp(r)
	r = r or this.her()
	if not r or not r.mobile then return end
	local st = this.state(r)
	local target = tes3.player.object.level
	local gained = 0
	while st.level < target do
		st.level = st.level + 1
		gainLevel(r)
		gained = gained + 1
	end
	if gained > 0 then
		saveStats(r)
		log("leveled up %d to %d", gained, st.level)
	end
end

function this.spawn()
	if this.her() or not chargenDone() then return this.her() end
	local spot = this.spotNear(tes3.player, 140, { tes3.player })
	log("showing up at %s in %s", tostring(spot), tes3.player.cell.id)
	local id = look.recordFor(look.lookFor(this.shownName()).race)
	local r = tes3.createReference({ object = id, position = spot, orientation = tes3.player.orientation, cell = tes3.player.cell })
	handle = tes3.makeSafeObjectHandle(r)
	tes3.player.data.opennpcId = r.baseObject.id
	this.applyName(r)
	this.state(r)
	setFollow(r)
	this.later(r, function(x) look.apply(x) end)   -- (her face, hair and outfit, once she can wear things)
	log("showed up in %s", tes3.player.cell.id)
	return r
end

--- Takes on a new copy of her (another race's record, after a swap): she's this one now, with her name, and following
--- or waiting as before.
function this.adopt(r)
	handle = tes3.makeSafeObjectHandle(r)
	tes3.player.data.opennpcId = r.baseObject.id
	this.applyName(r)
	this.later(r, function(x)
		if not x.mobile then return end
		if this.state(x).mode == "wait" then this.wait(x) else setFollow(x) end
		this.restoreStats(x)
	end)
end

-- ------------------------------------------------------------------ what the AI hears and what it can ask for (brain.lua)

function this.name() return this.shownName() end
function this.ownerName() return (tes3.player and tes3.player.object.name) or "the player" end
function this.ready() return tes3.player ~= nil and this.her() ~= nil end

local function stat(m) return string.format("%.0f/%.0f", m.health.current, m.health.base) end
local function steps(d)
	local n = math.max(1, math.floor(d / 70 + 0.5))
	return n == 1 and "right beside each other" or string.format("about %d steps apart", n)
end

local function timeOfDay()
	local h = tes3.worldController and tes3.worldController.hour.value or 12
	local part = (h < 5 and "night") or (h < 12 and "morning") or (h < 17 and "afternoon") or (h < 21 and "evening") or "night"
	return string.format("%s (%02d:%02d)", part, math.floor(h), math.floor((h % 1) * 60))
end

--- The situation in plain words, in order.
function this.situation()
	local r = this.her()
	local out = {}
	local owner = this.ownerName()
	if r and r.mobile then
		local st = this.state(r)
		local doing = st.mode == "wait" and ("waiting in " .. r.cell.displayName) or "following " .. owner
		local fighting = r.mobile.inCombat and r.mobile.actionData.target and r.mobile.actionData.target.reference
		if fighting then doing = doing .. ", fighting " .. fighting.object.name end
		if r.mobile.isDead then doing = "dead, until " .. owner .. " revives you" end
		table.insert(out, { "you", string.format("%s, health %s, level %d, %s", r.object.name, stat(r.mobile), st.level, doing) })
	end
	local m = tes3.mobilePlayer
	table.insert(out, { owner, string.format("health %s, level %d%s", stat(m), tes3.player.object.level, m.inCombat and ", fighting" or "") })
	local cell = tes3.player.cell
	local where = cell.displayName .. (cell.isInterior and " (indoors)" or " (outdoors)")
	if cell.region then where = where .. ", " .. cell.region.name end
	table.insert(out, { "where", where })
	table.insert(out, { "time", timeOfDay() })
	if r then
		local apart = r.cell ~= cell and (r.cell.isInterior or cell.isInterior)
		table.insert(out, { "between you", apart and ("in different places (you are in " .. r.cell.displayName .. ")") or steps(r.position:distance(tes3.player.position)) })
	end
	local near = {}
	for _, a in ipairs(tes3.findActorsInProximity({ reference = tes3.player, range = 1500 })) do
		local ref = a.reference
		if ref ~= tes3.player and ref ~= r and not a.isDead and #near < 5 then
			local hostile = a.inCombat and a.actionData.target == tes3.mobilePlayer
			table.insert(near, ref.object.name .. (hostile and " (attacking " .. owner .. ")" or ""))
		end
	end
	if #near > 0 then table.insert(out, { "nearby", table.concat(near, ", ") }) end
	return out
end

local ACTIONS = {
	{ name = "follow", about = "follow him: come along, let's go" },
	{ name = "wait", about = "wait right here until told to follow" },
	{ name = "come", about = "come to him right now, even from far away" },
	{ name = "fight", about = "attack what is attacking him, or the nearest enemy" },
	{ name = "stop_fighting", about = "stop fighting and stay with him" },
}
function this.actions() return ACTIONS end

--- The enemy to go for: whatever is attacking him, else the nearest one fighting anyone, else the nearest aggressive one.
local function enemy()
	local best, bestD
	for _, a in ipairs(tes3.findActorsInProximity({ reference = tes3.player, range = 2000 })) do
		local ref = a.reference
		if ref ~= tes3.player and ref ~= this.her() and not a.isDead then
			local d = ref.position:distance(tes3.player.position)
			local score = (a.inCombat and a.actionData.target == tes3.mobilePlayer and 0) or (a.inCombat and 1) or (a.fight >= 80 and 2) or nil
			if score then d = d + score * 10000 if not bestD or d < bestD then best, bestD = a, d end end
		end
	end
	return best
end

--- Does what the AI picked. Returns ok, why-not.
function this.command(action, args, byPlayer)
	local r = this.her()
	if not r or not r.mobile then return false, "she isn't here" end
	if r.mobile.isDead then return false, "she's dead until he revives her" end
	if action == "follow" then this.follow(r) return true end
	if action == "wait" then this.wait(r) return true end
	if action == "come" then
		this.state(r).mode = "follow"
		if r.cell ~= tes3.player.cell or r.position:distance(this.standPoint(r)) > 400 then this.bringToPlayer(r) end
		setFollow(r)
		return true
	end
	if action == "fight" then
		local foe = enemy()
		if not foe then return false, "no enemy nearby" end
		r.mobile:startCombat(foe)
		return true
	end
	if action == "stop_fighting" then
		r.mobile:stopCombat(true)
		if this.state(r).mode == "follow" then setFollow(r) end
		return true
	end
	return false, "not something she can do"
end

--- Her words on screen (only when no voice app speaks for her).
function this.say(text) tes3.messageBox("%s: %s", this.shownName(), text) end

--- The voice app named her (or stopped naming her): that companion's name, and her look.
function this.nameChanged()
	this.applyName()
	look.apply()
end

-- ------------------------------------------------------------------ the game's events

local watch
local settleTicks = 0   -- (ticks to sit out after a load or a jump)

--- Under water her breath stays full: the game's follow never swims up for air, so going under after him would drown
--- her where he'd come up fine.
local function keepBreath(r)
	local m = r.mobile
	if not m or not m.underwater then return end
	local full = tes3.findGMST("fHoldBreathTime").value
	if m.holdBreathTime < full then m.holdBreathTime = full end
end

--- Twice a second: shows up once the character is made, and comes over if she's left far behind.
function this.tick()
	if not tes3.player or tes3.menuMode() or not chargenDone() then return end
	-- (not in the first seconds after a load or a jump: the world is still being put together)
	if settleTicks > 0 then settleTicks = settleTicks - 1 return end
	local r = this.her()
	if not r then
		this.spawn()
		return
	end
	if r.mobile and r.mobile.isDead then return end
	keepBreath(r)
	if this.state(r).mode ~= "follow" then return end
	local at = this.standPoint(r)
	if isFar(r, at) then this.bringToPlayer(r) return end
	local d = r.position:distance(at)
	-- (fallen behind: she runs to catch up, and walks again once she's close)
	local m = r.mobile
	if m and m.forceRun ~= nil then
		if d > 350 then m.forceRun = true elseif d < 200 then m.forceRun = false end
	end
	-- (stuck on the way to him, more than 700 away: she comes over, behind him, when she hasn't moved herself in 6
	-- seconds (caught on something), or hasn't got any closer in 20 (she can't reach him: a roof he flew to). Just being
	-- slower than him isn't stuck: that rule brought her over every 6 seconds while she walked after him.)
	if d < 700 or not stuck.pos then resetStuck(r, d) return end
	if r.position:distance(stuck.pos) > 150 then stuck.pos, stuck.moveTicks = r.position:copy(), 0 else stuck.moveTicks = stuck.moveTicks + 1 end
	if d < stuck.best - 64 then stuck.best, stuck.closerTicks = d, 0 else stuck.closerTicks = stuck.closerTicks + 1 end
	if stuck.moveTicks >= 12 or stuck.closerTicks >= 40 then
		log("stuck %.0f away (%s)", d, stuck.moveTicks >= 12 and "not moving for 6 seconds" or "no closer in 20 seconds")
		this.bringToPlayer(r)
	end
end

function this.onLoaded()
	handle = nil
	settleTicks = 4
	brain.restart()
	if watch then pcall(function() watch:cancel() end) end
	watch = timer.start({ type = timer.simulate, duration = 0.5, iterations = -1, persist = false, callback = this.tick })
	local r = this.her()
	if r then
		r = look.apply(r) or r   -- (her look, which may have been changed in the menu meanwhile)
		this.applyName(r)
		local st = this.state(r)
		st.down = nil   -- (from 0.1.1's knock-down, gone)
		if st.mode == "wait" then this.wait(r) else this.follow(r) end
		this.restoreStats(r)   -- (first: a level gained since is added on top of her real stats)
		this.catchUp(r)
	end
end

--- The game built her again (she's back near him after being somewhere it had let go of): her stats back.
function this.onMobileActivated(e)
	local r = this.her()
	if r and e.reference == r then this.later(r, this.restoreStats) end
end

function this.onCellChanged(e)
	settleTicks = 2
	if e and e.cell then brain.happened(this.ownerName() .. " went into " .. e.cell.displayName) end
	local r = this.her()
	if not r or (r.mobile and r.mobile.isDead) then return end
	if this.state(r).mode == "follow" and isFar(r) then
		this.later(r, this.bringToPlayer)
	end
end

--- When something goes for him, she goes for it; when he goes for something, she helps.
function this.onCombatStarted(e)
	local r = this.her()
	if e.target == tes3.mobilePlayer and e.actor and e.actor.reference and (not r or e.actor ~= r.mobile) then
		brain.happened(e.actor.reference.object.name .. " attacked " .. this.ownerName())
	end
	if not r or not r.mobile or r.mobile.isDead or this.state(r).mode ~= "follow" then return end
	local me = r.mobile
	if e.target == tes3.mobilePlayer and e.actor ~= me then
		me:startCombat(e.actor)
	elseif e.actor == tes3.mobilePlayer and e.target ~= me then
		me:startCombat(e.target)
	end
end

function this.onLevelUp(e)
	brain.happened(string.format("%s reached level %d, and you leveled up with them", this.ownerName(), e and e.level or tes3.player.object.level))
	this.catchUp()
end

--- A journal entry: the AI hears what it says (shortened).
function this.onJournal(e)
	local text = e.info and e.info.text
	if text and text ~= "" then brain.happened("journal: " .. text:gsub("%s+", " "):sub(1, 180)) end
end

-- ------------------------------------------------------------------ dying, and being revived

--- She died: she stays where she fell, until he revives her at her body.
function this.onDeath(e)
	local r = this.her()
	if r and e.reference == r then
		log("died; waiting to be revived")
		brain.happened("you died")
	elseif e.reference == tes3.player then brain.happened(this.ownerName() .. " died") end
end

--- He used her body: she's back on her feet right there, with her level-ups and look, half her health, following him.
function this.revive(r)
	if not r.mobile or not r.mobile.isDead then return end
	r.mobile:resurrect({ resetState = false })
	this.later(r, function(x)
		if not x.mobile then return end
		this.restoreStats(x)
		tes3.setStatistic({ reference = x, name = "health", current = math.floor(x.mobile.health.base * 0.5) })
		look.apply(x)
		this.state(x).mode = "follow"
		setFollow(x)
		log("revived")
		brain.happened(this.ownerName() .. " revived you")
	end)
end

--- Her character never speaks with the game's own voice (greetings, idle lines, combat shouts, hit sounds): she's the
--- companion from the voice app, and her voice is that one, in the call. The game's voice made her an NPC.
function this.onInfoFilter(e)
	if e.passes == false or not e.dialogue or e.dialogue.type ~= tes3.dialogueType.voice then return end
	local r = this.her()
	if r and e.reference == r then e.passes = false end
end

--- Using her: follow or wait. (No "Talk": the game's chat window made her an NPC. Using her body revives her.)
function this.onActivate(e)
	local r = this.her()
	if not r or e.target ~= r or e.activator ~= tes3.player then return end
	if r.mobile and r.mobile.isDead then this.revive(r) return false end
	local st = this.state(r)
	tes3.messageBox({
		message = r.object.name .. (st.mode == "wait" and " is waiting here." or " is with you."),
		buttons = { "Follow me", "Wait here", "Never mind" },
		callback = function(m)
			if m.button == 0 then this.follow(r)
			elseif m.button == 1 then this.wait(r) end
		end,
	})
	return false
end

function this.init()
	look.init(this)
	event.register(tes3.event.loaded, this.onLoaded)
	event.register(tes3.event.cellChanged, this.onCellChanged)
	event.register(tes3.event.combatStarted, this.onCombatStarted)
	event.register(tes3.event.levelUp, this.onLevelUp)
	event.register(tes3.event.activate, this.onActivate)
	event.register(tes3.event.journal, this.onJournal)
	event.register(tes3.event.death, this.onDeath)
	event.register(tes3.event.infoFilter, this.onInfoFilter)
	event.register(tes3.event.mobileActivated, this.onMobileActivated)
	brain.init(this, this.config)
	log("ready (her AI: %s)", tostring(this.config.url))
end

return this
