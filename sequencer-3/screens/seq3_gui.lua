-- INIT START
if HOST then return end          -- control events re-run the script: build once
local ok, err = pcall(function()
  if __C then                        -- harness: install the chunk-module shim
    __L = __L or {}
    require = function(n)
      if not __L[n] then
        local f = __C[n]
        if not f then error("module '" .. n .. "' not compiled") end
        __L[n] = f()
        collectgarbage()
      end
      return __L[n]
    end
  end
  local boot = require("boot")
  boot()
end)
if not ok then print("INIT ERROR: " .. tostring(err)) end
-- INIT END
-- LOOP START
if not HOST then return end
FRAME = FRAME + 1
collectgarbage()
local ok, err = pcall(STEP)
if not ok then
  print("LOOP ERR f" .. FRAME .. ": " .. tostring(err))
  HOST = nil
end
-- LOOP END