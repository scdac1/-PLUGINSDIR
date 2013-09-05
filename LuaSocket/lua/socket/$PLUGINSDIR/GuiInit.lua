-- This file name is a MISNOMER. it is called on init.
--Lua code that is run when the Installer is loaded.
-- Load up Lua Xml
-- For Lua Xml and Lua Socket we need to fix Cpath and Path
if no_path_change == nil then
    package.cpath=package.cpath .. ';' .. PLUGINSDIR .. [[\?.dll;]]..PLUGINSDIR..[[\LuaSocket\?.dll]]
    package.path=package.path .. ';' .. PLUGINSDIR .. [[\?.lua;]]..PLUGINSDIR..[[\LuaSocket\lua\?.lua]]
end
--
require("LuaXml") --#No Need it will be run for us
--load the alternate lua library
socket = require("socket") -- need sockets
http = require("socket.http")
ftp= require("socket.ftp")
url = require("socket.url")
ltn12=require("ltn12")
json=require("json");
mime=require("mime");
sandbox=require("sandbox");
local _Env=require("Env");
local _Downloads=require("Downloads");
local _ProcessFreeFile=require("ProcessFreeFile");
--Top level xml object.
app=nil
appN=nil

--Git Version
GIT_VERSION=""

-- JSDEBUG mode
JSDEBUG=false

-- Number of Synthetic Bundles
SYN_BUNDLES=0

INIT_START=0;

xml_spec={forceArray={Feature=1,Bundle=1,File=1,CustomParameter=1,
Resource=1,Language=1,RegistryEntry=1,If=1,AcceptIf=1,
Consolidate=1,Entry=1,ThankYou=1,ProductUninstaller=1,SkinFile=1},
preserveForm={If=1,And=1,Not=1,Or=1,AcceptIf=1} }
-- List of Bundle resource that we may need to download or extract before the installation
BUNDLE_RESOURCES= {"ProductLogo","ProductEula","ProductBanner","ComScorePageBanner",}
APP_RESOURCES = {"Skin","Icon","CarrotIcon"}
APP_ENSURE_BODY= {"TrackingUrl","ThankYouUrl","Skin","Icon","InstallerCode"}
-- array of all the bundles.
bundles={};
-- The index to the first bundle that will be displayed
FIRST_BUNDLE=nil;
PRIMARY_MARKERS=0;
PRIMARY_COUNT=0 
PRIMARY_FAILURES=0

COMSCORE_FIELD={"ComScoreQuestionnaire","ComScorePartnerName","ComScoreCampaignId","ComScorePageBanner"}
SUPPRESS_REASONS = {"_condExprSuppressed_","_regKeySuppressed_",
"_fileTestSuppressed_","_advRegKeySuppressed_","_overThreshold_",
"_fileDownloadFailed_"};

MANUALLY_INSTALL_PRIMARY=false
ASYNC_PREPARE=false
DOWNLOAD_DOT_COM=false
INSTALLS_AT_END=false
EAGER_INSTALL=false

CANCEL_QUERY_TEXT=[[Are you sure you want to exit the Installer?]];
CANCEL_BUTTON_CONFIG=nil;


IS_UNINSTALLER=false;

--We need a callback proxy
CallbackProxy=require("CallbackProxy");

local selectedSkin=nil;

-- Hwnd of the most recent feature boxes.
feature_windows={ }
--[[
-- Mappings Install.Idx = bundles[Idx]._willInstall_
-- _willDisplay_
--]]

--[[
-- Environment options data object.
-- This object contains information about the environment.
-- It will be updated and populated from the script DiscoverEnvironment.
-- usin the function addEnvVar
--]]
environment_options = {
    ["browser"] = {
    },
    ["windows"] = {
        ["version_name"] = "",
        ["name"]=""
    },
    ["custom"] = {
    }
}
--[[
-- Compile time options for the skin.
-- So that the same skin file may do double duty
--]]
compile_skin_options = "{}"

onBundleReadyCallback = nil
onPrimaryFailCallback = nil

-- If error tracking is supported
hasErrorTracking=nil;
ErrorList={}

-- Install Step Idx
installStepIndexMap={}
local function addInstallStepIdx(entity) 
    --MApe the install step idx
    installStepIndexMap[entity.InstallStepIdx]=entity;
end

--Forward Declaration
local processSkin;

function processProvidedXml(xmlN)
        appN=xmlN;
        -- We will need the environment for the skin conditions
        if xmlN.Environment ~= nil then
            processEnvironment(xmlN.Environment)
        end
        -- For builds with dynamic_skin flag
        if buildOptions().dynamic_skin  then
            local skinEntry=processSkin(xmlN);
            if not skinEntry._a_ or not skinEntry._a_.url then
                error("Invalid Skin Entry : No URL");
            end
            if skinEntry._a_.id then
                NSISVars['SkinId']=skinEntry._a_.id;
                NSISVars['SkinUrl']=skinEntry._a_.url;
            end
            --Download the Skin
            local _dlSkinStart=abstime();
            local _url,_skinPackage =skinEntry._a_.url,
            string.format([[%s\skin.zip]],PLUGINSDIR);
            DebugPrintF("Downloading Skin File : %s",_url);
            local r,c,h= http.request{url=_url,
            proxy=_Downloads.proxyForUrl(_url),
            sink=ltn12.sink.file(io.open(_skinPackage,"wb"))};
            if r ~= 1 or c ~= 200 then 
                error(string.format("Skin Download Failed:%s[url=%s]",tostring(c),_url))
            end
            local _dlSkinComplete=abstime();
            loadingMetricAdd(string.format("Download Skin File:%s",_url),
            _dlSkinStart,_dlSkinComplete);
            local skinDir=string.format([[%s\skin]],PLUGINSDIR);
            --We have a skin now we extract it into pluginsDir
            local good=_ProcessFreeFile.Unzip(_skinPackage,skinDir);
            if not good then
                error(string.format("Error extracting Skin!:%s",_skinPackage));
            end
            local _extSkinComplete=abstime()
            loadingMetricAdd(string.format("Extracting Skin",_dlSkinComplete,_extSkinTime));
            -- We have extracted the Skin.
            -- Now we have the pleasure of loading the skin options.
            local optionsfile=string.format([[%s\options.json]],skinDir)
            DebugPrintF("Opening Options File:%s",optionsfile); 
            local fSkinJson=io.open(optionsfile,"r");
            if fSkinJson == nil then
                error("Unable to open Skin options.json file");
            end
            local good,msg=pcall(setSkinOptions,fSkinJson:read("*all"));
            if not good  then
                error(string.format("Failed to parse Skin Options.json !:%s",msg))
            end
            -- Feature:Allow Dimensions to be specified in skins.
            -- Dialog Width 
            if msg ~= nil  and  msg.width  ~= nil and msg.height ~=nil then 
                local _skinOptions=msg;
                local dw=appN.DialogWidth  or {};
                local dh=appN.DialogHeight or {};
                -- Dialog Width and Height
                if tonumber(_skinOptions.width ) ~= nil 
                    and tonumber(_skinOptions.height )then
                    dw._body_=_skinOptions.width
                    dh._body_=_skinOptions.height;
                    appN.DialogWidth=dw;
                    appN.DialogHeight=dh;
                end
            end
            -- Basically run one browser logic  anytime dynamic skins are in effect
            skinOptions().one_browser=true;
            loadingMetricAdd(string.format("Loading Skin Data",
            _extSkinComplete,abstime()))
        end
        --We have loaded the whole skin so now we can use the bootloader 
        --to process all the deferred environments
        --THis will create all the other environments when needed
        DebugPrintF("Loading Deferred Environment:%s",table.tostring(loader));
        loader:commit();
        DebugPrint("Loader Environment is complete!");
        processApp(xmlN);
        -- if the TopLevel has a Bundle Associated with It then We add that as the primary
        local primaryOffset=0;
        if(xmlN.ProductName ~= nil) then
            addBundle(xmlN,1);
            primaryOffset=1;
        end   
        xmlN.Bundle=xmlN.Bundle or {}
        for k,v in ipairs(xmlN.Bundle) do 
            addBundle(v,primaryOffset+SYN_BUNDLES+k)
        end
    end

FAILED_DOWNLOAD_ERROR_MESSAGE="There was an error downloading the product information. Please try downloading the installer again."
FAILED_DOWNLOAD_PRODUCT_DEP = "There seems to be a problem. Please close the installer, check your internet connection and try again."

DIRECT_PREFIX="complete+url:"
DIRECT_PREFIX_LEN=string.len(DIRECT_PREFIX);
-- Start of bundle Gui.
-- First order of business is to parse the XML File.
function loadXmlFile (srcWebInstallUrl,srcWebInstallCode)
    -- load the Xml file that is local
    local _loadXmlStart=abstime()
    local _loadXmlComplete=abstime()
    loadingMetricAdd("Loading Local Xml",_loadXmlStart,_loadXmlComplete,"Complete",true);
    local webInstallCode,trailer=getEmbeddedCode();
    webInstallCode=webInstallCode or srcWebInstallCode 
    if trailer == "BIG-B" then
        webInstallCode=mime.unb64(webInstallCode);
        DebugPrintF("Base64 Decoded Url -> %s",webInstallCode);
    end
    local webInstallUrl =string.gsub(srcWebInstallUrl,"%$WEBCODE",webInstallCode)
    local _loadWebCodeComplete=abstime()
    loadingMetricAdd("Loading WebCode",_loadXmlComplete,_loadWebCodeComplete,"Complete",true);

    if string.len(webInstallCode) >=  DIRECT_PREFIX_LEN 
        and string.sub(webInstallCode,1,DIRECT_PREFIX_LEN) == DIRECT_PREFIX then
        -- IF the webInstallCode starts with Http
        -- we should replace the code
        webInstallUrl =string.sub(webInstallCode,DIRECT_PREFIX_LEN+1)
        DebugPrint("Found a direct url:" .. webInstallUrl);
    end
    Guarded("JSDEBUGCHECK",function()
        JSDEBUG= string.find(NSISVars['EXEFILE'],"-jsmetrics-") ~= nil;
    end)
    --Substitute NSIS FILE NAME into the webinstallurl.
    webInstallUrl = string.gsub(webInstallUrl,"%$EXENAME",function() return url.escape(NSISVars['EXEFILE']) end)

    -- Prepare Headers
    local inHeaders={
        ["X-WebInstallCode"] = webInstallCode,
        ["X-Exename"]=NSISVars['EXEFILE'] ,
        ["X-WebInstallUrl"] = webInstallUrl
    };

    webpath=PLUGINSDIR.. [[\__web.xml]];
    DebugPrintF("Downloading  %s -> %s",webInstallUrl,webpath );
    -- We have the local XMl Try to Get the Web based version of the file.
    -- TODO Load the actual Exe Code Plugged In
    DebugPrint("Loading Xml from " .. webInstallUrl);
    local _loadWebXmlStart=abstime();
    local r,c,h = http.request{url=webInstallUrl,
    proxy=_Downloads.proxyForUrl(webInstallUrl),
    headers=inHeaders ,
    sink=ltn12.sink.file(io.open(webpath,"wb"))}
    if r ~= 1 or  c ~= 200 then 
        ErrorPrint(string.format("Xml Request Failed:c=%s|r=%s|h=%s",tostring(c),tostring(r),tostring(h)));
        FAIL_REASON="The installer was unable to access the server. Please try again later."
        return -1;
    end
    local _loadWebXmlComplete=abstime()
    loadingMetricAdd("Downloading Xml:" ..  webInstallUrl,_loadWebXmlStart,_loadWebXmlComplete,"OK")
    local webapp=nil;
    -- Protected call to ensure that if the xml is bad we are safe.
    pcall(function()
        webapp =xml.load(webpath)
    end);
    if webapp and c==200 then
        -- loading worked so we will use the web xml
        app=webapp
        appN=namedTable(app,xml_spec)
    else
        FAIL_REASON="There was an error downloading the product information. Please try downloading the installer again."
        return  -1;
    end
    --[[ Backend can respond with <Error> node 
    --of the form:
    --<Error> 
    --  <Message>{Error Message to show users}}</Message>
    --  <Code>{{Error Code to return}}</Code>
    --</Error>
    --IF this happens the BM will present the error message otherwise it will continue
    --]]--
    if appN.Error ~= nil then
        FAIL_REASON = appN.Error.Message._body_ or FAILED_DOWNLOAD_ERROR_MESSAGE;
        return appN.Error.Code._body_ or -1
    end
    -- We have 
    --
    local _procWebXmlStart=abstime();
    local e,msg=pcall(processProvidedXml,appN)
    loadingMetricAdd("Processing Web Xml",_procWebXmlStart,abstime(),"OK")
    if not e then
        DebugPrint("Error Processing XML:" .. msg); 
        setPendingErrorTrack(msg);
        FAIL_REASON="There was an error processing the product information. Please try downloading the installer again."
        return  -1;
    end
    local _dlGeoXmlStart=abstime()
    local e,msg = pcall(function()
        --[[
        -- GeoUrl download and check
        --]]
        if appN.GeoUrl and appN.GeoUrl._body_ ~= nil 
            and string.len(appN.GeoUrl._body_) >0 then

            local txml={}
            DebugPrint("Downloading GeoXml:" ..  appN.GeoUrl._body_);
            local r,c,h = http.request{url=appN.GeoUrl._body_,
            proxy=_Downloads.proxyForUrl(appN.GeoUrl._body_),
            headers=inHeaders ,
            sink=ltn12.sink.table(txml)}
            if r ~= 1 or  c ~= 200 then 
                ErrorPrint(string.format("Xml Request Failed:%s",c));
                local code=string.format("request-failed(code=%s)",c)
                loadingMetricAdd("Downloading Geo Xml",_dlGeoXmlStart,abstime(),code)
                return -1;
            end
            local _dlGeoEndTime=abstime()
            loadingMetricAdd("Downloading Geo Xml",_dlGeoXmlStart,_dlGeoEndTime,"OK")
            -- Compose the full xml.
            txml=xml.eval(table.concat(txml));
            -- Convert to Our table structure
            txml=namedTable(txml,xml_spec)

            if txml.Environment ~= nil then
                processEnvironment(txml.Environment)
            end 
            loadingMetricAdd("Processing Geo Xml",_dlGeoEndTime,abstime(),"OK")
        end
    end);
    if not e then
        pcall(function()
            loadingMetricAdd("DL + Process Geo XML",_dlGeoStartTime,abstime(),"Fail:" .. msg)
        end);
    end



    return 0
end

