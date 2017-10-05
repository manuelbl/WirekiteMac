//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import CoreFoundation
import Cocoa

class EPaper: NSObject {
    
    private static let DriverOutputControl: UInt8 = 0x01
    private static let BoosterSoftStartControl: UInt8 = 0x0C
    private static let WriteVCOMRegister: UInt8 = 0x11
    private static let SetDummyLinePeriod: UInt8 = 0x3A
    private static let SetGateTime: UInt8 = 0x3B
    private static let DataEntryModeSetting: UInt8 = 0x11
    private static let WriteLUTRegister: UInt8 = 0x32
    private static let WriteRAM: UInt8 = 0x24
    private static let MasterActivation: UInt8 = 0x20
    private static let DisplayUpdateControl1: UInt8 = 0x21
    private static let DisplayUpdateControl2: UInt8 = 0x22
    private static let TerminateFrameReadWrite: UInt8 = 0xff
    private static let SetRAMXAddressStartEndPosition: UInt8 = 0x44
    private static let SetRAMYAddressStartEndPosition: UInt8 = 0x45
    private static let SetRAMXAddressCounter: UInt8 = 0x4E
    private static let SetRAMYAddressCounter: UInt8 = 0x4F

    static let LUTFullUpdate: [UInt8] = [
        0x02, 0x02, 0x01, 0x11, 0x12, 0x12, 0x22, 0x22,
        0x66, 0x69, 0x69, 0x59, 0x58, 0x99, 0x99, 0x88,
        0x00, 0x00, 0x00, 0x00, 0xF8, 0xB4, 0x13, 0x51,
        0x35, 0x51, 0x51, 0x19, 0x01, 0x00
    ]
    
    static let LUTPartialUpdate: [UInt8] = [
        0x10, 0x18, 0x18, 0x08, 0x18, 0x18, 0x08, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x13, 0x14, 0x44, 0x12,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]
    
    var Width = 200
    var Height = 200
    
    private var device: WirekiteDevice?
    private var spi: PortID
    
    private var csPort: PortID
    private var dcPort: PortID
    private var busyPort: PortID
    private var resetPort: PortID
    
    private var graphics: CGContext?

    init(device: WirekiteDevice, spiPort: PortID, csPin: Int, dcPin: Int, busyPin: Int, resetPin: Int) {
        self.device = device
        self.spi = spiPort

        csPort = device.configureDigitalOutputPin(csPin, attributes: [], initialValue: true)
        dcPort = device.configureDigitalOutputPin(dcPin, attributes: [], initialValue: true)
        resetPort = device.configureDigitalOutputPin(resetPin, attributes: [], initialValue: true)
        busyPort = device.configureDigitalInputPin(busyPin, attributes: [], communication: .precached)
    }
    
    deinit {
        device?.releaseDigitalPin(onPort: csPort)
        device?.releaseDigitalPin(onPort: dcPort)
        device?.releaseDigitalPin(onPort: resetPort)
        device?.releaseDigitalPin(onPort: busyPort)
    }
    
    func initDevice() {
        graphics = CGContext(data: nil, width: Width, height: Height, bitsPerComponent: 8, bytesPerRow: Width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)

        reset()
        
        sendCommand(EPaper.DriverOutputControl, data: [ UInt8((Height - 1) & 0xff), UInt8(((Height - 1) >> 8) & 0xff), 0 ])
        sendCommand(EPaper.BoosterSoftStartControl, data: [ 0xd7, 0xd6, 0x9d ])
        sendCommand(EPaper.WriteVCOMRegister, data: [ 0xa8 ])
        sendCommand(EPaper.SetDummyLinePeriod, data: [ 0x1a ])
        sendCommand(EPaper.SetGateTime, data: [ 0x08 ])
        sendCommand(EPaper.DataEntryModeSetting, data: [ 0x03 ])
        
        sendCommand(EPaper.WriteLUTRegister, data: EPaper.LUTFullUpdate)
    }
    
