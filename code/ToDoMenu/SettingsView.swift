//
//  SettingsView.swift
//  ToDoMenu
//
//  Created by Sreekar Nimmagadda on 5/29/26.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: TaskStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header Section
            HStack(spacing: 12) {
                Image(systemName: "gearshape.2.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TaskSlab Preferences")
                        .font(.headline)
                    Text("Configure your minimalist workspace sync settings.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Sync / Storage Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Markdown Sync Location")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("Point this to an Obsidian Vault or local folder to automatically save and sync your scratchpad notes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Text(store.notesDirectoryURL.path)
                        .lineLimit(1)
                        .truncationMode(Text.TruncationMode.head)
                        .font(Font.system(size: 11, weight: .regular, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: Alignment.leading)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                    
                    Button("Change Folder…") {
                        store.changeNotesDirectory()
                    }
                }
            }
            
            Divider()
            
            // Keyboard Shortcuts Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global Toggle Panel")
                            .font(.body)
                        Text("Bring up or hide your scratchpad overlay from anywhere.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // The live shortcut recorder
                    ShortcutRecorderView(store: store)
                }
            }
            
            Spacer()
        }
        .padding(24)
        .frame(width: 480, height: 320)
    }
}

// MARK: - Interactive Shortcut Recorder View

struct ShortcutRecorderView: View {
    @ObservedObject var store: TaskStore
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    
    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            Text(isRecording ? "Type shortcut…" : currentShortcutString())
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .padding(.vertical, 5)
                .padding(.horizontal, 14)
                .background(isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.1))
                .foregroundColor(isRecording ? .red : .accentColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.red.opacity(0.5) : Color.accentColor.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }
    
    private func startRecording() {
        isRecording = true
        
        // Listen to raw hardware key events while the window is active
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Ignore bare key presses without structural modifiers (except Function keys)
            if modifiers.isEmpty && event.keyCode < 122 {
                return event
            }
            
            // Cancel recording cleanly on Escape
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            
            // Update store values and rebind
            store.updateGlobalHotkey(keyCode: Int(event.keyCode), modifiers: modifiers.rawValue)
            stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func currentShortcutString() -> String {
        let flags = NSEvent.ModifierFlags(rawValue: store.globalModifiersFlags)
        let keyCode = UInt16(store.globalKeyCode)
        
        var str = ""
        if flags.contains(.control) { str += "⌃ " }
        if flags.contains(.option)  { str += "⌥ " }
        if flags.contains(.shift)   { str += "⇧ " }
        if flags.contains(.command) { str += "⌘ " }
        
        str += KeyMapping.stringForKeyCode(keyCode)
        return str.isEmpty ? "Click to record" : str
    }
}

// MARK: - KeyCode Mapper Helper

struct KeyMapping {
    static func stringForKeyCode(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 49: return "Space"
        default: return "Key \(keyCode)"
        }
    }
}
