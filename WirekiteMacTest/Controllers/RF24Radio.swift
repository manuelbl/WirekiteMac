//
// Wirekite for MacOS
//
// Copyright (c) 2018 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//
// Major parts of this class is a translation of the RF24 Arduino library
// Portions Copyright (C) 2011 J. Coliz <maniacbug@ymail.com>


import Foundation
import os.log


fileprivate enum Register: UInt8 {
    case CONFIG      = 0x00
    case EN_AA       = 0x01
    case EN_RXADDR   = 0x02
    case SETUP_AW    = 0x03
    case SETUP_RETR  = 0x04
    case RF_CH       = 0x05
    case RF_SETUP    = 0x06
    case STATUS      = 0x07
    case OBSERVE_TX  = 0x08
    case RPD         = 0x09
    case RX_ADDR_P0  = 0x0A
    case RX_ADDR_P1  = 0x0B
    case RX_ADDR_P2  = 0x0C
    case RX_ADDR_P3  = 0x0D
    case RX_ADDR_P4  = 0x0E
    case RX_ADDR_P5  = 0x0F
    case TX_ADDR     = 0x10
    case RX_PW_P0    = 0x11
    case RX_PW_P1    = 0x12
    case RX_PW_P2    = 0x13
    case RX_PW_P3    = 0x14
    case RX_PW_P4    = 0x15
    case RX_PW_P5    = 0x16
    case FIFO_STATUS = 0x17
    case DYNPD       = 0x1C
    case FEATURE     = 0x1D
    
    func offset(by offset: Int) -> Register {
        return Register(rawValue: self.rawValue + UInt8(offset))!
    }
}

fileprivate struct RF24 {
    struct CONFIG {
        static let MASK_RX_DR: UInt8 = 0x40
        static let MASK_TX_DS: UInt8 = 0x20
        static let MASK_MAX_RT: UInt8 = 0x10
        static let EN_CRC: UInt8 = 0x08
        static let CRCO: UInt8 = 0x04
        static let PWR_UP: UInt8 = 0x02
        static let PRIM_RX: UInt8 = 0x01
    }
    struct RF_SETUP {
        static let CONT_WAVE: UInt8 = 0x80
        static let RF_DR_LOW: UInt8 = 0x20
        static let PLL_LOCK: UInt8 = 0x10
        static let RF_DR_HIGH: UInt8 = 0x08
        static let RF_PWR_MASK: UInt8 = 0x06
    }
    struct STATUS {
        static let RX_DR: UInt8 = 0x40
        static let TX_DS: UInt8 = 0x20
        static let MAX_RT: UInt8 = 0x10
        static let TX_FULL: UInt8 = 0x01
    }
    struct FEATURE {
        static let EN_DPL: UInt8 = 0x04
        static let EN_ACK_PAY: UInt8 = 0x02
        static let EN_DYN_ACK: UInt8 = 0x01
    }
    struct FIFO_STATUS {
        static let RX_REUSE: UInt8 = 0x40
        static let TX_FULL: UInt8 = 0x20
        static let TX_EMPTY: UInt8 = 0x10
        static let RX_FULL: UInt8 = 0x02
        static let RX_EMPTY: UInt8 = 0x01
    }
    struct CMD {
        static let R_REGISTER: UInt8 = 0x00
        static let W_REGISTER: UInt8 = 0x20
        static let R_RX_PAYLOAD: UInt8 = 0x61
        static let W_TX_PAYLOAD: UInt8 = 0xA0
        static let FLUSH_TX: UInt8 = 0xE1
        static let FLUSH_RX: UInt8 = 0xE2
        static let REUSE_TX_PL: UInt8 = 0xE3
        static let R_RX_PL_WID: UInt8  = 0x60
        static let W_ACK_PAYLOAD: UInt8 = 0xA8
        static let W_TX_PAYLOAD_NOACK: UInt8 = 0xB0
        static let NOP: UInt8 = 0xFF
    }
}


public enum DataRate {
    case _1mbps
    case _2mbps
    case _250kbps
}


public enum PALevel: Int {
    case Min = 0
    case Low = 1
    case High = 2
    case Max = 3
}


public class RF24Radio {
    
    private var device: WirekiteDevice?
    private var spi: PortID
    
    private var cePort: PortID
    private var csnPort: PortID
    private var irqPort: PortID = InvalidPortID
    
    private var isPlusModel = false
    private var dynamicPayloadEnabled = true
    private var addrWidth = 5
    private var payloadSize = 32
    private var pipe0ReadingAddress: UInt64 = 0
    
    private var readCompletion: ((RF24Radio, [UInt8]) -> Void)?
    private var expectedPayloadSize = 32


