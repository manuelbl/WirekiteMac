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

    func connectedDevice(_ device: WirekiteDevice!) {
        self.device = device
        ledPort = device.configureDigitalOutputPin(13, attributes: [])
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            timer in self.ledBlink()
        }
    }
    
    func disconnectedDevice(_ device: WirekiteDevice!) {
        if self.device == device {
            self.device = nil
            timer?.invalidate()
            timer = nil
        }
    }
    
    func ledBlink() {
        ledOn = !ledOn
        device?.writeDigitalPin(onPort: ledPort, value: ledOn)
    }
}

