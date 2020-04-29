import Foundation
import SwiftyGPIO

public class Light {
    
    public let gpio: GPIO
    
    public init(gpio: GPIO) {
        self.gpio = gpio
        
        gpio.direction = .OUT
        gpio.value = 0
    }
    
    public func turnOn(for time: TimeInterval? = nil) {
        gpio.value = 1
        
        if let time = time {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                self?.gpio.value = 0
            }
        }
    }
    
    public func turnOff(for time: TimeInterval? = nil) {
        gpio.value = 0
        
        if let time = time {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                self?.gpio.value = 1
            }
        }
    }
    
    public func cleanup() {
        gpio.value = 0
        gpio.direction = .IN
    }
    
    deinit {
        cleanup()
    }
}
