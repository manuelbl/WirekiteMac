//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa

class MainViewController : NSViewController, WirekiteServiceDelegate, NSWindowDelegate {
 
    var service: WirekiteService? = nil
    var deviceWindowControllers: [NSWindowController] = []
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
    }
    
    override func viewDidAppear() {
        if service == nil {
            service = WirekiteService()
            service?.delegate = self
            service?.start()
        }
    }
    
    func connectedDevice(_ device: WirekiteDevice!) {
        // create new window
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: "Device Window Controller") as! NSWindowController
        
        // hold on to the window controller
        deviceWindowControllers.append(windowController)
        let w = windowController.window!
        
        // this view controller acts as the window delegate
        // to be notified if the window is closed
        w.delegate = self
        
        // set representedObject to be the device
        windowController.contentViewController!.representedObject = device
        
        // show window
        w.makeKeyAndOrderFront(NSApplication.shared())
        
        // hide this window
        view.window?.orderOut(self)
    }
    
    func disconnectedDevice(_ device: WirekiteDevice!) {
        // Look for window with device
        for wc in deviceWindowControllers {
            let c = wc.contentViewController!
            let d = c.representedObject as? WirekiteDevice
            if d == device {
                c.representedObject = nil
                wc.window!.close()
                return
            }
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        let w = notification.object as! NSWindow

        if let device = w.contentViewController?.representedObject as? WirekiteDevice {
            device.resetConfiguration()
        }
        
        let size = deviceWindowControllers.count
        for i in 0 ..< size {
            if deviceWindowControllers[i].window === w {
                deviceWindowControllers.remove(at: i)
                if size == 1 {
                    view.window!.orderFront(self)
                }
                return
            }
        }
    }
}