    init(device: WirekiteDevice, spiPort: PortID, cePin: Int, csnPin: Int) {
        self.device = device
        self.spi = spiPort
        
        cePort = device.configureDigitalOutputPin(cePin, attributes: [], initialValue: false)
        csnPort = device.configureDigitalOutputPin(csnPin, attributes: [], initialValue: true)
    }
    
    deinit {
        device?.releaseDigitalPin(onPort: cePort)
        device?.releaseDigitalPin(onPort: csnPort)
        if irqPort != InvalidPortID {
            device?.releaseDigitalPin(onPort: irqPort)
        }
    }
    
    func initDevice() {
        Thread.sleep(forTimeInterval: 0.005)
        
        debugRegisters()

        // Reset CONFIG and enable 16-bit CRC.
        write(value: RF24.CONFIG.EN_CRC | RF24.CONFIG.CRCO, toRegister: .CONFIG)
        
        setRetries(delay: 5, count: 15)
        
        // check for connected module and if this is a p nRF24l01 variant
        isPlusModel = set(dataRate: ._250kbps)
        
        // Default speed
        let _ = set(dataRate: ._1mbps)
        
        // Disable dynamic payloads, to match dynamic_payloads_enabled setting - Reset value is 0
        toggleFeatures()
        write(value: 0, toRegister: .FEATURE)
        write(value: 0, toRegister: .DYNPD)
        dynamicPayloadEnabled = false
        
        // Reset current status
        // Notice reset and flush is the last thing we do
        write(value: RF24.STATUS.RX_DR | RF24.STATUS.TX_DS | RF24.STATUS.MAX_RT, toRegister: .STATUS)
        
        // Set up default configuration.  Callers can always change it later.
        // This channel should be universally safe and not bleed over into adjacent
        // spectrum.
        set(channel: 76)
        
        // Flush buffers
        flushRX()
        flushTX()
        
        powerUp() // Power up by default when begin() is called
        
        // Enable PTX, do not write CE high so radio will remain in standby I mode
        // (130us max to transition to RX or TX instead of 1500us from powerUp)
        // PTX should use only 22uA of power
        var config = read(fromRegister: .CONFIG)
        config &= ~RF24.CONFIG.PRIM_RX
        write(value: config, toRegister: .CONFIG)
        
        debugRegisters()
    }
    
    func configureIRQPin(irqPin: Int, payloadSize: Int,  completion: @escaping (RF24Radio, [UInt8]) -> Void) {
        readCompletion = completion
        expectedPayloadSize = payloadSize
        irqPort = device!.configureDigitalInputPin(irqPin, attributes: .triggerFalling) {
            (_, _) in
            self.interruptTriggered()
        }
    }
    
    var addressWidth: Int {
        get {
            return addrWidth
        }
        
        set(newValue) {
            var w = newValue - 2
            if w > 3 {
                w = 3
            } else if w < 0 {
                w = 0
            }
            
            write(value: UInt8(w), toRegister: .SETUP_AW)
            addrWidth = w + 2
        }
    }
    
    var dataAvailable: Bool {
        get {
            let status = read(fromRegister: .FIFO_STATUS)
            return (status & RF24.FIFO_STATUS.RX_EMPTY) == 0
        }
    }
    
    func setRetries(delay: Int, count: Int) {
        var delayCode: Int = (delay + 249) / 250 // delay in µs
        if delayCode > 15 {
            delayCode = 15
        }
        var retries = count
        if retries > 15 {
            retries = 15
        }
        let value = UInt8((delayCode << 4) | retries)
        write(value: value, toRegister: .SETUP_RETR)
    }
    
    func set(dataRate: DataRate) -> Bool {
        var setup = read(fromRegister: .RF_SETUP)
        setup &= ~(RF24.RF_SETUP.RF_DR_LOW | RF24.RF_SETUP.RF_DR_HIGH)
        setup |= dataRate == ._250kbps ? RF24.RF_SETUP.RF_DR_LOW : (dataRate == ._2mbps ? RF24.RF_SETUP.RF_DR_HIGH : 0)
        write(value: setup, toRegister: .RF_SETUP)
        
        // Verify our result
        return read(fromRegister: .RF_SETUP) == setup
    }
    
    func getStatus() -> UInt8 {
        return write(command: RF24.CMD.NOP)
    }
    
    func toggleFeatures() {
        let bytes: [UInt8] = [ 0x50, 0x73 ]
        let data = Data(bytes)
        device!.transmit(onSPIPort: spi, data: data, chipSelect: csnPort)
    }
    
    func set(channel: Int) {
        if channel >= 0 && channel <= 125 {
            write(value: UInt8(channel), toRegister: .RF_CH)
        }
    }
    
