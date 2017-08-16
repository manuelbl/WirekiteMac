//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Foundation


class OLEDSSH1106 {
    
    private static let SetContrast: UInt8 = 0x81
    private static let OutputRAMToDisplay: UInt8 = 0xA4
    private static let SetDisplayOn: UInt8 = 0xA5
    private static let SetNormalDisplay: UInt8 = 0xA6
    private static let SetInvertedDisplay: UInt8 = 0xA7
    private static let DisplayOff: UInt8 = 0xAE
    private static let DisplayOn: UInt8 = 0xAF
    
    private static let SetDisplayOffset: UInt8 = 0xD3
    private static let SetComPin: UInt8 = 0xDA
    
    private static let SetVCOMH: UInt8 = 0xDB
    
    private static let SetClockDivideRatio: UInt8 = 0xD5
    private static let SetPrecharge: UInt8 = 0xD9
    
    private static let SetMultiplexRatio: UInt8 = 0xA8
    
    private static let SETLOWCOLUMN: UInt8 = 0x00
    private static let SETHIGHCOLUMN: UInt8 = 0x10
    
    private static let SetStartLineBase: UInt8 = 0x40
    
    private static let PageAddressingMode: UInt8 = 0x20
    private static let COLUMNADDR: UInt8 = 0x21
    private static let PAGEADDR: UInt8 =   0x22
    
    private static let ScanDirectionIncreasing: UInt8 = 0xC0
    private static let ScanDirectionDecreasing: UInt8 = 0xC8
    
    private static let SegmentRampBase: UInt8 = 0xA0
    
    private static let ChargePump: UInt8 = 0x8D
    
    private static let EXTERNALVCC: UInt8 = 0x1
    private static let SWITCHCAPVCC: UInt8 = 0x2
    
    private static let ACTIVATE_SCROLL: UInt8 = 0x2F
    private static let DeactivateScroll: UInt8 = 0x2E
    private static let SET_VERTICAL_SCROLL_AREA: UInt8 = 0xA3
    private static let RIGHT_HORIZONTAL_SCROLL: UInt8 = 0x26
    private static let LEFT_HORIZONTAL_SCROLL: UInt8 = 0x27
    private static let VERTICAL_AND_RIGHT_HORIZONTAL_SCROLL: UInt8 = 0x29
    private static let VERTICAL_AND_LEFT_HORIZONTAL_SCROLL: UInt8 = 0x2A
    

    
    
    private let device: WirekiteDevice?
    private let i2cPort: PortID
    private let releasePort: Bool
    
    var displayAddress: UInt16 = 0x3C
    var width = 132
    var height = 64
    
    
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
        // Init sequence
        sendCommand(OLEDSSH1106.DisplayOff)
        
        sendCommand(OLEDSSH1106.SetClockDivideRatio, dataByte: 0x80)
        sendCommand(OLEDSSH1106.SetMultiplexRatio, dataByte: 0x3f)
        sendCommand(OLEDSSH1106.SetDisplayOffset, dataByte: 0x0)
        sendCommand(OLEDSSH1106.SetStartLineBase + 0)
        sendCommand(OLEDSSH1106.ChargePump, dataByte: 0x14)
        sendCommand(OLEDSSH1106.PageAddressingMode, dataByte: 0x00)
        sendCommand(OLEDSSH1106.SegmentRampBase + 0x1)
        sendCommand(OLEDSSH1106.ScanDirectionDecreasing)
        sendCommand(OLEDSSH1106.SetComPin, dataByte: 0x12)
        sendCommand(OLEDSSH1106.SetContrast, dataByte: 0xcf)
        sendCommand(OLEDSSH1106.SetPrecharge, dataByte: 0xF1)
        sendCommand(OLEDSSH1106.SetVCOMH, dataByte: 0x40)
        sendCommand(OLEDSSH1106.DeactivateScroll)
        sendCommand(OLEDSSH1106.OutputRAMToDisplay)
        sendCommand(OLEDSSH1106.SetInvertedDisplay)
        sendCommand(OLEDSSH1106.DisplayOn)
    }
    
    private func sendCommand(_ command: UInt8) {
        let bytes: [UInt8] = [ 0, command]
        let data = Data(bytes: bytes)
        let numSent = Int(device!.send(onI2CPort: i2cPort, data: data, toSlave: displayAddress))
        if numSent != data.count {
            NSLog("Sending command to OLED display failed")
        }
    }
    
    private func sendCommand(_ command: UInt8, dataByte: UInt8) {
        sendCommand(command)
        sendCommand(dataByte)
    }
    
}
