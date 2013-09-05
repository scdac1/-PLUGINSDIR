--Single Offer Page install
--Lua Code.
--This Basically Sets up the Browser window.
--Browser window is tagged "Offer"
-- Table of windows handls that need invalidating in 
-- terms fo refresh.
local RefreshQueue=nil;
local SCREEN_OFFERS = 1
local SCREEN_INSTALL = 2
local SCREEN_COMPLETE = 3
local SCREEN_FINISH = 4
local SCREEN_CANCEL =5
local SCREEN_UNINSTALL=6
local CurrentScreen=SCREEN_OFFERS
local LastScreen=SCREEN_OFFERS
local CurrentBrowser="";
changeInstallStateCallback=nil
runAsyncInstallCallback=nil
PrimaryInstallAction=nil;
SIMPLE_CANCEL=false

function getOfferBrowserTag()
  return getCurrentBrowserTag("Offer")
end

function getCancelBrowserTag()
  return getCurrentBrowserTag("Cancel")
end

function getInstBrowserTag()
    return getCurrentBrowserTag("Inst")
end

function getCompleteBrowserTag()
    return getCurrentBrowserTag("Complete");
end

webcontrol_waiting_for_load=1;

function doLoadOffer1(browser)
    DebugPrint("Do Load offer1");
    -- THis is to make sure hitting return doesnt move to the 
    -- next phase
    win32.EnableWindow(HwndAccept,0);
    if webcontrol_waiting_for_load == 1 then
        DebugPrint("Adding Applications");
        addApplications(browser);
        DebugPrint("Added Applications");
        webcontrol_waiting_for_load=0
        
        DebugPrint("going to run");
        if offer_events['async']  then 
            local tgt = bundles[install_events.last_bundle]
            if tgt == nil 
                or not tgt.status.ready then
                DebugPrint("Not Loading ... Bundle is not ready");
                webcontrol_waiting_for_load=1
                return
                --Reset the loading flag.
            end
        end
        local bId=(install_events.last_bundle-1)
        DebugTrace("Bundle[%d] is offering:%s",bId,debug.traceback())
        local script=[[offerBundle(]] .. bId ..[[)]];
        script=wrappedScript(script);
        DebugPrint("Script:" .. script)
        local wnd=browser.document.parentWindow
        wnd:execScript(script,"javascript");
        DebugPrint("offerBundle Complete");
        wnd:execScript([[delayedRefresh()]],"javascript");
        offer_events['loaded']=true;
        DebugPrint("delayRefresh");
    end
end

--[[
-- Installation process
--]]
function doLoadInstall(browser)
  if webcontrol_waiting_for_load == 1 then 
    webcontrol_waiting_for_load=0
    addApplications(browser)
    local script= wrappedScript("beginInstall();","doLoadInstall");
    DebugPrint("Script:" .. script)
    local wnd=browser.document.parentWindow
    wnd:execScript(script,"javascript");
    wnd:execScript([[delayedRefresh()]],"javascript");
  end
end

function updatePauseState(newState,browser)
    ComGuard("updatePauseState",function()
        browser=browser or getBrowser(getInstBrowserTag())
        local script=string.format([[setPauseState(%d)]],newState);
        local wnd=browser.document.parentWindow
        wnd:execScript(script,"javascript");
    end)
end

function navDoAccept()
    win32.EnableWindow(HwndAccept,1);
    nsis.postMessage(HWNDPARENT,WM_COMMAND,IDOK,0);
end

function navDoClose()
    nsis.postMessage(HWNDPARENT,WM_CLOSE,0,0);
end

function InstallComplete()
    navDoAccept();
    --[[
    local browser=getBrowser(getInstBrowserTag())
    local script="in
    DebugPrint("Script:" .. script)
    browser.document.parentWindow:execScript(script,"javascript");
    --]]
end

function InstallProgress(idx,msg,min,max,instStep,canPause)
    local browser=getBrowser(getInstBrowserTag())
    local bundle=bundles[idx];
    local entity=installStepIndexMap[instStep];
    if entity then
        DebugPrintF("InstallStepIdx[%d] => Range(%d,%d)",instStep,min,max);
        entity.downloaded=min or 0
        entity.toDownload=max or 1;
    end
    if bundle ==nil or browser == nil then return  end
    -- If there is a progress Target redirect is progress update to it.
    if bundle.progressTargetIdx ~= nil then idx= bundle.progressTargetIdx end
    local script=string.format("updateInstallProgress(%d,%d,%d,%d,%d)", idx ,min , max ,instStep,canPause);
    DebugPrint("Script:" .. script)
    browser.document.parentWindow:execScript(script,"javascript");
