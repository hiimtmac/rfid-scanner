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
    
    init(at path: String = "/home/ubuntu/rfid-scan.txt") throws {
        let url = URL(fileURLWithPath: path)
        
        self.fileURL = url
        self.writer = try CSVWriter(fileURL: url, append: true) { config in
            config.headers = ["Date", "Time", "Tag"]
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
        // usually where usb on pi shows up
        let mediaURL = URL(fileURLWithPath: "/media/ubuntu", isDirectory: true)
        // get url to any plugged in
        let urls = try fm.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        // take one (assume only one to be plugged in)
        guard let first = urls.first else {
            throw FileIOError.noUSB
        }
        
        let destination = first.appendingPathComponent("rfid-scan-data")
        try fm.copyItem(at: fileURL, to: destination)
        print(fileURL, destination)
    }
}
