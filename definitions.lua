


--CUSTOMDATADIR="[% CustomDataDir%]"

IDD_DECLINE_BUTTON=4
IDD_CANCEL_BUTTON=2 
IDD_BACK_BUTTON=3
IDD_ACCEPT_BUTTON=1
IDD_INSTALL_PROGRESS=1004
IDD_DOWNLOAD_PROGRESS=1034
IDD_DOWNLOAD_TEXT=1033
IDD_DOWNLOAD_BUTTON=1027
IDD_INSTFILES_FRAME=1032
IDD_INST_LABEL1=1006
IDD_INST_LABEL2=1033
IDD_INST_LIST=1016
PROGRESS_X="3u"
PROGRESS_WIDTH="164u"
PROGRESS_HEIGHT="11u"

--[[
LOGO_X=[%LogoX%]
LOGO_Y=[%LogoY%]
LOGO_WIDTH=[%LogoWidth%]
LOGO_HEIGHT=[%LogoHeight%]
BANNER_HEIGHT= 60
BANNER_X =LOGO_X + LOGO_WIDTH + LogoMarginRight 
BANNER_Y =${LOGO_Y}
CONTENT_X = ${BANNER_X}
CONTENT_Y= LogoY + LogoHeight + BannerMarginBottom
--]]
INIT_EULA_HEIGHT=157
INIT_EULA_WIDTH=273

PLUGINSDIR=nil;
LUA_PATH=nil;
--Setup directories
function setupDirs(pdir) 
  PLUGINSDIR=pdir;
  LUA_PATH=pdir .. "\\?";
end

-- Various Sizing Definitions
InitialWidth = 552
InitialHeight = 404
LogoWidth  = 60
LogoHeight = 60
LogoX      = 10
LogoY      = 10
LogoMarginRight=20
BannerMarginBottom=10
InitBannerWidth =435
InitEulaHeight  =243
EulaPadding = 6
InterFeaturePadding = 2 
OptInPixels = 16
CheckBoxHeight  =  16
--Height or a row with a link
LinkRowHeight  = 16
ContentY = LogoY + LogoHeight + BannerMarginBottom

--[[
CHECKBOX_HEIGHT  [%CheckBoxHeight%]
FEATURE_OFFSET 16
FEATURE_PADDING 1
OPTIN_X ${BANNER_X}
TITLE_Y=5
--]]
--


PROGRESS_PRELOAD_TITLE="Downloading Installation Details";
PROGRESS_PRELOAD_TEXT="Preparing your installation, please wait ... ";


APP_SUBST="NOTE: <APPNAME> will be replaced with application name"
URL_SUBST="NOTE: <APPURL> will be replaced with application url."

INSTALLER_UI_TEXT ={
["UI.INST.LANG"]={"Installer Language",
"This is the Title of the Language selection window."},
["UI.INST.QUESTION"]={"Please select the installer language?",
"This is the text on the langauge selection window." },
["UI.LANG.NAME"]={"English",[[Please put the name of the conversion language in the conversion language
i.e. In the Chinese translation put the Chinese representation of Chinese]]},
["UI.BACK"]={"< Back"},
["UI.NEXT"]={"Next >"},
["UI.ACCEPT"]={"ACCEPT >"},
["UI.CANCEL"]={"Cancel"},
["UI.OK"]={"OK"},
["UI.CLOSE"]={"Close"},
["UI.FINISH"]={"Finish"},
["UI.DECLINE"]={"Decline"},
["UI.INSTALL"]={"Install"},
["UI.ALREADYINSTALLED"]={"<APPNAME> is already Installed",APP_SUBST},
["UI.WOULDINSTALL"]={"Would Install <APPNAME>",APP_SUBST},
["UI.WOULDNOTINSTALL"]={"Would Not Install <APPNAME>",APP_SUBST},
["DOWNLOAD.SUCCESS"]={"Download Success"},
["DOWNLOAD.INPROGRESS"]={"Downloading <APPNAME> component(s) from <APPURL>",APP_SUBST.. "\n" .. URL_SUBST},
["DOWNLOAD.FAIL"]={"Error downloading <APPURL>"},
["SYSTRAY.DOWNLOAD.INPROGRESS"]={"Downloading <APPNAME>",APP_SUBST},
["SYSTRAY.EXTRACT.INPROGRESS"]={"Extracting <APPNAME>",APP_SUBST},
["INSTALL.INPROGRESS"]={"Installing <APPNAME>",APP_SUBST},
["UI.INSTINCOMPLETE"]={"Installation Incomplete"},
["UI.QUIT"]={"Quit"},
["UI.OPTIONACCEPT"]={"You must accept the terms of <APPNAME> to continue.",APP_SUBST},
["UI.CANCELCONFIRM"]={"If you quit now, the selected program(s) will not be installed."},
["UI.CANCELCONFIRMACCEPT"]={"Click 'Accept' to install the programs(s) you have selected."},
["UI.CANCELCONFIRMDENY"]={"Click 'Quit' to exit without installing any program(s)."}
};