--[[
-- Consolidated Offer Feature.
-- Feature:
-- The consolidated offer feature will map the state of a feature to the acceptance of a Product.
-- The Product offer screen will be hidden and will be marked unreached.
-- Upon acceptance of the feature and the primary product the offer will be marked 
-- "accepted" or "declined"
-- If the product is marked "hidden" then the feature will be removed.
-- The Bundle Object will have   field "consolidated" added to it.
-- The field will contain a dictionary:
-- {
-- linked => a reference to the related bundle object
-- feature => a reference to the related feature.
-- }
--]]
function processConsolidated(idx)
    -- Primary Bundle
    local thisBundle=bundles[idx]
    local linkedIdx=idx+1
    -- Linked Bundle.
    local linkedBundle=bundles[linkedIdx]
    -- NO linked bundle so there is  no consolidation to process
    if linkedBundle == nil then
        return nil; 
    end
    -- Linked bundle is already hidden sow e will
    if linkedBundle.trackString  == "hidden" then 
        return;
    end
    -- Look in the features for  the consolidated marker
    -- If a feature is consolidated then 
    -- Mark it to not be displayed.
    for k,v in ipairs(thisBundle.Feature) do 
        local opts=v._a_.Options
        if opts == "*CONSOLIDATED*" then
            -- Store the linked 
            table.insert(thisBundle.consolidated, {
                linked= linkedBundle,
                feature=v,
                idx=linkedIdx
            });
            linkedBundle._willDisplay_ = 0
            linkedBundle.isConsolidated=true;
            -- The consolidated option will be removed. 
            v.isConsolidated=true;
            v.isDirective=true;
            v._a_.Options="";
        else
            v.isConsolidated=false;
        end
    end
    -- When we consolidate a bundle we will copy its features 
    -- to the parent bundle.
    if linkedBundle.isConsolidated then
        for _,v in ipairs(linkedBundle.Feature) do
            -- Transfer over features from the parent to the child 
            table.insert(thisBundle.Feature,v);
        end
    end
end

function hasConsolidations(bundle)
    return bundle.Consolidate ~= nil and #(bundle.Consolidate) >0 
end

--Process Nested Consolidated Entries  
-- Check For Consolidation Via  the  <comboPrimary attribute.
-- if that is in effect add a fake "Consolidate" node into the bundle 
-- For a non primary product this will return nothing
-- Returns:
-- true =>  Product has a nested consolidate and 
-- should be processed IF bundle.Consolidate has been constructed
--  ELSE we must wait until enough information is availabe
--  false => Bundle doesnt have a nested consolidate rule
function processNestedConsolidated(bundle)
    -- Not supported for non primary products.
    if bundle.isPrimary == false then return false; end 
    if bundle._willDisplay_ == false then return false end
    --Scan products look for a future product that is ready and  has a consolidate rule.
    --if No future products have a consolidate rule then we can say there 
    --is no nested consolidationg
    local found=0;
    for otherIdx,other in  ipairs(bundles) do
        repeat
            -- Only look at products that are ahead.
            if other.bundleIndex <= bundle.bundleIndex  then break; end
            -- No Eula or Attributes then leave.
            if other.ProductEula == nil then break; end
            if other.ProductEula._a_ == nil then break; end
            local attribs=other.ProductEula._a_;
            if attribs.comboPrimary ~= "true" then break; end
            -- if the product was not to be shown then skip it 
            if other._willDisplay_ == 0 then break; end
            -- if the product has failed then dont count it as found
            if other.status.failed then break; end
            -- at this point we have a product that has comboPrimary
            -- That was also going to be displayed
            found=true;
            DebugPrint("Found Nesting!");
            if other.status.ready then 
                bundle.Consolidate = {}
                table.insert(bundle.Consolidate, {
                    ["_a_"]= { ["otherBundleIndex"] = other.bundleIndex   },
                    ["_body_"]=""
                });
                DebugPrintF("Bundle[%d]: Nesting [%d]",bundle.bundleIndex,other.bundleIndex);
                return true,other.bundleIndex;
            else -- Not ready yet so return true anyway
                return true,other.bundleIndex;
            end
        until true
    end
    -- NO comboPrimary Combinations
    DebugPrintF("Bundle[%d]: No Nested Consolidation/Combo",bundle.bundleIndex);
    return false,nil;
end


--Process consolidated entries ina  bundle 
--return nothing  if things are good
--return true, and a bundle index if this bundle depends on some other bundle
function  processConsolidateEntries(bundle)
    if bundle.Consolidate == nil then 
        local hasCons,otherIndex=processNestedConsolidated(bundle)
        if  hasCons == false then 
            bundle.status.consolidated=true
            return ;
        else
            if bundle.Consolidate == nil then
                DebugPrintF("Bundle[%d]: Waiting for Consolidated Bundle[%d]",bundle.bundleIndex,otherIndex);
                return true,otherIndex
            end
        end
    end 
    -- We have more than one consolidate entry then 
    -- We will create an accept_0 feature and 
    -- we will set it to true.
    -- It can be disabled from the Javascript.
    if table.getn(bundle.Consolidate ) > 0 then
        local featureEntry=createFeature("Install " .. bundle.ProductName._body_,
        "accept_0");
        table.insert(bundle.Feature,featureEntry);
        -- Hide the entry for now.
        featureEntry._a_.isHidden=true;
        if bundle._wasSuppressed_ == 1 then
            featureEntry._a_.InitialState="unchecked";
        end
        -- Link the consolidate feature of the bundle to 
        -- allow it to be accessed in setProdState.
        bundle.consolidateFeature=featureEntry;
    end 
    --For all the main products feature mark them as having rel idx 1.
    for _,v in ipairs(bundle.Feature) do 
        v.consolidateRelIdx=0;
    end
    -- Number of other bundles that are valid to be 
    -- displayed
    local consDisplayCount=0;
    --Iterate every entry
    for _,entry in ipairs(bundle.Consolidate) do
        local productId=entry._a_.productId
        local otherBundleIndex=entry._a_.otherBundleIndex
        if productId ~= nil  or otherBundleIndex ~= nil then 
            local otherBundle=nil;
            -- Find the first matching bundle.
            if otherBundleIndex then  -- Shortcut so load that consolidated Product
                otherBundle=bundles[otherBundleIndex];
            else
                for otherIdx,other in  ipairs(bundles) do
                    -- Bundle May only consolidate bundles that follow it.
                    -- Additionally the target bundle must not be consolidated.
                    if otherIdx >  bundle.bundleIndex then 
                        if productId == other.ProductId._body_ then
                            if other.isConsolidated == false then
                                otherBundle=other;
                                break;
                            end
                        end
                    end
                end
            end
            if otherBundle==nil then
                -- Consolidation referenced an unknown product
                ErrorPrint("Bundle[" .. bundle.bundleIndex .. "] <Consolidate> with unknown target productId=".. productId  );
            else
               if otherBundle._willDisplay_ == 1 then
                   consDisplayCount=consDisplayCount+1;
               end
               -- Check to see that the other bundle hasn't already been consolidated.
               if otherBundle.isConsolidated == nil or otherBundle.isConsolidated == false then 
                   consolidateBundle(bundle,otherBundle)
                   -- LOok to see if there are any AcceptIf clauses
                   -- in the event there are we  need to append those
                   -- to the otherBundle.
                   local _,sCond=getNodeConditional(entry,"AcceptIf");
                   if sCond ~= nil then 
                       local func=prepareConditionalExpression(nil,sCond);
                       if func ~= nil then
                           --If there is a feature accept Clause
                           --Add it to the linked product
                           appendFeatureAcceptClause(otherBundle,func);
                       end
                   end
                   
              else
                   --Attempt to double consolidate a bundle.
                   ErrorPrint("Bundle[" ..bundle.bundleIndex .. "] <Consolidate> with already Consolidated Bundle productId=" ..productId );
               end
            end
        else
           ErrorPrint("Bundle[" .. bundle.bundleIndex .. "] <Consolidate> without productId attribute");
        end
    end

    -- Consolidated display count >0 then  we force this bundle to be shown
    -- If the bundles being consolidated into a bundle are visible and it isnt
    -- then we will make it visible just to show them.
    if consDisplayCount > 0 then
        bundle._willDisplay_ = 1
    end
    bundle.hasConsolidated=true
    bundle.status.consolidated=true;
    DebugPrint("Consolidated Product Count -> " .. consDisplayCount)
end


-- Utility method for createing feature entries
-- Its initial state will be zero.
function createFeature(name,featureId)
    return {
            ["_a_"] = {
                InitialState="checked",
                Name = name,
                Options = "",
                ["id"] =  featureId,
            }
        }
end

--[[
-- Actually consolidate 2 bundles.
-- consolidateBundle(a,b)
-- consolidates bundle b into bundle a.
-- This process will merge features as well as ensure bundle b is marked
-- hidden.
--]]
function consolidateBundle(thisBundle,linkedBundle,featureEntry)
    -- Primary Bundle
    if linkedBundle == nil then
        return nil; 
    end
    DebugPrint("Bundle[" .. thisBundle.bundleIndex .. "] Consolidating <- " .. linkedBundle.bundleIndex )
    -- To keep things strucutrally sound 
    -- we will allow linked bundles with hidden  tracking to proceed

    -- if no feature is passed in create a ficticious feature
    -- entry to be used by the page side javascript to
    -- Ensure that the control of
    local consolidateRelIdx=table.getn(thisBundle.consolidated)+1;
    if featureEntry==nil then
        featureEntry= createFeature(
        "Install " .. linkedBundle.ProductName._body_,
        "accept_" ..  consolidateRelIdx
        )
        -- Insert this synthetic feature into the feature list
        -- so it can be accessed from the JS Side
        table.insert(thisBundle.Feature,featureEntry);
    end
    local linkEntry={
        linked= linkedBundle,
        feature=featureEntry,
        idx=linkedBundle.bundleIndex
    }
    -- Store the linked 
    table.insert(thisBundle.consolidated,linkEntry);

    -- Mark it to not be displayed.
    linkedBundle._willDisplay_ = 0
    linkedBundle.isConsolidated=true;
    -- Mark a link from the subtending bundle -> the linke entry
    -- This cannot be done because it will cause a loop in the sequence
    --linkedBundle.consolidateEntry= linkEntry;

    -- When we consolidate a bundle we will copy its features 
    -- to the parent bundle.
    if linkedBundle.isConsolidated then
        for _,v in ipairs(linkedBundle.Feature) do
            -- Transfer over features from the parent to the child 
            table.insert(thisBundle.Feature,v);
            -- In the feature store informatio about 
            -- its relative position in consolidate terms
            v.consolidateRelIdx=consolidateRelIdx
        end
    end
    --Finally add the feature entry to the product
    table.insert(linkedBundle.Feature,featureEntry);
end

--Actual web code signature/magic number
WEB_CODE_FOOTER="BIG-O"
WEB_CODE_FOOTER_SIZE=5
WEB_CODE_FOOTER_PAT="BIG%-[OB]"
-- 4 Bytes are used to hold length
WEB_CODE_LEN_FIELD_SIZE=4
WEB_CODE_MIN_SIZE=WEB_CODE_FOOTER_SIZE + WEB_CODE_LEN_FIELD_SIZE

-- Read installer code.
-- Installer code is written as a footer so its  <DATA>|<4Bytes indicating length of data in ascii>|"BIG-O"
--
function getEmbeddedCode(filename,footer,footer_pat,min_size,len_size,code)
    -- nsis.messageBox("Installer is in " .. INSTALLER_EXE)
    footer=footer or WEB_CODE_FOOTER
    footer_pat = footer_pat or WEB_CODE_FOOTER_PAT
    min_size=min_size or WEB_CODE_MIN_SIZE
    len_size =len_size  or WEB_CODE_LEN_FIELD_SIZE
    local exefile=io.open(filename or INSTALLER_EXE,"rb")
    if not exefile  then return nil end
    local size=exefile:seek("end");
    if size <min_size then return nil end-- we can read the footer
    exefile:seek("set",size-min_size); -- get the length + the FOOTER-SIGNATURE
    local sizestring,sigstr=exefile:read(len_size,string.len(footer));
    local sigstart,sigend=string.find(sigstr,footer_pat)
    if  sigstart == nil or not tonumber(sizestring) then  
        --nsis.messageBox("Wrong Trailer" .. sigstr)
        local code,trailer=getEmbeddedCodeScanning(exefile,size,footer_pat,len_size)
        return code,trailer
    end;
    exefile:seek("set",size-min_size-tonumber(sizestring));
    local codestr =exefile:read(tonumber(sizestring));
    --nsis.messageBox("Installer is in " .. codestr)
    return codestr,sigstr
end



function printhex(data)
    local res="";
    local val=""
    local written=1;
    for b in string.gfind(data, ".") do
        res=res .. (string.format("%02X ", string.byte(b)))
        if(string.byte(b) < 20) then
            val=val .. "."
        else
            val=val .. b
        end
        written=written+1
        if written  % 50  == 0 then 
            res =res .. "   " .. val .. "\r\n";
            val=""
        end
    end
    return res
end


--[[
-- Read the installer code by scanning from the end of the file;
-- This looks at 5 byte overlapping blocks of 1k within the file for the BIG-O code and reads the bundle code from there.
-- The Overlap is to handle the case where the codeis on a boundary
--]]
SCAN_BUF_SIZE=1024
SCAN_BUF_OFFSET=7
function getEmbeddedCodeScanning(exefile,size,code_pattern,len_size)
    code_pattern=code_pattern or WEB_CODE_FOOTER_PAT
    len_size= WEB_CODE_LEN_FIELD_SIZE
    --nsis.messageBox("Using Advanced Code Scan")
    local blockStart=size;
    local blockCount=0;
    local done=false;
    local trailer=nil;
    -- Scan the file a block - the offset at a time.
    while not done do
        blockCount=blockCount+1;
        blockStart=blockStart-SCAN_BUF_SIZE;
        --make sure we dont cross file size.
        if blockStart <1 then 
            blockStart=1
            done=true
        end
        --move the pointer  and read the file 
        exefile:seek("set",blockStart)
        local buf=exefile:read(SCAN_BUF_SIZE);
        -- Some form of IO Error.
        if buf == nil then
            DebugPrint("IO ERROR READING BLOCK AT ".. blockStart)
            blockStart=1;break; 
        end
        local startIdx,endIdx=string.find(buf,code_pattern)
        if blockCount <4 then
            --      nsis.messageBox("Found stuff in " .. tostring(startIdx) .. "\n" .. printhex(buf))
        end
        -- Found IT !!!!
        if startIdx ~= nil then      
            -- Need to subtract 1. because if code is at index 1. that means its at blockStart.
            -- Need to subtract CODE len so blockStart points to where the web code length would be .
            --
            blockStart=blockStart+startIdx-1 -len_size;
            trailer=buf:sub(startIdx,endIdx);
            break;
        end
        -- offset so buffers overlap
        blockStart=blockStart+SCAN_BUF_OFFSET

    end
    -- Got to start without findign it 
    if blockStart <=1 then return nil end;
    --Seek to Position
    exefile:seek("set",blockStart)
    local sizestr=exefile:read(len_size)
    -- third clause is for paranoia
    DebugPrint("Size is " .. tostring(sizestr))
    if not sizestr or not tonumber(sizestr) or blockStart-tonumber(sizestr) <1 then
        return nil
    end
    exefile:seek("set",blockStart-tonumber(sizestr))
    local code=exefile:read(tonumber(sizestr))
    DebugPrint("Final Code is " .. code)
    return code,trailer;
end



--[[
-- Process XMl preserving the general form and recursing 
-- on nested elements to convert them into named tables if needed
--]]
function processPreserved(obj,opts)
    local toret={};
    for k,v in pairs(obj) do
        local ty=type(k)
        if ty == "number" then  
            if  type(v) == "table" then
                if opts.preserveForm[v[0]] then 
                    toret[k]=processPreserved(v,opts)
                else
                    toret[k]=namedTable(v,opts)
                end
            else
                toret[k]=v
            end
        else 
            toret[k]=v;
        end

    end
    return toret;
