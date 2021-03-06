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
--  - Use simulator time in general (CAWR_flightTimeSec) and name vars
--       as xSimTime. When real time (os.time()) is used, name vars as xOsTime.
-----------------------------------------------
local versionNum = '0.0.10'

if not SUPPORTS_FLOATING_WINDOWS then
    logMsg('Please update your FlyWithLua to the latest version')
    return
end

require('graphics')
require('math')

-------------------- CONSTANTS --------------------
local LOG_INTERVAL_SECS = 0.3
local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = SECONDS_PER_MINUTE * 60
local NOTIFICATION_SECS = 10 -- Default time to show UI notifications

-- Start or stop recording when ground speed crosses this speed.
local AUTO_RECORDING_GROUND_SPEED_MPS = 3 -- Dataref is in m/s
-- Stop recording when the ground speed has been below the speed above
-- for more thsn this time.
local AUTO_STOP_TIME_SECS = 10 * SECONDS_PER_MINUTE
-- Disable automatic recording state change within this many seconds of the
-- making a state change.
local AUTO_RECORDING_DISABLE_SECS = 5 * SECONDS_PER_MINUTE
local FLIGHTDATA_DIRECTORY_NAME = 'cloudahoywriter'
local OUTPUT_PATH_NAME =  SYSTEM_DIRECTORY .. 'Output/' .. FLIGHTDATA_DIRECTORY_NAME
local PREFERENCES_FILE_NAME = SCRIPT_DIRECTORY .. 'cloudahoywriter.ini'

-------------------- STATE --------------------
local lastWriteSimTime = nil
-- Operating system time that recording started (real clock)
local recordingStartOsTime = nil
-- Flight time when recording started (pauses when sim pauses)
local recordingStartSimTime = nil
local recordingDisplayTime = '0:00:00'
-- True if the UI should be forced to show
local forceShowUi = false
-- Time when the UI will no longer be forced to show.
local forceShowUiSimTimeEnd = nil
-- Time when groundspeed was low. Will stop once the AUTO_STOP_TIME_SECS elapses.
local autoStopLowSpeedSimTime = nil
-- Time when the user last changed recording state manually.
-- No automatic changes until AUTO_RECORDING_DISABLE_SECS elapses
local userRecordingStateChangeSimTime = nil

-- User Settings
local pilotName = ''
local tailNumber = ''
local autoRecordEnable = true
local userForceShowUi = false
local developerModeEnable = false

local function is_recording()
    return recordingStartOsTime ~= nil
end

-- Force the UI to display for some seconds.
local function force_show_ui_secs(secondsToShow)
    secondsToShow = secondsToShow or NOTIFICATION_SECS
    forceShowUiSimTimeEnd = CAWR_flightTimeSec + secondsToShow
end

-- Returns true if the UI should be forced on.
local function should_force_show_ui()
    if not forceShowUiSimTimeEnd then return false end
    if CAWR_flightTimeSec > forceShowUiSimTimeEnd then
        forceShowUiSimTimeEnd = nil
        return false
    end
    return true
end

-- forward declarations
local maybe_write_data
local automatic_recording_state_check
local stop_recording

-- Runs on every frame. Has full access to datarefs. May write to file.
-- No drawing methods allowed.
function CAWR_on_every_frame()
    automatic_recording_state_check()
    maybe_write_data()
    forceShowUi = should_force_show_ui()
end

function CAWR_do_on_exit()
    if is_recording() then stop_recording() end
end
-------------------- STATE --------------------




-------------------- PREFERENCES FILE --------------------
local PREF_PILOT_NAME = 'PilotName'
local PREF_TAIL_NUMBER = 'TailNumber'
local PREF_AUTO_RECORD = 'AutoRecordEnable'
local PREF_FORCE_UI = 'AlwaysShowUi'
local PREF_DEVELOPER_MODE = 'DeveloperMode'

