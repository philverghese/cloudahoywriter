-----------------------------------------------
-- CloudAhoy Writer
--  Original Python by Adrian Velicu
--  Lua version by Phil Verghese
--
-- Code conventions
--  - Use local when possible
--  - Globals are prefixed with CAWR_
--  - Method names use_underscores
--  - Variable names useCamelCase
--  - Constant names are CAPITAL_WITH_UNDERSCORE
-----------------------------------------------
local versionNum = '0.0.2'

require('graphics')

-------------------- CONSTANTS --------------------
local LOG_INTERVAL_SECS = 0.3
local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = SECONDS_PER_MINUTE * 60
local FLIGHTDATA_DIRECTORY_NAME = 'flightdata'
local OUTPUT_PATH_NAME =  SYSTEM_DIRECTORY .. 'Output/' .. FLIGHTDATA_DIRECTORY_NAME

-------------------- STATE --------------------
local lastWriteTime = nil
local recordingStartOsTime = nil
local recordingStartSimTime = nil
local recordingDisplayTime = '0:00:00'

local function is_recording()
    return recordingStartOsTime ~= nil
end



-------------------- UI --------------------
-- Bounds for control box
local width = measure_string('X9:99:99X')
local height = 90
local cawrWidth = measure_string('CAWR')
local x1 = 0
local x2 = x1 + width
local y1 = (SCREEN_HIGHT / 2) - 50
local y2 = y1 + height
local centerX = x1 + (width / 2)
local centerY = y1 + ((y2 - y1) / 2)

-- Returns recording display time shown in the UI.
local function get_recording_display_time()
    if not is_recording() then return '0:00:00' end

    local elapsedSeconds = CAWR_flightTimeSec - recordingStartSimTime
    local hours = math.floor(elapsedSeconds / SECONDS_PER_HOUR)
    elapsedSeconds = elapsedSeconds - (hours * SECONDS_PER_HOUR)
    local minutes = math.floor(elapsedSeconds / SECONDS_PER_MINUTE)
    elapsedSeconds = elapsedSeconds - (minutes * SECONDS_PER_MINUTE)
    local seconds = math.floor(elapsedSeconds)

    return string.format('%01d:%02d:%02d', hours, minutes, seconds)
end

-- background color
local bgR = 0.2
local bgG = 0.2
local bgB = 0.2
local bgA = 0.8

-- foreground color
local fgR = 0.8
local fgG = 0.8
local fgB = 0.8
local fgA = 0.8

-- recording off color
local recOffR = 0.05
local recOffG = 0.05
local recOffB = 0.05
local recOffA = 0.8

-- recording on color
local recOnR = 0.9
local recOnG = 0.2
local recOnB = 0.2
local recOnA = 0.8

local maybe_write_data -- forward declaration

-- Runs on every draw. May write to file. May show UI.
function CAWR_on_every_draw()
    maybe_write_data()

    if MOUSE_X > width * 3 then return end

    XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)

    -- Background rectangle
    graphics.set_color(bgR, bgG, bgB, bgA)
    graphics.draw_rectangle(x1, y1, x2, y2)

    -- Foreground lines and text
    graphics.set_color(fgR, fgG, fgB, fgA)
    draw_string(centerX - (cawrWidth / 2), y2 - 16, 'CAWR')
    graphics.set_width(2)
    graphics.draw_line(x1, y2, x2, y2)
    graphics.draw_line(x1, y2 - 30, x2, y2 - 30)
    graphics.draw_line(x1 + 1, y2, x1 + 1, y1)
    graphics.draw_line(x2, y2, x2, y1)
    graphics.draw_line(x1, y1, x2, y1)

    -- Recording circle
    if is_recording() then
        graphics.set_color(recOnR, recOnG, recOnB, recOnA)
        recordingDisplayTime = get_recording_display_time()
    else
        graphics.set_color(recOffR, recOffG, recOffB, recOffA)
    end
    graphics.draw_filled_circle(centerX, centerY - 5, 12)
    graphics.set_color(fgR, fgG, fgB, fgA)
    graphics.draw_circle(centerX, centerY - 5, 12, 2)

    -- Recording time
    draw_string(centerX - (measure_string(recordingDisplayTime) / 2),
        y1 + 10, recordingDisplayTime)
end
-------------------- UI --------------------




-------------------- X-PLANE DATA  --------------------
local function meters_to_feet(meters)
    return meters * 3.281
end

local function mps_to_knots(mps)
    return mps * 1.944
