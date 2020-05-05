import threading

RASPBERRY = object()
board = RASPBERRY

import spidev
import RPi.GPIO as GPIO
SPIClass = spidev.SpiDev
def_pin_rst = 22
def_pin_irq = 18
def_pin_mode = GPIO.BOARD

class RFID(object):
    pin_rst = 22
    pin_ce = 0
    pin_irq = 18

    mode_idle = 0x00
    mode_auth = 0x0E
    mode_receive = 0x08
    mode_transmit = 0x04
    mode_transrec = 0x0C
    mode_reset = 0x0F
    mode_crc = 0x03

    auth_a = 0x60
    auth_b = 0x61

    act_read = 0x30
    act_write = 0xA0
    act_increment = 0xC1
    act_decrement = 0xC0
    act_restore = 0xC2
    act_transfer = 0xB0

    act_reqidl = 0x26
    act_reqall = 0x52
    act_anticl = 0x93
    act_select = 0x93
    act_end = 0x50

    reg_tx_control = 0x14
    length = 16

    antenna_gain = 0x04


    authed = False
    irq = threading.Event()

    def __init__(self, bus=0, device=0, speed=1000000, pin_rst=def_pin_rst,
            pin_ce=0, pin_irq=def_pin_irq, pin_mode = def_pin_mode):
        self.pin_rst = pin_rst
        self.pin_ce = pin_ce
        self.pin_irq = pin_irq

        self.spi = SPIClass()
        self.spi.open(bus, device)
        self.spi.max_speed_hz = speed

        GPIO.setmode(pin_mode)
        GPIO.setup(pin_irq, GPIO.IN, pull_up_down=GPIO.PUD_UP)
#        GPIO.add_event_detect(pin_irq, GPIO.FALLING,
#                callback=self.irq_callback)
#
#        self.init()

    def init(self):
        self.reset()                    # "soft reset" by writing 0x0F to CommandReg
        self.dev_write(0x2A, 0x8D)      # TModeReg - timer settings
        self.dev_write(0x2B, 0x3E)      # TPrescalerReg - set ftimer = 13.56MHz/(2*TPrescaler+2)
        self.dev_write(0x2D, 30)        # TReloadReg - set timer reload value
        self.dev_write(0x2C, 0)         #      "
        self.dev_write(0x15, 0x40)      # TxASKReg - force 100% ASK modulation
        self.dev_write(0x11, 0x3D)      # ModeReg - general settings for Tx and Rx
