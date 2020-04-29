import Foundation
import SwiftyGPIO

typealias Byte = UInt8
typealias Bytes = [Byte]

protocol RFIDDelegate: AnyObject {
    func rfidDidScanTag(_ rfid: RFID, withResult result: Result<Bytes, Error>)
}

enum RFIDError: Error, LocalizedError {
    case request(Byte) // what do you do/mean?
    case anticoll(Byte) // should you have multiple?
    case cardWrite(Byte) // should you have multipl?
    case selectTag(Byte)
    case auth(Byte)
    case read(Byte)
    case write(Byte)
    
    var errorDescription: String? {
        switch self {
        case .request(let reason): return "ERROR: RFID Tag Request: \(reason)"
        case .anticoll(let reason): return "ERROR: RFID Anticollision: \(reason)"
        case .cardWrite(let reason): return "ERROR: RFID Card Write: \(reason)"
        case .selectTag(let reason): return "ERROR: RFID Select Tag: \(reason)"
        case .auth(let reason): return "ERROR: RFID Auth: \(reason)"
        case .read(let reason): return "ERROR: RFID Read: \(reason)"
        case .write(let reason): return "ERROR: RFID Write: \(reason)"
        }
    }
}

class RFID {
    
    private let irqGPIO: GPIO
    /// antenna_gain = 0x04
    private var antenna_gain: Byte = 0x04
    /// is scanning for tags
    private var ranging = false
    
    let spi: SPIInterface
    
    let waitTime: TimeInterval
    
    weak var delegate: RFIDDelegate?
    
    private let MAX_LEN: Int                = 16
    
    private let PCD_IDLE: Byte              = 0x00
    private let PCD_AUTHENT: Byte           = 0x0E
    private let PCD_RECEIVE: Byte           = 0x08
    private let PCD_TRANSMIT: Byte          = 0x04
    private let PCD_TRANSCEIVE: Byte        = 0x0C
    private let PCD_RESETPHASE: Byte        = 0x0F
    private let PCD_CALCCRC: Byte           = 0x03
    
    private let PICC_REQIDL: Byte           = 0x26
    private let PICC_REQALL: Byte           = 0x52
    private let PICC_ANTICOLL: Byte         = 0x93
    private let PICC_SElECTTAG: Byte        = 0x93
    private let PICC_AUTHENT1A: Byte        = 0x60
    private let PICC_AUTHENT1B: Byte        = 0x61
    private let PICC_READ: Byte             = 0x30
    private let PICC_WRITE: Byte            = 0xA0
    private let PICC_DECREMENT: Byte        = 0xC0
    private let PICC_INCREMENT: Byte        = 0xC1
    private let PICC_RESTORE: Byte          = 0xC2
    private let PICC_TRANSFER: Byte         = 0xB0
    private let PICC_HALT: Byte             = 0x50
    
    private let MI_OK: Byte                 = 0
    private let MI_NOTAGERR: Byte           = 1
    private let MI_ERR: Byte                = 2
    
    private let Reserved00: Byte            = 0x00
    private let CommandReg: Byte            = 0x01
    private let CommIEnReg: Byte            = 0x02
    private let DivlEnReg: Byte             = 0x03
    private let CommIrqReg: Byte            = 0x04
    private let DivIrqReg: Byte             = 0x05
    private let ErrorReg: Byte              = 0x06
    private let Status1Reg: Byte            = 0x07
    private let Status2Reg: Byte            = 0x08
    private let FIFODataReg: Byte           = 0x09
    private let FIFOLevelReg: Byte          = 0x0A
    private let WaterLevelReg: Byte         = 0x0B
    private let ControlReg: Byte            = 0x0C
    private let BitFramingReg: Byte         = 0x0D
    private let CollReg: Byte               = 0x0E
    private let Reserved01: Byte            = 0x0F
    
