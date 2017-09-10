//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

import Cocoa
import AVFoundation
import WirekiteMac


class ViewController: NSViewController, WirekiteServiceDelegate {
    
    var service: WirekiteService? = nil
    var device: WirekiteDevice? = nil
    var greenButton: PortID = 0
    var redButton: PortID = 0
    var greenSound: AVAudioPlayer?
    var redSound: AVAudioPlayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        service = WirekiteService()
        service?.delegate = self
        service?.start()
    }
    
    func connectedDevice(_ device: WirekiteDevice!) {
        self.device = device
        greenButton = device.configureDigitalInputPin(14, attributes: [.triggerFalling, .pullup]) {
            _, value in self.playSound(self.greenSound)
        }
        redButton = device.configureDigitalInputPin(20, attributes: [.triggerFalling, .pullup]) {
            _, value in self.playSound(self.redSound)
        }

        greenSound = prepareSound("ding_dong")
        redSound = prepareSound("gliss")
    }
    
    func disconnectedDevice(_ device: WirekiteDevice!) {
        if self.device == device {
            self.device = nil
        }
    }
    
    func prepareSound(_ soundName: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "mp3") else { return nil }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch let error {
            print(error.localizedDescription)
            return nil
        }
    }
    
    func playSound(_ sound: AVAudioPlayer?) {
        sound!.play()
        sound!.prepareToPlay()
    }
}

