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


public enum RFOutputPower: Int {
    case Min = 0
    case Low = 1
    case High = 2
    case Max = 3
}


/**
 Controls a NRF24L01+ radio transceiver module
 */
public class RF24Radio {
    
    private var device: WirekiteDevice?
    private var spi: PortID
    
    private var cePort: PortID
    private var csnPort: PortID
    private var irqPort: PortID = InvalidPortID
    
    private var isPlusModel_ = false
    private var dynamicPayloadEnabled = true
    private var addressWidth_ = 5
    private var payloadSize_ = 32
    private var pipe0ReadingAddress: UInt64 = 0
    
    private var readCompletion: ((RF24Radio, Int, [UInt8]?) -> Void)?
    private var expectedPayloadSize = 32


    /**
     Creates a new instance.
 
     - Parameter device: Wirekite device
     
     - Parameter spiPort: port ID of the SPI bus
     
     - Parameter cePin: Wirekite pin number of the pin connected to the module's CE pin
     
     - Parameter csnPin: Wirkite pin number of the pin connected to the module's CSN pin
    */
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
    
    /**
        Initializes the module.
     
        Must be called before calling any other function or accessing properties
      */
    func initModule() {
        // Reset CONFIG and enable 16-bit CRC.
        write(value: RF24.CONFIG.EN_CRC | RF24.CONFIG.CRCO, toRegister: .CONFIG)
        
        setRetransmissions(count: 15, delay: 5)
        
        // check for connected module and if this is a p nRF24l01 variant
        dataRate = ._250kbps
        isPlusModel_ = dataRate == ._250kbps
        
        // Default speed
        dataRate = ._1mbps
        
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
        rfChannel = 76
        
        // Flush buffers
        discardReceivedPackets()
        discardQueuedTransmitPackets()
        
        powerUp() // Power up by default when begin() is called
        
        // Enable PTX, do not write CE high so radio will remain in standby I mode
        // (130us max to transition to RX or TX instead of 1500us from powerUp)
        // PTX should use only 22uA of power
        var config = read(fromRegister: .CONFIG)
        config &= ~RF24.CONFIG.PRIM_RX
        write(value: config, toRegister: .CONFIG)
    }
    
    
    // MARK: - Module configuration
    
    /**
     Configures the IRQ pin of the module.
     
     The module uses the IRQ pin to notify the host about events such as a recieved packet.
     
     If a payload size if 0 is specified, `nil` is passed in *packet* to the completion block.
     The completion block must then fetch the packet itself.
     
     - Parameter irqPin: Wirekit pin number of the pin connected to the module's IRQ pin
     
     - Parameter payloadSize: expected size of payload in received packets (in bytes)
     
     - Parameter completion: block called when a packet has been received
     
     - Parameter radio: the `RF24Radio` instance that has received the packet
     
     - Parameter pipe: the index of the pipe where the packet was received
     
     - Parameter packet: the received packet
    */
    func configureIRQPin(irqPin: Int, payloadSize: Int,  completion: @escaping (_ radio: RF24Radio, _ pipe: Int, _ packet: [UInt8]?) -> Void) {
        readCompletion = completion
        expectedPayloadSize = payloadSize
        irqPort = device!.configureDigitalInputPin(irqPin, attributes: .triggerFalling) {
            (_, _) in
            self.interruptTriggered()
        }
    }
    
    /**
     Address width (in bytes)
     
     Valid values are between 3 and 5. The default is 5.
    */
    var addressWidth: Int {
        get {
            return addressWidth_
        }
        
        set(newValue) {
            addressWidth_ = clamp(newValue, minValue: 3, maxValue: 5)
            write(value: UInt8(addressWidth_ - 2), toRegister: .SETUP_AW)
        }
    }
    
    /**
     Payload size (in bytes)
    */
    var payloadSize: Int {
        get {
            return payloadSize_
        }
        set(newValue) {
            payloadSize_ = clamp(newValue, minValue: 1, maxValue: 32)
        }
    }
    
