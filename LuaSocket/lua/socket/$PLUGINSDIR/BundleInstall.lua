--{{
-- Bundle Installation Module.
--}}

local M={}

local base=_G;
local fs=_G.fs;
local json=require("json");

local scheduler=require("scheduler");

-- TODO: Replace this with a  real interface
local _NotifyIcon = require("NotifyIcon"); 

local _UiState =  require("UiState")

-- Download system
local _Downloads = require("Downloads");
local _ProcessFreeFile=require("ProcessFreeFile");


local  _Env = require("Env");
--[[{
    ["getPluginsDir"]=function() end,
    ["expandNsisVars"]=function() end,
    ["getDownloadsDir"] = function() end,
    ["getInstallInOrder"] = function() end,
    ["getBundles"] = function() end,
    ["processXpi"] = function(fileobj,localfile,dest,destName)  end,
    ["processFileExtract"] = function(fileobj,localfile,dest,destName)  end,
    ["executeLuaScript"]= function(filename,fileobj,bundleIndex) end
}
]]--


local showNotify=function(bundle)
    if _Env.getSkinOptions().is_downloaddotcom then
        return bundle.isPrimary ==  false;
    else
        return true
    end
end

local PHASE_INSTALL,
PHASE_FINISH="install","finish";
M.PHASE_INSTALL = PHASE_INSTALL
M.PHASE_FINISH = PHASE_FINISH

local DebugPrint,DebugPrintF,ErrorPrint=_G.DebugPrint,_G.DebugPrintF,_G.ErrorPrint
    
--[[
-- PrepareInstall (bundle:table,phase:string,options:Table) -> 
-- bundle data structure
--]] 
function M.PrepareInstall(bundle,phase,opts)

    local bundleIndex=bundle.bundleIndex;
    DebugPrintF("Bundle[%d]:Preparing to install",bundleIndex)
    if scheduler.cancelled() then 
        DebugPrintF("Editing Cancelled!");
        return; 
    end;
    -- Check Installed and Will Install flags
    if bundle._installed_ == 1  then
        DebugPrintF("Bundle[%d]:Skipping Installed? - true",bundleIndex);
        return
    end
    if bundle._willInstall_ ~= 1 then 
        DebugPrintF("Bundle[%d]:Skipping willInstall? - false",bundleIndex);
        return 
    end
    local skip_action=false;

    if  _Env.getSkinOptions().do_install_at_finish then
        -- IF we are doing install at finish we skip the install part unless this
        -- is the finish phase
        skip_action = true
    end

    _ProcessFreeFile.processFreeFiles("installation",{
        ["SkipAction"]=skip_action,
        CurrentBundle=bundleIndex
    })
    local localFile,finalFile=nil,nil;
    if bundle.Embedded == 'true' then 
        --Embedded Bundle
        if bundle.ProductBinary._body_ ~= '' then
            DebugPrintF("Bundle[%d]:ProductBinary is -> %s",bundleIndex,bundle.ProductBinary._body_);
            if showNotify(bundle) then 
                _NotifyIcon.infoTip("$SYSTRAY.EXTRACT.INPROGRESS");
            end
            bundle._prepareStatus_ = 'success'
            _UiState.installStatus(bundle.bundleIndex,[[Downloaded]]);
        end
    else
        -- Online Bundle we need to download 
        if showNotify(bundle) then
            _NotifyIcon.infoTip(string.format("Downloading %s",bundle.ProductName._body_))
        end
        localFile,finalFile=_Env.expandNsisVars(bundle.LocalFile,bundleIndex),bundle.FinalFile;
        if finalFile ~= nil then
            finalFile=_Env.expandNsisVars(finalFile,bundleIndex);
        end
        --  Load the final file.
        local binary=bundle.ProductBinary._body_;
        local result=nil;
        repeat 
            if bundle._prepareStatus_ == 'success' then 
                result=bundle._prepareStatus_;
                break; -- Consider Coroutine for this.
            end
            DebugPrintF("Bundle[%d]:Downloading:%s -> %s",bundleIndex,binary,localFile)
            result =_Downloads.downloadFile(binary,localFile,_Downloads.standardProgress(bundleIndex),
            bundle.InstallStepIdx or -1,
            bundle.allowByteRange, bundle.FileSize or 0 )
            DebugPrintF("Initial Download was => %s",result);
            if result ~= "cancel" and result ~= "success" then
                if  bundle.AlternateProductBinary and bundle.AlternateProductBinary._body_ ~= nil then
                    binary  = bundle.AlternateProductBinary._body_
                    DebugPrint("Bundle[%d]:Trying Alternative Download %s",bundleIndex,binary);
                end
            end
        until true;
        if result == "success" then 
            bundle._prepareStatus_ = 'success'
            _UiState.installStatus(bundleIndex,[[Downloaded]]);
        elseif result == "cancel" then 
            _UiState.handleCancel(); -- This call may yield
        else
            bundle._prepareStatus_ = "fail"
            _UiState.installStatus(bundleIndex,[[Download Failed]]);
            if _Env.getSkinOptions().is_downloaddotcom and showNotify(bundle) then
                _NotifyIcon.errorTip("$DOWNLOAD.FAIL");
            end
        end
    end -- Embeded Product Conditional
    _Env.commitBundle(bundle);
    -- handle Scrambled files
    if bundle.Scramble._body_ == 'true' then 
        if localFile ~= nil and finalFile ~= nil then 
            DebugPrint(string.format("Unpackaging  %s -> %s ",localFile,finalFile));
            _Downloads.unscrambleFile(localFile,finalFile);
        else
            ErrorPrint("Scrambled Binary but NO localFile or finalFile");
            --Should not get here.
        end
    end