    private let Reserved10: Byte            = 0x10
    private let ModeReg: Byte               = 0x11
    private let TxModeReg: Byte             = 0x12
    private let RxModeReg: Byte             = 0x13
    private let TxControlReg: Byte          = 0x14
    private let TxAutoReg: Byte             = 0x15
    private let TxSelReg: Byte              = 0x16
    private let RxSelReg: Byte              = 0x17
    private let RxThresholdReg: Byte        = 0x18
    private let DemodReg: Byte              = 0x19
    private let Reserved11: Byte            = 0x1A
    private let Reserved12: Byte            = 0x1B
    private let MifareReg: Byte             = 0x1C
    private let Reserved13: Byte            = 0x1D
    private let Reserved14: Byte            = 0x1E
    private let SerialSpeedReg: Byte        = 0x1F
    
    private let Reserved20: Byte            = 0x20
    private let CRCResultRegM: Byte         = 0x21
    private let CRCResultRegL: Byte         = 0x22
    private let Reserved21: Byte            = 0x23
    private let ModWidthReg: Byte           = 0x24
    private let Reserved22: Byte            = 0x25
    private let RFCfgReg: Byte              = 0x26
    private let GsNReg: Byte                = 0x27
    private let CWGsPReg: Byte              = 0x28
    private let ModGsPReg: Byte             = 0x29
    private let TModeReg: Byte              = 0x2A
    private let TPrescalerReg: Byte         = 0x2B
    private let TReloadRegH: Byte           = 0x2C
    private let TReloadRegL: Byte           = 0x2D
    private let TCounterValueRegH: Byte     = 0x2E
    private let TCounterValueRegL: Byte     = 0x2F
    
    private let Reserved30: Byte            = 0x30
    private let TestSel1Reg: Byte           = 0x31
    private let TestSel2Reg: Byte           = 0x32
    private let TestPinEnReg: Byte          = 0x33
    private let TestPinValueReg: Byte       = 0x34
    private let TestBusReg: Byte            = 0x35
    private let AutoTestReg: Byte           = 0x36
    private let VersionReg: Byte            = 0x37
    private let AnalogTestReg: Byte         = 0x38
    private let TestDAC1Reg: Byte           = 0x39
    private let TestDAC2Reg: Byte           = 0x3A
    private let TestADCReg: Byte            = 0x3B
    private let Reserved31: Byte            = 0x3C
    private let Reserved32: Byte            = 0x3D
    private let Reserved33: Byte            = 0x3E
    private let Reserved34: Byte            = 0x3F
    
    /// Created new RFID scanner
    /// - Parameters:
    ///   - spi: spi to perfom scanning from
    ///   - irqGPIO: GPIO for inturrupt
    ///   - waitTime: Amount fo seconds to resume scanning after tag found
    init(spi: SPIInterface, irqGPIO: GPIO, waitTime: TimeInterval) {
        irqGPIO.direction = .IN
        irqGPIO.pull = .up
        
        self.spi = spi
        self.irqGPIO = irqGPIO
        self.waitTime = waitTime
        self.configure()
    }
    
    deinit {
        cleanup()
    }
    
    /// Dispatches onto custom utility queue, where it blocks
    /// on `waitForTag()` until a tag is found, then attempts
    /// to read the tag, signalling the delegate on success or error
    /// back on the main queue
    func startScanningForTags() {
        ranging = true
        
        let queue = DispatchQueue.init(label: "com.hiimtmac.scanner", qos: .utility)
        queue.async { [weak self] in
            guard let self = self else { return }
            while self.ranging {
                print("Wait for tag...")
                // this will block until iqr is triggered
                self.waitForTag()
                
                // try a bunch of times before bailing out
                let tries = 100
                for i in 1...tries {
                    do {
                        // scan for cards
                        let _ = try self.request()
                        
                        // get the UID of the card
                        let uid = try self.anticoll()
                        
                        // This is the default key for authentication
//                        let key: [Byte] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
                        
                        // Select the scanned tag
//                        let tag = try self.selectTag(serNum: uid)
                        
                        DispatchQueue.main.async {
                            self.delegate?.rfidDidScanTag(self, withResult: .success(uid))
                        }
                        sleep(UInt32(self.waitTime))
                        break
                    } catch {
                        if i == tries {
                            DispatchQueue.main.async {
                                self.delegate?.rfidDidScanTag(self, withResult: .failure(error))
                            }
                            sleep(1)
                        }
                    }
                }
            }
        }
    }
    