    func prepareForDrawing() -> CGContext {
        let gc = NSGraphicsContext(cgContext: graphics!, flipped: false)
        NSGraphicsContext.setCurrent(gc)
        return graphics!
    }
    
    func finishDrawing(shouldDither: Bool) {
        let data = graphics!.data
        let dataPtr = data!.bindMemory(to: UInt8.self, capacity: Width * Height)
        let dataBuffer = UnsafeBufferPointer(start: dataPtr, count: Width * Height)
        let pixels: [UInt8]
        if shouldDither {
            pixels = Dither.burkesDither(pixelData: [UInt8](dataBuffer), width: Width)
        } else {
            pixels = [UInt8](dataBuffer)
        }

        let stride = Width / 8
        var buf = [UInt8](repeating: 0xff, count: Height * stride)
        var srow = 0
        var t = 0
        for _ in 0 ..< Height {
            var s = srow
            for _ in 0 ..< stride {
                var byte: UInt8 = 0
                for _ in 0 ..< 8 {
                    byte <<= 1
                    if pixels[s] != 0 {
                        byte |= 1
                    }
                    s += 1
                }
                buf[t] = byte
                t += 1
            }
            srow += Width
        }

        setMemoryArea(x: 0, y: 0, width: Width - 1, height: Height - 1)
        setMemoryPointer(x: 0, y: 0)
        sendCommand(EPaper.WriteRAM, data: buf)
        displayFrame()
    }
    
    private func reset() {
        device!.writeDigitalPin(onPort: resetPort, value: false)
        Thread.sleep(forTimeInterval: 0.2)
        device!.writeDigitalPin(onPort: resetPort, value: true)
        Thread.sleep(forTimeInterval: 0.2)
    }
    
    private func waitUntilIdle() {
        while (device!.readDigitalPin(onPort: busyPort)) {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
    
    private func clearFrameMemory() {
        setMemoryArea(x: 0, y: 0, width: Width - 1, height: Height - 1)
        setMemoryPointer(x: 0, y: 0)
        sendCommand(EPaper.WriteRAM, data: [UInt8](repeating: 0xff, count: Width * Height / 8))
    }
    
    private func displayFrame() {
        sendCommand(EPaper.DisplayUpdateControl2, data: [ 0xC4 ])
        sendCommand(EPaper.MasterActivation, data: [])
        sendCommand(EPaper.TerminateFrameReadWrite, data: [])
        waitUntilIdle()
    }
    
    private func setMemoryArea(x: Int, y: Int, width: Int, height: Int) {
        sendCommand(EPaper.SetRAMXAddressStartEndPosition, data: [ UInt8((x >> 3) & 0xff), UInt8(((x + width) >> 3) & 0xff) ])
        sendCommand(EPaper.SetRAMYAddressStartEndPosition, data: [
            UInt8(y & 0xff), UInt8((y >> 8) & 0xff),
            UInt8((y + height) & 0xff), UInt8(((y + height) >> 8) & 0xff),
        ])
    }
    
    private func setMemoryPointer(x: Int, y: Int) {
        sendCommand(EPaper.SetRAMXAddressCounter, data: [ UInt8((x >> 3) & 0xff) ])
        sendCommand(EPaper.SetRAMYAddressCounter, data: [ UInt8(y & 0xff), UInt8((y >> 8) & 0xff) ])
        waitUntilIdle()
    }
    
    private func sendCommand(_ command: UInt8, data: [UInt8]) {
        // select command mode
        device!.writeDigitalPin(onPort: dcPort, value: false)
        
        let commandData = Data(bytes: [ command ])
        guard device!.transmit(onSPIPort: spi, data: commandData, chipSelect: csPort) == 1 else {
            NSLog("EPaper: Transmitting command byte failed")
            return
        }
        
        // select data mode
        device!.writeDigitalPin(onPort: dcPort, value: true)

        if (data.count > 0) {
            let commandLoad = Data(bytes: data)
            guard device!.transmit(onSPIPort: spi, data: commandLoad, chipSelect: csPort) == commandLoad.count else {
                NSLog("EPaper: Transmitting command data failed")
                return
            }
        }
    }
}
