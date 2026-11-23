-- Open NPC for Morrowind. Needs OpenNPC.esp (her person) in the load order.
local companion = require("opennpc.companion")
local menu = require("opennpc.menu")

-- (her look menu, in Esc > Mod Config)
event.register(tes3.event.modConfigReady, function() menu.register() end)

event.register(tes3.event.initialized, function()
	if not tes3.getObject(companion.NPC_ID) then
		mwse.log("[Open NPC] OpenNPC.esp isn't loaded: turn it on in the Morrowind Launcher's Data Files list.")
		return
	end
	companion.init()
end)
