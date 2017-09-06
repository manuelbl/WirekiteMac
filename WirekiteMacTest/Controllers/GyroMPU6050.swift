//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Foundation

class GyroMPU6050 {
    
    private let device: WirekiteDevice?
    private let i2cPort: PortID
    private let releasePort: Bool
    
    var isCalibrating = false
    
    var gyroAddress: Int = 0x68
    
    private var gyroXOffset: Int = 0
    private var gyroYOffset: Int = 0
    private var gyroZOffset: Int = 0
    
    var gyroX: Int = 0
    var gyroY: Int = 0
    var gyroZ: Int = 0
    
    var temperature: Double = 0
    
    var accelX: Int = 0
    var accelY: Int = 0
    var accelZ: Int = 0
    
    
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
    
    private func initSensor() {
        set(register: 0x6b, value: 0x00)
        set(register: 0x1b, value: 0x00)
        set(register: 0x1c, value: 0x08)
        set(register: 0x1a, value: 0x03)
        startCalibration()
    }
    
    func read() {
        let data = readBytes(startRegister: 0x3B, numBytes: 14)
        accelX = Int((Int16(data[0]) << 8) | Int16(data[1]))
        accelY = Int((Int16(data[2]) << 8) | Int16(data[3]))
        accelZ = Int((Int16(data[4]) << 8) | Int16(data[5]))
        let t = (Int16(data[6]) << 8) | Int16(data[7])
        temperature = Double(t) / 340 + 36.53
        gyroX = Int((Int16(data[8]) << 8) | Int16(data[9])) + gyroXOffset
        gyroY = Int((Int16(data[10]) << 8) | Int16(data[11])) + gyroYOffset
        gyroZ = Int((Int16(data[12]) << 8) | Int16(data[13])) + gyroZOffset
    }
    
    private func set(register: UInt8, value: UInt8) {
        let bytes: [UInt8] = [ register, value ]
        let data = Data(bytes: bytes)
        let len = device!.send(onI2CPort: i2cPort, data: data, toSlave: gyroAddress)
        if Int(len) != data.count {
            NSLog("Failed to set gyro regoster")
        }
    }
    
    private func readBytes(startRegister: UInt8, numBytes: Int) -> [UInt8] {
        let bytes: [UInt8] = [ startRegister ]
        let txData = Data(bytes: bytes)
        let result = device!.sendAndRequest(onI2CPort: i2cPort, data: txData, toSlave: gyroAddress, receiveLength: numBytes)
        if result?.count != numBytes {
            NSLog("Failed to read gyro values")
            return []
        }
        
        return [UInt8](result!)
    }
    
    private func startCalibration() {
        isCalibrating = true
        DispatchQueue.global(qos: .background).async {
            self.calibrate()
            self.isCalibrating = false
        }
    }

    func calibrate() {
        var offsetX = 0
        var offsetY = 0
        var offsetZ = 0
        
        let numSamples = 500
        for _ in 0..<numSamples {
            let data = readBytes(startRegister: 0x43, numBytes: 6)
            offsetX += Int((Int16(data[0]) << 8) | Int16(data[1]))
            offsetY += Int((Int16(data[2]) << 8) | Int16(data[3]))
            offsetZ += Int((Int16(data[4]) << 8) | Int16(data[5]))
            Thread.sleep(forTimeInterval: 0.001)
        }
        
        gyroXOffset = -(offsetX + numSamples / 2) / numSamples
        gyroYOffset = -(offsetY + numSamples / 2) / numSamples
        gyroZOffset = -(offsetZ + numSamples / 2) / numSamples
    }
}
