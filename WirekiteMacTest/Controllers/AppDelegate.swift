//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, WirekiteServiceDelegate, NSWindowDelegate {

    var service: WirekiteService? = nil
    var windowControllers: [NSWindowController] = [ ]

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        let window = NSApplication.shared().mainWindow!
        window.delegate = self
        windowControllers.append(window.windowController!)
        
        service = WirekiteService()
        service?.delegate = self
        service?.start()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func deviceAdded(_ newDevice: WirekiteDevice!) {
        // check for existing window without a device and use it
        for wc in windowControllers {
            let c = wc.contentViewController!
            if c.representedObject == nil {
                c.representedObject = newDevice
                return
            }
        }
        
        // open new window
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: "Device Window Controller") as! NSWindowController
        windowController.window!.delegate = self
        windowControllers.append(windowController)
        
        // set representedObject to be the device
        if let viewController: ViewController = windowController.contentViewController as! ViewController? {
            viewController.representedObject = newDevice
        }
        windowController.showWindow(nil)
    }
    
    func deviceRemoved(_ removedDevice: WirekiteDevice!) {
        // Look for window with device
        for wc in windowControllers {
            let c = wc.contentViewController!
            let device = c.representedObject as? WirekiteDevice
            if device == removedDevice {
                c.representedObject = nil
                // close window unless it is the last one left
                if windowControllers.count > 1 {
                    wc.window!.close()
                }
                return
            }
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        let size = windowControllers.count
        let w = notification.object as! NSWindow
        for i in 0 ..< size {
            if windowControllers[i].window === w {
                windowControllers.remove(at: i)
                return
            }
        }
    }
}

