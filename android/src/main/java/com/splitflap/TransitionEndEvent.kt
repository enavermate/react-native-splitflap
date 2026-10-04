package com.splitflap

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.Event

/** `onTransitionEnd` of SplitflapViewNativeComponent.ts: the text the board settled on, or left. */
class TransitionEndEvent(
  surfaceId: Int,
  viewId: Int,
  private val text: String,
  private val interrupted: Boolean,
) : Event<TransitionEndEvent>(surfaceId, viewId) {
  override fun getEventName(): String = NAME

  // Two ends in one frame are two facts (an interruption, then a finish); none may be merged.
  override fun canCoalesce(): Boolean = false

  override fun getEventData(): WritableMap =
    Arguments.createMap().apply {
      putString("text", text)
      putBoolean("interrupted", interrupted)
    }

  companion object {
    const val NAME = "topTransitionEnd"
  }
}