    /**
     Gets the number of retransmissions and the delay between them
    
     Reading these values requires communication with the module.

     - Parameter count: the number of retransmissions.
     
     - Parameter delay: the delay between retransmission (in µs)
    */
    func getRetransmissions() -> (count: Int, delay: Int) {
        let value = read(fromRegister: .SETUP_RETR)
        let count = Int(value & 0x0f)
        let delay = (Int(value >> 4) - 1) * 250
        return (count, delay)
    }
    
    /**
     Sets the number of retransmissions and the retry delay
     
     The delay value will be rounded to a multiple of 250µs.
     Valid delay values are between 250µs and 4000µs.
     Valid values for `count` are between 0 (no retransmissions) and 15.
     
     - Parameter count: the number of retransmissions.

     - Parameter delay: the delay between retransmissions (in µs)
    */
    func setRetransmissions(count: Int, delay: Int) {
        let delayCode: Int = clamp((delay + 124) / 250 - 1, minValue: 0, maxValue: 15)
        let retransmissions = clamp(count, minValue: 0, maxValue: 15)
        let value = UInt8((delayCode << 4) | retransmissions)
        write(value: value, toRegister: .SETUP_RETR)
    }
    
    /**
     Data rate for transmissions
     
     Reading this property requires communication with the module.
    */
    var dataRate: DataRate {
        get {
            let value = read(fromRegister: .RF_SETUP)
            var rate: DataRate
            if (value & RF24.RF_SETUP.RF_DR_LOW) != 0 {
                rate = ._250kbps
            } else if (value & RF24.RF_SETUP.RF_DR_HIGH) != 0 {
                rate = ._2mbps
            } else {
                rate = ._1mbps
            }
            return rate
        }
        set(newValue) {
            var setup = read(fromRegister: .RF_SETUP)
            setup &= ~(RF24.RF_SETUP.RF_DR_LOW | RF24.RF_SETUP.RF_DR_HIGH)
            setup |= newValue == ._250kbps ? RF24.RF_SETUP.RF_DR_LOW : (newValue == ._2mbps ? RF24.RF_SETUP.RF_DR_HIGH : 0)
            write(value: setup, toRegister: .RF_SETUP)
        }
    }
    
    /**
     RF output power
     
     Reading this property requires communication with the module
    */
    var rfOutputPower: RFOutputPower {
        get {
            let value = (read(fromRegister: .RF_SETUP) >> 1) & 0x03
            return RFOutputPower(rawValue: Int(value))!
        }
        set(newValue) {
            var setup = read(fromRegister: .RF_SETUP)
            setup &= ~RF24.RF_SETUP.RF_PWR_MASK
            setup |= UInt8(newValue.rawValue) << 1
            write(value: setup, toRegister: .RF_SETUP)
        }
    }
    
    /**
     Value of NRF24L01+ status register
    */
    var statusRegister: UInt8 {
        get {
            return write(command: RF24.CMD.NOP)
        }
    }
    
    /**
    */
    var isConnected: Bool {
        get {
            let value = read(fromRegister: .SETUP_AW)
            return value >= 1 && value <= 3
        }
    }
    
    /**
     RF channel number.
     
     Valid channel numbers are between 0 and 125.
    */
    var rfChannel: Int {
        get {
            return Int(read(fromRegister: .RF_CH))
        }
        set(newValue) {
            if newValue >= 0 && newValue <= 125 {
                write(value: UInt8(newValue), toRegister: .RF_CH)
            }
        }
    }
    
    /**
     Enables auto acknowledge for all pipes
    */
    var autoAck: Bool {
        get {
            return read(fromRegister: .EN_AA) == 0x3f
        }
        set(newValue) {
            write(value: newValue ? 0x3f : 0, toRegister: .EN_AA)
        }
    }
    
    /**
     Indicates if the connected module is a plus model
     (NRF24L01+ as opposed to NRF24L01)
    */
    var isPlusModel: Bool {
        get {
            return isPlusModel_
        }
    }
    
    /**
     Powers the module down
    */
    func powerDown() {
        device!.writeDigitalPin(onPort: cePort, value: false, synchronizedWithSPIPort: spi)
        var config = read(fromRegister: .CONFIG)
        config &= ~RF24.CONFIG.PWR_UP
        write(value: config, toRegister: .CONFIG)
    }
    
