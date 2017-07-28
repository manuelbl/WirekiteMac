//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa

class ViewController: NSViewController, WirekiteServiceDelegate, WirekiteDeviceDelegate {
    
    static let indicatorColorNormal = NSColor.black
    static let indicatorColorPressed = NSColor.orange
    static let indicatorColorInactive = NSColor.lightGray

    var service: WirekiteService? = nil
    var device: WirekiteDevice? = nil
    var timer: Timer? = nil
    
    var ledPortId: PortID = 0
    var ledOn = true
    
    var redLedId: PortID = 0
    var orangeLedId: PortID = 0
    var greenLedId: PortID = 0
    
    var switchPortId: PortID = 0
    
    var dutyCyclePin: PortID = 0
    var frequencyPin: PortID = 0
    
    var voltageXPin: PortID = 0
    var voltageYPin: PortID = 0
    var switchPin: PortID = 0
    
    var pwmOutPin: PortID = 0
    
    var prevFrequencyValue: Int16 = 3000
    
    
    @IBOutlet weak var checkboxRed: NSButton!
    @IBOutlet weak var checkboxOrange: NSButton!
    @IBOutlet weak var checkboxGreen: NSButton!

    @IBOutlet weak var switchLight: Light!
    @IBOutlet weak var dutyCycleValueLabel: NSTextField!
    @IBOutlet weak var frequencyValueLabel: NSTextField!
    
    @IBOutlet weak var analogStick: AnalogStick!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        service = WirekiteService()
        service?.delegate = self
        service?.start()
        
        resetUI(enabled: false)
    }
    
    override func viewDidDisappear() {
        if let device = device {
            device.resetConfiguration()
            self.device = nil
        }
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    func deviceAdded(_ newDevice: WirekiteDevice!) {
        NSLog("Wirekite device added")
        device = newDevice
        device?.delegate = self

        DispatchQueue.main.async {
            self.configurePins()
        }
    }
    
    
    func configurePins() {
        
        if let device = self.device {
            device.resetConfiguration()
            resetUI(enabled: true)
            device.configurePWMChannel(0, channel: 3, attributes: [])
            
            ledPortId = device.configureDigitalOutputPin(13, attributes: [])
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in self.ledBlink() }
            
            redLedId = device.configureDigitalOutputPin(16, attributes: .highCurrent)
            orangeLedId = device.configureDigitalOutputPin(17, attributes: .highCurrent)
            greenLedId = device.configureDigitalOutputPin(21, attributes: .highCurrent)
            
            switchPortId = device.configureDigitalInputPin(12,
                  attributes: [.triggerRaising, .triggerFalling, .pullup]) { _, value in
                    self.switchLight.on = value
            }
            switchLight.on = device.readDigitalPin(onPort: switchPortId)
            
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
            
            voltageXPin = device.configureAnalogInputPin(.A8, interval: 137) { _, value in
                self.analogStick.directionX = 1.0 - Double(value) / 16383.0
            }
            voltageYPin = device.configureAnalogInputPin(.A9, interval: 139) { _, value in
                self.analogStick.directionY = 1.0 - Double(value) / 16383.0
            }
            switchPin = device.configureDigitalInputPin(20, attributes: [.triggerRaising, .triggerFalling, .pullup]) {
                _, value in self.analogStick.indicatorColor = value ? ViewController.indicatorColorNormal : ViewController.indicatorColorPressed
            }
            analogStick.indicatorColor = device.readDigitalPin(onPort: switchPin) ? ViewController.indicatorColorNormal : ViewController.indicatorColorPressed
            
            pwmOutPin = device.configurePWMOutputPin(.pin10)
        }
    }
    
    
    func ledBlink() {
        device?.writeDigitalPin(onPort: ledPortId, value: ledOn)
        ledOn = !ledOn
    }
    
    
    func resetUI(enabled: Bool) {
        checkboxRed.state = NSOffState
        checkboxOrange.state = NSOffState
        checkboxGreen.state = NSOffState
        checkboxRed.isEnabled = enabled
        checkboxOrange.isEnabled = enabled
        checkboxGreen.isEnabled = enabled
        switchLight.on = false
        dutyCycleValueLabel.stringValue = "- %"
        frequencyValueLabel.stringValue = "- Hz"
        analogStick.directionX = 0
        analogStick.directionY = 0
        analogStick.indicatorColor = ViewController.indicatorColorInactive
    }
    
    
    func readAnalog() {
        let value2 = device!.readAnalogPin(onPort: voltageXPin)
        DispatchQueue.main.async {
            self.analogStick.directionX = 1.0 - Double(value2) / 16383.0
        }
        
        let value3 = device!.readAnalogPin(onPort: voltageYPin)
        DispatchQueue.main.async {
            self.analogStick.directionY = 1.0 - Double(value3) / 16383.0
        }
    }
    
    
    func deviceRemoved(_ removedDevice: WirekiteDevice!) {
        if device == removedDevice {
            NSLog("Wirekite device removed")
            device = nil
            timer?.invalidate()
            timer = nil
            resetUI(enabled: false)
        }
    }


    @IBAction func onCheckboxClicked(_ sender: Any) {
        let button = sender as! NSButton
        let ledPortId: PortID
        if button == checkboxRed {
            ledPortId = redLedId
        } else if button == checkboxOrange {
            ledPortId = orangeLedId
        } else {
            ledPortId = greenLedId
        }
        device!.writeDigitalPin(onPort: ledPortId, value: button.state == NSOnState)
    }
}

