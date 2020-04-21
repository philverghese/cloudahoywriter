-----------------------------------------------
-- CloudAhoy Writer
--  Original Python by Adrian Velicu
--  Lua version by Phil Verghese
-----------------------------------------------
local versionNum = '0.0.1'

require('graphics')

-- State
local is_recording = false
local enable_auto_hide = true

-- Bounds for control box
local width = measure_string("X99:99X")
local height = 90
local cawr_width = measure_string("CAWR")
local x1 = 0
local x2 = x1 + width
local y1 = (SCREEN_HIGHT / 2) - 50
local y2 = y1 + height
local centerX = x1 + (width / 2)
local centerY = y1 + ((y2 -y1) / 2)

---------- colors
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

-- recording off
local recOffR = 0.05
local recOffG = 0.05
local recOffB = 0.05
local recOffA = 0.8

-- recording on
local recOnR = 0.9
local recOnG = 0.2
local recOnB = 0.2
local recOnA = 0.8

function CAWR_show_ui()
    if enable_auto_hide and (MOUSE_X > width * 3) then
        return
    end

    XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)

    -- Background rectangle
    graphics.set_color(bgR, bgG, bgB, bgA)
    graphics.draw_rectangle(x1, y1, x2, y2)

    -- Foreground lines and text
    graphics.set_color(fgR, fgG, fgB, fgA)
    draw_string(centerX - (cawr_width / 2), y2 - 20, "CAWR")
    graphics.set_width(2)
    graphics.draw_line(x1, y2, x2, y2)
    graphics.draw_line(x1, y2 - 30, x2, y2 - 30)
    graphics.draw_line(x1 + 1, y2, x1 + 1, y1)
    graphics.draw_line(x2, y2, x2, y1)
    graphics.draw_line(x1, y1, x2, y1)

    -- Recording circle
    if (is_recording) then
        graphics.set_color(recOnR, recOnG, recOnB, recOnA)
    else
        graphics.set_color(recOffR, recOffG, recOffB, recOffA)
    end
    graphics.draw_filled_circle(centerX, centerY - 5, 12)
    graphics.set_color(fgR, fgG, fgB, fgA)
    graphics.draw_circle(centerX, centerY - 5, 12, 2)

    -- Recording time
    draw_string(centerX - (measure_string("12:34") / 2), y1 + 10, "12:34")
end

function CAWR_on_mouse_click()
    if MOUSE_X < x1 or MOUSE_X > x2 then return end
    if MOUSE_Y < y1 or MOUSE_Y > y2 then return end
    if MOUSE_STATUS == 'up' then
        is_recording = not is_recording
    end

    RESUME_MOUSE_CLICK = true -- consume click
end

do_every_draw("CAWR_show_ui()")
do_on_mouse_click("CAWR_on_mouse_click()")
