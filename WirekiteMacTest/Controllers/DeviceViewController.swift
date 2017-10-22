//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa

class DeviceViewController: NSViewController {
    
    // Configure attached test board
    static let hasBuiltInLED = true
    static let hasThreeLEDs = false
    static let hasPushButton = false
    static let hasTwoPotentiometers = false
    static let hasServo = false
    static let hasAnalogStick = false
    static let hasAmmeter = false
    static let hasOLED = false
    static let hasGyro = false
    static let hasEPaper = false
    static let hasColorTFT = true

    static let indicatorColorNormal = NSColor.black
    static let indicatorColorPressed = NSColor.orange
    static let indicatorColorInactive = NSColor.lightGray

    
    var device: WirekiteDevice? = nil
    
    // built-in LED
    var ledTimer: Timer? = nil
    var ledPortId: PortID = 0
    var ledOn = true
    
    // three LEDs
    var redLedPin: PortID = 0
    var orangeLedPin: PortID = 0
    var greenLedPin: PortID = 0
    
    // push button
    var pushButtonPin: PortID = 0
    
    // two potentiometers
    var dutyCyclePin: PortID = 0
    var frequencyPin: PortID = 0
    var pwmOutPin: PortID = 0
    var prevFrequencyValue: Double = 3000
    
    // analog stick
    var voltageXPin: PortID = 0
    var voltageYPin: PortID = 0
    var stickPushButtonPin: PortID = 0

    // servo
    var servoTimer: Timer? = nil
    var servo: Servo? = nil
    var servoPos: Double = 0
    
    // I2C bus
    var i2cPort: PortID = 0
    
    // ammeter
    var ammeter: Ammeter? = nil
    var ammeterTimer: Timer? = nil
    
    // OLED display
    var display: OLEDDisplay? = nil
    var displayTimer: Timer? = nil
    
    // Gyro / accelerometer
    var gyro: GyroMPU6050? = nil
    var gyroTimer: Timer? = nil
    
    // E-Paper
    var spi: PortID = 0
    var ePaper: EPaper? = nil
    var ePaperTimer: Timer? = nil
    var ePaperCharacter = 65
    
    // Color TFT
    var colorTFT: ColorTFT? = nil
    var colorTFTThread: Thread? = nil
    var colorTFTOffset = 0

    // three LEDs
    @IBOutlet weak var checkboxRed: NSButton!
    @IBOutlet weak var checkboxOrange: NSButton!
    @IBOutlet weak var checkboxGreen: NSButton!

    // push button
    @IBOutlet weak var pushButtonLight: Light!
    
    // two potentiometers
    @IBOutlet weak var dutyCycleValueLabel: NSTextField!
    @IBOutlet weak var frequencyValueLabel: NSTextField!
    
    // analog stick
    @IBOutlet weak var analogStick: AnalogStick!
    
    // ammeter
    @IBOutlet weak var currentValueLabel: NSTextField!
    