end

-- Converts sim/time/total_flight_time_sec to a time that's relative
-- to recording_start_time. sim/time/total_flight_time_sec resets to 0
-- when the aircraft or position is changed by the user.
local function simTime_to_recordingTime(simTime)
    return simTime - recordingStartSimTime
end

-- Data Table
--   Structure
--      - csvField: name of CloudAhoy CSV field
--      - dataRef: name of X-Plane dataref
--      - varName: name of variable mapped to the dataRef
--      - conversion: optional function to convert units from dataRef to CSV
--      - arrayIndex: index to look at for array datarefs
local dataTable = {
    {
        csvField='seconds/t',
        dataRef='sim/time/total_flight_time_sec',
        varName='CAWR_flightTimeSec',
        conversion=simTime_to_recordingTime,
    },
    {
        csvField='degrees/LAT',
        dataRef='sim/flightmodel/position/latitude',
        varName='LATITUDE',
    },
    {
        csvField='degrees/LON',
        dataRef='sim/flightmodel/position/longitude',
        varName='LONGITUDE',
    },
    {
        csvField='feet/ALT (GPS)',
        dataRef='sim/flightmodel/position/elevation',
        varName='ELEVATION',
        conversion=meters_to_feet,
    },
    {
        csvField='ft Baro/AltB',
        dataRef='sim/cockpit2/gauges/indicators/altitude_ft_pilot',
        varName='CAWR_indAlt',
    },
    {
        csvField='knots/GS',
        dataRef='sim/flightmodel/position/groundspeed',
        varName='CAWR_groundSpeed',
        conversion=mps_to_knots,
    },
    {
        csvField='knots/IAS',
        dataRef='sim/flightmodel/position/indicated_airspeed',
        varName='CAWR_indicatedSpeed',
    },
    {
        csvField='knots/TAS',
        dataRef='sim/flightmodel/position/true_airspeed',
        varName='CAWR_trueSpeed',
        conversion=mps_to_knots,
    },
    {
        csvField='degrees/HDG',
        dataRef='sim/flightmodel/position/mag_psi',
        varName='CAWR_heading',
    },
    {
        csvField='degrees/TRK',
        dataRef='sim/cockpit2/gauges/indicators/ground_track_mag_pilot',
        varName='CAWR_degreesTrack',
    },
    {
        csvField='degrees/MagVar',
        dataRef='sim/flightmodel/position/magnetic_variation',
        varName='CAWR_magVar',
    },
    {
        csvField='degrees/WndDr',
        dataRef='sim/weather/wind_direction_degt',
        varName='CAWR_windDirection',
    },
    {
        csvField='knots/WndSpd',
        dataRef='sim/weather/wind_speed_kt',
        varName='CAWR_windSpeed',
    },
    {
        csvField='degrees/Pitch',
        dataRef='sim/flightmodel/position/true_theta',
        varName='CAWR_degreesPitch',
    },
    {
        csvField='degrees/Roll',
        dataRef='sim/flightmodel/position/true_phi',
        varName='CAWR_degreesRoll',
    },
    {
        csvField='degrees/Yaw',
        dataRef='sim/flightmodel/position/beta',
        varName='CAWR_degreesYaw',
    },
    {
        csvField='fpm/VS',
        dataRef='sim/cockpit2/gauges/indicators/vvi_fpm_pilot',
        varName='CAWR_verticalSpeed',
    },
    {
        csvField='degrees/flaps',
        dataRef='sim/flightmodel2/wing/flap1_deg',
        varName='CAWR_flapDegrees',
        arrayIndex=0,
    },
    {
        csvField='down/gear',
        dataRef='sim/flightmodel2/gear/deploy_ratio',
        varName='CAWR_gearDown',
    },
    {
        csvField='rpm/E1 RPM',
        dataRef='sim/cockpit2/engine/indicators/prop_speed_rpm',
        varName='CAWR_propRpm1',
        arrayIndex=0,
    },
    {
        csvField='in hg/E1 MAP',
        dataRef='sim/cockpit2/engine/indicators/MPR_in_hg',
        varName='CAWR_manPres1',
    },
    -- TODO: Support multi-engine w/ RPM & MAP

    -- TODO: Add CDI fields fsd/HCDI, fsd/VCDI
}

