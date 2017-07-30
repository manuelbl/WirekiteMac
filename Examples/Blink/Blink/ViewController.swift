//
//  ViewController.swift
//  Blink
//
//  Created by Manuel Bleichenbacher on 30.07.17.
//  Copyright © 2017 Codecrete. All rights reserved.
//

import Cocoa
import WirekiteMac


class ViewController: NSViewController, WirekiteServiceDelegate {

    var service: WirekiteService? = nil
    var device: WirekiteDevice? = nil
    var timer: Timer? = nil
    var ledPort: PortID = 0
    var ledOn = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        service = WirekiteService()
        service?.delegate = self
        service?.start()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    func deviceAdded(_ newDevice: WirekiteDevice!) {
        device = newDevice
        device!.resetConfiguration()
        ledPort = device!.configureDigitalOutputPin(13, attributes: [])
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            timer in self.ledBlink()
        }
    }
    
    func deviceRemoved(_ removedDevice: WirekiteDevice!) {
        if device == removedDevice {
            device = nil
            timer?.invalidate()
            timer = nil
        }
    }
    
    func ledBlink() {
        ledOn = !ledOn
        device?.writeDigitalPin(onPort: ledPort, value: ledOn)
    }
}

