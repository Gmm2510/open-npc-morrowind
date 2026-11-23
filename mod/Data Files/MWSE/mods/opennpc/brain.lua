--- Her AI link, the same way Open NPC does it in other games. It asks any address that speaks OpenAI-style "chat
--- completions with tools" what she should do next, and hands the answer to her body (companion.lua). The body does the
--- work; the AI only picks what to do, the way a player would ask a friend.
---
--- When it asks: an app on this PC with the "wait" door (GET address/wait) says he just spoke to her some other way, for
--- example out loud on a voice call (the app adds his words to the next question itself), or a call starts. The door can
--- also give her name: the companion picked in the app, so the one in the game is the one on the call.
--- One question at a time, at most one every 2.5 seconds; whatever comes up while one is out is asked next.

local net = require("opennpc.net")
local socket = require("socket")

local this = {}

local MIN_GAP = 2.5
local log = function(fmt, ...) mwse.log("[Open NPC] " .. fmt, ...) end

local body          -- companion.lua
local config        -- its settings: url, key, model, useAppName
local state = {}

local function reset()
	state = {
		waitOn = nil,       -- the address has the wait door: true, false, or nil (not known yet)
		since = nil,        -- the words count the door last gave
		call = false,
		appName = "",
		model = config and config.model or "",
		busy = false,
		reasons = {},
		lastAsk = -MIN_GAP,
		happened = {},
		done = {},
		napUntil = 0,
		waiting = false,    -- a /wait request is out
		misses = 0,
		asks = 0,
		generation = (state.generation or 0) + 1,
	}
end

local function now() return socket.gettime() end
local function cut(s, n) s = tostring(s or "") return #s <= n and s or s:sub(1, n) end
local function push(list, line, max) table.insert(list, cut(line, 200)) while #list > max do table.remove(list, 1) end end

local function url(path) return (config.url or ""):gsub("/+$", "") .. path end
local function headers() return (config.key and config.key ~= "") and { Authorization = "Bearer " .. config.key } or nil end

--- The name she goes by: the app's, if it gives one and that's allowed, else her settings' name.
function this.appName() return state.appName end
function this.waitDoor() return state.waitOn end
function this.busy() return state.busy end
function this.asks() return state.asks end

--- Something worth a question came up: ask as soon as it's allowed.
function this.want(reason) state.reasons[reason] = true end

--- Something happened in the game; a line of it goes in the next question.
function this.happened(line) if line and line ~= "" then push(state.happened, line, 8) end end

-- ------------------------------------------------------------------ the question

function this.system()
	local name, owner = body.name(), body.ownerName()
	local l = {
		string.format("You control %s, a companion character in the world of The Elder Scrolls III: Morrowind, travelling with %s through the whole game.", name, owner),
		string.format("You only decide what %s does: call the act tool. The body follows, waits, fights and catches up by itself and tells you how it went.", name),
		string.format("When %s asks for something, do it right away with act. Take the obvious reading of what they want.", owner),
		string.format("When nobody asked for anything, keep doing what %s is doing, or do nothing.", name),
		state.waitOn and "Your words are never shown to anyone: when there is something to do, only call the tool; when there is nothing to do, answer with just \"nothing to do\"."
			or string.format("Anything you write besides the tool call shows up on screen as %s's words: keep it to one short, casual line, or nothing.", name),
		"Rules: never claim to be human. No slurs, hate, sexual content or dangerous real-world advice. Never ask for personal information.",
		"",
	}
	local acts = {}
	for _, a in ipairs(body.actions()) do table.insert(acts, a.name .. " (" .. a.about .. ")") end
	table.insert(l, "Actions: " .. table.concat(acts, ", ") .. ".")
	return table.concat(l, "\n")
end

function this.tools()
	local names = {}
	for _, a in ipairs(body.actions()) do table.insert(names, a.name) end
	return { {
		type = "function",
		["function"] = {
			name = "act",
			description = string.format("Make %s do something in the game. One action per call; the body carries it out by itself.", body.name()),
			parameters = {
				type = "object",
				properties = {
					action = { type = "string", enum = names, description = "What to do." },
					args = { type = "object", description = "Only the details the player gave. No details: {}." },
				},
				required = { "action" },
			},
		},
	} }
end

local function situationText()
	local out = {}
	for _, kv in ipairs(body.situation()) do
		if kv[2] and kv[2] ~= "" then table.insert(out, "- " .. kv[1] .. ": " .. kv[2]) end
	end
	return table.concat(out, "\n")
end

--- The question as it goes out (also used by the tests).
function this.question(reasons)
	local owner = body.ownerName()
	local parts = {}
	local sit = situationText()
	table.insert(parts, "Now:\n" .. (sit ~= "" and sit or "- just joined"))
	if #state.done > 0 then table.insert(parts, "What you were told to do lately:\n- " .. table.concat(state.done, "\n- ")) end
	if #state.happened > 0 then table.insert(parts, "What happened:\n- " .. table.concat(state.happened, "\n- ")) end
	if reasons.call and not reasons.words then table.insert(parts, owner .. " is with you now.") end
	local req = {
		messages = { { role = "system", content = this.system() }, { role = "user", content = table.concat(parts, "\n\n") } },
		tools = this.tools(),
		tool_choice = "auto",
		max_tokens = 400,
		stream = false,
	}
	if state.model and state.model ~= "" then req.model = state.model end
	return req
