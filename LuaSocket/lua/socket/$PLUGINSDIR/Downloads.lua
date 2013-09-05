

local base = _G



local socket = require("socket") -- need sockets
local http = require("socket.http")
local url = require("socket.url")
local ltn12 =require("ltn12")
local ftp = require("socket.ftp");
local net=base.net;

_G.SIMPLE_CANCEL=0
_G.queryCancelCallback=nil;
-- if true we willuse a byte range download where possible.
_G.USE_BYTE_RANGE=false

local P={} -- Private Variables
local stateName=nsis.stateName();

P.DebugPrint=_G.DebugPrintF or function(...)
end
local DebugPrint=P.DebugPrint

local DebugPrintF=P.DebugPrint
local ErrorPrint=P.DebugPrint


--Standard  progress hook
local function standardProgress(bundle)
    return function(msg,min,max,step,can_pause)
        local torun=string.format([[InstallProgress(%d,"%s",%d,%d,%d,%d)]],
        bundle,msg,min,max,step,can_pause);
        nsis.evalLater(0,torun)
    end
end

local function notifyprogress(pt,forced)
    local lasttime=pt.lasttime or 0.0;
    local now=os.clock()
    if pt.callback ~=  nil and (((now - lasttime) > 0.1) or forced) then
        if type(pt.callback) == 'function' then
            -- Downloaded 
            pt.callback("Downloading",pt.downloaded,pt.length,pt.download_step,
            pt.can_pause);
        else
            nsis.push(tostring(pt.download_step))
            nsis.push(tostring(pt.length))
            nsis.push(tostring(pt.downloaded));
            nsis.push(tostring("Downloading"));
            nsis.callback(pt.callback)
        end
        pt.lasttime=now;
    end

end




local function def_pause_loop()
    while(nsis.paused(stateName) == 1 ) do
        socket.select(nil,nil,0.05);
        if nsis.cancel(stateName)==1  then  return; end
    end
end
-- Spin while paused and NOT cancelled
P.pause_loop=def_pause_loop

--
-- A sink that writes to the end of a file.
--
local function nonclosingfilesink(fle,pt)
    return ltn12.sink.chain(function(chunk)
        if nsis.cancel(stateName) == 1 then
            error({type="cancel"});
        end
        if chunk ~= nil then 
            fle:write(chunk);
            pt.downloaded = pt.downloaded + string.len(chunk)
            notifyprogress(pt);
        end
        --Filter never leaves data 
        return chunk;
    end
    ,ltn12.sink.null());
end

local function sinkfor(filename,pt)
    return ltn12.sink.chain(function(chunk)
        --Filter to cancel if thread/state has been cancelled.
        P.pause_loop();
        if nsis.cancel(stateName) == 1 then
            error({type="cancel"});
        end
        if(chunk ~= nil) then
            pt.downloaded = pt.downloaded + string.len(chunk)
            notifyprogress(pt);    
        end
        return chunk;
    end,
    ltn12.sink.file(io.open(filename,"w+b")));
end

--[[
-- Parse a content range header
--]]
local function parseContentRangeHeader(hdr)
    -- bytes 0-102399/52213920
    local _type,_start,_end,_total = string.find(hdr,"([A-Za-z0-9]+) (%d+)-(%d+)/(%d+)")
    return {
        ['len'] = _total,
        ['start'] = _start,
        ['end'] = _end,
        ['type']=_type
    }

end

--[[
-- Get the Proxy for a  Url
--]]
local function proxy_for_url(source_url)
    if true then
        return nil;
    end
    local parsed=url.parse(source_url);
    local good,hostormsg=net.ProxyForUrl(source_url,parsed.host);
    if good then
        if string.len(hostormsg)  == 0 then 
            ErrorPrint("Proxy:Blank Host for(%s)",source_url);
            return nil
        end
        return hostormsg;
    end
        ErrorPrint("Proxy:Failed for Host(%s,rc=%s)",source_url,
        tostring(hostormsg))
        return nil
