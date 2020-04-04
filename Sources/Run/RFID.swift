import Foundation
import SwiftyGPIO

typealias Byte = UInt8
typealias Bytes = [Byte]

class RFID {
    
    /// pin_rst = 22
    /// pin_ce = 0
    /// pin_irq = 18
    private let pin_irq: GPIO

    /// mode_idle = 0x00
    private let mode_idle: Byte = 0x00
    /// mode_auth = 0x0E
    /// mode_receive = 0x08
    /// mode_transmit = 0x04
    /// mode_transrec = 0x0C
    private let mode_transrec: Byte = 0x0C
    /// mode_reset = 0x0F
    private let mode_reset: Byte = 0x0F
    /// mode_crc = 0x03
    private let mode_crc: Byte = 0x03

    /// auth_a = 0x60
    /// auth_b = 0x61

    /// act_read = 0x30
    /// act_write = 0xA0
    /// act_increment = 0xC1
    /// act_decrement = 0xC0
    /// act_restore = 0xC2
    /// act_transfer = 0xB0

    /// act_reqidl = 0x26
    /// act_reqall = 0x52
    /// act_anticl = 0x93
    private let act_anticl: Byte = 0x93
    /// act_select = 0x93
    private let act_select: Byte = 0x93
    /// act_end = 0x50

    /// reg_tx_control = 0x14
    private let reg_tx_control: Byte = 0x14
    /// length = 16
    private let length: Byte = 16

    /// antenna_gain = 0x04
    private var antenna_gain: Byte = 0x04

    /// authed = False
    private var authed = false
    ///irq = threading.Event()
    private let semaphore: DispatchSemaphore
    
    let spi: SPIInterface
    
    /// ```
    /// def __init__(self, bus=0, device=0, speed=1000000, pin_rst=def_pin_rst,
    ///         pin_ce=0, pin_irq=def_pin_irq, pin_mode = def_pin_mode):
    ///     self.pin_rst = pin_rst
    ///     self.pin_ce = pin_ce
    ///     self.pin_irq = pin_irq
    ///
    ///     self.spi = SPIClass()
    ///     self.spi.open(bus, device)
    ///     self.spi.max_speed_hz = speed
    ///
    ///     if pin_mode is not None:
    ///         GPIO.setmode(pin_mode)
    ///     if pin_rst != 0:
    ///         GPIO.setup(pin_rst, GPIO.OUT)
    ///         GPIO.output(pin_rst, 1)
    ///     GPIO.setup(pin_irq, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    ///     GPIO.add_event_detect(pin_irq, GPIO.FALLING,
    ///             callback=self.irq_callback)
    ///     if pin_ce != 0:
    ///         GPIO.setup(pin_ce, GPIO.OUT)
    ///         GPIO.output(pin_ce, 1)
    ///     self.init()
    /// ```
    init(spi: SPIInterface, gpio: GPIO) {
        self.spi = spi
        self.pin_irq = gpio
        
        let semaphore = DispatchSemaphore(value: 1)
        self.semaphore = semaphore
        
        gpio.direction = .IN
        gpio.pull = .up
        gpio.onFalling { _ in
            semaphore.signal()
        }
        
        self.configure()
    }
    
    /// ```
    /// def init(self):
    ///     self.reset()                    # "soft reset" by writing 0x0F to CommandReg
    ///     self.dev_write(0x2A, 0x8D)      # TModeReg - timer settings
    ///     self.dev_write(0x2B, 0x3E)      # TPrescalerReg - set ftimer = 13.56MHz/(2*TPrescaler+2)
    ///     self.dev_write(0x2D, 30)        # TReloadReg - set timer reload value
    ///     self.dev_write(0x2C, 0)         #      "
    ///     self.dev_write(0x15, 0x40)      # TxASKReg - force 100% ASK modulation
    ///     self.dev_write(0x11, 0x3D)      # ModeReg - general settings for Tx and Rx
    ///     self.dev_write(0x26, (self.antenna_gain<<4))    # RFCfgReg - set Rx's voltage gain factor
    ///     self.set_antenna(True)
    /// ```
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
    