local function initialize_datarefs()
    for i,v in ipairs(dataTable) do
        if string.find(v.varName, 'CAWR_') then
            -- Only register variables that start with our prefix. Some dataRefs
            -- we want are already registered by FWL (e.g. ELEVATION, LATITUDE).
            if not v.arrayIndex then 
                DataRef(v.varName, v.dataRef)
            else
                DataRef(v.varName, v.dataRef, "readonly", v.arrayIndex)
            end
        end
    end

    DataRef('CAWR_isPaused','sim/time/paused')
end
-------------------- X-PLANE DATA  --------------------



-------------------- DATA RECORDING --------------------
local function write_csv_header(startTime)
    -- Metadata
    io.write('Metadata,CA_CSV.3\n')
    io.write(string.format('GMT,%d\n', startTime))
    io.write('TAIL,UNKNOWN\n') -- TODO: Allow user entry
    io.write(string.format('GPS,X-Plane CloudAhoy Writer %s\n', versionNum))
    io.write('ISSIM,1\n')
    io.write('DATA,\n')

    -- Column identifiers
    local trailingChar = ','
    for i,v in ipairs(dataTable) do
        if i == #dataTable then trailingChar = '\n' end
        io.write(string.format('%s%s', v.csvField, trailingChar))
    end
end

local function start_recording()
    assert(not is_recording(), 'start_recording called in wrong state')
    local startTime = os.time()
    local times = os.date('*t', startTime)
    local outputFilename = string.format('CAWR-%4d-%02d-%02d_%02d-%02d-%02d.csv',
        times.year, times.month, times.day, times.hour, times.min, times.sec)
    io.output(OUTPUT_PATH_NAME .. '/' .. outputFilename)
    write_csv_header(startTime)

    -- Don't set this until the header is written to avoid a race with the code that
    -- writes the data after the header.
    recordingStartOsTime = startTime
    recordingStartSimTime = CAWR_flightTimeSec
end

local function stop_recording()
    assert(is_recording(), 'stop_recording called in wrong state')
    recordingStartOsTime = nil
    io.close()
end

local function toggle_recording_state()
    if is_recording() then
        stop_recording()
    else
        start_recording()
    end
end

-- Handles mouse clicks
function CAWR_on_mouse_click()
    if MOUSE_X < x1 or MOUSE_X > x2 then return end
    if MOUSE_Y < y1 or MOUSE_Y > y2 then return end
    if MOUSE_STATUS == 'up' then
        toggle_recording_state()
    end

    RESUME_MOUSE_CLICK = true -- consume click
end

-- Writes to output file. 
local function write_data()
    if not is_recording() then return end

    -- TODO: Maybe handle big location change when the user manually repositions aircraft using map.
       -- Start a new recording if we're in the middle of one
       -- Reset time vars maybe

    --TODO: Check sim/flightmodel2/misc/has_crashed to detect if the simulated
    --          airplane has had a simulated crash. Stop recording when that happens?
    if CAWR_isPaused == 1 then return end

    local trailingChar = ','
    for i,v in ipairs(dataTable) do
        if i == #dataTable then trailingChar = '\n' end
        local dataValue = _G[v.varName] or 0
        if v.conversion then dataValue = v.conversion(dataValue) end
        io.write(dataValue)
        io.write(trailingChar)
    end
end

-- Called from show_ui() on every draw. Keep this fast.
function maybe_write_data()
    if not is_recording() then return end
    if lastWriteTime and (os.clock() - lastWriteTime < LOG_INTERVAL_SECS) then return end
    write_data()
    lastWriteTime = os.clock()
end


-- Runs every 10 seconds
function CAWR_do_sometimes()
    if not is_recording() then return end
    io.flush()
end

-- Creates the 'Output/flightdata' directory if it doesn't exist.
local function create_output_directory()
    local outputDirectory = SYSTEM_DIRECTORY .. 'Output' -- X-plane Output
    local outputContents = directory_to_table(outputDirectory)
    for i, name in ipairs(outputContents) do
        if name == FLIGHTDATA_DIRECTORY_NAME then
            return
        end
    end
    local mkdirCommand = 'mkdir "' .. outputDirectory
            .. '/' .. FLIGHTDATA_DIRECTORY_NAME .. '"'
    print('executing: ' .. mkdirCommand)
    os.execute(mkdirCommand)
end
-------------------- DATA RECORDING --------------------




-------------------- MAIN --------------------
create_output_directory()
initialize_datarefs()




-------------------- FlyWithLua HOOKS --------------------
do_every_draw('CAWR_on_every_draw()')
do_on_mouse_click('CAWR_on_mouse_click()')
do_sometimes('CAWR_do_sometimes()')