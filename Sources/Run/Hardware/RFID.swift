import Foundation
import SwiftyGPIO

typealias Byte = UInt8
typealias Bytes = [Byte]

protocol RFIDDelegate: AnyObject {
    func rfidDidScanTag(_ rfid: RFID, withResult result: Result<Bytes, Error>)
}

enum RFIDError: Error, LocalizedError {
    case request(String) // what do you do/mean?
    case anticoll(String) // should you have multiple?
    case cardWrite(String) // should you have multipl?
    
    var errorDescription: String? {
        switch self {
        case .request(let reason): return "ERROR: RFID Tag Request: \(reason)"
        case .anticoll(let reason): return "ERROR: RFID Anticollision: \(reason)"
        case .cardWrite(let reason): return "ERROR: RFID Card Write: \(reason)"
        }
    }
}

class RFID {
    
    /// pin_irq = 18
    private let irqGPIO: GPIO
    /// mode_idle = 0x00
    private let mode_idle: Byte = 0x00
    /// mode_transrec = 0x0C
    private let mode_transrec: Byte = 0x0C
    /// mode_reset = 0x0F
    private let mode_reset: Byte = 0x0F
    /// mode_crc = 0x03
    private let mode_crc: Byte = 0x03
    /// act_anticl = 0x93
    private let act_anticl: Byte = 0x93
    /// act_select = 0x93
    private let act_select: Byte = 0x93
    /// reg_tx_control = 0x14
    private let reg_tx_control: Byte = 0x14
    /// length = 16
    private let length: Byte = 16
    /// antenna_gain = 0x04
    private var antenna_gain: Byte = 0x04
    /// is scanning for tags
    private var ranging = false
    
    let spi: SPIInterface
    
    let waitTime: TimeInterval
    
    weak var delegate: RFIDDelegate?
    
