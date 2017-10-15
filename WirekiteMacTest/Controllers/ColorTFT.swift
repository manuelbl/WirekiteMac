//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import CoreFoundation
import Cocoa

class ColorTFT: NSObject {
    
    private static let NOP: UInt8 =     0x00
    private static let SWRESET: UInt8 = 0x01
    private static let RDDID: UInt8 =   0x04
    private static let RDDST: UInt8 =   0x09

    private static let SLPIN: UInt8 =   0x10
    private static let SLPOUT: UInt8 =  0x11
    private static let PTLON: UInt8 =   0x12
    private static let NORON: UInt8 =   0x13

    private static let INVOFF: UInt8 =  0x20
    private static let INVON: UInt8 =   0x21
    private static let DISPOFF: UInt8 = 0x28
    private static let DISPON: UInt8 =  0x29
    private static let CASET: UInt8 =   0x2A
    private static let RASET: UInt8 =   0x2B
    private static let RAMWR: UInt8 =   0x2C
    private static let RAMRD: UInt8 =   0x2E

    private static let PTLAR: UInt8 =   0x30
    private static let COLMOD: UInt8 =  0x3A
    private static let MADCTL: UInt8 =  0x36

    private static let FRMCTR1: UInt8 = 0xB1
    private static let FRMCTR2: UInt8 = 0xB2
    private static let FRMCTR3: UInt8 = 0xB3
    private static let INVCTR: UInt8 =  0xB4
    private static let DISSET5: UInt8 = 0xB6

    private static let PWCTR1: UInt8 =  0xC0
    private static let PWCTR2: UInt8 =  0xC1
    private static let PWCTR3: UInt8 =  0xC2
    private static let PWCTR4: UInt8 =  0xC3
    private static let PWCTR5: UInt8 =  0xC4
    private static let VMCTR1: UInt8 =  0xC5

    private static let RDID1: UInt8 =   0xDA
    private static let RDID2: UInt8 =   0xDB
    private static let RDID3: UInt8 =   0xDC
    private static let RDID4: UInt8 =   0xDD

    private static let PWCTR6: UInt8 =  0xFC

    private static let GMCTRP1: UInt8 = 0xE0
    private static let GMCTRN1: UInt8 = 0xE1
 
    
    var Width = 160
    var Height = 128
    
    private var device: WirekiteDevice?
    private var spi: PortID
    
    private var csPort: PortID
    private var dcPort: PortID
    private var resetPort: PortID
    
    private var graphics: GraphicsBuffer?
    
    init(device: WirekiteDevice, spiPort: PortID, csPin: Int, dcPin: Int, resetPin: Int) {
        self.device = device
        self.spi = spiPort
        
        csPort = device.configureDigitalOutputPin(csPin, attributes: [], initialValue: true)
        dcPort = device.configureDigitalOutputPin(dcPin, attributes: [], initialValue: true)
        resetPort = device.configureDigitalOutputPin(resetPin, attributes: [], initialValue: true)
    }
    
    deinit {
        device?.releaseDigitalPin(onPort: csPort)
        device?.releaseDigitalPin(onPort: dcPort)
        device?.releaseDigitalPin(onPort: resetPort)
    }
    
