//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import CoreFoundation
import Cocoa


/**
    OLED display with SH1306 or SH1106 chip and I2C communication.
 */
class OLEDDisplay {
    
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
    private static let SetColumnAddressLow: UInt8 = 0x00
    private static let SetColumnAddressHigh: UInt8 = 0x10
    private static let SetPageAddress: UInt8 = 0xb0
    private static let SetStartLineBase: UInt8 = 0x40
    private static let PageAddressingMode: UInt8 = 0x20
    private static let ScanDirectionIncreasing: UInt8 = 0xC0
    private static let ScanDirectionDecreasing: UInt8 = 0xC8
    private static let SegmentRampBase: UInt8 = 0xA0
    private static let ChargePump: UInt8 = 0x8D
    private static let DeactivateScroll: UInt8 = 0x2E
    
    private let device: WirekiteDevice?
    private let i2cPort: PortID
    private var isInitialized = false
    private var offset = 0
    
    /** I2C slave address */
    var displayAddress: Int = 0x3C
    
    /** Display width (in pixel) */
    let Width = 128
    
    /** Display height (in pixel) */
    let Height = 64
    
    /**
        Horizontal display offset (in pixel)
     
        Use 0 for SH1306 chip, 2 for SH1106 chip.
    */
    var DisplayOffset = 0
    
    private var graphics: GraphicsBuffer?
    
    
    init(device: WirekiteDevice, i2cPort: PortID) {
        self.device = device
        self.i2cPort = i2cPort
    }
    
    private func initSensor(retries: Int) {
        // Init sequence
        let initSequence: [UInt8] = [
            0x80, OLEDDisplay.DisplayOff,
            0x80, OLEDDisplay.SetClockDivideRatio, 0x80, 0x80,
            0x80, OLEDDisplay.SetMultiplexRatio, 0x80, 0x3f,
            0x80, OLEDDisplay.SetDisplayOffset, 0x80, 0x0,
            0x80, OLEDDisplay.SetStartLineBase + 0,
            0x80, OLEDDisplay.ChargePump, 0x80, 0x14,
            0x80, OLEDDisplay.PageAddressingMode, 0x80, 0x00,
            0x80, OLEDDisplay.SegmentRampBase + 0x1,
            0x80, OLEDDisplay.ScanDirectionDecreasing,
            0x80, OLEDDisplay.SetComPin, 0x80, 0x12,
            0x80, OLEDDisplay.SetContrast, 0x80, 0xcf,
            0x80, OLEDDisplay.SetPrecharge, 0x80, 0xF1,
            0x80, OLEDDisplay.SetVCOMH, 0x80, 0x40,
            0x80, OLEDDisplay.DeactivateScroll,
            0x80, OLEDDisplay.OutputRAMToDisplay,
            0x80, OLEDDisplay.SetNormalDisplay,
            0x80, OLEDDisplay.DisplayOn
        ]
        let initSequenceData = Data(bytes: initSequence)
        let numBytesSent = device!.send(onI2CPort: i2cPort, data: initSequenceData, toSlave: displayAddress)
        if Int(numBytesSent) != initSequenceData.count {
            let result = device!.lastResult(onI2CPort: i2cPort)
            if result == .busBusy && retries > 0 {
                NSLog("OLED initialization: bus busy")
                device!.resetBus(onI2CPort: i2cPort)
                if device!.lastResult(onI2CPort: i2cPort) != .OK {
                    NSLog("Resetting bus failed")
                }
                initSensor(retries: retries - 1)
            } else {
                NSLog("OLED initialization failed: \(result.rawValue)")
            }
            return
        }

        graphics = GraphicsBuffer(width: Width, height: Height, isColor: false)
    }
    
    func draw(offset: Int) {
        
        let gc = graphics!.prepareForDrawing()
        
        gc.setFillColor(CGColor.black)
        gc.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
        
        let ngc = NSGraphicsContext(cgContext: gc, flipped: false)
        NSGraphicsContext.setCurrent(ngc)
        let font = NSFont(name: "Helvetica", size: 64)!
        let attr: [String: Any] = [
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: NSColor.white
        ]

        let s = "😱✌️🎃🐢☠️😨💩😱✌️" as NSString
        s.draw(at: NSMakePoint(CGFloat(offset), -10), withAttributes: attr)
    }
    
    func showTile() {
        
        if !isInitialized {
            initSensor(retries: 1)
            isInitialized = true
        }
        
        draw(offset: -offset)
        offset += 1
        if offset >= 448 {
            offset = 0
        }
        
        let pixels = graphics!.finishDrawing(format: .blackAndWhiteDithered)
        
        var tile = [UInt8](repeating: 0, count: Width + 7)

        for page in 0 ..< 8 {
            
            tile[0] = 0x80
            tile[1] = OLEDDisplay.SetPageAddress + UInt8(page)
            tile[2] = 0x80
            tile[3] = OLEDDisplay.SetColumnAddressLow | UInt8(DisplayOffset & 0x0f)
            tile[4] = 0x80
            tile[5] = OLEDDisplay.SetColumnAddressHigh | UInt8((DisplayOffset >> 4) & 0x0f)
            tile[6] = 0x40

            let index = page * 8 * Width
            for i in 0 ..< Width {
                
                var byte = 0
                var bit = 1
                var p = index + i
                for _ in 0 ..< 8 {
                    if pixels[p] != 0 {
                        byte |= bit
                    }
                    bit <<= 1
                    p += Width
                }
                
                tile[i + 7] = UInt8(byte)
            }
            let data = Data(bytes: tile)
            device!.submit(onI2CPort: i2cPort, data: data, toSlave: displayAddress)
        }
        
        /*
        // Just for the fun of it: read back some of the data
        // It's unclear why the data is offset by 1 pixel and the first byte is garbage
        let cmd: [UInt8] = [
            0x80, OLEDDisplay.SetPageAddress + UInt8(7),
            0x80, OLEDDisplay.SetColumnAddressLow | UInt8((DisplayOffset + 1) & 0x0f),
            0x80, OLEDDisplay.SetColumnAddressHigh | UInt8(((DisplayOffset + 1) >> 4) & 0x0f),
            0x40
        ]
        let cmdData = Data(bytes: cmd)
        let response = device!.sendAndRequest(onI2CPort: i2cPort, data: cmdData, toSlave: displayAddress, receiveLength: Width)!
        let responseBytes = [UInt8](response)
        
        // compare data
        for i in 1 ..< Width {
            assert(tile[i + 7] == responseBytes[i])
        }
        */
    }
    
    
}
