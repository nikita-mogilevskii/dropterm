import Carbon.HIToolbox

/// Global hotkey via Carbon. Ctrl+I by default (kVK_ANSI_I + controlKey).
/// NOTE (user-accepted trade-off): system-wide capture shadows Ctrl+I (Tab)
/// inside terminal apps; change the constants to rebind.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    init?(keyCode: UInt32 = UInt32(kVK_ANSI_I),
          modifiers: UInt32 = UInt32(controlKey),
          onPress: @escaping () -> Void) {
        self.onPress = onPress
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().onPress()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x44_54_4D_31), id: 1) // 'DTM1'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if hotKeyRef == nil { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
