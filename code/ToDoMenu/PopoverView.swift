//
//  PopoverView.swift
//  ToDoMenu
//
//  Created by Sreekar Nimmagadda on 5/28/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Tracks keyboard focus mapping cleanly across the view hierarchy
enum FocusField: Hashable {
    case inputField
    case row(id: UUID)
}

struct TaskPopoverView: View {
    @ObservedObject var store: TaskStore
    @State private var draft: String = ""
    @State private var isPinned: Bool = false
    @State private var selectedTaskId: UUID?
    
    // Tracks text alterations across specific task identifiers
    @State private var taskTexts: [UUID: String] = [:]
    
    // Tracks which rows have already processed their initial "overwrite" keystroke
    @State private var clearedTaskIds: Set<UUID> = []
    
    @FocusState private var focusedField: FocusField?
    
    // State to track the item currently being dragged
    @State private var draggingTask: Task?

    var body: some View {
        VStack(spacing: 0) {
            // Top structural margin
            Spacer().frame(height: 12)

            // Scrollable task list with Proxy Reader Engine
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(store.tasks.enumerated()), id: \.element.id) { index, task in
                            HStack {
                                // Drag indicator handle
                                Image(systemName: "line.3.horizontal")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary.opacity(0.4))
                                    .padding(.trailing, 4)
                                
                                // EMBEDDED TEXT FIELD: Active but stealthy.
                                CustomMacTextField(
                                    text: Binding(
                                        get: { taskTexts[task.id] ?? task.text },
                                        set: { newValue in
                                            let oldText = taskTexts[task.id] ?? task.text
                                            
                                            // Only clear the text if this is the FIRST keystroke since highlighting the row
                                            if selectedTaskId == task.id && !clearedTaskIds.contains(task.id) {
                                                clearedTaskIds.insert(task.id)
                                                if newValue.count > oldText.count, let lastChar = newValue.last {
                                                    taskTexts[task.id] = String(lastChar)
                                                } else {
                                                    taskTexts[task.id] = newValue
                                                }
                                            } else {
                                                // Regular typing mode takes over completely here
                                                taskTexts[task.id] = newValue
                                            }
                                        }
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
                                        moveTaskDelta(taskId: task.id, direction: .down)
                                    },
                                    onShiftUpArrow: {
                                        moveTaskDelta(taskId: task.id, direction: .up)
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
                            .onDrag {
                                commitAnyActiveEdits()
                                self.draggingTask = task
                                return NSItemProvider(object: task.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: TaskDropDelegate(item: task, store: store, currentDraggingItem: $draggingTask))
                            .id(task.id)
                            
                            if index < store.tasks.count - 1 {
                                Divider()
                                    .opacity(0.3)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .onChange(of: selectedTaskId) { oldValue, newValue in
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
            
            // Pin Button Cell
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
        .onAppear {
            focusedField = .inputField
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
        let calculatedHeight = CGFloat(store.tasks.count * 44) + CGFloat(max(0, store.tasks.count - 1) * 1)
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) * 0.4
        return min(calculatedHeight, maxHeight)
    }
    
    // MARK: - Persistence Logic For Inline Editing

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

// MARK: - Drop Delegate Logic Engine

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

// MARK: - Native Intercepting TextField Wrapper

struct CustomMacTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontDesignRounded: Bool
    var isEditingEnabled: Bool
    var onDownArrow: () -> Void
    var onUpArrow: () -> Void
    var onShiftDownArrow: () -> Void
    var onShiftUpArrow: () -> Void
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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomMacTextField

        init(_ parent: CustomMacTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        // INTERCEPTING APP-KIT SELECTORS: Bypasses standard text selection for structural shifts
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

// MARK: - Native Windows Blurry Glass Layer Bridge

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
