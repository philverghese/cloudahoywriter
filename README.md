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

If you click on the CAWR UI window, it will toggle the recording state. The litte circle turns red when recording, and the counter starts incrementing to show you how long the recording is. Tap the button again to stop recording.

After you stop recording, the data will be in your `X-Plane 11\Output\flightdata` directory as a `.CSV` file. Open [CloudAhoy](https://www.cloudahoy.com), click "Import" and drag-and-drop the file there.