//
//  PopoverView.swift
//  ToDoMenu
//
//  Created by Sreekar Nimmagadda on 5/28/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum FocusField: Hashable {
    case inputField
    case row(id: UUID)
    case markdownEditor(id: UUID)
}

struct TaskPopoverView: View {
    @ObservedObject var store: TaskStore
    @State private var draft: String = ""
    @State private var isPinned: Bool = false
    @State private var selectedTaskId: UUID?
    
    // Markdown Note States
    @State private var expandedNoteTaskId: UUID?
    @State private var currentNoteText: String = ""
    
    @State private var taskTexts: [UUID: String] = [:]
    @State private var clearedTaskIds: Set<UUID> = []
    @FocusState private var focusedField: FocusField?
    @State private var draggingTask: Task?

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 12)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(store.tasks.enumerated()), id: \.element.id) { index, task in
                            VStack(spacing: 0) {
                                HStack {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary.opacity(0.4))
                                        .padding(.trailing, 4)
                                    
                                    CustomMacTextField(
                                        text: Binding(
                                            get: { taskTexts[task.id] ?? task.text },
                                            set: { updateTaskText(for: task.id, newValue: $0) }
                                        ),
                                        placeholder: "Edit task…",
                                        fontDesignRounded: true,
                                        isEditingEnabled: clearedTaskIds.contains(task.id),
                                        onDownArrow: {
                                            commitInlineEdit(id: task.id)
                                            handleRowArrowMove(direction: .down, currentTaskId: task.id)
                                        },
                                        onUpArrow: {
                                            commitInlineEdit(id: task.id)
                                            handleRowArrowMove(direction: .up, currentTaskId: task.id)
                                        },
                                        onShiftDownArrow: {
                                            if expandedNoteTaskId == task.id {
                                                commitInlineEdit(id: task.id)
                                                focusedField = .markdownEditor(id: task.id)
                                            } else {
                                                moveTaskDelta(taskId: task.id, direction: .down)
                                            }
                                        },
                                        onShiftUpArrow: {
                                            if index > 0 {
                                                let previousTask = store.tasks[index - 1]
                                                if expandedNoteTaskId == previousTask.id {
                                                    commitInlineEdit(id: task.id)
                                                    selectedTaskId = previousTask.id
                                                    focusedField = .markdownEditor(id: previousTask.id)
                                                    return
                                                }
                                            }
                                            moveTaskDelta(taskId: task.id, direction: .up)
                                        },
                                        onCmdShiftToggle: {
                                            toggleMarkdownNote(for: task)
                                        },
                                        onDeleteKey: {
                                            deleteAndMoveSelection(task)
                                        },
                                        onSubmit: {
                                            commitInlineEdit(id: task.id)
                                        }
                                    )
                                    .focused($focusedField, equals: .row(id: task.id))
                                    .frame(height: 32)

                                    Spacer()
                                    
                                    if markdownFileExistsAndHasContent(for: task) {
                                        Image(systemName: "doc.text.fill")
                                            .font(.caption)
                                            .foregroundColor(.accentColor.opacity(0.7))
                                            .padding(.trailing, 4)
                                    }

                                    Button(action: { deleteAndMoveSelection(task) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(height: 44)
                                .padding(.horizontal, 16)
                                .background(selectedTaskId == task.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    commitAnyActiveEdits()
                                    selectedTaskId = task.id
                                    focusedField = .row(id: task.id)
                                    clearedTaskIds.insert(task.id)
                                }
                                
                                // FIXED: Dual-state workspace utilizing ZStack layout mapping for instant focus availability
                                if expandedNoteTaskId == task.id {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(focusedField == .markdownEditor(id: task.id) ? "MARKDOWN EDITOR — ACTIVE" : "MARKDOWN NOTE — RENDERED")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundColor(focusedField == .markdownEditor(id: task.id) ? .accentColor : .secondary)
                                            Spacer()
                                            Text(focusedField == .markdownEditor(id: task.id) ? "Shift+↑ to exit / read" : "Click to edit")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(.secondary.opacity(0.6))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.top, 4)
                                        
                                        ZStack {
                                            // 1. Plain Text Native Input layer
                                            FocusableTextEditor(
                                                text: $currentNoteText,
                                                onEscapeUp: {
                                                    focusedField = .row(id: task.id)
                                                    selectedTaskId = task.id
                                                },
                                                onEscapeDown: {
                                                    focusedField = .row(id: task.id)
                                                    selectedTaskId = task.id
                                                    handleRowArrowMove(direction: .down, currentTaskId: task.id)
                                                },
                                                onCmdShiftToggle: {
                                                    toggleMarkdownNote(for: task)
                                                }
                                            )
                                            .focused($focusedField, equals: .markdownEditor(id: task.id))
                                            .opacity(focusedField == .markdownEditor(id: task.id) ? 1.0 : 0.0)
                                            .allowsHitTesting(focusedField == .markdownEditor(id: task.id))
                                            
                                            // 2. FIXED: Rich Block-by-Block Markdown Render Engine
                                            ScrollView(.vertical, showsIndicators: true) {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    let lines = currentNoteText.components(separatedBy: .newlines)
                                                    // Skip the first line if it's the automated "# Task Title" header
                                                    let contentLines = lines.first?.hasPrefix("# ") == true ? Array(lines.dropFirst()) : lines
                                                    
                                                    if contentLines.joined(separator: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                        Text("*No additional scratchpad notes written yet.*")
                                                            .font(.system(size: 13))
                                                            .foregroundColor(.secondary.opacity(0.6))
                                                            .padding(.vertical, 4)
                                                    } else {
                                                        ForEach(Array(contentLines.enumerated()), id: \.offset) { _, line in
                                                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                                                            
                                                            if trimmed == "---" || trimmed == "***" {
                                                                Divider()
                                                                    .padding(.vertical, 4)
                                                            } else if trimmed.hasPrefix("# ") {
                                                                Text(LocalizedStringKey(String(trimmed.dropFirst(2))))
                                                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                                                    .foregroundColor(.primary)
                                                                    .padding(.top, 4)
                                                            } else if trimmed.hasPrefix("## ") {
                                                                Text(LocalizedStringKey(String(trimmed.dropFirst(3))))
                                                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                                    .foregroundColor(.primary)
                                                                    .padding(.top, 2)
                                                            } else if trimmed.hasPrefix("### ") {
                                                                Text(LocalizedStringKey(String(trimmed.dropFirst(4))))
                                                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                                    .foregroundColor(.secondary)
                                                            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                                                                HStack(alignment: .top, spacing: 6) {
                                                                    Text("•").foregroundColor(.accentColor)
                                                                    Text(LocalizedStringKey(String(trimmed.dropFirst(2))))
                                                                        .font(.system(size: 13))
                                                                }
                                                            } else {
                                                                // Standard line handling inline markdown strings (**bold**, *italics*)
                                                                Text(LocalizedStringKey(line))
                                                                    .font(.system(size: 13))
                                                                    .foregroundColor(.primary.opacity(0.9))
                                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                                    .fixedSize(horizontal: false, vertical: true)
                                                            }
                                                        }
                                                    }
                                                }
                                                .padding(.vertical, 4)
                                            }
                                            .opacity(focusedField == .markdownEditor(id: task.id) ? 0.0 : 1.0)
                                            .allowsHitTesting(focusedField != .markdownEditor(id: task.id))
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedTaskId = task.id
                                                focusedField = .markdownEditor(id: task.id)
                                            }
                                        }
                                        .frame(height: 110)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 8)
                                    }
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .id(task.id)
                            .onDrag {
                                commitAnyActiveEdits()
                                self.draggingTask = task
                                return NSItemProvider(object: task.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: TaskDropDelegate(item: task, store: store, currentDraggingItem: $draggingTask))
                            
                            if index < store.tasks.count - 1 {
                                Divider()
                                    .opacity(0.3)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .onChange(of: selectedTaskId) { _, newValue in
                    if let targetId = newValue {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            proxy.scrollTo(targetId, anchor: .center)
                        }
                    }
                }
            }
            .frame(height: calculateListHeight())
            
            if !store.tasks.isEmpty {
                Divider().opacity(0.3)
            }

            // Input Row
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.title3)
                
                CustomMacTextField(
                    text: $draft,
                    placeholder: "Type a task…",
                    fontDesignRounded: false,
                    isEditingEnabled: true,
                    onDownArrow: {
                        commitAnyActiveEdits()
                        if let firstTask = store.tasks.first {
                            selectedTaskId = firstTask.id
                            focusedField = .row(id: firstTask.id)
                        }
                    },
                    onUpArrow: {
                        commitAnyActiveEdits()
                        if let lastTask = store.tasks.last {
                            selectedTaskId = lastTask.id
                            focusedField = .row(id: lastTask.id)
                        }
                    },
                    onShiftDownArrow: {},
                    onShiftUpArrow: {},
                    onCmdShiftToggle: {},
                    onDeleteKey: {},
                    onSubmit: {
                        addTask()
                    }
                )
                .focused($focusedField, equals: .inputField)
                .frame(height: 32)
            }
            .frame(height: 48)
            .padding(.horizontal, 16)
            
            Divider().opacity(0.3)
            
            // Footer Action Toolbar
            HStack {
                Spacer()
                Button(action: togglePin) {
                    HStack(spacing: 6) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .rotationEffect(.degrees(isPinned ? 0 : 45))
                        Text(isPinned ? "Pinned (Drag Anywhere)" : "Pin Window")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(isPinned ? .accentColor : .primary.opacity(0.7))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .background(isPinned ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
                
                Button(action: { NotificationCenter.default.post(name: .requestOpenSettings, object: nil) }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.primary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
            }
            .frame(height: 44)
            .background(Color.primary.opacity(0.02))
        }
        .padding(.vertical, 2)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
                .blendMode(.overlay)
        )
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            commitAnyActiveEdits()
            selectedTaskId = nil
            focusedField = .inputField
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestHotkeyPinToggle)) { _ in
            togglePin()
        }
        .onPlaySound()
    }

    private func updateTaskText(for taskId: UUID, newValue: String) {
        let oldText = taskTexts[taskId] ?? (store.tasks.first(where: { $0.id == taskId })?.text ?? "")
        if selectedTaskId == taskId && !clearedTaskIds.contains(taskId) {
            clearedTaskIds.insert(taskId)
            if newValue.count > oldText.count, let lastChar = newValue.last {
                taskTexts[taskId] = String(lastChar)
            } else {
                taskTexts[taskId] = newValue
            }
        } else {
            taskTexts[taskId] = newValue
        }
    }

    private func addTask() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            store.add(draft)
        }
        draft = ""
    }
    
    private func togglePin() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPinned.toggle()
        }
        NotificationCenter.default.post(name: .toggleWindowPin, object: isPinned)
    }
    
    private func calculateListHeight() -> CGFloat {
        if store.tasks.isEmpty { return 0 }
        let staticRowsHeight = CGFloat(store.tasks.count * 44) + CGFloat(max(0, store.tasks.count - 1) * 1)
        let expandedNoteOffset = expandedNoteTaskId != nil ? CGFloat(132) : 0
        let totalCalculated = staticRowsHeight + expandedNoteOffset
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) * 0.5
        return min(totalCalculated, maxHeight)
    }
    
    private func toggleMarkdownNote(for task: Task) {
        commitAnyActiveEdits()
        let shiftingToOpen = (expandedNoteTaskId != task.id)
        
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            if expandedNoteTaskId == task.id {
                expandedNoteTaskId = nil
                currentNoteText = ""
            } else {
                expandedNoteTaskId = task.id
                currentNoteText = loadMarkdownNote(for: task)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if shiftingToOpen {
                self.focusedField = .markdownEditor(id: task.id)
            } else {
                self.focusedField = .row(id: task.id)
                self.selectedTaskId = task.id
            }
        }
    }
    
    private func getMarkdownFileURL(for task: Task) -> URL {
        return store.notesDirectoryURL.appendingPathComponent("\(task.id.uuidString).md")
    }
    
    private func loadMarkdownNote(for task: Task) -> String {
        let fileURL = getMarkdownFileURL(for: task)
        guard let savedString = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return "# \(task.text)\n\n"
        }
        return savedString
    }
    
    private func saveMarkdownNote(_ text: String, for task: Task) {
        let fileURL = getMarkdownFileURL(for: task)
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func markdownFileExistsAndHasContent(for task: Task) -> Bool {
        let fileURL = getMarkdownFileURL(for: task)
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        let lines = text.components(separatedBy: .newlines)
        let practicalText = lines.filter { !$0.starts(with: "#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return !practicalText.isEmpty
    }

    private func getRenderableMarkdown(for rawText: String) -> LocalizedStringKey {
        let lines = rawText.components(separatedBy: .newlines)
        if let firstLine = lines.first, firstLine.hasPrefix("# ") {
            let choppedLines = Array(lines.dropFirst())
            let jointText = choppedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return LocalizedStringKey(jointText.isEmpty ? "*No additional scratchpad notes written yet.*" : jointText)
        }
        return LocalizedStringKey(rawText)
    }
    
    private func commitInlineEdit(id: UUID) {
        guard let index = store.tasks.firstIndex(where: { $0.id == id }) else { return }
        clearedTaskIds.remove(id)
        
        if let currentText = taskTexts[id] {
            let cleanText = currentText.trimmingCharacters(in: .whitespaces)
            if cleanText.isEmpty {
                if let task = store.tasks.first(where: { $0.id == id }) {
                    deleteAndMoveSelection(task)
                }
            } else {
                withAnimation(.easeOut(duration: 0.15)) {
                    store.tasks[index] = Task(id: id, text: cleanText)
                    store.save()
                    
                    let task = store.tasks[index]
                    let existingNote = loadMarkdownNote(for: task)
                    var lines = existingNote.components(separatedBy: .newlines)
                    if let firstLine = lines.first, firstLine.starts(with: "#") {
                        lines[0] = "# \(cleanText)"
                        let updatedContent = lines.joined(separator: "\n")
                        saveMarkdownNote(updatedContent, for: task)
                    }
                }
            }
        }
        taskTexts.removeValue(forKey: id)
    }
    
    private func commitAnyActiveEdits() {
        for id in taskTexts.keys {
            commitInlineEdit(id: id)
        }
    }

    private func handleRowArrowMove(direction: MoveCommandDirection, currentTaskId: UUID) {
        guard let currentIndex = store.tasks.firstIndex(where: { $0.id == currentTaskId }) else { return }

        switch direction {
        case .down:
            if currentIndex == store.tasks.count - 1 {
                selectedTaskId = nil
                focusedField = .inputField
            } else {
                let targetId = store.tasks[currentIndex + 1].id
                selectedTaskId = targetId
                focusedField = .row(id: targetId)
            }
        case .up:
            if currentIndex == 0 {
                selectedTaskId = nil
                focusedField = .inputField
            } else {
                let targetId = store.tasks[currentIndex - 1].id
                selectedTaskId = targetId
                focusedField = .row(id: targetId)
            }
        default:
            break
        }
    }
    
    private func moveTaskDelta(taskId: UUID, direction: MoveCommandDirection) {
        guard let fromIndex = store.tasks.firstIndex(where: { $0.id == taskId }) else { return }

        let toIndex: Int
        if direction == .down {
            toIndex = fromIndex + 1
            guard toIndex < store.tasks.count else { return }
        } else {
            toIndex = fromIndex - 1
            guard toIndex >= 0 else { return }
        }
        
        commitInlineEdit(id: taskId)
        
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            store.tasks.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: direction == .down ? toIndex + 1 : toIndex)
            store.save()
        }
        
        selectedTaskId = taskId
        focusedField = .row(id: taskId)
        clearedTaskIds.insert(taskId)
    }
    
    private func deleteAndMoveSelection(_ task: Task) {
        guard let index = store.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        
        NSApp.keyWindow?.makeFirstResponder(nil)
        focusedField = nil
        
        taskTexts.removeValue(forKey: task.id)
        clearedTaskIds.remove(task.id)
        
        if expandedNoteTaskId == task.id {
            expandedNoteTaskId = nil
            currentNoteText = ""
        }
        
        let nextTargetId: UUID?
        if store.tasks.count <= 1 {
            nextTargetId = nil
        } else if index == store.tasks.count - 1 {
            nextTargetId = store.tasks[index - 1].id
        } else {
            nextTargetId = store.tasks[index + 1].id
        }
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            store.delete(task)
        }
        
        DispatchQueue.main.async {
            if let targetId = nextTargetId {
                self.selectedTaskId = targetId
                self.focusedField = .row(id: targetId)
            } else {
                self.selectedTaskId = nil
                self.focusedField = .inputField
            }
        }
    }
}