    func stopScanningForTags() {
        ranging = false
    }
    
    private func configure() {
        self.reset()                                            // "soft reset" by writing 0x0F to CommandReg
        
        self.devWrite(address: TModeReg, value: 0x8D)           // TModeReg - timer settings
        self.devWrite(address: TPrescalerReg, value: 0x3E)      // TPrescalerReg - set ftimer = 13.56MHz/(2*TPrescaler+2)
        self.devWrite(address: TReloadRegL, value: 30)          // TReloadReg - set timer reload value
        self.devWrite(address: TReloadRegH, value: 0)
        self.devWrite(address: TxAutoReg, value: 0x40)          // TxASKReg - force 100% ASK modulation
        self.devWrite(address: ModeReg, value: 0x3D)            // ModeReg - general settings for Tx and Rx
        
//        self.devWrite(address: 0x26, value: antenna_gain << 4)  // RFCfgReg - set Rx's voltage gain factor
        self.setAntennaOn()
    }
    
    func cleanup() {
        stopScanningForTags()
        irqGPIO.direction = .IN
        irqGPIO.value = 0
        irqGPIO.clearListeners()
        setAntennaOff()
    }
    
    private func devWrite(address: Byte, value: Byte) {
        spi.sendData([
            (address << 1) & 0x7E,
            value
        ], frequencyHz: 1_000_000)
    }
    
//    func write(address: Byte, data: Bytes) throws {
//        var buff1: [Byte] = [
//            PICC_WRITE,
//            address
//        ]
//
//        let crc1 = calulateCRC(data: buff1)
//        buff1.append(crc1[0])
//        buff1.append(crc1[1])
//
//        let (backData1, backLen1) = try cardWrite(command: PCD_TRANSCEIVE, data: buff1)
//
//        if backLen1 != 4 || (backData1[0] & 0x0F) != 0x0A {
//            throw RFIDError.write(MI_ERR)
//        }
//
//        print("\(backLen1) backdata & 0x0F == 0x0A \(backData1[0] & 0x0F)")
//
//        var buff2: [Byte] = []
//        for i in 0 ..< 16 {
//            buff2.append(data[i])
//        }
//
//        let crc2 = calulateCRC(data: buff2)
//        buff2.append(crc2[0])
//        buff2.append(crc2[1])
//
//        let (backData2, backLen2) = try cardWrite(command: PCD_TRANSCEIVE, data: buff2)
//
//        if backLen2 != 4 || (backData2[0] & 0x0F) != 0x0A {
//            throw RFIDError.write(MI_ERR)
//        }
//    }
    
    private func devRead(address: Byte) -> Byte {
        spi.sendDataAndRead([
            ((address << 1) & 0x7E) | 0x80,
            0
        ], frequencyHz: 1_000_000)[1]
    }
    
//    func read(address: Byte) throws -> Bytes {
//        var recvData: [Byte] = [
//            PICC_READ,
//            address
//        ]
//
//        let pOut = calulateCRC(data: recvData)
//        recvData.append(pOut[0])
//        recvData.append(pOut[1])
//
//        let (backData, _) = try cardWrite(command: PCD_TRANSCEIVE, data: recvData)
//
//        if backData.count == 16 {
//            print("Sector \(address) -> \(backData.map { String(format: "%02hhx", $0) }.joined(separator: ", "))")
//            return backData
//        } else {
//            throw RFIDError.read(MI_ERR)
//        }
//    }
    
