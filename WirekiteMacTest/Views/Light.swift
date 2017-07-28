//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa

@IBDesignable
class Light : NSView {
    
    static let grayFraction: CGFloat = 0.8
    static let grayColor = NSColor.lightGray
    
    @IBInspectable var color: NSColor = NSColor.red {
        didSet {
            offColor = color.blended(withFraction: Light.grayFraction, of: Light.grayColor)!
            needsDisplay = true
        }
    }
    
    @IBInspectable var on: Bool = false {
        didSet {
            offColor = color.blended(withFraction: Light.grayFraction, of: Light.grayColor)!
            needsDisplay = true
        }
    }
    
    private var offColor: NSColor = NSColor.red.blended(withFraction: Light.grayFraction, of: Light.grayColor)!
    
    
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
        
        let w = frame.width
        let h = frame.height
        let r = min(w, h) / 2
        
        let context = NSGraphicsContext.current()!.cgContext
        (on ? color : offColor).setFill()
        context.fillEllipse(in: CGRect(x: w / 2 - r, y: h / 2 - r, width: r * 2, height: r * 2))
    }
}
