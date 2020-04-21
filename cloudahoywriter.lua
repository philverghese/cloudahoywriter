-----------------------------------------------
-- CloudAhoy Writer
--  Original Python by Adrian Velicu
--  Lua port by Phil Verghese
-----------------------------------------------
local versionNum = "0.0.1"

require('graphics')

-- Bounds for control box
local x1 = 0
local x2 = 80
local y1 = (SCREEN_HIGHT / 2) - 200
local y2 = y1 + 100
local centerX = (x2 - x1) / 2
local centerY = (y2 - y1) / 2

-- colors
local background = {r=0.2, g=0.2, b=0.2, a=0.75}

function CAWR_show_ui()
    XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)
    graphics.set_color(background.r, background.g, background.b, background.a)
    graphics.draw_rectangle(x1, y1, x2, y2)
end

do_every_draw("CAWR_show_ui()")