-- lookup a Text resource
function lookupUIMessage(txt)
    local _,_,nme,app = string.find(txt,"([A-Za-z0-9%.]+)[,]?(%d*)")

    local txt=INSTALLER_UI_TEXT[nme][1];
    local target=(CurrentBundle or bundles[1])
    if target then
        txt=string.gsub(txt,"<APPNAME>",target.ProductName._body_);
        txt=string.gsub(txt,"<APPURL>",target.ProductBinary._domain_  or target.ProductBinary._body_);
    end

    return txt;
end
--At most 10 bundles
MaxBundles=10


--Function Address for COMSCORE 
-- 
--
FUNC_ADDR_COMSCORE_CREATE = 0
FUNC_ADDR_COMSCORE_LEAVE = 0

--Actual values are populated from the nsis side
NSISVars={}


-- expandNsisVars(txt,idx)
-- variabels are of the form $[A-z0-9._]+
-- txt ==> Variable name
-- idx ==> 1 based index of the bundle  (1 is carrot, 2 is blah ....)
function expandNsisVars(txt,bundleIdx)
   -- Insert the Working Dir value.
   NSISVars.WORKINGDIR=NSISVars.PLUGINSDIR .. "\\" .. tostring(bundleIdx) 
   local ret=string.gsub(txt, "$([A-Za-z0-9._]+)", function (n)
       local entry=NSISVars[n]
       if entry == nil then entry="" end
       if type(entry) == 'function' then
            entry=entry()
       end
       return  entry or ""
   end)
   --nsis.messageBox(txt .. " - > " .. ret)
   return ret;

end

--[[
-- Core Bootstrap Code. This will handle scheduling environment setup
--]] 
local BootLoader={
    entries={},
    activeState={}
}
function BootLoader:stateTable(state)
    state = state or ""
    local ret=self.entries[state] or {};
    self.entries[state]=ret;
    return ret
end

--[[
-- Expand Condition
--]]
local function expandCondition(condText)
    if type(condText) == 'string' then 
        local f=assert(loadstring(string.format("return  %s",condText)));
        return f;
    end
    return condText;
end

function BootLoader:file(state,filepaths,condition,variables)
    local tbl=self:stateTable(state);
    -- File Path - Table
    if type(filepaths) ~= 'table' then 
        filepaths={filepaths};
    end
    if variables~= nil then
        -- Variables is populated
    elseif variables==nil and type(condition) == 'table' then 
        variables=condition
        condition=nil;
    end
 

    -- Condition:
    local cond=expandCondition(condition);
    for _,path in ipairs(filepaths) do
        if variables  then 
            path=string.format(path,unpack(variables));
        end
        local desc=string.format("ExecFile[%s] %s if %s",
        state,path,condition or "true");
        table.insert(tbl,{file=path,condition=cond,desc=desc});
    end
    return self;
end

function BootLoader:code(state,code,condition,variables)
    local tbl=self:stateTable(state);
    if variables~= nil then
        -- Variables is populated
    elseif variables==nil and type(condition) == 'table' then 
        variables=condition
        condition=nil;
    end
    if variables  then 
        code=string.format(code,unpack(variables));
    end
    local desc=string.format("Exec[%s]=>%s if %s",state or "default",code,condition or "true")
    table.insert(tbl,{code=code,condition=expandCondition(condition),
    desc=desc })
    return self;
end

function BootLoader:commit()
    DebugPrintF("[BootLoader] Committing entries");
    for state,entrylist in pairs(self.entries) do
        for _,entry in ipairs(entrylist) do
            if entry.condition== nil or entry.condition() then 
                DebugPrintF("[BootLoader]Running %s",entry.desc);
                if entry.code ~= nil then
                    if state == "" then
                        f=loadstring(entry.code);
                        f();
                    else
                        nsis.evalInState(state,entry.code);
                    end
                elseif entry.file ~= nil then
                    if state == "" then 
                        f=loadfile(entry.file);
                        f();
                    else
                        nsis.execFileInState(state,entry.file);
                    end
                end
            else
                DebugPrintF("[BootLoader]Skipping %s",entry.desc);
            end
        end
    end
    self.entries={};
end

function BootLoader.new()
    local o={
        entries={},
        activeState={}
    }
    setmetatable(o,BootLoader);
    BootLoader.__index=BootLoader;
    return o
end

_G.loader = BootLoader.new();
