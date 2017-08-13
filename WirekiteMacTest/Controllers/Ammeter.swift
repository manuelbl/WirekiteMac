//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Foundation

class Ammeter {
    
    private static let InvalidValue = 0x7fffffff
    
    private let device: WirekiteDevice?
    private let i2cPort: PortID
    private let releasePort: Bool
    var ammeterAddress: UInt16 = 0x40
    
    init(device: WirekiteDevice, i2cPins: I2CPins) {
        self.device = device
        i2cPort = device.configureI2CMaster(i2cPins, frequency: 100000)
        releasePort = true
        initSensor()
    }
    
    init(device: WirekiteDevice, i2cPort: PortID) {
        self.device = device
        self.i2cPort = i2cPort
        releasePort = false
        initSensor()
    }
    
    deinit {
        if releasePort {
            device?.releaseI2CPort(i2cPort)
        }
    }

    func readAmps() -> Double {
        let value = read(register: 4, length: 2)
        if value == Ammeter.InvalidValue {
            return Double.nan
        }
        
        return Double(value) / 10
    }
    
    private func initSensor() {
        write(register: 5, value: 4096)
        write(register: 0, value: 0x2000 | 0x1800 | 0x04000 | 0x0018 | 0x0007)
    }

    private func write(register: Int, value: Int) {
        var bytes: [UInt8] = [ UInt8(register), 0, 0 ]
        bytes[1] = UInt8((value >> 8) & 0xff)
        bytes[2] = UInt8(value & 0xff)
        let data = Data(bytes: bytes)
        device?.send(onI2CPort: i2cPort, data: data, toSlave: ammeterAddress)
    }
    
    
    private func read(register: Int, length: Int) -> Int {
        let bytes: [UInt8] = [ UInt8(register) ]
        let data = Data(bytes: bytes)
        device?.send(onI2CPort: i2cPort, data: data, toSlave: ammeterAddress)
        
        if let data = device?.requetData(onI2CPort: i2cPort, fromSlave: ammeterAddress, length: 2) {
            let bytes = [UInt8](data)
            return Int((Int16(bytes[0]) << 8) | Int16(bytes[1]))
        }
        return Ammeter.InvalidValue
    }
}