local function read_preferences()
    local prefFile = io.open(PREFERENCES_FILE_NAME, 'r')
    if not prefFile then
        print('Unable to read ' .. PREFERENCES_FILE_NAME)
        return
    end
    local pos
    local param
    local value
    for line in prefFile:lines() do
        -- Start at char 2, true=plain text
        pos = string.find(line, '=', 2, true)
        if pos then
            param = string.sub(line, 1, pos - 1)
            value = string.sub(line, pos + 1)
            if param == PREF_PILOT_NAME then pilotName = value end
            if param == PREF_TAIL_NUMBER then tailNumber = value end
            if param == PREF_AUTO_RECORD then autoRecordEnable = (value == 'true') end
            if param == PREF_FORCE_UI then userForceShowUi = (value == 'true') end
            if param == PREF_DEVELOPER_MODE then developerModeEnable = (value == 'true') end
        end
    end
    prefFile:close()
end

local function write_pref_param(file, name, value)
    file:write(name .. '=' .. tostring(value) .. '\n')
end

local function write_preferences()
    local prefFile = io.open(PREFERENCES_FILE_NAME, 'w')
    if not prefFile then
        print('Unable to save preferences to ' .. PREFERENCES_FILE_NAME)
        return
    end
    prefFile:write('# Preferences for CloudAhoy Writer\n')
    if pilotName and pilotName ~= '' then
        write_pref_param(prefFile, PREF_PILOT_NAME, pilotName)
    end
    if tailNumber and tailNumber ~= '' then
        write_pref_param(prefFile, PREF_TAIL_NUMBER, tailNumber)
    end
    write_pref_param(prefFile, PREF_AUTO_RECORD, (autoRecordEnable == true))
    write_pref_param(prefFile, PREF_FORCE_UI, (userForceShowUi == true))
    write_pref_param(prefFile, PREF_DEVELOPER_MODE, (developerModeEnable == true))
    prefFile:close()
end

-------------------- PREFERENCES FILE -------------------




-------------------- UI --------------------
-- Bounds for control box
local width = measure_string('X9:99:99X')
local height = 90
local cawrWidth = measure_string('CAWR')
local cawrDividerHeight = 30
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

-- Runs on every draw. Show UI when appropriate. Do not read or write datarefs.
-- Put frequent dataref access in CAWR_on_every_frame().
function CAWR_on_every_draw()
    if MOUSE_X > width * 3 and not (userForceShowUi or forceShowUi) then
        return
    end

    XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)

    -- Background rectangle
    graphics.set_color(bgR, bgG, bgB, bgA)
    graphics.draw_rectangle(x1, y1, x2, y2)

    -- Foreground lines and text
    graphics.set_color(fgR, fgG, fgB, fgA)
    draw_string(centerX - (cawrWidth / 2), y2 - 16, 'CAWR')
    graphics.set_width(2)
    graphics.draw_line(x1, y2, x2, y2)
    graphics.draw_line(x1, y2 - cawrDividerHeight, x2, y2 - cawrDividerHeight)
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

-- Settings window
local settingsWindow = nil

local function show_settings_ui()
    read_preferences()
    settingsWindow = float_wnd_create(300, 150, 1, true)
    float_wnd_set_position(settingsWindow, x2 + width + 20, y2 - 200)
    float_wnd_set_title(settingsWindow, 'CloudAhoy Writer Settings')
    float_wnd_set_imgui_builder(settingsWindow, 'CAWR_settings_window_builder')
    float_wnd_set_onclose(settingsWindow, 'CAWR_settings_onclose')
end

local function toggle_settings_ui()
    if settingsWindow then
        float_wnd_destroy(settingsWindow)
        settingsWindow = nil
    else
        show_settings_ui()
    end
end

function CAWR_settings_onclose()
    settingsWindow = nil
    write_preferences()
end

