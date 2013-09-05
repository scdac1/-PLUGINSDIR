

-- Json and Mime are intentionally global;
json=require("json");
mime=require("mime");
local http,ftp,url =require("socket.http"),require("socket.ftp"),require("socket.url");
local _Downloads=require("Downloads");
-- List of resource we need to download to start
-- Contains a list of pairs { <downloadpath>, <localstorage>}
init_downloads={ }
-- List of resource to download for installation
--
inst_downloads={ }


-- List of resources we need to extrac
init_extract = { }

-- CACHE 
-- List of cached files.
DOWNLOAD_CACHE = {

}

function get_cached(x)
    if DOWNLOAD_CACHE[x] then
        return true,DOWNLOAD_CACHE[x]
    end
    return false,nil
end

function add_to_cache(url,headers,path)
    DOWNLOAD_CACHE[url]={
        ['headers']=headers,
        ['path']= nil -- For now we shall  not cache files
    }
end

--Single step ofa  download list.
function downloadListStep(lst,idx,withProgress)
    local v=lst[idx]
    local src=v[1];
    local dest=v[2];
    local owner=nil;
    local _good=nil;
    local _failureReason=nil;
    local cached_path=""
    local cache_expr
    local activity="Downloading ... ";
    if table.getn(v)  > 2 then
        owner=v[3]
    end
    if table.getn(v) > 3 then
        cache_expr=v[4]
    end
    if type(src) == 'table' then 
        sources=src
    else
        sources={src}
    end
    local _downloadStepStart=abstime();
    local final_src="-"
    for _,src in ipairs(sources) do
        final_src=src
        activity=string.format("Downloading:%s",src)
        repeat
            if owner~=nil then
                activity=string.format("Size Check:%s",tostring(src))
            end
            if dest == nil then
                _failureReason="Skipped";
                _good=1;
                break;
            end
            Guarded("downloadListStep",function()
                local fileSizeCallback=function(sz,ranges)
                    if owner == nil then return end;
                    if type(owner) == "table" then
                        owner.FileSize=sz
                        owner.allowByteRange = ranges
                        DebugPrint("FileSize -> " .. tostring(owner.FileSize))
                        DebugPrint("Allow ByteRange -> " .. tostring(ranges))
                    elseif type(owner) == "string" then
                        local torun=string.format(owner,sz,ranges);
                        DebugPrint("RUnning-> " .. tostring(torun))
                        nsis.evalLater(0,torun)
                    end
                    _failureReason=nil
                    _good=1
                end
                local cached,cdata=get_cached(src)
                --We only want to get the file size
                local parsed=url.parse(src);
                if owner ~= nil then
                    DebugPrint("Requesting Info on  .. " .. src )
                    repeat
                        if cached and cdata ~= nil and 
                            cdata.headers and cdata.headers['content-length'] then
                            DebugPrint("File Size Served From Cache!");
                            fileSizeCallback(cdata.headers['content-length']+0,(function()
                                if cdata.headers['accept-ranges'] == "bytes" then return 1 end
                                return 0
                            end)());
                            break;
                        end
                        local e ,msg =pcall(function()
                            if parsed.scheme == "http" then
                                local r,c,h = http.request {url=src,
                                proxy=_Downloads.proxyForUrl(src),
                                method="HEAD" }
                                if r==1 and c == 200  then
                                    fileSizeCallback(h['content-length'] +0,0)
                                    -- Cache the resposne
                                    add_to_cache(src,h,(function()
                                        if cdata  and cdata.path then
                                            return cdata.path
                                        end
                                        return nil
                                    end)());
                                    _good=1
                                else
                                    _good=nil
                                    if r ==1 then 
                                        _failureReason =string.format("bad-http-code=%s",tostring(c))
                                    else
                                        _failureReason = string.format("request-fail=%s",tostring(c));
                                    end
                                end
                            elseif parsed.scheme == "ftp" then
                                local havesize,e=ftp.get{url=src,command="size",
                                continue_handler=function(code,reply)
                                    if code==213  then
                                        local file_len=tonumber(reply:sub(5)) or 0
                                        fileSizeCallback(file_len,0)
                                        add_to_cache(src,{['content-length']=file_len},nil)
                                    end
                                    return 0;
                                end }
                                if havesize ~= 1 then
                                    _failureReason=string.format("ftp-error=%s",tostring(e))
                                    _good=nil;
                                else
                                    _good=1;
                                end
                            end
                        end);
                        if not e then
                            ErrorPrint("Failed Getting Details ... " .. tostring( msg));
                        end
                    until true
                    if lst == inst_downloads then 
                        idx=table.getn(init_downloads) + idx;
                    end
                    if withProgress then
                        nsis.setPos(HWND_PROGRESS,idx)
                    end    
                    return
                end

                local destFile=io.open(dest,"wb");
                --Now Support HTTP and FTP
                repeat 
                    if cdata and cdata.path then
                        cached_path=cdata.path
                        _good=1
                        DebugPrint("Using cache " .. src )
                        break;
                    end
                    DebugPrint("Downloading .. " .. src .. " => " .. dest )
                    if parsed.scheme == "http" then
                        local good,code,headers=http.request{url=src,
                        proxy=_Downloads.proxyForUrl(src),
                        sink=ltn12.sink.file(destFile)}
                        if good == nil then 
                            ErrorPrint(string.format("Download Failed:code=%s,headers=%s",code,table.tostring(headers)))
                        end
                        if good == 1 and code == 200 then
                            -- update the cache
                            add_to_cache(src,headers,dest)
                        else
                            if good ==1 then 
                                _failureReason =string.format("bad-http-code=%s",tostring(code))
                            else
                                _failureReason = string.format("request-fail=%s",tostring(code));
                            end
                            good=nil
                        end
                        _good=good
                    elseif parsed.scheme == "ftp" then
                        local good,err=ftp.get{url=src,
                        sink=ltn12.sink.file(destFile)}
                        if good == 1 then
                            add_to_cache(src,{},dest)
                        end
                        _good=good
                    end
                until true
                DebugPrint(string.format("Download returned %s",_good or "nil"))
                --destFile:close() -- close destination file
                if withProgress then
                    nsis.setPos(HWND_PROGRESS,idx)
                end    
            end)
            _good=_good or false
            if cached_path and cached_path~="" and cache_expr then
                local torun=string.format(cache_expr,cached_path);
                DebugPrint("Using Cache -> " .. tostring(torun))
                nsis.evalLater(0,torun)
            end
        until true
        if _good  then  -- on success stop
            break;
        end
    end
    nsis.evalLater(0,string.format("downloadListAsyncDone(%d,[[%s]],%s,[[%s]],[[%s]])",idx,final_src,tostring(_good),cached_path,tostring(_failureReason)));
    notifyMetricComplete(activity,_downloadStepStart,abstime(),_failureReason or "OK")
