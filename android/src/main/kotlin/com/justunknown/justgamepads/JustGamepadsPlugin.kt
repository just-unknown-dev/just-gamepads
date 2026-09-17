package com.justunknown.justgamepads

import android.content.Context
import android.hardware.input.InputManager
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel

/**
 * Connect/disconnect via [InputManager.InputDeviceListener]; per-frame state
 * via a [GamepadWindowCallbackWrapper] installed over the Activity's
 * [android.view.Window.Callback] — see that class's doc comment for why this
 * needs no `FlutterActivity` subclass. PlayStation controllers work
 * out-of-the-box here via Android's standard `SOURCE_JOYSTICK` HID support
 * (vendor `.kl` key-layout files handle the mapping at the OS level); no
 * special-casing needed for the event path, only for brand *detection* via
 * [android.view.InputDevice.getVendorId]/`getProductId`, sent up for the
 * shared Dart classifier.
 *
 * No thread marshaling is needed anywhere in this file (unlike the Windows
 * backend) — `InputDeviceListener` callbacks (registered with a null
 * `Handler`, so they use the calling thread's Looper) and
 * `dispatchKeyEvent`/`dispatchGenericMotionEvent` are both already delivered
 * on Android's main/UI thread, which is also where `onListen` (and thus
 * `registerInputDeviceListener`) is called from.
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

    // Per-device accumulated state — key events (buttons) and motion events
    // (axes) each carry only half the picture; every event re-emits the
    // full merged snapshot for that device (see emitState).
    private val buttonsByDevice = HashMap<Int, MutableSet<Int>>()
    private val axesByDevice = HashMap<Int, MutableMap<String, Double>>()

    private val deviceListener =
        object : InputManager.InputDeviceListener {
            override fun onInputDeviceAdded(deviceId: Int) = handleDeviceAdded(deviceId)

            override fun onInputDeviceRemoved(deviceId: Int) = handleDeviceRemoved(deviceId)

            override fun onInputDeviceChanged(deviceId: Int) {
                // State comes from dispatch (see above), not from this
                // notification — nothing to do here.
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
        inputManager?.unregisterInputDeviceListener(deviceListener)
        eventSink = null
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

    // Rotation (a config change) tears down and rebuilds the Activity's
    // Window.Callback chain — without this restore/reinstall pair, either
    // gamepad support silently breaks after rotation or the callback gets
    // double-wrapped on every config change.
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
        if (!GamepadEventMapper.isGamepadDevice(device)) return
        emitConnected(deviceId, device.name ?: "", device.vendorId, device.productId)
    }

    private fun handleDeviceRemoved(deviceId: Int) {
        buttonsByDevice.remove(deviceId)
        axesByDevice.remove(deviceId)
        emitDisconnected(deviceId)
    }

    // ── Per-frame state ──

    private fun handleKeyEvent(event: KeyEvent) {
        if (!GamepadEventMapper.isGamepadDevice(event.device)) return
        val index = GamepadEventMapper.buttonIndexForKeyCode(event.keyCode) ?: return
        val buttons = buttonsByDevice.getOrPut(event.deviceId) { mutableSetOf() }
        when (event.action) {
            KeyEvent.ACTION_DOWN -> buttons.add(index)
            KeyEvent.ACTION_UP -> buttons.remove(index)
            else -> return
        }
        emitState(event.deviceId)
    }

    private fun handleGenericMotionEvent(event: MotionEvent) {
        if (!GamepadEventMapper.isGamepadDevice(event.device)) return
        if (event.action != MotionEvent.ACTION_MOVE) return

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
        event["vendorId"] = vendorId
        event["productId"] = productId
        eventSink?.success(event)
    }

    private fun emitDisconnected(deviceId: Int) {
        val event = HashMap<String, Any?>()
        event["event"] = "disconnected"
        event["id"] = deviceId.toString()
        event["name"] = ""
        eventSink?.success(event)
    }
}