end
--[[
-- Download a File from {source_url} -> {filename}
--]]
local function download_file(source_url,filename,progress_addr,
    download_step,allow_range,file_size)
    local parsed=url.parse(source_url);
    local good=false;
    local err="unsupported";
    local rcode=nil;
    local rheaders=nil;
    local progress_table={
        ['downloaded']=0,
        ['download_step']=download_step,
        ['length']=0,
        ['callback']=progress_addr,
        ['can_pause']  = 0
    }
    local e,msg= pcall(function()
        if parsed.scheme == "ftp" then
            local havesize=ftp.get{url=source_url,command="size",
            continue_handler=function(code,reply)
                if code==213  then
                    progress_table.length = tonumber(reply:sub(5)) or 0
                end
                return 0;
            end
        }
        good,err =  ftp.get{url=source_url,
        sink=sinkfor(filename,progress_table)};
    elseif parsed.scheme ==  "http" then
        local proxy_host=proxy_for_url(source_url);
        if _G.USE_BYTE_RANGE and allow_range and file_size ~= nil and file_size > 0 then
            local bytes_downloaded=0 
            local fle=io.open(filename,"wb") -- open file for writing:
            local target_sink=nonclosingfilesink(fle,progress_table);
            local currOff=0
            local blocksize=102400
            progress_table.length =file_size; 
            repeat
                local farRange=currOff + blocksize -1;
                farRange=math.min(farRange,file_size-1)
                local _headers={
                    ["Range"] = string.format("bytes=%d-%d",currOff,farRange)
                }
                good,rcode,rheaders= http.request{url=source_url,
                proxy=proxy_host,
                headers=_headers,
                beforebody=function(code,headers)
                    local len=tonumber(headers['content-length']);
                    local cr=headers['content-range']
                    if code == 200 then
                        if len == nil then return end
                        bytes_downloaded=bytes_downloaded +  len
                    elseif code == 206 then
                        if len == nil then return end
                        if cr ~= nil then
                            local details=parseContentRangeHeader(cr);
                            currOff = currOff +  len;
                            -- Add to the number of bytes downloaded.
                            bytes_downloaded= bytes_downloaded+len
                            -- Progress Table length
                            progress_table.can_pause=1
                        end
                    end

                end,
                sink=target_sink};
                -- Error or non partial responses mean fail
                if rcode ~= 200 and rcode ~= 206 then
                    ErrorPrint(string.format("Request Failed(rc=%d)",rcode));
                    good=0;
                end
                P.pause_loop();
            until 1 ~= good  or bytes_downloaded >= file_size or nsis.cancel(stateName) == 1
            fle:close()
        else
            good,rcode,rheaders= http.request{url=source_url,
            proxy=proxy_host,
            beforebody=function(code,headers)
                if(code  == 200) then
                    local len=tonumber(headers['content-length']);
                    if len == nil then return end
                    progress_table.length = len;
                end
            end,
            sink=sinkfor(filename,progress_table)};
            if rcode ~= 200 then
                good=0
            end
        end
    else 
        -- Bad Protocol
        return "unsupported";
    end
end)
notifyprogress(progress_table,true);
if not good == 1 then
    ErrorPrint(string.format("removing[%s] due to fail",filename));
    os.remove(filename)
end
if not e then 
    if type(msg) == "table" then 
        ErrorPrint(string.format("download_file[%s] -> %s",source_url,table.tostring(msg)))
        msg=msg.type -- Preserve the Type Information in this case too
    else
        ErrorPrint(string.format("download_file[%s] -> %s",source_url,msg))
    end
    return msg
end
if good == 1 then
    return "success"
elseif nsis.cancel(stateName) == 1 then
    return "cancel"
else
    return "fail"
end
end

local scrambleExe=nil


--  Unscramble src -> dest (in the context of rundir (optional))
local function unscramble_file(src,dest,rundir)
    local exe=scrambleExe
    if exe == nil then
        exe=string.format([[%s\un.package.exe]],_G.PLUGINSDIR);
    end
    local unscr_line=string.format([["%s" "%s" "%s" "B"]],exe,src,dest)
    DebugPrintF("Running(Unscramble) %s",unscr_line);
    local rc,result,ec =win32.RunProcess(unscr_line,rundir or _G.PLUGINSDIR)
end

local function set_pause_loop(x)
    DebugPrintF("PauseLoop  Updated! From -> %s", tostring(P.pause_loop));
    P.pause_loop = x;
    DebugPrintF("PauseLoop  Updated! -> %s", tostring(P.pause_loop));
end

local M= {
    ["proxyForUrl"]=proxy_for_url,
    ["downloadFile"]=download_file,
    ["unscrambleFile"]=unscramble_file,
    ["standardProgress"]=standardProgress,
    ["setPauseLoop"]=set_pause_loop,
    ["setScrambleExe"]=function(newexe)
        scrambleExe=newexe;
    end,
    ["useByteRange"]=function(x)
        if x ~= nil then 
            _G.USE_BYTE_RANGE=x;
            DebugPrintF("USE_BYTE_RANGE -> %s",tostring(x))
        else
            return _G.USE_BYTE_RANGE
        end
    end
}
DebugPrint("Downloads Loaded!!!");

return M
