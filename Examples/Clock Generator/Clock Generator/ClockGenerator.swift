//
//  ClockGenerator.swift
//  Clock Generator
//
//  Created by Manuel Bleichenbacher on 10.10.17.
//  Copyright © 2017 Codecrete. All rights reserved.
//

import CoreFoundation
import WirekiteMac


class ClockGenerator {
    
    enum CrystalLoad: UInt8 {
        case c6pf =  64
        case c8pf =  128
        case c10pf = 192
    }
    
    enum PLL: Int {
        case A = 0
        case B = 1
    }
    
    enum MultiSynthDivider: Int {
        case div4   = 4
        case div6   = 6
        case div8   = 8
    }
    
    enum RDivider: Int {
        case div1   = 0
        case div2   = 1
        case div4   = 2
        case div8   = 3
        case div16  = 4
        case div32  = 5
        case div64  = 6
        case div128 = 7
    }
    
    private enum Register: UInt8 {
        case DEVICE_STATUS                      = 0
        case INTERRUPT_STATUS_STICKY            = 1
        case INTERRUPT_STATUS_MASK              = 2
        case OUTPUT_ENABLE_CONTROL              = 3
        case OEB_PIN_ENABLE_CONTROL             = 9
        case PLL_INPUT_SOURCE                   = 15
        case CLK0_CONTROL                       = 16
        case CLK1_CONTROL                       = 17
        case CLK2_CONTROL                       = 18
        case CLK3_CONTROL                       = 19
        case CLK4_CONTROL                       = 20
        case CLK5_CONTROL                       = 21
        case CLK6_CONTROL                       = 22
        case CLK7_CONTROL                       = 23
        case CLK3_0_DISABLE_STATE               = 24
        case CLK7_4_DISABLE_STATE               = 25
        case PLL_A_PARAMETERS                   = 26
        case PLL_B_PARAMETERS                   = 34
        case MULTISYNTH0_PARAMETERS_1           = 42
        case MULTISYNTH0_PARAMETERS_3           = 44
        case MULTISYNTH1_PARAMETERS_1           = 50
        case MULTISYNTH1_PARAMETERS_3           = 52
        case MULTISYNTH2_PARAMETERS_1           = 58
        case MULTISYNTH2_PARAMETERS_3           = 60
        case CLOCK_6_7_OUTPUT_DIVIDER           = 92
        case CLK0_INITIAL_PHASE_OFFSET          = 165
        case CLK1_INITIAL_PHASE_OFFSET          = 166
        case CLK2_INITIAL_PHASE_OFFSET          = 167
        case CLK3_INITIAL_PHASE_OFFSET          = 168
        case CLK4_INITIAL_PHASE_OFFSET          = 169
        case CLK5_INITIAL_PHASE_OFFSET          = 170
        case PLL_RESET                          = 177
        case CRYSTAL_INTERNAL_LOAD_CAPACITANCE  = 183
    }
    
    var SlaveAddress: Int = 0x60
    var crystalFrequency = 25000000.0
    var crystalLoad = CrystalLoad.c10pf

    private let device: WirekiteDevice
    private let i2c: PortID
    
    private var isInitialized = false
    private var crystalPPM: UInt32 = 30
    private var isPllAConfigured = false
    private var pllAFrequency: Int = 0
    private var isPllBConfigured = false
    private var pllBFrequency: Int = 0

    init(device: WirekiteDevice, i2c: PortID) {
        self.device = device
        self.i2c = i2c
    }
    
    func initDevice() {
        write(toRegister: .OUTPUT_ENABLE_CONTROL, value: 0xFF)

        write(toRegister: .CLK0_CONTROL, value: 0x80)
        write(toRegister: .CLK1_CONTROL, value: 0x80)
        write(toRegister: .CLK2_CONTROL, value: 0x80)
        write(toRegister: .CLK3_CONTROL, value: 0x80)
        write(toRegister: .CLK4_CONTROL, value: 0x80)
        write(toRegister: .CLK5_CONTROL, value: 0x80)
        write(toRegister: .CLK6_CONTROL, value: 0x80)
        write(toRegister: .CLK7_CONTROL, value: 0x80)

        write(toRegister: .CRYSTAL_INTERNAL_LOAD_CAPACITANCE, value: crystalLoad.rawValue)
        
        isPllAConfigured = false
        pllAFrequency = 0
        isPllBConfigured = false
        pllBFrequency = 0
        
        isInitialized = true
    }
    
