import SwiftyGPIO

print("Get spi")
let spi = SwiftyGPIO.hardwareSPIs(for: .RaspberryPi3)![0]
print("get irq")
let irq = SwiftyGPIO.GPIOs(for: .RaspberryPi3)[.P22]!

print("make rfid")
let rfid = RFID(spi: spi, gpio: irq)

print("write to rgister")
rfid.devWrite(address: 0x09, value: 0x06)

print("read from dev")
let read = rfid.devRead(address: 0x09)
print(read)
