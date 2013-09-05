--[[
-- Process Free Files
--]]
--
local M={}
local base=_G
local fs,job,win32=_G.fs,_G.job,_G.win32
local json=require("json");
local sandbox=require("sandbox");

-- TODO: Bootstrap 
local _Downloads =require("Downloads")
local _Env = require("Env")

local DebugPrint,DebugPrintF,ErrorPrint=_G.DebugPrint,_G.DebugPrintF,_G.ErrorPrint

local lastCompletedStart = 0


--Quick test to see if a file is a zip
local function isZip(filename)
    local _zip=false;
    pcall(function()
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


-- Return locals in specific scope
-- Havent tested this!!!
local function locals(scope)
  local variables = {}
  local idx = 1
  while true do
    local ln, lv = debug.getlocal(scope or 1, idx)
    if ln ~= nil then
      variables[ln] = lv
    else
      break
    end
    idx = 1 + idx
  end
  return variables
end



local function processCopyAction(thefile,bundleIndex,cxt)
    
    --_Env.processFileCopy(thefile,cxt.localFile,cxt.fileDest,cxt.fileDestName)
    if thefile.Online == true then 
        if thefile.inTmp then return end
        DebugPrintF([[Copying %s -> %s\%s]],cxt.localFile,cxt.fileDest,cxt.fileDestName);
         -- perform the file copy
        local ret,rc=fs.CopyFiles(cxt.localFile,string.format([[%s\%s]],cxt.fileDest,cxt.fileDestName)) 
        if ret ~= 0 then
            ErrorPrint("File Copy Failed!(%d,rc=%s)",ret,tostring(rc));
        else
            DebugPrintF("File Copy Complete (%d,rc=%s)",ret,tostring(rc))
        end
    else
        DebugPrint("Error|Found an offline file!");
    end
end

local unzipPlugin="nsisunz.dll"

local sevenzPlugin="nsis7z.dll"


local Unzip,Extract=nil;
local dlldir=nil;
local  function ensurePluginCalls()
    local pluginsDir=dlldir or _Env.getPluginsDir()
    Unzip=plugincall.new(string.format([[%s\%s]],pluginsDir,unzipPlugin),"Unzip")
    Extract=plugincall.new(string.format([[%s\%s]],pluginsDir,sevenzPlugin),"Extract")
end

--[[
-- Allow the Unzip and 7zip plugins to be rewritten
--]]
function M.setUnzipPlugin(newname)
    unzipPlugin=newname
end

function M.set7zPlugin(newname)
    sevenzPlugin=newname;
end

function M.setDllDir(newdir)
    dlldir=newdir;
end



local function processExtractAction(thefile,bundleIndex,cxt)
    ensurePluginCalls();
    DebugPrintF("Extract Files .. %s -> %s",cxt.localFile,cxt.fileDest);
    local rc=nil
    if isZip(cxt.localFile) then
        DebugPrintF("Extracting Zip");
        rc=Unzip:call(cxt.localFile,cxt.fileDest);
    else
        DebugPrintF("Extracting 7z");
        rc=Extract:call(cxt.localFile,string.format("$OUTDIR=%s",cxt.fileDest),"Extract Files")
    end
    DebugPrintF("Result -> %s",tostring(rc))
    --_Env.processFileExtract(thefile,cxt.localFile,cxt.fileDest,cxt.fileDestName)
end

local function processXpiAction(thefile,bundleIndex,cxt)
    _Env.processXpi(thefile,cxt.localFile)
end

--Handle An Xpi Via Running it directly though firefox.
local function processXpiDirect(thefile,bundleIndex,cxt)
    --_Env.processXpiDirect(thefile,cxt.localFile,cxt.fileDest,cxt.fileDestName)
    if not  fs.IsDirectory(cxt.fileDest) then 
        ErrorPrint(string.format("Destination was not a directory:%s",cxt.fileDest));
        return;
    end
    local dest=string.format([[%s\%s]],cxt.fileDest,cxt.fileDestName)
    if thefile.inTmp ~= true then
        local ret,rc=fs.CopyFiles(cxt.localFile ,dest)
        if ret ~= 0 then
            ErrorPrint(string.format("Failed  to Copy(%d,rc=%s:%s -> %s",ret,tostring(rc),cxt.localFile,dest));
            return
        end
    end
    if fs.FileExists(dest) then
        DebugPrintF("Launching Xpi: %s",dest); 
        local args=string.format([[-new-tab "file:///%s"]],dest)
        local good,err=_Env.ShellExecute("","firefox.exe",args,cxt.runDir,nil)
        if not good then
            ErrorPrint("Failed to Launch Firefox(rc=%s)",tostring(err));
        end
    end

end

-- [[
-- handle running a file.
-- File is either a Lua Script or a real exe
-- ]]
local function processRunAction(thefile,bundleIndex,cxt,__bundle)
    if thefile._a_.Scramble == 'true' then
        DebugPrintF(">Unscrambling %s -> %s",cxt.localFile,cxt.finalFile);
        _Downloads.unscrambleFile(cxt.localFile,cxt.finalFile)
    end
    local fileOpts=_Env.expandNsisVars(thefile._a_.Options,bundleIndex)
    local finalFile=cxt.finalFile;
    DebugPrintF("Bundle[%d]:Run Action for %s",bundleIndex,cxt.finalFile)
    if thefile.isLuaFile then 
        DebugPrintF("Executing Lua Script:%s",finalFile)
        sandbox.ExecuteLuaScript(finalFile,__bundle,thefile);
    else
        local runLine=string.format([["%s" %s]],finalFile,fileOpts)
        DebugPrintF("Running %s",runLine);
        local newjob=job.new()
        newjob:spawn(nil,runLine,cxt.runDir)
        if thefile._a_.WaitForExe == 'true' then
            DebugPrint("Waiting for Run to Complete");
            newjob:wait();
        end
    end
end

function M.processFreeFiles(intrigger,opts)
    DebugPrintF(">ProcessFreeFiles(%s,%s)",intrigger,table.tostring(opts or {}))
    --local bundles=_Env.getBundles();
    local startIdx,lastIdx=1,_Env.getNumBundles();
    if intrigger == "start" or intrigger == "offer" or intrigger=="installation" then
        startIdx=opts.CurrentBundle
        lastIdx= opts.CurrentBundle;
    end

    for bundleIndex=startIdx,lastIdx  do 
        local bundle=_Env.getBundle(bundleIndex)
        repeat
            local cmd=_Env.shouldDoFileTriggers(bundleIndex,intrigger,opts.CurrentBundle)
            if cmd == "break" then  return end
            if cmd == "true" then 
                if intrigger== "start" then
                    lastCompletedStart = bundleIndex+1;
                end
                for fIdx,thefile in ipairs(bundle.File) do
                    local trigger =thefile.FileTrigger
                    if trigger == intrigger then
                        -- Dont Run Test action
                        if  thefile.FileAction ~= "test" then
                            M.actualProcessFreeFile(thefile,bundleIndex,opts,bundle)
                        end
                    elseif  intrigger == "showfolders" then  
                        -- Show Folder is not a file action but is an action for this function
                        if thefile.AlreadyRun == 1 and thefile._a_.ShowFolder == 'true' then 
                            local path=_Env.expandNsisVars(thefile._a_.Destination,bundleIndex)
                            if thefile.FileAction == 'copy' or thefile.FileAction == 'extract' then
                                win32.ShellExecute("open",path,nil,nil,nil);
                            end
                        end
                    end
                end
                bundle.start_triggered=true;
                _Env.commitBundle(bundle);
            end
        until true
    end
    
end



--[[
-- Actual Free File handler.
-- Idea is to not use __bundle if possible 
-- IT will cause sync issue possibilities
--]]
function M.actualProcessFreeFile(thefile,bundleIndex,opts,__bundle)
    if thefile.AlreadyRun ~= nil then return end
    local sourceFile=thefile._a_.SourceFile
    local localFile = thefile.FileName
    local fileDest = _Env.normalizePath(_Env.expandNsisVars(thefile._a_.Destination,bundleIndex))
    local fileDestName=thefile.DestName
    local finalFile = _Env.normalizePath(_Env.expandNsisVars(thefile.FinalFile or thefile.FileName))
    local runDir = thefile.RunDir
    local status=nil;
    if thefile.Online  == true then 
        DebugPrintF(">Downloading %s -> %s",sourceFile,localFile);
        if thefile.inTmp then
            DebugPrint("Direct Download ... due to (inTmp)")
            localFile= string.format([[%s\%s]],fileDest,fileDestName)
            if string.find('extract xpi copy',thefile.FileAction) ~= nil then 
                fs.CreateDirectory(fileDest)
            end
            DebugPrintF("Downloading File -> %s",localFile);
        end
        repeat 
            -- THiese files are downloading at startup time
            if string.find("start offer" ,thefile.FileTrigger) ~= nil then
                status="success";
                DebugPrint("File is already downloaded");
                break
            end
            -- IF there is already an outcome on this download then break
            if thefile.download_status ~= nil then
                status=thefile.download_status
                break
            end
            --Try the download
            status=_Downloads.downloadFile(sourceFile,localFile,_Downloads.standardProgress(bundleIndex),
            thefile.InstallStepIdx or -1,
            thefile.allowByteRange,
            thefile.FileSize or 0);
            if status  ~= "cancel" and status ~= "success" then
                if  thefile._a_.AlternateSourceFile ~= nil then
                    sourceFile=thefile._a_.AlternateSourceFile
                    DebugPrintF("Trying Alternate Download %s",sourceFile);
                    status=_Downloads.downloadFile(sourceFile,localFile,_Downloads.standardProgress(bundleIndex),
                    thefile.InstallStepIdx or -1,
                    thefile.allowByteRange,
                    thefile.FileSize or 0);
                    DebugPrintF("Alternate Download Status  is %s",status);
                end
            end
            if status == "cancel" then
                _UiState.HandleCancel()
            else
                thefile.download_status=status
            end
        until true
    else
        DebugPrint("Offline File  ... Check for File");
        status="fail"
        if fs.FileExists(localFile) then
            status ="success"
        end
        
    end
    -- At this point we have handled the download business.
    --
    if opts.SkipAction then 
        DebugPrintF("Exiting File processing due to SkipAction");
        return
    end
     
    --Create target dir
    if string.find("extract xpi copy xpidirect",thefile.FileAction)~= nil then 
        if thefile._a_.ForceCreate == 'true' then
            DebugPrintF("Creating:%s",fileDest);
            fs.CreateDirectory(fileDest)
        end
    end
    local context={
       sourceFile=sourceFile,localFile=localFile,runDir=runDir,
       fileDest=fileDest,fileDestName=fileDestName,
       finalFile=finalFile
    }
     
    if status =="success" then
        if thefile.FileAction == 'copy' then
            processCopyAction(thefile,bundleIndex,context)
        elseif thefile.FileAction == 'extract' then
            processExtractAction(thefile,bundleIndex,context)
        elseif thefile.FileAction == 'xpi' then
            processXpiAction(thefile,bundleIndex,context)
        elseif thefile.FileAction == 'xpidirect' then
            processXpiDirectAction(thefile,bundleIndex,context);
        elseif thefile.FileAction == 'run' then
            processRunAction(thefile,bundleIndex,context,__bundle);
        end
    else
        DebugPrintF("Skipping Action status is '%s'",status)
    end
    if status ~= "cancel" then
        thefile.AlreadyRun=1
    end

end
--Public Unzip Interface
function M.Unzip(src,dest)
    ensurePluginCalls();
    return Unzip:call(src,dest) == "success";
end
M.isZip=isZip;
return M
