import Foundation
import CoreGraphics
import AppKit

/// Monitors keyboard events system-wide to detect the trigger key (Caps Lock by default)
/// Requires Accessibility permissions to function
class KeyboardMonitor {
    
    // MARK: - Types
    
    /// Callback type for when trigger key is pressed
    typealias TriggerCallback = () -> Void
    
    // MARK: - Properties
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onTrigger: TriggerCallback?
    
    /// Whether the monitor is currently active
    private(set) var isMonitoring = false
    
    // MARK: - Public Methods
    
    /// Start monitoring for the trigger key
    /// - Parameter callback: Called when the trigger key is pressed
    /// - Returns: True if monitoring started successfully
    @discardableResult
    func startMonitoring(onTrigger callback: @escaping TriggerCallback) -> Bool {
        guard !isMonitoring else { return true }
        
        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            print("KeyboardMonitor: Accessibility permission not granted")
            return false
        }
        
        self.onTrigger = callback
        
        // Create event tap for keyboard events
        // We're interested in kCGEventFlagsChanged which fires when modifier keys change
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        // The event tap callback
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handleEvent(type: type, event: event)
            
            return Unmanaged.passUnretained(event)
        }
        
        // Create the event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("KeyboardMonitor: Failed to create event tap")
            return false
        }
        
        self.eventTap = tap
        
        // Create run loop source and add to current run loop
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = runLoopSource
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isMonitoring = true
        print("KeyboardMonitor: Started monitoring")
        
        return true
    }
    
    /// Stop monitoring for keyboard events
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        onTrigger = nil
        isMonitoring = false
        
        print("KeyboardMonitor: Stopped monitoring")
    }
    
    // MARK: - Private Methods
    
    private func handleEvent(type: CGEventType, event: CGEvent) {
        // We're looking for Caps Lock
        // Caps Lock is indicated by the NSEvent.ModifierFlags.capsLock flag
        
        guard type == .flagsChanged else { return }

        // Check if Caps Lock was just pressed
        // Note: This is a simplified check. We may need more sophisticated
        // logic to detect press vs release and avoid triggering on every toggle.
        
        // For Caps Lock, we detect the press by looking at the keycode
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Caps Lock keycode is 57
        if keyCode == 57 {
            print("KeyboardMonitor: Caps Lock detected")
            
            // Call the trigger callback on the main thread
            DispatchQueue.main.async { [weak self] in
                self?.onTrigger?()
            }
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopMonitoring()
    }
}
