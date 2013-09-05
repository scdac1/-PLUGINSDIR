


local M,base = {},_G;
local CallbackProxy=require("CallbackProxy");


function M.precalcInstallProgress(bundleIndex)
    return CallbackProxy.invokeForResp("precalcInstallProgress",bundleIndex);
end
-- Get list of bundles
function M.getBundles()
    return CallbackProxy.invokeForResp("getBundles")
end
function M.getBundle(bundleIndex)
    return CallbackProxy.invokeForResp("getBundle",bundleIndex)
end

function M.getNumBundles(bundleIndex)
    return CallbackProxy.invokeForResp("getNumBundles")
end

function M.withBundles(func)
    local lastIdx=M.getNumBundles();
    for idx=1,lastIdx do
        local bundle=M.getBundle(idx);
        func(idx,bundle)
    end
end
function M.commitBundle(bundle)
    CallbackProxy.invokeForResp("commitBundle",bundle)
end

local pluginsDir=nil;
function M.getPluginsDir()
    if pluginsDir == nil then 
        pluginsDir=CallbackProxy.invokeForResp("getPluginsDir");
    end
    return pluginsDir
end


local downloadDir=nil;
function M.getDownloadsDir() 
    if downloadDir == nil then 
        downloadDir = CallbackProxy.invokeForResp("getDownloadsDir");
    end
    return downloadDir
end

function M.getInstallTargetDir()
    return CallbackProxy.invokeForResp("getInstallTargetDir");
end

function M.getInstallInOrder()
    return CallbackProxy.invokeForResp("getInstallInOrder");
end

function M.expandNsisVars(...)
    return CallbackProxy.invokeForResp("expandNsisVars",...)
end

function M.shouldDoFileTriggers(...)
    return CallbackProxy.invokeForResp("shouldDoFileTriggers",...);
end

function M.evalFeatureOptions(...)
    return CallbackProxy.invokeForResp("evalFeatureOptions",...);
end

function M.shellExecute(...)
    return CallbackProxy.invokeForResp("shellExecute",...);
end


-- Convert Paths INvolving Forward Slash to use BackSlash
-- Ideally this is called for a Path 
function M.normalizePath(text)
    local ret=string.gsub(text,[[/]],[[\]])
    return ret
end

--[[
-- Resum at some nsis function
--]]
function M.resumeMainAt(nsisAddr)
    CallbackProxy.call("resumeNsis",nsisAddr);
end





local SkinData=nil;
function M.getSkinOptions()
    if SkinData == nil then
        SkinData=CallbackProxy.invokeForResp("getSkinOptions")
        -- DebugPrintF("Skin Data=> %s",table.tostring(SkinData))
    end
    return SkinData
end

local function dummy(...)
    _G.DebugPrintF("Dummy Called with %s",table.tostring(dummy))
end
--for now
M.processFileExtract =dummy
M.processXpi=dummy;





return M;