// MARK: - Drop Delegate Context

struct TaskDropDelegate: DropDelegate {
    let item: Task
    let store: TaskStore
    @Binding var currentDraggingItem: Task?
    
    func performDrop(info: DropInfo) -> Bool {
        self.currentDraggingItem = nil
        store.save()
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let currentDraggingItem = currentDraggingItem,
              currentDraggingItem != item,
              let fromIndex = store.tasks.firstIndex(of: currentDraggingItem),
              let toIndex = store.tasks.firstIndex(of: item) else { return }
        
        if fromIndex != toIndex {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                store.tasks.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }
}

// MARK: - AppKit Multi-line Editor Engine

struct FocusableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onEscapeUp: () -> Void
    var onEscapeDown: () -> Void
    var onCmdShiftToggle: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        if let roundedDescriptor = NSFont.systemFont(ofSize: 13, weight: .regular).fontDescriptor.withDesign(.monospaced) {
            textView.font = NSFont(descriptor: roundedDescriptor, size: 13)
        }
        
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.delegate = context.coordinator
        
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.setupLocalMonitor(for: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FocusableTextEditor
        private var localMonitor: Any?

        init(_ parent: FocusableTextEditor) {
            self.parent = parent
        }
        
        deinit {
            if let monitor = localMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        
        func setupLocalMonitor(for textView: NSTextView) {
            guard localMonitor == nil else { return }
            
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, NSApp.keyWindow?.firstResponder == textView else { return event }
                
                let flags = event.modifierFlags
                let keyCode = event.keyCode
                
                if flags.contains(.command) && flags.contains(.shift) {
                    if keyCode == 126 || keyCode == 125 {
                        self.parent.onCmdShiftToggle()
                        return nil
                    }
                }
                
                if flags.contains(.shift) && !flags.contains(.command) {
                    if keyCode == 126 {
                        self.parent.onEscapeUp()
                        return nil
                    } else if keyCode == 125 {
                        self.parent.onEscapeDown()
                        return nil
                    }
                }
                
                return event
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - Native Custom Text Field Wrapper

struct CustomMacTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontDesignRounded: Bool
    var isEditingEnabled: Bool
    var onDownArrow: () -> Void
    var onUpArrow: () -> Void
    var onShiftDownArrow: () -> Void
    var onShiftUpArrow: () -> Void
    var onCmdShiftToggle: () -> Void
    var onDeleteKey: () -> Void
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        
        if fontDesignRounded {
            textField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
            if let roundedDescriptor = NSFont.systemFont(ofSize: 15, weight: .medium).fontDescriptor.withDesign(.rounded) {
                textField.font = NSFont(descriptor: roundedDescriptor, size: 15)
            }
        } else {
            textField.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        }
        
        textField.textColor = .labelColor
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        
        if let currentEditor = nsView.currentEditor() as? NSTextView {
            if currentEditor.selectedRange().length > 0 && !isEditingEnabled {
                currentEditor.setSelectedRange(NSRange(location: currentEditor.selectedRange().location, length: 0))
            }
        }
        
        context.coordinator.setupLocalMonitor(for: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomMacTextField
        private var localMonitor: Any?

        init(_ parent: CustomMacTextField) {
            self.parent = parent
        }
        
        deinit {
            if let monitor = localMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        
        func setupLocalMonitor(for textField: NSTextField) {
            guard localMonitor == nil else { return }
            
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, textField.currentEditor() != nil else { return event }
                
                let flags = event.modifierFlags
                if flags.contains(.command) && flags.contains(.shift) {
                    let keyCode = event.keyCode
                    if keyCode == 126 || keyCode == 125 {
                        self.parent.onCmdShiftToggle()
                        return nil
                    }
                }
                return event
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDownArrow()
                return true
            } else if commandSelector == #selector(NSResponder.moveDownAndModifySelection(_:)) || commandSelector == Selector("selectDown:") {
                parent.onShiftDownArrow()
                return true
            } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUpArrow()
                return true
            } else if commandSelector == #selector(NSResponder.moveUpAndModifySelection(_:)) || commandSelector == Selector("selectUp:") {
                parent.onShiftUpArrow()
                return true
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) || commandSelector == #selector(NSResponder.deleteForward(_:)) {
                if !parent.isEditingEnabled {
                    parent.onDeleteKey()
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Native Windows Layer Visual Bridge

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    func onPlaySound() -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: .requestHotkeyPinToggle)) { _ in
            NSSound(named: "Submarine")?.play()
        }
    }
}
