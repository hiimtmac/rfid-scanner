import Foundation
import SwiftyGPIO

public protocol ButtonDelegate: AnyObject {
    func buttonDidPush(_ button: Button)
}

public class Button {
    
    public let gpio: GPIO
    public weak var delegate: ButtonDelegate?
    
    public init(gpio: GPIO) {
        self.gpio = gpio
        
        gpio.direction = .IN
        gpio.value = 0
        gpio.bounceTime = 0.5
        gpio.onFalling { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.buttonDidPush(self)
        }
    }
    
    public func cleanup() {
        gpio.value = 0
        gpio.clearListeners()
        gpio.direction = .IN
    }
    
    deinit {
        cleanup()
    }
}
