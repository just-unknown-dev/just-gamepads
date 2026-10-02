import GameController

/// Bridges Apple's GameController framework to the wire protocol every
/// backend shares (see gamepad_wire_protocol.dart).
///
/// `GCExtendedGamepad` already maps Xbox, PlayStation, Switch Pro and MFi
/// controllers to named elements, with triggers reporting both an analog
/// value and a discrete press, so this needs almost no remapping.
///
/// This file is identical in ios/ and macos/; only the plugin registration
/// around it differs.
final class GamepadController {
    typealias EventCallback = (_ event: [String: Any]) -> Void

    private var onEvent: EventCallback?
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    // GCController exposes no stable hardware id, so a connection is
    // identified by object identity, with a counter for the wire id.
    private var trackedIds: [ObjectIdentifier: String] = [:]
    private var trackedControllers: [ObjectIdentifier: GCController] = [:]
    private var nextId = 1

    func start(onEvent: @escaping EventCallback) {
        stop()
        self.onEvent = onEvent

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

        for controller in GCController.controllers() {
            track(controller)
        }
    }

    func stop() {
        if let observer = connectObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = disconnectObserver { NotificationCenter.default.removeObserver(observer) }
        connectObserver = nil
        disconnectObserver = nil
        for controller in trackedControllers.values {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        trackedControllers.removeAll()
        trackedIds.removeAll()
        onEvent = nil
    }

    private func track(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        // Only full gamepads: micro gamepads (Siri Remote) and other
        // profiles can't fill the standard layout.
        guard trackedIds[key] == nil, let gamepad = controller.extendedGamepad else { return }
        let id = "gc-\(nextId)"
        nextId += 1
        trackedIds[key] = id
        trackedControllers[key] = controller
        controller.handlerQueue = .main

        emitConnected(id: id, controller: controller)
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            self?.emitState(id: id, gamepad: gamepad)
        }
        emitState(id: id, gamepad: gamepad)
    }

    private func untrack(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        guard let id = trackedIds.removeValue(forKey: key) else { return }
        trackedControllers.removeValue(forKey: key)
        controller.extendedGamepad?.valueChangedHandler = nil
        onEvent?(["event": "disconnected", "id": id])
    }

    private func emitConnected(id: String, controller: GCController) {
        // GameController exposes no numeric vendor/product id. The display
        // name is vendorName ("DualSense Wireless Controller"); the
        // productCategory ("DualSense", "Xbox One", "Switch Pro Controller")
        // is the more reliable classification hint.
        let category = controller.productCategory
        onEvent?([
            "event": "connected",
            "id": id,
            "name": controller.vendorName ?? category,
            "typeHint": category,
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

        // GameController's Y axes are up-positive; the wire protocol is
        // down-positive, so Y is negated.
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