    func configure(pll: PLL, integerMultiplier mult: Int) {
        configure(pll: pll, multiplier: mult, numerator: 0, denominator: 1)
    }
    
    func configure(pll: PLL, multiplier mult: Int, numerator num: Int, denominator denom: Int) {
        guard isInitialized else {
            NSLog("Clock generator: call initDevice() first")
            return
        }
        guard mult >= 15 && mult <= 90 else {
            NSLog("Clock generator: multiplier is outside range 15..90")
            return
        }
        guard num >= 0 && num <= 1048575 else {
            NSLog("Clock generator: numerator is outside range 0..1,048,575")
            return
        }
        guard denom >= 1 && denom <= 1048575 else {
            NSLog("Clock generator: denominator is outside range 1..1,048,575")
            return
        }
        
        let p1: UInt32
        let p2: UInt32
        let p3: UInt32
        
        if num == 0 {
            p1 = UInt32(128 * mult - 512)
            p2 = UInt32(num)
            p3 = UInt32(denom)
        } else {
            p1 = UInt32(128 * mult + Int(floor(128 * Double(num) / Double(denom) - 512)))
            p2 = UInt32(128 * num - denom * Int(floor(128 * Double(num) / Double(denom))))
            p3 = UInt32(denom)
        }
        
        var parameters = [UInt8](repeating: 0, count: 8)
        parameters[0] = UInt8( (p3 & 0x0000ff00) >>  8)
        parameters[1] = UInt8(  p3 & 0x000000ff)
        parameters[2] = UInt8( (p1 & 0x00030000) >> 16)
        parameters[3] = UInt8( (p1 & 0x0000ff00) >>  8)
        parameters[4] = UInt8(  p1 & 0x000000ff)
        parameters[5] = UInt8(((p2 & 0x000f0000) >> 16) | ((p3 & 0x000f0000) >> 12))
        parameters[6] = UInt8( (p2 & 0x0000ff00) >>  8)
        parameters[7] = UInt8(  p2 & 0x000000ff)
        
        let paramStartRegister: Register = pll == .A ? .PLL_A_PARAMETERS : .PLL_B_PARAMETERS
        write(startingAtRegister: paramStartRegister, data: parameters)
        
        let freq = Int(floor(crystalFrequency * (Double(mult) + Double(num) / Double(denom))))
        if pll == .A {
            pllAFrequency = freq
            isPllAConfigured = true
        } else {
            pllBFrequency = freq
            isPllBConfigured = true
        }
    }
    
    func configure(multiSynthOutput output: Int, pllSource: PLL, integerDivider div: MultiSynthDivider) {
        configure(multiSynthOutput: output, pllSource: pllSource, divider: div.rawValue, numerator: 0, denominator: 1)
    }
    
