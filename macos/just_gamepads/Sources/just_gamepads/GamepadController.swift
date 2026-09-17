import GameController

/// NOTE: unverified/uncompiled on this machine (no Xcode on Windows) —
/// written from documented `GameController` framework APIs. Needs a first
/// real build + real-hardware smoke test on macOS/iOS before shipping.
///
/// Bridges Apple's `GameController` framework into the `EventChannel`
/// wire protocol every backend shares (see gamepad_wire_protocol.dart).
/// `GCExtendedGamepad` already normalizes Xbox/PlayStation/MFi controllers to
/// named properties (`buttonA/B/X/Y`, shoulders, triggers with discrete
/// `.isPressed` *and* analog `.value` — unlike Android/Windows' RawGameController
/// fallback/Linux evdev, which only ever deliver triggers as analog, needing
/// the shared Dart `normalizeTriggerButtons` step), thumbsticks, dpad,
/// `buttonMenu`/`buttonOptions` — the cleanest of all backends, needing
/// almost no remap logic at all. Identical on iOS and macOS (this file is
/// duplicated verbatim in both `ios/` and `macos/` plugin source dirs — the
/// GameController API surface used here doesn't differ between the two,
/// only the surrounding Flutter plugin registration boilerplate does, which
/// isn't worth a shared-source-set indirection at this size).
final class GamepadController {
    typealias EventCallback = (_ event: [String: Any]) -> Void

    private var onEvent: EventCallback?
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    /// Keyed by `ObjectIdentifier(controller).hashValue` — GCController has
    /// no stable hardware serial exposed uniformly across devices, so object
    /// identity (stable for the lifetime of one connection) is used instead,
    /// same approach as the Windows backend's raw-pointer-keyed maps.
    private var trackedControllers: [Int: GCController] = [:]

    func start(onEvent: @escaping EventCallback) {
        self.onEvent = onEvent

        for controller in GCController.controllers() {
            track(controller)
        }

        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            self?.track(controller)
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            self?.untrack(controller)
        }
    }

    func stop() {
        if let observer = connectObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = disconnectObserver { NotificationCenter.default.removeObserver(observer) }
        connectObserver = nil
        disconnectObserver = nil
        for (_, controller) in trackedControllers {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        trackedControllers.removeAll()
        onEvent = nil
    }

    private func idFor(_ controller: GCController) -> String {
        "gc-\(ObjectIdentifier(controller).hashValue)"
    }

    private func track(_ controller: GCController) {
        let id = idFor(controller)
        trackedControllers[ObjectIdentifier(controller).hashValue] = controller
        // Explicit even though main is already the documented default —
        // guards against relying on undocumented per-OS-version behavior
        // for where valueChangedHandler callbacks land.
        controller.handlerQueue = .main

        emitConnected(id: id, controller: controller)

        controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, _ in
            self?.emitState(id: id, gamepad: gamepad)
        }
    }

    private func untrack(_ controller: GCController) {
        let key = ObjectIdentifier(controller).hashValue
        guard trackedControllers.removeValue(forKey: key) != nil else { return }
        controller.extendedGamepad?.valueChangedHandler = nil
        onEvent?(["event": "disconnected", "id": idFor(controller), "name": ""])
    }

    private func emitConnected(id: String, controller: GCController) {
        var name = controller.vendorName ?? ""
        if #available(iOS 14.0, macOS 11.0, *) {
            name = controller.productCategory
        }
        onEvent?([
            "event": "connected",
            "id": id,
            "name": name,
            // No numeric vendor/product id is exposed by GameController —
            // the shared Dart classifier falls back to name-substring
            // matching against `productCategory`/`vendorName` for this
            // backend (see GamepadDatabase's name-hint tier).
        ])
    }

    private func emitState(id: String, gamepad: GCExtendedGamepad) {
        var buttons: [Int] = []
        func addIf(_ pressed: Bool, _ index: Int) {
            if pressed { buttons.append(index) }
        }
        addIf(gamepad.buttonA.isPressed, 0)
        addIf(gamepad.buttonB.isPressed, 1)
        addIf(gamepad.buttonX.isPressed, 2)
        addIf(gamepad.buttonY.isPressed, 3)
        addIf(gamepad.leftShoulder.isPressed, 4)
        addIf(gamepad.rightShoulder.isPressed, 5)
        addIf(gamepad.leftTrigger.isPressed, 6)
        addIf(gamepad.rightTrigger.isPressed, 7)
        addIf(gamepad.buttonOptions?.isPressed ?? false, 8)
        addIf(gamepad.buttonMenu.isPressed, 9)
        addIf(gamepad.leftThumbstickButton?.isPressed ?? false, 10)
        addIf(gamepad.rightThumbstickButton?.isPressed ?? false, 11)
        addIf(gamepad.dpad.up.isPressed, 12)
        addIf(gamepad.dpad.down.isPressed, 13)
        addIf(gamepad.dpad.left.isPressed, 14)
        addIf(gamepad.dpad.right.isPressed, 15)

        // GameController's Y axes are +1 = up / -1 = down (documented:
        // "-1.0 (bottom) to 1.0 (top)"), matching Windows.Gaming.Input's
        // convention, not just_inputs' down-positive one (which the Web
        // backend passes straight through unmodified from the W3C Standard
        // Gamepad spec) — negate, same as the Windows backend does.
        let axes: [String: Double] = [
            "leftStickX": Double(gamepad.leftThumbstick.xAxis.value),
            "leftStickY": Double(-gamepad.leftThumbstick.yAxis.value),
            "rightStickX": Double(gamepad.rightThumbstick.xAxis.value),
            "rightStickY": Double(-gamepad.rightThumbstick.yAxis.value),
            "leftTrigger": Double(gamepad.leftTrigger.value),
            "rightTrigger": Double(gamepad.rightTrigger.value),
        ]

        onEvent?([
            "event": "state",
            "id": id,
            "axes": axes,
            "buttons": buttons,
        ])
    }
}
