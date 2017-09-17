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
    var analogInput: PortID = 0
    var bandgapReference: PortID = 0
    var bandgap: Double = 1 / 3.3
    
    @IBOutlet weak var voltageLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        service = WirekiteService()
        service?.delegate = self
        service?.start()
    }
    
    func connectedDevice(_ device: WirekiteDevice!) {
        self.device = device
        device.configureAnalogInputPin(.A1, interval: 100) {
            _, value in self.received(sample: value)
        }
        device.configureAnalogInputPin(.bandGap, interval: 990) {
            _, value in self.bandgap = value
        }
    }
    
    func disconnectedDevice(_ device: WirekiteDevice!) {
        if self.device == device {
            self.device = nil
        }
    }
    
    func received(sample value: Double) {
        let text = String(format: "%4.3f V", value / bandgap)
        voltageLabel.stringValue = text
    }
}
