



local base= _G;
local M={}



function M.handleCancel()
    --For now do nothing.
end

--[[ Simply Send this over to the main thread ]]--
function M.installStatus(bundleIndex,message)
    nsis.evalLater(0,string.format("InstallStatus(%d,[[%s]])",bundleIndex,message))
end



return  M
