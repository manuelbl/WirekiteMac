// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Foundation
import WirekiteMac

class Nunchuck {
    
    var device: WirekiteDevice?
    var i2cPort: PortID = 0
    var slaveAddress = 0x52
    
    var joystickX = 0
    var joystickY = 0
    var accelerometerX = 0
    var accelerometerY = 0
    var accelerometerZ = 0
    var cButton = false
    var zButton = false
    
    
    init(device: WirekiteDevice, i2cPort: PortID) {
        self.device = device
        self.i2cPort = i2cPort;
        initController()
        readData()
    }
    
    func readData() {
        let senssorData = device!.requestData(onI2CPort: i2cPort, fromSlave: slaveAddress, length: 6)
        if senssorData == nil || senssorData!.count != 6 {
            let result = device!.lastResult(onI2CPort: i2cPort).rawValue
            NSLog("nunchuck read failed - reason \(result)")
            return
        }
        
        var sensorBytes = [UInt8](senssorData!)
        
        joystickX = Int(sensorBytes[0])
        joystickY = Int(sensorBytes[1])
        accelerometerX = (Int(sensorBytes[2]) << 2) | Int((sensorBytes[5] >> 2) & 0x3)
        accelerometerY = (Int(sensorBytes[3]) << 2) | Int((sensorBytes[5] >> 4) & 0x3)
        accelerometerZ = (Int(sensorBytes[4]) << 2) | Int((sensorBytes[5] >> 6) & 0x3)
        cButton = (sensorBytes[5] & 2) == 0
        zButton = (sensorBytes[5] & 1) == 0

        // prepare next data read (convert command)
        let cmdBytes: [UInt8] = [ 0 ]
        let cmdData = Data(bytes: cmdBytes)
        device!.submit(onI2CPort: i2cPort, data: cmdData, toSlave: slaveAddress)
    }
    
    func initController() {
        let initSequenceBytes: [[UInt8]] = [
            [ 0xf0, 0x55 ],
            [ 0xfb, 0x00 ]
        ]
        
        for bytes in initSequenceBytes {
            let data = Data(bytes: bytes)
            let numBytes = device!.send(onI2CPort: i2cPort, data: data, toSlave: slaveAddress)
            if numBytes != bytes.count {
                let result = device!.lastResult(onI2CPort: i2cPort).rawValue
                NSLog("nunchuck init seq failed - reason \(result)")
                return
            }
        }
    }
}
