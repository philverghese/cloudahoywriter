"""
CloudAhoy Writer
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


# todo: change to ordereddict
DATAREF_MAP = OrderedDict([
	("seconds/t", "sim/time/total_flight_time_sec"),
	("degrees/LAT", "sim/flightmodel/position/latitude"),
	("degrees/LON", "sim/flightmodel/position/longitude"),
# dataref is in meters
	("feet/ALT (GPS)", lambda: int(XPLMGetDataf(XPLMFindDataRef("sim/flightmodel/position/elevation")) * 3.2)),
	("degrees/HDG","sim/flightmodel/position/mag_psi"),
	("degrees/Pitch","sim/flightmodel/position/true_theta"),
	("degrees/Roll","sim/flightmodel/position/true_phi"),
	("degrees/Yaw","sim/flightmodel/position/beta"),
	("degrees/WndDr","sim/weather/wind_direction_degt"),
# Quoting from docs: "WARNING: this dataref is in meters/second - the dataref NAME has a bug."
#lambda: XPLMGetDataf(XPLMFindDataRef("sim/weather/wind_speed_kt")) * 197
	("knots/WndSpd",lambda: int(XPLMGetDataf(XPLMFindDataRef("sim/weather/wind_speed_kt")))),
#	("fpm/VS","sim/cockpit2/gauges/indicators/vvi_fpm_pilot"),
# doesn't seem to work, maybe cloudahoy is expecting the barometric pressure?
#	("feet/ALT (baro)",lambda: int(XPLMGetDataf(XPLMFindDataRef("sim/flightmodel/misc/h_ind")))),
# TODO: needs conversion from dots to fraction of full scale deflection
#	("fsd/HCDI","sim/cockpit2/radios/indicators/nav1_hdef_dots_pilot"),
#	("fsd/VCDI","sim/cockpit2/radios/indicators/nav1_vdef_dots_pilot"),
	("knots/IAS","sim/flightmodel/position/indicated_airspeed2"),
# in meters/second
	("knots/GS",lambda: XPLMGetDataf(XPLMFindDataRef("sim/flightmodel/position/groundspeed"))*1.94),
	("knots/TAS","sim/cockpit2/gauges/indicators/true_airspeed_kts_pilot"),	
])

class PythonInterface:
	def XPluginStart(self):
		self.IsLogging = False
		self.MenuSetup()
		self.StartLogging()
		return (
			"CloudAhoy Writer",
			"Adi.CloudAhoyWriter",
			"Records sim data in a format understood by CloudAhoy.")

	def XPluginStop(self):
		self.MenuDestroy()
		self.StopLogging()

	def XPluginEnable(self):
		return 1

	def XPluginDisable(self):
		pass
	
	def XPluginReceiveMessage(self, inFromWho, inMessage, inParam):
		pass
	
	def MenuSetup(self):
		idx = XPLMAppendMenuItem(XPLMFindPluginsMenu(), "CloudAhoy Writer", 0, 0)
		self.ourMenuHandlerCb = self.MenuHandlerCB
		self.ourMenu = XPLMCreateMenu(self, "CloudAhoy Writer", XPLMFindPluginsMenu(), idx, self.ourMenuHandlerCb, 0)
		XPLMAppendMenuItem(self.ourMenu, "Start logging", 0, 1)
		XPLMAppendMenuItem(self.ourMenu, "Stop logging", 1, 1)
		XPLMAppendMenuItem(self.ourMenu, "Restart logging", 2, 1)
	
	def MenuDestroy(self):
		XPLMDestroyMenu(self.ourMenu)
	
	def MenuHandlerCB(self, inMenuRef, inItemRef):
		if inItemRef == 0:
			self.StartLogging()
		elif inItemRef == 1:
			self.StopLogging()
		elif inItemRef == 2:
			self.StopLogging()
			self.StartLogging()

	def StartLogging(self):
		if self.IsLogging:
			return
		
		self.IsLogging = True

		formattedDate = datetime.datetime.today().strftime("%Y-%m-%d_%H-%M-%S")
		self.OutputPath = self.__MakePathForFilename(formattedDate)
		self.OutputFile = open(self.OutputPath, 'w')
		self.LastFlushed = 0
		self.LastLogged = 0
		self.WriteMetadata()
		self.FLCB = self.FlightLoopCallback
		XPLMRegisterFlightLoopCallback(self, self.FLCB, LOG_INTERVAL_SECS, 0)
		XPLMSpeakString("CloudAhoy: started logging, output in %s" % self.OutputPath)
		
	def StopLogging(self, flightGivenName = None):
		if not self.IsLogging:
			return
		
		XPLMUnregisterFlightLoopCallback(self, self.FLCB, 0)
		self.OutputFile.close()
		finalPath = self.OutputPath
		if flightGivenName:
			finalPath = self.__MakePathForFilename(flightGivenName)
			os.rename(self.OutputPath, finalPath)
		
		XPLMSpeakString("CloudAhoy: finished logging, output in %s" % finalPath)
		
		self.FLCB = None
		self.OutputPath = None
		self.OutputFile = None
		self.IsLogging = False

	def WriteMetadata(self):
		self.OutputFile.write("Metadata,CA_CSV.3\n")
		self.OutputFile.write("GMT,%s\n" % int(time.time()))
		self.OutputFile.write("TAIL,X56433\n") # todo: ui to set tail number
		self.OutputFile.write("DATA,\n")
		self.OutputFile.write("%s\n" % ",".join([column_name for (column_name, _) in DATAREF_MAP.items()]))

	def FlightLoopCallback(self, elapsedMe, elapsedSim, counter, refcon):
		elapsed = XPLMGetDataf(XPLMFindDataRef("sim/time/total_flight_time_sec"))
		
		if int(elapsed / FLUSH_INTERVAL_SECS) > int(self.LastFlushed / FLUSH_INTERVAL_SECS):
			self.LastFlushed = elapsed
			self.OutputFile.flush()

		#if elapsed < self.LastLogged:
		#	# flight was reset
		#	StopLogging()
		#	return LOG_INTERVAL_SECS
		
		self.LastLogged = elapsed
		#paused = XPLMGetDatab(XPLMFindDataRef("sim/time/paused"))
		#if paused:
		#	return LOG_INTERVAL_SECS
		
		framevals = []
		#framevals.append(str(elapsed))
		for _, dataref in DATAREF_MAP.items():
			dataref_val = None
			if (callable(dataref)):
				dataref_val = dataref()
			else:
				dataref_val = XPLMGetDataf(XPLMFindDataRef(dataref))
			framevals.append(str(dataref_val))

		self.OutputFile.write(",".join(framevals) + "\n")
		
		return LOG_INTERVAL_SECS

	def __MakePathForFilename(self, filename):
		return "%s\\Output\\flightdata\\%s.csv" % (XPLMGetSystemPath(), filename)