    func flushTX() {
        let _ = write(command: RF24.CMD.FLUSH_TX)
    }
    
    func flushRX() {
        let _ = write(command: RF24.CMD.FLUSH_RX)
    }
    
    func powerDown() {
        device!.writeDigitalPin(onPort: cePort, value: false, synchronizedWithSPIPort: spi)
        var config = read(fromRegister: .CONFIG)
        config &= ~RF24.CONFIG.PWR_UP
        write(value: config, toRegister: .CONFIG)
    }
    
    func powerUp() {
        var config = read(fromRegister: .CONFIG)
        if (config & RF24.CONFIG.PWR_UP) == 0 {
            config |= RF24.CONFIG.PWR_UP
            write(value: config, toRegister: .CONFIG)
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
    
    func set(autoAck: Bool) {
        write(value: autoAck ? 0x3f : 0, toRegister: .EN_AA)
    }
    
    func set(paLevel: PALevel) {
        var setup = read(fromRegister: .RF_SETUP)
        setup &= ~RF24.RF_SETUP.RF_PWR_MASK
        setup |= UInt8(paLevel.rawValue) << 1
        write(value: setup, toRegister: .RF_SETUP)
    }
    
    func openWritingPipe(address: UInt64) {
        write(address: address, toRegister: .RX_ADDR_P0)
        write(address: address, toRegister: .TX_ADDR)
        write(value: UInt8(payloadSize), toRegister: .RX_PW_P0)
    }
    
    func openReadingPipe(child: Int, address: UInt64) {
        if child < 0 || child > 6 {
            return
        }
        if child == 0 {
            pipe0ReadingAddress = address
        }
        
        let addrRegister = Register.RX_ADDR_P0.offset(by: child)
        if child < 2 {
            write(address: address, toRegister: addrRegister)
        } else {
            write(value: UInt8(address & 0xff), toRegister: addrRegister)
        }
        
        let payloadRegister = Register.RX_PW_P0.offset(by: child)
        write(value: UInt8(payloadSize), toRegister: payloadRegister)
        
        var enRxAddr = read(fromRegister: .EN_RXADDR)
        enRxAddr |= UInt8(1 << child)
        write(value: enRxAddr, toRegister: .EN_RXADDR)
    }
    
    func closeReadingPipe(child: Int) {
        var enRxAddr = read(fromRegister: .EN_RXADDR)
        enRxAddr &= ~UInt8(1 << child)
        write(value: enRxAddr, toRegister: .EN_RXADDR)
    }
    
    func read(numBytes: Int) -> [UInt8] {
        let data = readPayload(numBytes: numBytes)
        let status: UInt8 = RF24.STATUS.RX_DR | RF24.STATUS.TX_DS | RF24.STATUS.MAX_RT
        write(value: status, toRegister: .STATUS)
        return data
    }
    
    private func readPayload(numBytes: Int) -> [UInt8] {
        let plSize = min(numBytes, payloadSize)
        let padSize = dynamicPayloadEnabled ? 0 : payloadSize - plSize
        
        var txData = [UInt8](repeating: RF24.CMD.NOP, count: plSize + padSize)
        txData[0] = RF24.CMD.R_RX_PAYLOAD
        let rxData = transmitAndRequest(txData: txData)
        return Array(rxData[..<plSize])
    }

    func debugRegisters() {
        
        // status
        debug(status: getStatus())

        // addresses
        debug(addressRegister: .RX_ADDR_P0, addressLength: addressWidth)
        debug(addressRegister: .RX_ADDR_P1, addressLength: addressWidth)
        debug(byteRegisters: .RX_ADDR_P2, count: 4, label: "RX_ADDR_P2..5")
        debug(addressRegister: .TX_ADDR, addressLength: addressWidth)
        
        debug(byteRegisters: .RX_PW_P0, count: 6, label: "RX_PW_P0..5")
        debug(byteRegister: .EN_AA)
        debug(byteRegister: .EN_RXADDR)
        debug(byteRegister: .RF_CH)
        debug(byteRegister: .RF_SETUP)
        debug(byteRegister: .SETUP_AW)
        debug(byteRegister: .CONFIG)
        debug(byteRegister: .DYNPD)
        debug(byteRegister: .FEATURE)
    }
    
    func debug(status: UInt8) {
        os_log("STATUS: RX_DR = %d, TX_DS = %d, MAX_RT = %d, RX_P_NO = %d, RX_FULL = %d",
               (status & RF24.STATUS.RX_DR) == 0 ? 0 : 1,
               (status & RF24.STATUS.TX_DS) == 0 ? 0 : 1,
               (status & RF24.STATUS.MAX_RT) == 0 ? 0 : 1,
               (status & 0x0e) >> 1,
               (status & RF24.STATUS.TX_FULL) == 0 ? 0 : 1)
    }
    
    fileprivate func debug(byteRegister register: Register) {
        let label = "\(register)"
        let valueStr = String(format: "%02x", read(fromRegister: register))
        os_log("%@: %@", label, valueStr)
    }
    
    fileprivate func debug(byteRegisters register: Register, count: Int, label: String) {
        var dataStr = ""
        for i in 0 ..< count {
            let value = read(fromRegister: register.offset(by: i))
            dataStr += String(format: " %02x", value)
        }
        os_log("%@:%@", label, dataStr)
    }
    
    fileprivate func debug(addressRegister register: Register, addressLength: Int) {
        let address = readAddress(fromRegister: register, length: addressLength)
        var addressStr = ""
        for i in 0 ..< addressLength {
            addressStr += String(format: "%02x", address[addressLength - i - 1])
        }
        let registerName = "\(register)"
        os_log("%@: %@", registerName, addressStr)
    }
    
    fileprivate func debug(addressRegister register: Register, length: Int = 1) {
        var dataStr = ""
        for i in 0 ..< length {
            let value = read(fromRegister: register.offset(by: i))
            dataStr += String(format: " %02x", value)
        }
        let registerName = "\(register)"
        os_log("%@:%@", registerName, dataStr)
    }
    
    func startListening() {
        powerUp()
        
        var config = read(fromRegister: .CONFIG)
        config |= RF24.CONFIG.PRIM_RX
        write(value: config, toRegister: .CONFIG)
        
        let status: UInt8 = RF24.STATUS.RX_DR | RF24.STATUS.TX_DS | RF24.STATUS.MAX_RT
        write(value: status, toRegister: .STATUS)

        device!.writeDigitalPin(onPort: cePort, value: true, synchronizedWithSPIPort: spi)

        // Restore the pipe0 adddress, if exists
        if (pipe0ReadingAddress & 0xff) != 0 {
            write(address: pipe0ReadingAddress, toRegister: .RX_ADDR_P0)
        } else {
            closeReadingPipe(child: 0)
        }
        
        if (read(fromRegister: .FEATURE) & RF24.FEATURE.EN_ACK_PAY) != 0 {
            flushTX()
        }
    }
    
    private func interruptTriggered() {
        let data = read(numBytes: expectedPayloadSize)
        readCompletion!(self, data)
    }
    

    private func addressToByteArray(address: UInt64) -> [UInt8] {
        // convert to byte array, LSB first
        var addr = address
        var bytes = [UInt8](repeating: 0, count: addressWidth)
        for i in 0 ..< addressWidth {
            bytes[i] = UInt8(addr & 0xff)
            addr >>= 8
        }
        return bytes
    }
    
    private func write(value: UInt8, toRegister register: Register) {
        let bytes: [UInt8] = [ writeCode(register: register), value ]
        let data = Data(bytes)
        device!.transmit(onSPIPort: spi, data: data, chipSelect: csnPort)
    }
    
    private func write(address: UInt64, toRegister register: Register) {
        var bytes: [UInt8] = [ writeCode(register: register) ]
        bytes.append(contentsOf: addressToByteArray(address: address))
        let data = Data(bytes)
        device!.transmit(onSPIPort: spi, data: data, chipSelect: csnPort)
    }
    
    private func write(command: UInt8) -> UInt8 {
        let txData: [UInt8] = [ command ]
        let rxData = transmitAndRequest(txData: txData)
        return rxData[0]
    }
    
    private func read(fromRegister register: Register) -> UInt8 {
        let txData: [UInt8] = [ readCode(register: register), RF24.CMD.NOP]
        let rxData = transmitAndRequest(txData: txData)
        return rxData[1]
    }
    
    private func readAddress(fromRegister register: Register, length: Int) -> [UInt8] {
        var txData = [UInt8](repeating: RF24.CMD.NOP, count: length + 1)
        txData[0] = readCode(register: register)
        let rxData = transmitAndRequest(txData: txData)
        return Array(rxData[1...])
    }

    private func writeCode(register: Register) -> UInt8 {
        return RF24.CMD.W_REGISTER | register.rawValue
    }
    
    private func readCode(register: Register) -> UInt8 {
        return RF24.CMD.R_REGISTER | register.rawValue
    }
    
    private func transmitAndRequest(txData: [UInt8]) -> [UInt8] {
        let txPayload = Data(txData)
        let rxPayload = device!.transmitAndRequest(onSPIPort: spi, data: txPayload, chipSelect: csnPort)
        if let rxPayload = rxPayload {
            return [UInt8](rxPayload)
        } else {
            return [UInt8]()
        }
    }
}