end

function InstallStatus(idx,status)
    local browser=getBrowser(getInstBrowserTag())
    local originalIdx=idx;
    local bundle=bundles[idx];
    if bundles==nil or browser == nil then return  end
    -- If there is a progress Target redirect is progress update to it.
    if bundle.progressTargetIdx ~= nil then idx= bundle.progressTargetIdx end
    -- In the even there is a problem in running the script
    ComGuard("InstallStatus",function()
        local script="updateInstallLine(" .. idx .. [[,"]] .. status .. [[",]] ..  originalIdx .. [[)]];
        DebugPrint("Script:" .. script)
        browser.document.parentWindow:execScript(script,"javascript");
    end)
end




install_events={["last_bundle"]=1,['document_complete']=0}
function install_events:DocumentComplete()
    Guarded("install_events:DocumentComplete",function()
        DebugPrint("install_events:DocumentComplete()");
        local browser = getBrowser(getInstBrowserTag())
        doLoadInstall(browser)
        DebugPrint("Install Document Complete");
        install_events['document_complete']=1
    end)
end
offer_complete_callback=nil;
offer_complete_trigger_count=0;
offer_events={
    ['loaded']=false,
    ['pending']=nil,
    ['future_ready']=false,
    ['async']=false
}
function offer_events:DocumentComplete(obj,url)
    --  nsis.messageBox("Document Complete Called");
    DebugPrintF("Running offer_events:DocumentComplete:[url=%s]",tostring(url));  
    Guarded("offer_events:DocumentComplete",function()
        --[[DebugTrace("offer_events:DocumentComplete(%s,%s,%s)\n%s",tostring(obj),tostring(obj and obj.LocationUrl),
        tostring(url),debug.traceback());
        if (obj and obj.LocationUrl == nil) and url ~= true then

            return;
        end
        ]]--
        if url and (url=="about:blank" 
            or string.find(url,"http") == 1) then
            DebugPrint("offer_events:Irrellevant Page Loaded");
            return
        end

        if webcontrol_waiting_for_load == 0 then 
            DebugPrint("offer_events:DocumentComplete -- Skipped");
            return
        end
        offer_complete_trigger_count=offer_complete_trigger_count+1;
        local browser=getBrowser(getOfferBrowserTag())
        -- Async means we need to call docyment complete every time we load offers
        if offer_events.async then
            resetDialogState();
        end
        doLoadOffer1(browser);
        DebugPrint("OfferLoaded!");
        if(offer_events['async']) then
            maybeRunOfferCompleteCallback();
        end

    end)
end

-- Check tos ee whether we should show the installer.
function maybeRunOfferCompleteCallback()
    if CurrentScreen ~=  SCREEN_OFFERS then return end;
    DebugPrintF("Maybe Offer Complete(callback=%s/trigger=%d)",tostring(offer_complete_callback),
    offer_complete_trigger_count);
    if offer_complete_callback ~= nil and 
        offer_complete_trigger_count ==1  then 
        DebugPrint("Calling Offer Complete");
        local tocall=offer_complete_callback
        offer_complete_callback = nil;
        DebugPrintF("Offer Complete Callback = %s",tostring(offer_complete_callback));
        nsis.callback(tocall);
        -- Dont need the callback anymore
        --nsis.callback(SCREEN_READY_FUNC)
    end
end

--Move to the next pending bundle if necessary
--This code assumes  that products will become ready in sequence.
function nextPending()
    --If nothing is pending then return now.
    if offer_events.pending == nil then return end;
    offer_events.future_ready=false;
    for x=offer_events.pending,table.getn(bundles),1 do
        repeat
            local b=bundles[x];
            -- If the next product is a primary skip it
            if b.isPrimary then break end
            -- if the pending product is not failed then we dont move
            if b.status.failed then break; end
            -- if next product was to not be shown 
            if b.status._willDisplay_ == 0 then break  end

            if b.status.ready and  b._willDisplay_ then 
                offer_events.future_ready=true
                return
            end;
        until true
    end
    -- This means all the products have failed
    offer_events.future_ready= true
    DebugPrint("Nothing Else is Pending!");
end

function pendingReady()
    nextPending();
    if offer_events.future_ready then return true end;
    return false
end

