--[[
-- Event Management framework to decouple install events from 
-- rest of the code that needs them 
-- at its core it maps names to a list of functions.
-- The functions are the handlers for the events 
--
--]]
EVT_DOWNLOAD_START=1 
EVT_DOWNLOAD_END=2
EVT_INSTALL_START=3
EVT_INSTALL_END=4

EVENT_MAP= {}

--Fire off an Event
function EVENT_MAP:add_event_handler(name,fn)
    if self[name]==nil then
    self[name]={fn}
    else
      table.insert(self[name],fn)
    end
end

--Fire Off and Event
function EVENT_MAP:fire_event(name,data)
    DebugPrint("Firing Event " .. name)
    local handlers=self [name];
    if handlers ==nil then return end
    for k,v in ipairs(handlers) do 
        pcall(function() v(data) end)
    end
end 
--Test Event Handler
--[[
EVENT_MAP:add_event_handler(EVT_INSTALL_START,function(dta) 
  nsis.messageBox("Install Started")
end)
--]]
