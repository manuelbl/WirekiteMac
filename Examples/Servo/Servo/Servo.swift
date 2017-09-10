// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Foundation
import WirekiteMac

/**
    Controls a servo using pulses between about 0.5ms and 2.1ms.
 
    Configure the timer associated with the PWM pin for a frequency of 100Hz.
 */
class Servo {
    
    /** Pin number */
    var pin: Int = 0
    
    /** Configured PWM port ID */
    var port: PortID = 0
    
    /** Wirekite device */
    var device: WirekiteDevice
    
    /** Pulse width for 0 degree (in ms) */
    var pulseWidth0Deg = 0.54
    
    /** Pulse width for 180 degree (in ms) */
    var pulseWidth180Deg = 2.10
    
    /** Frequency of pulse width modulation */
    var frequency = 100.0
    
    
    init(device: WirekiteDevice, pin: Int) {
        self.device = device
        self.pin = pin
    }
    
    deinit {
        if port != 0 {
            device.releasePWMPin(onPort: port)
        }
    }
    
    func turnOn(initialAngle: Double) {
        if port == 0 {
            port = device.configurePWMOutputPin(pin, initialDutyCycle: dutyCycle(forAngle: initialAngle))
        }
    }
    
    func turnOff() {
        if port != 0 {
            device.releasePWMPin(onPort: port)
            port = 0
        }
    }
    
    private func dutyCycle(forAngle angle: Double) -> Double {
        let clampedAngle = angle < 0 ? 0 : (angle > 180 ? 180 : angle)
        let frequencyInt = Int(frequency + 0.5)
        let length_ms = clampedAngle / 180 * (pulseWidth180Deg - pulseWidth0Deg) + pulseWidth0Deg
        return length_ms / (1000 / Double(frequencyInt))
    }
    
    func move(toAngle angle: Double) {
        device.writePWMPin(onPort: port, dutyCycle: dutyCycle(forAngle: angle))
    }
}
