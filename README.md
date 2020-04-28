## About This Plugin
This plugin records data from your X-Plane flight to a CSV file that's ready to import into [CloudAhoy](https://www.cloudahoy.com/). 

## Installation
1. Install [Fly With Lua NG](https://forums.x-plane.org/index.php?/files/file/38445-flywithlua-ng-next-generation-edition-for-x-plane-11-win-lin-mac/).
  - Click the "Download this file" button on the right side
  - Extract the zip. Copy the `FlyWithLua` directory to your `X-Plane 11\Resources\plugins` directory
2. Delete the file `X-Plane 11\Resources\plugins\FlyWithLua\Scripts\please read the manual.lua`
  - This is a default script that puts up a message on the X-Plane screen to read the Fly With Lua manual. You don't need to do that in order to use this plugin.
3. Copy `cloudahoywriter.lua` from this page to `X-Plane 11\Resources\plugins\FlyWithLua\Scripts`

## Usage
If you installed correctly, move your mouse to the left edge of the X-Plane window. You should see a little window pop up that says "CAWR" at the top (that's short for CloudAhoy Writer).

### Automatic Recording Start and Stop
* The plugin starts recording your flight data as soon as you start moving at around 5 knots.
* It will automatically stop recording after you've been stopped for about 10 minutes.
* The CAWR window will show for about 10 seconds when it automatically starts or stops recording.
* Automatic recording start or stop is disabled for about 5 minutes after you manually start or stop recording (see below).

### Manually starting and stopping recording
* You can manually start and stop recording by clicking on the CAWR UI window.
* The litte circle turns red when recording, and the counter starts incrementing to show you how long the recording is.
* Tap the CAWR UI again to stop recording.

## Uploading recording to CloudAhoy
* After you stop recording, the data will be in your `X-Plane 11\Output\flightdata` directory as a `.CSV` file.
* Open [CloudAhoy](https://www.cloudahoy.com), click "Import" at the top of the screen.
* The import window will open. You are required to enter the Pilot's name and aircraft tail number before you can import.
  * The CSV file is required to have the tail number in it, and will overwrite what you input. We'll work on that.
* Drag-and-drop the CSV file to the spot on the CloudAhoy window.