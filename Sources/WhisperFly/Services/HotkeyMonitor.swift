import Foundation
import Carbon

final class HotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    var onPress: (@Sendable () -> Void)?
    var onRelease: (@Sendable () -> Void)?
    
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    nonisolated(unsafe) private static var current: HotkeyMonitor?
    
    private let hotkeyID = EventHotKeyID(signature: 0x5746_4C57, id: 1) // "WFLW"
    
    func register() throws {
        unregister()
        HotkeyMonitor.current = self
        
        let keyCode: UInt32 = 49 // Space
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                let kind = GetEventKind(event)
                if kind == UInt32(kEventHotKeyPressed) {
                    HotkeyMonitor.current?.onPress?()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    HotkeyMonitor.current?.onRelease?()
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            nil,
            &handlerRef
        )
        
        guard status == noErr else {
            throw NSError(domain: "WhisperFly", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to install hotkey handler: \(status)"])
        }
        self.handlerRef = handlerRef
        
        var id = hotkeyID
        var ref: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        
        guard regStatus == noErr else {
            throw NSError(domain: "WhisperFly", code: 21, userInfo: [NSLocalizedDescriptionKey: "Failed to register hotkey: \(regStatus)"])
        }
        self.hotkeyRef = ref
    }
    
    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
        if HotkeyMonitor.current === self {
            HotkeyMonitor.current = nil
        }
    }
    
    deinit {
        unregister()
    }
}
