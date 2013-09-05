 -- Module Scheduler
local base=_G
local CallbackProxy=require("CallbackProxy");
local json=require("json");

local M={}

local threadTable,lastThread={},nil
local stateName=nsis.stateName()
local function Empty(...)
end

local SCHED="Scheduler|"
local DebugPrint,DebugPrintF,ErrorPrint=_G.DebugPrint or Empty,_G.DebugPrintF or Empty,_G.ErrorPrint or Empty

function M.done()
    return M.done;
end
function M.defer()
    return M.defer;
end



local updateSeq=0;
--Update the Queue state in the main thread
function M.updateQueueState(newstate)
    updateSeq=updateSeq+1;
    DebugPrintF("%sUpdateQueueState -> %s",SCHED,tostring(newstate));
    nsis.evalLater(1,string.format("setQueueState(%s,%d)",tostring(newstate),updateSeq))
end

-- Determin that the scheduler has no more work to do 
function M.isComplete()
    return table.getn(threadTable) == 0;
end

local function findThreadRecord(thread) 
    for idx,rec in ipairs(threadTable) do
        if rec.thread == thread then 
            return idx,rec
        end
    end
    return nil
end
local function removeRec(rec) 
    for _idx,_rec in ipairs(threadTable) do
        if _rec == rec then 
            table.remove(threadTable,_idx); -- Remove the Lead item on the thread Table.
            return true;
        end
    end
    return false;
end
--[[
-- Coroutine based pcall 
-- Function will perform a pcall like 
-- operation on the specified thread
--]]
function M.pcall(thread)
    --This is the thread that is calling us 
    local _idx,_rec= findThreadRecord(lastThread); 
    if _idx == nil then  -- Somehow thread is not scheduled
        ErrorPrint("%sAttempt to call Scheduler.call from non active(%s)",SCHED,tostring(thread));
        return false,"Scheduler.pcall can only be called from the active thread";
    end 
    -- If we are passed a function create a coroutine for it
    if type(thread) == "function" then
        local _func=thread;
        thread=coroutine.create(function(...)
            return _func(...)
        end);
    end

    -- Place this new thread in the callstack ahead of the lastThread
    table.insert(threadTable,_idx,{thread=thread,prio=_rec.prio,caller=_rec.thread})
    DebugPrintF("%sYielding Pcall to %s",SCHED,tostring(thread))
    local ret={coroutine.yield(M.pcall,thread)}
    DebugPrintF("%sResumed from Pcall With:%s",SCHED,table.tostring(ret))
    return unpack(ret);
end

--[[
-- Schedule thread to run with data as it arguments
-- thread = coroutine for running an install,
-- data =  table of orguments
-- when called from a proxy it may be {json.null()}
--]]
function M.run(thread,data,prio)
   if table.getn(data) == 1 and data[1] == json.null() then 
       data={};
   end
   while(M.paused()) do
       socket.select(nil,nil,0.05);
       if M.cancelled()  then    
           threadTable={}; -- Wipe out the thread table 
           lastThread=nil;
           M.updateQueueState(true);
           return;
       end
   end


   -- There are other thread on there so lets go ahead and push this one on and wait
   local needinsert,runnow=true,false;
   local rec=nil;
   if table.getn(threadTable)  > 0 then 
       -- Look for this thread if its in there then we break out
       -- If its the first we will also run it now
       for i,_rec in ipairs(threadTable) do 
           if _rec.thread == thread then 
               rec=_rec;
               rec.waiting=nil;
               needinsert=false;
               break;
           end
       end
   else
       runnow=true
       needinsert=true
   end
   if needinsert then
       DebugPrintF("Queued Thread:%s",tostring(thread))
       rec={["thread"]=thread,["data"]=data,
       ["prio"]=prio or  0};
       table.insert(threadTable,rec);
   else
       rec.data=data; -- Update the data
   end
   --Find the best thread to schedule
   M.updateQueueState(false);
   rec=nil;
   local active=nil;
   for i,_rec in ipairs(threadTable) do 
       if rec == nil then -- Pick the first record  
           rec=_rec
       else
           if _rec.prio > rec.prio then  -- with the best proirity
               rec=_rec;
           end
           --Everything else will be sorted by order
       end
   end
    --NO best record or best is waiting 
   if rec == nil or rec.waiting == true then  return  end
   -- Insert the thread we are about to run into the table.
   DebugPrintF("%sResuming:%s",SCHED,tostring(thread));
   lastThread=thread;
   local ret={coroutine.resume(thread,unpack(data))}
   if not ret[1] then  
        removeRec(rec) -- Remove the thread from the table.
       if rec.caller then  -- This was a pcall and it failed so we will schedule its caller with the message
           return M.run(rec.caller,{false,ret[2]});
       end
       local stacktrace=debug.traceback(thread)
       ErrorPrint("%sFailed:%s\n%s",SCHED,table.tostring(ret),stacktrace);
       return;
   end

   if CallbackProxy.isPending(ret[2]) then -- Callback pending 
       DebugPrintF("%sThread -> Proxy:%s",SCHED,tostring(thread));
       CallbackProxy.pending(thread,ret[3],M.run); 
       rec.waiting=true; -- Mark as waiting
       M.updateQueueState(false);
       return
   elseif ret[2] == M.pcall then 
       -- Someone is setting up a pcall from a coroutine
       --This is a pcall 
       rec.calling=true 
       -- Thread is already in the table so this shouldnt be wierd at all
       DebugPrintF("%spcall(%s) ->%s",SCHED,tostring(ret[2]),tostring(ret[3]));
       return M.run(ret[3],{}); -- Schedule this new Thread.
       --[[elseif ret[2] == M.defer then
       DebugPrintF("Thread -> Defer:%s",tostring(thread))
       -- return M.run(tt.thread,nil)
       ]]--
   elseif ret[2] == M.done then 
       removeRec(rec);
      DebugPrintF("%sComplete(%s) ( %d remaining)",SCHED,tostring(thread),table.getn(threadTable));
       if table.getn(threadTable) == 0 then 
           M.updateQueueState(true);
           return 
       end
       local tt=threadTable[1]
       --RUn the next item on the queue
       return M.run(tt.thread,tt.data)
   elseif rec.caller then  -- THis was a pcall thread So we will  schedule the caller with the data we got.
       removeRec(rec); --
       DebugPrintF("%sResuming(%s) from pcall %s",SCHED,tostring(thread),tostring(rec.thread))
       return M.run(rec.caller,{true,select(1)})
   else
       local stacktrace=debug.traceback(thread)
       ErrorPrint("%sDangling Coroutine!!!!! <- Thread(%s) -> %s\n%s",SCHED,tostring(thread),table.tostring(ret),stacktrace);

   end
end


function M.paused() 
    return nsis.paused(stateName) == 1;
end

function M.cancelled()
    return nsis.cancel(stateName) == 1;
end



 
--Some magic here so the scheulder module can be called
setmetatable(M,{
    __call=function(t,...)
        return M.run(...);
    end
});


return M;