    // gyro
    @IBOutlet weak var gyroXLabel: NSTextField!
    @IBOutlet weak var gyroYLabel: NSTextField!
    @IBOutlet weak var gyroZLabel: NSTextField!
    @IBOutlet weak var gyroTempLabel: NSTextField!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        resetUI(enabled: false)
    }
    
    override var representedObject: Any? {
        didSet {
            device = representedObject as? WirekiteDevice
            self.configurePins()
        }
    }
    
    override func viewDidDisappear() {
        stopTimers()
        device?.close()
        device = nil
    }
    
    func stopTimers() {
        ledTimer?.invalidate()
        ledTimer = nil
        servoTimer?.invalidate()
        servoTimer = nil
        ammeterTimer?.invalidate()
        ammeterTimer = nil
        gyroTimer?.invalidate()
        gyroTimer = nil
        displayTimer?.invalidate()
        displayTimer = nil
        ePaperTimer?.invalidate()
        ePaperTimer = nil
        colorTFTThread?.cancel()
        colorTFTThread = nil
    }

    func configurePins() {
        
        if let device = self.device {
            
            let mem = device.boardInfo(.availableMemory)
            NSLog("Available memory: \(mem)")
            let maxBlock = device.boardInfo(.maximumMemoryBlock)
            NSLog("Maximum memory block: \(maxBlock)")
            let version = device.boardInfo(.firmwareVersion)
            let versionChars = [
                Character(UnicodeScalar(48 + ((version >> 12) & 0xf))!),
                Character(UnicodeScalar(48 + ((version >> 8) & 0xf))!),
                ".",
                Character(UnicodeScalar(48 + ((version >> 4) & 0xf))!),
                Character(UnicodeScalar(48 + (version & 0xf))!)
            ];
            let versionString = String(versionChars)
            NSLog("Version: \(versionString)")
            
            resetUI(enabled: true)
            
            if DeviceViewController.hasBuiltInLED {
                ledPortId = device.configureDigitalOutputPin(13, attributes: [])
                ledOn = false
                ledTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in self.ledBlink() }
            }

            if DeviceViewController.hasThreeLEDs {
                redLedPin = device.configureDigitalOutputPin(16, attributes: .highCurrent)
                orangeLedPin = device.configureDigitalOutputPin(17, attributes: .highCurrent)
                greenLedPin = device.configureDigitalOutputPin(21, attributes: .highCurrent)
            }
            
            if DeviceViewController.hasPushButton {
                pushButtonPin = device.configureDigitalInputPin(12,
                    attributes: [.triggerRaising, .triggerFalling, .pullup]) { _, value in
                        self.pushButtonLight.on = value
                }
                pushButtonLight.on = device.readDigitalPin(onPort: pushButtonPin)
            }
            
            if DeviceViewController.hasTwoPotentiometers {
                dutyCyclePin = device.configureAnalogInputPin(.A4, interval: 127) { _, value in
                    let text = String(format: "%3.0f %%", value * 100)
                    self.dutyCycleValueLabel.stringValue = text
                    self.device!.writePWMPin(onPort: self.pwmOutPin, dutyCycle: value)
                }
                
                frequencyPin = device.configureAnalogInputPin(.A1, interval: 149) { _, value in
                    if abs(value - self.prevFrequencyValue) > 0.005 {
                        self.prevFrequencyValue = value
                        let frequency = Int((exp(exp(value)) - exp(1)) * 900 + 10)
                        self.device!.configurePWMTimer(0, frequency: frequency, attributes: [])
                        let text = String(format: "%d Hz", frequency)
                        self.frequencyValueLabel.stringValue = text
                    }
                }
                device.configurePWMChannel(0, channel: 3, attributes: [])
                pwmOutPin = device.configurePWMOutputPin(10)
            }
            
            if DeviceViewController.hasServo {
                let boardType = device.boardInfo(.boardType)
                device.configurePWMTimer(boardType == 1 ? 2 : 1, frequency: 100, attributes: [])
                servo = Servo(device: device, pin: 4)
                servo!.turnOn(initialAngle: 0)
                servoTimer = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { timer in self.moveServo() }
            }
 
            if DeviceViewController.hasAnalogStick {
                voltageXPin = device.configureAnalogInputPin(.A8, interval: 137) { _, value in
                    self.analogStick.directionX = 1.0 - value * 2
                }
                voltageYPin = device.configureAnalogInputPin(.A9, interval: 139) { _, value in
                    self.analogStick.directionY = 1.0 - value * 2
                }
                stickPushButtonPin = device.configureDigitalInputPin(20, attributes: [.triggerRaising, .triggerFalling, .pullup]) {
                    _, value in self.analogStick.indicatorColor = value ? DeviceViewController.indicatorColorNormal : DeviceViewController.indicatorColorPressed
                }
                analogStick.indicatorColor = device.readDigitalPin(onPort: stickPushButtonPin) ? DeviceViewController.indicatorColorNormal : DeviceViewController.indicatorColorPressed
            }
            
            if DeviceViewController.hasAmmeter || DeviceViewController.hasOLED || DeviceViewController.hasGyro {
                i2cPort = device.configureI2CMaster(.SCL16_SDA17, frequency: 400000)
            }
            
            if DeviceViewController.hasAmmeter {
                ammeter = Ammeter(device: device, i2cPort: i2cPort)
                ammeterTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { timer in self.readAmps() }
            }
            
            if DeviceViewController.hasOLED {
                display = OLEDDisplay(device: device, i2cPort: i2cPort)
                display!.DisplayOffset = 2
                displayTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in self.updateDisplay() }
            }
            
            if DeviceViewController.hasGyro {
                gyro = GyroMPU6050(device: device, i2cPort: i2cPort)
                gyroTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in self.updateGyro() }
            }
            
            if DeviceViewController.hasEPaper {
                spi = device.configureSPIMaster(forSCKPin: 14, mosiPin: 11, misoPin: InvalidPortID, frequency: 100000, attributes: [])
                ePaper = EPaper(device: device, spiPort: spi, csPin: 10, dcPin: 15, busyPin: 20, resetPin: 16)
                ePaper!.initDevice()
                ePaperTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { timer in self.updateEPaper() }
                ePaperTimer!.fire()
            }
            
            if DeviceViewController.hasColorTFT {
                spi = device.configureSPIMaster(forSCKPin: 20, mosiPin: 21, misoPin: InvalidPortID, frequency: 8000000, attributes: [])
                colorTFT = ColorTFT(device: device, spiPort: spi, csPin: 6, dcPin: 4, resetPin: 5)
                colorTFTThread = Thread() {
                    self.continuouslyUpdateTFT()
                }
                colorTFTThread!.name = "Color TFT"
                colorTFTThread!.start()
            }

        } else {
            resetUI(enabled: false)
        }
    }

    func resetUI(enabled: Bool) {
        checkboxRed.state = NSOffState
        checkboxOrange.state = NSOffState
        checkboxGreen.state = NSOffState
        checkboxRed.isEnabled = enabled && DeviceViewController.hasThreeLEDs
        checkboxOrange.isEnabled = enabled && DeviceViewController.hasThreeLEDs
        checkboxGreen.isEnabled = enabled && DeviceViewController.hasThreeLEDs
        pushButtonLight.on = false
        dutyCycleValueLabel.stringValue = "- %"
        frequencyValueLabel.stringValue = "- Hz"
        analogStick.directionX = 0
        analogStick.directionY = 0
        analogStick.indicatorColor = DeviceViewController.indicatorColorInactive
    }
    
    func ledBlink() {
        device?.writeDigitalPin(onPort: ledPortId, value: ledOn)
        ledOn = !ledOn
    }
    
    func moveServo() {
        servoPos += 0.2
        if servoPos > 210 {
            servoPos = -30
        }
        servo!.move(toAngle: servoPos)
    }
    
    @IBAction func onCheckboxClicked(_ sender: Any) {
        let button = sender as! NSButton
        let ledPin: PortID
        if button == checkboxRed {
            ledPin = redLedPin
        } else if button == checkboxOrange {
            ledPin = orangeLedPin
        } else {
            ledPin = greenLedPin
        }
        device!.writeDigitalPin(onPort: ledPin, value: button.state == NSOnState)
    }
    
    func readAmps() {
        let value = ammeter!.readAmps()
        let text = String(format: "%3.1f mA", value)
        currentValueLabel.stringValue = text
    }
    
    func updateGyro() {
        if (gyro!.isCalibrating) {
            gyroXLabel.stringValue = "Calibrating..."
            gyroYLabel.stringValue = ""
            gyroZLabel.stringValue = ""
            gyroTempLabel.stringValue = ""
        } else {
            gyro!.read()
            let textX = String(format: "X: %d", gyro!.gyroX)
            gyroXLabel.stringValue = textX
            let textY = String(format: "Y: %d", gyro!.gyroY)
            gyroYLabel.stringValue = textY
            let textZ = String(format: "Z: %d", gyro!.gyroZ)
            gyroZLabel.stringValue = textZ
            let textTemp = String(format: "Temp: %3.1f", gyro!.temperature)
            gyroTempLabel.stringValue = textTemp
        }
    }
    
    func updateDisplay() {
        display!.showTile()
    }
    
    func updateEPaper() {
        let gc = ePaper!.prepareForDrawing()
        gc.setShouldAntialias(false)
        gc.setShouldSmoothFonts(false)
        gc.setFillColor(CGColor.white)
        gc.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        gc.setStrokeColor(CGColor.black)
        gc.stroke(CGRect(x: 2, y: 2, width: 196, height: 196), width: 4)
        
        let font = NSFont(name: "Helvetica-Bold", size: 128)!
        let attr: [String: Any] = [
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: NSColor.black
        ]
        
        let s = String(describing: UnicodeScalar(ePaperCharacter)!) as NSString
        let w = s.size(withAttributes: attr)
        s.draw(at: NSMakePoint(100 - w.width / 2, 30), withAttributes: attr)
        ePaper!.finishDrawing(shouldDither: false)
        
        ePaperCharacter += 1
        if ePaperCharacter >= 91 {
            ePaperCharacter = 65
        }
    }
    
    func continuouslyUpdateTFT() {
        colorTFT!.initDevice()
        while !Thread.current.isCancelled {
            updateTFTInner()
        }
    }
    
    func updateTFTInner() {
        let gc = colorTFT!.prepareForDrawing()
        gc.setShouldAntialias(true)
        gc.setShouldSmoothFonts(true)
        gc.setShouldSubpixelPositionFonts(false)
        gc.setShouldSubpixelQuantizeFonts(false)
        gc.setFillColor(CGColor.white)
        gc.fill(CGRect(x: 0, y: 0, width: 160, height: 128))
        
        let font = NSFont(name: "Helvetica-Bold", size: 64)!
        let attr: [String: Any] = [
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: NSColor.black
        ]
        
        let s = "😱✌️🎃🐢☠️😨💩😱✌️🎃" as NSString
        s.draw(at: NSMakePoint(CGFloat(10 + colorTFTOffset), 30), withAttributes: attr)
        colorTFTOffset -= 10
        if colorTFTOffset <= -448 {
            colorTFTOffset += 448 // 448 = 7 * 64: 7 emojis - each one 64 pixel wide
        }

        colorTFT!.finishDrawing()
    }
    
    static func scheduleBackgroundTimer(withTimeInterval interval: DispatchTimeInterval, block: @escaping () -> ()) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.scheduleRepeating(deadline: DispatchTime.now(), interval: interval, leeway: DispatchTimeInterval.milliseconds(10))
        let workItem = DispatchWorkItem(block: block)
        timer.setEventHandler(handler: workItem)
        timer.resume()
        return timer
    }
    
    func synchronized(_ lock: Any, block: () -> ()) {
        objc_sync_enter(lock)
        defer {
            objc_sync_exit(lock)
        }
        block()
    }
}