function CAWR_settings_window_builder()
    -- TODO(issue #21): Move input text labels to the left
    -- imgui puts the labels on the right, and is awkward to fix
    -- https://github.com/ocornut/imgui/wiki
    -- https://github.com/libigl/libigl/issues/1300
    local pilotChanged, newPilot = imgui.InputText('Pilot Name', pilotName, 30)
    local tailChanged, newTail = imgui.InputText('Tail number', tailNumber, 30)
    if pilotChanged then pilotName = newPilot end
    if tailChanged then tailNumber = newTail end

    imgui.Separator()
    local autoRecChanged, newAutoRec =
        imgui.Checkbox('Automatic recording', autoRecordEnable)
    local alwaysShowChanged, newAlwaysShow =
        imgui.Checkbox('Always show UI', userForceShowUi)
    local developerModeChanged, newDevMode =
        imgui.Checkbox('Developer mode', developerModeEnable)
    if autoRecChanged then autoRecordEnable = newAutoRec end
    if alwaysShowChanged then userForceShowUi = newAlwaysShow end
    if developerModeChanged then developerModeEnable = newDevMode end
end
-------------------- UI --------------------




-------------------- X-PLANE DATA  --------------------
local function meters_to_feet(meters)
    return meters * 3.28084
end

local function mps_to_knots(mps)
    return mps * 1.94384
end

-- Converts sim/time/total_flight_time_sec to a time that's relative
-- to recording_start_time. sim/time/total_flight_time_sec resets to 0
-- when the aircraft or position is changed by the user.
local function simTime_to_recordingTime(simTime)
    return simTime - recordingStartSimTime
end

-- Converts dots(in the range [-2.5, 2.5]) to a scale of [-1, 1].
-- Positive values are a right needle.
-- If the horizontal navigation flag is set, or the input is outside the range
-- [-2.5, 2.5], then returned value will be nil.
local function horizontal_cdi(dots)
    if CAWR_horizontalFlagEnum == 0
        -- enum value 0 means the "off" flag is set.
        or dots > 2.51 or dots < -2.51 then
            -- dot values get a bit noisy right around 2.5
            return nil
    end

    -- If we made it this far, it's a valid horizontal needle.
    return dots / 2.5
end

-- Converts dots(in the range [-2.5, 2.5]) to a scale of [-1, 1].
-- Positive values are a down needle.
-- If the vertical navigation flag is set, or the input is outside the range
-- [-2.5, 2.5], then returned value will be nil.
local function vertical_cdi(dots)
    if CAWR_verticalFlagBool == 1
        -- 1 means vertical nav should exist, but its not received.
        or dots > 2.51 or dots < -2.51 then
            -- dot values get a bit noisy right around 2.5
            return nil
    end

    -- If we made it this far, it's a valid vertical needle.
    return dots / 2.5
end

-- Changes a positive to a negative and vice-versa.
local function change_sign(number )
    return -1 * number
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
        varName='CAWR_magneticVar',
        -- X-Plane uses negative values for east variation. CloudAhoy wants the opposite.
        conversion=change_sign,
    },
    {
        csvField='degrees/WndDr',
        dataRef='sim/cockpit2/gauges/indicators/wind_heading_deg_mag',
        varName='CAWR_windDirectionMag',
    },
    {
        csvField='knots/WndSpd',
        dataRef='sim/cockpit2/gauges/indicators/wind_speed_kts',
        varName='CAWR_windSpeedKts',
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
        arrayIndex=0,
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
        arrayIndex=0,
    },
    -- TODO: Support multi-engine w/ RPM & MAP
    {
        csvField='fsd/HCDI',
        dataRef='sim/cockpit2/radios/indicators/hsi_hdef_dots_pilot',
        varName='CAWR_HCDI',
        conversion=horizontal_cdi,
    },
    {
        csvField='fsd/VCDI',
        dataRef='sim/cockpit2/radios/indicators/hsi_vdef_dots_pilot',
        varName='CAWR_VCDI',
        conversion=vertical_cdi,
    },
}

local function initialize_datarefs()
    for i,v in ipairs(dataTable) do
        -- Only register variables that start with our prefix. Some dataRefs
        -- we want are already registered by FWL (e.g. ELEVATION, LATITUDE).
        if string.find(v.varName, 'CAWR_') then
            if not v.arrayIndex then
                DataRef(v.varName, v.dataRef)
            else
                DataRef(v.varName, v.dataRef, 'readonly', v.arrayIndex)
            end
        end
    end

    DataRef('CAWR_isPaused','sim/time/paused')
    DataRef('CAWR_horizontalFlagEnum', 'sim/cockpit2/radios/indicators/hsi_flag_from_to_pilot')
    DataRef('CAWR_verticalFlagBool', 'sim/cockpit2/radios/indicators/hsi_flag_glideslope_pilot_mech')
end
-------------------- X-PLANE DATA  --------------------



