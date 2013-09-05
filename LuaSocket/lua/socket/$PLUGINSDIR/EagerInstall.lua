--[[
--Eager Installation Code Path
-- require "Definitions.lua" and "Utils.lua"
-- ]]
--
if no_path_change == nil then
package.cpath=package.cpath .. ';' .. PLUGINSDIR .. [[\?.dll;]]..PLUGINSDIR..[[\LuaSocket\?.dll]]
package.path=package.path .. ';' .. PLUGINSDIR .. [[\?.lua;]]..PLUGINSDIR..[[\LuaSocket\lua\?.lua]]
end 

local json,mime=require("json"),require("mime");
local _Downloads=require("Downloads");
local CallbackProxy=require("CallbackProxy");
local _BundleInstall=require("BundleInstall");
local _ProcessFreeFile=require("ProcessFreeFile");
local _Env=require("Env")
local socket=require("socket"); -- WE need this to update user agent
http=require("socket.http");
local scheduler=require("scheduler");
local done,defer=scheduler.done,scheduler.defer
local sandbox=require("sandbox");

--[[
--
--]]
local function install_process(bundleIndex)
    --Prefilight the bundle first
    _Env.precalcInstallProgress(bundleIndex); 
    local bundle= _Env.getBundle(bundleIndex);
    _BundleInstall.PrepareInstall(bundle,_BundleInstall.PHASE_INSTALL,{});
    --Manual Install Primary   and this is aprimary then we skip
    if _Env.getSkinOptions().manual_install_primary 
        and bundle.isPrimary then
        return done();
    end
    -- IF we are installing at finish then same thing we go ahead and skip
    if install_at_finish then return end;
    -- Install the Bundle
    _BundleInstall.InstallBundle(bundle);
    return done()
end

local function defer_install_process()
    _BundleInstall.DoDeferredInstall()
    return done();
end

-- Start Installation of a bundle
function  startInstall(bundleIndex)
    local co=coroutine.create(install_process)
    -- Schedule the installer.
    DebugPrintF("[SCHED]Bundle[%d]:Install ",bundleIndex);
    scheduler(co,{bundleIndex})
end

--[[
-- Basically a containuation that can be invoked later.
--]]
function resumeMainAt(addr,...)
    local co=coroutine.create(function(addr,...)
        _Env.resumeMainAt(addr,...);
        return done()
    end)
    local args={...}
    DebugPrintF("[SCHED]Resuming at %d(%s)",addr,table.tostring(args));
    scheduler(co,{addr,...});
end

function startInstallSection()
    DebugPrintF("[SCHED]Starting InstallSection");
    local co=coroutine.create(function()
        _BundleInstall.SectionInstall()
        return done()
    end);
    scheduler(co,{});
end

function startDeferInstalls()
    local co=coroutine.create(defer_install_process);
    DebugPrintF("[SCHED]Starting DeferInstalls");
    scheduler(co,{});
end

function  startProcessFreeFile(action,currentbundle)
    local co=coroutine.create(function(action,opts)
        _ProcessFreeFile.processFreeFiles(action,opts);
        return done()
    end)
    local prio=0;
    DebugPrintF("[SCHED]ProcessFreeFile(%s,%s)",action,tostring(currentbundle))
    if action == "offer" then prio=1 end
    scheduler(co,{action,{CurrentBundle=currentbundle}},prio);
end

local defer_pause_loop=function()
    DebugPrint("Pause Loop Called!");
    coroutine.yield(defer())
end

function boot()
    DebugPrintF("Done is %s,Defer is %s",tostring(done),tostring(defer))
    scheduler.updateQueueState(false);
    --Replace sandbox pcall with scheduler pcall
    sandbox.updatePcall(scheduler.pcall);
    --Se thte dowload system to yield into the scheduiler
    --Cant Quite do this yet. But thats Ok lets not sweat it for now
    --The problem is that this is called from a c-function upstack
    --and as a result i cannot yield out of the coroutine
    --_Downloads.setPauseLoop(defer_pause_loop)
    -- TODO: When we talk about deflate or other compression think about what
    -- this means with respect to pausing
    _Downloads.useByteRange(true)
end

function isComplete()
    if scheduler.isComplete() then
        return 1
    end
    return 0;
end

function setArchPluginsDir(nsisname,_7zname)
    _ProcessFreeFile.setUnzipPlugin(string.format("%s.dll",nsisname));
    _ProcessFreeFile.set7zPlugin(string.format("%s.dll",_7zname));
end

--[[returns true when there is nothing left to schedule]]--
