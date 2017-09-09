//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa
import WirekiteMac


class ViewController: NSViewController, WirekiteServiceDelegate {
    
    var service: WirekiteService? = nil
    var device: WirekiteDevice? = nil
    var timer: Timer? = nil
    var redLight: PortID = 0
    var orangeLight: PortID = 0
    var greenLight: PortID = 0
    var trafficLightPhase = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        service = WirekiteService()
        service?.delegate = self
        service?.start()
    }
    
    func connectedDevice(_ device: WirekiteDevice!) {
        self.device = device
        redLight = device.configureDigitalOutputPin(16, attributes: [ .highCurrent ], initialValue: false)
        orangeLight = device.configureDigitalOutputPin(17, attributes: [ .highCurrent ], initialValue: false)
        greenLight = device.configureDigitalOutputPin(21, attributes: [ .highCurrent ], initialValue: false)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            timer in self.swichTrafficLight()
        }
    }
    
    func disconnectedDevice(_ device: WirekiteDevice!) {
        if self.device == device {
            self.device = nil
            timer?.invalidate()
            timer = nil
        }
    }
    
    func swichTrafficLight() {
        device?.writeDigitalPin(onPort: redLight, value: trafficLightPhase <= 3)
        device?.writeDigitalPin(onPort: orangeLight, value: trafficLightPhase == 3 || trafficLightPhase == 6)
        device?.writeDigitalPin(onPort: greenLight, value: trafficLightPhase >= 4 && trafficLightPhase <= 5)
        
        trafficLightPhase += 1
        if trafficLightPhase == 7 {
            trafficLightPhase = 0
        }
    }
}

