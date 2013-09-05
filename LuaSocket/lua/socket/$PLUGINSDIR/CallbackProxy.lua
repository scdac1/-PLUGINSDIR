--[[
Callback Proxy to allow asynchronous calls be synchronized a bit.
--]]
local M = {}
local base =_G;
local json,mime=require("json"),require("mime");
local stateName=nsis.stateName()

--List of registerd callbacks
local callbackTable={} 
local forceLocal=false;
local function Empty()
end
-- nsis.messageBox(string.format("Setting Up Callback Proxy:%s",debug.traceback()));
local DebugPrint,DebugPrintF,ErrorPrint=_G.DebugPrint or Empty,_G.DebugPrintF or Empty,_G.ErrorPrint or Empty

function M.registerLuaCallback(name,handler)
    callbackTable[name]=function(...)
        return handler(...)
    end
end


function M.invoke(name,...)
    return M.invokeWithToken(name,nil,{...});
end

--[[
-- Call a handler through the proxy and 
-- optionally if its local reutnr a table of the results.
--]]
function M.invokeWithToken(name,token,args)
    if callbackTable[name] ~= nil then 
        handler=callbackTable[name]
        local good,resp=pcall(function()
            return {handler(unpack(args))}
        end)
        if not good then
            DebugPrintF("Handler (%s) with args(%s) failed (%s)",name,table.tostring(args),resp);
            error(resp)
        end
        return nil;
    end
    if forceLocal then
        ErrorPrint("No handler found for:%s",name);
        return nil
    end
    local data=json.encode({["name"]=name,["args"]=args})
    --${Eval} "nsis.evalInState([[+prepare]],string.format([[init_downloads=json.decode((mime.unb64('%s')))]],(mime.b64(json.encode(init_downloads)))))"
    if token == nil then
        token="";
    end
    return string.format("CallbackProxy.run('%s','%s','%s')",mime.b64(data),token,stateName),data
end

--[[
-- Calla  hander t
--]]
function M.call(name,...)
   local ret=M.invoke(name,...) 
   --Never need ot worry about this as its delayed execution
   if ret ~= nil  then
       nsis.evalLater(0,ret);
   end
end

local lastToken=0;
local pendingTable={}
function M.invokeForResp(name,...)
    local args={...}
    -- In the event ther eis a proxy handler on this side we dont
    -- have to send this to the other queue
    -- we can basically invoke the  handler here./
    if callbackTable[name] ~= nil then
        handler=callbackTable[name]
        local good,resp=pcall(function()
                return {handler(unpack(args)),nil}
        end)
        if not good then 
            DebugPrintF("Handler (%s) with args(%s) failed (%s)",name,table.tostring(args),resp);
            error(resp);
        end
        return unpack(resp)
    end
    local retToken=string.format("_%s",lastToken);
    lastToken=lastToken+1;
    local toexec,rawdata=M.invokeWithToken(name,retToken,{...});
    -- Check to see if we can ahndle this without leaving tthe thread and all that
    DebugPrintF("CallbackProxy-Requesting:[%s]%s",retToken,rawdata)
    _G.nsis.evalLater(1,toexec); -- Invoke the callback in non blocking mode (1 in  delay)
    return coroutine.yield(M.pending,retToken);
end

--[[ Assuming we get a thread that is waiting and the token 
--we will need a function to give the result value to get the thread started again.
--]]
function M.pending(thread,_token,sched)
    -- Pending Table.
    pendingTable[_token]={["thread"]=thread,["sched"]=sched}
end
function M.isPending(val)
    return val ==M.pending 
end
--[[
-- Resume the CallbackProxu
-- token => A callback token 
-- args => Arguments to be returned.
--]]
function M.resume(_token,args)
    if type(args) == 'string' then
        args=json.decode(mime.unb64(args))
    end
    local entry=pendingTable[_token];
    if entry == nil then
        DebugPrintF("CallbackProxy-Resume:No Entry Found (token='%s')",_token);
        return 
    end;
    DebugPrintF("CallbackProxy-Resuming:%s",table.tostring(args))
    pendingTable[_token]=nil; -- Remove the entry
    --Resume the Scheduler.
    return entry.sched(entry.thread,args); -- Tail Call.
end

function M.forceLocal(newval)
    forceLocal=newval;
end

function M.run(t,token,src_state)
    if type(t) == "string" then
        t=json.decode(mime.unb64(t))
    end
    DebugPrintF("CallbackProxy-Request:#%s|%s",token or "-",table.tostring(t))
    local args=t.args
    local name=t.name
    --Args or Name is Nil then Stop
    if args ==nil or name == nil then
        return nil
    end
    local handler=callbackTable[name] --  Callback Table.
    local good,results=pcall(function()
        return {handler(unpack(args))}
    end)
    if not good then 
        DebugPrintF("Handler (%s) with args(%s) failed (%s)",name,table.tostring(args),results);
        results= {json.null()}
    end
    --Todo Handle Responses
    if token  ~= nil and token ~= '' then --  Respone was wanted
        local _results=json.encode(results)
        torun=string.format("CallbackProxy.resume('%s','%s')",token,mime.b64(_results))
        DebugPrintF("CallbackProxy-Response:(state=>%s),%s",src_state,torun)
        nsis.evalInState(src_state,torun)
        DebugPrintF("CallbackProxy-Response:(Response Sent!)=> %s",_results);
    end
end
--Put the Proxy in Glboal Space
_G.CallbackProxy=M
return M;
