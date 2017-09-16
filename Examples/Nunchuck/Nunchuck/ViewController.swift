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
    var i2c: PortID = 0
    var nunchuck: Nunchuck?
    var timer: Timer? = nil
    
    @IBOutlet weak var joyXLabel: NSTextField!
    @IBOutlet weak var joyYLabel: NSTextField!
    @IBOutlet weak var accelXLabel: NSTextField!
    @IBOutlet weak var accelYLabel: NSTextField!
    @IBOutlet weak var accelZLabel: NSTextField!
    @IBOutlet weak var buttonCLabel: NSTextField!
    @IBOutlet weak var buttonZLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        service = WirekiteService()
        service?.delegate = self
        service?.start()
    }
    
    func connectedDevice(_ device: WirekiteDevice!) {
        self.device = device
        i2c = device.configureI2CMaster(.SCL19_SDA18, frequency: 100000)
        nunchuck = Nunchuck(device: device, i2cPort: i2c)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
            _ in self.updateData()
        }
    }
    
    func disconnectedDevice(_ device: WirekiteDevice!) {
        if self.device == device {
            self.device = nil
            nunchuck = nil
            timer?.invalidate()
            timer = nil
        }
    }
    
    func updateData() {
        if let nunchuck = nunchuck {
            nunchuck.readData()
            joyXLabel.stringValue = "\(nunchuck.joystickX)"
            joyYLabel.stringValue = "\(nunchuck.joystickY)"
            accelXLabel.stringValue = "\(nunchuck.accelerometerX)"
            accelYLabel.stringValue = "\(nunchuck.accelerometerY)"
            accelZLabel.stringValue = "\(nunchuck.accelerometerZ)"
            buttonCLabel.stringValue = nunchuck.cButton ? "Pressed" : "-"
            buttonZLabel.stringValue = nunchuck.zButton ? "Pressed" : "-"
        }
    }
}
