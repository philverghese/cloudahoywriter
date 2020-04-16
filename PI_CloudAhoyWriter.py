"""
CloudAhoy Writer, by Adrian Velicu
"""

from XPLMDefs import *
from XPLMProcessing import *
from XPLMDataAccess import *
from XPLMUtilities import *
from XPLMMenus import *

import datetime
import time
import os
from collections import OrderedDict

FLUSH_INTERVAL_SECS = 5
LOG_INTERVAL_SECS = 0.3

IDENTITY = lambda x: x
DATAREF_MAP = OrderedDict([
	("seconds/t", ("sim/time/total_flight_time_sec", IDENTITY)),
	("degrees/LAT", ("sim/flightmodel/position/latitude", IDENTITY)),
	("degrees/LON", ("sim/flightmodel/position/longitude", IDENTITY)),
	("feet/ALT (GPS)", ("sim/flightmodel/position/elevation", lambda v: v*3.2)), # in meters
	("degrees/HDG", ("sim/flightmodel/position/mag_psi", IDENTITY)),
	("degrees/Pitch", ("sim/flightmodel/position/true_theta", IDENTITY)),
	("degrees/Roll", ("sim/flightmodel/position/true_phi", IDENTITY)),
	("degrees/Yaw", ("sim/flightmodel/position/beta", IDENTITY)),
	("degrees/WndDr", ("sim/weather/wind_direction_degt", IDENTITY)),
# Docs say: "WARNING: this dataref is in meters/second - the dataref NAME has a bug."
#  .. but they seem to be lying
	("knots/WndSpd", ("sim/weather/wind_speed_kt", IDENTITY)),
	("ft Baro/AltB", ("sim/flightmodel/misc/h_ind", IDENTITY)),
	("knots/IAS", ("sim/flightmodel/position/indicated_airspeed2", IDENTITY)),
	("knots/GS", ("sim/flightmodel/position/groundspeed", lambda v: v*1.94)), # in meters/second
	("knots/TAS", ("sim/cockpit2/gauges/indicators/true_airspeed_kts_pilot", IDENTITY)),
])

# Menu item indices
MENU_START = 0
MENU_STOP = 1
MENU_RESTART = 2

