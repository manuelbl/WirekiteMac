//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Foundation
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
    private let releasePort: Bool
    private var isInitialized = false
    private var offset = 0
    
    /** I2C slave address */
    var displayAddress: UInt16 = 0x3C
    
    /** Display width (in pixel) */
    let Width = 128
    
    /** Display height (in pixel) */
    let Height = 64
    
    /**
        Horizontal display offset (in pixel)
     
        Use 0 for SH1306 chip, 2 for SH1106 chip.
    */
    var DisplayOffset = 0
    
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
            NSLog("OLED initialization failed")
            return
        }

        graphics = CGContext(data: nil, width: Width, height: Height, bitsPerComponent: 8, bytesPerRow: Width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    }
    
    func draw(offset: Int) {
        
        graphics!.setFillColor(CGColor.black)
        graphics!.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
        
        let gc = NSGraphicsContext(cgContext: graphics!, flipped: false)
        NSGraphicsContext.setCurrent(gc)
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
            initSensor()
            isInitialized = true
        }
        
        draw(offset: -offset)
        offset += 1
        if offset >= 448 {
            offset = 0
        }
        
        let data = graphics!.data
        let dataPtr = data!.bindMemory(to: UInt8.self, capacity: Width * Height)
        let dataBuffer = UnsafeBufferPointer(start: dataPtr, count: Width * Height)
        let pixels = OLEDDisplay.burkesDither(pixelData: [UInt8](dataBuffer), width: Width)
        
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
    }
    
    
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
    
    
    /**
        Apply ordered 8x8 dithering to the specified grayscale pixelmap.
     
        - parameter pixelData: grayscale pixelmap as an array of pixel bytes
     
        - parameter width: width of pixelmap
     
        - parameter randomOffset: random offset for x and y dithering pattern (specified 0 if not needed)
     
        - returns: dithered pixelmap with black (0) and white (255) pixels
     */
    static func orderedDither(pixelData: [UInt8], width: Int, randomOffset: Int) -> [UInt8] {
        let offset = Int(OrderedDitheringMatrix[randomOffset & 0x3f])
        let xOffset = offset & 0x07
        let yOffset = offset >> 3
        
        let height = pixelData.count / width
        var result = [UInt8](repeating: 0, count: width * height)
        var p = 0
        for y in 0 ..< height {
            let yi = (y + yOffset) & 0x7
            for x in 0 ..< width {
                let xi = (x + xOffset) & 0x7
                let r = OrderedDitheringMatrix[yi * 8 + xi] << 2
                result[p] = pixelData[p] > r ? 255 : 0
                p += 1
            }
        }
        
        return result
    }


    /**
        Apply Burke's dithering to the specified grayscale pixelmap.

        - parameter pixelData: grayscale pixelmap as an array of pixel bytes

        - parameter width: width of pixelmap

        - returns: dithered pixelmap with black (0) and white (255) pixels
     */
    static func burkesDither(pixelData: [UInt8], width: Int) -> [UInt8] {
        
        let height = pixelData.count / width
        var result = [UInt8](repeating: 0, count: width * height)
        var currLine = [Int](repeating: 0, count: width)
        var nextLine = currLine
        
        var p = 0
        for _ in 0 ..< height {
            currLine = nextLine
            nextLine = [Int](repeating: 0, count: width)
            for x in 0 ..< width {
                let gs = Int(pixelData[p]) + currLine[x] // target value
                let bw = gs >= 128 ? 255 : 0 // black/white value
                let err = gs - bw // error
                result[p] = UInt8(bw)
                p += 1
                
                // distribute error
                nextLine[x] += err >> 2
                if x > 0 {
                    nextLine[x - 1] += err >> 3
                }
                if x > 1 {
                    nextLine[x - 2] += err >> 4
                }
                if x < width - 1 {
                    currLine[x + 1] = err >> 2
                    nextLine[x + 1] = err >> 3
                }
                if x < width - 2 {
                    currLine[x + 2] = err >> 3
                    nextLine[x + 2] = err >> 4
                }
            }
        }
        
        return result
    }
}
