-- This file name is a MISNOMER. it is called on init.
--Lua code that is run when the Installer is loaded.
-- Load up Lua Xml
-- For Lua Xml and Lua Socket we need to fix Cpath and Path
package.cpath=package.cpath .. ';' .. PLUGINSDIR .. [[\?.dll;]]..PLUGINSDIR..[[\LuaSocket\?.dll]]
package.path=package.path .. ';' .. PLUGINSDIR .. [[\?.lua;]]..PLUGINSDIR..[[\LuaSocket\lua\?.lua]]

local _Downloads=require("Downloads")
http=require("socket.http");


--Expose some stuff globally
download_file=_Downloads.downloadFile
standardProgress=_Downloads.standardProgress