-------------------- DATA RECORDING --------------------
local function write_csv_header(startTime)
    -- Metadata
    io.write('Metadata,CA_CSV.3\n')
    io.write(string.format('GMT,%d\n', startTime))
    if pilotName and pilotName ~= '' then
        io.write(string.format('PILOT,%s\n', pilotName))
    end
    if not tailNumber or tailNumber == '' then
        io.write('TAIL,UNKNOWN\n')
    else
        io.write(string.format('TAIL,%s\n',  tailNumber))
    end
    io.write(string.format('AIRCRAFT_TYPE,%s\n', PLANE_ICAO))
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

local function user_toggle_recording_state()
    userRecordingStateChangeSimTime = CAWR_flightTimeSec
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
        if MOUSE_Y > y2 - cawrDividerHeight then
            -- User clicked in the CAWR area at the top
            toggle_settings_ui()
        else
            user_toggle_recording_state()
        end
    end

    RESUME_MOUSE_CLICK = true -- consume click
end

-- Avoid logging crazy numbers like -3.3631163143796e-045 by
-- only having a fixed number of digits after the decimal.
-- Return the empty string for nil.
local PRECISION_CONSTANT = 10000
local function normalize_data(value)
    if value == nil then return '' end
    if (value >= 0) then
        return math.floor(value * PRECISION_CONSTANT) / PRECISION_CONSTANT
    else
        return math.ceil(value * PRECISION_CONSTANT) / PRECISION_CONSTANT
    end
end

-- Writes to output file.
local function write_data()
    if not is_recording() then return end
    if CAWR_isPaused == 1 then return end

    local trailingChar = ','
    for i,v in ipairs(dataTable) do
        if i == #dataTable then trailingChar = '\n' end
        local dataValue = _G[v.varName] or 0
        if v.conversion then dataValue = v.conversion(dataValue) end
        io.write(normalize_data(dataValue))
        io.write(trailingChar)
    end
end

-- Called from CAWR_on_every_frame. Keep this fast.
function maybe_write_data()
    if not is_recording() then return end
    -- TODO(issue #22): Handle big location change when the user manually repositions aircraft using map.
       -- Start a new recording if we're in the middle of one

    --TODO(issue #23): Check sim/flightmodel2/misc/has_crashed to detect if the simulated
    --          airplane has had a simulated crash. Stop recording when that happens.

    if lastWriteSimTime and (CAWR_flightTimeSec - lastWriteSimTime < LOG_INTERVAL_SECS) then return end
    write_data()
    lastWriteSimTime = CAWR_flightTimeSec
end

-- Called from CAWR_on_every_frame. Keep this fast.
-- Decides whether to automatically start or stop recording.
function automatic_recording_state_check()
    if not autoRecordEnable then return end
    if CAWR_isPaused == 1 then return end

    -- If we were counting down until automatically stopping, reset
    -- the clock when the airplane moves again.
    if CAWR_groundSpeed > AUTO_RECORDING_GROUND_SPEED_MPS then
        autoStopLowSpeedSimTime = nil
    end

    local currentSimTime = CAWR_flightTimeSec
    if userRecordingStateChangeSimTime
        and currentSimTime < userRecordingStateChangeSimTime + AUTO_RECORDING_DISABLE_SECS then
        -- Disable automatic state changes due to recent user action.
        return
    end
    if is_recording() then
        if CAWR_groundSpeed < AUTO_RECORDING_GROUND_SPEED_MPS then
            autoStopLowSpeedSimTime = autoStopLowSpeedSimTime
                or currentSimTime + AUTO_STOP_TIME_SECS
            if currentSimTime > autoStopLowSpeedSimTime then
                print('CAWR_debug: automatically stopping recording')
                autoStopLowSpeedSimTime = nil
                -- Update the total time string display before stopping
                recordingDisplayTime = get_recording_display_time()
                stop_recording()
                force_show_ui_secs()
            end
        end
    else -- not recording
        if CAWR_groundSpeed > AUTO_RECORDING_GROUND_SPEED_MPS then
            print('CAWR_debug: automatically START recording')
            start_recording()
            force_show_ui_secs()
        end
    end
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
read_preferences()




-------------------- FlyWithLua HOOKS --------------------
do_every_frame('CAWR_on_every_frame()')
do_every_draw('CAWR_on_every_draw()')
do_on_mouse_click('CAWR_on_mouse_click()')
do_sometimes('CAWR_do_sometimes()')
do_on_exit('CAWR_do_on_exit()')