    /// ```
    /// def spi_transfer(self, data):
    ///     if self.pin_ce != 0:
    ///         GPIO.output(self.pin_ce, 0)     # set chip select for SPI
    ///     r = self.spi.xfer2(data)            # SPI transfer, chip select held active between blocks
    ///     if self.pin_ce != 0:
    ///         GPIO.output(self.pin_ce, 1)     # release chip select
    ///     return r
    /// ```
    func spiTransfer(data: Bytes) {
        preconditionFailure("This method is not needed as the SPI is injected into this class")
    }
    
    /// ```
    /// def dev_write(self, address, value):
    ///     self.spi_transfer([(address << 1) & 0x7E, value]) # append 0 to address (LSB) and set MSB = 0
    /// ```
    func devWrite(address: Byte, value: Byte) {
        print("writing: \(value) to \(address)...")
        spi.sendData([(address << 1) & 0x7E, value], frequencyHz: 1_000_000)
    }
    
    /// ```
    /// def dev_read(self, address):
    ///     return self.spi_transfer([((address << 1) & 0x7E) | 0x80, 0])[1] # append 0 to address (LSB) and set MSB = 1
    /// ```
    func devRead(address: Byte) -> Byte {
        print("reading: \(address)...")
        return spi.sendDataAndRead([((address << 1) & 0x7E) | 0x80, 0], frequencyHz: 1_000_000)[1]
    }
    
    /// ```
    /// def set_bitmask(self, address, mask):
    ///     current = self.dev_read(address)
    ///     self.dev_write(address, current | mask)
    /// ```
    func setBitmask(address: Byte, mask: Byte) {
        let current = devRead(address: address)
        devWrite(address: address, value: current | mask)
    }
    
    /// ```
    /// def clear_bitmask(self, address, mask):
    ///     current = self.dev_read(address)
    ///     self.dev_write(address, current & (~mask))
    /// ```
    func clearBitmask(address: Byte, mask: Byte) {
        let current = devRead(address: address)
        devWrite(address: address, value: current & (~mask))
    }
    
    /// ```
    /// def set_antenna(self, state):
    ///     if state == True:
    ///         current = self.dev_read(self.reg_tx_control)
    ///         if ~(current & 0x03):
    ///             self.set_bitmask(self.reg_tx_control, 0x03)
    ///     else:
    ///         self.clear_bitmask(self.reg_tx_control, 0x03)
    /// ```
    func setAntenna(_ bool: Bool) {
        if bool {
            let current = devRead(address: reg_tx_control)
            if (current & 0x03) == 1 {
                setBitmask(address: reg_tx_control, mask: 0x03)
            }
        } else {
            clearBitmask(address: reg_tx_control, mask: 0x03)
        }
    }
    
    /// ```
    /// def set_antenna_gain(self, gain):
    ///     """
    ///     Sets antenna gain from a value from 0 to 7.
    ///     """
    ///     if 0 <= gain <= 7:
    ///         self.antenna_gain = gain
    /// ```
    func setAntennaGain(gain: Byte) {
        if (0...7).contains(gain) {
            antenna_gain = gain
        }
    }
    