    /**
     Powers the module up
    */
    func powerUp() {
        var config = read(fromRegister: .CONFIG)
        if (config & RF24.CONFIG.PWR_UP) == 0 {
            config |= RF24.CONFIG.PWR_UP
            write(value: config, toRegister: .CONFIG)
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
    
    
    // MARK: - Receiving
    
    /**
     Opens a pipe for receiving packets
     
     Addresses are between 2 and 5 bytes long (see `addressWidth`).
     So the most significant bits in `address` are ignored.
     
     Use pipe 1 as the primary receive channel as pipe 0 is mainly
     used to implement auto acknowledge.
     
     The address of pipes 2 to 5 must only differ from pipe 1 address
     in the least significant byte. Therefore, only the LSB is used
     for these pipes. The other bytes are ignored.
     
     - Parameter pipe: the pipe index (between 0 and 5)
     
     - Parameter address: the address of the pipe
    */
    func openReceivePipe(pipe: Int, address: UInt64) {
        if pipe < 0 || pipe > 6 {
            return
        }
        if pipe == 0 {
            pipe0ReadingAddress = address
        }
        
        let addrRegister = Register.RX_ADDR_P0.offset(by: pipe)
        if pipe < 2 {
            write(address: address, toRegister: addrRegister)
        } else {
            write(value: UInt8(address & 0xff), toRegister: addrRegister)
        }
        
        let payloadRegister = Register.RX_PW_P0.offset(by: pipe)
        write(value: UInt8(payloadSize_), toRegister: payloadRegister)
        
        var enRxAddr = read(fromRegister: .EN_RXADDR)
        enRxAddr |= UInt8(1 << pipe)
        write(value: enRxAddr, toRegister: .EN_RXADDR)
    }

    /**
     Closes the recieve pipe.
     
     - Parameter pipe: the pipe index (between 0 and 5)
    */
    func closeReceivePipe(pipe: Int) {
        var enRxAddr = read(fromRegister: .EN_RXADDR)
        enRxAddr &= ~UInt8(1 << pipe)
        write(value: enRxAddr, toRegister: .EN_RXADDR)
    }
    
    /**
     Indicates if a received packet is available and can be read
     
     Reading this property requires communication with the module.
     */
    var packetAvailable: Bool {
        get {
            let status = read(fromRegister: .FIFO_STATUS)
            return (status & RF24.FIFO_STATUS.RX_EMPTY) == 0
        }
    }
    
    /**
     Fetches the received packet from the module and removes it from the receive queue.
     
     The result is undefined if no packet has been received.
    */
    func fetchPacket(packetLength: Int) -> [UInt8] {
        let data = readPayload(numBytes: packetLength)
        write(value: RF24.STATUS.RX_DR, toRegister: .STATUS)
        return data
    }
    
    private func readPayload(numBytes: Int) -> [UInt8] {
        let plSize = min(numBytes, payloadSize_)
        let padSize = dynamicPayloadEnabled ? 0 : payloadSize_ - plSize
        
        var txData = [UInt8](repeating: RF24.CMD.NOP, count: plSize + padSize + 1)
        txData[0] = RF24.CMD.R_RX_PAYLOAD
        let rxData = transmitAndRequest(txData: txData)
        return Array(rxData[1..<plSize+1])
    }

    /**
     Discards all received packets from the receive queue
    */
    func discardReceivedPackets() {
        let _ = write(command: RF24.CMD.FLUSH_RX)
    }
    
    /**
     Starts to listen for incoming packets
    */
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
            closeReceivePipe(pipe: 0)
        }
        
        if (read(fromRegister: .FEATURE) & RF24.FEATURE.EN_ACK_PAY) != 0 {
            discardQueuedTransmitPackets()
        }
    }
    
