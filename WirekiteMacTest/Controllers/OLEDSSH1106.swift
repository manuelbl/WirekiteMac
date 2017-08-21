//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Foundation
import Cocoa


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
    
    private static let OrderedDitheringMatrix: [UInt8] = [
         0, 48, 12, 60,  3, 51, 15, 63,
        32, 16, 44, 28, 35, 19, 47, 31,
         8, 56,  4, 52, 11, 59,  7, 55,
        40, 24, 36, 20, 43, 27, 39, 23,
         2, 50, 14, 62,  1, 49, 13, 61,
        34, 18, 46, 30, 33, 17, 45, 29,
        10, 58,  6, 54,  9, 57,  5, 53,
        42, 26, 38, 22, 41, 25, 37, 21
    ]
    
    
    private let device: WirekiteDevice?
    private let i2cPort: PortID
    private let releasePort: Bool
    private var isInitialized = false
    private var xOffset = 0
    private var yOffset = 0
    
    var displayAddress: UInt16 = 0x3C
    let Width = 128
    let Height = 64
    
    private var graphics: CGContext?
    
    
    init(device: WirekiteDevice, i2cPins: I2CPins) {
        self.device = device
        i2cPort = device.configureI2CMaster(i2cPins, frequency: 400000)
        releasePort = true
    }
    
    init(device: WirekiteDevice, i2cPort: PortID) {
        self.device = device
        self.i2cPort = i2cPort
        releasePort = false
    }
    
    deinit {
        if releasePort {
            device?.releaseI2CPort(i2cPort)
        }
    }
    
    private func initSensor() {
        // Init sequence
        let initSequence: [UInt8] = [
            0x80, OLEDSSH1106.DisplayOff,
            0x80, OLEDSSH1106.SetClockDivideRatio, 0x80, 0x80,
            0x80, OLEDSSH1106.SetMultiplexRatio, 0x80, 0x3f,
            0x80, OLEDSSH1106.SetDisplayOffset, 0x80, 0x0,
            0x80, OLEDSSH1106.SetStartLineBase + 0,
            0x80, OLEDSSH1106.ChargePump, 0x80, 0x14,
            0x80, OLEDSSH1106.PageAddressingMode, 0x80, 0x00,
            0x80, OLEDSSH1106.SegmentRampBase + 0x1,
            0x80, OLEDSSH1106.ScanDirectionDecreasing,
            0x80, OLEDSSH1106.SetComPin, 0x80, 0x12,
            0x80, OLEDSSH1106.SetContrast, 0x80, 0xcf,
            0x80, OLEDSSH1106.SetPrecharge, 0x80, 0xF1,
            0x80, OLEDSSH1106.SetVCOMH, 0x80, 0x40,
            0x80, OLEDSSH1106.DeactivateScroll,
            0x80, OLEDSSH1106.OutputRAMToDisplay,
            0x80, OLEDSSH1106.SetNormalDisplay,
            0x80, OLEDSSH1106.DisplayOn
        ]
        let initSequenceData = Data(bytes: initSequence)
        let numBytesSent = device!.send(onI2CPort: i2cPort, data: initSequenceData, toSlave: displayAddress)
        if Int(numBytesSent) != initSequenceData.count {
            NSLog("OLED initialization failed")
            return
        }
    
        graphics = CGContext(data: nil, width: Width, height: Height, bitsPerComponent: 8, bytesPerRow: Width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        let gc = NSGraphicsContext(cgContext: graphics!, flipped: false)
        NSGraphicsContext.setCurrent(gc)
        let font = NSFont(name: "Helvetica", size: 64)!
        let attr: [String: Any] = [
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: NSColor.white
        ]

        let s = "😱😨" as NSString
        s.draw(at: NSMakePoint(0, -10), withAttributes: attr)
    }
    
    func showTile() {
        
        if !isInitialized {
            initSensor()
            isInitialized = true
        }
        
        
        let data = graphics!.data
        let dataPtr = data!.bindMemory(to: UInt8.self, capacity: Width * Height)
        let dataBuffer = UnsafeBufferPointer(start: dataPtr, count: Width * Height)
        let pixels = dither(pixelData: [UInt8](dataBuffer), width: Width)
        
        let startTime = DispatchTime.now()

        var tile = [UInt8](repeating: 0, count: Width + 7)

        for page in 0 ..< 8 {
            
            tile[0] = 0x80
            tile[1] = OLEDSSH1106.SetPageAddress + UInt8(page)
            tile[2] = 0x80
            tile[3] = OLEDSSH1106.SetColumnAddressLow | UInt8(2 & 0x0f)
            tile[4] = 0x80
            tile[5] = OLEDSSH1106.SetColumnAddressHigh | UInt8((2 >> 4) & 0x0f)
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
            let numSent = Int(device!.send(onI2CPort: i2cPort, data: data, toSlave: displayAddress))
            if numSent != data.count {
                NSLog("Sending command to OLED display failed")
            }
        }
        
        let endTime = DispatchTime.now()
        let elapsed = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        NSLog("Elapsed: \(elapsed)")
    }
    
    private func dither(pixelData: [UInt8], width: Int) -> [UInt8] {
        let height = pixelData.count / width
        var result = [UInt8](repeating: 0, count: width * height)
        var p = 0
        for y in 0 ..< height {
            let yi = (y + yOffset) & 0x7
            for x in 0 ..< width {
                let xi = (x + xOffset) & 0x7
                let r = OLEDSSH1106.OrderedDitheringMatrix[yi * 8 + xi] << 2
                result[p] = pixelData[p] > r ? 1 : 0
                p += 1
            }
        }
        
        xOffset = (xOffset + 3) & 7
        yOffset = (xOffset + 5) & 7
        
        return result
    }
}