    /// ```
    /// def card_write(self, command, data):
    ///     back_data = []
    ///     back_length = 0
    ///     error = False
    ///     irq = 0x00
    ///     irq_wait = 0x00
    ///     last_bits = None
    ///     n = 0
    ///
    ///     if command == self.mode_transrec:
    ///         irq = 0x77
    ///         irq_wait = 0x30
    ///
    ///     self.dev_write(0x02, irq | 0x80)    # enable IRQs: timer, error, low alert, idle, rx, tx
    ///     self.clear_bitmask(0x04, 0x80)      # clear interrupts
    ///     self.set_bitmask(0x0A, 0x80)        # clear FIFO
    ///     self.dev_write(0x01, self.mode_idle)    # put chip in idle mode
    ///
    ///     for i in range(len(data)):
    ///         self.dev_write(0x09, data[i])   # write data to FIFO
    ///
    ///     self.dev_write(0x01, command)       # set desired mode of operation
    ///
    ///     if command == self.mode_transrec:
    ///         self.set_bitmask(0x0D, 0x80)    # start transmission
    ///
    ///     i = 2000
    ///     while True:
    ///         n = self.dev_read(0x04) # poll IRQs
    ///         i -= 1
    ///         if ~((i != 0) and ~(n & 0x01) and ~(n & irq_wait)):
    ///             break
    ///
    ///     self.clear_bitmask(0x0D, 0x80)
    ///
    ///     if i != 0:
    ///         if (self.dev_read(0x06) & 0x1B) == 0x00:    # check ErrorReg
    ///             error = False
    ///
    ///             if n & irq & 0x01:
    ///                 print("E1")
    ///                 error = True
    ///
    ///             if command == self.mode_transrec:
    ///                 n = self.dev_read(0x0A)     # number of bytes stored in the FIFO
    ///                 last_bits = self.dev_read(0x0C) & 0x07  # number of valid bits in last rx'ed byte (if 000b, whole byte is /// valid)
    ///                 if last_bits != 0:
    ///                     back_length = (n - 1) * 8 + last_bits
    ///                 else:
    ///                     back_length = n * 8
    ///
    ///                 if n == 0:
    ///                     n = 1
    ///
    ///                 if n > self.length:     # max = 16 bytes
    ///                     n = self.length
    ///
    ///                 for i in range(n):
    ///                     back_data.append(self.dev_read(0x09))   # read from FIFO and store in back_data
    ///         else:
    ///             print("E2")
    ///             error = True
    ///
    ///     return (error, back_data, back_length)
    /// ```
    func cardWrite(command: Byte, data: Bytes) -> (Bytes, Int, Bool) {
        var backData = Bytes()
        var backLength = 0
        var error = false
        
        var irq: Byte = 0x00
        var irqWait: Byte = 0x00
        var lastBits: Byte = 0x00
        var n: Byte = 0
        
        if command == mode_transrec {
            irq = 0x77
            irqWait = 0x30
        }
        
        devWrite(address: 0x02, value: irq | 0x80)
        clearBitmask(address: 0x04, mask: 0x80)
        setBitmask(address: 0x0A, mask: 0x80)
        devWrite(address: 0x01, value: mode_idle)
        
        data.forEach { byte in
            devWrite(address: 0x09, value: byte)
        }
        
        devWrite(address: 0x01, value: command)
        
        if command == mode_transrec {
            setBitmask(address: 0x0D, mask: 0x80)
        }
        
        var i = 2000
        while true {
            n = devRead(address: 0x04)
            i -= 1
            
            let a = (i != 0)
            let b = !((n & 0x01) == 1)
            let c = !((n & irqWait) == 1)
            let agg = a && b && c
            
            if !(agg) {
                break
            }
        }
        
        clearBitmask(address: 0x0D, mask: 0x80)

        if i != 0 {
            if (devRead(address: 0x06) & 0x1B) == 0x00 {
                error = false
                
                if (n & irq & 0x01) == 1 {
                    print("E1")
                    error = true
                }
                
                if command == mode_transrec {
                    n = devRead(address: 0x0A)
                    lastBits = devRead(address: 0x0C) & 0x07
                    if lastBits != 0 {
                        backLength = Int(Byte((n - 1) * 8) + lastBits)
                    } else {
                        backLength = Int(n * 8)
                    }
                    
                    if n == 0 {
                        n = 1
                    }
                    
                    if n > length {
                        n = length
                    }
                    
                    (i..<Int(n)).forEach { _ in
                        backData.append(devRead(address: 0x09))
                    }
                }
            } else {
                print("e2")
                error = true
            }
        }
        
        return (backData, backLength, error)
    }
    
    /// ```
    /// def request(self, req_mode=0x26):
    ///     """
    ///     Requests for tag.
    ///     Returns (False, None) if no tag is present, otherwise returns (True, tag type)
    ///     """
    ///     error = True
    ///     back_bits = 0
    ///
    ///     self.dev_write(0x0D, 0x07)  # start transmision
    ///     (error, back_data, back_bits) = self.card_write(self.mode_transrec, [req_mode, ])
    ///
    ///     if error or (back_bits != 0x10):
    ///         return (True, None)
    ///
    ///     return (False, back_bits)
    /// ```
    func request(mode: Byte = 0x26) -> Bool {
        
        devWrite(address: 0x0D, value: 0x07)
        let (_, backBits, error) = cardWrite(command: mode_transrec, data: [mode])
        
        if error || (backBits != 0x10) {
            return true
        } else {
            return false
        }
    }
    