cancel_events={}
function cancel_events:DocumentComplete()
    DebugPrint("cancel_events:DocumentComplete()");
    local browser=getBrowser(getCancelBrowserTag())
    if webcontrol_waiting_for_load == 0 then 
        DebugPrint("cancel_events:DocumentComplete -- Skipped");
        return
    end
    webcontrol_waiting_for_load=0;
    addApplications(browser)
    local script=[[beginCancel()]]
    script=wrappedScript(script,"cancel_events:DocumentComplete");
    DebugPrint("Script:" .. script);
    browser.document.parentWindow:execScript(script,"javascript");
    nsis.callback(SCREEN_READY_FUNC)
end

-- Some WIndow messages i will need
--
IDOK  = 1 
IDYES = 6
IDCANCEL = 2
IDABORT = 3
IDNO = 7
WM_COMMAND        = 0x0111
WM_CLOSE          = 0x0010
WM_QUIT           = 0x0012
WM_NCMOUSEMOVE    = 0x00A0
WM_KEYDOWN        = 0x0100
WM_KEYUP          = 0x0101
WM_NCLBUTTONDBLCLK = 0x00A3
WM_NCLBUTTONDOWN = 0x00A1
WM_LBUTTONDOWN    = 0x0201
WM_LBUTTONUP      = 0x0202
WM_MBUTTONDOWN    = 0x0207
WM_MBUTTONUP      = 0x0208
WM_RBUTTONDOWN    = 0x0204
WM_RBUTTONUP      = 0x0205
WM_USER           = 0x400
BM_CLICKED=0x00F5

HTCAPTION = 2


SW_HIDE             = 0
SW_SHOWNORMAL       = 1
SW_NORMAL           = 1
SW_SHOWMINIMIZED    = 2
SW_SHOWMAXIMIZED    = 3
SW_MAXIMIZE         = 3
SW_SHOWNOACTIVATE   = 4
SW_SHOW             = 5
SW_MINIMIZE         = 6
SW_SHOWMINNOACTIVE  = 7
SW_SHOWNA           = 8
SW_RESTORE          = 9
SW_SHOWDEFAULT      = 10
SW_FORCEMINIMIZE    = 11
SW_MAX              = 11


-- Nsis window messages
WM_NOTIFY_OUTER_NEXT = WM_USER+0x8
WM_NOTIFY_CUSTOM_READY = WM_USER+0xd

-- Message box Constants
MB_OK   =                    0x00000000
MB_OKCANCEL  =               0x00000001
MB_ABORTRETRYIGNORE =        0x00000002
MB_YESNOCANCEL       =       0x00000003
MB_YESNO             =       0x00000004
MB_RETRYCANCEL       =       0x00000005


MB_ICONWARNING = 0x00000030



complete_events={}
function complete_events:DocumentComplete()
    --  nsis.messageBox("Document Complete Called");
    DebugPrint("complete_events:DocumentComplete()");
    local browser=getBrowser(getCompleteBrowserTag())
    addApplications(browser);
    if dialog_state.inited == false then 
        local script=[[beginComplete()]]
        DebugPrint("Script:" .. script);
        browser.document.parentWindow:execScript(script,"javascript");
        dialog_state.inited=true;
    end

end

Integrated_PAGE_WIDTH=0;
Integrated_PAGE_HEIGHT=0;

function setupIntegratedSizing()
    local pl,pt,pr,pb=win32.GetClientRect(HWNDPARENT)
    -- Get the page width and height.
    Integrated_PAGE_WIDTH=pr-pl;
    Integrated_PAGE_HEIGHT=pb-pt;
end
function fullScreenWindow(hwnd)
    --Resize the Page area to that isize
    --nsis.messageBox("Size of " .. HWNDPAGE .. "," .. Integrated_PAGE_WIDTH .. "," .. Integrated_PAGE_HEIGHT)
    win32.MoveWindow(hwnd,0,0,Integrated_PAGE_WIDTH,Integrated_PAGE_HEIGHT,1)
end
function visuallyHideWindow(hwnd)

    win32.MoveWindow(hwnd,-1,-1,1,1,1)
end

function moveOffscreen(windows)
    for _,hwnd in ipairs(windows) do
        visuallyHideWindow(hwnd)
    end
end
--Resize the Page area to that isize
--nsis.messageBox("Size of " .. HWNDPAGE .. "," .. Integrated_PAGE_WIDTH .. "," .. Integrated_PAGE_HEIGHT)



function setupRefreshQueue(windows)
    RefreshQueue = windows;
end

