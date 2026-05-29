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
    var taskStore = TaskStore()
    
    var globalHotKey: HotKey?
    
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        
        try? SMAppService.mainApp.register()
        
        // 1. Setup Status Bar Button
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tasks")
            button.imagePosition = .imageLeft
            button.action = #selector(togglePanel)
            button.target = self
        }

        // 2. Build the Custom Glass Panel Canvas
        panel = CustomPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 3. Set SwiftUI Content
        let contentView = TaskPopoverView(store: taskStore)
            .frame(width: 320)
        
        panel.contentView = NSHostingView(rootView: contentView)
        
        // 4. Register Notification Listeners
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePinToggle(_:)),
            name: Notification.Name.toggleWindowPin,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTaskDataChanged),
            name: Notification.Name.taskDataChanged,
            object: nil
        )
        
        // 5. 🌟 MODERN SHORTCUT MONITOR
        setupModernShortcut()
        
        updateMenuBarButton()
    }
    
    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @objc func togglePanel() {
        if panel.isVisible && panel.level != .mainMenu {
            panel.orderOut(nil)
        } else {
            if panel.level != .mainMenu {
                if let button = statusItem.button, let window = button.window {
                    let buttonFrame = window.frame
                    let panelWidth = panel.frame.width
                    let xPosition = buttonFrame.origin.x + (buttonFrame.width / 2) - (panelWidth / 2)
                    let yPosition = buttonFrame.origin.y - 10
                    panel.setFrameTopLeftPoint(NSPoint(x: xPosition, y: yPosition))
                } else {
                    panel.center()
                }
            }
            
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // 🌟 THE FIX: Modern local intercept monitor that captures Option + T instantly
    // 🌟 FIXED: Cleaned up the modifier flag check to use pure modern Swift (.option)
    private func setupModernShortcut() {
        // 🌟 This single line binds Option (alt) + T globally across your whole Mac perfectly
        globalHotKey = HotKey(key: .t, modifiers: [.option])
        
        globalHotKey?.keyDownHandler = { [weak self] in
            self?.togglePanel()
        }
    }
    @objc func handlePinToggle(_ notification: Notification) {
        guard let shouldPin = notification.object as? Bool else { return }
        panel.level = shouldPin ? .mainMenu : .statusBar
        panel.isPinned = shouldPin
    }
    
    @objc func handleTaskDataChanged() {
        updateMenuBarButton()
    }
    
    private func updateMenuBarButton() {
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
        if panel.level != .mainMenu {
            panel.orderOut(nil)
        }
    }
}

// MARK: - Subclassed Panel

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

// MARK: - Global Notification Extensions

extension Notification.Name {
    static let toggleWindowPin = Notification.Name("toggleWindowPin")
    static let taskDataChanged = Notification.Name("taskDataChanged")
}
