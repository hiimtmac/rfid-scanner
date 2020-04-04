import SwiftyGPIO
import Foundation

print("Get spi")
let spi = SwiftyGPIO.hardwareSPIs(for: .RaspberryPi3)![0]
print("get irq")
let irq = SwiftyGPIO.GPIOs(for: .RaspberryPi3)[.P24]!

print("make rfid")
let rfid = RFID(spi: spi, gpio: irq)

while true {
    print("wait for tag...")
    rfid.waitForTag()
    print("break wait for tag...")
//
//    let error = rfid.request()
//
//    if !error {
//        print("tag detected")
//        let result = rfid.anticoll()
//        switch result {
//        case .success(let bytes): print("UID: \(bytes)")
//        case .failure(let error): print(error.localizedDescription)
//        }
//
//        sleep(5)
//    } else {
//        print("error in request")
//    }
}
