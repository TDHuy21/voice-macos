import AppKit
import SwiftUI
import UI
import Engine
import Core

@available(macOS 14.2, *)
@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // Eye-rest timer dependencies (7.1, 7.3)
    private var breakTimerManager: BreakTimerManager?
    private var inputBlocker: InputBlocker?
    private var overlayController: BreakOverlayController?
    private var lastEyeRestTitle: String? = nil
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Redirect stdout and stderr to a file for persistent logging
        let logPath = "/Users/mac/Documents/GitHub/soundssource/app.log"
        freopen(logPath, "a", stdout)
        freopen(logPath, "a", stderr)
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        
        print("\n--- APP LAUNCHED (App Bundle) ---")
        
        // Create Popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverContentView())
        self.popover = popover
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePopoverResizeNotification(_:)),
            name: .popoverShouldResize,
            object: nil
        )
        
        // Create Status Item in Menu Bar
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SoundsSource")
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = statusItem
        
        // Initialize AudioEngineManager
        _ = AudioEngineManager.shared

        // 7.1: Initialise eye-rest timer subsystem
        let btm = BreakTimerManager.shared
        let blocker = InputBlocker()
        let overlayCtrl = BreakOverlayController(manager: btm)

        btm.inputBlocker = blocker
        btm.overlayController = overlayCtrl

        // 6.7: Status item update hook — set title during cycle, restore icon at idle
        btm.onStatusItemUpdate = { [weak self] title in
            guard let self else { return }
            self.lastEyeRestTitle = title
            self.refreshStatusItem()
        }

        self.breakTimerManager = btm
        self.inputBlocker = blocker
        self.overlayController = overlayCtrl

        // Pin TodoStore and wire remaining count change listener
        _ = TodoStore.shared
        TodoStore.shared.onRemainingCountChange = { [weak self] _ in
            self?.refreshStatusItem()
        }

        // Initialize and start TodoScheduler
        TodoScheduler.shared.start()

        refreshStatusItem()

        print("SoundsSource: AppDelegate initialized successfully.")
    }
    
    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            
            // Clear denied permission cue when popover is shown
            TodoScheduler.shared.showDeniedPermissionCue = false
            
            let showTodo = UserDefaults.standard.bool(forKey: "todos_showTodo")
            popover.contentSize = NSSize(width: showTodo ? 600 : 360, height: 440)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    @objc private func handlePopoverResizeNotification(_ notification: Notification) {
        guard let popover = popover, let userInfo = notification.userInfo,
              let width = userInfo["width"] as? CGFloat else { return }
        
        let newSize = NSSize(width: width, height: 440)
        if popover.contentSize != newSize {
            popover.animates = true
            popover.contentSize = newSize
        }
    }

    // 7.2: Graceful teardown — ensures tap removed, overlay hidden, audio restored
    public func applicationWillTerminate(_ notification: Notification) {
        breakTimerManager?.teardownOnTerminate()
        TodoStore.shared.saveSynchronously()
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        
        let btm = BreakTimerManager.shared
        if btm.phase != .idle {
            // Eye-rest cycle is active. It takes priority.
            if let title = lastEyeRestTitle {
                button.image = nil
                button.title = title
            } else {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Minh Thw")
                button.title = ""
            }
        } else {
            // Eye-rest is idle. Show the todo remaining count badge or plain waveform.
            let count = TodoStore.shared.remainingCount
            let isWarning = TodoScheduler.shared.showDeniedPermissionCue
            
            if isWarning {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SoundsSource")
                button.title = " ⚠️"
            } else if count > 0 {
                let circledNumbers = ["⓪", "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳"]
                let badgeStr: String
                if count < circledNumbers.count {
                    badgeStr = circledNumbers[count]
                } else {
                    badgeStr = "(\(count))"
                }
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SoundsSource")
                button.title = " " + badgeStr
            } else {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SoundsSource")
                button.title = ""
            }
        }
    }
}