    /// ```
    /// def anticoll(self):
    ///     """
    ///     Anti-collision detection.
    ///     Returns tuple of (error state, tag ID).
    ///     """
    ///     back_data = []
    ///     serial_number = []
    ///
    ///     serial_number_check = 0
    ///
    ///     self.dev_write(0x0D, 0x00)
    ///     serial_number.append(self.act_anticl)
    ///     serial_number.append(0x20)
    ///
    ///     (error, back_data, back_bits) = self.card_write(self.mode_transrec, serial_number)
    ///     if not error:
    ///         if len(back_data) == 5:
    ///             for i in range(4):
    ///                 serial_number_check = serial_number_check ^ back_data[i]
    ///
    ///             if serial_number_check != back_data[4]:
    ///                 error = True
    ///         else:
    ///             error = True
    ///
    ///     return (error, back_data)
    /// ```
    func anticoll() -> Result<Bytes, Error> {
        var serialNumber = Bytes()
        
        var serialNumberCheck: Byte = 0x00
        
        devWrite(address: 0x0D, value: 0x00)
        serialNumber.append(act_anticl)
        serialNumber.append(0x20)
        
        let (backData, _, error) = cardWrite(command: mode_transrec, data: serialNumber)
        if !error && backData.count == 5 {
            (0...3).forEach { i in
                serialNumberCheck = serialNumberCheck ^ backData[i]
            }
            
            if serialNumberCheck != backData[4] {
                return .failure(NSError(domain: "bad", code: 666, userInfo: nil))
            } else {
                return .success(backData)
            }
        } else {
            return .failure(NSError(domain: "bad", code: 666, userInfo: nil))
        }
    }
    
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
    
    /// ```
    /// def irq_callback(self, pin):
    ///     self.irq.set()
    /// ```
    var irqCallback: (GPIO) -> Void = { gpio in
//        self?.semaphore.signal()
        fatalError("not implemented")
    }
    
    /// ```
    ///def wait_for_tag(self):
    ///     # enable IRQ on detect
    ///     self.init()
    ///     self.irq.clear()
    ///     self.dev_write(0x04, 0x00)  # clear interrupts
    ///     self.dev_write(0x02, 0xA0)  # enable RxIRQ only
    ///     # wait for it
    ///     waiting = True
    ///     while waiting:
    ///         self.init()
    ///         #self.irq.clear()
    ///         self.dev_write(0x04, 0x00)
    ///         self.dev_write(0x02, 0xA0)
    ///
    ///         self.dev_write(0x09, 0x26)  # write something to FIFO
    ///         self.dev_write(0x01, 0x0C)  # TRX Mode: tx data in FIFO to antenna, then activate Rx
    ///         self.dev_write(0x0D, 0x87)  # start transmission
    ///         waiting = not self.irq.wait(0.1)
    ///     self.irq.clear()
    ///     self.init()
    /// ```
    func waitForTag() {
        devWrite(address: 0x04, value: 0x00) // clear interrupts
        devWrite(address: 0x02, value: 0xA0) // enable RxIRQ only
        
        var waiting = true
        while waiting {
            devWrite(address: 0x09, value: 0x26) // write something to FIFO
            devWrite(address: 0x01, value: 0x0C) // TRX Mode: tx data in FIFO to antenna, then activate Rx
            devWrite(address: 0x0D, value: 0x87) // start transmission

            waiting = semaphore.wait(timeout: .init(uptimeNanoseconds: 100_000_000)) == .timedOut
        }
        
        
    }
    
    /// ```
    /// def reset(self):
    ///     authed = False
    ///     self.dev_write(0x01, self.mode_reset)
    /// ```
    func reset() {
        authed = false
        devWrite(address: 0x01, value: mode_reset)
    }
    
    /// ```
    /// def cleanup(self):
    ///     """
    ///     Calls stop_crypto() if needed and cleanups GPIO.
    ///     """
    ///     if self.authed:
    ///         self.stop_crypto()
    ///     GPIO.cleanup()  # resets any used GPIOs to input
    /// ```
    deinit {
//        fatalError("not implemented")
    }
}

