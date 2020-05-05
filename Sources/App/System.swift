import Foundation
import SwiftyGPIO
import PiHardware

public enum SystemError: Error, LocalizedError {
    case noSPIs
    case gpio(GPIOName)
    
    public var errorDescription: String? {
        switch self {
        case .noSPIs: return "No hardware SPIs found"
        case .gpio(let name): return "No GPIO '\(name.rawValue)' found"
        }
    }
    
    public var errorCode: Int32 {
        switch self {
        case .noSPIs: return 600
        case .gpio: return 601
        }
    }
}

public class System {
    
    // RFID Scanner
    let rfid: RFID
    
    // LED Lights
    let powerLight: Light
    let readyLight: Light
    let successLight: Light
    
    // Export button
    let exportButton: Button

    // data holder
    let file: FileIO
    
    public init() throws {
        guard let spis = SwiftyGPIO.hardwareSPIs(for: .RaspberryPi3) else {
            throw SystemError.noSPIs
        }
        
        let gpios = SwiftyGPIO.GPIOs(for: .RaspberryPi3)
        
        guard let irq = gpios[.P4] else {
            throw SystemError.gpio(.P4)
        }
        
        guard let power = gpios[.P24] else {
            throw SystemError.gpio(.P24)
        }
        
        guard let ready = gpios[.P18] else {
            throw SystemError.gpio(.P18)
        }
        
        guard let success = gpios[.P23] else {
            throw SystemError.gpio(.P23)
        }

        guard let export = gpios[.P6] else {
            throw SystemError.gpio(.P6)
        }
        
        self.rfid = RFID(spi: spis[0], irqGPIO: irq, waitTime: 3)
        
        self.powerLight = Light(gpio: power)
        self.readyLight = Light(gpio: ready)
        self.successLight = Light(gpio: success)

        self.exportButton = Button(gpio: export)
        
        self.file = try FileIO()
        
        // setup
        self.rfid.delegate = self
        self.powerLight.turnOn()
        self.readyLight.turnOn()
        self.exportButton.delegate = self
    }
    
    public func run() throws {
        print("Start scanning for tags...")
        rfid.startScanningForTags()
    }
    
    public func cleanup() {
        powerLight.cleanup()
        readyLight.cleanup()
        successLight.cleanup()
        exportButton.cleanup()
        rfid.cleanup()
    }
    
    deinit {
        cleanup()
    }
}

extension System: RFIDDelegate {
    public func rfidDidScanTag(_ rfid: RFID, withResult result: Result<Bytes, Error>) {
        switch result {
        case .success(let bytes):
            let tag = bytes
                .map { "\($0)" }
                .joined(separator: "-")
                        
            do {
                try file.writeTagOccurrence(tag: tag)
                print("tag found")
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
    public func buttonDidPush(_ button: Button) {
        print("button pushed")
        do {
            try file.exportFile()
            successLight.turnOn(for: rfid.waitTime)
            readyLight.turnOff(for: rfid.waitTime)
        } catch {
            successLight.turnOff()
            print("write file error", error.localizedDescription)
        }
    }
}