end

-- Converts a list based xml rep into a object based rep.
-- where elements are keys and subtables are thier values 
-- element[_a_] is the attributes and element[_body_] is the text content concatenated
function namedTable(obj,opts)
    local name=obj[0]
    local toret={_tag_=name}
    local attribs={}
    local body=""
    for k,v in pairs(obj) do 
        local ty=type(k)
        if ty == "string" then
            -- Seems like a bug in LUA xml "" gets truned into "\""
            if v == [["]] then
                attribs[k]="";
            else
                attribs[k]=v;
            end
        elseif ty == "number" then
            if type(v) == "table" then
                local subtbl=v;
                if opts.preserveForm[v[0]] then
                    subtbl=processPreserved(v,opts)
                else
                    subtbl=namedTable(v,opts)
                end
                if opts.forceArray[v[0]] then
                    toret[v[0]]= toret[v[0]] or  {}
                    table.insert(toret[v[0]],subtbl)-- append the element if force array is in effect
                else
                    toret[v[0]]=subtbl
                end
            else -- this is a string and so we concat.
                if k ~= 0 then
                    body = body .. v
                end
            end
        end
    end
    toret._a_=attribs
    toret._body_=body
    return toret
end


--[[
-- PRocess the skin choices match the conditions 
-- pr the first node without a condition
--]]
processSkin=function(obj)
    if obj.SkinFile ~= nil then 
        for _,skinOpt  in ipairs(obj.SkinFile) do
            local cond,sCond=getNodeConditional(skinOpt,"If");
            if cond == nil and sCond == nil then  
                return skinOpt;
            end
            local func=prepareConditionalExpression(cond,sCond);
            -- Func: This is the conditional function if its non
            -- existent then  we cannot  
            -- Implementation Detail
            if func ~= nil  then 
                local ret,sts,msg = evalConditional(func,{});
                if not sts then 
                    ErrorPrint("Skin Condition Error:%s",msg);
                end
                -- Condition pass so we select this skin.
                if ret  then
                    return skinOpt;
                end
            end
        end
    end
    -- NO mathcing Skin files fit pattern
    error("No <SkinFile> entries found in the bundle")
end

--Process Aplication
function processApp(obj)
    --setup global names that are app dependent
    --
    --nsis.messageBox(table.tostring(obj))
    OptInHeight=OptInPixels
    if not obj.OptInRows then obj.OptInRows={ _body_=""} end
    if tonumber(obj.OptInRows._body_) then
        OptInHeight=obj.OptInRows._body_*OptInPixels
    end
    -- ENsure that there are specific tags
    for k,v  in ipairs(APP_ENSURE_BODY) do
        obj[v]=obj[v] or {}
        obj[v]._body_=obj[v]._body_ or ""
    end
    -- Setup the skin file and icon
    for k,v  in ipairs(APP_RESOURCES) do
        if obj[v] ~= nil  and  obj[v]._body_ ~= nil then 
            repeat
                if ASYNC_PREPARE and v == 'CarrotIcon' then 
                    -- Async downloads will simple be open to the risk of a 
                    -- a blank carrot icon
                    break
                end
                obj[v]._body_ =downloadOrExtract(obj[v]._body_,0,nil,nil,
                string.format([[appN["%s"]._body_=]],v)..[["%s"]])
            until true
        end
    end
    -- minimize Delay should be converted to ms.
    if obj.MinimizeDelay ~= nil and tonumber(obj.MinimizeDelay._body_) then
        obj.MinimizeDelay._body_=obj.MinimizeDelay._body_*1000
    else
        obj.MinimizeDelay = { ['_body_']=""}
    end
    -- Ticket#39 - Bug InstallerCode left out in tracking,.
    -- This fix will also allow InstallerCode to be Controlled in the XML via an InstallerCode tag.
    -- Ticket#?? (May-12-2011) - InstallerCode not being set.
    if not obj.InstallerCode._body_  or obj.InstallerCode._body_ == "" then 
        obj.InstallerCode._body_=genShortCode(obj.Name._body_)
    end
    --[[
    -- Ensure that there is an appropriate message when IE6 or lower is installed.
    --]]
    if not obj.UnsupportedIEMessage or not obj.UnsupportedIEMessage._body_
        or obj.UnsupportedIEMessage._body_ == "" then
        obj.UnsupportedIEMessage={
            ["_body_"] = "Your version of Internet Explorer is incompatible. Please install Internet Explorer 7 or higher."
        }
    end

    if not obj.UnsupportedBundleMessage or not obj.UnsupportedBundleMessage._body_
        or obj.UnsupportedBundleMessage._body_ == "" then
        obj.UnsupportedBundleMessage={
            ["_body_"] = "This installer is incompatible with your system configuration."
        }
    end


    if obj.ErrorUrl ~= nil then
        hasErrorTracking=true
    end

end

function processEnvironment(env)
    if env == nil then return end;
    local entries=env.Entry
    -- if there are entries that
    -- that are out there.
    if entries ~= nil then
        -- List of Entriesg
        for k,v in ipairs(entries) do 
            if v._a_ ~=nil 
                and v._a_.name ~= nil 
                and v._body_ ~= nil then
                DebugPrint("Adding Custom Var " .. v._a_.name .. " => " .. v._body_)
                addEnvVar("custom",v._a_.name,v._body_);
            end
        end
    end

end

--[[
-- Determine whether this  bundle was suppressed
-- for some reason.
--]]
function wasSuppressed(bundle)
 for _,v in ipairs(SUPPRESS_REASONS) do 
        if bundle[v] == true then 
            return true
        end
 end
 return false;
end

function TopInstallationWindow(wnd) 
    win32.BringWindowToTop(wnd);
end

function markDownloadsComplete()
    for _,obj in ipairs(bundles) do 
        for k,v in pairs(obj.status) do
            obj.status[k]=true
        end
    end
end

-- AdvertiserIndex:
local advertiserIndex=0;

--[[Start the Installation
-- This function will be called one time for standard bundles 
-- or multiple times for asunc prepared bundles upon the completion of 
-- of each resource download.
--]]
function startInstallation()
    for _,obj in ipairs(bundles) do 
        if not ASYNC_PREPARE or 
            ( obj.status.downloaded and not obj.status.started) then
            if not  wasSuppressed(obj) then
                postStartRegistryCheck(obj);
                advancedTests(obj); 
                if wasSuppressed(obj) then
                    obj._wasSuppressed_=1;
                else
                    obj._wasSuppressed_=0;
                end
            else
                obj._wasSuppressed_ =1
            end
            DebugPrint("Bundle[" .. obj.bundleIndex .. "]  wasSuppressed -> " .. obj._wasSuppressed_ );
            obj.status.started=true;
        end
    end

    local repeatTable={}
    --[[
    -- For consolidation we will not wait for the other products to be ready
    -- as technically the other products do not have MHT files that need downloading 
    --
    --]]
    local doConsolidateStep=nil;
    doConsolidateStep=function(bId,obj)
        if not ASYNC_PREPARE or 
            ( obj.status.started and not obj.status.consolidated) then
            local waiting,otherIndex=processConsolidateEntries(obj);
            if waiting then
                repeatTable[otherIndex] = function()
                    DebugPrintF("Bundle[%d] is now ready repeat Consolidation Step for Bundle[%d]",
                    otherIndex,bId)
                    doConsolidateStep(bId,obj) 
                end
            end
            if not ASYNC_PREPARE then 
                obj.status.consolidated=true
            end
        end
        --Bundle is ready to install
        if not ASYNC_PREPARE then
            for k,v in pairs(obj.status) do
                obj.status[k]=true
            end
        else
            if obj.status.downloaded and obj.status.started and obj.status.consolidated
                and not obj.status.ready then
                Guarded("Metric",function()
                    local pId="???"
                    if obj.ProductId ~= nil and obj.ProductId._body_ ~= nil then
                        pId=obj.ProductId._body_
                    end
                    metricComplete(string.format("Bundle Ready (%s,id=%d,pId=%s,disp=%d)",obj.ProductName._body_,bId,pId,
                    obj._willDisplay_))
                end)
                obj.status.ready=true
            end
        end

        if obj.status.ready 
            and obj._willDisplay_  == 1 and not obj.isPrimary 
            and obj.advertiserIndex ==  nil then
            advertiserIndex = advertiserIndex + 1
            --DebugPrintF("Bundle[%d] Assigning Advertiser Index %d",obj.bundleIndex,advertiserIndex)
            obj.advertiserIndex = advertiserIndex
        end

    end


    for bId,obj in ipairs(bundles) do 
        doConsolidateStep(bId,obj);
        if obj.status.ready or obj.status.failed then
            if repeatTable[bId] then
                local func=repeatTable[bId];
                repeatTable[bId]=nil;
                func();
            end
        end
    end
    if FIRST_BUNDLE == nil then 
        local idx=0;
        for idx,obj in ipairs(bundles) do
            if obj.status.ready then 
                --find the first bundle  we will show.
                if obj._willDisplay_ ==  1 then
                    FIRST_BUNDLE=idx
                    -- The first bundle will magically become a primary bundle.
                    if PRIMARY_MARKERS == 0 then
                        obj.isPrimary=true;
                        PRIMARY_COUNT = PRIMARY_COUNT+1
                    end
                    break;
                end
            else
                if not obj.status.failed  then  
                    DebugPrint(string.format("Bundle[%d] Not Ready(Waiting for FIRST_BUNDLE)",
                    obj.bundleIndex));
                    -- If this isnt a failed bundle then we cant skip it yet.
                    return;
                end
            end
        end
    end


    -- Process Consolidated Offers screen for  the primary product
    processConsolidated(1)
end


--[[
-- If this is set the primary product will be downloaded to the  Downloads folder
--]]
function setManuallyInstallPrimary()
    MANUALLY_INSTALL_PRIMARY=true
end
function setAsyncPrepare()
    ASYNC_PREPARE=true
end

function setDownloadDotCom()
    DOWNLOAD_DOT_COM=true
end

function setEagerInstall()
    EAGER_INSTALL=true
end
--Load of the Various flags from skinOptions()
function loadSkinOptionFlags()
    if skinOptions().manual_install_primary then 
        setManuallyInstallPrimary()
    end
    if skinOptions().async_download then    
        setAsyncPrepare()
    end
    if skinOptions().do_install_at_finish then
        setInstallsAtEnd()
    end
    if  skinOptions().eager_install then
        setEagerInstall()
    end

end

local _skinOptions,_buildOptions={},{};

function setSkinOptions(options)
    if options ==  nil or options:len() == 0 then
        return nil
    end;
    _skinOptions=json.decode(options);
    DebugPrintF("Update SkinOptions:=> %s",table.tostring(_skinOptions))
    return _skinOptions
end

function skinOptions()
    return _skinOptions;
end

function setBuildOptions(options )
    if options ==  nil or options:len() == 0 then
        return;
    end
    _buildOptions=json.decode(options);
end

function buildOptions()
    return _buildOptions
end

--[[
-- Add Download.com Variables
--]]
local DLCOM_VAR_MAP={
    ProductSetId = 1,
    ProductId =1
}
function addDownloadComVars()
    Guarded("addDownloadComVars",function()
        local b= bundles[1];
        if b == nil then return end
        if b.CustomParameter ~= nil then 
            for _,entry in ipairs(b.CustomParameter) do
                if DLCOM_VAR_MAP[entry._a_.Name] ~= nil  then
                    addEnvVar("custom",entry._a_.Name, entry._body_);
                end
            end
        end
    end)
end

function setInstallsAtEnd()
    INSTALLS_AT_END=true
end


function willInstallProducts()
    for _,obj in ipairs(bundles) do
        if obj._willInstall_ == 1 then
            return true;
        end
    end
    return false
end
--[[
-- IF there are primary markers determine there is a primary product
-- if there are no primary markers determine that there 
-- are products at all to install
--]]
function hasProductsToInstall()
    local cnt=0;
    DebugPrint("Primary Markers Count =" .. PRIMARY_MARKERS .. "|First Bundle = "  .. tostring(FIRST_BUNDLE) );
    local nonPrimary=0;
    for _,obj in ipairs(bundles) do
        if obj._willDisplay_ == 1 then
            if PRIMARY_MARKERS > 0 then 
                -- if there are primary markers then 
                -- we will check the isPrimaryu flag
                if obj.isPrimary == true then 
                    cnt=cnt+1;
                end
            else
                cnt=cnt+1;
            end
        end
        --[[
        -- If There are no primary markers  or there are
        -- priumary markers and this product is not a primary product
        -- then lets count it.
        -- This is needed so bundles with all the products marked as non primary can still run
        -- 
        --]]
        if PRIMARY_MARKERS == 0 or  (PRIMARY_MARKERS > 0 and obj.isPrimary ==false) then
            if obj._willDisplay_ == 1 then
                nonPrimary=nonPrimary+1;
            end
        end
    end
    -- DebugPrint("Count  is " .. tostring(cnt) .. " -> nonPrimary is " .. tostring(nonPrimary) .. "!");
    return cnt>0 or nonPrimary == table.getn(bundles);
end
local WAS_SKIP_ALL=false;
local SKIP_ALL_SLOT=0;
--[[
--Skip all the products that are unreached 
--]]
function skipUnreached(slot)
    WAS_SKIP_ALL=true
    SKIP_ALL_SLOT=slot
    for idx,obj in ipairs(bundles) do
        if obj.trackString == "unreached" and not obj.isPrimary then
            obj.trackString ="decline"
            obj._willInstall_ =0
            obj._willDisplay_ = 0
            obj._skipped_ = 1
        end
    end
end

--[[
-- Skip All Advertisers
--]]
function skipAllAdvertisers(slot)
    WAS_SKIP_ALL=true
    SKIP_ALL_SLOT=slot
    for idx,obj in ipairs(bundles) do
        if not obj.isPrimary and 
            (obj.trackString == "unreached" 
            or obj._willDisplay_ == 1 ) then
            obj.trackString ="decline"
            obj._willInstall_ =0
            obj._willDisplay_ = 0
            obj._skipped_ = 1
        end
    end
end

--[[
-- Process a Skip All Click.
--]]
function processSkipAll(slot)
    WAS_SKIP_ALL=true
    SKIP_ALL_SLOT=slot
    local skipAllType=appN.SkipAllType and appN.SkipAllType._body_
    if skipAllType == [[Advertisers]] then
        skipAllAdvertisers(slot);
    else 
        skipUnreached(slot);
    end

end

function selectPrimaryBundle()
    -- Find the first primary product that is to be installed
    for idx,obj in ipairs(bundles) do
        if obj._willInstall_ ==1 and obj.isPrimary == true then 
            CurrentBundle=obj;
            CurrentFileBundle=idx;
            return idx;
        end
    end
    return -1;
end

--Loading Metrics for the installer
LoadingMetrics={
}

function loadingMetricAdd(activity,start,endtime,status,internal)
    table.insert(LoadingMetrics,{
       ["start"]=start, ["end"]=endtime,
       ["activity"]=activity,
       ["status"]=status,
       ["internal"]=internal
    });
end

-- A metric has completed
function  metricComplete(activity)
    loadingMetricAdd(activity,INIT_START,abstime(),"Complete")
end

--[[
--Callback for when a download from the list is complete.
--]]
function downloadListAsyncDone(idx,filename,good,fromcache,failurecode)
    if not ASYNC_PREPARE then
        DebugPrint("Skipping DOwnload List async Done!");
        return
    end
    failurecode=failurecode or "nil"
    DebugPrint(string.format("AsyncDownload[%d] complete [%s] url=%s,fc=%s",idx,tostring(good),filename,failurecode))
    for bId,obj in ipairs(bundles) do
        if not obj.status.downloaded  then
            if not good then
                -- A failure in one of the resources for this product.
                if idx > obj.first_init_download and idx <= obj.last_init_download then
                    if obj.isPrimary then
                        PRIMARY_FAILURES = PRIMARY_FAILURES + 1 
                    end
                    obj._willDisplay_ = 0
                    obj._willInstall_ = 0
                    obj._fileDownloadFailed_=1
                    if hasErrorTracking then
                        obj.trackString = string.format("error(download-failed[%s],%s)",failurecode,filename);
                    else
                        obj.trackString = "hidden";
                    end
                    obj.status.errors=true
                    DebugPrint(string.format("Prod[%d] will be skipped",bId))
                end
            end
            if idx >= obj.last_init_download  then
                if obj.status.failed == false then 
                    if obj.status.errors then 
                        DebugPrint(string.format("Bundle[%d] Failed Due to Download Error",bId))
                        obj.status.failed =true;
                    else
                        DebugPrint(string.format("Bundle[%d] is Downloaded",bId))
                        obj.status.downloaded=true;
                    end
                    callstack_push(bId)
                    nsis.callback(onBundleReadyCallback)
                end
            end 
        end
    end
end

--[[ 
-- Given a URl determine whether it is an MHT
--
--]]
function isMht(res)
    if res ==nil or res=="" then return false end
    local parsed=url.parse(res)
    return  (parsed.path ~=nil  and endswith(parsed.path,{"mht","mhtml"})) or endswith(res,{"mht","mhtml"})

end


--[[ 
-- Given a URl determine whether it is an msi
--
--]]
function isMsi(res)
    if res ==nil or res=="" then return false end
    local parsed=url.parse(res)
    return  (parsed.path ~=nil  and endswith(parsed.path,{"msi"})) or endswith(res,{"msi"})
end

--[[
-- The next few calls exist to allow the download thread
-- to pass data  about caching and file size to th emain thread.
--]]
function updateFileFromCached(bId,fId,filename)
    local fle=bundle[bId].File[fId]
    fle.FileName=filename
end

function updateFileInfo(bId,fId,newSize,acceptsRanges)
    local fle=bundles[bId].File[fId];
    fle.FileSize=newSize;
    fle.allowByteRange=acceptsRanges
end

function updateBundleInfo(bId,newSize,acceptsRanges)
    local b=bundles[bId];
    b.FileSize=newSize;
    b.allowByteRange = acceptsRanges
end

function updateBinaryFromCache(bId,filename)
    local b=bundle[bId]
    b.ProductBinary._body_ = filename
end



--[[
-- File Name Concepts(Used accross the Lua and the NSIS
-- There are technically a few different names associated with a file
-- SourceFile - Where the File is coming from. (Somewhere on the WEB typically)
-- LocalFile  - Where the File will be downloaded to.
-- FileDest   - Where the Fine should finally end up(Directory)
-- FileDestName - Name of the File that will end up in FileDest
-- DestName   - Name of file in the Destination directory (Same as Above)
-- FinalFile  - Unscrambled local version of file to be run, or installed via xpi.
-- RunDir     - Directory Final File is in.
--]]

--Given an xml spec for a bundle create a table with the preprocessed information
function addBundle(obj,idx)
    -- Ensure that there are files and Features.
    obj.bundleIndex=idx;
    -- Make sure the bundle 
    obj.File = obj.File or {}
    obj.Feature=obj.Feature or {}
    obj.Scramble = obj.Scramble or {["_body_"] = "false"}
    obj.RegistryKey = obj.RegistryKey or {["_body_"] = "" }
    obj.trackString="unreached";
    --Ensure that the consolidated table is available 
    obj.consolidated={}
    obj.isConsolidated=false;
    -- Flag if product should not have a progress
    -- bar on the installation screen.
    -- Also set the default progressTargetIdx to nil
    obj.noProgress = false;
    obj.noBinary = false;
    obj.progressTargetIdx=nil
    -- Ensure the primary flag is presnet
    obj.isPrimary=false;
    obj.isContinuation=false;
    -- Have we done the start processing
    obj.status={}
    obj.status.ready=false; -- ready to install
    obj.status.downloaded=false; -- files are here.
    obj.status.started=false; -- prestart tests have completed
    obj.status.consolidated=false; -- consolidation done
    obj.status.errors = false; -- download stage failed
    obj.status.failed = false; -- download stage failed
    obj.start_triggered=false

    obj.first_init_download=table.getn(init_downloads);
    obj.allowByteRange=0

    -- get files and features
    local files=obj.File
    local feats=obj.Feature
    table.insert(bundles,obj) -- add to bundle list.
    if obj.PlainEula ~= nil then
        obj.PlainEula._body_=string.lower(obj.PlainEula._body_)
    else
        obj.PlainEula = { _body_ = "false"}
    end


    if obj.Primary ~= nil then
        PRIMARY_MARKERS=PRIMARY_MARKERS+1;
    end
    --Check if Primary element is present
    if obj.Primary ~= nil and obj.Primary._body_ == "true" then
        obj.isPrimary=true;
        PRIMARY_COUNT=PRIMARY_COUNT+1
    end

    --Check for Continuation Tag
    if obj.Continuation ~= nil and obj.Continuation._body_ == "true" then
        obj.isContinuation=true;
    end
    for n,v in ipairs(BUNDLE_RESOURCES) do
        local skip=false;
        if obj[v] == nil or obj[v]._body_ ==nil then 
            skip=true
        elseif v == "ProductEula" then
            -- For d
            if idx == 1 and DOWNLOAD_DOT_COM  then
                skip=true
            else
            skip = (not isMht(obj[v]._body_) ) and obj.PlainEula and  obj.PlainEula._body_ == "false"
            end
            local _ok,msg=pcall(function()
                local parsed=url.parse(obj[v]._body_)
                if parsed.query ~= nil then 
                    DebugPrint(string.format("Query is %s",tostring(parsed.query)));
                    if string.find(parsed.query,"continuation=true") ~= nil then
                        DebugPrint(string.format("Bundle[%d] is a continuation",idx));
                        obj.isContinuation=true
                    end
                end
            end);
            if not _ok then
                ErrorPrint(string.format("Failed to Get Query:%s",msg));
            end


        end
        if not skip then 
            DebugPrint("Resource: " .. v .. " -> " .. obj[v]._body_);

            obj[v]._body_ = downloadOrExtract(obj[v]._body_,idx,nil,nil,
            string.format([[bundles[%d]["%s"]._body_=]],idx,v).."[[%s]]")
        end
    end
    --[[
    -- Helper function to grab the file name specified via custom parameters
    --]]
    local getExplicitFileName=function()
                for k,v in ipairs(obj.CustomParameter) do
                    if v._a_ and v._a_.Name == "FileName" then
                        return v._body_
                    end
                end
                return nil
            end
            
    --download whatevers files we need for install and offer.
    --Bundle level download and extract list.
    local bDir=PLUGINSDIR .. "\\" .. idx .. "\\"
    for n,v in ipairs(files) do 
        v._a_.Options = v._a_.Options or "";
        v.allowByteRange=0;
        v.isLuaFile=false;
        if(v._a_.Action) then
            local _,_,act,_,when  = string.find(v._a_.Action,"(%S+) (%S+) (%S+)")
            v.FileAction=string.lower(act)
            v.FileTrigger=string.lower(when)
            local  isHttp=isOnlineResource(v._a_.SourceFile)
            local targetExpr= string.format("updateFileFromCached(%d,%d,",idx,n).."[[%s]])"
            v.Online = isHttp
            local download_record=nil;
            if v.FileTrigger == "offer" or v.FileTrigger == "start" then
                v.FileName,v.DestName,download_record=downloadOrExtract(v._a_.SourceFile,idx,nil,nil,targetExpr)
                local entry=init_downloads[#init_downloads];
                if entry  and v._a_.AlternateSourceFile and v._a_.AlternateSourceFile ~= "" then
                    local  src_list={entry[1],v._a_.AlternateSourceFile};
                    entry[1]=src_list;
                end
            elseif v.FileTrigger == "installation" or v.FileTrigger == "finish" then
                local owner=v;
                if ASYNC_PREPARE then
                    owner=string.format("updateFileInfo(%d,%d,",idx,n) .. "%d,%d)"
                end
                local nameProvider=nil;
                --[[
                --Apply the <FileName> rule for bundle with a single entry.
                -- Only single file and it is for installation or finish
                --  And it is for Extract or copy 
                --]]
                if table.getn(files) == 1 and (v.FileAction == "copy" or v.FileAction == "extract") then
                    nameProvider=function(fname)
                        return getExplicitFileName()  or fname;
                    end
                    
                end
                v.FileName,v.DestName,download_record=downloadOrExtract(v._a_.SourceFile,idx,inst_downloads,owner,targetExpr,nameProvider)
                local entry=inst_downloads[#inst_downloads];
                if entry  and v._a_.AlternateSourceFile and v._a_.AlternateSourceFile ~= "" then
                    local  src_list={entry[1],v._a_.AlternateSourceFile};
                    entry[1]=src_list;
                end

            end
            if v.FileAction == "xpidirect" then
                if v._a_.Destination == "" then  
                    v._a_.Destination=getDownloadsDir()
                    v._a_.ForceCreate = true
                end
            end
            -- Files being download into the TMP folder get the inTmp flag and 
            -- Are not double copied
            -- There is no risk of them not being cleaned up so we dont have to do the double
            if string.find(v._a_.Destination,"PLUGINSDIR") ~= nil 
                or string.find(v._a_.Destination,"WORKINGDIR")~=nil then
                v.inTmp=true
            else
                v.inTmp=false
            end
            --nsis.messageBox(v._a_.Destination .. "|" .. tostring(v.inTmp))
            v.RunDir  =  bDir;
            v.isLuaFile = endswith(v._a_.SourceFile,".lua");
            v._a_.Scramble=(v._a_.Scramble and string.lower(v._a_.Scramble)) or ""
            if v._a_.Scramble == "true" then
                v.FinalFile = v.FileName
                v.FileName= bDir.. v.DestName .. ".scr"
                if download_record ~= nil then
                    updateRecordForScramble(download_record,v.FileName);
                end
            else
                -- NO need to modify file name as it already contains the Path
                -- v.FileName=bDir.. v.FileName
            end

        end
    end 
    -- nsis.messageBox("Download Lists: init=".. table.tostring(init_downloads) .. "\n"
    -- .. "install=" .. table.tostring(inst_downloads))
    if obj.ProductBinary._body_ ~= "" then
        local fname,domain=res2FileName(obj.ProductBinary._body_)
        --[[ Feature : March -27-2013
        -- For Tucows the ProductBinary goes through a redirect link which 
        -- changes the filename.
        -- Given that the system cannot get the filename without gollowing the redirect
        -- which can only be done by making a network request early.
        -- I shall allow it to be specified Via a CustomParameter if present.
        --]]
        if obj.CustomParameter then
            local newFname=getExplicitFileName();
            if newFname ~= nil then
                DebugPrintF("Using Alternate Filename:%s -> %s",fname,newFname);
                fname=newFname;
            end
        end
        -- Plug in the Domain it will be used in substitutions involving <APPURL>
        obj.ProductBinary._domain_ ="http://" .. domain
        if isOnlineResource(obj.ProductBinary._body_) then
            obj.Embedded="false"
            -- name the local file.
            obj.LocalFile = bDir .. fname
            -- Make sure we get the size of the product binary too
            local owner=obj;
            if ASYNC_PREPARE then
                owner = string.format("updateBundleInfo(%d,",idx) .. "%d,%d)";
            end
            downloadOrExtract(obj.ProductBinary._body_,idx,inst_downloads,owner,
            string.format("updateBinaryFromCache(%d,",idx) .. "[[%s]])")
        else
            obj.Embedded="true"
            -- name of the local file we will extract it into
            fname=res2FileName("file://" .. obj.ProductBinary._body_)
            obj.LocalFile = bDir .. fname
        end

        -- mark Msi's
        -- Old Code tostring(endswith(string.lower(obj.ProductBinary._body_),"msi"))
        obj.ProductBinary.msi=tostring(isMsi(obj.ProductBinary._body_)) 
        --    nsis.messageBox("OPtions are ->" .. obj.ProductBinary._a_.msioptions .. "/" .. string.len(obj.ProductBinary._a_.msioptions)
        -- .. "/" ..   string.len(obj.ProductBinary._a_.options))
        obj.RunDir=bDir 
        -- IF we are manually installing the primary
        if MANUALLY_INSTALL_PRIMARY == true and obj.isPrimary == true then
            obj.RunDir= "$INSTALLDIR";
            obj.LocalFile ="$INSTALLDIR\\" .. fname
        end
        -- Scrambled 
        -- When it is unscrambled Final File will be moved back to LocalFile
        if string.lower(obj.Scramble._body_) == "true" then
            obj.FinalFile = obj.LocalFile
            obj.LocalFile = obj.LocalFile .. ".scr"
        end
    else
        -- TODO:[Test Succes on Product with No Binary]
        -- NO binary means we will mark this as embedded so it is properly skipped over.
        obj.Embedded="true"
        obj.noBinary=true;
    end


    if idx == 1 then
        obj._willInstall_ =  1
        obj._wouldInstall_ = 1
    else
        obj._willInstall_ = 0
        obj._wouldInstall_ = -1;
    end
    --Every bundle will be shown unless told otherwise.
    obj._willDisplay_ = 1
    obj._installed_=0


    -- The last index to be downloaded to show this product
    obj.last_init_download=table.getn(init_downloads)

    if DOWNLOAD_DOT_COM then
        if idx == 1 and  obj.last_init_download == obj.first_init_download then
            obj.status.downloaded=true
        end
    end

    -- Every Bundle would install initially.
    -- For Comscore Feature#49
    -- If a Bundle has the Comscore Questionaire we need to 
    -- make a  fake bundle that will present the questionaire.
    if obj.ComScoreQuestionnaire and obj.ComScoreQuestionnaire._body_ =="true" then
        local synBundle={
            ["_parentIdx_"]=idx, -- index of the parent /dependent bundle.
            ["_willInstall_"]=0, -- Disable the installation side of this thing
            ["_synBundle_"] =1, -- indicate taht this is a place holder.
            ["_pageCreate_"] = FUNC_ADDR_COMSCORE_CREATE,
            ["_pageLeave_"] = FUNC_ADDR_COMSCORE_LEAVE
        };
        -- Copy over comscore fields.
        for n1,v1 in ipairs(COMSCORE_FIELD) do 
            synBundle[v1]=obj[v1]
        end
        -- Add this bundle to the list
        table.insert(bundles,synBundle)
        SYN_BUNDLES=SYN_BUNDLES+1;
    end

    -- Feature based accept feature.
    -- Feature Requested: Nov/17/2011
    -- This feature will allow the accept decline status of a
    -- product be controlled by the acceptance of one of its features.
    obj.isFeatureAccept=false
    for n,v in ipairs(feats) do 
        -- Minor Regularization
        if v._a_.Options == nil then
            v._a_.Options = "" 
        end
        if v._a_.Name == nil then 
            v._a_.Name = "" 
        end
        -- Store the Bundle associated with this feature
        v.bundleIndex=idx;
        DebugPrint("Checking Feature [" .. v._a_.Name .. "] -> [" .. v._a_.Options .. "]" );
        if v._a_.Options == "*FEATUREACCEPT*" then 
            obj.isFeatureAccept=true;
            v._a_.Options =""; -- Wipe out the switch
            v.isDirective=true; -- So we can hide features from users
        else
            local expression=string.match(v._a_.Options,[[%*FEATUREACCEPT%*/(.*)]])
            if expression ~= nil then
                DebugPrint("FeatureAccept Expression => ".. expression);
                v._a_.Options="";
                v.isDirective=true; -- So we can hide from the user
                --Construct a function to evaluate the variables 
                local code=[[ return function(feature)]] ..  [[return ]] .. expression .. [[;]] ..  [[end]];
                DebugPrint("Feature Expression Code =>" .. code);
                local func,msg=loadstring(code)
                if( func ~= nil) then 
                    -- Add this to he object.
                    appendFeatureAcceptClause(obj,func());
                else
                    DebugPrint("Bad Feature Expression " .. msg);
                end
            end

            -- Look in Name field.
            --[[
            -- Conditional Features
            -- Introduced: December 16/2011
            -- A <Feature> ellement with a name of the form "*IF*/...."
            -- will be considered a feature that will 
            -- only append its corresponding options to the bundle If the expression in the 
            -- "..."  evaluates to true.
            --]]
            local cond_expr=string.match(v._a_.Name,[[%*IF%*/(.*)]])

            if cond_expr ~= nil then
                local func=prepareConditionalExpression(cond_expr);
                v.isDirective=true;
                --construct a function to evaluat the variables
                if func ~= nil then 
                    v.conditionalExpr =  func
                    v.isConditionalFeature= true;
                end
            else 
                -- an <If> node may also be within a feature
                -- and have the same effect.
                local cond_expr,cond_data=getNodeConditional(v)
                if cond_expr ~= nil or cond_data ~= nil then
                    -- Not nil  in the expr or the data
                    local func=prepareConditionalExpression(cond_expr,cond_data);
                    if func ~=nil then
                        v.isDirective=true;
                        v.conditionalExpr=func;
                        v.isConditionalFeature=true;
                    end
                end
            end
        end
    end

    --[[
    -- Look for aXml Level Fearture accept
    --]]
    if obj.isFeatureAccept == false then
        local _,cond_data=getNodeConditional(obj,"AcceptIf")
        if cond_data ~= nil then
            local func=prepareConditionalExpression(nil,cond_data)
            if func ~= nil then
                appendFeatureAcceptClause(obj,func);
            end
        end

    end



end

--Helper function that appends a feature accept function to a bundle
--It will AND this function into any existing function
function appendFeatureAcceptClause(obj,func)
    local lastfunc=obj.featureAcceptFunction;
    local finalfunc=func;
    if lastfunc ~= nil then 
        -- We will and the functions together
        finalfunc = function(...)
            return lastfunc(...) and func(...);
        end
    end
    obj.featureAcceptFunction=func;
    obj.isFeatureAccept=true;


end

-- return if a bundle is synthetic
function isSynBundle(bundle)
    if bundle._synBundle_  and bundle._synBundle_ == 1 then return true end
    return false
end

--[[
-- Advanced REgistry Checks.
-- Perform registry checks for <RegistryEntry> elements. Elements allow nesting and -- each nested group will have sub elements combines.
-- <RegistyEntry [op='and' not='true'] key='<string>' [value='<>']  >
-- if 'value' is not provided the key will be checked for presence.
-- if 'key' end in a slash it will be a toplevel key.
-- Otherwise it will be a key up to the slash and the associated value of
-- the subkey named after the slash
--]]
--Return whether to show the element.
function advancedRegistryChecks(obj)
    DebugPrint(string.format("Bundle[%s] Advanced Registry Check:",obj.bundleIndex)  );
    -- No registry entry so we show this item.
    if obj.RegistryEntry == nil then return true end
    return  evalRegistryEntry(obj.RegistryEntry[1]) == 0
end

function evalRegistryEntry(entry)
    DebugPrint("evalRegistryEntry:(" .. table.tostring(entry) .. ")");
    local pass=0;
    if entry.RegistryEntry then
        local cnt=0;
        for  _,e in ipairs(entry.RegistryEntry) do 
            cnt=cnt+1
            pass =pass + evalRegistryEntry(e)
        end
        -- And operator  mean all or nothing
        if entry._a_.op ~=nil and  entry._a_.op == "and" and cnt ~= pass then
            DebugPrint("Failed And Operator " .. cnt .. "<>" .. pass);
            pass=0
        end
        if pass~=0 then pass =1 end

    else
        if entry._a_.key == nil then return 0 end
        DebugPrint("Loading Key:" .. entry._a_.key)
        local regVal=entry._a_.value;
        local found=nil;
        withRegistryValues(entry._a_.key,function(root,path,value,isKey)
            found=0; 
            DebugPrint(root .. "::".. path .. "::" .. value .. "::" .. tostring(isKey))
            if regVal == nil then 
                -- If its a key and it exists or its a value and that exists then we are
                -- good.
                if isKey and registry.EnumRegKey(root,path) ~= 0 then 
                    found=1; return;
                end
                if not isKey 
                    and registry.EnumRegStr(root,path,value) ~=0 then 
                    found =1; return;    
                end
                DebugPrint("couldnt ENUM!");
            else  -- User specified a value.
                local realVal=registry.ReadRegStr(root,path,value)
                DebugPrint("Loaded Value => " ..  tostring(realVal))
                if realVal == regVal then found=1; return end;
            end
        end)
        if found == nil then 
            pass=0 
        else
            pass =found 
        end
    end
    if entry._a_['not'] ~= nil and  entry._a_['not'] == 'true' then 
        if pass >0 then pass =0 else pass =1 end
    end
    DebugPrint("Pass is " .. tostring(pass))
    if pass >0 then return 1 else return 0 end
end


-- Bundle level registry checks  to be run after
-- we have run the start scripts.
function preStartCheck(idx)
    local obj=bundles[idx]
    if isSynBundle(obj) then return end
    advancedTests(obj);
    if obj.RegistryKey._body_ ~= "" then
        local hide=nil;
        withRegistryValues(obj.RegistryKey._body_,function(root,path,value,isKey)
            local regVal=obj.RegistryValue._body_ 
            if regVal == "" then
                if isKey then
                    -- nsis.messageBox("Enum Regi Key" ..  root .. "][" .. path)
                    hide=registry.EnumRegKey(root,path) 
                    -- nsis.messageBox("Enum Regi Key" ..  root .. "][" .. path .. "]" .. hide)
                else
                    hide=registry.EnumRegStr(root,path,value) 
                end
            end
        end);
        -- nsis.messageBox(root .. "-" .. path .. "-" .. value .. "::" .. hide);
        if hide == 1 then
            obj.trackString="hidden"
            obj._regKeySuppressed_=true;
            obj._willInstall_=0
            obj._willDisplay_=0
        end
    end
    -- Set the was suppress flag early for simple cases
    if wasSuppressed(obj) then
        obj._wasSuppressed_=1;
    else
        obj._wasSuppressed_=0;
    end


end

--
-- Perform Bundle Level Registry Checks.
-- postStartRegistryCheck(obj) -> Perform Post Start Registry Checks.
function postStartRegistryCheck(obj)
    if isSynBundle(obj) then return end
    if obj.RegistryKey._body_ ~= "" then
        local hide=nil;
        withRegistryValues(obj.RegistryKey._body_,function(root,path,value,isKey)
            local regVal=obj.RegistryValue._body_ 
            if regVal ~= "" then
                -- IF there is  a value specified in the XML
                local realVal=registry.ReadRegStr(root,path,value) 
                if realVal == nil then realVal="NIL" end
                if  regVal == realVal then
                    --nsis.messageBox(root .. "-" .. path .. "::" .. value .. "::" .. " -> " .. realVal);
                    hide=1 -- Hide bundle. 
                end
            end
        end);
        -- nsis.messageBox(root .. "-" .. path .. "-" .. value .. "::" .. hide);
        if hide == 1 then
            obj.trackString="hidden"
            obj._regKeySuppressed_ = true
            obj._willInstall_=0
            obj._willDisplay_=0
        end
    end
    -- Havent decided to hide it then we can do the advanced check
    if hide ~= 1 then 
        if not advancedRegistryChecks(obj) then 
            DebugPrint("advancedRegistryChecks() -> Failed!");
            obj.trackString="hidden"
            obj._willInstall_=0
            obj._advRegKeySuppressed_=true
            obj._willDisplay_=0
        end
    end



    if  obj.RegistryVariables and obj.RegistryVariables._body_ ~= "" then
    expandRegistryVarList(obj.RegistryVariables._body_)
    -- Split the items by semicolon and then by =
    --[[ COmmented out June 10th 2010. THe function will do a better job.
    for _,vars in ipairs(split(obj.RegistryVariables._body_,"[;]+")) do 
    -- local arrItems=split(vars,"=")
    -- nsis.messageBox(table.tostring(arrItems))
    for var_name,var_reg in string.gmatch(vars,"([^=]+)=(.*)") do 
    --   nsis.messageBox(var_name .. "=>".. var_reg)
    withRegistryValues(var_reg,function(root,path,value,isKey)
    var_name="Registry." .. var_name
    NSISVars[var_name] = registry.ReadRegStr(root,path,value)
    end)
    -- nsis.messageBox(table.tostring(NSISVars))
    end
    end
    --]]
end

end

--[[
-- Registry Checks/Variable lookups to be invoked after the bundle has been installed.
-- This is invoked and will simply expand the PostInstallRegistryVariables if 
-- any
--]]
function postCompleteRegistryCheck(obj)
    if isSynBundle(obj) then return end
    if  obj.PostInstallRegistryVariables and obj.PostInstallRegistryVariables._body_ ~= "" then
        expandRegistryVarList(obj.PostInstallRegistryVariables._body_,obj._installed_,true,"default")
    end

end

--[[
-- Load a String of registry variables in the format
-- {name}={registryspec}; into NSISVars so they can be referenced
-- in variable expansions in the format $Registry.{name}
-- {installed} => Is this bundled installed
-- {reqInst} => Do we need the bundled to be installed to load variables 
-- {defString} => String to use for missing registry keys or bundles that arent installed.
-- ]]
function expandRegistryVarList(lst,installed,reqInst,defString)
    DebugPrint("expandRegistryVarList(" .. tostring(lst) .. "," .. tostring(installed) .. "," .. tostring(reqInst) .. "," .. tostring(defString) .. ")");
    -- Split the items by semicolon and then by =
    for _,vars in ipairs(split(lst,"[;]+")) do 
        -- local arrItems=split(vars,"=")
        -- nsis.messageBox(table.tostring(arrItems))
        local var_name,var_reg,var_def
        for var_name,var_reg in string.gmatch(vars,"([^=]+)=(.*)") do 
            --   nsis.messageBox(var_name .. "=>".. var_reg)
            withRegistryValues(var_reg,function(root,path,value,isKey)
                var_name="Registry." .. var_name
                if reqInst and not installed then 
                    NSISVars[var_name]=defString
                    return
                end
                NSISVars[var_name] = registry.ReadRegStr(root,path,value)
                if NSISVars[var_name] == nil then 
                    NSISVars[var_name]=defString
                end
            end)
            DebugPrint(var_name .. "=>" ..  NSISVars[var_name])
            -- nsis.messageBox(table.tostring(NSISVars))
        end
    end
end


--[[
-- Read a Regsitry key and invoke func with the 
-- values  that are found.
-- func will be invoked with a the key ,path and value  as well as wehther the registry entry is
--  a key,
--
--]]
function withRegistryValues(regstr,func)
    local parts=split(regstr,'[\\]+');
    -- nsis.messageBox(table.tostring(parts));
    local addedVal=false
    if table.getn(parts) == 2 then 
        table.insert(parts,"") 
        addedVal=true
    end
    if table.getn(parts) <3 then
        return false;
    else
        local root = parts[1];
        local path=parts[2]
        local value= parts[table.getn(parts)]
        local isKey=string.sub(regstr,-1,-1)  == "\\"
        if table.getn(parts)>3 then
            for x=3,table.getn(parts)-1 do
                path=path .. "\\" .. parts[x]
            end
        end
        if isKey and not addedVal then
            path=path .. "\\" .. value
            value=""
        end
        func(root,path,value,isKey);
        return true;
    end

end

--Temporary file nameing stuff.
TEMPIDX=1

--Given a resource name provide the name of a local file to go with it 
-- resName: string inurl format 
function res2FileName(resName)
    local parsed=url.parse(resName)
    local parts =url.parse_path(parsed.path)
    if table.getn(parts) >0 then
        return parts[table.getn(parts)],parsed.host
    else
        TEMPIDX=TEMPIDX+1;
        local suffix=""
        if isMht(resName) then 
            suffix=".mht"
        end
        return "File" .. TEMPIDX .. suffix,parsed.host
    end
end

--Is Online resource
-- Returns whether something is a weburl
function isOnlineResource(resName)
    local isHttp,_ = resName.find(resName,"http://")
    local isFtp,_  = resName.find(resName,"ftp://");
    return isHttp == 1  or isFtp == 1
end


--Given a download record adjust it to account for scramble
function updateRecordForScramble(rec,filename)
    rec[2]=filename
end

-- Add a resource to download list or extraction list depending name/target
-- resName : resource string
-- idx: bundle index.
-- {owner} => the object this file belongs to.  it wil have FileSize updated with the file size.
-- {targetExpr} => the string expression that can be used to update this value
-- returns {localfile},{destname},{download_record}
-- {localfile} => is in PLUGINSDIR
-- {destname} => the filename part of  localfile
function downloadOrExtract(resName,idx,targetList,owner,targetExpr,nameProvider) 
    if resName =="" then return "" end -- Blanks are skipped.
    targetList=targetList or init_downloads -- initial downloads by default
    local localFile= PLUGINSDIR .. "\\" .. idx .. "\\"
    local isWeb,_= isOnlineResource(resName)
    local destName="";
    -- Web resource.
    local rec=nil
    if  isWeb == true then
        destName=res2FileName(resName)
        if nameProvider ~= nil then  -- if a name provider is passed use it
            destName=nameProvider(destName);
        end
        localFile=localFile .. destName
        rec={resName,localFile,owner or nil,targetExpr or nil,idx}
        localFile=localFile;-- set to File Protocol
        table.insert(targetList,rec)
    else 
        destName=res2FileName("file://" .. resName)
        -- Fake a url and parse the last segment.
        localFile=resName -- localFile .. res2FileName("file://" .. resName)
        rec={resName,localFile}
        table.insert(init_extract,rec)
    end
    DebugPrint("DownloadOrExtract:" .. resName .. " -> " ..  localFile .. " / " ..  destName)
    return localFile,destName,rec;

end

function downloadListPreFilter(inlst)
    local lst={};
    local _error=false
    for k,v in ipairs(inlst) do
        local good,msg=pcall(function()
            if #v  >= 5 and v[5] ~= nil then 
                local b=bundles[v[5]]

                if b and  b._willDisplay_ == 0  and not hasConsolidations(b) then
                    DebugPrint(string.format("Dropping:%s",v[1]))
                    -- Drop the 
                    v[2]=nil;
                    --v.dropped=true;
                end
                table.insert(lst,v)
            else
                table.insert(lst,v)
            end
        end)
        if not good  then 
            ErrorPrint("downloadListPreFilter: %s,(record=%s)",msg,table.tostring(v))
            return inlst;
        end
    end

    return lst;
end

precalcInstallProgress,incPreCalcInstallProgress = (function()
    local toProcess={};
    local currentStep=0;
    local totalSize=0;
    local missingSizes=0;
    local nextStep =function()
        currentStep=currentStep+1;
        return currentStep;
    end
    local calcBundle=function(b)
        if b._willInstall_ ~= 1 then return end;
        if b.InstallStepIdx ~= nil then return end;-- Already calculcated
        local bundleBytes=0;
        for _,fle in ipairs(b.File) do 
            if fle.FileTrigger == "installation"  then
                fle.InstallStepIdx=nextStep()
                addInstallStepIdx(fle)
                if fle.FileSize~= nil then
                    totalSize=totalSize + fle.FileSize
                    bundleBytes = bundleBytes +  fle.FileSize
                else
                    DebugPrint(string.format("Bundle[%d] Missing Size for '%s'",b.bundleIndex,fle._a_.SourceFile))
                    missingSizes=missingSizes+1;
                end
            end
        end
        if b.ProductBinary and b.ProductBinary._body_ ~= "" then
            b.InstallStepIdx=nextStep();
            addInstallStepIdx(b)
            if b.FileSize ~= nil then
                totalSize=totalSize + b.FileSize
                bundleBytes = bundleBytes + b.FileSize
            else
                DebugPrint(string.format("Bundle[%d] Missing Size for '%s'",b.bundleIndex,
                b.ProductBinary._body_))
                missingSizes=missingSizes+1;
            end
        end
        -- Set the Number Of Bytes in the Bundle.
        b.TotalBundleBytes=bundleBytes;
    end
    local incCalc=calcBundle;
    local fullCalc= function()
        -- For each thing we may download we will compute a 
        -- 'InstallStepIdx' indicating the download order.
        for _,app in ipairs(bundles) do 
            if app.isPrimary == false or getInstallInOrder() then 
                calcBundle(app); 
            end
        end
        for _,app in ipairs(bundles) do 
            if app.isPrimary == true  and not getInstallInOrder() then
                calcBundle(app);
            end
        end
        appN.TotalInstallSteps=currentStep;
        if missingSizes==0 then
            appN.TotalDownloadSize = totalSize;
        end
    DebugPrint(string.format("PreCalcInstallProgress: Total=%s,missing=%d",appN.TotalDownloadSize or "-",missingSizes))
    end
    return fullCalc,incCalc
end)()

-- Does this installer use custom dialogs
function isCustomDialog()
    return string.lower(appN.CustomDialogSize) == 'true';
end

--dialog  siziing information
function pushDialogDims()
    nsis.push(appN.DialogWidth._body_ ,appN.DialogHeight._body_)
    --nsis.messageBox (appN.DialogWidth._body_ .. " X " .. appN.DialogHeight._body_)
end
--Push a top level application variable onto the stack
function pushAppVar(nme)
    if appN[nme] == nil then nsis.push("");return; end
    nsis.push(appN[nme]._body_)
end

--Get a Bundle Variable
function pushBundleVar(nme,idx)
    if nil == bundles[idx] or nil == bundles[idx][nme]
        or bundles[idx][nme]._body_ == nil then  
        nsis.push("");
        return;
    end
    nsis.push(bundles[idx][nme]._body_)
end

function alreadyInstalled()
end

function getBrandingText()
end

-- Set the install status and Tracking string for a product.
function setProdState(idx,state,tracking,from_user,decline_combos)
    DebugPrintF("Prod State for %d -> %d -> %s (%s)",
    idx,state,tostring(tracking),tostring(decline_combos))
    local b=bundles[idx]
    local e,msg=pcall(function()
        local inState=state+0;
        local inTracking=tracking
        -- Some times we run the installer even if
        -- its a decline  for tracking purposes
        local forceInstall =false;

        -- If the feature is an accept then we can adjust the prod state
        -- to simply swap out the  inputs
        if b.isConsolidated == true or b.hasConsolidated ==true then 
            -- Feature accept to only be activited
            -- in he case of Consolidated Bundles.
            if b.isFeatureAccept then
                local accept=false;
                if b.featureAcceptFunction ~= nil then 
                    local features={};
                    for k,v in ipairs(b.Feature) do 
                        -- Make a  map fo the true or false state of all the features
                        if v._a_.id ~= nil and v.isDirective ~= true then 
                            local checked=v._a_.InitialState == "checked";
                            features[v._a_.id]= checked;
                            if checked then forceInstall=true end;
                        end
                    end
                    DebugPrint("Running Function Args" .. table.tostring(features))
                    local e,msg=pcall(function()
                        local bndle={};
                        features['bundle_is_consolidated'] = b.isConsolidated == true;
                        accept=b.featureAcceptFunction(features);
                    end);
                    if not e then 
                        DebugPrint("Feature Accept Function Error:" .. msg);
                    end
                else
                    -- Fea 
                    for k,v in ipairs(b.Feature) do
                        if v.isDirective ~= true and v._a_.InitialState  ==  "checked" then
                            DebugPrint("Feature Named " .. v._a_.Name .. " => Accept")
                            accept=true;
                            break;
                        end
                    end
                end
                --[[
                -- Accept and decline bassed on the feature state.
                --]]
                if accept then 
                    state=1;
                    tracking="accept";
                else
                    if forceInstall then 
                        state =1;
                    else 
                        state=0
                    end
                    tracking="decline";
                end
                DebugPrint("[Updated/FeatureAccept]Prod State for "..idx.." -> " .. state ..","..tracking)
            end
            if b.consolidateFeature ~= nil then
                -- If there is a consolidate feature we will ignore the 
                if b.consolidateFeature._a_.InitialState == "checked"
                    and (state+0) == 1 then
                    if b.isFeatureAccept then
                        -- FeatureAccept used on a Product that is the result of a
                        -- Consolidation as well
                        -- Dont touch the tracking  either.
                    else
                        state=1
                        tracking="accept"
                    end
                else
                    state=0
                    tracking="decline"
                end
            end
        end

        if b._wasSuppressed_ == 0 then 
            --only accept and install the lead 
            --product if it wasnt suppressed
            b._willInstall_= state+0
            b.state=state+0
            b.trackString=tracking

            if b._willInstall_ == 1 and EAGER_INSTALL then
                if not b.isPrimary or getInstallInOrder() then  
                    DebugPrintF("Bundle[%d]: Eagerly Starting Install",b.bundleIndex);
                    --For an eager install bundle we kick off the installation
                    nsis.evalInState("+asyncinstall", string.format("startInstall(%d)",b.bundleIndex))
                end
            end
        else
            DebugPrint("Skipping as Product was Suppressed!");
        end
        if b.consolidated==nil then return end;
        for _,cons  in ipairs(b.consolidated) do
            -- If the linked bundle was suppressed then we need to skip it.
            if bundles[cons.idx]._wasSuppressed_ ~= 1 then
                -- We have a consolidated feature.
                DebugPrint("Consolidated(inState=" ..inState .. ")=>" .. table.tostring(cons)) 
                if cons.feature._a_.InitialState == "checked"
                    and inState == 1 then
                    -- Checked means bundle is accepted.
                    -- If an only if the top level product is acccept as well
                    if decline_combos  then
                        setProdState(cons.idx,0,"decline")
                    else
                        setProdState(cons.idx,1,"accept")
                    end
                else
                    setProdState(cons.idx,0,"decline");
                end
            end
        end
    end)
    if not e then
        DebugPrint(string.format("Error in SetProdState(%s)",msg))
    end
    DebugPrint("Final Prod State for ".. idx .." -> " .. b._willInstall_ ..",".. b.trackString)

end
function getProdState(idx)
    return bundles[idx]._willInstall_
end

--Whether a bundle can be declined"
--pPrimary cannot be declined
function canDecline(idx)
    if idx~=1 then return 1 end
    return 0
end

function displayBundle(idx)
    if bundles[idx] == nil then return 0 end
    if isSynBundle(bundles[idx]) then
        return bundles[bundles[idx]._parentIdx_]._willInstall_
    end
    -- nsis.messageBox("can display "..idx .. " " .. table.tostring(bundles[idx]))
    return bundles[idx]._willDisplay_
end

-- Calculate the amount of space to leave at the bottom for
-- a  BrandingLink 0 unless this has a below eula branding URL.
function bundleLinkHeight(idx)
    local b=bundles[idx]
    if b.LinkBelowEula and  string.lower(b.LinkBelowEula._body_) == "true" then
        return LinkRowHeight + InterFeaturePadding   
    end
    return 0
end

--Get the state of feature x in bundle
function bundleFeatureState(idx,fIdx)
    return bundles[idx].Feature[fIdx].state
end

-- has Offer actions
function hasOfferActions(bundle)
   if isSynBundle(bundle) then return false; end  
   for fIdx,thefile in ipairs(bundle.File) do
       if thefile.FileTrigger == "offer" then
           return true
       end
   end
   return false;
end

--Validation to ensure that we only perform actions fro the right bundles .
--installation and finish triggers only work for bundles that are going to be installed.
function shouldDoFileTriggers(idx,trg,current)
    trg=string.lower(trg)
    current=tonumber(current)
    local prefix=string.format("shouldDoFileTriggers(%d,%s,%s)->",idx,trg,tostring(current))
    if isSynBundle(bundles[idx]) then DebugPrint(prefix.."=>false"); return false end
    if  trg == "finish" or  trg =="installation"  then
        --DebugPrint(prefix .. table.tostring(bundles[idx]) )
        if bundles[idx]._willInstall_ == 0 then DebugPrint(prefix.."false");return "false" end
        if trg =="installation" then 
            -- For a bundle to get to installed! we did the free file thing.
            if bundles[idx]._installed_ == 1 then DebugPrint(prefix.."=>false");return false end
            if bundles[idx] ~= CurrentBundle and bundles[idx].bundleIndex ~=current  then
                DebugPrint(prefix.."=>false");
                return false 
            end
        end
    end
    if current and trg== "offer" then
        if current ~= idx then DebugPrint(prefix.."=>false");return "false" end
    end
    if trg == "start" then
        if bundles[idx].start_triggered then 
            return false;
        else
            if bundles[idx].status.downloaded == false then 
                DebugPrint(prefix.."=>false")
                if ASYNC_PREPARE then 
                    return "break";
                end
                return false;
            end
        end
    end
    DebugPrint(prefix.."=>true");
    return "true";
end

--Error Trac
function errorTrack(message)
    local good, errorUrl=pcall(function() 
        return expandNsisVars(appN.ErrorUrl._body_,1) 
    end)
    if not good  then
        ErrorPrint("No Error Tracking:%s",errorUrl);
        return
    end
    message=message or "";
    local errorData={Delta=reltime(),XmlDelta=initXmlTime,FileDelta=initFileTime};
    message=string.format("%s\n%s",message,json.encode(errorData));
    local postBody=string.format("error=%s" ,url.escape(message or ""))
    
    pcall(function()
        -- Post Hit for a tracking request.
        http.request{url=errorUrl,
        proxy = _Downloads.proxyForUrl(trackStr),
        method = "POST",
        headers =  {
            ["Content-Length"] = string.len(postBody),
            ["Content-Type"] = "application/x-www-form-urlencoded"
        },
        source=ltn12.source.string(postBody)
    }
    end)

end
local _pendingErrorMessage=nil;
function setPendingErrorTrack(msg)
    _pendingErrorMessage=msg;
end

--[[
-- Process Pending Error Tracking
--]]
function processPendingErrorTrack()
    if _pendingErrorMessage  ~= nil then
        errorTrack(_pendingErrorMessage);
        _pendingErrorMessage=nil;
    end
end


-- Init Xml and File flags
local initXmlTime=nil;
local initFileTime=nil;

function setXmlInitTime()
    initXmlTime=reltime();
end
function setFileInitTime()
    initFileTime=reltime()
end

--Tracking hit
--[[
--${IfExpr}  "appN.TrackingUrl._body_ != ''"
Custominetc::get /NOUNLOAD /SILENT "[%root.TrackingUrl.content%]Installer=[%root.InstallerCode%]&Product=[%ProdNames%]&Action=[%ActionList%]" "$PLUGINSDIR\tracking"   /END
${EndIfExpr}
-- Code makes a request to tracking service.
]]
local doneTrack=false;
function doTrackingHit(isCancel)
    if doneTrack then return end
    local trackStr=appN.TrackingUrl._body_;
    if trackStr == "" then return end
    local isPost=true;
    local numInstalls=0;
    -- Feature #58 : Tracking should include post install registry variables.
    trackStr=expandNsisVars(trackStr,1)
    local havQ,_=string.find(trackStr,"%?")
    local prefix="";
    if not havQ then
        --Appending ? for query string.
        prefix="?"
    else
        prefix="&"
    end

    local ensurePrefix=function()
        if prefix ~= "" then 
            trackStr=trackStr .. prefix;
            prefix="";
        else
            trackStr=trackStr .. "&";
        end
    end
    local postBody= "Installer=" .. appN.InstallerCode._body_;
    if isPost then
        DebugPrint("Tracking will be POST request");
        postBody=postBody .. "Installer=".. url.escape(appN.InstallerCode._body_)
        local ProdNames,Actions,ProdIds,_numInstalls = generateTrackInfo()
        numInstalls=_numInstalls
        postBody = postBody .. "&Product=" .. url.escape(ProdNames) .. "&Action=" .. url.escape(Actions)
        if ProdIds ~= nil then 
            postBody =postBody .. "&ProductId=" .. url.escape(ProdIds);
        end
    else
        ensurePrefix();
        trackStr=trackStr .. "Installer=".. appN.InstallerCode._body_
        local ProdNames,Actions,ProdIds,numInstalls = generateTrackInfo()
        numInstalls=_numInstalls
        ensurePrefix();
        trackStr = trackStr .. "Product=" .. ProdNames .. "&Action=" .. Actions
        if ProdIds ~= nil then 
            ensurePrefix();
            trackStr =trackStr .. "ProductId=" .. ProdIds;
        end
    end
    -- For cancels add an extra parameters
    if isCancel then
        ensurePrefix()
        trackStr=trackStr .. "cancel=1";
    end
    if WAS_SKIP_ALL  then
        ensurePrefix()
        trackStr=trackStr .. "skipAll=1"
        if SKIP_ALL_SLOT then
            ensurePrefix();
            trackStr = trackStr .. string.format("skipAllSlot=%s",tostring(SKIP_ALL_SLOT))
        end
    end
    pcall(function()
        ensurePrefix()
        trackStr=trackStr .. "numInstalls=" .. numInstalls
    end)
    ensurePrefix()
    local isPriv=environment_options['windows'].is_elevated;
    trackStr=trackStr .. "RunningElevated=" ..tostring(isPriv)
    -- Make sure to track how long since we started this is going out.
    ensurePrefix()
    trackStr=string.format("%sTimeDelta=%s",trackStr,reltime());
    if(initXmlTime ~= nil) then
        ensurePrefix();
        trackStr = string.format("%sInitXmlDelta=%s",trackStr,initXmlTime);
    end
    if initFileTime ~= nil then
        ensurePrefix();
        trackStr = string.format("%sInitFileDelta=%s",trackStr,initFileTime);
    end


    DebugPrint("Tracking -> " .. trackStr);
    if(isPost) then
        -- Post Hit for a tracking request.
        http.request{url=trackStr,
        proxy = _Downloads.proxyForUrl(trackStr),
        method = "POST",
        headers =  {
            ["Content-Length"] = string.len(postBody),
            ["Content-Type"] = "application/x-www-form-urlencoded"
        },
        source=ltn12.source.string(postBody)
    }
else
    -- Web Hit with Tracking Information
    http.request{url=trackStr,
    proxy=_Downloads.proxyForUrl(trackStr)}
end
doneTrack=true -- Flag that tracking is done .
end

-- Feature: ThankYouTargetBrowser
-- Allow the targetBrowser = "IE" to be specified in the ThankYouUrl to ensure that 
-- it is opened in internet explorer.
-- THis will honor an <If> child node or an "if" attribute.
-- In both cases errors will be treated as true
function openThankYouInIE()
    local thanks=appN.ThankYouUrl._a_;
    if thanks == nil or thanks.targetBrowser == nil then return false end
    if string.lower(thanks.targetBrowser) =="ie" then 
        local cond,sCond = getNodeConditional(appN.ThankYouUrl);
        if cond == nil  and sCond == nil then return true; end
        DebugPrint("ThankYouUrl(IE) Conditional Expression => " .. tostring(cond) .. "/" .. table.tostring(sCond));
        local func =prepareConditionalExpression(cond,sCond);
        if func == nil then  return true end -- For this we will default to true
        local ret,sts,msg=evalConditional(func,{});
        if not sts then 
            DebugPrint("ThankYouUrl(IE) Conditional Error:" .. msg);
            ret=true
        end
        return ret;
    end
    return false;
end

--[[
-- Get the Raw Thankyou Url COnsidering
-- conditions and such in the process
--]]
function getRawThankYouUrl()
    local thanks=appN.ThankYouUrl._body_;
    if appN.ThankYou == nil or table.getn(appN.ThankYou) == 0 then
        return thanks;
    end
    for _,entry in ipairs(appN.ThankYou) do
        if entry._a_ and entry._a_.url ~= nil then
            local cond,sCond = getNodeConditional(entry);
            if cond == nil and sCond == nil then 
                return entry._a_.url 
            end
            DebugPrint("<ThankYou> conditional expression => " .. tostring(cond) .. "/" .. tostring(sCond));
            local func =  prepareConditionalExpression(cond,sCond);
            if func ~= nil then 
                local ret,sts,msg = evalConditional(func,{});
                if not sts then 
                    DebugPrint("<ThankYou> conditional error:" .. msg);
                end
                if ret then 
                    return entry._a_.url;
                end
            end
        end
    end

    return "";
end

local doneThanks=false;
function doThanks()
    if doneThanks then return end;
    local thanksurl=getThankYouUrl()
    if thanksurl ~= nil and thanksurl ~= "" then
        if openThankYouInIE() then
            win32.ShellExecute("","iexplore.exe",thanksurl,nil,nil);
        else
            win32.ShellExecute("open",thanksurl,nil,nil,nil)
        end
    end
    doneThanks=true;
end

--[[
-- Get InstallInOrder   
--]]
function getInstallInOrder()
    -- Install in order for download.com test installer.
    -- this technically also has multiprogress
    if  INSTALLS_AT_END and DOWNLOAD_DOT_COM then
        -- For download.com 
        return true;
    end
    if appN.InstallInOrder ~= nil  and appN.InstallInOrder._body_ == "true" then 
        return true
    end
    return false;
end

function getSingleProgressBar()
    if appN.ConsolidateProgress ~= nil and appN.ConsolidateProgress._body_ == "true" then
        return true
    end
    return false
end


function getShortcutName()
    if appN.InstallShortcut and appN.InstallShortcut._body_ then
        return appN.InstallShortcut._body_
    end
    local _name=nil
    if DOWNLOAD_DOT_COM then
        pcall(function()
            if FIRST_BUNDLE then
                _name=bundles[FIRST_BUNDLE].ProductName._body_
            end
        end)
    end
    if _name ~= nil then
        return "Install " .. _name;
    end
    if appN.DisplayName and appN.DisplayName._body_ then
        return "Install " .. appN.DisplayName._body_
    end
    return nil;
end



--[[
-- Get the Thankyou Url
--]]
function getThankYouUrl()
    local thanks=getRawThankYouUrl();
    if thanks== "" then return "" end
    -- feature #58 - Post Install REgistry Variables should be expanded in the thank you expression.
    thanks=expandNsisVars(thanks,1)
    local havQ,_=string.find(thanks,"%?")
    if not havQ then
        --Appending ? for query string.
        thanks=thanks .. "?"
    else
        thanks=thanks .. "&"
    end
    thanks=thanks .. "Installer=" .. appN.InstallerCode._body_
    local ProdNames,Actions,ProdIds,numInstalls = generateTrackInfo(true)
    thanks = thanks .. "&Product=" .. ProdNames .. "&Action=" .. Actions
    if(ProdIds) then
        thanks = thanks .."&ProductId=" .. ProdIds
    end
    -- Feature:ThankYouUrlOptions.
    -- At a bundle level a list of parameters ThankYouUrlOptions 
    -- can be set. This Feature will expand out the contents of that
    -- variable and append them to the ThankYouUrl
    -- This is done per bundle
    for k,v in ipairs(bundles) do
        --Not Synthetic and Installed
        if not isSynBundle(v) and v._installed_ == 1 then 
            if v.ThankYouUrlOptions and v.ThankYouUrlOptions._body_ 
                and v.ThankYouUrlOptions._body_ ~= "" then 
                local opts=expandNsisVars(v.ThankYouUrlOptions._body_,k)
                thanks=thanks .. "&" .. opts
            end
        end
    end
    return thanks 
end

--Generate the shortcode 
function genShortCode(text)
    return text.gsub(text,"[^%w]","_")
end

-- Generate the Tracking String.
function generateTrackInfo(noHidden)
    local ProdNames=""
    local Actions=""
    local ProdIds=""
    local numInstalls=0;
    noHidden=noHidden or false;
    for k,v in ipairs(bundles) do 
        repeat 
            if isSynBundle(v) then 
                break;
            end
            --[[
            --If the bundel is hidden  dont track (requested by armando Jan 20th 2012 for the Kitara)
            --]]
            if noHidden and  v.trackString == "hidden" then
                break;
            end
            if k ~= 1 then 
                ProdNames = ProdNames .. "||"
                Actions = Actions .. "||"
                if(ProdIds ~= nil)  then 
                    ProdIds = ProdIds .. "||"
                end
            end
            Actions = Actions .. v.trackString
            ProdNames= ProdNames .. genShortCode(v.ProductName._body_)
            if ProdIds~= nil then
                if v.ProductId == nil or  v.ProductId._body_ == nil then
                    ProdIds=nil;
                else
                    ProdIds =  ProdIds .. v.ProductId._body_;
                end
            end

            if v._installed_ == 1 then
                numInstalls=numInstalls+1;
            end
        until  true
    end
    return ProdNames,Actions,ProdIds,numInstalls
end

function evalFeatureOptions(bundle) 
    local featureString="";
    -- This will hold the values of the non directive features.
    local features={}
    --Gather the values of all the non conditional features.
    for k,v in ipairs(bundle.Feature) do
        if v.bundleIndex == bundle.bundleIndex  then
            if  v.isConditionalFeature == nil then
                if v._a_.id ~=nil then
                    local checked=v._a_.InitialState == "checked";
                    features[v._a_.id] = checked;
                end
            end
        end
    end

    DebugPrint("Running Evaluating Conditional with features" .. table.tostring(features))
    for k,v in ipairs(bundle.Feature) do
        if v.bundleIndex == bundle.bundleIndex then 
            if v.isConditionalFeature == true and v.conditionalExpr ~=nil then 
                local addFeature=false;
                local e ,msg = pcall(function()
                    addFeature = v.conditionalExpr(features,environment_options['windows'],
                    environment_options['browser'],
                    environment_options['custom']);
                end);
                if not e then 
                    ErrorPrint("Conditional Expression Error:%s", msg);
                else
                    -- Add the feature the 
                    if addFeature then
                        featureString = featureString .. " " ..  v._a_.Options
                    end
                end

            else
                if v._a_.InitialState == "checked" then 
                    featureString =featureString .. " " .. v._a_.Options
                end
            end
        end
    end
    bundle._featureOptions_=featureString
    DebugPrint("Feature Options -> " .. featureString);
    return featureString
end


--Setting  up the User agent for the lua side of things.
function setGitVersion(version)
    GIT_VERSION=version;
    http.USERAGENT="Tightrope Bundle Manager(ref=[" .. GIT_VERSION .. "])";
end

--[[
-- Update the browser user agent string.
--]]
function updateUserAgent(productName)
    --Tread lightly
    pcall(function()
        local win=environment_options.windows;
        local uaString=productName .. "(ref=[" .. GIT_VERSION .."];" ..
        "windows=" .. tostring(win.major_version) .. "." ..
        tostring(win.minor_version) .. ";uac=" .. tostring(win.uac_enabled ) .. 
        ";elevated=" .. tostring(win.is_elevated) .. 
        ";dotnet=" .. tostring(win.dotnet_version) .. 
        ";startTime=" ..  initialtime() .. ")"
        http.USERAGENT=uaString;
    end);
    return http.USERAGENT
end


-- Add environment variable
-- [[
--
-- ]]
function addEnvVar(section,name,value)
    environment_options[section][name]=value;
    --For Custom Sections we will add variables into NSISVARS
    if section == "custom" then
        NSISVars[string.format("custom.%s",name)]=value;
    end
end

function hasVariation(name) 
    local cust=environment_options['custom']
    if cust['variation'] == nil then return false; end
    -- Special Case for SkipAll
    if name == 'skip-all' then 
        if appN.SkipAll ~= nil and appN.SkipAll._body_ ~= nil then 
            if appN.SkipAll._body_ == "true" then 
                return true;
            end
        end
    end
    return cust['variation']  ==  name;
end

local WIN_VERSION_TABLE = {
    ["5"] = {
        ["0"] = "2000",
        ["1"] = "xp",
        ["2"] = "2003"
    },
    ["6"] = {
        ["0"] = "vista",
        ["1"] = "7",
    }
};
-- Name the windows version.
-- [[
-- ]]
function nameWindowsVersion()
    local win=environment_options.windows;
    local major_table=WIN_VERSION_TABLE[win.major_version]    
    if major_table == nil then return end;
    local minor_table =major_table[win.minor_version]
    if minor_table == nil then return end;
    win.name=minor_table
    win.version_name= minor_table;
end

function expandVersion(str)
    local ret={major_version = 0,minor_version=0};
    local parts=split(str,"[\. ]+");
    local idx=0;
    for idx,val in ipairs(parts) do
        local num=tonumber(val);
        if num ~= nil then 
            if idx == 1 then ret.major_version=num; end
            if idx == 2 then ret.minor_version=num; end
        end
        if idx > 2 then break end;
    end

    return ret;
end

--[[
--Finalize the environment setup 
--]]
function finalizeEnvironment()
    -- Name the windows version
    nameWindowsVersion();
    local browser=environment_options.browser;
    -- Helper variables for default browser;
    browser.ie=expandVersion(browser.ie_version_string);
    browser.ff=expandVersion(browser.ff_version_string);
    browser.chrome=expandVersion(browser.chrome_version_string);
    browser.ie.is_default = (browser.default_browser == "IE"  )
    browser.ff.is_default = (browser.default_browser == "FF"  )
    browser.chrome.is_default= (browser.default_browser == "Chrome"  )

    browser.default_contains=function(x)
        return string.find(browser.default_exe,x) ~= nil;
    end

end


function getUnsupportedIEMessage()
    return appN.UnsupportedIEMessage._body_ 
end

--[[<XML>
--<UnsupportedBundleMessage>{string}</UnsupportedBundleMessage>
-- Message to be shown when a Installation can no tproceed
-- because there are no workable primary products that  can be installed.
--]]
function getUnsupportedBundleMessage()
    return appN.UnsupportedBundleMessage._body_ 
end

--[[<XML>
-- <PrimaryFailBundleMessage>{string}</PrimaryFailBundleMessage>
-- Message to be shown when all the primary products have errors 
-- downloading dependencies
--]]
function getPrimaryFailBundleMessage()
    if appN.PrimaryFailBundleMessage then 
        return appN.PrimaryFailBundleMessage._body_ or FAILED_DOWNLOAD_PRODUCT_DEP
    end
    return FAILED_DOWNLOAD_PRODUCT_DEP
end

--[[
-- Loading Screen Delay in milliseconds.
-- It is specified in the Xml in seconds
--]]
function getLoadingScreenDelay()
    local loadingTime=1.000 
    pcall(function()
        loadingTime=tonumber(appN.MinLoadingTime._body_);
    end);
    return loadingTime*1000;
end

--[[<XML>
-- <MinLoadingTime>XXX.XXX</MinLoadingTime>
-- Top Level xml element specifying the minimum amount of time 
-- the Loading screen should be presented.
--]]


-- Given an XML node get the attribute "if"
-- or the subtending <If> element associated with it and use its body
-- {altTag} -> An alternate xml tag name for the conditional node.
-- return -> <String>,<Table>
function getNodeConditional(xmldata,altTag)
    local ifelt=xmldata[altTag or 'If']
    if not altTag and  ifelt == nil then
        -- THere are attributes look for if
        if xmldata._a_ ~= nil then return xmldata._a_['if'],nil; end
        return nil,nil
    end
    return nil,ifelt
    --[[if ifelt[1] ~= nil then ifelt = ifelt[1] end
    if ifelt._body_ ~= nil then return ifelt._body_ end
    ]]--
end

--Evalueate a conditional expression  in the context of 
--a speciic feature table and the environment
--return retvalue,status,msg|result
function evalConditional(func,features,bundleIndex)
    local ret=false;
    local e,msg=pcall(function()
        ret =  func({},environment_options['windows'],
        environment_options['browser'],
        environment_options['custom'],bundleIndex or nil)
    end);
    return ret,e,msg;

end

--[[
-- Given a Dotted Expression from root
-- expand it out and evaluate it.
-- returns nil in the event there is a roadblock along the way.
--]]
function evalPropertyAccessor(root,expr)
    local parts=split(expr,'[\.]+');
    local retval=root;
    local evalSeq="";
    for _,v in ipairs(parts) do
        evalSeq = evalSeq  .. v .. " -> "
        if retval == nil then  
            ErrorPrint("evalPropertyAccessor:" .. evalSeq .. " => ??");
            return nil;
        end
        retval=retval[v]
    end 
    DebugPrint("evalPropertyAccessor:" .. evalSeq .. " => " .. tostring(retval))
    return retval;
end

--[[
-- Process an If Condition
-- This is recursive and handles the following clause types.
-- <And>
-- <Or>
-- <Not>
-- <Env>
-- <Feature>
-- <RegistryEntry>
-- <FileExists path="XXX"> - True if a specifi path exists
--]]
--This is the list of tags that contain clauses
local NESTED_COND_TAGS={['And']=1,['Or']=1,['Not']=1,['If']=1,['AcceptIf']=1}
local num_args=function(func)
    return function(a,b)
        return func(a+0,b+0);
    end

end
--[[Code to Handle Conditional ]]
local OP_HANDLERS={
    ["="] = function(prop,val)
        --DebugPrint(tostring(prop) ..  " == " .. tostring(val))
        return tostring(prop) == tostring(val);
    end,
    [">"] = num_args( function(prop,val)
        return prop > val;
    end),
    ["<"] = num_args(function(prop,val)
        return prop < val;
    end),
    [">="] = num_args(function(prop,val)
        return prop >= val;
    end),
    ["<="] = num_args(function(prop,val)
        return prop <= val;
    end),
    ["<>"] = function(prop,val)
        return tostring(prop) ~= tostring(val)
    end

}

--Conditional Clause handlers.
local CLAUSE_HANDLERS={
    -- Feature Lookup
    ["Feature"]=function(node,args)
        local name=node._a_.name;
        return args.feature[name] == true
    end,
    --Environtment Lookup
    ["Env"] = function(node,args)
        local prop=node._a_.property;
        if prop == nil then 
            ErrorPrint("Missing Property in <Env> clause");
            return false
        end
        local value =node._a_.value
        --[[
        -- if the value is missing then make it nil
        if value == "nil" then value =nil end
        if value == "true" then value = true end
        if value == "false" then value = false end;
        ]]--
        local op = node._a_.op or nil

        if op == nil then 
            return evalPropertyAccessor(args,prop) == true;
        end

        local handler=OP_HANDLERS[op]
        if handler ==nil then
            ErrorPrint("Unsupported operator " .. tostring(op) .. " in <Env> clause");
            return false;
        end
        local e,msg=pcall(function()
            return handler(evalPropertyAccessor(args,prop),value)
        end)
        if not e then 
            ErrorPrint("Error evaluating <Env property='" .. prop 
            .. "' op='" .. op .. "' value='" ..  value .. "' />:" ..  msg);
            return false;
        end
        return msg;
    end,
    --REgistry Entry 
    ["RegistryEntry"] = function(node,args)
        -- We will remove the not node as the caller will be handling the not.
        if node._a_["not"] ~= nil then
            node._a_["not"]=nil;
        end
        return evalRegistryEntry(node) == 1;
    end,
    ["FileExists"] = function(node,args)
        if node._a_['path'] ~= nil then 
            -- If there is a non Nil path then  check if it exists
            local real_path=expandNsisVars(node._a_['path'],args.bundleIndex);
            local is_dir=node._a_['isDirectory'];
            if not  fs.FileExists(real_path) then return false; end -- File doesn exist then fail 
            -- File Exists
            if is_dir ~= nil then 
                local real_dir=fs.IsDirectory(real_path);
                if is_dir == "true" then return real_dir; end  --if exist and is_dir is not true then good
                return  not real_dir -- if is_dir ==false
            else
                return true;
            end
        end
        return false;
        -- Check if a file exists
    end

}

--[[
--Process conditional node {node}
--in the context of features {feature},{windows},{browser},{custom},{bundleIndex}
--{node} is a single xml node in the LuaXML format
-- *OR* the Object format.
--
--]]
function processIfCond(node,feature,windows,browser,custom,bundleIndex) 
    local args={["feature"]=feature,["windows"]=windows,
    ["browser"]=browser,["custom"]=custom,["bundleIndex"]=bundleIndex}
    DebugPrint(table.tostring(args))
    local isNot=(node[0] == "Not") or (node._tag_ == "Not") or ((node._a_ and node._a_['not']) or node['not']) == "true";
    local e,ret=pcall(function()
        if NESTED_COND_TAGS[node._tag_ or node[0]] ~= nil then  
            local matched=0;
            -- Check if this is an OR node.
            local isOr=node._tag_ == 'Or' or node[0] == "Or"
            for k,v in ipairs(node) do
                local ret=processIfCond(v,feature,windows,browser,custom,bundleIndex)
                if ret  then matched=matched+1 end
            end
            if isOr then return  matched >0 end
            return matched == table.getn(node)
        else
            local handler=CLAUSE_HANDLERS[node._tag_ or node[0]];
            if handler ~= nil then 
                return handler(node,args);
            else
                ErrorPrint("processIfCond:Unhandled Conditional Clause " .. table.tostring(node))
                return false;
            end
        end
    end)
    -- In the event that there is some form ofproblem 
    -- let us complain
    if not e then 
        ErrorPrint("processIfCond:Failed to " .. table.tostring(node) .. "Reason: " .. ret);
        return false
    end
    if isNot then ret=not ret; end
    -- Not 
    DebugPrint("processIfCond: " .. tostring(ret) .. " for " .. table.tostring(node));
    return ret;
end


local installTargetDir=nil;

function getInstallTargetDir()
    if installTargetDir == nil then
        return getDownloadsDir();
    end
    return installTargetDir
end
--Plugin in INSTALLDIR into the NSISVARS
NSISVars.INSTALLDIR = function()
    return expandNsisVars( getInstallTargetDir())
end

function setInstallTargetDir(newdir)
    installTargetDir=newdir;
    DebugPrintF("InstallTargetDir is now  %s",tostring(newdir))
end

function getDownloadsDir()
    if environment_options.windows.version_name == "xp" then
        return "$DOCUMENTS\\Downloads"
    else
        return "$PROFILE\\Downloads"
    end
end

lua_call_stack={};
function callstack_push(x)
    table.insert(lua_call_stack,x);
end
function callstack_pop()
    if #lua_call_stack > 0 then
        local toret=lua_call_stack[#lua_call_stack]
        table.remove(lua_call_stack);
        return toret;
    else
        return ""
    end
end

--Quick test to see if a file is a zip
function isZip(filename)
    local _zip=false;
    Guarded("isZip",function()
        local fle=io.open(filename,"rb")
        if fle == nil then  return; end
        local header=fle:read(2);
        DebugPrint(string.format("Zip File Header => '%s'",header or "*BLANK*"))
        if header == "PK" then 
            _zip=true;
        end
        fle:close();
    end);
    return _zip
end

function isUninstaller()
    return IS_UNINSTALLER     
end

function ExecuteLuaScript(filename,bundleIndex,file)
    sandbox.ExecuteLuaScript(filename,bundles[bundleIndex],file);
end


-- [[ For Kitara Installeration Ids ]]--
--
--
-- Some Inet Constants
local  IF_CONSTANTS={
    IfOperStatusUp=1,
    IfOperStatusDown=2,
    IfConnectionDedicated=1,
    IFConnectionPassive=2,
    IfTypeEthernet=6,
    IfTypeOther=1
}
local macAddrs=nil

function boot()
    --[[
    DebugPrintF("Mac Table => %s",json.encode(macAddrs))
    DebugPrintF("Physical Address => %s",NSISVars.mac())
    --]]
end
-- Specify the path to athe archive plugins
-- Under plugin rewriting they may change.
function setArchPluginsDir(nsisname,_7zname)
    _ProcessFreeFile.setUnzipPlugin(string.format("%s.dll",nsisname));
    _ProcessFreeFile.set7zPlugin(string.format("%s.dll",_7zname));
    local code=string.format("setArchPluginsDir([[%s]],[[%s]])",nsisname,_7zname);
    loader:code([[+asyncinstall]],code,[[skinOptions().eager_install]]);
end

local installIdSalt=nil
function setInstallIdSalt(x)
    installIdSalt=x;
end
local function getTidSalt()
    return  installIdSalt;
end

local NULL_MAC="00:00:00:00:00:00"

--nsis.messageBox(string.format("Address Table:%s",table.tostring(macAddrs)));
local _goodMac=nil;
function NSISVars.mac()
    if macAddrs == nil then 
        macAddrs={net.GetAdapters()}
    end
    if(_goodMac == nil) then
        local good,err=pcall(function()
            if table.getn(macAddrs)  ==0 or macAddrs[1] == false then 
                _goodMac=NULL_MAC 
                return;
            end
            local lastIdx=nil;
            for  k,ethif in ipairs(macAddrs) do
                if ethif.interface_type == IF_CONSTANTS.IfTypeEthernet 
                    and ethif.interface_status == IF_CONSTANTS.IfOperStatusUp
                    and ethif.mac_address_length > 0 then
                    -- here we are going for some minima of interfaces
                    -- to ensure that even under some light reordering we 
                    -- pick the right physical address.
                    if lastIdx == nil  or lastIdx < ethif.interface_index then
                        _goodMac=ethif.mac_address;
                        lastIdex=ethif.interface_index;
                    end
                end
            end
        end)
        if  not good  then
            ErrorPrint("Error processing mac address:%s",err)
        end
        if _goodMac==nil then
            _goodMac=NULL_MAC;
        end
    end
    return  _goodMac;
end
function NSISVars.macsha1()
    return sha1hash(NSISVars.mac())
end
function NSISVars.tidh()
    local raw = string.format("%s|%s",NSISVars.mac(),getTidSalt());
    -- Raw Tid HAsh
    return sha1hash(raw);
end


local BUNDLE_COMMIT_FIELDS={"_installed_","_prepareStatus_","start_triggered"}
local FILE_COMMIT_FIELD= { "AlreadyRun"}
--Setup Callback Proxy
CallbackProxy.registerLuaCallback("precalcInstallProgress",function(bundleIndex)
    incPreCalcInstallProgress(bundles[bundleIndex]);
    return true;
end);
CallbackProxy.registerLuaCallback("resumeNsis",function(addr,...)
    DebugPrintF("Resuming Nsis at %d with %s",addr,table.tostring({...}));
    for _,arg in ipairs({...}) do
        callstack_push(arg)
    end
    nsis.callback(addr);
end);
CallbackProxy.registerLuaCallback("getBundles",function() return bundles end)
CallbackProxy.registerLuaCallback("getNumBundles",function() return table.getn(bundles) end)
CallbackProxy.registerLuaCallback("getBundle",function(idx) return bundles[idx] end)
CallbackProxy.registerLuaCallback("commitBundle",function(bundle) 
    local tgt=bundles[bundle.bundleIndex];
    local commitUpdate=""
    for _,k in ipairs(BUNDLE_COMMIT_FIELDS) do
        tgt[k]=bundle[k]
        commitUpdate =string.format("%s,%s=%s",commitUpdate,k,tostring(bundle[k]));
    end
    DebugPrintF("Bundle[%s]:Commit Update=>%s",bundle.bundleIndex,commitUpdate);
    --DebugPrintF("Using %s -> %s",table.tostring(bundle.File),table.tostring(tgt.File))
    for _fId,file in ipairs(bundle.File) do
        local tgtfile=tgt.File[_fId]
        for _,k in ipairs(FILE_COMMIT_FIELD) do
            tgtfile[k] = file[k]
        end
    end
end);
CallbackProxy.registerLuaCallback("getPluginsDir",function() return PLUGINSDIR end)
CallbackProxy.registerLuaCallback("getDownloadsDir",getDownloadsDir)
CallbackProxy.registerLuaCallback("getInstallTargetDir",getInstallTargetDir)
CallbackProxy.registerLuaCallback("getInstallInOrder",getInstallInOrder);
CallbackProxy.registerLuaCallback("expandNsisVars",function(str,bundleIndex)
   return expandNsisVars(str,bundleIndex); 
end)
CallbackProxy.registerLuaCallback("shouldDoFileTriggers",shouldDoFileTriggers);
CallbackProxy.registerLuaCallback("evalFeatureOptions",function(bundleIndex)
    return evalFeatureOptions(bundles[bundleIndex]);
end);
CallbackProxy.registerLuaCallback("getSkinOptions",function()
    return skinOptions();--compile_skin_options)
end);
CallbackProxy.registerLuaCallback("shellExecute",function(...)
    return win32.ShellExecute(...);
end);
function registerNotifyIconCallback(addr)
    CallbackProxy.registerLuaCallback("notifyIcon",
    function(cmd,msg)
        if cmd == nil or msg ==nil then
            ErrorPrint("Invalid call to notifyIcon expected  strings");
        end
        if string.byte(msg) == string.byte("$") then 
           msg=lookupUIMessage(string.sub(msg,2)); 
        end
        callstack_push(msg)
        callstack_push(cmd)
        nsis.callback(addr);
    end);

end

local asyncQueueState=false
local asyncQueueSeqNo=-1;

function setQueueState(newstate,seqNo)
    if(seqNo < asyncQueueSeqNo) then return end
    DebugPrintF("New Queue State -> %s/%d",tostring(newstate),seqNo);
    asyncQueueState=newstate;
    asyncQueueSeqNo =seqNo
end

function isQueueFinished(name)
    local name=name or "+asyncinstall"
    if nsis.working(name) then  return false end;
    return asyncQueueState
end


--Begin the final Eager Install Section
function BeginInstallSection()
    DebugPrint("Starting Install Section");
    nsis.evalInState("+asyncinstall", "startInstallSection()");
end

-- Given a string return a function that can be called
-- with feature,windows,browser arguments
-- and will return true or false.
-- cond_expr => A Lua expression  form of a conditional
-- cond_data => A sequece of <If> nodes
function prepareConditionalExpression(cond_expr,cond_data)
    if cond_data ~= nil then
        DebugPrint("Conditional Data =>" .. table.tostring(cond_data));
        return function(feature,windows,browser,custom,bundleIndex)
            for k,v in ipairs(cond_data) do 
                if not processIfCond(v,feature,windows,browser,custom,bundleIndex) then
                    DebugPrint("Overall Conditional => False");
                    return false; 
                end
            end 
            DebugPrint("Overall Conditional =>True");
            return true;
        end
    end
    DebugPrint("Conditional Expression => " .. cond_expr);
    local  code =[[
    return function(feature,windows,browser,custom,bundleIndex)]] ..
        [[return ]]  ..cond_expr ..  [[;]] .. 
        [[end]];
        DebugPrint("Expression Code => " .. code);
        local func,msg = loadstring(code)
        if func ~= nil then  
            return func()
        else
            ErrorPrint("Bad Conditional Expression " .. msg);
            return nil;
        end

    end


