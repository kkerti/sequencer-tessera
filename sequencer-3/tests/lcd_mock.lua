-- tests/lcd_mock.lua — a STRICT stand-in for the device LCD object.
--
-- Why strict: the permissive mock (an __index that returned a function for any
-- name) let `lcd:draw_area_filled(...)` pass 44 headless checks and then crash
-- the module on device — the real LCD has no such method. It also let a
-- full-screen clear pass (0,0,320,240) when the framebuffer corners are
-- 0..319 x 0..239, i.e. a write one pixel past each edge.
--
-- The whitelist is exactly the primitive set seq-1's cold-boot-proven profile
-- uses (dist/sequencer_ui.lua): draw_rectangle_filled, draw_rectangle,
-- draw_text_fast, draw_swap. Anything else, or any out-of-bounds coordinate,
-- is recorded as an error so the test fails here instead of on hardware.
--
--   local M = dofile("tests/lcd_mock.lua")
--   local lcd = M.new()
--   ... drive the draw ...
--   lcd.calls, lcd.errors

local M = {}

M.W, M.H = 320, 240          -- valid corners: 0..W-1, 0..H-1

-- name -> {kind}. "rect" = (x0,y0,x1,y1,color); "text" = (s,x,y,size,color).
local API = {
    draw_rectangle_filled = "rect",
    draw_rectangle        = "rect",
    draw_text_fast        = "text",
    draw_swap             = "none",
}

function M.new()
    local self = { calls = 0, errors = {} }

    local function err(msg)
        self.errors[#self.errors + 1] = msg
    end

    local function checkX(name, v, which)
        if type(v) ~= "number" then
            err(name .. ": " .. which .. " is not a number (" .. tostring(v) .. ")")
        elseif v < 0 or v > M.W - 1 then
            err(name .. ": " .. which .. "=" .. v .. " outside 0.." .. (M.W - 1))
        end
    end
    local function checkY(name, v, which)
        if type(v) ~= "number" then
            err(name .. ": " .. which .. " is not a number (" .. tostring(v) .. ")")
        elseif v < 0 or v > M.H - 1 then
            err(name .. ": " .. which .. "=" .. v .. " outside 0.." .. (M.H - 1))
        end
    end
    local function checkColor(name, c)
        if type(c) ~= "table" or #c ~= 3 then
            err(name .. ": colour must be a 3-element table")
        end
    end

    local handlers = {
        rect = function(name, x0, y0, x1, y1, color)
            checkX(name, x0, "x0"); checkY(name, y0, "y0")
            checkX(name, x1, "x1"); checkY(name, y1, "y1")
            checkColor(name, color)
        end,
        text = function(name, s, x, y, size, color)
            if type(s) ~= "string" and type(s) ~= "number" then
                err(name .. ": text must be a string or number")
            end
            checkX(name, x, "x"); checkY(name, y, "y")
            if type(size) ~= "number" then err(name .. ": size must be a number") end
            checkColor(name, color)
        end,
        none = function() end,
    }

    return setmetatable(self, {
        __index = function(_, name)
            local kind = API[name]
            if not kind then
                -- Record once per unknown name, then no-op so the test can
                -- keep running and report everything it found.
                err("unknown LCD method: " .. tostring(name)
                    .. " (device has only draw_rectangle_filled / draw_rectangle"
                    .. " / draw_text_fast / draw_swap)")
                return function() return true end
            end
            return function(_, a, b, c, d, e)
                self.calls = self.calls + 1
                handlers[kind](name, a, b, c, d, e)
                return true
            end
        end,
    })
end

return M
