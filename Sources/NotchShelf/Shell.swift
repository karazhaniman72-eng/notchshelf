import Foundation

/// Running a command-line tool and reading what it said. Several stores need
/// this — `system_profiler` for Bluetooth batteries and Wi-Fi, `ps` for memory,
/// `ping` for the network — and none of them should own it.
///
/// Blocking on purpose. Every caller is already on a background queue, and the
/// alternative is a callback for a program that finishes in ten milliseconds.
enum Shell {
    static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch {
            Log.write("shell failed path=\(path) error=\(error.localizedDescription)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
