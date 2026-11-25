//
//  HistoryTrace.swift
//  com.awareframework.ios.sensor.activityrecognition
//
//  Debug trace of the history queries. Written to a file so that it can be read from a device
//  without a console, e.g. `xcrun devicectl device copy from --domain-type appDataContainer
//  --source Library/Logs/AwareMotionTrace/activityrecognition.log`. Only written while `CONFIG.debug` is on.
//

import Foundation
import UIKit

final class HistoryTrace {

    var isEnabled = false

    /// Updated from notifications (UIApplication.shared is not available in every target)
    private(set) var appState = "unknown"
    private(set) var protectedDataAvailable = true

    private let name: String
    private let tag: String
    private let queue: DispatchQueue
    private var handle: FileHandle?
    private var observers: [NSObjectProtocol] = []
    private static let maxBytes: UInt64 = 8_000_000

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f
    }()

    init(name: String, tag: String) {
        self.name = name
        self.tag = tag
        self.queue = DispatchQueue(label: "com.awareframework.ios.sensor.\(name).trace", qos: .utility)
        let center = NotificationCenter.default
        let events: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "background"),
            (UIApplication.willEnterForegroundNotification, "foreground"),
            (UIApplication.didBecomeActiveNotification, "active"),
            (UIApplication.willResignActiveNotification, "inactive"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "protectedDataUnavailable"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "protectedDataAvailable"),
            (UIApplication.willTerminateNotification, "terminate"),
        ]
        for (notification, label) in events {
            observers.append(center.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                switch label {
                case "protectedDataUnavailable": self.protectedDataAvailable = false
                case "protectedDataAvailable": self.protectedDataAvailable = true
                case "terminate": break
                default: self.appState = label
                }
                self.log("APP \(label)")
            })
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        handle?.closeFile()
    }

    static func directory() -> URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/AwareMotionTrace", isDirectory: true)
    }

    func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(formatter.string(from: Date())) \(message())"
        print(tag, line)
        let data = Data((line + "\n").utf8)
        queue.async { [weak self] in self?.write(data) }
    }

    func format(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return formatter.string(from: date)
    }

    private func write(_ data: Data) {
        guard let directory = Self.directory() else { return }
        let url = directory.appendingPathComponent("\(name).log")
        if handle == nil {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                // Readable while the device is locked: the stall may happen then
                FileManager.default.createFile(atPath: url.path, contents: nil,
                                               attributes: [.protectionKey: FileProtectionType.none])
            }
            handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        }
        guard let handle else { return }
        handle.write(data)
        if handle.offsetInFile > Self.maxBytes {
            handle.closeFile()
            self.handle = nil
            let old = directory.appendingPathComponent("\(name).1.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
    }
}
