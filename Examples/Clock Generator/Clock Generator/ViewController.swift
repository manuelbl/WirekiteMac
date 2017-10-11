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
    var i2c: PortID = 0
    var clockGenerator: ClockGenerator? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        service = WirekiteService()
        service?.delegate = self
        service?.start()
    }
    
    func connectedDevice(_ device: WirekiteDevice!) {
        self.device = device
        i2c = device.configureI2CMaster(.SCL19_SDA18, frequency: 400000)
        clockGenerator = ClockGenerator(device: device, i2c: i2c)
        setupClockGenerator()
    }
    
    func disconnectedDevice(_ device: WirekiteDevice!) {
        if self.device == device {
            self.device = nil
            self.clockGenerator = nil
        }
    }
    
    func setupClockGenerator() {
        clockGenerator!.initDevice()
        
        // 75 MHz
        clockGenerator!.configure(pll: .A, integerMultiplier: 24)
        clockGenerator!.configure(multiSynthOutput: 0, pllSource: .A, integerDivider: .div8)
        
        // 13.553 MHz
        clockGenerator!.configure(pll: .B, multiplier: 24, numerator: 2, denominator: 3)
        clockGenerator!.configure(multiSynthOutput: 1, pllSource: .B, divider: 45, numerator: 1, denominator: 2)
        
        // 10.70 kHz
        clockGenerator!.configure(multiSynthOutput: 2, pllSource: .B, divider: 900, numerator: 0, denominator: 1)
        clockGenerator!.configure(rDividerOutput: 2, divider: .div64)
        
        clockGenerator!.setOutputs(enabled: true)
    }
}