    private func setBitmask(address: Byte, mask: Byte) {
        let current = devRead(address: address)
        devWrite(address: address, value: current | mask)
    }
    
    private func clearBitmask(address: Byte, mask: Byte) {
        let current = devRead(address: address)
        devWrite(address: address, value: current & ~mask)
    }
    
    private func setAntennaOn() {
        let current = devRead(address: TxControlReg)
        if ~(current & 0x03) != 0 {
            setBitmask(address: TxControlReg, mask: 0x03)
        }
    }
    
    private func setAntennaOff() {
        clearBitmask(address: TxControlReg, mask: 0x03)
    }
    
    private func setAntennaGain(gain: Byte) {
        // only set safe values to antenna
        if (0x00...0x07).contains(gain) {
            antenna_gain = gain
        }
    }
    
    private func reset() {
        devWrite(address: CommandReg, value: PCD_RESETPHASE)
    }
    
    /// This function is synchronous and will block its thread until
    /// it finds a tag, which will release its semaphore in the IRQ GPIO
    /// `onFalling(_:)` method
    private func waitForTag() {
        let semaphore = DispatchSemaphore(value: 0)
        
        irqGPIO.onFalling { gpio in
            semaphore.signal()
        }
        
        configure()
        
        var waiting = true
        while waiting {
            devWrite(address: 0x04, value: 0x00) // clear interrupts
            devWrite(address: 0x02, value: 0xA0) // enable RxIRQ only
            
            devWrite(address: 0x09, value: 0x26) // write something to FIFO
            devWrite(address: 0x01, value: 0x0C) // TRX Mode: tx data in FIFO to antenna, then activate Rx
            devWrite(address: 0x0D, value: 0x87) // start transmission
            
            waiting = semaphore.wait(timeout: .init(uptimeNanoseconds: 100_000_000)) == .timedOut
        }
        
        configure()
    }
    
    private func cardWrite(command: Byte, data: Bytes) throws -> (backData: Bytes, backLen: Int) {
        var irqEn: Byte = 0x00
        var waitIRq: Byte = 0x00

        if command == PCD_AUTHENT {
            irqEn = 0x12
            waitIRq = 0x10
        }

        if command == PCD_TRANSCEIVE {
            irqEn = 0x77
            waitIRq = 0x30
        }

        devWrite(address: CommIEnReg, value: irqEn | 0x80)
        clearBitmask(address: CommIrqReg, mask: 0x80)
        setBitmask(address: FIFOLevelReg, mask: 0x80)
        devWrite(address: CommandReg, value: PCD_IDLE)

        data.forEach { byte in
            devWrite(address: FIFODataReg, value: byte)
        }

        devWrite(address: CommandReg, value: command)

        if command == PCD_TRANSCEIVE {
            setBitmask(address: BitFramingReg, mask: 0x80)
        }

        var i = 2000
        var n: Byte = 0x00
        repeat {
            n = devRead(address: CommIrqReg)
            i -= 1
        } while !(i == 0 || (n & 0x01) != 0 || (n & waitIRq) != 0)

        clearBitmask(address: BitFramingReg, mask: 0x80)

        if i != 0 && (devRead(address: ErrorReg) & 0x1B) == 0x00 {
            if (n & irqEn & 0x01) != 0 {
                throw RFIDError.cardWrite(MI_NOTAGERR)
            }

            var backData: [Byte] = []
            var backLen = 0
            
            if command == PCD_TRANSCEIVE {
                var size = Int(devRead(address: FIFOLevelReg))
                let lastBits = Int(devRead(address: ControlReg) & 0x07)

                if lastBits != 0 {
                    backLen = (size - 1) * 8 + lastBits
                } else {
                    backLen = size * 8
                }

                if size == 0 { size = 1 }
                if size > MAX_LEN { size = MAX_LEN }
                for _ in 0 ..< size {
                    backData.append(devRead(address: FIFODataReg))
                }
            }
            
            return (backData: backData, backLen: backLen)
        } else {
            throw RFIDError.cardWrite(MI_ERR)
        }
    }
    
