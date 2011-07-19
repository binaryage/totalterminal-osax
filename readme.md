# TotalTerminal.osax

This source code implements scripting additions used by [TotalTerminal](http://totalterminal.binaryage.com).

**TotalTerminal** is a plugin for Apple's Terminal.app which brings Visor (famous Quake console) and more!

<!-- <a href="http://totalterminal.binaryage.com"><img src="http://totalterminal.binaryage.com/shared/img/totalterminal-mainshot.png"></a> -->

### Visit [totalterminal.binaryage.com](http://totalterminal.binaryage.com)

## Is this a replacement for SIMBL?

Yes, this is SIMBL-lite tailored specifically for TotalTerminal.

## TotalTerminal configuration file

In special case you may want to create ini file to override TotalTerminal configuration. Currently it is useful in case you install TotalTerminal.app elsewhere than into /Applications/TotalTerminal.app

config file ~/.totalterminal may look like this:

    location = ~/Applications/TotalTerminal.app

## BATTinit event

Installs TotalTerminal.bundle into running Terminal.app (/Applications/TotalTerminal.app is just a wrapper app for this script)

    tell application "Terminal"
        -- give Terminal some time to launch if it wasn't running (rare case)
        delay 1 -- this delay is important to prevent random "Connection is Invalid -609" AppleScript errors 
        try
            «event BATTinit»
        on error msg number num
            display dialog "Unable to launch TotalTerminal." & msg & " (" & (num as text) & ")"
        end try
    end tell

## BATTchck event

Check if TotalTerminal is present in running Terminal image.

    tell application "Terminal"
        -- give Terminal some time to launch if it wasn't running (rare case)
        delay 1 -- this delay is important to prevent random "Connection is Invalid -609" AppleScript errors 
        try
            «event BATTchck»
            set res to "present"
        on error msg number num
            set res to "not present"
        end try
        res
    end tell
