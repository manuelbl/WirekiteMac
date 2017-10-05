//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa

class Dither: NSObject {

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
                    currLine[x + 1] += err >> 2
                    nextLine[x + 1] += err >> 3
                }
                if x < width - 2 {
                    currLine[x + 2] += err >> 3
                    nextLine[x + 2] += err >> 4
                }
            }
        }
        
        return result
    }
}
