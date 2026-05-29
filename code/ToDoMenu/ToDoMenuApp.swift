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
    
    // Global hotkey to toggle panel open/closed
    var globalHotKey: HotKey?
    // Focused hotkey to toggle pin/unpin status
    var localPinHotKey: HotKey?
    
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
        
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "TaskSlab"
        panel.delegate = self
        
        // Make the window transparent so clipped SwiftUI layouts don't bleed gray rectangular shadow borders
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        
        let contentView = TaskPopoverView(store: taskStore)
        panel.contentView = NSHostingView(rootView: contentView)
        
        // Update menu badge count initially
        updateMenuBarButton()
        
        // 3. Global Option + T Key Binding
        globalHotKey = HotKey(key: .t, modifiers: [.option])
        globalHotKey?.keyDownHandler = { [weak self] in
            self?.togglePanel()
        }
        
        // 4. Focused-Only Option + W Pin Binding
        localPinHotKey = HotKey(key: .w, modifiers: [.option])
        localPinHotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            // Only trigger pinning if the app panel is actively focused
            if self.panel.isKeyWindow {
                NotificationCenter.default.post(name: .requestHotkeyPinToggle, object: nil)
            }
        }

        // Listen for user interaction events from the view hierarchy
        NotificationCenter.default.addObserver(self, selector: #selector(handlePinToggle(_:)), name: .toggleWindowPin, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataChanged), name: .taskDataChanged, object: nil)
    }
    
    @objc func togglePanel() {
        if panel.isVisible && panel.isKeyWindow {
            if !panel.isPinned {
                panel.orderOut(nil)
            }
        } else {
            // Place panel elegantly below the status bar icon
            if let button = statusItem.button, let windowScreen = button.window?.screen {
                let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
                let screenFrame = windowScreen.visibleFrame
                
                let panelWidth: CGFloat = 320
                let panelHeight = panel.frame.height
                
                var xPos = buttonFrame.origin.x + (buttonFrame.width / 2) - (panelWidth / 2)
                if xPos + panelWidth > screenFrame.maxX {
                    xPos = screenFrame.maxX - panelWidth - 10
                } else if xPos < screenFrame.minX {
                    xPos = screenFrame.minX + 10
                }
                
                let yPos = buttonFrame.origin.y - panelHeight - 4
                
                panel.setFrame(NSRect(x: xPos, y: yPos, width: panelWidth, height: panelHeight), display: true)
            }
            
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc private func handlePinToggle(_ notification: Notification) {
        if let isPinned = notification.object as? Bool {
            panel.isPinned = isPinned
            panel.level = isPinned ? .floating : .statusBar
            
            if isPinned {
                panel.styleMask.insert(.resizable)
            } else {
                panel.styleMask.remove(.resizable)
            }
        }
    }
    
    @objc private func handleDataChanged() {
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
        if !panel.isPinned {
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

// MARK: - Global Notification Name Extensions

extension Notification.Name {
    static let toggleWindowPin = Notification.Name("toggleWindowPin")
    static let taskDataChanged = Notification.Name("taskDataChanged")
    static let requestHotkeyPinToggle = Notification.Name("requestHotkeyPinToggle")
}