end

function xmlListLoadingInit()
    nsis.setText(HWND_PROGRESS_DIALOG,PROGRESS_PRELOAD_TITLE);
    nsis.setText(HWND_STATIC_TEXT,PROGRESS_PRELOAD_TEXT)
end
--[[
-- DownloadListBoot :- Boot the Downlaod Thread
--]]
function downloadListBoot(hwndText,hwndProgress,hwndDialog)
    HWND_STATIC_TEXT=hwndText;
    HWND_PROGRESS=hwndProgress;
    HWND_PROGRESS_DIALOG=hwndDialog;
    xmlListLoadingInit();
end

-- Init progress bar for a download list
function downloadListProgressInit(productName,lst1,lst2)
    nsis.setText(HWND_PROGRESS_DIALOG,productName);
    -- one extra spot to allow for the actual initialization and extraction of files
    nsis.setRange(HWND_PROGRESS,table.getn(lst1) + table.getn(lst2)+1)
    nsis.setText(HWND_STATIC_TEXT,"Preparing your installation, please wait ... ")
end


function processDownloadList(productName)
    DebugPrint("Processing Download List");
    nsis.evalLater(0,"DebugPrint([[Process Download List Starting]])")
    local _downloadListStart=abstime()
    local e ,msg =pcall(function()
        downloadListProgressInit(productName,init_downloads,inst_downloads); 
        local total= table.getn(init_downloads) + table.getn(inst_downloads);
        local dlcount = table.getn(init_downloads)
        -- Download stuff and pay attention for the cancel.
        DebugPrint(string.format("Downloading %d items",total))
        for x = 1,total,1 do 
            if  nsis.cancel() == 1 then
                DebugPrint("Thread is cancelled!");
                return
            end
            if x > dlcount  then
                downloadListStep(inst_downloads,x-dlcount,true);
            else
                downloadListStep(init_downloads,x,true)
            end
        end
    end)
    notifyMetricComplete("Downloading Resources",_downloadListStart,abstime(),"OK")
    if not e then
        DebugPrint("Error Downloading " .. tostring(msg))
    end
end


function notifyMetricComplete(activity,startt,endt,status,intern)
    local runn=string.format("loadingMetricAdd([[%s]],%d,%d,[[%s]],%s)",activity,startt,endt,status,tostring(intern or false))
    DebugPrint(runn)
    nsis.evalLater(0,runn)
end

--[[
-- Run an executable and call a callback when its done.
--]]
function asyncRunInstaller(exeline,execDir,callback)    
    Guarded("asyncRunInstaller",function()
        local rc,result,ec=win32.RunProcess(exeline,execDir);
        nsis.evalLater(0,callback);
        local trace=string.format("AsyncRunInstaller-> %d , %s,%d",rc, tostring(result),ec)
        DebugPrint(trace)
    end    )
end
