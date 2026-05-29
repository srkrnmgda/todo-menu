//
//  Logger.swift
//  ToDoMenu
//
//  Created by Sreekar Nimmagadda on 5/28/26.
//

import Foundation

final class TaskLogger {
    static let shared = TaskLogger()

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = dir.appendingPathComponent("TaskSlab", isDirectory: true)

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        fileURL = folder.appendingPathComponent("tasks.tsv")
    }

    func log(_ event: String, task: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(event)\t\(task)\t\(timestamp)\n"

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }
}
