-- boot.lua — harness/device bootstrap for the seq-3 GUI screen.
-- Installs the require shim (harness: over chunk-loaded modules; device: the
-- real FS loader), sets up the lcd shim (grid-wasm only), builds the engine
-- and the GUI host, and defines the per-frame STEP function. Everything here
-- runs once; the screen file guards with `if HOST then return end`.
local function installShim()
    if not lcd then
        lcd = setmetatable({}, {
            __index = function(_, name)
                return function(_, ...) return _G[name](0, ...) end
            end,
        })
    end
end

local origRequire = require
local function req(n)
    if not __L[n] then
        if __C then                              -- harness: chunk-loaded modules
            local f = __C[n]
            if not f then error("module '" .. n .. "' not compiled") end
            local mod = f()
            collectgarbage()
            __L[n] = mod
        else
            __L[n] = origRequire(n)              -- device: real FS loader
        end
    end
    return __L[n]
end

local function boot()
    installShim()
    if __C then require = req end                -- harness only
    __L = __L or {}
    MOCK = req("mock_engine")
    MOCK.init{ lanes = 4, channel = 1, demo = true }
    MOCK.onStart()
    local host = req("host")
    HOST = host:new(MOCK, lcd)
    FRAME = 0
    PREV = {}
    STEP = function()
        -- Consume the delta: the harness re-injects the grid table only on an
        -- event, so an unconsumed delta re-fires encTurn on every frame.
        local d = grid.encoder_delta
        if d ~= 0 then grid.encoder_delta = 0; HOST:encTurn(d) end
        for i = 0, 13 do
            local st = (grid.button_state[i] or 0) == 1
            if st ~= PREV[i] then
                PREV[i] = st
                if st then
                    if i <= 7 then HOST:keyDown(i)
                    elseif i >= 9 and i <= 12 then HOST:btnDown(i)
                    elseif i == 13 then HOST:encPress() end
                end
            end
        end
        if FRAME % 10 == 0 then HOST:onPulse() end
        HOST:render(FRAME)
    end
    print("seq3 gui ready")
end

return boot