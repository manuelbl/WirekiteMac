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
    static let hasAmmeter = true
    static let hasOLED = true
    static let hasGyro = true
    
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
    var prevFrequencyValue: Int16 = 3000
    
    // analog stick
    var voltageXPin: PortID = 0
    var voltageYPin: PortID = 0
    var stickPushButtonPin: PortID = 0

    // servo
    var servoTimer: Timer? = nil
    var servoPin: PortID = 0
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
    }

    func configurePins() {
        
        if let device = self.device {
            
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
                    let text = String(format: "%3.0f %%", Double(value) * 100 / 32767)
                    self.dutyCycleValueLabel.stringValue = text
                    self.device!.writePWMPin(onPort: self.pwmOutPin, dutyCycle: value)
                }
                
                frequencyPin = device.configureAnalogInputPin(.A1, interval: 149) { _, value in
                    if abs(Int(value - self.prevFrequencyValue)) > 100 {
                        self.prevFrequencyValue = value
                        let frequency = UInt32((exp(exp(Double(value) / 32767)) - exp(1)) * 900 + 10)
                        self.device!.configurePWMTimer(0, frequency: frequency, attributes: [])
                        let text = String(format: "%d Hz", frequency)
                        self.frequencyValueLabel.stringValue = text
                    }
                }
                device.configurePWMChannel(0, channel: 3, attributes: [])
                pwmOutPin = device.configurePWMOutputPin(.pin10)
            }
            
            if DeviceViewController.hasServo {
                device.configurePWMTimer(2, frequency: 100, attributes: [])
                servoPin = device.configurePWMOutputPin(.pin4)
                device.writePWMPin(onPort: servoPin, dutyCycle: 4915)
                servoTimer = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { timer in self.moveServo() }
            }
 
            if DeviceViewController.hasAnalogStick {
                voltageXPin = device.configureAnalogInputPin(.A8, interval: 137) { _, value in
                    self.analogStick.directionX = 1.0 - Double(value) / 16383.0
                }
                voltageYPin = device.configureAnalogInputPin(.A9, interval: 139) { _, value in
                    self.analogStick.directionY = 1.0 - Double(value) / 16383.0
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
                gyro!.calibrate {
                    self.gyroTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in self.updateGyro() }
                }
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
        
        let pulseWidth0Deg = 0.54
        let pulseWidth180Deg = 2.14
        let dutyCycleRange = 32767.0
        let frequency = 100.0
        
        let pos = servoPos < 0 ? 0 : (servoPos > 180 ? 180 : servoPos)
        let length_ms = pos / Double(180) * (pulseWidth180Deg - pulseWidth0Deg) + pulseWidth0Deg
        let dutyCycle = Int16(length_ms / (1000 / frequency) * dutyCycleRange + 0.5)
        device!.writePWMPin(onPort: servoPin, dutyCycle: dutyCycle)
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
    
    func updateDisplay() {
        display!.showTile()
    }
}