function windowRefresh()
    do 
        return
    end
    -- Repaint the window.
    DebugPrint("Invalidating Rect " .. HWNDPARENT );
    --win32.InvalidateRect(HWNDPARENT);
    -- Go through the inwindow in the queue and systematicall invalidate them.
    if RefreshQueue then
        for _,v in ipairs(RefreshQueue) do 
            DebugPrint("Invalidate Rect " .. string.format("%-8d/%08x",v,v) ) 
            --        win32.InvalidateRect(v);
            win32.UpdateWindow(v);
        end
    end
end



function setIntegratedFirstBundle(idx)
    install_events['last_bundle']=idx;
end

--[[
-- Resume integrated offer from pending state
--]]
function resumeIntegratedOffer()
    if offer_events.pending == nil then
        DebugPrint("Nothign is pending!");
        return 
    end
    local browser=getBrowser(getOfferBrowserTag())
    local bId=offer_events.pending-1
    if offer_events.pending ~= nil then
        DebugPrint(string.format("Resuming Installation at Bundle %d",offer_events.pending))
    end
    -- Clear this before calling JS as that might be reentrant
    offer_events.pending=nil;
    addApplications(browser);
    local script=[[offerBundle(]] .. (bId) ..[[,1,true)]];
    script=wrappedScript(script);
    DebugPrint("Script:" .. script)
    local wnd=browser.document.parentWindow
    wnd:execScript(script,"javascript");

end
--[[
-- Running the final INstaller.
--
--]]
function runningFinalInstall()
    Guarded("runningFinalInstall",function()
        local browser=getBrowser(getCompleteBrowserTag())
        local script = [[window.model && window.model.disabledButtons(true)]]
        local wnd=browser.document.parentWindow;
        wnd:execScript(script,"javascript");
    end);
end

--Begin the Integrated Offer
function startIntegratedOffer(hwnd,completecallback,async)
    updateCurrentScreen(SCREEN_OFFERS,getOfferBrowserTag())

    offer_complete_trigger_count=0;
    offer_complete_callback=completecallback
    DebugPrintF("Offer Complete Callback = %d",offer_complete_callback);
    if async then offer_events.async=true; end
    resetDialogState();
    -- luacom.StartLog("C:/Lua.log");
    local browser=getBrowser(getOfferBrowserTag())
    if browser == nil then
        ErrorPrint("UNALBE TO LOAD BROWSER!!!");
    end
    webcontrol_waiting_for_load=1;
    --browser.document:write({"This is a test!","THIS IS ANOTHER LINE"});a
    notifyConnect(browser,offer_events);
    --notifyConnect(browser.document,install_doc_events);
    if browser.document.readyState == "complete" then
        offer_events:DocumentComplete(true);
    end
    browser=nil;  
end

function installDocumentComplete()
    install_events['complete_counter']=install_events['complete_counter']+1;
    if install_events['complete_counter'] > 5 then
        return 1
    end
    return install_events['document_complete']
end
-- Beging Integrated Install
function startIntegratedInstall(hwnd)
    updateCurrentScreen(SCREEN_INSTALL,getInstBrowserTag())
    resetDialogState()
    install_events['document_complete']=0;
    install_events['complete_counter']=0
    local browser=getBrowser(getInstBrowserTag())
    webcontrol_waiting_for_load=1;
    --browser.document:write({"This is a test!","THIS IS ANOTHER LINE"});a
    notifyConnect(browser,install_events,ONE_BROWSER);
    --notifyConnect(browser.document,install_doc_events);
    if browser.document.readyState == "complete" then
        install_events:DocumentComplete()
    end
    browser=nil;  
end

-- Begin INtegrated Cancel
function startIntegratedCancel(hwnd)
    updateCurrentScreen(SCREEN_CANCEL,getCancelBrowserTag());
    resetDialogState()
    local browser=getBrowser(getCancelBrowserTag())
    webcontrol_waiting_for_load=1
    notifyConnect(browser,cancel_events,ONE_BROWSER);
    if browser.document.readyState == "complete" then
        cancel_events:DocumentComplete()
    end
    browser=nil;
end


-- Begin INtegrated Cancel
function startIntegratedComplete(hwnd)
    updateCurrentScreen(SCREEN_COMPLETE,getCompleteBrowserTag())
    resetDialogState()
    local browser=getBrowser(getCompleteBrowserTag())
    webcontrol_waiting_for_load=1
    notifyConnect(browser,complete_events,ONE_BROWSER);
    if browser.document.readyState == "complete" then
        DebugPrint("Document is already Ready");
        complete_events:DocumentComplete()
    end
    browser=nil;
end

GETWINDOW_FUNC = nil;
OPEN_URL_FUNC = nil;
SCREEN_READY_FUNC = nil;
BROWSE_FOLDER_FUNC=nil;

