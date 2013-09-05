require("luacom")

ONE_BROWSER=false;
ONE_TAG = "single_browser"
--
--This functions provides access to the Ib Browser control
--by reading a moniker for the specific suffix.
--The moniker is the only way to not direcrtly have the WebControl Code
--talk to the Lua code wich would require an NSIS cotnrol
function getBrowser(suffix)
   -- Browser is registerd as  A file Moniker.
    local sfx=suffix;
    if sfx == nil then
      sfx=""
    else
      sfx="-"..sfx
    end
    DebugPrint("getBrowser[" .. suffix .. "]");
    return luacom.GetObject("C:\\Nsis\\Browser"..sfx)

end



-- Browser Tag Names.
-- This is to handle collision of the monikers that are not being cleaned up so to speak.

BrowserTagIndices = {}
math.randomseed(CURRENT_PROCESS_ID)
BROWSER_RAND=math.random(10000);

function getNextBrowserTag(clazz)
  local idx=BrowserTagIndices[clazz] or 0
  idx=idx+1;
  BrowserTagIndices[clazz]=idx;
  local rettag=clazz .. BROWSER_RAND .. idx
   --nsis.messageBox("Tab Browser  @ " .. rettag)
  return rettag
end

function getCurrentBrowserTag(clazz)
    if ONE_BROWSER then
        clazz=ONE_TAG
    end
  local idx = BrowserTagIndices[clazz] or 0
  return clazz .. BROWSER_RAND .. idx
end





-- State variables
-- State variables 
dialog_state={
  loaded=false
}

 
dialog_state={
  loaded=false,
  inited=false
}

-- Reset the dialog state.
-- Should be called before we setup a new IE window for Script usage.
--
function resetDialogState()
  dialog_state.loaded=false;
  dialog_state.inited=false;
end

function wrappedScript(code,tag)
    if not isDebug() then return code end
    return string.format([[try{
        %s
    }catch(e){
        issueCommand("debug/log","JS-ERROR|(%s)" + e + "|" + e.lineNumber + "|" + e.message)
    }]],code,tag or "-")
end

-- Application State Matrix 

--[[
--Encode the minimal portion of APPN for the User Interface
--this skips over the Large and possible unwield <Bundle/> nodes
--]]
function appNForUi()
    local _appN={};
    for k,v in pairs(appN) do
        if k ~= "Bundle" then
            _appN[k]=v;
        end
    end
    return _appN;
end

--[[
-- Encode the bundles for the UI replacing 
-- empty/unused bundles with  <null>
-- this is done to reduce the amount of json parsing and data that hits the ui side of things.
--]]
function bundlesForUi()
    local _bundles={};
    local _last=nil;
    for k,v in ipairs(bundles) do
      if v._wasSuppressed_ ~= 1 then
          if _last ~= nil and 
              v.isContinuation == true  
              and _last._wasSuppressed_ == 1 then
              table.insert(_bundles,json.null);
          else
              table.insert(_bundles,v);
          end
       else
               table.insert(_bundles,json.null);
       end
       _last=v;
    end
    DebugPrint(string.format("Initial %d bundles (rendering %d)",#bundles,#_bundles));
    return _bundles
end

--Add a Bunch of controls toa  browser windows
function addApplications(browser,fire_complete)
    if(dialog_state.loaded ==true) then
        DebugPrint("App Applications Skip!");
        return;
    end
  -- Get the parent window.
  local wnd=browser.document.parentWindow;
  local arg="";
  if FIRST_BUNDLE ~= nil then
    arg=(FIRST_BUNDLE-1)
  end
   local script=[[setFirstBundle(]] .. arg .. [[);setBundleData(]]..json.encode(bundlesForUi()) ..  [[);
   setAppData(]]..json.encode(appNForUi()) ..  [[);
   setEnvData(]]..json.encode(environment_options) .. [[);
   setSkinData(]].. json.encode(skinOptions()) .. [[); ]];
    script=wrappedScript(script); 
    DebugPrint("Script:".. script);
   wnd:execScript(script,"javascript")
   DebugPrint("Exec Complete");
   if fire_complete == true then
    DebugPrint("Script: updateAppsComplete");
    wnd:execScript("updateAppsComplete()","javascript");
  end
  if isDebug() or JSDEBUG then
      DebugPrint("Enabling Debug!");
    wnd:execScript("enableDebug()","javascript");
  end
  DebugPrint("Reseting Dialog State");
  dialog_state.loaded=true
  DebugTrace("Added Applications:%s",debug.traceback());
end


--Update an applicatino row on the JS side
function updateApplication(browser,bundle,status)
  -- Get the parent window.
  local wnd=browser.document.parentWindow;
  local id =bundle._shortCode_
  -- to ensure continuity we will store the application states in the bundle object.
  bundle._LastApplicationState_=status
  local script=[[updateApplication("]] .. id .. [[","]].. status .. [[","")]]
   DebugPrint("Script:" .. script)
  wnd:execScript(script,"javascript");
  wnd=nil;
  browser=nil;

end

--[[
-
luacom.ImplInterface(calendar_events,
  "MSCAL.Calendar",
   "DCalendarEvents")
--
--]]
-- Bind a DispEvents interface 
-- Events that are transmitted via Idispatch not iUnknown so there is no 
-- strict vtable
function notifyConnect(ctrl,iface,skipOnOneBrowser)
    if skipOnOneBrowser == true then
        return;
    end
    local impl=luacom.ImplInterface(iface,"InternetExplorer.Application","DWebBrowserEvents2");
    --DebugPrint("Implemented " .. impl)
    local cookie=luacom.addConnection(ctrl,impl);
    if cookie == nil then 
        ErrorPrint(string.format("Lua Com returned bad Cookie!(%s <-> %s)",tostring(ctrl),tostring(iface)))
    else
        DebugPrint("Connection Cookie " .. tostring(cookie))
    end
    --local res,cookie=luacom.Connect(ctrl,iface);
    -- Register some stuff.
    --nsis.messageBox("Registered " .. tostring(res) .. "/" .. tostring(cookie))

end

