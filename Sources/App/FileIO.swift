import Foundation
import CodableCSV

enum FileIOError: Error, LocalizedError {
    case noUSB
    
    var errorDescription: String? {
        switch self {
        case .noUSB: return "No usbs"
        }
    }
}

class FileIO {
    
    let fm = FileManager.default
    let fileURL: URL
    let writer: CSVWriter
    
    init(with title: String = "rfid-scan") throws {
        let url = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent(title)
            .appendingPathExtension("csv")
        
        self.fileURL = url
        self.writer = try CSVWriter(fileURL: url, append: true) { config in
//            config.headers = ["Date", "Time", "Tag"]
            config.encoding = .utf8
        }
    }
    
    func writeTagOccurrence(tag: String) throws {
        let time = DateFormatter()
        time.timeZone = TimeZone(abbreviation: "UTC")
        time.dateFormat = "hh:mm:ss"
        
        let date = DateFormatter()
        date.timeZone = TimeZone(abbreviation: "UTC")
        date.dateFormat = "yyyy-MM-dd"
        
        let now = Date()
        
        let values = [
            date.string(from: now),
            time.string(from: now),
            tag
        ]
        
        try writer.write(row: values)
    }
    
    func exportFile() throws {
        let mount = Process()
        mount.executableURL = URL(fileURLWithPath: "/usr/bin/pmount")
        mount.arguments = ["-s", "/dev/sda2", "pi"]
        try mount.run()
        mount.waitUntilExit()
        
        defer {
            let umount = Process()
            umount.executableURL = URL(fileURLWithPath: "/usr/bin/pumount")
            umount.arguments = ["pi"]
            try? umount.run()
            umount.waitUntilExit()
        }
        
        let usbURL = URL(fileURLWithPath: "/media/pi", isDirectory: true)
        let destination = usbURL.appendingPathComponent(fileURL.lastPathComponent)
        try fm.copyItem(at: fileURL, to: destination)
    }
}
