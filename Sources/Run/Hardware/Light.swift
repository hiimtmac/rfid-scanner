import Foundation
import SwiftyGPIO

class Light {
    
    let gpio: GPIO
    
    init(gpio: GPIO) {
        self.gpio = gpio
        
        gpio.direction = .OUT
        gpio.value = 0
    }
    
    func turnOn(for time: TimeInterval? = nil) {
        gpio.value = 1
        
        if let time = time {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                self?.gpio.value = 0
            }
        }
    }
    
    func turnOff(for time: TimeInterval? = nil) {
        gpio.value = 0
        
        if let time = time {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                self?.gpio.value = 1
            }
        }
    }
    
    func cleanup() {
        gpio.value = 0
        gpio.direction = .IN
    }
    
    deinit {
        cleanup()
    }
}