    func initDevice() {
        graphics = GraphicsBuffer(width: Width, height: Height, isColor: true)
        
        reset()

        sendCommand(ColorTFT.SWRESET, data: [ ])
        Thread.sleep(forTimeInterval: 0.15)
        sendCommand(ColorTFT.SLPOUT, data: [ ])
        Thread.sleep(forTimeInterval: 0.5)

        sendCommand(ColorTFT.FRMCTR1, data: [ 0x01, 0x2C, 0x2D ])
        sendCommand(ColorTFT.FRMCTR2, data: [ 0x01, 0x2C, 0x2D ])
        sendCommand(ColorTFT.FRMCTR3, data: [ 0x01, 0x2C, 0x2D, 0x01, 0x2C, 0x2D ])
        sendCommand(ColorTFT.INVCTR, data: [ 0x07 ])
        sendCommand(ColorTFT.PWCTR1, data: [ 0xA2, 0x02, 0x84 ])
        sendCommand(ColorTFT.PWCTR2, data: [ 0xC5 ])
        sendCommand(ColorTFT.PWCTR3, data: [ 0x0A, 0x00 ])
        sendCommand(ColorTFT.PWCTR4, data: [ 0x8A, 0x2A ])
        sendCommand(ColorTFT.PWCTR5, data: [ 0x8A, 0xEE ])
        sendCommand(ColorTFT.VMCTR1, data: [ 0x0E ])
        sendCommand(ColorTFT.INVOFF, data: [ ])
        sendCommand(ColorTFT.MADCTL, data: [ 0xC8 ])
        sendCommand(ColorTFT.COLMOD, data: [ 0x05 ])
        
        sendCommand(ColorTFT.CASET, data: [ 0x00, 0x00, 0x00, 0x7F ])
        sendCommand(ColorTFT.RASET, data: [ 0x00, 0x00, 0x00, 0x9F ])

        sendCommand(ColorTFT.GMCTRP1, data: [ 0x00, 0x00, 0x00, 0x9F ])
        sendCommand(ColorTFT.GMCTRN1, data: [ 0x00, 0x00, 0x00, 0x9F ])
        sendCommand(ColorTFT.NORON, data: [ ])
        Thread.sleep(forTimeInterval: 0.01)
        sendCommand(ColorTFT.DISPON, data: [ ])
        Thread.sleep(forTimeInterval: 0.1)
        
        sendCommand(ColorTFT.MADCTL, data: [ 0xC0 ])
    }
    
    func prepareForDrawing() -> CGContext {
        return graphics!.prepareForDrawing()
    }
    
    func finishDrawing() {
        var pixels = graphics!.finishDrawing(format: .rgb565Rotated90)
        
        // swap pairs of bytes
        let len = pixels.count
        var p = 0
        while p < len {
            let t = pixels[p]
            pixels[p] = pixels[p + 1]
            pixels[p + 1] = t
            p += 2
        }
        
//        DispatchQueue.global(qos: .userInteractive).async {
            self.setAddressWindow(x: 0, y: 0, w: self.Height, h: self.Width)
            self.sendCommand(ColorTFT.RAMWR, data: pixels)
//        }
    }
    
    private func reset() {
        device!.writeDigitalPin(onPort: resetPort, value: true)
        device!.writeDigitalPin(onPort: csPort, value: false)
        Thread.sleep(forTimeInterval: 0.5)
        device!.writeDigitalPin(onPort: resetPort, value: false)
        Thread.sleep(forTimeInterval: 0.5)
        device!.writeDigitalPin(onPort: resetPort, value: true)
        Thread.sleep(forTimeInterval: 0.5)
        device!.writeDigitalPin(onPort: csPort, value: true)
    }
    
    private func setAddressWindow(x: Int, y: Int, w: Int, h: Int) {
        sendCommand(ColorTFT.CASET, data: [ 0x00, UInt8(x), 0x00, UInt8(x + w - 1) ])
        sendCommand(ColorTFT.RASET, data: [ 0x00, UInt8(y), 0x00, UInt8(y + h - 1) ])
    }
    
    private func sendCommand(_ command: UInt8, data: [UInt8]) {
        
        // select command mode
        device!.writeDigitalPin(onPort: dcPort, value: false, synchronizedWithSPIPort: spi)
        
        let commandData = Data(bytes: [ command ])
        device!.submit(onSPIPort: spi, data: commandData, chipSelect: csPort)
        
        // select data mode
        device!.writeDigitalPin(onPort: dcPort, value: true, synchronizedWithSPIPort: spi)
        
        if data.count == 0 {
            return
        }
        
        var offset = 0
        while offset < data.count {
            let end = min(offset + 2048, data.count)
            let commandLoad = Data(bytes: data[offset ..< end])
            device!.submit(onSPIPort: spi, data: commandLoad, chipSelect: csPort)
            offset = end
        }
    }
}