end

local function answer(raw, playerAsked)
	state.asks = state.asks + 1
	local res = json.decode(raw)
	local choice = res and res.choices and res.choices[1]
	local msg = choice and choice.message
	if not msg then log("the AI answered with nothing") return end
	local text = type(msg.content) == "string" and msg.content:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if text ~= "" and not state.waitOn and text:lower() ~= "nothing to do" then body.say(cut((text:gsub("%s+", " ")), 240)) end
	local n = 0
	for _, c in ipairs(msg.tool_calls or {}) do
		if n >= 2 then break end
		local input = {}
		local a = c["function"] and c["function"].arguments
		if type(a) == "table" then input = a elseif type(a) == "string" then input = json.decode(a) or {} end
		local action = type(input.action) == "string" and input.action:gsub("%s", "") or ""
		if action ~= "" then
			n = n + 1
			local args = type(input.args) == "table" and input.args or {}
			local ok, why = body.command(action, args, playerAsked)
			local how = ok and "started" or ("didn't start (" .. tostring(why) .. ")")
			push(state.done, action .. ": " .. how, 4)
			log("does %s: %s", action, how)
		end
	end
	if n == 0 then log("no move%s", text ~= "" and (": \"" .. cut(text, 120) .. "\"") or "") end
end

local function ask()
	local reasons = state.reasons
	state.reasons = {}
	state.busy = true
	state.lastAsk = now()
	local playerAsked = reasons.words or reasons.call or false
	local req = this.question(reasons)
	state.happened = {}
	local gen = state.generation
	net.request({ method = "POST", url = url("/chat/completions"), body = json.encode(req), headers = headers(), timeout = 60,
		done = function(status, raw, err)
			if gen ~= state.generation then return end
			state.busy = false
			if err then log("couldn't reach the AI: %s", err) return end
			if math.floor((status or 0) / 100) ~= 2 then log("couldn't reach the AI: %s %s", tostring(status), cut(raw, 200)) return end
			local ok, e = pcall(answer, raw, playerAsked)
			if not ok then log("the AI's answer couldn't be read: %s", tostring(e)) end
		end })
end

-- ------------------------------------------------------------------ the wait door

local function findModel()
	if state.model and state.model ~= "" then return end
	local gen = state.generation
	net.request({ method = "GET", url = url("/models"), headers = headers(), timeout = 5, done = function(status, raw)
		if gen ~= state.generation or math.floor((status or 0) / 100) ~= 2 then return end
		local j = json.decode(raw or "")
		local id = j and j.data and j.data[1] and j.data[1].id
		if id and (not state.model or state.model == "") then state.model = id log("model %s", id) end
	end })
end

local function cleanName(s)
	if type(s) ~= "string" then return "" end
	s = s:gsub("[%c\"]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return s:sub(1, 24)
end

local function waitOnce()
	state.waiting = true
	local q = state.since == nil and "" or string.format("?since=%d&call=%d&ms=25000", state.since, state.call and 1 or 0)
	local gen = state.generation
	net.request({ method = "GET", url = url("/wait" .. q), headers = headers(), timeout = 35, done = function(status, raw, err)
		if gen ~= state.generation then return end
		state.waiting = false
		if status == 404 then
			if state.waitOn ~= false then log("this AI has no wait door; she follows the menu only") end
			state.waitOn, state.since = false, nil
			state.napUntil = now() + 60
			return
		end
		if err or math.floor((status or 0) / 100) ~= 2 then
			state.misses = state.misses + 1
			if state.misses == 1 or state.misses % 10 == 0 then log("can't reach her AI at %s: %s", url("/wait"), tostring(err or status)) end
			if state.misses == 1 and state.waitOn == nil then state.waitOn = false end
			state.napUntil = now() + math.min(30, 2 ^ math.min(state.misses, 5))
			return
		end
		local j = json.decode(raw or "") or {}
		if state.waitOn ~= true then log("the wait door is there: she listens the moment you speak") end
		state.waitOn, state.misses = true, 0
		local words = tonumber(j.words) or 0
		local nowCall = j.call == true
		local named = cleanName(j.name)
		if named ~= state.appName then
			state.appName = named
			log(named == "" and "the app gives her no name" or ("the app calls her " .. named))
			body.nameChanged()
		end
		if state.since ~= nil and words > state.since then this.want("words") end
		if nowCall and not state.call then this.want("call") end
		state.since, state.call = words, nowCall
	end })
end

-- ------------------------------------------------------------------ running

--- Every frame: moves the open requests along, keeps the door open, asks when there's a reason.
function this.frame()
	net.pump()
	if not body or not config or not config.url or config.url == "" then return end
	if not state.waiting and now() >= state.napUntil then waitOnce() end
	if state.busy or next(state.reasons) == nil or not body.ready() then return end
	if now() < state.lastAsk + MIN_GAP then return end
	ask()
end

function this.init(companion, settings)
	body, config = companion, settings
	reset()
	findModel()
	event.register(tes3.event.enterFrame, function() local ok, e = pcall(this.frame) if not ok then log("link error: %s", tostring(e)) end end)
end

--- A new game or a load: no reply from before lands in it.
function this.restart()
	net.cancelAll()
	local keepName = state.appName
	reset()
	state.appName = keepName
	findModel()
end

return this