    /// Created new RFID scanner
    /// - Parameters:
    ///   - spi: spi to perfom scanning from
    ///   - irqGPIO: GPIO for inturrupt
    ///   - waitTime: Amount fo seconds to resume scanning after tag found
    init(spi: SPIInterface, irqGPIO: GPIO, waitTime: TimeInterval) {
        self.spi = spi
        self.irqGPIO = irqGPIO
        self.waitTime = waitTime
        
        irqGPIO.direction = .IN
        irqGPIO.pull = .up
        
        self.configure()
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
                self.waitForTag()
                
                do {
                    let _ = try self.request()
                    let uid = try self.anticoll()
                    DispatchQueue.main.async {
                        self.delegate?.rfidDidScanTag(self, withResult: .success(uid))
                    }
                    sleep(UInt32(self.waitTime))
                } catch {
                    DispatchQueue.main.async {
                        self.delegate?.rfidDidScanTag(self, withResult: .failure(error))
                    }
                    sleep(1)
                }
            }
        }
    }
    
    func stopScanningForTags() {
        ranging = false
    }
    
    func cleanup() {
        stopScanningForTags()
        irqGPIO.direction = .IN
        irqGPIO.value = 0
        irqGPIO.clearListeners()
    }
    
    deinit {
        cleanup()
    }
    
    private func configure() {
        self.reset()                                            // "soft reset" by writing 0x0F to CommandReg
        self.devWrite(address: 0x2A, value: 0x8D)               // TModeReg - timer settings
        self.devWrite(address: 0x2B, value: 0x3E)               // TPrescalerReg - set ftimer = 13.56MHz/(2*TPrescaler+2)
        self.devWrite(address: 0x2D, value: 30)                 // TReloadReg - set timer reload value
        self.devWrite(address: 0x2C, value: 0)
        self.devWrite(address: 0x15, value: 0x40)               // TxASKReg - force 100% ASK modulation
        self.devWrite(address: 0x11, value: 0x3D)               // ModeReg - general settings for Tx and Rx
        self.devWrite(address: 0x26, value: antenna_gain << 4)  // RFCfgReg - set Rx's voltage gain factor
        self.setAntenna(true)
    }
    
    private func devWrite(address: Byte, value: Byte) {
        spi.sendData([(address << 1) & 0x7E, value], frequencyHz: 1_000_000)
    }
    
    private func devRead(address: Byte) -> Byte {
        return spi.sendDataAndRead([((address << 1) & 0x7E) | 0x80, 0], frequencyHz: 1_000_000)[1]
    }
    
    private func setBitmask(address: Byte, mask: Byte) {
        let current = devRead(address: address)
        devWrite(address: address, value: current | mask)
    }
    
    private func clearBitmask(address: Byte, mask: Byte) {
        let current = devRead(address: address)
        devWrite(address: address, value: current & ~mask)
    }
    
    private func setAntenna(_ bool: Bool) {
        if bool {
            let current = devRead(address: reg_tx_control)
            if !((current & 0x03) == 1) {
                setBitmask(address: reg_tx_control, mask: 0x03)
            }
        } else {
            clearBitmask(address: reg_tx_control, mask: 0x03)
        }
    }
    
    private func setAntennaGain(gain: Byte) {
        // only set safe values to antenna
        if (0x00...0x07).contains(gain) {
            antenna_gain = gain
        }
    }
    
    private func reset() {
        devWrite(address: 0x01, value: mode_reset)
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
    
    func request(mode: Byte = 0x26) throws -> Byte {
        devWrite(address: 0x0D, value: 0x07) // start transmission
        
        var err = "Request error"
        
        for i in 0...99 {
            do {
                let (_, backBits) = try cardWrite(data: [mode])
                if backBits != 0x10 {
                    err = "Bad back bits: \(backBits) != 0x10"
                } else {
                    return backBits
                }
            } catch {
                err = error.localizedDescription
            }
            
            if i == 99 {
                throw RFIDError.request("No bueno - request did not succeed in 100 tries")
            }
        }
        
        throw RFIDError.request(err)
    }
    
    func anticoll() throws -> Bytes {
        devWrite(address: 0x0D, value: 0x00) // what do you do
        
        var err = "Anticol error"
        
        for i in 0...4 {
            do {
                let (backData, _) = try cardWrite(data: [act_anticl, 0x20]) // why
                
                guard backData.count == 5 else {
                    throw RFIDError.anticoll("Backdata count \(backData.count) != 5")
                }
                
                var serialNumberCheck: Byte = 0x00
                
                (0...3).forEach { i in
                    serialNumberCheck = serialNumberCheck ^ backData[i]
                }
                
                if serialNumberCheck != backData[4] {
                    err = "serialNumberCheck != backData[4]"
                } else {
                    return backData
                }
                
                if i == 4 {
                    throw RFIDError.anticoll("No bueno - anticoll did not succeed in 100 tries")
                }
            } catch {
                err = error.localizedDescription
            }
        }
        
        throw RFIDError.anticoll(err)
    }
    
    // https://www.programiz.com/swift-programming/bitwise-operators
    // https://developerinsider.co/advanced-operators-bitwise-by-example-swift-programming-language/
    func cardWrite(data: Bytes) throws -> (Bytes, Byte) {
        devWrite(address: 0x02, value: 0x77 | 0x80)      // enable IRQs: timer, error, low alert, idle, rx, tx
        clearBitmask(address: 0x04, mask: 0x80)         // clear interrupts
        setBitmask(address: 0x0A, mask: 0x80)           // clear FIFO
        devWrite(address: 0x01, value: mode_idle)       // put chip in idle mode
        
        data.forEach { byte in
            devWrite(address: 0x09, value: byte)        // write data to FIFO
        }
        
        devWrite(address: 0x01, value: mode_transrec)   // set desired mode of operation
        setBitmask(address: 0x0D, mask: 0x80)           // start transmission
        
        // 2000 in python, seems arbitrary just so it doesnt hang forever
        var i = 2000
        var n: Byte = 0x00
        while true {
            n = devRead(address: 0x04) // poll IRQs
            i -= 1
            
            let a = ~Int8(n & 0x01) // python is treating this as an Int not UInt
            let b = ~Int8(n & 0x30) // python is treating this as an Int not UInt
            
            if ~(a & b) != 0 {
                break
            }
        }
        
        clearBitmask(address: 0x0D, mask: 0x80)
        
        var backData: Bytes = []
        var backLength: Byte = 0x00
        
        if i != 0 {
            if (devRead(address: 0x06) & 0x1B) != 0x00 {
                throw RFIDError.cardWrite("E2")
            }
            
            if (n & 0x77 & 0x01) != 0x00 {
                throw RFIDError.cardWrite("E1: time out")
            }
            
            n = devRead(address: 0x0A)
            
            let lastBits = devRead(address: 0x0C) & 0x07
            
            if lastBits != 0x00 {
                backLength = (n - 1) * 8 + lastBits
            } else {
                backLength = n * 8
            }
            
            if n == 0x00 {
                n = 1
            }
            
            if n > length {
                n = length
            }
            
            (0..<n).forEach { _ in
                let byte = devRead(address: 0x09)
                backData.append(byte)
            }
        }
        
        return (backData, backLength)
    }
    
    // MARK: - Todo
    
    // TODO: figure out if we want to use this
    /* dont know if we use you
    /// ```
    /// def calculate_crc(self, data):
    ///     self.clear_bitmask(0x05, 0x04)
    ///     self.set_bitmask(0x0A, 0x80)
    ///
    ///     for i in range(len(data)):
    ///         self.dev_write(0x09, data[i])
    ///     self.dev_write(0x01, self.mode_crc)
    ///
    ///     i = 255
    ///     while True:
    ///         n = self.dev_read(0x05)
    ///         i -= 1
    ///         if not ((i != 0) and not (n & 0x04)):
    ///             break
    ///
    ///     ret_data = []
    ///     ret_data.append(self.dev_read(0x22))
    ///     ret_data.append(self.dev_read(0x21))
    ///
    ///     return ret_data
    /// ```
    func calculateCrc(data: Bytes) -> Bytes {
        print("caclulate crc: \(data)")
        clearBitmask(address: 0x05, mask: 0x04)
        setBitmask(address: 0x0A, mask: 0x80)
        
        data.forEach { byte in
            devWrite(address: 0x09, value: byte)
        }
        
        devWrite(address: 0x01, value: mode_crc)
        
        var i = 255
        while true {
            let n = devRead(address: 0x05)
            i -= 1
            
            if !((i != 0) && !((n & 0x04) == 1)) {
                break
            }
        }
        
        var data = Bytes()
        data.append(devRead(address: 0x22))
        data.append(devRead(address: 0x21))
        
        return data
    }
    
    /// ```
    /// def select_tag(self, uid):
    ///     """
    ///     Selects tag for further usage.
    ///     uid -- list or tuple with four bytes tag ID
    ///     Returns error state.
    ///     """
    ///     back_data = []
    ///     buf = []
    ///
    ///     buf.append(self.act_select)
    ///     buf.append(0x70)
    ///
    ///     for i in range(5):
    ///         buf.append(uid[i])
    ///
    ///     crc = self.calculate_crc(buf)
    ///     buf.append(crc[0])
    ///     buf.append(crc[1])
    ///
    ///     (error, back_data, back_length) = self.card_write(self.mode_transrec, buf)
    ///
    ///     if (not error) and (back_length == 0x18):
    ///         return False
    ///     else:
    ///         return True
    /// ```
    func selectTag(uid: Bytes) -> Bool {
        print("select tag: \(uid)")
        var buffer = Bytes()
        buffer.append(act_select)
        buffer.append(0x70)
        
        (0...4).forEach { i in
            buffer.append(uid[i])
        }
        
        let crc = calculateCrc(data: buffer)
        buffer.append(crc[0])
        buffer.append(crc[1])
        
        let (_, backLength, error) = cardWrite(command: mode_transrec, data: buffer)
        if (!error) && (backLength == 0x18) {
            return false
        } else {
            return true
        }
    }
    */
}