class PythonInterface:
	def XPluginStart(self):
		self.IsLogging = False
		self.InitDatarefs()
		self.MenuSetup()
		self.StartLogging()
		return (
			"CloudAhoy Writer",
			"Adi.CloudAhoyWriter",
			"Records sim data in a format understood by CloudAhoy.")

	def XPluginStop(self):
		self.StopLogging()
		self.MenuDestroy()

	def XPluginEnable(self):
		return 1

	def XPluginDisable(self):
		pass
	
	def XPluginReceiveMessage(self, inFromWho, inMessage, inParam):
		pass
	
	def MenuSetup(self):
		idx = XPLMAppendMenuItem(XPLMFindPluginsMenu(), "CloudAhoy Writer", 0, 0)
		self.ourMenuHandlerCb = self.MenuHandlerCB
		self.ourMenu = XPLMCreateMenu(self, "CloudAhoy Writer", 
		    XPLMFindPluginsMenu(), idx, self.ourMenuHandlerCb, 0)
		XPLMAppendMenuItem(self.ourMenu, "Start logging", MENU_START, 1)
		XPLMAppendMenuItem(self.ourMenu, "Stop logging", MENU_STOP, 1)
		XPLMAppendMenuItem(self.ourMenu, "Restart logging", MENU_RESTART, 1)

	def UpdateMenuItems(self):
		if self.IsLogging:
			XPLMEnableMenuItem(self.ourMenu, MENU_START, 0)
			XPLMEnableMenuItem(self.ourMenu, MENU_STOP, 1)
		else:
			XPLMEnableMenuItem(self.ourMenu, MENU_START, 1)
			XPLMEnableMenuItem(self.ourMenu, MENU_STOP, 0)
	
	def MenuDestroy(self):
		XPLMDestroyMenu(self, self.ourMenu)
	
	def MenuHandlerCB(self, inMenuRef, inItemRef):
		if inItemRef == MENU_START:
			self.StartLogging()
		elif inItemRef == MENU_STOP:
			self.StopLogging()
		elif inItemRef == MENU_RESTART:
			self.StopLogging()
			self.StartLogging()

	def InitDatarefs(self):
		self.datarefs = {}
		for column_name, (dataref_name, _) in DATAREF_MAP.items():
			self.datarefs[dataref_name] = XPLMFindDataRef(dataref_name)
		self.elapsed_time_dataref = XPLMFindDataRef("sim/time/total_flight_time_sec")
		self.paused_dataref = XPLMFindDataRef("sim/time/paused")

	def StartLogging(self):
		if self.IsLogging:
			return
		
		self.IsLogging = True
		self.UpdateMenuItems()

		formattedDate = datetime.datetime.today().strftime("%Y-%m-%d_%H-%M-%S")
		self.OutputPath = self.__MakePathForFilename(formattedDate)
		self.OutputFile = open(self.OutputPath, 'w')
		self.LastFlushed = 0
		self.LastLogged = 0
		self.PauseFrameProcessed = False
		self.WriteMetadata()
		self.FLCB = self.FlightLoopCallback
		XPLMSpeakString("CloudAhoy: started logging")
		XPLMRegisterFlightLoopCallback(self, self.FLCB, LOG_INTERVAL_SECS, 0)
		
	def StopLogging(self, flightGivenName = None):
		if not self.IsLogging:
			return
		
		XPLMUnregisterFlightLoopCallback(self, self.FLCB, 0)
		self.OutputFile.close()
		finalPath = self.OutputPath
		if flightGivenName:
			finalPath = self.__MakePathForFilename(flightGivenName)
			os.rename(self.OutputPath, finalPath)
			
		self.FLCB = None
		self.OutputPath = None
		self.OutputFile = None
		self.IsLogging = False
		self.UpdateMenuItems()
		XPLMSpeakString("CloudAhoy: stopped logging")

	def WriteMetadata(self):
		self.OutputFile.write("Metadata,CA_CSV.3\n")
		self.OutputFile.write("GMT,%s\n" % int(time.time()))
		self.OutputFile.write("TAIL,X56433\n") # todo: ui to set tail number
		self.OutputFile.write("GPS,XPlane\n")
		self.OutputFile.write("ISSIM,1\n")
		self.OutputFile.write("DATA,\n")
		self.OutputFile.write("%s\n" % ",".join([column_name for (column_name, (_, _)) in DATAREF_MAP.items()]))

	def FlightLoopCallback(self, elapsedMe, elapsedSim, counter, refcon):
		elapsed = XPLMGetDataf(self.elapsed_time_dataref)
		paused = XPLMGetDataf(self.paused_dataref)
		
		# Detect if we've already processed exactly one paused frame, and we are still paused
		if self.PauseFrameProcessed and paused:
			# Nothing to log or flush, just call us back later
			return LOG_INTERVAL_SECS
		
		# Detect world resets - when the world resets, elapsed resets, so it is extremely likely
		# it will be less than the last elapsed time logged
		if elapsed < self.LastLogged:
			self.StopLogging()
			self.StartLogging()
			return 0 # Stop getting callbacks; StartLogging will have registered a new flight loop function.
		
		# Log this frame
		framevals = []
		for _, (dataref_name, transform_fun) in DATAREF_MAP.items():
			dataref = self.datarefs[dataref_name]
			raw_value = XPLMGetDataf(dataref)
			real_value = transform_fun(raw_value)
			framevals.append(str(real_value))
		self.OutputFile.write(",".join(framevals) + "\n")
		self.LastLogged = elapsed
		
		# Flush the output file if:
		#   .. more than FLUSH_INTERVAL_SECS of _game time_ have passed, OR
		#   .. we are paused (only one frame will be logged when paused, as this method will return early on
		#      every other frame except the first)
		if (int(elapsed / FLUSH_INTERVAL_SECS) > int(self.LastFlushed / FLUSH_INTERVAL_SECS)) or paused:
			self.LastFlushed = elapsed
			self.OutputFile.flush()
		
		# If we just logged a paused frame, remember it, so we don't log further frames until we get unpaused
		if paused:
			self.PauseFrameProcessed = True
		else:
			self.PauseFrameProcessed = False
		
		return LOG_INTERVAL_SECS

	def __MakePathForFilename(self, filename):
		return "%s\\Output\\flightdata\\%s.csv" % (XPLMGetSystemPath(), filename)