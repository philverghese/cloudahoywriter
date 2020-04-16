## About This Plugin
This plugin records data from your X-Plane flight to a CSV file that's ready to import into [CloudAhoy](https://www.cloudahoy.com/)

## Installing
1. You need to have [Python 2.7](https://www.python.org/downloads/release/python-279/) installed.
1. Download [PythonInterface for X-Plane for Python 2.7 (version 2.73.06)](http://www.xpluginsdk.org/python_interface_latest_downloads.htm)
1. Extract the above ZIP file and put PythonInterface in your X-Plane `Resources\plugins` directory.
1. Create a directory under your X-Plane `Resources\plugins` called `PythonScripts`
1. Copy `PI_CloudAhoyWriter.py` to  X-Plane `Resources\plugins\PythonScripts`
  * Optionally edit the line that says `self.OutputFile.write("TAIL,X56433\n")` to put your desired tail number for logging in CloudAhoy.
1. Create a new directory under X-Plane `Output` called `flightdata`.

### Summary of directory structure after installing
```
(xplane root directory)
  ...
  |- Output
      |- flightdata
  ...
  | - Plugins
      |- PythonInterface
         |- 32
         |- 64
         ...
           PythonInterface.INI
         ...
      |- PythonScripts
         PI_CloudAhoyWriter.py
```
## Using the plugin
* The plugin automatically starts logging as soon as you launch X-Plane.
* When you are ready to stop logging, open the menu: Plugins > CloudAhoy Writer > Stop Logging
* The tracking file will be in your X-Plane `Output\flightdata` directory with a name based on the date and time.
* Upload that file to CloudAhoy

