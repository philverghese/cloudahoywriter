"""
CloudAhoy Writer
"""

from XPLMDefs import *
from XPLMProcessing import *
from XPLMDataAccess import *
from XPLMUtilities import *

import datetime
import time

FLUSH_INTERVAL_SECS = 30
LOG_INTERVAL_SECS = 0.3


# todo: change to ordereddict
DATAREF_MAP = {
	"degrees/LAT": "sim/flightmodel/position/latitude",
	"degrees/LON": "sim/flightmodel/position/longitude",
	"feet/ALT (GPS)": "sim/flightmodel/position/elevation"
}

class PythonInterface:
	def XPluginStart(self):
		global gOutputFile, gPlaneLat, gPlaneLon, gPlaneEl
		self.Name = "CloudAhoy Writer"
		self.Sig =  "Adi.CloudAhoyWriter"
		self.Desc = "Records sim data in a format understood by CloudAhoy."

		startTime = datetime.datetime.today()
		formattedDate = startTime.strftime("%Y-%m-%d_%H-%M-%S")
		outputPath = XPLMGetSystemPath() + "Output\\flightdata\\%s.csv" % formattedDate
		
		self.OutputFile = open(outputPath, 'w')
		self.LastFlushed = -1

		""" Find the data refs we want to record."""
		self.datarefs = []
		for column_name, dataref_string in DATAREF_MAP.iteritems():
			self.datarefs.append((column_name, XPLMFindDataRef(dataref_string)))
	
		self.WriteMetadata()

		self.FlightLoopCB = self.FlightLoopCallback
		XPLMRegisterFlightLoopCallback(self, self.FlightLoopCB, FLUSH_INTERVAL_SECS, 0)
		return self.Name, self.Sig, self.Desc

	def XPluginStop(self):
		XPLMUnregisterFlightLoopCallback(self, self.FlightLoopCB, 0)
		self.OutputFile.close()
		pass

	def XPluginEnable(self):
		return 1

	def XPluginDisable(self):
		pass

	def XPluginReceiveMessage(self, inFromWho, inMessage, inParam):
		pass

	def WriteMetadata(self):
		self.OutputFile.write("Metadata,CA_CSV3\n")
		self.OutputFile.write("GMT,%s\n" % int(time.time()))
		self.OutputFile.write("TAIL,SIMULATEDPLANE\n") # todo: ui to set tail number
		self.OutputFile.write("seconds/t,%s\n" % ",".join([column_name for (column_name, _) in self.datarefs]))
		self.OutputFile.write("DATA\n")

	def FlightLoopCallback(self, elapsedMe, elapsedSim, counter, refcon):
		elapsed = XPLMGetElapsedTime()
		framevals = []
		framevals.append(str(elapsed))
		for _, dataref in self.datarefs:
			framevals.append(str(XPLMGetDataf(dataref)))

		self.OutputFile.write(",".join(framevals) + "\n")
		
		if int(elapsed / FLUSH_INTERVAL_SECS) > int(self.LastFlushed / FLUSH_INTERVAL_SECS):
			self.LastFlushed = elapsed
			self.OutputFile.flush()

		return LOG_INTERVAL_SECS;
