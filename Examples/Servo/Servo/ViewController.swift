//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa
import AVFoundation
import WirekiteMac


class ViewController: NSViewController, WirekiteServiceDelegate {
    
    var service: WirekiteService? = nil
    var device: WirekiteDevice? = nil
    var servo: Servo?
    var timer: Timer?
    var angle = 0.0
    var angleInc = 30.0
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        service = WirekiteService()
        service?.delegate = self
        service?.start()
    }
    
    func connectedDevice(_ device: WirekiteDevice!) {
        self.device = device
        device.configurePWMTimer(0, frequency: 100, attributes: [])
        servo = Servo(device: device, pin: 10)
        servo!.turnOn(initialAngle: 0)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            timer in self.moveServo()
        }
    }
    
    func disconnectedDevice(_ device: WirekiteDevice!) {
        if self.device == device {
            self.device = nil
            timer?.invalidate()
            timer = nil
        }
    }
    
    func moveServo() {
        angle += angleInc
        if angle > 180.9 {
            angleInc = -30.0
            angle = 150.0
        }
        if angle < 0 {
            angleInc = 30.0
            angle = 30.0
        }
        servo!.move(toAngle: angle)
    }
}

