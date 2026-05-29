//
//  PopoverView.swift
//  ToDoMenu
//
//  Created by Sreekar Nimmagadda on 5/28/26.
//

import SwiftUI
import AppKit

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
    
    @FocusState private var focusedField: FocusField?

    var body: some View {
        VStack(spacing: 0) {
            // Top structural margin
            Spacer().frame(height: 12)

            // Scrollable task list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.tasks.enumerated()), id: \.element.id) { index, task in
                        HStack {
                            Text(task.text)
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundColor(.primary.opacity(0.85))
                                .lineLimit(1)

                            Spacer()

                            Button(action: { deleteAndMoveSelection(task) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.primary.opacity(0.25))
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                        .background(selectedTaskId == task.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contentShape(Rectangle())
                        .focusable()
                        .focused($focusedField, equals: .row(id: task.id))
                        .onTapGesture {
                            selectedTaskId = task.id
                            focusedField = .row(id: task.id)
                        }
                        .onMoveCommand { direction in
                            handleRowArrowMove(direction: direction, currentIndex: index)
                        }
                        .onDeleteCommand {
                            deleteAndMoveSelection(task)
                        }
                        
                        if index < store.tasks.count - 1 {
                            Divider()
                                .opacity(0.3)
                                .padding(.horizontal, 16)
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
                    .foregroundColor(.primary.opacity(0.3))
                    .font(.title3)
                
                CustomMacTextField(
                    text: $draft,
                    placeholder: "Type a task…",
                    onDownArrow: {
                        if let firstTask = store.tasks.first {
                            selectedTaskId = firstTask.id
                            focusedField = .row(id: firstTask.id)
                        }
                    },
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
                    .foregroundColor(isPinned ? .accentColor : .primary.opacity(0.6))
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
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
                .blendMode(.overlay)
        )
        // Forces keyboard state to lock onto the input box automatically on click/hotkey display events
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            selectedTaskId = nil
            focusedField = .inputField
        }
        // Catches wrapped up-arrow events sent from inside the custom AppKit text field
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("InputFieldUpArrowPressed"))) { _ in
            if let lastTask = store.tasks.last {
                selectedTaskId = lastTask.id
                focusedField = .row(id: lastTask.id)
            }
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
    
    // MARK: - Keyboard Flow Engine

    private func handleRowArrowMove(direction: MoveCommandDirection, currentIndex: Int) {
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
    
    private func deleteAndMoveSelection(_ task: Task) {
        guard let index = store.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        
        if store.tasks.count <= 1 {
            selectedTaskId = nil
            focusedField = .inputField
        } else if index == store.tasks.count - 1 {
            let targetId = store.tasks[index - 1].id
            selectedTaskId = targetId
            focusedField = .row(id: targetId)
        } else {
            let targetId = store.tasks[index + 1].id
            selectedTaskId = targetId
            focusedField = .row(id: targetId)
        }
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            store.delete(task)
        }
    }
}

// MARK: - Native Intercepting TextField Wrapper

struct CustomMacTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onDownArrow: () -> Void
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 16, weight: .regular)
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
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

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDownArrow()
                return true
            } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                NotificationCenter.default.post(name: NSNotification.Name("InputFieldUpArrowPressed"), object: nil)
                return true
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
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
