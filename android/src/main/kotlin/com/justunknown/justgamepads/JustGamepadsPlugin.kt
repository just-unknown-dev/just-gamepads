package com.justunknown.justgamepads

import android.content.Context
import android.hardware.input.InputManager
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel

/**
 * Connect/disconnect via [InputManager.InputDeviceListener]; state via a
 * [GamepadWindowCallbackWrapper] installed over the Activity's
 * [android.view.Window.Callback], so the host app needs no `FlutterActivity`
 * subclass. PlayStation and other HID controllers work through Android's own
 * key layout files; vendor/product ids go up for the shared Dart classifier.
 *
 * Everything here runs on the main thread: the device listener is
 * registered with a null Handler from `onListen` (main thread), and window
 * callbacks are dispatched there too, so no locking is needed.
 */
class JustGamepadsPlugin :
    FlutterPlugin,
    ActivityAware,
    EventChannel.StreamHandler {
    private lateinit var channel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var inputManager: InputManager? = null

    private var activityBinding: ActivityPluginBinding? = null
    private var originalWindowCallback: android.view.Window.Callback? = null
    private var wrapperCallback: GamepadWindowCallbackWrapper? = null

    // Controllers reported as connected. Removal notices arrive for every
    // input device (keyboards, mice...); only these produce a disconnect.
    private val knownDevices = HashSet<Int>()

    // Per-device accumulated state: key events (buttons) and motion events
    // (axes) each carry half the picture; every event re-emits the full
    // merged snapshot for that device (see emitState).
    private val buttonsByDevice = HashMap<Int, MutableSet<Int>>()
    private val axesByDevice = HashMap<Int, MutableMap<String, Double>>()

    private val deviceListener =
        object : InputManager.InputDeviceListener {
            override fun onInputDeviceAdded(deviceId: Int) = handleDeviceAdded(deviceId)

            override fun onInputDeviceRemoved(deviceId: Int) = handleDeviceRemoved(deviceId)

            override fun onInputDeviceChanged(deviceId: Int) {
                // State comes from dispatched events, not from this notice.
            }
        }

    // ── FlutterPlugin ──

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        inputManager =
            binding.applicationContext.getSystemService(Context.INPUT_SERVICE) as? InputManager
        channel = EventChannel(binding.binaryMessenger, "just_gamepads/events")
        channel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setStreamHandler(null)
        stopListening()
        inputManager = null
    }

    // ── EventChannel.StreamHandler ──

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        eventSink = events
        val manager = inputManager ?: return
        manager.registerInputDeviceListener(deviceListener, null)
        for (deviceId in manager.inputDeviceIds) handleDeviceAdded(deviceId)
    }

    override fun onCancel(arguments: Any?) {
        stopListening()
    }

    private fun stopListening() {
        inputManager?.unregisterInputDeviceListener(deviceListener)
        eventSink = null
        knownDevices.clear()
        buttonsByDevice.clear()
        axesByDevice.clear()
    }

    // ── ActivityAware: install/restore the Window.Callback wrapper ──

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        installWindowCallback(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        restoreWindowCallback()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        installWindowCallback(binding)
    }

    override fun onDetachedFromActivity() {
        restoreWindowCallback()
        activityBinding = null
    }

    private fun installWindowCallback(binding: ActivityPluginBinding) {
        val window = binding.activity.window
        val original = window.callback
        originalWindowCallback = original
        val wrapper =
            GamepadWindowCallbackWrapper(
                original = original,
                onKeyEvent = ::handleKeyEvent,
                onGenericMotionEvent = ::handleGenericMotionEvent,
            )
        wrapperCallback = wrapper
        window.callback = wrapper
    }

    // A config change (rotation) tears down and rebuilds the Activity's
    // Window.Callback chain; without this restore/reinstall pair, gamepad
    // input either stops after rotation or gets wrapped twice.
    private fun restoreWindowCallback() {
        val binding = activityBinding ?: return
        if (binding.activity.window.callback === wrapperCallback) {
            binding.activity.window.callback = originalWindowCallback
        }
        wrapperCallback = null
        originalWindowCallback = null
    }

    // ── Connect / disconnect ──

    private fun handleDeviceAdded(deviceId: Int) {
        val device = inputManager?.getInputDevice(deviceId) ?: return
        announce(device)
    }

    private fun announce(device: InputDevice) {
        if (eventSink == null || device.id in knownDevices) return
        if (!GamepadEventMapper.isGamepadDevice(device)) return
        knownDevices.add(device.id)
        emitConnected(device.id, device.name ?: "", device.vendorId, device.productId)
    }

    private fun handleDeviceRemoved(deviceId: Int) {
        buttonsByDevice.remove(deviceId)
        axesByDevice.remove(deviceId)
        if (knownDevices.remove(deviceId)) emitDisconnected(deviceId)
    }

    // ── Per-event state ──

    private fun handleKeyEvent(event: KeyEvent) {
        val device = event.device ?: return
        if (eventSink == null || !GamepadEventMapper.isGamepadDevice(device)) return
        val index = GamepadEventMapper.buttonIndexForKeyCode(event.keyCode) ?: return
        announce(device)
        val buttons = buttonsByDevice.getOrPut(event.deviceId) { mutableSetOf() }
        when (event.action) {
            KeyEvent.ACTION_DOWN -> buttons.add(index)
            KeyEvent.ACTION_UP -> buttons.remove(index)
            else -> return
        }
        emitState(event.deviceId)
    }

    private fun handleGenericMotionEvent(event: MotionEvent) {
        val device = event.device ?: return
        if (eventSink == null || !GamepadEventMapper.isGamepadDevice(device)) return
        if (event.action != MotionEvent.ACTION_MOVE) return
        announce(device)

        val axes = axesByDevice.getOrPut(event.deviceId) { mutableMapOf() }
        axes.putAll(GamepadEventMapper.axesForMotionEvent(event))

        val dpad = GamepadEventMapper.dpadFromMotionEvent(event)
        val buttons = buttonsByDevice.getOrPut(event.deviceId) { mutableSetOf() }
        setButton(buttons, 12, dpad.up)
        setButton(buttons, 13, dpad.down)
        setButton(buttons, 14, dpad.left)
        setButton(buttons, 15, dpad.right)

        emitState(event.deviceId)
    }

    private fun setButton(
        buttons: MutableSet<Int>,
        index: Int,
        held: Boolean,
    ) {
        if (held) buttons.add(index) else buttons.remove(index)
    }

    // ── Wire protocol emission (see gamepad_wire_protocol.dart) ──

    private fun emitState(deviceId: Int) {
        val event = HashMap<String, Any?>()
        event["event"] = "state"
        event["id"] = deviceId.toString()
        event["axes"] = axesByDevice[deviceId] ?: emptyMap<String, Double>()
        event["buttons"] = (buttonsByDevice[deviceId] ?: emptySet()).toList()
        eventSink?.success(event)
    }

    private fun emitConnected(
        deviceId: Int,
        name: String,
        vendorId: Int,
        productId: Int,
    ) {
        val event = HashMap<String, Any?>()
        event["event"] = "connected"
        event["id"] = deviceId.toString()
        event["name"] = name
        if (vendorId != 0) {
            event["vendorId"] = vendorId
            event["productId"] = productId
        }
        eventSink?.success(event)
    }

    private fun emitDisconnected(deviceId: Int) {
        val event = HashMap<String, Any?>()
        event["event"] = "disconnected"
        event["id"] = deviceId.toString()
        eventSink?.success(event)
    }
}
