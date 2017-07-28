//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa

@IBDesignable
class AnalogStick : NSView {
    
    static let circleColor = NSColor.darkGray
    
    @IBInspectable var directionX: Double = 0 {
        didSet {
            needsDisplay = true
        }
    }
    
    @IBInspectable var directionY: Double = 0 {
        didSet {
            needsDisplay = true
        }
    }
    
    @IBInspectable var indicatorColor: NSColor = NSColor.black {
        didSet {
            needsDisplay = true
        }
    }
    
    
    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    //or customized constructor/ init
    init(frame frameRect: NSRect, otherInfo:Int) {
        super.init(frame:frameRect)
        // other code
    }
    
    override func draw(_ dirtyRect: NSRect) {
        
        let w = bounds.width
        let h = bounds.height
        let r = min(w, h) / 2

        let context = NSGraphicsContext.current()!.cgContext

        AnalogStick.circleColor.setStroke()
        context.setLineWidth(2)
        context.strokeEllipse(in: CGRect(x: w / 2 - r + 1, y: h / 2 - r + 1, width: r * 2 - 2, height: r * 2 - 2))
        
        indicatorColor.setStroke()
        context.setLineWidth(9)
        context.setLineCap(.round)
        
        let angle = atan2(directionX, directionY)
        let len = max(CGFloat(max(abs(directionX), abs(directionY))) * r - 7, 0)
        let center = CGPoint(x: bounds.origin.x + bounds.width / 2, y: bounds.origin.y + bounds.height / 2)
        let lineSegments: [CGPoint] = [
            center,
            CGPoint(x: CGFloat(sin(angle)) * len + center.x, y: CGFloat(cos(angle)) * len + center.y)
        ]
        context.strokeLineSegments(between: lineSegments)
    }
}
