import Foundation
import SwiftyGPIO

enum SystemError: Error, LocalizedError {
    case noSPIs
    case gpio(GPIOName)
    
    var errorDescription: String? {
        switch self {
        case .noSPIs: return "No hardware SPIs found"
        case .gpio(let name): return "No GPIO '\(name.rawValue)' found"
        }
    }
}

class System {
    
    // RFID Scanner
    let rfid: RFID
    
    // LED Lights
    let powerLight: Light
    let readyLight: Light
    let successLight: Light
    
//    // Export button
//    let export: Button
//
    // data holder
    let file: FileIO
    
    init() throws {
        guard let spis = SwiftyGPIO.hardwareSPIs(for: .RaspberryPi3) else {
            throw SystemError.noSPIs
        }
        
        let gpios = SwiftyGPIO.GPIOs(for: .RaspberryPi3)
        
        guard let irq = gpios[.P24] else {
            throw SystemError.gpio(.P24)
        }
        
        guard let power = gpios[.P6] else {
            throw SystemError.gpio(.P6)
        }
        
        guard let ready = gpios[.P13] else {
            throw SystemError.gpio(.P13)
        }
        
        guard let success = gpios[.P19] else {
            throw SystemError.gpio(.P19)
        }

//        // TODO: select
//        guard let export = gpios[.P3] else {
//            throw SystemError.gpio(.P3)
//        }
        
        self.rfid = RFID(spi: spis[0], irqGPIO: irq, waitTime: 3)
        
        self.powerLight = Light(gpio: power)
        self.readyLight = Light(gpio: ready)
        self.successLight = Light(gpio: success)

//        self.export = Button(gpio: export)
        self.file = try FileIO()
        
        // setup
        self.rfid.delegate = self
        self.powerLight.turnOn()
        self.readyLight.turnOn()
//        self.export.delegate = self
    }
    
    func run() throws {
        print("Start scanning for tags...")
        rfid.startScanningForTags()
    }
    
    deinit {
        powerLight.turnOff()
        readyLight.turnOff()
    }
}

extension System: RFIDDelegate {
    func rfidDidScanTag(_ rfid: RFID, withResult result: Result<Bytes, Error>) {
        switch result {
        case .success(let bytes):
            let tag = bytes
                .map { "\($0)" }
                .joined(separator: "-")
                        
            do {
                try file.writeTagOccurrence(tag: tag)
                successLight.turnOn(for: rfid.waitTime)
                readyLight.turnOff(for: rfid.waitTime)
            } catch {
                successLight.turnOff()
                print("file write error", error.localizedDescription)
            }
        case .failure(let error):
            successLight.turnOff()
            print("scan tag error", error.localizedDescription)
        }
    }
}

extension System: ButtonDelegate {
    func buttonDidPush(_ button: Button) {
//        do {
//            try file.exportFile()
//            successLight.turnOn(for: 2)
//        } catch {
//            errorLight.turnOn(for: 2)
//        }
    }
}
