--- A small HTTP client that never blocks the game: each request moves along a little every frame (connect, send,
--- read), and calls `done(status, body, err)` once, on the game's main thread. Plain http:// only, which is all a local
--- app needs. Uses MWSE's LuaSocket.

local socket = require("socket")

local this = {}
local jobs = {}

local function parseUrl(url)
	local host, port, path = tostring(url):match("^http://([^/:]+):?(%d*)(.*)$")
	if not host then return nil end
	return host, tonumber(port) or 80, (path ~= "" and path) or "/"
end

local function finish(job, status, body, err)
	if job.finished then return end
	job.finished = true
	pcall(function() job.tcp:close() end)
	local ok, e = pcall(job.o.done, status, body, err)
	if not ok then mwse.log("[Open NPC] a reply handler failed: %s", tostring(e)) end
end

local function dechunk(s)
	local out, i = {}, 1
	while true do
		local nl = s:find("\r\n", i, true)
		if not nl then break end
		local size = tonumber(s:sub(i, nl - 1):match("^%x+"), 16)
		if not size or size == 0 then break end
		table.insert(out, s:sub(nl + 2, nl + 1 + size))
		i = nl + 2 + size + 2
	end
	return table.concat(out)
end

--- Tries to read a whole response out of what has arrived; returns status, body when it's complete.
local function parse(job, closed)
	local data = job.data
	local headEnd = data:find("\r\n\r\n", 1, true)
	if not headEnd then return nil end
	local head = data:sub(1, headEnd - 1)
	local status = tonumber(head:match("^HTTP/%d%.%d (%d%d%d)"))
	local body = data:sub(headEnd + 4)
	local length = tonumber(head:lower():match("\ncontent%-length:%s*(%d+)"))
	local chunked = head:lower():find("\ntransfer%-encoding:%s*chunked") ~= nil
	if length then
		if #body >= length then return status, body:sub(1, length) end
		return nil
	end
	if chunked then
		if body:find("\r\n0\r\n", 1, true) or body:sub(1, 3) == "0\r\n" or closed then return status, dechunk(body) end
		return nil
	end
	if closed then return status, body end
	return nil
end

--- Starts a request. o = { method, url, body (string or nil), headers (table or nil), timeout (seconds), done }.
function this.request(o)
	local host, port, path = parseUrl(o.url)
	if not host then o.done(nil, nil, "not an http:// address: " .. tostring(o.url)) return end
	local tcp = socket.tcp()
	tcp:settimeout(0)
	local lines = { string.format("%s %s HTTP/1.1", o.method or "GET", path), string.format("Host: %s:%d", host, port), "Connection: close" }
	for k, v in pairs(o.headers or {}) do table.insert(lines, k .. ": " .. v) end
	if o.body then
		table.insert(lines, "Content-Type: application/json")
		table.insert(lines, "Content-Length: " .. #o.body)
	end
	local job = { o = o, tcp = tcp, host = host, port = port, stage = "connect", out = table.concat(lines, "\r\n") .. "\r\n\r\n" .. (o.body or ""),
		sent = 0, data = "", deadline = socket.gettime() + (o.timeout or 30) }
	local ok, err = tcp:connect(host, port)
	if not ok and err ~= "timeout" and err ~= "Operation already in progress" then finish(job, nil, nil, "can't connect: " .. tostring(err)) return end
	if ok then job.stage = "send" end
	table.insert(jobs, job)
	return job
end

local function step(job)
	if job.finished then return end
	if socket.gettime() > job.deadline then finish(job, nil, nil, "timed out") return end
	if job.stage == "connect" then
		local _, writable = socket.select(nil, { job.tcp }, 0)
		if writable and #writable > 0 then
			if job.tcp:getpeername() then job.stage = "send" else finish(job, nil, nil, "connection refused") return end
		else
			return
		end
	end
	if job.stage == "send" then
		local last, err, partial = job.tcp:send(job.out, job.sent + 1)
		local upto = last or partial or job.sent
		job.sent = upto
		if err and err ~= "timeout" then finish(job, nil, nil, "send failed: " .. err) return end
		if job.sent >= #job.out then job.stage = "read" else return end
	end
	if job.stage == "read" then
		while true do
			local data, err, partial = job.tcp:receive(8192)
			local got = data or partial
			if got and #got > 0 then job.data = job.data .. got end
			if err == "closed" then
				local status, body = parse(job, true)
				if status then finish(job, status, body) else finish(job, nil, nil, "connection closed early") end
				return
			end
			if err == "timeout" or not got or #got == 0 then break end
		end
		local status, body = parse(job, false)
		if status then finish(job, status, body) end
	end
end

--- Moves every open request along. Called every frame.
function this.pump()
	if #jobs == 0 then return end
	for _, job in ipairs(jobs) do
		local ok, e = pcall(step, job)
		if not ok then finish(job, nil, nil, "error: " .. tostring(e)) end
	end
	local open = {}
	for _, job in ipairs(jobs) do if not job.finished then table.insert(open, job) end end
	jobs = open
end

--- Drops every open request (on load, so a reply from before never lands in a new game).
function this.cancelAll()
	for _, job in ipairs(jobs) do job.finished = true pcall(function() job.tcp:close() end) end
	jobs = {}
end

return this
