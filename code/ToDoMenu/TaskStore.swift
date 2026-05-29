//
//  TaskStore.swift
//  ToDoMenu
//
//  Created by Sreekar Nimmagadda on 5/28/26.
//

import Foundation
import Combine

final class TaskStore: ObservableObject {

    // Broadcasts changes automatically
    @Published var tasks: [Task] = [] {
        didSet {
            NotificationCenter.default.post(name: .taskDataChanged, object: nil)
        }
    }

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = dir.appendingPathComponent("TaskSlab", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Switch to a JSON file format for absolute stability
        fileURL = folder.appendingPathComponent("tasks.json")

        load()
    }

    func add(_ text: String) {
        let task = Task(text: text)
        tasks.append(task)
        save()
        TaskLogger.shared.log("CREATE", task: text)
    }

    func delete(_ task: Task) {
        tasks.removeAll { $0.id == task.id }
        save()
        TaskLogger.shared.log("DELETE", task: task.text)
    }

    // MARK: - Persistence

    func save() {
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            self.tasks = try JSONDecoder().decode([Task].self, from: data)
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }
}