function addBrowserToRefresh(hwnd)
    callstack_push(hwnd)
    nsis.callback(GETWINDOW_FUNC);
    local ret=callstack_pop()
    DebugPrint("[addBrowserToRefresh] Browser Window HWND -> " .. hwnd .. " -> " .. tostring(ret))
    if(RefreshQueue ==  nil) then
        RefreshQueue={ret}
    else
        table.insert(RefreshQueue,ret)
    end

end

-- Code is not in USes  below this line
-- The Extension Class  used by IE
External = {}
-- Lookup Data of a specific type
function External:getObjectData(objtype,subid)
    -- nsis.messageBox("Get Object Data Called");
end

HIDE_FEATURES=0;
JS_CURRENT_BUNDLE=0;
--Issue a command from Javascript to Lua
function External:issueCommand(name,data)
    DebugPrint("External:issueCommand(" .. name .. ")");--," .. data .. ")")
    local e,ret=pcall(function()
        if(data) then DebugPrint("Command Data :=>" .. data) end
        if name == "window/close" then
            if isUninstaller() then
                return navDoUninstallClose();
            end
            navDoClose()
        elseif name == "window/minimize" then 
            win32.ShowWindow(HWNDPARENT,SW_MINIMIZE);
        elseif name == "window/begindrag" then 
            -- begin window drag
            win32.ReleaseCapture()
            nsis.postMessage(HWNDPARENT,WM_NCLBUTTONDOWN,HTCAPTION,0)
        elseif name == "window/innerloaded" then 
            --The inner page has loaded.
            maybeRunOfferCompleteCallback();
        elseif name == "window/refresh"  then
            windowRefresh();
            --[[ This was implemented in the standard place
            --elseif name == "nav/cancel-popup" then
            local cancelret=nsis.messageBox("Are you sure you want to exit the Installer?","Warning",MB_YESNOCANCEL+MB_ICONWARNING);
            DebugPrint("Cancel Popup Selection:" .. tostring(cancelret))
            if cancelret == IDYES then 
            --Process the cancel.
            nsis.sendMessage(HWNDPARENT,WM_COMMAND,IDCANCEL,0);
            end
            ]]--
        elseif name == "nav/cancel" then
            --[[]]
            --nsis.sendMessage(HwndCancel,BM_CLICKED,0,0);
            if SIMPLE_CANCEL == true then
                DebugPrint("Invoking Query Cancel Callback");
                nsis.callback(queryCancelCallback);  
            else 
                DebugPrint("Standard Cancel");
                win32.EnableWindow(HwndCancel,1);
                nsis.postMessage(HWNDPARENT,WM_COMMAND,IDCANCEL,0);
            end
        elseif name == "nav/install" then
            --nsis.sendMessage(HwndAccept,BM_CLICKED,0,0)
            navDoAccept();
        elseif name == "nav/uninstall" then 
            navDoUninstall(data);
        elseif name == "nav/uninstall-close" then 
            navDoUninstallClose();
        elseif name == "nav/skipall" then 
            processSkipAll(JS_CURRENT_BUNDLE)
            navDoAccept()
        elseif name == "nav/install-now" then
            -- used with the 
            PrimaryInstallAction="now"
            if INSTALLS_AT_END then
                nsis.callback(runAsyncInstallCallback);
            else
                navDoAccept();
            end
        elseif name == "nav/install-open" then
            -- used with the 
            PrimaryInstallAction="open"
            navDoAccept();
        elseif name == "nav/install-show" then
            -- used with the 
            PrimaryInstallAction="show"
            navDoAccept();
        elseif name == "nav/install-close" then
            -- used with the 
            PrimaryInstallAction="close"
            navDoAccept();
        elseif name == "nav/install-saveas" then
            PrimaryInstallAction="saveas"
            navDoAccept();

        elseif name == "nav/install-later" then
            --nsis.sendMessage(HwndAccept,BM_CLICKED,0,0)
            PrimaryInstallAction="later"
            navDoAccept();
        elseif name == "install/pause" then
            callstack_push("pause")
            nsis.callback(changeInstallStateCallback);
            updatePauseState(1);
        elseif name == "install/resume" then
            callstack_push("resume")
            nsis.callback(changeInstallStateCallback);
            updatePauseState(0);
        elseif name == "install/metrics" then
            return json.encode({
                ["git_version"] = GIT_VERSION,
                ["initial"] = INIT_START,
                ["entries"] = LoadingMetrics
            });


        elseif name=="bundle/preOffer" then 
            -- TODO/DONE: Implement Process Free File Call.
            local bundle=bundles[data+0]
            -- Make sure to remember where they are. D
            DebugPrint("Last Bundle:" .. data)
            install_events['last_bundle']=data;
            if not offer_events['async'] or  bundle.status.ready == true then
                --Special case to allow  
                if hasOfferActions(bundle) then
                    callstack_push("offer");
                    callstack_push(data)
                    nsis.callback(processFreeFilesCallback)
                end
                return 1
            else
                if bundle.status.failed  then
                DebugPrint(string.format("Bundle[%d] Failed Will Continue",data+0));
                    return 1
                end
                DebugPrint(string.format("Bundle[%d] isnt ready. Resume Scheduled",data+0));
                offer_events['pending'] = data+0
                return 0
            end
        elseif name == "bundle/getProdState" then
            local prodId=data +1;
            local prod=bundles[prodId]
            local data=json.encode({
                _willInstall_ = prod._willInstall_,
                _willDisplay_ = prod._willDisplay_,
                advertiserIndex =  prod.advertiserIndex or -1,
                consolidated = prod.consolidated,
                isConsolidated =  prod.isConsolidated
            })
            DebugPrintF("ProductState:%d -> %s",prodId,data);
            return data;
        elseif name == "bundle/hasWouldInstall?" then 
            -- Check if the has wouldInstall Flag has been set.
            DebugPrint("hasWouldInstall("..data..")");
            local args=split(data,"|")
            local prodId=args[1]+1;
            local prod=bundles[prodId]
            DebugPrint("Would Install is " .. tostring(prod._wouldInstall_));
            if prod._wouldInstall_ ~= -1 then return 1 else return 0 end

        elseif name == "bundle/wouldInstall?" then 
            local args=split(data,"|")
            local prodId=args[1]+1;
            local prod=bundles[prodId]

            DebugPrint(string.format("Would Install => %s",data))
            if table.getn(args) ==2 then
                prod._wouldInstall_ =args[2]+0;
                --DebugPrint(string.format(">bundles[%s]._wouldInstall_ = %s",prodId,args[2]+0))
                local e,msg= pcall(function()
                    local browser=getBrowser(CurrentBrowser);      
                    local wnd=browser.document.parentWindow;
                    local val="yes";
                    if prod._wouldInstall_ == 1 then
                        val="yes";
                    else
                        val ="no";
                    end
                    DebugPrint("Setting installThisOne");
                    local script="window.model && window.model.installThisOne('" .. val .. "')"; 
                    wnd:execScript(script,"javascript");
                    -- Also Set the wouldInstall Flag for the current Bundle.
                    local jsIdx=(prodId-1);
                    script = "BundleData[" .. jsIdx .. "]._wouldInstall_ = " .. prod._wouldInstall_; 
                    -- DebugPrint("Setting Would Install" .. script);
                    wnd:execScript(script,"javascript");
                end);
                if not e then
                    DebugPrint("Error: There was an error!:" .. msg );
                end

            else
                -- DebugPrint(string.format("wouldInstall(%s) => %s",data,
                --tostring(prod._wouldInstall_)));
                if prod._wouldInstall_ ~= nil then
                    return prod._wouldInstall_;
                else 
                    if  prod._willInstall_ ==1 then 
                        return 1
                    else 
                        return 0
                    end
                end
            end
        elseif name == "bundle/setProdState" then 
            local args=split(data,"|");
            DebugPrint("setProdState("..data..")");
            -- Arrays are base 1 in lua and base zero in JS
            setProdState(args[1]+1,args[2],args[3],true,args[4] or false)
            -- We will return to the caller an array of 
            -- objects containing the display and install states
            local summary={};
            for _,v in ipairs(bundles) do
                -- Whenever we update a prod state e will transfer back the 
                -- _willInstall_ and _willDisplay_
                table.insert(summary,{
                    _willInstall_ = v._willInstall_,
                    _willDisplay_ = v._willDisplay_
                });

            end
            return json.encode(summary)
        elseif name == "bundle/featureState" then 
            --Get or set feature state.
            local args=split(data,"|");
            -- Arguments are [Bundle,Feature,newState]
            if #args  == 3 then
                bundles[args[1]+1].Feature[args[2]+1]._a_.InitialState=args[3] 
            end
            return bundles[args[1]+1].Feature[args[2]+1]._a_.InitialState 

        elseif name == "bundle/Current" then 
            if data ~= "" then 
                -- this is zero based.
                JS_CURRENT_BUNDLE=data+0;
            end
            return JS_CURRENT_BUNDLE;
        elseif name == "bundle/CurrentNested" then 
            -- Get the Current Nested Bundle.
            -- This is used for nested Combos products with the primary.
            local good,nested=pcall(function()
                local current=bundles[JS_CURRENT_BUNDLE+1]
                return bundles[current.consolidated[1].idx]
            end);
            if not good or nested ==nil  then
                ErrorPrint("Failed to get CurrentNested Bundle:%s",tostring(nested));
                return tostring(0) 
            end
            DebugPrintF("Current Nested bundle is %d",nested.bundleIndex);
            return nested.bundleIndex-1;
 
        elseif name == "bundle/features" then
            -- Get the Feature information.
            local tbl=table.copy(bundles[data+1].Feature);
            return json.encode(tbl)
        elseif name == "bundle/wasSuppressed?" then 
            --Determine if a bundle was suppressed
            -- Arguments are [BundleId,Index] 
            -- Index => 0 the current bundle 
            -- 1 =>First consolidated bundle
            -- N => Nth consolidated bundle.
            local args=split(data,"\01");
            local tgt=bundles[args[1]+1];
            local cIdx=args[2]+0;
            if cIdx == 0 then
                -- Index 0 maps to the lead bundle 
                return "" .. tgt._wasSuppressed_
            else
                -- Error handler 
                local e,ret=pcall(function()
                    local otherb= bundles[tgt.consolidated[cIdx].idx]
                    return "" .. otherb._wasSuppressed_
                end);
                if e then 
                    return ret 
                else

                end
                return "0";
            end
        elseif name == "bundle/featureOptions" then 
            local args=split(data,"\01");

            bundles[args[1]+1]._featureOptions_=args[2]
        elseif name == "bundle/featureById" then
            -- Set a  features state by Id/Name
            local args=split(data,"\01");
            local bId,ident=args[1]+1,args[2];
            local checked=nil;
            if #args ==3 then checked=args[3] end
            local b=bundles[bId];
            -- Iterateo over the features.
            for k,v in ipairs(b.Feature) do 
                -- Identifier.
                if v._a_.id ~= nil then
                    if v._a_.id == ident then
                        if checked ~= nil then 
                            v._a_.InitialState=checked
                        end
                        return v._a_.InitialState
                    elseif v.consolidateRelIdx ~= nil then 
                        -- To handle multiple products having the same 
                        -- attributes we will create a second variate of any id 
                        -- ending with __ <psoition index>
                        local altId=v._a_.id .. "__" .. tostring(v.consolidateRelIdx)
                        if altId == ident then
                            if checked ~= nil then 
                                v._a_.InitialState=checked
                            end
                            return v._a_.InitialState
                        end
                    end
                end
            end
            return "unchecked";
        elseif name == "bundle/customFeatures" then
            HIDE_FEATURES=1;
            DebugPrintF("Custom Features => ON");
            local e,msg= pcall(function()
                local browser=getBrowser(CurrentBrowser);      
                local wnd=browser.document.parentWindow;
                 DebugPrint("Setting hasCustomFeatures");
                local script=wrappedScript("window.model && window.model.hasCustomFeatures(true)");
                wnd:execScript(script,"javascript");
            end);

        elseif name == "bundle/customFeatures?" then 
            return "" .. HIDE_FEATURES;   
        elseif name == "bundle/customParameters" then
            -- Get the Custom parameter blob for the view.      
            local b=bundles[data+1]
            if b.CustomParameter == nil then return json.encode({}) end
            local tbl=table.copy(b.CustomParameter);
            return json.encode(tbl)
        elseif name == "app/data" then 
            local browser=getBrowser(CurrentBrowser);      
            addApplications(browser);
        elseif name == "app/environment" then
            return json.encode(environment_options)
        elseif name == "bundle/resetCustomFeatures" then
            HIDE_FEATURES=0;
            DebugPrintF("Custom Features => OFF");
        elseif name == "app/InstallInOrder?" then
            return tostring(getInstallInOrder())
        elseif name == "app/SingleProgressBar?" then
            return tostring(getSingleProgressBar())
        elseif name == "app/hasVariation?" then
            return tostring(hasVariation(data))
        elseif name == "app/isUninstaller?" then
            return tostring(isUninstaller())
        elseif name == "app/frameEval" then
            local args=split(data,"\01")
            local  frameId=args[1];
            local src = args[2]
            local code=args[3]
            DebugPrint(string.format("Getting Browser:%s",CurrentBrowser));
            local browser=getBrowser(CurrentBrowser);
            DebugPrint(string.format("Getting Iframe %s",frameId));
            local iframe=browser.document:getElementById(frameId)
            if iframe ~= nil then
                DebugPrint("Got Iframe");
                local  wnd=iframe.contentWindow;
                DebugPrint(string.format("Got Window:%s",tostring(wnd)))
                DebugPrint(string.format("Running Code:- %s" ,code));
                wnd:execScript(code);
            end
        elseif name == "app/writeRegistryBlock" then 
            local good=false;
            local e ,msg = pcall(function()
                local params=json.decode(data);
                writeRegistryBlock(params[1],params[2],params[3],params[4]);
                good=true;
            end);
            if not e then
                ErrorPrint(string.format("Failed to write registry:%s",msg));
            end
            return tostring(good);
        elseif name  == "app/pickfolder" then 
            ---Pick the installation target folder
            local args=split(data,"\01")
            local title,installAction=args[1],args[2]
            DebugPrintF("Install  Action -> %s",tostring(installAction));
            callstack_push(getInstallTargetDir())
            callstack_push(title);
            nsis.callback(BROWSE_FOLDER_FUNC);
            local ret=callstack_pop();
            if ret =="error" then return "0" end
            setInstallTargetDir(ret);
            if installAction ~= nil and action ~="" then
                PrimaryInstallAction=installAction
                navDoAccept();
            end
            return ret;
        elseif name == "app/thanks" then 
            doThanks(); -- Trigger the thanks logic.
        elseif name == "app/track" then
            doTrackingHit(false);
        elseif name == "lookup/message" then 
            local args=split(data,"\01")
            CurrentBundle = bundles[args[1]+1]
            local e,msg=pcall(function()
                return lookupUIMessage(args[2])
            end)
            if e then 
                return msg
            else
                DebugPrint("<Got " .. tostring(e) .. "|" .. tostring(msg))
                return "";
            end

            --[[local msg=lookupUIMessage(args[2]);
            DebugPrint("Got Response");
            DebugPrint("I Am Returning: " .. msg)
            return msg]]
        elseif name == "open/url" then
            callstack_push(data);
            nsis.callback(OPEN_URL_FUNC);
        elseif name == "parent/execute"  then
            DebugPrint(string.format("Gonna Execute: %s",data));
            local script=string.format([[new Function("%s").call(window)]],data);
                local e,msg= pcall(function()
                    local browser=getBrowser(CurrentBrowser);      
                    local wnd=browser.document.parentWindow;

                    wnd:execScript(script,"javascript");
                end)
                if not e then
                    DebugPrint(string.format("Failed Running Script!:%s",msg));
                else
                    return msg;
                end
        elseif name == "cancel/message" then 
            CANCEL_QUERY_TEXT = tostring(data);
            CANCEL_BUTTON_FLAGS = MB_YESNO +  MB_ICONWARNING
        elseif name == "debug/log" then
            DebugPrint(string.format("Log|%s",tostring(data)))
        elseif name == "debug/trace" then
            DebugTrace("JSTrace|%s",tostring(data))
        else
            DebugPrint("Unhandled Command!!!!");
        end
    end)
    if not e then
        DebugPrint("IssueCommand:Error" .. ret )
        return ""
    elseif ret == nil then 
        return ""
    else
        return ret;
    end
