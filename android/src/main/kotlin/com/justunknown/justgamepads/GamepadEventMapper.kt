package com.justunknown.justgamepads

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent

/**
 * Semantic keycode/axis -> just_inputs' standard GamepadButton/GamepadAxis
 * layout. Android's KeyEvent/MotionEvent constants are already *semantic*
 * (KEYCODE_BUTTON_A really does mean "the A button", not a positional
 * guess), so — unlike Windows' RawGameController fallback path or an
 * unrecognized Linux evdev device — this mapper needs no generic/positional
 * heuristic at all: every value here is a direct 1:1 translation.
 */
object GamepadEventMapper {
    /** `SOURCE_GAMEPAD`/`SOURCE_JOYSTICK`, excluding virtual devices. */
    fun isGamepadDevice(device: InputDevice?): Boolean {
        if (device == null || device.isVirtual) return false
        val sources = device.sources
        return (sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
    }

    /** GamepadButton.* index, or null for a keycode this layout has no slot for. */
    fun buttonIndexForKeyCode(keyCode: Int): Int? =
        when (keyCode) {
            KeyEvent.KEYCODE_BUTTON_A -> 0
            KeyEvent.KEYCODE_BUTTON_B -> 1
            KeyEvent.KEYCODE_BUTTON_X -> 2
            KeyEvent.KEYCODE_BUTTON_Y -> 3
            KeyEvent.KEYCODE_BUTTON_L1 -> 4
            KeyEvent.KEYCODE_BUTTON_R1 -> 5
            // L2/R2 are usually analog-only (AXIS_LTRIGGER/AXIS_RTRIGGER via
            // motion events, handled in axesForMotionEvent below, with the
            // shared Dart normalizeTriggerButtons deriving the digital
            // button from that) — but some controllers additionally report
            // literal key events for a full press, which these two lines
            // pass through directly when present.
            KeyEvent.KEYCODE_BUTTON_L2 -> 6
            KeyEvent.KEYCODE_BUTTON_R2 -> 7
            KeyEvent.KEYCODE_BUTTON_SELECT -> 8
            KeyEvent.KEYCODE_BUTTON_START -> 9
            KeyEvent.KEYCODE_BUTTON_THUMBL -> 10
            KeyEvent.KEYCODE_BUTTON_THUMBR -> 11
            // Fallback path: most gamepads report the dpad via AXIS_HAT_X/Y
            // motion events instead (see axesForMotionEvent), but a few
            // drivers send literal dpad key events — handling both means
            // either path works regardless of which a given device uses.
            KeyEvent.KEYCODE_DPAD_UP -> 12
            KeyEvent.KEYCODE_DPAD_DOWN -> 13
            KeyEvent.KEYCODE_DPAD_LEFT -> 14
            KeyEvent.KEYCODE_DPAD_RIGHT -> 15
            else -> null
        }

    /** Current axis snapshot from a generic motion event — see MotionEvent's
     * own semantics: each event already reports the *full current* reading
     * for every axis the device supports, not just whichever one changed. */
    fun axesForMotionEvent(event: MotionEvent): Map<String, Double> {
        val axes = HashMap<String, Double>()
        axes["leftStickX"] = event.getAxisValue(MotionEvent.AXIS_X).toDouble()
        // Android's joystick Y convention is already "negative = up,
        // positive = down" (per MotionEvent.AXIS_Y docs) — matching
        // just_inputs' down-positive convention directly, unlike Windows'
        // Windows.Gaming.Input (up-positive, negated in the Windows
        // backend). No sign flip needed here.
        axes["leftStickY"] = event.getAxisValue(MotionEvent.AXIS_Y).toDouble()
        // Right stick is commonly reported on AXIS_Z/AXIS_RZ for HID
        // gamepads under Android's generic joystick mapping.
        axes["rightStickX"] = event.getAxisValue(MotionEvent.AXIS_Z).toDouble()
        axes["rightStickY"] = event.getAxisValue(MotionEvent.AXIS_RZ).toDouble()
        axes["leftTrigger"] = event.getAxisValue(MotionEvent.AXIS_LTRIGGER).toDouble()
        axes["rightTrigger"] = event.getAxisValue(MotionEvent.AXIS_RTRIGGER).toDouble()
        return axes
    }

    /** Dpad-as-buttons derived from the hat axes, per [axesForMotionEvent]'s
     * doc comment on why dpad isn't reported as a regular analog axis. */
    fun dpadFromMotionEvent(event: MotionEvent): DpadState {
        val hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X)
        val hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        return DpadState(
            up = hatY < -0.5f,
            down = hatY > 0.5f,
            left = hatX < -0.5f,
            right = hatX > 0.5f,
        )
    }

    data class DpadState(val up: Boolean, val down: Boolean, val left: Boolean, val right: Boolean)
}