    /**
     Stops listening for incoming packets
    */
    func stopListening() {
        device!.writeDigitalPin(onPort: cePort, value: false, synchronizedWithSPIPort: spi)
        
        let feature = read(fromRegister: .FEATURE)
        if (feature & RF24.FEATURE.EN_ACK_PAY) != 0 {
            discardQueuedTransmitPackets()
        }
        
        var config = read(fromRegister: .CONFIG)
        config &= ~RF24.CONFIG.PRIM_RX
        write(value: config, toRegister: .FEATURE)
        
        var enRxAddr = read(fromRegister: .EN_RXADDR)
        enRxAddr |= 1
        write(value: enRxAddr, toRegister: .EN_RXADDR)
    }
    
    
    // MARK: - Transmitting
    
    /**
     Opens the pipe for transmitting packets
     
     Addresses are between 2 and 5 bytes long (see `addressWidth`).
     So the most significant bits in `address` are ignored.
     
     - Parameter address: the address of the pipe
     */
    func openTransmitPipe(address: UInt64) {
        write(address: address, toRegister: .RX_ADDR_P0)
        write(address: address, toRegister: .TX_ADDR)
        write(value: UInt8(payloadSize_), toRegister: .RX_PW_P0)
    }
    

    /**
     Discard the packets queue for transmission
    */
    func discardQueuedTransmitPackets() {
        let _ = write(command: RF24.CMD.FLUSH_TX)
    }
    
    
    // MARK: - Low level
    
    private func interruptTriggered() {
        while true {
            let status = read(fromRegister: .STATUS)
            
            if (status & RF24.STATUS.RX_DR) != 0 {
                // packet arrived
                let pipe = Int((status >> 1) & 0x07)
                let data: [UInt8]?
                if expectedPayloadSize > 0 {
                    data = fetchPacket(packetLength: expectedPayloadSize)
                } else {
                    data = nil
                }
                readCompletion!(self, pipe, data)
            
            } else if (status & RF24.STATUS.TX_DS) != 0 {
                // packet transmitted
                write(value: RF24.STATUS.TX_DS, toRegister: .STATUS)
                
            } else if (status & RF24.STATUS.MAX_RT) != 0 {
                // maximum number of retransmissions reached
                write(value: RF24.STATUS.MAX_RT, toRegister: .STATUS)
                
            } else {
                // no further work
                break
            }
        }
    }
    

    private func addressToByteArray(address: UInt64) -> [UInt8] {
        // convert to byte array, LSB first
        var addr = address
        var bytes = [UInt8](repeating: 0, count: addressWidth_)
        for i in 0 ..< addressWidth_ {
            bytes[i] = UInt8(addr & 0xff)
            addr >>= 8
        }
        return bytes
    }
    
    fileprivate func toggleFeatures() {
        let data: [UInt8] = [ 0x50, 0x73 ]
        transmit(txData: data)
    }
    
    private func write(value: UInt8, toRegister register: Register) {
        let data: [UInt8] = [ writeCode(register: register), value ]
        transmit(txData: data)
    }
    
    private func write(address: UInt64, toRegister register: Register) {
        var data: [UInt8] = [ writeCode(register: register) ]
        data.append(contentsOf: addressToByteArray(address: address))
        transmit(txData: data)
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
    
    private func transmit(txData: [UInt8]) {
        let txPayload = Data(txData)
        device!.submit(onSPIPort: spi, data: txPayload, chipSelect: csnPort)
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
    
    // MARK: - Debugging information
    
    /**
     Writes information about the module's status register to the debug output
     */
    func debugRegisters() {
        
        // status
        debug(status: statusRegister)
        
        // addresses
        debug(addressRegister: .RX_ADDR_P0, addressLength: addressWidth_)
        debug(addressRegister: .RX_ADDR_P1, addressLength: addressWidth_)
        debug(byteRegisters: .RX_ADDR_P2, count: 4, label: "RX_ADDR_P2..5")
        debug(addressRegister: .TX_ADDR, addressLength: addressWidth_)
        
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
    
    fileprivate func debug(status: UInt8) {
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

}


fileprivate func clamp<T>(_ value: T, minValue: T, maxValue: T) -> T where T : Comparable {
    return min(max(value, minValue), maxValue)
}