end
--[[
-- InstallBundle(bundle:table) ->
-- Given a bundle perform the installation actions for it.
--]]
function M.InstallBundle(bundle)
    local bundleIndex=bundle.bundleIndex;
    if scheduler.cancelled() then return end
    -- Already Installed
    if bundle._installed_ == 1 or bundle._failed_ == 1 then
        return 
    end
    -- No schedueld for install
    if bundle._willInstall_ ~= 1 then return end
    --If not prepared then we fail
    if bundle._prepareStatus_ ~= 'success' then
        _UiState.installStatus(bundleIndex,[[Download Error]]);
        bundle._failed_=1;
        bundle._installedMessage_ = "Download Error";
        return
    end
    _UiState.installStatus(bundleIndex,[[Installing]]);
    if _Env.getSkinOptions().is_downloaddotcom
         and showNotify(bundle) then
        _NotifyIcon.infoTip(string.format("Installing %s",bundle.ProductName._body_));
    end

    if bundle.ProductBinary._body_ ~= '' then 
        local finalExe = bundle.FinalFile or bundle.LocalFile
        finalExe = _Env.expandNsisVars(finalExe,bundleIndex)
        local _options=_Env.evalFeatureOptions(bundleIndex);
        local _noOptions =_options == nil or  _options == ''
        local msiOpts,runOpts,runLine = "","","";
        if bundle.ProductBinary.msi and string.lower(bundle.ProductBinary.msi) == 'true' then 
            -- Msi Case
            msiOpts = bundle.ProductBinary._a_.msioptions or ""
            if _noOptions then 
                runOpts = bundle.ProductBinary._a_.options or ""
            else
                runOpts = _options 
            end
            runOpts = _Env.expandNsisVars(runOpts,bundleIndex);
            runLine = string.format([[msiexec %s /i "%s" %s ]],msiOpts,finalExe,runOpts);
        else
            -- Non MSI
            if _noOptions then 
                runOpts =  bundle.ProductBinary._a_.options
            else
                runOpts =_options 
            end
            runOpts=_Env.expandNsisVars(runOpts,bundleIndex);
            runLine = string.format([["%s" %s]],finalExe,runOpts);
        end
        local newjob=job.new()
        DebugPrintF("Running :%s in (%s)",runLine,bundle.RunDir)
        newjob:spawn(nil,runLine,bundle.RunDir)
        if _Env.getSkinOptions().nowait_installs then 
            -- Nothing to do scope will resolve the cleanup.
        else
            DebugPrint("Waiting for Install"); 
            -- Wait for the Job to Complete
            newjob:wait();
        end
    end
    bundle._installed_ = 1;
    bundle._installedMessage_ = 'Success'
    _UiState.installStatus(bundleIndex,[[Installed]])
    _Env.commitBundle(bundle);
end

-- Install Prepare section
function M.SectionInstall()
    DebugPrint("Entering Install Prepare")
    --[[
    if _Env.getSkinOptions().allow_install_pause then
    _Downloads.useByteRange(true)
    end
    --]]
    local _skinOpts=_Env.getSkinOptions()
    if _skinOpts.manual_install_primary == true then
        local dir=_Downloads.getDownloadsDir();
        dir = _Env.expandNsisVars(dir,1);
        DebugPrintF("Creating Directory %s",dir)
        fs.CreateDirectory(dir)
    end
    --DebugPrint("Bundles:%s",json.encode(bundles));
    local install_at_finish=_skinOpts.do_install_at_finish
    _Env.withBundles(function(idx,bundle)
        repeat 
            if bundle.isPrimary == false or _Env.getInstallInOrder() then
                --DebugPrint("Bundle:%s",table.tostring(bundle));
                M.PrepareInstall(bundle,PHASE_INSTALL,{});
                if install_at_finish then
                    break;
                end
                --if we manually install the prumar
                if _skinOpts.manual_install_primary and bundle.isPrimary then
                    break;
                end

                --For non primaries or install in order 
                M.InstallBundle(bundle)
            end
        until true;
    end)
    _Env.withBundles(function(_,bundle)
        repeat 
            if bundle.isPrimary == true and not _Env.getInstallInOrder() then 
                M.PrepareInstall(bundle,PHASE_INSTALL,{})
                if install_at_finish then
                    break;
                end
                if _Env.getSkinOptions().manual_install_primary then
                    break;
                end
                M.InstallBundle(bundle);
            end
        until true
        _Env.commitBundle(bundle);
    end)
    --[[
    if _Env.getSkinOptions().allow_install_pause then
       _Downloads.useByteRange(false)
    end
    --]]
end


function M.DoDeferredInstall()
    _Env.withBundles(function(_,bundle)
        repeat 
            if bundle._installed_ ==1  or bundle._willInstall_ ~= 1 then
                break
            end
            _ProcessFreeFile.processFreeFiles(bundle,"installation",{});
            if _Env.getSkinOptions().manual_install_primary then
                if bundle.isPrimary then 
                    break
                end
            end
            M.InstallBundle(bundle)
        until true
    end)
end

return M


