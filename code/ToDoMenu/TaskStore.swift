//
//  TaskStore.swift
//  ToDoMenu
//
//  Created by Sreekar Nimmagadda on 5/28/26.
//

import Foundation
import Combine
import AppKit

final class TaskStore: ObservableObject {

    @Published var tasks: [Task] = [] {
        didSet {
            NotificationCenter.default.post(name: .taskDataChanged, object: nil)
        }
    }
    
    @Published var notesDirectoryURL: URL

    private let fileURL: URL
    private let directoryKey = "customNotesDirectoryPath"
    
    // Keybind Persistence Storage Keys
    private let hotkeyCodeKey = "globalHotkeyCode"
    private let hotkeyModifiersKey = "globalHotkeyModifiers"

    // Custom Keybind Fallback Accessors (Defaults to Option [⌥] + T)
    var globalKeyCode: Int {
        get {
            let savedValue = UserDefaults.standard.integer(forKey: hotkeyCodeKey)
            return savedValue == 0 ? 17 : savedValue // 17 is virtual hardware code for 'T'
        }
        set { UserDefaults.standard.set(newValue, forKey: hotkeyCodeKey) }
    }

    var globalModifiersFlags: UInt {
        get {
            if UserDefaults.standard.object(forKey: hotkeyModifiersKey) == nil {
                return NSEvent.ModifierFlags.option.rawValue
            }
            return UInt(UserDefaults.standard.integer(forKey: hotkeyModifiersKey))
        }
        set { UserDefaults.standard.set(newValue, forKey: hotkeyModifiersKey) }
    }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = dir.appendingPathComponent("TaskSlab", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        fileURL = folder.appendingPathComponent("tasks.json")
        
        if let savedPath = UserDefaults.standard.string(forKey: directoryKey),
           let url = URL(string: savedPath) {
            self.notesDirectoryURL = url
        } else {
            let defaultNotesFolder = folder.appendingPathComponent("Notes", isDirectory: true)
            try? FileManager.default.createDirectory(at: defaultNotesFolder, withIntermediateDirectories: true)
            self.notesDirectoryURL = defaultNotesFolder
        }

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
    
    func changeNotesDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Select Markdown Storage Folder"
        openPanel.prompt = "Choose Folder"
        
        if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
            self.notesDirectoryURL = selectedURL
            UserDefaults.standard.set(selectedURL.path, forKey: directoryKey)
            try? FileManager.default.createDirectory(at: selectedURL, withIntermediateDirectories: true)
            
            let currentTasks = self.tasks
            self.tasks = currentTasks
        }
    }
    
    func updateGlobalHotkey(keyCode: Int, modifiers: UInt) {
        globalKeyCode = keyCode
        globalModifiersFlags = modifiers
        objectWillChange.send()
        
        // Broadcast updates to cycle the hardware hotkey intercept loop
        NotificationCenter.default.post(name: Notification.Name("updateGlobalHotkeyBinding"), object: nil)
    }

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
