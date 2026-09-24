package com.reelay.reelay

import android.app.Activity
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Switches the TV to a display mode whose refresh rate matches the video
 * (exactly, or an exact multiple: 23.976 plays cleanly at 47.952 too), so
 * films don't judder on a 60 Hz output. Ported down from plezy's
 * FrameRateManager.
 *
 * The switch goes through the window's preferredDisplayModeId, which the
 * system honours for as long as the activity is in front; [clear] hands the
 * choice back to the system. A mode change renegotiates HDMI and blanks the
 * picture, so [match] only reports back once the display has changed and
 * settled (or a watchdog gives up on a TV that ignored the request), and
 * the player waits for it before starting.
 */
class FrameRateMatcher(private val activity: Activity) {
  private companion object {
    const val SETTLE_MS = 2000L
    const val WATCHDOG_MS = 5000L
    const val TOLERANCE = 0.1f
  }

  private val handler = Handler(Looper.getMainLooper())
  private var listener: DisplayManager.DisplayListener? = null
  private var pending: ((Boolean) -> Unit)? = null
  private val watchdog = Runnable { finish(false) } // the TV ignored the request

  private val displayManager get() = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

  @Suppress("DEPRECATION")
  private fun display(): Display? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) activity.display else activity.windowManager.defaultDisplay

  /** [onDone] gets whether the display actually switched. */
  fun match(fps: Float, videoWidth: Int, videoHeight: Int, onDone: (Boolean) -> Unit) {
    finish(false) // a newer request supersedes an unfinished one
    val display = display()
    val window = activity.window
    if (fps <= 0f || display == null || window == null) return onDone(false)

    val current = display.mode
    val target = bestMode(fps, current, display.supportedModes, videoWidth, videoHeight)
    if (target == null || target.modeId == current.modeId) return onDone(false)

    pending = onDone
    listener = object : DisplayManager.DisplayListener {
      override fun onDisplayAdded(displayId: Int) = Unit
      override fun onDisplayRemoved(displayId: Int) = Unit
      override fun onDisplayChanged(displayId: Int) {
        // HDMI renegotiation can fire several of these; settle once.
        displayManager.unregisterDisplayListener(this)
        listener = null
        handler.removeCallbacks(watchdog)
        handler.postDelayed({ finish(true) }, SETTLE_MS)
      }
    }
    displayManager.registerDisplayListener(listener, handler)
    handler.postDelayed(watchdog, SETTLE_MS + WATCHDOG_MS)
    window.attributes = window.attributes.apply { preferredDisplayModeId = target.modeId }
  }

  fun clear() {
    finish(false)
    activity.window?.let { w -> w.attributes = w.attributes.apply { preferredDisplayModeId = 0 } }
  }

  private fun finish(switched: Boolean) {
    handler.removeCallbacksAndMessages(null)
    listener?.let { displayManager.unregisterDisplayListener(it) }
    listener = null
    val done = pending ?: return
    pending = null
    done(switched)
  }

  /** 0 = exact, 1 = a whole multiple, null = no match. */
  private fun matchRank(refreshRate: Float, fps: Float): Int? {
    if (abs(refreshRate - fps) < TOLERANCE) return 0
    val multiple = (refreshRate / fps).roundToInt()
    return if (multiple > 1 && abs(refreshRate - fps * multiple) < TOLERANCE) 1 else null
  }

  private fun bestMode(
    fps: Float,
    current: Display.Mode,
    modes: Array<Display.Mode>,
    videoWidth: Int,
    videoHeight: Int,
  ): Display.Mode? {
    // Prefer a refresh-only change at the current resolution.
    modes
      .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
      .mapNotNull { m -> matchRank(m.refreshRate, fps)?.let { m to it } }
      .minWithOrNull(compareBy({ it.second }, { abs(it.first.refreshRate - current.refreshRate) }))
      ?.let { return it.first }

    // Otherwise allow a resolution change, but never below the video's own.
    if (videoWidth <= 0 || videoHeight <= 0) return null
    val area = current.physicalWidth.toLong() * current.physicalHeight
    return modes
      .filter { it.physicalWidth >= videoWidth && it.physicalHeight >= videoHeight }
      .mapNotNull { m -> matchRank(m.refreshRate, fps)?.let { m to it } }
      .minWithOrNull(
        compareBy({ abs(it.first.physicalWidth.toLong() * it.first.physicalHeight - area) }, { it.second }),
      )
      ?.first
  }
}