end

function updateCurrentScreen(newScr,browserTag)
    LastScreen=CurrentScreen;
    CurrentScreen=newScr;
    CurrentBrowser = browserTag;
    if newScr ~= SCREEN_CANCEL then
        DebugPrint("Reseting Abort Flag")
        nsis.setAbort(0);--Reset the abort flag
    end
end

function writeRegistryBlock(root,path,data,delete)

    for k,v  in pairs(data) do
        if delete then
            --DebugPrint(string.format([[Deleting %s\%s\%s]],root,path,k));
            registry.WriteRegValue(root,path,k,nil);
        else
            --DebugPrint(string.format([[Writing %s\%s\%s -> %s]],root,path,k,v));
            registry.WriteRegValue(root,path,k,v);
        end
    end


end

-- Setup a Com Object that the Browser can callback into.
_tlbdir=expandNsisVars("$PLUGINSDIR/extension.tlb");
DebugPrint("External Tlb is in " .. _tlbdir)
ExternalObj=luacom.ImplInterfaceFromTypelib(External, _tlbdir, "IExternal")
ExternalUnk=luacom.GetIUnknown(ExternalObj)
ExternalPtr=nsis.userdataPtr(ExternalUnk)
DebugPrint("External Object is "..  table.tostring(ExternalObj) .. " -> "..  ExternalPtr );