    /// gets tag type
    private func request(mode: Byte = 0x26) throws -> Int {
        devWrite(address: BitFramingReg, value: 0x07) // start transmission
        
        let (_, backLen) = try cardWrite(command: PCD_TRANSCEIVE, data: [mode])
        
        if backLen != 0x10 {
            throw RFIDError.request(MI_OK)
        } else {
            return backLen
        }
    }
    
    /// gets uid of tag
    private func anticoll() throws -> Bytes {
        devWrite(address: BitFramingReg, value: 0x00)
        
        let (backData, _) = try cardWrite(command: PCD_TRANSCEIVE, data: [PICC_ANTICOLL, 0x20])
        
        guard backData.count == 5, backData.dropLast().reduce(0, ^) == backData.last else {
            throw RFIDError.anticoll(MI_ERR)
        }
        
        return backData
    }
    
//    private func calulateCRC(data: [Byte]) -> [Byte] {
//        clearBitmask(address: DivIrqReg, mask: 0x04)
//        setBitmask(address: FIFOLevelReg, mask: 0x80)
//
//        data.forEach { byte in
//            devWrite(address: FIFODataReg, value: byte)
//        }
//
//        devWrite(address: CommandReg, value: PCD_CALCCRC)
//
//        var i = 0xFF
//        var n: Byte
//        repeat {
//            n = devRead(address: DivIrqReg)
//            i = i - 1
//        } while ((i != 0) && (n & 0x04) == 0)
//
//        return [
//            devRead(address: CRCResultRegL),
//            devRead(address: CRCResultRegM)
//        ]
//    }
    
//    private func selectTag(serNum: Bytes) throws -> Byte {
//        var buf: [Byte] = [PICC_SElECTTAG, 0x70]
//        for i in 0 ..< 5 {
//            buf.append(serNum[i])
//        }
//
//        let pOut = calulateCRC(data: buf)
//        buf.append(pOut[0])
//        buf.append(pOut[1])
//
//        let (backData, backLen) = try cardWrite(command: PCD_TRANSCEIVE, data: buf)
//
//        if backLen == 0x18 {
//            print("Size: \(backData[0])")
//            return backData[0]
//        } else {
//            throw RFIDError.selectTag(MI_ERR)
//        }
//    }
    
//    private func auth(authMode: Byte, blockAddr: Byte, sectorkey: [Byte], serNum: [Byte]) throws {
//        var buff: [Byte] = []
//
//        // First byte should be the authMode (A or B)
//        buff.append(authMode)
//
//        // Second byte is the trailerBlock (usually 7)
//        buff.append(blockAddr)
//
//        // Now we need to append the authKey which usually is 6 bytes of 0xFF
//        buff.append(contentsOf: sectorkey)
//
//        // Next we append the first 4 bytes of the UID
//        for i in 0 ..< 4 {
//            buff.append(serNum[i])
//        }
//
//        // Now we start the authentication itself
//        let (_, _) = try cardWrite(command: PCD_AUTHENT, data: buff)
//
//        if (devRead(address: Status2Reg) & 0x08) == 0 {
//            print("AUTH ERROR(status2reg & 0x08) != 0")
//            throw RFIDError.auth(MI_ERR)
//        }
//    }
    
//    private func stopCrypto() {
//        clearBitmask(address: Status2Reg, mask: 0x08)
//    }
    
//    private func dumpClassic1K(key: [Byte], uid: [Byte]) throws {
//        for i: Byte in 0 ..< 64 {
//            try auth(authMode: PICC_AUTHENT1A, blockAddr: i, sectorkey: key, serNum: uid)
//            let _ = try read(address: i)
//        }
//    }
}