#        self.dev_write(0x26, (self.antenna_gain<<4))    # RFCfgReg - set Rx's voltage gain factor
        self.set_antenna(True)

    def spi_transfer(self, data):
        if self.pin_ce != 0:
            GPIO.output(self.pin_ce, 0)     # set chip select for SPI
        r = self.spi.xfer2(data)            # SPI transfer, chip select held active between blocks
        if self.pin_ce != 0:                
            GPIO.output(self.pin_ce, 1)     # release chip select
        return r

    def dev_write(self, address, value):
        self.spi_transfer([(address << 1) & 0x7E, value]) # append 0 to address (LSB) and set MSB = 0

    def dev_read(self, address):
        return self.spi_transfer([((address << 1) & 0x7E) | 0x80, 0])[1] # append 0 to address (LSB) and set MSB = 1

    def set_bitmask(self, address, mask):
        current = self.dev_read(address)
        self.dev_write(address, current | mask)

    def clear_bitmask(self, address, mask):
        current = self.dev_read(address)
        self.dev_write(address, current & (~mask))

    def set_antenna(self, state):
        if state == True:
            current = self.dev_read(self.reg_tx_control)
            if ~(current & 0x03):
                self.set_bitmask(self.reg_tx_control, 0x03)
        else:
            self.clear_bitmask(self.reg_tx_control, 0x03)

    def set_antenna_gain(self, gain):
        """
        Sets antenna gain from a value from 0 to 7.
        """
        if 0 <= gain <= 7:
            self.antenna_gain = gain

    def card_write(self, command, data):
        back_data = []
        back_length = 0
        error = False
        irq = 0x00
        irq_wait = 0x00
        last_bits = None
        n = 0

        if command == self.mode_transrec:
            irq = 0x77
            irq_wait = 0x30

        self.dev_write(0x02, irq | 0x80)    # enable IRQs: timer, error, low alert, idle, rx, tx
        self.clear_bitmask(0x04, 0x80)      # clear interrupts
        self.set_bitmask(0x0A, 0x80)        # clear FIFO
        self.dev_write(0x01, self.mode_idle)    # put chip in idle mode

        for i in range(len(data)):
            self.dev_write(0x09, data[i])   # write data to FIFO

        self.dev_write(0x01, command)       # set desired mode of operation

        if command == self.mode_transrec:
            self.set_bitmask(0x0D, 0x80)    # start transmission

        i = 2000
        while True:
            n = self.dev_read(0x04) # poll IRQs
            i -= 1
            
            a = (i != 0)
            b = ~(n & 0x01)
            c = ~(n & irq_wait)
            agg = ~(b and c)
            
            if agg:
                print("n, i:", n, i)
                break

        self.clear_bitmask(0x0D, 0x80)

        if i != 0:
            if (self.dev_read(0x06) & 0x1B) == 0x00:    # check ErrorReg
                error = False
                
                print("n & 0x77 & 0x01", n & 0x77 & 0x01)
                if n & 0x77 & 0x01:
                    print("E1: Request timed out")
                    error = True

                if command == self.mode_transrec:
                    n = self.dev_read(0x0A)     # number of bytes stored in the FIFO
                    print("n", n)
                    last_bits = self.dev_read(0x0C) & 0x07  # number of valid bits in last rx'ed byte (if 000b, whole byte is valid)
                    print("last_bits", last_bits)
                    if last_bits != 0:
                        back_length = (n - 1) * 8 + last_bits
                    else:
                        back_length = n * 8
                        
                    print("back_length", back_length)

                    if n == 0:
                        n = 1

                    if n > self.length:     # max = 16 bytes
                        n = self.length

                    print("range(n)", range(n))
                    for i in range(n):
                        back_data.append(self.dev_read(0x09))   # read from FIFO and store in back_data
            else:
                print("E2")
                error = True

        print("return error, back_data, back_length", error, back_data, back_length)
        return (error, back_data, back_length)

    def request(self, req_mode=0x26):
        """
        Requests for tag.
        Returns (False, None) if no tag is present, otherwise returns (True, tag type)
        """
        error = True
        back_bits = 0

        self.dev_write(0x0D, 0x07)  # start transmision
        (error, back_data, back_bits) = self.card_write(self.mode_transrec, [req_mode])

        if error or (back_bits != 0x10):
            return (True, None)

        return (False, back_bits)

    def anticoll(self):
        """
        Anti-collision detection.
        Returns tuple of (error state, tag ID).
        """
        back_data = []
        serial_number = []

        serial_number_check = 0

        self.dev_write(0x0D, 0x00)
        serial_number.append(self.act_anticl)
        serial_number.append(0x20)

        (error, back_data, back_bits) = self.card_write(self.mode_transrec, serial_number)
        if not error:
            if len(back_data) == 5:
                for i in range(4):
                    serial_number_check = serial_number_check ^ back_data[i]

                if serial_number_check != back_data[4]:
                    error = True
            else:
                error = True

        return (error, back_data)

    def calculate_crc(self, data):
        self.clear_bitmask(0x05, 0x04)
        self.set_bitmask(0x0A, 0x80)

        for i in range(len(data)):
            self.dev_write(0x09, data[i])
        self.dev_write(0x01, self.mode_crc)

        i = 255
        while True:
            n = self.dev_read(0x05)
            i -= 1
            if not ((i != 0) and not (n & 0x04)):
                break

        ret_data = []
        ret_data.append(self.dev_read(0x22))
        ret_data.append(self.dev_read(0x21))

        return ret_data

    def select_tag(self, uid):
        """
        Selects tag for further usage.
        uid -- list or tuple with four bytes tag ID
        Returns error state.
        """
        back_data = []
        buf = []

        buf.append(self.act_select)
        buf.append(0x70)

        for i in range(5):
            buf.append(uid[i])

        crc = self.calculate_crc(buf)
        buf.append(crc[0])
        buf.append(crc[1])

        (error, back_data, back_length) = self.card_write(self.mode_transrec, buf)

        if (not error) and (back_length == 0x18):
            return False
        else:
            return True



    def irq_callback(self, pin):
        self.irq.set()

    def wait_for_tag(self):
        # enable IRQ on detect
        self.init()
        self.irq.clear() 
        self.dev_write(0x04, 0x00)  # clear interrupts
        self.dev_write(0x02, 0xA0)  # enable RxIRQ only
        # wait for it
        waiting = True
        while waiting:
            self.init()
            #self.irq.clear()
            self.dev_write(0x04, 0x00)
            self.dev_write(0x02, 0xA0)

            self.dev_write(0x09, 0x26)  # write something to FIFO
            self.dev_write(0x01, 0x0C)  # TRX Mode: tx data in FIFO to antenna, then activate Rx
            self.dev_write(0x0D, 0x87)  # start transmission
            waiting = not self.irq.wait(0.1)
        self.irq.clear()
        self.init()

    def reset(self):
        authed = False
        self.dev_write(0x01, self.mode_reset)

    def cleanup(self):
        """
        Calls stop_crypto() if needed and cleanups GPIO.
        """
        if self.authed:
            self.stop_crypto()
        GPIO.cleanup()  # resets any used GPIOs to input
