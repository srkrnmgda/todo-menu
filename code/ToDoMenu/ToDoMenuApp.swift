//
//  ToDoMenuApp.swift
//  ToDoMenu
//
//  Created by Sreekar Nimmagadda on 5/28/26.
//

import SwiftUI
import AppKit
import HotKey
import ServiceManagement

@main
struct TaskSlabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var panel: CustomPanel!
    var settingsWindow: NSWindow?
    var taskStore = TaskStore()
    
    var globalHotKey: HotKey?
    var localPinHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? SMAppService.mainApp.register()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tasks")
            button.imagePosition = .imageLeft
            button.action = #selector(togglePanel)
            button.target = self
        }

        panel = CustomPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self
        
        let contentView = TaskPopoverView(store: taskStore)
        panel.contentView = NSHostingView(rootView: contentView)
        
        setupHotKeys()
        updateMenuBadge()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePinToggle(_:)), name: .toggleWindowPin, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateMenuBadge), name: .taskDataChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsWindow), name: .requestOpenSettings, object: nil)
        
        // Listen for user customization revisions inside the Preferences Recorder View
        NotificationCenter.default.addObserver(self, selector: #selector(setupHotKeys), name: Notification.Name("updateGlobalHotkeyBinding"), object: nil)
    }
    
    @objc func openSettingsWindow() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView(store: taskStore)
        let hostingView = NSHostingView(rootView: settingsView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "To-Do Menu Preferences"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
        }
    }

    @objc private func setupHotKeys() {
        // Tear down any active carbon listener context prior to binding new variants
        globalHotKey = nil
        
        // Map saved UserDefault primitives explicitly into framework objects
        if let appKitKey = Key(carbonKeyCode: UInt32(taskStore.globalKeyCode)) {
            let appKitModifiers = NSEvent.ModifierFlags(rawValue: taskStore.globalModifiersFlags)
            var hotkeyKitModifiers: NSEvent.ModifierFlags = []
            
            if appKitModifiers.contains(.control) { hotkeyKitModifiers.insert(.control) }
            if appKitModifiers.contains(.option)  { hotkeyKitModifiers.insert(.option) }
            if appKitModifiers.contains(.shift)   { hotkeyKitModifiers.insert(.shift) }
            if appKitModifiers.contains(.command) { hotkeyKitModifiers.insert(.command) }
            
            globalHotKey = HotKey(key: appKitKey, modifiers: hotkeyKitModifiers)
            globalHotKey?.keyDownHandler = { [weak self] in
                self?.togglePanel()
            }
        }
        
        // Keep the local, static window-pin modifier active
        localPinHotKey = HotKey(key: .w, modifiers: [.option])
        localPinHotKey?.keyDownHandler = {
            NotificationCenter.default.post(name: .requestHotkeyPinToggle, object: nil)
        }
    }

    @objc func handlePinToggle(_ notification: Notification) {
        guard let isPinned = notification.object as? Bool else { return }
        panel.isPinned = isPinned
        panel.level = isPinned ? .floating : .statusBar
    }

    @objc func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if let button = statusItem.button, let windowScreen = button.window?.screen {
                let buttonFrame = button.window!.convertToScreen(button.frame)
                let screenFrame = windowScreen.frame
                
                let panelWidth = panel.frame.width
                var panelX = buttonFrame.origin.x + (buttonFrame.width / 2) - (panelWidth / 2)
                
                if panelX + panelWidth > screenFrame.origin.x + screenFrame.width {
                    panelX = screenFrame.origin.x + screenFrame.width - panelWidth - 12
                }
                if panelX < screenFrame.origin.x {
                    panelX = screenFrame.origin.x + 12
                }
                
                let panelY = buttonFrame.origin.y - panel.frame.height - 4
                
                panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
            }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func updateMenuBadge() {
        guard let button = statusItem.button else { return }
        let count = taskStore.tasks.count
        
        if count > 0 {
            button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            button.title = " \(count)"
        } else {
            button.title = ""
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow { return }
        if !panel.isPinned {
            panel.orderOut(nil)
        }
    }
}

class CustomPanel: NSPanel {
    var isPinned: Bool = false
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    
    override func mouseDown(with event: NSEvent) {
        guard isPinned else {
            super.mouseDown(with: event)
            return
        }
        let locationInView = event.locationInWindow
        if let contentView = self.contentView, let hitView = contentView.hitTest(locationInView) {
            if hitView.className.contains("TextField") || hitView.className.contains("Button") || hitView.className.contains("TextView") {
                super.mouseDown(with: event)
                return
            }
        }
        self.performDrag(with: event)
    }
}

extension Notification.Name {
    static let toggleWindowPin = Notification.Name("toggleWindowPin")
    static let taskDataChanged = Notification.Name("taskDataChanged")
    static let requestHotkeyPinToggle = Notification.Name("requestHotkeyPinToggle")
    static let requestOpenSettings = Notification.Name("requestOpenSettings")
}
