local base =_G;
local M={}

local callbackProxy=require("CallbackProxy")

function M.infoTip(text,timeout)
    callbackProxy.call("notifyIcon","no",text,timeout or ""  );
end

function M.errorTip(text,timeout)
    callbackProxy.call("notifyIcon","eo",text,timeout or ""  );
end

return M
