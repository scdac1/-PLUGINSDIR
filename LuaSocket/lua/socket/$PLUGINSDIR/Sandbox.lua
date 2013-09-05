--[[
-- Code Sandbox
--]]

local base=_G
local M= {}
local _Env=require("Env");
local sandbox_pcall=_G.pcall;

--[[
-- Lua Sandbox Support for Executing Scripts
--]]
local SAFE_NAMES={
    "error","assert","ipairs","pairs",
    "tonumber","tostring","pcall","next",
    "ErrorPrint","DebugPrint","DebugPrintF"
} 

local SAFE_SUB_MODULES = {
    ["string"] = {"byte","char","find","format","gmatch","gsub","len",
    "lower","match","rep", "reverse","upper","sub"}, 
    ["math"] = {["except"]={["randomseed"]=1}},
    ["os"] = {"getenv","difftime","clock"},
    ["json"]="*",
    ["registry"]="*",
    ["win32"]="*",
    ["nsis"]="*",
    ["table"]="*",
    ["luacom"]= "*"--[[]]--
}

local function file_exists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

local SANDBOX_ENV = {
    ["io"]= {
        ["file_exist"]=file_exists
    }
}

local function cloneModule(table,args)
    local ret={};
    if type(args) == "table" then
        if args["except"] then
            local bad=args["except"]
            for x,y in pairs(table) do 
                if bad[x] == nil then
                    ret[x]=y;
                end
            end
        else
            -- Explicit list of names
            for _,y in ipairs(args) do
                ret[y]=table[y]
            end
        end
    elseif args == "*" then
        for x,y in pairs(table) do 
            ret[x]=y
        end
    end
    return ret;
end

local sandboxReady=false;
local function prepare()
    if sandboxReady then return end;
    -- Clone Modules
    for x,y in pairs(SAFE_SUB_MODULES) do
        if _G[x]  ~= nil then 
            SANDBOX_ENV[x]=cloneModule(_G[x],y);
        else
            _G.DebugPrintF("Sandbox:Failed to sandbox module(%s->%s)",x,tostring(y))
        end
    end

    -- Clone
    for _,y in ipairs(SAFE_NAMES) do
        if y == "pcall" then 
            SANDBOX_ENV[y] = sandbox_pcall;
        else
            SANDBOX_ENV[y] = _G[y];
        end
    end
    sandboxReady=true;
end
--[[
-- Consistent Script Interface for "current"
-- representation the current  Bundle and optionally the current file
--]]
local function scriptFileEnvironment(bundle,file)
    return {
        ['bundle']=bundle,
        ['file'] =file,
        ['DebugPrint']= function(x,...)
            _G.DebugPrintF("SCRIPT:" .. x,...);
        end,
        ['ErrorPrint']= function(x,...)
            _G.ErrorPrint("SCRIPT:" .. x, ...);
        end,
        ['custom_parameter'] = function(name,...)
            if arg.n == 0 then
                if bundle.CustomParameter == nil then
                    return nil
                end
                local value=nil
                for _,param in ipairs(bundle.CustomParameter) do
                    if param._a_.Name == name then
                        value=params._body_;
                        break;
                    end
                end
                _G.DebugPrint(string.format("SCRIPT:CustomParameter/Get[%s] -> %s",name,tostring(value)))
                return value
            else
                local value=tostring(arg[1]) -- Get the value
                if bundle.CustomParameter == nil then
                    bundle.CustomParameter = {};
                end 
                -- Try to find the parameter
                for _,param in ipairs(bundle.CustomParameter) do
                    if param._a_.Name == name then 
                        _G.DebugPrint(string.format("SCRIPT:CustomParameter/Update[%s] -> %s",name,tostring(value)))
                        param._body_ =value 
                        return;
                    end
                end
                -- Add the custom Paramter
                _G.DebugPrint(string.format("SCRIPT:CustomParameter/Add[%s] -> %s",name,tostring(value)))
                table.insert(bundle.CustomParameter, { ["_a_"]={["Name"]=name},["_body_"]=value})

            end
        end,
        ['expand_path'] =function(str) 
            _G.DebugPrint(string.format("Script:expand_path(%s)",tostring(str)))
            return _Env.expandNsisVars(str,bundle.bundleIndex) 
        end,
        ['feature_checked'] = function(name,...) 
            _G.DebugPrint(string.format("Script:feature_checked(%s)",tostring(name)))
            -- Determine if a feature is checked
            local obj=bundle
            for k,v in ipairs(obj.Feature) do 
                if v.isConditionalFeature == nil then 
                    if v._a_.id == name  then
                        if arg.n == 0 then
                            return v._a_.InitialState == "checked"
                        else
                            local value=arg[1]
                            if type(value) == "number" then 
                                if value ~= 0  then value="checked" else value="unchecked" end
                            elseif type(value) == "string" then 
                                if value ~= "checked" then value ="unchecked" end
                            elseif type(value) == nil or not value  then 
                                value ="unchecked"
                            end
                            _G.DebugPrint(string.format("Script:feature_checked(%s)-> %s",tostring(name),value))
                            v._a_.InitialState =value 
                        end
                    end
                end
            end
            return false;
        end
    }
end

M.scriptFileEnvironment=scriptFileEnvironment
M.prepare=prepare
M.cloneNode=cloneNode
M.SANDBOX_ENV=SANDBOX_ENV

--[[
--Execute Lua File 
--]] 
function M.ExecuteLuaScript(filename,bundle,thefile)
    -- Download the Local File.
    local testfunc,error_message=loadfile(filename);
    if testfunc == nil  then
        ErrorPrint(string.format("Failed to load lua(filename=%s,message=%s)",filename,error_message));
        return true;
    end
    prepare();
    SANDBOX_ENV['test']=nil;
    SANDBOX_ENV['current']=scriptFileEnvironment(bundle,thefile)
    local good,msg= sandbox_pcall(function()
        setfenv(testfunc,SANDBOX_ENV)
        testfunc() -- Run teh test
    end)
    if not good then
        _G.ErrorPrint("Failed to run test code!: %s",tostring(msg));
    end
end

--[[
--Execute Lua File To dtermine if a function can be run
--]] 
function M.ExecutionLuaTest(thefile,local_file,idx,bundle)
    -- Download the Local File.
    local testfunc,error_message=loadfile(local_file);
    if testfunc == nil  then
        _G.ErrorPrint("Failed to load lua(filename=%s,message=%s)",local_file,error_message);
        return true;
    end
    local doInstall=true;

    prepare();
    SANDBOX_ENV['current']=scriptFileEnvironment(bundle,thefile)
    SANDBOX_ENV['test']={
        ['bundle']=bundle,
        ['set_install_state']=function(x) 
            _G.DebugPrintF("SCRIPT:Install State -> %s",tostring(x))
            doInstall=x 
        end
    }
    local good,msg= sandbox_pcall(function()
        _G.DebugPrintF("Executing Lua Test %s",local_file);
        setfenv(testfunc,SANDBOX_ENV)
        testfunc() -- Run teh test
    end)
    if not good then
       _G.ErrorPrint("Failed to run test code!: %s",msg);
    end
    return doInstall
end

function M.updatePcall(x)
    sandbox_pcall=x;
end

return M
