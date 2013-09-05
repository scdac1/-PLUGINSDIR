--require("luacom")
local sandbox=require("sandbox");
-- Advanced File Tests
--[[
-- Perform a File Execution Result test 
-- {file} => a <File> none 
-- {file} node is expected to have a PassResult.
-- @returns => 1 if the Test passes  and the bundle should be displayed
--]]
function ExecutionResultTest(file,local_file,idx)
    DebugPrint("File is -> " .. table.tostring(file));
    local opts=expandNsisVars(file._a_.Options or "" ,idx)
    local runexpr=[["]] .. local_file .. [[" ]] .. opts   ;
    local waitTime=tonumber(file._a_.TestWaitTime);
    if  waitTime == nil then
        waitTime=-1
    end
    DebugPrint("Launching ->" .. runexpr .. ", Will Wait => " .. waitTime)
    local pattern=file._a_.ResultPattern;
    --[[
    --local rc,result,timedout =win32.RunProcess(runexpr,file.RunDir,waitTime);
    --]]
    -- TODO: Handle the addition of the  Wait Time
    local rc,result,werr=win32.RunProcess(runexpr,file.RunDir);
    local trace="Run Resulted in ->" .. rc .."(werr=" .. werr .. ")," .. tostring(result) .. "/" ..  pattern 
    DebugPrint(trace)
    if result  ==  nil  then
        ErrorPrint(string.format("Failed to Run file test(rc=%d,werr=%d)",rc,werr));
        return true; -- We are not Ok with passing tests that failed
    end
    local patterns=split(pattern,"|")
    for _,pat in ipairs(patterns) do 
        local res= string.match(tostring(result),[[^]] .. pat..[[$]]) ~= nil
        -- In Test this pattern with the pattern in the result
        if res then 
            DebugPrint("Final Test Result -> " ..tostring( res ))
            return res 
        end
    end
    return false;
end

        


--[[
-- For the Specified bundle look for File Entries specified Test at Start
-- IF we find any actually run the tests.
--]]
function postStartFileChecks(obj)
    if isSynBundle(obj) then return end
    local files=obj.File
    idx=obj.bundleIndex
    for n,v in ipairs(files) do
        -- We are testing  at the start
        if v.FileTrigger == "start" and v.FileAction == "test" then
            -- Regex for return code.
            local resultPattern=v._a_.ResultPattern
            local file=v.DestName;
            local node=v;
            local local_file=node.FileName
            local isLua=endswith(local_file,".lua");

            if not isLua and ( resultPattern == nil or string.match(resultPattern,"^\s*$") ~= nil) then
                ErrorPrint("Missing Result pattern at File Entry " .. n 
                .. " in product " .. idx);
            elseif file == nil then 
                ErrorPrint("Missing Result  File at File Entry " .. n 
                .. " in product " .. idx);
            else
                -- Handling Scrambling of Test at Start.
                if node._a_.Scramble == "true" then
                    local ext=".un.exe";
                    if isLua then
                        ext=".un.lua";
                    end
                    local_file=node.FinalFile
                    local unscr_line=[["]] .. PLUGINSDIR .. [[\]]
                    .. [[un.package.exe" "]] .. local_file .. [[" "]]
                    .. local_file .. string.format([[%s" "B"]],ext);
                    DebugPrint("Unscrambling " .. local_file .. " ->\n " .. unscr_line)
                    local rc,result,ec =win32.RunProcess(unscr_line,node.RunDir)
                    local_file = string.format("%s%s",local_file,ext);
                end

                if endswith(local_file,".lua") then
                    if not sandbox.ExecutionLuaTest(v,local_file,idx,obj) then 
                        obj._fileTestSuppressed_ =true
                        obj._willDisplay_=0
                        obj._willInstall_=0
                        obj.trackString = "hidden"

                    end
                elseif not ExecutionResultTest(v,local_file,idx) then 
                    obj._fileTestSuppressed_=true
                    obj._willDisplay_=0
                    obj._willInstall_=0
                    obj.trackString="hidden"
                end
            end

        end
    end
end 

--
-- Look for an <IF> node or an "if" attribute for a bundle.
--
function bundleConditionExprChecks(bundle)
    local cond,sCond=getNodeConditional(bundle)
    if cond  == nil and sCond == nil then return end;
    DebugPrint("Bundle Conditional Expression => " .. tostring(cond) .. "," .. table.tostring(sCond));
    local func = prepareConditionalExpression(cond,sCond);
    if func == nil then return end;
    local showBundle=false;
    local showBundle,sts,msg = evalConditional(func,{},bundle.u,bundle.bundleIndex);
    if not sts then 
        DebugPrint("Bundle Conditional Error:" .. msg);
        showBundle=false;
    end
    if showBundle == false then
        DebugPrint("Hiding Bundle due to conditional");
        bundle._willDisplay_=0;
        bundle._condExprSuppressed_=true;
        bundle._willInstall_=0;
        bundle.trackString="hidden"
    end

end

--[[
-- Check to see if the product should be 
-- hidden due to an overflow.
--]]
function overflowCheck(bundle)
    local custom=environment_options.custom
    if bundle.ProductName ~= nil and bundle.ProductName._body_ ~= nil then
        local name=bundle.ProductName._body_;
        local keyname=string.format("over-threshold:%s",name)
        if custom[keyname]  == 'true' then
            DebugPrint("Hiding Bundle due to over-threshold");
            bundle._overThreshold_ = true
            bundle._willInstall_=0
            bundle._willDisplay_=0
            bundle.trackString="hidden"
        end
    end
end

function advancedTests(obj)
    bundleConditionExprChecks(obj);
    overflowCheck(obj)
    if obj.status.downloaded then 
        DebugPrint(string.format("Bundle[%d]: Running Post Start File Check",obj.bundleIndex))
        postStartFileChecks(obj)
    else
        DebugPrint(string.format("Bundle[%d]: Skipping Post Start Check for for now",  obj.bundleIndex))
    end 
end
