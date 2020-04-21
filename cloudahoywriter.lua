-----------------------------------------------
-- CloudAhoy Writer
--  Original Python by Adrian Velicu
--  Lua version by Phil Verghese
-----------------------------------------------
local versionNum = '0.0.1'

require('graphics')

-- Bounds for control box
local x1 = 0
local x2 = 80
local y1 = (SCREEN_HIGHT / 2) - 50
local y2 = y1 + 100
local centerX = (x2 - x1) / 2
local centerY = (y2 - y1) / 2

--------------------- colors
-- background
local bgR = 0.2
local bgG = 0.2
local bgB = 0.2
local bgA = 0.8

-- foreground
local fgR = 0.8
local fgG = 0.8
local fgB = 0.8
local fgA = 0.8


function CAWR_show_ui()
    XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)
    graphics.set_color(bgR, bgG, bgB, bgA)
    graphics.draw_rectangle(x1, y1, x2, y2)
    graphics.set_color(fgR, fgG, fgB, fgA)
    draw_string(x1 + 5, y2 - 20, "CAWR")
end

do_every_draw("CAWR_show_ui()")