package com.justunknown.justgamepads

import android.view.KeyEvent
import android.view.MotionEvent
import android.view.Window

/**
 * Wraps the Activity's existing [Window.Callback] to observe gamepad
 * key/motion events without requiring the host app to subclass
 * `FlutterActivity` — installed via [android.view.Window.setCallback] from
 * `onAttachedToActivity`, restored on detach (see `JustGamepadsPlugin`).
 *
 * Kotlin's interface delegation (`by original`) implements every method of
 * [Window.Callback] (there are ~20) by forwarding to [original] automatically
 * — only the two methods gamepad events arrive through are overridden below,
 * both of which still call through to [original] and return its result, so
 * this plugin is a pure observer riding alongside the callback chain, never
 * replacing or short-circuiting Flutter's own input handling.
 */
class GamepadWindowCallbackWrapper(
    private val original: Window.Callback,
    private val onKeyEvent: (KeyEvent) -> Unit,
    private val onGenericMotionEvent: (MotionEvent) -> Unit,
) : Window.Callback by original {
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        onKeyEvent(event)
        return original.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        onGenericMotionEvent(event)
        return original.dispatchGenericMotionEvent(event)
    }
}