    func configure(multiSynthOutput output: Int, pllSource: PLL, divider div: Int, numerator num: Int, denominator denom: Int) {
        guard isInitialized else {
            NSLog("Clock generator: call initDevice() first")
            return
        }
        guard output >= 0 && output <= 2 else {
            NSLog("Clock generator: output is outside range 0..2")
            return
        }
        guard div >= 4 && div <= 900 else {
            NSLog("Clock generator: divider is outside range 4..900")
            return
        }
        guard num >= 0 && num <= 1048575 else {
            NSLog("Clock generator: numerator is outside range 0..1,048,575")
            return
        }
        guard denom >= 1 && denom <= 1048575 else {
            NSLog("Clock generator: denominator is outside range 1..1,048,575")
            return
        }
        guard pllSource != .A || isPllAConfigured else {
            NSLog("Clock generator: configure PLL A first")
            return
        }
        guard pllSource != .B || isPllBConfigured else {
            NSLog("Clock generator: configure PLL B first")
            return
        }

        let p1: UInt32
        let p2: UInt32
        let p3: UInt32
        
        if num == 0 {
            p1 = UInt32(128 * div - 512)
            p2 = UInt32(num)
            p3 = UInt32(denom)
        } else {
            p1 = UInt32(128 * div + Int(floor(128 * Double(num) / Double(denom) - 512)))
            p2 = UInt32(128 * num - denom * Int(floor(128 * Double(num) / Double(denom))))
            p3 = UInt32(denom)
        }
        
        var parameters = [UInt8](repeating: 0, count: 8)
        parameters[0] = UInt8( (p3 & 0x0000ff00) >>  8)
        parameters[1] = UInt8(  p3 & 0x000000ff)
        parameters[2] = UInt8( (p1 & 0x00030000) >> 16)
        parameters[3] = UInt8( (p1 & 0x0000ff00) >>  8)
        parameters[4] = UInt8(  p1 & 0x000000ff)
        parameters[5] = UInt8(((p2 & 0x000f0000) >> 16) | ((p3 & 0x000f0000) >> 12))
        parameters[6] = UInt8( (p2 & 0x0000ff00) >>  8)
        parameters[7] = UInt8(  p2 & 0x000000ff)

        let paramStartRegister: Register
        let clockControlRegister: Register
        switch (output) {
        case 0:
            paramStartRegister = .MULTISYNTH0_PARAMETERS_1
            clockControlRegister = .CLK0_CONTROL
        case 1:
            paramStartRegister = .MULTISYNTH1_PARAMETERS_1
            clockControlRegister = .CLK1_CONTROL
        default:
            paramStartRegister = .MULTISYNTH2_PARAMETERS_1
            clockControlRegister = .CLK2_CONTROL
        }

        write(startingAtRegister: paramStartRegister, data: parameters)

        var clockControlValue: UInt8 = 0x0f
        if pllSource == .B {
            clockControlValue |= 1 << 5
        }
        if num == 0 {
            clockControlValue |= 1 << 6
        }
        write(toRegister: clockControlRegister, value: clockControlValue)
    }
    
    func configure(rDividerOutput output: Int, divider div: RDivider) {
        guard isInitialized else {
            NSLog("Clock generator: call initDevice() first")
            return
        }
        guard output >= 0 && output <= 2 else {
            NSLog("Clock generator: output is outside range 0..2")
            return
        }

        let param3Register: Register
        switch (output) {
        case 0:
            param3Register = .MULTISYNTH0_PARAMETERS_3
        case 1:
            param3Register = .MULTISYNTH1_PARAMETERS_3
        default:
            param3Register = .MULTISYNTH2_PARAMETERS_3
        }
        
        var registerValue = read(fromRegister: param3Register)
        registerValue &= 0x0f
        registerValue |= UInt8(div.rawValue) << 4
        write(toRegister: param3Register, value: registerValue)
    }
    
    func setOutputs(enabled: Bool) {
        guard isInitialized else {
            NSLog("Clock generator: call initDevice() first")
            return
        }
        
        write(toRegister: .OUTPUT_ENABLE_CONTROL, value: enabled ? 0x00 : 0xff)
    }
    
    private func write(toRegister register: Register, value: UInt8) {
        let bytes: [UInt8] = [ register.rawValue, value ]
        let data = Data(bytes: bytes)
        let len = device.send(onI2CPort: i2c, data: data, toSlave: SlaveAddress)
        if len != 2 {
            NSLog("Clock generator: writing to register failed (error %d", device.lastResult(onI2CPort: i2c).rawValue)
        }
    }
    
    private func write(startingAtRegister register: Register, data registerBytes: [UInt8]) {
        var bytes: [UInt8] = [ register.rawValue ]
        bytes.append(contentsOf: registerBytes)
        let data = Data(bytes: bytes)
        let len = device.send(onI2CPort: i2c, data: data, toSlave: SlaveAddress)
        if len != registerBytes.count + 1 {
            NSLog("Clock generator: writing to register failed (error %d", device.lastResult(onI2CPort: i2c).rawValue)
        }
    }
    
    private func read(fromRegister register: Register) -> UInt8 {
        let registerBytes: [UInt8] = [ register.rawValue ]
        let registerData = Data(bytes: registerBytes)
        let data = device.sendAndRequest(onI2CPort: i2c, data: registerData, toSlave: SlaveAddress, receiveLength: 1)
        if data == nil || data!.count != 1 {
            NSLog("Clock generator: reading from register failed")
            return 0
        }
        let bytes = [UInt8](data!)
        return bytes[0]
    }
}
